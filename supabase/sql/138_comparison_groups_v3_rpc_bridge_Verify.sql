select policy_version,status,activated_at,
       metadata->>'runtime_rpc_connected' as runtime_rpc_connected
from fitmatch_catalog.comparison_group_policies;

select p.proname,md5(pg_get_functiondef(p.oid)) as body_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'fitmatch_vnext_list_comparison_groups',
  'fitmatch_vnext_get_product_runtime',
  'fitmatch_vnext_upsert_closet_item',
  'fitmatch_vnext_update_closet_item',
  'fitmatch_vnext_list_closet_items',
  'fitmatch_vnext_find_reference_candidates',
  'fitmatch_vnext_eligible_candidate_sizes'
)
order by p.proname;

select fitmatch_vnext.product_comparison_group(id)
from fitmatch_vnext.products
where source_code='uniqlo' and source_product_key='E487939';
