# CampusShare RPC backend integration

## Scope and verification status

This document is based on local source and the read-only audit snapshot in `SUPABASE_DATABASE_AUDIT.md` dated 2026-11-10. No production SQL, RPC call, grant change, or policy change was performed. The four RPC planning inputs referenced in the previous task were absent from this checkout. `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` contains proposals, not proof of deployed staging or production functions.

## Authentication and transport

Every protected route first validates the incoming Bearer token through Supabase Auth `GET /auth/v1/user`. The backend takes the user UUID from the verified Auth response. Its shared Supabase HTTP client sends the configured publishable/anon key as `apikey` and the caller's token as `Authorization: Bearer ...`. `SupabaseClient::rpc` posts JSON to `/rest/v1/rpc/{function_name}` using that same request implementation. Existing connection/total timeouts are 5/15 seconds. Credentials and upstream response bodies are not logged.

The RPC bodies must derive actors using `auth.uid()`. No `owner_id`, `borrower_id`, or actor ID is accepted as RPC input. The frontend continues to use the current Supabase JS session and does not receive any service-role or secret key.

`SECURITY DEFINER` functions execute with the function owner's database privileges and can bypass RLS. Keep a fixed empty `search_path`, schema-qualify objects, check `auth.uid()` and ownership/state inside the function, and grant EXECUTE only to the role needed. Review against the [Supabase Database Functions security guidance](https://supabase.com/docs/guides/database/functions) before staging.

## Borrow-request creation contract

The existing local proposal in `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` defines:

```sql
public.create_borrow_request(p_resource_id bigint, p_due_at timestamptz DEFAULT NULL)
RETURNS SETOF public.borrow_requests
```

Proposed PostgREST request:

```json
{"p_resource_id":123,"p_due_at":null}
```

The function is intended to use `auth.uid()`, database `statement_timestamp()`, a resource row lock, ownership/self-borrow and availability checks, and an active-request check before inserting `pending`. Its proposed ACL is revoke EXECUTE from `PUBLIC`, `anon`, and `service_role`; grant EXECUTE to `authenticated`. Do not treat this as deployed. Stage and inspect its exact body, owner and `proacl` before enabling.

`RETURNS SETOF public.borrow_requests` is represented by PostgREST as a JSON array. The backend requires exactly one object and returns HTTP 201 with that row array. `SUPABASE_RPC_CREATE_BORROW_REQUEST` defaults false; while false, the endpoint returns HTTP 503 `borrow_requests_pending` before any PostgREST resource/request reads or writes. When true, it makes only the RPC request: on an error or timeout it does not issue a direct insert, because an RPC may have committed even if the response was lost. The public health response reports the configured RPC flags; a true flag is configuration information, not proof the RPC exists or passed staging verification.

## Atomic resource edit contract

`SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql` introduces a new, explicitly proposed function:

```sql
public.update_resource_atomic(p_resource_id bigint, p_changes jsonb)
RETURNS SETOF public.resources
```

The JSONB parameter is the whitelist-filtered partial payload from the existing `PATCH /api/resources/{id}`. Allowed fields are `title`, `description`, `category_id`, `resource_type`, and `availability_status`. Return is one resource row in a one-element array. The SQL locks and updates the row once, checks verified Auth identity/owner, enforces the verified availability values, and prevents an `available` result while an approved borrow request exists. Category existence is enforced by the existing FK. This function/signature is a design proposal, not an existing audited contract.

The proposed ACL is revoke EXECUTE from `PUBLIC`, `anon`, and `service_role`; grant to `authenticated`. The function owner needs the required resource table privileges; for a SECURITY DEFINER owner, review exact owner and BYPASSRLS implications in staging. The app flag defaults false. The existing frontend form and PATCH route remain unchanged; there is no split write. If RPC mode is enabled, it calls this function exclusively and never falls back to direct PATCH.

## Status operations

The audit snapshot recorded these existing function identity signatures and an observed ACL of EXECUTE for `PUBLIC`, `anon`, `authenticated`, and `service_role`:

- `public.approve_borrow_request(bigint, timestamptz)`
- `public.reject_borrow_request(bigint)`
- `public.return_borrowed_resource(bigint)`

The audit summary reports owner/pending checks and row locks; approval sets request approved and resource unavailable, rejection sets rejected, and return sets returned/returned_at and resource available. The resource owner is reported as the return actor. The local `SUPABASE_CORRECTION.sql` revokes EXECUTE from all four roles including `authenticated`; `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` instead revokes `PUBLIC`, `anon`, `service_role` and grants `authenticated`. This ACL conflict is unresolved for that audited project. The complete audited routine bodies and return types are not included in the current local deliverables.

Product decisions for this task state only the resource owner approves, rejects, and confirms return. Local API routes and frontend controls now exist behind `SUPABASE_RPC_BORROW_STATUS=false` by default. The separate staging migration proposes new status functions returning `SETOF public.borrow_requests`; this is not evidence of a function deployed in staging. Proposed routes return one row in an array and accept no client-supplied actor ID. Approve accepts optional `due_at`; reject and return accept `{}`. Obtain staging owner approval, inspect the complete installed function definitions and ACLs, and pass the two-user and concurrency checks before enabling the flag.

## Error mapping

The shared RPC mapper never returns a raw database message. It maps verified/token authorization failures to 401/403; `P0002`/missing records to 404; unique conflicts, own-resource/unavailable/duplicate/approved-loan conflicts to 409; known invalid-value SQLSTATEs to 400; unknown rejected database calls to 422; unavailable/missing RPC contracts and malformed success bodies to 502. Existing curl connect/total timeouts are 5/15 seconds and map to 502. Staging must verify actual PostgREST SQLSTATE/HTTP mappings for the installed functions.

## Feature flags

| Variable | Default | Meaning |
|---|---:|---|
| `SUPABASE_RPC_CREATE_BORROW_REQUEST` | `false` | False: disable request creation with HTTP 503. True: use `create_borrow_request` exclusively; no direct insert fallback. |
| `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE` | `false` | Use `update_resource_atomic`; otherwise retain the current single PostgREST PATCH. |
| `SUPABASE_RPC_BORROW_STATUS` | `false` | Use owner status RPCs; when false, actions return HTTP 503 with no database mutation. |

`SUPABASE_RPC_BORROW_STATUS=true` is rejected unless `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true`. Because the reviewed resource grant permits direct authenticated updates of `availability_status`, status operations must remain disabled until the owner applies and verifies `SUPABASE_STAGING_BORROWING_AVAILABILITY_CUTOVER.sql`. This removes the direct column privilege while retaining the reviewed metadata-only column grants. Enable only in staging after matching functions/ACLs, cutover permissions, two-user tests, and concurrency tests pass.
