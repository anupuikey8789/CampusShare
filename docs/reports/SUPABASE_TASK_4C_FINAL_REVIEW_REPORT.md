# CampusShare Task 4C — Final Staging SQL Review

## Scope and safety

This is a local source and proposal review only. No Supabase project was connected, no SQL was executed, no production or staging object was changed, no migration was deployed, and no commit or push was made. The five Task 4B deliverables, database audit, schema requirements, backend, frontend API/UI, RPC documentation, and Task 3C/3D review reports were inspected.

## Schema and application contract

The final staging schema proposal retains only the audited columns and constraints:

- `profiles`: `id`, `full_name`, `email`, `student_id`, `created_at`; Auth UUID primary/foreign key; `student_id` unique when non-null.
- `categories`: identity `id`, unique non-null `name`, `created_at`.
- `resources`: identity `id`, `title`, nullable `description` and `category_id`, `owner_id`, `resource_type`, `availability_status`, `created_at`; category/owner foreign keys; availability is `available` or `unavailable`.
- `borrow_requests`: identity `id`, `resource_id`, `borrower_id`, `status`, `requested_at`, nullable `due_at` and `returned_at`; resource/borrower foreign keys; the audited date checks and four visible/confirmed status values (`pending`, `approved`, `rejected`, `returned`).

Backend projections match these fields: categories use `id,name,created_at`; resources use the eight audited resource fields; borrowing reads use `resource_id,borrower_id,requested_at,due_at,returned_at,status`. The current API creates resources with `title,description,category_id,owner_id,resource_type,availability_status` (owner derived by the backend), and PATCH permits only `title,description,category_id,resource_type,availability_status`. Borrow creation sends `resource_id` and `due_at` in legacy mode or `p_resource_id` and `p_due_at` in opt-in RPC mode. The frontend consumes those same resource/category/request properties. Generated IDs and timestamps are omitted from create inputs and supplied by database defaults.

### `profiles.email` decision

The audit marks `profiles.email` NOT NULL and says the Auth trigger copies `NEW.email`; the frontend currently implements email/password sign-up. Keep `email NOT NULL` for a staging project configured for email identities. Do not fabricate a fallback address or silently make the column nullable. Phone-only or other email-null Auth identities would make profile insertion fail and roll back Auth user creation. The project owner must decide whether staging is email-only or whether the schema/trigger should support email-null identities before enabling another provider.

## Ten audited policies and proposed hardening

The schema file reproduces the ten audited permissive policies for fidelity. The separate policy proposal adds a restrictive identity gate to each table for role `authenticated`, requiring a non-null `auth.uid()` and an explicit `is_anonymous=false` claim; missing claims fail closed. This matters because Supabase anonymous Auth users can use the `authenticated` Postgres role. It then strengthens only `Create own borrow requests`; the other nine audited business policies remain intact.

The request INSERT check enforces actor equals `borrower_id`, initial `pending`, no `returned_at`, non-future `requested_at`, the due-date check, a different owner, and an available resource. The resource subquery is filtered by the `resources` SELECT policies, so the grants proposal includes resource SELECT. The owner-read request policy also reads resources; the resources policy has no request-table subquery, avoiding a policy recursion loop. The proposed INSERT expression intentionally does not query `borrow_requests` itself: that would re-enter the table's SELECT policies and can recurse. Duplicate prevention is delegated to the unique partial index and the SECURITY DEFINER request RPC.

The policy file adds `one_active_request_per_borrower_resource` over `(borrower_id, resource_id)` for `pending` or `approved`. Its preflight stops if such duplicate pairs already exist. This prevents same-pair active duplicates under concurrent transactions; it does not serialize resource availability changes. Different borrowers can still have pending requests for the same resource unless the owner selects a different product rule. The existing `one_active_approval_per_resource` index separately allows only one approved request per resource.

Restrictive identity policies and their `is_anonymous` claim behavior need staging validation against real normal and anonymous Auth JWTs. SQL text review cannot establish claim behavior or role membership.

