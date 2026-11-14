# CampusShare Supabase Test Plan

Use staging, disposable accounts A/B, controlled inboxes and test data. Never use service-role credentials. This audit ran no signup, mutation, or RPC; tests below are planned.

## Auth/profile
| Test | Expected |
|---|---|
| Register A with full_name | Existing confirmation setting applies; Auth UUID=profiles.id, name/email map |
| Blank name | UI rejects; current trigger accepts blank |
| confirm/login/logout/refresh | Matches Auth settings; restore/refresh works; logout clears session |
| Invalid/expired token | Backend 401, no privileged fallback |
| handle_new_user RPC after ACL correction | API execution denied; Auth signup trigger still works |

## Grants/RLS
| Test | Expected |
|---|---|
| anon table access | Denied after revoke; current grants broad but no anon policies |
| Auth category/resource reads | Allowed |
| A creates own resource | Allowed, owner_id=auth.uid |
| A spoofs owner or edits B resource | Denied |
| direct resource id/created_at update | Denied after column grants |
| invalid category FK / delete referenced resource | FK rejects; no orphan/cascade |
| borrower/owner request reads | Own requests or those for owned resources |
| unrelated user read | No private rows |

## Borrowing
| Test | Expected |
|---|---|
| B asks for available resource A owns | One pending row, borrower B |
| self/unavailable direct REST request | Current policy may allow; proposed policy denies |
| spoof borrower_id | Backend and RLS deny |
| insert approved/rejected/returned | Current policy lacks check; proposed pending-only denies |
| duplicate same-borrower request, sequential/concurrent | Backend check and proposed unique pending index reject duplicate |
| B and C concurrently request same resource | Both may be pending; only one approved |
| forged requested_at | Current table INSERT can set; future column grant/backend fix prevents |
| invalid resource/due date | FK/CHECK rejects |

## Status RPCs
Inspected, not called. Proposed correction disables them pending owner approval.
| Test | Expected |
|---|---|
| anon calls lifecycle RPC today | ACL allows attempt but body should reject; after revoke ACL denies |
| unrelated authenticated caller | Owner check denies today; after revoke all callers denied |
| owner approves pending/available | Current function sets approved/unavailable and locks request/resource |
| owner rejects pending | Rejected |
| owner returns approved | Current function returns/available; borrower cannot confirm |
| concurrent approvals | Resource lock serializes; unique approved index final guard |
| invalid due_at | Existing CHECK rejects |

Do not run lifecycle operations in production before actor rules are approved. No build or app test ran in this audit. For release separately run CMake/MSVC, backend mocks and frontend Node tests; mocks do not prove live Auth/RLS/grants. Re-run audit/advisors, rehearse in staging, test two users with their own JWTs, verify function ACL/index validity and negative cases, confirm CORS/Auth redirects, record sanitized expected/actual/pass-fail, and obtain explicit approval before SQL or production accounts/data.
