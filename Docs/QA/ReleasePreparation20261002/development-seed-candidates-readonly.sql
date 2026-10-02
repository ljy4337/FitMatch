begin read only;
with selected as (
 select p.id,p.source_code,p.source_product_key
 from fitmatch_vnext.products p where (p.source_code,p.source_product_key) in
 (('musinsa','5068731'),('musinsa','6948481'),('uniqlo','E484080'),('uniqlo','E465185'),('zara','549678665'),('zara','575944393'))
)
select p.source_code,p.source_product_key,p.id as product_id,r.id as source_observation_id,
 r.observed_at,r.payload_fingerprint,pv.id as variant_id,pv.source_variant_key,
 r.retailer_facts->>'product_name' as product_name,
 r.retailer_facts->>'canonical_url' as canonical_url,
 r.retailer_facts->>'source_category_path' as source_category_path,
 r.retailer_facts->'source_category_codes' as source_category_codes,
 jsonb_agg(jsonb_build_object('product_size_id',ps.id,'source_size_key',ps.source_size_key,
 'observation_size_identity',sz.value->>'size_identity','size_label',sz.value->>'size_label',
 'raw_measurements',sz.value->'measurements') order by ps.id) as sizes
from selected p
join fitmatch_vnext.product_ingestion_receipts r on r.product_id=p.id and r.processing_status='PROCESSED'
cross join lateral jsonb_array_elements(r.retailer_facts->'variants') v(value)
join fitmatch_vnext.product_variants pv on pv.product_id=p.id and pv.source_variant_key=v.value->>'external_variant_id'
cross join lateral jsonb_array_elements(v.value->'sizes') sz(value)
join fitmatch_vnext.product_sizes ps on ps.variant_id=pv.id and ps.source_size_key=sz.value->>'size_identity'
group by p.source_code,p.source_product_key,p.id,r.id,pv.id
having count(distinct ps.id)>=2
order by p.source_code,p.source_product_key,r.id,pv.id;
commit;
