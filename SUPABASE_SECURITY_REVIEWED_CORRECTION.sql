-- REVIEWED PROPOSAL ONLY. DO NOT EXECUTE IN PRODUCTION WITHOUT EXPLICIT APPROVAL.
-- Based on the 2026-11-10 read-only snapshot for dkyfkdmlkghucyepxbbh.
-- Re-run the audit and rehearse in staging. No existing policy/function/index is dropped.
-- Phase 1 preserves current backend direct writes, with stricter checks but residual races.
-- Phase 2/3 require a compatible C++ backend release; never apply their final revokes early.

-- PHASE 1: independent hardening.
BEGIN;
DO $preflight$
DECLARE v_rls integer; v_ins integer; v_dupes bigint;
BEGIN
 SELECT count(*) INTO v_rls FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname IN ('profiles','categories','resources','borrow_requests') AND c.relrowsecurity;
 IF v_rls<>4 THEN RAISE EXCEPTION 'Expected RLS on all four tables'; END IF;
 SELECT count(*) INTO v_ins FROM pg_policies WHERE schemaname='public' AND tablename='borrow_requests' AND cmd='INSERT';
 IF v_ins<>1 OR NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='borrow_requests' AND policyname='Create own borrow requests' AND cmd='INSERT')
 THEN RAISE EXCEPTION 'Borrow INSERT policies differ from reviewed snapshot'; END IF;
 SELECT count(*) INTO v_dupes FROM (SELECT borrower_id,resource_id FROM public.borrow_requests WHERE status='pending' GROUP BY borrower_id,resource_id HAVING count(*)>1)d;
 IF v_dupes<>0 THEN RAISE EXCEPTION 'Resolve pending duplicates manually'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_index WHERE indexrelid=to_regclass('public.one_active_approval_per_resource') AND indisunique AND indisvalid) THEN RAISE EXCEPTION 'Existing approved-request unique index missing or invalid'; END IF;
 IF to_regprocedure('public.approve_borrow_request(bigint,timestamp with time zone)') IS NULL
 OR to_regprocedure('public.reject_borrow_request(bigint)') IS NULL
 OR to_regprocedure('public.return_borrowed_resource(bigint)') IS NULL
 THEN RAISE EXCEPTION 'Reviewed status RPC missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND tgname='on_auth_user_created' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'Auth profile trigger missing'; END IF;
END $preflight$;

REVOKE ALL PRIVILEGES ON TABLE public.profiles,public.categories,public.resources,public.borrow_requests FROM PUBLIC,anon;
REVOKE ALL PRIVILEGES ON TABLE public.profiles,public.categories,public.resources,public.borrow_requests FROM authenticated;
GRANT SELECT ON TABLE public.categories TO authenticated;
GRANT SELECT ON TABLE public.resources TO authenticated;
GRANT INSERT(title,description,category_id,owner_id,resource_type,availability_status) ON TABLE public.resources TO authenticated;
-- Keep availability update for current UI until coordinated RPC cutover.
GRANT UPDATE(title,description,category_id,resource_type,availability_status) ON TABLE public.resources TO authenticated;
GRANT DELETE ON TABLE public.resources TO authenticated;
-- Keep direct INSERT temporarily for current backend compatibility.
GRANT SELECT,INSERT ON TABLE public.borrow_requests TO authenticated;

-- Alter in place. This blocks spoofed borrower IDs, invalid initial statuses,
-- self-borrow, unavailable resource, and same-user active duplicates.
ALTER POLICY "Create own borrow requests" ON public.borrow_requests WITH CHECK (
 borrower_id=(SELECT auth.uid()) AND status='pending' AND returned_at IS NULL
 AND requested_at<=statement_timestamp()
 AND EXISTS(SELECT 1 FROM public.resources r WHERE r.id=borrow_requests.resource_id
   AND r.owner_id<>(SELECT auth.uid()) AND r.availability_status='available')
 AND NOT EXISTS(SELECT 1 FROM public.borrow_requests x WHERE x.borrower_id=(SELECT auth.uid())
   AND x.resource_id=borrow_requests.resource_id AND x.status IN ('pending','approved'))
);

