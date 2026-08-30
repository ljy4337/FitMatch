CREATE OR REPLACE FUNCTION fitmatch_catalog.runtime_bottom_reclassification_gate_v1(p_release_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $gate$
DECLARE
  v_release fitmatch_catalog.releases%rowtype;
  v_parent_id uuid;
  v_mapping_count integer;
  v_mapping_parity integer;
  v_rule_count integer;
  v_rule_parity integer;
  v_history_count integer;
  v_confirmed integer;
  v_review integer;
  v_not_comparable integer;
  v_fingerprint_parity integer;
  v_history_parity integer;
  v_target_count integer;
  v_target_history_parity integer;
  v_other_count integer;
  v_missing_target_length integer;
  v_casual integer;
  v_homewear integer;
  v_chino integer;
  v_denim integer;
  v_sports integer;
  v_sweat integer;
  v_cargo integer;
  v_slacks integer;
  v_short integer;
  v_long integer;
  v_ankle integer;
  v_cropped integer;
  v_target_checksum text;
  v_policy_public integer;
  v_policy_vnext integer;
  v_camisole_history integer;
  v_camisole_product integer;
  v_core_invalid integer;
  v_set_leaks integer;
  v_mapping_checksum text;
  v_exact_checksum text;
  v_bundle_checksum text;
  v_pending_zara integer;
  v_blockers jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_release FROM fitmatch_catalog.releases WHERE id=p_release_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002', message='release_not_found'; END IF;

  SELECT id INTO v_parent_id FROM fitmatch_catalog.releases
  WHERE release_key='fitmatch-camisole-mapping-correction-2026-08-29-v1';

  IF v_parent_id IS NULL
     OR v_release.release_key<>'fitmatch-bottom-other-reclassification-2026-08-29-v1'
     OR v_release.validation_contract_version<>'fitmatch-release-gate-v5-bottom-reclassification'
     OR v_release.status NOT IN ('validated','active')
     OR v_release.expected_mapping_count<>3510
     OR v_release.expected_qa_count<>1608
     OR v_release.validated_at IS NULL
  THEN v_blockers:=v_blockers||jsonb_build_array('release_identity_or_contract_mismatch'); END IF;

  SELECT count(*) INTO v_mapping_count FROM fitmatch_catalog.source_category_mappings WHERE release_id=p_release_id;
  SELECT count(*) INTO v_mapping_parity
  FROM fitmatch_catalog.source_category_mappings parent
  JOIN fitmatch_catalog.source_category_mappings child
    ON child.release_id=p_release_id AND child.source_identity=parent.source_identity
  WHERE parent.release_id=v_parent_id
    AND (to_jsonb(child)-'release_id'-'created_at') IS NOT DISTINCT FROM (to_jsonb(parent)-'release_id'-'created_at');

  SELECT count(*) INTO v_rule_count FROM fitmatch_catalog.classification_structured_discriminator_rules WHERE release_id=p_release_id;
  SELECT count(*) INTO v_rule_parity
  FROM fitmatch_catalog.classification_structured_discriminator_rules parent
  JOIN fitmatch_catalog.classification_structured_discriminator_rules child
    ON child.release_id=p_release_id AND child.rule_id=parent.rule_id
  WHERE parent.release_id=v_parent_id
    AND (to_jsonb(child)-'release_id'-'created_at') IS NOT DISTINCT FROM (to_jsonb(parent)-'release_id'-'created_at');

  IF v_mapping_count<>3510 OR v_mapping_parity<>3510 OR v_rule_count<>21 OR v_rule_parity<>21 THEN
    v_blockers:=v_blockers||jsonb_build_array('fallback_artifact_parity_failed');
  END IF;

  SELECT count(*),
         count(*) FILTER(WHERE classification_status='confirmed'),
         count(*) FILTER(WHERE classification_status='review_required'),
         count(*) FILTER(WHERE classification_status='not_comparable')
  INTO v_history_count,v_confirmed,v_review,v_not_comparable
  FROM fitmatch_catalog.product_classification_history
  WHERE is_current AND mapping_release_id=p_release_id
    AND evidence @> '{"exact_product_authority":true}'::jsonb;

  IF v_history_count<>1608 OR v_confirmed<>1421 OR v_review<>0 OR v_not_comparable<>187 THEN
    v_blockers:=v_blockers||jsonb_build_array('current_history_counts_failed');
  END IF;

  SELECT count(*) INTO v_fingerprint_parity
  FROM fitmatch_catalog.product_classification_history h
  JOIN fitmatch_catalog.products p ON p.id=h.product_id
  WHERE h.is_current AND h.mapping_release_id=p_release_id
    AND h.evidence @> '{"exact_product_authority":true}'::jsonb
    AND h.input_fingerprint=p.input_fingerprint
    AND h.taxonomy_policy_version='db-classifier-2026-08-26-final';
  IF v_fingerprint_parity<>1608 THEN v_blockers:=v_blockers||jsonb_build_array('runtime_fingerprint_parity_failed'); END IF;

  SELECT count(*) INTO v_history_parity
  FROM fitmatch_catalog.product_classification_history h
  JOIN fitmatch_vnext.products v ON v.id=h.product_id
  LEFT JOIN fitmatch_vnext.garment_types gt ON gt.garment_type_code=v.garment_type_code
  WHERE h.is_current AND h.mapping_release_id=p_release_id
    AND ((v.classification_status='CONFIRMED'
      AND h.classification_status='confirmed'
      AND h.garment_type_code IS NOT DISTINCT FROM v.garment_type_code
      AND h.length_code IS NOT DISTINCT FROM CASE
        WHEN gt.uses_sleeve_length THEN v.sleeve_length_code
        WHEN gt.uses_lower_length THEN v.lower_length_code ELSE NULL END
      AND h.body_length_code IS NOT DISTINCT FROM CASE WHEN gt.uses_body_length THEN v.body_length_code ELSE NULL END)
    OR (v.classification_status='NOT_APPLICABLE'
      AND h.classification_status='not_comparable'
      AND h.category_code IS NULL AND h.detail_code IS NULL AND h.garment_type_code IS NULL
      AND h.comparison_family_code IS NULL AND h.length_code IS NULL AND h.body_length_code IS NULL));
  IF v_history_parity<>1608 THEN v_blockers:=v_blockers||jsonb_build_array('vnext_history_exact_parity_failed'); END IF;

  SELECT count(*),
         count(*) FILTER(WHERE garment_type_code='casual_pants'),
         count(*) FILTER(WHERE garment_type_code='homewear_bottom'),
         count(*) FILTER(WHERE garment_type_code='chino_cotton_pants'),
         count(*) FILTER(WHERE garment_type_code='denim_pants'),
         count(*) FILTER(WHERE garment_type_code='sports_bottom'),
         count(*) FILTER(WHERE garment_type_code='sweat_jogger_pants'),
         count(*) FILTER(WHERE garment_type_code='cargo_pants'),
         count(*) FILTER(WHERE garment_type_code='slacks_trousers'),
         count(*) FILTER(WHERE lower_length_code='short_length'),
         count(*) FILTER(WHERE lower_length_code='long_length'),
         count(*) FILTER(WHERE lower_length_code='ankle_length'),
         count(*) FILTER(WHERE lower_length_code='cropped_length'),
         count(*) FILTER(WHERE lower_length_code IS NULL)
  INTO v_target_count,v_casual,v_homewear,v_chino,v_denim,v_sports,v_sweat,v_cargo,v_slacks,
       v_short,v_long,v_ankle,v_cropped,v_missing_target_length
  FROM fitmatch_vnext.products
  WHERE source_extra->>'_bottom_reclassification'='fitmatch-bottom-other-reclassification-2026-08-29-v1';

  SELECT encode(extensions.digest(coalesce(string_agg(
      source_code||'|'||source_product_key||'|'||coalesce(garment_type_code,'')||'|'||coalesce(lower_length_code,''),
      E'\n' ORDER BY source_code,source_product_key),''),'sha256'),'hex')
  INTO v_target_checksum
  FROM fitmatch_vnext.products
  WHERE source_extra->>'_bottom_reclassification'='fitmatch-bottom-other-reclassification-2026-08-29-v1';

  SELECT count(*) INTO v_other_count
  FROM fitmatch_vnext.products
  WHERE classification_status='CONFIRMED' AND garment_type_code='other_standard_pants';

  IF v_target_count<>100 OR v_casual<>49 OR v_homewear<>14 OR v_chino<>7 OR v_denim<>10 OR v_sports<>8
     OR v_sweat<>6 OR v_cargo<>3 OR v_slacks<>3 OR v_short<>57 OR v_long<>33 OR v_ankle<>9 OR v_cropped<>1
     OR v_missing_target_length<>0 OR v_other_count<>0
     OR v_target_checksum<>'9c183490b228569b6b4d63e7e50a52d08488e58c1a35483df54dec4c446b6d9b'
  THEN v_blockers:=v_blockers||jsonb_build_array('bottom_reclassification_target_mismatch'); END IF;

  SELECT count(*) INTO v_target_history_parity
  FROM fitmatch_catalog.product_classification_history h
  JOIN fitmatch_catalog.products p ON p.id=h.product_id
  JOIN fitmatch_vnext.products v ON v.id=p.id
  WHERE h.is_current AND h.mapping_release_id=p_release_id
    AND v.source_extra->>'_bottom_reclassification'='fitmatch-bottom-other-reclassification-2026-08-29-v1'
    AND h.classification_status='confirmed'
    AND h.garment_type_code=v.garment_type_code
    AND h.length_code=v.lower_length_code
    AND h.body_length_code IS NULL
    AND h.category_code=CASE v.garment_type_code WHEN 'homewear_bottom' THEN 'homewear' ELSE 'bottoms' END
    AND h.detail_code=CASE v.garment_type_code
      WHEN 'casual_pants' THEN 'casual_pants'
      WHEN 'denim_pants' THEN 'jeans'
      WHEN 'chino_cotton_pants' THEN 'chino_cotton'
      WHEN 'cargo_pants' THEN 'cargo_utility'
      WHEN 'slacks_trousers' THEN 'slacks_trousers'
      WHEN 'sweat_jogger_pants' THEN 'sweat_jogger'
      WHEN 'homewear_bottom' THEN 'homewear_bottom'
      WHEN 'sports_bottom' THEN 'sports_bottom' ELSE NULL END
    AND h.comparison_family_code=CASE v.garment_type_code
      WHEN 'homewear_bottom' THEN 'homewear_bottom'
      WHEN 'sports_bottom' THEN 'sports_bottom' ELSE 'standard_pants' END;
  IF v_target_history_parity<>100 THEN v_blockers:=v_blockers||jsonb_build_array('bottom_runtime_history_parity_failed'); END IF;

  IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.products
      WHERE source_code='musinsa' AND source_product_key='6884177'
        AND garment_type_code='sports_bottom' AND lower_length_code='short_length'
        AND product_structure_code='SINGLE') THEN
    v_blockers:=v_blockers||jsonb_build_array('musinsa_6884177_structure_regression');
  END IF;

  SELECT count(*) INTO v_policy_public
  FROM public.comparison_policy_length_axes a
  JOIN public.comparison_policies p ON p.code=a.policy_code
  WHERE a.policy_code='standard_pants_v1' AND a.axis_code='leg' AND a.match_mode='exact_class'
    AND p.is_active
    AND p.evidence_note='표준 바지는 자동 비교 시 하의 길이 class가 정확히 같아야 한다. 서로 다른 길이는 사용자 수동 선택의 extended 비교만 허용한다.';

  SELECT count(*) INTO v_policy_vnext
  FROM fitmatch_vnext.comparison_policies
  WHERE policy_code='standard_pants' AND is_active AND lower_length_mismatch_policy='REQUIRE_MATCH';
  IF v_policy_public<>1 OR v_policy_vnext<>1 THEN v_blockers:=v_blockers||jsonb_build_array('automatic_bottom_length_policy_mismatch'); END IF;

  SELECT count(*) INTO v_camisole_product
  FROM fitmatch_vnext.products
  WHERE source_code='uniqlo'
    AND source_product_key IN ('E485709','E485710','E485711','E487121','E489044','E482148','E481994')
    AND classification_status='CONFIRMED' AND garment_type_code='women_camisole' AND sleeve_length_code='sleeveless';

  SELECT count(*) INTO v_camisole_history
  FROM fitmatch_catalog.product_classification_history h
  JOIN fitmatch_catalog.products p ON p.id=h.product_id
  WHERE h.is_current AND h.mapping_release_id=p_release_id AND p.source='uniqlo'
    AND p.external_product_id IN ('E485709','E485710','E485711','E487121','E489044','E482148','E481994')
    AND h.classification_status='confirmed' AND h.category_code='underwear'
    AND h.detail_code='women_camisole' AND h.garment_type_code='women_camisole'
    AND h.comparison_family_code='women_camisole' AND h.length_code='sleeveless' AND h.body_length_code IS NULL;
  IF v_camisole_product<>7 OR v_camisole_history<>7 THEN v_blockers:=v_blockers||jsonb_build_array('camisole_regression'); END IF;

  SELECT count(*) INTO v_core_invalid
  FROM fitmatch_catalog.product_classification_history h
  LEFT JOIN public.garment_types g ON g.code=h.garment_type_code AND g.is_active
  LEFT JOIN public.app_categories parent ON parent.code=h.category_code AND parent.depth=0 AND parent.parent_id IS NULL AND parent.is_active
  LEFT JOIN public.app_categories detail ON detail.code=h.detail_code AND detail.depth=1 AND detail.parent_id=parent.id AND detail.is_active
  LEFT JOIN public.comparison_groups family ON family.code=h.comparison_family_code AND family.is_active
  WHERE h.is_current AND h.mapping_release_id=p_release_id AND h.classification_status='confirmed'
    AND (g.code IS NULL OR parent.id IS NULL OR detail.id IS NULL OR family.code IS NULL
      OR g.major_category_code IS DISTINCT FROM h.category_code OR g.comparison_group_code IS DISTINCT FROM h.comparison_family_code);
  IF v_core_invalid<>0 THEN v_blockers:=v_blockers||jsonb_build_array('confirmed_core_tuple_invalid'); END IF;

  SELECT count(*) INTO v_set_leaks
  FROM fitmatch_catalog.product_classification_history h
  JOIN fitmatch_vnext.products v ON v.id=h.product_id
  WHERE h.is_current AND h.mapping_release_id=p_release_id AND v.product_structure_code='SET'
    AND h.classification_status<>'not_comparable';
  IF v_set_leaks<>0 THEN v_blockers:=v_blockers||jsonb_build_array('set_comparison_leak'); END IF;

  IF (SELECT count(*) FROM fitmatch_vnext.products)<>1608
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='CONFIRMED')<>1421
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='REVIEW_REQUIRED')<>0
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='NOT_APPLICABLE')<>187
  THEN v_blockers:=v_blockers||jsonb_build_array('vnext_population_changed'); END IF;

  SELECT encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'source_identity',m.source_identity,'source',m.source,'snapshot_id',m.snapshot_id,
      'external_category_id',m.external_category_id,'target',m.target,'normalized_path',m.normalized_path,
      'decision_status',m.decision_status,'mapping_status',m.mapping_status,
      'runtime_lookup_eligible',m.runtime_lookup_eligible,'eligibility',m.eligibility,
      'semantic_category_code',m.semantic_category_code,'semantic_garment_type',m.semantic_garment_type,
      'comparison_family',m.comparison_family,'source_external_key',m.source_external_key,
      'source_external_target_key',m.source_external_target_key,'source_path_key',m.source_path_key,
      'source_target_path_key',m.source_target_path_key,'raw_record',m.raw_record)::text,
      E'\n' ORDER BY m.source_identity),''),'sha256'),'hex')
  INTO v_mapping_checksum FROM fitmatch_catalog.source_category_mappings m WHERE m.release_id=p_release_id;

  SELECT encode(extensions.digest(coalesce(string_agg(
    p.source||'|'||p.external_product_id||'|'||p.input_fingerprint||'|'||
    CASE v.classification_status WHEN 'CONFIRMED' THEN 'confirmed' ELSE 'not_comparable' END||'|'||
    coalesce(v.garment_type_code,'')||'|'||
    coalesce(CASE WHEN gt.uses_sleeve_length THEN v.sleeve_length_code WHEN gt.uses_lower_length THEN v.lower_length_code END,'')||'|'||
    coalesce(CASE WHEN gt.uses_body_length THEN v.body_length_code END,''),
    E'\n' ORDER BY p.source,p.external_product_id),''),'sha256'),'hex')
  INTO v_exact_checksum
  FROM fitmatch_vnext.products v
  JOIN fitmatch_catalog.products p ON p.source=v.source_code AND p.external_product_id=v.source_product_key
  LEFT JOIN fitmatch_vnext.garment_types gt ON gt.garment_type_code=v.garment_type_code;

  v_bundle_checksum:=encode(extensions.digest(v_mapping_checksum||'|'||v_exact_checksum||'|'||v_rule_count::text,'sha256'),'hex');
  IF v_release.validation_report->>'source_mapping_checksum' IS DISTINCT FROM v_mapping_checksum
     OR v_release.validation_report->>'exact_authority_checksum' IS DISTINCT FROM v_exact_checksum
     OR v_release.validation_report->>'target_decision_checksum' IS DISTINCT FROM v_target_checksum
     OR v_release.bundle_checksum IS DISTINCT FROM v_bundle_checksum
  THEN v_blockers:=v_blockers||jsonb_build_array('release_checksum_mismatch'); END IF;

  IF NOT EXISTS (SELECT 1 FROM fitmatch_catalog.product_classification_history h
    JOIN fitmatch_catalog.products p ON p.id=h.product_id
    WHERE h.is_current AND h.mapping_release_id=p_release_id AND p.source='zara' AND p.external_product_id='545427337'
      AND h.classification_status='confirmed' AND h.garment_type_code='jacket')
  THEN v_blockers:=v_blockers||jsonb_build_array('zara_07782343_regression'); END IF;

  SELECT count(*) INTO v_pending_zara FROM fitmatch_catalog.data_quality_issues
  WHERE source_code='zara' AND issue_code='pending_owner_product_adjudication'
    AND raw_signature='01934230' AND status='acknowledged';
  IF v_pending_zara<>1 THEN v_blockers:=v_blockers||jsonb_build_array('zara_01934230_pending_adjudication_missing'); END IF;

  RETURN jsonb_build_object(
    'contract_version','fitmatch-release-gate-v5-bottom-reclassification','release_id',v_release.id,'release_key',v_release.release_key,
    'eligible',jsonb_array_length(v_blockers)=0,'blockers',v_blockers,
    'mapping_count',v_mapping_count,'mapping_parity',v_mapping_parity,'rule_count',v_rule_count,'rule_parity',v_rule_parity,
    'history_count',v_history_count,'confirmed_count',v_confirmed,'review_required_count',v_review,'not_comparable_count',v_not_comparable,
    'history_parity_count',v_history_parity,'fingerprint_parity_count',v_fingerprint_parity,
    'target_count',v_target_count,'target_history_parity_count',v_target_history_parity,'other_standard_pants_count',v_other_count,
    'target_decision_checksum',v_target_checksum,'casual_pants_count',v_casual,'homewear_bottom_count',v_homewear,
    'chino_cotton_pants_count',v_chino,'denim_pants_count',v_denim,'sports_bottom_count',v_sports,
    'sweat_jogger_pants_count',v_sweat,'cargo_pants_count',v_cargo,'slacks_trousers_count',v_slacks,
    'short_length_count',v_short,'long_length_count',v_long,'ankle_length_count',v_ankle,'cropped_length_count',v_cropped,
    'automatic_length_policy','exact_class','manual_cross_length_policy','app_extended_excluding_total_length_and_hem',
    'core_tuple_invalid_count',v_core_invalid,'set_leak_count',v_set_leaks,
    'source_mapping_checksum',v_mapping_checksum,'exact_authority_checksum',v_exact_checksum,'bundle_checksum',v_bundle_checksum);
