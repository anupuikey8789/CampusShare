# CampusShare Status RPC Staging Test Plan

## Safety and setup

This is a test plan only. No test below has been run. Use a separate disposable Supabase staging project, after reviewing its project reference. Do not use production credentials or a service-role key for application calls. Use the two normal student accounts as the minimum: **A**, resource owner, and **B**, borrower. Create disposable resources and request rows through the approved application/RPC flow. To test competing borrower requests for one resource, a third normal student account (**C**) is needed because A owns the resource and B must remain a distinct borrower.

Keep both RPC feature flags at `false` until the exact installed signatures, result types, owners, function settings, ACLs, and RLS/grants have been confirmed. These status routes are not implemented in the backend; direct PostgREST RPC calls from a secure staging test client may be used only after staging owner approval. Use each student's own Auth session. Never put tokens in test records or logs.

Before testing, capture the read-only results from `SUPABASE_STATUS_RPC_STAGING_INSPECTION.sql`. Confirm seed rows, initial statuses, and resource availability in staging. Record sanitized IDs, expected and actual results, and timestamps. Do not store names, emails, JWTs, or secrets in the report.

## Authorization and state-transition tests

| Test | Setup/action | Expected outcome |
|---|---|---|
| Owner approval | A owns an available resource with B's pending request; A invokes approval once. | One request changes from pending to approved, due date follows the function contract, and the resource becomes unavailable atomically. |
| Non-owner approval denial | C (or B when not the resource owner) invokes approval for the request. | Denied; request and resource remain unchanged. |
| Borrower tries to approve own request | B invokes approval for B's request on A's resource. | Denied; borrower identity does not grant owner authority. |
| Owner rejection | A rejects a pending request. | One transition pending → rejected; resource availability remains as specified by the verified function contract (audit summary says unchanged). |
| Borrower tries to reject own request | B invokes rejection for B's request on A's resource. | Denied; request remains pending. |
| Owner-confirmed return | A returns a request in approved state. | One transition approved → returned, `returned_at` is set by the database, and the resource becomes available atomically. |
| Borrower tries to confirm return | B invokes return for B's request. | Denied; request stays approved and resource unavailable. |
| Repeated approval | A invokes approval again after the request is approved. | Denied as an invalid/repeated transition; no timestamps or resource values are changed again. |
| Repeated rejection | A invokes rejection after the request is rejected. | Denied as an invalid/repeated transition; state is unchanged. |
| Repeated return | A invokes return after the request is returned. | Denied as an invalid/repeated transition; return timestamp/resource state do not change again. |
| Unauthenticated execution | Call each status RPC without an access token. | Rejected before any state change. Confirm no `PUBLIC`/`anon` EXECUTE access in the inspection results. |
| Anonymous Auth execution | Call each RPC with a valid Supabase anonymous Auth session, if anonymous sign-in is enabled. | Rejected if product policy is permanent students only. `authenticated` role membership alone is insufficient; inspect JWT claims and function checks. |

## Concurrency tests

Run concurrently with separate sessions and record which call acquires the lock first. Expected results depend on the verified SQL body, but every interleaving must preserve the listed invariants.

| Test | Concurrent actions | Required invariant/outcome |
|---|---|---|
| Two approvals, same request | Two A sessions approve the same pending request concurrently. | At most one call succeeds; exactly one pending → approved transition and one set of side effects. The other observes a denied/repeated transition or a documented unique conflict. |
| Competing requests, same resource | A receives pending requests from B and C for the same available resource; two A sessions approve them concurrently. | At most one request becomes approved; the resource ends unavailable. The other request remains pending or receives the verified denial/conflict. |
| Availability edit races with approval | A concurrently sets the resource available/unavailable through the atomic resource update while A approves a pending request for that resource. | No final state may have an approved request while the resource is available. The function order must serialize or reject one operation. |
| Request creation races with approval | B (and optionally C) creates a request while A approves an existing pending request for the same resource. | Creation either commits before approval or is rejected after the resource becomes unavailable; no request may cause an approved/available final state. Multiple pending requests may be allowed unless the verified uniqueness contract forbids them. |
| Duplicate request race | Two B sessions concurrently create a pending request for the same resource. | If the approved staging unique pending index is installed, at most one pending pair commits. Otherwise record the race as a blocking database gap; application prechecks are not sufficient. |
| Reject races with approval | A concurrently rejects and approves the same pending request from two sessions. | Exactly one transition wins; final status cannot be both approved and rejected. Resource availability matches the winning transition. |
| Return races with resource edit | A concurrently confirms return and edits availability/metadata on the same resource. | No approved request may coexist with available status after both calls finish; lock ordering must not deadlock or leave partial changes. |

For each concurrency test, repeat enough times to exercise both winners. Capture deadlocks/serialization failures distinctly. A deadlock or retryable error is not a passing outcome unless the client contract safely handles it and database state remains consistent.

## Profile provisioning test

1. With the proposed routine ACL changes applied only to staging, sign up a disposable Auth user through the official frontend/Auth flow.
2. Confirm signup succeeds and exactly one `profiles` row is created with `profiles.id` equal to the new Auth UUID.
3. Confirm expected full-name/email fields use the existing trigger behavior and no profile is created for a different UUID.
4. Sign out and verify ordinary profile RLS remains unchanged.

Expected result: automatic profile creation still fires without granting API callers direct invocation of `handle_new_user()`. If signup fails, stop; do not restore broad execution as a workaround before inspecting trigger ownership and ACL behavior.

## Evidence/reporting template

For every case, record: test ID, staging project reference (not URL credentials), sanitized row IDs, accounts/roles (A/B/C), expected result, actual result, PASS/FAIL/BLOCKED, observed SQLSTATE/HTTP status, final request status, final availability, and whether any deadlock occurred. Do not record access tokens, passwords, emails, or private row contents.

No production database change is authorized by this plan. Production rollout requires a separate approval after staging evidence and backend routes are reviewed.
