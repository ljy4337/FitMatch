begin;

do $preflight$
begin
    if to_regprocedure(
        'fitmatch_vnext.product_measurement_readiness(uuid,jsonb)'
    ) is null then
        raise exception 'product_measurement_readiness(uuid,jsonb) is missing';
    end if;
    if to_regprocedure(
        'fitmatch_vnext.effective_target_classification(uuid)'
    ) is null then
        raise exception 'effective_target_classification(uuid) is missing';
    end if;
end
$preflight$;

-- Classification authority and measurement readiness are separate contracts.
-- A confirmed category group must retain its authority while sizes, canonical
-- measurements, structure, or policy readiness remain fail-closed.
create or replace function fitmatch_vnext.product_readiness_with_context(
    p_product_id uuid,
    p_effective_classification jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
    select fitmatch_vnext.product_measurement_readiness(
        p_product_id,
        p_effective_classification
    )
$function$;

create or replace function fitmatch_vnext.effective_product_readiness(
    p_product_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
    select fitmatch_vnext.product_measurement_readiness(
        p_product_id,
        fitmatch_vnext.effective_target_classification(p_product_id)
    )
$function$;

alter function fitmatch_vnext.product_readiness_with_context(uuid,jsonb)
    owner to postgres;
alter function fitmatch_vnext.effective_product_readiness(uuid)
    owner to postgres;

revoke all on function fitmatch_vnext.product_readiness_with_context(uuid,jsonb)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.product_readiness_with_context(uuid,jsonb)
    to service_role;
revoke all on function fitmatch_vnext.effective_product_readiness(uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.effective_product_readiness(uuid)
    to service_role;

do $postflight$
declare
    definition text;
begin
    definition := pg_get_functiondef(
        'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure
    );
    if definition not like '%product_measurement_readiness%' then
        raise exception 'Context readiness is not measurement-readiness based';
    end if;

    definition := pg_get_functiondef(
        'fitmatch_vnext.effective_product_readiness(uuid)'::regprocedure
    );
    if definition not like '%product_measurement_readiness%'
       or definition not like '%effective_target_classification%' then
        raise exception 'Effective readiness contract was not aligned';
    end if;
end
$postflight$;

commit;
