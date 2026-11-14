# CampusShare Task 9 — Frontend UI and student experience

## UI audit findings

- The app was a single page with browse/resource and request sections, but had no signed-in dashboard or quick navigation to personal listings and requests.
- Search and category filtering existed; availability filtering and a clear-filters action did not.
- Resource cards showed the core resource fields, but the details dialog had no context-sensitive actions and resource type was missing from cards.
- Empty results had one generic message. Loading and API errors used live-region text, but dashboard and per-list busy/empty states were not present.
- The borrowing area had two lists, but a static warning always claimed owner actions were unavailable. That conflicted with the existing backend feature-flag contract.
- The existing stylesheet is `FRONTEND/style.css` and is linked correctly. Its filters and cards were responsive; the additional availability filter needed a wider desktop grid and a mobile layout.
- The backend API does not provide a human-readable resource-owner profile. The UI therefore does not expose the owner UUID as a name.

## Improvements implemented

- Added a signed-in dashboard with counts for the current user's loaded listings, available owned listings, visible pending requests, and visible approved requests; added recent owned listings and quick actions.
- Dashboard text states that counts and recent items use data currently loaded by the backend, capped at 100 rows per list. It does not claim to show global database totals.
- Added a My Resources view over the existing resource list. It uses the authenticated caller's returned `owner_id` and keeps edit/delete controls limited to owned resources.
- Added availability filtering and Clear filters. Search, category filtering, sorting, and the new filters work together.
- Improved cards and details with category, resource type, availability, full description, owner-edit/delete actions, and a borrow action only when available and enabled. Self-borrow, unavailable resources, active requests, and disabled borrowing features suppress the action.
- Added separate My Borrow Requests and Requests Received navigation/sections. Approve, Reject, and Confirm Return are derived from request state and appear only for owner-visible requests when the backend status feature is enabled. The backend remains the authorization boundary.
- Kept resource creation/editing on the existing authenticated endpoints, added consistent form validation messages, preserves the form on failure, blocks repeated submissions, refreshes records after successful changes, and displays success/error feedback.
- Added accessible status/empty messaging, busy state for the resource list and dashboard stats, responsive dashboard/card/filter layouts, and a clean no-results state.
- Added a small pure UI model used by the page for filtering, dashboard summaries, and feature/ownership-gated actions. The Supabase session and existing backend API helper remain the only authentication/API path.

## Files changed

- `FRONTEND/index.html`
- `FRONTEND/style.css`
- `FRONTEND/app.js`
- `FRONTEND/ui-model.js` (new)
- `FRONTEND/tests/app.test.cjs` (new)
- `FRONTEND/tests/ui.test.cjs` (new)
- `README.md` (frontend test command)
- `BACKEND/README.md` (frontend test command)
- `CAMPUSSHARE_LOCAL_SETUP_GUIDE.md` (frontend test command)
- `CAMPUSSHARE_TASK_9_REPORT.md` (this report)

No backend code, API helper, Auth code, configuration, database, or SQL was changed for Task 9.

## Screens completed

- Signed-out landing and existing login/register dialog.
- Signed-in student dashboard.
- Browse Resources with title/description search, category, availability, and sort filters.
- My Resources mode with owned resource actions.
- Add/Edit Resource form and Resource Details dialog.
- My Borrow Requests and Requests Received.

## Tests and checks

- **Frontend syntax checks:** passed for `config.js`, `auth.js`, `api.js`, `ui-model.js`, `app.js`, and all three frontend test files.
- **Frontend mock suite:** 31 passed, 0 failed (`auth.test.cjs`, `app.test.cjs`, and `ui.test.cjs`). App tests cover sign-in/sign-out state, dashboard data/loading, browse/search/category/availability filters, add validation/create success and failure, edit/delete success and failure, borrower and owner request views/actions, feature flags on/off, refreshes, and empty/API-error states.
- **Static checks:** passed for stylesheet path, app element references, balanced CSS braces, and trailing whitespace.
- **Credential-pattern scan:** no credential-shaped strings were found in the modified frontend files.
- No backend mock test or C++ build was run for this task because no backend file changed.
- No browser-based live sign-in, live Supabase request, database operation, or live RLS test was run.

## Pending items and limits

- The APIs return at most 100 rows per list, so dashboard counts, recent listings, and client-side search/filtering describe only loaded rows. Server-side filtering and pagination are not part of the current contract.
- Human-readable owner profile data is not available from the existing API; only `owner_id` is returned. The UI does not guess a person's name.
- Borrow submission and owner status actions remain hidden unless `/api/health` reports those backend features enabled. Keep the corresponding RPC flags disabled until the staging RPC and availability-permission cutover are reviewed and verified. Do not enable a flag merely to preview a button.
- Actual database grants/RLS, resource deletion constraints, email confirmation, and status transitions remain unverified live.

## Manual review steps

Use only the staging configuration already kept locally; do not paste its key into chat or use production credentials. In PowerShell, start the backend in one terminal from `BACKEND`:

```powershell
cd "C:\Users\Anup Uikey\CampusShare\BACKEND"
.\build-msvc\campusshare_backend.exe
```

In a second terminal, serve the static frontend:

```powershell
cd "C:\Users\Anup Uikey\CampusShare\FRONTEND"
python -m http.server 5500
```

Open `http://localhost:5500` and sign in with a designated staging test account. Review dashboard counts, recent listings, filters, My Resources, details, request sections, and responsive behavior. The configured resource create/edit/delete and request actions can write staging data if submitted; use disposable test records. With RPC flags off, borrow/status controls should remain hidden. Do not use production credentials or turn flags on just to preview controls.

## Recommended next task

Complete a human-reviewed staging walkthrough with two test accounts after the availability grant cutover and RPC contracts are validated. Record expected/actual results for each owner/borrower action and concurrent operation before enabling any workflow flags.

## Git and deployment status

- Branch: `main`.
- Read-only staged-diff inspection shows the 24 pre-existing generated-file deletions remain staged. No staging/unstaging/reset/restore command was run.
- `git status` and `git diff --check` remain unavailable in this environment because Git reports “this operation must be run in a work tree.” Independent frontend whitespace/static checks passed.
- No commit or push was made. No Supabase project was accessed and no SQL was executed.
