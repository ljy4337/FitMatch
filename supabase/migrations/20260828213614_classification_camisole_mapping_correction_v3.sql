CREATE OR REPLACE FUNCTION fitmatch_catalog.runtime_camisole_mapping_correction_gate_v1(p_release_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $function$
DECLARE
  v_release fitmatch_catalog.releases%rowtype;
  v_parent_id uuid;
  v_mapping_count integer;
  v_parent_parity integer;
  v_corrected_mapping_count integer;
  v_rule_count integer;
  v_rule_parity integer;
  v_history_count integer;
  v_confirmed integer;
  v_review integer;
  v_not_comparable integer;
  v_fingerprint_parity integer;
  v_history_parity integer;
  v_corrected_history_count integer;
  v_corrected_product_count integer;
  v_vnext_mapping_count integer;
  v_legacy_mapping_count integer;
  v_core_invalid integer;
  v_set_leaks integer;
  v_mapping_checksum text;
  v_exact_checksum text;
  v_bundle_checksum text;
  v_blockers jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_release FROM fitmatch_catalog.releases WHERE id=p_release_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='release_not_found'; END IF;
  SELECT id INTO v_parent_id FROM fitmatch_catalog.releases
  WHERE release_key='fitmatch-vnext-exact-authority-review-zero-2026-08-28-v1';

  IF v_parent_id IS NULL
     OR v_release.release_key<>'fitmatch-camisole-mapping-correction-2026-08-29-v1'
     OR v_release.validation_contract_version<>'fitmatch-release-gate-v4-camisole-correction'
     OR v_release.status NOT IN ('validated','active')
     OR v_release.expected_mapping_count<>3510
     OR v_release.expected_qa_count<>1608
     OR v_release.validated_at IS NULL
  THEN v_blockers:=v_blockers||jsonb_build_array('release_identity_or_contract_mismatch'); END IF;

  SELECT count(*) INTO v_mapping_count FROM fitmatch_catalog.source_category_mappings WHERE release_id=p_release_id;
  SELECT count(*) INTO v_parent_parity
  FROM fitmatch_catalog.source_category_mappings parent
  JOIN fitmatch_catalog.source_category_mappings child
    ON child.release_id=p_release_id AND child.source_identity=parent.source_identity
  WHERE parent.release_id=v_parent_id
    AND NOT(parent.source='uniqlo' AND parent.external_category_id IN ('141498','58275','58636'))
    AND (to_jsonb(child)-'release_id'-'created_at') IS NOT DISTINCT FROM (to_jsonb(parent)-'release_id'-'created_at');

  SELECT count(*) INTO v_corrected_mapping_count
  FROM fitmatch_catalog.source_category_mappings m
  WHERE m.release_id=p_release_id AND m.source='uniqlo'
    AND m.external_category_id IN ('141498','58275','58636')
    AND m.semantic_category_code='underwear'
    AND m.semantic_garment_type='women_camisole'
    AND m.comparison_family='women_camisole'
    AND m.raw_record->>'semanticCategoryCode'='underwear'
    AND m.raw_record->>'semanticGarmentType'='women_camisole'
    AND m.raw_record->'appMapping'->>'categoryCode'='underwear'
    AND m.raw_record->'appMapping'->>'detailCode'='women_camisole'
    AND m.raw_record->'appMapping'->>'currentComparisonFamily'='women_camisole'
    AND m.raw_record->'authorityContract'->>'authorityStatus'='verified'
    AND m.raw_record->'authorityContract'->>'resolutionScope'='category_direct'
    AND coalesce((m.raw_record->'authorityContract'->>'productRequired')::boolean,false)=false;
  IF v_mapping_count<>3510 OR v_parent_parity<>3507 OR v_corrected_mapping_count<>3 THEN
    v_blockers:=v_blockers||jsonb_build_array('source_mapping_correction_or_parity_failed');
  END IF;

  SELECT count(*) INTO v_rule_count FROM fitmatch_catalog.classification_structured_discriminator_rules WHERE release_id=p_release_id;
  SELECT count(*) INTO v_rule_parity
  FROM fitmatch_catalog.classification_structured_discriminator_rules parent
  JOIN fitmatch_catalog.classification_structured_discriminator_rules child
    ON child.release_id=p_release_id AND child.rule_id=parent.rule_id
  WHERE parent.release_id=v_parent_id
    AND (to_jsonb(child)-'release_id'-'created_at') IS NOT DISTINCT FROM (to_jsonb(parent)-'release_id'-'created_at');
  IF v_rule_count<>21 OR v_rule_parity<>21 THEN v_blockers:=v_blockers||jsonb_build_array('structured_rule_parity_failed'); END IF;

  SELECT count(*),count(*) FILTER(WHERE classification_status='confirmed'),
         count(*) FILTER(WHERE classification_status='review_required'),
         count(*) FILTER(WHERE classification_status='not_comparable')
  INTO v_history_count,v_confirmed,v_review,v_not_comparable
  FROM fitmatch_catalog.product_classification_history
  WHERE is_current AND mapping_release_id=p_release_id AND evidence @> '{"exact_product_authority":true}'::jsonb;
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
  WHERE h.is_current AND h.mapping_release_id=p_release_id AND (
    (v.classification_status='CONFIRMED' AND h.classification_status='confirmed'
      AND h.garment_type_code IS NOT DISTINCT FROM v.garment_type_code
      AND h.length_code IS NOT DISTINCT FROM CASE WHEN gt.uses_sleeve_length THEN v.sleeve_length_code WHEN gt.uses_lower_length THEN v.lower_length_code ELSE NULL END
      AND h.body_length_code IS NOT DISTINCT FROM CASE WHEN gt.uses_body_length THEN v.body_length_code ELSE NULL END)
    OR
    (v.classification_status='NOT_APPLICABLE' AND h.classification_status='not_comparable'
      AND h.category_code IS NULL AND h.detail_code IS NULL AND h.garment_type_code IS NULL
      AND h.comparison_family_code IS NULL AND h.length_code IS NULL AND h.body_length_code IS NULL));
  IF v_history_parity<>1608 THEN v_blockers:=v_blockers||jsonb_build_array('vnext_history_exact_parity_failed'); END IF;

  SELECT count(*) INTO v_corrected_history_count
  FROM fitmatch_catalog.product_classification_history h
  JOIN fitmatch_catalog.products p ON p.id=h.product_id
  WHERE h.is_current AND h.mapping_release_id=p_release_id AND p.source='uniqlo'
    AND p.external_product_id IN ('E485709','E485710','E485711','E487121','E489044','E482148','E481994')
    AND h.classification_status='confirmed' AND h.category_code='underwear'
    AND h.detail_code='women_camisole' AND h.garment_type_code='women_camisole'
    AND h.comparison_family_code='women_camisole' AND h.length_code='sleeveless' AND h.body_length_code IS NULL;
  IF v_corrected_history_count<>7 THEN v_blockers:=v_blockers||jsonb_build_array('camisole_runtime_history_failed'); END IF;

  SELECT count(*) INTO v_corrected_product_count FROM fitmatch_vnext.products
  WHERE source_code='uniqlo' AND source_product_key IN ('E485709','E485710','E485711','E487121','E489044','E482148','E481994')
    AND classification_status='CONFIRMED' AND garment_type_code='women_camisole' AND sleeve_length_code='sleeveless';
  IF v_corrected_product_count<>7 THEN v_blockers:=v_blockers||jsonb_build_array('camisole_vnext_product_failed'); END IF;

  SELECT count(*) INTO v_vnext_mapping_count
  FROM fitmatch_vnext.classification_signal_mappings m
  JOIN fitmatch_vnext.source_classification_signals s ON s.id=m.source_signal_id
  WHERE s.source_code='uniqlo' AND s.signal_kind='CATEGORY' AND s.external_key IN ('141498','58275','58636')
    AND m.is_active AND m.is_verified AND m.resolution_mode='DIRECT'
    AND m.garment_type_code='women_camisole' AND m.sleeve_length_code='sleeveless';
  IF v_vnext_mapping_count<>3 THEN v_blockers:=v_blockers||jsonb_build_array('camisole_vnext_mapping_failed'); END IF;

  SELECT count(*) INTO v_legacy_mapping_count
  FROM public.source_categories sc
  JOIN public.sources src ON src.id=sc.source_id
  JOIN public.source_category_mappings scm ON scm.source_category_id=sc.id
  JOIN public.garment_types g ON g.id=scm.garment_type_id
  WHERE src.code='uniqlo' AND sc.external_category_id IN ('141498','58275','58636')
    AND sc.app_category='underwear' AND sc.app_detail_category='women_camisole'
    AND g.code='women_camisole' AND scm.default_sleeve_class_code='sleeveless';
  IF v_legacy_mapping_count<>3 THEN v_blockers:=v_blockers||jsonb_build_array('camisole_legacy_mapping_failed'); END IF;

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
  FROM fitmatch_catalog.product_classification_history h JOIN fitmatch_vnext.products v ON v.id=h.product_id
  WHERE h.is_current AND h.mapping_release_id=p_release_id AND v.product_structure_code='SET' AND h.classification_status<>'not_comparable';
  IF v_set_leaks<>0 THEN v_blockers:=v_blockers||jsonb_build_array('set_comparison_leak'); END IF;

  IF (SELECT count(*) FROM fitmatch_vnext.products)<>1608
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='CONFIRMED')<>1421
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='REVIEW_REQUIRED')<>0
     OR (SELECT count(*) FROM fitmatch_vnext.products WHERE classification_status='NOT_APPLICABLE')<>187
  THEN v_blockers:=v_blockers||jsonb_build_array('vnext_population_changed'); END IF;

  SELECT encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'source_identity',m.source_identity,'source',m.source,'snapshot_id',m.snapshot_id,'external_category_id',m.external_category_id,
      'target',m.target,'normalized_path',m.normalized_path,'decision_status',m.decision_status,'mapping_status',m.mapping_status,
      'runtime_lookup_eligible',m.runtime_lookup_eligible,'eligibility',m.eligibility,'semantic_category_code',m.semantic_category_code,
      'semantic_garment_type',m.semantic_garment_type,'comparison_family',m.comparison_family,'source_external_key',m.source_external_key,
      'source_external_target_key',m.source_external_target_key,'source_path_key',m.source_path_key,'source_target_path_key',m.source_target_path_key,
      'raw_record',m.raw_record)::text,E'\n' ORDER BY m.source_identity),''),'sha256'),'hex')
  INTO v_mapping_checksum FROM fitmatch_catalog.source_category_mappings m WHERE m.release_id=p_release_id;

  SELECT encode(extensions.digest(coalesce(string_agg(
    p.source||'|'||p.external_product_id||'|'||p.input_fingerprint||'|'||CASE v.classification_status WHEN 'CONFIRMED' THEN 'confirmed' ELSE 'not_comparable' END||'|'||
    coalesce(v.garment_type_code,'')||'|'||coalesce(CASE WHEN gt.uses_sleeve_length THEN v.sleeve_length_code WHEN gt.uses_lower_length THEN v.lower_length_code END,'')||'|'||
    coalesce(CASE WHEN gt.uses_body_length THEN v.body_length_code END,''),E'\n' ORDER BY p.source,p.external_product_id),''),'sha256'),'hex')
  INTO v_exact_checksum
  FROM fitmatch_vnext.products v JOIN fitmatch_catalog.products p ON p.source=v.source_code AND p.external_product_id=v.source_product_key
  LEFT JOIN fitmatch_vnext.garment_types gt ON gt.garment_type_code=v.garment_type_code;

  v_bundle_checksum:=encode(extensions.digest(v_mapping_checksum||'|'||v_exact_checksum||'|'||v_rule_count::text,'sha256'),'hex');
  IF v_release.validation_report->>'source_mapping_checksum' IS DISTINCT FROM v_mapping_checksum
     OR v_release.validation_report->>'exact_authority_checksum' IS DISTINCT FROM v_exact_checksum
     OR v_release.bundle_checksum IS DISTINCT FROM v_bundle_checksum
  THEN v_blockers:=v_blockers||jsonb_build_array('release_checksum_mismatch'); END IF;

  IF NOT EXISTS(SELECT 1 FROM fitmatch_catalog.product_classification_history h JOIN fitmatch_catalog.products p ON p.id=h.product_id
    WHERE h.is_current AND h.mapping_release_id=p_release_id AND p.source='zara' AND p.external_product_id='545427337'
      AND h.classification_status='confirmed' AND h.garment_type_code='jacket')
  THEN v_blockers:=v_blockers||jsonb_build_array('zara_07782343_regression'); END IF;

  RETURN jsonb_build_object('contract_version','fitmatch-release-gate-v4-camisole-correction','release_id',v_release.id,'release_key',v_release.release_key,
    'eligible',jsonb_array_length(v_blockers)=0,'blockers',v_blockers,'mapping_count',v_mapping_count,'parent_mapping_parity',v_parent_parity,
    'corrected_mapping_count',v_corrected_mapping_count,'rule_count',v_rule_count,'rule_parity',v_rule_parity,'history_count',v_history_count,
    'confirmed_count',v_confirmed,'review_required_count',v_review,'not_comparable_count',v_not_comparable,'history_parity_count',v_history_parity,
    'fingerprint_parity_count',v_fingerprint_parity,'corrected_history_count',v_corrected_history_count,'corrected_product_count',v_corrected_product_count,
    'vnext_mapping_count',v_vnext_mapping_count,'legacy_mapping_count',v_legacy_mapping_count,'core_tuple_invalid_count',v_core_invalid,'set_leak_count',v_set_leaks,
    'source_mapping_checksum',v_mapping_checksum,'exact_authority_checksum',v_exact_checksum,'bundle_checksum',v_bundle_checksum);
