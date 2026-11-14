# CampusShare

CampusShare is a student resource-sharing MVP with a static HTML/CSS/JavaScript frontend and a C++17 Crow backend. Supabase Auth supplies the browser session; the backend validates each protected request with Supabase Auth, forwards the user's bearer token to PostgREST, and relies on the project's Row Level Security policies.

## Current capabilities

- Email/password registration, login, logout, session restoration, and token refresh through the official Supabase JavaScript v2 client.
- Authenticated category/resource reads; resource detail, create, owner edit, and owner delete.
- Search and category filtering over the resources returned by the API.
- RLS-filtered borrower/owner request reads. Creation is disabled by default until the secure staging RPC is verified and explicitly enabled; no direct-write fallback is used.
- No service-role key, database schema change, or RLS bypass.
- Owner approve/reject/return routes and frontend actions are implemented behind `SUPABASE_RPC_BORROW_STATUS=false`. Status mode also requires atomic resource RPC mode, and staging must remove authenticated direct UPDATE of `resources.availability_status` before enabling it. The verified database has no `authenticated` UPDATE grant or UPDATE policy for `borrow_requests`.

The complete endpoint contract, schema facts, known RLS grants, and limitations are in [BACKEND/README.md](BACKEND/README.md) and [BACKEND/SUPABASE_SCHEMA_REQUIREMENTS.md](BACKEND/SUPABASE_SCHEMA_REQUIREMENTS.md).

## Local setup (Windows)

Requirements: Visual Studio C++ Build Tools with MSVC, CMake 3.20+, Git, vcpkg with libcurl installed, Python 3, and Node.js 18+.

Initialize the checked-in dependencies once:

```powershell
git submodule update --init --recursive
```

Configure and build from `BACKEND` (replace the vcpkg path with the local installation):

```powershell
cd BACKEND
cmake -S . -B build-local -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake" -DCMAKE_BUILD_TYPE=Release
cmake --build build-local --config Release
```

Set backend configuration in the process environment or copy `BACKEND/.env.example` to the ignored `BACKEND/.env` file. Required names are `SUPABASE_URL` and `SUPABASE_ANON_KEY`; the latter must be a publishable or legacy anon key. Never use or publish a `service_role`/secret key. Optional names are `SERVER_HOST`, `SERVER_PORT`, and `CORS_ALLOWED_ORIGINS`. The default bind address is loopback. Use HTTPS for non-local Supabase URLs and an exact allowed origin for the frontend.

Set `supabaseUrl`, `supabasePublishableKey`, and if needed `apiBase` in `FRONTEND/config.js`. The URL and publishable key are intentionally browser-visible; no secret key belongs there. Serve the frontend from its directory:

```powershell
cd FRONTEND
python -m http.server 5500
```

Open `http://localhost:5500`. Configure the Supabase Auth site and redirect URLs for this local origin if the project requires email confirmation. Use a designated test account; registration creates a real Auth user. The static page downloads the pinned Supabase JS v2 UMD bundle from jsDelivr, so browser access to that CDN is required.

## API overview

`GET /api/health` and `GET /api/test` are public diagnostics. All category, resource, and borrowing-request data routes require `Authorization: Bearer <Supabase access token>`. Current routes:

Each list route currently returns at most 100 rows; there is no pagination yet. Search/category filters therefore cover only the returned resource page.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/categories` | Read categories |
| GET | `/api/resources` | List resources |
| GET | `/api/resources/{id}` | Read a resource |
| POST | `/api/resources` | Create a resource for the verified caller |
| PATCH | `/api/resources/{id}` | Update an owned resource |
| DELETE | `/api/resources/{id}` | Delete an owned resource |
| GET | `/api/borrow-requests` | Read rows allowed by borrower/owner RLS |
| POST | `/api/borrow-requests` | Create a request for the verified borrower |
| POST | `/api/borrow-requests/{id}/approve` | Owner-only RPC action; returns 503 while `SUPABASE_RPC_BORROW_STATUS=false` |
| POST | `/api/borrow-requests/{id}/reject` | Owner-only RPC action; returns 503 while `SUPABASE_RPC_BORROW_STATUS=false` |
| POST | `/api/borrow-requests/{id}/return` | Owner-only RPC action; returns 503 while `SUPABASE_RPC_BORROW_STATUS=false` |
| OPTIONS | `/api/*` | Preflight for configured CORS origins |

Mutation payloads must be JSON objects no larger than 16 KiB. Use the full API table and examples in [BACKEND/README.md](BACKEND/README.md). Resource deletion behavior with related requests depends on the live foreign-key action; the backend does not delete or rewrite borrowing records. Status routes have a local contract but are not staging-verified. See [the RPC rollout guide](CAMPUSSHARE_RPC_DEPLOYMENT_GUIDE.md) and the separate staging migration, availability permission cutover, validation, and rollback SQL files. No live SQL was executed.

## Tests

Build the backend as above, then from `BACKEND` run (adjust the executable path to the chosen CMake generator):

```powershell
python tests/test_api.py build-local/campusshare_backend.exe
```

From `FRONTEND` run:

```powershell
node --check app.js
node --check api.js
node --check auth.js
node --check ui-model.js
node --test tests/*.test.cjs
```

These automated API tests use a local mock of Supabase Auth and PostgREST; frontend tests mock Auth and fetch. They do not prove live Auth settings, database grants, RLS, profile provisioning, or resource deletion behavior.

## Deployment readiness checklist

- [ ] Provide and review the schema-only DDL/migrations for all required columns/defaults, foreign-key delete behavior, unique constraints, and grants.
- [x] Read-only schema inspection confirmed an `auth.users` insert trigger provisions `profiles` from Auth ID, email, and `full_name` metadata; the registration form now sends `full_name`. Live trigger execution remains untested.
- [ ] Configure backend secrets in the deployment secret store; use only a publishable/anon key alongside the caller's bearer token.
- [ ] Bind behind a TLS reverse proxy, set a production `SERVER_HOST`/port, exact `CORS_ALLOWED_ORIGINS`, proxy body limits, and request timeouts. Do not expose the development HTTP server directly.
- [ ] Configure Supabase Auth site/redirect URLs, email confirmation behavior, and a safe test account.
- [ ] Run live tests for allowed and denied reads/writes with borrower, owner, and unrelated users in a non-production test environment. No controlled test email accounts were supplied for this run.
- [ ] Decide whether concurrent requests may queue. The current duplicate precheck is caller-scoped and non-atomic; database uniqueness/transaction behavior is not verified.
- [ ] Keep status changes disabled until the project owner approves transition actors, transition rules, an UPDATE grant/RLS design, and database enforcement. No production database change is included.

No live database was modified as part of this work. Do not paste access tokens, passwords, database URLs, or secret keys into issues or chat.
