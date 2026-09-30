begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';
select pg_advisory_xact_lock(
  hashtext('fitmatch:measurement-policy-checksum-correction-2026-08-26-v1')
);

-- 118 is already immutable and applied. Its policy rows are semantically
-- identical between the local candidate and Production, but the local fixture
-- stores weight as unconstrained numeric while Production stores numeric(6,3).
-- jsonb preserves numeric scale in text, so the v1 raw checksum treated 1.2
-- and 1.200 as different. Guard both known raw encodings and require one
-- scale-independent canonical checksum before changing the gate contract.
do $migration_guard$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_policy_count integer;
  v_raw_checksum text;
  v_canonical_checksum text;
begin
  if to_regprocedure(
      'fitmatch_catalog.runtime_policy_contract_report_v1(uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_classification_db_final_gate_v1(uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_release_gate_report(uuid)'
    ) is null
  then
    raise exception '119_required_113_118_contract_missing';
  end if;

  select * into v_release
  from fitmatch_catalog.releases
  where id = '11800000-0000-4000-8000-000000000118'::uuid
  for update;

  if not found
    or v_release.release_key is distinct from
      'fitmatch-classification-authority-final-candidate-2026-08-26-v1'
    or v_release.status is distinct from 'validated'
    or v_release.validation_report->>'measurement_policy_checksum'
      not in (
        'd2a98b24f29ddfb57c0e2afa3215a7d9920a2a5f110fe50e301267c443ec4713',
        '42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0'
      )
  then
    raise exception '119_final_candidate_preimage_mismatch';
  end if;

  select count(*),
    encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'category_code', category.code,
      'measurement_key', item.canonical_key,
      'dimension_code', policy.dimension_code,
      'weight', policy.weight,
      'is_primary', policy.is_primary,
      'is_comparable', policy.is_comparable,
      'cross_source_mode', policy.cross_source_mode,
      'required_group_code', policy.required_group_code,
      'required_group_min_dimensions',
        policy.required_group_min_dimensions,
      'display_order', policy.display_order,
      'selection_priority', policy.selection_priority,
      'is_active', policy.is_active,
      'evidence_note', policy.evidence_note
    )::text, E'\n' order by
      category.code collate "C",
      item.canonical_key collate "C",
      policy.dimension_code collate "C"
    ), ''), 'sha256'), 'hex'),
    encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'category_code', category.code,
      'measurement_key', item.canonical_key,
      'dimension_code', policy.dimension_code,
      'weight', trim_scale(policy.weight),
      'is_primary', policy.is_primary,
      'is_comparable', policy.is_comparable,
      'cross_source_mode', policy.cross_source_mode,
      'required_group_code', policy.required_group_code,
      'required_group_min_dimensions',
        policy.required_group_min_dimensions,
      'display_order', policy.display_order,
      'selection_priority', policy.selection_priority,
      'is_active', policy.is_active,
      'evidence_note', policy.evidence_note
    )::text, E'\n' order by
      category.code collate "C",
      item.canonical_key collate "C",
      policy.dimension_code collate "C"
    ), ''), 'sha256'), 'hex')
  into v_policy_count, v_raw_checksum, v_canonical_checksum
  from public.app_category_measurement_policies policy
  join public.app_categories category on category.id = policy.app_category_id
  join public.measurement_items item on item.id = policy.measurement_item_id
  where policy.policy_version = '2026.07.1';

  if v_policy_count <> 63
    or v_raw_checksum not in (
      '6ad654049b08f6d19bd6a59c2a50482f550ee9edf6a0b9faad5d6f74b31a18a2',
      'd2a98b24f29ddfb57c0e2afa3215a7d9920a2a5f110fe50e301267c443ec4713'
    )
    or v_canonical_checksum is distinct from
      '42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0'
  then
    raise exception
      '119_measurement_policy_preimage_mismatch:count=%,raw=%,canonical=%',
      v_policy_count, v_raw_checksum, v_canonical_checksum;
  end if;
