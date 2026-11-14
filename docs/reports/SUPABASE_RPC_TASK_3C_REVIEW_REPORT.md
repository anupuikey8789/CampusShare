# CampusShare Task 3C — Atomic Resource Update Review

## Scope and safety

This is a local source and mock-test review of `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql`, the feature-flagged C++ caller, and the RPC documentation. No SQL was sent to Supabase, and no production or staging database was changed. No feature flag was enabled, and no commit or push was made.

## Findings

### High — anonymous Auth identities

Supabase anonymous Auth users can receive the Postgres `authenticated` role. The RPC must not treat a non-null `auth.uid()` or `authenticated` role as proof of a permanent student identity. The proposal now requires `auth.jwt()->>'is_anonymous'` to be explicitly `false`; a missing claim fails closed. Confirm the claim's presence and behavior with normal and anonymous staging tokens before enabling the flag. The backend's Auth `/user` verification confirms the token/user but does not independently make this product distinction.

### High — cross-operation concurrency remains unverified

The proposed function locks the resource row before checking for an approved borrow request and before changing availability. This makes the edit internally atomic. It prevents a race with approval/return only if those functions lock the same resource in a compatible order and perform their status/resource updates in the same transaction. The complete status-function bodies and lock order are not available in the repository, so this cross-function invariant is not yet verified. Do not enable the flag until staging concurrency tests prove it.

### Medium — nullable PATCH values did not match the schema contract

The C++ route previously rejected explicit JSON null for nullable `description` and `category_id`, preventing clients from clearing those fields. It now forwards null for those two fields while continuing to reject null for non-nullable fields. Omitted values remain omitted. Mock coverage checks this distinction.

### Medium — field lengths are undocumented

The checked-in schema evidence confirms the relevant columns but does not confirm per-column text length constraints. Neither SQL nor C++ invents title/description limits. The backend rejects bodies over 16 KiB, and the SQL proposal also caps serialized `p_changes` at 16 KiB. Confirm whether that payload cap and any database text constraints match staging.

### Medium — SECURITY DEFINER and grants need staging inspection

The proposal fixes `search_path` to empty, schema-qualifies database objects, derives the actor from `auth.uid()`, limits updates to the owned resource, and revokes EXECUTE from `PUBLIC`, `anon`, and `service_role` before granting it to `authenticated`. The owner must be a trusted migration role with the intended table privileges. Verify actual function owner, `prosecdef`, `proconfig`, ACL expansion, PostgREST exposure, and RLS/table grants in staging. SQL text review does not prove catalog ACL state.

### Medium — business error mapping requires staging confirmation

The C++ maps stable SQLSTATEs and a small set of known messages to sanitized HTTP errors. The proposal currently uses SQLSTATEs for validation/authorization/not-found, but PostgREST's concrete HTTP mapping and the category foreign-key response must be verified against the installed function. The API never returns raw database detail. A failed RPC does not trigger a direct PATCH fallback.

## Current atomic update contract

- Proposed signature: `public.update_resource_atomic(p_resource_id bigint, p_changes jsonb)`.
- Proposed return: `SETOF public.resources`; PostgREST success is expected as a one-row JSON array.
- Allowed change keys: `title`, `description`, `category_id`, `resource_type`, `availability_status`.
- `p_resource_id` must be positive; the changes object must be non-empty and no more than 16 KiB when serialized.
- Omitted values remain unchanged. Explicit JSON null clears only nullable `description` and `category_id`.
- Availability is `available` or `unavailable`. `owner_id` and all unknown keys are rejected.
- Identity comes from `auth.uid()`; anonymous identity is rejected using the `is_anonymous` JWT claim.
- Ownership and the approved-loan availability check occur under a resource row lock; all supplied fields update in one statement.
- Proposed EXECUTE ACL: revoke from `PUBLIC`, `anon`, and `service_role`, then grant to `authenticated`. This is not installed or verified.
- C++ caller: existing `PATCH /api/resources/{id}`, behind `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=false` by default. RPC failure never falls back to direct PATCH.

## Status RPC and profile-trigger review boundary

No approve/reject/return route or frontend action is added by this task. The audit snapshot reports these exact signatures and current EXECUTE access for `PUBLIC`, `anon`, `authenticated`, and `service_role`:

