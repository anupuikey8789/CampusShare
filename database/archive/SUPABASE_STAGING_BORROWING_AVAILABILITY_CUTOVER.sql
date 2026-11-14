-- CampusShare staging-only permission cutover proposal.
-- Never run against production. Codex did not execute this file.
--
-- Purpose: prevent authenticated callers from bypassing the resource lock and
-- status invariants by directly PATCHing availability_status through PostgREST.
-- Apply only after update_resource_atomic is installed/reviewed and the backend
-- has been deployed with SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true.
-- Status actions additionally require SUPABASE_RPC_BORROW_STATUS=true.
--
-- This preserves authenticated column updates to resource metadata granted by
-- SUPABASE_STAGING_GRANTS_FINAL_REVIEW.sql. Availability changes then go only
-- through the atomic SECURITY DEFINER RPC. Review effective grants (including
-- inherited role grants) in the validation query before applying.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
DECLARE
    v_rpc_oid oid;
    v_owner_bypass boolean;
    v_safe_search_path boolean;
BEGIN
    IF to_regclass('public.resources') IS NULL THEN
        RAISE EXCEPTION 'public.resources is missing; stop and inspect staging';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_catalog.pg_class
            WHERE oid='public.resources'::regclass) THEN
        RAISE EXCEPTION 'RLS must remain enabled on public.resources';
    END IF;
    IF has_table_privilege('authenticated', 'public.resources', 'UPDATE') THEN
        RAISE EXCEPTION 'authenticated has table-level resource UPDATE; inspect and remove broad grants before cutover';
    END IF;

    v_rpc_oid := to_regprocedure('public.update_resource_atomic(bigint,jsonb)');
    IF v_rpc_oid IS NULL THEN
        RAISE EXCEPTION 'update_resource_atomic(bigint,jsonb) is not installed';
    END IF;
    SELECT (owner.rolsuper OR owner.rolbypassrls),
           COALESCE(p.proconfig @> ARRAY['search_path=""'], false)
      INTO v_owner_bypass, v_safe_search_path
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_roles AS owner ON owner.oid=p.proowner
    WHERE p.oid=v_rpc_oid AND p.prosecdef;
    IF NOT COALESCE(v_owner_bypass, false) OR NOT COALESCE(v_safe_search_path, false) THEN
        RAISE EXCEPTION 'update_resource_atomic must be SECURITY DEFINER, have an empty search_path, and use its reviewed trusted owner';
    END IF;
    IF NOT has_function_privilege('authenticated', v_rpc_oid, 'EXECUTE')
       OR has_function_privilege('anon', v_rpc_oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'RPC EXECUTE ACLs do not match the authenticated-only staging contract';
    END IF;
    IF NOT has_column_privilege('authenticated', 'public.resources', 'availability_status', 'UPDATE') THEN
        RAISE EXCEPTION 'Expected pre-cutover availability column grant was not found; inspect actual ACL state';
    END IF;
END
$preflight$;

-- Keep title/description/category/type column grants; remove only direct
-- authenticated writes to the field that participates in the loan invariant.
REVOKE UPDATE (availability_status) ON TABLE public.resources FROM authenticated;

DO $postflight$
BEGIN
    IF has_column_privilege('authenticated', 'public.resources', 'availability_status', 'UPDATE') THEN
        RAISE EXCEPTION 'availability_status remains directly updatable by authenticated; inspect inherited/other grants';
    END IF;
END
$postflight$;

COMMIT;

-- Manual rollback guidance (do not run automatically): first set both RPC flags
-- false and stop the RPC backend. If restoring the old direct-PATCH application,
-- and only if the pre-cutover grant was present as in the reviewed grants file,
-- a staging owner may restore it with:
--   GRANT UPDATE (availability_status) ON TABLE public.resources TO authenticated;
-- Restoring this grant permits direct availability changes and weakens the
-- cross-table consistency guarantee. Review that risk before any rollback.
