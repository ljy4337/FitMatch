begin;

delete from fitmatch_catalog.product_comparison_group_overrides
where policy_version = 'retailer-comparison-groups-v2-single-20260911';

delete from fitmatch_catalog.source_category_comparison_groups
where policy_version = 'retailer-comparison-groups-v2-single-20260911';

delete from fitmatch_catalog.comparison_group_policies
where policy_version = 'retailer-comparison-groups-v2-single-20260911';

commit;

select
  to_regclass('fitmatch_catalog.product_comparison_group_overrides') is not null
    as override_table_preserved,
  count(*) filter (where policy_version = 'retailer-comparison-groups-v1-20260911')
    as v1_policy_count,
  count(*) filter (where policy_version = 'retailer-comparison-groups-v2-single-20260911')
    as v2_policy_count
from fitmatch_catalog.comparison_group_policies;
