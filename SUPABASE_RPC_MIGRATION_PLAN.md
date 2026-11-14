# CampusShare RPC migration plan

No database changes are made by this plan. Production SQL execution and permission changes require explicit approval. Use a staging project and disposable test accounts.

## Phase A — Contracts and staging SQL

1. Re-run the read-only metadata audit against the intended staging project.
2. Inspect exact function definitions, `proargnames`, argument/return types, owner, `SECURITY DEFINER`, fixed `search_path`, and `proacl` for the request and status RPCs.
3. Review `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql`; verify role, table privileges, RLS implications, category FK behavior, and row locks. Do not apply it before approval.
4. Resolve the status RPC ACL conflict between `SUPABASE_CORRECTION.sql` (authenticated execution revoked) and `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` (authenticated execution granted).
5. Test profile trigger/signup behavior after any staging function ACL change. Test data only; never production.

## Phase B — Backend deployment in staging

1. Build and deploy the backend with both RPC flags false; verify existing routes and frontend continue working.
2. Deploy the approved matching SQL contracts in staging.
3. Set `SUPABASE_RPC_CREATE_BORROW_REQUEST=true` in staging; verify request body parameters, user JWT forwarding, returned row shape, and no direct-write fallback.
4. Set `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true` in staging; verify metadata-only, availability-only and combined updates each produce one database operation and one returned resource row.
5. Verify RPC failures/timeouts do not trigger direct-write retries.

## Phase C — Two/three-account authorization and race tests

Use owner A, borrower B and unrelated student C with their own Auth sessions. Test allowed and denied operations, self-borrow, unavailable resource, foreign IDs, duplicate requests, category FK errors, invalid status values, approved-loan availability protection, and malformed/expired tokens. Run concurrent create-request/availability and approve/return races. Confirm constraints and locks yield consistent committed states.

Status operations stay disabled until exact definitions, return types, ACLs and route response mapping are verified. Product rules are owner-only approve, reject and return. Verify borrower and unrelated callers are denied by the database function itself.

## Phase D — Frontend compatibility

No frontend API change is needed for the existing create-request or resource PATCH route. Keep the edit form intact. Do not add status controls until staging status routes exist and two-account tests pass.

## Phase E — Direct-write permission cutover

Only after backend and frontend staging tests pass, obtain explicit approval for narrowly scoped grants. Revoke direct borrowing INSERT and resource `availability_status` UPDATE only after the corresponding routes are using the RPC. For the atomic full resource edit function, verify whether direct metadata UPDATE must also be restricted to meet the chosen threat model. Keep RLS and least-privilege SELECT/create/delete grants intact. Never use a service-role key as a workaround.

## Phase F — Production rollout/rollback

Production rollout requires a fresh audit, approved SQL diff, explicit owner approval, backup/rollback plan, monitored deployment, post-change audit, and staged rollout of feature flags. If RPC errors occur, do not retry through a second write path. Roll back the application only if current direct permissions still support it; otherwise deploy the RPC-capable prior version or coordinate an approved permission change. Do not restore `PUBLIC`/`anon` execution.

## Current gates

- Both flags default false.
- Borrow RPC contract is present only as a local proposal; staging installation/ACL/return shape unverified.
- Atomic update is a new local proposal; SQL approval and staging verification pending.
- Status definitions/return types are incomplete in local deliverables and ACL recommendations conflict; status routes absent.
- No live Supabase tests or production SQL execution have occurred.
