# CampusShare Task 11.1 — Authentication and Category Loading Diagnostic

## Root cause found

The current configuration files are aligned: `FRONTEND/config.local.js`, the effective frontend config, and both public-key variables in `BACKEND/.env` point to the staging project, use a recognized publishable-key format, and match one another. The values are intentionally not reproduced here.

The runtime was not aligned with those current files. Several older `campusshare_backend.exe` instances were running, including the repository's `BACKEND/build-msvc` binary and temporary CampusShare builds. The process owning port 18080 changed between checks. The repository binary was older than the current `main.cpp`, and a running process keeps the configuration it loaded at startup. The signed-in page showed the category and resource failures while those old instances were present. This stale/duplicate backend runtime is the confirmed local defect.

I stopped the verified CampusShare backend copies and started one freshly built repository executable from the `BACKEND` directory. It is now the sole repository backend process on port 18080, loaded with the current local `.env`. Health returns HTTP 200. The original browser's 401 cannot be attributed to one old process's in-memory key with certainty because its upstream Auth response was not captured before cleanup. A live authenticated request after the restart is still required to confirm that this fixes the staging flow end to end.

## Configuration and request flow reviewed

- `index.html` loads `config.local.js` before `config.js`; `config.js` preserves a valid local override. The property name is `supabasePublishableKey`.
- Supabase JS v2 uses persisted browser sessions and `autoRefreshToken`. Its `getSession()` returns the current session and refreshes when necessary ([Supabase `getSession`](https://supabase.com/docs/reference/javascript/auth-getsession)). The API helper obtains the token for each authenticated request rather than keeping a second token copy.
- `api.js` attaches `Authorization: Bearer <access token>` to categories and resources. The C++ backend verifies that user token through `/auth/v1/user`, with the public API key in a separate `apikey` header. PostgREST receives the user Bearer token and API key separately.
- The backend loads `.env` at startup from its working directory. Therefore it must be restarted after local configuration changes. Its `SUPABASE_ANON_KEY` remains canonical; `SUPABASE_API_KEY` is accepted as a compatibility fallback. If multiple aliases are configured, they must match or startup fails closed.
- Both `http://localhost:5500` and `http://127.0.0.1:5500` are allowed by the local CORS configuration. Missing-token reads to `/api/categories` and `/api/resources` still return 401, as required.

## Code changes

- `BACKEND/main.cpp`: select the canonical key or supported `SUPABASE_API_KEY` fallback; reject conflicting aliases without logging their values; log only which variable supplied the key; distinguish an Auth endpoint rejection (`auth_rejected`) from a missing/malformed token and from an Auth service outage. The Auth log reports status only, not upstream body, API key, or token.
- `BACKEND/.env.example`: document the optional `SUPABASE_API_KEY` compatibility alias and matching-key requirement.
- `FRONTEND/auth.js`: add a deduplicated forced-refresh method that uses the existing Supabase client/session only.
- `FRONTEND/api.js`: on a backend `auth_rejected`, force one session refresh and retry once with the returned token. Failed refresh asks the student to sign in again; a second Auth rejection points to checking frontend/backend staging configuration. No token is logged or stored by this helper.
- `BACKEND/tests/test_api.py`: test API-key alias fallback, reject conflicting aliases without echoing values, and verify mocked Auth plus distinct API-key/Bearer forwarding.
- `FRONTEND/tests/auth.test.cjs`: cover a valid signed-in session, the same session token on category reads, one refresh/retry after expiry, failed refresh, repeated backend rejection, and redacted diagnostics.
- `FRONTEND/tests/app.test.cjs`: test that all 12 approved category names populate the Add Resource dropdown from returned records.
- This report was updated in place. `config.js` and `config.local.js` needed no further changes because their current effective staging configuration already matched.

No SQL or database changes were made; no production project was accessed; no RPC flags were enabled.

## Tests and local runtime results

- Frontend suite: `node --test tests/*.test.cjs` — **55 passed, 0 failed**.
- JavaScript syntax checks for `config.js`, `auth.js`, `api.js`, and `app.js` — **passed**.
- C++ MSVC/CMake Release build: `BACKEND/build-msvc/campusshare_backend.exe` — **passed**. The first link attempt could not replace the in-use executable; after stopping the verified old process, the final link succeeded. The resulting executable is newer than `main.cpp`.
- Backend mock API suite — **passed**. It includes Auth acceptance/rejection/outage, API key and user token separation, alias/conflict handling, resource/categories behavior, CORS, and existing RPC safeguards. It used local mocks only.
- Local backend health — **HTTP 200, `status: ok`**. Both borrowing RPC feature flags report `false`.
- Local unauthenticated `/api/categories` and `/api/resources` — **401 `unauthorized`**, expected without a Bearer token.
- Local process check — one repository `build-msvc` backend process serves port 18080. Startup log identifies the selected environment variable only.
- `git diff --check` — **passed** (line-ending conversion warnings only). Git remains on `main`; the 24 pre-existing staged generated-file deletions remain staged. No stage/unstage/reset/commit/push was performed.

## Live staging status and next action

I inspected the existing signed-in browser page before the restart; it showed the reported resource and category errors. The computer-use control could not safely invoke the page's Refresh button after the backend restart, so **no authenticated live request was sent after the fix**. The 12 dropdown options were verified with frontend mock data, not with live rows. I did not access Supabase or execute SQL.

The rebuilt backend is currently running on port 18080. In the existing browser tab, hard-refresh `http://localhost:5500` with **Ctrl+Shift+R**, open Browse Resources and click **Refresh**, then open **Add Resource** and confirm the 12 categories appear. This ensures the page fetches current JavaScript and makes a new request through the single rebuilt backend. Do not start another backend instance while this one is running.

If the backend is stopped later, launch it from the directory that contains `.env`:

```powershell
Set-Location 'C:\Users\Anup Uikey\CampusShare\BACKEND'
.\build-msvc\campusshare_backend.exe
```

If errors remain, provide only the HTTP status and error code from the browser/backend diagnostics. Do not share request headers, access/refresh tokens, passwords, or key values.
