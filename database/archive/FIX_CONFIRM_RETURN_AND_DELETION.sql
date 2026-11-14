-- ============================================================================
-- CAMPUSSHARE — UNIFIED FIX: CONFIRM RETURN AND DELETE RESOURCE ATOMIC
-- ============================================================================
-- Run this in the Supabase Dashboard SQL Editor (https://supabase.com/dashboard/project/jxndjuslvccxgayoachm/sql)
--
-- This script fixes both operations cleanly:
--   1. Fixes return_borrowed_resource RPC (resolves unassigned variable bug and conversation dependencies)
--   2. Installs delete_resource_atomic RPC (enforces owner-only delete, cancels pending requests,
--      protects active loans, and preserves audit/transaction history)
--   3. Sets ON DELETE CASCADE on resource_handover_details so deletions don't fail with FK RESTRICT
--   4. Grants necessary table permissions (DELETE on handover/images, UPDATE on borrow_requests)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART 1: FIX CONFIRM RETURN (return_borrowed_resource RPC)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.return_borrowed_resource(p_request_id bigint)
RETURNS SETOF public.borrow_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_resource_id bigint;
    v_owner uuid;
    v_request public.borrow_requests%ROWTYPE;
BEGIN
    -- 1. Authentication check
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_request_id IS NULL OR p_request_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid request ID';
    END IF;

    -- 2. Fetch borrow request
    SELECT b.resource_id INTO v_resource_id
    FROM public.borrow_requests AS b WHERE b.id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found';
    END IF;

    -- 3. Lock resource and verify ownership
    SELECT r.owner_id INTO v_owner
    FROM public.resources AS r WHERE r.id = v_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;

    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may confirm return';
    END IF;

    -- 4. Lock borrow request and verify status
    SELECT b.* INTO v_request
    FROM public.borrow_requests AS b WHERE b.id = p_request_id FOR UPDATE;
    IF NOT FOUND OR v_request.resource_id <> v_resource_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request changed; retry after refresh';
    END IF;

    IF v_request.status = 'returned' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='This request has already been returned';
    END IF;

    IF v_request.status NOT IN ('approved', 'return_requested') THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not active';
    END IF;

    -- 5. Mark resource as available again
    UPDATE public.resources
    SET availability_status = 'available'
    WHERE id = v_resource_id AND owner_id = v_actor;

    -- 6. Mark borrow request as returned with current timestamp
    RETURN QUERY
    UPDATE public.borrow_requests AS b
    SET status = 'returned', returned_at = clock_timestamp()
    WHERE b.id = p_request_id AND b.status IN ('approved', 'return_requested')
    RETURNING b.*;
END;
$function$;

ALTER FUNCTION public.return_borrowed_resource(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;

-- ----------------------------------------------------------------------------
-- PART 2: PERMISSIONS & CONSTRAINTS FOR RESOURCE DELETION
-- ----------------------------------------------------------------------------
-- 1. Grant DELETE privilege on auxiliary tables to authenticated users
GRANT DELETE ON public.resource_handover_details TO authenticated;
GRANT DELETE ON public.resource_images TO authenticated;
GRANT UPDATE (status, returned_at) ON public.borrow_requests TO authenticated;

-- 2. Ensure RLS policies allow owners to delete their own auxiliary rows
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

-- 3. Update FK constraint on resource_handover_details to ON DELETE CASCADE
ALTER TABLE public.resource_handover_details
    DROP CONSTRAINT IF EXISTS resource_handover_details_resource_id_fkey,
    ADD CONSTRAINT resource_handover_details_resource_id_fkey
        FOREIGN KEY (resource_id)
        REFERENCES public.resources(id)
        ON DELETE CASCADE;

-- ----------------------------------------------------------------------------
-- PART 3: ATOMIC DELETE RPC (delete_resource_atomic)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_resource_atomic(p_resource_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_owner uuid;
    v_listing_state text;
    v_has_active_borrow boolean;
    v_has_history boolean;
BEGIN
    -- 1. Authentication check
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;

    IF p_resource_id IS NULL OR p_resource_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid resource ID';
    END IF;

    -- 2. Verify resource exists and lock it
    SELECT r.owner_id, COALESCE(r.listing_state, 'active')
    INTO v_owner, v_listing_state
    FROM public.resources AS r
    WHERE r.id = p_resource_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;

    -- 3. Strict owner-only authorization check
    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the owner can delete this resource.';
    END IF;

    -- 4. Check for ACTIVE ongoing loans (approved or return_requested)
    SELECT EXISTS (
        SELECT 1 FROM public.borrow_requests
        WHERE resource_id = p_resource_id
          AND status IN ('approved', 'return_requested')
    ) INTO v_has_active_borrow;

    IF v_has_active_borrow THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='This resource is currently on an active loan. Please confirm its return before deleting.';
    END IF;

    -- 5. Automatically cancel any harmless pending borrow or transfer requests
    UPDATE public.borrow_requests
    SET status = 'cancelled'
    WHERE resource_id = p_resource_id AND status = 'pending';

    UPDATE public.resource_transfer_requests
    SET status = 'cancelled'
    WHERE resource_id = p_resource_id AND status = 'pending';

    -- 6. Check if resource has completed past transactions that must be preserved
    IF v_listing_state IN ('sold', 'donated') THEN
        UPDATE public.resources
        SET availability_status = 'unavailable',
            listing_state = 'withdrawn'
        WHERE id = p_resource_id;
        RETURN;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.borrow_requests
        WHERE resource_id = p_resource_id AND status = 'returned'
    ) INTO v_has_history;

    IF v_has_history THEN
        UPDATE public.resources
        SET availability_status = 'unavailable',
            listing_state = 'withdrawn'
        WHERE id = p_resource_id;
        RETURN;
    END IF;

    -- 7. Unencumbered listing: delete auxiliary records and hard-delete resource
    DELETE FROM public.resource_handover_details WHERE resource_id = p_resource_id;
    DELETE FROM public.resource_images WHERE resource_id = p_resource_id;
    DELETE FROM public.resources WHERE id = p_resource_id;
END;
$function$;

ALTER FUNCTION public.delete_resource_atomic(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.delete_resource_atomic(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_resource_atomic(bigint) TO authenticated;
