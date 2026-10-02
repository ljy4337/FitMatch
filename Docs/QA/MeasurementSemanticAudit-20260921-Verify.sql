-- READ ONLY. Inspect definitions/dependencies before execution on another deployment.
-- No begin_comparison / complete_comparison / ingestion / mutation RPC calls.
BEGIN TRANSACTION READ ONLY;

-- 1. Confirmed dictionary semantic contradictions: expected 10 rows on 2026-09-21.
SELECT id,parser_code,raw_code,raw_label,fitmatch_category_code,source_measurement_code,
       created_at,updated_at
FROM fitmatch_vnext.source_measurement_aliases
WHERE source_code='uniqlo' AND is_active AND is_verified AND (
 (raw_code='knit-body-length-front' AND source_measurement_code='uniqlo.back_length.back_neck_to_hem') OR
 (raw_code='chest-width-html' AND source_measurement_code='uniqlo.chest_width.chest_pit_to_pit') OR
 (raw_code='waist-petticoat-html' AND source_measurement_code='uniqlo.waist_circumference.garment_waist_circumference') OR
 (raw_code='skirt-length-html' AND source_measurement_code='uniqlo.total_length.waist_to_skirt_hem'))
ORDER BY raw_code,fitmatch_category_code;

-- 2. Actual raw values: same size, native context versus comparison-group context.
WITH products AS MATERIALIZED (
 SELECT p.id,p.source_product_key,fitmatch_vnext.effective_target_classification(p.id) ctx
 FROM fitmatch_vnext.products p WHERE p.source_code='uniqlo'
 AND p.source_product_key IN ('E454311','E471717','E482514','E482522')
)
SELECT p.source_product_key,s.size_label,
 fitmatch_vnext.canonical_measurements_for_size(s.id) native_result,
 fitmatch_vnext.canonical_measurements_for_size_with_context(s.id,p.ctx) group_result
FROM products p JOIN fitmatch_vnext.product_variants v ON v.product_id=p.id
JOIN fitmatch_vnext.product_sizes s ON s.variant_id=v.id
ORDER BY p.source_product_key,s.size_label;

-- 3. Readiness exposes policy-selected count, not all successfully normalized data.
SELECT source_product_key,fitmatch_vnext.product_measurement_readiness(
 id,fitmatch_vnext.effective_target_classification(id)) readiness
FROM fitmatch_vnext.products WHERE source_code='uniqlo'
AND source_product_key IN ('E454311','E471717','E482514','E482522');

-- 4. Dictionary basis/representation differences are review candidates, not automatic errors.
SELECT s.source_measurement_code,s.measurement_basis_code,f.measurement_code,
 f.canonical_basis_code,s.representation_code source_representation,
 f.representation_code canonical_representation,m.scale_factor,m.offset_value
FROM fitmatch_vnext.source_measurement_mappings m
JOIN fitmatch_vnext.source_measurements s USING(source_measurement_code)
JOIN fitmatch_vnext.fitmatch_measurements f ON f.measurement_code=m.fitmatch_measurement_code
WHERE m.is_active AND m.is_verified AND
 (s.measurement_basis_code IS DISTINCT FROM f.canonical_basis_code OR
 s.representation_code IS DISTINCT FROM f.representation_code);

-- 5. Unknown/comparison-disabled definition must not depend on entry route.
SELECT fitmatch_vnext.resolve_measurement('uniqlo','size_chart','total-length',
 '전체 길이',NULL,'tops',65) alias_result,
 fitmatch_vnext.resolve_measurement('uniqlo','size_chart',
 'uniqlo.total_length.source_defined_total_length','전체 길이',NULL,'tops',65) exact_result;

-- 6. Group policy score inputs remain a separate, explicit set.
SELECT gt.garment_type_code,gt.comparison_policy_code,cm.fitmatch_measurement_code,cm.weight
FROM fitmatch_vnext.garment_types gt
JOIN fitmatch_vnext.comparison_policies cp ON cp.policy_code=gt.comparison_policy_code AND cp.is_active
JOIN fitmatch_vnext.comparison_metrics cm ON cm.comparison_policy_code=cp.policy_code
WHERE gt.garment_type_code LIKE 'comparison_group_%' AND cm.is_active AND cm.metric_mode='CANONICAL'
ORDER BY gt.garment_type_code,cm.priority,cm.fitmatch_measurement_code;
ROLLBACK;
