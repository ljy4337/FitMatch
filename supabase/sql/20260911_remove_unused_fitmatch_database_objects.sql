-- FitMatch current-app unused database cleanup
-- Audited against Supabase project hnkplvyegonlhumlejst on 2026-09-11.
--
-- Safety properties:
--   * No CASCADE.
--   * Runs in one transaction.
--   * Aborts if the audited inventory counts have drifted.
--   * Aborts if a surviving table/view/function/trigger depends on a removal target.
--   * Keeps Supabase-managed schemas and the current FitMatch vNext runtime.
--
-- This removes legacy/QA/staging objects. It can break old app builds, old batch
-- collectors, old QA SQL, and rollback tooling even though the current app does
-- not use them. Take a database backup before executing.
-- It also removes the legacy releases_activation_gate_trigger from the retained
-- fitmatch_catalog.releases table. The current app never activates releases;
-- this trigger only preserves the superseded release-validation toolchain.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

create temp table cleanup_relations (
    schema_name text not null,
    object_name text not null,
    object_kind text not null check (object_kind in ('table', 'view', 'sequence')),
    primary key (schema_name, object_name)
) on commit drop;

insert into cleanup_relations (schema_name, object_name, object_kind) values
-- fitmatch_catalog legacy tables
('fitmatch_catalog','app_categories','table'),
('fitmatch_catalog','app_category_details','table'),
('fitmatch_catalog','classification_exclusion_profiles','table'),
('fitmatch_catalog','classification_name_profiles','table'),
('fitmatch_catalog','classification_path_profiles','table'),
('fitmatch_catalog','classification_structured_discriminator_rules','table'),
('fitmatch_catalog','data_quality_issues','table'),
('fitmatch_catalog','documents','table'),
('fitmatch_catalog','product_classification_decisions','table'),
('fitmatch_catalog','product_collection_runs','table'),
('fitmatch_catalog','product_measurements','table'),
('fitmatch_catalog','product_observation_measurements','table'),
('fitmatch_catalog','product_observation_submissions','table'),
('fitmatch_catalog','product_observations','table'),
('fitmatch_catalog','product_sizes','table'),
('fitmatch_catalog','product_variants','table'),
('fitmatch_catalog','source_category_mappings','table'),
('fitmatch_catalog','source_product_snapshots','table'),
-- fitmatch_catalog legacy views
('fitmatch_catalog','current_source_products','view'),
('fitmatch_catalog','data_quality_review_queue','view'),
('fitmatch_catalog','product_mapping_exclusions','view'),
('fitmatch_catalog','product_mapping_gaps','view'),
('fitmatch_catalog','source_to_fitmatch_mappings','view'),
-- QA
('fitmatch_qa','classification_cases','table'),
('fitmatch_qa','validation_runs','table'),
-- staging
('fitmatch_staging','classification_candidates','table'),
('fitmatch_staging','identity_components','table'),
('fitmatch_staging','identity_conflict_adjudications','table'),
('fitmatch_staging','identity_matching_edges','table'),
('fitmatch_staging','import_runs','table'),
('fitmatch_staging','runtime_classification_parity_runs','table'),
('fitmatch_staging','runtime_classification_regression_cases','table'),
('fitmatch_staging','sampled_category_results','table'),
('fitmatch_staging','sampled_product_evidence','table'),
('fitmatch_staging','sampling_runs','table'),
('fitmatch_staging','source_category_hierarchy','table'),
('fitmatch_staging','source_category_nodes','table'),
('fitmatch_staging','source_snapshots','table'),
('fitmatch_staging','validation_results','table'),
-- old taxonomy
('fitmatch_taxonomy','category_app_mappings','table'),
('fitmatch_taxonomy','category_hierarchy','table'),
('fitmatch_taxonomy','classification_audit_history','table'),
('fitmatch_taxonomy','classification_decisions','table'),
('fitmatch_taxonomy','comparison_compatibility_rules','table'),
('fitmatch_taxonomy','comparison_detail_compatibility_rules','table'),
('fitmatch_taxonomy','comparison_families','table'),
('fitmatch_taxonomy','decision_evidence','table'),
('fitmatch_taxonomy','decision_length_axes','table'),
('fitmatch_taxonomy','extension_registry','table'),
('fitmatch_taxonomy','garment_measurement_policies','table'),
('fitmatch_taxonomy','legacy_identity_links','table'),
('fitmatch_taxonomy','length_class_definitions','table'),
('fitmatch_taxonomy','measurement_definitions','table'),
('fitmatch_taxonomy','policy_versions','table'),
('fitmatch_taxonomy','promotion_manifests','table'),
('fitmatch_taxonomy','runtime_classification_rules','table'),
('fitmatch_taxonomy','runtime_rule_sets','table'),
('fitmatch_taxonomy','semantic_garment_types','table'),
('fitmatch_taxonomy','source_categories','table'),
('fitmatch_taxonomy','source_measurement_aliases','table'),
('fitmatch_taxonomy','source_snapshots','table'),
-- vNext audit leftovers
('fitmatch_vnext','classification_remediation_audit','table'),
('fitmatch_vnext','manual_cross_comparison_rules','table'),
('fitmatch_vnext','mapping_remediation_audit','table'),
('fitmatch_vnext','profiles','table'),
('fitmatch_vnext','classification_remediation_audit_id_seq','sequence'),
('fitmatch_vnext','mapping_remediation_audit_id_seq','sequence'),
-- private backups
('private','source_category_mappings_pre_full_review_20260802','table'),
('private','source_category_mappings_pre_taxonomy_audit_20260802','table'),
-- public legacy tables (public.profiles is intentionally retained)
('public','app_categories','table'),
('public','app_category_comparison_policies','table'),
('public','app_category_measurement_policies','table'),
('public','app_category_measurement_policy_overrides','table'),
('public','brands','table'),
('public','category_aliases','table'),
('public','category_measurement_items','table'),
('public','client_source_category_mappings','table'),
('public','closet_item_classification_overrides','table'),
('public','closet_items','table'),
('public','common_categories','table'),
('public','comparison_groups','table'),
('public','comparison_history','table'),
('public','comparison_length_classes','table'),
('public','comparison_measurement_results','table'),
('public','comparison_policies','table'),
('public','comparison_policy_length_axes','table'),
('public','comparison_results','table'),
('public','comparison_runs','table'),
('public','garment_length_classes','table'),
('public','garment_length_classification_rules','table'),
('public','garment_types','table'),
('public','locales','table'),
('public','measurement_basis_conversions','table'),
('public','measurement_items','table'),
('public','product_intake_requests','table'),
('public','source_categories','table'),
('public','source_category_mappings','table'),
('public','source_measurement_mappings','table'),
('public','sources','table'),
('public','translation_keys','table'),
('public','translations','table'),
('public','user_settings','table'),
('public','v_confirmed','table'),
-- public legacy views
('public','closet_items_effective','view'),
('public','source_categories_readable','view'),
('public','v_category_mapping_review','view');

