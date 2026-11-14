# CampusShare Supabase Correction Plan

Proposed only for production project dkyfkdmlkghucyepxbbh. Nothing executed. Re-run [audit](SUPABASE_READ_ONLY_AUDIT.sql), rehearse on staging, obtain explicit approval. Grants and RLS are separate controls ([Supabase RLS guide](https://supabase.com/docs/guides/database/postgres/row-level-security)).

## P0: Request INSERT
Replace borrower-only INSERT check with: borrower_id=auth.uid(); status=pending; returned_at NULL; matching available resource owned by another user; no existing same-borrower pending/approved request. Existing resource SELECT true and request own-row SELECT support checks; verify no RLS recursion in staging. Add unique partial index (borrower_id,resource_id) WHERE status=pending. Recheck before build; never auto-delete duplicates. Different borrowers may have pending requests simultaneously. Keep existing approved-only unique index; the approval function locks the shared resource row.

## P0: definer RPC access
Three lifecycle RPCs already mutate status though table UPDATE is absent. Bodies check identity, ownership, status and lock rows, but EXECUTE is granted to PUBLIC/anon/authenticated. Until product owner approves actors/transitions, revoke all four roles from these functions. Do not grant table UPDATE. Later grant only approved RPCs to authenticated after two-user tests. Return currently requires the resource owner. Narrow execute on SECURITY DEFINER is recommended by [Supabase Database Functions docs](https://supabase.com/docs/guides/database/functions).
Revoke direct execute on handle_new_user, preserve trigger, test signup in staging. Empty search_path and qualified tables are good; no function replacement.

## P1: least privilege
Revoke PUBLIC/anon/authenticated table privileges, then grant profiles none (no app endpoint); categories SELECT; resources SELECT, INSERT columns title/description/category_id/owner_id/resource_type/availability_status, UPDATE columns title/description/category_id/resource_type/availability_status, DELETE; borrow_requests SELECT/INSERT. Matches current resource API and blocks direct id/owner/created_at edits. Keep owner RLS.
Current request POST sends status/requested_at/returned_at, so retain table INSERT with strict policy. Future column INSERT (resource_id,borrower_id,due_at) needs backend to omit system fields/use confirmed defaults first. Auth trigger provisions profiles, so direct profile INSERT is not needed.

## P1/P2
Create concurrently, outside transaction: resources(category_id), resources(owner_id), borrow_requests(borrower_id), borrow_requests(resource_id), unique partial borrow_requests(borrower_id,resource_id) WHERE status=pending. Performance Advisor found first three; resource_id index is partial. Recheck data. Concurrent build may leave invalid index on failure; inspect before any separately approved cleanup.
Keep the two request SELECT policies unless tests prove a merged borrower-OR-owner rule equivalent. NO ACTION FKs mean referenced resources/categories cannot be deleted; preserve request history. Validate full_name in signup UI; defer database constraint.

Execution order: stage; apply grants/policy/function ACL transaction; verify signup trigger; build indexes separately; run allow/deny and two-user tests/advisors. No production changes have been made.
