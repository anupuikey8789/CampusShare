-- CampusShare secure borrowing RPC migration proposal.
-- APPLY TO THE VERIFIED STAGING PROJECT ONLY, after owner review.
-- Never run against production. Codex did not execute this file.
--
-- Existing schema evidence used here is recorded in BACKEND/SUPABASE_SCHEMA_REQUIREMENTS.md:
-- resources(id bigint, owner_id uuid, availability_status text, ...)
-- borrow_requests(id bigint, resource_id bigint, borrower_id uuid, status text,
-- requested_at timestamptz, due_at timestamptz, returned_at timestamptz)
-- The three status function input signatures below match the repository's audit snapshot.
-- Status return types and bodies were not present in that snapshot; this migration proposes
-- RETURNS SETOF public.borrow_requests and is therefore a new staging contract.
--
-- Lock order for every operation that touches both tables is:
--   1) public.resources row
--   2) public.borrow_requests row(s)
-- create_borrow_request and update_resource_atomic lock only the resource and then read
-- requests. This ordering serializes request creation, approval, rejection, return, and
-- availability changes for a single resource. The unique active-pair index also protects
-- duplicate active requests from direct/concurrent inserts.
--
-- All functions use SECURITY DEFINER because the reviewed app grants do not grant
-- borrow_requests UPDATE and direct INSERT permissions may be withheld at cutover.
-- The function owner must be a trusted BYPASSRLS/superuser role with the table privileges
-- checked below. Every function validates auth.uid() and rejects anonymous Auth JWTs.
-- No table grants or RLS policies are changed by this migration.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
DECLARE
    v_rls_count integer;
    v_policy_count integer;
    v_duplicate_count bigint;
    v_constraint_count integer;
