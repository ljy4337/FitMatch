-- LOCAL DISPOSABLE POSTGRESQL 17 ONLY.
-- Validates the approved Phase 1B-2R safe-data revision against the exact
-- 1,608-product baseline. All product-decision and report probes roll back.

\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';

create temp table _phase1b2r_preflight as
select
  (select count(*) from fitmatch_catalog.products) product_count,
  (select count(*)
   from fitmatch_catalog.product_classification_decisions) decision_count,
  (select count(*)
   from fitmatch_catalog.product_classification_history) history_count,
  (select count(*)
   from fitmatch_catalog.source_category_mappings
   where release_id =
     '9f9c8155-61d9-41ce-9dd1-bf695ecc2140') baseline_mapping_count,
  (select count(*)
   from fitmatch_catalog.source_category_mappings
   where release_id =
     'f83ca2f0-88a4-4430-96fc-037d6f1efcc2') revision_mapping_count,
  (select count(*)
   from fitmatch_catalog.data_quality_issues
   where issue_code = 'CLASSIFICATION_AUTHORITY_REVIEW_REQUIRED'
     and evidence->>'candidate_release_id' =
       '9f9c8155-61d9-41ce-9dd1-bf695ecc2140') review_issue_count;

create temp table _phase1b2r_repository_manifest (
  line text not null
) on commit drop;
\copy _phase1b2r_repository_manifest(line) from 'supabase/sql/fixtures/117_classification_candidate_revision_manifest.jsonl'

create temp table _phase1b2r_baseline_shadow (
  line text not null
) on commit drop;
\copy _phase1b2r_baseline_shadow(line) from 'Docs/FitMatchClassificationPhase1B2Shadow-20260826.jsonl'

create temp table _phase1b2r_review_audit (
  line text not null
) on commit drop;
\copy _phase1b2r_review_audit(line) from 'Docs/FitMatchClassificationReviewEvidenceAudit-20260826.jsonl'

create temp table _phase1b2r_db_only (
  line text not null
) on commit drop;
\copy _phase1b2r_db_only(line) from 'Docs/FitMatchClassificationDBOnly105-20260826.jsonl'

do $$
declare
  v_artifact jsonb;
  v_gate jsonb;
  v_policy jsonb;
