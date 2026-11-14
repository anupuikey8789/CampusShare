-- PROPOSAL ONLY: behavior-level reconstruction for a fresh CampusShare-Staging
-- project. Never execute against production. This is not a byte-for-byte copy
-- of the audited function source; that source is not in this repository.
-- The audit records NEW.id, NEW.email, and raw_user_meta_data.full_name with an
-- empty-name fallback. The SQL below makes that inferred behavior explicit.
-- Review assumptions in SUPABASE_TASK_4B_REPORT.md before staging use.

DO $preflight$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Run only as the staging postgres owner so the new function can have the audited owner';
    END IF;
    IF to_regclass('auth.users') IS NULL OR to_regclass('public.profiles') IS NULL THEN
        RAISE EXCEPTION 'Expected staging Auth and profiles tables are missing';
    END IF;
    IF to_regprocedure('public.handle_new_user()') IS NOT NULL THEN
        RAISE EXCEPTION 'handle_new_user already exists; inspect it instead of replacing it';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'auth.users'::regclass
          AND tgname = 'on_auth_user_created'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'on_auth_user_created already exists; inspect it instead of replacing it';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'auth' AND table_name = 'users' AND column_name = 'id'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'auth' AND table_name = 'users' AND column_name = 'email'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'auth' AND table_name = 'users' AND column_name = 'raw_user_meta_data'
    ) THEN
        RAISE EXCEPTION 'Expected Auth user fields are missing; inspect staging before continuing';
    END IF;
END
$preflight$;

BEGIN;

CREATE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    INSERT INTO public.profiles (id, full_name, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
        NEW.email
    );
    RETURN NEW;
END
$function$;

-- New object only; the preflight refuses to modify an existing definition.
ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

-- Create the trigger while running as its owner, then remove direct execution
-- from API roles. Only this newly created function is affected by this file.
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

REVOKE ALL PRIVILEGES ON FUNCTION public.handle_new_user()
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
