-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 4 VERIFICATION
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- ============================================================================

-- 1. Verify meeting_proposals table structure
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'meeting_proposals'
ORDER BY ordinal_position;

-- 2. Verify constraints
SELECT conname, pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
WHERE t.relname = 'meeting_proposals';

-- 3. Verify meeting_proposals RLS and policies
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'meeting_proposals';

SELECT policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'meeting_proposals';

-- 4. Verify RPC signatures, security definer, and ownership
SELECT proname, pg_get_function_identity_arguments(p.oid) AS args,
       proowner::regrole AS owner, prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('propose_meeting', 'respond_to_meeting_proposal', 'get_conversation_proposals');

-- 5. Verify function permissions (PUBLIC and anon must have no execute privilege)
SELECT proname, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name IN ('propose_meeting', 'respond_to_meeting_proposal', 'get_conversation_proposals');

