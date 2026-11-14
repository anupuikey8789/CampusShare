# CampusShare local Windows setup

This guide starts the current frontend and C++ backend locally. It does not connect to a database through Codex. Local mock tests do not verify live Supabase behavior.

## Safety: staging only

Use only the Supabase project named CampusShare-Staging with reference **jxndjuslvccxgayoachm**. Verify that reference in the dashboard before copying settings.

- Do not use production credentials for this test.
- The frontend must use the staging project URL and publishable key (or legacy anon key).
- The backend must use the matching staging URL and key.
- Never put a service-role or secret key in frontend or backend configuration.
- Keep `SUPABASE_RPC_CREATE_BORROW_REQUEST=false`, `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=false`, and `SUPABASE_RPC_BORROW_STATUS=false`. All default to false.
- Do not paste keys or passwords into chat. A publishable key is browser-visible by design, but do not add local configuration files to Git.

## Required software

- Windows 10 or 11.
- Git with repository submodules.
- Visual Studio Build Tools with Desktop development with C++ and x64 MSVC.
- CMake 3.20 or newer and Ninja.
- vcpkg with libcurl installed for the active triplet.
- Python 3 and Node.js.

The existing MSVC build directory is `BACKEND/build-msvc`. If it is missing or stale, initialize the Crow and Asio submodules and configure CMake with the vcpkg toolchain installed on that machine.

## Configure the frontend

From the repository root, copy the local example:

```powershell
Copy-Item FRONTEND/config.local.example.js FRONTEND/config.local.js
```

Edit `FRONTEND/config.local.js` and enter the staging project URL and publishable key from CampusShare-Staging API settings. Keep `apiBase` as `http://127.0.0.1:18080` unless the backend runs elsewhere.

The page loads `config.local.js` before `config.js`. `FRONTEND/.gitignore` excludes the local file. The key is public client configuration; it does not bypass RLS. The example has blank values and contains no project credentials.

## Configure the backend

From the repository root:

```powershell
Copy-Item BACKEND/.env.example BACKEND/.env
```

Edit `BACKEND/.env` locally. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` to values from the same CampusShare-Staging project used by the frontend. `SUPABASE_KEY` is accepted as a legacy alias when `SUPABASE_ANON_KEY` is absent; prefer `SUPABASE_ANON_KEY`.

The backend reads `.env` from its current working directory. Operating-system environment variables take precedence. `BACKEND/.gitignore` ignores `.env` and `.env.*` while allowing `.env.example`.

Required:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` or legacy `SUPABASE_KEY`

Optional:

- `SERVER_HOST` (default `127.0.0.1`)
- `SERVER_PORT` (default `18080`)
- `CORS_ALLOWED_ORIGINS` (default allows localhost and 127.0.0.1 on ports 5500 and 5501)
- `SUPABASE_RPC_CREATE_BORROW_REQUEST` (default `false`)
- `SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE` (default `false`)
- `SUPABASE_RPC_BORROW_STATUS` (default `false`; requires atomic resource RPC mode and the staging availability-column permission cutover before enabling)

Startup fails with a concise message if required values are absent, a secret/service-role key is detected, the remote URL is not HTTPS, or a port/feature flag is malformed. It does not print configured URLs or keys. Plain HTTP is accepted only for localhost.

## Build the backend

Open an x64 Native Tools Command Prompt or Developer PowerShell for Visual Studio:

```powershell
cd C:\Users\Anup Uikey\CampusShare\BACKEND
cmake --build build-msvc --config Release
```

For a fresh checkout, initialize submodules from the repository root:

```powershell
cd C:\Users\Anup Uikey\CampusShare
git submodule update --init --recursive
```

If `build-msvc` has not been configured, configure it from `BACKEND` with the vcpkg toolchain path installed on the machine, then run the Release build command above. The current machine's existing CMake cache contains its Visual Studio Build Tools vcpkg path; another installation may differ.

The executable is `BACKEND/build-msvc/campusshare_backend.exe`.

## Start the backend on port 18080

In a new PowerShell window:

```powershell
cd C:\Users\Anup Uikey\CampusShare\BACKEND
.\build-msvc\campusshare_backend.exe
```

Start it from `BACKEND` so the relative `.env` file is found. The default bind address is `127.0.0.1:18080`. Leave the window running; press Ctrl+C to stop the server.

## Serve the frontend

In another PowerShell window:

```powershell
cd C:\Users\Anup Uikey\CampusShare\FRONTEND
python -m http.server 5500
```

Open [http://localhost:5500](http://localhost:5500). The default backend CORS allowlist includes this exact origin. If using another host or port, add that exact origin to `CORS_ALLOWED_ORIGINS` in the backend `.env` and restart the server. Do not use a wildcard.

## Verify local routes

In a third PowerShell window:

```powershell
Invoke-RestMethod http://127.0.0.1:18080/api/health
Invoke-RestMethod http://127.0.0.1:18080/api/test
```

Health reports service and configured RPC feature flags. It does not check Supabase connectivity or prove that an RPC exists. Categories and resources require a staging Auth session and are not anonymous health checks.

Local mock tests do not require Supabase credentials. From the repository root:

```powershell
python BACKEND\tests\test_api.py BACKEND\build-msvc\campusshare_backend.exe
node --check FRONTEND\config.js
node --check FRONTEND\auth.js
node --check FRONTEND\api.js
node --check FRONTEND\app.js
node --check FRONTEND\ui-model.js
node --test FRONTEND\tests\*.test.cjs
```

These tests use local mocks. They do not validate live Auth, RLS, grants, or database records.

## Troubleshooting

- **Frontend says Auth is not configured:** Check that `FRONTEND/config.local.js` exists, has a valid HTTPS project URL and non-empty publishable key, and loads before `config.js`. Never put a service-role key there.
- **Backend exits for missing configuration:** Check spelling and values in `BACKEND/.env`, start the process from `BACKEND`, and check for overriding environment variables.
- **Secret/service-role key rejected:** Replace it with the staging publishable/anon key. Do not weaken the backend validation.
- **CORS error:** Compare browser origin exactly with `CORS_ALLOWED_ORIGINS`; hostname and port both matter. Restart the backend after changing `.env`.
- **Connection refused:** Ensure the backend process is running and `apiBase` points to `http://127.0.0.1:18080`.
- **Sign-in or confirmation error:** Check the existing email Auth and redirect/site URL settings in CampusShare-Staging. Use a fresh test account.
- **HTTP 401:** The session may be missing, expired, or from a different project. Sign in again using the staging frontend settings.
- **HTTP 403:** A staging grant or RLS rule may deny the operation. Do not bypass it with privileged keys or policy changes.

Local build and mock test success does not establish live Supabase integration. Keep all RPC flags disabled until staging definitions, signatures, grants, policies, the direct `availability_status` UPDATE cutover, and concurrency behavior have been reviewed and validated. Status RPC mode also requires atomic resource RPC mode.
