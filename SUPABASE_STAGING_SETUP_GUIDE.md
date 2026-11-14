# CampusShare Staging Database Setup Guide

## Scope and safety

This package was reconstructed locally from the checked-in 2026-11-10 database audit, schema requirements, read-only audit query, and correction/RPC proposals. No Supabase connection was made and no SQL was run. It is for the separately named **CampusShare-Staging** project only. Verify the staging project reference in the dashboard before any manual execution; never use the production project.

The setup SQL intentionally does not create or replace database functions, triggers, grants, or revokes. It does create the four tables, constraints, indexes, and the RLS policies documented as existing. It contains no credentials, Auth passwords, service-role key, production records, or category seed values. Review the known weak borrowing-request INSERT policy before using any direct write path.

## Setup order

1. In Supabase, verify that the open project is `CampusShare-Staging`, confirm its project reference, and confirm it is disposable. The schema script stops if any of the four application tables already exist; do not remove existing objects to make it pass.
2. Review `SUPABASE_STAGING_SCHEMA.sql` and this guide. The script wraps its table, index, and policy DDL in one transaction after a preflight. Execute it manually only in the verified staging SQL Editor after the project owner approves. This agent has not executed it.
3. Review `SUPABASE_STAGING_VALIDATION.sql`. After setup, run it manually in that same staging project and save the metadata results. It contains SELECT-only inspection queries.
4. Compare all returned columns, defaults, constraints, indexes, RLS expressions, function/trigger inventory, and grants with this package. Stop on any discrepancy; do not apply a corrective migration by assumption.
5. Decide and review the staging table grants separately. The schema script intentionally has no GRANT or REVOKE statements, as requested. RLS policies do not themselves grant SQL table privileges. The current audit's required authenticated table privileges are a reference point, not an instruction to change staging permissions automatically.
6. Do not enable `SUPABASE_RPC_CREATE_BORROW_REQUEST` or `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE`. This package does not create their functions. Do not invoke status RPCs; they are not created here and their full definitions/ACLs remain unverified locally.

## Supabase Auth configuration and test accounts

1. In the staging Auth settings, enable the email/password provider. Confirm whether email confirmation is required, and set staging-only Site URL and redirect URLs to the actual local or staging frontend origin. Those project-specific settings were not present in the repository evidence.
2. Use two separate test student email accounts with inbox access: **Student A** will own a resource and **Student B** will request it. Use the frontend registration flow or Supabase Auth's staging-only user management. If confirmation is enabled, complete confirmation for both accounts.
3. Use unique test addresses and passwords managed locally or by the account owner. Do not paste passwords, access tokens, publishable keys, or service-role keys into this guide, source control, or chat.
4. The frontend registration sends `full_name` as Auth user metadata. However, this package omits `handle_new_user()` and `on_auth_user_created` because the repository has only an audit description of that function's behavior, not its verified source body. Consequently, new Auth users will not automatically get `profiles` rows from this schema script. The profile FK prevents them from owning resources or creating requests until the project owner supplies and reviews the exact trigger function source and a separate staging-only trigger setup is approved.
5. Do not work around the missing profile provisioning by weakening RLS or granting broad table access. Signup/profile provisioning is a hard staging integration blocker for user-owned data.

## Schema and RLS checks

Run `SUPABASE_STAGING_VALIDATION.sql` only in the staging project. Verify:

- The four tables have exactly the columns, nullability, identity behavior, and defaults documented in the database audit.
- The four primary keys, verified foreign keys/delete behavior, unique constraints, and date/status/availability checks match the audit.
- `one_active_approval_per_resource` is unique and partial on approved requests. The four non-unique FK lookup indexes in the setup file are staging performance indexes based on the audit's advisor findings, not part of the reported production seven-index inventory.
- RLS is enabled and not forced on all four tables. All ten policies and their complete `USING`/`WITH CHECK` expressions match the checked-in evidence.
- No UPDATE or DELETE policy was added to `borrow_requests`; no status RPC was created; the profile trigger remains absent until its implementation is verified.
- Inspect effective table/column grants and function execute access. The setup script does not alter permissions. Do not assume policy presence grants SQL privileges.

## Known gaps and assumptions

- The exact `handle_new_user()` body and Auth trigger implementation are not in local source evidence. It is intentionally omitted.
- Category names/rows were not included; no category data is seeded.
- No per-column text length constraints were verified; the script adds none.
- Status functions, request-creation RPC, and atomic resource-update RPC are not included. Their full contracts and staging permissions remain separate work.
- The confirmed borrowing-request INSERT policy checks only `borrower_id = auth.uid()`. It does not enforce pending-only status, prevent self-borrowing, require availability, or prevent duplicates. The package reproduces this observed policy exactly, so do not expose direct borrowing writes in staging until an approved safer RPC/policy design is installed and tested.
- The setup creates the verified partial unique approved-request index and non-unique lookup indexes. It does not create a pending-request unique index because that index is only proposed, not confirmed as existing or approved.
- The audit snapshot reports grants, but this package intentionally does not copy or alter any existing grants. Approve a minimal staging grant plan separately before API calls.

## Rollback and cleanup

The setup is wrapped in one transaction, so an error before COMMIT should roll back its DDL as a unit in PostgreSQL. If setup completes but staging validation fails, stop using the project and have its owner inspect the actual catalog before planning cleanup. This guide provides no DROP/rollback SQL. Never apply this package to production.
