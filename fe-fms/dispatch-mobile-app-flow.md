# Dispatch Mobile App — Process Flow

> **Audience:** mobile (Flutter) developer and LLM-assisted code generation.
> **Scope:** the runtime flow — what the app does, in what order, and how it reacts to each backend response. Pairs with [dispatch-mobile-api-contract.md](dispatch-mobile-api-contract.md), which defines request/response shapes. UI/UX choices (screens, copy, layout) are out of scope.
> **Convention:** "the app" = the mobile client. "Backend" = `/api/dispatch/*`. All times are `Asia/Manila`.

---

## 1. Actors and prerequisites

| Actor | Channel | Role |
|---|---|---|
| Admin (dispatcher) | Web console `/admin/dispatch/riders` | Creates rider accounts, issues activation codes, assigns/reassigns jobs, resets passwords, disables accounts. The mobile app does not touch this surface. |
| Rider | Mobile app | Activates account, logs in, views assigned jobs for today, starts and finishes jobs, optionally reports GPS. |
| Backend | Laravel + Sanctum | Validates tokens, enforces idempotency, persists job state, sends FCM push on assignment events. |

**Before a rider can use the app at all**, an admin must:
1. Create the rider in the web console (captures phone, fullname, etc.).
2. Issue a 6-digit activation code (24 h TTL, shown once in the admin UI).
3. Communicate phone + code to the rider out-of-band (in person / SMS / call).

---

## 2. Persistent client state

The app must persist (across cold starts) the following:

| Key | Type | Purpose | Lifetime |
|---|---|---|---|
| `auth.token` | string | Sanctum bearer token | Until logout, 401, or admin-side revoke |
| `auth.rider` | object | `{user_id, phone, fullname, company_id}` from login response | Refreshed by `GET /me` on app launch |
| `pending_idempotency_keys` | map<jobId, uuid> | One UUID per in-flight `start` or `finish` action | Deleted after the call returns 2xx or terminal 4xx |
| `pending_actions` | queue | Optional offline queue (see §8) | Until drained |
| `fcm.token` | string | Last FCM registration token sent to backend | Until Firebase rotates it |

**Never** persist the activation code or the user's password.

---

## 3. Token lifecycle (state machine)

```
        ┌─────────────────┐
        │   UNAUTHED      │  app launches with no token
        └────────┬────────┘
                 │
      activate or login (200)
                 │
                 ▼
        ┌─────────────────┐
        │  AUTHENTICATED  │◄─────── refresh-fcm, /me, /jobs/*, /position
        └────────┬────────┘
                 │
   ┌─────────────┼──────────────────┐
   │             │                  │
   │    /auth/logout (200)    any 401 from backend
   │             │                  │
   │             ▼                  ▼
   │     drop token, return    drop token, surface
   │     to UNAUTHED           "session expired",
   │                           return to UNAUTHED
   │
   │    403 "account disabled"
   │             │
   │             ▼
   │     drop token, surface "account disabled — contact dispatcher",
   │     return to UNAUTHED. Block re-login attempts until user
   │     dismisses the message.
```

**Rules**
- A 401 from **any** authenticated endpoint is terminal for that token. Do not retry the same call. Drop the token and route to the login screen.
- A 403 from `dispatch.rider` middleware means the admin disabled the account mid-session. Treat as terminal logout, but surface a different message than 401.
- The app does not need to "ping" the backend to validate the token — let the next real call fail naturally.

---

## 4. Job lifecycle (state machine)

A job, from the rider's perspective, has these states (`status` field on the job payload):

```
   null (unassigned)        ── invisible to rider; filtered server-side ──
       │
       │  admin assigns rider, FCM push delivered
       ▼
   null  (visible on /jobs/today, awaiting rider action)
       │
       │  rider taps "Start" → POST /jobs/{id}/start (idempotent)
       ▼
   1  (on-the-way)
       │
       │  rider taps "Finish" → POST /jobs/{id}/finish (idempotent, optional photos+notes)
       ▼
   2  (finished)            — terminal for the rider; no further actions allowed
```

**Status `3` (reschedule pending)** is set by an admin action, not the rider. When the app sees `status: 3` on a job, treat it as **read-only** (no Start, no Finish). Surface a banner like "rescheduled — awaiting dispatcher" and continue to show it in the list until it disappears (admin will either delete or reassign it for a different date).

