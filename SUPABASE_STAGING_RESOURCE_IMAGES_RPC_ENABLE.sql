-- CAMPUSSHARE STAGING ONLY. Grant image RPC execution only after reviewing
-- the image table, private bucket, and exact Storage object policies.
-- This does not grant table INSERT/UPDATE/DELETE and must not be run on prod.
-- Apply only after SUPABASE_STAGING_RESOURCE_IMAGES_RPC.sql and read-only
-- verification. This enables authenticated direct RPC calls; the C++ feature
-- flag is not a database security boundary.

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

-- These checks run in this transaction. Probe policies/constraints below are
-- created only to let PostgreSQL canonicalize the expected expressions; they
-- are removed before COMMIT and are never visible to other transactions.
-- RPC body fingerprints below bind activation to the complete locally
-- reviewed function definitions (including auth.uid()/anonymous rejection,
-- current-owner checks, resource row locks, exact bucket/path validation,
-- image-count/order limits, and Storage-object existence/removal sequencing).
-- This is a drift check, not a substitute for reviewing the source or a
-- cryptographic authorization boundary; the functions themselves enforce it.
DO $preflight_relations$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Run the reviewed activation proposal as postgres in Staging';
    END IF;
    IF to_regclass('public.resources') IS NULL
       OR to_regclass('public.resource_images') IS NULL
       OR to_regclass('storage.objects') IS NULL THEN
        RAISE EXCEPTION 'Reviewed resources, resource_images, and Storage objects relations are required';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c
               WHERE c.oid IN ('public.resource_images'::regclass,'storage.objects'::regclass)
                 AND NOT c.relrowsecurity) THEN
        RAISE EXCEPTION 'RLS must be enabled on resource_images and storage.objects';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.buckets b
                   WHERE b.id='campusshare-resource-images' AND b.public=false
                     AND b.file_size_limit=5242880 AND cardinality(b.allowed_mime_types)=3
                     AND b.allowed_mime_types @> ARRAY['image/jpeg','image/png','image/webp']::text[]) THEN
        RAISE EXCEPTION 'Private image bucket settings must match the reviewed 5 MiB JPEG/PNG/WebP contract';
    END IF;
    IF to_regprocedure('public.register_resource_images(bigint,jsonb)') IS NULL
       OR to_regprocedure('public.delete_resource_image_metadata(bigint)') IS NULL
       OR to_regprocedure('public.reorder_resource_images(bigint,bigint[])') IS NULL THEN
        RAISE EXCEPTION 'All three exact image RPC signatures must exist before activation';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
               WHERE p.schemaname='public' AND p.tablename='resource_images'
                 AND p.policyname='__cs_image_probe_metadata_select')
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
                  WHERE p.schemaname='storage' AND p.tablename='objects'
                    AND p.policyname LIKE '__cs_image_probe_%')
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
                  WHERE c.conrelid='public.resource_images'::regclass
                    AND c.conname LIKE '__cs_image_probe_%') THEN
        RAISE EXCEPTION 'A temporary preflight probe name already exists; inspect it before proceeding';
    END IF;
END
$preflight_relations$;

CREATE POLICY "__cs_image_probe_metadata_select"
ON public.resource_images FOR SELECT TO authenticated
USING (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND EXISTS (SELECT 1 FROM public.resources AS r
                WHERE r.id=public.resource_images.resource_id)
);
CREATE POLICY "__cs_image_probe_storage_select"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id='campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true)
    AND EXISTS (SELECT 1 FROM public.resource_images AS i
                JOIN public.resources AS r ON r.id=i.resource_id
                WHERE i.storage_path=name
                  AND cardinality(storage.foldername(name))=2
                  AND r.id::text=(storage.foldername(name))[2]
                  AND storage.filename(name) ~ '^[A-Za-z0-9_.-]{1,180}$'
                  AND storage.filename(name) !~ '\.\.'
                  AND pg_catalog.lower(storage.filename(name)) ~ '\.(jpg|jpeg|png|webp)$')
);
CREATE POLICY "__cs_image_probe_storage_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id='campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true)
    AND (storage.foldername(name))[1]=(SELECT auth.uid())::text
    AND cardinality(storage.foldername(name))=2
    AND (storage.foldername(name))[2] ~ '^[1-9][0-9]*$'
    AND storage.filename(name) ~ '^[A-Za-z0-9_.-]{1,180}$'
    AND storage.filename(name) !~ '\.\.'
    AND pg_catalog.lower(storage.filename(name)) ~ '\.(jpg|jpeg|png|webp)$'
    AND EXISTS (SELECT 1 FROM public.resources AS r
                WHERE r.id::text=(storage.foldername(name))[2]
                  AND r.owner_id=(SELECT auth.uid()))
);
CREATE POLICY "__cs_image_probe_storage_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id='campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true)
    AND (storage.foldername(name))[1]=(SELECT auth.uid())::text
    AND cardinality(storage.foldername(name))=2
    AND (storage.foldername(name))[2] ~ '^[1-9][0-9]*$'
    AND storage.filename(name) ~ '^[A-Za-z0-9_.-]{1,180}$'
    AND storage.filename(name) !~ '\.\.'
    AND pg_catalog.lower(storage.filename(name)) ~ '\.(jpg|jpeg|png|webp)$'
    AND EXISTS (SELECT 1 FROM public.resources AS r
                WHERE r.id::text=(storage.foldername(name))[2]
                  AND r.owner_id=(SELECT auth.uid()))
);

