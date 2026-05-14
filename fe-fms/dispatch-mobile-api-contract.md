# Dispatch Mobile API — Contract for Flutter Client

> **Audience:** mobile (Flutter) developer integrating the dispatch rider app.
> **Backend:** Laravel 11, Sanctum tokens. Source of truth: [routes/dispatch_api.php](../routes/dispatch_api.php) and `app/Http/Controllers/Api/Dispatch/*`.
> **Status:** v1, ready for integration. Surface is **separate from** the frozen legacy `/myapi/*` driver API — do not mix conventions.

---

## 1. Base URL & environments

| Environment | Base URL |
|---|---|
| Local dev | `http://127.0.0.1:8123` (XAMPP, port from HANDOFF smoke test) |
| Staging | _(confirm with backend; same host as admin staging)_ |
| Production | `https://<prod-host>` after DNS cutover |

All paths are prefixed with `/api/dispatch`. The dispatch surface is **not** gated by the `LEGACY_AUTH_USE_LARAVEL` feature flag, so it remains reachable independent of the legacy admin cutover.

---

## 2. Conventions

### Headers

| Header | Required on | Purpose |
|---|---|---|
| `Authorization: Bearer <token>` | Every authenticated request | Sanctum personal access token from `/auth/login` or `/auth/activate` |
| `Accept: application/json` | All requests | Forces JSON error responses |
| `Content-Type: application/json` | JSON POSTs | — |
| `Content-Type: multipart/form-data` | `POST /jobs/{id}/finish` (when uploading photos) | — |
| `Idempotency-Key: <uuid-v4>` | `POST /jobs/{id}/start`, `POST /jobs/{id}/finish` | UUID v4. See §6. |

### Success envelope

```json
{ "data": { ... }, "meta": { ... } }
```

`meta` is optional (currently only `/jobs/today` returns it).

> **Important:** this is **NOT** the legacy `/myapi/*` shape `{ "Success": true, "Message": "...", "Data": {} }`. The dispatch API uses the modern `{data, meta, errors}` convention.

### Error envelope

```json
{ "errors": [ { "message": "..." } ] }
```

Validation failures from Laravel return the framework default 422 shape:

```json
{ "message": "The phone field is required.", "errors": { "phone": ["The phone field is required."] } }
```

Treat any non-2xx as an error and prefer `errors[0].message` if present, otherwise fall back to `message`.

### Phone format

Login identifier. The server normalizes to `+63XXXXXXXXXX` (Philippines, E.164). The client may send `09XXXXXXXXX`, `639XXXXXXXXX`, or `+639XXXXXXXXX`; `App\Support\PhoneNumber::normalize()` accepts all three. **Server-side normalization is canonical** — store whatever the server returns (`rider.phone`), not the user's raw input.

### Job status enum

| Value | Meaning |
|---|---|
| `null` | Unassigned (admin not yet dispatched the rider) — riders should not see these on `/jobs/today` |
| `1` | On-the-way (rider has called `/start`) |
| `2` | Finished (rider has called `/finish`) |
| `3` | Reschedule pending (admin action; rider should treat as read-only) |

### Timestamps

All timestamps are server-local `Asia/Manila` (UTC+8) in `YYYY-MM-DD HH:MM:SS` format. The client should parse with the timezone fixed (do not assume device tz).

---

## 3. Authentication flow

```
┌──────────┐                                ┌─────────────┐
│  Admin   │  shows 6-digit code once       │   Backend   │
│  (web)   ├───────────────────────────────►│             │
└──────────┘                                └─────────────┘
      │  out-of-band (in person / SMS / call)
      ▼
┌──────────┐  POST /auth/activate           ┌─────────────┐
│  Rider   ├───────────────────────────────►│   Backend   │
│ (mobile) │  { phone, code, new_password,  │             │
│          │    device_name, fcm_token }    │             │
│          │◄───────────────────────────────┤             │
└──────────┘     200 { token, rider }       └─────────────┘

Subsequent app launches:
┌──────────┐  POST /auth/login              ┌─────────────┐
│  Rider   ├───────────────────────────────►│   Backend   │
│          │◄───────────────────────────────┤             │
└──────────┘     200 { token, rider }       └─────────────┘
```

**Forgot password:** there is **no** rider-triggered reset endpoint. The rider contacts the admin out-of-band; admin clicks "Reset password" in the web console; rider runs `/auth/activate` again with the new code.

---

## 4. Endpoint reference

