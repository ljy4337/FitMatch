-- FitMatch vNext final-remediation READ-ONLY audit.
-- Target: hnkplvyegonlhumlejst / fitmatch_vnext
-- This script performs no writes and returns one self-contained JSON report.

with
catalog_identity as (
    select lower(source) source_code, external_product_id::text source_product_key
    from fitmatch_catalog.products
),
vnext_identity as (
    select source_code, source_product_key
    from fitmatch_vnext.products
),
product_eval as materialized (
    select p.*,
           gt.is_active garment_active,
           gt.uses_sleeve_length,
           gt.uses_lower_length,
           gt.uses_body_length,
           gt.comparison_policy_code,
           fitmatch_vnext.classification_decision(
               p.source_code, p.source_product_key
           ) decision_one,
           fitmatch_vnext.classification_decision(
               p.source_code, p.source_product_key
           ) decision_two,
           fitmatch_vnext.product_readiness(p.id) readiness
    from fitmatch_vnext.products p
    left join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code
),
mapping_top as (
    select m.*,
           max(m.priority) over (
               partition by m.source_signal_id, m.audience_code
           ) max_priority
    from fitmatch_vnext.classification_signal_mappings m
    where m.is_active and m.is_verified
),
mapping_conflicts as (
    select source_signal_id, audience_code
    from mapping_top
    where priority = max_priority
    group by source_signal_id, audience_code
    having count(distinct concat_ws('|', resolution_mode,
        coalesce(garment_type_code, '∅'),
        coalesce(sleeve_length_code, '∅'),
        coalesce(lower_length_code, '∅'),
        coalesce(body_length_code, '∅'))) > 1
),
measurement_eval as materialized (
    select pm.id,
           fitmatch_vnext.resolve_measurement(
               p.source_code, pm.parser_code, pm.raw_code, pm.raw_label,
               p.garment_type_code, gt.category_code, pm.raw_value
           ) decision_one,
           fitmatch_vnext.resolve_measurement(
               p.source_code, pm.parser_code, pm.raw_code, pm.raw_label,
               p.garment_type_code, gt.category_code, pm.raw_value
           ) decision_two
    from fitmatch_vnext.product_size_measurements pm
    join fitmatch_vnext.product_sizes ps on ps.id = pm.product_size_id
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    left join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code
    where pm.is_current
),
size_semantics as materialized (
    select ps.id product_size_id,
           fitmatch_vnext.canonical_measurements_for_size(ps.id) canonical
    from fitmatch_vnext.product_sizes ps
),
latest_availability as materialized (
    select distinct on (o.product_size_id)
           o.product_size_id, o.availability_status, o.observed_at,
           o.valid_until, o.evidence_fingerprint
    from fitmatch_vnext.size_availability_observations o
    order by o.product_size_id, o.observed_at desc, o.id desc
),
policy_size_eval as (
    select p.id product_id, ps.id product_size_id,
           la.availability_status, la.valid_until, la.evidence_fingerprint,
           coalesce((ss.canonical ->> 'semantic_conflict_count')::integer, 0)
               semantic_conflict_count,
           cp.min_common_measurements, cp.required_any_min,
           count(distinct cm.fitmatch_measurement_code) policy_metric_count,
           count(distinct cm.fitmatch_measurement_code) filter (
               where cm.requirement_mode = 'REQUIRED_ANY'
           ) required_any_count
    from fitmatch_vnext.products p
    join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code and gt.is_active
    join fitmatch_vnext.comparison_policies cp
      on cp.policy_code = gt.comparison_policy_code and cp.is_active
    join fitmatch_vnext.product_variants pv on pv.product_id = p.id
    join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
    left join latest_availability la on la.product_size_id = ps.id
    join size_semantics ss on ss.product_size_id = ps.id
    left join lateral jsonb_array_elements(ss.canonical -> 'measurements') m on true
    left join fitmatch_vnext.comparison_metrics cm
      on cm.comparison_policy_code = cp.policy_code
     and cm.metric_mode = 'CANONICAL'
     and cm.is_active
     and cm.fitmatch_measurement_code = m ->> 'fitmatch_measurement_code'
    group by p.id, ps.id, la.availability_status, la.valid_until,
             la.evidence_fingerprint, ss.canonical,
             cp.min_common_measurements, cp.required_any_min
),
eligible_policy_sizes as (
    select *
    from policy_size_eval
    where availability_status = 'AVAILABLE'
      and valid_until is not null
      and valid_until >= now()
      and evidence_fingerprint is not null
      and semantic_conflict_count = 0
      and policy_metric_count >= min_common_measurements
      and required_any_count >= required_any_min
),
alias_top as (
    select a.*,
           max(priority) over (partition by source_code, parser_code,
               coalesce(raw_code, '∅'), normalized_label,
               coalesce(fitmatch_category_code, '∅'),
               coalesce(garment_type_code, '∅')) max_priority
    from fitmatch_vnext.source_measurement_aliases a
    where a.is_active and a.is_verified
),
alias_conflicts as (
    select source_code, parser_code, coalesce(raw_code, '∅') raw_code,
           normalized_label, coalesce(fitmatch_category_code, '∅') category_code,
           coalesce(garment_type_code, '∅') garment_type_code
    from alias_top where priority = max_priority
    group by 1,2,3,4,5,6
    having count(distinct source_measurement_code) > 1
),
boundary_cases(policy_code, case_code, measurement_codes, expected_allowed) as (
    values
      ('tshirt','TOP_EMPTY','{}'::text[],false),
      ('tshirt','TOP_CHEST_ONLY',array['chest_width'],false),
      ('tshirt','TOP_SHOULDER_ONLY',array['shoulder_width'],false),
      ('tshirt','TOP_LENGTH_ONLY',array['total_length'],false),
      ('tshirt','TOP_LENGTH_SLEEVE',array['total_length','sleeve_length'],false),
      ('tshirt','TOP_CHEST_LENGTH',array['chest_width','total_length'],true),
      ('tshirt','TOP_SHOULDER_LENGTH',array['shoulder_width','total_length'],true),
      ('jacket','OUTER_EMPTY','{}'::text[],false),
      ('jacket','OUTER_CHEST_ONLY',array['chest_width'],false),
      ('jacket','OUTER_LENGTH_SLEEVE',array['total_length','sleeve_length'],false),
      ('jacket','OUTER_CHEST_LENGTH',array['chest_width','total_length'],true),
      ('jacket','OUTER_CHEST_SHOULDER',array['chest_width','shoulder_width'],true),
      ('standard_pants','BOTTOM_EMPTY','{}'::text[],false),
      ('standard_pants','BOTTOM_WAIST_ONLY',array['waist_width'],false),
      ('standard_pants','BOTTOM_HIP_ONLY',array['hip_width'],false),
      ('standard_pants','BOTTOM_THIGH_ONLY',array['thigh_width'],false),
      ('standard_pants','BOTTOM_WAIST_HIP',array['waist_width','hip_width'],true),
      ('standard_pants','BOTTOM_WAIST_THIGH',array['waist_width','thigh_width'],true),
      ('standard_pants','BOTTOM_HIP_THIGH',array['hip_width','thigh_width'],true)
),
boundary_eval as (
    select b.*,
           cp.min_common_measurements, cp.required_any_min,
           count(distinct cm.fitmatch_measurement_code) common_count,
           count(distinct cm.fitmatch_measurement_code) filter (
               where cm.requirement_mode = 'REQUIRED_ANY'
           ) required_count
    from boundary_cases b
    join fitmatch_vnext.comparison_policies cp
      on cp.policy_code = b.policy_code and cp.is_active
    left join fitmatch_vnext.comparison_metrics cm
      on cm.comparison_policy_code = b.policy_code
     and cm.metric_mode = 'CANONICAL' and cm.is_active
     and cm.fitmatch_measurement_code = any(b.measurement_codes)
    group by b.policy_code, b.case_code, b.measurement_codes,
             b.expected_allowed, cp.min_common_measurements, cp.required_any_min
),
selected_functions(signature, user_facing) as (
    values
      ('fitmatch_vnext.ingest_product_observation(jsonb,uuid)',false),
      ('fitmatch_vnext.get_product_runtime(text,text)',true),
      ('fitmatch_vnext.resolve_product_classification(text,text,boolean)',false),
      ('fitmatch_vnext.product_readiness(uuid)',false),
      ('fitmatch_vnext.upsert_closet_item(jsonb)',true),
      ('fitmatch_vnext.list_closet_items()',true),
      ('fitmatch_vnext.set_closet_reference(uuid)',true),
      ('fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)',true),
      ('fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)',true),
      ('fitmatch_vnext.find_reference_candidates(uuid,uuid)',true),
      ('fitmatch_vnext.begin_comparison(jsonb)',true),
      ('fitmatch_vnext.complete_comparison(uuid,jsonb)',true),
      ('fitmatch_vnext.comparison_history()',true)
),
function_eval as (
    select sf.*, p.oid, p.prosecdef, p.proconfig,
           case when p.oid is null then null else pg_get_functiondef(p.oid) end definition
    from selected_functions sf
    left join pg_proc p on p.oid = to_regprocedure(sf.signature)
),
source_coverage as (
    select p.source_code,
           count(*) total,
           count(*) filter (where p.classification_status = 'CONFIRMED') confirmed,
           count(*) filter (where p.classification_status = 'REVIEW_REQUIRED') review_required,
           count(*) filter (where p.classification_status = 'NOT_APPLICABLE') not_applicable,
           count(*) filter (
               where p.classification_status = 'CONFIRMED'
                 and coalesce((fitmatch_vnext.classification_tuple_validation(
                     p.garment_type_code, p.product_structure_code, p.audience_code,
                     p.sleeve_length_code, p.lower_length_code, p.body_length_code
                 ) ->> 'valid')::boolean, false)
                 and p.garment_active
                 and exists (select 1 from fitmatch_vnext.comparison_policies cp
                     where cp.policy_code = p.comparison_policy_code and cp.is_active)
           ) potential_ready,
           count(*) filter (where p.readiness ->> 'status' = 'READY') evidence_ready,
           count(*) filter (where not exists (
               select 1 from fitmatch_vnext.product_variants pv
               join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
               where pv.product_id = p.id
           )) no_size,
           count(*) filter (where not exists (
               select 1 from fitmatch_vnext.product_variants pv
               join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
               join fitmatch_vnext.product_size_measurements pm
                 on pm.product_size_id = ps.id and pm.is_current
               where pv.product_id = p.id
           )) no_measurement,
           count(*) filter (where p.readiness ->> 'status' = 'NO_AVAILABLE_SIZE')
               no_available_size,
           count(*) filter (where p.readiness ->> 'status' = 'MAPPING_REQUIRED')
               mapping_required
    from product_eval p
    group by p.source_code
),
raw_counts as (
    select
      (select count(*) from vnext_identity) product_count,
      (select count(*) from (
          select source_code, source_product_key from vnext_identity
          group by 1,2 having count(*) > 1
      ) d) duplicate_identity_groups,
      (select count(*) from (
          select * from catalog_identity except select * from vnext_identity
      ) missing) baseline_identity_loss,
      (select count(*) from (
          select * from vnext_identity except select * from catalog_identity
      ) extra) vnext_only_products,
      (select count(*) from fitmatch_vnext.product_variants pv
       left join fitmatch_vnext.products p on p.id = pv.product_id
       where p.id is null) orphan_variants,
      (select count(*) from fitmatch_vnext.product_sizes ps
       left join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
       where pv.id is null) orphan_sizes,
      (select count(*) from fitmatch_vnext.product_size_measurements pm
       left join fitmatch_vnext.product_sizes ps on ps.id = pm.product_size_id
       where ps.id is null) orphan_measurements,
      (select count(*) from product_eval where classification_status='CONFIRMED') confirmed,
      (select count(*) from product_eval where classification_status='REVIEW_REQUIRED') review_required,
      (select count(*) from product_eval where classification_status='NOT_APPLICABLE') not_applicable,
      (select count(*) from product_eval
       where classification_status='CONFIRMED' and not coalesce((
           fitmatch_vnext.classification_tuple_validation(
             garment_type_code, product_structure_code, audience_code,
             sleeve_length_code, lower_length_code, body_length_code
           )->>'valid')::boolean,false)) confirmed_invalid,
      (select count(*) from product_eval
       where classification_status='CONFIRMED'
         and uses_sleeve_length and (sleeve_length_code is null or sleeve_length_code='UNKNOWN'))
          required_sleeve_missing,
      (select count(*) from product_eval
       where classification_status='CONFIRMED'
         and uses_lower_length and (lower_length_code is null or lower_length_code='UNKNOWN'))
          required_lower_missing,
      (select count(*) from product_eval
       where classification_status='CONFIRMED'
         and uses_body_length and (body_length_code is null or body_length_code='UNKNOWN'))
          required_body_missing,
      (select count(*) from product_eval
       where classification_status='CONFIRMED' and product_structure_code <> 'SINGLE')
          confirmed_non_single,
      (select count(*) from product_eval
       where classification_status='CONFIRMED' and not coalesce(garment_active,false))
          confirmed_inactive_garment,
      (select count(*) from product_eval
       where classification_status='CONFIRMED' and (
         primary_source_signal_id is null or classification_mapping_id is null
         or resolver_version is null or input_fingerprint is null
         or evidence_fingerprint is null or classified_at is null))
          confirmed_provenance_missing,
      (select count(*) from product_eval p
       left join fitmatch_vnext.classification_signal_mappings m
         on m.id=p.classification_mapping_id
       where p.classification_status='CONFIRMED'
         and (m.id is null or not m.is_active or not m.is_verified))
          confirmed_inactive_or_unverified_mapping,
      (select count(*) from mapping_conflicts) top_priority_conflicts,
      (select count(*) from fitmatch_vnext.classification_signal_mappings m
       left join fitmatch_vnext.garment_types gt
         on gt.garment_type_code=m.garment_type_code
       where m.is_active and m.is_verified and m.resolution_mode='DIRECT'
         and (m.garment_type_code is null or not coalesce(gt.is_active,false)
           or (gt.uses_sleeve_length and
               (m.sleeve_length_code is null or m.sleeve_length_code='UNKNOWN'))
           or (not gt.uses_sleeve_length and m.sleeve_length_code is not null)
           or (gt.uses_lower_length and
               (m.lower_length_code is null or m.lower_length_code='UNKNOWN'))
           or (not gt.uses_lower_length and m.lower_length_code is not null)
           or (gt.uses_body_length and
               (m.body_length_code is null or m.body_length_code='UNKNOWN'))
           or (not gt.uses_body_length and m.body_length_code is not null)))
          invalid_direct_mappings,
      (select count(*) from product_eval where decision_one <> decision_two)
          classification_repeated_input_mismatch,
      (select count(*) from product_eval
       where classification_status <> decision_one ->> 'classification_status'
          or product_structure_code is distinct from
               decision_one ->> 'product_structure_code'
          or garment_type_code is distinct from decision_one ->> 'garment_type_code'
          or sleeve_length_code is distinct from decision_one ->> 'sleeve_length_code'
          or lower_length_code is distinct from decision_one ->> 'lower_length_code'
          or body_length_code is distinct from decision_one ->> 'body_length_code')
          classification_stored_result_mismatch,
      (select count(*) from measurement_eval) current_raw_measurements,
      (select count(*) from measurement_eval where decision_one <> decision_two)
          measurement_repeated_input_mismatch,
      (select count(*) from alias_conflicts) active_alias_top_priority_conflicts,
      (select count(*) from policy_size_eval
       where availability_status='AVAILABLE' and valid_until is not null
         and valid_until>=now() and semantic_conflict_count>0)
          usable_size_semantic_conflicts,
      (select count(*) from fitmatch_vnext.fitmatch_measurements
       where is_active and (
         (measurement_code like '%_width' and representation_code <> 'FLAT_WIDTH')
         or (measurement_code like '%_circumference'
             and representation_code <> 'CIRCUMFERENCE')))
          width_circumference_representation_errors,
      (select count(*) from product_eval p
       where p.readiness ->> 'status'='READY'
         and not exists (select 1 from eligible_policy_sizes e
                         where e.product_id=p.id)) false_ready_products,
      (select count(*) from product_eval p
       where p.readiness ->> 'status'<>'READY'
         and p.classification_status='CONFIRMED'
         and coalesce((fitmatch_vnext.classification_tuple_validation(
             p.garment_type_code,p.product_structure_code,p.audience_code,
             p.sleeve_length_code,p.lower_length_code,p.body_length_code
         )->>'valid')::boolean,false)
         and exists (select 1 from eligible_policy_sizes e where e.product_id=p.id))
          false_not_ready_products,
      (select count(*) from latest_availability
       where availability_status='AVAILABLE'
         and (valid_until is null or valid_until<now())) current_expired_or_unbounded_available,
      (select count(*) from product_eval where readiness->>'status'='READY') ready,
      (select count(*) from product_eval where readiness->>'status'='NO_AVAILABLE_SIZE')
          no_available_size,
      (select count(*) from product_eval where readiness->>'status'='NO_MEASUREMENT_DATA')
          no_measurement_data,
      (select count(*) from product_eval where readiness->>'status'='MAPPING_REQUIRED')
          mapping_required,
      (select count(*) from product_eval
       where readiness->>'status'='INSUFFICIENT_MEASUREMENTS') insufficient_measurements,
      (select count(*) from product_eval
       where readiness->>'status'='CLASSIFICATION_REQUIRED') classification_required,
      (select count(*) from product_eval where readiness->>'status'='NOT_APPLICABLE')
          readiness_not_applicable,
      (select count(*) from product_eval
       where (source_code,source_product_key) in (
         ('musinsa','6805433'),('uniqlo','E482856'),('zara','561264931'))
         and readiness->>'status'='READY') golden_ready_count,
      (select count(*) from boundary_eval) boundary_case_count,
      (select count(*) from boundary_eval
       where ((common_count>=min_common_measurements
           and required_count>=required_any_min) is distinct from expected_allowed))
          boundary_failures,
      (select count(*) from fitmatch_vnext.garment_types gt
       join fitmatch_vnext.comparison_policies cp
         on cp.policy_code=gt.comparison_policy_code
       where gt.is_active and not cp.is_active) active_garment_inactive_policy,
      (select count(*) from function_eval where oid is null) missing_runtime_functions,
      (select count(*) from function_eval
       where prosecdef and not coalesce(proconfig @> array['search_path=""'],false))
          insecure_definer_search_paths,
      (select count(*) from function_eval
       where definition ilike '%fitmatch_catalog.%'
          or definition ilike '%public.fitmatch_%') selected_legacy_business_references,
      (select count(*) from information_schema.role_table_grants g
       where g.table_schema='fitmatch_vnext' and g.grantee='authenticated'
         and g.table_name in ('products','product_variants','product_sizes',
           'product_size_measurements','source_identifiers',
           'source_classification_signals','product_classification_signals',
           'size_availability_observations','classification_signal_mappings',
           'closet_items','closet_item_measurements','comparisons',
           'product_ingestion_receipts')
         and g.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE'))
          broad_authenticated_write_grants,
      (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='fitmatch_vnext'
         and c.relname in ('closet_items','closet_item_measurements','comparisons',
           'product_ingestion_receipts','size_availability_observations')
         and not c.relrowsecurity) sensitive_rls_disabled,
      (has_function_privilege('anon',
        'fitmatch_vnext.ingest_product_observation(jsonb,uuid)','EXECUTE')
       or has_function_privilege('authenticated',
        'fitmatch_vnext.ingest_product_observation(jsonb,uuid)','EXECUTE'))::integer
          ingestion_not_service_only,
      (select count(*) from function_eval
       where user_facing and not has_function_privilege(
           'authenticated', signature, 'EXECUTE')) authenticated_rpc_grant_missing,
      (has_function_privilege('anon',
        'fitmatch_vnext.begin_comparison(jsonb)','EXECUTE')
       or has_function_privilege('anon',
        'fitmatch_vnext.complete_comparison(uuid,jsonb)','EXECUTE')
       or has_function_privilege('anon',
        'fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)','EXECUTE'))::integer
          anonymous_comparison_execute,
      (select count(*) from fitmatch_vnext.comparisons
       where result_status='COMPLETED' and (
         recommended_product_size_id is null or recommended_size_label is null
         or fit_score is null or reliability_level is null or coverage_ratio is null
         or completed_at is null or result_payload_hash is null
         or reference_snapshot='{}' or target_snapshot='{}'
         or authority_snapshot='{}' or policy_snapshot='{}'
         or input_snapshot='{}' or result_evidence='{}'
         or jsonb_array_length(result_evidence->'candidate_size_ranking')=0
         or jsonb_array_length(result_evidence->'metric_evidence')=0))
          completed_history_invalid,
      (select count(*) from fitmatch_vnext.product_ingestion_receipts
       where processing_status='PROCESSING') stuck_ingestion_receipts,
      (select count(*) from supabase_migrations.schema_migrations
       where name in ('vnext_ingestion_contract','vnext_readiness_policy_metrics',
        'vnext_candidate_size_authority','vnext_comparison_begin_provenance',
        'vnext_completion_validation','vnext_reference_candidate_discovery',
        'vnext_final_security_regression',
        'vnext_completion_ingestion_hardening')) remediation_migration_count,
      (select count(*) from pg_trigger
       where tgrelid='fitmatch_vnext.comparisons'::regclass
         and tgname in ('comparisons_protect_completed',
                        'comparisons_validate_completion_payload')
         and not tgisinternal) comparison_protection_trigger_count,
      (select count(*) from pg_trigger
       where tgrelid='fitmatch_vnext.product_ingestion_receipts'::regclass
         and tgname in ('product_ingestion_receipts_protect_evidence',
                        'product_ingestion_receipts_validate_facts')
         and not tgisinternal) ingestion_protection_trigger_count,
      (to_regclass('fitmatch_vnext.closet_items_reference_scope_uidx') is not null)::integer
          atomic_reference_unique_index,
      (select count(*) from fitmatch_vnext.products
       where source_product_key like 'vnext-final-regression-%') fixture_product_pollution
),
gate_values as (
    select r.*,
      array[
        baseline_identity_loss=0,
        duplicate_identity_groups+orphan_variants+orphan_sizes+orphan_measurements=0,
        confirmed_invalid=0,
        required_sleeve_missing+required_lower_missing+required_body_missing
          +confirmed_non_single+confirmed_inactive_garment=0,
        confirmed_provenance_missing+confirmed_inactive_or_unverified_mapping=0,
        top_priority_conflicts+invalid_direct_mappings=0,
        classification_repeated_input_mismatch+classification_stored_result_mismatch=0,
        measurement_repeated_input_mismatch+active_alias_top_priority_conflicts=0,
        usable_size_semantic_conflicts+width_circumference_representation_errors=0,
        false_ready_products+false_not_ready_products=0,
        golden_ready_count=3,
        boundary_case_count=19 and boundary_failures=0
          and active_garment_inactive_policy=0,
        missing_runtime_functions=0,
        ingestion_not_service_only=0 and stuck_ingestion_receipts=0,
        broad_authenticated_write_grants=0 and sensitive_rls_disabled=0,
        insecure_definer_search_paths=0 and authenticated_rpc_grant_missing=0
          and anonymous_comparison_execute=0,
        selected_legacy_business_references=0,
        completed_history_invalid=0 and comparison_protection_trigger_count=2,
        ingestion_protection_trigger_count=2 and atomic_reference_unique_index=1,
        remediation_migration_count=8 and fixture_product_pollution=0
      ] contract_gates
    from raw_counts r
),
scored as (
    select g.*,
           (select count(*) from unnest(g.contract_gates) passed where passed)
               passed_gate_count,
           (select count(*) from unnest(g.contract_gates) passed where not passed)
               p0_count
    from gate_values g
)
select jsonb_build_object(
  'audit', jsonb_build_object(
    'project_id','hnkplvyegonlhumlejst',
    'schema','fitmatch_vnext',
    'audited_at',now(),
    'mode','READ_ONLY'
  ),
  'product_identity', jsonb_build_object(
    'products',product_count,
    'duplicate_identity_groups',duplicate_identity_groups,
    'baseline_identity_loss',baseline_identity_loss,
    'vnext_only_products',vnext_only_products,
    'orphan_variants',orphan_variants,
    'orphan_sizes',orphan_sizes,
    'orphan_measurements',orphan_measurements
  ),
  'classification', jsonb_build_object(
    'confirmed',confirmed,'review_required',review_required,
    'not_applicable',not_applicable,'confirmed_invalid',confirmed_invalid,
    'required_sleeve_missing',required_sleeve_missing,
    'required_lower_missing',required_lower_missing,
    'required_body_missing',required_body_missing,
    'confirmed_non_single',confirmed_non_single,
    'confirmed_inactive_garment',confirmed_inactive_garment,
    'confirmed_provenance_missing',confirmed_provenance_missing,
    'confirmed_inactive_or_unverified_mapping',confirmed_inactive_or_unverified_mapping,
    'invalid_direct_mappings',invalid_direct_mappings,
    'top_priority_conflicts',top_priority_conflicts,
    'replay_count',product_count,
    'repeated_input_mismatch',classification_repeated_input_mismatch,
    'stored_result_mismatch',classification_stored_result_mismatch
  ),
  'measurement', jsonb_build_object(
    'current_raw_measurements',current_raw_measurements,
    'repeated_input_mismatch',measurement_repeated_input_mismatch,
    'active_alias_top_priority_conflicts',active_alias_top_priority_conflicts,
    'usable_size_semantic_conflicts',usable_size_semantic_conflicts,
    'width_circumference_representation_errors',
      width_circumference_representation_errors
  ),
  'readiness', jsonb_build_object(
    'ready',ready,'no_available_size',no_available_size,
    'no_measurement_data',no_measurement_data,
    'mapping_required',mapping_required,
    'insufficient_measurements',insufficient_measurements,
    'classification_required',classification_required,
    'not_applicable',readiness_not_applicable,
    'false_ready_products',false_ready_products,
    'false_not_ready_products',false_not_ready_products,
    'current_expired_or_unbounded_available',current_expired_or_unbounded_available,
    'golden_ready_count',golden_ready_count
  ),
  'policy',jsonb_build_object(
    'boundary_passed',boundary_case_count-boundary_failures,
    'boundary_total',boundary_case_count,
    'boundary_failures',boundary_failures,
    'active_garment_inactive_policy',active_garment_inactive_policy
  ),
  'runtime_security_history',jsonb_build_object(
    'missing_runtime_functions',missing_runtime_functions,
    'selected_legacy_business_references',selected_legacy_business_references,
    'broad_authenticated_write_grants',broad_authenticated_write_grants,
    'sensitive_rls_disabled',sensitive_rls_disabled,
    'insecure_definer_search_paths',insecure_definer_search_paths,
    'authenticated_rpc_grant_missing',authenticated_rpc_grant_missing,
    'anonymous_comparison_execute',anonymous_comparison_execute,
    'ingestion_not_service_only',ingestion_not_service_only,
    'stuck_ingestion_receipts',stuck_ingestion_receipts,
    'completed_history_invalid',completed_history_invalid,
    'comparison_protection_trigger_count',comparison_protection_trigger_count,
    'ingestion_protection_trigger_count',ingestion_protection_trigger_count,
    'atomic_reference_unique_index',atomic_reference_unique_index,
    'remediation_migration_count',remediation_migration_count,
    'fixture_product_pollution',fixture_product_pollution
  ),
  'source_coverage',(
    select jsonb_agg(to_jsonb(sc) order by sc.source_code) from source_coverage sc
  ),
  'score',passed_gate_count*5,
  'score_denominator',100,
  'p0_count',p0_count,
  'verdict',case when p0_count=0 then 'VNext PRE-E2E READY'
                 else 'VNext PRE-E2E NOT READY' end
) final_read_only_audit
from scored;

