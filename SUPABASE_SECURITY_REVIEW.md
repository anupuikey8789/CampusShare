# CampusShare Supabase Security Review

**Scope:** static review of Task 1's five deliverables and local API payloads in the canonical checkout. It relies on the read-only snapshot dated 2026-11-10 for project dkyfkdmlkghucyepxbbh. This review made no production SQL calls, changed no permissions, and ran no database tests.

## Confirmed findings

### Borrowing INSERT policy — P0
The recorded policy checks only borrower_id equals auth.uid(). This blocks borrower ID spoofing, but direct authenticated PostgREST can attempt self-borrow, unavailable resources, non-pending initial statuses, and active duplicates. Backend validation cannot secure direct table access. A stricter WITH CHECK can block these cases, but a policy subquery is not a row lock, so it cannot prevent a race with an availability update.

### Existing status functions — P0
The captured exact definitions show three public SECURITY DEFINER functions owned by postgres, with empty search_path and explicit schema-qualified table references. Their ACL grants EXECUTE to PUBLIC, anon, authenticated, and service_role.

- approve_borrow_request(request_id,due_at): requires auth.uid; locks request and resource; verifies resource owner, pending status, non-self borrower, and available resource; sets approved/due_at and resource unavailable.
- reject_borrow_request(request_id): requires auth.uid; locks request; verifies owner and pending; sets rejected and leaves resource availability unchanged.
- return_borrowed_resource(request_id): requires auth.uid; locks request and resource; verifies owner and approved; sets returned_at/status and resource available. Return is resource-owner-confirmed, not borrower-confirmed.

Authenticated execution is justified for these specific owner-checked workflow functions if owner approval/rejection and owner-confirmed return are intended. Keep access explicit for authenticated; revoke PUBLIC, anon, and service_role. Do not grant table UPDATE. Confirm the return actor before applying. The partial unique approved index plus approval function's resource lock protects concurrent approvals. Function calls update request/resource in one transaction. Normalize not-found/unauthorized errors before external use to reduce request-ID probing.

### Profile trigger
The captured function is the AFTER INSERT Auth trigger, SECURITY DEFINER, postgres-owned, empty search_path, and writes the matching Auth UUID/email plus metadata full_name to profiles. It accepts an empty name. EXECUTE is granted through PUBLIC and directly to API roles. Revoke direct API execution, preserve the existing trigger, and verify signup/profile creation in staging. Do not replace the function or trigger. No live signup test was done.

### Race and availability consistency — P0
The previous correction's EXISTS availability check is not atomic. Current C++ code checks availability, then makes a separate PostgREST INSERT; availability can change between those requests. The UI also lets owners PATCH availability directly while an approved request exists, potentially showing an active loan as available. A secure final cutover needs a transaction-safe request RPC that locks the resource, plus an owner availability RPC that refuses available while an approved request exists. Then revoke direct request INSERT and availability UPDATE. This requires a coordinated backend release; the current app must not be left with those grants revoked before it calls the RPCs.

### App permissions
Current app needs categories SELECT; resources SELECT/INSERT/UPDATE/DELETE; borrow_requests SELECT/INSERT; no direct profiles access. Resource create/update fields allow column grants excluding id, owner_id, created_at from updates. Request POST sends resource_id, verified borrower_id, requested_at, status=pending, returned_at=NULL and optional due_at. It is not atomic with the prior availability/duplicate checks. Preserve direct request INSERT and availability UPDATE only during the transition; remove them after compatible backend deployment.

## Reviewed design
Static request policy checks borrower identity, pending status, returned_at NULL, non-self, available resource, and no own pending/approved request. A unique partial index on (borrower_id,resource_id) WHERE status=pending closes same-borrower concurrent duplicates. Different borrowers may have pending requests; existing approved-only unique index plus row lock permits at most one approval. For final race safety, create_borrow_request derives borrower_id from auth.uid, stamps server time/status, locks and validates resource, checks active duplicates, and inserts atomically. set_resource_availability locks the owned resource and refuses available while an approved request exists. Both are SECURITY DEFINER, fixed empty search_path, fully qualified, and executable only by authenticated. Revoke direct table writes after backend cutover.

## Migration and rollback risks
Independent: narrow table grants, strengthen the INSERT policy, add indexes, and narrow definer ACLs while preserving authenticated access to the three status RPCs. These do not require app changes; the policy-only interval still has an availability race.
Coordinated: add the two RPCs, update backend calls, test, then revoke request INSERT and availability UPDATE. Do not apply final revokes before code deployment.
Revoke handle_new_user execute from API roles only after staging signup proves the trigger still fires. Existing trigger is retained. Apply grant/policy/function changes in a transaction; rollback before commit is automatic. Concurrent indexes are separate autocommit statements; inspect indisvalid on failure and remove only a newly created invalid index after approval. Never drop existing policies, functions, or one_active_approval_per_resource. Rollback to direct writes reopens races and requires explicit approval. Never restore anon/PUBLIC execution.

**Unresolved:** explicit product confirmation for owner-confirmed return, staging verification of trigger and RPC policy behavior, concurrent two-user tests, compatible backend RPC release, and a fresh production audit. No live tests or SQL were run here.
