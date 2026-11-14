-- READ-ONLY validation for the separately verified CampusShare-Staging project.
-- Confirm the project name/reference in the dashboard before running manually.
-- Never use this as a production migration. This file contains SELECT queries only.
-- It does not return table row contents.

SELECT current_database() AS database_name,
       current_user AS database_role,
       current_setting('server_version') AS postgres_version,
       now() AS inspected_at;

-- Table columns, types, nullability, identity mode, and defaults.
SELECT table_schema,
       table_name,
       ordinal_position,
       column_name,
       data_type,
       udt_name,
       is_nullable,
       column_default,
       is_identity,
       identity_generation
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('profiles', 'categories', 'resources', 'borrow_requests')
ORDER BY table_name, ordinal_position;

-- Primary, foreign, unique, and check constraints with exact definitions.
SELECT constraint_ns.nspname AS schema_name,
       table_rel.relname AS table_name,
       constraint_row.conname AS constraint_name,
       CASE constraint_row.contype
           WHEN 'p' THEN 'PRIMARY KEY'
           WHEN 'f' THEN 'FOREIGN KEY'
           WHEN 'u' THEN 'UNIQUE'
           WHEN 'c' THEN 'CHECK'
           ELSE constraint_row.contype::text
       END AS constraint_type,
       pg_get_constraintdef(constraint_row.oid, true) AS constraint_definition,
       referenced_rel.oid::regclass AS referenced_table,
       constraint_row.convalidated AS is_validated
FROM pg_constraint AS constraint_row
JOIN pg_class AS table_rel ON table_rel.oid = constraint_row.conrelid
JOIN pg_namespace AS constraint_ns ON constraint_ns.oid = table_rel.relnamespace
LEFT JOIN pg_class AS referenced_rel ON referenced_rel.oid = constraint_row.confrelid
WHERE constraint_ns.nspname = 'public'
  AND table_rel.relname IN ('profiles', 'categories', 'resources', 'borrow_requests')
ORDER BY table_rel.relname, constraint_row.contype, constraint_row.conname;

-- All indexes, including predicates and validity/readiness state.
SELECT table_ns.nspname AS schema_name,
       table_rel.relname AS table_name,
       index_rel.relname AS index_name,
       index_row.indisprimary AS is_primary,
       index_row.indisunique AS is_unique,
       index_row.indisvalid AS is_valid,
       index_row.indisready AS is_ready,
       pg_get_expr(index_row.indpred, index_row.indrelid) AS predicate,
       pg_get_indexdef(index_row.indexrelid) AS index_definition
FROM pg_index AS index_row
JOIN pg_class AS table_rel ON table_rel.oid = index_row.indrelid
JOIN pg_namespace AS table_ns ON table_ns.oid = table_rel.relnamespace
JOIN pg_class AS index_rel ON index_rel.oid = index_row.indexrelid
WHERE table_ns.nspname = 'public'
  AND table_rel.relname IN ('profiles', 'categories', 'resources', 'borrow_requests')
ORDER BY table_rel.relname, index_rel.relname;

-- RLS flags and full policy expressions.
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

-- Effective schema USAGE, including inherited role membership.
SELECT role_row.role_name,
       has_schema_privilege(role_row.role_name, 'public', 'USAGE') AS can_use_public_schema,
       has_schema_privilege(role_row.role_name, 'public', 'CREATE') AS can_create_in_public
FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS role_row(role_name)
ORDER BY role_row.role_name;

-- Effective table privileges, including inherited role membership. This
-- complements the raw grant listings below.
SELECT role_row.role_name,
       table_row.table_name,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'SELECT') AS can_select,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'INSERT') AS can_insert,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'UPDATE') AS can_update,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'DELETE') AS can_delete,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'TRUNCATE') AS can_truncate,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'REFERENCES') AS can_reference,
       has_table_privilege(role_row.role_name, format('public.%I', table_row.table_name), 'TRIGGER') AS can_create_trigger
FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS role_row(role_name)
CROSS JOIN (VALUES ('profiles'), ('categories'), ('resources'), ('borrow_requests')) AS table_row(table_name)
ORDER BY role_row.role_name, table_row.table_name;

-- Effective per-column rights; detects column ACLs and table-level rights.
SELECT role_row.role_name,
       column_row.table_name,
       column_row.column_name,
       has_column_privilege(role_row.role_name, format('public.%I', column_row.table_name), column_row.column_name, 'SELECT') AS can_select,
       has_column_privilege(role_row.role_name, format('public.%I', column_row.table_name), column_row.column_name, 'INSERT') AS can_insert,
       has_column_privilege(role_row.role_name, format('public.%I', column_row.table_name), column_row.column_name, 'UPDATE') AS can_update,
       has_column_privilege(role_row.role_name, format('public.%I', column_row.table_name), column_row.column_name, 'REFERENCES') AS can_reference
FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS role_row(role_name)
JOIN information_schema.columns AS column_row
  ON column_row.table_schema = 'public'
 AND column_row.table_name IN ('profiles', 'categories', 'resources', 'borrow_requests')
ORDER BY role_row.role_name, column_row.table_name, column_row.ordinal_position;

-- Table-level grants as exposed by the information schema.
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

-- Explicit column-level grants.
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

-- Related routines: definitions, result types, owners, security settings, ACLs,
-- and effective execution access. Empty results for omitted RPCs are expected.
SELECT namespace_row.nspname AS schema_name,
       function_row.proname AS function_name,
       function_row.oid::regprocedure AS exact_signature,
       pg_get_function_arguments(function_row.oid) AS arguments,
       pg_get_function_result(function_row.oid) AS return_type,
       pg_get_userbyid(function_row.proowner) AS function_owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_configuration,
       function_row.proacl AS raw_execute_acl,
       has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_can_execute_effectively,
       has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_can_execute_effectively,
       has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_can_execute_effectively,
       pg_get_functiondef(function_row.oid) AS function_definition
FROM pg_proc AS function_row
JOIN pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE namespace_row.nspname = 'public'
  AND function_row.proname IN (
      'handle_new_user',
      'create_borrow_request',
      'update_resource_atomic',
      'set_resource_availability',
      'approve_borrow_request',
      'reject_borrow_request',
      'return_borrowed_resource'
  )
ORDER BY function_row.proname, function_row.oid::regprocedure::text;

-- Auth user trigger attachment and referenced function metadata.
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
       pg_get_functiondef(function_row.oid) AS trigger_function_definition
FROM pg_trigger AS trigger_row
JOIN pg_class AS table_rel ON table_rel.oid = trigger_row.tgrelid
JOIN pg_namespace AS trigger_ns ON trigger_ns.oid = table_rel.relnamespace
JOIN pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_namespace AS function_ns ON function_ns.oid = function_row.pronamespace
WHERE trigger_ns.nspname = 'auth'
  AND table_rel.relname = 'users'
  AND NOT trigger_row.tgisinternal
ORDER BY trigger_row.tgname;
