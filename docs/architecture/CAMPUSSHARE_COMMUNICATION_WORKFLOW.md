# CampusShare Borrowing Communication Workflow

This document details the communication system architecture, UI states, meeting scheduling, and return coordination.

---

## 1. Conversation Creation & Lifecycle

Conversations are created atomically inside database approval workflows:
- **Borrow Request Approval:** `approve_borrow_request` creates a row in `public.conversations` linked to `borrow_request_id`.
- **Marketplace Sell/Donate Approval:** `approve_resource_transfer_request` creates a conversation linked to the transfer.

### Conversation Roles
- **Owner (`owner_id`):** The student who listed the resource.
- **Requester / Borrower (`borrower_id`):** The student requesting the resource.
- Both roles have symmetrical messaging permissions.

### Conversation States
- **`active`:** Allows sending messages, proposing meetings, and submitting return requests.
- **`closed`:** Read-only mode activated when an item is returned or transfer is completed. All new messages and meeting proposals are rejected.

---

## 2. In-Chat Meeting Proposals

Students coordinate physical resource exchange directly in the thread:

### Proposal Attributes
- `meeting_type`: `handover` (giving item to borrower) or `return` (giving item back to owner).
- `meeting_date` & `meeting_time`: Converted to/from unambiguous `timestamptz` in `Asia/Kolkata` (IST).
- `location`: Exact campus spot (e.g. "Main Library Entrance", "Block 3 Cafeteria").
- `notes`: Optional contact hint (e.g. "I am wearing a yellow hoodie").

### Proposal State Transitions
```
                [Proposer Submits]
                        │
                        ▼
                     pending
                        │
       ┌────────────────┼────────────────┐
       ▼                ▼                ▼
   [Accepted]       [Declined]      [Cancelled]
 (By Recipient)   (By Recipient)   (By Proposer)
```

- When a new proposal is created, any prior active proposal in that thread is marked `superseded`.
- When an accepted proposal exists, a green badge displays the confirmed meeting time in readable IST format.

---

## 3. Return Coordination Workflow

1. **Borrower Requests Return:**
   - In the active chat, borrower clicks **"Request Return"**.
   - Backend calls `POST /api/conversations/<id>/return-request`.
   - The underlying `borrow_requests` record status changes from `approved` to `return_requested`.
   - The owner receives an immediate notification.

2. **Scheduling Return Handover:**
   - Either student can propose a `return` meeting time/location.
   - Counterparty accepts the proposal.

3. **Owner Confirms Return:**
   - When physical handover occurs, the owner clicks **"Confirm Return"** (available on the request card and thread).
   - Backend calls `POST /api/borrow-requests/<id>/return` which invokes `return_borrowed_resource`.
   - **Effects:**
     - `borrow_requests.status` becomes `returned`.
     - `borrow_requests.returned_at` is set to statement timestamp.
     - `resources.availability_status` is restored to `available`.
     - `conversations.status` is set to `closed`.
     - Any pending meeting proposals are marked `cancelled`.
     - Borrower receives a completion notification.

