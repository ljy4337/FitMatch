begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(
  hashtext('fitmatch:authoritative-classification-foundation-v1')
);

-- Migration 114 is a hard prerequisite. This migration must never recreate or
-- bypass the release gate and review-queue objects owned by 114.
do $$
begin
  if to_regprocedure(
      'fitmatch_catalog.runtime_release_gate_report(uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_activate_validated_release(uuid)'
    ) is null
    or to_regprocedure(
      'fitmatch_catalog.runtime_triage_data_quality_issue(uuid,text,smallint,uuid,text,jsonb)'
    ) is null
    or to_regclass(
      'fitmatch_catalog.data_quality_review_queue'
    ) is null then
    raise exception using
      errcode = '55000',
      message = 'migration_114_release_gate_prerequisite_missing';
  end if;

  if has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_activate_validated_release(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_activate_validated_release(uuid)',
      'EXECUTE'
    )
    or has_function_privilege(
      'anon',
      'fitmatch_catalog.runtime_triage_data_quality_issue(uuid,text,smallint,uuid,text,jsonb)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'fitmatch_catalog.runtime_triage_data_quality_issue(uuid,text,smallint,uuid,text,jsonb)',
      'EXECUTE'
    ) then
    raise exception using
      errcode = '42501',
      message = 'migration_114_trusted_boundary_invalid';
  end if;
end $$;

-- Preserve the existing (source, external_product_id) primary key and every
-- legacy row. The default exposes the existing implicit authority explicitly
-- without an UPDATE statement.
alter table fitmatch_catalog.product_classification_decisions
  add column if not exists garment_type_code text,
  add column if not exists authority_status text not null default 'legacy';

