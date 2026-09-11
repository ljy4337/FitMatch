select
  position('CATEGORY_GROUP' in pg_get_functiondef(p.oid)) > 0
    as category_group_context_enabled,
  md5(pg_get_functiondef(p.oid)) as body_md5
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='fitmatch_vnext'
  and p.proname='canonical_measurements_for_size_with_context';

begin;
select set_config(
  'request.jwt.claim.sub',
  (select user_id::text from fitmatch_vnext.closet_items
   where deleted_at is null order by created_at limit 1), true
);

with target as (
  select p.id product_id, s.id size_id,
         fitmatch_vnext.effective_target_classification(p.id) effective
  from fitmatch_vnext.products p
  join fitmatch_vnext.product_variants v on v.product_id=p.id
  join fitmatch_vnext.product_sizes s on s.variant_id=v.id
  where p.source_code='uniqlo'
    and p.source_product_key='E487939'
    and v.source_variant_key='10'
  order by s.sort_order nulls last, s.id
  limit 1
), result as (
  select product_id, size_id, effective,
         fitmatch_vnext.canonical_measurements_for_size_with_context(
           size_id, effective
         ) measurements
  from target
)
select
  effective->>'effective_source' as effective_source,
  effective->>'comparison_group_code' as group_code,
  measurements->>'classification_context_source' as measurement_context_source,
  (measurements->>'raw_measurement_count')::int as raw_measurement_count,
  jsonb_array_length(measurements->'measurements') as canonical_measurement_count,
  (measurements->>'unresolved_count')::int as unresolved_count
from result;

rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  (select user_id::text from fitmatch_vnext.closet_items
   where deleted_at is null and comparison_group_code='A'
   order by created_at limit 1), true
);

with reference_item as materialized (
  select id
  from fitmatch_vnext.closet_items
  where user_id=auth.uid() and deleted_at is null
    and comparison_group_code='A'
  order by is_reference desc, created_at
  limit 1
), target as materialized (
  select p.id product_id, v.id variant_id
  from fitmatch_vnext.products p
  join fitmatch_vnext.product_variants v on v.product_id=p.id
  where p.source_code='uniqlo' and p.source_product_key='E487939'
    and v.source_variant_key='10'
  limit 1
), eligible as materialized (
  select public.fitmatch_vnext_eligible_candidate_sizes(
    reference_item.id, target.product_id, target.variant_id, true
  ) value
  from reference_item, target
), request as materialized (
  select jsonb_build_object(
    'client_comparison_id', gen_random_uuid(),
    'reference_closet_item_id', reference_item.id,
    'target_product_id', target.product_id,
    'target_variant_id', target.variant_id,
    'authorization_product_size_id',
      eligible.value->'authorized_candidate_product_size_ids'->>0,
    'manual_explicit', true,
    'candidate_product_size_ids',
      eligible.value->'authorized_candidate_product_size_ids'
  ) value
  from reference_item, target, eligible
), first_call as materialized (
  select public.fitmatch_vnext_begin_comparison(request.value) value
  from request
), retry_call as materialized (
  select public.fitmatch_vnext_begin_comparison(request.value) value
  from request, first_call
)
select
  (eligible.value->>'allowed')::boolean as eligible_allowed,
  jsonb_array_length(eligible.value->'candidates') as eligible_size_count,
  eligible.value->>'classification_source' as classification_source,
  first_call.value->>'created' as first_created,
  retry_call.value->>'idempotent' as retry_idempotent,
  first_call.value->>'comparison_id' = retry_call.value->>'comparison_id'
    as retry_same_comparison
from eligible, first_call, retry_call;

rollback;