create temp table cleanup_function_names (
    schema_name text not null,
    function_name text not null,
    primary key (schema_name, function_name)
) on commit drop;

insert into cleanup_function_names (schema_name, function_name) values
-- fitmatch_catalog: retain sync_product_body_length and its helper
-- runtime_infer_body_length_code. The obsolete release gate trigger is removed.
('fitmatch_catalog','enforce_release_activation_gate'),
('fitmatch_catalog','resolve_product_classification'),
('fitmatch_catalog','runtime_activate_validated_release'),
('fitmatch_catalog','runtime_audience_scope_correction_gate_v1'),
('fitmatch_catalog','runtime_bottom_reclassification_gate_v1'),
('fitmatch_catalog','runtime_camisole_mapping_correction_gate_v1'),
('fitmatch_catalog','runtime_classification_candidate_artifact_report_v1'),
('fitmatch_catalog','runtime_classification_candidate_decision_manifest_v1'),
('fitmatch_catalog','runtime_classification_candidate_mapping_manifest_v1'),
('fitmatch_catalog','runtime_classification_candidate_review_manifest_v1'),
('fitmatch_catalog','runtime_classification_candidate_revision_artifact_report_v1'),
('fitmatch_catalog','runtime_classification_candidate_revision_decision_manifest_v2'),
('fitmatch_catalog','runtime_classification_candidate_revision_gate_report_v1'),
('fitmatch_catalog','runtime_classification_candidate_revision_manifest_v1'),
('fitmatch_catalog','runtime_classification_candidate_revision_mapping_manifest_v2'),
('fitmatch_catalog','runtime_classification_db_final_decision_manifest_v1'),
('fitmatch_catalog','runtime_classification_db_final_gate_v1'),
('fitmatch_catalog','runtime_classification_db_final_manifest_v1'),
('fitmatch_catalog','runtime_classifier_v5_release_gate_v1'),
('fitmatch_catalog','runtime_closet_measurement_overlap'),
('fitmatch_catalog','runtime_evaluate_comparison_profiles'),
('fitmatch_catalog','runtime_evaluate_comparison_profiles_v2'),
('fitmatch_catalog','runtime_evaluate_comparison_profiles_v3'),
('fitmatch_catalog','runtime_evaluate_comparison_profiles_v4'),
('fitmatch_catalog','runtime_evaluate_product_compatibility'),
('fitmatch_catalog','runtime_genders_are_compatible'),
('fitmatch_catalog','runtime_ingest_product_payload'),
('fitmatch_catalog','runtime_max_measurement_overlap'),
('fitmatch_catalog','runtime_measurement_kind'),
('fitmatch_catalog','runtime_normalize_gender'),
('fitmatch_catalog','runtime_normalize_mapping_target_v1'),
('fitmatch_catalog','runtime_normalize_measurement'),
('fitmatch_catalog','runtime_normalize_measurement_v2'),
('fitmatch_catalog','runtime_normalize_product_audience_v1'),
('fitmatch_catalog','runtime_normalized_category_path'),
('fitmatch_catalog','runtime_policy_contract_report_v1'),
('fitmatch_catalog','runtime_prepare_size_comparison'),
('fitmatch_catalog','runtime_product_fingerprint'),
('fitmatch_catalog','runtime_product_name_signature'),
('fitmatch_catalog','runtime_record_observation_issue'),
('fitmatch_catalog','runtime_record_product_classification'),
('fitmatch_catalog','runtime_record_product_classification_v2'),
('fitmatch_catalog','runtime_record_signature_issue'),
('fitmatch_catalog','runtime_release_gate_report'),
('fitmatch_catalog','runtime_release_gate_report_pre120_v2'),
('fitmatch_catalog','runtime_resolve_and_promote_product'),
('fitmatch_catalog','runtime_resolve_observation_issue'),
('fitmatch_catalog','runtime_resolve_product'),
('fitmatch_catalog','runtime_resolve_product_classification_v2'),
('fitmatch_catalog','runtime_resolve_product_classification_v3'),
('fitmatch_catalog','runtime_resolve_product_classification_v4'),
('fitmatch_catalog','runtime_resolve_product_classification_v5'),
('fitmatch_catalog','runtime_resolve_signature_issue'),
('fitmatch_catalog','runtime_resolve_source_mapping'),
('fitmatch_catalog','runtime_review_zero_gate_v1'),
('fitmatch_catalog','runtime_source_category_hint_v5'),
('fitmatch_catalog','runtime_triage_data_quality_issue'),
('fitmatch_catalog','runtime_upsert_measurement'),
('fitmatch_catalog','runtime_upsert_product'),
('fitmatch_catalog','runtime_upsert_size'),
('fitmatch_catalog','runtime_upsert_variant'),
('fitmatch_catalog','runtime_validate_classification_tuple_v1'),
('fitmatch_catalog','sync_closet_body_length'),
('fitmatch_catalog','sync_product_from_snapshot'),
-- QA and old taxonomy
('fitmatch_qa','validate_product_runtime'),
('fitmatch_qa','validate_product_runtime_v2'),
('fitmatch_qa','validate_product_runtime_v3'),
('fitmatch_taxonomy','evaluate_runtime_classification'),
('fitmatch_taxonomy','runtime_is_comparable'),
-- superseded vNext internals
('fitmatch_vnext','comparison_unit_tuple_validation'),
('fitmatch_vnext','ingest_product_observation_v1'),
-- public legacy RPC/functions; retain current vNext RPCs, handle_new_user and set_updated_at
('public','fitmatch_batch_ingest_product'),
('public','fitmatch_batch_products_needing_ingest'),
('public','fitmatch_begin_comparison'),
('public','fitmatch_clear_closet_classification_override'),
('public','fitmatch_complete_comparison'),
('public','fitmatch_delete_closet_item'),
('public','fitmatch_find_reference_candidates'),
('public','fitmatch_get_product_runtime'),
('public','fitmatch_list_closet_items'),
('public','fitmatch_process_product_observation'),
('public','fitmatch_register_closet_item'),
('public','fitmatch_resolve_product'),
('public','fitmatch_set_closet_classification_override'),
('public','fitmatch_set_closet_reference'),
('public','fitmatch_set_updated_at'),
('public','fitmatch_submit_product_observation'),
('public','fitmatch_upsert_closet_item'),
('public','fitmatch_validate_category_hierarchy'),
('public','fitmatch_vnext_authorize_comparison'),
('public','fitmatch_vnext_list_comparison_groups');

