-- CAMPUSSHARE STAGING ONLY: image metadata RPC functions.
-- No database was accessed and this file must not be run against production.
--
-- Prerequisites:
-- 1. Review/apply SUPABASE_STAGING_RESOURCE_IMAGES_TABLE.sql, or verify the
--    exact existing resource_images table contract.
-- 2. Create the private campusshare-resource-images bucket in the Staging
--    Dashboard with a 5 MiB limit and image/jpeg, image/png, image/webp.
-- 3. Review/apply SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql.
-- 4. Run SUPABASE_STAGING_RESOURCE_IMAGES_VERIFY.sql first and resolve any
--    existing table/function/policy mismatch. Do not apply duplicate packages.
--
-- This script creates functions with EXECUTE revoked from all API roles.
-- Execute access is added separately by
-- SUPABASE_STAGING_RESOURCE_IMAGES_RPC_ENABLE.sql only after review.
-- Functions use the caller's auth.uid(), lock resources before image rows,
-- and never accept client-supplied owner IDs. They are SECURITY DEFINER because
-- authenticated has SELECT-only table privileges; every operation validates
-- identity and ownership explicitly. search_path is empty and object names are
-- schema-qualified.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
BEGIN
    IF to_regclass('public.resources') IS NULL OR to_regclass('public.resource_images') IS NULL THEN
        RAISE EXCEPTION 'public.resources and public.resource_images must already exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resources' AND column_name='id' AND data_type='bigint')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resources' AND column_name='owner_id' AND data_type='uuid')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='id' AND data_type='bigint' AND is_identity='YES' AND identity_generation='ALWAYS' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='resource_id' AND data_type='bigint' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='storage_path' AND data_type='text' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='alt_text' AND data_type='text' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='sort_order' AND data_type='integer' AND is_nullable='NO')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resource_images' AND column_name='created_at' AND data_type='timestamp with time zone' AND is_nullable='NO' AND column_default IS NOT NULL) THEN
        RAISE EXCEPTION 'Image RPCs require resources(id bigint, owner_id uuid) and resource_images(id bigint, resource_id bigint, storage_path text, alt_text text, sort_order integer)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid='public.resource_images'::regclass AND c.relrowsecurity) THEN
        RAISE EXCEPTION 'RLS must be enabled on public.resource_images';
    END IF;
    IF NOT has_table_privilege('authenticated','public.resource_images','SELECT')
       OR has_table_privilege('authenticated','public.resource_images','INSERT')
       OR has_table_privilege('authenticated','public.resource_images','UPDATE')
       OR has_table_privilege('authenticated','public.resource_images','DELETE')
       OR has_table_privilege('anon','public.resource_images','SELECT') THEN
        RAISE EXCEPTION 'Expected authenticated SELECT-only and no anon access on resource_images';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.resource_images'::regclass AND c.contype='p' AND c.convalidated
          AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='id' AND NOT a.attisdropped)]::smallint[]
    ) THEN
        RAISE EXCEPTION 'Expected a validated primary key on resource_images(id)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.resource_images'::regclass AND c.contype='f' AND c.convalidated
          AND c.confrelid='public.resources'::regclass AND c.confdeltype='r'
          AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='resource_id' AND NOT a.attisdropped)]::smallint[]
          AND c.confkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.confrelid AND a.attname='id' AND NOT a.attisdropped)]::smallint[]
    ) THEN
        RAISE EXCEPTION 'Expected resource_images.resource_id -> resources.id ON DELETE RESTRICT';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.resource_images'::regclass AND c.contype='u' AND c.convalidated
          AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='storage_path' AND NOT a.attisdropped)]::smallint[]
    ) THEN
        RAISE EXCEPTION 'Expected a validated unique constraint on resource_images.storage_path';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.resource_images'::regclass AND c.conname='resource_images_resource_sort_order_key'
          AND c.contype='u' AND c.convalidated AND c.condeferrable AND c.condeferred
          AND c.conkey=ARRAY[
              (SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='resource_id' AND NOT a.attisdropped),
              (SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname='sort_order' AND NOT a.attisdropped)
          ]::smallint[]
    ) THEN
        RAISE EXCEPTION 'Expected deferrable unique (resource_id, sort_order) constraint is missing';
    END IF;
    IF EXISTS (
        SELECT 1 FROM (VALUES
            ('resource_images_storage_path_length_check'),
            ('resource_images_alt_text_length_check'),
            ('resource_images_sort_order_check')
        ) AS expected(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
                          WHERE c.conrelid='public.resource_images'::regclass
                            AND c.conname=expected.name AND c.contype='c' AND c.convalidated)
    ) THEN
        RAISE EXCEPTION 'Expected validated image path, alt-text, and sort-order checks are missing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.buckets b WHERE b.id='campusshare-resource-images' AND b.public=false AND b.file_size_limit=5242880 AND cardinality(b.allowed_mime_types)=3 AND b.allowed_mime_types @> ARRAY['image/jpeg','image/png','image/webp']::text[]) THEN
        RAISE EXCEPTION 'Create and verify the private image bucket and its size/MIME limits first';
    END IF;
    IF to_regprocedure('public.register_resource_images(bigint,jsonb)') IS NOT NULL
       OR to_regprocedure('public.delete_resource_image_metadata(bigint)') IS NOT NULL
       OR to_regprocedure('public.reorder_resource_images(bigint,bigint[])') IS NOT NULL THEN
        RAISE EXCEPTION 'An image RPC signature already exists; inspect it instead of replacing it';
    END IF;
