-- Read-only post-119 validation. Run before rollback-successor creation and
-- activation, then run the existing 118 full validation transaction.

begin;

set local transaction read only;
set local statement_timeout = '300s';

do $validation$
declare
  v_policy_count integer;
  v_raw_checksum text;
  v_canonical_checksum text;
  v_policy_report jsonb;
  v_final_gate jsonb;
  v_release_gate jsonb;
  v_proc pg_proc%rowtype;
begin
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
    or v_raw_checksum is distinct from
      '6ad654049b08f6d19bd6a59c2a50482f550ee9edf6a0b9faad5d6f74b31a18a2'
    or v_canonical_checksum is distinct from
      '42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0'
  then
    raise exception
      '119_measurement_checksum_validation_failed:count=%,raw=%,canonical=%',
      v_policy_count, v_raw_checksum, v_canonical_checksum;
  end if;

  v_policy_report := fitmatch_catalog.runtime_policy_contract_report_v1(
    '11800000-0000-4000-8000-000000000118'::uuid
  );
  v_final_gate := fitmatch_catalog.runtime_classification_db_final_gate_v1(
    '11800000-0000-4000-8000-000000000118'::uuid
  );
  v_release_gate := fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-000000000118'::uuid
  );
  if not coalesce((v_policy_report->>'eligible')::boolean, false)
    or not coalesce((v_final_gate->>'eligible')::boolean, false)
    or not coalesce((v_release_gate->>'eligible')::boolean, false)
    or v_policy_report->>'measurement_policy_checksum' is distinct from
      '42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0'
  then
    raise exception '119_candidate_gate_validation_failed:%',
      jsonb_build_object(
        'policy', v_policy_report,
        'final', v_final_gate,
        'release', v_release_gate
      );
  end if;

  select * into strict v_proc
  from pg_proc
  where oid =
    'fitmatch_catalog.runtime_policy_contract_report_v1(uuid)'::regprocedure;
  if v_proc.prosecdef
    or v_proc.provolatile <> 's'
    or v_proc.proconfig is distinct from array['search_path=""']::text[]
    or has_function_privilege(
      'anon', v_proc.oid, 'EXECUTE'
    )
    or has_function_privilege(
      'authenticated', v_proc.oid, 'EXECUTE'
    )
    or not has_function_privilege(
      'service_role', v_proc.oid, 'EXECUTE'
    )
  then
    raise exception '119_function_security_or_grant_regression';
  end if;

  if (select count(*) from fitmatch_catalog.releases where status = 'active')
      <> 1
    or (select id from fitmatch_catalog.releases where status = 'active')
      is distinct from '65d72393-4a40-4e99-b701-fdc1ff865774'::uuid
    or (select status from fitmatch_catalog.releases
        where id = '11800000-0000-4000-8000-000000000118'::uuid)
      is distinct from 'validated'
  then
    raise exception '119_pre_activation_release_pointer_changed';
  end if;
end
$validation$;

select jsonb_build_object(
  'passed', true,
  'contract', 'measurement-policy-checksum-semantic-v2',
  'policy_rows', 63,
  'production_raw_checksum',
    '6ad654049b08f6d19bd6a59c2a50482f550ee9edf6a0b9faad5d6f74b31a18a2',
  'canonical_checksum',
    '42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0',
  'candidate_gate', 'PASS',
  'production_write_count', 0
) as validation_result;

rollback;
