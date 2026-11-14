-- CAMPUSSHARE STAGING ONLY rollback for SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql.
-- Codex did not execute this file. Never use in production.
-- Disable and verify the marketplace/image backend flags manually first.
-- This is intentionally fail-closed. It refuses rollback after any transfer,
-- image metadata/object, handover, report, or non-default marketplace data exists.
-- Storage bucket is retained; delete it manually only after separate review.

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Rollback requires staging database owner'; END IF;
 IF to_regclass('public.resource_transfer_requests') IS NULL OR to_regclass('public.resource_images') IS NULL OR to_regclass('public.resource_handover_details') IS NULL OR to_regclass('public.resource_listing_reports') IS NULL THEN RAISE EXCEPTION 'Marketplace objects are missing or partial; inspect manually'; END IF;
 IF EXISTS(SELECT 1 FROM public.resource_transfer_requests) OR EXISTS(SELECT 1 FROM public.resource_images) OR EXISTS(SELECT 1 FROM public.resource_handover_details) OR EXISTS(SELECT 1 FROM public.resource_listing_reports) THEN RAISE EXCEPTION 'Marketplace records exist; export and review before rollback'; END IF;
 IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='campusshare-resource-images') THEN RAISE EXCEPTION 'Storage objects exist; archive/remove through reviewed Storage operations before rollback'; END IF;
 IF EXISTS(SELECT 1 FROM public.resources WHERE listing_mode<>'borrow' OR borrow_price_kind<>'free' OR borrow_price_amount IS NOT NULL OR sale_original_price IS NOT NULL OR sale_price IS NOT NULL OR item_condition IS NOT NULL OR purchase_year IS NOT NULL OR listing_state<>'active') THEN RAISE EXCEPTION 'Non-default marketplace resource data exists; export/review before rollback'; END IF;
 IF pg_catalog.obj_description('public.resource_images'::regclass,'pg_class') IS DISTINCT FROM 'CampusShare staging marketplace extension v1' OR pg_catalog.obj_description('public.resource_transfer_requests'::regclass,'pg_class') IS DISTINCT FROM 'CampusShare staging marketplace extension v1' THEN RAISE EXCEPTION 'Table marker mismatch; this is not the reviewed migration'; END IF;
 IF to_regprocedure('public.create_borrow_request(bigint,timestamp with time zone)') IS NULL OR to_regprocedure('public.update_marketplace_resource_atomic(bigint,jsonb)') IS NULL OR to_regprocedure('public.reorder_resource_images(bigint,bigint[])') IS NULL OR to_regprocedure('public.register_resource_images(bigint,jsonb)') IS NULL OR to_regprocedure('public.delete_resource_image_metadata(bigint)') IS NULL THEN RAISE EXCEPTION 'Expected functions are missing; inspect partial state'; END IF;
END $preflight$;

DROP POLICY IF EXISTS "CampusShare students read permitted images" ON storage.objects;
DROP POLICY IF EXISTS "CampusShare owners upload images" ON storage.objects;
DROP POLICY IF EXISTS "CampusShare owners delete images" ON storage.objects;
DROP POLICY "CampusShare students read related transfer requests" ON public.resource_transfer_requests;
DROP POLICY "CampusShare students read resource images" ON public.resource_images;
DROP POLICY "CampusShare owners add resource images" ON public.resource_images;
DROP POLICY "CampusShare owners delete resource images" ON public.resource_images;
DROP POLICY "CampusShare owners manage handover details" ON public.resource_handover_details;
DROP POLICY "CampusShare related students read handover details" ON public.resource_handover_details;
DROP POLICY "CampusShare reporters read own listing reports" ON public.resource_listing_reports;
DROP POLICY "CampusShare moderators read listing reports" ON public.resource_listing_reports;
DROP POLICY "CampusShare students submit listing reports" ON public.resource_listing_reports;

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
DROP FUNCTION public.create_resource_transfer_request(bigint,text);
DROP FUNCTION public.approve_resource_transfer_request(bigint);
DROP FUNCTION public.reject_resource_transfer_request(bigint);
DROP FUNCTION public.cancel_resource_transfer_request(bigint);
DROP FUNCTION public.complete_resource_sale(bigint);
DROP FUNCTION public.complete_resource_donation(bigint);
DROP FUNCTION public.update_marketplace_resource_atomic(bigint,jsonb);
DROP FUNCTION public.reorder_resource_images(bigint,bigint[]);
DROP FUNCTION public.register_resource_images(bigint,jsonb);
DROP FUNCTION public.delete_resource_image_metadata(bigint);
DROP FUNCTION public.review_resource_listing_report(bigint,text,text);
DROP TRIGGER campusshare_validate_resource_listing ON public.resources;
REVOKE ALL ON FUNCTION public.validate_resource_listing() FROM PUBLIC,anon,authenticated,service_role;
DROP FUNCTION public.validate_resource_listing();

