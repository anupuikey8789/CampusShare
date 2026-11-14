-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 3 ROLLBACK
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Drops send_message RPC.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.send_message(uuid, text, text);

COMMIT;

