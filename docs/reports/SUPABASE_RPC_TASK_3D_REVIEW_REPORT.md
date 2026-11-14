# CampusShare Task 3D — Status RPC Security and Concurrency Review

## Scope and safety

Reviewed the repository's existing audit, correction proposals, RPC documentation, atomic resource-update proposal, and C++ route registrations. No connection to Supabase was made, no SQL was executed, no database grants/policies/schema/data were changed, no feature flag was enabled, and no backend status RPC calls were implemented. The two correction SQL files were left unchanged. No commit or push was made.

## Files inspected

- `SUPABASE_DATABASE_AUDIT.md`
- `SUPABASE_SECURITY_REVIEW.md`
- `SUPABASE_CORRECTION.sql`
- `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql`
- `SUPABASE_READ_ONLY_AUDIT.sql`
- `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql`
- `SUPABASE_RPC_IMPLEMENTATION.md`
- `SUPABASE_RPC_BACKEND_INTEGRATION.md`
- `SUPABASE_RPC_API_CONTRACTS.md`
- `SUPABASE_RPC_MIGRATION_PLAN.md`
- `SUPABASE_RPC_TEST_CASES.md`
- `BACKEND/main.cpp`

## Status function evidence

The following properties are reported by the 2026-11-10 read-only audit snapshot; the repository does not contain the captured full function source or catalog output rows. Treat behavior below as audit-reported, not independently reverified against the current database.

| Function | Signature | Return type | Owner/security/search path and EXECUTE | Audit-reported checks and effects |
|---|---|---|---|---|
| `approve_borrow_request` | `public.approve_borrow_request(bigint,timestamptz)` | Not recorded | Audit reports owner `postgres`, `SECURITY DEFINER`, empty `search_path`; EXECUTE to `PUBLIC`, `anon`, `authenticated`, `service_role` | Checks `auth.uid()`, resource owner, pending status, borrower differs from owner, and resource availability; locks request and resource; sets approved and resource unavailable. Lock order and SQLSTATEs are not recorded. |
| `reject_borrow_request` | `public.reject_borrow_request(bigint)` | Not recorded | Same audit-reported owner/security/search path and four-role EXECUTE access | Checks authenticated owner and pending status; locks request; sets rejected; leaves resource availability unchanged. Exact checks, SQLSTATEs, and lock order are unavailable. |
| `return_borrowed_resource` | `public.return_borrowed_resource(bigint)` | Not recorded | Same audit-reported owner/security/search path and four-role EXECUTE access | Checks owner and approved status; locks request and resource; sets returned/return timestamp and resource available. Audit describes return as owner-confirmed. Lock order and SQLSTATEs are not recorded. |

The audit says each function performs its work as one function invocation, but full routine source and any exception handling are absent. PostgreSQL statement/transaction atomicity is expected for a single RPC invocation unless the function catches errors and commits partial work through some other mechanism; the actual exception behavior cannot be confirmed without source. No explicit transaction-control statements are recorded.

Also inspected:

- Proposed `create_borrow_request(bigint,timestamptz DEFAULT NULL) RETURNS SETOF public.borrow_requests` in `SUPABASE_CORRECTION.sql`: derives borrower from `auth.uid()`, locks the resource before checking owner/availability/active duplicate, then inserts a pending request. This is a local proposal, not a deployed or verified contract. It checks non-null identity but does not check the anonymous Auth JWT claim.
- Proposed `update_resource_atomic(bigint,jsonb) RETURNS SETOF public.resources` in `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql`: locks the owned resource, checks approved requests, and updates supplied values in one function call. It is local proposal code; it has no live contract status.
- `BACKEND/main.cpp` has authenticated create/read request routes and a feature-flagged create-request RPC. It has no approve, reject, return, or borrowing-request status routes. Both RPC flags default to false. No status RPC implementation was added.

## Missing evidence

Before any status API work, obtain current staging results for:

1. Full definitions, argument names/types/defaults, and return types for all three status functions.
2. Actual owner, `prosecdef`, `proconfig`, raw ACL and effective EXECUTE access, including inherited role grants.
3. Whether each function explicitly rejects anonymous Auth JWTs. The `authenticated` database role can include Supabase anonymous Auth users; a non-null `auth.uid()` alone does not prove a permanent student account.
4. Exact `FOR UPDATE` statements and their order across request/resource rows, plus all paths that read or update those rows.
5. Exact state predicates, timestamp assignment/default behavior, SQLSTATEs, exception handling, and whether any multi-row changes happen atomically.
6. Current RLS policy expressions and table/column grants after any staging migration.
7. Current profile trigger attachment, trigger-function owner/security/configuration/ACL and a signup test after any trigger-function ACL change.

The return types and full SQLSTATE contracts are specifically absent from local documentation. They have not been guessed here.

## EXECUTE permission conflict and recommendation

The audit snapshot reports EXECUTE to `PUBLIC`, `anon`, `authenticated`, and `service_role` for all three status routines.

