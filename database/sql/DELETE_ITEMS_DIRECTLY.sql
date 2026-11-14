-- ============================================================================
-- CAMPUSSHARE — COMPLETE CASCADE REMOVAL SCRIPT FOR UNWANTED / TEST LISTINGS
-- Removes: notes (id 2), book (id 5), Lifecycle Test Item (id 11), Direct RPC Test (id 12)
-- Handles all conversation, message, proposal, and borrow request foreign keys.
-- Run in Supabase SQL Editor: https://supabase.com/dashboard/project/jxndjuslvccxgayoachm/sql
-- ============================================================================

BEGIN;

-- 1. Delete messages and meeting proposals belonging to affected conversations
DELETE FROM public.messages
WHERE conversation_id IN (
    SELECT id FROM public.conversations
    WHERE resource_id IN (2, 5, 11, 12)
       OR borrow_request_id IN (SELECT id FROM public.borrow_requests WHERE resource_id IN (2, 5, 11, 12))
);

DELETE FROM public.meeting_proposals
WHERE conversation_id IN (
    SELECT id FROM public.conversations
    WHERE resource_id IN (2, 5, 11, 12)
       OR borrow_request_id IN (SELECT id FROM public.borrow_requests WHERE resource_id IN (2, 5, 11, 12))
);

-- 2. Delete conversations referencing these resources or borrow requests
DELETE FROM public.conversations
WHERE resource_id IN (2, 5, 11, 12)
   OR borrow_request_id IN (SELECT id FROM public.borrow_requests WHERE resource_id IN (2, 5, 11, 12));

-- 3. Delete borrow requests
DELETE FROM public.borrow_requests WHERE resource_id IN (2, 5, 11, 12);

-- 4. Delete transfer requests, handover details, images, and reports
DELETE FROM public.resource_transfer_requests WHERE resource_id IN (2, 5, 11, 12);
DELETE FROM public.resource_handover_details WHERE resource_id IN (2, 5, 11, 12);
DELETE FROM public.resource_images WHERE resource_id IN (2, 5, 11, 12);
DELETE FROM public.resource_listing_reports WHERE resource_id IN (2, 5, 11, 12);

-- 5. Finally delete the resource listings
DELETE FROM public.resources WHERE id IN (2, 5, 11, 12);

COMMIT;

-- Verify all 4 are permanently removed:
SELECT id, title FROM public.resources WHERE id IN (2, 5, 11, 12);
