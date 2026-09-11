with mappings as (
  select *
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v2-single-20260911'
), provider_counts as (
  select source_code, count(*) as category_count
  from mappings
  group by source_code
), override_counts as (
  select source_code, count(*) as override_count
  from fitmatch_catalog.product_comparison_group_overrides
  where policy_version = 'retailer-comparison-groups-v2-single-20260911'
  group by source_code
)
select
  policy.policy_version,
  policy.status,
  policy.source_checksum_sha256,
  count(*) as category_node_count,
  count(distinct (mappings.source_code, mappings.source_category_key)) as distinct_category_node_count,
  (select jsonb_object_agg(source_code, category_count order by source_code) from provider_counts)
    as provider_category_counts,
  (select coalesce(sum(override_count), 0) from override_counts) as product_override_count
from fitmatch_catalog.comparison_group_policies policy
join mappings on true
where policy.policy_version = 'retailer-comparison-groups-v2-single-20260911'
group by policy.policy_version, policy.status, policy.source_checksum_sha256;
