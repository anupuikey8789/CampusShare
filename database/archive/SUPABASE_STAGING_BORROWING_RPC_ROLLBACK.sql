-- STAGING ONLY. Rollback proposal for SUPABASE_STAGING_BORROWING_RPC_MIGRATION.sql.
-- Codex did not execute this file. Never run against production.
--
-- Before applying: stop/disable the RPC-capable backend or set all three RPC flags
-- false and restart it. Confirm requests are no longer reaching these routines.
-- This rollback drops only routines carrying the Task 8 migration comment marker.
-- It drops the active-pair index only when this migration created and marked it.
-- An equivalent index that existed before this migration is retained.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
BEGIN
    IF to_regprocedure('public.create_borrow_request(bigint,timestamp with time zone)') IS NULL
       OR to_regprocedure('public.approve_borrow_request(bigint,timestamp with time zone)') IS NULL
       OR to_regprocedure('public.reject_borrow_request(bigint)') IS NULL
       OR to_regprocedure('public.return_borrowed_resource(bigint)') IS NULL
       OR to_regprocedure('public.update_resource_atomic(bigint,jsonb)') IS NULL THEN
        RAISE EXCEPTION 'One or more Task 8 routines are absent; inspect partial migration state manually';
    END IF;

    IF obj_description(to_regprocedure('public.create_borrow_request(bigint,timestamp with time zone)'), 'pg_proc')
           IS DISTINCT FROM 'CampusShare staging Task 8 RPC migration v1'
       OR obj_description(to_regprocedure('public.approve_borrow_request(bigint,timestamp with time zone)'), 'pg_proc')
           IS DISTINCT FROM 'CampusShare staging Task 8 RPC migration v1'
       OR obj_description(to_regprocedure('public.reject_borrow_request(bigint)'), 'pg_proc')
           IS DISTINCT FROM 'CampusShare staging Task 8 RPC migration v1'
       OR obj_description(to_regprocedure('public.return_borrowed_resource(bigint)'), 'pg_proc')
           IS DISTINCT FROM 'CampusShare staging Task 8 RPC migration v1'
       OR obj_description(to_regprocedure('public.update_resource_atomic(bigint,jsonb)'), 'pg_proc')
           IS DISTINCT FROM 'CampusShare staging Task 8 RPC migration v1' THEN
        RAISE EXCEPTION 'Routine comment marker differs; refuse automatic rollback';
    END IF;
END
$preflight$;

REVOKE ALL PRIVILEGES ON FUNCTION public.create_borrow_request(bigint,timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.approve_borrow_request(bigint,timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.reject_borrow_request(bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.update_resource_atomic(bigint,jsonb) FROM PUBLIC, anon, authenticated, service_role;

DROP FUNCTION public.create_borrow_request(bigint,timestamptz);
DROP FUNCTION public.approve_borrow_request(bigint,timestamptz);
DROP FUNCTION public.reject_borrow_request(bigint);
DROP FUNCTION public.return_borrowed_resource(bigint);
DROP FUNCTION public.update_resource_atomic(bigint,jsonb);

DO $index_rollback$
BEGIN
    IF to_regclass('public.one_active_request_per_borrower_resource') IS NOT NULL
       AND obj_description(
           'public.one_active_request_per_borrower_resource'::regclass, 'pg_class'
       ) = 'CampusShare staging Task 8 RPC migration v1' THEN
        EXECUTE 'DROP INDEX public.one_active_request_per_borrower_resource';
    END IF;
END
$index_rollback$;

COMMIT;
