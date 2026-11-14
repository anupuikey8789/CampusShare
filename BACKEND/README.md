# CampusShare backend

This C++17 service uses Crow for HTTP routing and libcurl for Supabase Auth and PostgREST. It exposes health/test, authenticated category/resource CRUD, borrower-owned request routes, and default-off marketplace RPC/storage metadata operations. The static frontend uses Supabase Auth email/password sessions; database authorization remains inside Supabase and proposed RPC functions.

## Requirements (Windows)

- Visual Studio C++ Build Tools (MSVC) or a supported MinGW-w64 toolchain.
- CMake 3.20 or newer.
- Git (including the checked-in Crow and Asio submodules).
- vcpkg for libcurl.
- Python 3 for the local HTTP integration checks.

Install vcpkg once if it is not already available:

```powershell
git clone https://github.com/microsoft/vcpkg C:/dev/vcpkg
C:/dev/vcpkg/bootstrap-vcpkg.bat
```

From the repository root, initialize dependencies if they are not present:

```powershell
git submodule update --init --recursive
```

Install libcurl through vcpkg, then configure/build from `BACKEND`. Replace the example paths with your local tool locations:

```powershell
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake"
cmake --build build --config Release
```

For a Visual Studio generator, the executable is `build/Release/campusshare_backend.exe`; for a single-configuration generator, it is `build/campusshare_backend.exe`.

The bundled `build/` directory was previously generated from a different machine and source tree. Reconfigure in a fresh build directory (for example `build-local`) if CMake reports stale cache paths.

## Configuration

Copy `.env.example` to `.env` in `BACKEND` and fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Environment variables take precedence over `.env`. The legacy `SUPABASE_KEY` variable is accepted as an alias for compatibility.

Only a Supabase publishable/anon key is appropriate in this server. Never put a `service_role` or secret key in `.env`, source control, or a client. `.env` is ignored by Git. The server validates that the URL uses HTTPS; HTTP is accepted only for localhost URLs. It listens on `127.0.0.1:18080` by default. Set `SERVER_HOST`/`SERVER_PORT` to override it.

`CORS_ALLOWED_ORIGINS` is a comma-separated list of exact origins. The default permits common local development origins on ports 5500 and 5501. Set an explicit production origin before deployment; do not use `*`.

`SUPABASE_RPC_CREATE_BORROW_REQUEST`, `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE`, and `SUPABASE_RPC_BORROW_STATUS` default to `false`. Borrow-request creation and status changes fail closed with HTTP 503 while their flags are false; these operations have no direct-write fallback. The public health response reports configured flag values so the frontend can hide unavailable actions. A true flag is not proof that the matching RPC exists or is secure. Staging function bodies, grants, and transaction behavior remain unverified. Status mode also requires atomic resource-update mode; startup rejects a status-only configuration. Before enabling status actions, the owner must remove the authenticated direct UPDATE privilege on `resources.availability_status`, or callers could bypass the RPC lock. No live Supabase tests have been run.

`SUPABASE_MARKETPLACE_ENABLED` defaults to `false`. It gates extended resource columns, sale/donation request operations, handover details, and listing reports. With the marketplace flag on, resource PATCH uses `update_marketplace_resource_atomic`; it never falls back to direct PostgREST PATCH. Borrow-request creation and borrowing approve/reject/return remain controlled by their separate RPC flags.

`SUPABASE_RESOURCE_IMAGES_ENABLED` defaults to `false` and independently gates only image metadata routes. It does not enable marketplace fields or sale/donation/handover/report routes. Enable it only after the staging `resource_images` table, grants/RLS, private `campusshare-resource-images` bucket, and Storage policies have been reviewed and tested. The `/api/health` response reports `features.resource_images_enabled`; the frontend uses this value to enable upload, saved-image management, and gallery reads. A true flag does not create the table or bucket, and no live Storage test has been performed.

## Frontend Auth setup

