-- Roll back 20260924101000 before rolling back 20260924100000. This removes
-- only the list projection wrapper. Stored detail snapshots remain intact so
-- a later re-apply can expose the same exact user selection.

begin;

drop function if exists public.fitmatch_vnext_list_closet_items();
drop function if exists fitmatch_vnext.list_closet_items();
alter function fitmatch_vnext.list_closet_items_detail_snapshot_base()
    rename to list_closet_items;

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
