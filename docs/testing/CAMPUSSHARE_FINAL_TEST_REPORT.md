# CampusShare Final Test Report

**Execution Timestamp:** 2026-11-14 13:48:03 IST  
**Environment:** Windows 11, Node.js v24.13.1  
**Total Tests Discovered:** 88  
**Total Tests Executed:** 88  
**Passed:** 88  
**Failed:** 0  
**Skipped / Cancelled:** 0  

---

## Suite Summary

| Suite File | Tests | Passed | Failed | Status |
|---|---|---|---|---|
| `FRONTEND/tests/app.test.cjs` | 38 | 38 | 0 | **PASS** |
| `FRONTEND/tests/ui.test.cjs` | 10 | 10 | 0 | **PASS** |
| `FRONTEND/tests/communication.test.cjs` | 12 | 12 | 0 | **PASS** |
| `FRONTEND/tests/auth.test.cjs` | 28 | 28 | 0 | **PASS** |
| **Total** | **88** | **88** | **0** | **100% PASS** |

---

## Detailed Results

### 1. Application Integration (`app.test.cjs` - 38 tests)
- [PASS] signed-in dashboard loads real counts and separates borrower/owner requests
- [PASS] signed-out state hides student tools; sign-in and sign-out update navigation and dashboard
- [PASS] registration rate limits show a friendly no-retry message and concurrent submits send only once
- [PASS] signup forwards college and personal email addresses without a domain restriction
- [PASS] separate page navigation updates the URL and active item and supports back and forward
- [PASS] dedicated Sell and Donate pages filter real loaded listing modes and expose marketplace filters only when enabled
- [PASS] hamburger closes by toggle, outside click, and Escape
- [PASS] dashboard displays only the signed-in Auth profile name and empty activity state
- [PASS] page route survives refresh and protected routes redirect signed-out visitors
- [PASS] resource and dashboard loading states clear after records arrive
- [PASS] resource details loads the selected record through the authenticated API helper
- [PASS] resource detail failures render an error and do not show stale owner actions
- [PASS] browse availability/category filters, my listings, and clear filters update the rendered cards
- [PASS] browse listing-type filter separates Borrow, Sell, and Donate from material type
- [PASS] resource form validates, creates, refreshes dashboard, and reports failures
- [PASS] marketplace resource form validates sell pricing, saves handover, and displays the direct-payment notice
- [PASS] resource images validate, preview, remove, upload to Storage, and save metadata
- [PASS] saved image removal is coordinated by the authenticated backend
- [PASS] reordering saved images persists the selected primary image order
- [PASS] saved image metadata restores the primary photo and gallery in Browse and Details
- [PASS] failed Storage upload attempts are cleaned up using the same signed-in session
- [PASS] image picker and primary preview remain available in Add and Edit when marketplace fields are hidden
- [PASS] image upload can be enabled independently while marketplace fields and workflows stay disabled
- [PASS] sell requests can be submitted and then owner-approved and completed in the UI mock
- [PASS] donations require owner approval and a separate permanent handover confirmation
- [PASS] listing reports are submitted for human review without automatic account action
- [PASS] moderation controls display only for the trusted moderator claim and submit review outcomes
- [PASS] all Add Resource entry points open the form; cancel closes without submitting
- [PASS] Add Resource form opens when categories have not loaded and explains the blocker
- [PASS] category loading, population, selection, empty and API error states are explicit
- [PASS] Add Resource dropdown displays all twelve approved categories returned by the API
- [PASS] Add Resource rejects a category ID that is not in the loaded category list
- [PASS] edit and delete actions call the authenticated API and refresh owned listings
- [PASS] edit and delete failures surface safe user-facing messages without crashing
- [PASS] borrow and owner status actions stay hidden when feature flags are off and appear only for an owner when enabled
- [PASS] borrow creation and owner status controls refresh lists after successful actions
- [PASS] borrow request API failure is visible without fabricating a request
- [PASS] empty results and request failures render messages instead of stale empty stats

### 2. UI Model Helpers (`ui.test.cjs` - 10 tests)
- [PASS] resource discovery filters search, category, type, availability, and owner
- [PASS] resource discovery can independently filter Borrow, Sell, and Donate listing modes
- [PASS] marketplace discovery filters INR price ranges and sale condition, and sorts by price
- [PASS] dashboard totals and recent listings use only returned records
- [PASS] marketplace dashboard counts only active listings and completed transactions
- [PASS] borrow actions require availability, a different owner, and enabled flags
- [PASS] owner status controls are feature-gated and match the request state
- [PASS] resource form validates required schema-backed fields
- [PASS] page contains dashboard, separate Borrow/Sell/Donate views, price filters, personal listings, and request sections
- [PASS] every statically referenced app element exists in the page

### 3. Borrowing Communication (`communication.test.cjs` - 12 tests)
- [PASS] ui.conversationRole correctly distinguishes borrower and owner roles
- [PASS] ui.conversationPartnerName displays partner's name accurately
- [PASS] ui.activeMeetingProposal filters the active pending proposal
- [PASS] ui.confirmedMeeting identifies accepted meeting
- [PASS] ui.formatMeetingTimeIST formats 24h times to readable IST notation
- [PASS] ui.ownerRequestActions allows return on return_requested and approved states
- [PASS] CampusShareApi communication endpoints format URLs and JSON payloads correctly
- [PASS] index.html contains all communication layout, sidebar, thread and meeting elements
- [PASS] style.css contains responsive styles for communication layout and chat bubbles
- [PASS] communication validation: empty message and invalid parameters are rejected
- [PASS] meeting proposal validation: requires valid type, date, time and location
- [PASS] meeting response validation: requires valid action

### 4. Authentication & Security (`auth.test.cjs` - 28 tests)
- [PASS] frontend configuration exposes string project and API settings
- [PASS] valid local frontend configuration overrides defaults without logging key values
- [PASS] placeholder local key is ignored safely and never appears in diagnostics
- [PASS] Supabase Auth adapter uses v2 email/password methods and restores a session
- [PASS] resource image Storage uses the user's configured Supabase client and private bucket
- [PASS] category and resource GET calls send the current session Bearer token
- [PASS] a valid login session is the same session used by the category request
- [PASS] a rejected expired token is refreshed once and the new token is retried
- [PASS] backend Auth rejection after refresh is reported safely and does not retry indefinitely
- [PASS] an expired session that cannot refresh prompts login and does not retry the API
- [PASS] categories API accepts empty results, returns categories, and reports upstream failure (3 subtests)
- [PASS] resource details uses the authenticated detail route and validates its one-row response (2 subtests)
- [PASS] resource CRUD and borrowing API methods use the authenticated backend routes
- [PASS] marketplace APIs use authenticated backend routes and preserve request payloads
- [PASS] missing config and missing session prevent authenticated API requests (2 subtests)
- [PASS] missing Supabase configuration notice is outside the login dialog
- [PASS] health API returns backend RPC feature flags without authentication
- [PASS] API helper reports malformed JSON and HTTP errors (3 subtests)

