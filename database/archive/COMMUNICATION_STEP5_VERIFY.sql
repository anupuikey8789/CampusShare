-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 5 VERIFICATION
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- ============================================================================

-- 1. Verify notifications table columns
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'notifications'
ORDER BY ordinal_position;

-- 2. Verify notifications RLS and policies
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'notifications';

SELECT policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'notifications';

-- 3. Verify mark_notifications_read RPC
SELECT proname, pg_get_function_identity_arguments(p.oid) AS args,
       proowner::regrole AS owner, prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'mark_notifications_read';

-- 4. Verify table grants (authenticated has SELECT, mutations revoked)
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'notifications';

