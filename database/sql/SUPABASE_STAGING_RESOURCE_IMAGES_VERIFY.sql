-- Read-only validation for CampusShare-Staging resource images.
-- Run only after reviewing/applying the staging proposals. No row or secret
-- values are returned. Execute one SELECT at a time in the SQL Editor.

-- 1. Confirm the exact metadata columns and defaults.
SELECT column_name,data_type,is_nullable,column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='resource_images'
ORDER BY ordinal_position;

-- 2. Confirm PK, FK, length/order checks, and unique image/order constraints.
SELECT c.conname,pg_catalog.pg_get_constraintdef(c.oid,true) AS definition
FROM pg_catalog.pg_constraint c
WHERE c.conrelid=to_regclass('public.resource_images')
ORDER BY c.conname;

-- 3. Confirm the supporting index definitions and validity.
SELECT i.relname AS index_name,x.indisunique,x.indisvalid,
       pg_catalog.pg_get_indexdef(x.indexrelid) AS definition
FROM pg_catalog.pg_index AS x
JOIN pg_catalog.pg_class AS i ON i.oid=x.indexrelid
WHERE x.indrelid=to_regclass('public.resource_images')
ORDER BY i.relname;

-- 4. Confirm table RLS is enabled.
SELECT c.relrowsecurity,c.relforcerowsecurity
FROM pg_catalog.pg_class c
WHERE c.oid=to_regclass('public.resource_images');

-- 5. Review exact metadata policies; these expressions contain no row data.
SELECT policyname,permissive,roles,cmd,qual,with_check
FROM pg_catalog.pg_policies
WHERE schemaname='public' AND tablename='resource_images'
ORDER BY policyname;

-- 6. Review effective application table privileges (booleans only).
SELECT role_name,
       has_schema_privilege(role_name,'public','USAGE') AS public_schema_usage,
       COALESCE(has_table_privilege(role_name,to_regclass('public.resource_images'),'SELECT'),false) AS can_select,
       COALESCE(has_table_privilege(role_name,to_regclass('public.resource_images'),'INSERT'),false) AS can_insert,
       COALESCE(has_table_privilege(role_name,to_regclass('public.resource_images'),'UPDATE'),false) AS can_update,
       COALESCE(has_table_privilege(role_name,to_regclass('public.resource_images'),'DELETE'),false) AS can_delete
FROM (VALUES ('anon'),('authenticated'),('service_role')) AS roles(role_name)
ORDER BY role_name;

-- 7. Confirm bucket settings; does not list objects.
SELECT id,name,public,file_size_limit,allowed_mime_types
FROM storage.buckets
WHERE id='campusshare-resource-images';

-- 8. Inspect EVERY storage.objects policy (no object names/data). PostgreSQL's
-- permissive policies combine with OR. Any candidate shown below can expand
-- access unless its full expression scopes the bucket and path correctly.
SELECT policyname,permissive,roles,cmd,qual,with_check,
       CASE WHEN permissive='PERMISSIVE'
                  AND roles && ARRAY['public','anon','authenticated']::name[]
                  AND cmd IN ('ALL','SELECT','INSERT','UPDATE','DELETE')
            THEN 'REVIEW: may broaden access for the CampusShare bucket'
            ELSE 'Does not add a permissive grant to anon/authenticated/PUBLIC'
       END AS access_review
FROM pg_catalog.pg_policies
WHERE schemaname='storage' AND tablename='objects'
ORDER BY policyname;

-- 9. Confirm the image RPC signatures, owner, SECURITY DEFINER and search_path.
-- Execute privileges should be false before RPC_ENABLE and true only for authenticated after it.
SELECT p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_catalog.pg_get_function_result(p.oid) AS result_type,owner.rolname AS function_owner,
       p.prosecdef,p.proconfig,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') AS service_role_execute
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
JOIN pg_catalog.pg_roles owner ON owner.oid=p.proowner
WHERE n.nspname='public' AND p.proname IN
 ('register_resource_images','delete_resource_image_metadata','reorder_resource_images')
ORDER BY p.proname;

-- 10. Read full image RPC definitions; inspect auth.uid(), owner/resource locks,
-- Storage object existence, input validation, and absence of client user IDs.
SELECT p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_catalog.pg_get_functiondef(p.oid) AS definition
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('register_resource_images','delete_resource_image_metadata','reorder_resource_images')
ORDER BY p.proname;

-- 11. Confirm no direct table-write privilege is required by the RPC design.
SELECT role_name,
       COALESCE(has_table_privilege(role_name,to_regclass('public.resource_images'),'SELECT'),false) AS can_select,
       COALESCE(has_table_privilege(role_name,to_regclass('public.resource_images'),'INSERT'),false) AS can_insert,
       COALESCE(has_table_privilege(role_name,to_regclass('public.resource_images'),'UPDATE'),false) AS can_update,
       COALESCE(has_table_privilege(role_name,to_regclass('public.resource_images'),'DELETE'),false) AS can_delete
FROM (VALUES ('anon'),('authenticated'),('service_role')) AS roles(role_name)
ORDER BY role_name;