create temp table cleanup_triggers (
    table_schema text not null,
    table_name text not null,
    trigger_name text not null,
    primary key (table_schema, table_name, trigger_name)
) on commit drop;

insert into cleanup_triggers (table_schema, table_name, trigger_name) values
('fitmatch_catalog','releases','releases_activation_gate_trigger');

create temp table cleanup_relation_oids on commit drop as
select c.oid, r.schema_name, r.object_name, r.object_kind
from cleanup_relations r
join pg_namespace n on n.nspname = r.schema_name
join pg_class c on c.relnamespace = n.oid and c.relname = r.object_name
where (r.object_kind = 'table' and c.relkind in ('r','p'))
   or (r.object_kind = 'view' and c.relkind in ('v','m'))
   or (r.object_kind = 'sequence' and c.relkind = 'S');

create temp table cleanup_function_oids on commit drop as
select p.oid, f.schema_name, f.function_name,
       pg_get_function_identity_arguments(p.oid) as identity_arguments
from cleanup_function_names f
join pg_namespace n on n.nspname = f.schema_name
join pg_proc p on p.pronamespace = n.oid
              and p.proname = f.function_name
              and p.prokind = 'f';

do $preflight$
declare
    v_missing text;
    v_external text;
begin
    if (select count(*) from cleanup_relations) <> 106 then
        raise exception 'Cleanup relation manifest count changed';
    end if;

    if (select count(*) from cleanup_relation_oids) <> 106 then
        select string_agg(format('%I.%I', r.schema_name, r.object_name), ', ' order by r.schema_name, r.object_name)
          into v_missing
        from cleanup_relations r
        left join cleanup_relation_oids o
          on o.schema_name = r.schema_name and o.object_name = r.object_name
        where o.oid is null;
        raise exception 'Relation inventory drift; missing or wrong kind: %', coalesce(v_missing, 'unknown');
    end if;

    if (select count(*) from cleanup_function_names) <> 91
       or (select count(*) from cleanup_function_oids) <> 91 then
        select string_agg(format('%I.%I', f.schema_name, f.function_name), ', ' order by f.schema_name, f.function_name)
          into v_missing
        from cleanup_function_names f
        left join cleanup_function_oids o
          on o.schema_name = f.schema_name and o.function_name = f.function_name
        where o.oid is null;
        raise exception 'Function inventory drift; missing/extra overload: %', coalesce(v_missing, 'inspect live function inventory');
    end if;

    if (select count(*) from cleanup_triggers) <> 1
       or (select count(*)
           from cleanup_triggers x
           join pg_namespace n on n.nspname = x.table_schema
           join pg_class c on c.relnamespace = n.oid and c.relname = x.table_name
           join pg_trigger t on t.tgrelid = c.oid and t.tgname = x.trigger_name
           where not t.tgisinternal) <> 1 then
        raise exception 'Trigger inventory drift: expected releases_activation_gate_trigger';
    end if;

    -- A surviving table must never reference a table scheduled for removal.
    select string_agg(
               format('%s -> %s', conrelid::regclass, confrelid::regclass),
               ', ' order by conrelid::regclass::text, confrelid::regclass::text
           )
      into v_external
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid in (select oid from cleanup_relation_oids)
      and c.conrelid not in (select oid from cleanup_relation_oids);

    if v_external is not null then
        raise exception 'Surviving FK depends on removal target: %', v_external;
    end if;

    -- A surviving view must never depend on a relation scheduled for removal.
    select string_agg(distinct format('%s -> %s', rw.ev_class::regclass, d.refobjid::regclass), ', ')
      into v_external
    from pg_depend d
    join pg_rewrite rw on rw.oid = d.objid and d.classid = 'pg_rewrite'::regclass
    where d.refobjid in (select oid from cleanup_relation_oids)
      and rw.ev_class not in (select oid from cleanup_relation_oids)
      and rw.ev_class <> d.refobjid;

    if v_external is not null then
        raise exception 'Surviving view depends on removal target: %', v_external;
    end if;

    -- A trigger on a surviving table must never call a function being removed.
    select string_agg(format('%s.%I -> %s', t.tgrelid::regclass, t.tgname, t.tgfoid::regprocedure), ', ')
      into v_external
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and t.tgfoid in (select oid from cleanup_function_oids)
      and t.tgrelid not in (select oid from cleanup_relation_oids)
      and not exists (
          select 1 from cleanup_triggers x
          where x.table_schema = n.nspname
            and x.table_name = c.relname
            and x.trigger_name = t.tgname
      );

    if v_external is not null then
        raise exception 'Surviving trigger depends on removal function: %', v_external;
    end if;

    -- Current app functions use an empty search_path and fully qualified calls.
    -- Abort if any surviving app-schema function source names a removal target.
    select string_agg(distinct format('%I.%I -> %I.%I', fn.nspname, p.proname, r.schema_name, r.object_name), ', ')
      into v_external
    from pg_proc p
    join pg_namespace fn on fn.oid = p.pronamespace
    join cleanup_relations r
      on position(lower(r.schema_name || '.' || r.object_name) in lower(pg_get_functiondef(p.oid))) > 0
    where p.prokind = 'f'
      and fn.nspname in ('public','fitmatch_catalog','fitmatch_vnext')
      and p.oid not in (select oid from cleanup_function_oids);

    if v_external is not null then
        raise exception 'Surviving function references removal relation: %', v_external;
    end if;

    select string_agg(distinct format('%I.%I -> %I.%I', fn.nspname, p.proname, f.schema_name, f.function_name), ', ')
      into v_external
    from pg_proc p
    join pg_namespace fn on fn.oid = p.pronamespace
    join cleanup_function_names f
      on position(lower(f.schema_name || '.' || f.function_name) in lower(pg_get_functiondef(p.oid))) > 0
    where p.prokind = 'f'
      and fn.nspname in ('public','fitmatch_catalog','fitmatch_vnext')
      and p.oid not in (select oid from cleanup_function_oids);

    if v_external is not null then
        raise exception 'Surviving function references removal function: %', v_external;
    end if;
