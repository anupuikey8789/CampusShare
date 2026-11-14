# CampusShare Quality Assurance & Test Plan

**Test Engine:** Node.js native test runner (`node --test`)  
**Directory:** `FRONTEND/tests/`

---

## 1. Test Suite Breakdown

### A. `FRONTEND/tests/app.test.cjs` (38 Tests)
- **Coverage:** Full application workflow integration, DOM event handling, SPA navigation, forms, image uploads, marketplace features, and error handling.
- **Key Scenarios:**
  - Navigation between views (`#browse`, `#sell`, `#donate`, `#my-resources`, `#borrowing`, `#marketplace-requests`, `#messages`).
  - Add Resource modal validation and category dropdown population.
  - Multi-image drag-and-drop validation (MIME types, 5MB limit, 10 images max).
  - Borrow request creation and owner status updates.
  - Marketplace sell/donate transfer requests and completions.
  - Moderation controls and listing report submissions.

### B. `FRONTEND/tests/ui.test.cjs` (10 Tests)
- **Coverage:** Pure unit testing of UI models, filters, sorting, and metrics calculations in `FRONTEND/ui-model.js`.
- **Key Scenarios:**
  - Resource filtering across search terms, categories, availability, and listing modes.
  - INR price range filtering and condition filtering.
  - Calculation of dashboard metrics without pagination truncation.
  - Verification of static DOM element existence.

### C. `FRONTEND/tests/communication.test.cjs` (12 Tests)
- **Coverage:** Borrowing communication system helpers, API client formats, input validation, and responsive style definitions.
- **Key Scenarios:**
  - Role calculation (`owner`, `borrower`, or `null` for third parties).
  - Partner display names.
  - Active proposal and confirmed meeting detection.
  - IST time formatting (`ui.formatMeetingTimeIST`).
  - Owner request action visibility in `return_requested` status.
  - API endpoint payload and URL structures.
  - Client-side input validation on messages, meetings, and responses.
  - CSS layout and bubble classes presence.

### D. `FRONTEND/tests/auth.test.cjs` (28 Tests)
- **Coverage:** Authentication lifecycle, JWT access tokens, refresh tokens, error mapping, and health check contract.
- **Key Scenarios:**
  - Token injection via `Bearer` header.
  - Automatic retry with refreshed token on 401.
  - Session restoration and sign-out handling.
  - Backend health check contract validation (`api_version`, `build_id`, `features`).
  - Safe error propagation without leaking private credentials.

---

## 2. Test Execution Command

Run all tests in one sequence:
```powershell
node FRONTEND/tests/app.test.cjs; node FRONTEND/tests/ui.test.cjs; node FRONTEND/tests/communication.test.cjs; node FRONTEND/tests/auth.test.cjs
```
**Total Passing Tests:** 88 / 88 (100% Pass Rate).

