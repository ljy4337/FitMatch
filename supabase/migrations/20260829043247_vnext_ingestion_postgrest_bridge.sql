-- FitMatch vNext ingress bridge for the public PostgREST schema.
-- The Edge Function remains the authenticated transport boundary. This wrapper
-- contains no classification logic and delegates exclusively to the service-only
-- fitmatch_vnext ingestion authority.
-- Data impact: none.
-- Rollback:
--   drop function public.fitmatch_vnext_ingest_product_observation(jsonb, uuid);

create or replace function public.fitmatch_vnext_ingest_product_observation(
    p_payload jsonb,
    p_actor_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
    if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Service role required';
    end if;

    return fitmatch_vnext.ingest_product_observation(p_payload, p_actor_id);
end
$function$;

revoke all on function public.fitmatch_vnext_ingest_product_observation(jsonb, uuid)
    from public, anon, authenticated;
grant execute on function public.fitmatch_vnext_ingest_product_observation(jsonb, uuid)
    to service_role;

comment on function public.fitmatch_vnext_ingest_product_observation(jsonb, uuid)
is 'Service-role-only PostgREST transport bridge to fitmatch_vnext.ingest_product_observation; contains no classification authority.';

do $verify$
declare
    function_oid oid;
    function_config text[];
begin
    function_oid := to_regprocedure(
        'public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'
    );
    if function_oid is null then
        raise exception 'vNext ingestion transport bridge is missing';
    end if;

    select proconfig into function_config
    from pg_proc
    where oid = function_oid;

    if not coalesce(function_config @> array['search_path=""'], false) then
        raise exception 'vNext ingestion transport bridge search_path is not fixed';
    end if;
    if has_function_privilege('anon', function_oid, 'EXECUTE')
       or has_function_privilege('authenticated', function_oid, 'EXECUTE') then
        raise exception 'vNext ingestion transport bridge is exposed to client roles';
    end if;
    if not has_function_privilege('service_role', function_oid, 'EXECUTE') then
        raise exception 'vNext ingestion transport bridge is unavailable to service_role';
    end if;
end
$verify$;;