-- Preserve authenticated workflow only on the reviewed owner/status-checking functions.
REVOKE EXECUTE ON FUNCTION public.approve_borrow_request(bigint,timestamptz) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.approve_borrow_request(bigint,timestamptz) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_borrow_request(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.reject_borrow_request(bigint) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;
-- Trigger remains; verify signup after revoking direct function RPC access.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

-- PHASE 1 indexes: each statement separately in autocommit, outside any transaction.
-- Recheck duplicates immediately before unique build. Do not clean/delete rows automatically.
CREATE INDEX CONCURRENTLY resources_category_id_idx ON public.resources(category_id);
CREATE INDEX CONCURRENTLY resources_owner_id_idx ON public.resources(owner_id);
CREATE INDEX CONCURRENTLY borrow_requests_borrower_id_idx ON public.borrow_requests(borrower_id);
CREATE INDEX CONCURRENTLY borrow_requests_resource_id_idx ON public.borrow_requests(resource_id);
CREATE UNIQUE INDEX CONCURRENTLY one_pending_request_per_borrower_resource
 ON public.borrow_requests(borrower_id,resource_id) WHERE status='pending';

-- PHASE 2, coordinated: do not apply until the backend is changed to call these RPCs.
-- Function owner must have BYPASSRLS/superuser; routines derive identities from auth.uid().
BEGIN;
DO $rpc_preflight$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls))
 THEN RAISE EXCEPTION 'RPC creator must bypass RLS; stop otherwise'; END IF;
 IF to_regprocedure('public.create_borrow_request(bigint,timestamp with time zone)') IS NOT NULL
 OR to_regprocedure('public.set_resource_availability(bigint,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'RPC name already exists; inspect rather than replace'; END IF;
END $rpc_preflight$;

CREATE FUNCTION public.create_borrow_request(p_resource_id bigint,p_due_at timestamptz DEFAULT NULL)
RETURNS SETOF public.borrow_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_user uuid := (SELECT auth.uid());
 v_owner uuid;
 v_availability text;
 v_requested timestamptz := pg_catalog.statement_timestamp();
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF p_resource_id IS NULL THEN RAISE EXCEPTION 'resource_id required'; END IF;
 IF p_due_at IS NOT NULL AND p_due_at<v_requested THEN RAISE EXCEPTION 'due_at precedes request time'; END IF;
 SELECT r.owner_id,r.availability_status INTO v_owner,v_availability
 FROM public.resources r WHERE r.id=p_resource_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Resource not found'; END IF;
 IF v_owner=v_user THEN RAISE EXCEPTION 'Cannot request own resource'; END IF;
 IF v_availability<>'available' THEN RAISE EXCEPTION 'Resource unavailable'; END IF;
 IF EXISTS(SELECT 1 FROM public.borrow_requests b WHERE b.borrower_id=v_user
   AND b.resource_id=p_resource_id AND b.status IN ('pending','approved'))
 THEN RAISE EXCEPTION 'Active request exists'; END IF;
 RETURN QUERY INSERT INTO public.borrow_requests(resource_id,borrower_id,status,requested_at,due_at,returned_at)
 VALUES(p_resource_id,v_user,'pending',v_requested,p_due_at,NULL) RETURNING *;
END
$function$;
REVOKE ALL ON FUNCTION public.create_borrow_request(bigint,timestamptz) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_borrow_request(bigint,timestamptz) TO authenticated;

CREATE FUNCTION public.set_resource_availability(p_resource_id bigint,p_status text)
RETURNS SETOF public.resources LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_user uuid := (SELECT auth.uid());
 v_owner uuid;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF p_resource_id IS NULL THEN RAISE EXCEPTION 'resource_id required'; END IF;
 IF p_status IS NULL OR p_status NOT IN ('available','unavailable')
 THEN RAISE EXCEPTION 'Invalid availability status'; END IF;
 SELECT r.owner_id INTO v_owner FROM public.resources r WHERE r.id=p_resource_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Resource not found'; END IF;
 IF v_owner<>v_user THEN RAISE EXCEPTION 'Only the owner may change availability'; END IF;
 IF p_status='available' AND EXISTS(SELECT 1 FROM public.borrow_requests b
   WHERE b.resource_id=p_resource_id AND b.status='approved')
 THEN RAISE EXCEPTION 'Approved loan remains active'; END IF;
 RETURN QUERY UPDATE public.resources r SET availability_status=p_status
 WHERE r.id=p_resource_id AND r.owner_id=v_user RETURNING r.*;
END
$function$;
REVOKE ALL ON FUNCTION public.set_resource_availability(bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.set_resource_availability(bigint,text) TO authenticated;
COMMIT;

-- PHASE 3 final cutover only after compatible backend deployment and staging tests:
-- Backend calls create_borrow_request(p_resource_id,p_due_at) and set_resource_availability(p_resource_id,p_status)
-- with the user's Bearer JWT. Then close direct bypass paths:
BEGIN;
REVOKE INSERT ON TABLE public.borrow_requests FROM authenticated;
REVOKE UPDATE(availability_status) ON TABLE public.resources FROM authenticated;
COMMIT;
-- Keep the INSERT policy as defense-in-depth; it does not provide row locking by itself.

-- ROLLBACK GUIDANCE (not executable):
-- Errors before COMMIT roll that transaction back. For concurrent index failure inspect
-- pg_index.indisvalid; remove only newly named invalid indexes after review. Never remove the
-- existing approved index. Before Phase 3 rollback, redeploy compatible prior app, then restore
-- only authenticated INSERT/availability grants with owner approval (this reopens races).
-- Revoke authenticated EXECUTE on the two newly added RPCs before removing them, and drop only
-- those new functions after no client calls them. Never restore anon/PUBLIC status execution.
-- Do not restore weak request policy automatically. Existing policies/functions/trigger remain.
