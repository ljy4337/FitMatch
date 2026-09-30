begin;

delete from fitmatch_catalog.source_category_comparison_groups
where policy_version='retailer-comparison-groups-v3-seven-20260911'
  and source_code='zara'
  and source_category_key like 'zara-legacy:%';

update fitmatch_catalog.comparison_group_policies
set metadata=metadata-'zara_v1_category_compatibility',validated_at=now()
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