### 4.1 `POST /api/dispatch/auth/activate`

Public. Throttled **5 requests / minute** per IP+phone. Sets the rider's password on first use (or after admin reset) and returns a token.

**Request body**

| Field | Type | Notes |
|---|---|---|
| `phone` | string | Will be normalized to +63 |
| `code` | string | Exactly 6 digits, from admin |
| `new_password` | string | Min 8 chars, no other complexity rules |
| `device_name` | string | ≤120 chars, e.g. `"Pixel 8 — Juan"` |
| `fcm_token` | string? | Optional FCM registration token |
| `platform` | string? | `"android"` or `"ios"` |

**200 response**

```json
{
  "data": {
    "token": "1|abcDef...plain-sanctum-token",
    "rider": {
      "user_id": 4242,
      "phone": "+639171234567",
      "fullname": "Juan dela Cruz",
      "company_id": 12
    }
  }
}
```

**Errors**

| Status | Meaning |
|---|---|
| 422 | Invalid phone format / invalid or expired code / validation failure |
| 404 | Account not found or disabled |
| 429 | Throttle exceeded (5/min) |

> **Lockout:** 10 bad code attempts invalidates the code; the rider must contact the admin to issue a new one.

**curl example**

```bash
curl -X POST https://<host>/api/dispatch/auth/activate \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "09171234567",
    "code": "482910",
    "new_password": "secret-1234",
    "device_name": "Pixel 8 — Juan",
    "fcm_token": "fcm:abc...",
    "platform": "android"
  }'
```

---

### 4.2 `POST /api/dispatch/auth/login`

Public. Throttled **5 requests / minute** per IP+phone.

**Request body**

| Field | Type | Notes |
|---|---|---|
| `phone` | string | Normalized to +63 |
| `password` | string | — |
| `device_name` | string | ≤120 chars |
| `fcm_token` | string? | Optional |
| `platform` | string? | `"android"` or `"ios"` |

**200 response** — same shape as `/auth/activate` (token + rider).

**Errors**

| Status | Meaning |
|---|---|
| 401 | Invalid credentials, account not activated, or account disabled |
| 422 | Invalid phone format |
| 429 | Throttle exceeded |

**curl example**

```bash
curl -X POST https://<host>/api/dispatch/auth/login \
  -H "Accept: application/json" -H "Content-Type: application/json" \
  -d '{"phone":"09171234567","password":"secret-1234","device_name":"Pixel 8 — Juan","platform":"android"}'
```

---

### 4.3 `POST /api/dispatch/auth/logout`

Auth required. Revokes the **current** token + deletes its device record. Other devices remain logged in.

**Request body:** none.

**200 response**

```json
{ "data": { "ok": true } }
```

---

### 4.4 `GET /api/dispatch/me`

Auth required. Returns rider profile + company info. Use on app launch to refresh state.

**200 response**

```json
{
  "data": {
    "rider": {
      "user_id": 4242,
      "phone": "+639171234567",
      "fullname": "Juan dela Cruz",
      "category": "rider",
      "license": "N01-12-345678"
    },
    "company": {
      "id": 12,
      "name": "Acme Logistics",
      "tier": "pro"
    }
  }
}
```

`company` may be `null` if the rider's company row is missing (edge case).

---

### 4.5 `GET /api/dispatch/jobs/today`

Auth required. Returns all jobs assigned to this rider for the current `Asia/Manila` date, ordered by `route_order` (nulls last) then `id`.

**200 response**

```json
{
  "data": {
    "jobs": [
      {
        "id": 901,
        "job_name": "Drop-off — Makati branch",
        "status": 1,
        "job_date": "2026-05-08",
        "address": "1234 Ayala Ave, Makati",
        "lat": 14.5547,
        "lng": 121.0244,
        "route_id": 31,
        "route_order": 2,
        "scheduled_arrival": "2026-05-08 09:30:00",
        "actual_arrival": "2026-05-08 09:34:12",
        "finish_when": null,
        "notes": null,
        "photos": null
      }
    ]
  },
  "meta": { "date": "2026-05-08", "tz": "Asia/Manila" }
}
```

**Notes**
- `photos` is `null` here (only populated on detail and after `/finish`).
- `status: null` jobs are filtered server-side to assigned-only via `UserID = rider.UserID`, so unassigned jobs never appear.

---

### 4.6 `GET /api/dispatch/jobs/{id}`

Auth required. Single job, scoped to the calling rider.

**200 response**

