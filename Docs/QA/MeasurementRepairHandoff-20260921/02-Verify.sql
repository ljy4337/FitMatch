BEGIN READ ONLY;
DO $verify$ BEGIN
IF md5(pg_get_functiondef(to_regprocedure('fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)'))) IS DISTINCT FROM 'c59cc698167dc25362e043068b920670' THEN RAISE EXCEPTION 'Rollback blocked: function changed after repair'; END IF;
IF md5(pg_get_functiondef(to_regprocedure('fitmatch_vnext.product_measurement_readiness(uuid,jsonb)'))) IS DISTINCT FROM '4d9516769c12b658ab5ea05fae7b235f' THEN RAISE EXCEPTION 'Rollback blocked: function changed after repair'; END IF;
IF md5(pg_get_functiondef(to_regprocedure('fitmatch_vnext.resolve_measurement(text,text,text,text,text,text,numeric)'))) IS DISTINCT FROM '299fe7dcc0862f438a5e49fb7327669f' THEN RAISE EXCEPTION 'Rollback blocked: function changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='9156094f-2e30-4d6d-913a-0081f5169ad5'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'tops' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.gathered_body_width.body_width_including_gather_and_tack' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='3e5b0fba-7f41-4c7c-b904-b66b8127e41b'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'outerwear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.gathered_body_width.body_width_including_gather_and_tack' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='2f5985d0-df46-4847-a2e5-0855df03c0af'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'dresses' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.gathered_body_width.body_width_including_gather_and_tack' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'underwear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.gathered_body_width.body_width_including_gather_and_tack' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='8f16f198-16ad-4ee6-984a-627d7d76a920'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'homewear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.gathered_body_width.body_width_including_gather_and_tack' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'waist-petticoat-html' AND a.raw_label IS NOT DISTINCT FROM '허리 둘레 (상품 사이즈)<br> [페티코트]' AND a.normalized_label IS NOT DISTINCT FROM '허리 둘레 (상품 사이즈)<br> [페티코트]' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'skirts' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'size_chart' AND a.raw_code IS NOT DISTINCT FROM 'knit-body-length-front' AND a.raw_label IS NOT DISTINCT FROM '앞기장' AND a.normalized_label IS NOT DISTINCT FROM '앞기장' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'dresses' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.front_length.front_neck_to_hem' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='74df726e-e236-4019-9548-6bc371ce5ad9'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'size_chart' AND a.raw_code IS NOT DISTINCT FROM 'knit-body-length-front' AND a.raw_label IS NOT DISTINCT FROM '앞기장' AND a.normalized_label IS NOT DISTINCT FROM '앞기장' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'underwear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.front_length.front_neck_to_hem' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'size_chart' AND a.raw_code IS NOT DISTINCT FROM 'knit-body-length-front' AND a.raw_label IS NOT DISTINCT FROM '앞기장' AND a.normalized_label IS NOT DISTINCT FROM '앞기장' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'homewear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.front_length.front_neck_to_hem' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='b86f0d4a-c767-43fd-8349-265e9ea123b6'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'skirt-length-html' AND a.raw_label IS NOT DISTINCT FROM '치마 길이<br> [페티코트]' AND a.normalized_label IS NOT DISTINCT FROM '치마 길이<br> [페티코트]' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'skirts' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.source_measurement_code IS NOT DISTINCT FROM 'uniqlo.petticoat_length.petticoat_waist_to_hem' AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true) THEN RAISE EXCEPTION 'Rollback blocked: alias changed after repair'; END IF;
END $verify$;
SELECT 'PASS: deployed definitions and 10 aliases match repair' result;
ROLLBACK;
-- READ ONLY post-apply verification for hnkplvyegonlhumlejst.
begin transaction read only;

select id, raw_code, raw_label, parser_code, fitmatch_category_code,
       source_measurement_code, is_active, is_verified
from fitmatch_vnext.source_measurement_aliases
where id in (
  '9156094f-2e30-4d6d-913a-0081f5169ad5'::uuid,
  '3e5b0fba-7f41-4c7c-b904-b66b8127e41b'::uuid,
  '2f5985d0-df46-4847-a2e5-0855df03c0af'::uuid,
  '8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'::uuid,
  '8f16f198-16ad-4ee6-984a-627d7d76a920'::uuid,
  '6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'::uuid,
  '9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'::uuid,
  '74df726e-e236-4019-9548-6bc371ce5ad9'::uuid,
  '5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'::uuid,
  'b86f0d4a-c767-43fd-8349-265e9ea123b6'::uuid
)
order by raw_code, fitmatch_category_code;

with products as materialized (
  select p.id,p.source_product_key,fitmatch_vnext.effective_target_classification(p.id) ctx
  from fitmatch_vnext.products p where p.source_code='uniqlo'
  and p.source_product_key in ('E454311','E471717','E482514','E482522')
), contexts as materialized (
  select p.id,p.source_product_key, p.ctx,
         p.ctx || jsonb_build_object(
           'effective_source','CATEGORY_GROUP','garment_type_code','comparison_group_innerwear',
           'category_code','underwear','comparison_policy_code','men_undershirt'
         ) innerwear_ctx
  from products p
)
select c.source_product_key,s.size_label,
  fitmatch_vnext.canonical_measurements_for_size_with_context(s.id,c.ctx)->'measurements' native_context_measurements,
  fitmatch_vnext.canonical_measurements_for_size_with_context(s.id,c.innerwear_ctx)->'measurements' innerwear_context_measurements
from contexts c
join fitmatch_vnext.product_variants v on v.product_id=c.id
join fitmatch_vnext.product_sizes s on s.variant_id=v.id
order by c.source_product_key,s.size_label;

select fitmatch_vnext.resolve_measurement(
  'uniqlo','size_chart','uniqlo.total_length.source_defined_total_length','전체 길이',null,'tops',65
) exact_result,
fitmatch_vnext.resolve_measurement(
  'uniqlo','size_chart','total-length','전체 길이',null,'tops',65
) alias_result;

rollback;
