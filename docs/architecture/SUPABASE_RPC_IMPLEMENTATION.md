# CampusShare Supabase RPC implementation

## Status and safety boundary

This document describes the local backend integration only. No production SQL was executed, no production grants or policies were changed, and no live RPC was tested. The SQL in `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` remains a proposal. Re-run the read-only audit and inspect exact staging definitions, grants, and return types before enabling RPC mode.

The C++ service continues to validate the current Supabase access token using Auth `GET /auth/v1/user`. It sends the user's token as `Authorization: Bearer …` and the configured publishable/anon key separately as `apikey`. Database functions must derive actor identity from `auth.uid()`. The application must never use or expose a service-role key.

The Auth user lookup alone does not distinguish permanent users from Supabase anonymous Auth users. The proposed atomic update SQL rejects a JWT with `is_anonymous=true` and fails closed if that claim is absent. Validate in staging that ordinary signed-in tokens include the expected claim before enabling the RPC. Supabase documents that anonymous Auth users use the `authenticated` Postgres role, so role membership alone is insufficient ([anonymous sign-ins](https://supabase.com/docs/guides/auth/auth-anonymous), [JWT claims](https://supabase.com/docs/guides/auth/jwt-fields)).

## Implemented transport and request creation

`SupabaseClient::rpc` posts JSON parameters to `/rest/v1/rpc/{function_name}` through the existing libcurl client. That client applies the existing connection and total timeouts, JSON headers, user Bearer token, and API key. The helper accepts only lowercase letters, digits, and underscores in an RPC name. It does not log request bodies, response bodies, or credentials.

`POST /api/borrow-requests` retains the existing public payload:

```json
{"resource_id":123,"due_at":null}
```

The existing frontend currently serializes resource IDs as strings, so the backend accepts either a string ID or an integral JSON number. RPC mode requires a positive bigint ID. The caller cannot supply `borrower_id`, `status`, or timestamps.

Set `SUPABASE_RPC_CREATE_BORROW_REQUEST=true` only in a staging environment after deploying and inspecting the matching function. The default is `false`, preserving the current direct PostgREST behavior for compatibility. When enabled, the backend calls `create_borrow_request` with `p_resource_id` and `p_due_at`; it does not perform availability/duplicate prechecks, and it never falls back to a direct insert if the RPC fails. A successful response is expected to be one JSON row in an array, matching the local reviewed proposal's `RETURNS SETOF public.borrow_requests`. This is a proposal contract, not a verified deployed function contract. An empty or malformed success body fails with 502.

`SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE` defaults to `false`. When enabled, `PATCH /api/resources/{id}` validates the same editable fields, skips the separate owner pre-read, and calls the proposed `update_resource_atomic(p_resource_id bigint,p_changes jsonb)`. The JSONB changes object contains only fields supplied in the existing PATCH payload. The proposed function returns `SETOF public.resources`, which PostgREST represents as a one-row array. This new local SQL proposal is not an existing verified database function and has not been applied. Do not enable the flag until the SQL contract is approved and verified in staging. RPC errors do not fall back to direct PATCH.

The PATCH contract accepts explicit JSON `null` for nullable `description` and `category_id`; omission means preserve the stored value. Other fields remain type-checked, and `owner_id` is not accepted. The backend caps the complete request body at 16 KiB, and the SQL proposal applies the same cap to the JSONB changes object. The verified schema snapshot does not document per-column text length constraints, so this implementation claims no title/description maximum. Confirm other database constraints in staging.

The current direct-write route remains available only while the flag is false. It is not safe against concurrent duplicates or availability races. Do not use this fallback after staging/production direct INSERT permissions are revoked.

## HTTP error behavior

RPC errors are converted to generic JSON errors; database messages and details are not returned. The helper maps unauthenticated, permission, missing-row, known conflict, and invalid-data cases to 401, 403, 404, 409, and 400 respectively. Unrecognized or unavailable RPC responses map to 422 or 502. Logs contain only transport and HTTP status diagnostics.

The proposed SQL currently raises default PL/pgSQL exceptions for several conditions. Staging must verify PostgREST's actual SQLSTATE/HTTP mapping. If a condition cannot be distinguished without parsing private database message text, revise the SQL proposal to assign stable SQLSTATEs before relying on a specific HTTP mapping.

## Not implemented / blocked

### Atomic resource edit (implemented locally; staging blocked)

The default `PATCH /api/resources/{id}` remains a single PostgREST row update, preserving current form behavior. A separate proposal, `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql`, defines a new `update_resource_atomic(bigint,jsonb)` signature because the existing deliverables contained no such function. Its C++ caller is behind the false-by-default flag. The proposal rejects anonymous Auth identities, locks the owned resource row, validates editable JSON fields and availability, relies on the verified category FK for category existence, prevents marking a resource available while an approved request exists, applies all fields in one UPDATE, and returns the row. It still needs SQL review and staging verification before the flag is enabled. The row lock protects the approved-request check only if status-changing SQL takes a compatible lock in the same transaction; exact status function bodies and lock order are unavailable locally, so verify this race in staging.

### Approval, rejection, and return

No status routes or frontend controls were added. The audit snapshot documents existing `approve_borrow_request(bigint,timestamptz)`, `reject_borrow_request(bigint)`, and `return_borrowed_resource(bigint)` functions and describes owner/status checks. However, their return types are not recorded in the available contract, and the ACL direction conflicts across deliverables: `SUPABASE_CORRECTION.sql` revokes authenticated execution, while `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` grants it. The Task 3 decision that only the resource owner confirms return is compatible with the audited function description, but this does not resolve the ACL conflict. Resolve the ACL proposal, inspect exact function definitions/return types in staging, and test both allowed and denied identities before adding routes.

### Availability RPC

The local reviewed SQL proposes `set_resource_availability(bigint,text) RETURNS SETOF public.resources`. The function covers availability alone and is not used by the combined edit form. The new atomic update proposal supersedes it for the existing combined PATCH when its flag is enabled.

## Existing contract retained

- `GET /api/borrow-requests`: authenticated; returns the RLS-filtered JSON array.
- `POST /api/borrow-requests`: authenticated; accepts `resource_id` and optional `due_at`; returns 201 with a one-row array.
- `PATCH /api/resources/{id}`: authenticated; retains the current atomic single-row PostgREST update and response array.
- No request status update or delete route is exposed.

All errors use `{ "error": { "code": "…", "message": "…" } }`. The current frontend request method is unchanged. No actor ID is sent by the browser.
