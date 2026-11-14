-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 4: MEETING PROPOSALS
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Creates meeting_proposals table, RLS policies, propose_meeting RPC,
--              respond_to_meeting_proposal RPC, and get_conversation_proposals RPC.
-- Campus Timezone: Asia/Kolkata (IST, UTC+05:30)
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. CREATE MEETING PROPOSALS TABLE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meeting_proposals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE RESTRICT,
    proposer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    meeting_type text NOT NULL CHECK (meeting_type IN ('handover', 'return')),
    meeting_date date NOT NULL,
    meeting_time text NOT NULL CHECK (meeting_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
    meeting_timestamp timestamptz NOT NULL,
    location text NOT NULL,
    notes text,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled', 'superseded')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    responded_at timestamptz,
    CONSTRAINT chk_meeting_location_length CHECK (char_length(trim(location)) BETWEEN 2 AND 255),
    CONSTRAINT chk_meeting_distinct_participants CHECK (proposer_id <> recipient_id)
);

CREATE INDEX IF NOT EXISTS idx_meeting_proposals_conversation ON public.meeting_proposals (conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_meeting_proposals_status ON public.meeting_proposals (conversation_id, status);


-- ----------------------------------------------------------------------------
-- 2. TABLE PRIVILEGES & MINIMUM GRANTS
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.meeting_proposals FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.meeting_proposals TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.meeting_proposals FROM authenticated;


-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.meeting_proposals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "meeting_proposals_select_participants" ON public.meeting_proposals;

CREATE POLICY "meeting_proposals_select_participants"
    ON public.meeting_proposals
    FOR SELECT
    TO authenticated
    USING (public.is_conversation_participant(conversation_id));


-- ----------------------------------------------------------------------------
-- 4. RPC: propose_meeting (Asia/Kolkata timezone, conversation lock, own cancel)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.propose_meeting(
    p_conversation_id uuid,
    p_meeting_type text,
    p_meeting_date date,
    p_meeting_time text,
    p_location text,
    p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_proposer_id uuid;
    v_conv RECORD;
    v_recipient_id uuid;
    v_timestamp_tz timestamptz;
    v_clean_location text;
    v_clean_notes text;
    v_proposal_id uuid;
    v_proposer_name text;
BEGIN
    v_proposer_id := auth.uid();
    IF v_proposer_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required.';
    END IF;

    IF p_meeting_type NOT IN ('handover', 'return') THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid meeting type. Must be handover or return.';
    END IF;

    v_clean_location := trim(p_location);
    IF v_clean_location IS NULL OR char_length(v_clean_location) < 2 OR char_length(v_clean_location) > 255 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Location must be between 2 and 255 characters.';
    END IF;

    IF p_meeting_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid meeting time format. Use HH:MM in 24-hour format.';
    END IF;

    -- Unambiguous conversion using Asia/Kolkata campus timezone
    v_timestamp_tz := (p_meeting_date::text || ' ' || p_meeting_time || ':00 Asia/Kolkata')::timestamptz;

    IF v_timestamp_tz <= clock_timestamp() THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Meeting time must be in the future (Asia/Kolkata timezone).';
    END IF;

    -- Lock conversation row
    SELECT id, borrower_id, owner_id, status
    INTO v_conv
    FROM public.conversations
    WHERE id = p_conversation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Conversation not found.';
    END IF;

    IF v_conv.borrower_id <> v_proposer_id AND v_conv.owner_id <> v_proposer_id THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Unauthorized: You are not a participant in this conversation.';
    END IF;

    IF v_conv.status <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot propose meetings in a closed conversation.';
    END IF;

    v_recipient_id := CASE WHEN v_conv.borrower_id = v_proposer_id THEN v_conv.owner_id ELSE v_conv.borrower_id END;

    -- Check if partner already has a pending proposal
    IF EXISTS (
        SELECT 1
        FROM public.meeting_proposals
        WHERE conversation_id = p_conversation_id
          AND proposer_id = v_recipient_id
          AND status = 'pending'
    ) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='The other student has already proposed a meeting. Please accept, decline, or ask them to adjust.';
    END IF;

    -- Cancel proposer's OWN prior pending proposal
    UPDATE public.meeting_proposals
    SET status = 'cancelled',
        responded_at = clock_timestamp()
    WHERE conversation_id = p_conversation_id
      AND proposer_id = v_proposer_id
      AND status = 'pending';

    v_clean_notes := NULLIF(trim(p_notes), '');
    IF v_clean_notes IS NOT NULL AND char_length(v_clean_notes) > 500 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Notes cannot exceed 500 characters.';
    END IF;

    INSERT INTO public.meeting_proposals (
        conversation_id,
        proposer_id,
        recipient_id,
        meeting_type,
        meeting_date,
        meeting_time,
        meeting_timestamp,
        location,
        notes,
        status,
        created_at
    )
    VALUES (
        p_conversation_id,
        v_proposer_id,
        v_recipient_id,
        p_meeting_type,
        p_meeting_date,
        p_meeting_time,
        v_timestamp_tz,
        v_clean_location,
        v_clean_notes,
        'pending',
        clock_timestamp()
    )
    RETURNING id INTO v_proposal_id;

    -- Notify recipient if notifications table exists
    IF to_regclass('public.notifications') IS NOT NULL THEN
        SELECT COALESCE(full_name, 'A student')
        INTO v_proposer_name
        FROM public.profiles
        WHERE id = v_proposer_id;

        INSERT INTO public.notifications (user_id, type, title, body, reference_id)
        VALUES (
            v_recipient_id,
            'meeting_proposed',
            'Meeting Proposed',
            v_proposer_name || ' proposed a meeting on ' || to_char(p_meeting_date, 'Mon DD, YYYY') || ' at ' || p_meeting_time || ' (' || v_clean_location || ').',
            p_conversation_id::text
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'proposal_id', v_proposal_id,
        'meeting_timestamp', v_timestamp_tz,
        'status', 'pending'
    );
END;
$$;

ALTER FUNCTION public.propose_meeting(uuid, text, date, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.propose_meeting(uuid, text, date, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.propose_meeting(uuid, text, date, text, text, text) TO authenticated;


-- ----------------------------------------------------------------------------
-- 5. RPC: respond_to_meeting_proposal (Lock, active validation, role check)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.respond_to_meeting_proposal(
    p_proposal_id uuid,
    p_action text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_id uuid;
    v_prop RECORD;
    v_conv RECORD;
    v_actor_name text;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required.';
    END IF;

    IF p_action NOT IN ('accept', 'decline', 'cancel') THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid action. Must be accept, decline, or cancel.';
    END IF;

    SELECT id, conversation_id, proposer_id, recipient_id, meeting_type, meeting_date, meeting_time, meeting_timestamp, location, status
    INTO v_prop
    FROM public.meeting_proposals
    WHERE id = p_proposal_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Meeting proposal not found.';
    END IF;

    IF v_prop.status <> 'pending' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE = format('Proposal is no longer pending (current status: %s)', v_prop.status);
    END IF;

    -- Lock conversation and verify status
    SELECT id, borrower_id, owner_id, status
    INTO v_conv
    FROM public.conversations
    WHERE id = v_prop.conversation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Associated conversation not found.';
    END IF;

    IF v_conv.status <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot modify meeting proposals for a closed conversation.';
    END IF;

    IF p_action = 'cancel' THEN
        IF v_actor_id <> v_prop.proposer_id THEN
            RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the proposer can cancel this proposal.';
        END IF;

        UPDATE public.meeting_proposals
        SET status = 'cancelled',
            responded_at = clock_timestamp()
        WHERE id = p_proposal_id;

        IF to_regclass('public.notifications') IS NOT NULL THEN
            SELECT COALESCE(full_name, 'A student') INTO v_actor_name FROM public.profiles WHERE id = v_actor_id;
            INSERT INTO public.notifications (user_id, type, title, body, reference_id)
            VALUES (
                v_prop.recipient_id,
                'meeting_cancelled',
                'Meeting Cancelled',
                v_actor_name || ' cancelled the proposed meeting for ' || to_char(v_prop.meeting_date, 'Mon DD') || '.',
                v_prop.conversation_id::text
            );
        END IF;

    ELSIF p_action = 'decline' THEN
        IF v_actor_id <> v_prop.recipient_id THEN
            RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the recipient can decline this proposal.';
        END IF;

        UPDATE public.meeting_proposals
        SET status = 'declined',
            responded_at = clock_timestamp()
        WHERE id = p_proposal_id;

        IF to_regclass('public.notifications') IS NOT NULL THEN
            SELECT COALESCE(full_name, 'A student') INTO v_actor_name FROM public.profiles WHERE id = v_actor_id;
            INSERT INTO public.notifications (user_id, type, title, body, reference_id)
            VALUES (
                v_prop.proposer_id,
                'meeting_declined',
                'Meeting Declined',
                v_actor_name || ' declined the proposed meeting for ' || to_char(v_prop.meeting_date, 'Mon DD') || '.',
                v_prop.conversation_id::text
            );
        END IF;

    ELSIF p_action = 'accept' THEN
        IF v_actor_id <> v_prop.recipient_id THEN
            RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the recipient can accept this proposal.';
        END IF;

        IF v_prop.meeting_timestamp <= clock_timestamp() THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Cannot accept an expired meeting proposal.';
        END IF;

        UPDATE public.meeting_proposals
        SET status = 'accepted',
            responded_at = clock_timestamp()
        WHERE id = p_proposal_id;

        -- Automatically supersede other pending proposals in this conversation
        UPDATE public.meeting_proposals
        SET status = 'superseded',
            responded_at = clock_timestamp()
        WHERE conversation_id = v_prop.conversation_id
          AND id <> p_proposal_id
          AND status = 'pending';

        IF to_regclass('public.notifications') IS NOT NULL THEN
            SELECT COALESCE(full_name, 'A student') INTO v_actor_name FROM public.profiles WHERE id = v_actor_id;
            INSERT INTO public.notifications (user_id, type, title, body, reference_id)
            VALUES (
                v_prop.proposer_id,
                'meeting_accepted',
                'Meeting Confirmed',
                v_actor_name || ' accepted the meeting on ' || to_char(v_prop.meeting_date, 'Mon DD') || ' at ' || v_prop.meeting_time || ' (' || v_prop.location || ').',
                v_prop.conversation_id::text
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'proposal_id', p_proposal_id,
        'status', CASE WHEN p_action = 'accept' THEN 'accepted' WHEN p_action = 'decline' THEN 'declined' ELSE 'cancelled' END
    );
END;
$$;

ALTER FUNCTION public.respond_to_meeting_proposal(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.respond_to_meeting_proposal(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_to_meeting_proposal(uuid, text) TO authenticated;


-- ----------------------------------------------------------------------------
-- 6. RPC: get_conversation_proposals
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_conversation_proposals(p_conversation_id uuid)
RETURNS TABLE (
    id uuid,
    conversation_id uuid,
    proposer_id uuid,
    proposer_name text,
    recipient_id uuid,
    recipient_name text,
    meeting_type text,
    meeting_date date,
    meeting_time text,
    meeting_timestamp timestamptz,
    location text,
    notes text,
    status text,
    created_at timestamptz,
    responded_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;

    IF NOT public.is_conversation_participant(p_conversation_id) THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Unauthorized: You are not a participant in this conversation.';
    END IF;

    RETURN QUERY
    SELECT 
        mp.id,
        mp.conversation_id,
        mp.proposer_id,
        COALESCE(pp.full_name, 'Student')::text AS proposer_name,
        mp.recipient_id,
        COALESCE(pr.full_name, 'Student')::text AS recipient_name,
        mp.meeting_type,
        mp.meeting_date,
        mp.meeting_time,
        mp.meeting_timestamp,
        mp.location,
        mp.notes,
        mp.status,
        mp.created_at,
        mp.responded_at
    FROM public.meeting_proposals mp
    LEFT JOIN public.profiles pp ON pp.id = mp.proposer_id
    LEFT JOIN public.profiles pr ON pr.id = mp.recipient_id
    WHERE mp.conversation_id = p_conversation_id
    ORDER BY mp.created_at DESC;
END;
$$;

ALTER FUNCTION public.get_conversation_proposals(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_conversation_proposals(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_conversation_proposals(uuid) TO authenticated;

COMMIT;

