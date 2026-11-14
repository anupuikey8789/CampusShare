# CampusShare Staging Resource Images: Enablement Checklist

**Project scope:** CampusShare-Staging only (`jxndjuslvccxgayoachm`). These files are proposals. No Supabase project was accessed and no SQL was executed. Never use production credentials, a service-role key, or a secret key.

## What controls the feature

`SUPABASE_RESOURCE_IMAGES_ENABLED` defaults to `false` in the backend configuration. The C++ `/api/health` response reports `features.resource_images_enabled`; the frontend uses that value to gate saved-image operations. This is an application feature flag, **not a database security boundary**. Storage policies and PostgREST function grants independently determine what a signed-in user can do directly with Supabase. Keep backend and frontend pointed at the same staging project.

The image feature uses a separate image-only setup path. Do **not** apply `SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql` just to enable photos: that larger proposal also creates Sell/Donate, transfer, handover, and report database functions. If that migration has already been applied, inspect its image table/RPC/policies with the verification SQL and do not apply duplicate image-only SQL.

## Actual request flow and required APIs

The browser sends file bytes directly to Supabase Storage with the signed-in user's Supabase JS session. Upload uses `upsert: false`; signed image URLs are requested for 600 seconds. The user access token is never replaced with a service-role credential.

The C++ backend validates the same user's token and uses its Bearer token plus the configured public API key for metadata operations:

- `GET /api/resources/{id}/images` — reads ordered metadata through PostgREST/RLS.
- `POST /api/resources/{id}/images` — validates paths, file suffixes, order and the image count, then calls `register_resource_images`.
- `POST /api/resources/{id}/images/reorder` — calls `reorder_resource_images`.
- `DELETE /api/resource-images/{id}` — verifies current ownership, removes the Storage object with the user JWT, then calls `delete_resource_image_metadata` to delete metadata and compact order.

The delete RPC now refuses to remove metadata while its Storage object still exists. This protects against direct RPC-only calls leaving an unreferenced live object; the backend's supported sequence is still Storage DELETE first, then the metadata RPC. The Storage and Postgres operations are separate services, so a failure between them still requires exact-path reconciliation.

There is intentionally no C++ byte-upload endpoint. The browser's authenticated Storage client performs the upload; Storage RLS authorizes it. The database RPCs independently enforce authenticated non-anonymous identity, owner/resource matching, path shape, an existing object, max 10 images, and serialized order changes. Resource locks serialize concurrent registration/reorder/delete operations. Storage and Postgres are separate services, so object removal and metadata deletion cannot be one transaction; a failure between them needs reconciliation.

## Staging setup sequence

Keep `SUPABASE_RESOURCE_IMAGES_ENABLED=false` throughout setup. Do not edit `BACKEND/.env` until all staging dependencies below are verified.

1. In Supabase SQL Editor, run the read-only queries in `SUPABASE_STAGING_RESOURCE_IMAGES_VERIFY.sql` one at a time. Check whether the table, bucket, named policies, and RPC signatures already exist. If anything exists, inspect it; never blindly rerun a create proposal or replace an unknown policy.
2. If absent, review and apply `SUPABASE_STAGING_RESOURCE_IMAGES_TABLE.sql`. It requires verified `resources.id bigint` and `resources.owner_id uuid`; it proposes `resource_images` columns `id bigint identity`, `resource_id bigint`, `storage_path text`, `alt_text text`, `sort_order integer`, `created_at timestamptz`, an FK, path/alt/order checks, and a deferrable unique `(resource_id, sort_order)` constraint. RLS is enabled; authenticated receives `SELECT` only, with no direct metadata write grants or write policies. Never run it if the table already exists.
3. In the **Staging** Dashboard, open **Storage → New bucket** and create `campusshare-resource-images` with **Public bucket off**, maximum file size **5 MiB (5,242,880 bytes)**, and allowed MIME types exactly `image/jpeg`, `image/png`, `image/webp`. Do not create the bucket by editing Storage catalog rows.
4. Run query 8 in `SUPABASE_STAGING_RESOURCE_IMAGES_VERIFY.sql` and inspect **every** existing `storage.objects` policy. No actual Staging policy inventory was available to Codex, so no existing broad policy can be declared absent. PostgreSQL `PERMISSIVE` policies combine with OR: any `PUBLIC`, `anon`, or `authenticated` policy for `ALL`, `SELECT`, `INSERT`, `UPDATE`, or `DELETE` may widen access if its full expression also admits this bucket. In particular, `USING (true)`, `WITH CHECK (true)`, a missing bucket condition, or an expression that admits `campusshare-resource-images` can defeat the scoped rules. Stop and resolve such policies. Then review and apply `SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql`. Reads require a matching metadata row and readable resource; upload paths must be exactly `{auth.uid()}/{resource_id}/{filename}` for an owned resource; DELETE also requires the first path folder to match `auth.uid()` and the resource to be currently owned. There is no object UPDATE policy because upload uses `upsert=false`.
5. Review and apply `SUPABASE_STAGING_RESOURCE_IMAGES_RPC.sql`. This creates exactly three `SECURITY DEFINER` RPCs with empty `search_path`, ownership checks, resource-row locks, explicit schema-qualified table references, and execution revoked from all API roles. It does not grant any image metadata DML privileges.
6. Run the validation queries again. Read each full RPC definition and confirm owner, `SECURITY DEFINER`, empty `search_path`, exact signatures/bodies, table RLS, effective grants, bucket limits, and every Storage policy. Before activation, RPC execute should be unavailable to anon/authenticated/service_role.
7. Only after the review passes, apply `SUPABASE_STAGING_RESOURCE_IMAGES_RPC_ENABLE.sql`. Its preflight temporarily creates expression probes inside one transaction, compares the actual metadata/Storage policies with the PostgreSQL-canonicalized reviewed expressions, checks exact table columns/constraints/grants and RPC security settings/body fingerprints, then removes probes before granting EXECUTE to `authenticated` only. It aborts on any additional permissive Storage policy for PUBLIC/anon/authenticated operations. That fail-closed rule may also block a safe policy for another bucket; inspect the complete inventory before deciding how to revise the reviewed allowlist. The script does not drop or rewrite real policies. Once granted, RPCs can be called directly, so their authorization checks—not the backend feature flag—are the security boundary.
8. Configure local frontend URL and publishable key, and backend URL/API key, to the **same staging project**. Do not paste config values into chat. Keep `SUPABASE_MARKETPLACE_ENABLED=false` and all borrowing/atomic RPC flags false. After the database and Storage checks and the two-account tests below pass, set only `SUPABASE_RESOURCE_IMAGES_ENABLED=true` in the ignored local backend `.env`, restart the backend, and confirm `/api/health` reports the image flag true and marketplace false.