END
$function$;

CREATE OR REPLACE FUNCTION fitmatch_catalog.runtime_release_gate_report(p_release_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE v_release_key text;
BEGIN
  SELECT release_key INTO v_release_key FROM fitmatch_catalog.releases WHERE id=p_release_id;
  IF v_release_key='fitmatch-camisole-mapping-correction-2026-08-29-v1' THEN RETURN fitmatch_catalog.runtime_camisole_mapping_correction_gate_v1(p_release_id); END IF;
  IF p_release_id='12100000-0000-4000-8000-000000000121'::uuid THEN RETURN fitmatch_catalog.runtime_review_zero_gate_v1(p_release_id); END IF;
  IF p_release_id='12000000-0000-4000-8000-000000000120'::uuid THEN RETURN fitmatch_catalog.runtime_audience_scope_correction_gate_v1(p_release_id); END IF;
  RETURN fitmatch_catalog.runtime_release_gate_report_pre120_v2(p_release_id);
END
$function$;

DO $do$
DECLARE
  v_parent_id uuid;
  v_new_release_id uuid:=gen_random_uuid();
  v_now timestamptz:=now();
  v_mapping_checksum text;
  v_exact_checksum text;
  v_bundle_checksum text;
  v_count integer;
BEGIN
  SELECT id INTO v_parent_id FROM fitmatch_catalog.releases
  WHERE release_key='fitmatch-vnext-exact-authority-review-zero-2026-08-28-v1' AND status='active';
  IF v_parent_id IS NULL THEN RAISE EXCEPTION 'active parent release 121 not found'; END IF;
  IF EXISTS(SELECT 1 FROM fitmatch_catalog.releases WHERE release_key='fitmatch-camisole-mapping-correction-2026-08-29-v1') THEN RAISE EXCEPTION 'camisole correction release already exists'; END IF;

  SELECT count(*) INTO v_count
  FROM public.source_categories sc JOIN public.sources src ON src.id=sc.source_id
  JOIN public.source_category_mappings scm ON scm.source_category_id=sc.id JOIN public.garment_types g ON g.id=scm.garment_type_id
  WHERE src.code='uniqlo' AND sc.external_category_id IN ('141498','58275','58636') AND g.code='tank_top';
  IF v_count<>3 THEN RAISE EXCEPTION 'legacy camisole preimage mismatch: %',v_count; END IF;

  SELECT count(*) INTO v_count
  FROM fitmatch_vnext.classification_signal_mappings m JOIN fitmatch_vnext.source_classification_signals s ON s.id=m.source_signal_id
  WHERE s.source_code='uniqlo' AND s.signal_kind='CATEGORY' AND s.external_key IN ('141498','58275','58636')
    AND m.is_active AND m.is_verified AND m.resolution_mode='DIRECT' AND m.garment_type_code='tank_top' AND m.sleeve_length_code='sleeveless';
  IF v_count<>3 THEN RAISE EXCEPTION 'vnext camisole mapping preimage mismatch: %',v_count; END IF;

  SELECT count(*) INTO v_count FROM fitmatch_vnext.products
  WHERE source_code='uniqlo' AND source_product_key IN ('E485709','E485710','E485711','E487121','E489044','E482148','E481994')
    AND classification_status='CONFIRMED' AND garment_type_code='base_layer_top';
  IF v_count<>7 THEN RAISE EXCEPTION 'vnext camisole product preimage mismatch: %',v_count; END IF;

  SELECT count(*) INTO v_count FROM fitmatch_catalog.source_category_mappings
  WHERE release_id=v_parent_id AND source='uniqlo' AND external_category_id IN ('141498','58275','58636') AND semantic_garment_type='base_layer_top';
  IF v_count<>3 THEN RAISE EXCEPTION 'runtime camisole mapping preimage mismatch: %',v_count; END IF;

  SELECT count(*) INTO v_count
  FROM fitmatch_catalog.product_classification_history h JOIN fitmatch_catalog.products p ON p.id=h.product_id
  WHERE h.is_current AND h.mapping_release_id=v_parent_id AND p.source='uniqlo'
    AND p.external_product_id IN ('E485709','E485710','E485711','E487121','E489044','E482148','E481994') AND h.garment_type_code='base_layer_top';
  IF v_count<>7 THEN RAISE EXCEPTION 'runtime camisole history preimage mismatch: %',v_count; END IF;

  UPDATE public.source_category_mappings scm
  SET garment_type_id=(SELECT id FROM public.garment_types WHERE code='women_camisole' AND is_active),default_sleeve_class_code='sleeveless',
      evidence=jsonb_set(coalesce(scm.evidence,'{}'::jsonb),'{taxonomy_full_review,garment_type_candidate}',to_jsonb('women_camisole'::text),true)
        || jsonb_build_object('camisole_correction_20260829',jsonb_build_object('basis','explicit_camisole_source_category_and_existing_app_detail','approved_by','owner','corrected_at',v_now)),
      updated_at=v_now
  FROM public.source_categories sc,public.sources src
  WHERE scm.source_category_id=sc.id AND sc.source_id=src.id AND src.code='uniqlo' AND sc.external_category_id IN ('141498','58275','58636');
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>3 THEN RAISE EXCEPTION 'legacy mapping update count mismatch: %',v_count; END IF;

  UPDATE fitmatch_vnext.classification_signal_mappings m
  SET garment_type_code='women_camisole',sleeve_length_code='sleeveless',updated_at=v_now
  FROM fitmatch_vnext.source_classification_signals s
  WHERE m.source_signal_id=s.id AND s.source_code='uniqlo' AND s.signal_kind='CATEGORY' AND s.external_key IN ('141498','58275','58636')
    AND m.is_active AND m.is_verified AND m.resolution_mode='DIRECT';
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>3 THEN RAISE EXCEPTION 'vnext mapping update count mismatch: %',v_count; END IF;

  UPDATE fitmatch_vnext.products
  SET garment_type_code='women_camisole',sleeve_length_code='sleeveless',classification_source='ADMIN_OVERRIDE',classified_at=v_now,
      source_extra=source_extra||jsonb_build_object('_camisole_mapping_correction','explicit_source_category_to_women_camisole_2026-08-29-v1',
        '_camisole_mapping_basis','official_camisole_category_plus_existing_fitmatch_app_detail'),updated_at=v_now
  WHERE source_code='uniqlo' AND source_product_key IN ('E485709','E485710','E485711','E487121','E489044','E482148','E481994');
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>7 THEN RAISE EXCEPTION 'vnext product update count mismatch: %',v_count; END IF;

  INSERT INTO fitmatch_catalog.releases(id,release_key,taxonomy_version,policy_version,status,bundle_checksum,app_taxonomy_checksum,expected_mapping_count,expected_qa_count,
    metadata,created_at,validated_at,activated_at,validation_contract_version,validation_report,release_gate_checked_at,release_gate_result)
  SELECT v_new_release_id,'fitmatch-camisole-mapping-correction-2026-08-29-v1',taxonomy_version,policy_version,'validated',bundle_checksum,app_taxonomy_checksum,3510,1608,
    metadata||jsonb_build_object('parent_release_id',v_parent_id,'change_scope','uniqlo_camisole_mapping_correction','corrected_category_ids',jsonb_build_array('141498','58275','58636'),'corrected_product_count',7),
    v_now,v_now,NULL,'fitmatch-release-gate-v4-camisole-correction','{}'::jsonb,NULL,'{}'::jsonb
  FROM fitmatch_catalog.releases WHERE id=v_parent_id;

  INSERT INTO fitmatch_catalog.source_category_mappings(release_id,source_identity,source,snapshot_id,external_category_id,target,normalized_path,decision_status,mapping_status,
    runtime_lookup_eligible,eligibility,semantic_category_code,semantic_garment_type,comparison_family,source_external_key,source_external_target_key,source_path_key,source_target_path_key,raw_record,created_at)
  SELECT v_new_release_id,source_identity,source,snapshot_id,external_category_id,target,normalized_path,decision_status,mapping_status,runtime_lookup_eligible,eligibility,
    semantic_category_code,semantic_garment_type,comparison_family,source_external_key,source_external_target_key,source_path_key,source_target_path_key,raw_record,v_now
  FROM fitmatch_catalog.source_category_mappings WHERE release_id=v_parent_id;
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>3510 THEN RAISE EXCEPTION 'mapping clone count mismatch: %',v_count; END IF;

  UPDATE fitmatch_catalog.source_category_mappings
  SET semantic_category_code='underwear',semantic_garment_type='women_camisole',comparison_family='women_camisole',
      raw_record=jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(coalesce(raw_record,'{}'::jsonb),'{semanticCategoryCode}',to_jsonb('underwear'::text),true),
        '{semanticGarmentType}',to_jsonb('women_camisole'::text),true),'{comparisonFamily}',to_jsonb('women_camisole'::text),true),
        '{appMapping,categoryCode}',to_jsonb('underwear'::text),true),'{appMapping,detailCode}',to_jsonb('women_camisole'::text),true),
        '{appMapping,currentComparisonFamily}',to_jsonb('women_camisole'::text),true)
        ||jsonb_build_object('camisoleCorrection',jsonb_build_object('basis','explicit_camisole_source_category_and_existing_fitmatch_app_detail','correctedAt',v_now,'releaseKey','fitmatch-camisole-mapping-correction-2026-08-29-v1'))
  WHERE release_id=v_new_release_id AND source='uniqlo' AND external_category_id IN ('141498','58275','58636');
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>3 THEN RAISE EXCEPTION 'runtime mapping correction count mismatch: %',v_count; END IF;

  INSERT INTO fitmatch_catalog.classification_structured_discriminator_rules(release_id,rule_id,source,discriminator_key,discriminator_value,external_category_id,normalized_path,target,
    outcome,category_code,detail_code,garment_type_code,family_code,length_code,body_length_code,exclusion_reason_code,authority_status,resolution_scope,runtime_eligible,evidence,policy_version,created_at)
  SELECT v_new_release_id,rule_id,source,discriminator_key,discriminator_value,external_category_id,normalized_path,target,outcome,category_code,detail_code,garment_type_code,family_code,
    length_code,body_length_code,exclusion_reason_code,authority_status,resolution_scope,runtime_eligible,evidence,policy_version,v_now
  FROM fitmatch_catalog.classification_structured_discriminator_rules WHERE release_id=v_parent_id;
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>21 THEN RAISE EXCEPTION 'rule clone count mismatch: %',v_count; END IF;

  INSERT INTO fitmatch_catalog.product_classification_history(id,product_id,input_fingerprint,category_code,detail_code,comparison_family_code,length_code,classification_status,
    classification_method,confidence,requires_user_confirmation,taxonomy_policy_version,mapping_release_id,decision_version,evidence,is_current,reviewed_by,reviewed_at,superseded_at,created_at,
    body_length_code,garment_type_code)
  SELECT gen_random_uuid(),product_id,input_fingerprint,category_code,detail_code,comparison_family_code,length_code,classification_status,classification_method,confidence,
    requires_user_confirmation,taxonomy_policy_version,v_new_release_id,'vnext-exact-authority-camisole-correction-2026-08-29-v1',
    jsonb_set(coalesce(evidence,'{}'::jsonb),'{release_id}',to_jsonb(v_new_release_id::text),true)||jsonb_build_object('release_key','fitmatch-camisole-mapping-correction-2026-08-29-v1','camisole_mapping_correction_release',true),
    false,reviewed_by,reviewed_at,NULL,v_now,body_length_code,garment_type_code
  FROM fitmatch_catalog.product_classification_history WHERE is_current AND mapping_release_id=v_parent_id;
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>1608 THEN RAISE EXCEPTION 'history clone count mismatch: %',v_count; END IF;

  UPDATE fitmatch_catalog.product_classification_history h
  SET category_code='underwear',detail_code='women_camisole',comparison_family_code='women_camisole',length_code='sleeveless',body_length_code=NULL,garment_type_code='women_camisole',
      evidence=h.evidence||jsonb_build_object('camisole_mapping_correction',true,'camisole_mapping_basis','explicit_source_category_to_women_camisole','vnext_classification_source','ADMIN_OVERRIDE')
  FROM fitmatch_catalog.products p
  WHERE h.product_id=p.id AND h.mapping_release_id=v_new_release_id AND NOT h.is_current AND p.source='uniqlo'
    AND p.external_product_id IN ('E485709','E485710','E485711','E487121','E489044','E482148','E481994');
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>7 THEN RAISE EXCEPTION 'history correction count mismatch: %',v_count; END IF;

  UPDATE fitmatch_catalog.product_classification_history SET is_current=false,superseded_at=v_now WHERE is_current AND mapping_release_id=v_parent_id;
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>1608 THEN RAISE EXCEPTION 'parent history supersede count mismatch: %',v_count; END IF;
  UPDATE fitmatch_catalog.product_classification_history SET is_current=true WHERE mapping_release_id=v_new_release_id AND NOT is_current AND superseded_at IS NULL;
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>1608 THEN RAISE EXCEPTION 'new history activation count mismatch: %',v_count; END IF;

  SELECT encode(extensions.digest(coalesce(string_agg(jsonb_build_object('source_identity',m.source_identity,'source',m.source,'snapshot_id',m.snapshot_id,
    'external_category_id',m.external_category_id,'target',m.target,'normalized_path',m.normalized_path,'decision_status',m.decision_status,'mapping_status',m.mapping_status,
    'runtime_lookup_eligible',m.runtime_lookup_eligible,'eligibility',m.eligibility,'semantic_category_code',m.semantic_category_code,'semantic_garment_type',m.semantic_garment_type,
    'comparison_family',m.comparison_family,'source_external_key',m.source_external_key,'source_external_target_key',m.source_external_target_key,'source_path_key',m.source_path_key,
    'source_target_path_key',m.source_target_path_key,'raw_record',m.raw_record)::text,E'\n' ORDER BY m.source_identity),''),'sha256'),'hex') INTO v_mapping_checksum
  FROM fitmatch_catalog.source_category_mappings m WHERE m.release_id=v_new_release_id;

  SELECT encode(extensions.digest(coalesce(string_agg(p.source||'|'||p.external_product_id||'|'||p.input_fingerprint||'|'||CASE v.classification_status WHEN 'CONFIRMED' THEN 'confirmed' ELSE 'not_comparable' END||'|'||
    coalesce(v.garment_type_code,'')||'|'||coalesce(CASE WHEN gt.uses_sleeve_length THEN v.sleeve_length_code WHEN gt.uses_lower_length THEN v.lower_length_code END,'')||'|'||
    coalesce(CASE WHEN gt.uses_body_length THEN v.body_length_code END,''),E'\n' ORDER BY p.source,p.external_product_id),''),'sha256'),'hex') INTO v_exact_checksum
  FROM fitmatch_vnext.products v JOIN fitmatch_catalog.products p ON p.source=v.source_code AND p.external_product_id=v.source_product_key
  LEFT JOIN fitmatch_vnext.garment_types gt ON gt.garment_type_code=v.garment_type_code;

  v_bundle_checksum:=encode(extensions.digest(v_mapping_checksum||'|'||v_exact_checksum||'|21','sha256'),'hex');
  UPDATE fitmatch_catalog.releases
  SET bundle_checksum=v_bundle_checksum,validation_report=jsonb_build_object('parent_release_id',v_parent_id,'source_mapping_count',3510,'structured_discriminator_rule_count',21,
    'shadow_product_count',1608,'confirmed_count',1421,'review_required_count',0,'not_comparable_count',187,'corrected_mapping_count',3,'corrected_product_count',7,
    'source_mapping_checksum',v_mapping_checksum,'exact_authority_checksum',v_exact_checksum,'camisole_mapping_correction_validated',true),validated_at=v_now
  WHERE id=v_new_release_id;

  UPDATE fitmatch_catalog.releases SET status='retired' WHERE id=v_parent_id AND status='active';
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>1 THEN RAISE EXCEPTION 'parent release retire failed: %',v_count; END IF;
  UPDATE fitmatch_catalog.releases SET status='active',activated_at=v_now WHERE id=v_new_release_id AND status='validated';
  GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count<>1 THEN RAISE EXCEPTION 'new release activation failed: %',v_count; END IF;
END
$do$;;
