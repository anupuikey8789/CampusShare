-- CampusShare marketplace extension for CampusShare-Staging ONLY.
-- Proposal: inspect the staging schema before manual application. Codex did not
-- connect to Supabase or execute SQL. Never apply this file to production.
-- Apply the reviewed base schema/grants/policies and
-- SUPABASE_STAGING_BORROWING_RPC_MIGRATION.sql first. Create the private Storage
-- bucket in Dashboard and apply SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql
-- after this migration. Keep marketplace and image flags disabled until tested.

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE n integer;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Run only as the reviewed staging database owner'; END IF;
 IF to_regclass('public.profiles') IS NULL OR to_regclass('public.categories') IS NULL OR to_regclass('public.resources') IS NULL OR to_regclass('public.borrow_requests') IS NULL THEN RAISE EXCEPTION 'CampusShare base tables are missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resources' AND column_name='id' AND data_type='bigint') OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resources' AND column_name='owner_id' AND data_type='uuid') OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='borrow_requests' AND column_name='resource_id' AND data_type='bigint') THEN RAISE EXCEPTION 'Base ID or owner types differ from verified contracts'; END IF;
 SELECT count(*) INTO n FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace s ON s.oid=c.relnamespace WHERE s.nspname='public' AND c.relname IN('profiles','categories','resources','borrow_requests') AND c.relrowsecurity;
 IF n<>4 THEN RAISE EXCEPTION 'Enable and review RLS on all four base tables'; END IF;
 IF to_regprocedure('public.create_borrow_request(bigint,timestamp with time zone)') IS NULL OR to_regprocedure('public.approve_borrow_request(bigint,timestamp with time zone)') IS NULL OR to_regprocedure('public.reject_borrow_request(bigint)') IS NULL OR to_regprocedure('public.return_borrowed_resource(bigint)') IS NULL OR to_regprocedure('public.update_resource_atomic(bigint,jsonb)') IS NULL THEN RAISE EXCEPTION 'Apply and review the base borrowing RPC migration first'; END IF;
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='resources' AND column_name IN('listing_mode','borrow_price_kind','borrow_price_amount','sale_original_price','sale_price','item_condition','purchase_year','listing_state')) OR to_regclass('public.resource_transfer_requests') IS NOT NULL OR to_regclass('public.resource_images') IS NOT NULL OR to_regclass('public.resource_handover_details') IS NOT NULL OR to_regclass('public.resource_listing_reports') IS NOT NULL THEN RAISE EXCEPTION 'Marketplace objects already exist; inspect instead of replacing'; END IF;
 IF to_regprocedure('public.register_resource_images(bigint,jsonb)') IS NOT NULL OR to_regprocedure('public.delete_resource_image_metadata(bigint)') IS NOT NULL OR to_regprocedure('public.create_resource_transfer_request(bigint,text)') IS NOT NULL OR to_regprocedure('public.approve_resource_transfer_request(bigint)') IS NOT NULL OR to_regprocedure('public.reject_resource_transfer_request(bigint)') IS NOT NULL OR to_regprocedure('public.cancel_resource_transfer_request(bigint)') IS NOT NULL OR to_regprocedure('public.complete_resource_sale(bigint)') IS NOT NULL OR to_regprocedure('public.complete_resource_donation(bigint)') IS NOT NULL OR to_regprocedure('public.update_marketplace_resource_atomic(bigint,jsonb)') IS NOT NULL OR to_regprocedure('public.reorder_resource_images(bigint,bigint[])') IS NOT NULL OR to_regprocedure('public.review_resource_listing_report(bigint,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'Marketplace RPC signature already exists; inspect it before applying'; END IF;
 IF EXISTS(SELECT 1 FROM public.borrow_requests WHERE status IN('pending','approved') GROUP BY borrower_id,resource_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate active borrow pairs exist; review before adding index'; END IF;
END $preflight$;

ALTER TABLE public.resources ADD COLUMN listing_mode text NOT NULL DEFAULT 'borrow', ADD COLUMN borrow_price_kind text NOT NULL DEFAULT 'free', ADD COLUMN borrow_price_amount numeric(12,2), ADD COLUMN sale_original_price numeric(12,2), ADD COLUMN sale_price numeric(12,2), ADD COLUMN item_condition text, ADD COLUMN purchase_year integer, ADD COLUMN listing_state text NOT NULL DEFAULT 'active';
ALTER TABLE public.resources ADD CONSTRAINT resources_listing_mode_check CHECK(listing_mode IN('borrow','sell','donate')), ADD CONSTRAINT resources_borrow_price_kind_check CHECK(borrow_price_kind IN('free','fixed','per_day','per_week')), ADD CONSTRAINT resources_purchase_year_check CHECK(purchase_year IS NULL OR purchase_year BETWEEN 1900 AND 9999), ADD CONSTRAINT resources_listing_state_check CHECK(listing_state IN('active','reserved','sold','donated')), ADD CONSTRAINT resources_listing_price_shape_check CHECK((listing_mode='borrow' AND sale_original_price IS NULL AND sale_price IS NULL AND item_condition IS NULL AND purchase_year IS NULL AND ((borrow_price_kind='free' AND borrow_price_amount IS NULL) OR (borrow_price_kind<>'free' AND borrow_price_amount IS NOT NULL AND borrow_price_amount>0 AND borrow_price_amount<>'NaN'::numeric))) OR (listing_mode='sell' AND borrow_price_kind='free' AND borrow_price_amount IS NULL AND sale_original_price IS NOT NULL AND sale_original_price>0 AND sale_original_price<>'NaN'::numeric AND sale_price IS NOT NULL AND sale_price>0 AND sale_price<>'NaN'::numeric AND sale_price<=sale_original_price AND item_condition IS NOT NULL AND item_condition IN('new','like_new','good','fair') AND purchase_year IS NOT NULL AND purchase_year BETWEEN 1900 AND 9999) OR (listing_mode='donate' AND borrow_price_kind='free' AND borrow_price_amount IS NULL AND sale_original_price IS NULL AND sale_price IS NULL AND item_condition IS NULL AND purchase_year IS NULL)), ADD CONSTRAINT resources_terminal_state_check CHECK((listing_state IN('sold','donated') AND availability_status='unavailable' AND ((listing_state='sold' AND listing_mode='sell') OR (listing_state='donated' AND listing_mode='donate'))) OR (listing_state='reserved' AND listing_mode IN('sell','donate') AND availability_status='unavailable') OR listing_state='active');
CREATE INDEX resources_listing_browse_idx ON public.resources(listing_mode,listing_state,availability_status,category_id);
CREATE UNIQUE INDEX IF NOT EXISTS one_active_request_per_borrower_resource ON public.borrow_requests(borrower_id,resource_id) WHERE status IN('pending','approved');

CREATE TABLE public.resource_transfer_requests(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,resource_id bigint NOT NULL REFERENCES public.resources(id) ON DELETE RESTRICT,owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,requester_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,request_type text NOT NULL CHECK(request_type IN('sell','donate')),status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','approved','rejected','cancelled','completed')),requested_at timestamptz NOT NULL DEFAULT pg_catalog.statement_timestamp(),completed_at timestamptz,CONSTRAINT transfer_no_self_request CHECK(owner_id<>requester_id),CONSTRAINT transfer_completion_shape CHECK((status='completed')=(completed_at IS NOT NULL)));
CREATE INDEX resource_transfer_requester_created_idx ON public.resource_transfer_requests(requester_id,requested_at DESC);
CREATE INDEX resource_transfer_owner_created_idx ON public.resource_transfer_requests(owner_id,requested_at DESC);
CREATE INDEX resource_transfer_resource_status_idx ON public.resource_transfer_requests(resource_id,status);
CREATE UNIQUE INDEX one_active_transfer_per_requester_resource ON public.resource_transfer_requests(resource_id,requester_id) WHERE status IN('pending','approved');
CREATE UNIQUE INDEX one_approved_transfer_per_resource ON public.resource_transfer_requests(resource_id) WHERE status='approved';
ALTER TABLE public.resource_transfer_requests ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.resource_transfer_requests TO authenticated;
CREATE POLICY "CampusShare students read related transfer requests" ON public.resource_transfer_requests FOR SELECT TO authenticated USING((SELECT auth.uid()) IS NOT NULL AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) AND ((SELECT auth.uid())=requester_id OR (SELECT auth.uid())=owner_id));

CREATE TABLE public.resource_images(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,resource_id bigint NOT NULL REFERENCES public.resources(id) ON DELETE RESTRICT,storage_path text NOT NULL UNIQUE,alt_text text NOT NULL DEFAULT '',sort_order integer NOT NULL,created_at timestamptz NOT NULL DEFAULT pg_catalog.statement_timestamp(),CONSTRAINT resource_images_storage_path_length_check CHECK(char_length(storage_path) BETWEEN 1 AND 500),CONSTRAINT resource_images_alt_text_length_check CHECK(char_length(alt_text)<=200),CONSTRAINT resource_images_sort_order_check CHECK(sort_order BETWEEN 0 AND 9),CONSTRAINT resource_images_resource_sort_order_key UNIQUE(resource_id,sort_order) DEFERRABLE INITIALLY DEFERRED);
CREATE INDEX resource_images_resource_idx ON public.resource_images(resource_id,sort_order);
ALTER TABLE public.resource_images ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.resource_images FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.resource_images TO authenticated;
CREATE POLICY "CampusShare students read resource images" ON public.resource_images FOR SELECT TO authenticated USING((SELECT auth.uid()) IS NOT NULL AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) AND EXISTS(SELECT 1 FROM public.resources r WHERE r.id=resource_id));

CREATE TABLE public.resource_handover_details(resource_id bigint PRIMARY KEY REFERENCES public.resources(id) ON DELETE RESTRICT,pickup_location text NOT NULL CHECK(char_length(btrim(pickup_location)) BETWEEN 1 AND 160),meeting_point text NOT NULL CHECK(char_length(btrim(meeting_point)) BETWEEN 1 AND 160),preferred_pickup_time text CHECK(preferred_pickup_time IS NULL OR char_length(preferred_pickup_time)<=160),instructions text CHECK(instructions IS NULL OR char_length(instructions)<=1000),updated_at timestamptz NOT NULL DEFAULT pg_catalog.statement_timestamp());
ALTER TABLE public.resource_handover_details ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE ON public.resource_handover_details TO authenticated;
CREATE POLICY "CampusShare owners manage handover details" ON public.resource_handover_details FOR ALL TO authenticated USING((SELECT auth.uid()) IS NOT NULL AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) AND EXISTS(SELECT 1 FROM public.resources r WHERE r.id=resource_id AND r.owner_id=(SELECT auth.uid()))) WITH CHECK((SELECT auth.uid()) IS NOT NULL AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) AND EXISTS(SELECT 1 FROM public.resources r WHERE r.id=resource_id AND r.owner_id=(SELECT auth.uid())));
CREATE POLICY "CampusShare related students read handover details" ON public.resource_handover_details FOR SELECT TO authenticated USING((SELECT auth.uid()) IS NOT NULL AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) AND (EXISTS(SELECT 1 FROM public.resources r WHERE r.id=resource_handover_details.resource_id AND r.owner_id=(SELECT auth.uid())) OR EXISTS(SELECT 1 FROM public.borrow_requests b WHERE b.resource_id=resource_handover_details.resource_id AND b.status IN('approved','returned') AND b.borrower_id=(SELECT auth.uid())) OR EXISTS(SELECT 1 FROM public.resource_transfer_requests t WHERE t.resource_id=resource_handover_details.resource_id AND t.requester_id=(SELECT auth.uid()) AND t.status IN('approved','completed'))));