begin
  if to_regprocedure(
      'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(text,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_classification_candidate_revision_mapping_manifest_v2()'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(uuid)'
    ) is null then
    raise exception 'phase1b2r_function_compile_contract_missing';
  end if;

  if has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()',
      'EXECUTE'
    )
    or not has_function_privilege(
      'service_role',
      'fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(uuid)',
      'EXECUTE'
    )
    or not has_function_privilege(
      'service_role',
      'fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()',
      'EXECUTE'
    ) then
    raise exception 'phase1b2r_role_grant_matrix_invalid';
  end if;

  if (select product_count from _phase1b2r_preflight) <> 1608
    or (select decision_count from _phase1b2r_preflight) <> 5056
    or (select history_count from _phase1b2r_preflight) <> 0
    or (select baseline_mapping_count from _phase1b2r_preflight) <> 3492
    or (select revision_mapping_count from _phase1b2r_preflight) <> 3509
    or (select review_issue_count from _phase1b2r_preflight) <> 1037
    or (select count(*) from _phase1b2r_repository_manifest) <> 84
    or (select count(*) from _phase1b2r_baseline_shadow) <> 1608
    or (select count(*) from _phase1b2r_review_audit) <> 1431
    or (select count(*) from _phase1b2r_db_only) <> 105 then
    raise exception 'phase1b2r_preflight_count_mismatch';
  end if;

  if exists (
    (select value
     from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
     except
     select line::jsonb from _phase1b2r_repository_manifest)
    union all
    (select line::jsonb from _phase1b2r_repository_manifest
     except
     select value
     from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1())
  ) then
    raise exception 'phase1b2r_repository_sql_manifest_parity_failed';
  end if;

  if (select count(*)
      from fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()) <> 116
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
        where authority_status = 'verified') <> 115
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
        where authority_status = 'revoked') <> 1
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_revision_mapping_manifest_v2()) <> 3509 then
    raise exception 'phase1b2r_combined_manifest_count_mismatch';
  end if;

  v_policy := fitmatch_catalog.runtime_policy_contract_report_v1(
    'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
  );
  if not coalesce((v_policy->>'eligible')::boolean, false)
    or (v_policy->>'classifier_policy_count')::integer <> 1532
    or (v_policy->>'comparison_policy_count')::integer <> 30
    or (v_policy->>'compatibility_rule_count')::integer <> 2
    or (v_policy->>'measurement_policy_count')::integer <> 25 then
    raise exception 'phase1b2r_runtime_policy_contract_failed:%', v_policy;
  end if;

  v_artifact :=
    fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
    );
  if coalesce((v_artifact->>'eligible')::boolean, false)
    or not (v_artifact->'blockers'
      ? 'targeted_decision_count_or_content_mismatch')
    or (v_artifact->>'mapping_count')::integer <> 3509
    or v_artifact->'mapping_buckets' is distinct from
      '{"CATEGORY_DIRECT":51,"PRODUCT_REQUIRED":999,"INVALID_MAPPING":359,"OTHER_EXISTING":2100}'::jsonb
    or (v_artifact->>'target_clone_count')::integer <> 17
    or (v_artifact->>'product_required_count')::integer <> 10
    or (v_artifact->>'revoke_count')::integer <> 30
    or (v_artifact->>'unresolved_vocabulary_parity_count')::integer <> 24
    or (v_artifact->>'unresolved_vocabulary_mismatch_count')::integer <> 0
    or (v_artifact->>'unapproved_base_mismatch_count')::integer <> 0 then
    raise exception 'phase1b2r_pre_decision_artifact_failed:%', v_artifact;
  end if;

  v_gate :=
    fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
    );
  if coalesce((v_gate->>'eligible')::boolean, false)
    or not (v_gate->'blockers'
      ? 'targeted_decision_count_or_content_mismatch') then
    raise exception 'phase1b2r_pre_decision_gate_must_fail:%', v_gate;
  end if;
end $$;

-- Exact 116-row combined decision manifest is exercised only inside this
-- rollback transaction. Migration 117 performs no persistent decision write.
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
  'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid,
  manifest.decision_version,
  manifest.evidence || jsonb_build_object(
    'body_length_code', manifest.body_length_code,
    'candidate_release_id',
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2',
    'candidate_manifest_checksum',
      '997f8fca3726ef38b728e5bc0c2e2dcd4cb72e578a70d3a26d3d3fda6aee3f16'
  ),
  manifest.authority_status
from fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
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
  from fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
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

  if v_invalid_verified <> 0
    or (select count(*)
        from fitmatch_catalog.product_classification_decisions) <> 5056 then
    raise exception 'phase1b2r_targeted_decision_validation_failed:%',
      v_invalid_verified;
  end if;
end $$;

