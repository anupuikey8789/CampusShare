# CampusShare Marketplace Repair and Readiness Report

## A. What was inspected

- Branch and Git status, including the 24 staged generated-file deletions.
- Task 12/13 reports, frontend API/auth/app/UI code, C++ Crow routes/configuration/CORS, backend tests, CMake/MSVC settings, marketplace migration/rollback/verification/guide, and resource-image SQL package.
- Local backend health, CORS response/preflight, process ID/path, and binary/source timestamps. `BACKEND/.env` and `FRONTEND/config.local.js` were not read. No credentials or tokens were inspected.
- No Supabase project or SQL editor was accessed.

## B. Diagnosed problems

### Sell and Donate

**IMPLEMENTED:** The frontend and backend contain distinct Sell and Donate listing forms, filtering, details, transfer requests, approval/rejection and completion routes. The SQL proposal defines transaction RPCs and listing states.

**BLOCKED:** The live local `/api/health` response omits `marketplace_enabled` (the current frontend correctly treats an absent flag as false). `SUPABASE_MARKETPLACE_ENABLED` defaults to false in the safe template. The repository’s latest integration reports say the marketplace migration was not applied or validated. The pages’ “unavailable” notices are therefore a fail-closed state; removing them or forcing the flag would not make the database operations safe. The active `.env` value was not read and is unknown.

### Borrowing

**LOCALLY TESTED:** `http://127.0.0.1:18080/api/health` returned HTTP 200. A GET to `/api/resources` without a token returned HTTP 401 as expected, with CORS headers for `http://localhost:5500`. An OPTIONS preflight returned HTTP 204 with the expected origin, methods and headers.

**BLOCKED:** The currently running process reports borrow-request creation, status actions and atomic resource updates as false. This is why the request/owner buttons are disabled. No flag was enabled.

### Backend “could not be reached” message

The backend is listening on `127.0.0.1:18080`; health, CORS and preflight succeeded locally. So the backend being stopped and this server’s CORS allowlist are not the cause of that exact browser message during this inspection. The API helper uses that message only when browser `fetch` rejects. The configured browser API base and the browser’s actual failing request could not be verified without reading the prohibited `config.local.js` or using the signed-in browser session. The cause of that particular browser fetch rejection remains **NOT VERIFIED**.

### Stale running executable

PID **32268** is running `BACKEND/build-msvc/campusshare_backend.exe`. Its recorded timestamp is earlier than the current `BACKEND/main.cpp`. Its health JSON omits the current `marketplace_enabled` and `resource_images_enabled` fields. This is direct evidence that the server is running an older build. PID 32268 was not stopped. A fresh Release executable was built separately in a temporary directory and was not bound to port 18080.

### Resources could not be loaded

The unauthenticated resource request correctly returns 401. Since the signed-in browser token and actual request were not inspected or replayed, the authenticated request’s result is **NOT VERIFIED**. A failed auth/session or a browser API-base mismatch can explain the page message; no root cause for that authenticated request can be asserted from the available evidence.

## C. Files changed in this task

- `SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql` — hardened the image metadata delete RPC to refuse deletion while its Storage object still exists.
- `SUPABASE_STAGING_MARKETPLACE_GUIDE.md` — documented the Storage-first deletion sequence and non-atomic recovery case.
- `CAMPUSSHARE_TASK_13_REPORT.md` — corrected the stale claim that the proposed marketplace migration lacks image-count/order concurrency protection.
- `CAMPUSSHARE_MARKETPLACE_REPAIR_REPORT.md` — this report.

No frontend or C++ source was changed in this task. Existing source already implements the UI and gated API operations; the live application is using an older executable and the relevant feature flags/database setup are not verified.

## D. Frontend changes/status

**IMPLEMENTED:** Separate Borrowing, Sell, Donate, Browse and My Resources views; filters; resource forms and validation; authenticated API helper; image previews/gallery; request controls; loading/error/empty states and payment disclaimers exist in the current source.

**NOT VERIFIED:** No browser-based two-account test was run. Filters currently operate on records returned by the API; the resource API returns at most 100 rows and does not provide server-side search/filter pagination. Dashboard counts use returned records and are not global totals.

## E. Backend changes/status

**IMPLEMENTED:** The current C++ source contains authenticated category/resource CRUD, borrow request read/create/status routes, transfer request operations, image metadata/order/delete routes, handover routes, listing report routes, Auth verification, CORS and feature-flag gates. Sensitive Auth tokens are passed in the Bearer header and are not intentionally logged. No service-role key is used for normal requests.

