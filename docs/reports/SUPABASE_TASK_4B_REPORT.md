# CampusShare Task 4B — Staging Setup Hardening Report

## Safety

No Supabase project was accessed. No SQL was executed, no production object or permission was changed, no migration was deployed, and the existing production correction SQL files were not edited. No status RPC definitions or permission corrections were combined into the staging proposals. No commit or push was made.

## Files reviewed

- `SUPABASE_STAGING_SCHEMA.sql`
- `SUPABASE_STAGING_SETUP_GUIDE.md`
- `SUPABASE_STAGING_VALIDATION.sql`
- `SUPABASE_TASK_4A_REPORT.md`
- `SUPABASE_DATABASE_AUDIT.md`
- `SUPABASE_SECURITY_REVIEW.md`
- `SUPABASE_CORRECTION.sql`
- `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql`
- Also cross-checked `BACKEND/SUPABASE_SCHEMA_REQUIREMENTS.md`, `BACKEND/main.cpp`, `.env.example`, the Task 3C/3D reports, and local RPC documentation.

## Profile creation trigger assessment

The original function text cannot be recovered byte-for-byte from this repository. The audit evidence does establish its reported behavior: an AFTER INSERT trigger named `on_auth_user_created` on `auth.users` calls `public.handle_new_user()`, which inserts Auth ID, metadata full name with an empty fallback, and Auth email into `public.profiles`. The schema confirms `profiles.id`, `full_name`, and `email` and the Auth ID relationship.

Created `SUPABASE_STAGING_TRIGGER_PROPOSAL.sql` as an explicitly labeled behavior-level reconstruction, not a claim to have recovered the original source. The assumptions are visible in comments and code: extract `full_name` using JSON text access, use `''` if missing/null, copy `NEW.email` directly, perform a plain insert, return `NEW`, and use the audited trigger name/timing. It defines a new `SECURITY DEFINER` routine with `search_path = ''`, qualifies `public.profiles`, sets owner `postgres`, creates the trigger only if neither object already exists, then revokes direct execution from `PUBLIC`, `anon`, `authenticated`, and `service_role`. It does not replace existing objects. Signup behavior must be tested in staging after review.

Unverified detail: the Auth email field is copied directly. Since `profiles.email` is NOT NULL, an Auth identity without email would fail profile creation; this proposal is suitable only for the configured email/password staging flow unless the owner approves another behavior. The function source's exact exception handling, metadata normalization, conflict handling, and grants were not in the local evidence.

## Least-privilege grants proposal

Created `SUPABASE_STAGING_GRANTS_PROPOSAL.sql`. It removes table privileges for `PUBLIC`, `anon`, and `authenticated` on the four staging tables, then grants only the current required authenticated operations:

| Table | `anon` / `PUBLIC` | `authenticated` target | Reason |
|---|---|---|---|
| `profiles` | none | no direct table privilege | No current C++/frontend profile endpoint; the trigger owns profile creation. |
| `categories` | none | SELECT | Categories API reads `id,name,created_at`. |
| `resources` | none | SELECT; INSERT on editable/create columns; UPDATE on editable columns excluding `owner_id`; DELETE | Current resource CRUD routes. RLS enforces owner identity; resource reads are also used for owner checks. |
| `borrow_requests` | none | SELECT only | Current GET route, with borrower/owner SELECT policies. Direct INSERT/UPDATE/DELETE are withheld. |

No grant is made to `service_role`; the backend must use the user's token and public API key. The proposal does not modify function EXECUTE ACLs. Supabase's platform-level `service_role` characteristics and any project default ACLs must still be inspected; this file does not revoke a service-role table grant.

The current C++ direct request-creation path (RPC flag false) needs `INSERT` on `borrow_requests` and would fail under the least-privilege target. Enabling it would preserve a race-prone direct write path. The target is to install/review the separate `create_borrow_request` function contract, grant its EXECUTE privilege only after source/ACL review, then configure the staging backend to use that RPC. The existing SQL file contains a proposal, not a verified deployed function, so this report does not treat it as installed or grant it here.

## Borrow-request policy and concurrency

The verified INSERT policy only checks `borrower_id = auth.uid()`. It permits initial states other than pending, self-borrowing, unavailable resources, and duplicates when the caller also has the required table grants. The staged schema reconstruction preserves that policy for fidelity; the separate `SUPABASE_STAGING_SECURITY_POLICIES_PROPOSAL.sql` strengthens it for staging.

