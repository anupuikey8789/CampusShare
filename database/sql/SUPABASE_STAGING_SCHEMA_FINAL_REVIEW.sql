-- Final consistency-review copy of the CampusShare STAGING schema reconstruction.
-- STAGING ONLY: do not execute against production or an initialized project.
-- This is schema setup, not a read-only query. Review Task 4B files first.
-- No credentials, row data, grants, revokes, triggers, or RPC functions here.
-- The application currently signs up with email/password. Keep this profile
-- email NOT NULL shape only for staging configured to use email identities;
-- phone-only or email-less providers require an owner decision first.

DO $preflight$
BEGIN
    IF to_regclass('public.profiles') IS NOT NULL
       OR to_regclass('public.categories') IS NOT NULL
       OR to_regclass('public.resources') IS NOT NULL
       OR to_regclass('public.borrow_requests') IS NOT NULL THEN
        RAISE EXCEPTION 'CampusShare tables already exist; inspect staging and stop';
    END IF;
END
$preflight$;

BEGIN;

CREATE TABLE public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name text NOT NULL,
    -- Matches the current email/password frontend flow; not nullable in audit.
    email text NOT NULL,
    student_id text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.categories (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.resources (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title text NOT NULL,
    description text,
    category_id bigint,
    owner_id uuid NOT NULL,
    resource_type text NOT NULL DEFAULT 'Other',
    availability_status text NOT NULL DEFAULT 'available',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT resources_category_id_fkey
        FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE NO ACTION,
    CONSTRAINT resources_owner_id_fkey
        FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE NO ACTION,
    CONSTRAINT resources_availability_status_check
        CHECK (availability_status = ANY (ARRAY['available'::text, 'unavailable'::text]))
);

CREATE TABLE public.borrow_requests (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id bigint NOT NULL,
    borrower_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    requested_at timestamptz NOT NULL DEFAULT now(),
    due_at timestamptz,
    returned_at timestamptz,
    CONSTRAINT borrow_requests_borrower_id_fkey
        FOREIGN KEY (borrower_id) REFERENCES public.profiles(id) ON DELETE NO ACTION,
    CONSTRAINT borrow_requests_resource_id_fkey
        FOREIGN KEY (resource_id) REFERENCES public.resources(id) ON DELETE NO ACTION,
    CONSTRAINT borrow_requests_check
        CHECK ((due_at IS NULL) OR (due_at >= requested_at)),
    CONSTRAINT borrow_requests_check1
        CHECK ((returned_at IS NULL) OR (returned_at >= requested_at)),
    CONSTRAINT borrow_requests_status_check
        CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'returned'::text]))
);

-- Verified existing partial uniqueness rule.
CREATE UNIQUE INDEX one_active_approval_per_resource
    ON public.borrow_requests (resource_id)
    WHERE status = 'approved';

-- Staging performance additions recommended by the audit; these are not in the
-- reported production index inventory and do not change row uniqueness.
CREATE INDEX resources_category_id_idx ON public.resources (category_id);
CREATE INDEX resources_owner_id_idx ON public.resources (owner_id);
CREATE INDEX borrow_requests_borrower_id_idx ON public.borrow_requests (borrower_id);
CREATE INDEX borrow_requests_resource_id_idx ON public.borrow_requests (resource_id);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.borrow_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Read own profile" ON public.profiles
    FOR SELECT TO authenticated USING ((SELECT auth.uid()) = id);
CREATE POLICY "Update own profile" ON public.profiles
    FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = id)
    WITH CHECK ((SELECT auth.uid()) = id);
CREATE POLICY "Read categories" ON public.categories
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "Read resources" ON public.resources
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "Add own resources" ON public.resources
    FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = owner_id);
CREATE POLICY "Update own resources" ON public.resources
    FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = owner_id)
    WITH CHECK ((SELECT auth.uid()) = owner_id);
CREATE POLICY "Delete own resources" ON public.resources
    FOR DELETE TO authenticated USING ((SELECT auth.uid()) = owner_id);

-- This policy is reproduced from the audit for schema fidelity. It is not a
-- safe direct-write policy; see SUPABASE_STAGING_SECURITY_POLICIES_PROPOSAL.sql.
CREATE POLICY "Create own borrow requests" ON public.borrow_requests
    FOR INSERT TO authenticated WITH CHECK (
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
CREATE POLICY "Read own borrow requests" ON public.borrow_requests
    FOR SELECT TO authenticated USING ((SELECT auth.uid()) = borrower_id);
CREATE POLICY "Owners read requests for their resources" ON public.borrow_requests
    FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.resources
            WHERE resources.id = borrow_requests.resource_id
              AND resources.owner_id = (SELECT auth.uid())
        )
    );

COMMIT;