alter table fitmatch_catalog.product_classification_history
  add column if not exists garment_type_code text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid =
        'fitmatch_catalog.product_classification_decisions'::regclass
      and conname = 'product_classification_decisions_authority_status_check'
  ) then
    alter table fitmatch_catalog.product_classification_decisions
      add constraint product_classification_decisions_authority_status_check
      check (authority_status in ('legacy', 'verified', 'revoked'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid =
        'fitmatch_catalog.product_classification_decisions'::regclass
      and conname = 'product_classification_decisions_verified_complete_check'
  ) then
    alter table fitmatch_catalog.product_classification_decisions
      add constraint product_classification_decisions_verified_complete_check
      check (
        authority_status <> 'verified'
        or (
          category_code is not null
          and detail_code is not null
          and garment_type_code is not null
          and comparison_family is not null
          and requires_user_confirmation = false
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid =
        'fitmatch_catalog.product_classification_decisions'::regclass
      and conname = 'product_classification_decisions_garment_type_code_fkey'
  ) then
    if not exists (
      select 1
      from pg_index index_row
      join pg_class table_row on table_row.oid = index_row.indrelid
      join pg_namespace table_schema on table_schema.oid = table_row.relnamespace
      where table_schema.nspname = 'public'
        and table_row.relname = 'garment_types'
        and index_row.indisunique
        and index_row.indisvalid
        and index_row.indpred is null
        and index_row.indexprs is null
        and index_row.indnkeyatts = 1
        and (
          select attribute_row.attname
          from unnest(index_row.indkey)
            with ordinality indexed_column(attnum, position)
          join pg_attribute attribute_row
            on attribute_row.attrelid = index_row.indrelid
           and attribute_row.attnum = indexed_column.attnum
          order by indexed_column.position
          limit 1
        ) = 'code'
    ) then
      raise exception using
        errcode = '55000',
        message = 'garment_type_code_unique_dependency_missing';
    end if;

    alter table fitmatch_catalog.product_classification_decisions
      add constraint product_classification_decisions_garment_type_code_fkey
      foreign key (garment_type_code)
      references public.garment_types(code)
      on update restrict
      on delete restrict;
  end if;
end $$;

comment on column
  fitmatch_catalog.product_classification_decisions.garment_type_code is
  'Canonical garment type. Nullable for preserved legacy or non-comparable decisions.';
comment on column
  fitmatch_catalog.product_classification_decisions.authority_status is
  'Authority lifecycle: legacy, verified, or revoked. Verified rows must be complete.';
comment on column
  fitmatch_catalog.product_classification_history.garment_type_code is
  'Canonical garment type captured by append-only recorder v2; existing history remains NULL.';

create or replace function
fitmatch_catalog.runtime_validate_classification_tuple_v1(
  p_category_code text,
  p_detail_code text,
  p_garment_type_code text,
  p_family_code text,
  p_length_code text default null,
  p_body_length_code text default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_category_code text := nullif(lower(btrim(p_category_code)), '');
  v_detail_code text := nullif(lower(btrim(p_detail_code)), '');
  v_garment_type_code text := nullif(lower(btrim(p_garment_type_code)), '');
  v_family_code text := nullif(lower(btrim(p_family_code)), '');
  v_length_code text := nullif(lower(btrim(p_length_code)), '');
  v_body_length_code text := nullif(lower(btrim(p_body_length_code)), '');
  v_blockers text[] := array[]::text[];
  v_major_id uuid;
  v_garment public.garment_types%rowtype;
  v_group public.comparison_groups%rowtype;
  v_garment_found boolean := false;
  v_group_found boolean := false;
  v_requires_sleeve boolean := false;
  v_requires_pants boolean := false;
  v_requires_body boolean := false;
  v_sleeve_state text := 'not_required';
  v_pants_state text := 'not_required';
  v_body_state text := 'not_required';
begin
  if v_category_code is null then
    v_blockers := array_append(v_blockers, 'category_code_missing');
  else
    select category.id
    into v_major_id
    from public.app_categories category
    where category.code = v_category_code
      and category.depth = 0
      and category.parent_id is null
      and category.is_active
    order by category.id
    limit 1;

    if v_major_id is null then
      v_blockers := array_append(
        v_blockers,
        'category_code_not_found_or_inactive'
      );
    end if;
  end if;

  if v_detail_code is null then
    v_blockers := array_append(v_blockers, 'detail_code_missing');
  elsif not exists (
    select 1
    from public.app_categories detail
    where detail.code = v_detail_code
      and detail.depth = 1
      and detail.is_active
  ) then
    v_blockers := array_append(
      v_blockers,
      'detail_code_not_found_or_inactive'
    );
  elsif v_major_id is not null
    and not exists (
      select 1
      from public.app_categories detail
      where detail.code = v_detail_code
        and detail.depth = 1
        and detail.parent_id = v_major_id
        and detail.is_active
    ) then
    v_blockers := array_append(v_blockers, 'category_detail_mismatch');
  end if;

  if v_garment_type_code is null then
    v_blockers := array_append(v_blockers, 'garment_type_code_missing');
  else
    select garment.*
    into v_garment
    from public.garment_types garment
    where garment.code = v_garment_type_code
      and garment.is_active
    limit 1;
    v_garment_found := found;

    if not v_garment_found then
      v_blockers := array_append(
        v_blockers,
        'garment_type_code_not_found_or_inactive'
      );
    elsif v_category_code is not null
      and v_garment.major_category_code <> v_category_code then
      v_blockers := array_append(
        v_blockers,
        'category_garment_type_mismatch'
      );
    end if;
  end if;

  if v_family_code is null then
    v_blockers := array_append(v_blockers, 'family_code_missing');
  else
    select comparison_group.*
    into v_group
    from public.comparison_groups comparison_group
    where comparison_group.code = v_family_code
      and comparison_group.is_active
    limit 1;
    v_group_found := found;

    if not v_group_found then
      v_blockers := array_append(
        v_blockers,
        'family_code_not_found_or_inactive'
      );
    elsif v_category_code is not null
      and v_group.major_category_code <> v_category_code then
      v_blockers := array_append(v_blockers, 'category_family_mismatch');
    end if;
  end if;

  if v_garment_found and v_group_found
    and v_garment.comparison_group_code <> v_family_code then
    v_blockers := array_append(v_blockers, 'garment_family_mismatch');
  end if;

  if v_garment_found then
    v_requires_sleeve := v_garment.requires_sleeve_class;
    v_requires_pants := v_garment.requires_pants_length;
    v_requires_body := v_garment.requires_body_length;
  end if;

  if v_requires_sleeve and v_requires_pants then
    v_blockers := array_append(
      v_blockers,
      'garment_requires_conflicting_length_axes'
    );
  end if;

  if v_requires_sleeve then
    if v_length_code is null then
      v_sleeve_state := 'missing';
      v_blockers := array_append(
        v_blockers,
        'required_sleeve_axis_missing'
      );
    elsif v_length_code = 'not_applicable' then
      v_sleeve_state := 'not_applicable';
      v_blockers := array_append(
        v_blockers,
        'required_sleeve_axis_not_applicable'
      );
    elsif v_length_code in ('unknown', 'unknown_sleeve') then
      v_sleeve_state := 'unknown';
      v_blockers := array_append(
        v_blockers,
        'required_sleeve_axis_unknown'
      );
    elsif not exists (
      select 1
      from public.comparison_length_classes length_class
      where length_class.code = v_length_code
        and length_class.axis_code = 'sleeve'
        and length_class.is_active
    ) then
      v_sleeve_state := 'invalid';
      v_blockers := array_append(v_blockers, 'sleeve_axis_code_invalid');
    else
      v_sleeve_state := 'provided';
    end if;
  elsif v_requires_pants then
    if v_length_code is null then
      v_pants_state := 'missing';
      v_blockers := array_append(
        v_blockers,
        'required_pants_axis_missing'
      );
    elsif v_length_code = 'not_applicable' then
      v_pants_state := 'not_applicable';
      v_blockers := array_append(
        v_blockers,
        'required_pants_axis_not_applicable'
      );
    elsif v_length_code in ('unknown', 'unknown_leg_length') then
      v_pants_state := 'unknown';
      v_blockers := array_append(
        v_blockers,
        'required_pants_axis_unknown'
      );
    elsif not exists (
      select 1
      from public.comparison_length_classes length_class
      where length_class.code = v_length_code
        and length_class.axis_code = 'leg'
        and length_class.is_active
    ) then
      v_pants_state := 'invalid';
      v_blockers := array_append(v_blockers, 'pants_axis_code_invalid');
    else
      v_pants_state := 'provided';
    end if;
  else
    if v_length_code is null then
      v_sleeve_state := 'absent';
      v_pants_state := 'absent';
    elsif v_length_code = 'not_applicable' then
      v_sleeve_state := 'not_applicable';
      v_pants_state := 'not_applicable';
    elsif v_length_code in (
      'unknown',
      'unknown_sleeve',
      'unknown_leg_length'
    ) then
      v_sleeve_state := 'unknown';
      v_pants_state := 'unknown';
      v_blockers := array_append(
        v_blockers,
        'length_axis_unknown_for_non_required_axis'
      );
    else
      v_sleeve_state := 'provided';
      v_pants_state := 'provided';
      v_blockers := array_append(
        v_blockers,
        'length_axis_not_applicable_to_garment'
      );
    end if;
  end if;

  if v_requires_body then
    if v_body_length_code is null then
      v_body_state := 'missing';
      v_blockers := array_append(
        v_blockers,
        'required_body_axis_missing'
      );
    elsif v_body_length_code = 'not_applicable' then
      v_body_state := 'not_applicable';
      v_blockers := array_append(
        v_blockers,
        'required_body_axis_not_applicable'
      );
    elsif v_body_length_code in ('unknown', 'unknown_body') then
      v_body_state := 'unknown';
      v_blockers := array_append(
        v_blockers,
        'required_body_axis_unknown'
      );
    elsif not exists (
      select 1
      from public.comparison_length_classes length_class
      where length_class.code = v_body_length_code
        and length_class.axis_code = 'body'
        and length_class.is_active
    ) then
      v_body_state := 'invalid';
      v_blockers := array_append(v_blockers, 'body_axis_code_invalid');
    else
      v_body_state := 'provided';
    end if;
  else
    if v_body_length_code is null then
      v_body_state := 'absent';
    elsif v_body_length_code = 'not_applicable' then
      v_body_state := 'not_applicable';
    elsif v_body_length_code in ('unknown', 'unknown_body') then
      v_body_state := 'unknown';
      v_blockers := array_append(
        v_blockers,
        'body_axis_unknown_for_non_required_axis'
      );
    else
      v_body_state := 'provided';
      v_blockers := array_append(
        v_blockers,
        'body_axis_not_applicable_to_garment'
      );
    end if;
  end if;

  return jsonb_build_object(
    'valid', cardinality(v_blockers) = 0,
    'blockers', to_jsonb(v_blockers),
    'normalized', jsonb_build_object(
      'category_code', v_category_code,
      'detail_code', v_detail_code,
      'garment_type_code', v_garment_type_code,
      'family_code', v_family_code,
      'length_code', v_length_code,
      'body_length_code', v_body_length_code
    ),
    'required_axes', jsonb_build_object(
      'sleeve', jsonb_build_object(
        'required', v_requires_sleeve,
        'state', v_sleeve_state
      ),
      'pants', jsonb_build_object(
        'required', v_requires_pants,
        'state', v_pants_state
      ),
      'body', jsonb_build_object(
        'required', v_requires_body,
        'state', v_body_state
      )
    ),
    'contract_version', 'classification-tuple-v1'
  );
end $$;

create or replace function
fitmatch_catalog.runtime_resolve_product_classification_v4(
  p_source text,
  p_external_product_id text,
  p_product_name text,
  p_source_category_path text,
  p_payload jsonb default '{}'::jsonb,
  p_release_id uuid default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_source text := lower(btrim(coalesce(p_source, '')));
  v_external_product_id text := btrim(coalesce(p_external_product_id, ''));
  v_product_name text := btrim(coalesce(p_product_name, ''));
  v_path text := fitmatch_catalog.runtime_normalized_category_path(
    p_source_category_path
  );
  v_signature text := fitmatch_catalog.runtime_product_name_signature(
    p_product_name
  );
  v_fingerprint text := fitmatch_catalog.runtime_product_fingerprint(
    p_product_name,
    p_source_category_path
  );
  v_target text := upper(nullif(btrim(coalesce(p_payload->>'audience', '')), ''));
  v_release_id uuid;
  v_release_policy_version text;
  v_runtime_policy_contract jsonb;
  v_classifier_policy_version text;
  v_classifier_policy_source text;
  v_decision fitmatch_catalog.product_classification_decisions%rowtype;
  v_decision_found boolean := false;
  v_mapping fitmatch_catalog.source_category_mappings%rowtype;
  v_mapping_found boolean := false;
  v_mapping_ambiguous boolean := false;
  v_mapping_count integer := 0;
  v_mapping_scope text;
  v_mapping_authority text;
  v_mapping_product_required boolean := false;
  v_mapping_category text;
  v_mapping_detail text;
  v_mapping_garment text;
  v_mapping_family text;
  v_mapping_length text;
  v_mapping_body_length text;
  v_mapping_tuple_validation jsonb;
  v_decision_tuple_validation jsonb;
  v_profile_tuple_validation jsonb;
  v_name_profile fitmatch_catalog.classification_name_profiles%rowtype;
  v_path_profile fitmatch_catalog.classification_path_profiles%rowtype;
  v_exclusion fitmatch_catalog.classification_exclusion_profiles%rowtype;
  v_profile_found boolean := false;
  v_profile_category text;
  v_profile_detail text;
  v_profile_garment text;
  v_profile_family text;
  v_profile_length text;
  v_profile_body_length text;
  v_profile_method text;
  v_profile_source text;
  v_profile_sample_count integer;
  v_profile_evidence jsonb;
  v_decision_body_length text;
  v_verified_decision_blocks_lower_authority boolean := false;
  v_conflicts jsonb := '[]'::jsonb;
  v_unresolved_reasons jsonb := '[]'::jsonb;
begin
  if v_source !~ '^[a-z][a-z0-9_]*$'
    or v_external_product_id = ''
    or v_product_name = ''
    or jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'invalid_product_classification_preview_input';
  end if;

  if p_release_id is null then
    select release.id,
      release.policy_version,
      release.validation_report->'runtime_policy_contract'
    into v_release_id,
      v_release_policy_version,
      v_runtime_policy_contract
    from fitmatch_catalog.releases release
    where release.status = 'active'
    order by release.activated_at desc nulls last, release.created_at desc
    limit 1;
  else
    select release.id,
      release.policy_version,
      release.validation_report->'runtime_policy_contract'
    into v_release_id,
      v_release_policy_version,
      v_runtime_policy_contract
    from fitmatch_catalog.releases release
    where release.id = p_release_id;

    if not found then
      raise exception using errcode = 'P0002', message = 'release_not_found';
    end if;
  end if;

  if jsonb_typeof(v_runtime_policy_contract) = 'object' then
    v_classifier_policy_version := nullif(btrim(
      v_runtime_policy_contract->>'classifier_policy_version'
    ), '');
    if v_classifier_policy_version is not null then
      v_classifier_policy_source := 'release_runtime_policy_contract';
    end if;
  end if;

  if v_classifier_policy_version is null then
    v_unresolved_reasons := v_unresolved_reasons
      || jsonb_build_array('classifier_policy_version_missing');
  end if;

  select decision.*
  into v_decision
  from fitmatch_catalog.product_classification_decisions decision
  where decision.source = v_source
    and decision.external_product_id = v_external_product_id;
  v_decision_found := found
    and v_decision.input_fingerprint = v_fingerprint;

  if v_release_id is not null
    and jsonb_typeof(p_payload->'source_category_codes') = 'array'
    and jsonb_array_length(p_payload->'source_category_codes') > 0 then
    with codes as (
      select category_code.value as code, category_code.ordinality
      from jsonb_array_elements_text(
        p_payload->'source_category_codes'
      ) with ordinality category_code(value, ordinality)
    ), candidates as (
      select mapping.*, code.ordinality,
        max(code.ordinality) over () as max_ordinality
      from codes code
      join fitmatch_catalog.source_category_mappings mapping
        on mapping.release_id = v_release_id
       and mapping.source = v_source
       and mapping.external_category_id = code.code
       and (v_target is null or mapping.target = v_target)
    ), leaf as (
      select *
      from candidates
      where ordinality = max_ordinality
    )
    select count(*),
      count(distinct row(
        decision_status,
        mapping_status,
        eligibility,
        semantic_category_code,
        semantic_garment_type,
        comparison_family,
        raw_record#>>'{appMapping,detailCode}',
        raw_record#>>'{authorityContract,resolutionScope}'
      )) > 1
    into v_mapping_count, v_mapping_ambiguous
    from leaf;

    if v_mapping_count > 0 and not v_mapping_ambiguous then
      with codes as (
        select category_code.value as code, category_code.ordinality
        from jsonb_array_elements_text(
          p_payload->'source_category_codes'
        ) with ordinality category_code(value, ordinality)
      ), candidates as (
        select mapping.source_identity, code.ordinality,
          max(code.ordinality) over () as max_ordinality
        from codes code
        join fitmatch_catalog.source_category_mappings mapping
          on mapping.release_id = v_release_id
         and mapping.source = v_source
         and mapping.external_category_id = code.code
         and (v_target is null or mapping.target = v_target)
      )
      select mapping.*
      into v_mapping
      from candidates candidate
      join fitmatch_catalog.source_category_mappings mapping
        on mapping.release_id = v_release_id
       and mapping.source_identity = candidate.source_identity
      where candidate.ordinality = candidate.max_ordinality
      order by candidate.source_identity
      limit 1;
      v_mapping_found := found;
    end if;
  end if;

  if not v_mapping_found
    and not v_mapping_ambiguous
    and v_release_id is not null
    and v_path <> '' then
    select count(*),
      count(distinct row(
        mapping.decision_status,
        mapping.mapping_status,
        mapping.eligibility,
        mapping.semantic_category_code,
        mapping.semantic_garment_type,
        mapping.comparison_family,
        mapping.raw_record#>>'{appMapping,detailCode}',
        mapping.raw_record#>>'{authorityContract,resolutionScope}'
      )) > 1
    into v_mapping_count, v_mapping_ambiguous
    from fitmatch_catalog.source_category_mappings mapping
    where mapping.release_id = v_release_id
      and mapping.source = v_source
      and fitmatch_catalog.runtime_normalized_category_path(
        mapping.normalized_path
      ) = v_path
      and (v_target is null or mapping.target = v_target);

    if v_mapping_count > 0 and not v_mapping_ambiguous then
      select mapping.*
      into v_mapping
      from fitmatch_catalog.source_category_mappings mapping
      where mapping.release_id = v_release_id
        and mapping.source = v_source
        and fitmatch_catalog.runtime_normalized_category_path(
          mapping.normalized_path
        ) = v_path
        and (v_target is null or mapping.target = v_target)
      order by mapping.source_identity
      limit 1;
      v_mapping_found := found;
    end if;
  end if;

  if v_mapping_ambiguous then
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'code', 'source_mapping_ambiguous',
      'release_id', v_release_id,
      'candidate_count', v_mapping_count
    ));
    v_unresolved_reasons := v_unresolved_reasons
      || jsonb_build_array('source_mapping_ambiguous');
  elsif v_mapping_found then
    v_mapping_scope := lower(coalesce(
      nullif(v_mapping.raw_record#>>'{authorityContract,resolutionScope}', ''),
      nullif(v_mapping.raw_record->>'resolutionScope', ''),
      ''
    ));
    v_mapping_authority := lower(coalesce(
      nullif(v_mapping.raw_record#>>'{authorityContract,authorityStatus}', ''),
      nullif(v_mapping.raw_record->>'authorityStatus', ''),
      ''
    ));
    v_mapping_product_required :=
      v_mapping_scope = 'product_required'
      or lower(coalesce(
        v_mapping.raw_record#>>'{authorityContract,productRequired}',
        v_mapping.raw_record->>'productRequired',
        'false'
      )) in ('true', '1', 'yes');
    v_mapping_category := nullif(lower(btrim(coalesce(
      v_mapping.semantic_category_code,
      v_mapping.raw_record#>>'{appMapping,categoryCode}'
    ))), '');
    v_mapping_detail := nullif(lower(btrim(
      v_mapping.raw_record#>>'{appMapping,detailCode}'
    )), '');
    v_mapping_garment := nullif(lower(btrim(
      v_mapping.semantic_garment_type
    )), '');
    v_mapping_family := nullif(lower(btrim(
      v_mapping.comparison_family
    )), '');

    select case
        when garment.requires_sleeve_class
          then v_mapping.raw_record#>>'{lengthAxes,sleeve}'
        when garment.requires_pants_length
          then coalesce(
            nullif(v_mapping.raw_record#>>'{lengthAxes,leggings}', ''),
            v_mapping.raw_record#>>'{lengthAxes,pants}'
          )
        else 'not_applicable'
      end,
      case
        when garment.requires_body_length
          then coalesce(
            nullif(v_mapping.raw_record#>>'{lengthAxes,body}', ''),
            v_mapping.raw_record#>>'{lengthAxes,skirt}'
          )
        else 'not_applicable'
      end
    into v_mapping_length, v_mapping_body_length
    from public.garment_types garment
    where garment.code = v_mapping_garment
      and garment.is_active;

    v_mapping_length := nullif(lower(btrim(v_mapping_length)), '');
    v_mapping_body_length := nullif(
      lower(btrim(v_mapping_body_length)),
      ''
    );
    v_mapping_tuple_validation :=
      fitmatch_catalog.runtime_validate_classification_tuple_v1(
        v_mapping_category,
        v_mapping_detail,
        v_mapping_garment,
        v_mapping_family,
        v_mapping_length,
        v_mapping_body_length
      );

    if v_mapping_product_required then
      v_unresolved_reasons := v_unresolved_reasons
        || jsonb_build_array('source_mapping_product_required');
    elsif v_mapping_scope <> 'category_direct'
      or v_mapping_authority <> 'verified' then
      v_unresolved_reasons := v_unresolved_reasons
        || jsonb_build_array('source_mapping_authority_unverified');
    elsif not coalesce(
      (v_mapping_tuple_validation->>'valid')::boolean,
      false
    ) then
      v_unresolved_reasons := v_unresolved_reasons
        || jsonb_build_array('source_mapping_tuple_invalid');
    end if;
  end if;

  if v_decision_found and v_decision.authority_status <> 'revoked' then
    v_decision_body_length := nullif(lower(btrim(
      v_decision.evidence->>'body_length_code'
    )), '');
    v_decision_tuple_validation :=
      fitmatch_catalog.runtime_validate_classification_tuple_v1(
        v_decision.category_code,
        v_decision.detail_code,
        v_decision.garment_type_code,
        v_decision.comparison_family,
        v_decision.length_type,
        v_decision_body_length
      );

    v_verified_decision_blocks_lower_authority :=
      v_decision.authority_status = 'verified'
      and not coalesce(
        (v_decision_tuple_validation->>'valid')::boolean,
        false
      );

    if v_mapping_found and (
      v_decision.category_code is distinct from v_mapping_category
      or v_decision.detail_code is distinct from v_mapping_detail
      or v_decision.comparison_family is distinct from v_mapping_family
      or v_decision.length_type is distinct from v_mapping_length
      or (
        v_decision.garment_type_code is not null
        and v_mapping_garment is not null
        and v_decision.garment_type_code is distinct from v_mapping_garment
      )
      or (
        v_decision_body_length is not null
        and v_mapping_body_length is not null
        and v_decision_body_length is distinct from v_mapping_body_length
      )
    ) then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'code', 'product_decision_source_mapping_conflict',
        'decision_authority_status', v_decision.authority_status,
        'decision_version', v_decision.decision_version,
        'mapping_release_id', v_release_id,
        'mapping_source_identity', v_mapping.source_identity,
        'decision_tuple', jsonb_build_object(
          'category_code', v_decision.category_code,
          'detail_code', v_decision.detail_code,
          'garment_type_code', v_decision.garment_type_code,
          'family_code', v_decision.comparison_family,
          'length_code', v_decision.length_type,
          'body_length_code', v_decision_body_length
        ),
        'mapping_tuple', jsonb_build_object(
          'category_code', v_mapping_category,
          'detail_code', v_mapping_detail,
          'garment_type_code', v_mapping_garment,
          'family_code', v_mapping_family,
          'length_code', v_mapping_length,
          'body_length_code', v_mapping_body_length
        )
      ));
    end if;
  end if;

  -- Verified exact product authority is the only path allowed to win while
  -- still surfacing a lower-priority mapping disagreement.
  if v_decision_found
    and v_decision.authority_status = 'verified'
    and coalesce(
      (v_decision_tuple_validation->>'valid')::boolean,
      false
    ) then
    return jsonb_build_object(
      'category_code', v_decision.category_code,
      'detail_code', v_decision.detail_code,
      'garment_type_code', v_decision.garment_type_code,
      'family_code', v_decision.comparison_family,
      'length_code', v_decision.length_type,
      'body_length_code', v_decision_body_length,
      'classification_status', 'confirmed',
      'classification_method', 'canonical_product_decision',
      'authority_status', 'verified',
      'confidence', 1,
      'requires_user_confirmation', false,
      'mapping_release_id', null,
      'decision_version', v_decision.decision_version,
      'tuple_validation', v_decision_tuple_validation,
      'authority_conflicts', v_conflicts,
      'evidence', jsonb_build_object(
        'decision_release_id', v_decision.release_id,
        'decision_evidence', v_decision.evidence,
        'shadow_contract', true,
        'classifier_policy_version_source', v_classifier_policy_source,
        'classifier_policy_version_missing',
          v_classifier_policy_version is null
      ),
      'classifier_policy_version', v_classifier_policy_version
    );
  end if;

  if v_mapping_found
    and not v_mapping_ambiguous
    and v_mapping_authority = 'verified'
    and v_mapping_scope = 'category_direct'
    and not v_mapping_product_required
    and v_mapping.decision_status = 'confirmed'
    and v_mapping.mapping_status = 'direct'
    and v_mapping.runtime_lookup_eligible
    and v_mapping.eligibility
    and not v_verified_decision_blocks_lower_authority
    and coalesce(
      (v_mapping_tuple_validation->>'valid')::boolean,
      false
    )
    and jsonb_array_length(v_conflicts) = 0 then
    return jsonb_build_object(
      'category_code', v_mapping_category,
      'detail_code', v_mapping_detail,
      'garment_type_code', v_mapping_garment,
      'family_code', v_mapping_family,
      'length_code', v_mapping_length,
      'body_length_code', v_mapping_body_length,
      'classification_status', 'confirmed',
      'classification_method', 'category_mapping',
      'authority_status', 'verified',
      'confidence', 0.99,
      'requires_user_confirmation', false,
      'mapping_release_id', v_release_id,
      'decision_version', coalesce(
        nullif(v_mapping.raw_record->>'policyVersion', ''),
        v_release_policy_version
      ),
      'tuple_validation', v_mapping_tuple_validation,
      'authority_conflicts', v_conflicts,
      'evidence', jsonb_build_object(
        'source_mapping_identity', v_mapping.source_identity,
        'source_category_id', v_mapping.external_category_id,
        'resolution_scope', v_mapping_scope,
        'shadow_contract', true,
        'classifier_policy_version_source', v_classifier_policy_source,
        'classifier_policy_version_missing',
          v_classifier_policy_version is null
      ),
      'classifier_policy_version', v_classifier_policy_version
    );
  end if;

  if v_classifier_policy_version is not null and v_signature <> '' then
    select profile.*
    into v_name_profile
    from fitmatch_catalog.classification_name_profiles profile
    where profile.policy_version = v_classifier_policy_version
      and profile.source = v_source
      and profile.normalized_path = v_path
      and profile.name_signature = v_signature
      and profile.auto_eligible
      and lower(coalesce(profile.evidence->>'authority_status', '')) =
        'verified';

    if found then
      v_profile_found := true;
      v_profile_category := v_name_profile.category_code;
      v_profile_detail := v_name_profile.detail_code;
      v_profile_garment := nullif(
        lower(btrim(v_name_profile.evidence->>'garment_type_code')),
        ''
      );
      v_profile_family := v_name_profile.comparison_family_code;
      v_profile_length := v_name_profile.length_code;
      v_profile_body_length := nullif(
        lower(btrim(v_name_profile.evidence->>'body_length_code')),
        ''
      );
      v_profile_method := 'verified_name_signature_profile';
      v_profile_source := 'name_profile';
      v_profile_sample_count := v_name_profile.sample_count;
      v_profile_evidence := v_name_profile.evidence;
    end if;
  end if;

  if not v_profile_found and v_classifier_policy_version is not null then
    select profile.*
    into v_path_profile
    from fitmatch_catalog.classification_path_profiles profile
    where profile.policy_version = v_classifier_policy_version
      and profile.source = v_source
      and profile.normalized_path = v_path
      and profile.auto_eligible
      and lower(coalesce(profile.evidence->>'authority_status', '')) =
        'verified';

    if found then
      v_profile_found := true;
      v_profile_category := v_path_profile.category_code;
      v_profile_detail := v_path_profile.detail_code;
      v_profile_garment := nullif(
        lower(btrim(v_path_profile.evidence->>'garment_type_code')),
        ''
      );
      v_profile_family := v_path_profile.comparison_family_code;
      v_profile_length := v_path_profile.length_code;
      v_profile_body_length := nullif(
        lower(btrim(v_path_profile.evidence->>'body_length_code')),
        ''
      );
      v_profile_method := 'verified_path_profile';
      v_profile_source := 'path_profile';
      v_profile_sample_count := v_path_profile.sample_count;
      v_profile_evidence := v_path_profile.evidence;
    end if;
  end if;

  if v_profile_found then
    v_profile_tuple_validation :=
      fitmatch_catalog.runtime_validate_classification_tuple_v1(
        v_profile_category,
        v_profile_detail,
        v_profile_garment,
        v_profile_family,
        v_profile_length,
        v_profile_body_length
      );

    if v_decision_found and v_decision.authority_status <> 'revoked' and (
      v_decision.category_code is distinct from v_profile_category
      or v_decision.detail_code is distinct from v_profile_detail
      or v_decision.comparison_family is distinct from v_profile_family
      or v_decision.length_type is distinct from v_profile_length
      or (
        v_decision.garment_type_code is not null
        and v_profile_garment is not null
        and v_decision.garment_type_code is distinct from v_profile_garment
      )
    ) then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'code', 'product_decision_verified_profile_conflict',
        'profile_source', v_profile_source,
        'profile_policy_version', v_classifier_policy_version
      ));
    end if;

    if v_mapping_found and (
      v_mapping_category is distinct from v_profile_category
      or v_mapping_detail is distinct from v_profile_detail
      or v_mapping_family is distinct from v_profile_family
      or v_mapping_length is distinct from v_profile_length
      or (
        v_mapping_garment is not null
        and v_profile_garment is not null
        and v_mapping_garment is distinct from v_profile_garment
      )
    ) then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'code', 'source_mapping_verified_profile_conflict',
        'mapping_source_identity', v_mapping.source_identity,
        'profile_source', v_profile_source,
        'profile_policy_version', v_classifier_policy_version
      ));
    end if;

    if coalesce(
      (v_profile_tuple_validation->>'valid')::boolean,
      false
    )
      and not v_verified_decision_blocks_lower_authority
      and jsonb_array_length(v_conflicts) = 0 then
      return jsonb_build_object(
        'category_code', v_profile_category,
        'detail_code', v_profile_detail,
        'garment_type_code', v_profile_garment,
        'family_code', v_profile_family,
        'length_code', v_profile_length,
        'body_length_code', v_profile_body_length,
        'classification_status', 'confirmed',
        'classification_method', 'product_classifier',
        'authority_status', 'verified',
        'confidence', case
          when v_profile_sample_count >= 5 then 0.98
          else 0.96
        end,
        'requires_user_confirmation', false,
        'mapping_release_id', null,
        'decision_version', v_classifier_policy_version,
        'tuple_validation', v_profile_tuple_validation,
        'authority_conflicts', v_conflicts,
        'evidence', jsonb_build_object(
          'profile_source', v_profile_source,
          'profile_method', v_profile_method,
          'sample_count', v_profile_sample_count,
          'profile_evidence', v_profile_evidence,
          'shadow_contract', true,
          'classifier_policy_version_source', v_classifier_policy_source,
          'classifier_policy_version_missing',
            v_classifier_policy_version is null
        ),
        'classifier_policy_version', v_classifier_policy_version
      );
    end if;
  end if;

  if v_decision_found
    and v_decision.authority_status = 'legacy'
    and coalesce(
      (v_decision_tuple_validation->>'valid')::boolean,
      false
    )
    and jsonb_array_length(v_conflicts) = 0 then
    return jsonb_build_object(
      'category_code', v_decision.category_code,
      'detail_code', v_decision.detail_code,
      'garment_type_code', v_decision.garment_type_code,
      'family_code', v_decision.comparison_family,
      'length_code', v_decision.length_type,
      'body_length_code', v_decision_body_length,
      'classification_status', 'confirmed',
      'classification_method', 'canonical_product_decision',
      'authority_status', 'legacy',
      'confidence', 0.90,
      'requires_user_confirmation', false,
      'mapping_release_id', null,
      'decision_version', v_decision.decision_version,
      'tuple_validation', v_decision_tuple_validation,
      'authority_conflicts', v_conflicts,
      'evidence', jsonb_build_object(
        'legacy_authority', true,
        'decision_release_id', v_decision.release_id,
        'decision_evidence', v_decision.evidence,
        'shadow_contract', true,
        'classifier_policy_version_source', v_classifier_policy_source,
        'classifier_policy_version_missing',
          v_classifier_policy_version is null
      ),
      'classifier_policy_version', v_classifier_policy_version
    );
  end if;

  if v_classifier_policy_version is not null then
    select exclusion.*
    into v_exclusion
    from fitmatch_catalog.classification_exclusion_profiles exclusion
    where exclusion.policy_version = v_classifier_policy_version
      and exclusion.source = v_source
      and exclusion.normalized_path = v_path
      and exclusion.auto_eligible
      and lower(coalesce(exclusion.evidence->>'authority_status', '')) =
        'verified';

    if found
      and not v_verified_decision_blocks_lower_authority
      and jsonb_array_length(v_conflicts) = 0 then
      return jsonb_build_object(
        'category_code', null,
        'detail_code', null,
        'garment_type_code', null,
        'family_code', null,
        'length_code', null,
        'body_length_code', null,
        'classification_status', 'not_comparable',
        'classification_method', 'category_mapping',
        'authority_status', 'verified',
        'confidence', 1,
        'requires_user_confirmation', false,
        'mapping_release_id', null,
        'decision_version', v_classifier_policy_version,
        'tuple_validation', null,
        'authority_conflicts', v_conflicts,
        'evidence', jsonb_build_object(
          'exclusion_reason', v_exclusion.reason_code,
          'sample_count', v_exclusion.sample_count,
          'exclusion_evidence', v_exclusion.evidence,
          'shadow_contract', true,
          'classifier_policy_version_source', v_classifier_policy_source,
          'classifier_policy_version_missing',
            v_classifier_policy_version is null
        ),
        'classifier_policy_version', v_classifier_policy_version
      );
    end if;
  end if;

  if v_decision_found and v_decision.authority_status = 'revoked' then
    v_unresolved_reasons := v_unresolved_reasons
      || jsonb_build_array('exact_product_decision_revoked');
  elsif v_verified_decision_blocks_lower_authority then
    v_unresolved_reasons := v_unresolved_reasons
      || jsonb_build_array('verified_product_decision_tuple_invalid');
  elsif v_decision_found and not coalesce(
    (v_decision_tuple_validation->>'valid')::boolean,
    false
  ) then
    v_unresolved_reasons := v_unresolved_reasons
      || jsonb_build_array('exact_product_decision_tuple_invalid');
  end if;
  if v_profile_found and not coalesce(
    (v_profile_tuple_validation->>'valid')::boolean,
    false
  ) then
    v_unresolved_reasons := v_unresolved_reasons
      || jsonb_build_array('verified_profile_tuple_invalid');
  end if;
  if jsonb_array_length(v_conflicts) > 0 then
    v_unresolved_reasons := v_unresolved_reasons
      || jsonb_build_array('authority_conflict_unresolved');
  end if;
  if jsonb_array_length(v_unresolved_reasons) = 0 then
    v_unresolved_reasons := jsonb_build_array(
      'no_verified_auto_eligible_authority'
    );
  end if;

  return jsonb_build_object(
    'category_code', null,
    'detail_code', null,
    'garment_type_code', null,
    'family_code', null,
    'length_code', null,
    'body_length_code', null,
    'classification_status', 'review_required',
    'classification_method', 'unknown',
    'authority_status', null,
    'confidence', null,
    'requires_user_confirmation', true,
    'mapping_release_id', v_release_id,
    'decision_version', null,
    'tuple_validation', null,
    'authority_conflicts', v_conflicts,
    'evidence', jsonb_build_object(
      'unresolved_reasons', v_unresolved_reasons,
      'mapping_tuple_validation', v_mapping_tuple_validation,
      'decision_tuple_validation', v_decision_tuple_validation,
      'profile_tuple_validation', v_profile_tuple_validation,
      'shadow_contract', true,
      'classifier_policy_version_source', v_classifier_policy_source,
      'classifier_policy_version_missing',
        v_classifier_policy_version is null
    ),
    'classifier_policy_version', v_classifier_policy_version
  );
