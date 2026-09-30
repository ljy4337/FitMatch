-- LOCAL/DISPOSABLE fixture only. Never run against a connected user database.
-- Uses the captured real 2-arg internal/public functions; downstream eligibility
-- is a controlled one-metric fixture, not a full comparison-engine test.
SELECT set_config('audit.user','00000000-0000-0000-0000-000000000010',false);
DO $test$
DECLARE first_result jsonb; second_result jsonb; code text; checks integer := 0;
BEGIN
 FOR code IN SELECT chr(i) FROM generate_series(65,71)i LOOP
  UPDATE fitmatch_vnext.products SET group_code=code;
  UPDATE fitmatch_vnext.closet_items SET is_reference=false;
  first_result := public.fitmatch_vnext_find_reference_candidates(
    '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
  UPDATE fitmatch_vnext.closet_items SET is_reference=true;
  second_result := public.fitmatch_vnext_find_reference_candidates(
    '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
  -- Only the historical flag itself may differ; decisions/order/size IDs cannot.
  first_result := (SELECT jsonb_agg(x-'is_current_reference' ORDER BY ord)
    FROM jsonb_array_elements(first_result->'candidates') WITH ORDINALITY v(x,ord));
  second_result := (SELECT jsonb_agg(x-'is_current_reference' ORDER BY ord)
    FROM jsonb_array_elements(second_result->'candidates') WITH ORDINALITY v(x,ord));
  IF first_result IS DISTINCT FROM second_result THEN RAISE EXCEPTION 'Legacy flag changes candidates for %',code; END IF;
  IF jsonb_array_length(first_result)<>7 THEN RAISE EXCEPTION 'Foreign/deleted/zero-evidence candidate regression'; END IF;
  IF first_result->0->'comparison_group'->>'group_code' IS DISTINCT FROM code THEN RAISE EXCEPTION 'Same group priority lost'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(first_result) x WHERE x->>'decision'<>'MANUAL_EXTENDED' OR NOT (x->>'manual_explicit_required')::boolean) THEN RAISE EXCEPTION 'Manual selection policy lost'; END IF;
  checks := checks+1;
 END LOOP;
 PERFORM set_config('audit.user','',false);
 BEGIN
  PERFORM public.fitmatch_vnext_find_reference_candidates('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
  RAISE EXCEPTION 'Auth gate did not reject';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'Authentication required' THEN RAISE; END IF;
 END;
 PERFORM set_config('audit.user','00000000-0000-0000-0000-000000000010',false);
 BEGIN
  PERFORM public.fitmatch_vnext_find_reference_candidates('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000099');
  RAISE EXCEPTION 'Variant gate did not reject';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'Target variant hierarchy mismatch' THEN RAISE; END IF;
 END;
 RAISE NOTICE 'PASS: % groups x 2 reference states; one metric, cross group, zero metric, foreign/deleted, auth, variant checks',checks;
END $test$;
