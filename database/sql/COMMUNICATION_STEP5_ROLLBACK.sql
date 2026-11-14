-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 5 ROLLBACK
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Drops mark_notifications_read RPC and notifications table.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.mark_notifications_read(uuid[], boolean);
DROP TABLE IF EXISTS public.notifications CASCADE;

COMMIT;