```json
{ "data": { "id": 901, "job_name": "...", "status": 1, "...": "...", "photos": [] } }
```

`photos` is an array (possibly empty) on the detail view: `[ { "id": 17, "photo": "job_901_1715000000_0.jpg" } ]`.

To render a photo, request it from the backend image-serving endpoint *(not yet exposed publicly — coordinate with backend if needed; current files live under `storage/app/dispatch_jobs/`)*.

**Errors**

| Status | Meaning |
|---|---|
| 404 | Job not found or not assigned to this rider |

---

### 4.7 `POST /api/dispatch/jobs/{id}/start`

Auth required. **`Idempotency-Key` (UUID v4) header required.**

Marks job as on-the-way (`status = 1`) and stamps `actual_arrival = now()` if not already set.

**Request body:** none.

**200 response** — same shape as `GET /jobs/{id}` (the updated job).

**Errors**

| Status | Meaning |
|---|---|
| 400 | Missing or non-UUID `Idempotency-Key` |
| 404 | Job not found / not assigned |
| 409 | Job already finished, **OR** duplicate in-flight request with same key |

> If the same `Idempotency-Key` is sent twice within 24h with the same `(user, endpoint)` tuple, the server replays the cached response (same status code). The client may safely retry on network failure with the *same* key.

**curl example**

```bash
curl -X POST https://<host>/api/dispatch/jobs/901/start \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json" \
  -H "Idempotency-Key: $(uuidgen)"
```

**Dart snippet**

```dart
import 'package:uuid/uuid.dart';
final key = const Uuid().v4();
final res = await dio.post('/api/dispatch/jobs/$jobId/start',
  options: Options(headers: { 'Idempotency-Key': key }),
);
```

---

### 4.8 `POST /api/dispatch/jobs/{id}/finish`

Auth required. **`Idempotency-Key` (UUID v4) header required.**

Marks job as finished (`status = 2`), stamps `finish_when = now()`, optionally saves notes, optionally uploads up to 5 proof-of-work photos.

**Request body** (multipart/form-data)

| Field | Type | Notes |
|---|---|---|
| `notes` | string? | ≤ 2000 chars |
| `photos[]` | file[] | Max 5 files, each ≤ 4 MB, must be image (jpg/png) |

**200 response** — updated job with `photos` array populated:

```json
{
  "data": {
    "id": 901,
    "status": 2,
    "finish_when": "2026-05-08 11:42:09",
    "notes": "Customer signed off",
    "photos": [
      { "id": 17, "photo": "job_901_1715000000_0.jpg" },
      { "id": 18, "photo": "job_901_1715000000_1.jpg" }
    ],
    "...": "..."
  }
}
```

**Errors**

| Status | Meaning |
|---|---|
| 400 | Missing or non-UUID `Idempotency-Key` |
| 404 | Job not found / not assigned |
| 409 | Job already finished, OR duplicate in-flight request |
| 422 | Validation failure (file too big, > 5 files, non-image, notes too long) |

> Photo upload + DB write are wrapped in a transaction. If the DB write fails, uploaded files are deleted. Safe to retry with the *same* `Idempotency-Key`.

**curl example**

```bash
curl -X POST https://<host>/api/dispatch/jobs/901/finish \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "notes=Customer signed off" \
  -F "photos[]=@/path/to/proof1.jpg" \
  -F "photos[]=@/path/to/proof2.jpg"
```

---

### 4.9 `POST /api/dispatch/position`

Auth required. **Optional fallback** for GPS reporting when Traxroot device data is stale. Inserts into the shared `VehiclePositions` table keyed by the rider's linked `MasterVehicle.TraxrootID`.

**Request body**

| Field | Type | Notes |
|---|---|---|
| `lat` | number | Between -90 and 90 |
| `lng` | number | Between -180 and 180 |
| `recorded_at` | string? | ISO 8601 datetime; defaults to server `now()` |

**200 response**

```json
{ "data": { "ok": true } }
```

**Errors**

| Status | Meaning |
|---|---|
| 404 | Rider has no `MasterVehicle` row with a `TraxrootID` |
| 422 | lat/lng out of range or non-numeric |

> Cadence is the client's call. A sensible default is **every 30–60 s while the app is foregrounded and the rider is on an active job**. Do not poll while idle.

---

### 4.10 `POST /api/dispatch/devices/refresh-fcm`

Auth required. Updates the FCM token for the **current device** (looked up by Sanctum token ID). Call this whenever Firebase issues a new registration token.

