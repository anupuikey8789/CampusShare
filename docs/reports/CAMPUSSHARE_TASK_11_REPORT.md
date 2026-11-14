# CampusShare Task 11 — Category Integration and Add Resource

**Repository:** `C:\Users\Anup Uikey\CampusShare`

**Date:** 2026-11-13

## Findings and root cause

The frontend only populated the category dropdown after a combined `Promise.all()` for categories, resources, and health completed. If either the category request or resource request failed, the shared error handler called `clearLibrary()` and emptied both lists. The Add Resource form then showed the same “categories are not available yet” message for loading, an empty table, and an API failure. This prevented the UI from identifying or recovering from the actual state.

I corrected that code-level failure mode by loading category and resource results independently and representing category loading, empty, and error states separately. The previous status message alone does **not** prove why the staging dropdown was empty. Because this task explicitly forbade database access, I could not determine whether the staging table currently has no rows, the API is denied, or staging configuration differs from the frontend.

The available schema documentation records `public.categories` with `id bigint GENERATED ALWAYS AS IDENTITY` primary key, `name text NOT NULL UNIQUE`, and `created_at timestamptz NOT NULL DEFAULT now()`. It records an authenticated SELECT grant and the `Read categories` policy with `USING (true)`. These facts are from existing repository evidence; they were not re-queried, and staging parity was not verified.

## Changes implemented

- The UI now distinguishes loading, empty, and failed category requests in the dropdown and Add Resource form.
- Category and resource loading no longer fail as one combined operation. Resource browsing remains available when the category API fails, and the category error is visible with a refresh instruction.
- The existing authenticated `GET /api/categories` route remains the source of dropdown records. It verifies the Bearer token and selects only `id,name,created_at`; the API helper uses the current Supabase Auth session token.
- Add Resource requires the selected category ID to match a category returned by the authenticated API. Its numeric value is preserved as `category_id` through the frontend and backend; no category IDs are hardcoded.
- The C++ POST route now requires a positive bigint category ID and sends it as a JSON number to PostgREST. PATCH validates a non-null category ID the same way while preserving schema-supported `null`. Existing foreign-key enforcement still rejects a positive ID that does not exist.
- Existing title, description, resource type, and availability validation remains in place. The existing POST route remains unchanged; Crow derives `owner_id` from the verified Auth identity.
- After a successful create, the existing library refresh updates Browse Resources and My Resources.
- No backend route or database schema change was made.

## Approved categories

The staging seed and verification scripts contain these exact names:

1. Study Materials
2. Books
3. Documents
4. Digital Resources
5. Tutoring & Peer Help
6. Study Groups & Projects
7. Equipment & Electronics
8. Stationery & Supplies
9. Opportunities
10. Campus Life & Events
11. Housing & Essentials
12. Announcements & Lost & Found

## SQL files prepared

- [SUPABASE_STAGING_CATEGORIES_SEED.sql](</C:/Users/Anup Uikey/CampusShare/SUPABASE_STAGING_CATEGORIES_SEED.sql>) inserts only `name`. It relies on the existing identity/default behavior, skips exact duplicates with the verified unique constraint, and does not insert a case- or outer-whitespace-equivalent name. Existing category IDs and references are not changed.
- [SUPABASE_STAGING_CATEGORIES_VERIFY.sql](</C:/Users/Anup Uikey/CampusShare/SUPABASE_STAGING_CATEGORIES_VERIFY.sql>) is read-only. It reports each approved name as `OK`, `EXISTING EQUIVALENT NAME; PRESERVED`, or `MISSING`, and includes an optional normalized duplicate check.

Neither script was executed. No Supabase project was accessed, and production was not touched.

## Files changed

- `FRONTEND/app.js`
- `FRONTEND/tests/app.test.cjs`
- `FRONTEND/tests/auth.test.cjs`
- `BACKEND/main.cpp`
- `BACKEND/tests/test_api.py`
- `SUPABASE_STAGING_CATEGORIES_SEED.sql`
- `SUPABASE_STAGING_CATEGORIES_VERIFY.sql`
- `CAMPUSSHARE_TASK_11_REPORT.md`

## Tests and checks

- Frontend suite: **48 passed, 0 failed** (`node --test tests/*.test.cjs`). This includes category API success/empty/error cases, category loading and dropdown population, selected ID handling, invalid category submission, Add Resource success/failure, authentication, and UI recovery when categories fail.
- JavaScript syntax checks: **passed** for `app.js`, `api.js`, `auth.js`, and `ui-model.js` using `node --check`.
- Backend mock API suite: **passed** with a local Release Crow executable and local mock Auth/PostgREST server. It covers category reads, empty/error/malformed responses, authentication, CORS, resource creation, owner assignment, malformed/missing category IDs, foreign-key rejection for a nonexistent numeric ID, resource reads/updates/deletes, and upstream failures. This does not test Supabase RLS or staging data.
- MSVC/CMake Release build: **passed** using the existing vcpkg installation; output is in the separate local build directory `C:\CP _PROJECT FILES AND PPT\CampusShare-task11-release-build`.
- SQL static checks: **passed** for 12 entries in each script, use of only the documented categories columns, duplicate protection, balanced seed transaction, read-only verification statements, and absence of destructive statements or credential/project URL literals. These checks do not establish PostgreSQL runtime behavior.
- `git diff --check`: **passed** for the changed tracked files; only the repository’s LF/CRLF conversion warnings were reported.

## Manual staging steps

1. Review `SUPABASE_STAGING_CATEGORIES_SEED.sql` and confirm the SQL Editor is connected to **CampusShare-Staging**. Do not run it in production.
2. Run the seed script once in the staging SQL Editor.
3. Run `SUPABASE_STAGING_CATEGORIES_VERIFY.sql`. Confirm all twelve approved names report `OK` or a preserved equivalent name. Investigate any `MISSING` result before using Add Resource.
4. Start the backend with its existing local `.env` from the `BACKEND` directory and confirm that its URL/key point to the same staging project as the frontend. Do not display or share key values:
   ```powershell
   Set-Location 'C:\Users\Anup Uikey\CampusShare\BACKEND'
   & 'C:\CP _PROJECT FILES AND PPT\CampusShare-task11-release-build\campusshare_backend.exe'
   ```
5. In another PowerShell window, serve `FRONTEND` on an origin allowed by the backend CORS configuration:
   ```powershell
   Set-Location 'C:\Users\Anup Uikey\CampusShare\FRONTEND'
   python -m http.server 5500
   ```
   Open `http://localhost:5500`, sign in using a staging test student, and open Add Resource.
6. Confirm the category names appear, select one, complete the required fields, and submit. Confirm the success message and that the resource appears in Browse Resources and My Resources after refresh.
7. Open the new resource’s Details, edit it, refresh, and verify the update. Delete the test resource if no borrowing row references it; the existing FK may reject deletion when borrowing history exists.

## Remaining limitations

- Live staging category data, Auth, grants, RLS, and resource creation were not tested. The staging table could be empty or the category API/configuration could still fail; the read-only verification query and browser test distinguish those cases.
- The category SELECT policy/grant evidence is documented from previous inspection, not verified against staging during this task.
- Resource list reads are capped at 100 rows and the frontend filters that returned set.
- Borrowing RPC flags remain unchanged and disabled; no borrowing behavior or database policy was modified.

## Git and safety

Branch is `main`. No staging/unstaging, reset, cleanup, commit, or push operation was performed. The index still contains the **24 pre-existing staged generated-file deletions**. No `.env` content, service-role key, or secret was added to the changed files.