## Least-privilege grants proposal

The separate grants proposal revokes table ACLs for `PUBLIC`, `anon`, `authenticated`, and `service_role` on the four application tables, then grants `USAGE` on `public` to `authenticated` and:

| Table | Authenticated grant target | Reason |
|---|---|---|
| `profiles` | none | No profile route; trigger creates profiles as its trusted owner. |
| `categories` | SELECT | Category API. |
| `resources` | SELECT; INSERT only on create columns; UPDATE only on editable columns excluding `owner_id`; DELETE | Current backend CRUD; RLS remains the row-level authority. |
| `borrow_requests` | SELECT only | Borrower/owner request reads. Direct INSERT/UPDATE/DELETE withheld. |

No table privilege is granted to `anon`, `PUBLIC`, or `service_role`. No identity sequence grant is proposed: the API omits `GENERATED ALWAYS` identity values and PostgreSQL generates them through the identity definition. This must still be verified with the staging project's effective-privilege query. The current direct borrow-request POST path will be denied by this least-privilege target until the reviewed RPC is installed and enabled. The existing feature flags default off, so do not test that write against this grant target before coordinating the RPC cutover. Resource create/edit/delete remain direct PostgREST operations and require the listed column/table grants plus matching RLS.

Schema `USAGE`, table/column ACLs, RLS, and Supabase Data API schema exposure are separate gates. The proposal intentionally does not change global/default ACLs or other objects. Staging must inspect effective inherited rights and confirm `public` is exposed to PostgREST. Supabase documents that grants and RLS both govern access, and newly created projects may require explicit Data API exposure configuration.

## Auth trigger proposal

Audit evidence supports behavior, not byte-for-byte source recovery: an AFTER INSERT trigger `on_auth_user_created` calls `public.handle_new_user()`, inserting Auth UUID, metadata `full_name` with empty fallback, and Auth email. The separate proposal states that behavior explicitly and uses `SECURITY DEFINER`, `SET search_path = ''`, schema-qualified `public.profiles`, owner `postgres`, and revokes direct execution from API roles after trigger creation. It refuses to replace an existing function or trigger.

PostgreSQL requires the trigger creator to have `TRIGGER` on `auth.users` and `EXECUTE` on the trigger function at creation. The proposal assumes the Supabase staging `postgres` role can create the function and trigger. PostgreSQL trigger invocation does not require the API caller to execute the trigger function directly; however, actual Supabase-managed Auth trigger execution, role ownership, and ACL behavior must be verified by a staging signup smoke test. Since `profiles.email` is NOT NULL, null `NEW.email` causes profile insertion failure and Auth user creation failure. No exception suppression is added: silently accepting an Auth account without its required profile would break the observed relationship. Decide provider scope before applying.

## `create_borrow_request` proposed contract

The separate SQL file proposes a new function; it does not claim an existing deployed definition:

```sql
public.create_borrow_request(p_resource_id bigint, p_due_at timestamptz DEFAULT NULL)
RETURNS SETOF public.borrow_requests
```

The caller provides only resource ID and optional due time. The function requires `auth.uid()` and an explicit non-anonymous claim, rejects invalid IDs, locks the resource row first, verifies it exists/is available/is not owned by the actor, and checks for the actor/resource pair in pending or approved state. It sets `borrower_id`, `status='pending'`, `requested_at=pg_catalog.statement_timestamp()`, and `returned_at=NULL` in PostgreSQL, validates `due_at >= requested_at`, then inserts and returns one row. Using the same statement timestamp as the INSERT policy's `requested_at <= statement_timestamp()` condition matches that policy's time basis for the same RPC statement; it avoids a wall-clock sampling mismatch from `clock_timestamp()`. Expected PostgREST success is a one-element JSON array. Proposed EXECUTE is revoked from `PUBLIC`, `anon`, and `service_role`, with `authenticated` granted only.

