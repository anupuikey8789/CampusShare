-- FINAL-REVIEW PROPOSAL ONLY: apply only to the reviewed CampusShare-Staging
-- schema after owner approval. Never apply to production. This adjusts schema
-- USAGE and privileges on the four application tables only; it does not grant
-- function execution or change any status RPC ACL.
--
-- Secure target: request creation must use a separately reviewed RPC contract.
-- Therefore direct INSERT on borrow_requests is deliberately not granted.
-- With the current C++ flag false, POST /api/borrow-requests returns HTTP 503
-- before any PostgREST resource/request read or write. Do not grant direct
-- request INSERT; the app can use the RPC only after staging verification.

DO $preflight$
BEGIN
    IF to_regclass('public.profiles') IS NULL
       OR to_regclass('public.categories') IS NULL
       OR to_regclass('public.resources') IS NULL
       OR to_regclass('public.borrow_requests') IS NULL THEN
        RAISE EXCEPTION 'Expected CampusShare staging tables are missing';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_attribute AS a
        JOIN pg_class AS c ON c.oid = a.attrelid
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname IN ('profiles', 'categories', 'resources', 'borrow_requests')
          AND a.attnum > 0 AND NOT a.attisdropped
          AND a.attacl IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Explicit column ACLs exist; inspect them before table privilege reset';
    END IF;
END
$preflight$;

BEGIN;

-- Remove existing/default table privileges from public, anon, authenticated,
-- and service_role on these four staging tables, then grant only the operations
-- below. This file does not change role-wide/default ACLs or other objects.
REVOKE ALL PRIVILEGES ON TABLE
    public.profiles, public.categories, public.resources, public.borrow_requests
FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON SCHEMA public TO authenticated;

-- No profile table access is required by current C++/frontend API routes.
-- The Auth trigger proposal runs as its trusted owner to create the profile.

GRANT SELECT ON TABLE public.categories TO authenticated;

GRANT SELECT ON TABLE public.resources TO authenticated;
GRANT INSERT (title, description, category_id, owner_id, resource_type, availability_status)
    ON TABLE public.resources TO authenticated;
GRANT UPDATE (title, description, category_id, resource_type, availability_status)
    ON TABLE public.resources TO authenticated;
GRANT DELETE ON TABLE public.resources TO authenticated;

-- Borrower/owner reads use the two verified SELECT policies and resource SELECT.
GRANT SELECT ON TABLE public.borrow_requests TO authenticated;

-- Deliberately absent:
-- * profiles SELECT/INSERT/UPDATE/DELETE: no current app route needs direct access.
-- * borrow_requests INSERT/UPDATE/DELETE: direct INSERT is not safe; status
--   mutations have no table UPDATE grant/policy and no backend route.
-- * privileges for anon or PUBLIC, and any grant to service_role.
-- * EXECUTE privileges on create_borrow_request or status RPCs.

COMMIT;
