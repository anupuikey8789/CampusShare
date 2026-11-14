-- CampusShare STAGING schema reconstruction, based only on checked-in audit
-- evidence. This is a setup script, NOT a read-only audit. Do not execute it
-- against production or against a staging project containing existing objects.
-- No credentials, data rows, Auth trigger/function, RPCs, or permission changes
-- are included. Review the companion setup guide before any staging use.

DO $preflight$
BEGIN
    IF to_regclass('public.profiles') IS NOT NULL
       OR to_regclass('public.categories') IS NOT NULL
       OR to_regclass('public.resources') IS NOT NULL
       OR to_regclass('public.borrow_requests') IS NOT NULL THEN
        RAISE EXCEPTION 'CampusShare tables already exist; inspect the staging project and stop';
    END IF;
END
$preflight$;

BEGIN;

CREATE TABLE public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name text NOT NULL,
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

-- This partial unique index is recorded in the audit snapshot. It permits at
-- most one approved request per resource; it does not constrain pending rows.
CREATE UNIQUE INDEX one_active_approval_per_resource
    ON public.borrow_requests (resource_id)
    WHERE status = 'approved';

-- Non-unique lookup indexes were reported missing by the audit and are included
-- as staging performance indexes. They do not change row-level business rules.
CREATE INDEX resources_category_id_idx ON public.resources (category_id);
CREATE INDEX resources_owner_id_idx ON public.resources (owner_id);
CREATE INDEX borrow_requests_borrower_id_idx ON public.borrow_requests (borrower_id);
CREATE INDEX borrow_requests_resource_id_idx ON public.borrow_requests (resource_id);

-- RLS was verified enabled and not forced on these four tables.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.borrow_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Read own profile" ON public.profiles
    FOR SELECT TO authenticated
    USING ((SELECT auth.uid()) = id);

CREATE POLICY "Update own profile" ON public.profiles
    FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = id)
    WITH CHECK ((SELECT auth.uid()) = id);

CREATE POLICY "Read categories" ON public.categories
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Read resources" ON public.resources
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Add own resources" ON public.resources
    FOR INSERT TO authenticated
    WITH CHECK ((SELECT auth.uid()) = owner_id);

CREATE POLICY "Update own resources" ON public.resources
    FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = owner_id)
    WITH CHECK ((SELECT auth.uid()) = owner_id);

CREATE POLICY "Delete own resources" ON public.resources
    FOR DELETE TO authenticated
    USING ((SELECT auth.uid()) = owner_id);

-- This is the exact INSERT policy recorded in the audit, not a hardened
-- borrowing workflow. It checks borrower identity only and does not enforce
-- pending-only status, self-borrow prevention, resource availability, or
-- duplicate prevention. Keep direct borrowing writes disabled until a reviewed
-- database RPC/policy contract replaces or safely constrains this path.
CREATE POLICY "Create own borrow requests" ON public.borrow_requests
    FOR INSERT TO authenticated
    WITH CHECK ((SELECT auth.uid()) = borrower_id);

CREATE POLICY "Read own borrow requests" ON public.borrow_requests
    FOR SELECT TO authenticated
    USING ((SELECT auth.uid()) = borrower_id);

CREATE POLICY "Owners read requests for their resources" ON public.borrow_requests
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.resources
            WHERE resources.id = borrow_requests.resource_id
              AND resources.owner_id = (SELECT auth.uid())
        )
    );

-- Deliberately omitted:
-- * handle_new_user() and on_auth_user_created: the audit documents behavior,
--   but the function's exact source is not present in this repository.
-- * Status/request/availability RPCs: full definitions and staging contracts
--   are not part of this reconstructed schema package.
-- * Table/schema/function GRANT or REVOKE statements: permissions are left
--   unchanged per task restrictions. RLS policies do not themselves grant SQL
--   privileges; see SUPABASE_STAGING_SETUP_GUIDE.md before staging API tests.
-- * Pending-request unique index: it is a proposal, not a verified constraint.
-- * Category seed rows: no category row values are included in the audit.
COMMIT;