- `SUPABASE_CORRECTION.sql` revokes EXECUTE from all four, including `authenticated`; its later authenticated grants are commented future statements. Applied as written, it disables these status operations for the app.
- `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` revokes `PUBLIC`, `anon`, and `service_role`, then grants EXECUTE to `authenticated` for each exact signature. This retains only the app's authenticated workflow.
- Neither script was changed or executed during Task 3D.

**Recommended policy:** only grant EXECUTE to `authenticated`, and only after confirming each function enforces resource-owner identity and the allowed transition internally. Revoke `PUBLIC`, `anon`, and `service_role`; do not grant table UPDATE as a substitute. Owner A may approve/reject requests for A's resource and confirm return; borrower B and unrelated C must be denied. If the product excludes anonymous sign-ins, each function must also reject an Auth JWT whose `is_anonymous` claim is true (and fail closed if the claim is absent), because role `authenticated` includes anonymous Auth users. Validate effective ACLs, including role membership, in staging. If function bodies do not meet these requirements, do not grant authenticated execution until separately approved function corrections exist.

The audit-reported owner/status checks are encouraging but are insufficient to resolve the missing exact definitions, return actor, anonymous-user behavior, and lock-order questions.

## Concurrency findings

### What the local proposal code shows

- `create_borrow_request` locks the resource before checking availability and pending/approved duplicates. Calls using this function for the same resource serialize on that row. The proposed pending-pair unique index is not evidence that the index exists in the target database.
- `update_resource_atomic` locks the owned resource before checking for an approved request and applying the metadata/availability update.
- The current direct borrow-request route has prechecks followed by a separate write when its RPC flag is false; those separate HTTP calls are race-prone. Current defaults remain false, so this is a present compatibility limitation, not a resolved database invariant.
- The audit reports an existing unique partial index for one approved request per resource. This protects the indexed uniqueness invariant if current and valid; it does not alone establish consistent resource availability or prevent pending duplicates.
- The proposed pending unique index is `(borrower_id, resource_id) WHERE status='pending'`; its application is only in proposal SQL and must be verified before relying on it.

### What remains conditional on unavailable status bodies

The audit summary says approval and return lock request and resource but does not identify their order. If they lock request then resource while another future path locks resource then request, a deadlock is possible. If all paths lock in one global order, that particular cycle can be avoided. The known create/update proposals lock the resource; their duplicate/approved checks are ordinary reads, not explicit request-row locks. This reduces some lock cycles but does not prove compatibility with the actual status routines, indexes, FK checks, or future code.

Potential races that must be resolved in staging:

- Two approval calls for the same pending request must serialize and only one transition may succeed.
- Two different pending requests for the same resource must never both become approved. The partial unique approved index and resource availability check are relevant, but the function must re-check state after obtaining its locks.
- An availability edit to `available` racing with approval or return must never leave an approved request and an available resource. The atomic edit checks approved rows under a resource lock; the status routines must take a compatible lock and update request/resource in one transaction.
- Request creation racing with approval must serialize on the resource if both use the proposed RPC. If creation wins first, a pending request may coexist with an approved request unless the product/database forbids that; if approval wins first, creation should observe unavailable and fail. The intended multiple-pending policy must be explicit.
- Concurrent duplicate creation is guarded by the proposed resource lock only when every caller uses that function. Direct authenticated INSERT can bypass that lock; the proposed pending unique index is needed if one pending pair is a required invariant.
- Rejection versus approval on the same request should serialize on its row; repeated rejection/approval/return should fail without reapplying side effects. Exact predicates are unavailable.

No race or deadlock outcome is asserted as tested. The provided staging plan calls for concurrent sessions and final-state checks.

## New read-only staging inspection script

Created `SUPABASE_STATUS_RPC_STAGING_INSPECTION.sql`. It uses SELECT-only catalog and information-schema queries for function sources/signatures/results/owners/settings/ACLs, effective role access, the Auth trigger and function, RLS policies, and table/column grants. Its header says to run only in a separately verified staging project. It does not contain database mutation statements and was not executed.

## New staging test plan

Created `SUPABASE_STATUS_RPC_STAGING_TEST_PLAN.md`. It covers owner and non-owner authorization, borrower attempts, owner return, repeated transitions, anonymous/unauthenticated calls, concurrent approval/availability/request creation/duplicates, and trigger-based profile creation. It distinguishes the two-account minimum from the third account needed to test competing borrowers for one owner's resource. Every case is unexecuted and includes expected outcomes and evidence handling.

## Recommended next step

Run the new inspection script manually in an isolated staging project and save its catalog output. Review the actual function bodies and ACLs, decide whether anonymous Auth identities are permitted, and verify the resource/request lock order. Only then finalize a single permission proposal and prepare backend status routes with mock tests. Keep RPC flags off; do not alter production.

## Local checks and Git state

Local checks should confirm the new inspection file contains only SELECT statements, documentation files are present and have no trailing whitespace, and `git diff --check` passes. No status RPC or staging test was run.

At Task 3D start, branch was `main` tracking `origin/main`; the index contained 24 staged generated-file deletions. Preserve these deletions unchanged. No commit or push is part of this task.
