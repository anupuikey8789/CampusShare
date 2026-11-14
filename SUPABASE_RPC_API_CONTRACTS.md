# CampusShare API and RPC contracts

This is a local implementation contract. The SQL proposal is not deployed or production-approved. All protected routes require `Authorization: Bearer <current Supabase access token>`.

## Existing public API

Errors retain `{ "error": { "code": "...", "message": "..." } }`.

| Route | Input | RPC mode and response |
|---|---|---|
| `POST /api/borrow-requests` | `{ "resource_id": 123, "due_at": null }`; no actor, status, or timestamp fields allowed. The frontend sends a numeric bigint ID. | RPC flag off: return 503 `borrow_requests_pending` without PostgREST reads or writes. RPC flag on: call only `create_borrow_request`; return 201 with a one-row array. There is no direct-write fallback. |
| `PATCH /api/resources/{id}` | Non-empty JSON object with any subset of `title`, `description`, `category_id`, `resource_type`, `availability_status`. Unsupported keys rejected. Availability is only `available` or `unavailable`. | RPC flag off: one PostgREST PATCH. RPC flag on: `update_resource_atomic`; return 200 with a one-row array. Existing edit form remains a single operation. |

Success payloads keep the current JSON-array shape. RPC `RETURNS SETOF` row contracts below are proposals based on the checked-in SQL, not live staging verification.

## Borrow request RPC proposal

Exact local proposed SQL signature:

```sql
public.create_borrow_request(p_resource_id bigint, p_due_at timestamptz DEFAULT NULL)
RETURNS SETOF public.borrow_requests
```

Parameters: `p_resource_id` is a positive bigint, `p_due_at` is null or an ISO timestamp. The function derives borrower identity and status/timestamp; the caller supplies none of those. Proposed privilege: EXECUTE to `authenticated` only after revoking `PUBLIC`, `anon`, and `service_role`. Return: PostgREST one-row JSON array; backend requires one object. HTTP result: 201.

## Atomic resource update proposal

New proposed SQL signature, not found in the existing audit:

```sql
public.update_resource_atomic(p_resource_id bigint, p_changes jsonb)
RETURNS SETOF public.resources
```

`p_changes` is a non-empty object containing only `title`, `description`, `category_id`, `resource_type`, and/or `availability_status`. The request body is passed as the JSON object; `p_resource_id` is the positive bigint parsed from the route. The database must own all authorization and invariant checks and return one row. Proposed privilege: authenticated-only EXECUTE after revoking `PUBLIC`, `anon`, and `service_role`. HTTP result: 200. The corresponding SQL is in `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE_PROPOSAL.sql` and must be reviewed before use.

Omitted fields preserve stored values. Explicit `null` is accepted only for nullable `description` and `category_id` and clears that field. Null for other fields is invalid. The complete PATCH body is capped at 16 KiB by the backend; the proposal applies a 16 KiB cap to serialized `p_changes` too. No verified per-column text limits are available. The proposed function requires `is_anonymous=false` and fails closed when that claim is absent; the C++ Auth lookup does not independently distinguish anonymous users. Successful PostgREST output must be a one-row array, and the caller has no direct-PATCH fallback.

## Borrow-request status RPC proposals (staging only; disabled by default)

The migration proposal defines these new staging contracts; they are not verified as deployed anywhere:

| RPC signature | Input JSON | Intended action |
|---|---|---|
| `approve_borrow_request(bigint, timestamptz) RETURNS SETOF public.borrow_requests` | `{"p_request_id":123,"p_due_at":null}` | Resource owner approves a pending request and atomically marks the resource unavailable. A null due date preserves the request's current due date. |
| `reject_borrow_request(bigint) RETURNS SETOF public.borrow_requests` | `{"p_request_id":123}` | Resource owner rejects a pending request. |
| `return_borrowed_resource(bigint) RETURNS SETOF public.borrow_requests` | `{"p_request_id":123}` | Resource owner confirms return, sets the database return time, and makes the resource available. |

Proposed HTTP routes are `POST /api/borrow-requests/{id}/approve`, `/reject`, and `/return`. All require a verified Supabase access token. The backend sends the public API key separately and forwards the caller's JWT. It accepts no owner or borrower ID. Success returns HTTP 200 and exactly one row in a JSON array. Error SQLSTATEs are mapped to generic 401/403/404/409/400/422/502 responses without returning database details. Invalid request IDs or extra body fields are rejected before the RPC call.

The SQL proposal locks the resource row before the request row for each operation that touches both; approval also checks owner, pending status and availability before changing both rows in one transaction. Reject checks owner and pending status. Return checks owner and approved/unavailable state, records `statement_timestamp()`, and restores availability. These are proposed source properties only; SQL has not been run or concurrency-tested. `SUPABASE_RPC_BORROW_STATUS` defaults to `false`; when false each route returns 503. The frontend hides controls unless the backend health response says enabled. A true flag only reports local configuration; it does not attest that staging functions, grants, or policies were verified.

The migration grants EXECUTE only to `authenticated` after revoking it from `PUBLIC`, `anon`, `authenticated`, and `service_role`, and each proposed SECURITY DEFINER function checks `auth.uid()` and the `is_anonymous` claim. The function owner, definer security implications, exact function bodies, ACLs, and simultaneous-user behavior must be reviewed in staging before enabling. The known staging database has no direct `borrow_requests` UPDATE grant or policy; the backend has no direct-write fallback. The current authenticated resource UPDATE grant does include `availability_status`, which could bypass the atomic lock and leave a request/resource state inconsistent. Keep status RPC mode disabled until the owner applies and verifies the separate `SUPABASE_STAGING_BORROWING_AVAILABILITY_CUTOVER.sql` proposal to remove that direct column privilege. The backend also requires atomic resource-update mode before status RPC mode can be enabled.

## Error handling

RPC errors do not expose raw SQL messages/details. Expected categories: 400 invalid input; 401 missing/invalid identity; 403 denied owner/permission; 404 missing record; 409 duplicate/conflict/state transition; 422 other database rejection; 502 upstream timeout, unavailable/mismatched function, or malformed success response. Actual PostgREST behavior must be checked against staging functions before release.