BEGIN
    IF to_regclass('public.profiles') IS NULL
       OR to_regclass('public.categories') IS NULL
       OR to_regclass('public.resources') IS NULL
       OR to_regclass('public.borrow_requests') IS NULL THEN
        RAISE EXCEPTION 'CampusShare staging tables are missing; stop and inspect the target';
    END IF;

    SELECT count(*) INTO v_rls_count
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('profiles','categories','resources','borrow_requests')
      AND c.relrowsecurity;
    IF v_rls_count <> 4 THEN
        RAISE EXCEPTION 'RLS must be enabled on all four CampusShare tables';
    END IF;

    SELECT count(*) INTO v_policy_count
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND (tablename, policyname) IN (
          ('profiles','Read own profile'),
          ('profiles','Update own profile'),
          ('categories','Read categories'),
          ('resources','Read resources'),
          ('resources','Add own resources'),
          ('resources','Update own resources'),
          ('resources','Delete own resources'),
          ('borrow_requests','Create own borrow requests'),
          ('borrow_requests','Read own borrow requests'),
          ('borrow_requests','Owners read requests for their resources')
      );
    IF v_policy_count <> 10 THEN
        RAISE EXCEPTION 'Expected the ten reviewed RLS policies; inspect staging before continuing';
    END IF;

    SELECT count(*) INTO v_constraint_count
    FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid IN ('public.resources'::regclass, 'public.borrow_requests'::regclass)
      AND c.conname IN (
          'resources_availability_status_check',
          'borrow_requests_check',
          'borrow_requests_check1',
          'borrow_requests_status_check',
          'resources_owner_id_fkey',
          'borrow_requests_resource_id_fkey',
          'borrow_requests_borrower_id_fkey'
      );
    IF v_constraint_count <> 7 THEN
        RAISE EXCEPTION 'Expected verified availability, request-date/status, and ownership constraints';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='resources'
          AND column_name='id' AND data_type='bigint'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='resources'
          AND column_name='owner_id' AND data_type='uuid'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='resources'
          AND column_name='availability_status' AND data_type='text'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='borrow_requests'
          AND column_name='id' AND data_type='bigint'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='borrow_requests'
          AND column_name='resource_id' AND data_type='bigint'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='borrow_requests'
          AND column_name='borrower_id' AND data_type='uuid'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='borrow_requests'
          AND column_name='status' AND data_type='text'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='borrow_requests'
          AND column_name='requested_at' AND data_type='timestamp with time zone'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='borrow_requests'
          AND column_name='due_at' AND data_type='timestamp with time zone'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='borrow_requests'
          AND column_name='returned_at' AND data_type='timestamp with time zone'
    ) THEN
        RAISE EXCEPTION 'CampusShare column types differ from the reviewed schema';
    END IF;

    IF NOT (SELECT rolsuper OR rolbypassrls FROM pg_catalog.pg_roles WHERE rolname=current_user) THEN
        RAISE EXCEPTION 'Migration/function owner must be a trusted BYPASSRLS or superuser role';
    END IF;
    IF NOT has_table_privilege(current_user, 'public.resources', 'SELECT')
       OR NOT has_table_privilege(current_user, 'public.resources', 'UPDATE')
       OR NOT has_table_privilege(current_user, 'public.borrow_requests', 'SELECT')
       OR NOT has_table_privilege(current_user, 'public.borrow_requests', 'INSERT')
       OR NOT has_table_privilege(current_user, 'public.borrow_requests', 'UPDATE') THEN
        RAISE EXCEPTION 'Function owner lacks required table privileges';
    END IF;
    IF NOT has_schema_privilege('authenticated', 'public', 'USAGE') THEN
        RAISE EXCEPTION 'authenticated lacks USAGE on public; inspect Data API grants';
    END IF;
    IF has_table_privilege('authenticated', 'public.borrow_requests', 'UPDATE')
       OR EXISTS (
           SELECT 1 FROM pg_catalog.pg_policies
           WHERE schemaname='public' AND tablename='borrow_requests' AND cmd='UPDATE'
       ) THEN
        RAISE EXCEPTION 'Unexpected direct borrow_requests UPDATE privilege/policy; review before installing RPCs';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
        WHERE n.nspname='public'
          AND p.proname IN (
              'create_borrow_request','approve_borrow_request','reject_borrow_request',
              'return_borrowed_resource','update_resource_atomic'
          )
    ) THEN
        RAISE EXCEPTION 'A CampusShare RPC name already exists; inspect it rather than replacing it';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_index AS i
        WHERE i.indexrelid='public.one_active_approval_per_resource'::regclass
          AND i.indrelid='public.borrow_requests'::regclass
          AND i.indisunique AND i.indisvalid AND i.indisready
          AND pg_catalog.pg_get_indexdef(i.indexrelid) LIKE '%resource_id%'
          AND pg_catalog.pg_get_expr(i.indpred, i.indrelid) LIKE '%approved%'
    ) THEN
        RAISE EXCEPTION 'Verified one-approved-request-per-resource index is missing or differs';
    END IF;

    IF to_regclass('public.one_active_request_per_borrower_resource') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_index AS i
           WHERE i.indexrelid='public.one_active_request_per_borrower_resource'::regclass
             AND i.indrelid='public.borrow_requests'::regclass
             AND i.indisunique AND i.indisvalid AND i.indisready
             AND i.indnkeyatts=2 AND i.indnatts=2
             AND pg_catalog.pg_get_indexdef(i.indexrelid) LIKE '%borrower_id, resource_id%'
             AND pg_catalog.pg_get_expr(i.indpred, i.indrelid) LIKE '%pending%'
             AND pg_catalog.pg_get_expr(i.indpred, i.indrelid) LIKE '%approved%'
       ) THEN
        RAISE EXCEPTION 'Active borrower/resource index exists with an unexpected definition';
    END IF;

    SELECT count(*) INTO v_duplicate_count
    FROM (
        SELECT borrower_id, resource_id
        FROM public.borrow_requests
        WHERE status IN ('pending','approved')
        GROUP BY borrower_id, resource_id
        HAVING count(*) > 1
    ) AS duplicates;
    IF v_duplicate_count > 0 THEN
        RAISE EXCEPTION 'Active borrower/resource duplicates exist; resolve manually before creating the unique index';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.borrow_requests AS b
        JOIN public.resources AS r ON r.id=b.resource_id
        WHERE b.status='approved' AND r.availability_status <> 'unavailable'
    ) THEN
        RAISE EXCEPTION 'Approved requests conflict with resource availability; reconcile manually before migration';
    END IF;