end $$;

create or replace function
fitmatch_catalog.runtime_record_product_classification_v2(
  p_product_id uuid,
  p_resolution jsonb
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_product fitmatch_catalog.products%rowtype;
  v_history_id uuid;
  v_status text := coalesce(
    nullif(p_resolution->>'classification_status', ''),
    'unclassified'
  );
  v_method text := coalesce(
    nullif(p_resolution->>'classification_method', ''),
    'unknown'
  );
  v_confirmation boolean := coalesce(
    (p_resolution->>'requires_user_confirmation')::boolean,
    v_status <> 'confirmed'
  );
  v_release_id uuid := nullif(
    p_resolution->>'mapping_release_id',
    ''
  )::uuid;
  v_decision_version text := coalesce(
    nullif(p_resolution->>'decision_version', ''),
    'classification-tuple-v1'
  );
  v_confidence numeric := nullif(p_resolution->>'confidence', '')::numeric;
  v_tuple_validation jsonb;
  v_evidence jsonb;
begin
  if jsonb_typeof(coalesce(p_resolution, '{}'::jsonb)) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'classification_resolution_must_be_object';
  end if;

  select product.*
  into v_product
  from fitmatch_catalog.products product
  where product.id = p_product_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'product_not_found';
  end if;

  if v_status not in (
      'confirmed',
      'review_required',
      'not_comparable',
      'unclassified'
    ) then
    raise exception using
      errcode = '22023',
      message = 'invalid_classification_status';
  end if;
  if v_method not in (
      'canonical_product_decision',
      'category_mapping',
      'product_classifier',
      'manual_review',
      'user_override',
      'migration',
      'unknown'
    ) then
    raise exception using
      errcode = '22023',
      message = 'invalid_classification_method';
  end if;
  if v_confidence is not null and (v_confidence < 0 or v_confidence > 1) then
    raise exception using errcode = '22023', message = 'invalid_confidence';
  end if;

  v_tuple_validation :=
    fitmatch_catalog.runtime_validate_classification_tuple_v1(
      p_resolution->>'category_code',
      p_resolution->>'detail_code',
      p_resolution->>'garment_type_code',
      p_resolution->>'family_code',
      p_resolution->>'length_code',
      p_resolution->>'body_length_code'
    );

  if v_status = 'confirmed' and (
    v_confirmation
    or not coalesce((v_tuple_validation->>'valid')::boolean, false)
  ) then
    raise exception using
      errcode = '22023',
      message = 'confirmed_classification_tuple_invalid',
      detail = v_tuple_validation::text;
  end if;

  v_evidence := case
    when jsonb_typeof(p_resolution->'evidence') = 'object'
      then p_resolution->'evidence'
    else '{}'::jsonb
  end || jsonb_build_object(
    'tuple_validation', v_tuple_validation,
    'authority_status', p_resolution->>'authority_status',
    'authority_conflicts', coalesce(
      p_resolution->'authority_conflicts',
      '[]'::jsonb
    ),
    'recorder_contract_version', 'classification-recorder-v2'
  );

  update fitmatch_catalog.product_classification_history history
  set is_current = false,
      superseded_at = now()
  where history.product_id = p_product_id
    and history.is_current;

  insert into fitmatch_catalog.product_classification_history (
    product_id,
    input_fingerprint,
    category_code,
    detail_code,
    garment_type_code,
    comparison_family_code,
    length_code,
    body_length_code,
    classification_status,
    classification_method,
    confidence,
    requires_user_confirmation,
    taxonomy_policy_version,
    mapping_release_id,
    decision_version,
    evidence,
    reviewed_by,
    reviewed_at
  ) values (
    p_product_id,
    v_product.input_fingerprint,
    nullif(p_resolution->>'category_code', ''),
    nullif(p_resolution->>'detail_code', ''),
    nullif(p_resolution->>'garment_type_code', ''),
    nullif(p_resolution->>'family_code', ''),
    nullif(p_resolution->>'length_code', ''),
    nullif(p_resolution->>'body_length_code', ''),
    v_status,
    v_method,
    v_confidence,
    v_confirmation,
    nullif(p_resolution->>'classifier_policy_version', ''),
    v_release_id,
    v_decision_version,
    v_evidence,
    nullif(p_resolution->>'reviewed_by', '')::uuid,
    nullif(p_resolution->>'reviewed_at', '')::timestamptz
  )
  returning id into v_history_id;

  if (
    select count(*)
    from fitmatch_catalog.product_classification_history history
    where history.product_id = p_product_id
      and history.is_current
  ) <> 1 then
    raise exception using
      errcode = '23514',
      message = 'product_current_classification_invariant_failed';
  end if;

  return v_history_id;
end $$;

-- The first 12 arguments preserve the v3 profile order. Garment types and the
-- allow-extended flag retain the Phase 1B-1 order; release identity is appended
-- so comparison, compatibility-rule, and measurement versions are pinned.
create or replace function
fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
  p_reference_category text,
  p_reference_gender text,
  p_reference_family text,
  p_reference_detail text,
  p_reference_length text,
  p_reference_body_length text,
  p_target_category text,
  p_target_gender text,
  p_target_family text,
  p_target_detail text,
  p_target_length text,
  p_target_body_length text,
  p_reference_garment_type text,
  p_target_garment_type text,
  p_allow_extended boolean default false,
  p_release_id uuid default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_reference_validation jsonb :=
    fitmatch_catalog.runtime_validate_classification_tuple_v1(
      p_reference_category,
      p_reference_detail,
      p_reference_garment_type,
      p_reference_family,
      p_reference_length,
      p_reference_body_length
    );
  v_target_validation jsonb :=
    fitmatch_catalog.runtime_validate_classification_tuple_v1(
      p_target_category,
      p_target_detail,
      p_target_garment_type,
      p_target_family,
      p_target_length,
      p_target_body_length
    );
  v_reference_category text :=
    v_reference_validation#>>'{normalized,category_code}';
  v_reference_detail text :=
    v_reference_validation#>>'{normalized,detail_code}';
  v_reference_length text :=
    v_reference_validation#>>'{normalized,length_code}';
  v_reference_body_length text :=
    v_reference_validation#>>'{normalized,body_length_code}';
  v_target_category text :=
    v_target_validation#>>'{normalized,category_code}';
  v_target_detail text :=
    v_target_validation#>>'{normalized,detail_code}';
  v_target_length text :=
    v_target_validation#>>'{normalized,length_code}';
  v_target_body_length text :=
    v_target_validation#>>'{normalized,body_length_code}';
  v_release_id uuid;
  v_runtime_policy_contract jsonb;
  v_comparison_policy_version text;
  v_compatibility_rule_version text;
  v_measurement_policy_version text;
  v_reference_garment public.garment_types%rowtype;
  v_target_garment public.garment_types%rowtype;
  v_reference_group public.comparison_groups%rowtype;
  v_target_group public.comparison_groups%rowtype;
  v_reference_policy public.comparison_policies%rowtype;
  v_target_policy public.comparison_policies%rowtype;
  v_pair_rule fitmatch_taxonomy.comparison_compatibility_rules%rowtype;
  v_pair_rule_found boolean := false;
  v_same_group boolean := false;
  v_length_mismatch boolean := false;
  v_body_mismatch boolean := false;
  v_excluded text[] := array[]::text[];
  v_measurement_count integer := 0;
  v_usable_measurement_count integer := 0;
  v_required_any_available integer := 0;
  v_reference_required_group_count integer := 0;
  v_target_required_group_count integer := 0;
  v_reference_required_group_min integer := 0;
  v_target_required_group_min integer := 0;
  v_minimum_common_measurements integer := 0;
  v_measurement_dimensions jsonb := '[]'::jsonb;
  v_measurement_policy_versions jsonb := '[]'::jsonb;
  v_required_measurements jsonb := '[]'::jsonb;
  v_required_any_measurements jsonb := '[]'::jsonb;
  v_minimum_required_any integer := 0;
  v_measurement_weights jsonb := '{}'::jsonb;
  v_reason text;
begin
  if p_release_id is null then
    select release.id,
      release.validation_report->'runtime_policy_contract'
    into v_release_id, v_runtime_policy_contract
    from fitmatch_catalog.releases release
    where release.status = 'active'
    order by release.activated_at desc nulls last, release.created_at desc
    limit 1;
  else
    select release.id,
      release.validation_report->'runtime_policy_contract'
    into v_release_id, v_runtime_policy_contract
    from fitmatch_catalog.releases release
    where release.id = p_release_id;

    if not found then
      raise exception using errcode = 'P0002', message = 'release_not_found';
    end if;
  end if;

  if v_release_id is null
    or jsonb_typeof(v_runtime_policy_contract) is distinct from 'object' then
    v_reason := 'runtime_policy_contract_missing';
  else
    v_comparison_policy_version := nullif(btrim(
      v_runtime_policy_contract->>'comparison_policy_version'
    ), '');
    v_compatibility_rule_version := nullif(btrim(
      v_runtime_policy_contract->>'compatibility_rule_version'
    ), '');
    v_measurement_policy_version := nullif(btrim(
      v_runtime_policy_contract->>'measurement_policy_version'
    ), '');

    if v_comparison_policy_version is null then
      v_reason := 'comparison_policy_version_missing';
    elsif v_compatibility_rule_version is null then
      v_reason := 'compatibility_rule_version_missing';
    elsif v_measurement_policy_version is null then
      v_reason := 'measurement_policy_version_missing';
    end if;
  end if;

  if v_reason is null and not exists (
    select 1
    from public.comparison_policies policy
    where policy.policy_version = v_comparison_policy_version
      and policy.is_active
  ) then
    v_reason := 'comparison_policy_version_missing';
  elsif v_reason is null and not exists (
    select 1
    from fitmatch_taxonomy.comparison_compatibility_rules rule
    where rule.policy_version = v_compatibility_rule_version
  ) then
    v_reason := 'compatibility_rule_version_missing';
  elsif v_reason is null and not exists (
    select 1
    from public.app_category_measurement_policies policy
    where policy.policy_version = v_measurement_policy_version
      and policy.is_active
      and policy.is_comparable
  ) then
    v_reason := 'measurement_policy_version_missing';
  end if;

  if v_reason is not null then
    return jsonb_build_object(
      'allowed', false,
      'level', 'incompatible',
      'reason', v_reason,
      'release_id', v_release_id,
      'comparison_policy_version', v_comparison_policy_version,
      'compatibility_rule_version', v_compatibility_rule_version,
      'measurement_policy_version', v_measurement_policy_version,
      'reference_tuple_validation', v_reference_validation,
      'target_tuple_validation', v_target_validation,
      'excluded_measurements', '[]'::jsonb,
      'minimum_common_measurements', null,
      'required_measurements', '[]'::jsonb,
      'required_any_measurements', '[]'::jsonb,
      'minimum_required_any', 0,
      'measurement_weights', '{}'::jsonb,
      'extended_requested', p_allow_extended,
      'policy_version', 'classification-comparison-v4'
    );
  end if;

  if v_reference_category is distinct from v_target_category then
    v_reason := 'major_category_incompatible';
  elsif v_reference_category = 'homewear'
    and (
      lower(btrim(coalesce(p_reference_garment_type, ''))) not in (
        'homewear_top', 'homewear_bottom', 'homewear_set'
      )
      or lower(btrim(coalesce(p_target_garment_type, ''))) not in (
        'homewear_top', 'homewear_bottom', 'homewear_set'
      )
    ) then
    v_reason := 'homewear_subtype_policy_unavailable';
  elsif v_reference_category = 'underwear'
    and (
      lower(btrim(coalesce(p_reference_garment_type, ''))) in (
        '', 'underwear', 'generic_underwear'
      )
      or lower(btrim(coalesce(p_target_garment_type, ''))) in (
        '', 'underwear', 'generic_underwear'
      )
    ) then
    v_reason := 'generic_underwear_comparison_blocked';
  elsif v_reference_category = 'dresses'
    and (
      not coalesce((v_reference_validation->>'valid')::boolean, false)
      or not coalesce((v_target_validation->>'valid')::boolean, false)
    ) then
    v_reason := 'dress_contract_or_measurement_policy_unavailable';
  elsif not coalesce((v_reference_validation->>'valid')::boolean, false) then
    v_reason := 'reference_tuple_invalid';
  elsif not coalesce((v_target_validation->>'valid')::boolean, false) then
    v_reason := 'target_tuple_invalid';
  end if;

  if v_reason is not null then
    return jsonb_build_object(
      'allowed', false,
      'level', 'incompatible',
      'reason', v_reason,
      'release_id', v_release_id,
      'comparison_policy_version', v_comparison_policy_version,
      'compatibility_rule_version', v_compatibility_rule_version,
      'measurement_policy_version', v_measurement_policy_version,
      'reference_tuple_validation', v_reference_validation,
      'target_tuple_validation', v_target_validation,
      'excluded_measurements', '[]'::jsonb,
      'minimum_common_measurements', null,
      'required_measurements', '[]'::jsonb,
      'required_any_measurements', '[]'::jsonb,
      'minimum_required_any', 0,
      'measurement_weights', '{}'::jsonb,
      'extended_requested', p_allow_extended,
      'policy_version', 'classification-comparison-v4'
    );
  end if;

  select garment.*
  into strict v_reference_garment
  from public.garment_types garment
  where garment.code = lower(btrim(p_reference_garment_type))
    and garment.is_active;
  select garment.*
  into strict v_target_garment
  from public.garment_types garment
  where garment.code = lower(btrim(p_target_garment_type))
    and garment.is_active;

  if array[v_reference_garment.code, v_target_garment.code]
      @> array['base_layer_top', 'tshirt']::text[] then
    v_reason := 'base_layer_top_tshirt_automatic_comparison_blocked';
  elsif v_reference_garment.requires_sleeve_class
      is distinct from v_target_garment.requires_sleeve_class
    or v_reference_garment.requires_pants_length
      is distinct from v_target_garment.requires_pants_length
    or v_reference_garment.requires_body_length
      is distinct from v_target_garment.requires_body_length then
    v_reason := 'garment_axis_contract_mismatch';
  end if;

  if v_reason is null then
    select comparison_group.*
    into strict v_reference_group
    from public.comparison_groups comparison_group
    where comparison_group.code = v_reference_garment.comparison_group_code
      and comparison_group.is_active;
    select comparison_group.*
    into strict v_target_group
    from public.comparison_groups comparison_group
    where comparison_group.code = v_target_garment.comparison_group_code
      and comparison_group.is_active;

    if not v_reference_group.is_auto_comparable
      or not v_target_group.is_auto_comparable then
      v_reason := 'comparison_group_not_auto_comparable';
    end if;
  end if;

  if v_reason is null then
    select policy.*
    into v_reference_policy
    from public.comparison_policies policy
    where policy.comparison_group_code = v_reference_group.code
      and policy.policy_version = v_comparison_policy_version
      and policy.is_active
    order by policy.code
    limit 1;
    if not found then
      v_reason := 'comparison_policy_version_missing';
    end if;
  end if;

  if v_reason is null then
    select policy.*
    into v_target_policy
    from public.comparison_policies policy
    where policy.comparison_group_code = v_target_group.code
      and policy.policy_version = v_comparison_policy_version
      and policy.is_active
    order by policy.code
    limit 1;
    if not found then
      v_reason := 'comparison_policy_version_missing';
    end if;
  end if;

  if v_reason is null then
    v_same_group := v_reference_group.code = v_target_group.code;

    if not v_same_group then
      select compatibility_rule.*
      into v_pair_rule
      from fitmatch_taxonomy.comparison_compatibility_rules
        compatibility_rule
      where compatibility_rule.policy_version =
          v_compatibility_rule_version
        and (
          (
            compatibility_rule.from_family_code = v_reference_group.code
            and compatibility_rule.to_family_code = v_target_group.code
          )
          or (
            not compatibility_rule.directional
            and compatibility_rule.from_family_code = v_target_group.code
            and compatibility_rule.to_family_code = v_reference_group.code
          )
        )
      order by
        (compatibility_rule.from_family_code = v_reference_group.code
          and compatibility_rule.to_family_code = v_target_group.code) desc,
        compatibility_rule.from_family_code,
        compatibility_rule.to_family_code
      limit 1;
      v_pair_rule_found := found;

      if not v_pair_rule_found then
        v_reason := 'comparison_group_incompatible';
      elsif not v_pair_rule.allowed then
        v_reason := 'compatibility_rule_denied';
      elsif coalesce(p_allow_extended, false)
        and not v_pair_rule.fallback_allowed then
        v_reason := 'compatibility_fallback_not_allowed';
      end if;
    elsif (
      v_reference_policy.cross_type_mode = 'same_type_only'
      or v_target_policy.cross_type_mode = 'same_type_only'
    ) and v_reference_garment.code <> v_target_garment.code then
      v_reason := 'garment_type_incompatible';
    end if;
  end if;

  if v_reason is null and not fitmatch_catalog.runtime_genders_are_compatible(
    p_reference_gender,
    p_target_gender,
    v_target_group.code
  ) then
    v_reason := 'gender_incompatible';
  end if;

  if v_reason is null then
    v_length_mismatch := (
      v_reference_garment.requires_sleeve_class
      or v_reference_garment.requires_pants_length
      or v_target_garment.requires_sleeve_class
      or v_target_garment.requires_pants_length
    ) and v_reference_length is distinct from v_target_length;
    v_body_mismatch := (
      v_reference_garment.requires_body_length
      or v_target_garment.requires_body_length
    ) and v_reference_body_length is distinct from v_target_body_length;

    if v_pair_rule_found then
      if (v_length_mismatch or v_body_mismatch)
        and v_pair_rule.length_match_required
        and not coalesce(p_allow_extended, false) then
        v_reason := case
          when v_body_mismatch then 'required_body_axis_mismatch'
          else 'required_length_axis_mismatch'
        end;
      elsif v_length_mismatch or v_body_mismatch then
        v_excluded := v_pair_rule.length_mismatch_excluded_measurements;
      end if;
    else
      if v_length_mismatch and not coalesce(p_allow_extended, false) then
        v_reason := 'required_length_axis_mismatch';
      elsif v_body_mismatch and not coalesce(p_allow_extended, false) then
        v_reason := 'required_body_axis_mismatch';
      elsif v_length_mismatch then
        if v_reference_garment.requires_sleeve_class then
          v_excluded := array_append(v_excluded, 'sleeve_length');
        elsif v_reference_garment.requires_pants_length then
          v_excluded := array_append(v_excluded, 'total_length');
          v_excluded := array_append(v_excluded, 'hem');
        end if;
      end if;
      if v_reason is null and v_body_mismatch
        and not ('total_length' = any(v_excluded)) then
        v_excluded := array_append(v_excluded, 'total_length');
      end if;
    end if;
  end if;

  if v_reason is null then
    select count(distinct measurement_policy.dimension_code),
      count(distinct measurement_policy.dimension_code) filter (
        where measurement_policy.required_group_code =
          v_reference_policy.required_measurement_group_code
      ),
      count(distinct measurement_policy.dimension_code) filter (
        where measurement_policy.required_group_code =
          v_target_policy.required_measurement_group_code
      ),
      coalesce(max(measurement_policy.required_group_min_dimensions)
        filter (
          where measurement_policy.required_group_code =
            v_reference_policy.required_measurement_group_code
        ), 0),
      coalesce(max(measurement_policy.required_group_min_dimensions)
        filter (
          where measurement_policy.required_group_code =
            v_target_policy.required_measurement_group_code
        ), 0),
      coalesce(
        jsonb_agg(distinct measurement_policy.dimension_code),
        '[]'::jsonb
      ),
      coalesce(jsonb_agg(distinct measurement_policy.dimension_code)
        filter (
          where measurement_policy.required_group_code in (
            v_reference_policy.required_measurement_group_code,
            v_target_policy.required_measurement_group_code
          )
        ), '[]'::jsonb)
    into v_measurement_count,
      v_reference_required_group_count,
      v_target_required_group_count,
      v_reference_required_group_min,
      v_target_required_group_min,
      v_measurement_dimensions,
      v_required_any_measurements
    from public.app_category_measurement_policies measurement_policy
    join public.app_categories category
      on category.id = measurement_policy.app_category_id
    where category.code = v_reference_category
      and category.depth = 0
      and category.is_active
      and measurement_policy.policy_version = v_measurement_policy_version
      and measurement_policy.is_active
      and measurement_policy.is_comparable;

    if v_measurement_count = 0 then
      v_reason := 'measurement_policy_version_missing';
    else
      v_measurement_policy_versions :=
        jsonb_build_array(v_measurement_policy_version);

      select coalesce(
        jsonb_object_agg(weighted.dimension_code, weighted.weight),
        '{}'::jsonb
      )
      into v_measurement_weights
      from (
        select measurement_policy.dimension_code,
          max(measurement_policy.weight) as weight
        from public.app_category_measurement_policies measurement_policy
        join public.app_categories category
          on category.id = measurement_policy.app_category_id
        where category.code = v_reference_category
          and category.depth = 0
          and category.is_active
          and measurement_policy.policy_version =
            v_measurement_policy_version
          and measurement_policy.is_active
          and measurement_policy.is_comparable
        group by measurement_policy.dimension_code
      ) weighted;
    end if;
  end if;

  if v_reason is null then
    v_minimum_common_measurements := greatest(
      v_reference_policy.min_comparable_dimensions,
      v_target_policy.min_comparable_dimensions,
      case when v_pair_rule_found
        then v_pair_rule.minimum_common_measurements else 0 end
    );
    v_minimum_required_any := case
      when v_pair_rule_found then v_pair_rule.minimum_required_any
      else greatest(
        v_reference_required_group_min,
        v_target_required_group_min
      )
    end;

    if v_pair_rule_found
      and cardinality(v_pair_rule.required_measurements) > 0 then
      v_required_measurements := to_jsonb(v_pair_rule.required_measurements);
    end if;
    if v_pair_rule_found
      and cardinality(v_pair_rule.required_any_measurements) > 0 then
      v_required_any_measurements :=
        to_jsonb(v_pair_rule.required_any_measurements);
    end if;
    if v_pair_rule_found
      and v_pair_rule.measurement_weights <> '{}'::jsonb then
      v_measurement_weights := v_pair_rule.measurement_weights;
    end if;

    select count(*)
    into v_usable_measurement_count
    from jsonb_array_elements_text(v_measurement_dimensions) dimension
    where not (dimension.value = any(v_excluded));

    select count(*)
    into v_required_any_available
    from jsonb_array_elements_text(v_required_any_measurements) required_any
    where v_measurement_dimensions ? required_any.value
      and not (required_any.value = any(v_excluded));

    if v_usable_measurement_count < v_minimum_common_measurements then
      v_reason := 'measurement_policy_incomplete';
    elsif exists (
      select 1
      from jsonb_array_elements_text(v_required_measurements) required
      where not (v_measurement_dimensions ? required.value)
        or required.value = any(v_excluded)
    ) then
      v_reason := 'required_measurement_missing';
    elsif v_minimum_required_any > 0
      and v_required_any_available < v_minimum_required_any then
      v_reason := 'required_any_measurement_incomplete';
    elsif v_reference_policy.required_measurement_group_code is not null
      and v_reference_required_group_count
        < v_reference_required_group_min then
      v_reason := 'required_measurement_group_incomplete';
    elsif v_target_policy.required_measurement_group_code is not null
      and v_target_required_group_count < v_target_required_group_min then
      v_reason := 'required_measurement_group_incomplete';
    end if;
  end if;

  if v_reason is not null then
    return jsonb_build_object(
      'allowed', false,
      'level', 'incompatible',
      'reason', v_reason,
      'release_id', v_release_id,
      'comparison_policy_version', v_comparison_policy_version,
      'compatibility_rule_version', v_compatibility_rule_version,
      'measurement_policy_version', v_measurement_policy_version,
      'reference_tuple_validation', v_reference_validation,
      'target_tuple_validation', v_target_validation,
      'excluded_measurements', to_jsonb(v_excluded),
      'minimum_common_measurements', v_minimum_common_measurements,
      'required_measurements', v_required_measurements,
      'required_any_measurements', v_required_any_measurements,
      'minimum_required_any', v_minimum_required_any,
      'measurement_weights', v_measurement_weights,
      'measurement_policy_dimensions', v_measurement_dimensions,
      'measurement_policy_versions', v_measurement_policy_versions,
      'extended_requested', p_allow_extended,
      'policy_version', 'classification-comparison-v4'
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'level', case
      when (v_length_mismatch or v_body_mismatch)
        and (
          not v_pair_rule_found
          or v_pair_rule.length_match_required
        ) then 'extended'
      else 'direct'
    end,
    'reason', null,
    'release_id', v_release_id,
    'comparison_policy_version', v_comparison_policy_version,
    'compatibility_rule_version', v_compatibility_rule_version,
    'measurement_policy_version', v_measurement_policy_version,
    'reference_category', v_reference_category,
    'target_category', v_target_category,
    'reference_garment_type', v_reference_garment.code,
    'target_garment_type', v_target_garment.code,
    'reference_family', v_reference_garment.comparison_group_code,
    'target_family', v_target_garment.comparison_group_code,
    'reference_detail', v_reference_detail,
    'target_detail', v_target_detail,
    'reference_length', v_reference_length,
    'target_length', v_target_length,
    'reference_body_length', v_reference_body_length,
    'target_body_length', v_target_body_length,
    'length_mismatch', v_length_mismatch,
    'body_length_mismatch', v_body_mismatch,
    'excluded_measurements', to_jsonb(v_excluded),
    'minimum_common_measurements', v_minimum_common_measurements,
    'required_measurements', v_required_measurements,
    'required_any_measurements', v_required_any_measurements,
    'minimum_required_any', v_minimum_required_any,
    'measurement_weights', v_measurement_weights,
    'reference_required_measurement_group_code',
      v_reference_policy.required_measurement_group_code,
    'target_required_measurement_group_code',
      v_target_policy.required_measurement_group_code,
    'measurement_policy_dimensions', v_measurement_dimensions,
    'measurement_policy_versions', v_measurement_policy_versions,
    'compatibility_rule', case when v_pair_rule_found then
      jsonb_build_object(
        'allowed', v_pair_rule.allowed,
        'fallback_allowed', v_pair_rule.fallback_allowed,
        'length_match_required', v_pair_rule.length_match_required,
        'length_mismatch_excluded_measurements',
          to_jsonb(v_pair_rule.length_mismatch_excluded_measurements),
        'minimum_common_measurements',
          v_pair_rule.minimum_common_measurements,
        'required_measurements', to_jsonb(v_pair_rule.required_measurements),
        'required_any_measurements',
          to_jsonb(v_pair_rule.required_any_measurements),
        'minimum_required_any', v_pair_rule.minimum_required_any,
        'measurement_weights', v_pair_rule.measurement_weights,
        'directional', v_pair_rule.directional,
        'policy_version', v_pair_rule.policy_version
      ) else null end,
    'reference_tuple_validation', v_reference_validation,
    'target_tuple_validation', v_target_validation,
    'extended_requested', p_allow_extended,
    'policy_version', 'classification-comparison-v4'
  );
end $$;

revoke all on function
  fitmatch_catalog.runtime_validate_classification_tuple_v1(
    text, text, text, text, text, text
  ) from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    text, text, text, text, jsonb, uuid
  ) from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_record_product_classification_v2(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    text, text, text, text, text, text,
    text, text, text, text, text, text,
    text, text, boolean, uuid
  ) from public, anon, authenticated;