end
$migration_guard$;

create or replace function
fitmatch_catalog.runtime_policy_contract_report_v1(
  p_release_id uuid
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_contract jsonb;
  v_classifier_version text;
  v_comparison_version text;
  v_compatibility_version text;
  v_measurement_version text;
  v_classifier_count integer := 0;
  v_comparison_count integer := 0;
  v_compatibility_count integer := 0;
  v_measurement_count integer := 0;
  v_classifier_checksum text;
  v_comparison_checksum text;
  v_compatibility_checksum text;
  v_measurement_checksum text;
  v_blockers jsonb := '[]'::jsonb;
begin
  select * into v_release
  from fitmatch_catalog.releases
  where id = p_release_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'release_not_found';
  end if;

  v_contract := v_release.validation_report->'runtime_policy_contract';
  if jsonb_typeof(v_contract) <> 'object' then
    v_blockers := v_blockers
      || jsonb_build_array('runtime_policy_contract_missing');
  end if;
  v_classifier_version := nullif(btrim(
    v_contract->>'classifier_policy_version'
  ), '');
  v_comparison_version := nullif(btrim(
    v_contract->>'comparison_policy_version'
  ), '');
  v_compatibility_version := nullif(btrim(
    v_contract->>'compatibility_rule_version'
  ), '');
  v_measurement_version := nullif(btrim(
    v_contract->>'measurement_policy_version'
  ), '');

  if v_classifier_version is null then
    v_blockers := v_blockers
      || jsonb_build_array('classifier_policy_version_missing');
  else
    with policy_rows as (
      select concat('name|', source, '|', normalized_path, '|', name_signature) key,
        jsonb_build_object(
          'kind', 'name', 'source', source,
          'normalized_path', normalized_path,
          'name_signature', name_signature,
          'category_code', category_code, 'detail_code', detail_code,
          'comparison_family_code', comparison_family_code,
          'length_code', length_code, 'sample_count', sample_count,
          'review_count', review_count,
          'distinct_decision_count', distinct_decision_count,
          'auto_eligible', auto_eligible, 'evidence', evidence
        ) value
      from fitmatch_catalog.classification_name_profiles
      where policy_version = v_classifier_version
      union all
      select concat('path|', source, '|', normalized_path),
        jsonb_build_object(
          'kind', 'path', 'source', source,
          'normalized_path', normalized_path,
          'category_code', category_code, 'detail_code', detail_code,
          'comparison_family_code', comparison_family_code,
          'length_code', length_code, 'sample_count', sample_count,
          'review_count', review_count,
          'distinct_decision_count', distinct_decision_count,
          'auto_eligible', auto_eligible, 'evidence', evidence
        )
      from fitmatch_catalog.classification_path_profiles
      where policy_version = v_classifier_version
      union all
      select concat('exclusion|', source, '|', normalized_path),
        jsonb_build_object(
          'kind', 'exclusion', 'source', source,
          'normalized_path', normalized_path,
          'sample_count', sample_count, 'auto_eligible', auto_eligible,
          'reason_code', reason_code, 'evidence', evidence
        )
      from fitmatch_catalog.classification_exclusion_profiles
      where policy_version = v_classifier_version
    )
    select count(*), encode(extensions.digest(
      coalesce(string_agg(value::text, E'\n' order by key), ''), 'sha256'
    ), 'hex')
    into v_classifier_count, v_classifier_checksum
    from policy_rows;
    if v_classifier_count = 0 then
      v_blockers := v_blockers
        || jsonb_build_array('classifier_policy_version_missing');
    end if;
  end if;

  if v_comparison_version is null then
    v_blockers := v_blockers
      || jsonb_build_array('comparison_policy_version_missing');
  else
    select count(*), encode(extensions.digest(
      coalesce(string_agg(jsonb_build_object(
        'code', policy.code,
        'comparison_group_code', policy.comparison_group_code,
        'cross_type_mode', policy.cross_type_mode,
        'reference_priority_mode', policy.reference_priority_mode,
        'min_comparable_dimensions', policy.min_comparable_dimensions,
        'required_measurement_group_code',
          policy.required_measurement_group_code,
        'is_active', policy.is_active,
        'evidence_note', policy.evidence_note
      )::text, E'\n' order by policy.code), ''), 'sha256'
    ), 'hex')
    into v_comparison_count, v_comparison_checksum
    from public.comparison_policies policy
    where policy.policy_version = v_comparison_version;
    if v_comparison_count = 0 then
      v_blockers := v_blockers
        || jsonb_build_array('comparison_policy_version_missing');
    end if;
  end if;

  if v_compatibility_version is null then
    v_blockers := v_blockers
      || jsonb_build_array('compatibility_rule_version_missing');
  else
    select count(*), encode(extensions.digest(
      coalesce(string_agg(jsonb_build_object(
        'from_family_code', rule.from_family_code,
        'to_family_code', rule.to_family_code,
        'allowed', rule.allowed,
        'directional', rule.directional,
        'length_match_required', rule.length_match_required,
        'length_mismatch_excluded_measurements',
          rule.length_mismatch_excluded_measurements,
        'minimum_common_measurements', rule.minimum_common_measurements,
        'required_measurements', rule.required_measurements,
        'required_any_measurements', rule.required_any_measurements,
        'minimum_required_any', rule.minimum_required_any,
        'measurement_weights', rule.measurement_weights,
        'fallback_allowed', rule.fallback_allowed
      )::text, E'\n' order by
        rule.from_family_code, rule.to_family_code), ''), 'sha256'
    ), 'hex')
    into v_compatibility_count, v_compatibility_checksum
    from fitmatch_taxonomy.comparison_compatibility_rules rule
    where rule.policy_version = v_compatibility_version;
    if v_compatibility_count = 0 then
      v_blockers := v_blockers
        || jsonb_build_array('compatibility_rule_version_missing');
    end if;
  end if;

  if v_measurement_version is null then
    v_blockers := v_blockers
      || jsonb_build_array('measurement_policy_version_missing');
  else
    select count(*), encode(extensions.digest(
      coalesce(string_agg(jsonb_build_object(
        'category_code', category.code,
        'measurement_key', item.canonical_key,
        'dimension_code', policy.dimension_code,
        'weight', trim_scale(policy.weight),
        'is_primary', policy.is_primary,
        'is_comparable', policy.is_comparable,
        'cross_source_mode', policy.cross_source_mode,
        'required_group_code', policy.required_group_code,
        'required_group_min_dimensions',
          policy.required_group_min_dimensions,
        'display_order', policy.display_order,
        'selection_priority', policy.selection_priority,
        'is_active', policy.is_active,
        'evidence_note', policy.evidence_note
      )::text, E'\n' order by
        category.code collate "C",
        item.canonical_key collate "C",
        policy.dimension_code collate "C"), ''),
      'sha256'
    ), 'hex')
    into v_measurement_count, v_measurement_checksum
    from public.app_category_measurement_policies policy
    join public.app_categories category on category.id = policy.app_category_id
    join public.measurement_items item on item.id = policy.measurement_item_id
    where policy.policy_version = v_measurement_version;
    if v_measurement_count = 0 then
      v_blockers := v_blockers
        || jsonb_build_array('measurement_policy_version_missing');
    end if;
  end if;

  if nullif(v_release.validation_report->>'classifier_policy_checksum', '')
      is distinct from v_classifier_checksum then
    v_blockers := v_blockers
      || jsonb_build_array('classifier_policy_checksum_mismatch');
  end if;
  if nullif(v_release.validation_report->>'comparison_policy_checksum', '')
      is distinct from v_comparison_checksum then
    v_blockers := v_blockers
      || jsonb_build_array('comparison_policy_checksum_mismatch');
  end if;
  if nullif(
      v_release.validation_report->>'compatibility_rule_checksum', ''
    ) is distinct from v_compatibility_checksum then
    v_blockers := v_blockers
      || jsonb_build_array('compatibility_rule_checksum_mismatch');
  end if;
  if nullif(v_release.validation_report->>'measurement_policy_checksum', '')
      is distinct from v_measurement_checksum then
    v_blockers := v_blockers
      || jsonb_build_array('measurement_policy_checksum_mismatch');
  end if;
  if not (v_release.validation_report
      @> '{"runtime_policy_contract_validated":true}'::jsonb) then
    v_blockers := v_blockers
      || jsonb_build_array('runtime_policy_contract_not_validated');
  end if;

  return jsonb_build_object(
    'eligible', jsonb_array_length(v_blockers) = 0,
    'blockers', v_blockers,
    'runtime_policy_contract', v_contract,
    'classifier_policy_count', v_classifier_count,
    'comparison_policy_count', v_comparison_count,
    'compatibility_rule_count', v_compatibility_count,
    'measurement_policy_count', v_measurement_count,
    'classifier_policy_checksum', v_classifier_checksum,
    'comparison_policy_checksum', v_comparison_checksum,
    'compatibility_rule_checksum', v_compatibility_checksum,
    'measurement_policy_checksum', v_measurement_checksum
  );
end
$$;

revoke all on function
  fitmatch_catalog.runtime_policy_contract_report_v1(uuid)
  from public, anon, authenticated;
grant execute on function
  fitmatch_catalog.runtime_policy_contract_report_v1(uuid)
  to service_role;

update fitmatch_catalog.releases
set validation_report = jsonb_set(
      validation_report,
      '{measurement_policy_checksum}',
      to_jsonb(
        '42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0'
          ::text
      ),
      false
    ) || jsonb_build_object(
      'measurement_policy_checksum_contract',
        'semantic-v2-trim-scale-weight-c-collation',
      'measurement_policy_checksum_correction',
        '119_classification_measurement_policy_checksum_correction',
      'measurement_policy_checksum_previous_candidate',
        'd2a98b24f29ddfb57c0e2afa3215a7d9920a2a5f110fe50e301267c443ec4713',
      'measurement_policy_checksum_production_raw_observed',
        '6ad654049b08f6d19bd6a59c2a50482f550ee9edf6a0b9faad5d6f74b31a18a2'
    )
where id = '11800000-0000-4000-8000-000000000118'::uuid;

do $postcondition$
declare
  v_policy_report jsonb;
  v_final_gate jsonb;
  v_release_gate jsonb;
begin
  v_policy_report := fitmatch_catalog.runtime_policy_contract_report_v1(
    '11800000-0000-4000-8000-000000000118'::uuid
  );
  v_final_gate := fitmatch_catalog.runtime_classification_db_final_gate_v1(
    '11800000-0000-4000-8000-000000000118'::uuid
  );
  v_release_gate := fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-000000000118'::uuid
  );

  if (v_policy_report->>'measurement_policy_count')::integer <> 63
    or v_policy_report->>'measurement_policy_checksum' is distinct from
      '42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0'
    or not coalesce((v_policy_report->>'eligible')::boolean, false)
    or jsonb_array_length(coalesce(
      v_policy_report->'blockers', '[]'::jsonb
    )) <> 0
    or not coalesce((v_final_gate->>'eligible')::boolean, false)
    or jsonb_array_length(coalesce(
      v_final_gate->'blockers', '[]'::jsonb
    )) <> 0
    or not coalesce((v_release_gate->>'eligible')::boolean, false)
    or jsonb_array_length(coalesce(
      v_release_gate->'blockers', '[]'::jsonb
    )) <> 0
  then
    raise exception
      '119_candidate_gate_postcondition_failed:policy=%,final=%,release=%',
      v_policy_report, v_final_gate, v_release_gate;
  end if;
end
$postcondition$;

comment on function
  fitmatch_catalog.runtime_policy_contract_report_v1(uuid)
is 'Release policy gate report. Measurement weights are checksum-canonicalized with trim_scale and C collation so equal numeric values hash identically across schema typmods.';

commit;
;
