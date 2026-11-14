-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 3 VERIFICATION
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- ============================================================================

-- 1. Check send_message function signature, security definer, and ownership
SELECT proname, pg_get_function_identity_arguments(p.oid) AS args,
       proowner::regrole AS owner, prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'send_message';

-- 2. Verify permissions (PUBLIC and anon must have no execute privilege)
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name = 'send_message';