grant execute on function
  fitmatch_catalog.runtime_validate_classification_tuple_v1(
    text, text, text, text, text, text
  ) to service_role;
grant execute on function
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    text, text, text, text, jsonb, uuid
  ) to service_role;
grant execute on function
  fitmatch_catalog.runtime_record_product_classification_v2(uuid, jsonb)
  to service_role;
grant execute on function
  fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    text, text, text, text, text, text,
    text, text, text, text, text, text,
    text, text, boolean, uuid
  ) to service_role;

comment on function
  fitmatch_catalog.runtime_validate_classification_tuple_v1(
    text, text, text, text, text, text
  ) is
  'Final candidate structural tuple contract. Authority conflicts are intentionally outside this validator.';
comment on function
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    text, text, text, text, jsonb, uuid
  ) is
  'Service-role shadow resolver. No existing runtime or public RPC calls this function in Phase 1B-1.';
comment on function
  fitmatch_catalog.runtime_record_product_classification_v2(uuid, jsonb) is
  'Final candidate append/supersede recorder with garment type support; not called by production in Phase 1B-1.';
comment on function
  fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    text, text, text, text, text, text,
    text, text, text, text, text, text,
    text, text, boolean, uuid
  ) is
  'Service-role shadow comparison evaluator pinned to a release runtime policy contract. Public candidate/comparison RPCs remain on v3.';

commit;