Edit `FRONTEND/config.js` locally and set `supabaseUrl` plus `supabasePublishableKey` from the Supabase project's API settings. These are browser-visible settings; use only the publishable key (or legacy anon key). Never place a service-role or secret key in frontend configuration. Set `apiBase` if the C++ backend is not at `http://127.0.0.1:18080`.

The page loads the official Supabase JavaScript v2 UMD client from a version-pinned CDN script. Its browser Auth client handles email/password registration and login, persists/restores the session, refreshes tokens, and signs out. Registration may require email confirmation depending on the project's existing Auth settings. The app does not create a second session store. `FRONTEND/auth.js` connects the current session's access token to `CampusShareApi`; the helper sends it as `Authorization: Bearer <token>`. The backend validates it with Supabase Auth and forwards it separately from the publishable API key to PostgREST, leaving RLS enabled.

For local development, configure the backend first as described above, then serve the frontend from its directory so the origin matches the backend's CORS allowlist:

```powershell
cd FRONTEND
python -m http.server 5500
```

Open `http://localhost:5500`. If your Supabase Auth settings require email confirmation, configure the project's site URL and allowed redirect URLs for the local frontend origin. Do not change database policies or grants to make sign-in work. The frontend includes borrow/lend, sale and donation forms; image upload, previews and removal; private campus handover details; and listing reports. These marketplace screens stay hidden unless the backend health response reports the marketplace flag enabled. Borrow approve/reject/return actions remain separately controlled by the borrowing-status and atomic-update flags.

## API

Successful reads and creates return JSON (list routes return arrays); resource deletion returns HTTP 204 with no body.

List routes currently cap each upstream read at 100 rows and expose no pagination parameters. The frontend search/category filters operate only on the rows received, so they are not complete beyond that cap. Add cursor/range pagination before the project expects more than 100 rows.

| Method | Path | Authentication | Behavior |
| --- | --- | --- | --- |
| GET | `/api/health` | Public | Returns status/service and RPC feature booleans. Does not check Supabase connectivity or prove that an RPC is installed. |
| GET | `/api/test` | Public | Compatibility endpoint returning a JSON status/message object. |
| GET | `/api/categories` | Verified Supabase access token | Reads at most 100 rows with `id,name,created_at`; relies on project grants/RLS. |
| GET | `/api/resources` | Verified Supabase access token | Lists up to 100 rows using confirmed resource columns. |
| GET | `/api/resources/{id}` | Verified Supabase access token | Returns a matching visible row in a one-element array, or 404. |
| POST | `/api/resources` | Verified Supabase access token | Creates a resource; derives `owner_id`; availability is restricted to `available`/`unavailable`. |
| PATCH | `/api/resources/{id}` | Verified Supabase access token | Partially updates allowed resource fields; owner identity and creation fields cannot be changed. Relies on confirmed owner UPDATE RLS. |
| DELETE | `/api/resources/{id}` | Verified Supabase access token | Deletes through PostgREST and relies on owner RLS. If a borrowing-request FK restricts deletion, the endpoint returns a generic 409; FK delete behavior is unverified. |
| GET | `/api/borrow-requests` | Verified Supabase access token | Lets the confirmed borrower-read and resource-owner-read policies filter the rows; the client cannot choose an identity filter. |
| POST | `/api/borrow-requests` | Verified Supabase access token | Returns `503` with `borrow_requests_pending` while the flag is false. With `SUPABASE_RPC_CREATE_BORROW_REQUEST=true`, sends only `p_resource_id` and `p_due_at` to the proposed RPC. There is no direct-write fallback. Enable only after the deployed function, signature, return type, grants, and staging behavior are verified. |
| POST | `/api/borrow-requests/{id}/approve` | Verified Supabase access token | Returns `503` while `SUPABASE_RPC_BORROW_STATUS=false`. When enabled, calls only `approve_borrow_request`; accepts `{}` or `{"due_at":null|string}` and returns one row array with HTTP 200. Proposed RPC only; not staging-verified. |
| POST | `/api/borrow-requests/{id}/reject` | Verified Supabase access token | Returns `503` while disabled. When enabled, calls only `reject_borrow_request`; accepts `{}` and returns one row array with HTTP 200. Proposed RPC only; not staging-verified. |
| POST | `/api/borrow-requests/{id}/return` | Verified Supabase access token | Returns `503` while disabled. When enabled, calls only `return_borrowed_resource`; accepts `{}` and returns one row array with HTTP 200. Proposed RPC only; not staging-verified. |
| OPTIONS | `/api/*` | Public | CORS preflight allows GET, POST, PUT, PATCH, DELETE, and OPTIONS for configured origins. |

