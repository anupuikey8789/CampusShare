-- PROPOSED ONLY. DO NOT EXECUTE without owner approval. Ref dkyfkdmlkghucyepxbbh.
-- Re-run audit, rehearse staging, back up. No service-role, GRANT ALL, UPDATE grant/policy, cleanup.
-- Intentionally disables status RPCs pending explicit workflow approval.
BEGIN;
DO $preflight$
DECLARE v_rls integer; v_ins integer; v_dup bigint;
BEGIN
 SELECT count(*) INTO v_rls FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN ('profiles','categories','resources','borrow_requests') AND c.relrowsecurity;
 IF v_rls<>4 THEN RAISE EXCEPTION 'Expected RLS on four tables'; END IF;
 SELECT count(*) INTO v_ins FROM pg_policies WHERE schemaname='public' AND tablename='borrow_requests' AND cmd='INSERT';
 IF v_ins<>1 OR NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='borrow_requests' AND policyname='Create own borrow requests' AND cmd='INSERT') THEN RAISE EXCEPTION 'Request INSERT policies changed'; END IF;
 SELECT count(*) INTO v_dup FROM (SELECT borrower_id,resource_id FROM public.borrow_requests WHERE status='pending' GROUP BY borrower_id,resource_id HAVING count(*)>1)d;
 IF v_dup<>0 THEN RAISE EXCEPTION 'Resolve pending duplicates manually'; END IF;
 IF to_regclass('public.one_active_approval_per_resource') IS NULL THEN RAISE EXCEPTION 'Approval index missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND tgname='on_auth_user_created' AND NOT tgisinternal) THEN RAISE EXCEPTION 'Auth profile trigger missing'; END IF;
END $preflight$;
REVOKE ALL PRIVILEGES ON TABLE public.profiles,public.categories,public.resources,public.borrow_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.categories TO authenticated;
GRANT SELECT ON TABLE public.resources TO authenticated;
GRANT INSERT(title,description,category_id,owner_id,resource_type,availability_status) ON TABLE public.resources TO authenticated;
GRANT UPDATE(title,description,category_id,resource_type,availability_status) ON TABLE public.resources TO authenticated;
GRANT DELETE ON TABLE public.resources TO authenticated;
GRANT SELECT,INSERT ON TABLE public.borrow_requests TO authenticated;
DROP POLICY "Create own borrow requests" ON public.borrow_requests;
CREATE POLICY "Create own borrow requests" ON public.borrow_requests FOR INSERT TO authenticated WITH CHECK (
 borrower_id=(SELECT auth.uid()) AND status='pending' AND returned_at IS NULL
 AND EXISTS(SELECT 1 FROM public.resources r WHERE r.id=borrow_requests.resource_id AND r.owner_id<>(SELECT auth.uid()) AND r.availability_status='available')
 AND NOT EXISTS(SELECT 1 FROM public.borrow_requests existing WHERE existing.borrower_id=(SELECT auth.uid()) AND existing.resource_id=borrow_requests.resource_id AND existing.status IN ('pending','approved'))
);
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION public.approve_borrow_request(bigint,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION public.reject_borrow_request(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
-- Validate Auth signup in staging after handle_new_user EXECUTE revoke.
-- Phase 2: execute each statement separately in autocommit, never inside BEGIN.
CREATE INDEX CONCURRENTLY resources_category_id_idx ON public.resources(category_id);
CREATE INDEX CONCURRENTLY resources_owner_id_idx ON public.resources(owner_id);
CREATE INDEX CONCURRENTLY borrow_requests_borrower_id_idx ON public.borrow_requests(borrower_id);
CREATE INDEX CONCURRENTLY borrow_requests_resource_id_idx ON public.borrow_requests(resource_id);
CREATE UNIQUE INDEX CONCURRENTLY one_pending_request_per_borrower_resource ON public.borrow_requests(borrower_id,resource_id) WHERE status='pending';
-- Future only after backend omits status/requested_at/returned_at:
-- REVOKE INSERT ON TABLE public.borrow_requests FROM authenticated;
-- GRANT INSERT(resource_id,borrower_id,due_at) ON TABLE public.borrow_requests TO authenticated;
-- Future only after owner approval/tests:
-- GRANT EXECUTE ON FUNCTION public.approve_borrow_request(bigint,timestamptz) TO authenticated;
-- GRANT EXECUTE ON FUNCTION public.reject_borrow_request(bigint) TO authenticated;
-- GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;
