-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 6 VERIFICATION
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- ============================================================================

-- 1. Check borrow_requests status check constraint definition
SELECT conname, pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
WHERE t.relname = 'borrow_requests'
  AND c.conname = 'chk_borrow_requests_status';

-- 2. Verify active borrow requests unique index includes return_requested
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'borrow_requests'
  AND indexname = 'idx_borrow_requests_one_active';

-- 3. Verify request_return RPC signature and ownership
SELECT proname, pg_get_function_identity_arguments(p.oid) AS args,
       proowner::regrole AS owner, prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('request_return', 'return_borrowed_resource');