END
$gate$;

CREATE OR REPLACE FUNCTION fitmatch_catalog.runtime_release_gate_report(p_release_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $router$
DECLARE v_release_key text;
BEGIN
  SELECT release_key INTO v_release_key FROM fitmatch_catalog.releases WHERE id=p_release_id;
  IF v_release_key='fitmatch-bottom-other-reclassification-2026-08-29-v1' THEN
    RETURN fitmatch_catalog.runtime_bottom_reclassification_gate_v1(p_release_id);
  END IF;
  IF v_release_key='fitmatch-camisole-mapping-correction-2026-08-29-v1' THEN
    RETURN fitmatch_catalog.runtime_camisole_mapping_correction_gate_v1(p_release_id);
  END IF;
  IF p_release_id='12100000-0000-4000-8000-000000000121'::uuid THEN RETURN fitmatch_catalog.runtime_review_zero_gate_v1(p_release_id); END IF;
  IF p_release_id='12000000-0000-4000-8000-000000000120'::uuid THEN RETURN fitmatch_catalog.runtime_audience_scope_correction_gate_v1(p_release_id); END IF;
  RETURN fitmatch_catalog.runtime_release_gate_report_pre120_v2(p_release_id);
END
$router$;

DO $do$
DECLARE
  v_parent fitmatch_catalog.releases%rowtype;
  v_new_id uuid := gen_random_uuid();
  v_new_key text := 'fitmatch-bottom-other-reclassification-2026-08-29-v1';
  v_now timestamptz := now();
  v_count integer;
  v_policy_rows integer;
  v_history_rows integer;
  v_mapping_checksum text;
  v_exact_checksum text;
  v_target_checksum text;
  v_rule_count integer;
  v_bundle_checksum text;
  v_gate jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('fitmatch:bottom-other-reclassification-2026-08-29'));

  SELECT * INTO v_parent FROM fitmatch_catalog.releases WHERE status='active' FOR UPDATE;
  IF NOT FOUND OR v_parent.release_key<>'fitmatch-camisole-mapping-correction-2026-08-29-v1' THEN
    RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_parent_release_mismatch';
  END IF;
  IF (SELECT count(*) FROM fitmatch_catalog.releases WHERE status='active')<>1 THEN
    RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_active_release_cardinality';
  END IF;
  IF EXISTS (SELECT 1 FROM fitmatch_catalog.releases WHERE release_key=v_new_key) THEN
    RAISE EXCEPTION USING errcode='23505', message='bottom_reclassification_release_already_exists';
  END IF;

  IF (SELECT count(*) FROM fitmatch_vnext.products)<>1608
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='CONFIRMED')<>1421
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='REVIEW_REQUIRED')<>0
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='NOT_APPLICABLE')<>187
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='CONFIRMED' AND garment_type_code='other_standard_pants')<>100
  THEN RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_preimage_population_mismatch'; END IF;

  CREATE TEMP TABLE _bottom_decisions(
    source_code text NOT NULL, source_product_key text NOT NULL, new_garment text NOT NULL,
    new_length text NOT NULL, new_structure text, basis text NOT NULL,
    PRIMARY KEY(source_code,source_product_key)) ON COMMIT DROP;

  INSERT INTO _bottom_decisions(source_code,source_product_key,new_garment,new_length,new_structure,basis) VALUES
