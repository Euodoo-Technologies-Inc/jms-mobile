# Conversation History

A log of Claude Code sessions for this project, intended as a quick way to recover context when resuming closed sessions.

## How to use

- Append a new entry at the top of the **Sessions** list for each meaningful session.
- Keep entries short: what was worked on, decisions made, files touched, and open follow-ups.
- To resume a prior session in the terminal: `claude --resume` (interactive picker) or `claude --continue` (most recent in this directory).

## Entry template

```
### YYYY-MM-DD — <short title>
- **Goal:** <what the user wanted>
- **Changes:** <files/areas modified>
- **Decisions:** <non-obvious choices and why>
- **Open items:** <follow-ups, TODOs, blockers>
```

## Sessions

### 2026-05-11 — Dispatch UI build-out on `main`

- **Goal:** Implement the full dispatch rider surface per `dispatch-mobile-api-contract.md` and `dispatch-mobile-app-flow.md`, side-by-side with the existing legacy app (no legacy backend changes).
- **Changes:**
  - **Local backend default**: [variables.dart](lib/core/constants/variables.dart) — `BASE_URL` defaults to `http://10.0.2.2:8000/myapi` for emulator dev against local Laravel + `efms` DB.
  - **Dispatch infrastructure**: [lib/core/dispatch/](lib/core/dispatch/) — `dispatch_constants.dart` (endpoints, prefs keys, contract limits), `dispatch_api_client.dart` (bearer + idempotency + `{data,meta,errors}` envelope + `DispatchApiException`), `dispatch_idempotency.dart` (persistent UUID v4 keys per action), `dispatch_uuid.dart` (RFC 4122 v4, no `uuid` pkg).
  - **Data layer**: [lib/data/dispatch/](lib/data/dispatch/) — `DispatchJob`/`DispatchRider`/`DispatchCompany`/`DispatchJobPhoto` models, `DispatchAuthDatasource` (activate/login/logout/me/refresh-fcm), `DispatchJobsDatasource` (today/detail/start/finish), `DispatchPositionDatasource`, `DispatchQueueRepository` (offline queue with photo copies in `<docs>/dispatch_queue_photos/`).
  - **Controllers**: [lib/page/dispatch/controller/](lib/page/dispatch/controller/) — `DispatchAuthController` (cold-start `/me`, 401/403-disabled handlers, persistent token/rider/company), `DispatchJobsController` (jobsToday + cache + foreground refresh via `WidgetsBindingObserver`, idempotency rules, network-failure enqueue throwing `DispatchQueuedException`).
  - **Services**: [lib/page/dispatch/service/](lib/page/dispatch/service/) — `DispatchFcmService` (`onTokenRefresh` → `/devices/refresh-fcm` + `onMessage`/`onMessageOpenedApp`/`getInitialMessage` → refresh jobs when `data.job_id` present), `DispatchPositionService` (45s GPS pings only while foregrounded + authed + ≥1 active job; suppresses on first 404), `DispatchSyncService` (drains offline queue FIFO on reconnect/auth-flip per §8.3).
  - **UI**: [lib/page/dispatch/presentation/](lib/page/dispatch/presentation/) — `DispatchLoginPage`, `DispatchActivatePage`, `DispatchJobsPage` (with stale-cache banner + pending-sync chip), `DispatchJobDetailPage` (status-gated Start/Finish + filename-only photos placeholder), `DispatchFinishJobPage` (≤5 photos × ≤4MB + notes ≤2000), `DispatchDisabledPage` (dead-end 403 screen).
  - **Integration**: [main.dart](lib/main.dart) registers `DispatchAuthController` + the three services as permanent; `RootGate` prefers dispatch (or `DispatchDisabledPage` when latched). [login_page.dart](lib/page/auth/presentation/login_page.dart) gained a "Rider sign-in (dispatch)" link.
  - **Polish**: Suppress Android 12+ stretch overscroll + bouncy physics globally via [no_stretch_scroll_behavior.dart](lib/core/widgets/no_stretch_scroll_behavior.dart) wired in `GetMaterialApp.scrollBehavior`.
  - **Dep**: Added `geolocator: ^13.0.2` to [pubspec.yaml](pubspec.yaml) for GPS pings; Android location permissions already present.
- **Decisions:**
  - **Side-by-side** legacy + dispatch (option B): both surfaces co-exist. `RootGate` prefers dispatch when both authed; legacy login screen has an explicit "Rider sign-in (dispatch)" entry point.
  - **No UUID dep**: hand-rolled v4 to keep `pubspec` lean.
  - **Photos display**: filenames-as-chips placeholder — backend has no rider-side image-serving endpoint yet (contract §9). Swap to network thumbnails once exposed.
  - **No optimistic UI** for start/finish (correctness over snappiness, per docs §8.4).
  - **Auth flip + nav unwind bug** fixed by `Get.offAll(() => const RootGate())` after login/activate instead of `popUntil` — the Obx swap was racing with route-stack manipulation.
  - **Persistent cache for `/jobs/today`** lives in SharedPreferences. On API failure, cached list stays visible with an amber "stale" banner instead of a blank error screen. Future refreshes overwrite on success.
- **Open items:**
  - **Backend bug**: `/jobs/today` currently returns 500 — `Call to member function toDateString() on string`. Fix in `laravel-fms` (cast `job_date`/`scheduled_arrival`/etc. as `date`/`datetime` on the dispatch Job model, or wrap with `Carbon::parse(...)`). Until then, first-ever launch on a fresh install still shows the error screen; once one successful fetch lands, the cache covers subsequent failures.
  - **Forgot-password** is admin-mediated only per contract; no app-side button.
  - **Photo thumbnails** pending backend signed-URL endpoint.
  - **Smoke test (contract §8)** end-to-end pending the toDateString fix.

### 2026-05-11 — Set up history.md
- **Goal:** Create a running log of Claude Code sessions to aid resuming closed conversations.
- **Changes:** Added `history.md` (this file).
- **Decisions:** Newest-first ordering; manual entries (not auto-generated) to keep them concise and meaningful.
