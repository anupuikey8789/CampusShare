-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 3: SENDING & RECEIVING MESSAGES
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Creates the secure, idempotent send_message RPC with conversation
--              row locking, active status verification, and duplicate-safe handling.
-- ============================================================================

BEGIN;

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

    -- Lock conversation row and verify participation and status
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

    -- Idempotency check: return existing message if already processed
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

    -- Insert new message with concurrency safety
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

    -- Touch conversation updated_at for sorting
    UPDATE public.conversations
    SET updated_at = v_sent_at
    WHERE id = p_conversation_id;

    -- If notifications table exists, insert new message notification
    IF to_regclass('public.notifications') IS NOT NULL THEN
        SELECT COALESCE(full_name, 'A student')
        INTO v_sender_name
        FROM public.profiles
        WHERE id = v_sender_id;

        INSERT INTO public.notifications (user_id, type, title, body, reference_id)
        VALUES (
            v_recipient_id,
            'new_message',
            'New message from ' || v_sender_name,
            CASE WHEN char_length(v_clean_content) > 80 THEN substring(v_clean_content FROM 1 FOR 77) || '…' ELSE v_clean_content END,
            p_conversation_id::text
        );
    END IF;

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

COMMIT;