- `public.approve_borrow_request(bigint,timestamptz)`
- `public.reject_borrow_request(bigint)`
- `public.return_borrowed_resource(bigint)`

The proposed `SUPABASE_CORRECTION.sql` revokes EXECUTE from all four roles (with authenticated grants only shown as commented future statements), so that script disables all three workflows. `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` instead revokes `PUBLIC`, `anon`, and `service_role`, then grants `authenticated` on each exact signature. That second approach matches the documented owner-checked workflow only if the exact function bodies, ownership checks, status transitions, and return-confirmation product rule are verified. These SQL files conflict; neither was executed. The complete deployed definitions and return types still require staging inspection.

Both correction proposals revoke direct EXECUTE on `public.handle_new_user()` from API roles while leaving the `auth.users` trigger intact. PostgreSQL documents EXECUTE as a prerequisite for creating a trigger on its function; the proposed revoke does not itself drop or replace the existing trigger. Still verify that signup/profile provisioning works in staging after the ACL change, and verify function owner/SECURITY DEFINER/search_path. This task changes no profile-trigger ACL and does not claim signup was tested.

## Local verification

The expanded `BACKEND/tests/test_api.py` suite exercises a local mock only. It covers metadata-only, availability-only, combined updates, nullable fields, missing token, mocked anonymous-user rejection, owner denial, invalid IDs/fields/status/title/types, empty payload, oversized payload, missing resource, category FK error, approved-loan conflict, malformed success, timeout, separate API key and Bearer headers, and absence of a direct-write fallback. The anonymous case verifies C++ error handling for a mocked database 28000 response; it does not execute the SQL JWT check.

The final verification performed for this review:

```powershell
cmake --build BACKEND/build-msvc --config Release
# [1/2] compile main.cpp; [2/2] link campusshare_backend.exe — succeeded
python BACKEND/tests/test_api.py BACKEND/build-msvc/campusshare_backend.exe
# PASS: config/service-key rejection; mocked Auth; direct and RPC request paths;
# atomic resource RPC parameters and ownership denial; availability conflicts;
# malformed responses; timeout/no-fallback; disabled status routes; CORS/OPTIONS
```

The first run of the expanded mock suite exposed an incorrect test-side request-count baseline after the new missing/anonymous-token cases. That assertion was corrected to snapshot the current RPC call count immediately before invalid-input cases; the complete suite then passed.

Static SQL checks are limited to source inspection and delimiter/statement structure. A PostgreSQL parser is not currently available in the local environment; no SQL has been executed. Do not describe the proposal as database-validated.

## Staging gates before enabling

1. Re-run the read-only schema, grant, policy, function-owner, function-definition, and ACL audit in the intended staging project.
2. Confirm the exact `resources` constraints, defaults, category FK behavior, and text length limits.
3. Verify normal signed-in JWTs contain `is_anonymous=false`; anonymous or missing-claim tokens are rejected.
4. Confirm the function owner is trusted, fixed `search_path` is retained, and only the intended role can EXECUTE.
5. Test owner and two non-owner accounts; unknown keys, null semantics, category FK failure, missing row, malformed input, and approved-loan conflict.
6. Race availability edits against approval and return. Confirm both code paths lock resources consistently and preserve status/availability invariants under concurrent transactions.
7. Confirm PostgREST's response row shape and SQLSTATE-to-HTTP mapping. Confirm the API has no direct-write fallback.
8. Run the profile provisioning smoke test separately if trigger-function permissions are changed.
9. Keep `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=false` until all staging gates pass and application rollout is approved.

## Changed files in Task 3C

- `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql`
- `BACKEND/main.cpp`
- `BACKEND/tests/test_api.py`
- `SUPABASE_RPC_IMPLEMENTATION.md`
- `SUPABASE_RPC_API_CONTRACTS.md`
- `SUPABASE_RPC_TEST_CASES.md`
- `SUPABASE_RPC_DEPLOYMENT_CHECKLIST.md`
- `SUPABASE_RPC_ROLLBACK_PLAN.md`
- `SUPABASE_RPC_TASK_3C_REVIEW_REPORT.md`

