-- ==============================================================================
-- CampusShare - Complete Borrowing Workflow Database Setup
-- Run this in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/jxndjuslvccxgayoachm/sql
-- ==============================================================================

-- 1. Ensure Table Constraints & Partial Unique Index
CREATE UNIQUE INDEX IF NOT EXISTS one_active_request_per_borrower_resource
ON public.borrow_requests (borrower_id, resource_id)
WHERE status IN ('pending', 'approved');

-- 2. CREATE FUNCTION: create_borrow_request
CREATE OR REPLACE FUNCTION public.create_borrow_request(
    p_resource_id bigint,
    p_due_at timestamptz DEFAULT NULL
)
RETURNS SETOF public.borrow_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_owner uuid;
    v_availability text;
    v_requested_at timestamptz := pg_catalog.statement_timestamp();
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid resource ID';
    END IF;

    SELECT r.owner_id, r.availability_status INTO v_owner, v_availability
    FROM public.resources AS r
    WHERE r.id = p_resource_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    IF v_owner = v_actor THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot request own resource';
    END IF;
    IF v_availability IS DISTINCT FROM 'available' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resource unavailable';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.borrow_requests AS b
        WHERE b.borrower_id = v_actor
          AND b.resource_id = p_resource_id
          AND b.status IN ('pending', 'approved')
    ) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Active request exists';
    END IF;
    IF p_due_at IS NOT NULL AND p_due_at < v_requested_at THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='due_at precedes request time';
    END IF;

    RETURN QUERY
    INSERT INTO public.borrow_requests
        (resource_id, borrower_id, status, requested_at, due_at, returned_at)
    VALUES
        (p_resource_id, v_actor, 'pending', v_requested_at, p_due_at, NULL)
    RETURNING *;
END;
$function$;

-- 3. CREATE FUNCTION: approve_borrow_request
CREATE OR REPLACE FUNCTION public.approve_borrow_request(
    p_request_id bigint,
    p_due_at timestamptz DEFAULT NULL
)
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
    v_availability text;
    v_request public.borrow_requests%ROWTYPE;
    v_next_due_at timestamptz;
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_request_id IS NULL OR p_request_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid request ID';
    END IF;

    SELECT b.resource_id INTO v_resource_id
    FROM public.borrow_requests AS b WHERE b.id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found';
    END IF;
    SELECT r.owner_id, r.availability_status INTO v_owner, v_availability
    FROM public.resources AS r WHERE r.id = v_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    SELECT b.* INTO v_request
    FROM public.borrow_requests AS b WHERE b.id = p_request_id FOR UPDATE;
    IF NOT FOUND OR v_request.resource_id <> v_resource_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request changed; retry after refresh';
    END IF;
    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may change this request';
    END IF;
    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not pending';
    END IF;
    IF v_request.borrower_id = v_actor THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Owner cannot approve own request';
    END IF;
    IF v_availability <> 'available' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resource unavailable';
    END IF;

    v_next_due_at := COALESCE(p_due_at, v_request.due_at);
    IF v_next_due_at IS NOT NULL AND v_next_due_at < v_request.requested_at THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='due_at precedes request time';
    END IF;

    UPDATE public.resources
    SET availability_status = 'unavailable'
    WHERE id = v_resource_id AND owner_id = v_actor AND availability_status = 'available';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resource availability changed';
    END IF;

    RETURN QUERY
    UPDATE public.borrow_requests AS b
    SET status = 'approved', due_at = v_next_due_at
    WHERE b.id = p_request_id AND b.status = 'pending'
    RETURNING b.*;
END;
$function$;

-- 4. CREATE FUNCTION: reject_borrow_request
CREATE OR REPLACE FUNCTION public.reject_borrow_request(p_request_id bigint)
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
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_request_id IS NULL OR p_request_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid request ID';
    END IF;

    SELECT b.resource_id INTO v_resource_id
    FROM public.borrow_requests AS b WHERE b.id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found';
    END IF;
    SELECT r.owner_id INTO v_owner
    FROM public.resources AS r WHERE r.id = v_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    SELECT b.* INTO v_request
    FROM public.borrow_requests AS b WHERE b.id = p_request_id FOR UPDATE;
    IF NOT FOUND OR v_request.resource_id <> v_resource_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request changed; retry after refresh';
    END IF;
    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may change this request';
    END IF;
    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not pending';
    END IF;

    RETURN QUERY
    UPDATE public.borrow_requests AS b SET status = 'rejected'
    WHERE b.id = p_request_id AND b.status = 'pending'
    RETURNING b.*;
END;
$function$;

-- 5. CREATE FUNCTION: return_borrowed_resource
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
    v_availability text;
    v_request public.borrow_requests%ROWTYPE;
    v_returned_at timestamptz := pg_catalog.statement_timestamp();
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_request_id IS NULL OR p_request_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid request ID';
    END IF;

    SELECT b.resource_id INTO v_resource_id
    FROM public.borrow_requests AS b WHERE b.id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found';
    END IF;
    SELECT r.owner_id, r.availability_status INTO v_owner, v_availability
    FROM public.resources AS r WHERE r.id = v_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    SELECT b.* INTO v_request
    FROM public.borrow_requests AS b WHERE b.id = p_request_id FOR UPDATE;
    IF NOT FOUND OR v_request.resource_id <> v_resource_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request changed; retry after refresh';
    END IF;
    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may change this request';
    END IF;
    IF v_request.status <> 'approved' OR v_availability <> 'unavailable' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not an active approved loan';
    END IF;

    UPDATE public.borrow_requests AS b
    SET status = 'returned', returned_at = v_returned_at
    WHERE b.id = p_request_id AND b.status = 'approved'
    RETURNING b.* INTO v_request;

    UPDATE public.resources AS r
    SET availability_status = 'available'
    WHERE r.id = v_resource_id AND r.owner_id = v_actor AND r.availability_status = 'unavailable';

    RETURN NEXT v_request;
END;
$function$;

-- 6. Ensure RLS & Policies on borrow_requests
ALTER TABLE public.borrow_requests ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON public.borrow_requests TO authenticated;

DROP POLICY IF EXISTS "Read own borrow requests" ON public.borrow_requests;
CREATE POLICY "Read own borrow requests" ON public.borrow_requests
    FOR SELECT TO authenticated
    USING (auth.uid() = borrower_id);

DROP POLICY IF EXISTS "Owners read requests for their resources" ON public.borrow_requests;
CREATE POLICY "Owners read requests for their resources" ON public.borrow_requests
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.resources AS r
        WHERE r.id = borrow_requests.resource_id
          AND r.owner_id = auth.uid()
    ));

-- 7. Grant Permissions to authenticated role
GRANT EXECUTE ON FUNCTION public.create_borrow_request(bigint, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_borrow_request(bigint, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_borrow_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;
