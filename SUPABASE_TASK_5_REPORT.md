# CampusShare Task 5 — Staging Validation and Signup Testing

## Scope and safety

This task used repository files and user-provided screenshot findings only. No Supabase project was connected, no SQL was executed, and no database, Auth setting, production configuration, or RPC feature flag was changed. No code behavior was modified. No files were staged or unstaged, and there was no commit or push.

The user-provided screenshot confirms the staging trigger metadata: `on_auth_user_created`, AFTER INSERT on `auth.users`, enabled, calls `public.handle_new_user()`, owner `postgres`, `SECURITY DEFINER`, empty search path, and an EXECUTE ACL that appears to contain only `postgres`. This confirms the displayed metadata only; it does not prove a live signup creates a profile.

## What was inspected

- Existing staging schema, grant, policy, trigger, and read-only validation SQL.
- Staging setup guide and Task 4A, 4B, 4C, and 4D reports.
- Database audit and Task 3D status-RPC security/concurrency review.
- `SUPABASE_STATUS_RPC_STAGING_INSPECTION.sql` and status-RPC test plan.
- Frontend project configuration, Auth flow, API helper, root setup guide, and C++ backend routes.

## Files created

1. `SUPABASE_STAGING_SIGNUP_SMOKE_TEST.md` — beginner instructions for a fresh staging test account and a boolean-only check of profile existence, UUID equality, and email equality.
2. `SUPABASE_STAGING_VALIDATION_NEXT.sql` — eight separately labeled read-only SELECT queries for the signup check, effective table privileges, RLS flags, policy expressions, indexes, status RPC metadata/ACLs, full status function definitions, and trigger/function configuration.
3. `SUPABASE_TASK_5_REPORT.md` — this report.

Existing project files were not modified.

## Status RPC safety review: what is and is not known

The checked-in audit records summary findings, but the full current status-RPC definitions/results are not available in the repository or in the screenshots shared so far. Therefore, actual row locks, lock order, and authorization behavior have not been independently inspected.

The local audit summary reports:

- `approve_borrow_request(bigint,timestamptz)` checks the Auth user, resource owner, pending status, non-self borrowing, and resource availability; it locks request/resource rows and sets the request approved and resource unavailable. The exact lock order and full function body are missing.
- `reject_borrow_request(bigint)` checks an authenticated owner and pending status, locks the request, and sets it rejected. The full body and exact authorization/lock details are missing.
- `return_borrowed_resource(bigint)` checks the owner and approved status, locks request/resource rows, and marks the request returned and resource available. The exact lock order and full body are missing.

These are audit-reported summaries, not verification of the definitions currently installed in staging. The user has not supplied the validation query outputs for these functions. Consequently, I cannot confirm from actual definitions that the resource owner is the only permitted actor for all three operations, that the lock order is safe, or that concurrent status changes cannot leave resource availability inconsistent. The reported unique index allowing only one approved request per resource is useful but does not alone prove the whole availability invariant.

`SUPABASE_STAGING_VALIDATION_NEXT.sql` includes separate queries to retrieve each function’s exact signature, owner, `SECURITY DEFINER`, function configuration/search path, ACL/effective EXECUTE access, and full definition. Review those results in staging before enabling status routes or the new create-request RPC. In particular, compare the lock sequence across approval, rejection, return, `update_resource_atomic`, and request creation; do not assume compatible locking from function names or summary text.

## Static checks performed

- Inspected the existing validation SQL’s query categories and confirmed the follow-up is separate, labeled, and uses SELECT statements only.
- Checked the new SQL text for the requested role names, four application tables, policy and RLS catalogs, index definition, status function names/signatures/definitions, function owner/security/configuration/ACL, and trigger configuration fields.
- Reviewed the signup check query to ensure it returns booleans rather than email addresses, UUIDs, or user rows.
- Confirmed the new guide directs the user to configure frontend and backend against the staging project and not production.
- No SQL parser or database execution was used. These checks do not establish SQL parser acceptance or live Supabase behavior.

No backend build or test suite was run: only documentation and read-only SQL files were created, and no backend code changed.

## Checks the user still needs to run manually

1. Confirm the dashboard project is **CampusShare-Staging** (`jxndjuslvccxgayoachm`), and verify frontend and backend configuration both point to it.
2. Follow `SUPABASE_STAGING_SIGNUP_SMOKE_TEST.md` with a fresh test email and run only QUERY 1 in `SUPABASE_STAGING_VALIDATION_NEXT.sql`. The expected booleans are all `true`.
3. Run the remaining labeled validation queries one at a time in the staging SQL Editor. The status function definition query is necessary before anyone can confirm lock order, owner-only authorization, status transitions, or concurrency behavior.
4. Keep `SUPABASE_RPC_CREATE_BORROW_REQUEST` and `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE` disabled. Do not deploy the proposed create-request RPC until the status-RPC definitions and lock ordering have been reviewed.

## Git state

The repository remains on branch `main` tracking `origin/main`. The 24 pre-existing staged generated-file deletions remain staged. Existing user changes were preserved. No staging operation, reset, restore, commit, or push was performed.

## Next action

Use the staging-only frontend to register one fresh test account, then run **QUERY 1** from `SUPABASE_STAGING_VALIDATION_NEXT.sql` with that account’s Auth UUID. Confirm all four results are `true`. Do not share the UUID or email; report only the boolean results.
