-- ==============================================================================
-- CampusShare - Complete Marketplace (Sell & Donate) Workflow Setup
-- Run this in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/jxndjuslvccxgayoachm/sql
-- ==============================================================================

-- 1. Extend public.resources with Marketplace Columns & Constraints
ALTER TABLE public.resources
    ADD COLUMN IF NOT EXISTS listing_mode text NOT NULL DEFAULT 'borrow',
    ADD COLUMN IF NOT EXISTS borrow_price_kind text NOT NULL DEFAULT 'free',
    ADD COLUMN IF NOT EXISTS borrow_price_amount numeric(12,2),
    ADD COLUMN IF NOT EXISTS sale_original_price numeric(12,2),
    ADD COLUMN IF NOT EXISTS sale_price numeric(12,2),
    ADD COLUMN IF NOT EXISTS item_condition text,
    ADD COLUMN IF NOT EXISTS purchase_year integer,
    ADD COLUMN IF NOT EXISTS listing_state text NOT NULL DEFAULT 'active';

DO $$
BEGIN
    ALTER TABLE public.resources DROP CONSTRAINT IF EXISTS resources_listing_mode_check;
    ALTER TABLE public.resources ADD CONSTRAINT resources_listing_mode_check CHECK (listing_mode IN ('borrow', 'sell', 'donate'));

    ALTER TABLE public.resources DROP CONSTRAINT IF EXISTS resources_borrow_price_kind_check;
    ALTER TABLE public.resources ADD CONSTRAINT resources_borrow_price_kind_check CHECK (borrow_price_kind IN ('free', 'fixed', 'per_day', 'per_week'));

    ALTER TABLE public.resources DROP CONSTRAINT IF EXISTS resources_item_condition_check;
    ALTER TABLE public.resources ADD CONSTRAINT resources_item_condition_check CHECK (item_condition IS NULL OR item_condition IN ('new', 'like_new', 'good', 'fair'));

    ALTER TABLE public.resources DROP CONSTRAINT IF EXISTS resources_listing_state_check;
    ALTER TABLE public.resources ADD CONSTRAINT resources_listing_state_check CHECK (listing_state IN ('active', 'reserved', 'sold', 'donated'));
END $$;