-- Restore the pre-marketplace Task 8 borrow creator. Direct INSERT/UPDATE table
-- grants remain revoked; no insecure fallback or resource UPDATE grant is restored.
CREATE OR REPLACE FUNCTION public.create_borrow_request(p_resource_id bigint,p_due_at timestamptz DEFAULT NULL)
RETURNS SETOF public.borrow_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE actor uuid:=(SELECT auth.uid()); anonymous boolean:=COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean,true); owner_id uuid; availability text; requested timestamptz:=pg_catalog.statement_timestamp();
BEGIN
 IF actor IS NULL OR anonymous THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='Authentication required'; END IF;
 IF p_resource_id IS NULL OR p_resource_id<=0 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Invalid resource ID'; END IF;
 SELECT r.owner_id,r.availability_status INTO owner_id,availability FROM public.resources r WHERE r.id=p_resource_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='Resource not found'; END IF;
 IF owner_id=actor THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Cannot request own resource'; END IF;
 IF availability IS DISTINCT FROM 'available' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Resource unavailable'; END IF;
 IF EXISTS(SELECT 1 FROM public.borrow_requests b WHERE b.borrower_id=actor AND b.resource_id=p_resource_id AND b.status IN('pending','approved')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='Active request exists'; END IF;
 IF p_due_at IS NOT NULL AND p_due_at<requested THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='due_at precedes request time'; END IF;
 RETURN QUERY INSERT INTO public.borrow_requests(resource_id,borrower_id,status,requested_at,due_at,returned_at) VALUES(p_resource_id,actor,'pending',requested,p_due_at,NULL) RETURNING *;
END $f$;
ALTER FUNCTION public.create_borrow_request(bigint,timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_borrow_request(bigint,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_borrow_request(bigint,timestamptz) TO authenticated;
COMMENT ON FUNCTION public.create_borrow_request(bigint,timestamptz) IS 'CampusShare staging Task 8 RPC migration v1';

DROP TABLE public.resource_listing_reports;
DROP TABLE public.resource_handover_details;
DROP TABLE public.resource_images;
DROP TABLE public.resource_transfer_requests;
DROP INDEX public.resources_listing_browse_idx;
ALTER TABLE public.resources DROP CONSTRAINT resources_listing_mode_check,DROP CONSTRAINT resources_borrow_price_kind_check,DROP CONSTRAINT resources_purchase_year_check,DROP CONSTRAINT resources_listing_state_check,DROP CONSTRAINT resources_listing_price_shape_check,DROP CONSTRAINT resources_terminal_state_check;
ALTER TABLE public.resources DROP COLUMN listing_mode,DROP COLUMN borrow_price_kind,DROP COLUMN borrow_price_amount,DROP COLUMN sale_original_price,DROP COLUMN sale_price,DROP COLUMN item_condition,DROP COLUMN purchase_year,DROP COLUMN listing_state;
-- Keep one_active_request_per_borrower_resource and all existing table grants,
-- base RLS policies, base RPCs and the private Storage bucket. Do not regrant
-- direct borrow or resource mutation privileges as part of rollback.
COMMIT;
