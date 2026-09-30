-- LOCAL/STAGING ONLY. Run after migrations 113, 114, and 115.
-- Every synthetic row is contained in this transaction and rolled back.
begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

do $$
declare
  v_runtime_validation jsonb;
  v_gate_report jsonb;
  v_active_release_id uuid;
begin
  -- A. Additive columns and constraints.
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'fitmatch_catalog'
      and table_name = 'product_classification_decisions'
      and column_name = 'garment_type_code'
      and data_type = 'text'
      and is_nullable = 'YES'
  )
    or not exists (
      select 1
      from information_schema.columns
      where table_schema = 'fitmatch_catalog'
        and table_name = 'product_classification_decisions'
        and column_name = 'authority_status'
        and data_type = 'text'
        and is_nullable = 'NO'
        and column_default = '''legacy''::text'
    )
    or not exists (
      select 1
      from information_schema.columns
      where table_schema = 'fitmatch_catalog'
        and table_name = 'product_classification_history'
        and column_name = 'garment_type_code'
        and data_type = 'text'
        and is_nullable = 'YES'
    ) then
    raise exception 'phase 1B-1 additive columns are missing or incompatible';
  end if;

  if not exists (
      select 1
      from pg_constraint
      where conrelid =
          'fitmatch_catalog.product_classification_decisions'::regclass
        and conname =
          'product_classification_decisions_authority_status_check'
        and convalidated
    )
    or not exists (
      select 1
      from pg_constraint
      where conrelid =
          'fitmatch_catalog.product_classification_decisions'::regclass
        and conname =
          'product_classification_decisions_verified_complete_check'
        and convalidated
    )
    or not exists (
      select 1
      from pg_constraint
      where conrelid =
          'fitmatch_catalog.product_classification_decisions'::regclass
        and conname =
          'product_classification_decisions_garment_type_code_fkey'
        and convalidated
    ) then
    raise exception 'phase 1B-1 decision constraints are missing';
  end if;

  -- B-D. The disposable fixture has one legacy row in each runtime table.
  -- Migration 115 must expose defaults without rewriting any of those rows.
  if (select count(*)
      from fitmatch_catalog.product_classification_decisions) <> 1
    or (select count(*)
        from fitmatch_catalog.product_classification_decisions
        where authority_status = 'legacy') <> 1
    or exists (
      select 1
      from fitmatch_catalog.product_classification_decisions
      where garment_type_code is not null
    ) then
    raise exception 'synthetic legacy decision was not preserved';
  end if;

  if (select count(*)
      from fitmatch_catalog.product_classification_history) <> 1
    or exists (
      select 1
      from fitmatch_catalog.product_classification_history
      where garment_type_code is not null
    )
    or (select count(*)
        from fitmatch_catalog.product_classification_history
        where is_current) <> 1
    or exists (
      select 1
      from fitmatch_catalog.product_classification_history
      where is_current
      group by product_id
      having count(*) <> 1
    ) then
    raise exception 'existing classification history changed unexpectedly';
  end if;

  if (select count(*) from fitmatch_catalog.products) <> 1
    or (select count(*)
        from fitmatch_catalog.product_measurements) <> 0 then
    raise exception 'product or measurement count changed unexpectedly';
  end if;

  -- I. Old v2/v3 and public RPC signatures remain present. The runner records
  -- pre/post definition hashes outside this rolled-back fixture transaction.
  if not exists (
      select 1
      from pg_proc function_row
      join pg_namespace function_schema
        on function_schema.oid = function_row.pronamespace
      where function_schema.nspname = 'fitmatch_catalog'
        and function_row.proname =
          'runtime_resolve_product_classification_v2'
        and pg_get_function_identity_arguments(function_row.oid) =
          'text, text, text, text, jsonb'
    )
    or not exists (
      select 1
      from pg_proc function_row
      join pg_namespace function_schema
        on function_schema.oid = function_row.pronamespace
      where function_schema.nspname = 'fitmatch_catalog'
        and function_row.proname =
          'runtime_resolve_product_classification_v3'
    )
    or not exists (
      select 1
      from pg_proc function_row
      join pg_namespace function_schema
        on function_schema.oid = function_row.pronamespace
      where function_schema.nspname = 'fitmatch_catalog'
        and function_row.proname =
          'runtime_record_product_classification'
    )
    or not exists (
      select 1
      from pg_proc function_row
      join pg_namespace function_schema
        on function_schema.oid = function_row.pronamespace
      where function_schema.nspname = 'fitmatch_catalog'
        and function_row.proname =
          'runtime_evaluate_comparison_profiles_v3'
    ) then
    raise exception 'old internal v2/v3 function contract changed';
  end if;

  if not exists (
      select 1
      from pg_proc function_row
      join pg_namespace function_schema
        on function_schema.oid = function_row.pronamespace
      where function_schema.nspname = 'public'
        and function_row.proname = 'fitmatch_resolve_product'
    )
    or not exists (
      select 1
      from pg_proc function_row
      join pg_namespace function_schema
        on function_schema.oid = function_row.pronamespace
      where function_schema.nspname = 'public'
        and function_row.proname = 'fitmatch_get_product_runtime'
    )
    or not exists (
      select 1
      from pg_proc function_row
      join pg_namespace function_schema
        on function_schema.oid = function_row.pronamespace
      where function_schema.nspname = 'public'
        and function_row.proname = 'fitmatch_find_reference_candidates'
    )
    or not exists (
      select 1
      from pg_proc function_row
      join pg_namespace function_schema
        on function_schema.oid = function_row.pronamespace
      where function_schema.nspname = 'public'
        and function_row.proname = 'fitmatch_begin_comparison'
    ) then
    raise exception 'old public RPC definition changed';
  end if;

  if exists (
      select 1
      from (values
        ('fitmatch_catalog.runtime_resolve_product_classification_v2(text,text,text,text,jsonb)'),
        ('fitmatch_catalog.runtime_resolve_product_classification_v3(text,text,text,text,jsonb)'),
        ('fitmatch_catalog.runtime_record_product_classification(uuid,jsonb)'),
        ('fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(text,text,text,text,text,text,text,text,text,text,text,text,boolean)')
      ) function_contract(signature)
      cross join (values ('anon'), ('authenticated')) app_role(role_name)
      where has_function_privilege(
        app_role.role_name,
        function_contract.signature,
        'EXECUTE'
      )
    )
    or exists (
      select 1
      from (values
        ('fitmatch_catalog.runtime_resolve_product_classification_v2(text,text,text,text,jsonb)'),
        ('fitmatch_catalog.runtime_resolve_product_classification_v3(text,text,text,text,jsonb)'),
        ('fitmatch_catalog.runtime_record_product_classification(uuid,jsonb)'),
        ('fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(text,text,text,text,text,text,text,text,text,text,text,text,boolean)')
      ) function_contract(signature)
      where not has_function_privilege(
        'service_role',
        function_contract.signature,
        'EXECUTE'
      )
    )
    or exists (
      select 1
      from (values
        ('public.fitmatch_resolve_product(jsonb)'),
        ('public.fitmatch_get_product_runtime(jsonb)'),
        ('public.fitmatch_find_reference_candidates(uuid)'),
        ('public.fitmatch_begin_comparison(uuid,uuid,boolean,uuid)')
      ) function_contract(signature)
      where has_function_privilege(
          'anon',
          function_contract.signature,
          'EXECUTE'
        )
        or not has_function_privilege(
          'authenticated',
          function_contract.signature,
          'EXECUTE'
        )
        or not has_function_privilege(
          'service_role',
          function_contract.signature,
          'EXECUTE'
        )
    ) then
    raise exception 'old internal/public function grant baseline changed';
  end if;

  v_runtime_validation := fitmatch_qa.validate_product_runtime_v3();
  if not coalesce((v_runtime_validation->>'passed')::boolean, false) then
    raise exception 'existing product runtime v3 validation failed: %',
      v_runtime_validation;
  end if;

  -- J. 114 object, release gate, view security, and grants.
  if to_regclass('fitmatch_catalog.releases_one_active_idx') is null
    or to_regclass('fitmatch_catalog.data_quality_review_queue') is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_release_gate_report(uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_activate_validated_release(uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_triage_data_quality_issue(uuid,text,smallint,uuid,text,jsonb)'
    ) is null
    or not exists (
      select 1
      from pg_class view_row
      join pg_namespace view_schema on view_schema.oid = view_row.relnamespace
      where view_schema.nspname = 'fitmatch_catalog'
        and view_row.relname = 'data_quality_review_queue'
        and view_row.relkind = 'v'
        and 'security_invoker=true' = any(coalesce(
          view_row.reloptions,
          array[]::text[]
        ))
    ) then
    raise exception 'migration 114 objects are missing or insecure';
  end if;

  if exists (
      select 1
      from (values
        ('fitmatch_catalog.runtime_release_gate_report(uuid)'),
        ('fitmatch_catalog.runtime_activate_validated_release(uuid)'),
        ('fitmatch_catalog.runtime_triage_data_quality_issue(uuid,text,smallint,uuid,text,jsonb)')
      ) function_contract(signature)
      cross join (values ('anon'), ('authenticated')) app_role(role_name)
      where has_function_privilege(
        app_role.role_name,
        function_contract.signature,
        'EXECUTE'
      )
    )
    or exists (
      select 1
      from (values
        ('fitmatch_catalog.runtime_release_gate_report(uuid)'),
        ('fitmatch_catalog.runtime_activate_validated_release(uuid)'),
        ('fitmatch_catalog.runtime_triage_data_quality_issue(uuid,text,smallint,uuid,text,jsonb)')
      ) function_contract(signature)
      where not has_function_privilege(
        'service_role',
        function_contract.signature,
        'EXECUTE'
      )
    )
    or exists (
      select 1
      from (values ('anon'), ('authenticated')) app_role(role_name)
      where has_table_privilege(
        app_role.role_name,
        'fitmatch_catalog.data_quality_review_queue',
        'SELECT'
      )
    )
    or not has_table_privilege(
      'service_role',
      'fitmatch_catalog.data_quality_review_queue',
      'SELECT'
    ) then
    raise exception 'migration 114 trusted grants are invalid';
  end if;

  select release.id
  into strict v_active_release_id
  from fitmatch_catalog.releases release
  where release.status = 'active'
  order by release.activated_at desc nulls last, release.created_at desc
  limit 1;

  update fitmatch_catalog.releases
  set validation_report = jsonb_build_object(
    'runtime_policy_contract', jsonb_build_object(
      'classifier_policy_version', 'classifier-v1',
      'comparison_policy_version', 'comparison-policy-v1',
      'compatibility_rule_version', 'compatibility-rule-v1',
      'measurement_policy_version', 'measure-v1'
    )
  )
  where id = v_active_release_id;
  v_gate_report :=
    fitmatch_catalog.runtime_release_gate_report(v_active_release_id);
  if coalesce((v_gate_report->>'eligible')::boolean, true) then
    raise exception 'current mapping-only release must remain gate-ineligible';
  end if;

  -- New internal functions are service-role only and no public preview RPC was
  -- added. They remain shadow contracts until explicit activation.
  if exists (
      select 1
      from (values
        ('fitmatch_catalog.runtime_validate_classification_tuple_v1(text,text,text,text,text,text)'),
        ('fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'),
        ('fitmatch_catalog.runtime_record_product_classification_v2(uuid,jsonb)'),
        ('fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(text,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,uuid)')
      ) function_contract(signature)
      cross join (values ('anon'), ('authenticated')) app_role(role_name)
      where has_function_privilege(
        app_role.role_name,
        function_contract.signature,
        'EXECUTE'
      )
    )
    or exists (
      select 1
      from (values
        ('fitmatch_catalog.runtime_validate_classification_tuple_v1(text,text,text,text,text,text)'),
        ('fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'),
        ('fitmatch_catalog.runtime_record_product_classification_v2(uuid,jsonb)'),
        ('fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(text,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,uuid)')
      ) function_contract(signature)
      where not has_function_privilege(
        'service_role',
        function_contract.signature,
        'EXECUTE'
      )
    )
    or to_regprocedure(
      'public.fitmatch_preview_product_classification_v4(text,text,text,text,jsonb,uuid)'
    ) is not null then
    raise exception 'phase 1B-1 shadow function grant boundary is invalid';
  end if;
end $$;

-- 113/114 runtime checks: signature aggregation/triage, activation gate
-- rejection and acceptance, trigger recursion boundary, and review view.
do $$
declare
  v_active_release_id uuid;
  v_candidate_release_id uuid;
  v_issue_id uuid;
  v_triage jsonb;
begin
  select id into strict v_active_release_id
  from fitmatch_catalog.releases
  where status = 'active';

  v_issue_id := fitmatch_catalog.runtime_record_signature_issue(
    'fixture', 'UNKNOWN_SOURCE_CATEGORY', 'fixture > unmapped', 'medium',
    '{"fixture":true}'::jsonb
  );
  v_triage := fitmatch_catalog.runtime_triage_data_quality_issue(
    v_issue_id, 'acknowledged', 60::smallint, null::uuid,
    'local fixture', '{}'::jsonb
  );
  if v_triage->>'status' <> 'acknowledged'
    or not exists (
      select 1
      from fitmatch_catalog.data_quality_review_queue
      where id = v_issue_id and effective_priority = 60
    ) then
    raise exception '113/114 issue triage runtime failed: %', v_triage;
  end if;

  -- Invalid direct activation reaches the AFTER trigger and is rejected. The
  -- exception block rolls back the temporary retirement of the active row.
  begin
    update fitmatch_catalog.releases
    set status = 'retired'
    where id = v_active_release_id;

    insert into fitmatch_catalog.releases (
      release_key, taxonomy_version, policy_version, status,
      bundle_checksum, app_taxonomy_checksum, expected_mapping_count,
      expected_qa_count
    ) values (
      'synthetic-trigger-denied', 'taxonomy-v1', 'taxonomy-policy-v1',
      'active', 'fixture', 'fixture', 0, 0
    );
    raise exception 'release activation trigger accepted an invalid release';
  exception
    when sqlstate '23514' then
      null;
  end;

  if not exists (
    select 1 from fitmatch_catalog.releases
    where id = v_active_release_id and status = 'active'
  ) then
    raise exception 'failed trigger fixture did not roll back';
  end if;

  -- A fully evidenced synthetic release can pass the same trigger. A custom
  -- exception rolls this successful activation fixture back immediately.
  begin
    insert into fitmatch_catalog.releases (
      release_key, taxonomy_version, policy_version, status,
      bundle_checksum, app_taxonomy_checksum, expected_mapping_count,
      expected_qa_count, validation_contract_version, validation_report,
      validated_at
    ) values (
      'synthetic-trigger-allowed', 'taxonomy-v1', 'taxonomy-policy-v1',
      'validated', 'fixture-bundle', 'fixture-app', 1, 1,
      'fitmatch-release-gate-v1',
      '{"qa_full_validation_included":true,"core_regression_passed":true,"current_behavior_parity_passed":true,"production_identity_verified":true,"label_sample_sufficiency_passed":true,"unsafe_auto_accept_count":0,"classification_conflict_leak_count":0,"measurement_alias_conflict_count":0}'::jsonb,
      now()
    ) returning id into v_candidate_release_id;

    insert into fitmatch_catalog.source_category_mappings (
      release_id, source_identity, source, snapshot_id,
      external_category_id, target, normalized_path, decision_status,
      mapping_status, runtime_lookup_eligible, eligibility,
      semantic_category_code, semantic_garment_type, comparison_family,
      raw_record
    )
    select v_candidate_release_id, 'fixture:gate', source, snapshot_id,
      'fixture-gate', target, 'fixture/gate', decision_status,
      mapping_status, runtime_lookup_eligible, eligibility,
      semantic_category_code, semantic_garment_type, comparison_family,
      raw_record
    from fitmatch_catalog.source_category_mappings
    where release_id = v_active_release_id
    order by source_identity
    limit 1;

    update fitmatch_catalog.releases
    set status = 'retired'
    where id = v_active_release_id;
    update fitmatch_catalog.releases
    set status = 'active', activated_at = now()
    where id = v_candidate_release_id;

    if not exists (
      select 1
      from fitmatch_catalog.releases
      where id = v_candidate_release_id
        and status = 'active'
        and release_gate_result @> '{"eligible":true}'::jsonb
        and release_gate_checked_at is not null
    ) then
      raise exception 'release activation trigger did not persist gate proof';
    end if;

    raise exception using
      errcode = 'P1V01', message = 'rollback_successful_gate_fixture';
  exception
    when sqlstate 'P1V01' then
      null;
  end;

  if not exists (
    select 1 from fitmatch_catalog.releases
    where id = v_active_release_id and status = 'active'
  ) then
    raise exception 'successful trigger fixture did not roll back';
  end if;
end $$;

-- The new garment FK rejects invalid children and RESTRICTs parent mutation.
do $$
declare
  v_active_release_id uuid;
begin
  select id into strict v_active_release_id
  from fitmatch_catalog.releases
  where status = 'active';

  begin
    insert into fitmatch_catalog.product_classification_decisions (
      source, external_product_id, product_name, source_category_path,
      input_fingerprint, garment_type_code, requires_user_confirmation,
      release_id, decision_version, authority_status
    ) values (
      'fixture_fk', 'missing-child', 'Fixture', 'fixture/fk',
      md5('fixture-fk-missing'), 'does_not_exist', true,
      v_active_release_id, 'fixture-v1', 'legacy'
    );
    raise exception 'garment child FK accepted an unknown code';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into fitmatch_catalog.product_classification_decisions (
      source, external_product_id, product_name, source_category_path,
      input_fingerprint, garment_type_code, requires_user_confirmation,
      release_id, decision_version, authority_status
    ) values (
      'fixture_fk', 'restrict-parent', 'Fixture', 'fixture/fk',
      md5('fixture-fk-restrict'), 'tshirt', true,
      v_active_release_id, 'fixture-v1', 'legacy'
    );
    delete from public.garment_types where code = 'tshirt';
    raise exception 'garment parent delete bypassed RESTRICT';
  exception
    when foreign_key_violation then
      null;
  end;
end $$;

-- E. Canonical tuple validator fixtures, including K-bucket separation.
do $$
declare
  v_result jsonb;
begin
  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'tops', 'short_sleeve', 'tshirt', 'tshirt', 'short_sleeve', null
  );
  if not coalesce((v_result->>'valid')::boolean, false) then
    raise exception 'valid tshirt tuple rejected: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'tops', 'base_layer_top', 'base_layer_top', 'base_layer_top',
    'short_sleeve', null
  );
  if not coalesce((v_result->>'valid')::boolean, false) then
    raise exception 'valid base-layer tuple rejected: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'tops', 'jeans', 'tshirt', 'tshirt', 'short_sleeve', null
  );
  if coalesce((v_result->>'valid')::boolean, true)
    or not (v_result->'blockers' @> '["category_detail_mismatch"]'::jsonb) then
    raise exception 'category/detail mismatch was not blocked: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'bottoms', 'short_pants', 'tshirt', 'tshirt', 'short_sleeve', null
  );
  if coalesce((v_result->>'valid')::boolean, true)
    or not (v_result->'blockers'
      @> '["category_garment_type_mismatch"]'::jsonb) then
    raise exception 'garment/category mismatch was not blocked: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'tops', 'short_sleeve', 'tshirt', 'base_layer_top',
    'short_sleeve', null
  );
  if coalesce((v_result->>'valid')::boolean, true)
    or not (v_result->'blockers' @> '["garment_family_mismatch"]'::jsonb) then
    raise exception 'garment/family mismatch was not blocked: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'tops', 'short_sleeve', 'tshirt', 'tshirt', null, null
  );
  if coalesce((v_result->>'valid')::boolean, true)
    or not (v_result->'blockers'
      @> '["required_sleeve_axis_missing"]'::jsonb) then
    raise exception 'missing sleeve axis was not blocked: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'tops', 'short_sleeve', 'tshirt', 'tshirt', 'unknown', null
  );
  if coalesce((v_result->>'valid')::boolean, true)
    or not (v_result->'blockers'
      @> '["required_sleeve_axis_unknown"]'::jsonb) then
    raise exception 'unknown sleeve axis was not distinguished: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'tops', 'short_sleeve', 'tshirt', 'tshirt', 'not_applicable', null
  );
  if coalesce((v_result->>'valid')::boolean, true)
    or not (v_result->'blockers'
      @> '["required_sleeve_axis_not_applicable"]'::jsonb) then
    raise exception 'not-applicable sleeve axis was not distinguished: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'skirts', 'skirt', 'skirt', 'skirt', 'not_applicable', 'short_body'
  );
  if not coalesce((v_result->>'valid')::boolean, false) then
    raise exception 'valid skirt body-axis tuple rejected: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'skirts', 'skirt', 'skirt', 'skirt', 'not_applicable', null
  );
  if coalesce((v_result->>'valid')::boolean, true)
    or not (v_result->'blockers'
      @> '["required_body_axis_missing"]'::jsonb) then
    raise exception 'missing skirt body axis was not blocked: %', v_result;
  end if;

  -- K-style: structural tuple stays valid; authority disagreement is not an
  -- input to this validator and is tested separately in resolver v4 below.
  v_result := fitmatch_catalog.runtime_validate_classification_tuple_v1(
    'tops', 'polo_shirt', 'tshirt', 'tshirt', 'short_sleeve', null
  );
  if not coalesce((v_result->>'valid')::boolean, false) then
    raise exception 'K-style structurally valid tuple was conflated: %', v_result;
  end if;
end $$;

-- F-G. Resolver and recorder fixtures. All writes roll back below.
do $$
declare
  v_decision_count integer := (
    select count(*)
    from fitmatch_catalog.product_classification_decisions
  );
  v_history_count integer := (
    select count(*)
    from fitmatch_catalog.product_classification_history
  );
  v_product_count integer := (
    select count(*)
    from fitmatch_catalog.products
  );
  v_measurement_count integer := (
    select count(*)
    from fitmatch_catalog.product_measurements
  );
  v_active_release_id uuid;
  v_mismatch_release_id uuid;
  v_missing_release_id uuid;
  v_snapshot_id uuid;
  v_product_id uuid;
  v_first_history_id uuid;
  v_second_history_id uuid;
  v_result jsonb;
begin
  select release.id
  into strict v_active_release_id
  from fitmatch_catalog.releases release
  where release.status = 'active'
  order by release.activated_at desc nulls last, release.created_at desc
  limit 1;

  select mapping.snapshot_id
  into strict v_snapshot_id
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id = v_active_release_id
  order by mapping.source_identity
  limit 1;

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
  ) values
    (
      'verification_phase1b1',
      'verified-wins',
      '검증 반팔 티셔츠',
      'verification > verified conflict',
      fitmatch_catalog.runtime_product_fingerprint(
        '검증 반팔 티셔츠',
        'verification > verified conflict'
      ),
      'tops', 'short_sleeve', 'tshirt', 'tshirt', 'short_sleeve',
      false, v_active_release_id, 'verification-v1', '{}'::jsonb,
      'verified'
    ),
    (
      'verification_phase1b1',
      'revoked-ignored',
      '검증 반팔 티셔츠',
      'verification > revoked',
      fitmatch_catalog.runtime_product_fingerprint(
        '검증 반팔 티셔츠',
        'verification > revoked'
      ),
      'tops', 'short_sleeve', 'tshirt', 'tshirt', 'short_sleeve',
      false, v_active_release_id, 'verification-v1', '{}'::jsonb,
      'revoked'
    ),
    (
      'verification_phase1b1',
      'legacy-candidate',
      '검증 반팔 티셔츠',
      'verification > legacy',
      fitmatch_catalog.runtime_product_fingerprint(
        '검증 반팔 티셔츠',
        'verification > legacy'
      ),
      'tops', 'short_sleeve', 'tshirt', 'tshirt', 'short_sleeve',
      false, v_active_release_id, 'verification-v1', '{}'::jsonb,
      'legacy'
    ),
    (
      'verification_phase1b1',
      'both-untrusted',
      '검증 반팔 티셔츠',
      'verification > both untrusted',
      fitmatch_catalog.runtime_product_fingerprint(
        '검증 반팔 티셔츠',
        'verification > both untrusted'
      ),
      'tops', 'short_sleeve', 'tshirt', 'tshirt', 'short_sleeve',
      false, v_active_release_id, 'verification-v1', '{}'::jsonb,
      'legacy'
    ),
    (
      'verification_phase1b1',
      'mapping-conflict-legacy',
      '검증 반팔 티셔츠',
      'verification > mapping conflict legacy',
      fitmatch_catalog.runtime_product_fingerprint(
        '검증 반팔 티셔츠',
        'verification > mapping conflict legacy'
      ),
      'tops', 'base_layer_top', 'base_layer_top', 'base_layer_top',
      'short_sleeve', false, v_active_release_id, 'verification-v1',
      '{}'::jsonb, 'legacy'
    ),
    (
      'verification_phase1b1',
      'profile-conflict-legacy',
      '검증 반팔 티셔츠',
      'verification > profile conflict legacy',
      fitmatch_catalog.runtime_product_fingerprint(
        '검증 반팔 티셔츠',
        'verification > profile conflict legacy'
      ),
      'tops', 'base_layer_top', 'base_layer_top', 'base_layer_top',
      'short_sleeve', false, v_active_release_id, 'verification-v1',
      '{}'::jsonb, 'legacy'
    );

  insert into fitmatch_catalog.source_category_mappings (
    release_id,
    source_identity,
    source,
    snapshot_id,
    external_category_id,
    target,
    normalized_path,
    decision_status,
    mapping_status,
    runtime_lookup_eligible,
    eligibility,
    semantic_category_code,
    semantic_garment_type,
    comparison_family,
    raw_record
  )
  select
    v_active_release_id,
    'verification_phase1b1|' || fixture.external_category_id,
    'verification_phase1b1',
    v_snapshot_id,
    fixture.external_category_id,
    'UNKNOWN',
    fixture.path,
    'confirmed',
    'direct',
    true,
    true,
    fixture.category_code,
    fixture.garment_type_code,
    fixture.family_code,
    jsonb_build_object(
      'policyVersion', 'verification-v1',
      'appMapping', jsonb_build_object(
        'categoryCode', fixture.category_code,
        'detailCode', fixture.detail_code,
        'mappingStatus', 'direct'
      ),
      'lengthAxes', jsonb_build_object(
        'sleeve', fixture.length_code,
        'pants', 'not_applicable',
        'leggings', 'not_applicable',
        'body', 'not_applicable',
        'skirt', 'not_applicable'
      ),
      'authorityContract', jsonb_build_object(
        'authorityStatus', fixture.authority_status,
        'resolutionScope', fixture.resolution_scope,
        'productRequired', fixture.resolution_scope = 'product_required'
      )
    )
  from (values
    (
      '900001', 'verification > verified conflict',
      'tops', 'base_layer_top', 'base_layer_top', 'base_layer_top',
      'short_sleeve', 'verified', 'category_direct'
    ),
    (
      '900002', 'verification > clear direct',
      'tops', 'short_sleeve', 'tshirt', 'tshirt',
      'short_sleeve', 'verified', 'category_direct'
    ),
    (
      '900003', 'verification > product required',
      'tops', 'short_sleeve', 'tshirt', 'tshirt',
      'short_sleeve', 'verified', 'product_required'
    ),
    (
      '900004', 'verification > invalid mapping',
      'bottoms', 'short_sleeve', 'tshirt', 'tshirt',
      'short_sleeve', 'verified', 'category_direct'
    ),
    (
      '900005', 'verification > both untrusted',
      'tops', 'base_layer_top', 'base_layer_top', 'base_layer_top',
      'short_sleeve', 'legacy', 'category_direct'
    ),
    (
      '900006', 'verification > mapping conflict legacy',
      'tops', 'short_sleeve', 'tshirt', 'tshirt',
      'short_sleeve', 'verified', 'category_direct'
    )
  ) as fixture(
    external_category_id,
    path,
    category_code,
    detail_code,
    garment_type_code,
    family_code,
    length_code,
    authority_status,
    resolution_scope
  );

  insert into fitmatch_catalog.classification_name_profiles (
    policy_version,
    source,
    normalized_path,
    name_signature,
    category_code,
    detail_code,
    comparison_family_code,
    length_code,
    sample_count,
    review_count,
    distinct_decision_count,
    auto_eligible,
    evidence
  ) values
    (
      'classifier-v1',
      'verification_phase1b1',
      fitmatch_catalog.runtime_normalized_category_path(
        'verification > profile'
      ),
      fitmatch_catalog.runtime_product_name_signature('검증 반팔 티셔츠'),
      'tops', 'short_sleeve', 'tshirt', 'short_sleeve',
      2, 0, 1, true,
      '{"authority_status":"verified","garment_type_code":"tshirt"}'::jsonb
    ),
    (
      'classifier-v1',
      'verification_phase1b1',
      fitmatch_catalog.runtime_normalized_category_path(
        'verification > profile conflict legacy'
      ),
      fitmatch_catalog.runtime_product_name_signature('검증 반팔 티셔츠'),
      'tops', 'short_sleeve', 'tshirt', 'short_sleeve',
      2, 0, 1, true,
      '{"authority_status":"verified","garment_type_code":"tshirt"}'::jsonb
    );

  insert into fitmatch_catalog.classification_exclusion_profiles (
    policy_version,
    source,
    normalized_path,
    sample_count,
    auto_eligible,
    reason_code,
    evidence
  ) values (
    'classifier-v1',
    'verification_phase1b1',
    fitmatch_catalog.runtime_normalized_category_path(
      'verification > excluded'
    ),
    2, true, 'verified_fixture_exclusion',
    '{"authority_status":"verified"}'::jsonb
  );

  insert into fitmatch_catalog.releases (
    release_key, taxonomy_version, policy_version, status,
    bundle_checksum, app_taxonomy_checksum, expected_mapping_count,
    expected_qa_count, validation_report
  ) values
    (
      'synthetic-classifier-mismatch', 'taxonomy-v1',
      'taxonomy-policy-v1', 'loading', 'fixture', 'fixture', 0, 0,
      '{"runtime_policy_contract":{"classifier_policy_version":"classifier-v2","comparison_policy_version":"comparison-policy-v1","compatibility_rule_version":"compatibility-rule-v1","measurement_policy_version":"measure-v1"}}'::jsonb
    ),
    (
      'synthetic-policy-contract-missing', 'taxonomy-v1',
      'taxonomy-policy-v1', 'loading', 'fixture', 'fixture', 0, 0,
      '{}'::jsonb
    );

  select id into strict v_mismatch_release_id
  from fitmatch_catalog.releases
  where release_key = 'synthetic-classifier-mismatch';
  select id into strict v_missing_release_id
  from fitmatch_catalog.releases
  where release_key = 'synthetic-policy-contract-missing';

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'verified-wins', '검증 반팔 티셔츠',
    'verification > verified conflict',
    '{"source_category_codes":["900001"]}'::jsonb,
    v_active_release_id
  );
  if v_result->>'classification_status' <> 'confirmed'
    or v_result->>'authority_status' <> 'verified'
    or v_result->>'classification_method' <> 'canonical_product_decision'
    or v_result->>'garment_type_code' <> 'tshirt'
    or jsonb_array_length(v_result->'authority_conflicts') <> 1 then
    raise exception 'verified decision did not win with conflict surfaced: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'revoked-ignored', '검증 반팔 티셔츠',
    'verification > revoked', '{}'::jsonb, v_active_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or not coalesce(
      v_result->'evidence'->'unresolved_reasons'
        @> '["exact_product_decision_revoked"]'::jsonb,
      false
    ) then
    raise exception 'revoked decision was not ignored: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'clear-direct', '검증 반팔 티셔츠',
    'verification > clear direct',
    '{"source_category_codes":["900002"]}'::jsonb,
    v_active_release_id
  );
  if v_result->>'classification_status' <> 'confirmed'
    or v_result->>'classification_method' <> 'category_mapping'
    or v_result->>'garment_type_code' <> 'tshirt' then
    raise exception 'clear direct mapping was not selected: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'product-required', '검증 반팔 티셔츠',
    'verification > product required',
    '{"source_category_codes":["900003"]}'::jsonb,
    v_active_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or not coalesce(
      v_result->'evidence'->'unresolved_reasons'
        @> '["source_mapping_product_required"]'::jsonb,
      false
    ) then
    raise exception 'product-required mapping did not fail closed: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'invalid-mapping', '검증 잘못된 매핑',
    'verification > invalid mapping',
    '{"source_category_codes":["900004"]}'::jsonb,
    v_active_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or not coalesce(
      v_result->'evidence'->'unresolved_reasons'
        @> '["source_mapping_tuple_invalid"]'::jsonb,
      false
    ) then
    raise exception 'invalid mapping did not fail closed: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'legacy-candidate', '검증 반팔 티셔츠',
    'verification > legacy', '{}'::jsonb, v_active_release_id
  );
  if v_result->>'classification_status' <> 'confirmed'
    or v_result->>'authority_status' <> 'legacy'
    or v_result->'evidence'->>'legacy_authority' <> 'true' then
    raise exception 'valid conflict-free legacy decision was not marked: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'both-untrusted', '검증 반팔 티셔츠',
    'verification > both untrusted',
    '{"source_category_codes":["900005"]}'::jsonb,
    v_active_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or jsonb_array_length(v_result->'authority_conflicts') = 0 then
    raise exception 'both-untrusted conflict did not fail closed: %', v_result;
  end if;

  -- A. A verified direct mapping does not silently override a conflicting
  -- legacy exact decision.
  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'mapping-conflict-legacy',
    '검증 반팔 티셔츠', 'verification > mapping conflict legacy',
    '{"source_category_codes":["900006"]}'::jsonb,
    v_active_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or jsonb_array_length(v_result->'authority_conflicts') = 0 then
    raise exception 'verified mapping/legacy conflict did not fail closed: %',
      v_result;
  end if;

  -- B. A verified profile also stays fail-closed against conflicting legacy
  -- product authority.
  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'profile-conflict-legacy',
    '검증 반팔 티셔츠', 'verification > profile conflict legacy',
    '{}'::jsonb, v_active_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or jsonb_array_length(v_result->'authority_conflicts') = 0 then
    raise exception 'verified profile/legacy conflict did not fail closed: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'profile-candidate', '검증 반팔 티셔츠',
    'verification > profile',
    '{}'::jsonb,
    v_active_release_id
  );
  if v_result->>'classification_status' <> 'confirmed'
    or v_result->>'classification_method' <> 'product_classifier'
    or v_result->>'garment_type_code' <> 'tshirt'
    or v_result->>'classifier_policy_version' <> 'classifier-v1'
    or v_result->'evidence'->>'classifier_policy_version_source'
      <> 'release_runtime_policy_contract' then
    raise exception 'verified profile was not selected: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'profile-policy-mismatch',
    '검증 반팔 티셔츠', 'verification > profile',
    '{}'::jsonb, v_mismatch_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or v_result->>'classifier_policy_version' <> 'classifier-v2' then
    raise exception 'mismatched classifier profile version was used: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'profile-policy-missing',
    '검증 반팔 티셔츠', 'verification > profile',
    '{}'::jsonb, v_missing_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or not coalesce(
      v_result->'evidence'->'unresolved_reasons'
        @> '["classifier_policy_version_missing"]'::jsonb,
      false
    ) then
    raise exception 'missing classifier policy did not fail closed: %',
      v_result;
  end if;

  -- Raw observation payload cannot override the selected release contract.
  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'profile-policy-payload-spoof',
    '검증 반팔 티셔츠', 'verification > profile',
    '{"classifier_policy_version":"classifier-v1"}'::jsonb,
    v_mismatch_release_id
  );
  if v_result->>'classification_status' <> 'review_required'
    or v_result->>'classifier_policy_version' <> 'classifier-v2'
    or v_result->'evidence'->>'classifier_policy_version_source'
      <> 'release_runtime_policy_contract' then
    raise exception 'raw payload spoof changed release classifier policy: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_resolve_product_classification_v4(
    'verification_phase1b1', 'excluded-candidate', '검증 제외 상품',
    'verification > excluded',
    '{}'::jsonb,
    v_active_release_id
  );
  if v_result->>'classification_status' <> 'not_comparable'
    or v_result->>'authority_status' <> 'verified' then
    raise exception 'verified exclusion was not selected: %', v_result;
  end if;

  insert into fitmatch_catalog.products (
    source,
    external_product_id,
    product_name,
    source_category_path,
    raw_payload,
    input_fingerprint
  ) values (
    'verification_phase1b1',
    'recorder-v2',
    '검증 반팔 티셔츠',
    'verification > recorder',
    '{}'::jsonb,
    fitmatch_catalog.runtime_product_fingerprint(
      '검증 반팔 티셔츠',
      'verification > recorder'
    )
  ) returning id into v_product_id;

  v_first_history_id :=
    fitmatch_catalog.runtime_record_product_classification_v2(
      v_product_id,
      jsonb_build_object(
        'category_code', 'tops',
        'detail_code', 'short_sleeve',
        'garment_type_code', 'tshirt',
        'family_code', 'tshirt',
        'length_code', 'short_sleeve',
        'classification_status', 'confirmed',
        'classification_method', 'canonical_product_decision',
        'authority_status', 'verified',
        'confidence', 1,
        'requires_user_confirmation', false,
        'mapping_release_id', v_active_release_id,
        'decision_version', 'recorder-verification-v1',
        'classifier_policy_version', 'verification-v1',
        'authority_conflicts', '[]'::jsonb,
        'evidence', '{"fixture":true}'::jsonb
      )
    );
  v_second_history_id :=
    fitmatch_catalog.runtime_record_product_classification_v2(
      v_product_id,
      jsonb_build_object(
        'category_code', 'tops',
        'detail_code', 'short_sleeve',
        'garment_type_code', 'tshirt',
        'family_code', 'tshirt',
        'length_code', 'short_sleeve',
        'classification_status', 'confirmed',
        'classification_method', 'canonical_product_decision',
        'authority_status', 'verified',
        'confidence', 1,
        'requires_user_confirmation', false,
        'mapping_release_id', v_active_release_id,
        'decision_version', 'recorder-verification-v2',
        'classifier_policy_version', 'verification-v1',
        'authority_conflicts', '[]'::jsonb,
        'evidence', '{"fixture":true}'::jsonb
      )
    );

  if v_first_history_id = v_second_history_id
    or (select count(*)
        from fitmatch_catalog.product_classification_history
        where product_id = v_product_id) <> 2
    or (select count(*)
        from fitmatch_catalog.product_classification_history
        where product_id = v_product_id and is_current) <> 1
    or not exists (
      select 1
      from fitmatch_catalog.product_classification_history
      where id = v_first_history_id
        and not is_current
        and superseded_at is not null
    )
    or not exists (
      select 1
      from fitmatch_catalog.product_classification_history
      where id = v_second_history_id
        and is_current
        and garment_type_code = 'tshirt'
    ) then
    raise exception 'recorder v2 append/supersede invariant failed';
  end if;

  begin
    perform fitmatch_catalog.runtime_record_product_classification_v2(
      v_product_id,
      jsonb_build_object(
        'category_code', 'bottoms',
        'detail_code', 'short_pants',
        'garment_type_code', 'tshirt',
        'family_code', 'tshirt',
        'length_code', 'short_sleeve',
        'classification_status', 'confirmed',
        'classification_method', 'category_mapping',
        'requires_user_confirmation', false
      )
    );
    raise exception 'recorder v2 accepted an invalid confirmed tuple';
  exception
    when sqlstate '22023' then
      null;
  end;

  if (select count(*)
      from fitmatch_catalog.product_classification_history
      where product_id = v_product_id and is_current) <> 1 then
    raise exception 'failed recorder call damaged current invariant';
  end if;

  if (select count(*)
      from fitmatch_catalog.product_classification_decisions)
      <> v_decision_count + 6
    or (select count(*)
        from fitmatch_catalog.product_classification_history)
      <> v_history_count + 2
    or (select count(*) from fitmatch_catalog.products)
      <> v_product_count + 1
    or (select count(*) from fitmatch_catalog.product_measurements)
      <> v_measurement_count then
    raise exception 'fixture touched an unexpected production-shaped data set';
  end if;
end $$;

-- H. Shadow comparison evaluator contract.
do $$
declare
  v_active_release_id uuid;
  v_missing_comparison_release_id uuid;
  v_missing_rule_release_id uuid;
  v_missing_measurement_release_id uuid;
  v_missing_contract_release_id uuid;
  v_result jsonb;
begin
  select id into strict v_active_release_id
  from fitmatch_catalog.releases
  where status = 'active';

  select id into strict v_missing_contract_release_id
  from fitmatch_catalog.releases
  where release_key = 'synthetic-policy-contract-missing';

  insert into fitmatch_catalog.releases (
    release_key, taxonomy_version, policy_version, status,
    bundle_checksum, app_taxonomy_checksum, expected_mapping_count,
    expected_qa_count, validation_report
  ) values
    (
      'synthetic-missing-comparison-version', 'taxonomy-v1',
      'taxonomy-policy-v1', 'loading', 'fixture', 'fixture', 0, 0,
      '{"runtime_policy_contract":{"classifier_policy_version":"classifier-v1","comparison_policy_version":"comparison-policy-missing","compatibility_rule_version":"compatibility-rule-v1","measurement_policy_version":"measure-v1"}}'::jsonb
    ),
    (
      'synthetic-missing-rule-version', 'taxonomy-v1',
      'taxonomy-policy-v1', 'loading', 'fixture', 'fixture', 0, 0,
      '{"runtime_policy_contract":{"classifier_policy_version":"classifier-v1","comparison_policy_version":"comparison-policy-v1","compatibility_rule_version":"compatibility-rule-missing","measurement_policy_version":"measure-v1"}}'::jsonb
    ),
    (
      'synthetic-missing-measurement-version', 'taxonomy-v1',
      'taxonomy-policy-v1', 'loading', 'fixture', 'fixture', 0, 0,
      '{"runtime_policy_contract":{"classifier_policy_version":"classifier-v1","comparison_policy_version":"comparison-policy-v1","compatibility_rule_version":"compatibility-rule-v1","measurement_policy_version":"measure-missing"}}'::jsonb
    );

  select id into strict v_missing_comparison_release_id
  from fitmatch_catalog.releases
  where release_key = 'synthetic-missing-comparison-version';
  select id into strict v_missing_rule_release_id
  from fitmatch_catalog.releases
  where release_key = 'synthetic-missing-rule-version';
  select id into strict v_missing_measurement_release_id
  from fitmatch_catalog.releases
  where release_key = 'synthetic-missing-measurement-version';

  -- Same-group policy and measurement rows are pinned to exactly one version.
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tshirt', 'tshirt', false, v_active_release_id
  );
  if not coalesce((v_result->>'allowed')::boolean, false)
    or v_result->>'comparison_policy_version' <> 'comparison-policy-v1'
    or v_result->>'compatibility_rule_version' <> 'compatibility-rule-v1'
    or v_result->>'measurement_policy_version' <> 'measure-v1'
    or v_result ? 'compatibility_policy_version'
    or v_result->'measurement_policy_versions' <> '["measure-v1"]'::jsonb
    or v_result->'measurement_policy_dimensions' ? 'other_only'
    or v_result->'measurement_weights' ? 'other_only' then
    raise exception 'policy-ready tshirt comparison was rejected: %', v_result;
  end if;

  -- Allowed cross-group rule consumes every typed requirement and uses the
  -- rule weights rather than mixing policy versions.
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'shirt', 'shirt', 'short_sleeve', null,
    'tshirt', 'shirt', false, v_active_release_id
  );
  if not coalesce((v_result->>'allowed')::boolean, false)
    or v_result->'required_measurements' <> '["chest"]'::jsonb
    or not (v_result->'required_any_measurements'
      @> '["shoulder","waist"]'::jsonb)
    or (v_result->>'minimum_required_any')::integer <> 1
    or v_result->'measurement_weights' <> '{"chest":2.5}'::jsonb
    or v_result#>>'{compatibility_rule,policy_version}'
      <> 'compatibility-rule-v1'
    or v_result#>>'{compatibility_rule,directional}' <> 'false' then
    raise exception 'allowed compatibility rule contract failed: %', v_result;
  end if;

  -- An explicit denial always wins.
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'knit', 'knit', 'short_sleeve', null,
    'tshirt', 'knit', false, v_active_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'compatibility_rule_denied' then
    raise exception 'allowed=false compatibility rule was not denied: %',
      v_result;
  end if;

  -- Extended mode cannot bypass fallback_allowed=false.
  update fitmatch_taxonomy.comparison_compatibility_rules
  set fallback_allowed = false
  where from_family_code = 'tshirt'
    and to_family_code = 'shirt'
    and policy_version = 'compatibility-rule-v1';
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'shirt', 'shirt', 'short_sleeve', null,
    'tshirt', 'shirt', true, v_active_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'compatibility_fallback_not_allowed' then
    raise exception 'fallback_allowed=false was bypassed: %', v_result;
  end if;
  update fitmatch_taxonomy.comparison_compatibility_rules
  set fallback_allowed = true
  where from_family_code = 'tshirt'
    and to_family_code = 'shirt'
    and policy_version = 'compatibility-rule-v1';

  -- length_match_required=true blocks automatic mismatch.
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'shirt', 'shirt', 'long_sleeve', null,
    'tshirt', 'shirt', false, v_active_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'required_length_axis_mismatch' then
    raise exception 'required cross-group length mismatch did not block: %',
      v_result;
  end if;

  -- With fallback allowed, the rule's exact exclusion list is used.
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'shirt', 'shirt', 'long_sleeve', null,
    'tshirt', 'shirt', true, v_active_release_id
  );
  if not coalesce((v_result->>'allowed')::boolean, false)
    or v_result->>'level' <> 'extended'
    or v_result->'excluded_measurements' <> '["sleeve_length"]'::jsonb then
    raise exception 'rule length fallback/exclusion contract failed: %',
      v_result;
  end if;

  -- length_match_required=false permits mismatch without automatic fallback.
  update fitmatch_taxonomy.comparison_compatibility_rules
  set length_match_required = false
  where from_family_code = 'tshirt'
    and to_family_code = 'shirt'
    and policy_version = 'compatibility-rule-v1';
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'shirt', 'shirt', 'long_sleeve', null,
    'tshirt', 'shirt', false, v_active_release_id
  );
  if not coalesce((v_result->>'allowed')::boolean, false)
    or v_result->>'level' <> 'direct' then
    raise exception 'length_match_required=false still blocked mismatch: %',
      v_result;
  end if;
  update fitmatch_taxonomy.comparison_compatibility_rules
  set length_match_required = true
  where from_family_code = 'tshirt'
    and to_family_code = 'shirt'
    and policy_version = 'compatibility-rule-v1';

  -- Directional rules cannot be consumed in reverse.
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'knit', 'knit', 'short_sleeve', null,
    'tops', 'unisex', 'shirt', 'shirt', 'short_sleeve', null,
    'knit', 'shirt', false, v_active_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'comparison_group_incompatible' then
    raise exception 'directional reverse comparison was allowed: %', v_result;
  end if;

  -- Comparison policy and compatibility rule vocabularies are independently
  -- pinned. Neither missing version may borrow rows from another version.
  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'shirt', 'shirt', 'short_sleeve', null,
    'tshirt', 'shirt', false, v_missing_comparison_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'comparison_policy_version_missing' then
    raise exception 'wrong comparison policy version was used: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'shirt', 'shirt', 'short_sleeve', null,
    'tshirt', 'shirt', false, v_missing_rule_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'compatibility_rule_version_missing' then
    raise exception 'wrong compatibility rule version was used: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tshirt', 'tshirt', false, v_missing_measurement_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'measurement_policy_version_missing' then
    raise exception 'missing measurement policy did not fail closed: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'tshirt', 'tshirt', false, v_missing_contract_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'runtime_policy_contract_missing' then
    raise exception 'missing runtime policy contract did not fail closed: %',
      v_result;
  end if;

  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops', 'unisex', 'base_layer_top', 'base_layer_top',
    'short_sleeve', null,
    'tops', 'unisex', 'tshirt', 'short_sleeve', 'short_sleeve', null,
    'base_layer_top', 'tshirt', false, v_active_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason'
      <> 'base_layer_top_tshirt_automatic_comparison_blocked' then
    raise exception 'base-layer/tshirt comparison was not blocked: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'underwear', 'unisex', 'underwear', 'underwear',
    null, null,
    'underwear', 'unisex', 'underwear', 'underwear',
    null, null,
    'underwear', 'underwear', false, v_active_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true)
    or v_result->>'reason' <> 'generic_underwear_comparison_blocked' then
    raise exception 'generic underwear did not fail closed: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'homewear', 'unisex', 'homewear', 'homewear', null, null,
    'homewear', 'unisex', 'homewear', 'homewear', null, null,
    'homewear', 'homewear', false, v_active_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true) then
    raise exception 'unseeded Homewear Option A did not fail closed: %', v_result;
  end if;

  v_result := fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'dresses', 'unisex', 'dress', 'dress', null, 'short_body',
    'dresses', 'unisex', 'dress', 'dress', null, 'short_body',
    'dress', 'dress', false, v_active_release_id
  );
  if coalesce((v_result->>'allowed')::boolean, true) then
    raise exception 'unseeded dress policy did not fail closed: %', v_result;
  end if;
end $$;

-- K. This entire validation transaction, including recorder fixtures, leaves
-- the database unchanged.
rollback;
