select group_code, display_order, display_name, description
from fitmatch_catalog.comparison_groups
where active
order by display_order;

select group_code, count(*) as category_count, sum(product_count) as product_count
from fitmatch_catalog.source_category_comparison_groups
where policy_version = 'retailer-comparison-groups-v3-seven-20260911'
group by group_code
order by group_code;

select policy_version, status, activated_at,
       metadata ->> 'runtime_rpc_connected' as runtime_rpc_connected
from fitmatch_catalog.comparison_group_policies;

select count(*) as closet_count,
       count(*) filter (where comparison_group_code is not null) as grouped_count,
       count(*) filter (where comparison_group_code is null) as ungrouped_count
from fitmatch_vnext.closet_items
where deleted_at is null;

select fitmatch_vnext.product_comparison_group(p.id) as comparison_group
from fitmatch_vnext.products p
where p.source_code = 'uniqlo' and p.source_product_key = 'E487939';