Marketplace routes below return `503 marketplace_disabled` unless `SUPABASE_MARKETPLACE_ENABLED=true`. Image metadata routes are separate and return `503 resource_images_disabled` unless `SUPABASE_RESOURCE_IMAGES_ENABLED=true`. They use the verified user's Bearer token for PostgREST/RPC calls; Storage bytes use the existing Supabase JS client and the user's session. None have been live-tested against the staging project.

| Method | Path | Behavior |
| --- | --- | --- |
| PATCH | `/api/resources/{id}` | Uses `update_marketplace_resource_atomic` in marketplace mode; owner and field checks are enforced by the RPC and RLS. |
| GET | `/api/marketplace/transfer-requests` | Returns rows visible to the current requester/owner under RLS. |
| POST | `/api/resources/{id}/transfer-requests` | Accepts `{"request_type":"sell"}` or `{"request_type":"donate"}`; invokes identity-derived request RPC. |
| POST | `/api/marketplace/transfer-requests/{id}/approve` | Owner approval via RPC; donation completes permanent transfer, sale reserves the listing. |
| POST | `/api/marketplace/transfer-requests/{id}/reject` | Owner rejection via RPC. |
| POST | `/api/marketplace/transfer-requests/{id}/complete-sale` | Owner confirms off-platform sale completion via RPC. No payment processing occurs. |
| GET/POST | `/api/resources/{id}/images` | Reads or saves metadata for image objects uploaded through the private Supabase Storage API. The authenticated user JWT is forwarded; RLS remains authoritative. |
| DELETE | `/api/resource-images/{id}` | Looks up owner-visible metadata, deletes the private Storage object with the same user JWT, then removes metadata. If either step is denied or fails, the backend returns an error and does not bypass RLS. |
| GET/PUT | `/api/resources/{id}/handover` | Reads or upserts private campus pickup details; row visibility is expected to be limited by RLS to involved students. |
| POST | `/api/resources/{id}/reports` | Inserts a pending listing report with `reporter_id` derived by the backend. |
| GET | `/api/marketplace/reports` | Returns only reports visible to the current user; there is no moderator action route. |

The marketplace table names, added resource columns, and RPC contracts come from the unexecuted staging proposal, not verified live schema. Reports are submitted for human review; the application does not automatically suspend accounts. A verified moderator role and RLS/grant contract are still missing.

Example authenticated create-resource request (the backend supplies `owner_id`):

```http
POST /api/resources HTTP/1.1
Authorization: Bearer <current-supabase-access-token>
Content-Type: application/json

{"title":"Data Structures Notes","description":"Printed study notes","category_id":"<existing-category-id>","resource_type":"book","availability_status":"available"}
```

Successful creates return `201` and a one-element JSON array containing the selected resource columns, for example:

```json
[{"id":"<resource-id>","title":"Data Structures Notes","description":"Printed study notes","category_id":"<category-id>","owner_id":"<authenticated-user-id>","resource_type":"book","availability_status":"available","created_at":"<database-timestamp>"}]
```

Example borrowing-request request (the backend supplies `borrower_id`, `requested_at`, `returned_at`, and `status`):

```http
POST /api/borrow-requests HTTP/1.1
Authorization: Bearer <current-supabase-access-token>
Content-Type: application/json

{"resource_id":"<existing-available-resource-id>","due_at":null}
```

Successful RPC-backed request creation returns `201` with a one-element JSON array. The database RPC must set `status` to `pending`; a caller cannot set status or identity fields. While RPC mode is disabled, the route returns `503` and performs no resource/request PostgREST reads or writes. Errors have the form `{"error":{"code":"...","message":"..."}}`. A permission denial is a generic 403, invalid data is 422, conflicting constraints are 409, and an upstream/auth transport failure is reported without returning Supabase's response body.

