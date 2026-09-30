begin;
select set_config(
  'request.jwt.claim.sub',
  (select user_id::text from fitmatch_vnext.closet_items
   where deleted_at is null order by created_at limit 1),true
);
with target as (
  select p.id product_id,(select pv.id from fitmatch_vnext.product_variants pv
    where pv.product_id=p.id order by pv.sort_order,pv.id limit 1) variant_id
  from fitmatch_vnext.products p
  where p.source_code='uniqlo' and p.source_product_key='E487939'
), result as (
  select public.fitmatch_vnext_find_reference_candidates(product_id,variant_id) value
  from target
)
select value->>'status' status,
       value->'comparison_group' target_group,
       value->>'same_group_count' same_group_count,
       value->>'measurements_used_for_candidate_selection' measurements_used,
       jsonb_array_length(value->'candidates') candidate_count,
       jsonb_array_length(value->'fallback_closet_items') fallback_count
from result;
rollback;
