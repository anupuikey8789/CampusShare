-- Fix return_borrowed_resource RPC
-- Resolves PostgreSQL runtime error: "record v_res is not assigned yet"
-- Enables resource owners to successfully confirm returns on approved or return_requested items

CREATE OR REPLACE FUNCTION public.return_borrowed_resource(p_request_id bigint)
RETURNS SETOF public.borrow_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := (SELECT auth.uid());
    v_is_anonymous boolean := COALESCE((SELECT (auth.jwt()->>'is_anonymous')::boolean), true);
    v_resource_id bigint;
    v_owner uuid;
    v_request public.borrow_requests%ROWTYPE;
BEGIN
    IF v_actor IS NULL OR v_is_anonymous THEN
        RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='Authentication required';
    END IF;
    IF p_request_id IS NULL OR p_request_id <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Invalid request ID';
    END IF;

    SELECT b.resource_id INTO v_resource_id
    FROM public.borrow_requests AS b WHERE b.id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Request not found';
    END IF;

    SELECT r.owner_id INTO v_owner
    FROM public.resources AS r WHERE r.id = v_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Resource not found';
    END IF;

    SELECT b.* INTO v_request
    FROM public.borrow_requests AS b WHERE b.id = p_request_id FOR UPDATE;
    IF NOT FOUND OR v_request.resource_id <> v_resource_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request changed; retry after refresh';
    END IF;

    IF v_owner <> v_actor THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Only the resource owner may return this request';
    END IF;
    IF v_request.status NOT IN ('approved', 'return_requested') THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Request is not active';
    END IF;

    UPDATE public.resources
    SET availability_status = 'available'
    WHERE id = v_resource_id AND owner_id = v_actor;

    RETURN QUERY
    UPDATE public.borrow_requests AS b
    SET status = 'returned', returned_at = clock_timestamp()
    WHERE b.id = p_request_id AND b.status IN ('approved', 'return_requested')
    RETURNING b.*;
END;
$function$;

ALTER FUNCTION public.return_borrowed_resource(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.return_borrowed_resource(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.return_borrowed_resource(bigint) TO authenticated;
