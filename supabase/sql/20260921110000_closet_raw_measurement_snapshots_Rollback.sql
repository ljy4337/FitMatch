-- Recovery for 20260921110000_closet_raw_measurement_snapshots.sql.
-- It refuses to erase any immutable source snapshot or retained nonpositive
-- retailer fact. Archive/migrate those rows before attempting recovery.

begin;

do $guard_snapshot_data$
begin
    if exists (select 1 from fitmatch_vnext.closet_item_source_measurement_snapshots)
       or exists (select 1 from fitmatch_vnext.closet_item_source_measurements) then
        raise exception 'Cannot roll back while Closet source snapshots exist';
    end if;
    if exists (
        select 1 from fitmatch_vnext.product_size_measurements
        where raw_value <= 0
    ) then
        raise exception 'Cannot roll back while retained nonpositive raw facts exist';
    end if;
end
$guard_snapshot_data$;

-- Public functions must detach from the replacement OIDs before restoration.
create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base(p_request)
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare result_value jsonb;
begin
    result_value := fitmatch_vnext.list_closet_items_snapshot_base();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'comparison_group', fitmatch_vnext.closet_comparison_group((item ->> 'id')::uuid)
        ) order by ordinal)
        from jsonb_array_elements(result_value) with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$;

drop function fitmatch_vnext.upsert_closet_item_with_group_for_swift(jsonb);
drop function fitmatch_vnext.list_closet_items();
alter function fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base(jsonb)
    rename to upsert_closet_item_with_group_for_swift;
alter function fitmatch_vnext.list_closet_items_snapshot_base()
    rename to list_closet_items;

-- Restore the exact deployed group bridges, not the pre-group private APIs.
create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.upsert_closet_item_with_group_for_swift(p_request)
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare result_value jsonb;
begin
    result_value := fitmatch_vnext.list_closet_items();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'comparison_group', fitmatch_vnext.closet_comparison_group((item ->> 'id')::uuid)
        ) order by ordinal)
        from jsonb_array_elements(result_value) with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$;

do $restore_raw_validation$
declare
    definition text;
    old_multiline_clause text := 'where m.product_size_id = p_product_size_id' || E'\n'
        || '      and m.is_current' || E'\n' || '      and m.raw_value > 0';
    new_multiline_clause text := 'where m.product_size_id = p_product_size_id' || E'\n'
        || '      and m.is_current';
    old_inline_clause text := 'where m.product_size_id = p_product_size_id and m.is_current'
        || E'\n' || '      and m.raw_value > 0';
    new_inline_clause text := 'where m.product_size_id = p_product_size_id and m.is_current';
    procedure_name regprocedure;
begin
    select pg_get_functiondef(
        'fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)'::regprocedure
    ) into definition;
    if position('if raw_value_value is null' in definition) = 0
       or position('Measurement requires a numeric value and code or label' in definition) = 0 then
        raise exception 'Unexpected ingestion rollback preimage';
    end if;
    definition := replace(definition,
        'if raw_value_value is null',
        'if raw_value_value is null or raw_value_value <= 0');
    definition := replace(definition,
        'Measurement requires a numeric value and code or label',
        'Measurement requires a positive value and code or label');
    execute definition;

    foreach procedure_name in array array[
        'fitmatch_vnext.canonical_measurements_for_size(uuid)'::regprocedure,
        'fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)'::regprocedure
    ] loop
        select pg_get_functiondef(procedure_name) into definition;
        if position(old_multiline_clause in definition) > 0 then
            execute replace(definition, old_multiline_clause, new_multiline_clause);
        elsif position(old_inline_clause in definition) > 0 then
            execute replace(definition, old_inline_clause, new_inline_clause);
        else
            raise exception 'Unexpected canonical rollback preimage for %', procedure_name;
        end if;
    end loop;
end
$restore_raw_validation$;

drop table fitmatch_vnext.closet_item_source_measurements;
drop table fitmatch_vnext.closet_item_source_measurement_snapshots;

revoke all on function public.fitmatch_vnext_upsert_closet_item(jsonb) from public, anon;
grant execute on function public.fitmatch_vnext_upsert_closet_item(jsonb)
    to authenticated, service_role;
revoke all on function public.fitmatch_vnext_list_closet_items() from public, anon;
grant execute on function public.fitmatch_vnext_list_closet_items()
    to authenticated, service_role;

commit;