There is deliberately no direct PATCH/DELETE route for borrowing requests. The three status POST routes are RPC-only and disabled by default because the staging RPC package is not verified. The current production database has no authenticated UPDATE grant/policy, and status values do not authorize a transition. Keep `SUPABASE_RPC_BORROW_STATUS=false` until the staging definitions, ACLs, and two-user/concurrency tests have been reviewed.

Protected requests validate the bearer token with Supabase Auth `GET /auth/v1/user`, then forward that token and the publishable/anon API key to PostgREST so RLS remains active. No service-role key is supported. Errors use `{"error":{"code":"...","message":"..."}}`; upstream details and credentials are not returned or logged. Transport/server failures map to 502 and authorization/constraint failures to generic 4xx responses.

Mutation JSON bodies are limited to 16 KiB and must be JSON objects. A title containing only whitespace is rejected. Crow buffers request bodies before route handlers run; this endpoint check limits JSON processing and upstream writes, but does not cap pre-handler memory use. Configure the production reverse proxy/load balancer with a request-body limit (at most 16 KiB for these routes) and request timeouts. Do not expose this development server directly to untrusted networks.

### Borrowing status API (implemented behind a default-off flag)

The status routes call only proposed RPC functions; the false default flag returns HTTP 503 before any RPC call. No direct request-table update is implemented. The verified `authenticated` role has neither an UPDATE grant nor an UPDATE RLS policy on `borrow_requests`, and the status values do not authorize a change.

The complete staging-only contract, exact manual rollout order, test cases, and rollback precautions are documented in [`../CAMPUSSHARE_RPC_DEPLOYMENT_GUIDE.md`](../CAMPUSSHARE_RPC_DEPLOYMENT_GUIDE.md) and [`../SUPABASE_RPC_API_CONTRACTS.md`](../SUPABASE_RPC_API_CONTRACTS.md). The required availability permission cutover proposal is [`../SUPABASE_STAGING_BORROWING_AVAILABILITY_CUTOVER.sql`](../SUPABASE_STAGING_BORROWING_AVAILABILITY_CUTOVER.sql). These proposals are unexecuted. Do not enable status actions until staging validation, the permission cutover, and two-account/concurrency tests pass.

## Confirmed schema links and current limits

The repository contains no SQL migrations or complete schema export. The project owner supplied these foreign keys from a read-only schema query:

- `resources.category_id` → `categories.id` (`resources_category_id_fkey`)
- `resources.owner_id` → `profiles.id` (`resources_owner_id_fkey`)
- `borrow_requests.borrower_id` → `profiles.id` (`borrow_requests_borrower_id_fkey`)
- `borrow_requests.resource_id` → `resources.id` (`borrow_requests_resource_id_fkey`)

`profiles.id` is confirmed as a primary key referencing `auth.users(id)` with `ON DELETE CASCADE`. Read-only metadata confirms column definitions, defaults, grants, RLS enabled/not forced, and the Auth-user profile trigger; details are in [`SUPABASE_SCHEMA_REQUIREMENTS.md`](SUPABASE_SCHEMA_REQUIREMENTS.md). `authenticated` has an owner-scoped resource UPDATE grant/policy. For `borrow_requests`, it has no UPDATE grant or UPDATE policy; no status-changing operation is exposed. Live Auth trigger execution and Data API/RLS operations remain untested.

The frontend connects `CampusShareApi.setAccessTokenProvider` to the Supabase Auth session accessor and stores no separate token. Resource writes rely on the verified owner policies. Request submission prechecks current resource availability and the caller's own active request using that caller's token; these checks are not atomic across concurrent users. The profile trigger needs a live signup test; local frontend/backend configuration is currently absent. Security metadata was queried read-only; live Auth or Data API behavior must still be tested against a configured project.

### Latest live readiness check (2026-11-01)