END
$preflight$;

CREATE FUNCTION public.register_resource_images(p_resource_id bigint, p_images jsonb)
RETURNS SETOF public.resource_images
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    item jsonb;
    image_path text;
    order_value integer;
    alt_value text;
    current_owner uuid;
    current_count integer;
    seen_paths text[] := ARRAY[]::text[];
    seen_orders integer[] := ARRAY[]::integer[];
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0 OR p_images IS NULL
       OR pg_catalog.jsonb_typeof(p_images) IS DISTINCT FROM 'array'
       OR pg_catalog.jsonb_array_length(p_images) < 1 OR pg_catalog.jsonb_array_length(p_images) > 10 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid image registration';
    END IF;

    SELECT r.owner_id INTO current_owner
      FROM public.resources AS r WHERE r.id=p_resource_id FOR UPDATE;
    IF NOT FOUND OR current_owner IS DISTINCT FROM actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may add images';
    END IF;
    SELECT count(*)::integer INTO current_count
      FROM public.resource_images AS i WHERE i.resource_id=p_resource_id;
    IF current_count + pg_catalog.jsonb_array_length(p_images) > 10 THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='A resource can have no more than 10 images';
    END IF;

    FOR item IN SELECT e.value FROM pg_catalog.jsonb_array_elements(p_images) AS e(value) LOOP
        IF pg_catalog.jsonb_typeof(item) IS DISTINCT FROM 'object'
           OR EXISTS (SELECT 1 FROM pg_catalog.jsonb_object_keys(item) AS k(key)
                      WHERE k.key NOT IN ('storage_path','alt_text','sort_order'))
           OR pg_catalog.jsonb_typeof(item->'storage_path') IS DISTINCT FROM 'string'
           OR pg_catalog.jsonb_typeof(item->'sort_order') IS DISTINCT FROM 'number' THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid image metadata fields';
        END IF;
        image_path := item->>'storage_path';
        alt_value := COALESCE(item->>'alt_text','');
        IF image_path IS NULL OR char_length(image_path)>500
           OR image_path !~ ('^'||actor::text||'/'||p_resource_id::text||'/[A-Za-z0-9_.-]{1,180}$')
           OR pg_catalog.strpos(image_path,'..')>0
           OR pg_catalog.lower(image_path)!~'\.(jpg|jpeg|png|webp)$'
           OR char_length(alt_value)>200 THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Image path or alternative text is invalid';
        END IF;
        IF (item->>'sort_order')::numeric <> pg_catalog.trunc((item->>'sort_order')::numeric)
           OR (item->>'sort_order')::integer NOT BETWEEN 0 AND 9 THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Image order must be an integer from 0 to 9';
        END IF;
        order_value := (item->>'sort_order')::integer;
        IF order_value=ANY(seen_orders) OR image_path=ANY(seen_paths)
           OR EXISTS (SELECT 1 FROM public.resource_images AS i
                      WHERE i.resource_id=p_resource_id AND (i.sort_order=order_value OR i.storage_path=image_path)) THEN
            RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Image path or order already exists';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM storage.objects AS o
                       WHERE o.bucket_id='campusshare-resource-images' AND o.name=image_path) THEN
            RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Uploaded Storage object was not found';
        END IF;
        seen_orders := pg_catalog.array_append(seen_orders, order_value);
        seen_paths := pg_catalog.array_append(seen_paths, image_path);
    END LOOP;

    RETURN QUERY
      INSERT INTO public.resource_images(resource_id,storage_path,alt_text,sort_order)
      SELECT p_resource_id, e.value->>'storage_path', COALESCE(e.value->>'alt_text',''), (e.value->>'sort_order')::integer
        FROM pg_catalog.jsonb_array_elements(p_images) AS e(value)
       ORDER BY (e.value->>'sort_order')::integer
      RETURNING *;
