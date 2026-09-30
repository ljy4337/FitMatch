select garment_type_code,category_code,comparison_policy_code,display_name
from fitmatch_vnext.garment_types
where garment_type_code like 'comparison_group_%'
order by sort_order;

select fitmatch_vnext.effective_target_classification(id)
from fitmatch_vnext.products
where source_code='uniqlo' and source_product_key='E487939';

select p.proname,md5(pg_get_functiondef(p.oid)) body_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname,p.proname) in (
 ('fitmatch_vnext','effective_target_classification'),
 ('public','fitmatch_vnext_upsert_closet_item'),
 ('public','fitmatch_vnext_update_closet_item')
)
order by n.nspname,p.proname;