Supabase MCP read-only access succeeded for the active project named `CampusShare`, ref `dkyfkdmlkghucyepxbbh`. It returned schema metadata (not application row contents): five categories and zero profiles, resources, and borrowing requests at inspection time. A separate read-only lookup for the previously mentioned ref `kieihfixgbfiormlqhmi` returned a permission error; the connector's project list contains only the `dkyfkdmlkghucyepxbbh` CampusShare project. Confirm the intended target before creating test users or data. The metadata confirmed the `auth.users` AFTER INSERT profile trigger, required `profiles.full_name`/`email`, and that the trigger reads `full_name` from Auth user metadata and email/id from the Auth user. The frontend registration form now supplies `full_name`. This trigger has not been exercised by a live signup.

The same metadata confirms RLS enabled and not forced on the four public tables; `authenticated` has no borrowing-request UPDATE grant and there is no UPDATE policy. The partial unique index `one_active_approval_per_resource` prevents more than one `approved` request for a resource, but does not close the concurrent pending-request or per-borrower duplicate race. Resource deletion is constrained by the `borrow_requests.resource_id` foreign key with `NO ACTION`; the backend will surface a generic 409 when references block deletion. No live RLS/API request or Auth sign-in was run. `FRONTEND/config.js` remains blank, `BACKEND/.env` is absent, and no Supabase environment variables were set, so the app is not currently configured to run against the project.

### Latest QA results (2026-11-01)

- **Live read-only metadata:** passed for `dkyfkdmlkghucyepxbbh`; no table records were read. Lookup of `kieihfixgbfiormlqhmi` was denied by the connector.
- **MSVC/CMake Release build:** passed; the existing Ninja build reported `no work to do` and returned exit code 0.
- **Backend mock HTTP suite:** passed for auth/config, CRUD/request routes, ownership, validation, upstream failures, and CORS. It uses local mock Auth/PostgREST and is not live RLS testing.
- **Frontend syntax checks:** passed for `app.js`, `api.js`, `auth.js`, and `config.js`.
- **Frontend Auth/API tests:** 10 passed, 0 failed, including the signup `full_name` metadata payload. These tests mock Supabase and backend responses.
- **HTML ID structure and `git diff --check`:** passed (the diff check may report the repository's existing CRLF conversion warnings).
- **Live signup, confirmation, login/logout, session restore/expiry, resource CRUD, RLS isolation, borrowing visibility/conflicts, and FK delete behavior:** not run. Local config is blank, and no controlled test inbox/account was supplied.

See [`SUPABASE_SCHEMA_REQUIREMENTS.md`](SUPABASE_SCHEMA_REQUIREMENTS.md) for the schema-only export checklist and [`AUTHENTICATION.md`](AUTHENTICATION.md) for the proposed token and authorization contract. These documents describe what is needed; they do not claim that the project schema or authentication settings have been inspected or implemented.

## Running and stopping

Run the executable from the `BACKEND` directory so it can read `.env`. Use Ctrl+C to stop the Crow server. The server emits a startup line and minimal framework warnings; it does not log request headers, bodies or secrets.

## Verification

After building, start the server from `BACKEND` with valid local configuration. For local route tests that do not require Supabase credentials, run the mock-backed integration checks from `BACKEND`:

```powershell
python tests/test_api.py build-msvc/campusshare_backend.exe
```

The script covers missing configuration, secret-key rejection, health/test, mock Auth success/failure, bearer forwarding, categories/resources/borrowing routes, spoofed IDs, availability/date validation, disabled borrowing status transitions, upstream failures, unknown routes, and CORS. It does not access Supabase or prove live JWT/RLS behavior. Replace the executable path with `build/Release/campusshare_backend.exe` for a Visual Studio multi-configuration build.

Run the frontend mock tests from `FRONTEND` with Node.js 18 or newer:

```powershell
node --check app.js
node --check api.js
node --check auth.js
node --check ui-model.js
node --test tests/*.test.cjs
```

These tests mock Supabase Auth and backend responses. They do not prove that the configured project's email settings, credentials, CORS deployment origin, or live database grants/RLS work.
