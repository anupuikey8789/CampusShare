-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 1 VERIFICATION
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- ============================================================================

-- 1. Check conversations table definition
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'conversations'
ORDER BY ordinal_position;

-- 2. Verify constraints on conversations
SELECT conname, pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
WHERE t.relname = 'conversations';

-- 3. Verify RLS is enabled and policies on conversations
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'conversations';

SELECT policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'conversations';

-- 4. Verify table grants on conversations
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'conversations';

-- 5. Verify approve_borrow_request function signature and ownership
SELECT proname, pg_get_function_identity_arguments(p.oid) AS args,
       proowner::regrole AS owner, prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'approve_borrow_request';