The route families and contracts are documented in `BACKEND/README.md` and `SUPABASE_STAGING_MARKETPLACE_GUIDE.md`. Marketplace mutations call RPCs with the verified user's JWT; there is no direct-write fallback for these gated mutations. Health is unauthenticated and exposes feature booleans only.

## F. SQL changes prepared

The migration already contains:

- Marketplace listing fields and checks.
- Borrow/transfer request constraints and unique indexes for active borrower/resource requests and one approved transfer per resource.
- Image metadata with a deferrable unique `(resource_id, sort_order)` constraint; registration locks the resource row before checking/inserting images.
- Owner/auth checks and row locking inside proposed RPCs.
- RLS/grants, Storage prerequisites, and a conservative rollback/verification package.

This task aligned the full marketplace migration’s `delete_resource_image_metadata` body with the image-only RPC proposal: it first captures the image path, verifies the current owner and row lock, then refuses metadata deletion while the corresponding `storage.objects` row remains. This prevents a direct metadata-only RPC call from orphaning a live object. The C++ sequence remains Storage DELETE first, then metadata RPC. Because those operations are not one cross-service transaction, a failure between them still needs exact-path recovery.

**NOT VERIFIED:** PostgreSQL syntax/behavior, actual Staging schema, grants, RLS, Storage policies, function definitions, or concurrency behavior. No SQL was executed.

## G. API route summary

| Route family | Operations | Gate / access |
|---|---|---|
| `/api/health`, `/api/test` | GET | Public diagnostics; health reports configured flags only |
| `/api/categories`, `/api/resources`, `/api/resources/{id}` | GET; resource POST/PATCH/DELETE | Authenticated; resources use verified user JWT and RLS |
| `/api/borrow-requests` | GET, POST; `/{id}/approve`, `/{id}/reject`, `/{id}/return` POST | Authenticated; creation/status mutation RPC flags remain false; no direct-write fallback |
| `/api/marketplace/transfer-requests`, `/api/resources/{id}/transfer-requests` | GET / POST; transfer `approve`, `reject`, `cancel`, `complete-sale`, `complete-donation` POST | Authenticated; marketplace flag remains false |
| `/api/resources/{id}/images`, `/api/resources/{id}/images/reorder`, `/api/resource-images/{id}` | GET/POST, POST, DELETE | Authenticated; image flag remains false; Storage policies and RPC grants are separate requirements |
| `/api/resources/{id}/handover` | GET/PUT | Authenticated; marketplace flag and database RLS required |
| `/api/resources/{id}/reports`, `/api/marketplace/reports`, `/api/marketplace/reports/{id}/review` | POST, GET, POST | Authenticated; marketplace flag; trusted moderator claim enforced in proposed RPC |

The current API resource and request list operations cap reads at 100 records. Pagination, server-side combined filtering, and complete-result statistics remain unfinished.

## H. Security findings

- **IMPLEMENTED in source/proposals:** Verified Supabase Auth user identity; user JWT forwarded separately from the public API key; ownership IDs derived server-side; RPC-only sensitive mutations; no service-role bypass; marketplace and image operations default disabled.
- **SQL proposal only:** Transactional row locks, uniqueness constraints, current-owner checks, RLS/grants, Storage path restrictions and moderator claim checks.
- **NOT VERIFIED:** Actual Staging broad `storage.objects` policy inventory, applied grants/RLS, Storage configuration, Auth claims, RPC ACLs and two-user authorization. The owner must run the read-only verification queries and inspect all Storage policies before applying/enabling anything.
- **Moderator workflow:** Proposed review RPC trusts the signed `app_metadata.campusshare_role=moderator` claim. A trusted administrator must provision and revoke that claim securely; no live moderator role configuration was verified.
- **Permanent transfers and images:** Images use the uploader's UUID folder. A recipient of a completed sale/donation cannot delete inherited objects under the former owner's UUID under the current strict Storage DELETE policy. Requires a separate owner-reviewed cleanup/transfer design.
- **Paid borrowing:** The current request RPC/API contract records resource, borrower, due dates and status but does not snapshot the agreed charge amount/type on each request. Preventing later price edits from changing a pending request's displayed terms requires an explicit schema/RPC decision and migration before this is treated as a reliable rental contract.
- **Names:** Current profile RLS only establishes own-profile visibility. Public seller/donor/borrower display names are not verified as available through a safe profile policy/API. No private contact information is exposed to work around this.

## I. Tests executed