('musinsa','3225860','casual_pants','short_length',NULL,'linen shorts'),
('musinsa','3346165','casual_pants','long_length',NULL,'waterproof windbreaker pants'),
('musinsa','4062254','casual_pants','long_length',NULL,'generic woven/easy wide pants'),
('musinsa','4663938','casual_pants','long_length',NULL,'generic woven/easy wide pants'),
('musinsa','4720624','casual_pants','short_length',NULL,'generic shorts'),
('musinsa','4818151','casual_pants','long_length',NULL,'generic woven/easy wide pants'),
('musinsa','5139106','casual_pants','short_length',NULL,'generic shorts'),
('musinsa','5442400','casual_pants','short_length',NULL,'generic shorts'),
('musinsa','5504965','denim_pants','short_length',NULL,'explicit denim'),
('musinsa','6145321','casual_pants','short_length',NULL,'generic shorts'),
('musinsa','6152463','casual_pants','long_length',NULL,'generic woven/easy wide pants'),
('musinsa','6469952','denim_pants','short_length',NULL,'explicit denim'),
('musinsa','6518709','casual_pants','long_length',NULL,'chambray/cotton woven'),
('musinsa','6686255','sports_bottom','short_length',NULL,'club sports shorts'),
('musinsa','6829724','casual_pants','long_length',NULL,'work pants generic'),
('musinsa','6837218','casual_pants','long_length',NULL,'chambray/cotton woven'),
('musinsa','6874981','casual_pants','cropped_length',NULL,'capri pants'),
('musinsa','6884177','sports_bottom','short_length','SINGLE','sports 2-in-1 single garment'),
('musinsa','6907832','denim_pants','short_length',NULL,'explicit denim'),
('musinsa','6908818','sports_bottom','long_length',NULL,'trail gear leisure pants'),
('musinsa','6908820','sports_bottom','long_length',NULL,'trail gear leisure pants'),
('musinsa','6928699','denim_pants','short_length',NULL,'explicit denim'),
('uniqlo','E458325','casual_pants','short_length',NULL,'easy shorts'),
('uniqlo','E461420','homewear_bottom','ankle_length',NULL,'lounge ankle pants'),
('uniqlo','E473696','chino_cotton_pants','short_length',NULL,'linen cotton shorts'),
('uniqlo','E473791','casual_pants','long_length',NULL,'linen blend easy pants'),
('uniqlo','E474481','sports_bottom','long_length',NULL,'ultra stretch active pants'),
('uniqlo','E477869','sports_bottom','long_length',NULL,'ultra stretch active pants'),
('uniqlo','E478670','homewear_bottom','ankle_length',NULL,'lounge ankle pants'),
('uniqlo','E478702','denim_pants','short_length',NULL,'jorts'),
('uniqlo','E479134','homewear_bottom','ankle_length',NULL,'lounge ankle pants'),
('uniqlo','E479575','casual_pants','long_length',NULL,'kids easy pants'),
('uniqlo','E481582','casual_pants','short_length',NULL,'easy shorts'),
('uniqlo','E481583','homewear_bottom','short_length',NULL,'lounge shorts'),
('uniqlo','E481786','casual_pants','short_length',NULL,'generic easy shorts'),
('uniqlo','E481787','denim_pants','short_length',NULL,'explicit denim shorts'),
('uniqlo','E481788','casual_pants','short_length',NULL,'generic easy shorts'),
('uniqlo','E481790','casual_pants','short_length',NULL,'generic easy shorts'),
('uniqlo','E482172','chino_cotton_pants','short_length',NULL,'linen cotton shorts'),
('uniqlo','E482259','homewear_bottom','ankle_length',NULL,'lounge ankle pants'),
('uniqlo','E482260','homewear_bottom','short_length',NULL,'lounge/homewear shorts'),
('uniqlo','E482646','chino_cotton_pants','short_length',NULL,'cotton woven shorts'),
('uniqlo','E482937','sports_bottom','short_length',NULL,'gear/performance shorts'),
('uniqlo','E482944','chino_cotton_pants','short_length',NULL,'explicit chino'),
('uniqlo','E483001','cargo_pants','long_length',NULL,'utility pants'),
('uniqlo','E483327','denim_pants','short_length',NULL,'explicit denim shorts'),
('uniqlo','E483329','casual_pants','short_length',NULL,'skorts in shorts/skirt-pants retailer path'),
('uniqlo','E483394','casual_pants','short_length',NULL,'skorts in shorts/skirt-pants retailer path'),
('uniqlo','E483395','casual_pants','short_length',NULL,'generic easy shorts'),
('uniqlo','E483406','sports_bottom','short_length',NULL,'gear/performance shorts'),
('uniqlo','E483411','casual_pants','short_length',NULL,'AIRism cotton half pants'),
('uniqlo','E483412','casual_pants','short_length',NULL,'AIRism cotton half pants'),
('uniqlo','E483903','casual_pants','long_length',NULL,'linen blend easy pants'),
('uniqlo','E483912','homewear_bottom','short_length',NULL,'lounge/homewear shorts'),
('uniqlo','E483913','homewear_bottom','short_length',NULL,'lounge/homewear shorts'),
('uniqlo','E484064','casual_pants','short_length',NULL,'skorts in shorts/skirt-pants retailer path'),
('uniqlo','E484598','casual_pants','short_length',NULL,'nylon shorts'),
('uniqlo','E484784','homewear_bottom','ankle_length',NULL,'lounge ankle pants'),
('uniqlo','E484875','casual_pants','long_length',NULL,'barrel pants'),
('uniqlo','E484920','casual_pants','short_length',NULL,'chambray shorts'),
('uniqlo','E484924','casual_pants','short_length',NULL,'skorts in shorts/skirt-pants retailer path'),
('uniqlo','E485322','casual_pants','short_length',NULL,'generic easy shorts'),
('uniqlo','E485593','casual_pants','short_length',NULL,'nylon culotte'),
('uniqlo','E485739','casual_pants','short_length',NULL,'generic easy shorts'),
('uniqlo','E486220','casual_pants','short_length',NULL,'skorts in shorts/skirt-pants retailer path'),
('uniqlo','E486468','homewear_bottom','ankle_length',NULL,'lounge ankle pants'),
('uniqlo','E486471','homewear_bottom','ankle_length',NULL,'lounge ankle pants'),
('uniqlo','E486683','sweat_jogger_pants','long_length',NULL,'explicit sweat pants'),
('uniqlo','E486684','casual_pants','ankle_length',NULL,'explicit ankle barrel pants'),
('uniqlo','E486723','denim_pants','short_length',NULL,'jorts'),
('uniqlo','E486724','sweat_jogger_pants','long_length',NULL,'explicit sweat pants'),
('uniqlo','E486726','cargo_pants','short_length',NULL,'explicit cargo shorts'),
('uniqlo','E486729','casual_pants','long_length',NULL,'twill woven pants'),
('uniqlo','E486982','cargo_pants','long_length',NULL,'utility pants'),
('uniqlo','E487273','casual_pants','short_length',NULL,'skorts in shorts/skirt-pants retailer path'),
('uniqlo','E487345','sweat_jogger_pants','ankle_length',NULL,'sweat ankle pants'),
('uniqlo','E487375','sweat_jogger_pants','long_length',NULL,'explicit jogger'),
('uniqlo','E487891','casual_pants','short_length',NULL,'generic shorts'),
('uniqlo','E488010','slacks_trousers','short_length',NULL,'smart culotte'),
('uniqlo','E488163','sweat_jogger_pants','long_length',NULL,'explicit sweat pants'),
('uniqlo','E488203','casual_pants','short_length',NULL,'corduroy culotte'),
('uniqlo','E488357','homewear_bottom','short_length',NULL,'lounge/homewear shorts'),
('uniqlo','E488358','homewear_bottom','short_length',NULL,'lounge/homewear shorts'),
('uniqlo','E488426','sweat_jogger_pants','long_length',NULL,'explicit sweat pants'),
('uniqlo','E488694','denim_pants','short_length',NULL,'denim culotte'),
('uniqlo','E488738','denim_pants','short_length',NULL,'denim skorts'),
('uniqlo','E488814','slacks_trousers','short_length',NULL,'smart culotte'),
('uniqlo','E488997','casual_pants','short_length',NULL,'generic shorts'),
('uniqlo','E489049','homewear_bottom','short_length',NULL,'lounge/homewear shorts'),
('uniqlo','E489065','casual_pants','short_length',NULL,'skorts in shorts/skirt-pants retailer path'),
('uniqlo','E489125','casual_pants','short_length',NULL,'generic shorts'),
('uniqlo','E489417','casual_pants','long_length',NULL,'barrel leg long length'),
('zara','545473154','casual_pants','long_length',NULL,'skirt pants fashion trousers'),
('zara','548577264','casual_pants','long_length',NULL,'barrel pants'),
('zara','555161842','chino_cotton_pants','long_length',NULL,'explicit chino'),
('zara','555162424','chino_cotton_pants','long_length',NULL,'explicit chino'),
('zara','556139700','slacks_trousers','long_length',NULL,'explicit suit trousers'),
('zara','560347128','casual_pants','long_length',NULL,'poplin woven pants'),
('zara','561264931','chino_cotton_pants','long_length',NULL,'explicit chino'),
('zara','561610369','casual_pants','long_length',NULL,'bombacho pants');

  IF (SELECT count(*) FROM _bottom_decisions)<>100 THEN RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_decision_count_mismatch'; END IF;

  SELECT count(*) INTO v_count FROM fitmatch_vnext.products v
  JOIN _bottom_decisions d ON d.source_code=v.source_code AND d.source_product_key=v.source_product_key
  WHERE v.classification_status='CONFIRMED' AND v.garment_type_code='other_standard_pants';
  IF v_count<>100 THEN RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_target_preimage_mismatch'; END IF;

  IF EXISTS (SELECT 1 FROM _bottom_decisions d LEFT JOIN fitmatch_vnext.garment_types g
    ON g.garment_type_code=d.new_garment AND g.is_active
    WHERE g.garment_type_code IS NULL OR NOT g.uses_lower_length) THEN
    RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_invalid_target_garment';
  END IF;

  CREATE TEMP TABLE _bottom_tuple_map(garment text PRIMARY KEY,category_code text NOT NULL,detail_code text NOT NULL,family_code text NOT NULL) ON COMMIT DROP;
  INSERT INTO _bottom_tuple_map VALUES
    ('casual_pants','bottoms','casual_pants','standard_pants'),
    ('denim_pants','bottoms','jeans','standard_pants'),
    ('chino_cotton_pants','bottoms','chino_cotton','standard_pants'),
    ('cargo_pants','bottoms','cargo_utility','standard_pants'),
    ('slacks_trousers','bottoms','slacks_trousers','standard_pants'),
    ('sweat_jogger_pants','bottoms','sweat_jogger','standard_pants'),
    ('homewear_bottom','homewear','homewear_bottom','homewear_bottom'),
    ('sports_bottom','bottoms','sports_bottom','sports_bottom');

  IF EXISTS (SELECT 1 FROM _bottom_tuple_map t
    LEFT JOIN public.garment_types g ON g.code=t.garment AND g.is_active
    LEFT JOIN public.app_categories parent ON parent.code=t.category_code AND parent.depth=0 AND parent.parent_id IS NULL AND parent.is_active
    LEFT JOIN public.app_categories detail ON detail.code=t.detail_code AND detail.depth=1 AND detail.parent_id=parent.id AND detail.is_active
    LEFT JOIN public.comparison_groups family ON family.code=t.family_code AND family.is_active
    WHERE g.code IS NULL OR parent.id IS NULL OR detail.id IS NULL OR family.code IS NULL
      OR g.major_category_code IS DISTINCT FROM t.category_code OR g.comparison_group_code IS DISTINCT FROM t.family_code) THEN
    RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_tuple_contract_invalid';
  END IF;

  CREATE TEMP TABLE _bottom_old_hist ON COMMIT DROP AS SELECT * FROM fitmatch_catalog.product_classification_history WHERE is_current;
  IF (SELECT count(*) FROM _bottom_old_hist)<>1608 OR (SELECT count(*) FROM _bottom_old_hist WHERE mapping_release_id=v_parent.id)<>1608 THEN
    RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_history_preimage_mismatch';
  END IF;

  INSERT INTO fitmatch_catalog.releases(id,release_key,taxonomy_version,policy_version,status,bundle_checksum,
    app_taxonomy_checksum,expected_mapping_count,expected_qa_count,metadata,validation_contract_version,validation_report,release_gate_result)
  VALUES(v_new_id,v_new_key,v_parent.taxonomy_version,v_parent.policy_version,'loading',v_parent.bundle_checksum,
    v_parent.app_taxonomy_checksum,3510,1608,
    jsonb_build_object('phase','Bottom taxonomy exact adjudication','review_zero',true,
      'change_scope','other_standard_pants_100_reclassification_and_exact_auto_length_policy','parent_release_id',v_parent.id,
      'reclassified_product_count',100,'automatic_bottom_length_policy','exact_class',
      'manual_cross_length_policy','app_extended_excluding_total_length_and_hem','future_product_fallback','runtime_resolve_product_classification_v4'),
    'fitmatch-release-gate-v5-bottom-reclassification','{}'::jsonb,'{}'::jsonb);

  INSERT INTO fitmatch_catalog.source_category_mappings(release_id,source_identity,source,snapshot_id,external_category_id,target,
    normalized_path,decision_status,mapping_status,runtime_lookup_eligible,eligibility,semantic_category_code,semantic_garment_type,
    comparison_family,source_external_key,source_external_target_key,source_path_key,source_target_path_key,raw_record)
  SELECT v_new_id,source_identity,source,snapshot_id,external_category_id,target,normalized_path,decision_status,mapping_status,
    runtime_lookup_eligible,eligibility,semantic_category_code,semantic_garment_type,comparison_family,source_external_key,
    source_external_target_key,source_path_key,source_target_path_key,raw_record
  FROM fitmatch_catalog.source_category_mappings WHERE release_id=v_parent.id;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>3510 THEN RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_mapping_copy_count_mismatch'; END IF;

  INSERT INTO fitmatch_catalog.classification_structured_discriminator_rules(release_id,rule_id,source,discriminator_key,discriminator_value,
    external_category_id,normalized_path,target,outcome,category_code,detail_code,garment_type_code,family_code,length_code,body_length_code,
    exclusion_reason_code,authority_status,resolution_scope,runtime_eligible,evidence,policy_version)
  SELECT v_new_id,rule_id,source,discriminator_key,discriminator_value,external_category_id,normalized_path,target,outcome,category_code,
    detail_code,garment_type_code,family_code,length_code,body_length_code,exclusion_reason_code,authority_status,resolution_scope,
    runtime_eligible,evidence,policy_version
  FROM fitmatch_catalog.classification_structured_discriminator_rules WHERE release_id=v_parent.id;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>21 THEN RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_rule_copy_count_mismatch'; END IF;

  UPDATE fitmatch_vnext.products v SET garment_type_code=d.new_garment,lower_length_code=d.new_length,
      product_structure_code=coalesce(d.new_structure,v.product_structure_code),classification_source='ADMIN_OVERRIDE',classified_at=v_now,
      source_extra=coalesce(v.source_extra,'{}'::jsonb)||jsonb_build_object('_bottom_reclassification',v_new_key,
        '_bottom_reclassification_basis',d.basis,'_bottom_reclassification_previous_garment',v.garment_type_code,
        '_bottom_reclassification_previous_length',v.lower_length_code,'_bottom_reclassification_structure_override',d.new_structure),
      updated_at=v_now
  FROM _bottom_decisions d
  WHERE v.source_code=d.source_code AND v.source_product_key=d.source_product_key
    AND v.classification_status='CONFIRMED' AND v.garment_type_code='other_standard_pants';
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>100 THEN RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_product_update_count_mismatch'; END IF;

  UPDATE public.comparison_policy_length_axes SET match_mode='exact_class'
  WHERE policy_code='standard_pants_v1' AND axis_code='leg';
  GET DIAGNOSTICS v_policy_rows=ROW_COUNT;
  IF v_policy_rows<>1 THEN RAISE EXCEPTION USING errcode='23514', message='standard_pants_length_policy_axis_update_failed'; END IF;

  UPDATE public.comparison_policies
  SET evidence_note='표준 바지는 자동 비교 시 하의 길이 class가 정확히 같아야 한다. 서로 다른 길이는 사용자 수동 선택의 extended 비교만 허용한다.',updated_at=v_now
  WHERE code='standard_pants_v1' AND is_active;
  GET DIAGNOSTICS v_policy_rows=ROW_COUNT;
  IF v_policy_rows<>1 THEN RAISE EXCEPTION USING errcode='23514', message='standard_pants_policy_note_update_failed'; END IF;

  IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.comparison_policies
      WHERE policy_code='standard_pants' AND is_active AND lower_length_mismatch_policy='REQUIRE_MATCH') THEN
    RAISE EXCEPTION USING errcode='23514', message='vnext_standard_pants_require_match_missing';
  END IF;

  UPDATE fitmatch_catalog.product_classification_history SET is_current=false,superseded_at=v_now WHERE is_current;
  GET DIAGNOSTICS v_history_rows=ROW_COUNT;
  IF v_history_rows<>1608 THEN RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_history_supersede_count_mismatch'; END IF;

  INSERT INTO fitmatch_catalog.product_classification_history(product_id,input_fingerprint,category_code,detail_code,comparison_family_code,
    length_code,classification_status,classification_method,confidence,requires_user_confirmation,taxonomy_policy_version,mapping_release_id,
    decision_version,evidence,is_current,reviewed_by,reviewed_at,body_length_code,garment_type_code)
  SELECT oh.product_id,oh.input_fingerprint,
    CASE WHEN d.source_product_key IS NOT NULL THEN t.category_code ELSE oh.category_code END,
    CASE WHEN d.source_product_key IS NOT NULL THEN t.detail_code ELSE oh.detail_code END,
    CASE WHEN d.source_product_key IS NOT NULL THEN t.family_code ELSE oh.comparison_family_code END,
    CASE WHEN d.source_product_key IS NOT NULL THEN d.new_length ELSE oh.length_code END,
    oh.classification_status,'migration',CASE WHEN d.source_product_key IS NOT NULL THEN 1.0 ELSE oh.confidence END,
    CASE WHEN d.source_product_key IS NOT NULL THEN false ELSE oh.requires_user_confirmation END,
    'db-classifier-2026-08-26-final',v_new_id,'bottom-other-reclassification-2026-08-29-v1',
    coalesce(oh.evidence,'{}'::jsonb)||jsonb_build_object('exact_product_authority',true,'mapping_release_key',v_new_key,'materialized_release_id',v_new_id::text)
      ||CASE WHEN d.source_product_key IS NOT NULL THEN jsonb_build_object('bottom_reclassification',v_new_key,
        'bottom_reclassification_basis',d.basis,'bottom_reclassification_previous_garment',oh.garment_type_code,
        'bottom_reclassification_previous_length',oh.length_code) ELSE '{}'::jsonb END,
    true,oh.reviewed_by,oh.reviewed_at,CASE WHEN d.source_product_key IS NOT NULL THEN NULL ELSE oh.body_length_code END,
    CASE WHEN d.source_product_key IS NOT NULL THEN d.new_garment ELSE oh.garment_type_code END
  FROM _bottom_old_hist oh
  JOIN fitmatch_catalog.products p ON p.id=oh.product_id
  LEFT JOIN _bottom_decisions d ON d.source_code=p.source AND d.source_product_key=p.external_product_id
  LEFT JOIN _bottom_tuple_map t ON t.garment=d.new_garment;
  GET DIAGNOSTICS v_history_rows=ROW_COUNT;
  IF v_history_rows<>1608 THEN RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_history_insert_count_mismatch'; END IF;
  IF (SELECT count(*) FROM fitmatch_catalog.product_classification_history WHERE is_current AND mapping_release_id=v_new_id)<>1608 THEN
    RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_current_history_count_mismatch';
  END IF;

  SELECT encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'source_identity',m.source_identity,'source',m.source,'snapshot_id',m.snapshot_id,'external_category_id',m.external_category_id,
      'target',m.target,'normalized_path',m.normalized_path,'decision_status',m.decision_status,'mapping_status',m.mapping_status,
      'runtime_lookup_eligible',m.runtime_lookup_eligible,'eligibility',m.eligibility,'semantic_category_code',m.semantic_category_code,
      'semantic_garment_type',m.semantic_garment_type,'comparison_family',m.comparison_family,'source_external_key',m.source_external_key,
      'source_external_target_key',m.source_external_target_key,'source_path_key',m.source_path_key,'source_target_path_key',m.source_target_path_key,
      'raw_record',m.raw_record)::text,E'\n' ORDER BY m.source_identity),''),'sha256'),'hex')
  INTO v_mapping_checksum FROM fitmatch_catalog.source_category_mappings m WHERE m.release_id=v_new_id;

  SELECT encode(extensions.digest(coalesce(string_agg(p.source||'|'||p.external_product_id||'|'||p.input_fingerprint||'|'||
    CASE v.classification_status WHEN 'CONFIRMED' THEN 'confirmed' ELSE 'not_comparable' END||'|'||coalesce(v.garment_type_code,'')||'|'||
    coalesce(CASE WHEN gt.uses_sleeve_length THEN v.sleeve_length_code WHEN gt.uses_lower_length THEN v.lower_length_code END,'')||'|'||
    coalesce(CASE WHEN gt.uses_body_length THEN v.body_length_code END,''),E'\n' ORDER BY p.source,p.external_product_id),''),'sha256'),'hex')
  INTO v_exact_checksum
  FROM fitmatch_vnext.products v JOIN fitmatch_catalog.products p ON p.source=v.source_code AND p.external_product_id=v.source_product_key
  LEFT JOIN fitmatch_vnext.garment_types gt ON gt.garment_type_code=v.garment_type_code;

  SELECT encode(extensions.digest(coalesce(string_agg(source_code||'|'||source_product_key||'|'||coalesce(garment_type_code,'')||'|'||
      coalesce(lower_length_code,''),E'\n' ORDER BY source_code,source_product_key),''),'sha256'),'hex')
  INTO v_target_checksum FROM fitmatch_vnext.products WHERE source_extra->>'_bottom_reclassification'=v_new_key;
  IF v_target_checksum<>'9c183490b228569b6b4d63e7e50a52d08488e58c1a35483df54dec4c446b6d9b' THEN
    RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_target_checksum_failed';
  END IF;

  SELECT count(*) INTO v_rule_count FROM fitmatch_catalog.classification_structured_discriminator_rules WHERE release_id=v_new_id;
  v_bundle_checksum:=encode(extensions.digest(v_mapping_checksum||'|'||v_exact_checksum||'|'||v_rule_count::text,'sha256'),'hex');

  UPDATE fitmatch_catalog.releases
  SET bundle_checksum=v_bundle_checksum,status='validated',validated_at=v_now,
      validation_report=jsonb_build_object('source_mapping_checksum',v_mapping_checksum,'exact_authority_checksum',v_exact_checksum,
        'target_decision_checksum',v_target_checksum,'shadow_product_count',1608,'confirmed_count',1421,'review_required_count',0,
        'not_comparable_count',187,'reclassified_product_count',100,'other_standard_pants_after',0,'casual_pants_count',49,
        'homewear_bottom_count',14,'chino_cotton_pants_count',7,'denim_pants_count',10,'sports_bottom_count',8,
        'sweat_jogger_pants_count',6,'cargo_pants_count',3,'slacks_trousers_count',3,'short_length_count',57,'long_length_count',33,
        'ankle_length_count',9,'cropped_length_count',1,'automatic_bottom_length_policy','exact_class',
        'manual_cross_length_policy','app_extended_excluding_total_length_and_hem','history_write_count',1608,'history_delete_count',0,
        'production_product_update_count',100)
  WHERE id=v_new_id;

  v_gate:=fitmatch_catalog.runtime_bottom_reclassification_gate_v1(v_new_id);
  IF NOT coalesce((v_gate->>'eligible')::boolean,false) THEN
    RAISE EXCEPTION USING errcode='23514',message='bottom_reclassification_pre_activation_gate_failed',detail=v_gate::text;
  END IF;

  PERFORM fitmatch_catalog.runtime_activate_validated_release(v_new_id);
  IF NOT EXISTS (SELECT 1 FROM fitmatch_catalog.releases WHERE id=v_new_id AND status='active'
      AND coalesce((release_gate_result->>'eligible')::boolean,false)) THEN
    RAISE EXCEPTION USING errcode='23514', message='bottom_reclassification_activation_failed';
  END IF;
END
$do$;;
