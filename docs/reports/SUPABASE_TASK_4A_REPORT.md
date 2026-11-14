# CampusShare Task 4A — Staging Database Setup Package

## Safety and scope

This package was prepared from repository evidence only. No Supabase connection was made; no SQL was executed; production and staging functions, permissions, policies, schema, and data were not changed. No credentials or student records were included. No commit or push was made.

## Files inspected

- `SUPABASE_DATABASE_AUDIT.md`
- `BACKEND/SUPABASE_SCHEMA_REQUIREMENTS.md`
- `SUPABASE_READ_ONLY_AUDIT.sql`
- `SUPABASE_CORRECTION_PLAN.md`
- `SUPABASE_CORRECTION.sql`
- `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql`
- `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql`
- `SUPABASE_STATUS_RPC_STAGING_INSPECTION.sql`
- RPC implementation/API/migration documentation and the Task 3C/3D review reports

## Schema reconstructed

`SUPABASE_STAGING_SCHEMA.sql` reconstructs `profiles`, `categories`, `resources`, and `borrow_requests` from the verified audit fields/defaults, PKs, FKs, delete behavior, unique constraints, check constraints, RLS mode, and ten observed policies.

It includes the verified partial unique index `one_active_approval_per_resource`. It also includes four non-unique FK lookup indexes recommended by the checked-in audit/correction materials; these are identified in comments and the guide as staging performance additions, not members of the reported production index inventory. No pending-request unique index is added because it remains a proposal rather than a verified constraint.

The observed borrowing-request INSERT policy is reproduced exactly (`borrower_id = auth.uid()`). The setup SQL and guide prominently warn that it does not enforce pending-only status, self-borrow prevention, availability, or duplicate prevention. Direct borrowing writes should remain disabled until an approved safer database contract is available.

## Missing information and limitations

- The exact source of `handle_new_user()` is absent from the repository. The audit describes its behavior but does not provide its implementation. The staging schema therefore omits the function and `auth.users` trigger. Auth signup will not create `profiles` rows from this package alone; owner/profile workflows remain blocked until that source is provided and reviewed.
- The package contains no status RPCs, request-creation RPC, or atomic resource-update RPC. Their full definitions/contracts are not part of this schema reconstruction.
- No GRANT or REVOKE statements are included. Table privileges are a separate gate from RLS and need a separately reviewed staging-only decision before API testing.
- No category row values or text-length limits were present in the evidence; no seed data or guessed limits were added.
- The report and guide distinguish observed production facts from staging-only recommended lookup indexes and unresolved assumptions.

## Deliverables

- `SUPABASE_STAGING_SCHEMA.sql` — setup DDL with a table-existence preflight and one transaction; no function or permission DDL.
- `SUPABASE_STAGING_SETUP_GUIDE.md` — staging-only order, Auth setup, two test accounts, validation, blockers, and rollback cautions.
- `SUPABASE_STAGING_VALIDATION.sql` — SELECT-only catalog queries for columns, constraints, indexes, RLS/policies, functions/triggers, and effective table/column grants.
- `SUPABASE_TASK_4A_REPORT.md` — this report.

## Static validation

Local static checks were run only. They verified that the setup file contains all four tables and ten policies, has a transaction boundary, and contains no function creation or permission statements; the validation file contains only SELECT statements; all four generated files are UTF-8 without trailing whitespace; and `git diff --check` passes. These checks do not parse SQL with PostgreSQL and do not prove the setup will execute successfully in Supabase.

## Git state

Branch remains `main`. The 24 pre-existing staged generated-file deletions remain unchanged. The four Task 4A deliverables are untracked additions. No commit or push was made.
