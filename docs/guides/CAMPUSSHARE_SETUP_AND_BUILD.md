# CampusShare Setup and Build Guide

This guide explains how to build the C++ Crow backend, configure Supabase credentials, and run the complete application locally.

---

## 1. Prerequisites

- **Operating System:** Windows 10/11 (or Linux)
- **Compiler:** MSVC v143+ (Visual Studio 2022) with C++17 support
- **Build System:** CMake 3.25+ and Ninja or MSBuild
- **Runtime:** Node.js v18+ (for testing and local server)
- **Database:** Supabase project (Staging: `jxndjuslvccxgayoachm`)

---

## 2. Backend Configuration & Build

### A. Environment Configuration (`BACKEND/.env`)
Create `BACKEND/.env` with the following keys:
```env
SUPABASE_URL=https://jxndjuslvccxgayoachm.supabase.co
SUPABASE_ANON_KEY=<your_supabase_anon_key>
SUPABASE_RPC_CREATE_BORROW_REQUEST=true
SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true
SUPABASE_RPC_BORROW_STATUS=true
SUPABASE_MARKETPLACE_ENABLED=true
SUPABASE_RESOURCE_IMAGES_ENABLED=true
SUPABASE_COMMUNICATION_ENABLED=false
```
*(Enable `SUPABASE_COMMUNICATION_ENABLED=true` once the communication SQL migration has been applied in Supabase).*

### B. Building with CMake and MSBuild
From the repository root:
```powershell
Set-Location BACKEND
cmake -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
```
The compiled executable will be located at `BACKEND/build/Release/campusshare_backend.exe`.

### C. Running the Backend Service
```powershell
Set-Location BACKEND
.\build\Release\campusshare_backend.exe
```
The server will start listening on `0.0.0.0:18080`.

---

## 3. Frontend Setup & Execution

The frontend is pure vanilla JavaScript and does not require a build step.

### A. Local Configuration (`FRONTEND/config.local.js`)
If overriding project defaults, create `FRONTEND/config.local.js`:
```javascript
window.__CAMPUSSHARE_CONFIG__ = {
    supabaseUrl: "https://jxndjuslvccxgayoachm.supabase.co",
    supabaseAnonKey: "<your_supabase_anon_key>",
    apiBaseUrl: "http://127.0.0.1:18080"
};
```

### B. Serving the Frontend
Run a static HTTP server on port 5500:
```powershell
python -m http.server 5500 -d FRONTEND
```
Access the application in your browser at `http://localhost:5500`.

---

## 4. Running the Automated Test Suite

From the repository root:
```powershell
node FRONTEND/tests/app.test.cjs
node FRONTEND/tests/ui.test.cjs
node FRONTEND/tests/communication.test.cjs
node FRONTEND/tests/auth.test.cjs
```
All 88 tests should pass without errors.