The pending/approved query is inside a SECURITY DEFINER function whose owner must actually bypass RLS or own the table under the appropriate configuration. A resource-row `FOR UPDATE` lock serializes requests for that resource with any cooperating availability/approval routine. It only provides cross-operation safety if those routines lock the same resource first, then lock/revalidate the request row. Task 3D says audit summaries report status routine behavior but the exact bodies and lock ordering are unavailable; do not enable this RPC alongside status mutations until staging confirms compatible ordering. The unique partial index is a final concurrency backstop for borrower/resource active duplicates. SQLSTATE and PostgREST HTTP mappings are proposals and require staging tests.

## Recommended staging review order

1. Owner confirms the staging project is the intended disposable project and chooses email-only Auth or approves a different profile-email design.
2. Review and apply `SUPABASE_STAGING_SCHEMA_FINAL_REVIEW.sql` only to an empty staging project.
3. Review the trigger assumptions, role ownership and Auth trigger behavior; apply `SUPABASE_STAGING_TRIGGER_FINAL_REVIEW.sql` only after the email decision.
4. Inspect any existing requests. Review `SUPABASE_STAGING_SECURITY_POLICIES_FINAL_REVIEW.sql`; resolve active duplicate pairs by an approved process before creating its index.
5. Review `SUPABASE_STAGING_GRANTS_FINAL_REVIEW.sql`; verify effective schema/table/column rights and PostgREST exposure.
6. Inspect current status RPC bodies, owners, ACLs, and lock order in staging before applying `SUPABASE_CREATE_BORROW_REQUEST_RPC_PROPOSAL.sql`. The RPC proposal depends on the active-pair index and compatible resource-first locking.
7. Run the read-only validation SQL and two-account staging tests. Keep RPC flags disabled until all gates pass. No SQL from this review has been applied.

These are separate proposals. The grants and policy proposals have transaction blocks and preflight guards; schema creation is also transactional after a read-only preflight. The trigger and RPC proposals create new objects only and fail if objects already exist. A failed statement within a transaction rolls back that transaction; preflight DO blocks run before their transaction, so they are read-only checks and abort before DDL. For rollback, stop the staging app and use separately reviewed inverse DDL only after checking dependencies and test data. Do not run blanket DROP statements: schema objects may have dependencies. No automated rollback script is included.

## Static validation and execution results

At Task 4C, the Release build reported `ninja: no work to do`, the backend mock API suite passed, frontend JavaScript syntax checks passed, and `git diff --check` passed with existing LF-to-CRLF warnings. Source-only SQL checks verified expected transaction markers, no `DROP`/`TRUNCATE`/`DELETE FROM`, policy/RPC active-index naming, absence of a recursive request-table policy subquery, function security/ACL markers, and sensitive-literal scans. No SQL parser or database was used. These checks cannot prove PostgreSQL syntax, Supabase role capabilities, PostgREST exposure, trigger behavior, RLS enforcement, or concurrency semantics.

Task 4D changed only SQL proposals and documentation; backend/frontend code was not changed, so the build and mock suite were not rerun for Task 4D. Mock tests do not prove live Auth, grants, RLS, or RPC behavior. No live Supabase test was performed.

## Remaining decisions and risks

- Confirm whether Auth is restricted to email/password; decide expected behavior for Auth users with null email.
- Verify the normal/anonymous token `is_anonymous` claim and staging policies.
- Verify staging role grants, column ACLs, `public` schema USAGE, Data API exposure, and `service_role` effective access.
- Inspect the exact three status RPC bodies/return types/ACLs and lock ordering before using the create-request RPC concurrently with status workflows.
- Confirm the intended concurrent request rule for different borrowers and whether one active request per borrower/resource matches product expectations.
- Confirm category seed data and any unaudited text constraints/defaults.
- Validate RPC response shape and SQLSTATE/HTTP error mapping in staging.

## Repository state

No database was accessed or changed. No commit or push was made. The existing 24 staged generated-file deletions were not intentionally modified; final Git status must be checked before handoff.