### Do not combine setup paths

Use either:

- **Image-only path:** table proposal + dashboard bucket + Storage policy proposal + image RPC proposal + final image RPC enable script; or
- **Full marketplace path:** the reviewed marketplace migration, which contains its own image table/RPCs and also adds unrelated marketplace database operations.

Never run both create paths. The image-only RPC script deliberately aborts if those function signatures already exist.

## Manual staging acceptance tests

Use two test accounts, A (resource owner) and B (other student):

1. A creates a resource; upload 1–10 JPEG/PNG/WebP files each no larger than 5 MiB. Confirm the first chosen image has `sort_order=0`, metadata appears, the gallery displays, and images still load after refresh/sign-in.
2. A reorders images and confirms the primary image changes. A deletes an image and confirms the object and metadata disappear and remaining sort orders are compact.
3. B can view an image only if the resource's authenticated read policy allows it, but B cannot upload, reorder, or delete A's images. Try a forged path and direct RPC call as B; both must fail.
4. Try 11 images, unsupported MIME, oversize file, self/foreign resource path, duplicate active slot, and storage permission denial. Expect a safe failure with no persistent invalid metadata; verify failed-upload cleanup.
5. Verify the bucket remains private and access uses expiring signed URLs. Confirm ordinary resource CRUD, borrowing, marketplace, handover, and report flags remain disabled as configured.

## Failure/recovery limitations

- Keep the image flag false during setup. If the activation transaction fails, do not continue with partial setup; issue `ROLLBACK` in the SQL Editor if the transaction remains open, then rerun read-only verification. Probe policies and constraints are transactional and are dropped before a successful commit.
- To withdraw a successful activation, disable the app feature first and restart the local backend. After confirming no client is using the image APIs, have the Staging owner revoke `EXECUTE` from `authenticated` on the three exact image RPC signatures. Verify PUBLIC, anon, and service_role remain without EXECUTE. Drop the named Storage policies only after confirming they are no longer used. Retain the bucket, functions, table, and rows until data dependencies have been reviewed; no destructive rollback script is supplied.
- Never delete Storage objects with SQL. Remove only reviewed paths using the authenticated Storage API. Do not drop the metadata table if rows or bucket objects remain.

- A browser/network failure after Storage upload but before metadata registration may leave an unreferenced object. The UI attempts cleanup; do not run broad automatic cleanup. Reconcile only verified paths.
- If Storage deletion succeeds but the metadata RPC fails, the metadata row can point to a missing object. The API returns a safe error; retry or reconcile the exact row/path under owner review.
- C++ first verifies current resource ownership, but Storage DELETE also requires the first object-path folder to equal the caller's UUID. After a sale or donation transfers ownership, the new owner cannot delete inherited images stored below the former owner's UUID folder. The image-only package is compatible with non-transferred resources; combining it with permanent ownership transfer needs a separate reviewed cleanup design.
- Bucket MIME restrictions validate the declared content type. Browser checks are not a server-side file decoder; stronger content inspection would require a trusted image processing service.
- Signed image URLs expire after 10 minutes. Reloading/reopening fetches fresh signed URLs.
- None of these scripts prove that Staging currently has the expected schema or policies. Only the owner can run the manual staging checks.
