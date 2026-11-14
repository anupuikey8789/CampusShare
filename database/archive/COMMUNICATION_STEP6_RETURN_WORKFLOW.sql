-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 6: RETURN WORKFLOW
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Updates status constraint and unique index for 'return_requested',
--              creates request_return RPC (borrower-initiated), and enhances
--              return_borrowed_resource RPC (owner confirmation & conversation closure).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. UPDATE BORROW_REQUESTS STATUS CONSTRAINT AND ACTIVE INDEX
-- ----------------------------------------------------------------------------
ALTER TABLE public.borrow_requests
    DROP CONSTRAINT IF EXISTS chk_borrow_requests_status,
    DROP CONSTRAINT IF EXISTS borrow_requests_status_check;

ALTER TABLE public.borrow_requests
    ADD CONSTRAINT chk_borrow_requests_status
    CHECK (status IN ('pending', 'approved', 'rejected', 'returned', 'return_requested'));

DROP INDEX IF EXISTS public.one_active_request_per_borrower_resource;
DROP INDEX IF EXISTS public.idx_borrow_requests_one_active;

CREATE UNIQUE INDEX idx_borrow_requests_one_active
    ON public.borrow_requests (borrower_id, resource_id)
    WHERE status IN ('pending', 'approved', 'return_requested');


-- ----------------------------------------------------------------------------
-- 2. RPC: request_return (Borrower-Initiated Return Request)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_return(p_conversation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_borrower_id uuid;
    v_conv RECORD;
    v_req RECORD;
    v_res_title text;
    v_borrower_name text;
BEGIN
    v_borrower_id := auth.uid();
    IF v_borrower_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required.';
    END IF;

    SELECT id, borrow_request_id, resource_id, borrower_id, owner_id, status
    INTO v_conv
    FROM public.conversations
    WHERE id = p_conversation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Conversation not found.';
    END IF;

    IF v_conv.borrower_id <> v_borrower_id THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Unauthorized: Only the borrower can initiate a return request.';
    END IF;

    IF v_conv.status <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot request return on a closed conversation.';
    END IF;

    SELECT id, status
    INTO v_req
    FROM public.borrow_requests
    WHERE id = v_conv.borrow_request_id
    FOR UPDATE;

    IF v_req.status <> 'approved' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE = format('Borrow request must be in approved status to request return (current: %s)', v_req.status);
    END IF;

    UPDATE public.borrow_requests
    SET status = 'return_requested',
        updated_at = clock_timestamp()
    WHERE id = v_conv.borrow_request_id;

    IF to_regclass('public.notifications') IS NOT NULL THEN
        SELECT title INTO v_res_title FROM public.resources WHERE id = v_conv.resource_id;
        SELECT COALESCE(full_name, 'The borrower') INTO v_borrower_name FROM public.profiles WHERE id = v_borrower_id;

        INSERT INTO public.notifications (user_id, type, title, body, reference_id)
        VALUES (
            v_conv.owner_id,
            'return_requested',
            'Return Requested',
            v_borrower_name || ' wants to return "' || v_res_title || '". Please arrange handover or confirm return.',
            p_conversation_id::text
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'conversation_id', p_conversation_id,
        'status', 'return_requested'
    );
END;
$$;

ALTER FUNCTION public.request_return(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.request_return(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_return(uuid) TO authenticated;


-- ----------------------------------------------------------------------------
-- 3. RPC: return_borrowed_resource (Owner Confirmed Return & Conversation Closure)
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
    v_conv RECORD;
    v_owner_name text;
    v_res_title text;
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

    SELECT r.owner_id, r.title INTO v_owner, v_res_title
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
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may confirm return';
    END IF;

    IF v_request.status NOT IN ('approved', 'return_requested') THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Only approved or return-requested items can be returned';
    END IF;

    -- Make resource available again
    UPDATE public.resources
    SET availability_status = 'available'
    WHERE id = v_resource_id AND owner_id = v_actor;

    -- Close conversation and cancel pending meeting proposals
    UPDATE public.conversations
    SET status = 'closed',
        closed_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE borrow_request_id = p_request_id
    RETURNING id INTO v_conv.id;

    IF v_conv.id IS NOT NULL THEN
        UPDATE public.meeting_proposals
        SET status = 'cancelled',
            responded_at = clock_timestamp()
        WHERE conversation_id = v_conv.id
          AND status = 'pending';
    END IF;

    -- Notify borrower
    IF to_regclass('public.notifications') IS NOT NULL THEN
        SELECT COALESCE(full_name, 'The owner') INTO v_owner_name FROM public.profiles WHERE id = v_actor;
        INSERT INTO public.notifications (user_id, type, title, body, reference_id)
        VALUES (
            v_request.borrower_id,
            'resource_returned',
            'Resource Returned',
            v_owner_name || ' confirmed the return of "' || v_res_title || '".',
            p_request_id::text
        );
    END IF;

    RETURN QUERY
    UPDATE public.borrow_requests AS b
    SET status = 'returned',
        returned_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE b.id = p_request_id
    RETURNING b.*;
END;
$function$;

ALTER FUNCTION public.return_borrowed_resource(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;

COMMIT;