create temp table _phase1b2r_resolution on commit drop as
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
  coalesce(
    candidate_mapping.raw_record#>>'{phase1b2Adjudication,bucket}',
    fallback_mapping.raw_record#>>'{phase1b2Adjudication,bucket}',
    'NO_MATCH'
  ) mapping_bucket
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
    'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
  ) result
) resolution
left join lateral (
  select mapping.*
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id =
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
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
    'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
 and candidate_mapping.source_identity = coalesce(
   resolution.result#>>'{evidence,source_mapping_identity}',
   resolution.result#>>'{authority_conflicts,0,mapping_source_identity}',
   product.raw_payload->>'phase1b2_mapping_source_identity'
 );

create temp table _phase1b2r_shadow on commit drop as
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
        'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
      )
      else jsonb_build_object(
        'allowed', false,
        'reason', 'classification_not_confirmed',
        'release_id', 'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
      )
    end comparison_preview
  from _phase1b2r_resolution resolved
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
      'classification_status', resolution->>'classification_status',
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
        else coalesce((resolution#>>'{tuple_validation,valid}')::boolean,
          false)
      end,
      'mapping_bucket', mapping_bucket,
      'mapping_source_identity', selected_mapping_source_identity,
      'decision_used',
        resolution->>'classification_method' =
          'canonical_product_decision',
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

create temp table _phase1b2r_shadow_summary on commit drop as
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
from _phase1b2r_shadow;

create temp table _phase1b2r_approved_gain on commit drop as
select distinct
  split_part(product_key, ':', 1) source,
  substring(product_key from position(':' in product_key) + 1)
    external_product_id,
  manifest.line::jsonb->>'record_type' approval_type
from _phase1b2r_repository_manifest manifest
cross join lateral jsonb_array_elements_text(
  manifest.line::jsonb->'affected_products'
) product(product_key)
where manifest.line::jsonb->>'record_type' in (
  'approved_target_clone', 'approved_product_decision'
);

do $$
declare
  v_summary _phase1b2r_shadow_summary%rowtype;
  v_input_mismatch integer;
  v_existing_regression integer;
  v_comparison_regression integer;
  v_approved_transition_count integer;
  v_unexpected_transition_count integer;
  v_clone_mapping_selected_count integer;
  v_clone_transition_count integer;
  v_clone_conflict_count integer;
  v_clone_conflict_products jsonb;
  v_decision_transition_count integer;
  v_gold_exact integer;
  v_unsafe_product_required integer;
  v_unsafe_revoked integer;
  v_both_untrusted_unresolved integer;
  v_conflict_unresolved integer;
  v_unknown_fallback integer;
  v_underwear_leak integer;
  v_tshirt_base_layer_probe jsonb;
  v_vocabulary_owner_review integer;
  v_invalid_vocabulary_review integer;
  v_profile_confirm_count integer;
begin
  select * into v_summary from _phase1b2r_shadow_summary;
  if v_summary.product_count <> 1608
    or v_summary.unique_product_count <> 1608
    or v_summary.confirmed_count <> 256
    or v_summary.review_required_count <> 1352
    or v_summary.not_comparable_count <> 0
    or v_summary.unclassified_count <> 0
    or v_summary.confirmed_tuple_invalid_count <> 0 then
    raise exception 'phase1b2r_shadow_cardinality_or_distribution_failed:%',
      row_to_json(v_summary);
  end if;

  select count(*) into v_input_mismatch
  from _phase1b2r_baseline_shadow baseline
  full join _phase1b2r_shadow revision
    on revision.source = baseline.line::jsonb->>'source'
   and revision.external_product_id =
     baseline.line::jsonb->>'external_product_id'
  where revision.source is null
    or baseline.line is null
    or revision.input_fingerprint is distinct from
      baseline.line::jsonb->>'fingerprint';
  if v_input_mismatch <> 0 then
    raise exception 'phase1b2r_input_key_or_fingerprint_drift:%',
      v_input_mismatch;
  end if;

  select count(*) into v_existing_regression
  from _phase1b2r_baseline_shadow baseline
  join _phase1b2r_shadow revision
    on revision.source = baseline.line::jsonb->>'source'
   and revision.external_product_id =
     baseline.line::jsonb->>'external_product_id'
  where baseline.line::jsonb->>'status' = 'confirmed'
    and (
      revision.resolution->>'classification_status' <> 'confirmed'
      or revision.manifest_row->'candidate_classification' is distinct from
        baseline.line::jsonb->'candidate_classification'
      or revision.manifest_row->>'method' is distinct from
        baseline.line::jsonb->>'method'
      or revision.manifest_row->>'authority_status' is distinct from
        baseline.line::jsonb->>'authority_status'
    );
  if v_existing_regression <> 0 then
    raise exception 'phase1b2r_existing_177_regression:%',
      v_existing_regression;
  end if;

  select count(*) into v_comparison_regression
  from _phase1b2r_baseline_shadow baseline
  join _phase1b2r_shadow revision
    on revision.source = baseline.line::jsonb->>'source'
   and revision.external_product_id =
     baseline.line::jsonb->>'external_product_id'
  where baseline.line::jsonb->>'status' = 'confirmed'
    and (
      revision.comparison_preview->>'allowed' is distinct from
        baseline.line::jsonb#>>'{comparison_eligibility_preview,allowed}'
      or revision.comparison_preview->>'reason' is distinct from
        baseline.line::jsonb#>>'{comparison_eligibility_preview,reason}'
    );
  if v_comparison_regression <> 0 then
    raise exception 'phase1b2r_comparison_eligibility_regression:%',
      v_comparison_regression;
  end if;

  if (select count(*) from _phase1b2r_approved_gain) <> 86 then
    raise exception 'phase1b2r_approved_gain_unique_count_mismatch';
  end if;

  select count(*) into v_approved_transition_count
  from _phase1b2r_approved_gain approved
  join _phase1b2r_baseline_shadow baseline
    on baseline.line::jsonb->>'source' = approved.source
   and baseline.line::jsonb->>'external_product_id' =
     approved.external_product_id
  join _phase1b2r_shadow revision using (source, external_product_id)
  where baseline.line::jsonb->>'status' = 'review_required'
    and revision.resolution->>'classification_status' = 'confirmed';

  select count(*) into v_unexpected_transition_count
  from _phase1b2r_baseline_shadow baseline
  join _phase1b2r_shadow revision
    on revision.source = baseline.line::jsonb->>'source'
   and revision.external_product_id =
     baseline.line::jsonb->>'external_product_id'
  left join _phase1b2r_approved_gain approved
    on approved.source = revision.source
   and approved.external_product_id = revision.external_product_id
  where baseline.line::jsonb->>'status' is distinct from
      revision.resolution->>'classification_status'
    and approved.source is null;

  select count(*) into v_clone_transition_count
  from _phase1b2r_approved_gain approved
  join _phase1b2r_shadow revision using (source, external_product_id)
  where approved.approval_type = 'approved_target_clone'
    and revision.resolution @>
      '{"classification_status":"confirmed","classification_method":"category_mapping","authority_status":"verified"}'::jsonb
    and exists (
      select 1
      from _phase1b2r_repository_manifest manifest
      where manifest.line::jsonb->>'record_type' =
          'approved_target_clone'
        and manifest.line::jsonb->>'source_identity' =
          revision.selected_mapping_source_identity
    );

  select count(*) into v_clone_mapping_selected_count
  from _phase1b2r_approved_gain approved
  join _phase1b2r_shadow revision using (source, external_product_id)
  where approved.approval_type = 'approved_target_clone'
    and exists (
      select 1
      from _phase1b2r_repository_manifest manifest
      where manifest.line::jsonb->>'record_type' =
          'approved_target_clone'
        and manifest.line::jsonb->>'source_identity' =
          revision.selected_mapping_source_identity
    );

  select count(*), jsonb_agg(
      revision.source || ':' || revision.external_product_id
      order by revision.source, revision.external_product_id
    )
  into v_clone_conflict_count, v_clone_conflict_products
  from _phase1b2r_approved_gain approved
  join _phase1b2r_shadow revision using (source, external_product_id)
  where approved.approval_type = 'approved_target_clone'
    and revision.resolution->>'classification_status' = 'review_required'
    and exists (
      select 1
      from jsonb_array_elements(coalesce(
        revision.resolution->'authority_conflicts', '[]'::jsonb
      )) conflict(value)
      where conflict.value->>'code' =
        'product_decision_source_mapping_conflict'
    );

  select count(*) into v_decision_transition_count
  from _phase1b2r_approved_gain approved
  join _phase1b2r_shadow revision using (source, external_product_id)
  where approved.approval_type = 'approved_product_decision'
    and revision.resolution @>
      '{"classification_status":"confirmed","classification_method":"canonical_product_decision","authority_status":"verified","category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve"}'::jsonb;

  if v_approved_transition_count <> 79
    or v_clone_mapping_selected_count <> 84
    or v_clone_transition_count <> 77
    or v_clone_conflict_count <> 7
    or v_clone_conflict_products is distinct from
      '["musinsa:5982920","musinsa:6515855","musinsa:6534177","musinsa:6781113","musinsa:6797265","musinsa:6797266","musinsa:6797271"]'::jsonb
    or v_decision_transition_count <> 2
    or v_unexpected_transition_count <> 0 then
    raise exception 'phase1b2r_observed_partial_transition_mismatch approved=% clone_selected=% clone_confirmed=% clone_conflict=% clone_conflict_products=% decisions=% unexpected=%',
      v_approved_transition_count, v_clone_mapping_selected_count,
      v_clone_transition_count, v_clone_conflict_count,
      v_clone_conflict_products, v_decision_transition_count,
      v_unexpected_transition_count;
  end if;

  if (select count(*) from _phase1b2r_shadow
      where source = 'musinsa'
        and resolution->>'classification_status' = 'confirmed') <> 80
    or (select count(*) from _phase1b2r_shadow
        where source = 'musinsa'
          and resolution->>'classification_status' = 'review_required')
      <> 314
    or (select count(*) from _phase1b2r_shadow
        where source = 'uniqlo'
          and resolution->>'classification_status' = 'confirmed') <> 176
    or (select count(*) from _phase1b2r_shadow
        where source = 'uniqlo'
          and resolution->>'classification_status' = 'review_required')
      <> 1008
    or (select count(*) from _phase1b2r_shadow
        where source = 'zara'
          and resolution->>'classification_status' = 'confirmed') <> 0
    or (select count(*) from _phase1b2r_shadow
        where source = 'zara'
          and resolution->>'classification_status' = 'review_required')
      <> 30 then
    raise exception 'phase1b2r_source_distribution_mismatch';
  end if;

  select count(*) into v_gold_exact
  from _phase1b2r_shadow
  where source = 'uniqlo'
    and (
      (external_product_id = 'E482514'
       and resolution @> '{"classification_status":"confirmed","classification_method":"canonical_product_decision","authority_status":"verified","category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve"}'::jsonb)
      or
      (external_product_id in ('E454311', 'E456567')
       and resolution @> '{"classification_status":"confirmed","classification_method":"canonical_product_decision","authority_status":"verified","category_code":"tops","detail_code":"base_layer_top","garment_type_code":"base_layer_top","family_code":"base_layer_top","length_code":"short_sleeve"}'::jsonb)
    );
  if v_gold_exact <> 3 then
    raise exception 'phase1b2r_gold_exact_failed:%', v_gold_exact;
  end if;

  select count(*) into v_unsafe_product_required
  from _phase1b2r_shadow
  where mapping_bucket = 'PRODUCT_REQUIRED'
    and resolution->>'classification_status' = 'confirmed'
    and resolution->>'classification_method' not in (
      'canonical_product_decision', 'product_classifier'
    );

  select count(*) into v_unsafe_revoked
  from _phase1b2r_shadow shadow
  where resolution->>'classification_status' = 'confirmed'
    and resolution->>'classification_method' = 'category_mapping'
    and exists (
      select 1
      from _phase1b2r_repository_manifest manifest
      where manifest.line::jsonb->>'record_type' =
          'approved_mapping_disposition'
        and manifest.line::jsonb->>'verdict' =
          'SHOULD_BE_REVOKED_NO_REPLACEMENT'
        and manifest.line::jsonb->>'source_identity' =
          shadow.selected_mapping_source_identity
    );

  select count(*) into v_both_untrusted_unresolved
  from _phase1b2r_shadow shadow
  join fitmatch_catalog.runtime_classification_candidate_review_manifest_v1()
    review using (source, external_product_id)
  where review.conflict_root_cause = 'G_BOTH_UNTRUSTED'
    and shadow.external_product_id <> 'E482514'
    and shadow.resolution->>'classification_status' <> 'review_required';

  select count(*) into v_conflict_unresolved
  from _phase1b2r_review_audit audit
  join _phase1b2r_shadow shadow
    on shadow.source = audit.line::jsonb->>'source'
   and shadow.external_product_id =
     audit.line::jsonb->>'external_product_id'
  where audit.line::jsonb->>'primary_root_cause' = 'AUTHORITY_CONFLICT'
    and not (
      shadow.source = 'uniqlo'
      and shadow.external_product_id = 'E482522'
    )
    and shadow.resolution->>'classification_status' = 'review_required';

  select count(*) into v_unknown_fallback
  from _phase1b2r_shadow
  where resolution->>'classification_status' = 'confirmed'
    and resolution->>'category_code' = 'tops'
    and resolution->>'detail_code' in ('tshirt', 'other', 'unknown')
    and resolution->>'garment_type_code' in ('other', 'unknown')
    and resolution->>'authority_status' is distinct from 'verified';

  select count(*) into v_underwear_leak
  from _phase1b2r_shadow
  where resolution->>'category_code' = 'underwear'
    and coalesce((comparison_preview->>'allowed')::boolean, false)
    and coalesce(resolution->>'garment_type_code', '') in (
      '', 'underwear', 'generic_underwear'
    );

  select count(*) into v_profile_confirm_count
  from _phase1b2r_shadow
  where resolution->>'classification_method' = 'product_classifier';

  if v_unsafe_product_required <> 0
    or v_unsafe_revoked <> 0
    or v_both_untrusted_unresolved <> 0
    or v_conflict_unresolved <> 717
    or v_unknown_fallback <> 0
    or v_underwear_leak <> 0
    or v_profile_confirm_count <> 0 then
    raise exception 'phase1b2r_fail_closed_acceptance_failed product_required=% revoked=% both_untrusted=% conflict717=% fallback=% underwear=% profile=%',
      v_unsafe_product_required, v_unsafe_revoked,
      v_both_untrusted_unresolved, v_conflict_unresolved,
      v_unknown_fallback, v_underwear_leak, v_profile_confirm_count;
  end if;

  select count(*) into v_vocabulary_owner_review
  from _phase1b2r_db_only item
  join _phase1b2r_shadow shadow
    on shadow.source = item.line::jsonb->>'source'
   and shadow.external_product_id =
     item.line::jsonb->>'external_product_id'
  where item.line::jsonb->>'verdict' =
      'VOCABULARY_TRANSLATION_NEEDS_OWNER_CONFIRM'
    and shadow.resolution->>'classification_status' = 'review_required';

  select count(*) into v_invalid_vocabulary_review
  from _phase1b2r_repository_manifest manifest
  cross join lateral jsonb_array_elements_text(
    manifest.line::jsonb->'affected_products'
  ) product(product_key)
  join _phase1b2r_shadow shadow
    on shadow.source = split_part(product_key, ':', 1)
   and shadow.external_product_id =
     substring(product_key from position(':' in product_key) + 1)
  where manifest.line::jsonb->>'record_type' =
      'unapproved_invalid_vocabulary_parity'
    and shadow.resolution->>'classification_status' = 'review_required';

  if v_vocabulary_owner_review <> 7
    or v_invalid_vocabulary_review <> 71 then
    raise exception 'phase1b2r_unapproved_vocabulary_changed owner7=% invalid71=%',
      v_vocabulary_owner_review, v_invalid_vocabulary_review;
  end if;

  v_tshirt_base_layer_probe :=
    fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
      'tops', 'MEN', 'tshirt', 'short_sleeve', 'short_sleeve', null,
      'tops', 'MEN', 'base_layer_top', 'base_layer_top',
      'short_sleeve', null, 'tshirt', 'base_layer_top', false,
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
    );
  if coalesce((v_tshirt_base_layer_probe->>'allowed')::boolean, false)
    or v_tshirt_base_layer_probe->>'reason' <>
      'base_layer_top_tshirt_automatic_comparison_blocked' then
    raise exception 'phase1b2r_tshirt_base_layer_safety_failed:%',
      v_tshirt_base_layer_probe;
  end if;

  update fitmatch_catalog.releases
  set validation_report = validation_report || jsonb_build_object(
    'shadow_output_checksum', v_summary.shadow_output_checksum,
    'confirmed_count', v_summary.confirmed_count,
    'review_required_count', v_summary.review_required_count,
    'required_approved_review_to_confirmed_count', 86,
    'approved_review_to_confirmed_count', v_approved_transition_count,
    'target_clone_mapping_selected_count',
      v_clone_mapping_selected_count,
    'target_clone_confirmed_count', v_clone_transition_count,
    'target_clone_legacy_decision_conflict_count',
      v_clone_conflict_count,
    'target_clone_legacy_decision_conflict_products',
      v_clone_conflict_products,
    'owner_acceptance_target_met', false,
    'acceptance_result', 'PARTIAL_NO_GO'
  )
  where id = 'f83ca2f0-88a4-4430-96fc-037d6f1efcc2';

  raise notice 'PHASE1B2R_SHADOW_SUMMARY=%', row_to_json(v_summary);
  raise notice 'PHASE1B2R_TRANSITIONS baseline_confirmed_retained=177 approved_review_to_confirmed=% unexpected=% clone_selected=% clone_confirmed=% clone_conflict=% decisions=%',
    v_approved_transition_count, v_unexpected_transition_count,
    v_clone_mapping_selected_count, v_clone_transition_count,
    v_clone_conflict_count, v_decision_transition_count;
  raise notice 'PHASE1B2R_FAIL_CLOSED product_required=% revoked=% both_untrusted=% conflict_unresolved=% fallback=% underwear=% profile=% vocabulary_owner=% invalid_vocabulary=% comparison_regression=%',
    v_unsafe_product_required, v_unsafe_revoked,
    v_both_untrusted_unresolved, v_conflict_unresolved,
    v_unknown_fallback, v_underwear_leak, v_profile_confirm_count,
    v_vocabulary_owner_review, v_invalid_vocabulary_review,
    v_comparison_regression;
