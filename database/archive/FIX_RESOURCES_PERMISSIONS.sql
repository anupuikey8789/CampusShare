-- ==============================================================================
-- CampusShare Staging Fix: Grant Resource Permissions & Ensure RLS Policies
-- Target Table: public.resources
-- Root Cause: Column-level INSERT grants lacked the marketplace columns
--             (listing_mode, borrow_price_kind, etc.), causing PostgREST
--             to return HTTP 403 Forbidden when creating a resource.
-- ==============================================================================

BEGIN;

-- 1. Ensure table-level permissions for authenticated users on public.resources
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.resources TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- 2. Ensure Row Level Security is active
ALTER TABLE public.resources ENABLE ROW LEVEL SECURITY;

-- 3. Re-create standard RLS policies for public.resources
DROP POLICY IF EXISTS "Read resources" ON public.resources;
CREATE POLICY "Read resources" ON public.resources
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Add own resources" ON public.resources;
CREATE POLICY "Add own resources" ON public.resources
    FOR INSERT TO authenticated
    WITH CHECK ((SELECT auth.uid()) = owner_id);

DROP POLICY IF EXISTS "Update own resources" ON public.resources;
CREATE POLICY "Update own resources" ON public.resources
    FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = owner_id)
    WITH CHECK ((SELECT auth.uid()) = owner_id);

DROP POLICY IF EXISTS "Delete own resources" ON public.resources;
CREATE POLICY "Delete own resources" ON public.resources
    FOR DELETE TO authenticated
    USING ((SELECT auth.uid()) = owner_id);

COMMIT;

-- Verification Query:
SELECT grantee, privilege_type 
FROM information_schema.role_table_grants 
WHERE table_name = 'resources' AND grantee = 'authenticated';

SELECT policyname, cmd, roles 
FROM pg_policies 
WHERE tablename = 'resources';

