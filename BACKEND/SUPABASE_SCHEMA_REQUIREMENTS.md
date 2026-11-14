# Supabase schema information required for CampusShare

## Latest read-only live metadata inspection

On 2026-11-01 the connected Supabase MCP listed the active project named `CampusShare` as `dkyfkdmlkghucyepxbbh` and returned read-only schema metadata for `public`. This verifies management/schema access for that project, not application Auth sessions or RLS-enforced API access. No table records were queried and no production objects or data were changed. A metadata count snapshot reported 5 categories and 0 profiles, resources, and borrowing requests.

The live column metadata confirms these definitions:

| Table | Column | Type | Nullability / default |
| --- | --- | --- | --- |
| `profiles` | `id` | `uuid` | NOT NULL; primary key; FK to `auth.users(id)` with `ON DELETE CASCADE` |
| `profiles` | `full_name` | `text` | NOT NULL; no default |
| `profiles` | `email` | `text` | NOT NULL; no default |
| `profiles` | `student_id` | `text` | nullable; unique when non-NULL |
| `profiles` | `created_at` | `timestamptz` | NOT NULL; default `now()` |
| `categories` | `id` | `bigint` | NOT NULL; GENERATED ALWAYS identity; primary key |
| `categories` | `name` | `text` | NOT NULL; unique |
| `categories` | `created_at` | `timestamptz` | NOT NULL; default `now()` |
| `resources` | `id` | `bigint` | NOT NULL; GENERATED ALWAYS identity; primary key |
| `resources` | `title` | `text` | NOT NULL; no default |
| `resources` | `description` | `text` | nullable; no default |
| `resources` | `category_id` | `bigint` | nullable; no default |
| `resources` | `owner_id` | `uuid` | NOT NULL; no default |
| `resources` | `resource_type` | `text` | NOT NULL; default `'Other'` |
| `resources` | `availability_status` | `text` | NOT NULL; default `'available'` |
| `resources` | `created_at` | `timestamptz` | NOT NULL; default `now()` |
| `borrow_requests` | `id` | `bigint` | NOT NULL; GENERATED ALWAYS identity; primary key |
| `borrow_requests` | `resource_id` | `bigint` | NOT NULL; no default |
| `borrow_requests` | `borrower_id` | `uuid` | NOT NULL; no default |
| `borrow_requests` | `status` | `text` | NOT NULL; default `'pending'` |
| `borrow_requests` | `requested_at` | `timestamptz` | NOT NULL; default `now()` |
| `borrow_requests` | `due_at` | `timestamptz` | nullable; no default |
| `borrow_requests` | `returned_at` | `timestamptz` | nullable; no default |

The same inspection confirmed primary/unique keys and foreign-key delete behavior: `profiles.id` → `auth.users.id` cascades; `resources.category_id` → `categories.id`, `resources.owner_id` → `profiles.id`, `borrow_requests.resource_id` → `resources.id`, and `borrow_requests.borrower_id` → `profiles.id` all use PostgreSQL's default `NO ACTION` delete behavior. Thus resource deletion is blocked while a borrowing request references it; no automatic request cleanup should be assumed. Category deletion is blocked while resources reference it. The only non-primary unique indexes are `categories_name_key`, `profiles_student_id_key`, and the partial `borrow_requests.one_active_approval_per_resource` on `resource_id` where `status = 'approved'`. The latter prevents two approved requests for one resource, but does not prevent concurrent duplicate pending requests or duplicate requests by one borrower.

RLS is enabled and not forced on all four tables: `profiles`, `categories`, `resources`, and `borrow_requests`. Read-only metadata confirms a public `auth.users` AFTER INSERT trigger named `on_auth_user_created` invoking `public.handle_new_user()`. The function is `SECURITY DEFINER` with an empty `search_path`; metadata inspection confirmed it inserts a `public.profiles` row using the Auth user ID, `raw_user_meta_data.full_name` (with a coalesce fallback), and Auth email. The trigger does not populate `student_id`. There is no INSERT policy for `profiles`; profile creation therefore depends on this trigger, not a direct authenticated profile INSERT. The browser registration form now sends the verified `full_name` metadata. Live signup and trigger execution have not yet been tested.