end $$;

do $$
declare
  v_artifact jsonb;
  v_gate jsonb;
  v_stored_checksum text;
  v_actual_checksum text;
begin
  select validation_report->>'shadow_output_checksum'
  into v_stored_checksum
  from fitmatch_catalog.releases
  where id = 'f83ca2f0-88a4-4430-96fc-037d6f1efcc2';
  select shadow_output_checksum into v_actual_checksum
  from _phase1b2r_shadow_summary;
  if v_stored_checksum is distinct from v_actual_checksum then
    raise exception 'phase1b2r_shadow_checksum_mismatch stored=% actual=%',
      v_stored_checksum, v_actual_checksum;
  end if;

  v_artifact :=
    fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
    );
  if not coalesce((v_artifact->>'eligible')::boolean, false)
    or (v_artifact->>'targeted_decision_match_count')::integer <> 116
    or (v_artifact->>'targeted_decision_mismatch_count')::integer <> 0 then
    raise exception 'phase1b2r_post_decision_artifact_gate_failed:%',
      v_artifact;
  end if;

  v_gate :=
    fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'
    );
  if coalesce((v_gate->>'eligible')::boolean, false)
    or jsonb_array_length(v_gate->'blockers') <> 1
    or not (v_gate->'blockers' ? 'approved_transition_shortfall') then
    raise exception 'phase1b2r_expected_no_go_gate_failed:%', v_gate;
  end if;

  if (select status from fitmatch_catalog.releases
      where id = '65d72393-4a40-4e99-b701-fdc1ff865774') <> 'active'
    or (select status from fitmatch_catalog.releases
        where id = 'f83ca2f0-88a4-4430-96fc-037d6f1efcc2') <>
      'validated'
    or (select count(*) from fitmatch_catalog.releases
        where status = 'active') <> 1
    or (select count(*)
        from fitmatch_catalog.product_classification_history) <> 0 then
    raise exception 'phase1b2r_release_or_history_mutation_detected';
  end if;
end $$;

-- stdout is exactly the 1,608 revision shadow JSONL rows.
copy (
  select manifest_row
  from _phase1b2r_shadow
  order by source, external_product_id
) to stdout;

rollback;
