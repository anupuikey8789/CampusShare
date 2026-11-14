-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — COMPLETE STAGING DEPLOYMENT
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Sets up private conversations, messages, meeting proposals,
--              notifications, RLS policies, zero-trust permissions, and RPCs.
-- Campus Timezone: Asia/Kolkata (IST, UTC+05:30)
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. UPDATE BORROW_REQUESTS STATUS CONSTRAINT AND ACTIVE UNIQUE INDEX
-- ----------------------------------------------------------------------------
ALTER TABLE public.borrow_requests
    ADD COLUMN IF NOT EXISTS request_message text;

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
-- 2. CREATE CORE COMMUNICATION TABLES
-- ----------------------------------------------------------------------------

-- Table 1: conversations
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

-- Table 2: messages
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE RESTRICT,
    sender_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    content text NOT NULL,
    client_idempotency_key text NOT NULL,
    sent_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    is_read boolean NOT NULL DEFAULT FALSE,
    CONSTRAINT chk_messages_content_length CHECK (char_length(trim(content)) BETWEEN 1 AND 2000),
    CONSTRAINT chk_messages_idempotency_length CHECK (char_length(trim(client_idempotency_key)) BETWEEN 8 AND 128),
    CONSTRAINT uq_messages_idempotency UNIQUE (conversation_id, sender_id, client_idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_sent_at ON public.messages (conversation_id, sent_at ASC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON public.messages (sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_unread ON public.messages (conversation_id, is_read) WHERE is_read = FALSE;

-- Table 3: meeting_proposals
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

-- Table 4: notifications
CREATE TABLE IF NOT EXISTS public.notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type text NOT NULL CHECK (type IN (
        'borrow_requested',
        'borrow_approved',
        'borrow_rejected',
        'new_message',
        'meeting_proposed',
        'meeting_accepted',
        'meeting_declined',
        'meeting_cancelled',
        'return_requested',
        'resource_returned'
    )),
    title text NOT NULL,
    body text NOT NULL,
    reference_id text,
    is_read boolean NOT NULL DEFAULT FALSE,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON public.notifications (user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON public.notifications (user_id, created_at DESC);


-- ----------------------------------------------------------------------------
-- 3. TABLE PRIVILEGES & MINIMUM ACCESS
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.conversations, public.messages, public.meeting_proposals, public.notifications FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.conversations, public.messages, public.meeting_proposals, public.notifications TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.conversations, public.messages, public.meeting_proposals, public.notifications FROM authenticated;


-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "conversations_select_participants" ON public.conversations;
CREATE POLICY "conversations_select_participants"
    ON public.conversations FOR SELECT TO authenticated
    USING (borrower_id = (SELECT auth.uid()) OR owner_id = (SELECT auth.uid()));

-- Participant helper function (Strict internal auth.uid() check)
CREATE OR REPLACE FUNCTION public.is_conversation_participant(p_conversation_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = p_conversation_id
          AND (c.borrower_id = v_user_id OR c.owner_id = v_user_id)
    );
END;
$$;

ALTER FUNCTION public.is_conversation_participant(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_conversation_participant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(uuid) TO authenticated;

DROP POLICY IF EXISTS "messages_select_participants" ON public.messages;
CREATE POLICY "messages_select_participants"
    ON public.messages FOR SELECT TO authenticated
    USING (public.is_conversation_participant(conversation_id));

DROP POLICY IF EXISTS "meeting_proposals_select_participants" ON public.meeting_proposals;
CREATE POLICY "meeting_proposals_select_participants"
    ON public.meeting_proposals FOR SELECT TO authenticated
    USING (public.is_conversation_participant(conversation_id));

DROP POLICY IF EXISTS "notifications_select_owner" ON public.notifications;
CREATE POLICY "notifications_select_owner"
    ON public.notifications FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));


-- ----------------------------------------------------------------------------
-- 5. WORKFLOW RPC FUNCTIONS
-- ----------------------------------------------------------------------------

-- A. approve_borrow_request (Atomic conversation creation)
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
    v_conv_id uuid;
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

    SELECT r.owner_id, r.availability_status, r.title INTO v_owner, v_availability, v_res_title
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

    -- Atomically insert conversation
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
        updated_at = clock_timestamp()
    RETURNING id INTO v_conv_id;

    -- Notification
    SELECT COALESCE(full_name, 'The owner') INTO v_owner_name FROM public.profiles WHERE id = v_actor;
    INSERT INTO public.notifications (user_id, type, title, body, reference_id)
    VALUES (
        v_request.borrower_id,
        'borrow_approved',
        'Borrow Request Approved',
        v_owner_name || ' approved your request for "' || v_res_title || '". You can now coordinate handover.',
        v_conv_id::text
    );

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


-- B. get_my_conversations
CREATE OR REPLACE FUNCTION public.get_my_conversations()
RETURNS TABLE (
    id uuid,
    borrow_request_id bigint,
    resource_id bigint,
    resource_title text,
    borrower_id uuid,
    borrower_name text,
    owner_id uuid,
    owner_name text,
    status text,
    created_at timestamptz,
    updated_at timestamptz,
    closed_at timestamptz,
    last_message text,
    last_message_at timestamptz,
    unread_count bigint
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

    RETURN QUERY
    SELECT 
        c.id,
        c.borrow_request_id,
        c.resource_id,
        COALESCE(r.title, 'Unknown Resource')::text AS resource_title,
        c.borrower_id,
        COALESCE(pb.full_name, 'Student')::text AS borrower_name,
        c.owner_id,
        COALESCE(po.full_name, 'Owner')::text AS owner_name,
        c.status,
        c.created_at,
        c.updated_at,
        c.closed_at,
        (
            SELECT m.content 
            FROM public.messages m 
            WHERE m.conversation_id = c.id 
            ORDER BY m.sent_at DESC 
            LIMIT 1
        )::text AS last_message,
        (
            SELECT m.sent_at 
            FROM public.messages m 
            WHERE m.conversation_id = c.id 
            ORDER BY m.sent_at DESC 
            LIMIT 1
        ) AS last_message_at,
        (
            SELECT count(*) 
            FROM public.messages m 
            WHERE m.conversation_id = c.id 
              AND m.sender_id <> v_user_id 
              AND m.is_read = FALSE
        )::bigint AS unread_count
    FROM public.conversations c
    JOIN public.resources r ON r.id = c.resource_id
    LEFT JOIN public.profiles pb ON pb.id = c.borrower_id
    LEFT JOIN public.profiles po ON po.id = c.owner_id
    WHERE c.borrower_id = v_user_id OR c.owner_id = v_user_id
    ORDER BY c.updated_at DESC;
END;
$$;

ALTER FUNCTION public.get_my_conversations() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_my_conversations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_conversations() TO authenticated;


-- C. get_conversation_messages
CREATE OR REPLACE FUNCTION public.get_conversation_messages(
    p_conversation_id uuid,
    p_limit int DEFAULT 50,
    p_before timestamptz DEFAULT NULL
)
RETURNS TABLE (
    id uuid,
    conversation_id uuid,
    sender_id uuid,
    sender_name text,
    content text,
    sent_at timestamptz,
    is_read boolean,
    client_idempotency_key text
)
LANGUAGE plpgsql
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

    UPDATE public.messages m
    SET is_read = TRUE
    WHERE m.conversation_id = p_conversation_id
      AND m.sender_id <> v_user_id
      AND m.is_read = FALSE;

    RETURN QUERY
    SELECT 
        m.id,
        m.conversation_id,
        m.sender_id,
        COALESCE(p.full_name, 'Student')::text AS sender_name,
        m.content,
        m.sent_at,
        m.is_read,
        m.client_idempotency_key
    FROM (
        SELECT sm.*
        FROM public.messages sm
        WHERE sm.conversation_id = p_conversation_id
          AND (p_before IS NULL OR sm.sent_at < p_before)
        ORDER BY sm.sent_at DESC
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)
    ) m
    LEFT JOIN public.profiles p ON p.id = m.sender_id
    ORDER BY m.sent_at ASC;
END;
$$;

ALTER FUNCTION public.get_conversation_messages(uuid, int, timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_conversation_messages(uuid, int, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_conversation_messages(uuid, int, timestamptz) TO authenticated;


-- D. send_message
CREATE OR REPLACE FUNCTION public.send_message(
    p_conversation_id uuid,
    p_content text,
    p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_sender_id uuid;
    v_conv RECORD;
    v_recipient_id uuid;
    v_clean_content text;
    v_clean_key text;
    v_existing_msg RECORD;
    v_message_id uuid;
    v_sent_at timestamptz;
    v_sender_name text;
BEGIN
    v_sender_id := auth.uid();
    IF v_sender_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required.';
    END IF;

    v_clean_key := trim(p_idempotency_key);
    IF v_clean_key IS NULL OR char_length(v_clean_key) < 8 OR char_length(v_clean_key) > 128 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='A valid client idempotency key between 8 and 128 characters is required.';
    END IF;

    v_clean_content := trim(p_content);
    IF v_clean_content IS NULL OR char_length(v_clean_content) < 1 OR char_length(v_clean_content) > 2000 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Message content must be between 1 and 2000 characters.';
    END IF;

    SELECT id, borrower_id, owner_id, status
    INTO v_conv
    FROM public.conversations
    WHERE id = p_conversation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Conversation not found.';
    END IF;

    IF v_conv.borrower_id <> v_sender_id AND v_conv.owner_id <> v_sender_id THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Unauthorized: You are not a participant in this conversation.';
    END IF;

    IF v_conv.status <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot send messages in a closed conversation.';
    END IF;

    v_recipient_id := CASE WHEN v_conv.borrower_id = v_sender_id THEN v_conv.owner_id ELSE v_conv.borrower_id END;

    SELECT id, conversation_id, sender_id, content, sent_at, client_idempotency_key
    INTO v_existing_msg
    FROM public.messages
    WHERE conversation_id = p_conversation_id
      AND sender_id = v_sender_id
      AND client_idempotency_key = v_clean_key;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'status', 'duplicate',
            'message', jsonb_build_object(
                'id', v_existing_msg.id,
                'conversation_id', v_existing_msg.conversation_id,
                'sender_id', v_existing_msg.sender_id,
                'content', v_existing_msg.content,
                'sent_at', v_existing_msg.sent_at
            )
        );
    END IF;

    BEGIN
        INSERT INTO public.messages (
            conversation_id,
            sender_id,
            content,
            client_idempotency_key,
            sent_at
        )
        VALUES (
            p_conversation_id,
            v_sender_id,
            v_clean_content,
            v_clean_key,
            clock_timestamp()
        )
        RETURNING id, sent_at INTO v_message_id, v_sent_at;
    EXCEPTION WHEN unique_violation THEN
        SELECT id, conversation_id, sender_id, content, sent_at
        INTO v_existing_msg
        FROM public.messages
        WHERE conversation_id = p_conversation_id
          AND sender_id = v_sender_id
          AND client_idempotency_key = v_clean_key;

        RETURN jsonb_build_object(
            'status', 'duplicate',
            'message', jsonb_build_object(
                'id', v_existing_msg.id,
                'conversation_id', v_existing_msg.conversation_id,
                'sender_id', v_existing_msg.sender_id,
                'content', v_existing_msg.content,
                'sent_at', v_existing_msg.sent_at
            )
        );
    END;

    UPDATE public.conversations
    SET updated_at = v_sent_at
    WHERE id = p_conversation_id;

    SELECT COALESCE(full_name, 'A student') INTO v_sender_name FROM public.profiles WHERE id = v_sender_id;

    INSERT INTO public.notifications (user_id, type, title, body, reference_id)
    VALUES (
        v_recipient_id,
        'new_message',
        'New message from ' || v_sender_name,
        CASE WHEN char_length(v_clean_content) > 80 THEN substring(v_clean_content FROM 1 FOR 77) || '…' ELSE v_clean_content END,
        p_conversation_id::text
    );

    RETURN jsonb_build_object(
        'status', 'sent',
        'message', jsonb_build_object(
            'id', v_message_id,
            'conversation_id', p_conversation_id,
            'sender_id', v_sender_id,
            'content', v_clean_content,
            'sent_at', v_sent_at
        )
    );
END;
$$;

ALTER FUNCTION public.send_message(uuid, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.send_message(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, text, text) TO authenticated;


-- E. propose_meeting
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

    v_timestamp_tz := (p_meeting_date::text || ' ' || p_meeting_time || ':00 Asia/Kolkata')::timestamptz;

    IF v_timestamp_tz <= clock_timestamp() THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Meeting time must be in the future (Asia/Kolkata timezone).';
    END IF;

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

    IF EXISTS (
        SELECT 1
        FROM public.meeting_proposals
        WHERE conversation_id = p_conversation_id
          AND proposer_id = v_recipient_id
          AND status = 'pending'
    ) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='The other student has already proposed a meeting. Please accept, decline, or ask them to adjust.';
    END IF;

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

    SELECT COALESCE(full_name, 'A student') INTO v_proposer_name FROM public.profiles WHERE id = v_proposer_id;

    INSERT INTO public.notifications (user_id, type, title, body, reference_id)
    VALUES (
        v_recipient_id,
        'meeting_proposed',
        'Meeting Proposed',
        v_proposer_name || ' proposed a meeting on ' || to_char(p_meeting_date, 'Mon DD, YYYY') || ' at ' || p_meeting_time || ' (' || v_clean_location || ').',
        p_conversation_id::text
    );

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


-- F. respond_to_meeting_proposal
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

    SELECT COALESCE(full_name, 'A student') INTO v_actor_name FROM public.profiles WHERE id = v_actor_id;

    IF p_action = 'cancel' THEN
        IF v_actor_id <> v_prop.proposer_id THEN
            RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the proposer can cancel this proposal.';
        END IF;

        UPDATE public.meeting_proposals
        SET status = 'cancelled',
            responded_at = clock_timestamp()
        WHERE id = p_proposal_id;

        INSERT INTO public.notifications (user_id, type, title, body, reference_id)
        VALUES (
            v_prop.recipient_id,
            'meeting_cancelled',
            'Meeting Cancelled',
            v_actor_name || ' cancelled the proposed meeting for ' || to_char(v_prop.meeting_date, 'Mon DD') || '.',
            v_prop.conversation_id::text
        );

    ELSIF p_action = 'decline' THEN
        IF v_actor_id <> v_prop.recipient_id THEN
            RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the recipient can decline this proposal.';
        END IF;

        UPDATE public.meeting_proposals
        SET status = 'declined',
            responded_at = clock_timestamp()
        WHERE id = p_proposal_id;

        INSERT INTO public.notifications (user_id, type, title, body, reference_id)
        VALUES (
            v_prop.proposer_id,
            'meeting_declined',
            'Meeting Declined',
            v_actor_name || ' declined the proposed meeting for ' || to_char(v_prop.meeting_date, 'Mon DD') || '.',
            v_prop.conversation_id::text
        );

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

        UPDATE public.meeting_proposals
        SET status = 'superseded',
            responded_at = clock_timestamp()
        WHERE conversation_id = v_prop.conversation_id
          AND id <> p_proposal_id
          AND status = 'pending';

        INSERT INTO public.notifications (user_id, type, title, body, reference_id)
        VALUES (
            v_prop.proposer_id,
            'meeting_accepted',
            'Meeting Confirmed',
            v_actor_name || ' accepted the meeting on ' || to_char(v_prop.meeting_date, 'Mon DD') || ' at ' || v_prop.meeting_time || ' (' || v_prop.location || ').',
            v_prop.conversation_id::text
        );
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


-- G. get_conversation_proposals
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


-- H. request_return
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


-- I. return_borrowed_resource
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

    UPDATE public.resources
    SET availability_status = 'available'
    WHERE id = v_resource_id AND owner_id = v_actor;

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

    SELECT COALESCE(full_name, 'The owner') INTO v_owner_name FROM public.profiles WHERE id = v_actor;

    INSERT INTO public.notifications (user_id, type, title, body, reference_id)
    VALUES (
        v_request.borrower_id,
        'resource_returned',
        'Resource Returned',
        v_owner_name || ' confirmed the return of "' || v_res_title || '".',
        p_request_id::text
    );

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


-- J. mark_notifications_read
CREATE OR REPLACE FUNCTION public.mark_notifications_read(
    p_notification_ids uuid[] DEFAULT NULL,
    p_mark_all boolean DEFAULT FALSE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid;
    v_updated_count integer;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required.';
    END IF;

    IF p_mark_all THEN
        UPDATE public.notifications
        SET is_read = TRUE
        WHERE user_id = v_user_id
          AND is_read = FALSE;
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    ELSIF p_notification_ids IS NOT NULL AND array_length(p_notification_ids, 1) > 0 THEN
        UPDATE public.notifications
        SET is_read = TRUE
        WHERE user_id = v_user_id
          AND id = ANY(p_notification_ids)
          AND is_read = FALSE;
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    ELSE
        v_updated_count := 0;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'marked_read', v_updated_count
    );
END;
$$;

ALTER FUNCTION public.mark_notifications_read(uuid[], boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.mark_notifications_read(uuid[], boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(uuid[], boolean) TO authenticated;

COMMIT;

