-- READ-ONLY checks for CampusShare-Staging marketplace rollout.
-- Select and run one query at a time. No record contents or personal data are returned.
-- Do not use against production. Codex did not execute these queries.

-- 1. Marketplace columns and table shapes.
SELECT table_name,column_name,data_type,is_nullable,column_default FROM information_schema.columns
WHERE table_schema='public' AND table_name IN('resources','resource_transfer_requests','resource_images','resource_handover_details','resource_listing_reports')
ORDER BY table_name,ordinal_position;

-- 2. Constraints and foreign keys.
SELECT c.conrelid::regclass AS table_name,c.conname,pg_catalog.pg_get_constraintdef(c.oid,true) AS definition
FROM pg_catalog.pg_constraint c WHERE c.connamespace='public'::regnamespace AND c.conrelid IN('public.resources'::regclass,'public.borrow_requests'::regclass,'public.resource_transfer_requests'::regclass,'public.resource_images'::regclass,'public.resource_handover_details'::regclass,'public.resource_listing_reports'::regclass)
ORDER BY table_name::text,c.conname;

-- 3. Indexes, including concurrency guards for active requests and image slots.
SELECT t.relname AS table_name,i.relname AS index_name,x.indisunique,x.indisvalid,pg_catalog.pg_get_indexdef(x.indexrelid) AS definition
FROM pg_catalog.pg_index x JOIN pg_catalog.pg_class i ON i.oid=x.indexrelid JOIN pg_catalog.pg_class t ON t.oid=x.indrelid JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
WHERE n.nspname='public' AND t.relname IN('resources','borrow_requests','resource_transfer_requests','resource_images','resource_handover_details','resource_listing_reports')
ORDER BY t.relname,i.relname;

-- 4. RLS enabled status and exact marketplace policy expressions.
SELECT c.relname,c.relrowsecurity,c.relforcerowsecurity FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN('resources','borrow_requests','resource_transfer_requests','resource_images','resource_handover_details','resource_listing_reports') ORDER BY c.relname;
SELECT schemaname,tablename,policyname,roles,cmd,qual,with_check FROM pg_catalog.pg_policies
WHERE (schemaname='public' AND tablename IN('resources','borrow_requests','resource_transfer_requests','resource_images','resource_handover_details','resource_listing_reports')) OR (schemaname='storage' AND tablename='objects' AND policyname LIKE 'CampusShare %')
ORDER BY schemaname,tablename,policyname;

-- 5. Table/schema grants only as effective booleans; no rows or credentials.
SELECT role_name,has_schema_privilege(role_name,'public','USAGE') AS public_usage,
 has_table_privilege(role_name,'public.resources','SELECT') AS resources_select,
 has_table_privilege(role_name,'public.resources','INSERT') AS resources_insert,
 has_table_privilege(role_name,'public.resources','UPDATE') AS resources_update,
 has_table_privilege(role_name,'public.borrow_requests','INSERT') AS borrow_direct_insert,
 has_table_privilege(role_name,'public.borrow_requests','UPDATE') AS borrow_direct_update,
 has_table_privilege(role_name,'public.resource_transfer_requests','INSERT') AS transfers_direct_insert,
 has_table_privilege(role_name,'public.resource_transfer_requests','UPDATE') AS transfers_direct_update,
 has_table_privilege(role_name,'public.resource_images','INSERT') AS image_metadata_insert,
 has_table_privilege(role_name,'public.resource_images','UPDATE') AS image_metadata_update,
 has_table_privilege(role_name,'public.resource_handover_details','UPDATE') AS handover_update,
 has_table_privilege(role_name,'public.resource_listing_reports','UPDATE') AS reports_direct_update
FROM (VALUES('anon'),('authenticated'),('service_role')) roles(role_name) ORDER BY role_name;

-- 6. Function signatures, owner, security mode, search_path config and execute ACL.
SELECT p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,pg_catalog.pg_get_function_result(p.oid) AS result_type,owner.rolname AS owner,p.prosecdef,p.proconfig,p.proacl,
 has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
 has_function_privilege('service_role',p.oid,'EXECUTE') AS service_role_execute
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace JOIN pg_catalog.pg_roles owner ON owner.oid=p.proowner
WHERE n.nspname='public' AND p.proname IN('create_borrow_request','approve_borrow_request','reject_borrow_request','return_borrowed_resource','update_resource_atomic','create_resource_transfer_request','approve_resource_transfer_request','reject_resource_transfer_request','cancel_resource_transfer_request','complete_resource_sale','complete_resource_donation','update_marketplace_resource_atomic','register_resource_images','delete_resource_image_metadata','reorder_resource_images','review_resource_listing_report')
ORDER BY p.proname,arguments;

-- 7. Full function definitions (no row data).
SELECT p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,pg_catalog.pg_get_functiondef(p.oid) AS definition
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN('create_borrow_request','approve_borrow_request','reject_borrow_request','return_borrowed_resource','update_resource_atomic','create_resource_transfer_request','approve_resource_transfer_request','reject_resource_transfer_request','cancel_resource_transfer_request','complete_resource_sale','complete_resource_donation','update_marketplace_resource_atomic','register_resource_images','delete_resource_image_metadata','reorder_resource_images','review_resource_listing_report')
ORDER BY p.proname,arguments;

-- 8. Auth profile trigger and resource validation trigger. Function source can be read separately if needed.
SELECT trigger_name,event_object_schema,event_object_table,event_manipulation,action_timing,action_statement
FROM information_schema.triggers WHERE (event_object_schema='auth' AND event_object_table='users' AND trigger_name='on_auth_user_created') OR (event_object_schema='public' AND event_object_table='resources' AND trigger_name='campusshare_validate_resource_listing')
ORDER BY event_object_schema,event_object_table,trigger_name;
SELECT p.proname,owner.rolname AS owner,p.prosecdef,p.proconfig,p.proacl
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace JOIN pg_catalog.pg_roles owner ON owner.oid=p.proowner
WHERE n.nspname='public' AND p.proname IN('handle_new_user','validate_resource_listing');

-- 9. Private bucket settings and named Storage policies only.
SELECT id,name,public,file_size_limit,allowed_mime_types FROM storage.buckets WHERE id='campusshare-resource-images';
SELECT policyname,roles,cmd,qual,with_check FROM pg_catalog.pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'CampusShare %' ORDER BY policyname;

-- 10. Aggregate consistency checks only; no user or resource details.
SELECT (SELECT count(*) FROM public.resource_transfer_requests WHERE status='approved') AS approved_transfers,
 (SELECT count(*) FROM public.resource_transfer_requests t JOIN public.resources r ON r.id=t.resource_id WHERE t.status='approved' AND (r.availability_status<>'unavailable' OR r.listing_state<>'reserved')) AS approved_transfer_state_mismatch,
 (SELECT count(*) FROM public.resources WHERE listing_state IN('sold','donated') AND availability_status<>'unavailable') AS terminal_listing_mismatch,
 (SELECT count(*) FROM (SELECT resource_id FROM public.resource_images GROUP BY resource_id HAVING count(*)>10) q) AS resources_over_image_limit;
