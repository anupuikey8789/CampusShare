# CampusShare Task 8 — Backend startup diagnosis

## Root cause

The executable named in the report, `BACKEND/campusshare.exe`, is an old ignored binary dated 2026-10-28. It is not the current CMake target. I reproduced its immediate silent exit with Supabase environment variables explicitly blank: Windows returned exit code `-1073741701` (`0xC000007B`, invalid image format), with zero stdout and stderr bytes. That is a Windows loader/binary compatibility failure, before the current C++ configuration diagnostics can run.

The current CMake Release target is `BACKEND/build-msvc/campusshare_backend.exe`. File metadata after the final rebuild shows the old binary at 2026-10-28 11:06:32 UTC and the CMake output at 2026-11-12 02:59:59 UTC, so the CMake output is newer. `BACKEND/campusshare.exe` is ignored by `BACKEND/.gitignore` and also appears among the existing staged generated-file deletions. It was not overwritten, staged, unstaged, removed, or otherwise changed.

In the current source, missing `SUPABASE_URL` or `SUPABASE_ANON_KEY` already prints a clear error and returns exit code 1. `.env` is read relative to the process working directory, so the backend should be launched from `BACKEND`. The existing local `.env` file was present during this task; its contents were not displayed, copied, or recorded. Environment variables override values loaded from that file.

## Changes made

- `BACKEND/main.cpp`: Crow now runs asynchronously while main waits for readiness. Since Crow's wait notification may occur before binding finishes, startup also checks Crow's bound-state flag. The “listening” message is printed only after the socket is bound. A five-second readiness timeout or bind failure returns a nonzero exit and reports the bind address/port; startup/runtime exceptions produce a concise diagnostic. No credentials or request data are logged by these new messages.
- `FRONTEND/tests/auth.test.cjs`: adjusted the configuration-shape assertion to work with the user's locally configured frontend values without asserting or printing those values.
- `CAMPUSSHARE_TASK_8_REPORT.md`: this report.

Both RPC feature flags were explicitly set to false for the local server verification. They remain false by default. No Supabase project was connected to, no SQL was executed, and no database/API operation that contacts Supabase was run.

## Build and tests

- **MSVC/CMake Release build:** passed; compiled `main.cpp` and linked `campusshare_backend.exe` under `BACKEND/build-msvc`.
- **Missing-configuration check:** passed. With the three Supabase key/URL environment variables set to empty for this check (so `.env` was not used), the current executable exited with code 1 and emitted the expected missing-configuration diagnostic. Values were not printed.
- **Occupied-port check:** passed. With a local test listener holding port 18080, the backend exited with code 1 and emitted the bind-readiness diagnostic.
- **Backend mock API suite:** passed using `BACKEND/build-msvc/campusshare_backend.exe`. It covers configuration/service-key rejection, mocked Auth, request/RPC behavior, validation, upstream failures, timeouts, and CORS.
- **Actual local server check:** passed. Started the current CMake executable from `BACKEND`, observed the exact readiness line for `127.0.0.1:18080`, confirmed `Test-NetConnection` succeeded, and called only local `GET /api/health` and `GET /api/test`. Health returned `ok`; both RPC flags were false. The test route returned `success` / `Crow routes are working`. I stopped only the process started for this check.
- After cleanup, confirmed no process was listening on port 18080.
- **Frontend syntax checks:** passed for `config.js`, `auth.js`, `api.js`, and `app.js`.
- **Frontend mock tests:** **13 passed, 0 failed**.
- No live Supabase Auth, PostgREST, RLS, or database behavior was tested.

## Exact launch command

From PowerShell:

```powershell
cd C:\Users\Anup Uikey\CampusShare\BACKEND
.\build-msvc\campusshare_backend.exe
```

Do not launch `BACKEND\campusshare.exe`; that is the stale binary that produced the Windows loader error. The correct path is `BACKEND\build-msvc\campusshare_backend.exe`.

## Git state and safety

Branch remains `main` tracking `origin/main`. All 24 pre-existing staged generated-file deletions remain staged and unchanged. No staging, unstaging, reset, clean, commit, or push occurred. No Supabase configuration or database was changed.

---

# CampusShare Task 8 — Secure borrowing workflow and RPC readiness

## Implemented locally

The C++ backend now exposes authenticated, opt-in owner actions:

- `POST /api/borrow-requests/{id}/approve` with `{}` or `{"due_at":null|string}`.
- `POST /api/borrow-requests/{id}/reject` with `{}`.
- `POST /api/borrow-requests/{id}/return` with `{}`.

Each route verifies the Supabase access token, forwards the user's JWT separately from the configured public API key, rejects malformed IDs and unexpected fields, expects exactly one row in a JSON array, and sanitizes upstream errors. `SUPABASE_RPC_BORROW_STATUS` defaults to `false`; with the flag off, each action responds with 503 and does not call PostgREST. Startup also rejects status mode unless `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true`. There is no direct `borrow_requests` UPDATE fallback. The borrow-request read projection now includes `id` for action links.

The frontend API helper calls those routes. The owner request cards show Approve/Reject for pending requests and Confirm return for approved requests only when `/api/health` reports the status flag enabled. UI visibility is convenience only; the proposed SQL function must enforce ownership and transitions. All three RPC flags remain false by default in source and `.env.example`.

