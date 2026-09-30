-- Read-only regression for reported MUSINSA 5328103, every exact size identity.
WITH sizes AS (
 SELECT s.id,s.size_label FROM fitmatch_vnext.product_sizes s
 JOIN fitmatch_vnext.product_variants v ON v.id=s.variant_id
 WHERE v.product_id='cd77c9ce-5fe0-4c89-8f82-30ef608f3bb8'
), contexts AS (
 SELECT s.*,
 fitmatch_vnext.canonical_measurements_for_size_with_context(s.id,
 fitmatch_vnext.effective_target_classification('cd77c9ce-5fe0-4c89-8f82-30ef608f3bb8')) runtime,
 fitmatch_vnext.canonical_measurements_for_size_with_context(s.id,
 fitmatch_vnext.comparison_group_tuple('cd77c9ce-5fe0-4c89-8f82-30ef608f3bb8',NULL) ||
 jsonb_build_object('product_id','cd77c9ce-5fe0-4c89-8f82-30ef608f3bb8','effective_source','USER_EXPLICIT')) snapshot
 FROM sizes s
), expected AS (
 SELECT s.id, jsonb_agg(jsonb_build_object('code',
 CASE m.raw_label WHEN '총장' THEN 'outseam' WHEN '허리단면' THEN 'waist_width'
 WHEN '엉덩이단면' THEN 'hip_width' WHEN '허벅지단면' THEN 'thigh_width'
 WHEN '밑위' THEN 'front_rise' WHEN '밑단단면' THEN 'hem_width' END,
 'value',m.raw_value,'unit_code','cm')) metrics
 FROM sizes s JOIN fitmatch_vnext.product_size_measurements m ON m.product_size_id=s.id GROUP BY s.id
)
SELECT c.id,c.size_label,
 jsonb_array_length(snapshot->'measurements') canonical_count,
 snapshot->>'unresolved_count' unresolved_count,
 snapshot->>'semantic_conflict_count' semantic_conflict_count,
 runtime->'measurements'=snapshot->'measurements' contexts_agree,
 NOT EXISTS (
 SELECT 1 FROM jsonb_array_elements(e.metrics) request
 WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(snapshot->'measurements') actual
 WHERE actual->>'fitmatch_measurement_code'=request->>'code'
 AND (actual->>'value')::numeric=(request->>'value')::numeric
 AND actual->>'unit_code'=request->>'unit_code')
 ) snapshot_values_match,
 (SELECT value->>'value' FROM jsonb_array_elements(snapshot->'measurements') WHERE value->>'fitmatch_measurement_code'='outseam') outseam_cm
FROM contexts c JOIN expected e USING(id) ORDER BY c.size_label;
