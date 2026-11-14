-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 1: CONVERSATION CREATION
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Creates the conversations table, configures RLS and permissions,
--              and updates approve_borrow_request to atomically create a private
--              conversation between borrower and owner upon request approval.
-- Note: Preserves SETOF public.borrow_requests return type for full C++ Crow compatibility.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. CREATE CONVERSATIONS TABLE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    borrow_request_id bigint NOT NULL REFERENCES public.borrow_requests(id) ON DELETE RESTRICT,
    resource_id bigint NOT NULL REFERENCES public.resources(id) ON DELETE RESTRICT,
    borrower_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    closed_at timestamptz,
    CONSTRAINT uq_conversations_borrow_request UNIQUE (borrow_request_id),
    CONSTRAINT chk_conversations_distinct_participants CHECK (borrower_id <> owner_id)
);

CREATE INDEX IF NOT EXISTS idx_conversations_borrower ON public.conversations (borrower_id);
CREATE INDEX IF NOT EXISTS idx_conversations_owner ON public.conversations (owner_id);
CREATE INDEX IF NOT EXISTS idx_conversations_resource ON public.conversations (resource_id);
CREATE INDEX IF NOT EXISTS idx_conversations_status ON public.conversations (status);


-- ----------------------------------------------------------------------------
-- 2. TABLE PRIVILEGES & MINIMUM GRANTS
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.conversations FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.conversations TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.conversations FROM authenticated;


-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "conversations_select_participants" ON public.conversations;

CREATE POLICY "conversations_select_participants"
    ON public.conversations
    FOR SELECT
    TO authenticated
    USING (
        borrower_id = (SELECT auth.uid()) OR
        owner_id = (SELECT auth.uid())
    );


-- ----------------------------------------------------------------------------
-- 4. UPDATE APPROVE_BORROW_REQUEST RPC (ATOMIC CONVERSATION CREATION)
-- ----------------------------------------------------------------------------
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

    -- Update resource availability
    UPDATE public.resources
    SET availability_status = 'unavailable'
    WHERE id = v_resource_id AND owner_id = v_actor AND availability_status = 'available';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resource availability changed';
    END IF;

    -- Atomically create or reactivate private conversation
    INSERT INTO public.conversations (
        borrow_request_id,
        resource_id,
        borrower_id,
        owner_id,
        status,
        created_at,
        updated_at
    )
    VALUES (
        p_request_id,
        v_resource_id,
        v_request.borrower_id,
        v_actor,
        'active',
        clock_timestamp(),
        clock_timestamp()
    )
    ON CONFLICT (borrow_request_id) DO UPDATE
    SET status = 'active',
        updated_at = clock_timestamp();

    -- Return updated borrow request row
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

COMMIT;