The grants snapshot confirms `authenticated` has SELECT/INSERT/UPDATE/DELETE table grants for `profiles`, `categories`, and `resources`, and SELECT/INSERT/DELETE (but no UPDATE) for `borrow_requests`. The `anon` role also has broad table grants, but RLS is enabled and no anon policies were found for these tables. Grants alone do not make those anon operations authorized. The status constraint and a unique index do not grant authorization. No `borrow_requests` UPDATE policy exists. No production grants or policies were changed.

## Inspection result

The repository currently contains no first-party SQL schema, migration, or database definition files. Read-only Supabase metadata queries were available for CampusShare project `dkyfkdmlkghucyepxbbh`; policy and grant findings below were queried on 2026-11-01. No table row data was queried, and no production changes were made.

The project owner has supplied these key and relationship findings from read-only schema queries. They are recorded as confirmed project facts; no row data was supplied:

| Constraint | Referencing column | Referenced column |
| --- | --- | --- |
| `borrow_requests_borrower_id_fkey` | `borrow_requests.borrower_id` | `profiles.id` |
| `borrow_requests_resource_id_fkey` | `borrow_requests.resource_id` | `resources.id` |
| `resources_category_id_fkey` | `resources.category_id` | `categories.id` |
| `resources_owner_id_fkey` | `resources.owner_id` | `profiles.id` |

The project owner also confirmed that `profiles.id` is a primary key and references `auth.users(id)` with `ON DELETE CASCADE`. Therefore the profile key is linked to the Auth user ID. Profile creation/provisioning behavior and the remaining table columns are still unknown.

## Confirmed check constraints

| Table | Constraint | Verified definition / visible fragment | Scope |
| --- | --- | --- | --- |
| `resources` | `resources_availability_status_check` | `CHECK (availability_status = ANY (ARRAY['available'::text, 'unavailable'::text]))` | The allowed `availability_status` values are `available` and `unavailable`. |
| `borrow_requests` | `borrow_requests_check` | `CHECK ((due_at IS NULL) OR (due_at >= requested_at))` | A non-null `due_at` must be at least `requested_at`. |
| `borrow_requests` | `borrow_requests_check1` | `CHECK ((returned_at IS NULL) OR (returned_at >= requested_at))` | A non-null `returned_at` must be at least `requested_at`; no comparison to `due_at` is established. |
| `borrow_requests` | `borrow_requests_status_check` | `CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'returned'::text]))` | Complete allowed value list confirmed: `pending`, `approved`, `rejected`, `returned`. This is a value constraint only; it does not authorize transitions. |

These checks do not establish defaults, nullability of other columns, or allowed status transitions. The complete status value list is confirmed, including `returned`, but the constraint does not specify which actors may change a status or which transitions are permitted.

The project owner described the intended meanings as `pending` (submitted), `approved` (approved), `rejected` (rejected), and `returned` (resource returned). This documents status semantics only; it does not define a permitted transition graph.

## Preliminary RLS findings

The project owner reports ten policies across `borrow_requests`, `categories`, `profiles`, and `resources`. All listed policies apply to the `authenticated` role. The expressions below are transcribed from the supplied SQL Editor findings; borrowing-request, resource, and category policy metadata was subsequently checked through read-only queries. The findings remain preliminary, not a complete security audit; RLS/grants for `profiles`, policy mode, and other security mechanisms still need confirmation.

