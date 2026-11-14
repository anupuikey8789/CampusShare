# CampusShare Supabase Database Audit

**Snapshot:** 2026-11-10. **Project:** CampusShare production, ref dkyfkdmlkghucyepxbbh. **Method:** read-only metadata, aggregate counts, Supabase Security/Performance/Health Advisors. No row values were read, RPC called, or correction executed. Re-run [audit SQL](SUPABASE_READ_ONLY_AUDIT.sql) before approved migration.

## Schema / constraints
RLS is enabled, not forced, on all four public tables.
- profiles: id uuid PK, full_name/email text NOT NULL, student_id nullable UNIQUE, created_at timestamptz DEFAULT now().
- categories: id bigint GENERATED ALWAYS identity PK, name text NOT NULL UNIQUE, created_at timestamptz DEFAULT now().
- resources: id bigint GENERATED ALWAYS identity PK, title text NOT NULL, description nullable, category_id nullable, owner_id uuid NOT NULL, resource_type text DEFAULT 'Other', availability_status text DEFAULT 'available', created_at timestamptz DEFAULT now().
- borrow_requests: id bigint GENERATED ALWAYS identity PK, resource_id bigint NOT NULL, borrower_id uuid NOT NULL, status text DEFAULT 'pending' NOT NULL, requested_at timestamptz DEFAULT now() NOT NULL, due_at/returned_at nullable.
FKs: profiles.id→auth.users.id CASCADE; resources.owner_id→profiles.id; resources.category_id→categories.id; borrow_requests.borrower_id→profiles.id; borrow_requests.resource_id→resources.id. Other deletes NO ACTION. Checks: due_at/returned_at NULL or >= requested_at; status pending/approved/rejected/returned; availability available/unavailable. Unique keys include category name, profile student_id and partial request resource_id WHERE status='approved'.

## Policies and grants
All ten policies target authenticated. borrow_requests INSERT checks only borrower_id=auth.uid(); SELECT allows own borrower rows and resource owners via EXISTS. categories SELECT true. profiles SELECT own id and UPDATE own id in USING/WITH CHECK. resources SELECT true; INSERT owner_id=auth.uid(); DELETE owner_id=auth.uid(); UPDATE owner_id=auth.uid() in USING/WITH CHECK. No borrow_requests UPDATE policy. Permissive policies OR together.

**Critical gap:** request INSERT does not require status=pending, prevent self-borrow, require resource available, or prevent an active duplicate. Direct authenticated PostgREST calls can attempt initial approved/rejected/returned statuses; backend checks do not protect direct table access.

Observed table grants: anon and authenticated each have SELECT/INSERT/DELETE/REFERENCES/TRIGGER/TRUNCATE on borrow_requests (no UPDATE); SELECT/INSERT/UPDATE/DELETE/REFERENCES/TRIGGER/TRUNCATE on categories, profiles, resources. No PUBLIC table grants or explicit column ACLs returned. Grants do not bypass RLS but are a separate gate. App needs categories SELECT; resources SELECT/INSERT/UPDATE/DELETE; requests SELECT/INSERT; no profile endpoint. Column-level resource grants match current API and prevent direct edits to id/owner/created_at. Request API sends status/requested_at/returned_at, so column-only request INSERT needs a compatible backend change.

## Auth trigger
on_auth_user_created AFTER INSERT on auth.users calls public.handle_new_user(). Owned by postgres, SECURITY DEFINER, empty search_path; explicitly inserts profiles id/full_name/email from Auth id/email and raw_user_meta_data.full_name (empty fallback). Empty names accepted. Its EXECUTE includes PUBLIC, anon, authenticated, service_role; Security Advisor flags it. Preserve trigger; test signup in staging after proposed ACL revoke.

## Status RPCs: important additional finding
Three public SECURITY DEFINER functions owned by postgres, empty search_path, EXECUTE granted PUBLIC/anon/authenticated/service_role:
- approve_borrow_request(bigint,timestamptz): checks auth.uid, owner, pending, non-self, available; locks request/resource; sets approved and resource unavailable.
- reject_borrow_request(bigint): checks authenticated owner and pending; locks request, sets rejected.
- return_borrowed_resource(bigint): checks owner and approved; locks request/resource; sets returned and resource available. Return is owner-confirmed only.

Thus authenticated RPC status changes are already available despite no table UPDATE grant/policy. App has no routes and no RPC was called. Function bodies contain ownership/status guards, but PUBLIC/anon exposure is unnecessary; keep RPCs disabled until actor/transition rules are approved. Return actor needs confirmation.

## Indexes, data, advisors
Seven indexes: four PKs; categories_name_key; profiles_student_id_key; one_active_approval_per_resource (partial approved). It does not prevent duplicate pending. Counts: 5 categories, zero profiles/resources/requests; zero pending duplicate pairs. Recheck before indexes; never auto-clean new conflicts.

Performance Advisor: missing indexes on borrow_requests.borrower_id and resources.category_id/owner_id; add full borrow_requests.resource_id index because listed index is partial. It also warns about the two permissive request SELECT policies; borrower OR owner access is intended. Security Advisor: 4 anon and 4 authenticated definer warnings (trigger + 3 RPCs). Health Advisor: no lints.

Confirmed: schema, policies, grants, trigger and RPC definitions/ACLs, counts/advisors. Untested: live signup/confirmation, trigger runtime, token-backed API/RLS, two-user isolation, RPC behavior, FK deletes, duplicate races, correction behavior. No credentials or personal records read.
