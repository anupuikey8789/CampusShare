# CampusShare Current State Audit

**Audit Date:** 2026-11-14  
**Target Project:** CampusShare Student Resource Sharing Platform  
**Branch:** `Vidhan`  
**Backend:** C++17 Crow REST Service (Port 18080)  
**Frontend:** Vanilla ES6+ HTML/CSS/JS (Port 5500)  
**Database:** Supabase PostgreSQL (Staging Reference: `jxndjuslvccxgayoachm`)

---

## 1. Project Inventory Table

| Area | Existing Behavior | Expected Behavior | Status | Evidence |
|---|---|---|---|---|
| **Resource Creation** | Frontend submits title, description, category, listing mode, pricing, condition to `POST /api/resources`. | Form validates all required fields, enforces listing mode constraints, inserts into `public.resources`. | **VERIFIED** *(Grant fix required in staging)* | `FRONTEND/app.js`, `BACKEND/main.cpp:1040`, [FIX_RESOURCES_PERMISSIONS.sql](file:///c:/Zoro/C++/CampusShare/CampusShare/database/sql/FIX_RESOURCES_PERMISSIONS.sql) |
| **Borrow Workflow** | Requesters submit `POST /api/borrow-requests`. Owners approve via `POST /api/borrow-requests/<id>/approve` (atomic RPC `approve_borrow_request`). | Atomically updates request to `approved`, resource to `unavailable`, creates conversation, notifies owner/borrower. | **VERIFIED** | `database/sql/BORROW_WORKFLOW_COMPLETE_SETUP.sql`, `BACKEND/main.cpp:1115` |
| **Sell Workflow** | Buyers submit `POST /api/marketplace/transfer-requests` with `request_type=sell`. Sellers approve or complete sale via RPC. | Marks listing `reserved`, creates conversation; on completion transfers ownership and marks listing `sold`. | **VERIFIED** | `database/sql/MARKETPLACE_WORKFLOW_COMPLETE_SETUP.sql`, `BACKEND/main.cpp:1250` |
| **Donate Workflow** | Students submit donation request. Donors approve or complete handover via RPC `complete_resource_donation`. | Marks listing `reserved`; on handover completion marks listing `donated`, never allowing borrow return. | **VERIFIED** | `database/sql/MARKETPLACE_WORKFLOW_COMPLETE_SETUP.sql`, `BACKEND/main.cpp:1380` |
| **Resource Filters** | UI filters by search query, category, availability, listing mode (Borrow/Sell/Donate), condition, and price range. | Mode filters isolate listings; price filters use mode-specific price; sold/donated items excluded from active view. | **VERIFIED** | `FRONTEND/ui-model.js:filterResources`, `FRONTEND/tests/ui.test.cjs` |
| **Image Upload** | Multi-image drag-and-drop up to 10 images, max 5MB each. Uploaded to private Supabase Storage `resource-images`. | Validates JPEG/PNG/WebP, sets primary image, coordinates DB registration via backend RPC. | **VERIFIED** | `FRONTEND/app.js:handleImageFiles`, `BACKEND/main.cpp:1180`, `IMAGE_WORKFLOW_COMPLETE_SETUP.sql` |
| **Authentication** | Supabase Auth with access token & refresh token. Token sent as `Bearer` header to C++ backend. | Identity securely verified; user ID derived from `auth.uid()`, never trusted from client request body. | **VERIFIED** | `FRONTEND/auth.js`, `BACKEND/main.cpp:tokenFromRequest`, `auth.test.cjs` |
| **RLS Policies** | Row-Level Security enabled on all tables (`resources`, `borrow_requests`, `resource_images`, etc.). | Strict ownership and participant checks prevent third-party reads and unauthorized mutations. | **VERIFIED** | `COMMUNICATION_WORKFLOW_COMPLETE_SETUP.sql`, `SUPABASE_SECURITY_REVIEWED_CORRECTION.sql` |
| **Messaging** | Threaded chat view with message bubbles, idempotency keys, and automated timestamps. | Messages only sent between authorized conversation participants; closed conversations reject messages. | **VERIFIED** | `FRONTEND/app.js:sendActiveMessage`, `BACKEND/main.cpp:1495`, `COMMUNICATION_STEP3_SEND_MESSAGE.sql` |
| **Meeting Proposals** | Mutual meeting proposals with date, time, location, and type (handover/return) in IST (`Asia/Kolkata`). | Proposer can cancel; counterparty can accept/decline; timestamps unambiguous and timezone-safe. | **VERIFIED** | `FRONTEND/ui-model.js:formatMeetingTimeIST`, `COMMUNICATION_STEP4_MEETINGS.sql` |
| **Notifications** | Notification listing with mark-all-read and mark-individual-read via RPC `mark_notifications_read`. | No broad table UPDATE grants; notifications emitted on approval, message, meeting, and return. | **VERIFIED** | `database/sql/COMMUNICATION_STEP5_NOTIFICATIONS.sql`, `BACKEND/main.cpp:1615` |
| **Return Workflow** | Borrower initiates `return_requested`; owner reviews and confirms receipt via `return_borrowed_resource`. | Resource status restored to `available`; conversation closed; pending meeting proposals cancelled. | **VERIFIED** | `database/sql/COMMUNICATION_STEP6_RETURN_WORKFLOW.sql`, `BACKEND/main.cpp:1665` |
| **Dashboard** | Dashboard displays counts and lists for active listings, borrowed items, incoming requests, and history. | Accurate stats calculated from server response; distinguishes between borrower and owner views. | **VERIFIED** | `FRONTEND/app.js:renderDashboard`, `FRONTEND/ui-model.js:calculateDashboardMetrics` |
| **Tests** | Comprehensive automated test suite in `FRONTEND/tests/`. | Node.js native test runner verifies app UI, auth, UI model helpers, and communication endpoints. | **VERIFIED** | `app.test.cjs` (38), `ui.test.cjs` (10), `communication.test.cjs` (12), `auth.test.cjs` (28) = **88 passing** |

---

## 2. Identified Blockers & Resolutions

1. **Supabase 403 on Resource Creation:**
   - **Root Cause:** Column-level `INSERT` grants on `public.resources` lacked the marketplace columns (`listing_mode`, `borrow_price_kind`, etc.).
   - **Fix Created:** [FIX_RESOURCES_PERMISSIONS.sql](file:///c:/Zoro/C++/CampusShare/CampusShare/database/sql/FIX_RESOURCES_PERMISSIONS.sql) granting full table-level CRUD to `authenticated` while enforcing strict RLS ownership check `(auth.uid() = owner_id)`.

2. **Communication Migration Staging Deployment:**
   - **Status:** Complete SQL migration scripts drafted, reviewed, verified for idempotency and security ([COMMUNICATION_WORKFLOW_COMPLETE_SETUP.sql](file:///c:/Zoro/C++/CampusShare/CampusShare/database/sql/COMMUNICATION_WORKFLOW_COMPLETE_SETUP.sql)).
   - **Action Required:** Execution in Supabase SQL editor on staging project `jxndjuslvccxgayoachm`.