**Request body**

| Field | Type |
|---|---|
| `fcm_token` | string (≤ 255) |

**200 response**

```json
{ "data": { "ok": true } }
```

**Errors**

| Status | Meaning |
|---|---|
| 404 | No device record for the current token (should not happen — implies token was issued without a device row) |

---

## 5. Error code reference

| Code | When it appears | Client should… |
|---|---|---|
| 400 | Missing/invalid `Idempotency-Key` | Generate a new UUID v4 and retry |
| 401 | Invalid credentials, missing/expired Bearer token | Force re-login (drop cached token) |
| 403 | Account disabled | Show "contact your dispatcher" message; clear cached token |
| 404 | Resource missing or not yours | Refresh `/jobs/today`; if persistent, contact admin |
| 409 | Job already finished, OR duplicate in-flight request | Treat as "already done"; refresh job state |
| 422 | Validation failure | Show field-level message |
| 429 | Throttle (login/activate only) | Back off ≥ 60 s before retrying |
| 5xx | Backend error | Retry with exponential backoff; report to backend |

---

## 6. Idempotency: must-read

Two endpoints **require** an `Idempotency-Key` header:

- `POST /jobs/{id}/start`
- `POST /jobs/{id}/finish`

**Rules**

1. The key must be a **UUID v4** (lowercase hex with dashes). Other formats → 400.
2. **Generate a fresh key per logical action**, not per HTTP retry. A retry of "finish job 901" must reuse the same key the original attempt used so the server can replay the response.
3. Keys are scoped to `(key, user_id, endpoint)`. The server caches the response for **24 hours**.
4. Concurrent duplicates (same key in flight) → 409 "Duplicate or in-flight request". Wait and retry once.
5. After a network failure, **retry with the same key**. The server will:
   - Replay the success response (200) if the original completed, OR
   - Run the action if the original threw before recording (the claim is released on uncaught exceptions).

**Recommended client pattern**

```dart
// When the user taps "Start Job", generate ONE key and persist it locally
// against the job ID until the call succeeds:
final key = pendingKeys[jobId] ??= const Uuid().v4();
try {
  await api.startJob(jobId, idempotencyKey: key);
  pendingKeys.remove(jobId);
} on DioException catch (e) {
  // keep pendingKeys[jobId] — next retry uses the same key
}
```

---

## 7. Push notifications

The backend sends FCM v1 messages to the rider's registered device tokens on key events (e.g., new job assignment). Setup:

- Get the Firebase project ID from backend (`FIREBASE_PROJECT_ID` in `.env`).
- Register your Flutter app in that Firebase project.
- Pass the FCM registration token via `fcm_token` on `/auth/login` or `/auth/activate`, and call `/devices/refresh-fcm` when Firebase rotates it.
- Backend silently no-ops if `storage/app/firebase/service-account.json` is absent on the host — coordinate with backend to confirm staging has it.

---

## 8. Smoke test (mobile dev's first-day checklist)

1. Backend admin creates a test rider in `/admin/dispatch/riders` and shares the 6-digit code + phone.
2. App: `POST /auth/activate` with phone + code + chosen password → store the returned token.
3. App: `GET /me` → renders profile/company.
4. Backend admin assigns a job to the test rider for today.
5. App: `GET /jobs/today` → see the job with `status: null`.
6. App: `POST /jobs/{id}/start` with a new UUID Idempotency-Key → response shows `status: 1`.
7. App: `POST /jobs/{id}/finish` with notes + 1 photo → response shows `status: 2` and one photo entry.
8. App: `POST /auth/logout` → token revoked.
9. App: any subsequent call → 401, force re-login.

If any step fails, capture the request (URL, headers, body) and the full error response, and send to backend.

---

## 9. Open items / known caveats

- **No automated tests yet** for the dispatch endpoints — schema and behavior may evolve. Backend will version any breaking change.
- **No throttle on authenticated job endpoints** — please don't spam start/finish; client logic should be event-driven (user tap), not polled.
- **No rider-side image-serving endpoint** for finished-job photos (yet). If the mobile app needs to display photos it just uploaded, render the local file from the picker. If it needs to display photos from another rider/device, ask backend to expose a signed URL.
- **No `forgot password` API** — flow is admin-mediated only (rider contacts admin, admin resets, rider re-activates).
- **Single-tenant phone uniqueness:** phone numbers are globally unique. If a rider switches companies, the admin uses the "Transfer" action; the rider is forced to log in again.
