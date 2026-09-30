-- Read-only postflight. Does not set auth claims or insert user data.
WITH contexts AS (
 SELECT p.source_code,p.source_product_key,s.id,s.size_label,
 fitmatch_vnext.canonical_measurements_for_size_with_context(s.id,
 fitmatch_vnext.comparison_group_tuple(p.id,NULL)||jsonb_build_object('product_id',p.id,'effective_source','USER_EXPLICIT')) payload
 FROM fitmatch_vnext.products p JOIN fitmatch_vnext.product_variants v ON v.product_id=p.id
 JOIN fitmatch_vnext.product_sizes s ON s.variant_id=v.id
 WHERE fitmatch_vnext.product_comparison_group(p.id)->>'group_code' is not null
), checks AS (
 SELECT *,jsonb_array_length(payload->'measurements') n,
 NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'measurements') m
 WHERE nullif(m->>'fitmatch_measurement_code','') IS NULL OR nullif(m->>'source_measurement_code','') IS NULL
 OR (m->>'value')::numeric<=0 OR lower(m->>'unit_code')<>'cm') valid_rows,
 (SELECT count(*)=count(distinct m->>'fitmatch_measurement_code') FROM jsonb_array_elements(payload->'measurements') m) unique_codes
 FROM contexts
) SELECT source_code,count(*) sizes,count(*) FILTER(WHERE n>0) usable_sizes,
 count(*) FILTER(WHERE NOT valid_rows) invalid_snapshots,
 count(*) FILTER(WHERE NOT unique_codes) duplicate_code_sizes,
 sum(coalesce((payload->>'semantic_conflict_count')::int,0)) conflicts
 FROM checks GROUP BY source_code;

DO $verify$
BEGIN
 IF auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'Run this check without a user session'; END IF;
 BEGIN
  PERFORM fitmatch_vnext.apply_linked_closet_snapshot_for_swift('{"use_server_measurements":true,"measurements":[]}'::jsonb);
  RAISE EXCEPTION 'FAIL: unauthenticated create accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'Authentication required' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM fitmatch_vnext.find_reference_candidates(NULL::uuid,NULL::uuid);
  RAISE EXCEPTION 'FAIL: unauthenticated candidate query accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'Authentication required' THEN RAISE; END IF;
 END;
END $verify$;