The proposed `WITH CHECK` requires a non-anonymous Auth identity, borrower ID equal to `auth.uid()`, `status='pending'`, `returned_at IS NULL`, request time not in the future, due-date check, a different resource owner, an available resource, and no same-borrower/resource pending or approved request. The policy alone cannot prevent two concurrent transactions from both observing no duplicate. The proposal adds a partial unique index on `(borrower_id, resource_id) WHERE status='pending'`; it aborts if duplicate pending rows exist and does not delete/alter rows.

The policy/index still cannot atomically serialize a borrow request against an availability change or approval. The proposed `create_borrow_request` RPC should, inside one database transaction, derive borrower ID from `auth.uid()`, reject anonymous/missing identity, ignore client-supplied status/borrower/timestamp values, lock the resource row, verify it exists/is not owned by the borrower/is available, reject the borrower's pending or approved duplicate, set `pending` and database-generated request time, validate `due_at`, insert, and map uniqueness conflicts safely. It must use a consistent lock protocol with approval and resource-availability functions. This is design guidance only; no deployed function definition or signature is asserted.

The policies also add a fail-closed `is_anonymous=false` claim condition across staging reads and writes. This is a staging hardening choice, not part of the observed production policy text. Validate the claim on normal and anonymous staging Auth tokens.

## Revised package files

1. `SUPABASE_STAGING_SCHEMA_REVISED.sql` — table/schema and audited policy reconstruction, no grants or functions.
2. `SUPABASE_STAGING_GRANTS_PROPOSAL.sql` — separate table privilege proposal, no function EXECUTE changes.
3. `SUPABASE_STAGING_SECURITY_POLICIES_PROPOSAL.sql` — staging policy strengthening plus pending-pair unique index.
4. `SUPABASE_STAGING_TRIGGER_PROPOSAL.sql` — staging-only behavior-level Auth trigger reconstruction.
5. `SUPABASE_TASK_4B_REPORT.md` — this report.

None of the proposals includes approve/reject/return functions or resolves the conflicting production status-RPC ACL corrections. `SUPABASE_CORRECTION.sql` and `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` remain unchanged.

## Recommended staging order

1. Confirm the project reference is `CampusShare-Staging`, the project is disposable, and the schema is empty. Do not execute against production.
2. Review and apply `SUPABASE_STAGING_SCHEMA_REVISED.sql` in the staging SQL Editor.
3. Review `SUPABASE_STAGING_TRIGGER_PROPOSAL.sql`, including its assumptions, then apply only if approved. Test signup and profile UUID/email/name behavior.
4. Inspect existing request rows (if any). Review and apply `SUPABASE_STAGING_SECURITY_POLICIES_PROPOSAL.sql`; its pending unique index creation intentionally fails on duplicate pairs rather than cleaning them.
5. Review and apply `SUPABASE_STAGING_GRANTS_PROPOSAL.sql`. Confirm schema USAGE and actual effective grants with the read-only validation file.
6. Run `SUPABASE_STAGING_VALIDATION.sql`; compare actual objects and privileges to the plan. No API mutations should be tested until profile provisioning, grants, and request RPC access are resolved.
7. Do not enable status RPCs. Keep backend RPC flags off until the relevant staging function definitions, grants, row locks, and tests are reviewed.

The order of steps 3–5 may be adjusted by the staging owner, but policies should be hardened before any authenticated write grants are enabled. The SQL files are separate proposals and have not been run.

## Remaining uncertainties

- Exact original `handle_new_user()` source, email-null behavior, error handling, and exact function ACL.
- Whether normal Auth tokens always contain `is_anonymous=false` in this project and whether anonymous sign-in is enabled.
- Actual staging default privileges, schema USAGE, table grants, and effective service-role privileges.
- The status RPC bodies, return types, SQLSTATE behavior, permissions, and lock order.
- Whether different borrowers may have simultaneous pending requests for one resource; this package permits that while preventing duplicate pending requests by the same borrower/resource.
- The create-request RPC's deployed signature/implementation and direct-write cutover timing.
- Category seed values and any additional constraints/defaults not in the audit.
- No SQL parser/database validation was available or attempted; static checks cannot guarantee PostgreSQL/Supabase execution.

## Static validation and Git

Static checks only: generated SQL has expected transaction boundaries; staging grants contain no status-function ACL statements; policies contain no status transitions; schema/policy files reference only audited columns; no destructive row/object-removal statements are present; read-only validation remains SELECT-only; no credential-shaped values or production URL literals were found in the five Task 4B files. These checks do not establish database validity.

The branch remains `main`. The 24 pre-existing staged generated-file deletions remain unchanged. Existing unstaged/untracked work was preserved. No Supabase project was accessed or modified, and no commit or push occurred.
