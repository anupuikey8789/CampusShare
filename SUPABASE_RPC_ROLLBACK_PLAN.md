# CampusShare Supabase RPC rollback plan

No production changes have been made by this implementation. Rollback steps below are conditional planning; do not execute database changes without approval.

## Application rollback during staging

1. Disable `SUPABASE_RPC_CREATE_BORROW_REQUEST` only if staging still permits the legacy authenticated insert and the team intentionally accepts its duplicate/availability race risks.
2. If direct INSERT has already been revoked, do not flip the flag off: the old path will fail. Restore a compatible RPC-capable backend or obtain approval for a narrowly scoped temporary grant while the service is stopped or protected from duplicate writes.
3. Never let one request attempt both RPC and direct insert. A failed/timeout RPC can have an uncertain outcome; do not automatically retry through PostgREST because the transaction may already have committed. Re-read the request state using the caller's token or surface a retry-safe conflict response.
4. `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE` defaults to `false`. Keep it false until the proposal is approved and staging-verified. If enabled in staging and rollback is required, confirm that legacy authenticated PATCH permission remains valid before disabling the flag and restarting the backend. Do not split metadata and availability into separate writes. If direct PATCH has been revoked, keep the RPC-capable backend and repair the RPC rather than switching to a failing or privileged path.
5. If a status endpoint is introduced later and fails, disable the endpoint/UI together. Do not restore broad `PUBLIC`, `anon`, or service-role access to a definer function.

## Database rollback after a separately approved migration

- Re-run read-only inspection first and identify exactly which statements succeeded. Do not replay a whole script blindly.
- Before restoring direct borrower INSERT or availability UPDATE, confirm the application version, pause mutations if needed, and obtain approval. Restoring direct writes reopens non-atomic paths.
- Retain narrow RPC ACLs and owner/status checks. Never restore `PUBLIC`/`anon` execution or use the service-role key to bypass RLS.
- Do not drop functions, policies, or indexes as an automatic rollback. Remove only newly created objects after verifying they are not in use and their exact names/definitions match the approved migration.
- If a concurrent index build fails, inspect `pg_index.indisvalid`; do not drop an index unless it is confirmed to be the newly created failed index and that cleanup is approved.
- Preserve the existing approved-request unique index and profile trigger. Verify signup/profile creation after any function ACL change.
- Capture sanitized verification results and re-run the read-only audit after rollback.

## Current safe fallback

The local borrow-request RPC flag defaults off, so current direct behavior remains compatible pending staging validation. That path retains known race limitations. Atomic resource edits continue as one PostgREST PATCH. No status mutation route is exposed. Production policy/grant changes remain blocked pending explicit approval and successful two-account staging tests.