**Forbidden transitions** (the backend will reject these — the app should disable the corresponding buttons):
- `2 → 1` (cannot un-finish): backend returns 409 "Job already finished".
- `start` or `finish` on a job that is not assigned to this rider: backend returns 404.
- `finish` without first calling `start` is **allowed** by the backend (it just sets `status: 2`). The app may either allow it or enforce client-side ordering — backend doesn't care.

---

## 5. Happy path

This is the canonical "first-time rider, first job of the day" sequence.

### 5.1 First launch — activation

```
1. App launches → reads auth.token from storage → none found.
2. Show phone-entry screen.
3. User enters phone + 6-digit code (received from admin) + chosen password.
4. App: POST /api/dispatch/auth/activate
     {
       phone, code, new_password,
       device_name: "<model> — <user-chosen label>",
       fcm_token:   <from FirebaseMessaging.getToken(), nullable>,
       platform:    "android" | "ios"
     }
5. On 200:
     persist auth.token   ← response.data.token
     persist auth.rider   ← response.data.rider
     persist fcm.token    ← whatever the app sent
     transition to AUTHENTICATED → home screen.
6. On 422 "Invalid or expired code" → see §6.1.
7. On 404 "Account not found or disabled" → see §6.2.
```

### 5.2 Subsequent launches — login

```
1. App launches → reads auth.token from storage → present.
2. App: GET /api/dispatch/me   (token validity check + profile refresh)
3. On 200: render home; refresh auth.rider; proceed to §5.3.
4. On 401: drop auth.token, route to login screen.
```

If the user logs out and comes back:

```
1. Show phone+password screen.
2. App: POST /api/dispatch/auth/login
     { phone, password, device_name, fcm_token, platform }
3. On 200: same as activation step 5.
4. On 401 "Invalid credentials" → surface error, allow retry.
5. On 429 → see §6.3.
```

### 5.3 Daily workflow

```
1. App: GET /api/dispatch/jobs/today
2. Render the list ordered as returned (server-sorted by route_order, id).
3. User taps a job → app may either:
     (a) navigate using the data already in the list, OR
     (b) GET /api/dispatch/jobs/{id} for a fresh copy.
   Both are valid. Prefer (b) before showing Start/Finish actions to
   avoid acting on stale state.

4. User taps "Start":
     a. key = pending_idempotency_keys[jobId] ?? Uuid.v4()
     b. persist pending_idempotency_keys[jobId] = key
     c. POST /api/dispatch/jobs/{id}/start
        Header: Idempotency-Key: <key>
     d. On 200: update local job to status=1; remove pending_idempotency_keys[jobId].
     e. On 409 "Job already finished": refresh the job (GET /jobs/{id}); remove pending key.
     f. On network failure / 5xx: KEEP pending_idempotency_keys[jobId]. Retry later with the SAME key.

5. User performs the work physically; app may post GPS pings (§5.4).

6. User taps "Finish":
     a. Optionally collect photos (≤ 5, ≤ 4 MB each, image only) and notes (≤ 2000 chars).
     b. key = pending_idempotency_keys[jobId] ?? Uuid.v4()  (a NEW key — different from the start key)
        NOTE: Use a DIFFERENT key namespace, e.g. pending_idempotency_keys["finish:$jobId"],
        because start and finish are separate logical actions on the backend.
     c. persist pending_idempotency_keys["finish:$jobId"] = key
     d. POST /api/dispatch/jobs/{id}/finish (multipart)
        Header: Idempotency-Key: <key>
        Body: notes (optional), photos[] (optional)
     e. On 200: update local job to status=2; populate photos from response;
        remove pending_idempotency_keys["finish:$jobId"].
     f. On 409 "Job already finished": refresh the job; remove pending key.
     g. On network failure / 5xx: KEEP pending key; retry later with same key + same files.
        (See §8 for the retry pattern with files.)

7. User taps "Logout":
     a. POST /api/dispatch/auth/logout
     b. Regardless of response (200 or network failure), wipe auth.token,
        auth.rider, fcm.token, and pending keys locally. Return to login screen.
        Rationale: a stuck token is harmless (server will revoke on its own
        TTL or on next admin action); leaving the app "logged in" with a
        revoked token is a worse UX.
```