| Table | Policy | Command | Role | `USING` | `WITH CHECK` |
| --- | --- | --- | --- | --- | --- |
| `borrow_requests` | `Create own borrow requests` | INSERT | `authenticated` | Not applicable | `(SELECT auth.uid()) = borrower_id` |
| `borrow_requests` | `Owners read requests for their resources` | SELECT | `authenticated` | `EXISTS (SELECT 1 FROM resources WHERE resources.id = borrow_requests.resource_id AND resources.owner_id = (SELECT auth.uid()))` | Not applicable |
| `borrow_requests` | `Read own borrow requests` | SELECT | `authenticated` | `(SELECT auth.uid()) = borrower_id` | Not applicable |
| `categories` | `Read categories` | SELECT | `authenticated` | `true` | Not applicable |
| `profiles` | `Read own profile` | SELECT | `authenticated` | `(SELECT auth.uid()) = id` | Not applicable |
| `profiles` | `Update own profile` | UPDATE | `authenticated` | `(SELECT auth.uid()) = id` | `(SELECT auth.uid()) = id` |
| `resources` | `Add own resources` | INSERT | `authenticated` | Not applicable | `(SELECT auth.uid()) = owner_id` |
| `resources` | `Delete own resources` | DELETE | `authenticated` | `(SELECT auth.uid()) = owner_id` | Not applicable |
| `resources` | `Read resources` | SELECT | `authenticated` | `true` | Not applicable |
| `resources` | `Update own resources` | UPDATE | `authenticated` | `(SELECT auth.uid()) = owner_id` | `(SELECT auth.uid()) = owner_id` |

The complete owner-read expression and all four `resources` policy expressions were read from `pg_policies` in read-only queries on 2026-11-01. The resource UPDATE check is confirmed as `(SELECT auth.uid()) = owner_id`. Do not treat policy names as proof beyond the expressions listed here.

The `true` conditions apply to the named SELECT policies for `authenticated`; they do not establish `anon` access. The C++ categories route now requires an access token verified by Supabase Auth and forwards it to PostgREST. This behavior has only been tested with local mocks, not production.

Read-only metadata queries against project `dkyfkdmlkghucyepxbbh` on 2026-11-01 confirmed `borrow_requests`, `resources`, and `categories` have RLS enabled and not forced. For `borrow_requests`, `authenticated` has `SELECT`, `INSERT`, and `DELETE` table grants, but no `UPDATE` grant; `pg_policies` returned no UPDATE or DELETE policy. `anon` has table grants but no listed policy; RLS denies row access without a matching policy. Therefore only authenticated borrower/owner reads and borrower inserts are supported; request deletion and all updates remain unavailable. For `resources`, both `anon` and `authenticated` have SELECT/INSERT/UPDATE/DELETE grants; the four authenticated policies govern those operations, including owner-scoped UPDATE `USING` and `WITH CHECK`. No anon policy is listed, so anon table grants do not permit access through RLS. For `categories`, both roles have SELECT/INSERT/UPDATE/DELETE grants, but the only listed policy is authenticated SELECT with `USING true`; no write policy is present, so do not expose category mutations, and anon has no matching policy. `service_role` has UPDATE grants, but application code must not use that privileged role to bypass RLS. No production policy or grant was changed.

## Authorization and API implementation status

Protected handlers call Supabase Auth `GET /auth/v1/user` with the bearer token and public API key. Only the returned Auth user ID is used as identity; the same bearer token is forwarded to PostgREST so the existing RLS rules apply. Failure to verify fails closed. Local tests mock this Auth endpoint and do not prove live authentication. No service-role/secret key is used. Client-supplied `owner_id` and `borrower_id` are rejected.