CREATE TABLE public.resource_listing_reports(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,resource_id bigint NOT NULL REFERENCES public.resources(id) ON DELETE RESTRICT,reporter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,reason text NOT NULL CHECK(reason IN('misleading_original_price','unreasonable_selling_price','incorrect_description','suspicious_listing','other')),details text CHECK(details IS NULL OR char_length(details)<=2000),status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','resolved','dismissed')),moderator_notes text CHECK(moderator_notes IS NULL OR char_length(moderator_notes)<=1000),reviewer_id uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,created_at timestamptz NOT NULL DEFAULT pg_catalog.statement_timestamp(),reviewed_at timestamptz,CONSTRAINT listing_report_review_shape CHECK((status='pending' AND reviewer_id IS NULL AND reviewed_at IS NULL) OR (status IN('resolved','dismissed') AND reviewer_id IS NOT NULL AND reviewed_at IS NOT NULL)));
CREATE INDEX resource_listing_reports_resource_idx ON public.resource_listing_reports(resource_id,created_at DESC);
CREATE INDEX resource_listing_reports_reporter_idx ON public.resource_listing_reports(reporter_id,created_at DESC);
CREATE UNIQUE INDEX one_pending_report_per_reporter_resource ON public.resource_listing_reports(resource_id,reporter_id) WHERE status='pending';
ALTER TABLE public.resource_listing_reports ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT ON public.resource_listing_reports TO authenticated;
CREATE POLICY "CampusShare reporters read own listing reports" ON public.resource_listing_reports FOR SELECT TO authenticated USING((SELECT auth.uid()) IS NOT NULL AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) AND reporter_id=(SELECT auth.uid()));
CREATE POLICY "CampusShare moderators read listing reports" ON public.resource_listing_reports FOR SELECT TO authenticated USING((SELECT auth.uid()) IS NOT NULL AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) AND (SELECT auth.jwt()->'app_metadata'->>'campusshare_role')='moderator');
CREATE POLICY "CampusShare students submit listing reports" ON public.resource_listing_reports FOR INSERT TO authenticated WITH CHECK((SELECT auth.uid()) IS NOT NULL AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) AND reporter_id=(SELECT auth.uid()) AND status='pending' AND reviewer_id IS NULL AND reviewed_at IS NULL AND EXISTS(SELECT 1 FROM public.resources r WHERE r.id=resource_id AND r.owner_id<>(SELECT auth.uid())));
-- Timestamp and terminal-state rules also apply to direct authenticated INSERTs.
CREATE OR REPLACE FUNCTION public.validate_resource_listing() RETURNS trigger LANGUAGE plpgsql SET search_path=''
AS $f$ BEGIN
 IF NEW.listing_mode='sell' AND NEW.purchase_year>extract(year FROM pg_catalog.statement_timestamp())::integer THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Purchase year cannot be in the future'; END IF;
 IF TG_OP='UPDATE' AND OLD.listing_state IN('sold','donated') AND (NEW.listing_state IS DISTINCT FROM OLD.listing_state OR NEW.listing_mode IS DISTINCT FROM OLD.listing_mode OR NEW.availability_status IS DISTINCT FROM 'unavailable' OR NEW.owner_id IS DISTINCT FROM OLD.owner_id) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Completed sale and donation listings are permanent'; END IF;
 IF NEW.listing_state IN('sold','donated') AND NEW.availability_status<>'unavailable' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Sold and donated listings must remain unavailable'; END IF;
 RETURN NEW;
