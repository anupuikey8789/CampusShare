# CampusShare marketplace staging rollout guide

**Staging project only:** CampusShare-Staging, project reference `jxndjuslvccxgayoachm`. Never use production credentials. Codex did not connect to any Supabase project or run SQL. All SQL files are proposals for a human owner to review and apply manually.

## What is implemented locally

The frontend and C++ backend contain Borrow, Sell, Donate, image, private handover, price-report and moderator-review flows. Borrow and transfer state changes are designed as locked PostgreSQL RPCs; normal app calls keep the user's Bearer token and never use a service-role key. Feature flags in the committed example remain false. Mock tests do not establish that these RPCs or RLS policies exist in staging.

## Review the SQL package

Use the existing base schema and policies only after comparing them with the staging verification output. The required order is:

1. In the staging SQL Editor, run the read-only queries in `SUPABASE_STAGING_VALIDATION_NEXT.sql` and `SUPABASE_STAGING_BORROWING_RPC_VALIDATION.sql` one at a time. Confirm the four base tables, columns, policy definitions, grants and profile trigger. Stop if IDs/types/policies differ.
2. Confirm the reviewed base schema, grants and ten RLS policies are already present. If not, have the project owner review `SUPABASE_STAGING_SCHEMA_FINAL_REVIEW.sql`, `SUPABASE_STAGING_GRANTS_FINAL_REVIEW.sql`, and `SUPABASE_STAGING_SECURITY_POLICIES_FINAL_REVIEW.sql` before manually applying only the missing, approved parts. Do not rerun schema creation on existing tables.
3. Review and apply `SUPABASE_STAGING_BORROWING_RPC_MIGRATION.sql` only if the five base RPC definitions and ACLs are absent or an exact reviewed replacement is approved. This migration is a prerequisite to the marketplace extension.
4. Review `SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql`. It is a transaction-wrapped, fail-closed proposal. It adds listing fields, transfer/image/handover/report tables, constraints, policies, indexes, trigger and RPCs, and revokes direct resource/request writes where atomic RPCs take over. It requires the base borrowing RPC migration. It intentionally aborts if extension objects or function signatures already exist.
5. **Do not also run `SUPABASE_STAGING_RESOURCE_IMAGES_TABLE.sql`** when the marketplace migration created `resource_images`; it is an alternative image-table-only proposal for a different rollout path.
6. In Storage settings for this staging project, create the private `campusshare-resource-images` bucket with a 5 MiB file limit and only `image/jpeg`, `image/png`, `image/webp`. Review existing `storage.objects` policies, then apply `SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql`.
7. Run the updated `SUPABASE_STAGING_MARKETPLACE_VERIFY.sql` query by query. Inspect the complete RPC bodies, `SECURITY DEFINER`, empty `search_path`, owners, grants, all RLS expressions, Storage policies, and aggregate mismatch counts. Do not share keys, JWTs, emails or row contents.
8. If any data or Storage objects have been created, the rollback will intentionally refuse. If staging rollback is still needed before user data exists, disable all local feature flags first and read `SUPABASE_STAGING_MARKETPLACE_ROLLBACK.sql` line by line. It never drops the bucket, never restores direct-write grants and leaves the active-borrow unique index in place.

The migration is a proposal, not a claim that PostgreSQL syntax or staging behavior has been verified. A DBA should review the RPC bodies and grants in the staging SQL Editor before applying it. Apply this to staging only.

## Authentication and moderator setup

Use the staging Supabase URL and matching **publishable** key in `FRONTEND/config.local.js`, and the same project's public API key in the ignored `BACKEND/.env`. Do not use a secret/service-role key. Keep email/password Auth and the profile-creation trigger enabled. Use two fresh test accounts (Student A and Student B); complete email confirmation if the project requires it. Verify profile IDs match Auth user IDs without exporting profile rows.

No moderator account or moderator grant is created by this package. The review RPC checks the trusted JWT `app_metadata.campusshare_role = moderator`; never use editable `user_metadata` or a frontend-only flag. A project owner must provision any moderator claim through a protected Auth Admin channel and require a token refresh before testing. If no such secure process exists, leave report review unavailable; ordinary users can submit/read their own reports.

## Feature flags and local cutover

