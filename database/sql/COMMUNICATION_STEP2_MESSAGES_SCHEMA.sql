-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 2: MESSAGES & HISTORY
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Creates messages table, is_conversation_participant helper,
--              RLS policies, get_my_conversations RPC, and get_conversation_messages RPC.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. CREATE MESSAGES TABLE
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- 2. HELPER FUNCTION: is_conversation_participant (auth.uid() internal check)
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- 3. TABLE PRIVILEGES & MINIMUM GRANTS
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.messages FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.messages TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.messages FROM authenticated;


-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "messages_select_participants" ON public.messages;

CREATE POLICY "messages_select_participants"
    ON public.messages
    FOR SELECT
    TO authenticated
    USING (public.is_conversation_participant(conversation_id));


-- ----------------------------------------------------------------------------
-- 5. RPC: get_my_conversations
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- 6. RPC: get_conversation_messages
-- ----------------------------------------------------------------------------
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

    -- Automatically mark unread incoming messages as read
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

COMMIT;

