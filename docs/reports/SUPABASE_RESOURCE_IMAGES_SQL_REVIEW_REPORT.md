# CampusShare Resource Image SQL Package Review

## Scope and safety

Reviewed the five staging-only image SQL files, their setup guide, and the current C++ and frontend image contracts. No Supabase project was accessed, no SQL was executed, no database settings or feature flags were changed, and Git staging was not changed. No live `storage.objects` policy inventory was available to this review.

## Corrections made

1. **Verification query 3 alias:** `SUPABASE_STAGING_RESOURCE_IMAGES_VERIFY.sql` uses an explicit `x` alias for `pg_index` and refers to `x.indrelid`, `x.indexrelid`, `x.indisunique`, and `x.indisvalid`. The missing-alias error is corrected.
2. **Storage DELETE path ownership:** `SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql` requires the first folder returned by `storage.foldername(name)` to equal `(SELECT auth.uid())::text`, as well as the exact two-folder path, safe filename, allowed extension, target bucket, and current resource ownership.
3. **Broad policy discovery:** verification query 8 lists every policy on `storage.objects`, including full `USING` and `WITH CHECK` expressions and roles/commands. The setup guide explains that permissive policies combine with OR and calls out broad `true`, missing bucket scope, and otherwise bucket-admitting expressions. The activation preflight fails closed on additional permissive policies applying to PUBLIC, anon, or authenticated. This repository contains the three intended CampusShare policy definitions; it cannot establish what other policies currently exist in Staging.
4. **RPC activation preflight:** `SUPABASE_STAGING_RESOURCE_IMAGES_RPC_ENABLE.sql` compares actual policy definitions (role, command, permissive mode, and full expression) with temporary PostgreSQL-canonicalized probes. It also checks table columns, grants, constraints, bucket settings, RLS, function owner/language/security/search path, argument/result contracts, ACLs, and exact reviewed function-body fingerprints. It does not rely only on policy names or source substrings. The fingerprints are drift checks; they are not a proof of SQL semantics or a substitute for human review.
5. **Metadata delete consistency:** `SUPABASE_STAGING_RESOURCE_IMAGES_RPC.sql` now refuses metadata deletion while the Storage object still exists. The backend sequence deletes the object using the signed-in user's token before calling the metadata RPC. The enable script's fingerprint for this reviewed function was updated. Storage and database deletion remain separate operations; failures between them still need reconciliation.
6. **Rollback/failure handling:** setup instructions keep the image feature disabled during setup, describe transaction rollback after a failed SQL Editor run, and require disabling the app flag and revoking exact RPC grants before withdrawing a successful activation. They retain the bucket/data and avoid broad or destructive cleanup.

## Contract cross-check

The image table proposal defines exactly six columns: `id bigint` identity/PK, `resource_id bigint` FK to `resources.id` with `ON DELETE RESTRICT`, `storage_path text`, `alt_text text`, `sort_order integer`, and `created_at timestamptz`. It constrains path length, alt-text length, order 0–9, unique storage path, and deferrable unique `(resource_id, sort_order)`.

RPC signatures agree across the SQL and C++ calls:

- `register_resource_images(bigint, jsonb)` with `p_resource_id`, `p_images`, returning rows of `public.resource_images`.
- `delete_resource_image_metadata(bigint)` with `p_image_id`, returning `boolean`.
- `reorder_resource_images(bigint, bigint[])` with `p_resource_id`, `p_image_ids`, returning rows of `public.resource_images`.

The frontend uploads bytes directly to the private `campusshare-resource-images` bucket using its authenticated Supabase session and `upsert: false`. It uses `{auth.uid()}/{resource_id}/{filename}` paths, JPEG/PNG/WebP, at most 10 images per resource and 5 MiB each. The C++ backend verifies the JWT, validates that path and metadata, uses that user's JWT for PostgREST/RPC and Storage deletion, and returns ordered metadata. Storage deletion and metadata deletion are non-atomic; the setup guide documents recovery. The user-facing feature flag remains separate and disabled until manual staging review.

## Security findings and remaining limits

- The local SQL package cannot show whether Staging has a broad `storage.objects` policy. Before applying policies or the activation script, the project owner must inspect query 8's full inventory and resolve any permissive policy that could admit this bucket. The activation script intentionally aborts on any additional permissive policy for the relevant roles, even if it might be safely scoped to another bucket; that requires an explicit review before changing the preflight.
- Image paths are tied to the uploading user's UUID. After a permanent resource ownership transfer, the new owner cannot delete inherited images stored in the former owner's UUID folder under this policy. The setup guide records this marketplace integration blocker; a separate reviewed transfer/cleanup design is required.
- The bucket MIME restriction and browser validation inspect declared MIME type, not decoded file bytes. Strong content inspection is not provided by this package.
- SQL has not been parsed or executed by PostgreSQL. Static review cannot establish syntax acceptance, actual grants/RLS behavior, trigger behavior, or live Storage behavior.

## Files in the corrected package

- `SUPABASE_STAGING_RESOURCE_IMAGES_TABLE.sql`
- `SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql`
- `SUPABASE_STAGING_RESOURCE_IMAGES_RPC.sql`
- `SUPABASE_STAGING_RESOURCE_IMAGES_RPC_ENABLE.sql`
- `SUPABASE_STAGING_RESOURCE_IMAGES_VERIFY.sql`
- `SUPABASE_STAGING_RESOURCE_IMAGES_SETUP.md`

The SQL files are complete standalone files in the repository; the setup guide specifies the image-only versus full-marketplace setup paths and warns not to apply both.

## Validation performed

- Compared the three declared function signatures and JSON parameter names with the C++ RPC calls.
- Compared path shape, bucket name, allowed extensions, metadata fields, ordering bounds, image cap, MIME/size settings, and the Storage-delete-before-metadata-delete sequence across SQL, C++, and frontend.
- Confirmed the RPC activation check fingerprints match the locally reviewed function definitions after the metadata-delete guard change.
- Confirmed query 8 returns policy definitions only, not object names or row data.
- Ran whitespace/diff checks and checked Git status; no SQL execution, build, or live integration test was performed because application code was not changed.

## Git and completion status

The pre-existing staged generated-file deletions were left untouched; no stage/unstage/reset/commit/push operation was performed. All pre-existing unstaged and untracked user work was preserved. The current repository status should be rechecked locally before applying any staging SQL. No SQL is approved for production use; these proposals are staging-only and require owner review and actual Staging validation.
