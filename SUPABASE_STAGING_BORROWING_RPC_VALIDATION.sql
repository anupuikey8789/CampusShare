-- READ-ONLY validation for CampusShare-Staging.
-- Verify project reference jxndjuslvccxgayoachm in the Supabase dashboard first.
-- Run one SELECT at a time. Every statement in this file is read-only.
-- Outputs schema/catalog metadata and aggregate invariant counts only; no row contents,
-- emails, identities, tokens, keys, or passwords are selected.

-- 1. Confirm the SQL Editor role and database context (not a project-ref proof).
SELECT current_database() AS database_name, current_user AS editor_role;

-- 2. Review the exact table columns, types, nullability, and defaults used by the RPCs.
SELECT table_name, column_name, data_type, is_nullable, column_default, is_identity
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name IN ('profiles','categories','resources','borrow_requests')
ORDER BY table_name, ordinal_position;

-- 3. Review the table constraints, foreign-key targets, and check expressions.
SELECT c.conrelid::regclass AS table_name, c.conname AS constraint_name,
       c.contype AS constraint_type, pg_catalog.pg_get_constraintdef(c.oid, true) AS definition
FROM pg_catalog.pg_constraint AS c
WHERE c.connamespace='public'::regnamespace
  AND c.conrelid IN (
      'public.profiles'::regclass, 'public.categories'::regclass,
      'public.resources'::regclass, 'public.borrow_requests'::regclass
  )
ORDER BY table_name::text, constraint_name;

-- 4. Review RLS enabled/forced status.
SELECT n.nspname AS schema_name, c.relname AS table_name,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN ('profiles','categories','resources','borrow_requests')
ORDER BY c.relname;

-- 5. Review all public policies and their exact expressions.
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_catalog.pg_policies
WHERE schemaname='public'
  AND tablename IN ('profiles','categories','resources','borrow_requests')
ORDER BY tablename, policyname;

-- 6. Review indexes, validity, uniqueness, and predicates.
SELECT t.relname AS table_name, i.relname AS index_name,
       x.indisunique AS is_unique, x.indisvalid AS is_valid, x.indisready AS is_ready,
       pg_catalog.pg_get_indexdef(x.indexrelid) AS definition
FROM pg_catalog.pg_index AS x
JOIN pg_catalog.pg_class AS i ON i.oid=x.indexrelid
JOIN pg_catalog.pg_class AS t ON t.oid=x.indrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid=t.relnamespace
WHERE n.nspname='public'
  AND t.relname IN ('profiles','categories','resources','borrow_requests')
ORDER BY t.relname, i.relname;

-- 7. Review effective table/schema privileges; booleans only.
SELECT role_name,
       has_schema_privilege(role_name, 'public', 'USAGE') AS public_schema_usage,
       has_table_privilege(role_name, 'public.profiles', 'SELECT') AS profiles_select,
       has_table_privilege(role_name, 'public.profiles', 'UPDATE') AS profiles_update,
       has_table_privilege(role_name, 'public.categories', 'SELECT') AS categories_select,
       has_table_privilege(role_name, 'public.resources', 'SELECT') AS resources_select,
       has_table_privilege(role_name, 'public.resources', 'INSERT') AS resources_insert,
       has_table_privilege(role_name, 'public.resources', 'UPDATE') AS resources_update,
       has_column_privilege(role_name, 'public.resources', 'availability_status', 'UPDATE')
           AS resources_availability_status_update,
       has_column_privilege(role_name, 'public.resources', 'title', 'UPDATE') AS resources_title_update,
       has_column_privilege(role_name, 'public.resources', 'description', 'UPDATE') AS resources_description_update,
       has_column_privilege(role_name, 'public.resources', 'category_id', 'UPDATE') AS resources_category_id_update,
       has_column_privilege(role_name, 'public.resources', 'resource_type', 'UPDATE') AS resources_type_update,
       has_table_privilege(role_name, 'public.resources', 'DELETE') AS resources_delete,
       has_table_privilege(role_name, 'public.borrow_requests', 'SELECT') AS requests_select,
       has_table_privilege(role_name, 'public.borrow_requests', 'INSERT') AS requests_insert,
       has_table_privilege(role_name, 'public.borrow_requests', 'UPDATE') AS requests_update
FROM (VALUES ('anon'),('authenticated'),('service_role')) AS roles(role_name)
ORDER BY role_name;

-- 8. Aggregate-only race/invariant preflight; no borrower/resource IDs are returned.
SELECT
  (SELECT count(*) FROM (
      SELECT borrower_id, resource_id
      FROM public.borrow_requests
      WHERE status IN ('pending','approved')
      GROUP BY borrower_id, resource_id
      HAVING count(*) > 1
  ) AS duplicate_pairs) AS duplicate_active_borrower_resource_groups,
  (SELECT count(*) FROM public.borrow_requests AS b
      JOIN public.resources AS r ON r.id=b.resource_id
      WHERE b.status='approved' AND r.availability_status <> 'unavailable'
  ) AS approved_requests_with_non_unavailable_resources;

-- 9. Function signatures, result types, owners, SECURITY DEFINER, search_path, and ACL.
SELECT n.nspname AS schema_name, p.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_catalog.pg_get_function_result(p.oid) AS result_type,
       owner.rolname AS function_owner, p.prosecdef AS security_definer,
       p.proconfig AS function_settings, p.proacl AS execute_acl,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
JOIN pg_catalog.pg_roles AS owner ON owner.oid=p.proowner
WHERE n.nspname='public'
  AND p.proname IN (
      'create_borrow_request','approve_borrow_request','reject_borrow_request',
      'return_borrowed_resource','update_resource_atomic'
  )
ORDER BY p.proname, identity_arguments;

-- 10. Full definitions. Verify each uses SET search_path = '', derives auth.uid(),
-- rejects anonymous identities, and locks resources before request rows.
SELECT p.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_catalog.pg_get_functiondef(p.oid) AS complete_definition
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN (
      'create_borrow_request','approve_borrow_request','reject_borrow_request',
      'return_borrowed_resource','update_resource_atomic'
  )
ORDER BY p.proname, identity_arguments;

-- 11. Expanded function ACL entries (ACL only; no routine body or user data).
SELECT p.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee) END AS grantee,
       a.privilege_type, a.is_grantable
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
) AS a
WHERE n.nspname='public'
  AND p.proname IN (
      'create_borrow_request','approve_borrow_request','reject_borrow_request',
      'return_borrowed_resource','update_resource_atomic'
  )
ORDER BY p.proname, identity_arguments, grantee, a.privilege_type;

-- 12. Compare function comments with the migration ownership marker used by rollback.
SELECT p.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_catalog.obj_description(p.oid, 'pg_proc') AS migration_marker
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN (
      'create_borrow_request','approve_borrow_request','reject_borrow_request',
      'return_borrowed_resource','update_resource_atomic'
  )
ORDER BY p.proname, identity_arguments;