| API operation | Implementation and data/policy mapping | Remaining gates / limits |
| --- | --- | --- |
| `GET /api/categories` | Implemented; authenticated caller; categories are passed through without guessing display columns. | Authenticated SELECT grant and RLS policy confirmed; live API read remains untested. |
| `GET /api/resources`, `GET /api/resources/{id}` | Implemented with explicit projection `id,title,description,category_id,owner_id,resource_type,availability_status,created_at`; authenticated SELECT policy reports `USING true`. Frontend searches titles/descriptions and filters by category locally. | No server-side search/filter params; live API visibility is untested. |
| `POST /api/resources` | Implemented; accepts title, description, category_id, resource_type, availability_status; derives owner_id from verified Auth identity; rejects supplied IDs; availability restricted to `available` or `unavailable`. Relies on verified INSERT `WITH CHECK auth.uid() = owner_id`. | Table grant and policy confirmed; remaining required fields/defaults, profile provisioning, and production Data API behavior are unverified. |
| `DELETE /api/resources/{id}` | Implemented; verifies the resource owner through authenticated SELECT before issuing DELETE, then relies on verified DELETE `USING auth.uid() = owner_id`; bearer token is forwarded. | Table grant and policy confirmed; live RLS behavior is untested; linked-request foreign-key behavior is not confirmed. |
| `PATCH /api/resources/{id}` | Implemented for `title`, `description`, `category_id`, `resource_type`, and `availability_status`; verifies owner before update, disallows changes to `owner_id`, `id`, and `created_at`, and validates availability. Relies on verified UPDATE `USING` and `WITH CHECK auth.uid() = owner_id`, plus the SELECT policy required for UPDATE. | Table grant and policy confirmed; remaining column behavior and live Data API operation are untested. |
| `GET /api/borrow-requests` | Implemented with no client-selected identity filter; forwards the verified bearer and lets RLS return only rows allowed by the confirmed borrower-owned SELECT policy or owner-read `EXISTS` policy. | Table grant and both policies are confirmed; live API behavior remains untested. |
| `POST /api/borrow-requests` | Implemented; derives `borrower_id`, server-generates `requested_at`, initializes `returned_at` to null, sets `pending`, accepts optional nullable `due_at`, and checks UTC value >= `requested_at`. It verifies the resource is visible, available, and not owned by the caller, and checks the caller's own rows for an existing `pending`/`approved` request. Client-supplied identity/status/date lifecycle fields are rejected. Relies on verified INSERT `WITH CHECK auth.uid() = borrower_id` and caller SELECT policy. | Checks are preflight reads, not an atomic global conflict guarantee. RLS hides other borrowers' requests, and no uniqueness constraint/locking design is confirmed. Other required fields/defaults, profile provisioning, and live Data API behavior remain unverified. |
| Borrow request approval/rejection/return or other status changes | **Not implemented.** | `authenticated` lacks UPDATE grant and no UPDATE policy exists. Do not enable without a separately reviewed authorization design and approved policy/grant change. |

The frontend now supports resource create/edit/delete, category selection, detail viewing, search/category filtering, request creation, and borrower/owner request reading. It displays status values returned by RLS. There are no approve/reject/return actions because current production permissions prohibit request updates.

For resource and request inserts, the verified `profiles.id` → `auth.users(id)` relationship establishes the identity mapping. The referenced profile row must still exist, and its provisioning mechanism and remaining required fields are unknown. The handlers are implemented locally, but a real operation may be rejected by a missing profile, grant, required column, or RLS rule. No live auth or integration test has run.

### Remaining blockers before claiming live integration

- Authorization design and permitted transitions for any future borrow-request UPDATE. Current `authenticated` grants/policies do not allow it.
- Remaining required columns, nullability/defaults, and live Data API behavior; metadata confirms grants and RLS state for categories, resources, and borrow_requests.
- Profile provisioning behavior so an Auth user has the referenced `profiles` row.
- Run live Auth/API tests against an approved test account/environment. Do not send tokens or secret keys in chat.

### Implemented code surface and test coverage

- `BACKEND/main.cpp`: verifies via Supabase Auth `/auth/v1/user`, derives caller ID from the returned user, forwards the bearer to PostgREST, and has no service-role path.
- `BACKEND/main.cpp`: implements categories, resource list/detail/create/update/delete, policy-filtered borrower/owner request read, and borrower request creation. Request status-changing routes are absent.
- `BACKEND/tests/test_api.py`: local mock tests cover absent/invalid/valid tokens, two identities, API-key/token forwarding, resource ownership checks, self/unavailable/duplicate borrowing rejection, validation, denied request-status updates, upstream errors, and CORS. Mock tests do not validate live signing configuration or RLS behavior.
- Add integration checks only against an approved non-production Supabase project with separate owner, borrower, and unrelated test users. Verify RLS denials as well as allowed reads/writes. Local mocks can test forwarding and request construction, but cannot prove production RLS behavior.

