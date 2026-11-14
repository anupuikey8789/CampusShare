# CampusShare Supabase RPC deployment checklist

This checklist is for a future staging rollout. It does not authorize production SQL. Do not use service-role credentials for application requests.

## Before staging SQL

- [ ] Re-run `SUPABASE_READ_ONLY_AUDIT.sql` against the intended staging project and compare schema, grants, policies, function bodies, owners, `search_path`, ACLs, indexes, and constraints with the reviewed snapshot.
- [ ] Confirm the staging URL/project and that test accounts and test resources are disposable.
- [ ] Review `SUPABASE_CORRECTION_PLAN.md`, `SUPABASE_CORRECTION.sql`, and `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` together. Resolve their conflicting authenticated grants/revokes for the three status RPCs.
- [ ] Inspect exact RPC `proargnames`, argument types, return types, owners, `prosecdef`, `proconfig`, and ACLs. Verify every `SECURITY DEFINER` function has a fixed safe search path and schema-qualified objects.
- [ ] Review `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql` and approve or revise its proposed signature/result. Preserve one-request atomic form behavior.
- [ ] Verify Auth tokens contain the expected `is_anonymous` claim; test that the function rejects anonymous identities and accepts normal signed-in users. Missing claim is intended to fail closed.
- [ ] Inspect actual resource text constraints/defaults. The proposal has no invented per-column text length and caps the JSON payload at 16 KiB; confirm compatibility with staging.
- [ ] Inspect exact approve/reject/return function bodies and lock order. Prove they serialize with the resource lock used by `update_resource_atomic` when checking approved-loan invariants.
- [ ] Confirm that profile creation still works in staging if trigger-function EXECUTE ACLs are narrowed.
- [ ] Obtain approval for any staging SQL changes. Apply only to staging; never run the reviewed correction against production as a test.

## Backend build and local mocks

- [ ] Build the MSVC/CMake Release target.
- [ ] Run `python BACKEND/tests/test_api.py <backend executable>` and the frontend test suite.
- [ ] Verify the default `SUPABASE_RPC_CREATE_BORROW_REQUEST=false` path returns 503 `borrow_requests_pending` and makes no PostgREST resource/request read or write.
- [ ] Verify `/api/health` reports configured RPC flag booleans and the frontend hides request actions when request RPC mode is false; a true flag is not proof that the SQL function is installed.
- [ ] Verify RPC mode requires an authenticated user, forwards that user's JWT and the configured public API key separately, and sends only `p_resource_id` and `p_due_at`.
- [ ] Verify atomic update RPC sends `p_resource_id` and a whitelist-filtered `p_changes` object and returns one resource row.
- [ ] Verify omitted fields preserve data and explicit null clears only nullable `description` or `category_id`; test unknown keys and type validation.
- [ ] Verify missing-token and anonymous-user denial at the function boundary, not merely via Postgres role membership.
- [ ] Verify a failed RPC never triggers a direct-write fallback.
- [ ] Verify duplicate and state errors return sanitized expected HTTP codes; no raw Postgres details, access tokens, or private row data appear in logs or responses.
- [ ] Confirm connection/total timeouts, malformed JSON, CORS allowlist, and preflight behavior.

## Staging integration with two student accounts

- [ ] Use student A as resource owner and student B as borrower; use their own browser sessions and current access tokens.
- [ ] Verify B can submit a pending request for A's available resource; verify borrower identity is derived from `auth.uid()`.
- [ ] Verify self-borrowing, unavailable/missing resources, forged borrower IDs, duplicate active requests, and invalid due dates are rejected.
- [ ] Run simultaneous request attempts for the same borrower/resource and confirm at most one pending row; run competing requests from B and C and confirm the documented multi-pending behavior.
- [ ] Run concurrent request creation and availability changes; confirm resource locks produce a consistent result.
- [ ] Confirm token forwarding still triggers existing grants/RLS as the calling user. Never substitute a service-role key if permission fails.
- [ ] Test every authorized and unauthorized resource owner operation, including a request from an unrelated third account.
- [ ] Test status functions only after their ACL conflict is resolved. Verify owner-only approval/rejection/return, borrower denial for return, invalid/repeated transitions, and transaction-level resource/request consistency.
- [ ] Test Auth profile provisioning and normal sign-in/session refresh.
- [ ] Record expected/actual/pass-fail for each test. Label mocks and live staging results separately.

## Rollout gate

- [ ] Deploy a backend that supports the same public route contracts before changing grants.
- [ ] Enable `SUPABASE_RPC_CREATE_BORROW_REQUEST=true` in staging only; confirm the matching function signature and returned array.
- [ ] Do not enable a resource-edit RPC until its SQL signature and atomic semantics are approved, installed in staging, and tested.
- [ ] Do not expose approval/rejection/return controls until status RPC ACLs and routes are resolved and tested.
- [ ] Obtain explicit approval before any production grant, policy, function, index, or schema change.
- [ ] Re-run the audit after an approved production rollout and verify direct write privileges are removed only after the compatible backend is deployed.
