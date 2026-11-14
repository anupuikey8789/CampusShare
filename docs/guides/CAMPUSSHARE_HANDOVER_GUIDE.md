# CAMPUSSHARE
## Complete Project Handover & Development Guide

**Project:** CampusShare – A Student Resource Sharing Platform  
**Repository:** https://github.com/anupuikey8789/CampusShare  
**Branch:** `main`  
**Latest local commit:** `8b1850ac7`  
**Commit message:** Complete CampusShare project implementation  
**Project status:** Core implementation committed locally; GitHub push and several integrations remain pending.

---

# 1. Project Overview

CampusShare is a student resource-sharing platform designed to help college students share, borrow, sell and donate educational resources.

Students can make better use of resources they no longer need, while other students can access useful materials at lower costs or for free.

### Main objectives

- Allow students to share educational resources.
- Allow students to borrow resources temporarily.
- Allow students to sell used resources.
- Allow students to donate resources.
- Provide authentication and user profiles.
- Manage borrowing requests and resource availability.
- Provide secure image uploads.
- Protect user information and resource ownership.

# 2. Technology Stack

| Component | Technology |
|---|---|
| Frontend | HTML, CSS, JavaScript |
| Backend | C++ |
| Backend framework | Crow |
| Database | Supabase PostgreSQL |
| Authentication | Supabase Auth |
| Storage | Supabase Storage |
| API communication | HTTP / REST |
| Build system | CMake |
| Testing | Node.js tests and Python API tests |
| Development environment | Visual Studio Code |
| Version control | Git and GitHub |

### Project architecture

Frontend communicates with the C++ backend. The backend communicates with Supabase for authentication, database operations and storage.

The frontend should not receive privileged Supabase service-role credentials.

# 3. Project Folder Structure

Important folders and files:

