-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — MASTER ROLLBACK SCRIPT
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Completely and safely rolls back all communication tables,
--              RPCs, and restores baseline borrowing functions and constraints.
-- ============================================================================

BEGIN;

-- 1. Drop Communication Functions
DROP FUNCTION IF EXISTS public.mark_notifications_read(uuid[], boolean);
DROP FUNCTION IF EXISTS public.request_return(uuid);
DROP FUNCTION IF EXISTS public.get_conversation_proposals(uuid);
DROP FUNCTION IF EXISTS public.respond_to_meeting_proposal(uuid, text);
DROP FUNCTION IF EXISTS public.propose_meeting(uuid, text, date, text, text, text);
DROP FUNCTION IF EXISTS public.send_message(uuid, text, text);
DROP FUNCTION IF EXISTS public.get_conversation_messages(uuid, int, timestamptz);
DROP FUNCTION IF EXISTS public.get_my_conversations();
DROP FUNCTION IF EXISTS public.is_conversation_participant(uuid);

-- 2. Drop Tables
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.meeting_proposals CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;

-- 3. Restore Baseline approve_borrow_request
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

ALTER FUNCTION public.approve_borrow_request(bigint, timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.approve_borrow_request(bigint, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_borrow_request(bigint, timestamptz) TO authenticated;

-- 4. Restore Baseline return_borrowed_resource
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
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may return this request';
    END IF;
    IF v_request.status <> 'approved' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not approved';
    END IF;

    UPDATE public.resources
    SET availability_status = 'available'
    WHERE id = v_resource_id AND owner_id = v_actor;

    RETURN QUERY
    UPDATE public.borrow_requests AS b
    SET status = 'returned', returned_at = clock_timestamp()
    WHERE b.id = p_request_id AND b.status = 'approved'
    RETURNING b.*;
END;
$function$;

ALTER FUNCTION public.return_borrowed_resource(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;

-- 5. Restore Constraints and Index
ALTER TABLE public.borrow_requests
    DROP CONSTRAINT IF EXISTS chk_borrow_requests_status;

ALTER TABLE public.borrow_requests
    ADD CONSTRAINT chk_borrow_requests_status
    CHECK (status IN ('pending', 'approved', 'rejected', 'returned'));

DROP INDEX IF EXISTS public.idx_borrow_requests_one_active;

CREATE UNIQUE INDEX one_active_request_per_borrower_resource
    ON public.borrow_requests (borrower_id, resource_id)
    WHERE status IN ('pending', 'approved');

COMMIT;

