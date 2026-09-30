-- Preserve an explicit Closet display-detail separately from the server's
-- canonical garment family.  This migration only extends the existing list
-- projection; group authority and canonical comparison policy stay unchanged.

begin;

do $preflight$
begin
    if not exists (
        select 1
        from pg_attribute
        where attrelid = 'fitmatch_vnext.closet_items'::regclass
          and attname = 'closet_detail_code_snapshot'
          and not attisdropped
    ) then
        raise exception 'Missing closet_detail_code_snapshot column';
    end if;
    if to_regprocedure(
        'fitmatch_vnext.set_closet_detail_snapshot_for_swift(uuid,jsonb)'
    ) is null then
        raise exception 'Missing Closet detail snapshot writer';
    end if;
end
$preflight$;

do $rename_list_owner$
begin
    if to_regprocedure('fitmatch_vnext.list_closet_items_detail_snapshot_base()') is null then
        if to_regprocedure('fitmatch_vnext.list_closet_items()') is null then
            raise exception 'Missing Closet list preimage';
        end if;
        alter function fitmatch_vnext.list_closet_items()
            rename to list_closet_items_detail_snapshot_base;
    end if;
end
$rename_list_owner$;

create or replace function fitmatch_vnext.list_closet_items()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    prior_items jsonb;
begin
    prior_items := fitmatch_vnext.list_closet_items_detail_snapshot_base();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'closet_detail_code_snapshot', (
                select nullif(btrim(ci.closet_detail_code_snapshot), '')
                from fitmatch_vnext.closet_items ci
                where ci.id = (item ->> 'id')::uuid
            )
        ) order by ordinal)
        from jsonb_array_elements(coalesce(prior_items, '[]'::jsonb))
            with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$;

-- Rebind the public bridge after its private dependency was renamed. The
-- existing comparison-group projection is retained exactly as before.
create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
    result_value jsonb;
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

revoke all on function fitmatch_vnext.list_closet_items() from public, anon;
grant execute on function fitmatch_vnext.list_closet_items() to authenticated, service_role;
revoke all on function public.fitmatch_vnext_list_closet_items() from public, anon;
grant execute on function public.fitmatch_vnext_list_closet_items()
    to authenticated, service_role;

commit;
