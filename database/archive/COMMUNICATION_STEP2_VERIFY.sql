-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 2 VERIFICATION
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- ============================================================================

-- 1. Verify messages table structure
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'messages'
ORDER BY ordinal_position;

-- 2. Verify constraints and idempotency unique constraint
SELECT conname, pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
WHERE t.relname = 'messages';

-- 3. Verify messages RLS is enabled and policies
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'messages';

SELECT policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'messages';

-- 4. Verify RPC signatures, security definer settings, and ownership
SELECT proname, pg_get_function_identity_arguments(p.oid) AS args,
       proowner::regrole AS owner, prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('is_conversation_participant', 'get_my_conversations', 'get_conversation_messages');

-- 5. Verify function permissions (PUBLIC and anon should be empty/revoked)
SELECT proname, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name IN ('is_conversation_participant', 'get_my_conversations', 'get_conversation_messages');