END
$preflight$;

-- If this exact index was already applied with the reviewed RLS package, retain it.
-- A newly created index is marked so rollback will never drop an older owner-created index.
-- CREATE INDEX is transactional here; for a large table it can block writers.
DO $index$
BEGIN
    IF to_regclass('public.one_active_request_per_borrower_resource') IS NULL THEN
        EXECUTE 'CREATE UNIQUE INDEX one_active_request_per_borrower_resource
                 ON public.borrow_requests (borrower_id, resource_id)
                 WHERE status IN (''pending'',''approved'')';
        EXECUTE 'COMMENT ON INDEX public.one_active_request_per_borrower_resource
                 IS ''CampusShare staging Task 8 RPC migration v1''';
    END IF;
END
$index$;

CREATE FUNCTION public.create_borrow_request(
    p_resource_id bigint,
    p_due_at timestamptz DEFAULT NULL
)
RETURNS SETOF public.borrow_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_owner uuid;
    v_availability text;
    v_requested_at timestamptz := pg_catalog.statement_timestamp();
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid resource ID';
    END IF;

    SELECT r.owner_id, r.availability_status INTO v_owner, v_availability
    FROM public.resources AS r
    WHERE r.id=p_resource_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    IF v_owner=v_actor THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Cannot request own resource';
    END IF;
    IF v_availability IS DISTINCT FROM 'available' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resource unavailable';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.borrow_requests AS b
        WHERE b.borrower_id=v_actor
          AND b.resource_id=p_resource_id
          AND b.status IN ('pending','approved')
    ) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Active request exists';
    END IF;
    IF p_due_at IS NOT NULL AND p_due_at < v_requested_at THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='due_at precedes request time';
    END IF;

    RETURN QUERY
    INSERT INTO public.borrow_requests
        (resource_id, borrower_id, status, requested_at, due_at, returned_at)
    VALUES
        (p_resource_id, v_actor, 'pending', v_requested_at, p_due_at, NULL)
    RETURNING *;
END
$function$;

CREATE FUNCTION public.approve_borrow_request(
    p_request_id bigint,
    p_due_at timestamptz
)
RETURNS SETOF public.borrow_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_resource_id bigint;
    v_owner uuid;
    v_availability text;
    v_request public.borrow_requests%ROWTYPE;
    v_next_due_at timestamptz;
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_request_id IS NULL OR p_request_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid request ID';
    END IF;

    -- Read the immutable resource key, lock resource first, then lock/recheck request.
    SELECT b.resource_id INTO v_resource_id
    FROM public.borrow_requests AS b WHERE b.id=p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found';
    END IF;
    SELECT r.owner_id, r.availability_status INTO v_owner, v_availability
    FROM public.resources AS r WHERE r.id=v_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    SELECT b.* INTO v_request
    FROM public.borrow_requests AS b WHERE b.id=p_request_id FOR UPDATE;
    IF NOT FOUND OR v_request.resource_id <> v_resource_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request changed; retry after refresh';
    END IF;
    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may change this request';
    END IF;
    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not pending';
    END IF;
    IF v_request.borrower_id=v_actor THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Owner cannot approve own request';
    END IF;
    IF v_availability <> 'available' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resource unavailable';
    END IF;

    v_next_due_at := COALESCE(p_due_at, v_request.due_at);
    IF v_next_due_at IS NOT NULL AND v_next_due_at < v_request.requested_at THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='due_at precedes request time';
    END IF;

    UPDATE public.resources
    SET availability_status='unavailable'
    WHERE id=v_resource_id AND owner_id=v_actor AND availability_status='available';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resource availability changed';
    END IF;
    RETURN QUERY
    UPDATE public.borrow_requests AS b
    SET status='approved', due_at=v_next_due_at
    WHERE b.id=p_request_id AND b.status='pending'
    RETURNING b.*;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not pending';
    END IF;
END
$function$;

CREATE FUNCTION public.reject_borrow_request(p_request_id bigint)
RETURNS SETOF public.borrow_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_resource_id bigint;
    v_owner uuid;
    v_request public.borrow_requests%ROWTYPE;
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_request_id IS NULL OR p_request_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid request ID';
    END IF;
    SELECT b.resource_id INTO v_resource_id
    FROM public.borrow_requests AS b WHERE b.id=p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found';
    END IF;
    SELECT r.owner_id INTO v_owner
    FROM public.resources AS r WHERE r.id=v_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    SELECT b.* INTO v_request
    FROM public.borrow_requests AS b WHERE b.id=p_request_id FOR UPDATE;
    IF NOT FOUND OR v_request.resource_id <> v_resource_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request changed; retry after refresh';
    END IF;
    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may change this request';
    END IF;
    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not pending';
    END IF;
    RETURN QUERY
    UPDATE public.borrow_requests AS b SET status='rejected'
    WHERE b.id=p_request_id AND b.status='pending'
    RETURNING b.*;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not pending';
    END IF;
END
$function$;

CREATE FUNCTION public.return_borrowed_resource(p_request_id bigint)
RETURNS SETOF public.borrow_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_resource_id bigint;
    v_owner uuid;
    v_availability text;
    v_request public.borrow_requests%ROWTYPE;
    v_returned_at timestamptz := pg_catalog.statement_timestamp();
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_request_id IS NULL OR p_request_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid request ID';
    END IF;
    SELECT b.resource_id INTO v_resource_id
    FROM public.borrow_requests AS b WHERE b.id=p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found';
    END IF;
    SELECT r.owner_id, r.availability_status INTO v_owner, v_availability
    FROM public.resources AS r WHERE r.id=v_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;
    SELECT b.* INTO v_request
    FROM public.borrow_requests AS b WHERE b.id=p_request_id FOR UPDATE;
    IF NOT FOUND OR v_request.resource_id <> v_resource_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request changed; retry after refresh';
    END IF;
    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may change this request';
    END IF;
    IF v_request.status <> 'approved' OR v_availability <> 'unavailable' THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not an active approved loan';
    END IF;

    UPDATE public.borrow_requests AS b
    SET status='returned', returned_at=v_returned_at
    WHERE b.id=p_request_id AND b.status='approved'
    RETURNING b.* INTO v_request;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not an active approved loan';
    END IF;
    UPDATE public.resources AS r
    SET availability_status='available'
    WHERE r.id=v_resource_id AND r.owner_id=v_actor AND r.availability_status='unavailable';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Resource availability changed';
    END IF;
    RETURN NEXT v_request;
END
$function$;

CREATE FUNCTION public.update_resource_atomic(p_resource_id bigint, p_changes jsonb)
RETURNS SETOF public.resources
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_resource public.resources%ROWTYPE;
    v_next_availability text;
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0
       OR p_changes IS NULL
       OR pg_catalog.jsonb_typeof(p_changes) <> 'object'
       OR p_changes = '{}'::jsonb
       OR pg_catalog.octet_length(p_changes::text) > 16384 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid resource changes';
    END IF;
    IF (p_changes - ARRAY['title','description','category_id','resource_type','availability_status']::text[]) <> '{}'::jsonb THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Unsupported resource field';
    END IF;
    IF p_changes ? 'title' AND
       (pg_catalog.jsonb_typeof(p_changes->'title') <> 'string' OR pg_catalog.btrim(p_changes->>'title') = '') THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid title';
    END IF;
    IF p_changes ? 'description' AND pg_catalog.jsonb_typeof(p_changes->'description') NOT IN ('string','null') THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid description';
    END IF;
    IF p_changes ? 'category_id' AND pg_catalog.jsonb_typeof(p_changes->'category_id') NOT IN ('number','string','null') THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid category ID';
    END IF;
    IF p_changes ? 'category_id' AND pg_catalog.jsonb_typeof(p_changes->'category_id') IN ('number','string') AND
       (p_changes->>'category_id' !~ '^[0-9]+$'
        OR (p_changes->>'category_id')::numeric <= 0
        OR (p_changes->>'category_id')::numeric > 9223372036854775807) THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid category ID';
    END IF;
    IF p_changes ? 'resource_type' AND
       (pg_catalog.jsonb_typeof(p_changes->'resource_type') <> 'string' OR pg_catalog.btrim(p_changes->>'resource_type') = '') THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid resource type';
    END IF;
    IF p_changes ? 'availability_status' AND
       (pg_catalog.jsonb_typeof(p_changes->'availability_status') <> 'string'
        OR p_changes->>'availability_status' NOT IN ('available','unavailable')) THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid availability status';
    END IF;

    SELECT r.* INTO v_resource
    FROM public.resources AS r
    WHERE r.id=p_resource_id AND r.owner_id=v_actor
    FOR UPDATE;
    IF NOT FOUND THEN
        IF EXISTS (SELECT 1 FROM public.resources AS r WHERE r.id=p_resource_id) THEN
            RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the owner may update this resource';
        END IF;
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;

    v_next_availability := CASE WHEN p_changes ? 'availability_status'
        THEN p_changes->>'availability_status' ELSE v_resource.availability_status END;
    IF v_next_availability='available' AND EXISTS (
        SELECT 1 FROM public.borrow_requests AS b
        WHERE b.resource_id=p_resource_id AND b.status='approved'
    ) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Approved loan remains active';
    END IF;

    RETURN QUERY
    UPDATE public.resources AS r SET
        title=CASE WHEN p_changes ? 'title' THEN p_changes->>'title' ELSE r.title END,
        description=CASE WHEN p_changes ? 'description'
            THEN CASE WHEN pg_catalog.jsonb_typeof(p_changes->'description')='null'
                      THEN NULL ELSE p_changes->>'description' END
            ELSE r.description END,
        category_id=CASE WHEN p_changes ? 'category_id'
            THEN CASE WHEN pg_catalog.jsonb_typeof(p_changes->'category_id')='null'
                      THEN NULL ELSE (p_changes->>'category_id')::bigint END
            ELSE r.category_id END,
        resource_type=CASE WHEN p_changes ? 'resource_type' THEN p_changes->>'resource_type' ELSE r.resource_type END,
        availability_status=v_next_availability
    WHERE r.id=p_resource_id AND r.owner_id=v_actor
    RETURNING r.*;
END
$function$;

-- Definer routines are a narrow authenticated RPC boundary; PUBLIC, anon, and service_role
-- receive no EXECUTE. The frontend never receives a service-role key.
REVOKE ALL PRIVILEGES ON FUNCTION public.create_borrow_request(bigint,timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.approve_borrow_request(bigint,timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.reject_borrow_request(bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.update_resource_atomic(bigint,jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_borrow_request(bigint,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_borrow_request(bigint,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_borrow_request(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_resource_atomic(bigint,jsonb) TO authenticated;

COMMENT ON FUNCTION public.create_borrow_request(bigint,timestamptz) IS 'CampusShare staging Task 8 RPC migration v1';
COMMENT ON FUNCTION public.approve_borrow_request(bigint,timestamptz) IS 'CampusShare staging Task 8 RPC migration v1';
COMMENT ON FUNCTION public.reject_borrow_request(bigint) IS 'CampusShare staging Task 8 RPC migration v1';
COMMENT ON FUNCTION public.return_borrowed_resource(bigint) IS 'CampusShare staging Task 8 RPC migration v1';
COMMENT ON FUNCTION public.update_resource_atomic(bigint,jsonb) IS 'CampusShare staging Task 8 RPC migration v1';

COMMIT;
