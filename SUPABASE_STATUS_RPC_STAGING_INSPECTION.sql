-- READ-ONLY INSPECTION QUERIES ONLY.
-- Run this script manually in the SQL Editor of a separate, disposable STAGING
-- Supabase project after checking its project reference in the dashboard.
-- Do not run this script in production. It contains only SELECT statements and
-- does not change database objects, privileges, policies, or rows.
-- Results may include routine source code and policy expressions; keep them in
-- the project security review and do not publish tokens or row data.

-- Identify the connected database context before reviewing any result.
SELECT current_database() AS database_name,
       current_user AS database_role,
       current_setting('server_version') AS postgres_version,
       now() AS inspected_at;

-- Exact public status/request/resource function definitions and catalog
-- properties. This displays source, argument names/types, result type, owner,
-- security mode, function configuration, and effective role access.
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       p.oid::regprocedure AS exact_signature,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_get_function_arguments(p.oid) AS declared_arguments,
       pg_get_function_result(p.oid) AS return_type,
       pg_get_userbyid(p.proowner) AS function_owner,
       CASE WHEN p.prosecdef THEN 'SECURITY DEFINER' ELSE 'SECURITY INVOKER' END AS security_mode,
       p.proconfig AS function_configuration,
       p.proacl AS raw_execute_acl,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute_effectively,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute_effectively,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute_effectively,
       pg_get_functiondef(p.oid) AS complete_definition
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'approve_borrow_request',
      'reject_borrow_request',
      'return_borrowed_resource',
      'create_borrow_request',
      'update_resource_atomic',
      'set_resource_availability'
  )
ORDER BY p.proname, p.oid::regprocedure::text;

-- Expand routine ACLs, including the default ACL when the catalog ACL is NULL.
-- Grantee OID zero is the PUBLIC pseudo-role.
SELECT p.oid::regprocedure AS exact_signature,
       CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee.rolname END AS grantee,
       grantor.rolname AS grantor,
       acl.privilege_type,
       acl.is_grantable
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(
    COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
) AS acl
LEFT JOIN pg_roles AS grantee ON grantee.oid = acl.grantee
JOIN pg_roles AS grantor ON grantor.oid = acl.grantor
WHERE n.nspname = 'public'
  AND p.proname IN (
      'approve_borrow_request',
      'reject_borrow_request',
      'return_borrowed_resource',
      'create_borrow_request',
      'update_resource_atomic',
      'set_resource_availability'
  )
ORDER BY p.oid::regprocedure::text, grantee;

-- Auth profile trigger attachment and the complete trigger-function body.
SELECT trigger_ns.nspname AS table_schema,
       table_rel.relname AS table_name,
       trigger_row.tgname AS trigger_name,
       pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
       trigger_row.tgenabled AS trigger_enabled_state,
       function_ns.nspname AS function_schema,
       function_row.oid::regprocedure AS trigger_function_signature,
       pg_get_userbyid(function_row.proowner) AS function_owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_configuration,
       function_row.proacl AS raw_execute_acl,
       pg_get_functiondef(function_row.oid) AS complete_function_definition
FROM pg_trigger AS trigger_row
JOIN pg_class AS table_rel ON table_rel.oid = trigger_row.tgrelid
JOIN pg_namespace AS trigger_ns ON trigger_ns.oid = table_rel.relnamespace
JOIN pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_namespace AS function_ns ON function_ns.oid = function_row.pronamespace
WHERE trigger_ns.nspname = 'auth'
  AND table_rel.relname = 'users'
  AND NOT trigger_row.tgisinternal
ORDER BY trigger_row.tgname;

-- RLS state and policies for the application tables. The policy expressions
-- are included in full so USING and WITH CHECK are not inferred from names.
SELECT table_rel.oid::regclass AS table_name,
       table_rel.relrowsecurity AS row_level_security_enabled,
       table_rel.relforcerowsecurity AS row_level_security_forced,
       policy.policyname,
       policy.permissive,
       policy.roles,
       policy.cmd,
       policy.qual AS using_expression,
       policy.with_check AS with_check_expression
FROM pg_class AS table_rel
JOIN pg_namespace AS table_ns ON table_ns.oid = table_rel.relnamespace
LEFT JOIN pg_policies AS policy
       ON policy.schemaname = table_ns.nspname
      AND policy.tablename = table_rel.relname
WHERE table_ns.nspname = 'public'
  AND table_rel.relname IN ('profiles', 'categories', 'resources', 'borrow_requests')
ORDER BY table_rel.relname, policy.cmd, policy.policyname;

-- Effective table-level privileges reported by the information schema.
SELECT table_schema,
       table_name,
       grantee,
       grantor,
       privilege_type,
       is_grantable,
       with_hierarchy
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name IN ('profiles', 'categories', 'resources', 'borrow_requests')
ORDER BY table_name, grantee, privilege_type;

-- Explicit column-level ACLs on the same application tables.
SELECT table_ns.nspname AS schema_name,
       table_rel.relname AS table_name,
       attribute.attname AS column_name,
       CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee.rolname END AS grantee,
       grantor.rolname AS grantor,
       acl.privilege_type,
       acl.is_grantable
FROM pg_attribute AS attribute
JOIN pg_class AS table_rel ON table_rel.oid = attribute.attrelid
JOIN pg_namespace AS table_ns ON table_ns.oid = table_rel.relnamespace
CROSS JOIN LATERAL aclexplode(attribute.attacl) AS acl
LEFT JOIN pg_roles AS grantee ON grantee.oid = acl.grantee
JOIN pg_roles AS grantor ON grantor.oid = acl.grantor
WHERE table_ns.nspname = 'public'
  AND table_rel.relname IN ('profiles', 'categories', 'resources', 'borrow_requests')
  AND attribute.attnum > 0
  AND NOT attribute.attisdropped
  AND attribute.attacl IS NOT NULL
ORDER BY table_rel.relname, attribute.attnum, grantee, acl.privilege_type;