-- 2. Create Table: resource_transfer_requests (Sell & Donate Requests)
CREATE TABLE IF NOT EXISTS public.resource_transfer_requests (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id bigint NOT NULL REFERENCES public.resources(id) ON DELETE RESTRICT,
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    requester_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    request_type text NOT NULL CHECK (request_type IN ('sell', 'donate')),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled', 'completed')),
    requested_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    completed_at timestamptz,
    CONSTRAINT transfer_no_self_request CHECK (owner_id <> requester_id),
    CONSTRAINT transfer_completion_shape CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS resource_transfer_requester_created_idx ON public.resource_transfer_requests (requester_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS resource_transfer_owner_created_idx ON public.resource_transfer_requests (owner_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS resource_transfer_resource_status_idx ON public.resource_transfer_requests (resource_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS one_active_transfer_per_requester_resource ON public.resource_transfer_requests (resource_id, requester_id) WHERE status IN ('pending', 'approved');
CREATE UNIQUE INDEX IF NOT EXISTS one_approved_transfer_per_resource ON public.resource_transfer_requests (resource_id) WHERE status = 'approved';

ALTER TABLE public.resource_transfer_requests ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.resource_transfer_requests TO authenticated;

DROP POLICY IF EXISTS "CampusShare users read own transfer requests" ON public.resource_transfer_requests;
CREATE POLICY "CampusShare users read own transfer requests"
ON public.resource_transfer_requests FOR SELECT TO authenticated
USING (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND (owner_id = (SELECT auth.uid()) OR requester_id = (SELECT auth.uid()))
);

-- 3. Create Table: resource_handover_details (Campus Pickup Location & Meeting Point)
CREATE TABLE IF NOT EXISTS public.resource_handover_details (
    resource_id bigint PRIMARY KEY REFERENCES public.resources(id) ON DELETE CASCADE,
    pickup_location text NOT NULL,
    meeting_point text NOT NULL,
    preferred_pickup_time text,
    instructions text,
    created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    CONSTRAINT handover_location_length_check CHECK (char_length(pickup_location) BETWEEN 1 AND 160),
    CONSTRAINT handover_meeting_point_length_check CHECK (char_length(meeting_point) BETWEEN 1 AND 160),
    CONSTRAINT handover_preferred_time_length_check CHECK (preferred_pickup_time IS NULL OR char_length(preferred_pickup_time) BETWEEN 1 AND 160),
    CONSTRAINT handover_instructions_length_check CHECK (instructions IS NULL OR char_length(instructions) BETWEEN 1 AND 1000)
);

ALTER TABLE public.resource_handover_details ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.resource_handover_details TO authenticated;

DROP POLICY IF EXISTS "CampusShare handover read by owner or approved party" ON public.resource_handover_details;
CREATE POLICY "CampusShare handover read by owner or approved party"
ON public.resource_handover_details FOR SELECT TO authenticated
USING (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND (
        EXISTS (SELECT 1 FROM public.resources r WHERE r.id = resource_handover_details.resource_id AND r.owner_id = (SELECT auth.uid()))
        OR EXISTS (SELECT 1 FROM public.borrow_requests b WHERE b.resource_id = resource_handover_details.resource_id AND b.borrower_id = (SELECT auth.uid()) AND b.status IN ('approved', 'returned'))
        OR EXISTS (SELECT 1 FROM public.resource_transfer_requests t WHERE t.resource_id = resource_handover_details.resource_id AND t.requester_id = (SELECT auth.uid()) AND t.status IN ('approved', 'completed'))
    )
);

DROP POLICY IF EXISTS "CampusShare owners save handover details" ON public.resource_handover_details;
CREATE POLICY "CampusShare owners save handover details"
ON public.resource_handover_details FOR ALL TO authenticated
USING (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND EXISTS (SELECT 1 FROM public.resources r WHERE r.id = resource_handover_details.resource_id AND r.owner_id = (SELECT auth.uid()))
)
WITH CHECK (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND EXISTS (SELECT 1 FROM public.resources r WHERE r.id = resource_id AND r.owner_id = (SELECT auth.uid()))
);

-- 4. Create Table: resource_listing_reports (Listing Reports & Price Flagging)
CREATE TABLE IF NOT EXISTS public.resource_listing_reports (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id bigint NOT NULL REFERENCES public.resources(id) ON DELETE RESTRICT,
    reporter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    reason text NOT NULL CHECK (reason IN ('misleading_original_price', 'unreasonable_selling_price', 'incorrect_description', 'suspicious_listing', 'other')),
    details text CHECK (details IS NULL OR char_length(details) <= 2000),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'dismissed')),
    moderator_notes text CHECK (moderator_notes IS NULL OR char_length(moderator_notes) <= 1000),
    reviewer_id uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    reviewed_at timestamptz,
    CONSTRAINT listing_report_review_shape CHECK ((status = 'pending' AND reviewer_id IS NULL AND reviewed_at IS NULL) OR (status IN ('resolved', 'dismissed') AND reviewer_id IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS resource_listing_reports_resource_idx ON public.resource_listing_reports (resource_id, created_at DESC);
CREATE INDEX IF NOT EXISTS resource_listing_reports_reporter_idx ON public.resource_listing_reports (reporter_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS one_pending_report_per_reporter_resource ON public.resource_listing_reports (resource_id, reporter_id) WHERE status = 'pending';

ALTER TABLE public.resource_listing_reports ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.resource_listing_reports TO authenticated;

DROP POLICY IF EXISTS "CampusShare reporters read own listing reports" ON public.resource_listing_reports;
CREATE POLICY "CampusShare reporters read own listing reports"
ON public.resource_listing_reports FOR SELECT TO authenticated
USING (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND reporter_id = (SELECT auth.uid())
);

DROP POLICY IF EXISTS "CampusShare moderators read listing reports" ON public.resource_listing_reports;
CREATE POLICY "CampusShare moderators read listing reports"
ON public.resource_listing_reports FOR SELECT TO authenticated
USING (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND (SELECT auth.jwt()->'app_metadata'->>'campusshare_role') = 'moderator'
);

DROP POLICY IF EXISTS "CampusShare students submit listing reports" ON public.resource_listing_reports;
CREATE POLICY "CampusShare students submit listing reports"
ON public.resource_listing_reports FOR INSERT TO authenticated
WITH CHECK (
    (SELECT auth.uid()) IS NOT NULL
    AND NOT COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true)
    AND reporter_id = (SELECT auth.uid())
    AND status = 'pending'
    AND reviewer_id IS NULL
    AND reviewed_at IS NULL
    AND EXISTS (SELECT 1 FROM public.resources r WHERE r.id = resource_id AND r.owner_id <> (SELECT auth.uid()))
);

-- 5. RPC FUNCTIONS

-- RPC 1: create_resource_transfer_request
CREATE OR REPLACE FUNCTION public.create_resource_transfer_request(
    p_resource_id bigint,
    p_request_type text
)
RETURNS SETOF public.resource_transfer_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    v_owner_id uuid;
    v_mode text;
    v_state text;
    v_avail text;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0 OR p_request_type NOT IN ('sell', 'donate') THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid transfer request parameters';
    END IF;

    SELECT r.owner_id, r.listing_mode, r.listing_state, r.availability_status
      INTO v_owner_id, v_mode, v_state, v_avail
      FROM public.resources r
     WHERE r.id = p_resource_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    IF v_owner_id = actor THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot request own resource';
    END IF;
    IF v_mode <> p_request_type OR v_state <> 'active' OR v_avail <> 'available' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Listing unavailable for this request';
    END IF;

    RETURN QUERY
      INSERT INTO public.resource_transfer_requests (resource_id, owner_id, requester_id, request_type, status)
      VALUES (p_resource_id, v_owner_id, actor, p_request_type, 'pending')
      RETURNING *;
END
$function$;

-- RPC 2: approve_resource_transfer_request
CREATE OR REPLACE FUNCTION public.approve_resource_transfer_request(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    rid bigint;
    v_owner_id uuid;
    v_mode text;
    v_state text;
    v_avail text;
    req public.resource_transfer_requests;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;

    SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id = p_request_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found'; END IF;

    SELECT r.owner_id, r.listing_mode, r.listing_state, r.availability_status
      INTO v_owner_id, v_mode, v_state, v_avail
      FROM public.resources r WHERE r.id = rid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found'; END IF;

    SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id = p_request_id FOR UPDATE;
    IF actor <> v_owner_id OR req.owner_id <> v_owner_id THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only current owner may approve';
    END IF;
    IF req.status <> 'pending' OR req.request_type <> v_mode OR v_state <> 'active' OR v_avail <> 'available' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Invalid approval transition';
    END IF;
    IF EXISTS (SELECT 1 FROM public.borrow_requests b WHERE b.resource_id = rid AND b.status IN ('pending', 'approved')) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Borrow requests are active';
    END IF;

    UPDATE public.resource_transfer_requests SET status = 'rejected' WHERE resource_id = rid AND id <> p_request_id AND status = 'pending';
    UPDATE public.resource_transfer_requests SET status = 'approved' WHERE id = p_request_id RETURNING * INTO req;
    UPDATE public.resources SET availability_status = 'unavailable', listing_state = 'reserved' WHERE id = rid;
    RETURN NEXT req;
END
$function$;

-- RPC 3: reject_resource_transfer_request
CREATE OR REPLACE FUNCTION public.reject_resource_transfer_request(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    rid bigint;
    v_owner_id uuid;
    req public.resource_transfer_requests;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;

    SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id = p_request_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found'; END IF;

    SELECT r.owner_id INTO v_owner_id FROM public.resources r WHERE r.id = rid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found'; END IF;

    SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id = p_request_id FOR UPDATE;
    IF actor <> v_owner_id OR req.owner_id <> v_owner_id THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only current owner may reject';
    END IF;
    IF req.status <> 'pending' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Only pending requests may be rejected';
    END IF;

    UPDATE public.resource_transfer_requests SET status = 'rejected' WHERE id = p_request_id RETURNING * INTO req;
    RETURN NEXT req;
END
$function$;

-- RPC 4: cancel_resource_transfer_request
CREATE OR REPLACE FUNCTION public.cancel_resource_transfer_request(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    rid bigint;
    req public.resource_transfer_requests;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;

    SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id = p_request_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found'; END IF;

    PERFORM 1 FROM public.resources r WHERE r.id = rid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found'; END IF;

    SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id = p_request_id FOR UPDATE;
    IF actor <> req.requester_id THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only requester may cancel';
    END IF;
    IF req.status <> 'pending' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Only pending requests may be cancelled';
    END IF;

    UPDATE public.resource_transfer_requests SET status = 'cancelled' WHERE id = p_request_id RETURNING * INTO req;
    RETURN NEXT req;
END
$function$;

-- RPC 5: complete_resource_sale
CREATE OR REPLACE FUNCTION public.complete_resource_sale(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    rid bigint;
    v_owner_id uuid;
    v_mode text;
    v_state text;
    req public.resource_transfer_requests;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;

    SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id = p_request_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found'; END IF;

    SELECT r.owner_id, r.listing_mode, r.listing_state INTO v_owner_id, v_mode, v_state FROM public.resources r WHERE r.id = rid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found'; END IF;

    SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id = p_request_id FOR UPDATE;
    IF actor <> v_owner_id OR req.owner_id <> v_owner_id THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only current owner may complete sale';
    END IF;
    IF req.status <> 'approved' OR req.request_type <> 'sell' OR v_mode <> 'sell' OR v_state <> 'reserved' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Invalid sale completion transition';
    END IF;

    UPDATE public.resources SET owner_id = req.requester_id, listing_state = 'sold', availability_status = 'unavailable' WHERE id = rid;
    UPDATE public.resource_transfer_requests SET status = 'completed', completed_at = pg_catalog.statement_timestamp() WHERE id = p_request_id RETURNING * INTO req;
    RETURN NEXT req;
END
$function$;

-- RPC 6: complete_resource_donation
CREATE OR REPLACE FUNCTION public.complete_resource_donation(p_request_id bigint)
RETURNS SETOF public.resource_transfer_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    rid bigint;
    v_owner_id uuid;
    v_mode text;
    v_state text;
    req public.resource_transfer_requests;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;

    SELECT t.resource_id INTO rid FROM public.resource_transfer_requests t WHERE t.id = p_request_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found'; END IF;

    SELECT r.owner_id, r.listing_mode, r.listing_state INTO v_owner_id, v_mode, v_state FROM public.resources r WHERE r.id = rid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found'; END IF;

    SELECT t.* INTO req FROM public.resource_transfer_requests t WHERE t.id = p_request_id FOR UPDATE;
    IF actor <> v_owner_id OR req.owner_id <> v_owner_id THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only current owner may complete donation';
    END IF;
    IF req.status <> 'approved' OR req.request_type <> 'donate' OR v_mode <> 'donate' OR v_state <> 'reserved' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Invalid donation completion transition';
    END IF;

    UPDATE public.resources SET owner_id = req.requester_id, listing_state = 'donated', availability_status = 'unavailable' WHERE id = rid;
    UPDATE public.resource_transfer_requests SET status = 'completed', completed_at = pg_catalog.statement_timestamp() WHERE id = p_request_id RETURNING * INTO req;
    RETURN NEXT req;
END
$function$;

-- RPC 7: update_marketplace_resource_atomic
CREATE OR REPLACE FUNCTION public.update_marketplace_resource_atomic(p_resource_id bigint, p_changes jsonb)
RETURNS SETOF public.resources
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    r public.resources;
    mode text;
    kind text;
    amount numeric(12,2);
    original numeric(12,2);
    sale numeric(12,2);
    condition_value text;
    year_value integer;
    avail text;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0 OR p_changes IS NULL OR pg_catalog.jsonb_typeof(p_changes) <> 'object' OR p_changes = '{}'::jsonb THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid resource update';
    END IF;

    SELECT x.* INTO r FROM public.resources x WHERE x.id = p_resource_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found'; END IF;
    IF r.owner_id <> actor THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only resource owner may update'; END IF;

    IF p_changes ? 'title' AND (pg_catalog.jsonb_typeof(p_changes->'title') <> 'string' OR length(btrim(p_changes->>'title')) = 0) THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Title must be a non-empty string';
    END IF;
    IF r.listing_state IN ('sold', 'donated') THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Completed listings are permanent';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.jsonb_object_keys(p_changes) AS keys(key)
               WHERE key NOT IN ('title', 'description', 'category_id', 'resource_type', 'availability_status', 'listing_mode', 'borrow_price_kind', 'borrow_price_amount', 'sale_original_price', 'sale_price', 'item_condition', 'purchase_year')) THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Unsupported resource field';
    END IF;

    mode := COALESCE(p_changes->>'listing_mode', r.listing_mode);
    IF mode NOT IN ('borrow', 'sell', 'donate') THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid listing mode'; END IF;
    IF mode <> r.listing_mode AND EXISTS (SELECT 1 FROM public.resource_transfer_requests t WHERE t.resource_id = p_resource_id) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Listing type cannot change after transfer history';
    END IF;
    IF mode <> r.listing_mode AND EXISTS (SELECT 1 FROM public.borrow_requests b WHERE b.resource_id = p_resource_id) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Listing type cannot change after borrowing history';
    END IF;

    avail := COALESCE(p_changes->>'availability_status', r.availability_status);
    IF avail NOT IN ('available', 'unavailable') THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid availability'; END IF;
    IF avail = 'available' AND EXISTS (SELECT 1 FROM public.borrow_requests b WHERE b.resource_id = p_resource_id AND b.status = 'approved') THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Return the approved borrowing before restoring availability';
    END IF;

    IF mode = 'borrow' THEN
        kind := COALESCE(p_changes->>'borrow_price_kind', CASE WHEN r.listing_mode = 'borrow' THEN r.borrow_price_kind ELSE 'free' END);
        IF kind NOT IN ('free', 'fixed', 'per_day', 'per_week') THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid borrowing charge kind'; END IF;
        IF kind = 'free' THEN amount := NULL;
        ELSE
            amount := COALESCE(NULLIF(p_changes->>'borrow_price_amount', '')::numeric, CASE WHEN r.listing_mode = 'borrow' THEN r.borrow_price_amount END);
            IF amount IS NULL OR amount <= 0 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Paid borrowing requires a positive charge'; END IF;
        END IF;
        original := NULL; sale := NULL; condition_value := NULL; year_value := NULL;
    ELSIF mode = 'sell' THEN
        kind := 'free'; amount := NULL;
        original := COALESCE(NULLIF(p_changes->>'sale_original_price', '')::numeric, CASE WHEN r.listing_mode = 'sell' THEN r.sale_original_price END);
        sale := COALESCE(NULLIF(p_changes->>'sale_price', '')::numeric, CASE WHEN r.listing_mode = 'sell' THEN r.sale_price END);
        condition_value := COALESCE(p_changes->>'item_condition', CASE WHEN r.listing_mode = 'sell' THEN r.item_condition END);
        year_value := COALESCE(NULLIF(p_changes->>'purchase_year', '')::integer, CASE WHEN r.listing_mode = 'sell' THEN r.purchase_year END);
        IF original IS NULL OR sale IS NULL OR original <= 0 OR sale <= 0 OR sale > original THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Valid original and fixed sale prices are required';
        END IF;
        IF condition_value NOT IN ('new', 'like_new', 'good', 'fair') OR year_value IS NULL OR year_value < 1900 OR year_value > extract(year FROM pg_catalog.statement_timestamp())::integer THEN
            RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Valid condition and non-future purchase year are required';
        END IF;
    ELSE
        kind := 'free'; amount := NULL; original := NULL; sale := NULL; condition_value := NULL; year_value := NULL;
    END IF;

    IF r.listing_state = 'reserved' AND avail = 'available' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resolve the approved transfer before restoring availability';
    END IF;

    RETURN QUERY
      UPDATE public.resources x
         SET title = CASE WHEN p_changes ? 'title' THEN p_changes->>'title' ELSE x.title END,
             description = CASE WHEN p_changes ? 'description' THEN p_changes->>'description' ELSE x.description END,
             category_id = CASE WHEN p_changes ? 'category_id' THEN NULLIF(p_changes->>'category_id', '')::bigint ELSE x.category_id END,
             resource_type = CASE WHEN p_changes ? 'resource_type' THEN p_changes->>'resource_type' ELSE x.resource_type END,
             availability_status = avail,
             listing_mode = mode,
             borrow_price_kind = kind,
             borrow_price_amount = amount,
             sale_original_price = original,
             sale_price = sale,
             item_condition = condition_value,
             purchase_year = year_value
       WHERE x.id = p_resource_id
      RETURNING x.*;
END
$function$;

-- RPC 8: review_resource_listing_report
CREATE OR REPLACE FUNCTION public.review_resource_listing_report(p_report_id bigint, p_outcome text, p_notes text DEFAULT NULL)
RETURNS SETOF public.resource_listing_reports
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor uuid := (SELECT auth.uid());
    report_row public.resource_listing_reports;
BEGIN
    IF actor IS NULL OR COALESCE(((SELECT auth.jwt())->>'is_anonymous')::boolean, true) THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF (SELECT auth.jwt()->'app_metadata'->>'campusshare_role') IS DISTINCT FROM 'moderator' THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Moderator authorization required';
    END IF;
    IF p_report_id IS NULL OR p_report_id <= 0 OR p_outcome NOT IN ('resolved', 'dismissed') OR (p_notes IS NOT NULL AND char_length(p_notes) > 1000) THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid report review';
    END IF;

    SELECT x.* INTO report_row FROM public.resource_listing_reports x WHERE x.id = p_report_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Report not found'; END IF;
    IF report_row.status <> 'pending' THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Report already reviewed'; END IF;

    UPDATE public.resource_listing_reports
       SET status = p_outcome,
           moderator_notes = p_notes,
           reviewer_id = actor,
           reviewed_at = pg_catalog.statement_timestamp()
     WHERE id = p_report_id
    RETURNING * INTO report_row;
    RETURN NEXT report_row;
END
$function$;

-- 6. Grant Permissions to Authenticated Users
GRANT EXECUTE ON FUNCTION public.create_resource_transfer_request(bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_resource_transfer_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_resource_transfer_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_resource_transfer_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_resource_sale(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_resource_donation(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_marketplace_resource_atomic(bigint, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_resource_listing_report(bigint, text, text) TO authenticated;

