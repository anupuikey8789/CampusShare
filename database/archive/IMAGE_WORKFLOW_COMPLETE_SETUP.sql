-- ==============================================================================
-- CampusShare - Complete Resource Images Workflow Setup
-- Run this in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/jxndjuslvccxgayoachm/sql
-- ==============================================================================

-- 1. Create Private Storage Bucket for Resource Images (5 MiB, JPEG/PNG/WebP)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'campusshare-resource-images',
    'campusshare-resource-images',
    false,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- 2. Ensure Table public.resource_images Exists with Correct Structure
CREATE TABLE IF NOT EXISTS public.resource_images (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id bigint NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    storage_path text NOT NULL UNIQUE,
    alt_text text NOT NULL DEFAULT '',
    sort_order integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

-- Ensure Constraints on public.resource_images
DO $$
BEGIN
    -- Ensure unique storage_path
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conrelid = 'public.resource_images'::regclass AND contype = 'u'
        AND conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'public.resource_images'::regclass AND attname = 'storage_path')]::smallint[]
    ) THEN
        ALTER TABLE public.resource_images ADD CONSTRAINT resource_images_storage_path_key UNIQUE (storage_path);
    END IF;

    -- Ensure Deferrable Unique Constraint on (resource_id, sort_order)
    ALTER TABLE public.resource_images DROP CONSTRAINT IF EXISTS resource_images_resource_sort_order_key;
    ALTER TABLE public.resource_images ADD CONSTRAINT resource_images_resource_sort_order_key
        UNIQUE (resource_id, sort_order) DEFERRABLE INITIALLY DEFERRED;

    -- Ensure Checks
    ALTER TABLE public.resource_images DROP CONSTRAINT IF EXISTS resource_images_storage_path_length_check;
    ALTER TABLE public.resource_images ADD CONSTRAINT resource_images_storage_path_length_check
        CHECK (char_length(storage_path) BETWEEN 1 AND 500);

    ALTER TABLE public.resource_images DROP CONSTRAINT IF EXISTS resource_images_alt_text_length_check;
    ALTER TABLE public.resource_images ADD CONSTRAINT resource_images_alt_text_length_check
        CHECK (char_length(alt_text) <= 200);

    ALTER TABLE public.resource_images DROP CONSTRAINT IF EXISTS resource_images_sort_order_check;
    ALTER TABLE public.resource_images ADD CONSTRAINT resource_images_sort_order_check
        CHECK (sort_order BETWEEN 0 AND 9);
END $$;

-- Enable RLS and Set Grants on public.resource_images
ALTER TABLE public.resource_images ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON TABLE public.resource_images TO authenticated;

-- RLS Policy on public.resource_images
DROP POLICY IF EXISTS "CampusShare students read resource images" ON public.resource_images;
CREATE POLICY "CampusShare students read resource images"
ON public.resource_images FOR SELECT TO authenticated
USING (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND EXISTS (
        SELECT 1 FROM public.resources AS r
        WHERE r.id = public.resource_images.resource_id
    )
);

-- 3. Storage RLS Policies on storage.objects
DROP POLICY IF EXISTS "CampusShare students read permitted images" ON storage.objects;
CREATE POLICY "CampusShare students read permitted images"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND EXISTS (
        SELECT 1
        FROM public.resource_images AS i
        JOIN public.resources AS r ON r.id = i.resource_id
        WHERE i.storage_path = name
          AND cardinality(storage.foldername(name)) = 2
          AND r.id::text = (storage.foldername(name))[2]
          AND storage.filename(name) ~ '^[A-Za-z0-9_.-]{1,180}$'
          AND storage.filename(name) !~ '\.\.'
          AND pg_catalog.lower(storage.filename(name)) ~ '\.(jpg|jpeg|png|webp)$'
    )
);

DROP POLICY IF EXISTS "CampusShare owners upload images" ON storage.objects;
CREATE POLICY "CampusShare owners upload images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
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

DROP POLICY IF EXISTS "CampusShare owners delete images" ON storage.objects;
CREATE POLICY "CampusShare owners delete images"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'campusshare-resource-images'
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
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

