-- PROPOSAL ONLY. Never execute this file against production without explicit approval.
-- New function design based on the audited public.resources fields and current PATCH payload.
-- Signature/return contract are newly proposed here; they are not reported as an existing DB function.
-- Deploy and validate in staging first. No direct-write grants are changed by this file.
--
-- Concurrency design: lock the target resource row. Existing status RPCs were reported to lock
-- that same resource during approve/return; re-inspect their exact bodies in staging to confirm.
-- Ownership is derived from auth.uid(). SECURITY DEFINER requires a trusted owner with table
-- privileges; the body must keep its fixed empty search_path and schema-qualified references.
-- The audited schema uses text columns with no confirmed per-column length constraints, so this
-- proposal does not invent title/description lengths. It caps the JSON changes payload at 16 KiB,
-- matching the backend mutation-body limit. Confirm this cap in staging before relying on it.

BEGIN;

DO $preflight$
BEGIN
    IF to_regclass('public.resources') IS NULL OR to_regclass('public.borrow_requests') IS NULL THEN
        RAISE EXCEPTION 'Expected CampusShare resource tables are missing';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = current_user AND (rolsuper OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'Function creator must be a trusted BYPASSRLS/superuser role';
    END IF;
    IF to_regprocedure('public.update_resource_atomic(bigint,jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'Function already exists; inspect it rather than replacing it';
    END IF;
END
$preflight$;

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
        RAISE EXCEPTION USING ERRCODE = '28000', MESSAGE = 'Permanent authenticated user required';
    END IF;
    IF p_resource_id IS NULL OR p_resource_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid resource ID';
    END IF;
    IF p_changes IS NULL OR pg_catalog.jsonb_typeof(p_changes) <> 'object' OR p_changes = '{}'::jsonb THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'A non-empty changes object is required';
    END IF;
    IF pg_catalog.octet_length(p_changes::text) > 16384 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Changes payload exceeds 16 KiB';
    END IF;
    IF (p_changes - ARRAY['title','description','category_id','resource_type','availability_status']) <> '{}'::jsonb THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Unsupported resource field';
    END IF;
    IF p_changes ? 'title' AND
       (pg_catalog.jsonb_typeof(p_changes->'title') <> 'string' OR pg_catalog.btrim(p_changes->>'title') = '') THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid title';
    END IF;
    IF p_changes ? 'description' AND
       pg_catalog.jsonb_typeof(p_changes->'description') NOT IN ('string','null') THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid description';
    END IF;
    IF p_changes ? 'category_id' AND pg_catalog.jsonb_typeof(p_changes->'category_id') NOT IN ('number','string','null') THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid category ID';
    END IF;
    IF p_changes ? 'category_id' AND pg_catalog.jsonb_typeof(p_changes->'category_id') IN ('number','string') AND
       (p_changes->>'category_id' !~ '^[0-9]+$' OR (p_changes->>'category_id')::numeric <= 0 OR
        (p_changes->>'category_id')::numeric > 9223372036854775807) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid category ID';
    END IF;
    IF p_changes ? 'resource_type' AND
       (pg_catalog.jsonb_typeof(p_changes->'resource_type') <> 'string' OR pg_catalog.btrim(p_changes->>'resource_type') = '') THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid resource type';
    END IF;
    IF p_changes ? 'availability_status' AND
       (pg_catalog.jsonb_typeof(p_changes->'availability_status') <> 'string' OR
        p_changes->>'availability_status' NOT IN ('available','unavailable')) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid availability status';
    END IF;

    SELECT r.* INTO v_resource
    FROM public.resources AS r
    WHERE r.id = p_resource_id AND r.owner_id = v_actor
    FOR UPDATE;
    IF NOT FOUND THEN
        IF EXISTS (SELECT 1 FROM public.resources AS r WHERE r.id = p_resource_id) THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owner may update this resource';
        END IF;
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Resource not found';
    END IF;

    v_next_availability := CASE
        WHEN p_changes ? 'availability_status' THEN p_changes->>'availability_status'
        ELSE v_resource.availability_status
    END;
    IF v_next_availability = 'available' AND EXISTS (
        SELECT 1 FROM public.borrow_requests AS b
        WHERE b.resource_id = p_resource_id AND b.status = 'approved'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Approved loan remains active';
    END IF;

    RETURN QUERY
    UPDATE public.resources AS r SET
        title = CASE WHEN p_changes ? 'title' THEN p_changes->>'title' ELSE r.title END,
        description = CASE WHEN p_changes ? 'description'
                           THEN CASE WHEN pg_catalog.jsonb_typeof(p_changes->'description') = 'null'
                                     THEN NULL ELSE p_changes->>'description' END
                           ELSE r.description END,
        category_id = CASE WHEN p_changes ? 'category_id'
                           THEN CASE WHEN pg_catalog.jsonb_typeof(p_changes->'category_id') = 'null'
                                     THEN NULL ELSE (p_changes->>'category_id')::bigint END
                           ELSE r.category_id END,
        resource_type = CASE WHEN p_changes ? 'resource_type' THEN p_changes->>'resource_type' ELSE r.resource_type END,
        availability_status = v_next_availability
    WHERE r.id = p_resource_id AND r.owner_id = v_actor
    RETURNING r.*;
END
$function$;

REVOKE ALL ON FUNCTION public.update_resource_atomic(bigint,jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.update_resource_atomic(bigint,jsonb) TO authenticated;

COMMIT;

-- Deployment/rollback notes:
-- 1. Review and rehearse in staging; validate category FK, ownership, RLS, ACL, return shape,
--    and races against approval/return before application rollout.
-- 2. Keep direct authenticated PATCH grants until the compatible backend and two-user tests pass.
-- 3. Only after staging and owner approval, revoke direct availability UPDATE if that is the
--    approved policy. This proposal intentionally does not alter table grants or RLS policies.
-- 4. Rollback the backend first. Revoke this function's authenticated EXECUTE before dropping it,
--    and only after verifying no deployed caller remains. No rollback SQL is run automatically.
