-- LOCAL DISPOSABLE POSTGRESQL 17 ONLY.
-- Validates migration 116 with production-shaped non-user data. Every
-- decision/history/release-state probe is enclosed by the final ROLLBACK.

\set ON_ERROR_STOP on
\set QUIET 1

begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';

create temp table _phase1b2_preflight as
select
  (select count(*) from fitmatch_catalog.products) product_count,
  (select count(*)
   from fitmatch_catalog.product_classification_decisions) decision_count,
  (select count(*)
   from fitmatch_catalog.product_classification_history) history_count,
  (select count(*)
   from fitmatch_catalog.data_quality_issues
   where issue_code = 'CLASSIFICATION_AUTHORITY_REVIEW_REQUIRED'
     and evidence->>'candidate_release_id' =
       '9f9c8155-61d9-41ce-9dd1-bf695ecc2140') review_issue_count;

create temp table _phase1b2_repository_manifest (
  line text not null
) on commit drop;
\copy _phase1b2_repository_manifest(line) from 'supabase/sql/fixtures/116_classification_candidate_manifest.jsonl'

do $$
declare
  v_policy jsonb;
  v_artifact jsonb;
  v_gate jsonb;
begin
  if to_regprocedure(
      'fitmatch_catalog.runtime_validate_classification_tuple_v1(text,text,text,text,text,text)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_record_product_classification_v2(uuid,jsonb)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(text,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_policy_contract_report_v1(uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_classification_candidate_artifact_report_v1(uuid)'
    ) is null then
    raise exception 'phase1b2_function_compile_contract_missing';
  end if;

  if not exists (
      select 1 from pg_constraint
      where conrelid =
        'fitmatch_catalog.product_classification_decisions'::regclass
        and conname =
          'product_classification_decisions_verified_complete_check'
    )
    or not exists (
      select 1 from pg_constraint
      where conrelid =
        'fitmatch_catalog.product_classification_decisions'::regclass
        and conname =
          'product_classification_decisions_garment_type_code_fkey'
        and contype = 'f'
    ) then
    raise exception 'phase1b2_check_or_fk_contract_missing';
  end if;

  if not exists (
      select 1 from pg_trigger
      where tgrelid = 'fitmatch_catalog.releases'::regclass
        and tgname = 'releases_activation_gate_trigger'
        and tgenabled <> 'D'
    ) then
    raise exception 'phase1b2_release_gate_trigger_missing';
  end if;

  if has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_release_gate_report(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_release_gate_report(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_policy_contract_report_v1(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_policy_contract_report_v1(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_classification_candidate_artifact_report_v1(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_classification_candidate_artifact_report_v1(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_classification_candidate_mapping_manifest_v1()',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_classification_candidate_review_manifest_v1()',
      'EXECUTE'
    )
    or not has_function_privilege(
      'service_role',
      'fitmatch_catalog.runtime_release_gate_report(uuid)',
      'EXECUTE'
    )
    or not has_function_privilege(
      'service_role',
      'fitmatch_catalog.runtime_policy_contract_report_v1(uuid)',
      'EXECUTE'
    )
    or not has_function_privilege(
      'service_role',
      'fitmatch_catalog.runtime_classification_candidate_artifact_report_v1(uuid)',
      'EXECUTE'
    )
    or not has_function_privilege(
      'service_role',
      'fitmatch_catalog.runtime_classification_candidate_mapping_manifest_v1()',
      'EXECUTE'
    )
    or not has_function_privilege(
      'service_role',
      'fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()',
      'EXECUTE'
    )
    or not has_function_privilege(
      'service_role',
      'fitmatch_catalog.runtime_classification_candidate_review_manifest_v1()',
      'EXECUTE'
    ) then
    raise exception 'phase1b2_role_grant_matrix_invalid';
  end if;

  if (select product_count from _phase1b2_preflight) <> 1608
    or (select decision_count from _phase1b2_preflight) <> 5056
    or (select review_issue_count from _phase1b2_preflight) <> 1037 then
    raise exception 'phase1b2_preflight_count_mismatch';
  end if;

  if exists (
      (select to_jsonb(manifest)
       from fitmatch_catalog.runtime_classification_candidate_mapping_manifest_v1()
         manifest
       except
       select line::jsonb - 'record_type'
       from _phase1b2_repository_manifest
       where line::jsonb->>'record_type' = 'candidate_mapping_authority')
      union all
      (select line::jsonb - 'record_type'
       from _phase1b2_repository_manifest
       where line::jsonb->>'record_type' = 'candidate_mapping_authority'
       except
       select to_jsonb(manifest)
       from fitmatch_catalog.runtime_classification_candidate_mapping_manifest_v1()
         manifest)
    )
    or exists (
      (select to_jsonb(manifest)
       from fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()
         manifest
       except
       select line::jsonb - 'record_type'
       from _phase1b2_repository_manifest
       where line::jsonb->>'record_type' = 'candidate_product_decision')
      union all
      (select line::jsonb - 'record_type'
       from _phase1b2_repository_manifest
       where line::jsonb->>'record_type' = 'candidate_product_decision'
       except
       select to_jsonb(manifest)
       from fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()
         manifest)
    )
    or exists (
      (select to_jsonb(manifest)
       from fitmatch_catalog.runtime_classification_candidate_review_manifest_v1()
         manifest
       except
       select line::jsonb - 'record_type'
       from _phase1b2_repository_manifest
       where line::jsonb->>'record_type' = 'candidate_manual_review_issue')
      union all
      (select line::jsonb - 'record_type'
       from _phase1b2_repository_manifest
       where line::jsonb->>'record_type' = 'candidate_manual_review_issue'
       except
       select to_jsonb(manifest)
       from fitmatch_catalog.runtime_classification_candidate_review_manifest_v1()
         manifest)
    ) then
    raise exception 'phase1b2_repository_sql_manifest_parity_failed';
  end if;

  v_policy := fitmatch_catalog.runtime_policy_contract_report_v1(
    '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
  );
  if not coalesce((v_policy->>'eligible')::boolean, false)
    or (v_policy->>'classifier_policy_count')::integer <> 1532
    or (v_policy->>'comparison_policy_count')::integer <> 30
    or (v_policy->>'compatibility_rule_count')::integer <> 2
    or (v_policy->>'measurement_policy_count')::integer <> 25 then
    raise exception 'phase1b2_runtime_policy_contract_failed:%', v_policy;
  end if;

  v_artifact :=
    fitmatch_catalog.runtime_classification_candidate_artifact_report_v1(
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
    );
  if coalesce((v_artifact->>'eligible')::boolean, false)
    or not (v_artifact->'blockers'
      ? 'targeted_decision_count_or_content_mismatch')
    or (v_artifact->>'mapping_count')::integer <> 3492
    or v_artifact->'mapping_buckets' is distinct from
      '{"CATEGORY_DIRECT":34,"PRODUCT_REQUIRED":989,"INVALID_MAPPING":369,"OTHER_EXISTING":2100}'::jsonb
    or (v_artifact->>'manual_review_match_count')::integer <> 1037 then
    raise exception 'phase1b2_pre_activation_artifact_gate_failed:%',
      v_artifact;
  end if;

  v_gate := fitmatch_catalog.runtime_release_gate_report(
    '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
  );
  if coalesce((v_gate->>'eligible')::boolean, false)
    or not (v_gate->'blockers'
      ? 'targeted_decision_count_or_content_mismatch') then
    raise exception 'phase1b2_pre_activation_gate_must_fail:%', v_gate;
  end if;
end $$;

-- Negative four-field/checksum/validation-flag probes. Each mutation is local
-- to this transaction and the exact report is restored before shadow work.
do $$
declare
  v_release_id constant uuid :=
    '9f9c8155-61d9-41ce-9dd1-bf695ecc2140';
  v_original jsonb;
  v_contract jsonb;
  v_report jsonb;
  v_field text;
  v_reason text;
begin
  select validation_report into v_original
  from fitmatch_catalog.releases
  where id = v_release_id;
  v_contract := v_original->'runtime_policy_contract';

  foreach v_field in array array[
    'classifier_policy_version',
    'comparison_policy_version',
    'compatibility_rule_version',
    'measurement_policy_version'
  ] loop
    v_reason := case v_field
      when 'classifier_policy_version'
        then 'classifier_policy_version_missing'
      when 'comparison_policy_version'
        then 'comparison_policy_version_missing'
      when 'compatibility_rule_version'
        then 'compatibility_rule_version_missing'
      else 'measurement_policy_version_missing'
    end;
    update fitmatch_catalog.releases
    set validation_report = jsonb_set(
      v_original,
      '{runtime_policy_contract}',
      v_contract - v_field
    )
    where id = v_release_id;
    v_report := fitmatch_catalog.runtime_release_gate_report(v_release_id);
    if not (v_report->'blockers' ? v_reason) then
      raise exception 'phase1b2_policy_field_negative_probe_failed:%:%',
        v_field, v_report;
    end if;
  end loop;

  update fitmatch_catalog.releases
  set validation_report = jsonb_set(
    v_original,
    '{runtime_policy_contract,classifier_policy_version}',
    '"classifier-version-not-present"'::jsonb
  )
  where id = v_release_id;
  v_report := fitmatch_catalog.runtime_release_gate_report(v_release_id);
  if not (v_report->'blockers' ? 'classifier_policy_version_missing') then
    raise exception 'phase1b2_policy_row_negative_probe_failed:%', v_report;
  end if;

  update fitmatch_catalog.releases
  set validation_report = jsonb_set(
    v_original,
    '{classifier_policy_checksum}',
    '"checksum-spoof"'::jsonb
  )
  where id = v_release_id;
  v_report := fitmatch_catalog.runtime_release_gate_report(v_release_id);
  if not (v_report->'blockers' ? 'classifier_policy_checksum_mismatch') then
    raise exception 'phase1b2_policy_checksum_negative_probe_failed:%',
      v_report;
  end if;

  update fitmatch_catalog.releases
  set validation_report = jsonb_set(
    v_original,
    '{runtime_policy_contract_validated}',
    'false'::jsonb
  )
  where id = v_release_id;
  v_report := fitmatch_catalog.runtime_release_gate_report(v_release_id);
  if not (v_report->'blockers'
      ? 'runtime_policy_contract_not_validated') then
    raise exception 'phase1b2_policy_flag_negative_probe_failed:%', v_report;
  end if;

  update fitmatch_catalog.releases
  set validation_report = v_original
  where id = v_release_id;
end $$;

-- Exercise the 114 trigger itself while the 114 targeted decisions are still
-- absent. Parent retirement and every subsequent state change are rolled back.
update fitmatch_catalog.releases
set status = 'retired'
where id = '65d72393-4a40-4e99-b701-fdc1ff865774';

do $$
begin
  begin
    update fitmatch_catalog.releases
    set status = 'active'
    where id = '9f9c8155-61d9-41ce-9dd1-bf695ecc2140';
    raise exception 'phase1b2_negative_trigger_probe_unexpectedly_allowed';
  exception
    when check_violation then
      if sqlerrm <> 'release_activation_gate_failed' then
        raise;
      end if;
  end;
end $$;

-- The exact 114-row write is activation-scoped. It is tested here only and is
-- rolled back; migration 116 deliberately does not perform this upsert.
insert into fitmatch_catalog.product_classification_decisions (
  source,
  external_product_id,
  product_name,
  source_category_path,
  input_fingerprint,
  category_code,
  detail_code,
  garment_type_code,
  comparison_family,
  length_type,
  requires_user_confirmation,
  release_id,
  decision_version,
  evidence,
  authority_status
)
select
  manifest.source,
  manifest.external_product_id,
  manifest.product_name,
  manifest.source_category_path,
  manifest.input_fingerprint,
  manifest.category_code,
  manifest.detail_code,
  manifest.garment_type_code,
  manifest.family_code,
  manifest.length_code,
  manifest.requires_user_confirmation,
  '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'::uuid,
  manifest.decision_version,
  manifest.evidence || jsonb_build_object(
    'body_length_code', manifest.body_length_code,
    'candidate_release_id',
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140',
    'candidate_manifest_checksum',
      '16000e9ddb51eda923d242fadb97422ee868af503496eb440f3bca7e0206b820'
  ),
  manifest.authority_status
from fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()
  manifest
on conflict (source, external_product_id) do update
set product_name = excluded.product_name,
    source_category_path = excluded.source_category_path,
    input_fingerprint = excluded.input_fingerprint,
    category_code = excluded.category_code,
    detail_code = excluded.detail_code,
    garment_type_code = excluded.garment_type_code,
    comparison_family = excluded.comparison_family,
    length_type = excluded.length_type,
    requires_user_confirmation = excluded.requires_user_confirmation,
    release_id = excluded.release_id,
    decision_version = excluded.decision_version,
    evidence = excluded.evidence,
    authority_status = excluded.authority_status,
    updated_at = now();

do $$
declare
  v_invalid_verified integer;
begin
  select count(*) into v_invalid_verified
  from fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()
    manifest
  cross join lateral (
    select fitmatch_catalog.runtime_validate_classification_tuple_v1(
      manifest.category_code,
      manifest.detail_code,
      manifest.garment_type_code,
      manifest.family_code,
      manifest.length_code,
      manifest.body_length_code
    ) result
  ) validation
  where manifest.authority_status = 'verified'
    and not coalesce((validation.result->>'valid')::boolean, false);

  if (select count(*)
      from fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()
      where authority_status = 'verified') <> 113
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()
        where authority_status = 'revoked') <> 1
    or v_invalid_verified <> 0 then
    raise exception 'phase1b2_targeted_decision_validation_failed:%',
      v_invalid_verified;
  end if;
end $$;

create temp table _phase1b2_resolution on commit drop as
select
  product.id product_id,
  product.source,
  product.external_product_id,
  product.product_name,
  product.audience,
  product.source_category_path,
  product.source_category_codes,
  product.input_fingerprint,
  product.raw_payload->'phase1b2_current' current_classification,
  product.raw_payload->'phase1b2_comparison_readiness'
    current_comparison_readiness,
  product.raw_payload->'phase1b2_independent_adjudication'
    independent_adjudication,
  resolution.result resolution,
  coalesce(
    resolution.result#>>'{evidence,source_mapping_identity}',
    resolution.result#>>'{authority_conflicts,0,mapping_source_identity}',
    product.raw_payload->>'phase1b2_mapping_source_identity',
    fallback_mapping.source_identity
  ) selected_mapping_source_identity,
  coalesce(candidate_mapping.raw_record#>>'{phase1b2Adjudication,bucket}',
    fallback_mapping.raw_record#>>'{phase1b2Adjudication,bucket}',
    'NO_MATCH') mapping_bucket
from fitmatch_catalog.products product
cross join lateral (
  select fitmatch_catalog.runtime_resolve_product_classification_v4(
    product.source,
    product.external_product_id,
    product.product_name,
    product.source_category_path,
    jsonb_build_object(
      'audience', product.audience,
      'source_category_codes', to_jsonb(product.source_category_codes)
    ),
    '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
  ) result
) resolution
left join lateral (
  select mapping.*
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id =
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
    and mapping.source = product.source
    and (
      mapping.external_category_id = any(product.source_category_codes)
      or fitmatch_catalog.runtime_normalized_category_path(
        mapping.normalized_path
      ) = fitmatch_catalog.runtime_normalized_category_path(
        product.source_category_path
      )
    )
    and (
      mapping.target = upper(coalesce(product.audience, ''))
      or mapping.target = 'UNKNOWN'
    )
  order by
    array_position(product.source_category_codes,
      mapping.external_category_id) desc nulls last,
    mapping.source_identity
  limit 1
) fallback_mapping on true
left join fitmatch_catalog.source_category_mappings candidate_mapping
  on candidate_mapping.release_id =
    '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
 and candidate_mapping.source_identity = coalesce(
   resolution.result#>>'{evidence,source_mapping_identity}',
   resolution.result#>>'{authority_conflicts,0,mapping_source_identity}',
   product.raw_payload->>'phase1b2_mapping_source_identity'
 );

create temp table _phase1b2_shadow on commit drop as
with previewed as (
  select resolved.*,
    case
      when resolved.resolution->>'classification_status' = 'confirmed'
      then fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
        resolved.resolution->>'category_code',
        resolved.audience,
        resolved.resolution->>'family_code',
        resolved.resolution->>'detail_code',
        resolved.resolution->>'length_code',
        resolved.resolution->>'body_length_code',
        resolved.resolution->>'category_code',
        resolved.audience,
        resolved.resolution->>'family_code',
        resolved.resolution->>'detail_code',
        resolved.resolution->>'length_code',
        resolved.resolution->>'body_length_code',
        resolved.resolution->>'garment_type_code',
        resolved.resolution->>'garment_type_code',
        false,
        '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
      )
      else jsonb_build_object(
        'allowed', false,
        'reason', 'classification_not_confirmed',
        'release_id', '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
      )
    end comparison_preview
  from _phase1b2_resolution resolved
), manifested as (
  select previewed.*,
    jsonb_build_object(
      'source', source,
      'external_product_id', external_product_id,
      'fingerprint', input_fingerprint,
      'current_production_classification', current_classification,
      'candidate_classification', jsonb_build_object(
        'category_code', resolution->>'category_code',
        'detail_code', resolution->>'detail_code',
        'garment_type_code', resolution->>'garment_type_code',
        'family_code', resolution->>'family_code',
        'length_code', resolution->>'length_code',
        'body_length_code', resolution->>'body_length_code'
      ),
      'status', resolution->>'classification_status',
      'method', resolution->>'classification_method',
      'authority_status', resolution->>'authority_status',
      'category_code', resolution->>'category_code',
      'detail_code', resolution->>'detail_code',
      'garment_type_code', resolution->>'garment_type_code',
      'family_code', resolution->>'family_code',
      'length_code', resolution->>'length_code',
      'body_length_code', resolution->>'body_length_code',
      'tuple_valid', case
        when resolution->'tuple_validation' is null then null
        else coalesce((resolution#>>'{tuple_validation,valid}')::boolean, false)
      end,
      'mapping_bucket', mapping_bucket,
      'mapping_source_identity', selected_mapping_source_identity,
      'decision_used',
        resolution->>'classification_method' = 'canonical_product_decision',
      'profile_used',
        resolution->>'classification_method' = 'product_classifier',
      'authority_conflicts',
        coalesce(resolution->'authority_conflicts', '[]'::jsonb),
      'unresolved_reasons',
        coalesce(resolution#>'{evidence,unresolved_reasons}', '[]'::jsonb),
      'comparison_eligibility_preview', comparison_preview,
      'current_comparison_readiness', current_comparison_readiness,
      'independent_adjudication', independent_adjudication,
      'reason_evidence', resolution->'evidence'
    ) manifest_row
  from previewed
)
select * from manifested;

create temp table _phase1b2_shadow_summary on commit drop as
select
  count(*) product_count,
  count(distinct (source, external_product_id)) unique_product_count,
  count(*) filter (
    where resolution->>'classification_status' = 'confirmed'
  ) confirmed_count,
  count(*) filter (
    where resolution->>'classification_status' = 'review_required'
  ) review_required_count,
  count(*) filter (
    where resolution->>'classification_status' = 'not_comparable'
  ) not_comparable_count,
  count(*) filter (
    where resolution->>'classification_status' = 'unclassified'
  ) unclassified_count,
  count(*) filter (
    where resolution->>'classification_status' = 'confirmed'
      and not coalesce(
        (resolution#>>'{tuple_validation,valid}')::boolean,
        false
      )
  ) confirmed_tuple_invalid_count,
  encode(extensions.digest(
    string_agg(manifest_row::text, E'\n'
      order by source, external_product_id) || E'\n',
    'sha256'
  ), 'hex') shadow_output_checksum
from _phase1b2_shadow;

do $$
declare
  v_summary _phase1b2_shadow_summary%rowtype;
  v_gold_exact integer;
  v_unsafe_product_required integer;
  v_unsafe_invalid_mapping integer;
  v_both_untrusted_unresolved_confirm integer;
  v_both_untrusted_unsafe integer;
  v_unknown_fallback integer;
  v_underwear_leak integer;
  v_tshirt_base_layer_probe jsonb;
  v_stored_shadow_checksum text;
begin
  select * into v_summary from _phase1b2_shadow_summary;
  if v_summary.product_count <> 1608
    or v_summary.unique_product_count <> 1608
    or v_summary.confirmed_tuple_invalid_count <> 0 then
    raise exception 'phase1b2_shadow_cardinality_or_tuple_failed:%',
      row_to_json(v_summary);
  end if;

  select count(*) into v_gold_exact
  from _phase1b2_shadow
  where source = 'uniqlo'
    and (
      (external_product_id = 'E482514'
       and resolution @> '{"classification_status":"confirmed","classification_method":"canonical_product_decision","authority_status":"verified","category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve"}'::jsonb)
      or
      (external_product_id in ('E454311', 'E456567')
       and resolution @> '{"classification_status":"confirmed","classification_method":"canonical_product_decision","authority_status":"verified","category_code":"tops","detail_code":"base_layer_top","garment_type_code":"base_layer_top","family_code":"base_layer_top","length_code":"short_sleeve"}'::jsonb)
    );
  if v_gold_exact <> 3 then
    raise exception 'phase1b2_gold_exact_failed:%', v_gold_exact;
  end if;

  select count(*) into v_unsafe_product_required
  from _phase1b2_shadow
  where mapping_bucket = 'PRODUCT_REQUIRED'
    and resolution->>'classification_status' = 'confirmed'
    and resolution->>'classification_method' not in (
      'canonical_product_decision', 'product_classifier'
    );
  select count(*) into v_unsafe_invalid_mapping
  from _phase1b2_shadow
  where mapping_bucket = 'INVALID_MAPPING'
    and resolution->>'classification_status' = 'confirmed'
    and resolution->>'classification_method' not in (
      'canonical_product_decision', 'product_classifier'
    );
  select count(*) into v_both_untrusted_unresolved_confirm
  from _phase1b2_shadow shadow
  join fitmatch_catalog.runtime_classification_candidate_review_manifest_v1()
    review using (source, external_product_id)
  where review.conflict_root_cause = 'G_BOTH_UNTRUSTED'
    and shadow.resolution->>'classification_status' = 'confirmed';
  select v_both_untrusted_unresolved_confirm + count(*) into v_both_untrusted_unsafe
  from _phase1b2_shadow
  where source = 'uniqlo'
    and external_product_id = 'E482514'
    and (
      resolution->>'classification_status' <> 'confirmed'
      or resolution->>'classification_method' <>
        'canonical_product_decision'
      or resolution->>'authority_status' <> 'verified'
    );
  select count(*) into v_unknown_fallback
  from _phase1b2_shadow
  where resolution->>'classification_status' = 'confirmed'
    and resolution->>'category_code' = 'tops'
    and resolution->>'detail_code' in ('tshirt', 'other', 'unknown')
    and resolution->>'garment_type_code' in ('other', 'unknown')
    and resolution->>'authority_status' is distinct from 'verified';
  select count(*) into v_underwear_leak
  from _phase1b2_shadow
  where resolution->>'category_code' = 'underwear'
    and coalesce((comparison_preview->>'allowed')::boolean, false)
    and coalesce(resolution->>'garment_type_code', '') in (
      '', 'underwear', 'generic_underwear'
    );

  if v_unsafe_product_required <> 0
    or v_unsafe_invalid_mapping <> 0
    or v_both_untrusted_unresolved_confirm <> 0
    or v_both_untrusted_unsafe <> 0
    or v_unknown_fallback <> 0
    or v_underwear_leak <> 0 then
    raise exception 'phase1b2_fail_closed_acceptance_failed product_required=% invalid=% both_unresolved=% both_unsafe=% fallback=% underwear=%',
      v_unsafe_product_required, v_unsafe_invalid_mapping,
      v_both_untrusted_unresolved_confirm, v_both_untrusted_unsafe,
      v_unknown_fallback, v_underwear_leak;
  end if;

  v_tshirt_base_layer_probe :=
    fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
      'tops', 'MEN', 'tshirt', 'short_sleeve', 'short_sleeve', null,
      'tops', 'MEN', 'base_layer_top', 'base_layer_top',
      'short_sleeve', null, 'tshirt', 'base_layer_top', false,
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
    );
  if coalesce((v_tshirt_base_layer_probe->>'allowed')::boolean, false)
    or v_tshirt_base_layer_probe->>'reason' <>
      'base_layer_top_tshirt_automatic_comparison_blocked' then
    raise exception 'phase1b2_tshirt_base_layer_safety_failed:%',
      v_tshirt_base_layer_probe;
  end if;

  select validation_report->>'shadow_output_checksum'
  into v_stored_shadow_checksum
  from fitmatch_catalog.releases
  where id = '9f9c8155-61d9-41ce-9dd1-bf695ecc2140';
  if v_stored_shadow_checksum not like '__%'
    and v_stored_shadow_checksum is distinct from
      v_summary.shadow_output_checksum then
    raise exception 'phase1b2_shadow_checksum_mismatch stored=% actual=%',
      v_stored_shadow_checksum, v_summary.shadow_output_checksum;
  end if;

  raise notice 'PHASE1B2_SHADOW_SUMMARY=%', row_to_json(v_summary);
  raise notice 'PHASE1B2_FAIL_CLOSED product_required=% invalid=% both_untrusted_original=310 both_untrusted_owner_resolved=1 both_untrusted_unresolved=309 both_untrusted_unsafe=% unknown_fallback=% underwear_leak=%',
    v_unsafe_product_required, v_unsafe_invalid_mapping,
    v_both_untrusted_unsafe, v_unknown_fallback, v_underwear_leak;
end $$;

do $$
declare
  v_artifact jsonb;
  v_gate jsonb;
begin
  v_artifact :=
    fitmatch_catalog.runtime_classification_candidate_artifact_report_v1(
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
    );
  if not coalesce((v_artifact->>'eligible')::boolean, false)
    or (v_artifact->>'targeted_decision_match_count')::integer <> 114
    or (v_artifact->>'targeted_decision_mismatch_count')::integer <> 0 then
    raise exception 'phase1b2_post_decision_artifact_gate_failed:%',
      v_artifact;
  end if;

  v_gate := fitmatch_catalog.runtime_release_gate_report(
    '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
  );
  if not coalesce((v_gate->>'eligible')::boolean, false) then
    raise exception 'phase1b2_positive_gate_failed:%', v_gate;
  end if;

  perform fitmatch_catalog.runtime_activate_validated_release(
    '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'
  );
  if (select status from fitmatch_catalog.releases
      where id = '9f9c8155-61d9-41ce-9dd1-bf695ecc2140') <> 'active'
    or (select count(*) from fitmatch_catalog.releases
        where status = 'active') <> 1 then
    raise exception 'phase1b2_positive_activation_probe_failed';
  end if;
end $$;

-- Recorder append/supersede proof. These history rows are rolled back.
do $$
declare
  v_product_id uuid;
  v_resolution jsonb;
begin
  select product_id, resolution into v_product_id, v_resolution
  from _phase1b2_shadow
  where source = 'uniqlo' and external_product_id = 'E482514';
  perform fitmatch_catalog.runtime_record_product_classification_v2(
    v_product_id, v_resolution
  );
  perform fitmatch_catalog.runtime_record_product_classification_v2(
    v_product_id, v_resolution
  );
  if (select count(*)
      from fitmatch_catalog.product_classification_history
      where product_id = v_product_id) <> 2
    or (select count(*)
        from fitmatch_catalog.product_classification_history
        where product_id = v_product_id and is_current) <> 1 then
    raise exception 'phase1b2_recorder_append_supersede_failed';
  end if;
end $$;

do $$
declare
  v_overlap integer;
  v_exact integer;
  v_mismatch integer;
  v_review integer;
  v_residual integer;
begin
  select
    count(*),
    count(*) filter (where
      jsonb_build_array(
        resolution->>'category_code',
        resolution->>'detail_code',
        resolution->>'family_code',
        resolution->>'length_code',
        resolution->>'classification_status'
      ) = independent_adjudication->'expected_tuple'
    ),
    count(*) filter (where
      jsonb_build_array(
        resolution->>'category_code',
        resolution->>'detail_code',
        resolution->>'family_code',
        resolution->>'length_code',
        resolution->>'classification_status'
      ) <> independent_adjudication->'expected_tuple'
    ),
    count(*) filter (where
      resolution->>'classification_status' = 'review_required'
    ),
    count(*) filter (where
      independent_adjudication->>'phase_target' =
        'PHASE_1B_DB_DECISION_AND_HISTORY'
      and jsonb_build_array(
        resolution->>'category_code',
        resolution->>'detail_code',
        resolution->>'family_code',
        resolution->>'length_code',
        resolution->>'classification_status'
      ) <> independent_adjudication->'expected_tuple'
    )
  into v_overlap, v_exact, v_mismatch, v_review, v_residual
  from _phase1b2_shadow
  where independent_adjudication is not null;

  raise notice 'PHASE1B2_INDEPENDENT overlap=% exact=% mismatch=% review_required=% db_change_target_residual=% expected_rows_modified=0',
    v_overlap, v_exact, v_mismatch, v_review, v_residual;
end $$;

-- stdout is intentionally only the 1,608 machine-readable shadow rows.
copy (
  select manifest_row
  from _phase1b2_shadow
  order by source, external_product_id
) to stdout;

rollback;

\set QUIET 0