end
$preflight$;

-- Explicitly remove the obsolete trigger from the retained releases table.
do $drop_explicit_candidate_triggers$
declare r record;
begin
    for r in
        select x.table_schema, x.table_name, x.trigger_name
        from cleanup_triggers x
    loop
        execute format(
            'drop trigger %I on %I.%I',
            r.trigger_name, r.table_schema, r.table_name
        );
    end loop;
end
$drop_explicit_candidate_triggers$;

-- Remove triggers belonging to tables that are themselves removal targets.
do $drop_candidate_triggers$
declare r record;
begin
    for r in
        select t.tgrelid::regclass as table_id, t.tgname
        from pg_trigger t
        where not t.tgisinternal
          and t.tgrelid in (
              select oid from cleanup_relation_oids where object_kind = 'table'
          )
    loop
        execute format('drop trigger %I on %s', r.tgname, r.table_id);
    end loop;
end
$drop_candidate_triggers$;

-- Drop candidate views from leaves inward, without CASCADE.
do $drop_candidate_views$
declare
    r record;
    v_progress integer;
begin
    loop
        v_progress := 0;
        for r in
            select * from cleanup_relation_oids
            where object_kind = 'view'
            order by schema_name, object_name
        loop
            begin
                execute format('drop view %I.%I', r.schema_name, r.object_name);
                delete from cleanup_relation_oids where oid = r.oid;
                v_progress := v_progress + 1;
            exception when dependent_objects_still_exist then
                null;
            end;
        end loop;

        exit when not exists (select 1 from cleanup_relation_oids where object_kind = 'view');
        if v_progress = 0 then
            raise exception 'Could not remove all candidate views without CASCADE';
        end if;
    end loop;