### 5.4 Optional: GPS reporting

If product wants it, while the app is foregrounded **and** at least one job is in `status: 1`:

```
every 30–60 s:
   POST /api/dispatch/position { lat, lng, recorded_at: <ISO8601> }
```

Stop posting when the app is backgrounded or there are no active jobs. **Do not** queue offline GPS pings — the value of stale GPS is near zero.

A 404 "No vehicle linked to rider" is **not** a fatal error: the rider's `MasterVehicle` record is missing or has no Traxroot ID. Suppress the error after the first occurrence (log it, stop retrying for the session) and let the dispatcher fix the vehicle link admin-side.

---

## 6. Error and retry flows

### 6.1 Bad activation code (422)

The backend tracks `ActivationAttempts`. After **10** bad codes, the code is invalidated server-side; the rider must contact the admin for a new one.

```
- attempts 1–9: the app shows the error and allows retry.
- attempt 10: backend returns 422 — the app cannot distinguish "bad code"
  from "code now invalidated" by status alone. Always surface the
  errors[0].message string; include "if this keeps failing, contact your
  dispatcher" in the UI.
```

The app **must not** track attempts client-side or proactively block — the server is authoritative.

### 6.2 Activation: account not found / disabled (404)

Two causes, indistinguishable to the client:
- Phone has no `DispatchRiderAuth` row (admin didn't create it).
- Account exists but `Status = 'disabled'`.

App action: surface "Account not found or disabled — contact your dispatcher." No retry.

### 6.3 Throttle (429)

Only `/auth/login` and `/auth/activate` are throttled (5/min per IP+phone). On 429:
- Disable the submit button for at least 60 s.
- Surface the throttle message.
- Do **not** silently retry.

### 6.4 401 mid-session

Any authenticated endpoint may return 401 if:
- Token was revoked admin-side (password reset, transfer, device revoke).
- Token was deleted by another logout from the same device (race).

```
on 401 from any endpoint except /auth/login and /auth/activate:
   wipe auth.token, auth.rider, pending_idempotency_keys
   route to login screen
   surface "Session expired — please sign in again."
```

### 6.5 403 "account disabled" mid-session

```
on 403 with errors[0].message containing "disabled":
   wipe auth state (same as 401)
   surface "Account disabled — contact your dispatcher."
   keep the user on a dead-end screen; do NOT show the login form
   until they dismiss the message (so they don't immediately re-attempt).
```

### 6.6 Idempotent retries (start / finish)

The cardinal rule: **one logical action = one Idempotency-Key**. A network retry of the same logical action MUST reuse the same key.

```
function callIdempotent(action, jobId, fn):
   bucket = "pending_idempotency_keys[$action:$jobId]"
   key = read(bucket) or Uuid.v4()
   write(bucket, key)
   try:
      response = fn(key)               // POST with Idempotency-Key: $key
      if response.status in [200, 409]: clear(bucket)   // terminal
      return response
   catch network_error, 5xx:
      // KEEP bucket — next retry uses same key
      throw
```

**Server response semantics with the same key:**

| Server saw | Returns |
|---|---|
| Original call already completed (any 2xx or 4xx) | The cached response, same status code (replay) |
| Original call still in flight (very rare) | 409 "Duplicate or in-flight request" |
| Original call threw an uncaught exception (claim released) | Acts as a fresh call (re-runs the action) |

**Key rotation:** if the app receives a terminal response (200, 404, 409, 422), the action is settled; clear the persisted key. The next user-initiated action gets a fresh UUID.

**24-hour TTL:** keys expire server-side after 24 h. If the app holds a key longer than that and retries, the server treats it as fresh — which is fine, because by that point any server-side effect was either committed or rolled back long ago.

### 6.7 Validation errors on finish (422)

```
{ "message": "...", "errors": { "photos.0": ["The photos.0 must not be greater than 4096 kilobytes."] } }
```

App action: surface the field message; do NOT retry automatically. The user must remove or replace the offending file. **Clear the persisted Idempotency-Key for this finish** since the request never produced a server-side effect — but reusing it would also be safe.

---

## 7. Multi-device and token rotation

### 7.1 Multi-device support

The backend allows multiple active tokens per rider, one per device. Each `/auth/login` and `/auth/activate` call issues a **new** token + creates a `DispatchRiderDevice` row keyed by `device_name`.

The app should **not** assume one device per rider:
- Don't show a "you are signed in elsewhere" warning. The backend doesn't surface that.
- Logout only kills the **current** device's token.

### 7.2 Admin-side device revocation

The admin can revoke a single device from the web console. The next API call from that device returns 401. App handles it via §6.4.

### 7.3 FCM token rotation

Firebase rotates the FCM registration token periodically (app reinstall, token expiry, restored from backup). Hook:

```
FirebaseMessaging.onTokenRefresh listener:
   newToken = event.token
   if auth.token is present:
      POST /api/dispatch/devices/refresh-fcm { fcm_token: newToken }
      on 200: update fcm.token in storage
      on 401: handle as §6.4
      on 404: log + surface to backend (device row missing — rare race)
   else:
      cache newToken; send on next login/activate via the fcm_token field.
```

Do **not** call `refresh-fcm` if the token hasn't changed — it's harmless but wasteful.

### 7.4 Re-authentication after admin password reset

If the admin resets the rider's password, all tokens for that rider are revoked. The rider must re-activate (the admin shows them a new 6-digit code). From the mobile app's perspective, this is identical to the very first activation (§5.1), except the rider already exists in the system. The app does not need to distinguish.

### 7.5 Re-authentication after company transfer

If a superadmin transfers the rider to a different company, all tokens are revoked. The rider's phone and password are unchanged, so the rider just logs in again (§5.2). The next `/me` will show a different `company`.

---

## 8. Offline / poor connectivity

> **Backend has no offline queue support.** Everything below is a client-side recommendation. Adopt only what's worth the engineering cost — most riders will be online most of the time.

### 8.1 Read paths

| Endpoint | Cache strategy |
|---|---|
| `GET /me` | Cache the last response; refresh on app foreground. Show cached data with a "stale" indicator if offline. |
| `GET /jobs/today` | Cache last response. Show cached list when offline. Refresh on foreground and on pull-to-refresh. |
| `GET /jobs/{id}` | Optional cache. Detail can fall back to the list payload (it's the same shape minus `photos`). |

### 8.2 Write paths — what to queue and what NOT to queue

| Action | Queue while offline? | Why |
|---|---|---|
| `POST /auth/activate` | **No** — interactive, user must see result | — |
| `POST /auth/login` | **No** | — |
| `POST /auth/logout` | **No** — wipe locally, don't bother retrying | A revoked-but-unsent logout is harmless. |
| `POST /jobs/{id}/start` | **Yes** — high value, idempotent | Persist the Idempotency-Key + jobId; drain on reconnect. |
| `POST /jobs/{id}/finish` | **Yes** — high value, idempotent, but with caveats | Persist the key, jobId, notes, AND **the actual photo file paths** (not just metadata). On drain, re-read the files and re-upload. If a photo file has been deleted from the device, the queued action fails — surface to user. |
| `POST /position` | **No** — stale GPS is worthless | Drop offline GPS pings. |
| `POST /devices/refresh-fcm` | **Yes** — small, idempotent on FCM token equality | Coalesce: only the latest FCM token needs to be sent. |

### 8.3 Drain order on reconnect

```
on connectivity restored:
   for each queued action in FIFO order:
      execute it with its persisted Idempotency-Key
      on 2xx: remove from queue
      on 409 (already finished / already done): remove from queue (it's done)
      on 401: stop draining; route to login (§6.4)
      on 422 (validation): remove from queue, surface to user
      on 5xx / network error: stop draining, retry later
```

### 8.4 Optimistic UI

Allowed for `start` and `finish` IF the app is willing to roll back on terminal failure (404, 422):

```
when user taps Start while offline:
   immediately render job as status=1 in the local UI
   queue the start action
   on terminal failure during drain: revert the local status, surface the error
```

If the team prefers correctness over snappiness, skip optimistic UI and just block actions while offline.

### 8.5 Conflict semantics

Two scenarios where the queue might "race" with reality:

- **Admin reassigned the job mid-offline.** On drain, `start` returns 404. Drop the queued action and refresh `/jobs/today`.
- **Rider already finished the job from a second device.** On drain, `finish` returns 409. Drop the queued action and refresh.

These are user-visible state changes; surface a brief "Job updated by dispatcher" notice rather than a hard error.

---

## 9. App lifecycle hooks

| Event | App action |
|---|---|
| Cold start, has token | `GET /me` → if 401, route to login; else `GET /jobs/today` |
| Cold start, no token | Route to login |
| Foreground after background | `GET /jobs/today` (refresh); drain offline queue if non-empty |
| Background | Stop GPS pings; do **not** revoke token |
| Receive FCM push | If push payload includes `job_id`, refresh `/jobs/today` and optionally `/jobs/{id}`; surface system notification |
| Network reconnect | Drain offline queue (§8.3) |
| FCM `onTokenRefresh` | §7.3 |
| Logout button | §5.3 step 7 |

---

## 10. Sequence diagrams (compact)

### 10.1 First-time activation

```
Rider          App                 Backend            Admin
  │            │                     │                  │
  │  (out-of-band: phone + code)     │◄─ creates rider, issues code
  │ ─────────────────────────────────┼──────────────────│
  │            │                     │                  │
  │ enter phone, code, password      │                  │
  │ ──────────►│                     │                  │
  │            │ POST /auth/activate │                  │
  │            │ ───────────────────►│                  │
  │            │ ◄───── 200 token,rider                  │
  │            │ persist token       │                  │
  │            │ GET /me             │                  │
  │            │ ───────────────────►│                  │
  │            │ ◄───── 200 profile                      │
  │            │ GET /jobs/today     │                  │
  │            │ ───────────────────►│                  │
  │ ◄── home screen with job list   │                  │
```

### 10.2 Start → finish a job (with retries)

```
Rider     App                              Backend
  │       │                                  │
  │ taps Start                               │
  │ ─────►│                                  │
  │       │ key = uuid; persist              │
  │       │ POST /jobs/901/start             │
  │       │ Idempotency-Key: <key>           │
  │       │ ──────── network drop ─────────►(timeout)
  │       │ (keep persisted key)             │
  │       │                                  │
  │       │ retry: POST /jobs/901/start      │
  │       │ Idempotency-Key: <same key>      │
  │       │ ────────────────────────────────►│
  │       │ ◄──── 200 status=1 (replay or fresh)
  │       │ clear persisted key              │
  │ ◄── UI shows "On the way"               │
  │                                          │
  │ taps Finish (with photos+notes)          │
  │ ─────►│                                  │
  │       │ key2 = uuid; persist             │
  │       │ POST /jobs/901/finish (multipart)│
  │       │ Idempotency-Key: <key2>          │
  │       │ ────────────────────────────────►│
  │       │ ◄──── 200 status=2, photos       │
  │       │ clear persisted key              │
  │ ◄── UI shows "Done"                      │
```

### 10.3 Token revoked admin-side

```
Rider     App                              Backend
  │       │ GET /jobs/today                  │
  │       │ ────────────────────────────────►│
  │       │ ◄──── 401                        │
  │       │ wipe token + state               │
  │ ◄── login screen, "Session expired"     │
```

---

## 11. Quick checklist for the mobile dev

Before declaring v1 ready:

- [ ] Persisted: `auth.token`, `auth.rider`, `fcm.token`, `pending_idempotency_keys`.
- [ ] All authenticated requests carry `Authorization: Bearer <token>` and `Accept: application/json`.
- [ ] `start` and `finish` calls always carry an `Idempotency-Key: <uuid-v4>` header, persisted across retries.
- [ ] Different keys for `start:$jobId` and `finish:$jobId` (different logical actions).
- [ ] Single 401 handler that wipes state and routes to login.
- [ ] Single 403-disabled handler that surfaces a different message.
- [ ] FCM `onTokenRefresh` posts to `/devices/refresh-fcm`.
- [ ] Logout wipes local state regardless of network response.
- [ ] No GPS pings while backgrounded or no active jobs.
- [ ] Offline queue (if implemented) only queues `start`, `finish`, and `refresh-fcm`.
- [ ] Photos validated client-side: image only, ≤ 4 MB each, ≤ 5 per finish.
- [ ] Phone numbers can be entered as `09…`, `639…`, or `+639…`; canonical value comes from server response.
- [ ] Smoke test (§8 of the contract doc) passes end-to-end against staging.
