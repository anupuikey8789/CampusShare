-- ==============================================================================
-- CampusShare Staging Migration: Atomic Resource Deletion & Handover Clean-up
-- Target Schema: public
-- Resolves: 
--   1. PostgreSQL foreign key constraint violation on resource_handover_details (ON DELETE RESTRICT)
--   2. Lack of DELETE grant on resource_handover_details and resource_images for authenticated role
--   3. Strict owner-only deletion enforcement ("Only the owner can delete this resource.")
--   4. Active request protection (disallows deletion if active/pending requests exist)
--   5. History preservation (withdraws rather than hard-deletes completed/archived loans)
-- ==============================================================================

BEGIN;

-- 1. Grant DELETE privilege on resource_handover_details and resource_images to authenticated users
GRANT DELETE ON public.resource_handover_details TO authenticated;
GRANT DELETE ON public.resource_images TO authenticated;

-- 2. Ensure RLS policies allow owners to delete their own listing handover details and images
DROP POLICY IF EXISTS "Owners delete own handover details" ON public.resource_handover_details;
CREATE POLICY "Owners delete own handover details" ON public.resource_handover_details
    FOR DELETE TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL 
        AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
        AND EXISTS (
            SELECT 1 FROM public.resources r 
            WHERE r.id = resource_handover_details.resource_id 
              AND r.owner_id = (SELECT auth.uid())
        )
    );

DROP POLICY IF EXISTS "Owners delete own resource images" ON public.resource_images;
CREATE POLICY "Owners delete own resource images" ON public.resource_images
    FOR DELETE TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL 
        AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
        AND EXISTS (
            SELECT 1 FROM public.resources r 
            WHERE r.id = resource_images.resource_id 
              AND r.owner_id = (SELECT auth.uid())
        )
    );

-- 3. Adjust Foreign Key on 1-to-1 handover metadata table to CASCADE when parent resource is deleted
ALTER TABLE public.resource_handover_details
    DROP CONSTRAINT IF EXISTS resource_handover_details_resource_id_fkey,
    ADD CONSTRAINT resource_handover_details_resource_id_fkey
    FOREIGN KEY (resource_id) REFERENCES public.resources(id) ON DELETE CASCADE;

-- 4. Create atomic deletion RPC function
CREATE OR REPLACE FUNCTION public.delete_resource_atomic(p_resource_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_owner uuid;
    v_has_active_borrow boolean;
    v_has_active_transfer boolean;
    v_has_history boolean;
    v_listing_state text;
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;

    IF p_resource_id IS NULL OR p_resource_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid resource ID';
    END IF;

    SELECT r.owner_id, COALESCE(r.listing_state, 'active')
    INTO v_owner, v_listing_state
    FROM public.resources AS r
    WHERE r.id = p_resource_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;

    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the owner can delete this resource.';
    END IF;

    -- Check for active / pending borrow requests
    SELECT EXISTS (
        SELECT 1 FROM public.borrow_requests
        WHERE resource_id = p_resource_id
          AND status IN ('pending', 'approved', 'return_requested')
    ) INTO v_has_active_borrow;

    IF v_has_active_borrow THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot delete listing with active or pending borrow requests. Please complete or reject them first.';
    END IF;

    -- Check for active / pending transfer requests (buy / donate)
    SELECT EXISTS (
        SELECT 1 FROM public.resource_transfer_requests
        WHERE resource_id = p_resource_id
          AND status IN ('pending', 'approved')
    ) INTO v_has_active_transfer;

    IF v_has_active_transfer THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot delete listing with active or pending transfer requests. Please complete or reject them first.';
    END IF;

    -- Check if resource is in terminal completed state
    IF v_listing_state IN ('sold', 'donated') THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Completed sale and donation listings are permanent and cannot be deleted.';
    END IF;

    -- Check if completed transaction history exists (e.g. past returned loans or completed transfers)
    SELECT (
        EXISTS (SELECT 1 FROM public.borrow_requests WHERE resource_id = p_resource_id)
        OR EXISTS (SELECT 1 FROM public.resource_transfer_requests WHERE resource_id = p_resource_id)
    ) INTO v_has_history;

    IF v_has_history THEN
        -- Withdraw listing to preserve audit history
        UPDATE public.resources
        SET availability_status = 'unavailable',
            listing_state = 'withdrawn'
        WHERE id = p_resource_id AND owner_id = v_actor;
        RETURN true;
    END IF;

    -- Clean up dependent auxiliary records for this unrequested resource
    DELETE FROM public.resource_handover_details WHERE resource_id = p_resource_id;
    DELETE FROM public.resource_images WHERE resource_id = p_resource_id;
    DELETE FROM public.resource_listing_reports WHERE resource_id = p_resource_id;

    -- Delete resource permanently
    DELETE FROM public.resources WHERE id = p_resource_id AND owner_id = v_actor;

    RETURN true;
END;
$function$;

ALTER FUNCTION public.delete_resource_atomic(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.delete_resource_atomic(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_resource_atomic(bigint) TO authenticated;

COMMIT;
