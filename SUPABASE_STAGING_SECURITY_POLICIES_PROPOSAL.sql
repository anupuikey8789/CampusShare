-- PROPOSAL ONLY for CampusShare-Staging. Review and apply only after checking
-- the staging project reference. Do not apply to production.
-- This updates staging RLS policies and adds one staging-only unique index.
-- It does not define or grant any RPC, and it does not change table grants.
--
-- The expressions below retain the audited owner/borrower rules, reject
-- anonymous Auth identities (which may use the authenticated database role),
-- and strengthen request INSERT. A policy check alone is not a concurrency
-- primitive; the pending-pair unique index below is an additional guard.

DO $preflight$
DECLARE
    v_policy_count integer;
BEGIN
    IF to_regclass('public.profiles') IS NULL
       OR to_regclass('public.categories') IS NULL
       OR to_regclass('public.resources') IS NULL
       OR to_regclass('public.borrow_requests') IS NULL THEN
        RAISE EXCEPTION 'Expected CampusShare staging tables are missing';
    END IF;

    SELECT count(*) INTO v_policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('profiles', 'categories', 'resources', 'borrow_requests');
    IF v_policy_count <> 10 THEN
        RAISE EXCEPTION 'Expected the ten audited policies; inspect staging policies before continuing';
    END IF;

    IF to_regclass('public.one_pending_request_per_borrower_resource') IS NOT NULL THEN
        RAISE EXCEPTION 'Pending-pair index already exists; inspect its exact definition';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.borrow_requests
        WHERE status = 'pending'
        GROUP BY borrower_id, resource_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Pending duplicates exist; resolve by approved staging procedure before index creation';
    END IF;
END
$preflight$;

BEGIN;

-- Recheck each named policy exists before relying on ALTER POLICY.
DO $policy_preflight$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Read own profile')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Update own profile')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='categories' AND policyname='Read categories')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='resources' AND policyname='Read resources')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='resources' AND policyname='Add own resources')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='resources' AND policyname='Update own resources')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='resources' AND policyname='Delete own resources')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='borrow_requests' AND policyname='Create own borrow requests')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='borrow_requests' AND policyname='Read own borrow requests')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='borrow_requests' AND policyname='Owners read requests for their resources') THEN
        RAISE EXCEPTION 'An audited policy is missing; inspect staging before continuing';
    END IF;
END
$policy_preflight$;

ALTER POLICY "Read own profile" ON public.profiles
    USING ((SELECT auth.uid()) = id
       AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false);

ALTER POLICY "Update own profile" ON public.profiles
    USING ((SELECT auth.uid()) = id
       AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false)
    WITH CHECK ((SELECT auth.uid()) = id
       AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false);

ALTER POLICY "Read categories" ON public.categories
    USING (COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false);

ALTER POLICY "Read resources" ON public.resources
    USING (COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false);

ALTER POLICY "Add own resources" ON public.resources
    WITH CHECK ((SELECT auth.uid()) = owner_id
       AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false);

ALTER POLICY "Update own resources" ON public.resources
    USING ((SELECT auth.uid()) = owner_id
       AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false)
    WITH CHECK ((SELECT auth.uid()) = owner_id
       AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false);

ALTER POLICY "Delete own resources" ON public.resources
    USING ((SELECT auth.uid()) = owner_id
       AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false);

-- Insert check: identity, permanent Auth identity, initial state, valid dates,
-- non-self borrowing, available resource, and no existing active request for
-- this borrower/resource pair. `requested_at <= now` only rejects future times;
-- the RPC must ignore any client timestamp and set it server-side.
ALTER POLICY "Create own borrow requests" ON public.borrow_requests
    WITH CHECK (
        borrower_id = (SELECT auth.uid())
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
        AND status = 'pending'
        AND returned_at IS NULL
        AND requested_at <= statement_timestamp()
        AND (due_at IS NULL OR due_at >= requested_at)
        AND EXISTS (
            SELECT 1 FROM public.resources AS r
            WHERE r.id = borrow_requests.resource_id
              AND r.owner_id <> (SELECT auth.uid())
              AND r.availability_status = 'available'
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.borrow_requests AS prior
            WHERE prior.borrower_id = (SELECT auth.uid())
              AND prior.resource_id = borrow_requests.resource_id
              AND prior.status IN ('pending', 'approved')
        )
    );

ALTER POLICY "Read own borrow requests" ON public.borrow_requests
    USING ((SELECT auth.uid()) = borrower_id
       AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false);

ALTER POLICY "Owners read requests for their resources" ON public.borrow_requests
    USING (
        COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
        AND EXISTS (
            SELECT 1 FROM public.resources AS r
            WHERE r.id = borrow_requests.resource_id
              AND r.owner_id = (SELECT auth.uid())
        )
    );

-- This protects same-borrower/same-resource pending duplicates across
-- concurrent transactions. It does not serialize availability changes or
-- competing borrowers; the reviewed RPC must lock the resource row.
CREATE UNIQUE INDEX one_pending_request_per_borrower_resource
    ON public.borrow_requests (borrower_id, resource_id)
    WHERE status = 'pending';

COMMIT;