ALTER TABLE public.resource_images
    ADD CONSTRAINT "__cs_image_probe_path_length" CHECK (char_length(storage_path) BETWEEN 1 AND 500) NOT VALID,
    ADD CONSTRAINT "__cs_image_probe_alt_length" CHECK (char_length(alt_text) <= 200) NOT VALID,
    ADD CONSTRAINT "__cs_image_probe_order_range" CHECK (sort_order BETWEEN 0 AND 9) NOT VALID;

DO $preflight_contract$
DECLARE
    fn record;
    expected_definition text;
    actual_definition text;
    check_name text;
BEGIN
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='public' AND table_name='resource_images') <> 6
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='id' AND data_type='bigint' AND is_nullable='NO' AND is_identity='YES' AND identity_generation='ALWAYS')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='resource_id' AND data_type='bigint' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='storage_path' AND data_type='text' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='alt_text' AND data_type='text' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='sort_order' AND data_type='integer' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='created_at' AND data_type='timestamp with time zone' AND is_nullable='NO' AND column_default IS NOT NULL) THEN
        RAISE EXCEPTION 'resource_images columns differ from the reviewed six-column contract';
    END IF;
    IF NOT has_table_privilege('authenticated','public.resource_images','SELECT')
       OR has_table_privilege('authenticated','public.resource_images','INSERT')
       OR has_table_privilege('authenticated','public.resource_images','UPDATE')
       OR has_table_privilege('authenticated','public.resource_images','DELETE')
       OR has_table_privilege('anon','public.resource_images','SELECT') THEN
        RAISE EXCEPTION 'Effective table grants must be authenticated SELECT-only with no anon SELECT';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
                   WHERE c.conrelid='public.resource_images'::regclass AND c.contype='p' AND c.convalidated
                     AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='id' AND NOT a.attisdropped)]::smallint[])
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
                   WHERE c.conrelid='public.resource_images'::regclass AND c.contype='f' AND c.convalidated
                     AND c.confrelid='public.resources'::regclass AND c.confdeltype='r'
                     AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='resource_id' AND NOT a.attisdropped)]::smallint[]
                     AND c.confkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.confrelid AND a.attname='id' AND NOT a.attisdropped)]::smallint[])
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
                   WHERE c.conrelid='public.resource_images'::regclass AND c.contype='u' AND c.convalidated
                     AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='storage_path' AND NOT a.attisdropped)]::smallint[])
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
                   WHERE c.conrelid='public.resource_images'::regclass AND c.conname='resource_images_resource_sort_order_key'
                     AND c.contype='u' AND c.convalidated AND c.condeferrable AND c.condeferred
                     AND c.conkey=ARRAY[
                       (SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='resource_id' AND NOT a.attisdropped),
                       (SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='sort_order' AND NOT a.attisdropped)
                     ]::smallint[]) THEN
        RAISE EXCEPTION 'Primary key, ON DELETE RESTRICT foreign key, or exact unique constraints differ from the image contract';
    END IF;

    FOREACH check_name IN ARRAY ARRAY[
        'resource_images_storage_path_length_check',
        'resource_images_alt_text_length_check',
        'resource_images_sort_order_check'
    ] LOOP
        SELECT pg_catalog.pg_get_constraintdef(c.oid,true) INTO actual_definition
        FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.resource_images'::regclass AND c.conname=check_name
          AND c.contype='c' AND c.convalidated;
        IF actual_definition IS NULL THEN RAISE EXCEPTION 'Required validated check constraint % is missing',check_name; END IF;
        SELECT regexp_replace(pg_catalog.pg_get_constraintdef(c.oid,true),'\s+NOT VALID$','') INTO expected_definition
        FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.resource_images'::regclass
          AND c.conname=CASE check_name
              WHEN 'resource_images_storage_path_length_check' THEN '__cs_image_probe_path_length'
              WHEN 'resource_images_alt_text_length_check' THEN '__cs_image_probe_alt_length'
              ELSE '__cs_image_probe_order_range' END;
        IF actual_definition IS DISTINCT FROM expected_definition THEN
            RAISE EXCEPTION 'Check constraint % does not match the reviewed expression',check_name;
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p JOIN pg_catalog.pg_policies q
                   ON q.schemaname='public' AND q.tablename='resource_images' AND q.policyname='__cs_image_probe_metadata_select'
                   WHERE p.schemaname='public' AND p.tablename='resource_images' AND p.policyname='CampusShare students read resource images'
                     AND p.permissive=q.permissive AND p.roles=q.roles AND p.cmd=q.cmd
                     AND p.qual IS NOT DISTINCT FROM q.qual AND p.with_check IS NOT DISTINCT FROM q.with_check) THEN
        RAISE EXCEPTION 'Metadata SELECT policy does not exactly match the reviewed identity/read expression';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
               WHERE p.schemaname='public' AND p.tablename='resource_images'
                 AND p.policyname<>'CampusShare students read resource images'
                 AND p.permissive='PERMISSIVE' AND p.cmd IN ('INSERT','UPDATE','DELETE','ALL')
                 AND p.roles && ARRAY['public','anon','authenticated']::name[]) THEN
        RAISE EXCEPTION 'A permissive direct metadata-write policy exists; inspect and remove/resolve it before RPC activation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p JOIN pg_catalog.pg_policies q
                   ON q.schemaname='storage' AND q.tablename='objects' AND q.policyname='__cs_image_probe_storage_select'
                   WHERE p.schemaname='storage' AND p.tablename='objects' AND p.policyname='CampusShare students read permitted images'
                     AND p.permissive=q.permissive AND p.roles=q.roles AND p.cmd=q.cmd
                     AND p.qual IS NOT DISTINCT FROM q.qual AND p.with_check IS NOT DISTINCT FROM q.with_check)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p JOIN pg_catalog.pg_policies q
                   ON q.schemaname='storage' AND q.tablename='objects' AND q.policyname='__cs_image_probe_storage_insert'
                   WHERE p.schemaname='storage' AND p.tablename='objects' AND p.policyname='CampusShare owners upload images'
                     AND p.permissive=q.permissive AND p.roles=q.roles AND p.cmd=q.cmd
                     AND p.qual IS NOT DISTINCT FROM q.qual AND p.with_check IS NOT DISTINCT FROM q.with_check)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p JOIN pg_catalog.pg_policies q
                   ON q.schemaname='storage' AND q.tablename='objects' AND q.policyname='__cs_image_probe_storage_delete'
                   WHERE p.schemaname='storage' AND p.tablename='objects' AND p.policyname='CampusShare owners delete images'
                     AND p.permissive=q.permissive AND p.roles=q.roles AND p.cmd=q.cmd
                     AND p.qual IS NOT DISTINCT FROM q.qual AND p.with_check IS NOT DISTINCT FROM q.with_check) THEN
        RAISE EXCEPTION 'A named Storage policy does not exactly match the reviewed role, command, permissive mode, and full expression';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
               WHERE p.schemaname='storage' AND p.tablename='objects'
                 AND p.policyname NOT IN ('CampusShare students read permitted images','CampusShare owners upload images','CampusShare owners delete images',
                                          '__cs_image_probe_storage_select','__cs_image_probe_storage_insert','__cs_image_probe_storage_delete')
                 AND p.permissive='PERMISSIVE' AND p.cmd IN ('ALL','SELECT','INSERT','UPDATE','DELETE')
                 AND p.roles && ARRAY['public','anon','authenticated']::name[]) THEN
        RAISE EXCEPTION 'An additional permissive storage.objects policy exists for PUBLIC/anon/authenticated. Inspect the full policy inventory; any such policy blocks activation until explicitly resolved.';
    END IF;

    FOR fn IN
        SELECT p.oid,p.proname,p.prosrc,p.proconfig,p.prosecdef,p.proowner,p.proargnames,
               p.prorettype,p.proretset,l.lanname,
               owner.rolname AS owner_name
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        JOIN pg_catalog.pg_roles owner ON owner.oid=p.proowner
        WHERE p.oid IN (to_regprocedure('public.register_resource_images(bigint,jsonb)'),
                        to_regprocedure('public.delete_resource_image_metadata(bigint)'),
                        to_regprocedure('public.reorder_resource_images(bigint,bigint[])'))
    LOOP
        IF fn.owner_name<>'postgres' OR NOT fn.prosecdef OR fn.lanname<>'plpgsql'
           OR fn.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[] THEN
            RAISE EXCEPTION 'An image RPC must be postgres-owned PL/pgSQL SECURITY DEFINER with only an empty search_path';
        END IF;
        IF (fn.proname='register_resource_images' AND
              (fn.proargnames IS DISTINCT FROM ARRAY['p_resource_id','p_images']::text[]
               OR fn.prorettype<>'public.resource_images'::regclass OR NOT fn.proretset))
           OR (fn.proname='delete_resource_image_metadata' AND
              (fn.proargnames IS DISTINCT FROM ARRAY['p_image_id']::text[]
               OR fn.prorettype<>'boolean'::regtype OR fn.proretset))
           OR (fn.proname='reorder_resource_images' AND
              (fn.proargnames IS DISTINCT FROM ARRAY['p_resource_id','p_image_ids']::text[]
               OR fn.prorettype<>'public.resource_images'::regclass OR NOT fn.proretset)) THEN
            RAISE EXCEPTION 'An image RPC argument name or result contract differs from the backend/API contract';
        END IF;
        IF (fn.proname='register_resource_images' AND pg_catalog.md5(replace(fn.prosrc,chr(13),''))<>'7d1bad6190f543a7f69fb67dafd1e92a')
           OR (fn.proname='delete_resource_image_metadata' AND pg_catalog.md5(replace(fn.prosrc,chr(13),''))<>'afe0599a1cd0c7885cd2b24463a2bb8c')
           OR (fn.proname='reorder_resource_images' AND pg_catalog.md5(replace(fn.prosrc,chr(13),''))<>'272fb356c986ea2946178a11cfb0a700') THEN
            RAISE EXCEPTION 'An image RPC body differs from the locally reviewed definition; review source and update its fingerprint only after approval';
        END IF;
        IF has_function_privilege('anon',fn.oid,'EXECUTE')
           OR has_function_privilege('service_role',fn.oid,'EXECUTE')
           OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
                    (SELECT p.proacl FROM pg_catalog.pg_proc p WHERE p.oid=fn.oid),
                    pg_catalog.acldefault('f',fn.proowner))) AS acl
                      WHERE acl.privilege_type='EXECUTE' AND acl.grantee=0) THEN
            RAISE EXCEPTION 'An image RPC has PUBLIC, anon, or service_role EXECUTE access';
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM pg_catalog.pg_proc p
        WHERE p.oid IN (to_regprocedure('public.register_resource_images(bigint,jsonb)'),
                        to_regprocedure('public.delete_resource_image_metadata(bigint)'),
                        to_regprocedure('public.reorder_resource_images(bigint,bigint[])'))) <> 3 THEN
        RAISE EXCEPTION 'One or more exact image RPC signatures are missing';
    END IF;
END
$preflight_contract$;

DROP POLICY "__cs_image_probe_metadata_select" ON public.resource_images;
DROP POLICY "__cs_image_probe_storage_select" ON storage.objects;
DROP POLICY "__cs_image_probe_storage_insert" ON storage.objects;
DROP POLICY "__cs_image_probe_storage_delete" ON storage.objects;
ALTER TABLE public.resource_images
    DROP CONSTRAINT "__cs_image_probe_path_length",
    DROP CONSTRAINT "__cs_image_probe_alt_length",
    DROP CONSTRAINT "__cs_image_probe_order_range";

GRANT EXECUTE ON FUNCTION public.register_resource_images(bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_resource_image_metadata(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reorder_resource_images(bigint,bigint[]) TO authenticated;

COMMIT;