end
$drop_candidate_views$;

-- Candidate-to-candidate foreign keys only. External FKs were rejected above.
do $drop_candidate_foreign_keys$
declare r record;
begin
    for r in
        select c.conrelid::regclass as table_id, c.conname
        from pg_constraint c
        where c.contype = 'f'
          and c.conrelid in (select oid from cleanup_relation_oids where object_kind = 'table')
          and c.confrelid in (select oid from cleanup_relation_oids where object_kind = 'table')
    loop
        execute format('alter table %s drop constraint %I', r.table_id, r.conname);
    end loop;
end
$drop_candidate_foreign_keys$;

-- Functions and relations can depend on each other through defaults/types.
-- Repeatedly remove only objects PostgreSQL says are independently droppable.
do $drop_candidates$
declare
    r record;
    v_progress integer;
    v_remaining text;
begin
    loop
        v_progress := 0;

        for r in
            select * from cleanup_function_oids order by schema_name, function_name, oid
        loop
            begin
                execute format(
                    'drop function %I.%I(%s)',
                    r.schema_name, r.function_name, r.identity_arguments
                );
                delete from cleanup_function_oids where oid = r.oid;
                v_progress := v_progress + 1;
            exception when dependent_objects_still_exist then
                null;
            end;
        end loop;

        for r in
            select * from cleanup_relation_oids
            where object_kind = 'table'
            order by schema_name, object_name
        loop
            begin
                execute format('drop table %I.%I', r.schema_name, r.object_name);
                delete from cleanup_relation_oids where oid = r.oid;
                v_progress := v_progress + 1;
            exception when dependent_objects_still_exist then
                null;
            when undefined_table then
                -- An owned sequence/table may already have disappeared together
                -- with its owner in an earlier pass.
                delete from cleanup_relation_oids where oid = r.oid;
                v_progress := v_progress + 1;
            end;
        end loop;

        for r in
            select * from cleanup_relation_oids
            where object_kind = 'sequence'
            order by schema_name, object_name
        loop
            begin
                execute format('drop sequence %I.%I', r.schema_name, r.object_name);
                delete from cleanup_relation_oids where oid = r.oid;
                v_progress := v_progress + 1;
            exception when dependent_objects_still_exist then
                null;
            when undefined_table then
                -- Owned sequences are dropped automatically with their table.
                delete from cleanup_relation_oids where oid = r.oid;
                v_progress := v_progress + 1;
            end;
        end loop;

        exit when not exists (select 1 from cleanup_function_oids)
              and not exists (select 1 from cleanup_relation_oids);

        if v_progress = 0 then
            select string_agg(object_id, ', ' order by object_id)
              into v_remaining
            from (
                select format('function %I.%I(%s)', schema_name, function_name, identity_arguments) object_id
                from cleanup_function_oids
                union all
                select format('%s %I.%I', object_kind, schema_name, object_name)
                from cleanup_relation_oids
            ) x;
            raise exception 'Cleanup stopped; unresolved dependencies remain: %', v_remaining;
        end if;
    end loop;