**BACKEND/**
- `main.cpp` – Main C++ backend implementation.
- `CMakeLists.txt` – Backend build configuration.
- `.env.example` – Example backend configuration.
- `AUTHENTICATION.md` – Authentication documentation.
- `README.md` – Backend instructions.
- `tests/` – Backend API tests.
- `Crow/` – Crow framework files.
- `asio/` – Asio networking dependency.

**FRONTEND/**
- `index.html` – Main frontend page.
- `style.css` – Application styling.
- `app.js` – Main frontend application logic.
- `api.js` – API communication.
- `auth.js` – Authentication functionality.
- `config.js` – Frontend configuration.
- `ui-model.js` – UI state and model logic.
- `tests/` – Frontend tests.

**database/**
- `sql/` – All database schema, migration, RPC, security policy, and validation SQL scripts.

**docs/**
- `architecture/` – Architecture, RPC contracts, and integration specs.
- `guides/` – Setup, migration, rollback, and testing guides.
- `reports/` – Task audit and review reports.

**Root directory**
- `README.md` – Main project overview and setup guide.
- `.gitignore` – Excludes local secrets and generated files.
- `.gitmodules` – Git submodules (Crow, Asio).

# 4. Features Implemented

The following features are present in the project implementation. Their live integration still needs end-to-end verification.

## 4.1 User authentication

- Supabase authentication integration.
- User registration and login functionality.
- Frontend authentication handling.
- Backend bearer-token verification.
- User identity validation.

## 4.2 Resource management

- Create resources.
- View available resources.
- Manage personal resources.
- Update resource information.
- Delete resources.
- Categorize resources.

## 4.3 Borrowing system

- Students can request to borrow resources.
- Owners can approve or reject requests.
- Borrowing has a due date.
- Borrowed resources have a return workflow.
- Returned resources can become available again.

## 4.4 Selling system

- Students can list resources for sale.
- Selling price must not exceed original purchase price.
- Resource condition options:
  - New
  - Like New
  - Good
  - Fair
- Buyers can submit purchase requests.
- Sellers can approve or reject requests.
- Completed sales permanently transfer the resource.

CampusShare does not process payments. Students arrange payments directly.

## 4.5 Donation system

- Students can list resources for donation.
- Donation requests can be approved or rejected.
- Owners complete the handover.
- Donated resources are marked as permanently transferred.

## 4.6 Resource images

The implementation includes code for:

- Multiple images per resource.
- JPEG, PNG and WebP formats.
- Maximum 10 images per resource.
- Maximum 5 MiB per image.
- Image metadata registration.
- Image ordering.
- Primary image selection.
- Private storage integration.
- Image deletion and reordering.

**Important:** Image uploads are not currently enabled in the running application. This is explained in Section 6.

# 5. Supabase Database and Security

The project includes database-related work for these tables:

- `profiles`
- `categories`
- `resources`
- `borrow_requests`

RLS (Row Level Security) is enabled on the four base tables according to the previous project review.

Other database work includes:

- Signup trigger and profile creation.
- Borrow request RPC functions.
- Resource update RPC proposals.
- Marketplace migration scripts.
- Image metadata table and RPC scripts.
- Storage policy proposals.
- Verification and rollback scripts.

### Important distinction

SQL files committed to GitHub are project files. Their presence does not prove that the corresponding SQL has been deployed successfully to Supabase.

Do not execute every SQL file randomly. Some files are proposals, alternatives, migrations, verification scripts or rollback scripts.

Use the staging environment only.

Production Supabase must not be modified during development.

# 6. Current Known Problems

## Issue 1: Resource image upload is disabled

Current user-facing message:

"Your photos are selected, but image uploads are not enabled by the backend yet."

### What we discovered

The backend source contains:

`SUPABASE_RESOURCE_IMAGES_ENABLED`

The code defaults this setting to `false`.

The setting was missing from the local `BACKEND/.env` file.

The backend source also contains:
- `register_resource_images`
- `reorder_resource_images`
- Resource image metadata API routes.

The running backend health endpoint reported only three feature flags:

- `borrow_request_rpc_enabled`
- `borrow_status_rpc_enabled`
- `atomic_resource_update_rpc_enabled`

It did not report `resource_images_enabled`.

The running backend may be an older executable.

### What remains to fix

1. Inspect the current C++ image-upload implementation.
2. Verify the staging Storage bucket exists.
3. Verify storage security policies.
4. Verify the `resource_images` table.
5. Verify image registration and reordering RPC functions.
6. Verify authenticated users can upload only permitted images.
7. Rebuild the latest backend.
8. Restart it only after coordinating with the current running process.
9. Enable the image feature flag only after staging verification.
10. Test upload, display, deletion and reordering from the browser.

Do not simply set the flag to `true`.

## Issue 2: Running backend may be outdated

The running backend health endpoint returned:

```json
{
  "status": "ok",
  "service": "CampusShare backend",
  "features": {
    "borrow_request_rpc_enabled": false,
    "borrow_status_rpc_enabled": false,
    "atomic_resource_update_rpc_enabled": false
  }
}
```

The source code contains additional image integration functionality, but the running executable does not report the corresponding feature flag.

The process previously identified was:

`BACKEND/build-msvc/campusshare_backend.exe`

Its process ID was 32268 during the earlier inspection. Verify the process again before taking any action.

## Issue 3: CMake unavailable in current PowerShell

**Resolved:** CMake is available via Visual Studio Build Tools at:
`C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`

## Issue 4: Backend health compatibility

Earlier frontend tests reported one failure:

`health API returns backend RPC feature flags without authentication`

The error indicated that the running backend was outdated or incompatible with the frontend's expected health response.

**Analysis:** The test fixture mock in `FRONTEND/tests/auth.test.cjs` returns only two feature flags and omits `api_version: "1.0.0"`, `build_id`, `marketplace_enabled`, and `resource_images_enabled`, which `FRONTEND/api.js` expects according to the expanded v1.0.0 health contract.

# 7. Test Results

Latest frontend test run:

| Result | Count |
|---|---:|
| Total tests | 76 |
| Passed | 75 |
| Failed | 1 |

The single failed test is `health API returns backend RPC feature flags without authentication` due to the test mock payload schema.

### Frontend test command

From the project root:

```powershell
node --test FRONTEND/tests/*.test.cjs
```

### Backend testing

The backend has Python API tests under:

`BACKEND/tests/test_api.py`

Review the test instructions in `BACKEND/README.md` before running them.

# 8. GitHub and Current Commit Status

Repository:

https://github.com/anupuikey8789/CampusShare

When ready:

```powershell
git push origin main
```

# 9. Security Rules

1. Never upload `.env` files.
2. Never upload `config.local.js`.
3. Never expose Supabase service-role keys.
4. Never use production Supabase for development experiments.
5. Keep feature flags disabled until their integrations are verified.
6. Verify RLS policies before enabling database operations.
7. Validate bearer tokens on the backend.
8. Ensure users can modify only resources they are authorized to manage.
9. Protect private pickup and handover information.
10. Ensure moderators have appropriate authorization for reports.
11. Verify Storage policies before enabling uploads.
12. Never execute an unreviewed SQL migration.

# 10. Remaining Work

## Priority 1 – Complete image uploads
- [ ] Verify staging Storage bucket.
- [ ] Verify storage policies.
- [ ] Verify image metadata table.
- [ ] Verify RPC functions.
- [ ] Verify image upload API.
- [ ] Build latest backend.
- [ ] Test authenticated image upload.
- [ ] Test image deletion and reordering.

## Priority 2 – Backend and frontend integration
- [x] Resolve CMake installation/path.
- [ ] Build latest C++ backend.
- [ ] Verify health endpoint compatibility.
- [ ] Run all frontend tests.
- [ ] Run backend tests.
- [ ] Verify authentication.
- [ ] Verify CRUD operations.
- [ ] Verify borrowing workflows.
- [ ] Verify selling workflows.
- [ ] Verify donation workflows.

## Priority 3 – Supabase security and database verification
- [ ] Review staging schema.
- [ ] Review RLS policies.
- [ ] Review grants.
- [ ] Verify signup trigger.
- [ ] Verify RPC permissions.
- [ ] Verify Storage access restrictions.
- [ ] Verify private information protection.
- [ ] Verify database transaction behavior.

## Priority 4 – Deployment
- [ ] Push the latest commit to GitHub.
- [ ] Invite friend as collaborator.
- [ ] Prepare a reliable backend build guide.
- [ ] Host the C++ backend.
- [ ] Deploy the frontend.
- [ ] Configure staging Supabase connection.
- [ ] Configure production separately after testing.
- [ ] Test the application from another computer.

---

**End of Project Handover Document**

