# CampusShare Canonical Business Logic Specification

**System:** CampusShare Student Resource Sharing Platform  
**Architecture:** Frontend (SPA) + Backend (C++ Crow) + Database (Supabase PostgreSQL + RLS + RPC)

---

## 1. Resource Listing Modes

Every resource record has exactly one `listing_mode`:

1. **`borrow`**:
   - Intended for temporary lending and borrowing between students.
   - Pricing can be `free` or paid (`fixed`, `per_day`, `per_week`).
   - Does not have `sale_price` or `condition` fields.
   - Enters the Borrow lifecycle.

2. **`sell`**:
   - Intended for permanent transfer of ownership for monetary consideration.
   - Requires `sale_original_price`, `sale_price` (where `sale_price <= sale_original_price`), `item_condition` (`new`, `like_new`, `good`, `fair`), and valid `purchase_year` (1900 to current year).
   - Enters the Sell transfer lifecycle.
   - CampusShare does not handle financial transactions; students arrange physical payment directly.

3. **`donate`**:
   - Intended for free permanent handover of unneeded items.
   - Prohibits both borrow charges and sale prices.
   - Enters the Donation transfer lifecycle.

---

## 2. Resource States & Availability

### Resource Status (`availability_status`)
- `available`: Open for discovery and new requests.
- `unavailable`: Currently borrowed, reserved, sold, or withdrawn.

### Resource Listing State (`listing_state`)
- `active`: Currently discoverable in Browse.
- `reserved`: An incoming Sell or Donate request has been approved; pending physical handover and confirmation.
- `sold`: Sale confirmed; ownership transferred; permanently removed from active listings.
- `donated`: Donation confirmed; permanently removed from active listings.

---

## 3. Workflow Lifecycles

### A. Borrow Workflow
```
[Requester submits Request] 
       │
       ▼
  Status: pending
       │
       ├──► [Owner Rejects] ──► Status: rejected (Resource stays available)
       │
       └──► [Owner Approves (RPC)]
                 │
                 ▼
            Status: approved
            Resource: unavailable
            Conversation created atomically
                 │
                 ▼
            [Handover Meeting proposed / accepted]
                 │
                 ▼
            [Borrower requests return (`POST /api/conversations/<id>/return-request`)]
                 │
                 ▼
            Status: return_requested
                 │
                 ▼
            [Owner confirms return (RPC `return_borrowed_resource`)]
                 │
                 ▼
            Status: returned
            Resource: available
            Conversation: closed
```

### B. Sell Workflow
```
[Buyer submits Transfer Request (`request_type=sell`)]
       │
       ▼
  Status: pending
       │
       ├──► [Seller Rejects] ──► Status: rejected
       │
       └──► [Seller Approves (RPC)]
                 │
                 ▼
            Status: approved
            Resource: reserved & unavailable
            Conversation created atomically
                 │
                 ▼
            [Students arrange handover & direct payment]
                 │
                 ▼
            [Seller confirms sale completion (RPC `complete_resource_sale`)]
                 │
                 ▼
            Status: completed
            Listing State: sold
            Resource: unavailable
            Conversation: closed
```

### C. Donate Workflow
```
[Recipient submits Donation Request (`request_type=donate`)]
       │
       ▼
  Status: pending
       │
       ├──► [Owner Rejects] ──► Status: rejected
       │
       └──► [Owner Approves (RPC)]
                 │
                 ▼
            Status: approved
            Resource: reserved & unavailable
            Conversation created atomically
                 │
                 ▼
            [Students arrange handover]
                 │
                 ▼
            [Donor confirms donation completion (RPC `complete_resource_donation`)]
                 │
                 ▼
            Status: completed
            Listing State: donated
            Resource: unavailable
            Conversation: closed
```

---

## 4. Invariant Rules & Security Principles

1. **No Self-Requests:** A user cannot borrow, buy, or request a donation for their own resource (`requester_id <> owner_id`).
2. **Mutual Exclusivity:** A Sell listing cannot be borrowed. A Borrow listing cannot be sold.
3. **Single Active Approval:** At most one approved borrow or transfer request may exist for any resource simultaneously.
4. **Conversation Access:** Only conversation participants (`borrower_id` and `owner_id`) can access messages, meeting proposals, or handover details.
5. **Safe Meeting Times:** Meeting times are stored as `timestamptz` evaluated in the campus timezone `Asia/Kolkata`.
6. **Controlled Notifications:** Updates to notifications (`mark_read`) are restricted to the notification recipient via authenticated RPC, preventing malicious third-party manipulation.