-- 4. RPC FUNCTION 1: register_resource_images
CREATE OR REPLACE FUNCTION public.register_resource_images(
    p_resource_id bigint,
    p_images jsonb
)
RETURNS SETOF public.resource_images
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
      FROM public.resources AS r WHERE r.id = p_resource_id FOR UPDATE;
    IF NOT FOUND OR current_owner IS DISTINCT FROM actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may add images';
    END IF;
    SELECT count(*)::integer INTO current_count
      FROM public.resource_images AS i WHERE i.resource_id = p_resource_id;
    IF current_count + pg_catalog.jsonb_array_length(p_images) > 10 THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='A resource can have no more than 10 images';
    END IF;

    FOR item IN SELECT e.value FROM pg_catalog.jsonb_array_elements(p_images) AS e(value) LOOP
        IF pg_catalog.jsonb_typeof(item) IS DISTINCT FROM 'object'
           OR EXISTS (SELECT 1 FROM pg_catalog.jsonb_object_keys(item) AS k(key)
                      WHERE k.key NOT IN ('storage_path', 'alt_text', 'sort_order'))
           OR pg_catalog.jsonb_typeof(item->'storage_path') IS DISTINCT FROM 'string'
           OR pg_catalog.jsonb_typeof(item->'sort_order') IS DISTINCT FROM 'number' THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid image metadata fields';
        END IF;
        image_path := item->>'storage_path';
        alt_value := COALESCE(item->>'alt_text', '');
        IF image_path IS NULL OR char_length(image_path) > 500
           OR image_path !~ ('^' || actor::text || '/' || p_resource_id::text || '/[A-Za-z0-9_.-]{1,180}$')
           OR pg_catalog.strpos(image_path, '..') > 0
           OR pg_catalog.lower(image_path) !~ '\.(jpg|jpeg|png|webp)$'
           OR char_length(alt_value) > 200 THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Image path or alternative text is invalid';
        END IF;
        IF (item->>'sort_order')::numeric <> pg_catalog.trunc((item->>'sort_order')::numeric)
           OR (item->>'sort_order')::integer NOT BETWEEN 0 AND 9 THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Image order must be an integer from 0 to 9';
        END IF;
        order_value := (item->>'sort_order')::integer;
        IF order_value = ANY(seen_orders) OR image_path = ANY(seen_paths)
           OR EXISTS (SELECT 1 FROM public.resource_images AS i
                      WHERE i.resource_id = p_resource_id AND (i.sort_order = order_value OR i.storage_path = image_path)) THEN
            RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Image path or order already exists';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM storage.objects AS o
                       WHERE o.bucket_id = 'campusshare-resource-images' AND o.name = image_path) THEN
            RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Uploaded Storage object was not found';
        END IF;
        seen_orders := pg_catalog.array_append(seen_orders, order_value);
        seen_paths := pg_catalog.array_append(seen_paths, image_path);
    END LOOP;

    RETURN QUERY
      INSERT INTO public.resource_images (resource_id, storage_path, alt_text, sort_order)
      SELECT p_resource_id, e.value->>'storage_path', COALESCE(e.value->>'alt_text', ''), (e.value->>'sort_order')::integer
        FROM pg_catalog.jsonb_array_elements(p_images) AS e(value)
       ORDER BY (e.value->>'sort_order')::integer
      RETURNING *;
END
$function$;

-- 5. RPC FUNCTION 2: delete_resource_image_metadata
CREATE OR REPLACE FUNCTION public.delete_resource_image_metadata(
    p_image_id bigint
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    resource_key bigint;
    current_owner uuid;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_image_id IS NULL OR p_image_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid image ID';
    END IF;
    SELECT i.resource_id INTO resource_key FROM public.resource_images AS i WHERE i.id = p_image_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Image metadata not found'; END IF;
    SELECT r.owner_id INTO current_owner FROM public.resources AS r WHERE r.id = resource_key FOR UPDATE;
    IF NOT FOUND OR current_owner IS DISTINCT FROM actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the current resource owner may delete images';
    END IF;
    PERFORM 1 FROM public.resource_images AS i WHERE i.id = p_image_id AND i.resource_id = resource_key FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Image metadata not found'; END IF;

    -- The C++ route removes the Storage object first with the caller's JWT.
    -- Refuse direct RPC-only metadata deletion while the object still exists.
    IF EXISTS (SELECT 1 FROM storage.objects AS o
               WHERE o.bucket_id = 'campusshare-resource-images'
                 AND o.name = (SELECT i.storage_path FROM public.resource_images AS i WHERE i.id = p_image_id)) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Remove the Storage object before deleting its metadata';
    END IF;

    DELETE FROM public.resource_images AS i WHERE i.id = p_image_id;
    SET CONSTRAINTS public.resource_images_resource_sort_order_key DEFERRED;
    WITH ranked AS (
        SELECT i.id, (row_number() OVER (ORDER BY i.sort_order, i.id) - 1)::integer AS new_order
          FROM public.resource_images AS i WHERE i.resource_id = resource_key
    )
    UPDATE public.resource_images AS i SET sort_order = ranked.new_order
      FROM ranked WHERE i.id = ranked.id;
    RETURN true;
END
$function$;

-- 6. RPC FUNCTION 3: reorder_resource_images
CREATE OR REPLACE FUNCTION public.reorder_resource_images(
    p_resource_id bigint,
    p_image_ids bigint[]
)
RETURNS SETOF public.resource_images
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    total_count integer;
    distinct_count integer;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0 OR p_image_ids IS NULL OR cardinality(p_image_ids) > 10 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid image ordering request';
    END IF;
    PERFORM 1 FROM public.resources AS r WHERE r.id = p_resource_id AND r.owner_id = actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may reorder images'; END IF;

    SELECT count(*)::integer, count(DISTINCT x)::integer INTO total_count, distinct_count
      FROM unnest(p_image_ids) AS ids(x);
    IF total_count <> distinct_count
       OR total_count <> (SELECT count(*) FROM public.resource_images AS i WHERE i.resource_id = p_resource_id)
       OR EXISTS (SELECT 1 FROM unnest(p_image_ids) AS ids(x)
                  WHERE NOT EXISTS (SELECT 1 FROM public.resource_images AS i
                                    WHERE i.id = ids.x AND i.resource_id = p_resource_id)) THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Order must include every saved image exactly once';
    END IF;
    SET CONSTRAINTS public.resource_images_resource_sort_order_key DEFERRED;
    RETURN QUERY
      UPDATE public.resource_images AS i SET sort_order = orders.ordinality::integer - 1
        FROM unnest(p_image_ids) WITH ORDINALITY AS orders(id, ordinality)
       WHERE i.resource_id = p_resource_id AND i.id = orders.id
      RETURNING i.*;
END
$function$;

-- 7. Grant Execution Permissions to Authenticated Users
GRANT EXECUTE ON FUNCTION public.register_resource_images(bigint, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_resource_image_metadata(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reorder_resource_images(bigint, bigint[]) TO authenticated;

