-- Run only after 113_p3_data_quality_observability.sql in a staging/local DB.
-- The transaction always rolls back and leaves no verification issue row.
begin;

do $$
declare
  v_signature text := 'p3-verification-' || txid_current()::text;
  v_first_id uuid;
  v_second_id uuid;
  v_count integer;
  v_status text;
  v_resolution jsonb;
  v_evidence jsonb;
begin
  v_first_id := fitmatch_catalog.runtime_record_signature_issue(
    'verification',
    'UNKNOWN_MEASUREMENT_ALIAS',
    v_signature,
    'medium',
    jsonb_build_object('attempt', 1)
  );
  v_second_id := fitmatch_catalog.runtime_record_signature_issue(
    'verification',
    'UNKNOWN_MEASUREMENT_ALIAS',
    v_signature,
    'medium',
    jsonb_build_object('attempt', 2)
  );

  select occurrence_count, status
  into v_count, v_status
  from fitmatch_catalog.data_quality_issues
  where id = v_first_id;

  if v_first_id is distinct from v_second_id
     or v_count <> 2
     or v_status <> 'open' then
    raise exception 'signature aggregation failed';
  end if;

  perform fitmatch_catalog.runtime_resolve_signature_issue(
    'verification',
    'UNKNOWN_MEASUREMENT_ALIAS',
    v_signature,
    jsonb_build_object('resolved_by', 'verification')
  );

  select status into v_status
  from fitmatch_catalog.data_quality_issues
  where id = v_first_id;
  if v_status <> 'resolved' then
    raise exception 'signature resolution failed';
  end if;

  v_second_id := fitmatch_catalog.runtime_record_signature_issue(
    'verification',
    'UNKNOWN_MEASUREMENT_ALIAS',
    v_signature,
    'medium',
    jsonb_build_object('attempt', 3)
  );

  select occurrence_count, status, resolution, evidence
  into v_count, v_status, v_resolution, v_evidence
  from fitmatch_catalog.data_quality_issues
  where id = v_first_id;
  if v_first_id is distinct from v_second_id
     or v_count <> 3
     or v_status <> 'open'
     or v_resolution <> '{}'::jsonb
     or v_evidence->'previous_resolution'->>'resolved_by' <> 'verification' then
    raise exception 'resolved issue re-observation failed';
  end if;

  if has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_record_signature_issue(text,text,text,text,jsonb)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_record_signature_issue(text,text,text,text,jsonb)',
      'EXECUTE'
    ) then
    raise exception 'signature issue helper is exposed to an app role';
  end if;
end $$;

do $$
declare
  v_suffix text := txid_current()::text;
  v_external_id text := 'p3-observability-' || txid_current()::text;
  v_category_path text := 'p3 > unknown > ' || txid_current()::text;
  v_raw_code text := 'p3-unknown-' || txid_current()::text;
  v_raw_label text := 'P3 Unknown Span ' || txid_current()::text;
  v_payload jsonb;
  v_observation_id uuid;
  v_result jsonb;
  v_issue_codes text[];
begin
  v_payload := jsonb_build_object(
    'source', 'uniqlo',
    'external_product_id', v_external_id,
    'product_name', 'P3 긴소매 검증 상품 반팔 티셔츠',
    'source_category_path', v_category_path,
    'source_category_codes', jsonb_build_array('P3_UNKNOWN_' || v_suffix),
    'raw_payload', jsonb_build_object(
      'local_classification_conflict', 'true',
      'local_classification_conflict_dimensions', 'length',
      'local_classification_conflict_evidence', 'long_sleeve->short_sleeve',
      'local_classification_safety_policy_version', 'p1-verification'
    ),
    'variants', jsonb_build_array(jsonb_build_object(
      'external_variant_id', '__default__',
      'sizes', jsonb_build_array(jsonb_build_object(
        'size_identity', 'm',
        'size_label', 'M',
        'measurements', jsonb_build_array(jsonb_build_object(
          'measurement_identity', v_raw_code,
          'raw_code', v_raw_code,
          'raw_label', v_raw_label,
          'raw_value', 51,
          'raw_unit', 'cm',
          'raw_representation', 'p3_unverified_basis'
        ))
      ))
    ))
  );

  insert into fitmatch_catalog.product_observations (
    source, external_product_id, payload_fingerprint,
    observation_origin, raw_payload
  ) values (
    'uniqlo', v_external_id, md5(v_payload::text), 'backend', v_payload
  ) returning id into v_observation_id;

  insert into fitmatch_catalog.product_observation_measurements (
    observation_id, external_variant_id, size_identity, size_label,
    measurement_ordinal, measurement_identity, raw_code, raw_label,
    raw_value, raw_unit, raw_representation
  ) values (
    v_observation_id, '__default__', 'm', 'M', 0,
    v_raw_code, v_raw_code, v_raw_label, 51, 'cm', 'p3_unverified_basis'
  );

  v_result := public.fitmatch_process_product_observation(v_observation_id);
  if v_result->>'status' <> 'promoted'
     or coalesce((v_result->'summary'->>'data_quality_issue_count')::integer, 0) <> 3 then
    raise exception 'observation data-quality processing failed: %', v_result;
  end if;

  select array_agg(issue_code order by issue_code)
  into v_issue_codes
  from fitmatch_catalog.data_quality_issues
  where evidence->>'latest_observation_id' = v_observation_id::text
    and status = 'open'
    and issue_fingerprint is not null;

  if v_issue_codes is distinct from array[
      'CLASSIFICATION_CONFLICT',
      'UNKNOWN_MEASUREMENT_ALIAS',
      'UNKNOWN_SOURCE_CATEGORY'
    ]::text[] then
    raise exception 'unexpected observation issue codes: %', v_issue_codes;
  end if;
end $$;

rollback;
