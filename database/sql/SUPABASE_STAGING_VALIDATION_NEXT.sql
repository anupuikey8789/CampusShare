-- CampusShare-Staging follow-up validation.
-- Run one SELECT query at a time in the SQL Editor for the project named
-- CampusShare-Staging (reference jxndjuslvccxgayoachm). Do not run in production.
-- Read-only: this file contains SELECT statements only and returns no table rows
-- from profiles/resources/borrow_requests and no Auth email/password/token data.

-- QUERY 1 — Signup smoke check: profile exists and ID/email match the Auth user.
-- Replace the UUID literal with the fresh test user's Auth UUID locally.
-- Output contains booleans only; do not paste the UUID or other account data in chat.
WITH test_user AS (
    SELECT id, email
    FROM auth.users
    WHERE id = 'PASTE_FRESH_STAGING_TEST_USER_UUID_HERE'::uuid
)
SELECT EXISTS (SELECT 1 FROM test_user) AS auth_user_found,
       EXISTS (
           SELECT 1
           FROM public.profiles AS p
           JOIN test_user AS u ON p.email IS NOT DISTINCT FROM u.email
       ) AS profile_found,
       EXISTS (
           SELECT 1
           FROM public.profiles AS p
           JOIN test_user AS u ON u.id = p.id
       ) AS profile_id_matches,
       EXISTS (
           SELECT 1
           FROM public.profiles AS p
           JOIN test_user AS u ON u.id = p.id
           WHERE p.email IS NOT DISTINCT FROM u.email
       ) AS profile_email_matches;

-- QUERY 2 — Effective table permissions for API roles.
SELECT role_row.role_name,
       table_row.table_name,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'SELECT') AS can_select,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'INSERT') AS can_insert,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'UPDATE') AS can_update,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'DELETE') AS can_delete,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'TRUNCATE') AS can_truncate
FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS role_row(role_name)
CROSS JOIN (VALUES ('profiles'), ('categories'), ('resources'), ('borrow_requests')) AS table_row(table_name)
ORDER BY role_row.role_name, table_row.table_name;

-- QUERY 3 — RLS enabled/forced status for all four application tables.
SELECT table_row.relname AS table_name,
       table_row.relrowsecurity AS rls_enabled,
       table_row.relforcerowsecurity AS rls_forced
FROM pg_class AS table_row
JOIN pg_namespace AS schema_row ON schema_row.oid = table_row.relnamespace
WHERE schema_row.nspname = 'public'
  AND table_row.relname IN ('profiles', 'categories', 'resources', 'borrow_requests')
  AND table_row.relkind IN ('r', 'p')
ORDER BY table_row.relname;

-- QUERY 4 — Full RLS policy expressions on the four application tables.
SELECT policy.schemaname,
       policy.tablename,
       policy.policyname,
       policy.permissive,
       policy.roles,
       policy.cmd,
       policy.qual AS using_expression,
       policy.with_check AS with_check_expression
FROM pg_policies AS policy
WHERE policy.schemaname = 'public'
  AND policy.tablename IN ('profiles', 'categories', 'resources', 'borrow_requests')
ORDER BY policy.tablename, policy.cmd, policy.policyname;

-- QUERY 5 — Indexes and predicates, including the active-request unique index.
SELECT table_row.relname AS table_name,
       index_row.relname AS index_name,
       pg_index.indisunique AS is_unique,
       pg_index.indisvalid AS is_valid,
       pg_index.indisready AS is_ready,
       pg_get_expr(pg_index.indpred, pg_index.indrelid) AS predicate,
       pg_get_indexdef(pg_index.indexrelid) AS index_definition
FROM pg_index
JOIN pg_class AS table_row ON table_row.oid = pg_index.indrelid
JOIN pg_namespace AS schema_row ON schema_row.oid = table_row.relnamespace
JOIN pg_class AS index_row ON index_row.oid = pg_index.indexrelid
WHERE schema_row.nspname = 'public'
  AND table_row.relname IN ('profiles', 'categories', 'resources', 'borrow_requests')
ORDER BY table_row.relname, index_row.relname;

-- QUERY 6 — Status RPC signatures, owner, security mode, search_path, and ACL.
-- This returns function metadata only; use QUERY 7 for full function source.
SELECT function_row.proname AS function_name,
       function_row.oid::regprocedure AS exact_signature,
       pg_get_function_arguments(function_row.oid) AS arguments,
       pg_get_function_result(function_row.oid) AS return_type,
       pg_get_userbyid(function_row.proowner) AS function_owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_configuration,
       function_row.proacl AS execute_acl,
       has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_can_execute,
       has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_can_execute
FROM pg_proc AS function_row
JOIN pg_namespace AS schema_row ON schema_row.oid = function_row.pronamespace
WHERE schema_row.nspname = 'public'
  AND function_row.proname IN (
      'approve_borrow_request',
      'reject_borrow_request',
      'return_borrowed_resource'
  )
ORDER BY function_row.proname, function_row.oid::regprocedure::text;

-- QUERY 7 — Full definitions of the three status RPCs.
-- Inspect results privately; do not share a result if it contains a credential.
SELECT function_row.oid::regprocedure AS exact_signature,
       pg_get_functiondef(function_row.oid) AS full_function_definition
FROM pg_proc AS function_row
JOIN pg_namespace AS schema_row ON schema_row.oid = function_row.pronamespace
WHERE schema_row.nspname = 'public'
  AND function_row.proname IN (
      'approve_borrow_request',
      'reject_borrow_request',
      'return_borrowed_resource'
  )
ORDER BY function_row.proname, function_row.oid::regprocedure::text;

-- QUERY 8 — Auth trigger and trigger-function metadata/configuration.
-- No Auth user rows or profile rows are returned.
SELECT trigger_row.tgname AS trigger_name,
       pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
       trigger_row.tgenabled AS trigger_enabled_code,
       function_row.oid::regprocedure AS trigger_function_signature,
       pg_get_userbyid(function_row.proowner) AS function_owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_configuration,
       function_row.proacl AS execute_acl,
       has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_can_execute,
       has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_can_execute
FROM pg_trigger AS trigger_row
JOIN pg_class AS table_row ON table_row.oid = trigger_row.tgrelid
JOIN pg_namespace AS table_schema ON table_schema.oid = table_row.relnamespace
JOIN pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
WHERE table_schema.nspname = 'auth'
  AND table_row.relname = 'users'
  AND trigger_row.tgname = 'on_auth_user_created'
  AND NOT trigger_row.tgisinternal;