The defaults in `BACKEND/.env.example` remain disabled. Do not turn any flag on until the SQL is applied to staging, all verification queries are reviewed, and two-account authorization tests pass.

- `SUPABASE_RPC_CREATE_BORROW_REQUEST=true` is required because the migration revokes direct INSERT on `borrow_requests`.
- `SUPABASE_RPC_BORROW_STATUS=true` is required for approve/reject/return RPC status actions; the backend also requires atomic-update RPC mode for this status UI.
- `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true` is required because direct resource UPDATE is revoked.
- `SUPABASE_MARKETPLACE_ENABLED=true` enables Sell/Donate, transfer/handover/report APIs and the marketplace atomic update RPC. It is separate from the base flags.
- `SUPABASE_RESOURCE_IMAGES_ENABLED=true` enables the image API routes in this backend process only. Database RLS, Storage policies and RPC ACLs remain independently enforced.
  Image metadata writes use the authenticated `register_resource_images` and `delete_resource_image_metadata` RPCs. Registration verifies uploaded Storage objects, locks the owned resource, validates paths/order and enforces the image limit transactionally. Image deletion uses the signed-in user's Storage DELETE first; the metadata RPC now refuses deletion while the corresponding Storage object row exists. The calls are not one transaction, so a failure between them requires exact-path reconciliation.
  Image-only setup uses the dedicated resource-image table, RPC, RPC-enable, and Storage policy proposals. Do not apply the full marketplace migration solely for photos; it also grants authenticated execution on unrelated marketplace RPCs.

Set flags only in a local ignored `.env` that points exclusively to staging. Keep them false before then. Do not paste `.env` into chat. To run after staging review, from a Visual Studio Developer PowerShell:

```powershell
cd "C:\Users\Anup Uikey\CampusShare\BACKEND"
cmake --build build-msvc --config Release
.\build-msvc\campusshare_backend.exe
```

Serve `FRONTEND` at `http://localhost:5500`; verify `GET http://127.0.0.1:18080/api/health` and its feature flags. Do not replace or stop a server process unless you are managing that local process yourself.

## Two-student staging test sequence

1. Student A creates one free Borrow listing, one paid Borrow listing (fixed, per-day or per-week), one Sell listing with valid original/selling prices, a selected condition and non-future purchase year, and one Donate listing.
2. Upload up to ten JPG/PNG/WebP photos to a listing. Confirm first photo is primary, saved reordering persists after reload, and removal works. Try an unsupported format, an 11th photo, and a file over 5 MiB; each must be rejected. Verify the object bucket is private.
3. Student B browses each listing, opens details, and submits requests for the borrow/sale/donation listings. Confirm no user can request their own resource, unavailable items reject requests, and duplicate requests do not create records.
4. Verify A sees incoming requests and B sees only outgoing requests. As B, attempt to approve/complete A's requests and read private handover details before approval; both must fail. As A, approve one transfer and verify the listing becomes unavailable/reserved; competing approvals must fail. Complete a sale and donation separately; they must become permanently sold/donated and must not become borrowable or requestable again.
5. For Borrow, have A approve B's request and confirm availability becomes unavailable; confirm return as owner and availability may become available. Verify a second borrower cannot win a simultaneous approval.
6. Verify only the owner and approved/completed relevant requester can read handover locations. A third account must be denied.
7. Submit a listing report as B. A non-moderator must not see other users' reports or invoke review. Only an explicitly provisioned moderator may resolve/dismiss; verify no account is banned automatically.
8. Confirm the application displays that CampusShare does not process payments; students arrange payment directly.
9. Re-run read-only verification. Review policy ACLs and RPC definitions after testing. Do not use production accounts or data.

## Known limitations before manual staging validation

- No live staging Auth, RLS, PostgREST, Storage, two-account, concurrency or RPC test was performed by Codex.
- The migration assumes the verified base ID/ownership types and five base borrowing RPC signatures; compare actual staging definitions before applying.
- A Storage API call and a PostgREST metadata transaction cannot be made atomic together. Browser cleanup handles reported upload failure; a browser crash after upload can leave an orphan object. Periodically inspect owner-scoped Storage paths before any manual cleanup. Never delete unknown objects automatically.
- Private handover, report moderation and post-transfer image delete policies require two-account verification.
- Payment is outside version one. CampusShare stores no payment credentials and does not verify payments.
