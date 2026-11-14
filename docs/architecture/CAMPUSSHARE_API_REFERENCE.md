# CampusShare Backend API Reference

**Host:** `http://127.0.0.1:18080`  
**Authentication:** HTTP Bearer token (`Authorization: Bearer <supabase_access_token>`)

---

## 1. System Endpoints

### `GET /api/health`
- **Auth Required:** No
- **Response:**
  ```json
  {
    "status": "ok",
    "api_version": "1.0.0",
    "build_id": "...",
    "features": {
      "borrow_request_rpc_enabled": true,
      "borrow_status_rpc_enabled": true,
      "atomic_resource_update_rpc_enabled": true,
      "marketplace_enabled": true,
      "resource_images_enabled": true,
      "communication_enabled": false
    }
  }
  ```

---

## 2. Resource Management

### `GET /api/categories`
- **Auth Required:** Yes
- **Returns:** List of category records `[{ id, name, created_at }]`.

### `GET /api/resources`
- **Auth Required:** Yes
- **Returns:** List of resources filtered by student visibility.

### `GET /api/resources/<id>`
- **Auth Required:** Yes
- **Returns:** Single resource object with ownership, category, and images.

### `POST /api/resources`
- **Auth Required:** Yes
- **Body:**
  ```json
  {
    "title": "Data Structures Book",
    "description": "Like new condition",
    "category_id": 1,
    "resource_type": "physical",
    "listing_mode": "borrow",
    "borrow_price_kind": "free"
  }
  ```
- **Returns:** Created resource object (Status `201 Created`).

### `PATCH /api/resources/<id>`
- **Auth Required:** Yes (Owner only)
- **Body:** Partial resource fields to update.

### `DELETE /api/resources/<id>`
- **Auth Required:** Yes (Owner only)
- **Returns:** `200 OK` on successful removal.

---

## 3. Borrowing Endpoints

### `GET /api/borrow-requests`
- **Auth Required:** Yes
- **Returns:** List of borrow requests relevant to the user (as borrower or owner).

### `POST /api/borrow-requests`
- **Auth Required:** Yes
- **Body:** `{"resource_id": 12, "request_message": "Need this for project"}`
- **Returns:** Created pending borrow request.

### `POST /api/borrow-requests/<id>/approve`
- **Auth Required:** Yes (Owner only)
- **Body:** `{"due_at": "2026-11-25T18:00:00Z"}`
- **Returns:** Updated request record. Creates conversation.

### `POST /api/borrow-requests/<id>/reject`
- **Auth Required:** Yes (Owner only)
- **Returns:** Updated request record (status: `rejected`).

### `POST /api/borrow-requests/<id>/return`
- **Auth Required:** Yes (Owner only)
- **Returns:** Updated request record (status: `returned`). Restores availability.

---

## 4. Communication Endpoints *(Gated by `SUPABASE_COMMUNICATION_ENABLED`)*

### `GET /api/conversations`
- **Auth Required:** Yes
- **Returns:** Active and closed conversations where the caller is a participant.

### `GET /api/conversations/<id>/messages`
- **Auth Required:** Yes (Participant only)
- **Returns:** List of messages ordered chronologically.

### `POST /api/conversations/<id>/messages`
- **Auth Required:** Yes (Participant only)
- **Body:**
  ```json
  {
    "content": "Can we meet at the cafeteria?",
    "client_idempotency_key": "unique-client-uuid-or-timestamp"
  }
  ```
- **Returns:** Inserted message record.

### `GET /api/conversations/<id>/meetings`
- **Auth Required:** Yes (Participant only)
- **Returns:** List of meeting proposals for the conversation.

### `POST /api/conversations/<id>/meetings`
- **Auth Required:** Yes (Participant only)
- **Body:**
  ```json
  {
    "meeting_type": "handover",
    "meeting_date": "2026-11-20",
    "meeting_time": "14:30",
    "location": "Main Library Steps",
    "notes": "Look for blue backpack"
  }
  ```
- **Returns:** Created meeting proposal record.

### `POST /api/meetings/<id>/respond`
- **Auth Required:** Yes (Participant only)
- **Body:** `{"action": "accept"}` *(or "decline", "cancel")*
- **Returns:** Updated meeting proposal.

### `POST /api/conversations/<id>/return-request`
- **Auth Required:** Yes (Borrower only)
- **Returns:** Transition response marking request as `return_requested`.

### `GET /api/notifications`
- **Auth Required:** Yes
- **Returns:** Unread and recent notifications for the caller.

### `POST /api/notifications/mark-read`
- **Auth Required:** Yes
- **Body:** `{"ids": [101, 102], "mark_all": false}`
- **Returns:** Number of notifications updated.

