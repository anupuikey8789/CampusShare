-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 2 ROLLBACK
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Drops Step 2 RPCs and messages table.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.get_conversation_messages(uuid, int, timestamptz);
DROP FUNCTION IF EXISTS public.get_my_conversations();
DROP FUNCTION IF EXISTS public.is_conversation_participant(uuid);
DROP TABLE IF EXISTS public.messages CASCADE;

COMMIT;

