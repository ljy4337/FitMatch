with mapping_totals as (
  select
    count(distinct (source_code, source_category_key)) as category_node_count,
    count(*) as group_membership_count
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v1-20260911'
), provider_totals as (
  select
    source_code,
    count(distinct source_category_key) as category_count
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v1-20260911'
  group by source_code
), provider_json as (
  select jsonb_object_agg(source_code, category_count order by source_code)
    as provider_category_counts
  from provider_totals
)
select
  policy.policy_version,
  policy.status,
  policy.source_checksum_sha256,
  mapping_totals.category_node_count,
  mapping_totals.group_membership_count,
  provider_json.provider_category_counts
from fitmatch_catalog.comparison_group_policies policy
cross join mapping_totals
cross join provider_json
where policy.policy_version = 'retailer-comparison-groups-v1-20260911';
