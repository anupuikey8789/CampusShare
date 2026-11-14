-- FINAL-REVIEW PROPOSAL ONLY for CampusShare-Staging. Review and apply only after checking
-- the staging project reference. Do not apply to production.
-- This updates staging RLS policies and adds one staging-only unique index.
-- It does not define or grant any RPC, and it does not change table grants.
--
-- The expressions below retain the audited owner/borrower rules, reject
-- anonymous Auth identities (which may use the authenticated database role),
-- and strengthen request INSERT. A policy check alone is not a concurrency
-- primitive; the active-pair unique index below is an additional guard.

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

    IF to_regclass('public.one_active_request_per_borrower_resource') IS NOT NULL THEN
        RAISE EXCEPTION 'Active-pair index already exists; inspect its exact definition';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND policyname IN (
              'Permanent authenticated profiles',
              'Permanent authenticated categories',
              'Permanent authenticated resources',
              'Permanent authenticated borrow requests'
          )
    ) THEN
        RAISE EXCEPTION 'A restrictive identity policy already exists; inspect before continuing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.borrow_requests
        WHERE status IN ('pending', 'approved')
        GROUP BY borrower_id, resource_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Active duplicates exist; resolve by approved staging procedure before index creation';
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

-- Restrictive policies are ANDed with the audited permissive policies. This
-- avoids relying on every current and future permissive rule to repeat the
-- authenticated/non-anonymous identity gate.
CREATE POLICY "Permanent authenticated profiles" ON public.profiles
    AS RESTRICTIVE FOR ALL TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
    )
    WITH CHECK (
        (SELECT auth.uid()) IS NOT NULL
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
    );

CREATE POLICY "Permanent authenticated categories" ON public.categories
    AS RESTRICTIVE FOR ALL TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
    )
    WITH CHECK (
        (SELECT auth.uid()) IS NOT NULL
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
    );

CREATE POLICY "Permanent authenticated resources" ON public.resources
    AS RESTRICTIVE FOR ALL TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
    )
    WITH CHECK (
        (SELECT auth.uid()) IS NOT NULL
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
    );

CREATE POLICY "Permanent authenticated borrow requests" ON public.borrow_requests
    AS RESTRICTIVE FOR ALL TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
    )
    WITH CHECK (
        (SELECT auth.uid()) IS NOT NULL
        AND COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true) = false
    );

-- Insert check: identity, permanent Auth identity, initial state, valid dates,
-- non-self borrowing and an available resource. The active-pair unique index
-- prevents concurrent duplicates; the SECURITY DEFINER RPC performs the
-- active-request lookup without recursively invoking this table's RLS.
-- `requested_at <= now` only rejects future values; the RPC sets it server-side.
ALTER POLICY "Create own borrow requests" ON public.borrow_requests
    WITH CHECK (
        borrower_id = (SELECT auth.uid())
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
    );

-- The other nine policies retain their audited row rules. The restrictive
-- gates above apply to those reads and writes without introducing table
-- subqueries, so they do not add RLS recursion.

-- This protects same-borrower/same-resource active duplicates across
-- concurrent transactions. It does not serialize availability changes or
-- competing borrowers; the reviewed RPC must lock the resource row. The
-- broader active predicate matches the RPC's pending-or-approved rule.
CREATE UNIQUE INDEX one_active_request_per_borrower_resource
    ON public.borrow_requests (borrower_id, resource_id)
    WHERE status IN ('pending', 'approved');

COMMIT;
