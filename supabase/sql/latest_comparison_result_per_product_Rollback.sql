begin;

drop trigger if exists comparisons_advance_result_head
on fitmatch_vnext.comparisons;
drop function if exists fitmatch_vnext.advance_comparison_result_head();

-- Restore comparison_history() from the immediately preceding deployed
-- migration before dropping the head table.
-- Source: deployed fitmatch_vnext.comparison_history() before this migration.
create or replace function fitmatch_vnext.comparison_history()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare caller_id uuid := auth.uid();
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    return coalesce((
        select jsonb_agg(
            to_jsonb(c) || jsonb_build_object(
                'reference_client_item_id', ci.client_item_id,
                'target_source_product_key', p.source_product_key,
                'target_category_code', gt.category_code
            ) order by c.created_at desc, c.id
        )
        from fitmatch_vnext.comparisons c
        left join fitmatch_vnext.closet_items ci
          on ci.id = c.reference_closet_item_id and ci.user_id = c.user_id
        left join fitmatch_vnext.products p on p.id = c.target_product_id
        left join fitmatch_vnext.garment_types gt
          on gt.garment_type_code = p.garment_type_code
        where c.user_id = caller_id
          and c.deleted_at is null
    ), '[]'::jsonb);
end
$function$;

drop table if exists fitmatch_vnext.comparison_result_heads;
commit;
