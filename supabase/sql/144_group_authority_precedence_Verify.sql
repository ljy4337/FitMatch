begin;
select set_config(
 'request.jwt.claim.sub',
 (select user_id::text from fitmatch_vnext.closet_items
  where deleted_at is null and comparison_group_code='A'
  order by created_at limit 1),true
);

select p.source_code,p.source_product_key,
       e.value->>'detail_classification_status' detail_status,
       e.value->>'classification_status' effective_status,
       e.value->>'effective_source' effective_source,
       e.value->>'comparison_group_code' group_code
from fitmatch_vnext.products p
cross join lateral (
 select fitmatch_vnext.effective_target_classification(p.id) value
) e
where (p.source_code,p.source_product_key) in (
 ('uniqlo','E487939'),('uniqlo','E465185'),('zara','550429724')
)
order by p.source_code,p.source_product_key;

rollback;
