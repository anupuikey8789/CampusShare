-- CAMPUSSHARE STAGING ONLY: Storage RLS policies for resource photos.
-- Do not run against production. No database was accessed by Codex.
--
-- Prerequisites:
-- 1. In the CampusShare-Staging dashboard, create the PRIVATE bucket
--    campusshare-resource-images with a 5 MiB limit and MIME types
--    image/jpeg, image/png, image/webp.
-- 2. The reviewed marketplace schema must already provide public.resources
--    (id, owner_id) and public.resource_images (resource_id, storage_path).
-- 3. The public.resources authenticated SELECT policy must permit resource
--    rows used by the frontend's browse/details views.
--
-- These policies allow authenticated students to upload only beneath their
-- own Auth UUID and a resource they own. Reads are limited to registered
-- objects attached to a readable resource. Deletion requires BOTH the
-- current resource owner and the first path folder to equal auth.uid(). In an
-- ownership transfer, the new owner cannot delete objects uploaded under the
-- former owner's folder; that transfer-cleanup case requires a separate
-- reviewed design and is not solved by this image-only package.
-- There is intentionally no UPDATE policy: uploads use upsert=false and
-- replacing a photo removes the old object, then uploads a new unique path.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM storage.buckets
        WHERE id = 'campusshare-resource-images'
          AND public = false
          AND file_size_limit = 5242880
          AND cardinality(allowed_mime_types) = 3
          AND allowed_mime_types @> ARRAY['image/jpeg','image/png','image/webp']::text[]
    ) THEN
        RAISE EXCEPTION 'Create and verify the private resource image bucket in the staging Dashboard first';
    END IF;
    IF to_regclass('public.resources') IS NULL OR to_regclass('public.resource_images') IS NULL THEN
        RAISE EXCEPTION 'Reviewed staging resource and resource_images tables are required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='resources' AND column_name='id' AND data_type='bigint')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='resources' AND column_name='owner_id' AND data_type='uuid')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='resource_images' AND column_name='resource_id' AND data_type='bigint')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='resource_images' AND column_name='storage_path' AND data_type='text') THEN
        RAISE EXCEPTION 'Expected resources(id bigint, owner_id uuid) and resource_images(resource_id bigint, storage_path text)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='storage' AND c.relname='objects' AND c.relrowsecurity
    ) THEN
        RAISE EXCEPTION 'Storage object RLS must be enabled by Supabase';
    END IF;
END
$preflight$;

-- Re-running this reviewed staging script replaces only these three named
-- CampusShare policies. Review any existing definitions before applying.
DROP POLICY IF EXISTS "CampusShare students read permitted images" ON storage.objects;
DROP POLICY IF EXISTS "CampusShare owners upload images" ON storage.objects;
DROP POLICY IF EXISTS "CampusShare owners delete images" ON storage.objects;

CREATE POLICY "CampusShare students read permitted images"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true)
    AND EXISTS (
        SELECT 1
        FROM public.resource_images AS i
        JOIN public.resources AS r ON r.id=i.resource_id
        WHERE i.storage_path=name
          AND cardinality(storage.foldername(name)) = 2
          AND r.id::text=(storage.foldername(name))[2]
          AND storage.filename(name) ~ '^[A-Za-z0-9_.-]{1,180}$'
          AND storage.filename(name) !~ '\.\.'
          AND pg_catalog.lower(storage.filename(name)) ~ '\.(jpg|jpeg|png|webp)$'
    )
);

CREATE POLICY "CampusShare owners upload images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true)
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND cardinality(storage.foldername(name)) = 2
    AND (storage.foldername(name))[2] ~ '^[1-9][0-9]*$'
    AND storage.filename(name) ~ '^[A-Za-z0-9_.-]{1,180}$'
    AND storage.filename(name) !~ '\.\.'
    AND pg_catalog.lower(storage.filename(name)) ~ '\.(jpg|jpeg|png|webp)$'
    AND EXISTS (
        SELECT 1
        FROM public.resources AS r
        WHERE r.id::text = (storage.foldername(name))[2]
          AND r.owner_id = (SELECT auth.uid())
    )
);

-- Deletion is limited to an object uploaded under the current authenticated
-- owner's UUID folder and attached to a resource they currently own.
CREATE POLICY "CampusShare owners delete images"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true)
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND cardinality(storage.foldername(name)) = 2
    AND (storage.foldername(name))[2] ~ '^[1-9][0-9]*$'
    AND storage.filename(name) ~ '^[A-Za-z0-9_.-]{1,180}$'
    AND storage.filename(name) !~ '\.\.'
    AND pg_catalog.lower(storage.filename(name)) ~ '\.(jpg|jpeg|png|webp)$'
    AND EXISTS (
        SELECT 1
        FROM public.resources AS r
        WHERE r.id::text = (storage.foldername(name))[2]
          AND r.owner_id = (SELECT auth.uid())
    )
);

COMMIT;

-- Rollback guidance (manual, staging only): after disabling image uploads and
-- verifying no application relies on these policies, drop only the three
-- policy names above. Keep the bucket and its objects until separately
-- reviewed through the Supabase Dashboard/Storage API.
