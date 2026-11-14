# CampusShare Task 12 — Full-Stack Feature Audit and Staging Plan

## Scope and safety

This task requests a larger product extension: paid/free borrowing, sale, donation, pricing rules, listing reports, private images, private handover details, request workflows, C++ APIs, and responsive UI. The existing project already contains Supabase Auth, authenticated resource CRUD, authenticated reads, and feature-gated borrowing routes. The audited base schema has four tables and does not contain verified sale/donation pricing, image metadata, handover detail, or listing-report objects.

No Supabase project was accessed. No SQL was executed. No production or staging object was modified. Existing RPC flags remain disabled; no commit or push was made.

## Verified existing foundation

- C++ Crow authenticates user requests through Supabase Auth, forwards the user token separately from the public API key, and uses PostgREST for existing resources, categories, and borrowing routes.
- Existing resources are modeled as general materials with `title`, `description`, `category_id`, `owner_id`, `resource_type`, `availability_status`, and `created_at`.
- Existing `borrow_requests` supports `pending`, `approved`, `rejected`, `returned`, but the production table has no UPDATE RLS policy. Status updates must use reviewed owner-authorized RPCs; the feature flags are off by default.
- The current frontend includes separate navigation, dashboard, resource browse/CRUD forms, authenticated session handling, and feature-gated borrowing controls.

## New staging proposal

Created `SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql`, `SUPABASE_STAGING_MARKETPLACE_ROLLBACK.sql`, `SUPABASE_STAGING_MARKETPLACE_VERIFY.sql`, and `SUPABASE_STAGING_MARKETPLACE_GUIDE.md`.

The proposed migration adds `listing_mode` and validated pricing/state fields to resources; creates transfer-request, private image metadata, private handover details, and report tables; sets RLS/grants; requires an owner-created private image bucket; and defines five authenticated-only SECURITY DEFINER functions with empty search paths and row-lock checks. Sale and donation requests are separate from borrow requests. The SQL is a proposal derived from the product requirements, not a verified deployed schema.

The rollback refuses to proceed if extension tables contain rows, resource marketplace values exist, or Storage objects remain. It intentionally leaves the empty private bucket in place for manual dashboard cleanup and does not restore grants automatically because their pre-migration state must be reviewed.

## Implementation status

The repository's existing resource and borrowing APIs were inspected. The baseline functionality is present, but the new seller/buyer/recipient, image, report, pricing, and private handover flows are not yet fully wired through C++ and the browser. The proposed SQL provides a contract for the next coding cutover, but backend/frontend route changes and two-account staging tests remain necessary. Do not enable a new feature flag based only on SQL deployment.

Specific dependencies:

- Storage bucket `campusshare-resource-images` must be created through the staging dashboard as private, with 5 MiB and JPEG/PNG/WebP limits. Current live Storage configuration is unknown.
- C++ APIs must be added for transfer request reads and RPC operations, image metadata/handover management, and listing reports; only the existing borrow APIs are present.
- The UI must add listing mode and pricing fields, buyer/seller transfer controls, file preview/upload/cleanup, report flow, private handover controls, and a direct-payment disclaimer.
- Owner-only availability and transfer consistency require staging grants/policies and `update_marketplace_resource_atomic` review. Existing direct resource availability updates must be cut over before enabling transition RPCs.
- No verified moderator role exists; moderation must remain a manual owner process unless an access model is confirmed.

## Validation performed

- Read-only inspection of current Git state, backend routes, frontend API/forms, schema requirements, staging schema/policy/grant SQL, and borrowing RPC proposals.
- Static review of the newly written SQL and guide only. No SQL parser or PostgreSQL execution was used; syntax and live Supabase semantics remain unverified.
- This task's new migration/rollback/verification SQL was not applied to any database.
- No full new-feature end-to-end tests were run because the application routes and staging objects for these features are not yet implemented/deployed.

## Next steps

1. Owner reviews the proposed data model and private bucket settings.
2. Owner applies the migration only to staging and runs the read-only verification SQL.
3. Complete backend API and frontend flows against this reviewed contract, keeping all feature flags off during development.
4. Run mock tests and Release build, then two-account staging tests for authorization, concurrency, privacy, uploads, sale/donation completion, and reporting.
5. Enable each staging feature flag only after owner approval and passing staging checks.