END $f$;
REVOKE ALL ON FUNCTION public.validate_resource_listing() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER campusshare_validate_resource_listing BEFORE INSERT OR UPDATE ON public.resources FOR EACH ROW EXECUTE FUNCTION public.validate_resource_listing();
REVOKE UPDATE ON public.resources FROM authenticated;
REVOKE UPDATE(id,title,description,category_id,owner_id,resource_type,availability_status,created_at,listing_mode,borrow_price_kind,borrow_price_amount,sale_original_price,sale_price,item_condition,purchase_year,listing_state) ON public.resources FROM authenticated;

-- Serialize borrow creation with transfer approvals by locking the resource first.
CREATE OR REPLACE FUNCTION public.create_borrow_request(p_resource_id bigint,p_due_at timestamptz DEFAULT NULL)
RETURNS SETOF public.borrow_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); owner_id uuid; avail text; mode text; state text; requested timestamptz:=pg_catalog.statement_timestamp();
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 IF p_resource_id IS NULL OR p_resource_id<=0 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid resource ID'; END IF;
 SELECT r.owner_id,r.availability_status,r.listing_mode,r.listing_state INTO owner_id,avail,mode,state FROM public.resources r WHERE r.id=p_resource_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 IF owner_id=actor THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Cannot request own resource'; END IF;
 IF mode<>'borrow' OR state<>'active' OR avail<>'available' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Resource is not available for borrowing'; END IF;
 IF p_due_at IS NOT NULL AND p_due_at<requested THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Due date precedes request time'; END IF;
 IF EXISTS(SELECT 1 FROM public.borrow_requests b WHERE b.borrower_id=actor AND b.resource_id=p_resource_id AND b.status IN('pending','approved')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Active request exists'; END IF;
 RETURN QUERY INSERT INTO public.borrow_requests(resource_id,borrower_id,status,requested_at,due_at,returned_at) VALUES(p_resource_id,actor,'pending',requested,p_due_at,NULL) RETURNING *;
END $f$;

CREATE OR REPLACE FUNCTION public.create_resource_transfer_request(p_resource_id bigint,p_request_type text)
RETURNS SETOF public.resource_transfer_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); owner_id uuid; mode text; state text; avail text;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 IF p_resource_id IS NULL OR p_resource_id<=0 OR p_request_type NOT IN('sell','donate') THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid transfer request'; END IF;
 SELECT r.owner_id,r.listing_mode,r.listing_state,r.availability_status INTO owner_id,mode,state,avail FROM public.resources r WHERE r.id=p_resource_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 IF owner_id=actor THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Cannot request own resource'; END IF;
 IF mode<>p_request_type OR state<>'active' OR avail<>'available' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Listing unavailable for this request'; END IF;
 RETURN QUERY INSERT INTO public.resource_transfer_requests(resource_id,owner_id,requester_id,request_type,status) VALUES(p_resource_id,owner_id,actor,p_request_type,'pending') RETURNING *;
