-- Roll back 20260924100000 only after the later detail-list migration has
-- been rolled back. This restores the prior private owners and the deployed
-- public group-aware wrappers. It deliberately leaves immutable raw snapshot
-- rows intact; no Closet or History data is deleted.

begin;

drop function if exists public.fitmatch_vnext_update_closet_item(uuid,jsonb);
drop function if exists fitmatch_vnext.update_closet_item(uuid,jsonb);
alter function fitmatch_vnext.update_closet_item_snapshot_base(uuid,jsonb)
    rename to update_closet_item;

create or replace function public.fitmatch_vnext_update_closet_item(
    p_closet_item_id uuid,
    p_request jsonb
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
    request_value jsonb := p_request;
    result_value jsonb;
    product_id_value uuid;
    group_tuple jsonb;
    generated_group_tuple boolean := false;
    group_value jsonb;
begin
    if request_value is not null
       and nullif(btrim(request_value ->> 'product_id'), '') is not null
       and request_value ? 'measurements' then
        product_id_value := (request_value ->> 'product_id')::uuid;
        if not request_value ? 'closet_classification_override' then
            group_tuple := fitmatch_vnext.comparison_group_tuple(
                product_id_value,
                nullif(btrim(request_value ->> 'comparison_group_code'), '')
            );
            if group_tuple is null then
                raise exception 'Comparison group selection required';
            end if;
            request_value := jsonb_set(
                request_value,
                '{closet_classification_override}',
                jsonb_build_object(
                    'audience_code', group_tuple ->> 'audience_code',
                    'category_code', group_tuple ->> 'category_code',
                    'garment_type_code', group_tuple ->> 'garment_type_code'
                ),
                true
            );
            generated_group_tuple := true;
        end if;
        result_value := fitmatch_vnext.apply_linked_closet_snapshot_for_swift(
            request_value,
            p_closet_item_id
        );
    else
        result_value := fitmatch_vnext.update_closet_item(p_closet_item_id, request_value);
        perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
            p_closet_item_id,
            request_value
        );
    end if;

    if generated_group_tuple then
        update fitmatch_vnext.closet_items
           set classification_source = case when p_request ? 'comparison_group_code'
                    then 'USER_EDITED' else 'BACKEND' end,
               classification_resolver_version = 'comparison-group-v3',
               closet_detail_code_snapshot = null
         where id = p_closet_item_id
           and user_id = auth.uid();
    end if;

    group_value := fitmatch_vnext.apply_closet_comparison_group(
        p_closet_item_id,
        nullif(btrim(p_request ->> 'comparison_group_code'), ''),
        p_request ? 'comparison_group_code'
    );
    return result_value || jsonb_build_object('comparison_group', group_value);
end
$function$;

drop function if exists public.fitmatch_vnext_list_closet_items();
drop function if exists fitmatch_vnext.list_closet_items();
alter function fitmatch_vnext.list_closet_items_snapshot_receipt_base()
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

revoke all on function fitmatch_vnext.update_closet_item(uuid,jsonb) from public, anon;
grant execute on function fitmatch_vnext.update_closet_item(uuid,jsonb)
    to authenticated, service_role;
revoke all on function public.fitmatch_vnext_update_closet_item(uuid,jsonb) from public, anon;
grant execute on function public.fitmatch_vnext_update_closet_item(uuid,jsonb)
    to authenticated, service_role;
revoke all on function fitmatch_vnext.list_closet_items() from public, anon;
grant execute on function fitmatch_vnext.list_closet_items() to authenticated, service_role;
revoke all on function public.fitmatch_vnext_list_closet_items() from public, anon;
grant execute on function public.fitmatch_vnext_list_closet_items()
    to authenticated, service_role;

commit;
