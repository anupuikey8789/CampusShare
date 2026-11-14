-- PROPOSAL ONLY: apply only to the newly prepared CampusShare-Staging schema
-- after owner review. Never apply to production. This adjusts table privileges
-- on the four application tables only; it does not grant function execution or
-- change any status RPC ACL. No service_role privilege is granted.
--
-- Secure target: request creation must use a separately reviewed RPC contract.
-- Therefore direct INSERT on borrow_requests is deliberately not granted.
-- With the current C++ flag false, POST /api/borrow-requests will be denied
-- until the request RPC has been approved/deployed in staging and the app is
-- separately configured for that staging test.

DO $preflight$
BEGIN
    IF to_regclass('public.profiles') IS NULL
       OR to_regclass('public.categories') IS NULL
       OR to_regclass('public.resources') IS NULL
       OR to_regclass('public.borrow_requests') IS NULL THEN
        RAISE EXCEPTION 'Expected CampusShare staging tables are missing';
    END IF;
END
$preflight$;

BEGIN;

-- Remove table-level privileges from the public pseudo-role, anon, and
-- authenticated on these staging tables, then grant only the operations below.
-- service_role is intentionally untouched; the app must never use its key.
REVOKE ALL PRIVILEGES ON TABLE
    public.profiles, public.categories, public.resources, public.borrow_requests
FROM PUBLIC, anon, authenticated;

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
-- * privileges for anon, PUBLIC, or service_role.
-- * EXECUTE privileges on create_borrow_request or status RPCs.

COMMIT;