END $f$;

CREATE OR REPLACE FUNCTION public.approve_resource_transfer_request(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); rid bigint; owner_id uuid; mode text; state text; avail text; req public.resource_transfer_requests;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id=p_request_id; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Request not found'; END IF;
 SELECT r.owner_id,r.listing_mode,r.listing_state,r.availability_status INTO owner_id,mode,state,avail FROM public.resources r WHERE r.id=rid FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id=p_request_id FOR UPDATE;
 IF actor<>owner_id OR req.owner_id<>owner_id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only current owner may approve'; END IF;
 IF req.status<>'pending' OR req.request_type<>mode OR state<>'active' OR avail<>'available' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Invalid approval transition'; END IF;
 IF EXISTS(SELECT 1 FROM public.borrow_requests b WHERE b.resource_id=rid AND b.status IN('pending','approved')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Borrow requests are active'; END IF;
 UPDATE public.resource_transfer_requests SET status='rejected' WHERE resource_id=rid AND id<>p_request_id AND status='pending';
 UPDATE public.resource_transfer_requests SET status='approved' WHERE id=p_request_id RETURNING * INTO req;
 UPDATE public.resources SET availability_status='unavailable',listing_state='reserved' WHERE id=rid;
 RETURN NEXT req;
END $f$;

CREATE OR REPLACE FUNCTION public.reject_resource_transfer_request(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); rid bigint; owner_id uuid; req public.resource_transfer_requests;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id=p_request_id; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Request not found'; END IF;
 SELECT r.owner_id INTO owner_id FROM public.resources r WHERE r.id=rid FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id=p_request_id FOR UPDATE;
 IF actor<>owner_id OR req.owner_id<>owner_id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only current owner may reject'; END IF;
 IF req.status<>'pending' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Only pending requests may be rejected'; END IF;
 UPDATE public.resource_transfer_requests SET status='rejected' WHERE id=p_request_id RETURNING * INTO req; RETURN NEXT req;
END $f$;

CREATE OR REPLACE FUNCTION public.cancel_resource_transfer_request(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); rid bigint; req public.resource_transfer_requests;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id=p_request_id; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Request not found'; END IF;
 PERFORM 1 FROM public.resources r WHERE r.id=rid FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id=p_request_id FOR UPDATE;
 IF actor<>req.requester_id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only requester may cancel'; END IF;
 IF req.status<>'pending' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Only pending requests may be cancelled'; END IF;
 UPDATE public.resource_transfer_requests SET status='cancelled' WHERE id=p_request_id RETURNING * INTO req; RETURN NEXT req;
END $f$;
CREATE OR REPLACE FUNCTION public.complete_resource_sale(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); rid bigint; owner_id uuid; mode text; state text; req public.resource_transfer_requests;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id=p_request_id; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Request not found'; END IF;
 SELECT r.owner_id,r.listing_mode,r.listing_state INTO owner_id,mode,state FROM public.resources r WHERE r.id=rid FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id=p_request_id FOR UPDATE;
 IF actor<>owner_id OR req.owner_id<>owner_id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only current owner may complete sale'; END IF;
 IF req.status<>'approved' OR req.request_type<>'sell' OR mode<>'sell' OR state<>'reserved' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Invalid sale completion transition'; END IF;
 UPDATE public.resources SET owner_id=req.requester_id,listing_state='sold',availability_status='unavailable' WHERE id=rid;
 UPDATE public.resource_transfer_requests SET status='completed',completed_at=pg_catalog.statement_timestamp() WHERE id=p_request_id RETURNING * INTO req; RETURN NEXT req;
END $f$;

CREATE OR REPLACE FUNCTION public.complete_resource_donation(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); rid bigint; owner_id uuid; mode text; state text; req public.resource_transfer_requests;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id=p_request_id; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Request not found'; END IF;
 SELECT r.owner_id,r.listing_mode,r.listing_state INTO owner_id,mode,state FROM public.resources r WHERE r.id=rid FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id=p_request_id FOR UPDATE;
 IF actor<>owner_id OR req.owner_id<>owner_id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only current owner may complete donation'; END IF;
 IF req.status<>'approved' OR req.request_type<>'donate' OR mode<>'donate' OR state<>'reserved' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Invalid donation completion transition'; END IF;
 UPDATE public.resources SET owner_id=req.requester_id,listing_state='donated',availability_status='unavailable' WHERE id=rid;
 UPDATE public.resource_transfer_requests SET status='completed',completed_at=pg_catalog.statement_timestamp() WHERE id=p_request_id RETURNING * INTO req; RETURN NEXT req;
END $f$;

CREATE OR REPLACE FUNCTION public.update_marketplace_resource_atomic(p_resource_id bigint,p_changes jsonb)
RETURNS SETOF public.resources LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); r public.resources; mode text; kind text; amount numeric(12,2); original numeric(12,2); sale numeric(12,2); condition_value text; year_value integer; avail text;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 IF p_resource_id IS NULL OR p_resource_id<=0 OR p_changes IS NULL OR pg_catalog.jsonb_typeof(p_changes)<>'object' OR p_changes='{}'::jsonb THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid resource update'; END IF;
 SELECT x.* INTO r FROM public.resources x WHERE x.id=p_resource_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 IF r.owner_id<>actor THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only resource owner may update'; END IF;
 IF p_changes ? 'title' AND (pg_catalog.jsonb_typeof(p_changes->'title')<>'string' OR length(btrim(p_changes->>'title'))=0) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Title must be a non-empty string'; END IF;
 IF r.listing_state IN('sold','donated') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Completed listings are permanent'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(p_changes) AS keys(key) WHERE key NOT IN('title','description','category_id','resource_type','availability_status','listing_mode','borrow_price_kind','borrow_price_amount','sale_original_price','sale_price','item_condition','purchase_year')) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Unsupported resource field'; END IF;
 mode:=COALESCE(p_changes->>'listing_mode',r.listing_mode);
 IF mode NOT IN('borrow','sell','donate') THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid listing mode'; END IF;
 IF mode<>r.listing_mode AND EXISTS(SELECT 1 FROM public.resource_transfer_requests t WHERE t.resource_id=p_resource_id) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Listing type cannot change after transfer history'; END IF;
 IF mode<>r.listing_mode AND EXISTS(SELECT 1 FROM public.borrow_requests b WHERE b.resource_id=p_resource_id) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Listing type cannot change after borrowing history'; END IF;
 avail:=COALESCE(p_changes->>'availability_status',r.availability_status);
 IF avail NOT IN('available','unavailable') THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid availability'; END IF;
 IF avail='available' AND EXISTS(SELECT 1 FROM public.borrow_requests b WHERE b.resource_id=p_resource_id AND b.status='approved') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Return the approved borrowing before restoring availability'; END IF;
 IF mode='borrow' THEN
  kind:=COALESCE(p_changes->>'borrow_price_kind',CASE WHEN r.listing_mode='borrow' THEN r.borrow_price_kind ELSE 'free' END);
  IF kind NOT IN('free','fixed','per_day','per_week') THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid borrowing charge kind'; END IF;
  IF kind='free' THEN amount:=NULL; ELSE amount:=COALESCE(NULLIF(p_changes->>'borrow_price_amount','')::numeric,CASE WHEN r.listing_mode='borrow' THEN r.borrow_price_amount END); IF amount IS NULL OR amount<=0 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Paid borrowing requires a positive charge'; END IF; END IF;
  original:=NULL;sale:=NULL;condition_value:=NULL;year_value:=NULL;
 ELSIF mode='sell' THEN
  kind:='free';amount:=NULL;
  original:=COALESCE(NULLIF(p_changes->>'sale_original_price','')::numeric,CASE WHEN r.listing_mode='sell' THEN r.sale_original_price END);
  sale:=COALESCE(NULLIF(p_changes->>'sale_price','')::numeric,CASE WHEN r.listing_mode='sell' THEN r.sale_price END);
  condition_value:=COALESCE(p_changes->>'item_condition',CASE WHEN r.listing_mode='sell' THEN r.item_condition END);
  year_value:=COALESCE(NULLIF(p_changes->>'purchase_year','')::integer,CASE WHEN r.listing_mode='sell' THEN r.purchase_year END);
  IF original IS NULL OR sale IS NULL OR original<=0 OR sale<=0 OR sale>original THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Valid original and fixed sale prices are required'; END IF;
  IF condition_value NOT IN('new','like_new','good','fair') OR year_value IS NULL OR year_value<1900 OR year_value>extract(year FROM pg_catalog.statement_timestamp())::integer THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Valid condition and non-future purchase year are required'; END IF;
 ELSE kind:='free';amount:=NULL;original:=NULL;sale:=NULL;condition_value:=NULL;year_value:=NULL;
 END IF;
 IF r.listing_state='reserved' AND avail='available' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Resolve the approved transfer before restoring availability'; END IF;
 RETURN QUERY UPDATE public.resources x SET title=CASE WHEN p_changes?'title' THEN p_changes->>'title' ELSE x.title END, description=CASE WHEN p_changes?'description' THEN p_changes->>'description' ELSE x.description END, category_id=CASE WHEN p_changes?'category_id' THEN NULLIF(p_changes->>'category_id','')::bigint ELSE x.category_id END, resource_type=CASE WHEN p_changes?'resource_type' THEN p_changes->>'resource_type' ELSE x.resource_type END, availability_status=avail,listing_mode=mode,borrow_price_kind=kind,borrow_price_amount=amount,sale_original_price=original,sale_price=sale,item_condition=condition_value,purchase_year=year_value WHERE x.id=p_resource_id RETURNING x.*;
