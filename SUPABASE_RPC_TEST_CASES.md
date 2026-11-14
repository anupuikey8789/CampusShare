# CampusShare RPC test cases

Local mock tests exercise HTTP contracts only. They do not validate JWT cryptography independently of Supabase Auth, database function bodies, RLS, grants, row locks, or production/staging state.

## Local automated cases

| Case | Expected result |
|---|---|
| RPC flag false | Valid authenticated request returns 503 `borrow_requests_pending`; no resource/request PostgREST read or write occurs. |
| Health feature flags | Public health returns configured RPC flag booleans; this does not prove the database functions are installed. |
| Create RPC valid token | `POST /rest/v1/rpc/create_borrow_request`, API key and user Bearer token separate, parameters contain only `p_resource_id` and `p_due_at`; API returns 201 array. |
| Create RPC missing/invalid token | 401; RPC is not called. |
| RPC failure/unique conflict | Sanitized 409; no direct POST fallback and no raw SQL message in response. |
| RPC error for self/unavailable/duplicate request | Sanitized 409 if the function maps to the known error contract. |
| RPC malformed success JSON/empty or wrong row count | 502 invalid upstream response. |
| Atomic resource edit valid token | `POST /rest/v1/rpc/update_resource_atomic` with `p_resource_id` and one `p_changes` object; no direct owner pre-read or PATCH. API returns 200 array. |
| Metadata-only, availability-only, combined edits | Mocked RPC receives the exact supplied subset and returns one row. |
| Explicit nulls | `description: null` and `category_id: null` are forwarded as null; omitted fields stay omitted. |
| Missing token | Atomic PATCH returns 401 before any RPC call. |
| Anonymous Auth identity | Mock Auth resolves an ID, mocked RPC returns 28000, API returns sanitized 401, with no direct PATCH. This does not execute or validate the SQL claim check. |
| Resource update from non-owner | Mock DB returns 403/42501; response is sanitized and no direct PATCH occurs. |
| Invalid ID, unsupported key, empty object, invalid title/type/status | 400 before RPC; no update RPC call. |
| Oversized update | More than 16 KiB body returns 413 before RPC. |
| Missing resource / invalid category FK | Mock P0002 maps to 404; mocked 23503 maps to sanitized 400. |
| Invalid availability value | 400 before RPC call. |
| Approved request prevents availability=available | Mock SQL conflict becomes 409; no raw message exposed. |
| Atomic resource RPC timeout | Curl timeout becomes 502; no direct PATCH fallback. |
| Status update path | Current route is not registered; response is 404 and no status RPC is called. |

Run: `python BACKEND/tests/test_api.py BACKEND/build-msvc/campusshare_backend.exe`. These are local mock transport tests only; they do not validate JWT cryptography, deployed SQL, RLS, grants, row locks, or live Supabase behavior.

## Required live staging cases

Use separate A (resource owner), B (borrower), and C (unrelated student) accounts. Use their own browser-managed access tokens. Do not use a service-role key.

1. Create-request RPC: valid B request for A's available resource; self-borrow; unavailable/missing resource; forged borrower ID in unsupported input; duplicate pending/approved request; invalid past `due_at`; concurrent duplicate submissions; simultaneous create and owner availability update.
2. Atomic update RPC: A metadata-only, availability-only, and combined edits; B and C attempting A's resource; forged owner ID/unsupported fields; invalid availability; invalid category FK; making an approved resource available; simultaneous update and approval/return.
3. Verify response row shape and actual SQLSTATE/HTTP mapping for each exception. Confirm Postgres timestamps, row locks, and committed resource/request consistency.
4. Verify function EXECUTE grants and direct table grants separately. Confirm no anonymous/PUBLIC/service-role execution and no service-role key in the app.
5. Status functions, only after ACL resolution: owner A approve/reject/return; B attempting approval/rejection/return; C attempts; wrong/repeated transition; concurrent approvals; return/resource availability transaction consistency.
6. Record expected result, actual result, pass/fail, account role, and sanitized request ID. Do not record tokens or personal row data.