The staging-only SQL migration proposes five functions: `create_borrow_request`, `approve_borrow_request`, `reject_borrow_request`, `return_borrowed_resource`, and `update_resource_atomic`. The status functions return `SETOF public.borrow_requests`; this return contract is new and not confirmed as deployed. The migration does not change table grants or RLS policies. It revokes function EXECUTE from PUBLIC/anon/authenticated/service_role before granting authenticated-only execution, uses SECURITY DEFINER with an empty search path, derives identity from `auth.uid()`, and rejects missing/anonymous identity claims. The function owner and bypass-RLS implications require review.

The proposal locks the resource before the borrowing request for operations touching both tables. Approval requires an owner, pending request, and available resource; it atomically approves and marks the resource unavailable. Rejection is owner-only and pending-only. Return is owner-only for an approved unavailable loan, sets `returned_at` on the database side, then marks the resource available. Request creation uses the database timestamp, prevents self-borrow/unavailable-resource requests, and checks active duplicates. The existing partial index prevents two approved requests for one resource; the proposed borrower/resource unique index prevents duplicate active requests by the same borrower. Multiple different borrowers may have pending requests in the queue; confirm that behavior as a staging product rule.

Added a staging deployment guide, rollback proposal, and read-only validation queries. The validation queries expose metadata and aggregate invariant counts, not request rows, emails, tokens, or keys. None of these SQL files was run.

Review also found that the existing staging resource grant includes direct authenticated UPDATE on `availability_status`. That can bypass the RPC lock even if the app uses the C++ backend. Added a separate staging cutover proposal to revoke that single column privilege after `update_resource_atomic` is installed and validated. The backend now rejects status-RPC mode unless atomic-resource-RPC mode is also enabled. The direct grant cutover is still required because users can call PostgREST outside the app.

## Files changed for this task

- `BACKEND/main.cpp`
- `BACKEND/tests/test_api.py`
- `BACKEND/.env.example`
- `BACKEND/README.md`
- `FRONTEND/api.js`
- `FRONTEND/app.js`
- `FRONTEND/tests/auth.test.cjs`
- `README.md`
- `CAMPUSSHARE_LOCAL_SETUP_GUIDE.md`
- `SUPABASE_RPC_API_CONTRACTS.md`
- `SUPABASE_RPC_BACKEND_INTEGRATION.md`
- `SUPABASE_STAGING_BORROWING_RPC_MIGRATION.sql`
- `SUPABASE_STAGING_BORROWING_RPC_ROLLBACK.sql`
- `SUPABASE_STAGING_BORROWING_RPC_VALIDATION.sql`
- `SUPABASE_STAGING_BORROWING_AVAILABILITY_CUTOVER.sql`
- `CAMPUSSHARE_RPC_DEPLOYMENT_GUIDE.md`
- `CAMPUSSHARE_TASK_8_REPORT.md`

## Local verification

- **Existing Release build directory:** compiling `main.cpp` succeeded, but linking failed with `LNK1104: cannot open file 'campusshare_backend.exe'`. The existing executable was not overwritten. The cause of that file-open failure is not established.
- **Isolated temporary MSVC/CMake Release build:** passed; the updated backend source compiled and linked in the OS temporary directory, leaving the existing executable untouched.
- **Backend HTTP mock suite:** passed using the temporary executable. Coverage includes missing/invalid auth, default-off status routes, owner versus non-owner RPC forwarding, identity/API-key separation, invalid IDs/payloads/dates, sanitized permission/state errors, malformed RPC output, timeout, no direct-write fallback, resource and create-request RPC behavior, and CORS. These mocks do not execute SQL or validate database authorization.
- **Frontend syntax checks:** passed for `app.js`, `api.js`, and `auth.js`.
- **Frontend mock tests:** 13 passed, 0 failed, including the three status methods and their request bodies.
- **Python test syntax:** passed using an in-memory AST parse.
- **Static SQL contract cross-check and credential-pattern scan:** passed for names, default-off/dependency gates, function ACL statements, SECURITY DEFINER/search-path declarations, transaction wrappers, availability-column cutover, read-only validation statements, and absence of credential-shaped values or project URLs in the reviewed deliverables.
- No PostgreSQL client/server or Docker executable was available for parser or isolated transaction checks. Static checks do not establish PostgreSQL syntax or runtime behavior.

## Not verified and next staging gate

No Supabase project was accessed and no SQL was executed. Staging function ownership, JWT `is_anonymous` claims, effective EXECUTE privileges, RLS interaction, actual return shapes, two-user authorization, duplicate handling, resource/status consistency, and races remain unverified. The status UI must remain disabled until the owner reviews the full migration, a human applies it to the staging project, the read-only validation output matches, and separate-account plus concurrent-action tests pass. Do not enable any of the three RPC flags in production.

The local Git commands identify the repository root and branch `main`, but `git status` and unstaged `git diff --check` fail with “this operation must be run in a work tree.” Read-only `git diff --cached --name-status` still works and shows exactly the same 24 staged `D` entries for generated files noted earlier. No `git add`, `git reset`, `git restore`, commit, or push command was run, so the index was not modified. No commit or push occurred.