END $f$;

CREATE OR REPLACE FUNCTION public.reorder_resource_images(p_resource_id bigint,p_image_ids bigint[])
RETURNS SETOF public.resource_images LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); n integer; distinct_n integer;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 IF p_resource_id IS NULL OR p_resource_id<=0 OR p_image_ids IS NULL OR cardinality(p_image_ids)>10 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid image order'; END IF;
 PERFORM 1 FROM public.resources r WHERE r.id=p_resource_id AND r.owner_id=actor FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only owner can reorder images'; END IF;
 SELECT count(*),count(DISTINCT x) INTO n,distinct_n FROM unnest(p_image_ids) x;
 IF n<>distinct_n OR n<>(SELECT count(*) FROM public.resource_images i WHERE i.resource_id=p_resource_id) OR EXISTS(SELECT 1 FROM unnest(p_image_ids) x WHERE NOT EXISTS(SELECT 1 FROM public.resource_images i WHERE i.id=x AND i.resource_id=p_resource_id)) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Order must include every saved image once'; END IF;
 SET CONSTRAINTS public.resource_images_resource_sort_order_key DEFERRED;
 RETURN QUERY UPDATE public.resource_images i SET sort_order=o.ordinality::integer-1 FROM unnest(p_image_ids) WITH ORDINALITY o(id,ordinality) WHERE i.resource_id=p_resource_id AND i.id=o.id RETURNING i.*;
