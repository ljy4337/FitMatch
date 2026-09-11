begin;

drop function if exists fitmatch_vnext.legacy_comparison_group(text);
drop function if exists fitmatch_vnext.product_comparison_group(uuid);

drop index if exists fitmatch_vnext.closet_items_user_comparison_group_idx;
alter table fitmatch_vnext.closet_items
  drop constraint if exists closet_items_comparison_group_source_chk,
  drop constraint if exists closet_items_comparison_group_code_chk,
  drop column if exists comparison_group_policy_version,
  drop column if exists comparison_group_source,
  drop column if exists comparison_group_code;

delete from fitmatch_catalog.product_comparison_group_overrides
where policy_version = 'retailer-comparison-groups-v3-seven-20260911';
delete from fitmatch_catalog.source_category_comparison_groups
where policy_version = 'retailer-comparison-groups-v3-seven-20260911';
delete from fitmatch_catalog.comparison_group_policies
where policy_version = 'retailer-comparison-groups-v3-seven-20260911';

drop table if exists fitmatch_catalog.comparison_groups;

commit;