- Frontend suite: `node --test FRONTEND/tests/*.test.cjs` — **76 passed, 0 failed** (mock/UI/API tests).
- JavaScript syntax: `node --check` for `app.js`, `api.js`, `auth.js`, `ui-model.js`, `config.js` — **passed**.
- MSVC/CMake Release build of current C++ source in a unique temporary directory — **passed**. This avoided replacing the executable held by PID 32268.
- Backend mock API suite against that fresh temporary executable — **passed**. Covered configuration/flag validation, Auth mocks, API key/Bearer separation, RPC-only operations/no fallback, transfer/atomic edit/image/handover/report paths, malformed responses, timeouts and CORS.
- Local unauthenticated health/CORS/OPTIONS checks — health 200, resources 401 without token, preflight 204 with allowlisted origin. These are local server checks, not live Supabase tests.
- SQL text checks: verified the image table/index/constraint and RPC names, Storage DELETE folder predicate, verification query alias, function body drift fingerprints, balanced SQL quoting and absence of unfinished markers — **passed static checks**.
- `git diff --check` and staged diff check — passed with existing line-ending conversion warnings only.

## J. Tests not executed

- No live Supabase Auth, PostgREST, Storage, RLS, RPC or database transaction tests; no credentials/session were used and no Supabase project was accessed.
- No two-account browser tests, responsive browser automation, concurrent database tests, actual seller/buyer/donor/owner actions, or private handover visibility test.
- No PostgreSQL parser/execution. Static text checks do not validate SQL syntax or database semantics.
- The fresh executable was not started because port 18080 is already owned by PID 32268, which the task forbids stopping. The existing process itself was left untouched.

## K. Features verified locally

- **LOCALLY TESTED / MOCK TESTED:** Current-source C++ Release compilation and backend mock route suite.
- **MOCK TESTED:** Existing frontend unit/UI/API tests, including Sell/Donate/borrow/image flows behind flags and failure behavior.
- **LOCALLY TESTED:** Existing server port, health and CORS/preflight behavior for `http://localhost:5500`.
- **NOT VERIFIED:** End-to-end browser to authenticated backend to Staging database.

## L. Supabase Staging status

**NOT VERIFIED.** No Staging project was accessed in this task; the migration and policies remain proposals unless the owner applied them separately. No feature was tested against live Staging. Nothing here is labeled STAGING VERIFIED.

## M. Feature availability and flags

The running health response explicitly reports borrow-request creation, borrow status changes, and atomic resource updates as false. It omits marketplace and image flag properties because the process is stale; the frontend treats missing properties as false. The active `.env` was not inspected, so the configured marketplace/image flag values are unknown. No flags were changed. Do not enable any flag until matching Staging SQL, policies, grants, runtime configuration and two-account tests are reviewed and pass.

## N. Manual Staging steps

1. Review the Marketplace migration, rollback, verification and guide, including the corrected image-delete RPC. Use only the project reference `jxndjuslvccxgayoachm`.
2. In the Staging SQL Editor, run the guide's read-only preflight and inspect every `storage.objects` policy before applying anything. Stop if any broad or unexpected policy exists.
3. Apply the selected staging setup path only after review; do not combine the full marketplace migration with the alternative image-only table/RPC path.
4. Create/verify the private image bucket in the Staging dashboard and apply the Storage policies separately as documented.
5. Run verification queries and check function signatures, owners, `SECURITY DEFINER`, empty search paths, EXECUTE ACLs, table grants, RLS and indexes.
6. Use two disposable test accounts for borrow, sale, donation, image ownership, handover privacy, duplicate/concurrent requests, unauthorized actions and terminal listing behavior.
7. Only after tests pass, deliberately enable the required local staging flags and restart the backend. Keep the local production process and production project untouched.

## O. Known limitations

- Resource, request and report reads are limited to 100; filters are primarily client-side. Dashboard totals describe returned records, not database-wide aggregates.
- No live price snapshot for paid borrow terms, and no verified profile display-name contract for other users.
- Browser's generic backend-unavailable message cannot be tied to a specific API base/fetch failure without inspecting the prohibited local config or browser request details.
- Current server is stale relative to source; a current binary was built separately but cannot replace the locked running process without the user's manual restart.
- Sale/donation completion with inherited resource images needs a transfer cleanup design.
- No operational moderator provisioning workflow or staging permission confirmation.

## P. Exact next action

First review and manually apply the staging setup only after reading the migration guide and verifying the actual Storage policy inventory. Then, when ready to replace the local process, stop/restart PID 32268 yourself and launch a current Release build from the `BACKEND` working directory. Keep all flags false until the two-account Staging tests pass. Do not paste keys or tokens into chat.

## Git state

Branch is `main`. The **24 pre-existing staged generated-file deletions are unchanged**. All unstaged and untracked work was preserved. No stage/unstage/reset/clean/commit/push operation was performed.