END $f$;
CREATE OR REPLACE FUNCTION public.register_resource_images(p_resource_id bigint,p_images jsonb)
RETURNS SETOF public.resource_images LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); item jsonb; image_path text; alt text; order_value integer; n integer; owner_id uuid; state text;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 IF p_resource_id IS NULL OR p_resource_id<=0 OR p_images IS NULL OR pg_catalog.jsonb_typeof(p_images) IS DISTINCT FROM 'array' OR pg_catalog.jsonb_array_length(p_images)<1 OR pg_catalog.jsonb_array_length(p_images)>10 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid image registration'; END IF;
 SELECT r.owner_id,r.listing_state INTO owner_id,state FROM public.resources r WHERE r.id=p_resource_id FOR UPDATE;
 IF NOT FOUND OR owner_id<>actor THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only current resource owner may add images'; END IF;
 IF state IN('sold','donated') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Terminal listings cannot be changed'; END IF;
 SELECT count(*) INTO n FROM public.resource_images i WHERE i.resource_id=p_resource_id;
 IF n+pg_catalog.jsonb_array_length(p_images)>10 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='A resource can have no more than 10 images'; END IF;
 FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_images) LOOP
  IF pg_catalog.jsonb_typeof(item) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(item) AS k(key) WHERE key NOT IN('storage_path','alt_text','sort_order')) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid image metadata fields'; END IF;
  IF pg_catalog.jsonb_typeof(item->'storage_path') IS DISTINCT FROM 'string' OR pg_catalog.jsonb_typeof(item->'sort_order') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Image path and integer order are required'; END IF;
  image_path:=item->>'storage_path';
  IF image_path NOT LIKE actor::text||'/'||p_resource_id::text||'/%' OR image_path !~ ('^'||actor::text||'/'||p_resource_id::text||'/[A-Za-z0-9_.-]{1,180}$') OR position('..' in image_path)>0 OR lower(image_path)!~'\.(jpg|jpeg|png|webp)$' OR char_length(image_path)>500 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Image path is invalid'; END IF;
  IF item ? 'alt_text' AND (pg_catalog.jsonb_typeof(item->'alt_text') IS DISTINCT FROM 'string' OR char_length(item->>'alt_text')>200) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid image alternative text'; END IF;
  IF (item->>'sort_order')::numeric<>trunc((item->>'sort_order')::numeric) OR (item->>'sort_order')::integer NOT BETWEEN 0 AND 9 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid image order'; END IF;
  order_value:=(item->>'sort_order')::integer;
  IF EXISTS(SELECT 1 FROM public.resource_images i WHERE i.resource_id=p_resource_id AND (i.sort_order=order_value OR i.storage_path=image_path)) THEN RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='Image order or path already exists'; END IF;
  IF NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='campusshare-resource-images' AND o.name=image_path) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Uploaded Storage object was not found'; END IF;
 END LOOP;
 RETURN QUERY INSERT INTO public.resource_images(resource_id,storage_path,alt_text,sort_order)
   SELECT p_resource_id,value->>'storage_path',COALESCE(value->>'alt_text',''),(value->>'sort_order')::integer FROM pg_catalog.jsonb_array_elements(p_images) AS images(value)
   ORDER BY (value->>'sort_order')::integer RETURNING *;
