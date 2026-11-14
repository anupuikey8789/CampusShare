-- CAMPUSSHARE STAGING ONLY. This creates only the resource image metadata
-- table; it does not create the Storage bucket or touch production.
-- Review the assumptions below against staging before execution.
--
-- Reconstructed from current C++/frontend contracts: resources.id is bigint;
-- resources.owner_id is uuid; the API reads/writes resource_images fields
-- id, resource_id, storage_path, alt_text, sort_order, created_at.
-- The standalone proposal uses bigint identity for id based on the backend/RPC contract. Verify the actual Staging type before applying; never replace an existing table.
-- sort_order 0 is the primary image. A deferrable unique 0..9 slot per resource
-- enforces the ten-image ceiling under
-- concurrent RPC writes. Authenticated receives SELECT only; metadata changes
-- use the checked RPCs.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
BEGIN
    IF to_regclass('public.resources') IS NULL THEN
        RAISE EXCEPTION 'public.resources must exist before adding resource images';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='resources'
                 AND column_name='id' AND data_type <> 'bigint') THEN
        RAISE EXCEPTION 'Expected public.resources.id bigint; inspect the actual staging schema';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='resources'
                     AND column_name='id' AND data_type='bigint')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='resources'
                        AND column_name='owner_id' AND data_type='uuid') THEN
        RAISE EXCEPTION 'Expected resources.id bigint and resources.owner_id uuid';
    END IF;
    IF to_regclass('public.resource_images') IS NOT NULL THEN
        RAISE EXCEPTION 'public.resource_images already exists; inspect it instead of replacing it';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='storage' AND c.relname='objects' AND c.relrowsecurity
    ) THEN
        RAISE EXCEPTION 'Supabase Storage object RLS must be enabled';
    END IF;
END
$preflight$;

CREATE TABLE public.resource_images (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id bigint NOT NULL
        REFERENCES public.resources(id) ON DELETE RESTRICT,
    storage_path text NOT NULL UNIQUE,
    alt_text text NOT NULL DEFAULT '',
    sort_order integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.statement_timestamp(),
    CONSTRAINT resource_images_storage_path_length_check
        CHECK (char_length(storage_path) BETWEEN 1 AND 500),
    CONSTRAINT resource_images_alt_text_length_check
        CHECK (char_length(alt_text) <= 200),
    CONSTRAINT resource_images_sort_order_check
        CHECK (sort_order BETWEEN 0 AND 9),
    CONSTRAINT resource_images_resource_sort_order_key
        UNIQUE (resource_id, sort_order) DEFERRABLE INITIALLY DEFERRED
);

ALTER TABLE public.resource_images ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public TO authenticated;
REVOKE ALL ON TABLE public.resource_images FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.resource_images TO authenticated;

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


COMMIT;

-- Rollback guidance (staging only): do not drop this table while rows or
-- Storage objects exist. Export/review image metadata and remove owned objects
-- through the Storage API first. Then review/drop the named read policy, revoke
-- table grants, and drop public.resource_images only after manual approval.
-- Leave shared USAGE on schema public unchanged during rollback.
