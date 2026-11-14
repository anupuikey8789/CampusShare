-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 5: NOTIFICATIONS
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Creates notifications table, RLS, permissions, and mark_notifications_read RPC.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. CREATE NOTIFICATIONS TABLE
-- ----------------------------------------------------------------------------
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
-- 2. TABLE PRIVILEGES & MINIMUM GRANTS
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.notifications FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.notifications TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.notifications FROM authenticated;


-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_select_owner" ON public.notifications;

CREATE POLICY "notifications_select_owner"
    ON public.notifications
    FOR SELECT
    TO authenticated
    USING (user_id = (SELECT auth.uid()));


-- ----------------------------------------------------------------------------
-- 4. RPC: mark_notifications_read (Controlled Column-Level Mutation)
-- ----------------------------------------------------------------------------
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