END $f$;

CREATE OR REPLACE FUNCTION public.delete_resource_image_metadata(p_image_id bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); rid bigint; owner_id uuid; object_path text;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 IF p_image_id IS NULL OR p_image_id<=0 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid image ID'; END IF;
 SELECT i.resource_id,i.storage_path INTO rid,object_path FROM public.resource_images i WHERE i.id=p_image_id;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Image metadata not found'; END IF;
 SELECT r.owner_id INTO owner_id FROM public.resources r WHERE r.id=rid FOR UPDATE;
 IF NOT FOUND OR owner_id<>actor THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only current resource owner may delete images'; END IF;
 PERFORM 1 FROM public.resource_images i WHERE i.id=p_image_id AND i.resource_id=rid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Image metadata not found'; END IF;
 IF EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='campusshare-resource-images' AND o.name=object_path) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Remove the Storage object before deleting its metadata'; END IF;
 DELETE FROM public.resource_images WHERE id=p_image_id;
 SET CONSTRAINTS public.resource_images_resource_sort_order_key DEFERRED;
 WITH ranked AS (SELECT i.id,(row_number() OVER(ORDER BY i.sort_order,i.id)-1)::integer AS new_order FROM public.resource_images i WHERE i.resource_id=rid)
 UPDATE public.resource_images i SET sort_order=ranked.new_order FROM ranked WHERE i.id=ranked.id;
 RETURN true;
END $f$;

CREATE OR REPLACE FUNCTION public.review_resource_listing_report(p_report_id bigint,p_outcome text,p_notes text DEFAULT NULL)
RETURNS SETOF public.resource_listing_reports LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); report_row public.resource_listing_reports;
BEGIN
 IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true) THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 IF (SELECT auth.jwt()->'app_metadata'->>'campusshare_role') IS DISTINCT FROM 'moderator' THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Moderator authorization required'; END IF;
 IF p_report_id IS NULL OR p_report_id<=0 OR p_outcome NOT IN('resolved','dismissed') OR (p_notes IS NOT NULL AND char_length(p_notes)>1000) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid report review'; END IF;
 SELECT x.* INTO report_row FROM public.resource_listing_reports x WHERE x.id=p_report_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Report not found'; END IF;
 IF report_row.status<>'pending' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Report already reviewed'; END IF;
 UPDATE public.resource_listing_reports SET status=p_outcome,moderator_notes=p_notes,reviewer_id=actor,reviewed_at=pg_catalog.statement_timestamp() WHERE id=p_report_id RETURNING * INTO report_row;
 RETURN NEXT report_row;
