-- PROPOSAL ONLY: new staging function contract for CampusShare request creation.
-- This is not a discovered or deployed production definition. Never execute in
-- production. Review the lock-order and function-owner prerequisites below.
-- No approve/reject/return function is defined or altered by this file.
--
-- Required coordination: update_resource_atomic locks resources first. Status
-- approval/return routines must also lock the resource before locking/changing
-- the request row. Their deployed bodies/order are unknown, so do not use this
-- function concurrently with them until staging inspection confirms compatible
-- resource -> request lock ordering.

DO $preflight$
BEGIN
    IF to_regclass('public.resources') IS NULL
       OR to_regclass('public.borrow_requests') IS NULL THEN
        RAISE EXCEPTION 'Expected CampusShare staging tables are missing';
    END IF;
    IF to_regprocedure('public.create_borrow_request(bigint,timestamp with time zone)') IS NOT NULL THEN
        RAISE EXCEPTION 'create_borrow_request already exists; inspect it instead of replacing it';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = current_user AND (rolsuper OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'Function owner must be a trusted RLS-bypass database role';
    END IF;
    IF NOT has_table_privilege(current_user, 'public.resources', 'SELECT')
       OR NOT has_table_privilege(current_user, 'public.resources', 'UPDATE')
       OR NOT has_table_privilege(current_user, 'public.borrow_requests', 'SELECT')
       OR NOT has_table_privilege(current_user, 'public.borrow_requests', 'INSERT') THEN
        RAISE EXCEPTION 'Function owner lacks required resource-lock/request table privileges';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index AS i
        WHERE i.indexrelid = to_regclass('public.one_active_request_per_borrower_resource')
          AND i.indisunique AND i.indisvalid AND i.indisready
    ) THEN
        RAISE EXCEPTION 'Expected valid active-pair unique index is missing; inspect staging';
    END IF;
END
$preflight$;

BEGIN;

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
    v_is_anonymous boolean := COALESCE(
        (SELECT (auth.jwt()->>'is_anonymous')::boolean), true
    );
    v_owner uuid;
    v_availability text;
    v_requested_at timestamptz;
BEGIN
    -- Fail closed for missing identities and Auth anonymous users. The
    -- authenticated Postgres role alone does not distinguish those identities.
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE = '28000', MESSAGE = 'Authentication required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid resource ID';
    END IF;

    -- Match update_resource_atomic: lock the shared resource row first. This
    -- serializes creation against availability changes that follow this order.
    SELECT r.owner_id, r.availability_status
      INTO v_owner, v_availability
    FROM public.resources AS r
    WHERE r.id = p_resource_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Resource not found';
    END IF;
    IF v_owner = v_actor THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Cannot request own resource';
    END IF;
    IF v_availability IS DISTINCT FROM 'available' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Resource unavailable';
    END IF;

    -- Different borrowers may have pending requests if that product behavior
    -- is approved. A borrower may not have another pending or approved request
    -- for this resource. The partial unique index is the concurrent backstop.
    IF EXISTS (
        SELECT 1
        FROM public.borrow_requests AS prior
        WHERE prior.borrower_id = v_actor
          AND prior.resource_id = p_resource_id
          AND prior.status IN ('pending', 'approved')
    ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Active request exists';
    END IF;

    -- Match the INSERT policy's statement_timestamp() predicate exactly. Both
    -- values refer to the PostgREST RPC statement, so requested_at is not
    -- rejected as later than the policy's timestamp by a clock-time race.
    v_requested_at := pg_catalog.statement_timestamp();
    IF p_due_at IS NOT NULL AND p_due_at < v_requested_at THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'due_at precedes request time';
    END IF;

    -- Actor, initial status, request time, and return state are always generated
    -- here; no client-supplied borrower/status/timestamps are accepted.
    RETURN QUERY
    INSERT INTO public.borrow_requests (
        resource_id, borrower_id, status, requested_at, due_at, returned_at
    )
    VALUES (
        p_resource_id, v_actor, 'pending', v_requested_at, p_due_at, NULL
    )
    RETURNING *;
END
$function$;

-- Remove the default PUBLIC EXECUTE ACL and any direct API-role access, then
-- grant only the intended signed-in Data API role. The function owner retains
-- implicit owner rights. This file changes no other routine ACL.
REVOKE ALL PRIVILEGES ON FUNCTION
    public.create_borrow_request(bigint, timestamptz)
FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION
    public.create_borrow_request(bigint, timestamptz)
TO authenticated;

COMMIT;

-- C++ compatibility contract: POST /api/borrow-requests sends only
-- {"p_resource_id": positive bigint, "p_due_at": nullable timestamptz} to
-- PostgREST. The existing handler expects one row in a JSON array. Error
-- SQLSTATEs/messages above map to its sanitized 401/400/404/409 responses.
-- Keep SUPABASE_RPC_CREATE_BORROW_REQUEST=false until the exact function,
-- permissions, response shape, and two-account/concurrency tests pass in staging.