END
$function$;

CREATE FUNCTION public.delete_resource_image_metadata(p_image_id bigint)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    resource_key bigint;
    current_owner uuid;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_image_id IS NULL OR p_image_id<=0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid image ID';
    END IF;
    SELECT i.resource_id INTO resource_key FROM public.resource_images AS i WHERE i.id=p_image_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Image metadata not found'; END IF;
    SELECT r.owner_id INTO current_owner FROM public.resources AS r WHERE r.id=resource_key FOR UPDATE;
    IF NOT FOUND OR current_owner IS DISTINCT FROM actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the current resource owner may delete images';
    END IF;
    PERFORM 1 FROM public.resource_images AS i WHERE i.id=p_image_id AND i.resource_id=resource_key FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Image metadata not found'; END IF;

    -- The C++ route removes the Storage object first with the caller's JWT.
    -- Refuse direct RPC-only metadata deletion while the object still exists,
    -- so an authenticated caller cannot orphan a live object by invoking the
    -- granted RPC without going through the backend sequence.
    IF EXISTS (SELECT 1 FROM storage.objects AS o
               WHERE o.bucket_id='campusshare-resource-images'
                 AND o.name=(SELECT i.storage_path FROM public.resource_images AS i WHERE i.id=p_image_id)) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Remove the Storage object before deleting its metadata';
    END IF;

    DELETE FROM public.resource_images AS i WHERE i.id=p_image_id;
    SET CONSTRAINTS public.resource_images_resource_sort_order_key DEFERRED;
    WITH ranked AS (
        SELECT i.id, (row_number() OVER (ORDER BY i.sort_order,i.id)-1)::integer AS new_order
          FROM public.resource_images AS i WHERE i.resource_id=resource_key
    )
    UPDATE public.resource_images AS i SET sort_order=ranked.new_order
      FROM ranked WHERE i.id=ranked.id;
    RETURN true;
END
$function$;

CREATE FUNCTION public.reorder_resource_images(p_resource_id bigint, p_image_ids bigint[])
RETURNS SETOF public.resource_images
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    total_count integer;
    distinct_count integer;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id<=0 OR p_image_ids IS NULL OR cardinality(p_image_ids)>10 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid image ordering request';
    END IF;
    PERFORM 1 FROM public.resources AS r WHERE r.id=p_resource_id AND r.owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may reorder images'; END IF;

    SELECT count(*)::integer, count(DISTINCT x)::integer INTO total_count,distinct_count
      FROM unnest(p_image_ids) AS ids(x);
    IF total_count<>distinct_count
       OR total_count<>(SELECT count(*) FROM public.resource_images AS i WHERE i.resource_id=p_resource_id)
       OR EXISTS (SELECT 1 FROM unnest(p_image_ids) AS ids(x)
                  WHERE NOT EXISTS (SELECT 1 FROM public.resource_images AS i
                                    WHERE i.id=ids.x AND i.resource_id=p_resource_id)) THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Order must include every saved image exactly once';
    END IF;
    SET CONSTRAINTS public.resource_images_resource_sort_order_key DEFERRED;
    RETURN QUERY
      UPDATE public.resource_images AS i SET sort_order=orders.ordinality::integer-1
        FROM unnest(p_image_ids) WITH ORDINALITY AS orders(id,ordinality)
       WHERE i.resource_id=p_resource_id AND i.id=orders.id
      RETURNING i.*;
END
$function$;

ALTER FUNCTION public.register_resource_images(bigint,jsonb) OWNER TO postgres;
ALTER FUNCTION public.delete_resource_image_metadata(bigint) OWNER TO postgres;
ALTER FUNCTION public.reorder_resource_images(bigint,bigint[]) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.register_resource_images(bigint,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.delete_resource_image_metadata(bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.reorder_resource_images(bigint,bigint[]) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