END $f$;

COMMENT ON TABLE public.resource_transfer_requests IS 'CampusShare staging marketplace extension v1';
COMMENT ON TABLE public.resource_images IS 'CampusShare staging marketplace extension v1';
COMMENT ON TABLE public.resource_handover_details IS 'CampusShare staging marketplace extension v1';
COMMENT ON TABLE public.resource_listing_reports IS 'CampusShare staging marketplace extension v1';

-- Remove the two direct mutation paths only after the RPCs above are reviewed.
-- Application cutover is coordinated: set the corresponding flags locally only
-- after staging SQL and two-account tests; do not enable them in this package.
REVOKE INSERT,UPDATE ON public.borrow_requests FROM authenticated;
ALTER FUNCTION public.validate_resource_listing() OWNER TO postgres;
ALTER FUNCTION public.create_borrow_request(bigint,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.approve_borrow_request(bigint,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.reject_borrow_request(bigint) OWNER TO postgres;
ALTER FUNCTION public.return_borrowed_resource(bigint) OWNER TO postgres;
ALTER FUNCTION public.update_resource_atomic(bigint,jsonb) OWNER TO postgres;
ALTER FUNCTION public.create_resource_transfer_request(bigint,text) OWNER TO postgres;
ALTER FUNCTION public.approve_resource_transfer_request(bigint) OWNER TO postgres;
ALTER FUNCTION public.reject_resource_transfer_request(bigint) OWNER TO postgres;
ALTER FUNCTION public.cancel_resource_transfer_request(bigint) OWNER TO postgres;
ALTER FUNCTION public.complete_resource_sale(bigint) OWNER TO postgres;
ALTER FUNCTION public.complete_resource_donation(bigint) OWNER TO postgres;
ALTER FUNCTION public.update_marketplace_resource_atomic(bigint,jsonb) OWNER TO postgres;
ALTER FUNCTION public.reorder_resource_images(bigint,bigint[]) OWNER TO postgres;
ALTER FUNCTION public.register_resource_images(bigint,jsonb) OWNER TO postgres;
ALTER FUNCTION public.delete_resource_image_metadata(bigint) OWNER TO postgres;
ALTER FUNCTION public.review_resource_listing_report(bigint,text,text) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.validate_resource_listing() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_borrow_request(bigint,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.approve_borrow_request(bigint,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reject_borrow_request(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.update_resource_atomic(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_resource_transfer_request(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.approve_resource_transfer_request(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reject_resource_transfer_request(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.cancel_resource_transfer_request(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.complete_resource_sale(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.complete_resource_donation(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.update_marketplace_resource_atomic(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reorder_resource_images(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.register_resource_images(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_resource_image_metadata(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.review_resource_listing_report(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_borrow_request(bigint,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_borrow_request(bigint,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_borrow_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_resource_atomic(bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_resource_transfer_request(bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_resource_transfer_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_resource_transfer_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_resource_transfer_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_resource_sale(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_resource_donation(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_marketplace_resource_atomic(bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reorder_resource_images(bigint,bigint[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_resource_images(bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_resource_image_metadata(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_resource_listing_report(bigint,text,text) TO authenticated;

COMMENT ON FUNCTION public.create_borrow_request(bigint,timestamptz) IS 'CampusShare staging marketplace extension; borrow-only listing guard and resource lock';
COMMENT ON FUNCTION public.create_resource_transfer_request(bigint,text) IS 'CampusShare staging marketplace; authenticated requester, owner snapshot, locked resource';
COMMENT ON FUNCTION public.approve_resource_transfer_request(bigint) IS 'CampusShare staging marketplace; owner-only atomic reservation';
COMMENT ON FUNCTION public.reject_resource_transfer_request(bigint) IS 'CampusShare staging marketplace; owner-only pending transition';
COMMENT ON FUNCTION public.cancel_resource_transfer_request(bigint) IS 'CampusShare staging marketplace; requester-only pending cancellation';
COMMENT ON FUNCTION public.complete_resource_sale(bigint) IS 'CampusShare staging marketplace; permanent owner transfer';
COMMENT ON FUNCTION public.complete_resource_donation(bigint) IS 'CampusShare staging marketplace; permanent owner transfer';
COMMENT ON FUNCTION public.update_marketplace_resource_atomic(bigint,jsonb) IS 'CampusShare staging marketplace; owner-only validated resource update';
COMMENT ON FUNCTION public.reorder_resource_images(bigint,bigint[]) IS 'CampusShare staging marketplace; owner-only saved image ordering';
COMMENT ON FUNCTION public.register_resource_images(bigint,jsonb) IS 'CampusShare staging image metadata transaction v1';
COMMENT ON FUNCTION public.delete_resource_image_metadata(bigint) IS 'CampusShare staging image metadata transaction v1';
COMMENT ON FUNCTION public.review_resource_listing_report(bigint,text,text) IS 'CampusShare staging marketplace; app_metadata moderator authorization';

COMMIT;