No credentials or personal row data are included in these artifacts. No staged files were changed; the 24 pre-existing generated-file deletions remain untouched.

## Follow-up review and validation (2026-11-13)

The earlier report remains intact. This addendum records the follow-up review and the exact current limitations.

### Changes made in this follow-up

- Hardened `SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql`: non-borrow listings must have free/no borrow pricing; image metadata now blocks resource deletion until Storage objects and metadata are explicitly cleaned up; anonymous identities are rejected by private-data and image policies; private Storage paths are constrained to the user/resource folder shape; the marketplace update RPC locks the resource and refuses edits during an approved transfer or active loan; and sale/donation approval rejects other pending transfer and borrowing requests for that resource.
- Corrected the broad resource-write cutover. The migration revokes table-level `UPDATE` for `authenticated` and grants only title, description, category and resource-type updates. A column-level revoke alone would not reliably override a table-wide grant. This intentionally breaks the current direct availability PATCH until an approved backend atomic-update cutover is deployed.
- Also revokes authenticated execution of the old Task 8 `update_resource_atomic` function, which is unaware of marketplace transfer reservations. The rollback restores its authenticated grant only after removing the marketplace schema; the feature flag remains off.
- The staging migration requires the reviewed Task 8 borrow RPC and active-request unique index first. It replaces the known Task 8 `create_borrow_request(bigint,timestamptz)` definition to reject sell/donate listings, strengthens the existing INSERT policy to require an authenticated borrow-mode, available, non-owned resource and initial `pending` state, and revokes direct INSERT so the identity-derived RPC is the only create path.
- Updated the rollback to restore the known Task 8 borrow function and retain safer request checks. It deliberately does not restore direct INSERT or table-wide resource UPDATE grants. Those permissions need an owner-reviewed cutover decision; the rollback is therefore conservative and is not a byte-for-byte privilege restoration.
- Updated the guide and read-only verification SQL to disclose/test the permission cutover and borrow RPC contract.

### Validation actually run

- Frontend Node test suite: **55 passed, 0 failed**.
- Backend mock API suite: **passed** after running outside the restricted sandbox. An in-sandbox run failed because Windows denied loopback socket use (`WinError 10013`); the suite itself only uses local HTTP mocks and contains no live Supabase tests.
- Existing MSVC CMake Release target `campusshare_backend`: **build command succeeded; Ninja reported “no work to do.”** This confirms the existing target was up to date, not a fresh compilation. The Release executable timestamp was later than `BACKEND/main.cpp` at inspection time.
- No PostgreSQL parser or execution was used. The staging SQL remains unexecuted and its PostgreSQL/Supabase behavior is unverified.
- No SQL, Supabase project, Auth endpoint, Storage bucket, production, or staging database was accessed.

### Incomplete application work and blockers

- The base authenticated resource CRUD and borrow-request read/create workflow exists in the repository, with borrow status actions feature-gated. **The new sale, donation, paid borrowing, images, listing reports, and private handover experiences are not implemented in C++ or the browser.** This is not a complete full-stack feature release.
- The migration’s grant cutover means the existing availability editor will fail until the backend and UI use the reviewed atomic RPC. Do not apply the SQL first and expect the old app to continue working.
- The migration and RPCs need owner review, PostgreSQL validation in a disposable staging project, two-account authorization/concurrency testing, and an application cutover before any flag is enabled. The status/moderation identity, payment, public campus-location rules, Storage behavior, and cleanup procedure remain unverified.
- No feature flag was enabled. No commit or push occurred, and no staging command was issued. Read-only Git status shows branch `main` and the same 24 staged generated-file deletions, plus pre-existing modified/untracked user files. The Task 12 files are untracked as part of the pre-existing untracked documentation set. `git diff --check` and `git diff --cached --check` passed (Git emitted only its existing LF/CRLF conversion warnings). No other staged entries were added.

### Next safe step

Have the database owner review the migration/rollback and the explicit direct-write cutover, then validate them in a disposable staging project. Keep the current app and all RPC flags unchanged until the C++ and frontend marketplace operations, their mock tests, and two-account staging tests are implemented and reviewed.
