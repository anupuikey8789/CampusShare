# CampusShare backend

This C++17 service uses Crow for HTTP routing and libcurl for the Supabase REST request. It currently exposes health/test endpoints and a read-only categories proxy. The static frontend still renders its sample resources locally; `FRONTEND/api.js` now provides a small client for the known health and categories routes, but it does not assume category column names or resource endpoints.

## Requirements (Windows)

- Visual Studio C++ Build Tools (MSVC) or a supported MinGW-w64 toolchain.
- CMake 3.20 or newer.
- Git (including the checked-in Crow and Asio submodules).
- vcpkg for libcurl.
- Python 3 for the local HTTP integration checks.

Install vcpkg once if it is not already available:

```powershell
git clone https://github.com/microsoft/vcpkg C:/dev/vcpkg
C:/dev/vcpkg/bootstrap-vcpkg.bat
```

From the repository root, initialize dependencies if they are not present:

```powershell
git submodule update --init --recursive
```

Install libcurl through vcpkg, then configure/build from `BACKEND`. Replace the example paths with your local tool locations:

```powershell
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake"
cmake --build build --config Release
```

For a Visual Studio generator, the executable is `build/Release/campusshare_backend.exe`; for a single-configuration generator, it is `build/campusshare_backend.exe`.

The bundled `build/` directory was previously generated from a different machine and source tree. Reconfigure in a fresh build directory (for example `build-local`) if CMake reports stale cache paths.

## Configuration

Copy `.env.example` to `.env` in `BACKEND` and fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Environment variables take precedence over `.env`. The legacy `SUPABASE_KEY` variable is accepted as an alias for compatibility.

Only a Supabase publishable/anon key is appropriate in this server. Never put a `service_role` or secret key in `.env`, source control, or a client. `.env` is ignored by Git. The server validates that the URL uses HTTPS; HTTP is accepted only for localhost URLs. It listens on `127.0.0.1:18080` by default. Set `SERVER_HOST`/`SERVER_PORT` to override it.

`CORS_ALLOWED_ORIGINS` is a comma-separated list of exact origins. The default permits common local development origins on ports 5500 and 5501. Set an explicit production origin before deployment; do not use `*`.

## API

All successful API responses are JSON except that the categories endpoint returns the JSON array from Supabase.

| Method | Path | Authentication | Behavior |
| --- | --- | --- | --- |
| GET | `/api/health` | Public | Returns `{"status":"ok","service":"CampusShare backend"}`. Does not check Supabase connectivity. |
| GET | `/api/test` | Public | Compatibility endpoint returning a JSON status/message object. |
| GET | `/api/categories` | Public through the configured anon key | Reads at most 100 rows from `categories` using `select=*`. Requires Supabase REST access and a valid table/policy. |
| OPTIONS | `/api/*` | Public | CORS preflight response for configured origins. |

Errors use `{"error":{"code":"...","message":"..."}}`. Supabase failures return 502 with a generic response; logs include only transport/HTTP status, never credentials or response bodies. A valid empty JSON array is passed through as an empty result; the source database must be checked to determine whether it contains expected category records.

## Current limits and required Supabase work

The repository contains no Supabase migrations/schema, RLS policy definitions, or schema documentation. The frontend currently uses hard-coded sample cards, filters and adds them only in browser memory; there is no login flow or API contract. For these reasons, resource CRUD, borrowing, profiles and authenticated/ownership operations have not been added: their table/column relationships and security policies cannot be verified safely from this repository.

Before expanding the API, provide the authoritative schema/migrations and decide whether user JWTs are sent to this backend or the frontend talks directly to Supabase. If this backend will authorize users, add token validation through Supabase Auth and enforce ownership with RLS and/or verified server-side identity. The current categories route uses the anon/publishable key and relies on Supabase grants/RLS to govern reads. Confirm that `categories` is readable to the intended audience and that RLS is enabled with suitable policies. No live Supabase request has been verified in this environment.

## Running and stopping

Run the executable from the `BACKEND` directory so it can read `.env`. Use Ctrl+C to stop the Crow server. The server emits a startup line and minimal framework warnings; it does not log request headers, bodies or secrets.

## Verification

After building, start the server from `BACKEND` with valid local configuration. For local route tests that do not require Supabase credentials, run the mock-backed integration checks from `BACKEND`:

```powershell
python tests/test_api.py build-msvc/campusshare_backend.exe
```

The script verifies missing-configuration startup, health/test responses, categories pass-through against a local mock, upstream and malformed-JSON errors, and allowed/disallowed CORS origins. It does not access Supabase. Replace the executable path with `build/Release/campusshare_backend.exe` for a Visual Studio multi-configuration build. A live `/api/categories` check still requires the user's local `.env` or environment configuration and a real schema/policy; it has not been run here.
