# CampusShare secure borrowing RPC rollout guide

## Scope and safety

This is a staging-only rollout plan. The SQL in `SUPABASE_STAGING_BORROWING_RPC_MIGRATION.sql`, `SUPABASE_STAGING_BORROWING_RPC_ROLLBACK.sql`, and `SUPABASE_STAGING_BORROWING_RPC_VALIDATION.sql` is a proposal. It has not been executed or validated against PostgreSQL. Do not use these files against production. Do not turn a feature flag on because the backend reports it as enabled; the health response describes configuration only.

The approved product rule for this proposal is that only a resource owner may approve, reject, or confirm return. The RPCs derive the actor using `auth.uid()`. The frontend never sends an owner or borrower ID. The backend forwards the user's access token and configured publishable/anon key separately. There is no service-role key and no direct-write fallback for borrowing requests or status changes. Status RPC mode also requires atomic resource-update mode; the backend rejects a status-only configuration.

## Proposed routes and contracts

| Route | Request body | Success |
|---|---|---|
| `POST /api/borrow-requests` | `{"resource_id":123,"due_at":null}` | 201, one pending request in a JSON array; only after the create-request flag is enabled. |
| `POST /api/borrow-requests/{id}/approve` | `{}` or `{"due_at":"2027-01-10T00:00:00Z"}` | 200, one approved request row array. `due_at: null` preserves the request's current due date. |
| `POST /api/borrow-requests/{id}/reject` | `{}` | 200, one rejected request row array. |
| `POST /api/borrow-requests/{id}/return` | `{}` | 200, one returned request row array. The database sets `returned_at`. |

All routes require a valid Supabase access token. The status routes return 503 `borrow_status_pending` and make no RPC call while `SUPABASE_RPC_BORROW_STATUS=false`. Invalid ID/body input is rejected before the RPC. RLS or SQL errors are sanitized. No direct `borrow_requests` UPDATE is provided.

## Staging order

1. Confirm you are in the separate `CampusShare-Staging` project (`jxndjuslvccxgayoachm`), not production. Use disposable test accounts and resources. Do not paste project keys or tokens into chat.
2. Keep all three backend flags false: `SUPABASE_RPC_CREATE_BORROW_REQUEST`, `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE`, and `SUPABASE_RPC_BORROW_STATUS`.
3. Export the staging schema and inspect the read-only results in `SUPABASE_STAGING_BORROWING_RPC_VALIDATION.sql`. Resolve any mismatch with the migration preconditions before proceeding.
4. Have the database owner review the entire migration, especially the SECURITY DEFINER owner and BYPASSRLS behavior, authenticated-only EXECUTE ACLs, exact function bodies, partial unique index, and approval/return state invariants. This migration does not change table grants or RLS policies; it adds five functions and may add the active borrower/resource unique index if it is absent.
5. Arrange a staging backup/export and an agreed recovery window. The SQL uses a transaction and precondition checks, but a unique-index build can wait on table locks. Do not remove duplicates automatically; the migration aborts when active duplicate pairs exist.
6. If approved, a human operator may run `SUPABASE_STAGING_BORROWING_RPC_MIGRATION.sql` manually in the staging SQL Editor. Stop on any preflight error. Codex has not executed SQL.
7. Run each labeled SELECT in `SUPABASE_STAGING_BORROWING_RPC_VALIDATION.sql` separately. Confirm function signatures and definitions, fixed empty search path, owner, `SECURITY DEFINER`, `authenticated` EXECUTE only, no direct `borrow_requests` UPDATE grant/policy, and the exact unique indexes. A SQL Editor success message alone is insufficient.
8. Deploy the backend with all flags false. Apply `SUPABASE_STAGING_BORROWING_AVAILABILITY_CUTOVER.sql` only after its function/grant preconditions and the metadata-only resource update grants are confirmed. It removes authenticated direct UPDATE on `availability_status` while preserving metadata column updates. This is needed because the existing grant would otherwise let a caller bypass the RPC lock and make an approved resource available.
9. Set `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true` in staging, restart the backend, and test owner metadata/availability edits through the existing PATCH route. The route now sends all edits through the atomic RPC. Keep `SUPABASE_RPC_BORROW_STATUS=false` during this check.
10. Test RPCs through the app/backend using normal authenticated user sessions (not SQL Editor calls). Use Student A as owner, Student B as borrower, and Student C as unrelated user. Confirm owner-only transitions, invalid/repeated transitions, no self-borrow, unavailable-resource denial, duplicate handling, and correct status/availability after each action.
11. Test races using separate sessions: competing approvals for different requests on one resource; borrower duplicate submissions; a request racing an availability change; and return racing an edit. Confirm at most one approval and that resource availability matches the approved/returned request. The migration intends to serialize resource-changing operations by locking the resource row first; only staging concurrency tests can establish runtime behavior.
12. Only after review and all tests pass, enable `SUPABASE_RPC_BORROW_STATUS=true`, restart the backend, check `/api/health`, and test UI action visibility and error handling. Enable create, atomic edit, and status actions separately. The status flag is invalid unless atomic resource RPC mode is also true.

## Rollback

First set all enabled RPC flags to false and restart the backend. Verify no requests are being sent to the functions. If restoring direct availability PATCH behavior, review the risk comment in `SUPABASE_STAGING_BORROWING_AVAILABILITY_CUTOVER.sql` and restore the grant only if that is explicitly accepted. Then review `SUPABASE_STAGING_BORROWING_RPC_ROLLBACK.sql` against the staging state. It requires the Task 8 function comment markers and drops only these five marked routines; it removes the active-request index only when this migration created and marked that index. If a marker or precondition differs, stop and perform a manual owner-reviewed rollback. Do not roll back by deleting unrelated functions or changing RLS/grants. The transaction makes rollback all-or-nothing if it completes.

## Local verification already available

From the repository root, build the Windows Release target using the existing configured build directory, then run:

```powershell
cmake --build BACKEND/build-msvc --config Release
python BACKEND/tests/test_api.py BACKEND/build-msvc/campusshare_backend.exe
node --check FRONTEND/app.js
node --check FRONTEND/api.js
node --test FRONTEND/tests/auth.test.cjs
```

These are local/mock checks. They do not establish PostgreSQL syntax validity, staging deployment, JWT claim contents, RLS/grant behavior, or transaction/concurrency correctness. Never put a service-role key in browser configuration or use it to make a test pass.
