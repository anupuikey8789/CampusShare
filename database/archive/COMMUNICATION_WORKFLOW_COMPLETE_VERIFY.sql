-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — MASTER VERIFICATION SCRIPT
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- ============================================================================

-- 1. Table definitions
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name IN ('conversations', 'messages', 'meeting_proposals', 'notifications')
ORDER BY table_name, ordinal_position;

-- 2. Check constraints
SELECT conname, pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
WHERE t.relname IN ('borrow_requests', 'conversations', 'messages', 'meeting_proposals', 'notifications');

-- 3. Indexes
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE tablename IN ('borrow_requests', 'conversations', 'messages', 'meeting_proposals', 'notifications')
ORDER BY tablename, indexname;

-- 4. RLS enabled status
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename IN ('conversations', 'messages', 'meeting_proposals', 'notifications');

-- 5. RLS policies
SELECT tablename, policyname, roles, cmd, qual
FROM pg_policies
WHERE tablename IN ('conversations', 'messages', 'meeting_proposals', 'notifications')
ORDER BY tablename, policyname;

-- 6. RPC functions, ownership and security definer
SELECT proname, pg_get_function_identity_arguments(p.oid) AS args,
       proowner::regrole AS owner, prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN (
      'approve_borrow_request',
      'is_conversation_participant',
      'get_my_conversations',
      'get_conversation_messages',
      'send_message',
      'propose_meeting',
      'respond_to_meeting_proposal',
      'get_conversation_proposals',
      'request_return',
      'return_borrowed_resource',
      'mark_notifications_read'
  )
ORDER BY proname;

-- 7. Function routine privileges (PUBLIC and anon should have no privileges)
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name IN (
      'approve_borrow_request',
      'is_conversation_participant',
      'get_my_conversations',
      'get_conversation_messages',
      'send_message',
      'propose_meeting',
      'respond_to_meeting_proposal',
      'get_conversation_proposals',
      'request_return',
      'return_borrowed_resource',
      'mark_notifications_read'
  )
ORDER BY routine_name, grantee;

