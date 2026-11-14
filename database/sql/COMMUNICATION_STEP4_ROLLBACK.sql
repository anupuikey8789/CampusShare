-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 4 ROLLBACK
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Drops Step 4 RPCs and meeting_proposals table.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.get_conversation_proposals(uuid);
DROP FUNCTION IF EXISTS public.respond_to_meeting_proposal(uuid, text);
DROP FUNCTION IF EXISTS public.propose_meeting(uuid, text, date, text, text, text);
DROP TABLE IF EXISTS public.meeting_proposals CASCADE;

COMMIT;