Search and category filtering are implemented in the frontend using confirmed `title`, `description`, and `category_id` fields; server-side query filters are not added. Approval, rejection, return, and any borrow-request status mutation are excluded because `authenticated` has no UPDATE grant or UPDATE policy; the confirmed status constraint does not authorize transitions. Duplicate-request prechecks only see rows allowed to the caller by RLS and cannot guarantee no concurrent/global conflict without database-level support.

## API mapping based on confirmed relationships

| API data need | Verified relationship available | Still needed before implementation |
| --- | --- | --- |
| Categories for a resource form or filter | `resources.category_id` references `categories.id`; known columns are `id`, `name`, `created_at` | Ordering behavior and live authenticated read still need verification |
| Resource list/details | A resource can reference a category and an owner profile through the two verified `resources` foreign keys | Resource/profile fields to expose, nullability, visibility rules, search/filter/order fields, and safe join/projection rules |
| Borrowing requests | A request references a borrower profile and a resource; the complete status value constraint and borrower-owned create/read policies are known | Remaining columns/defaults/grants for production readiness; any future owner-side workflow authorization |

Implemented database-backed routes use the projections and mappings above. No join to profiles is performed; the frontend maps categories to resources by the verified ID fields. Supabase Auth sessions supply bearer tokens to the existing routes. No live sign-in, RLS, or Data API operation has been tested.

## Preferred schema-only export

If this repository has migrations, provide every ordered file under `supabase/migrations/` and any schema-definition files under `supabase/schemas/`. Include relevant migration files even if they only create functions, triggers, enums, policies, or grants. Do not include seed files or table rows.

If migrations are unavailable, from the linked project run:

```sh
supabase db dump --linked -f supabase/schema-only.sql
```

This exports schema DDL without table data and does not apply changes to the live database. Keep ACL statements: do not add `--no-acl` or `--no-privileges`, because grants are needed to understand API access. Review the export before sharing and remove connection strings or other credentials if any appear. Supabase CLI dump behavior and scope are documented in the [CLI reference](https://supabase.com/docs/reference/cli/supabase-db-dump).

The default dump excludes Supabase-managed schemas such as `auth` and `storage`. If CampusShare customizes those schemas, separately provide only the relevant migration or schema-only DDL for its auth-user triggers/functions and storage policies/references; never include `auth.users` records. See the [Supabase migration guide](https://supabase.com/docs/guides/local-development/overview).

## Required schema details

The migration files or export should make these details reviewable:

- Tables and columns, including types, nullability, defaults, generated/identity behavior, and comments where they describe intent.
- Primary keys, unique constraints, foreign keys, delete/update actions, check constraints, indexes, enums, domains, and composite relationships.
- Any additional resource/category and resource-owner/profile details beyond the confirmed foreign keys above, including column definitions and `ON DELETE`/`ON UPDATE` behavior.
- Profile provisioning behavior and any trigger/function that creates or updates a profile; the `profiles.id` primary-key reference to `auth.users(id)` with `ON DELETE CASCADE` is confirmed.
- Borrowing/request columns, status type or check constraint, permitted transitions, and transition logic.
- `GRANT`/`REVOKE`, default privileges, RLS enabled/forced state, and each policy's command, target roles, `USING`, and `WITH CHECK` expressions.
- Relevant views and their security mode; functions and triggers that affect authorization or data lifecycle.
- Storage buckets only if the app uses them, with object policies and the schema's references to stored paths/IDs.

Do not provide row data, user records, passwords, access/refresh tokens, database URLs, API keys, or service-role/secret keys. A schema-only artifact is enough; if it contains comments or function bodies with secrets, redact those before sharing while retaining the access-control logic.

## Authentication contract still needed

Please also state the intended sign-in providers, whether email confirmation is required, password reset behavior, signup policy, callback URLs, and which operations require an authenticated user. Describe the intended ownership and administrative roles and how a profile is created. Do not share credentials or tokens. The browser should use Supabase Auth and send its current access token to protected backend endpoints; the C++ service must verify the token and derive the user identity from verified claims before enforcing authorization. Details are in [Supabase Auth sessions](https://supabase.com/docs/guides/auth/sessions) and [JWT verification](https://supabase.com/docs/guides/auth/jwts).