end
$drop_candidates$;

-- These schemas should now be empty. No CASCADE is used.
drop schema fitmatch_qa;
drop schema fitmatch_staging;
drop schema fitmatch_taxonomy;
drop schema private;

-- Final invariants for the current app.
do $postflight$
declare
    v_root_count integer;
begin
    select count(*) into v_root_count
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any(array[
          'fitmatch_vnext_upsert_closet_item',
          'fitmatch_vnext_update_closet_item',
          'fitmatch_vnext_list_closet_items',
          'fitmatch_vnext_delete_closet_item',
          'fitmatch_vnext_set_closet_reference',
          'fitmatch_vnext_unset_closet_reference',
          'fitmatch_vnext_set_closet_classification_override',
          'fitmatch_vnext_clear_closet_classification_override',
          'fitmatch_vnext_get_product_runtime',
          'fitmatch_vnext_get_classification_recovery_options',
          'fitmatch_vnext_set_user_product_classification',
          'fitmatch_vnext_clear_user_product_classification',
          'fitmatch_vnext_find_reference_candidates',
          'fitmatch_vnext_eligible_candidate_sizes',
          'fitmatch_vnext_begin_comparison',
          'fitmatch_vnext_complete_comparison',
          'fitmatch_vnext_comparison_history',
          'fitmatch_vnext_hide_comparison_history',
          'fitmatch_vnext_ingest_product_observation'
      ]::text[]);

    if v_root_count <> 19 then
        raise exception 'Postflight failed: expected 19 current app RPCs, found %', v_root_count;
    end if;

    if to_regclass('public.profiles') is null
       or to_regprocedure('public.handle_new_user()') is null
       or to_regprocedure('public.set_updated_at()') is null then
        raise exception 'Postflight failed: Auth profile objects are missing';
    end if;

    if to_regclass('fitmatch_catalog.current_product_classifications') is null
       or to_regclass('fitmatch_catalog.source_category_comparison_groups') is null
       or to_regclass('fitmatch_vnext.products') is null
       or to_regclass('fitmatch_vnext.closet_items') is null
       or to_regclass('fitmatch_vnext.comparisons') is null then
        raise exception 'Postflight failed: current runtime relations are missing';
    end if;

    if to_regprocedure('fitmatch_catalog.sync_product_body_length()') is null
       or to_regprocedure('fitmatch_catalog.runtime_infer_body_length_code(text,text,text)') is null then
        raise exception 'Postflight failed: classification-history trigger helpers are missing';
    end if;
end
$postflight$;

commit;

-- Read-back summary. Expected removal counts:
--   96 tables, 8 views, 2 sequences, 91 functions.
select n.nspname as schema_name,
       count(*) filter (where c.relkind in ('r','p')) as tables,
       count(*) filter (where c.relkind in ('v','m')) as views,
       count(*) filter (where c.relkind = 'S') as sequences
from pg_namespace n
left join pg_class c on c.relnamespace = n.oid
where n.nspname in ('public','fitmatch_catalog','fitmatch_vnext')
group by n.nspname
order by n.nspname;
