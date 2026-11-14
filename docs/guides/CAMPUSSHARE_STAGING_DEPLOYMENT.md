# CampusShare Staging Deployment & Migration Guide

**Target Environment:** Staging Supabase (`jxndjuslvccxgayoachm`)  
**Strict Safety Policy:** NEVER execute SQL against production (`dkyfkdmlkghucyepxbbh`).

---

## 1. Migration Execution Order

To deploy new capabilities to the staging environment, execute SQL migrations in the Supabase SQL Editor in the exact sequence below:

### Step 1: Fix Resource Permissions
- **File:** [FIX_RESOURCES_PERMISSIONS.sql](file:///c:/Zoro/C++/CampusShare/CampusShare/database/sql/FIX_RESOURCES_PERMISSIONS.sql)
- **Purpose:** Resolves the HTTP 403 Forbidden on resource creation by granting table-level CRUD permissions on `public.resources` to `authenticated` and ensuring RLS checks `(auth.uid() = owner_id)`.
- **Pre-check:**
  ```sql
  SELECT grantee, privilege_type FROM information_schema.role_table_grants WHERE table_name = 'resources';
  ```
- **Execute:** Run the contents of `FIX_RESOURCES_PERMISSIONS.sql`.
- **Verification:**
  ```sql
  SELECT policyname, cmd FROM pg_policies WHERE tablename = 'resources';
  ```

### Step 2: Consolidated Borrowing Communication System
- **File:** [COMMUNICATION_WORKFLOW_COMPLETE_SETUP.sql](file:///c:/Zoro/C++/CampusShare/CampusShare/database/sql/COMMUNICATION_WORKFLOW_COMPLETE_SETUP.sql)
- **Purpose:** Deploys Steps 1 through 6 of the Borrowing Communication System:
  1. `public.conversations` table and automatic creation in `approve_borrow_request`.
  2. `public.messages` table with idempotency key index.
  3. `send_conversation_message` RPC.
  4. `public.meeting_proposals` table, `propose_meeting` RPC, and `respond_to_meeting_proposal` RPC with IST timezone enforcement.
  5. `public.notifications` table and `mark_notifications_read` RPC.
  6. Return workflow integration (`return_requested` state and `return_borrowed_resource` RPC).
- **Execute:** Run the contents of `COMMUNICATION_WORKFLOW_COMPLETE_SETUP.sql`.
- **Post-verification:** Run [COMMUNICATION_WORKFLOW_COMPLETE_VERIFY.sql](file:///c:/Zoro/C++/CampusShare/CampusShare/database/sql/COMMUNICATION_WORKFLOW_COMPLETE_VERIFY.sql).

---

## 2. Feature Activation & Cutover

Once the database migration verifies successfully:

1. **Enable Feature Flag in Backend:**
   In `BACKEND/.env`:
   ```env
   SUPABASE_COMMUNICATION_ENABLED=true
   ```

2. **Rebuild Backend Executable:**
   ```powershell
   cmake --build BACKEND/build --config Release
   ```

3. **Restart Backend Service:**
   Restart `campusshare_backend.exe` to serve the new `/api/conversations`, `/api/meetings`, and `/api/notifications` endpoints.

4. **Rollback Strategy:**
   If any regression occurs, run [COMMUNICATION_WORKFLOW_COMPLETE_ROLLBACK.sql](file:///c:/Zoro/C++/CampusShare/CampusShare/database/sql/COMMUNICATION_WORKFLOW_COMPLETE_ROLLBACK.sql) in the Supabase SQL editor and set `SUPABASE_COMMUNICATION_ENABLED=false` in `BACKEND/.env`.

