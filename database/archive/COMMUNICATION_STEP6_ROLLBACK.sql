-- ============================================================================
-- CAMPUSSHARE BORROWING COMMUNICATION SYSTEM — STEP 6 ROLLBACK
-- Target: Supabase PostgreSQL (Staging: jxndjuslvccxgayoachm)
-- Description: Restores borrow_requests constraints and baseline return function.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.request_return(uuid);

ALTER TABLE public.borrow_requests
    DROP CONSTRAINT IF EXISTS chk_borrow_requests_status;

ALTER TABLE public.borrow_requests
    ADD CONSTRAINT chk_borrow_requests_status
    CHECK (status IN ('pending', 'approved', 'rejected', 'returned'));

DROP INDEX IF EXISTS public.idx_borrow_requests_one_active;

CREATE UNIQUE INDEX one_active_request_per_borrower_resource
    ON public.borrow_requests (borrower_id, resource_id)
    WHERE status IN ('pending', 'approved');

COMMIT;

