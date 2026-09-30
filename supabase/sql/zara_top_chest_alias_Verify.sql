-- Read-only. No authentication impersonation or user-row mutation.
-- Both TOPS and the existing DRESSES alias must be verified/active and unique.
SELECT fitmatch_category_code, source_measurement_code, is_verified, is_active, count(*)
FROM fitmatch_vnext.source_measurement_aliases
WHERE source_code='zara' AND parser_code='zara_kr_size_measure_guide_v1'
  AND raw_code='zone-name-chest'
GROUP BY fitmatch_category_code,source_measurement_code,is_verified,is_active;

-- Inspect the reported product's actual canonical result after explicit group A.
-- This does not claim to execute authenticated candidate/begin/complete RPCs.
WITH contexts AS (
  SELECT pv.id variant_id,
    fitmatch_vnext.comparison_target_context(p.id,pv.id,'A')->'effective_classification' effective
  FROM fitmatch_vnext.products p
  JOIN fitmatch_vnext.product_variants pv ON pv.product_id=p.id
  WHERE p.source_code='zara' AND p.source_product_key='549678665'
), canonical AS (
  SELECT ps.size_label,
    fitmatch_vnext.canonical_measurements_for_session_group(ps.id,c.effective) value
  FROM contexts c JOIN fitmatch_vnext.product_sizes ps ON ps.variant_id=c.variant_id
)
SELECT size_label, value->>'semantic_conflict_count' semantic_conflict_count,
  (SELECT jsonb_agg(m) FROM jsonb_array_elements(value->'measurements') m
   WHERE m->>'fitmatch_measurement_code'='chest_width') chest_width
FROM canonical;
