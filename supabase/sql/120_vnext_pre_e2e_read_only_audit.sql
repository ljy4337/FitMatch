-- FitMatch vNext Production Database final PRE-E2E read-only audit.
-- Target project: hnkplvyegonlhumlejst
-- Target schema: fitmatch_vnext

-- 1. Product identity parity and hierarchy integrity.
with catalog_identity as (
    select lower(source) source_code, external_product_id::text source_product_key
    from fitmatch_catalog.products
), vnext_identity as (
    select lower(source_code) source_code, source_product_key
    from fitmatch_vnext.products
)
select
    (select count(*) from vnext_identity) product_count,
    (select count(*) from (
        select source_code, source_product_key
        from vnext_identity group by 1, 2 having count(*) > 1
    ) duplicates) duplicate_identity_groups,
    (select count(*) from (
        select * from catalog_identity except select * from vnext_identity
    ) missing) catalog_missing_in_vnext,
    (select count(*) from (
        select * from vnext_identity except select * from catalog_identity
    ) extra) vnext_missing_in_catalog,
    (select count(*) from fitmatch_vnext.product_variants pv
     left join fitmatch_vnext.products p on p.id = pv.product_id
     where p.id is null) orphan_variants,
    (select count(*) from fitmatch_vnext.product_sizes ps
     left join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
     where pv.id is null) orphan_sizes,
    (select count(*) from fitmatch_vnext.product_size_measurements pm
     left join fitmatch_vnext.product_sizes ps on ps.id = pm.product_size_id
     where ps.id is null) orphan_measurements;

-- 2. Classification invariants, provenance, mapping invariants, and replay.
with mapping_top as (
    select m.*,
           max(priority) over (partition by source_signal_id, audience_code) max_priority
    from fitmatch_vnext.classification_signal_mappings m
    where is_active and is_verified
), replay as (
    select p.*,
           fitmatch_vnext.classification_decision(
               p.source_code, p.source_product_key
           ) decision_one,
           fitmatch_vnext.classification_decision(
               p.source_code, p.source_product_key
           ) decision_two
    from fitmatch_vnext.products p
)
select
    count(*) replay_count,
    count(*) filter (where classification_status = 'CONFIRMED') confirmed,
    count(*) filter (where classification_status = 'REVIEW_REQUIRED') review_required,
    count(*) filter (where classification_status = 'NOT_APPLICABLE') not_applicable,
    count(*) filter (
        where classification_status = 'CONFIRMED'
          and not (fitmatch_vnext.classification_tuple_validation(
              garment_type_code, product_structure_code, audience_code,
              sleeve_length_code, lower_length_code, body_length_code
          ) ->> 'valid')::boolean
    ) confirmed_invalid,
    count(*) filter (
        where classification_status = 'CONFIRMED'
          and (primary_source_signal_id is null
               or classification_mapping_id is null
               or resolver_version is null
               or input_fingerprint is null
               or evidence_fingerprint is null)
    ) confirmed_provenance_missing,
    count(*) filter (where decision_one <> decision_two) repeated_input_mismatch,
    count(*) filter (
        where classification_status <> decision_one ->> 'classification_status'
           or garment_type_code is distinct from decision_one ->> 'garment_type_code'
           or sleeve_length_code is distinct from decision_one ->> 'sleeve_length_code'
           or lower_length_code is distinct from decision_one ->> 'lower_length_code'
           or body_length_code is distinct from decision_one ->> 'body_length_code'
    ) stored_result_mismatch,
    (select count(*) from (
        select source_signal_id, audience_code
        from mapping_top where priority = max_priority
        group by 1, 2
        having count(distinct concat_ws('|', resolution_mode,
            coalesce(garment_type_code, '∅'),
            coalesce(sleeve_length_code, '∅'),
            coalesce(lower_length_code, '∅'),
            coalesce(body_length_code, '∅'))) > 1
    ) conflicts) top_priority_conflict_groups
from replay;

-- 3. Full semantic resolver regression.
with decisions as (
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
), size_semantics as (
    select (fitmatch_vnext.canonical_measurements_for_size(ps.id)
        ->> 'semantic_conflict_count')::integer semantic_conflicts
    from fitmatch_vnext.product_sizes ps
)
select
    count(*) measurement_count,
    count(*) filter (where decision_one ->> 'resolution_status' = 'RESOLVED') resolved,
    count(*) filter (where decision_one ->> 'resolution_status' = 'UNMAPPED') unmapped,
    count(*) filter (
        where decision_one ->> 'resolution_status' = 'MAPPING_REQUIRED'
    ) mapping_required,
    count(*) filter (where decision_one ->> 'resolution_status' = 'AMBIGUOUS') ambiguous,
    count(*) filter (where decision_one <> decision_two) repeated_input_mismatch,
    (select coalesce(sum(semantic_conflicts), 0) from size_semantics) semantic_conflicts
from decisions;

-- 4. Runtime readiness and provider golden fixtures.
with readiness as (
    select p.source_code, p.source_product_key,
           fitmatch_vnext.product_readiness(p.id) result
    from fitmatch_vnext.products p
)
select
    count(*) filter (where result ->> 'status' = 'READY') ready_products,
    count(*) filter (where result ->> 'status' = 'CLASSIFICATION_REQUIRED')
        classification_required,
    count(*) filter (where result ->> 'status' = 'NO_AVAILABLE_SIZE') no_available_size,
    count(*) filter (where result ->> 'status' = 'NO_MEASUREMENT_DATA') no_measurement_data,
    count(*) filter (where result ->> 'status' = 'INSUFFICIENT_MEASUREMENTS')
        insufficient_measurements,
    count(*) filter (where result ->> 'status' = 'POLICY_UNAVAILABLE') policy_unavailable,
    count(*) filter (where source_code = 'musinsa' and source_product_key = '6805433'
        and result ->> 'status' = 'READY') musinsa_golden_ready,
    count(*) filter (where source_code = 'uniqlo' and source_product_key = 'E482856'
        and result ->> 'status' = 'READY') uniqlo_golden_ready,
    count(*) filter (where source_code = 'zara' and source_product_key = '561264931'
        and result ->> 'status' = 'READY') zara_golden_ready
from readiness;

-- 5. Policy, history, grants, and RLS final gates.
select
    (select count(*)
     from fitmatch_vnext.garment_types gt
     join fitmatch_vnext.comparison_policies cp
       on cp.policy_code = gt.comparison_policy_code
     where gt.is_active and not cp.is_active) active_garment_inactive_policy,
    (select count(*)
     from fitmatch_vnext.comparisons
     where result_status = 'COMPLETED'
       and (recommended_product_size_id is null
            or authority_snapshot = '{}'::jsonb
            or policy_snapshot = '{}'::jsonb
            or input_snapshot = '{}'::jsonb
            or result_evidence = '{}'::jsonb)) completed_history_invalid,
    has_schema_privilege('anon', 'fitmatch_vnext', 'USAGE') anon_schema_usage,
    has_function_privilege(
        'anon', 'fitmatch_vnext.get_product_runtime(text,text)', 'EXECUTE'
    ) anon_runtime_execute,
    has_function_privilege(
        'authenticated', 'fitmatch_vnext.get_product_runtime(text,text)', 'EXECUTE'
    ) authenticated_runtime_execute,
    (select count(*)
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'fitmatch_vnext'
       and c.relname in ('profiles', 'closet_items', 'closet_item_measurements',
           'comparisons', 'size_availability_observations',
           'classification_remediation_audit', 'mapping_remediation_audit')
       and not c.relrowsecurity) sensitive_rls_disabled;
