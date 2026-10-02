BEGIN READ ONLY;
SELECT jsonb_build_object(
'aliases',(select jsonb_agg(to_jsonb(a)) from fitmatch_vnext.source_measurement_aliases a),
'sources',(select jsonb_agg(to_jsonb(a)) from fitmatch_vnext.source_measurements a),
'mappings',(select jsonb_agg(to_jsonb(a)) from fitmatch_vnext.source_measurement_mappings a),
'canonical',(select jsonb_agg(to_jsonb(a)) from fitmatch_vnext.fitmatch_measurements a),
'categories',(select jsonb_agg(jsonb_build_object('source',source_code,'key',source_category_key,'path',category_path,'group',group_code,'disposition',disposition)) from fitmatch_catalog.source_category_comparison_groups where policy_version='retailer-comparison-groups-v3-seven-20260911'),
'products',(select jsonb_agg(jsonb_build_object('source',p.source_code,'key',p.source_product_key,'name',p.product_name,'url',p.canonical_url,'path',p.source_extra->>'source_category_path','group',fitmatch_vnext.product_comparison_group(p.id))) from fitmatch_vnext.products p),
'raw',(select jsonb_agg(t) from (
select p.source_code source,p.source_product_key product,p.garment_type_code garment,g.category_code category,m.parser_code parser,m.raw_code,m.raw_label,m.raw_unit_code unit,count(*) rows,min(m.raw_value) min_value,max(m.raw_value) max_value,
fitmatch_vnext.resolve_measurement(p.source_code,m.parser_code,m.raw_code,m.raw_label,p.garment_type_code,g.category_code,null) resolution
from fitmatch_vnext.product_size_measurements m
join fitmatch_vnext.product_sizes s on s.id=m.product_size_id
join fitmatch_vnext.product_variants v on v.id=s.variant_id
join fitmatch_vnext.products p on p.id=v.product_id
left join fitmatch_vnext.garment_types g on g.garment_type_code=p.garment_type_code
where m.is_current group by p.source_code,p.source_product_key,p.garment_type_code,g.category_code,m.parser_code,m.raw_code,m.raw_label,m.raw_unit_code) t)
) audit; ROLLBACK;
