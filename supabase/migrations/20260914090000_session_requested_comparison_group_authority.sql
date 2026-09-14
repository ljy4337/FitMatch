-- Session-only comparison-group authority for globally unmapped products.
-- Prepared migration: applying this file is a separate Production operation.

create or replace function fitmatch_vnext.comparison_target_context(
  p_target_product_id uuid,
  p_target_variant_id uuid,
  p_requested_group_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  product_row fitmatch_vnext.products%rowtype;
  requested_code text := nullif(upper(btrim(p_requested_group_code)), '');
  grouped jsonb;
  resolved jsonb;
  effective_value jsonb;
  garment_row fitmatch_vnext.garment_types%rowtype;
  policy_row fitmatch_vnext.comparison_policies%rowtype;
  unit_value jsonb;
  source_value text;
  authority_version constant text := 'fitmatch-vnext-session-group-context-v1';
  authority_fingerprint text;
  group_value jsonb;
begin
  select * into product_row
  from fitmatch_vnext.products p
  where p.id = p_target_product_id;
  if not found then raise exception 'Target product not found'; end if;

  if p_target_variant_id is not null and not exists (
    select 1 from fitmatch_vnext.product_variants pv
    where pv.id = p_target_variant_id and pv.product_id = product_row.id
  ) then
    raise exception 'Target variant hierarchy mismatch';
  end if;

  resolved := fitmatch_vnext.product_comparison_group(product_row.id);
  if resolved->>'status' in ('EXCLUDED', 'NOT_APPLICABLE') then
    raise exception 'Target product is not applicable for comparison';
  end if;
  if requested_code is not null and resolved->>'group_code' is not null then
    raise exception 'Requested comparison group is allowed only when retailer mapping is missing';
  end if;

  grouped := fitmatch_vnext.comparison_group_tuple(
    product_row.id, requested_code
  );
  if grouped is null then
    return jsonb_build_object(
      'status', 'COMPARISON_GROUP_REQUIRED',
      'effective_classification',
        fitmatch_vnext.effective_target_classification(product_row.id),
      'target_comparison_group', null
    );
  end if;
  if requested_code is not null
     and requested_code not in ('A','B','C','D','E','F','G') then
    raise exception 'Invalid requested comparison group';
  end if;

  select * into garment_row
  from fitmatch_vnext.garment_types gt
  where gt.garment_type_code = grouped->>'garment_type_code'
    and gt.category_code = grouped->>'category_code'
    and gt.is_active;
  if not found or nullif(btrim(garment_row.comparison_policy_code), '') is null then
    raise exception 'Active comparison group policy is missing';
  end if;

  select * into policy_row
  from fitmatch_vnext.comparison_policies cp
  where cp.policy_code = garment_row.comparison_policy_code
    and cp.is_active;
  if not found then raise exception 'Active comparison policy is missing'; end if;

  unit_value := fitmatch_vnext.product_comparison_unit_decision(product_row.id);
  if not coalesce((unit_value->>'eligible')::boolean, false) then
    raise exception 'Target product structure is not comparable';
  end if;

  source_value := case when requested_code is null
    then coalesce(resolved->>'source', 'RETAILER_CATEGORY')
    else 'SESSION_USER_SELECTED' end;
  authority_fingerprint := encode(extensions.digest(concat_ws('|',
    product_row.id::text,
    coalesce(p_target_variant_id::text, 'none'),
    grouped->>'group_code',
    source_value,
    garment_row.comparison_policy_code,
    policy_row.policy_version,
    policy_row.policy_checksum,
    coalesce(product_row.input_fingerprint, 'none'),
    coalesce(product_row.evidence_fingerprint, 'none'),
    authority_version
  ), 'sha256'), 'hex');

  group_value := jsonb_build_object(
    'status', 'COMPARABLE',
    'group_code', grouped->>'group_code',
    'display_name', case grouped->>'group_code'
      when 'A' then '상의' when 'B' then '아우터' when 'C' then '바지'
      when 'D' then '스커트' when 'E' then '원피스·한벌옷'
      when 'F' then '이너웨어' when 'G' then '홈웨어·파자마' end,
    'source', source_value,
    'category_code', garment_row.category_code,
    'garment_type_code', garment_row.garment_type_code,
    'comparison_policy_code', garment_row.comparison_policy_code,
    'policy_version', policy_row.policy_version,
    'policy_checksum', policy_row.policy_checksum,
    'authority_version', authority_version,
    'authority_fingerprint', authority_fingerprint
  );

  if requested_code is null then
    effective_value := fitmatch_vnext.effective_target_classification(
      product_row.id
    );
  else
    effective_value := jsonb_build_object(
      'product_id', product_row.id,
      'target_variant_id', p_target_variant_id,
      'state', 'SESSION_GROUP_CONFIRMED',
      'classification_status', 'CONFIRMED',
      'effective_source', source_value,
      'category_code', garment_row.category_code,
      'garment_type_code', garment_row.garment_type_code,
      'audience_code', case
        when product_row.audience_code in ('MEN','WOMEN','UNISEX','KIDS','BABY')
          then product_row.audience_code else 'UNKNOWN' end,
      'sleeve_length_code', null,
      'lower_length_code', null,
      'body_length_code', null,
      'comparison_policy_code', garment_row.comparison_policy_code,
      'comparison_group_code', grouped->>'group_code',
      'comparison_group_source', source_value,
      'comparison_group_policy_version', policy_row.policy_version,
      'requested_comparison_group_code', requested_code,
      'product_structure_code', coalesce(
        nullif(product_row.product_structure_code, ''), 'UNKNOWN'
      ),
      'override_revision', 0,
      'effective_authority_fingerprint', authority_fingerprint,
      'effective_contract_version', authority_version
    );
  end if;

  return jsonb_build_object(
    'status', 'READY',
    'target_product_id', product_row.id,
    'target_variant_id', p_target_variant_id,
    'effective_classification', effective_value,
    'target_comparison_group', group_value,
    'comparison_unit', unit_value
  );
end
$$;

create or replace function fitmatch_vnext.canonical_measurements_for_session_group(
  p_product_size_id uuid,
  p_effective_classification jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_effective_classification->>'effective_source'
     is distinct from 'SESSION_USER_SELECTED' then
    raise exception 'Session comparison-group measurement context required';
  end if;

  -- The existing CATEGORY_GROUP resolver already performs the canonical
  -- source-alias, unit, and semantic-conflict checks. Only its transient
  -- dispatch source is adapted; the returned/session authority stays intact.
  return fitmatch_vnext.canonical_measurements_for_size_with_context(
    p_product_size_id,
    p_effective_classification || jsonb_build_object(
      'effective_source', 'CATEGORY_GROUP'
    )
  ) || jsonb_build_object(
    'classification_context_source', 'SESSION_USER_SELECTED'
  );
end
$$;

create or replace function fitmatch_vnext.authorize_comparison_with_context_v1(
  p_reference_closet_item_id uuid,
  p_target_product_id uuid,
  p_target_product_size_id uuid,
  p_manual_explicit boolean,
  p_effective_classification jsonb,
  p_requested_group_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  ref fitmatch_vnext.closet_items%rowtype;
  target fitmatch_vnext.products%rowtype;
  ref_gt fitmatch_vnext.garment_types%rowtype;
  target_gt fitmatch_vnext.garment_types%rowtype;
  policy fitmatch_vnext.comparison_policies%rowtype;
  context_value jsonb;
  effective_value jsonb;
  canonical_value jsonb;
  evidence_value jsonb;
  unit_value jsonb;
  target_variant_id uuid;
  ref_domain text;
  target_domain text;
  audience_ok boolean;
  common_count integer := 0;
  reason_code_value text := 'INVALID_AUTHORITY';
  reason_value text := 'Invalid comparison authority';
  decision_value text := 'BLOCKED';
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  <<evaluate_pair>>
  begin
    select * into ref from fitmatch_vnext.closet_items ci
    where ci.id = p_reference_closet_item_id
      and ci.user_id = caller_id and ci.deleted_at is null;
    if not found then
      reason_value := 'Reference is missing or not owned'; exit evaluate_pair;
    end if;
    select * into target from fitmatch_vnext.products p
    where p.id = p_target_product_id;
    if not found then reason_value := 'Target product not found'; exit evaluate_pair; end if;

    select pv.id into target_variant_id
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where ps.id = p_target_product_size_id and pv.product_id = target.id;
    if not found then
      reason_code_value := 'NO_ELIGIBLE_TARGET_SIZE';
      reason_value := 'Target size hierarchy mismatch'; exit evaluate_pair;
    end if;
    context_value := fitmatch_vnext.comparison_target_context(
      target.id, target_variant_id, p_requested_group_code
    );
    effective_value := context_value->'effective_classification';
    if p_effective_classification is distinct from effective_value then
      reason_value := 'Stale or invalid effective classification context';
      exit evaluate_pair;
    end if;
    if effective_value->>'classification_status' is distinct from 'CONFIRMED' then
      reason_code_value := 'CLASSIFICATION_REQUIRED';
      reason_value := 'Target effective classification is not CONFIRMED';
      exit evaluate_pair;
    end if;
    unit_value := fitmatch_vnext.product_comparison_unit_decision(target.id);
    if not coalesce((unit_value->>'eligible')::boolean, false) then
      reason_code_value := 'STRUCTURALLY_NOT_COMPARABLE';
      reason_value := unit_value->>'reason'; exit evaluate_pair;
    end if;
    select * into ref_gt from fitmatch_vnext.garment_types
    where garment_type_code = ref.garment_type_code and is_active;
    select * into target_gt from fitmatch_vnext.garment_types
    where garment_type_code = effective_value->>'garment_type_code' and is_active;
    if ref_gt.garment_type_code is null or target_gt.garment_type_code is null then
      reason_value := 'Unsupported garment'; exit evaluate_pair;
    end if;
    if fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then
      reason_code_value := 'INCOMPATIBLE_BODY_REGION';
      reason_value := 'Reference comparison group does not match requested group';
      exit evaluate_pair;
    end if;
    select * into policy from fitmatch_vnext.comparison_policies
    where policy_code = target_gt.comparison_policy_code and is_active;
    if not found then reason_value := 'Comparison policy unavailable'; exit evaluate_pair; end if;

    ref_domain := fitmatch_vnext.comparison_domain_20260908(
      ref_gt.comparison_policy_code
    );
    target_domain := fitmatch_vnext.comparison_domain_20260908(
      target_gt.comparison_policy_code
    );
    if ref_gt.comparison_policy_code is distinct from target_gt.comparison_policy_code
       and not (ref_domain = target_domain and ref_domain in ('UPPER_BODY','LOWER_BODY')) then
      reason_code_value := 'INCOMPATIBLE_BODY_REGION';
      reason_value := 'Comparison domains are incompatible'; exit evaluate_pair;
    end if;
    audience_ok := case policy.audience_policy_code
      when 'IGNORE' then true
      when 'ADULT_ANY' then ref.audience_code in ('MEN','WOMEN','UNISEX')
        and effective_value->>'audience_code' in ('MEN','WOMEN','UNISEX')
      when 'SAME_ONLY' then ref.audience_code = effective_value->>'audience_code'
      else ref.audience_code = effective_value->>'audience_code'
        or ref.audience_code = 'UNISEX'
        or effective_value->>'audience_code' = 'UNISEX' end;
    if not coalesce(audience_ok, false) then
      reason_code_value := 'INCOMPATIBLE_AUDIENCE';
      reason_value := 'Audience is incompatible'; exit evaluate_pair;
    end if;

    canonical_value := fitmatch_vnext.canonical_measurements_for_session_group(
      p_target_product_size_id, effective_value
    );
    if coalesce((canonical_value->>'semantic_conflict_count')::integer, 0) > 0 then
      reason_value := 'Canonical measurement semantic conflict'; exit evaluate_pair;
    end if;
    evidence_value := fitmatch_vnext.comparison_evidence_20260908(
      ref.id, policy.policy_code, canonical_value
    );
    common_count := jsonb_array_length(evidence_value);
    if common_count < 1 then
      decision_value := 'MEASUREMENTS_REQUIRED';
      reason_code_value := 'NO_COMMON_MEASUREMENTS';
      reason_value := 'No usable common canonical policy measurement';
      exit evaluate_pair;
    end if;
    if not coalesce(p_manual_explicit, false) then
      reason_code_value := 'NO_AUTOMATIC_REFERENCE';
      reason_value := 'Explicit user selection is required'; exit evaluate_pair;
    end if;
    decision_value := 'MANUAL_EXTENDED';
    reason_code_value := 'USER_SELECTED_REFERENCE';
    reason_value := 'User-selected comparison with server-validated session group';
  end evaluate_pair;

  return jsonb_build_object(
    'decision', decision_value,
    'allowed', decision_value = 'MANUAL_EXTENDED',
    'mode', case when decision_value = 'MANUAL_EXTENDED'
      then decision_value else 'NONE' end,
    'reason_code', reason_code_value,
    'reason', reason_value,
    'reference_measurement_domain', ref_domain,
    'target_measurement_domain', target_domain,
    'excluded_measurement_codes', '[]'::jsonb,
    'excluded_measurement_reasons', '[]'::jsonb,
    'required_measurement_codes', '[]'::jsonb,
    'minimum_common', 1,
    'common_measurement_count', common_count,
    'policy_code', policy.policy_code,
    'policy_version', policy.policy_version,
    'policy_checksum', policy.policy_checksum,
    'classification_source', effective_value->>'effective_source',
    'effective_authority_fingerprint',
      effective_value->>'effective_authority_fingerprint',
    'override_revision', effective_value->'override_revision',
    'target_comparison_group', context_value->'target_comparison_group',
    'authorization_version', 'fitmatch-vnext-session-group-authorization-v1'
  );
end
$$;

create or replace function fitmatch_vnext.authorize_comparison_with_context(
  p_reference_closet_item_id uuid,
  p_target_product_id uuid,
  p_target_product_size_id uuid,
  p_manual_explicit boolean,
  p_effective_classification jsonb,
  p_requested_group_code text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select fitmatch_vnext.authorize_comparison_with_context_v1(
    p_reference_closet_item_id, p_target_product_id,
    p_target_product_size_id, p_manual_explicit,
    p_effective_classification, p_requested_group_code
  )
$$;

create or replace function fitmatch_vnext.eligible_candidate_sizes(
  p_reference_closet_item_id uuid,
  p_target_product_id uuid,
  p_target_variant_id uuid,
  p_manual_explicit boolean,
  p_requested_group_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  reference_row fitmatch_vnext.closet_items%rowtype;
  context_value jsonb;
  effective_value jsonb;
  size_row record;
  canonical_value jsonb;
  authorization_value jsonb;
  comparison_measurements_value jsonb;
  candidates_value jsonb := '[]'::jsonb;
  fingerprint_candidates_value jsonb := '[]'::jsonb;
  candidate_value jsonb;
  semantic_conflict_count_value integer := 0;
  rejected_reason_code_value text;
  authority_version_value constant text :=
    'fitmatch-vnext-session-group-candidates-v1';
  authority_fingerprint_value text;
begin
  if p_requested_group_code is null then
    return fitmatch_vnext.eligible_candidate_sizes(
      p_reference_closet_item_id, p_target_product_id,
      p_target_variant_id, p_manual_explicit
    );
  end if;
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into reference_row from fitmatch_vnext.closet_items ci
  where ci.id = p_reference_closet_item_id
    and ci.user_id = caller_id and ci.deleted_at is null;
  if not found then raise exception 'Reference is missing or not owned'; end if;

  context_value := fitmatch_vnext.comparison_target_context(
    p_target_product_id, p_target_variant_id, p_requested_group_code
  );
  effective_value := context_value->'effective_classification';
  if effective_value->>'classification_status' is distinct from 'CONFIRMED' then
    return jsonb_build_object(
      'allowed', false, 'decision', 'BLOCKED',
      'reason_code', 'CLASSIFICATION_REQUIRED',
      'reason', 'Target comparison context is not confirmed',
      'authorized_candidate_product_size_ids', '[]'::jsonb,
      'candidates', '[]'::jsonb,
      'target_comparison_group', context_value->'target_comparison_group'
    );
  end if;

  for size_row in
    select ps.id as product_size_id, ps.size_label, ps.sort_order,
      availability.availability_status,
      availability.observed_at as availability_observed_at,
      availability.valid_until as availability_valid_until,
      availability.evidence_fingerprint as availability_evidence_fingerprint
    from fitmatch_vnext.product_sizes ps
    left join lateral (
      select o.availability_status, o.observed_at, o.valid_until,
        o.evidence_fingerprint
      from fitmatch_vnext.size_availability_observations o
      where o.product_size_id = ps.id
      order by o.observed_at desc, o.id desc limit 1
    ) availability on true
    where ps.variant_id = p_target_variant_id
    order by ps.sort_order, ps.id
  loop
    canonical_value := fitmatch_vnext.canonical_measurements_for_session_group(
      size_row.product_size_id, effective_value
    );
    if coalesce((canonical_value->>'semantic_conflict_count')::integer, 0) > 0 then
      semantic_conflict_count_value := semantic_conflict_count_value + 1;
      continue;
    end if;
    authorization_value := fitmatch_vnext.authorize_comparison_with_context(
      reference_row.id, p_target_product_id, size_row.product_size_id,
      p_manual_explicit, effective_value, p_requested_group_code
    );
    if not coalesce((authorization_value->>'allowed')::boolean, false) then
      rejected_reason_code_value := coalesce(
        rejected_reason_code_value, authorization_value->>'reason_code'
      );
      continue;
    end if;
    comparison_measurements_value := fitmatch_vnext.comparison_evidence_20260908(
      reference_row.id, authorization_value->>'policy_code', canonical_value
    );
    if jsonb_array_length(comparison_measurements_value) < 1 then continue; end if;
    candidate_value := jsonb_build_object(
      'product_size_id', size_row.product_size_id,
      'size_label', size_row.size_label,
      'availability', jsonb_build_object(
        'status', size_row.availability_status,
        'observed_at', size_row.availability_observed_at,
        'valid_until', size_row.availability_valid_until,
        'evidence_fingerprint', size_row.availability_evidence_fingerprint
      ),
      'canonical_measurements', canonical_value,
      'comparison_measurements', comparison_measurements_value,
      'authorization', authorization_value
    );
    candidates_value := candidates_value || jsonb_build_array(candidate_value);
    fingerprint_candidates_value := fingerprint_candidates_value
      || jsonb_build_array(candidate_value - 'availability');
  end loop;

  authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
    reference_row.id::text, p_target_product_id::text,
    p_target_variant_id::text, p_manual_explicit::text,
    effective_value->>'effective_authority_fingerprint',
    fingerprint_candidates_value::text, authority_version_value
  ), 'sha256'), 'hex');

  return jsonb_build_object(
    'allowed', jsonb_array_length(candidates_value) > 0,
    'decision', case when jsonb_array_length(candidates_value) > 0
      then 'MANUAL_EXTENDED' else 'BLOCKED' end,
    'reason_code', case when jsonb_array_length(candidates_value) > 0
      then 'USER_SELECTED_REFERENCE'
      else coalesce(rejected_reason_code_value, 'NO_ELIGIBLE_TARGET_SIZE') end,
    'mode', case when jsonb_array_length(candidates_value) > 0
      then 'MANUAL_EXTENDED' else 'NONE' end,
    'reason', case when jsonb_array_length(candidates_value) > 0
      then 'Database-generated eligible candidate set'
      when semantic_conflict_count_value > 0
      then 'Canonical measurement semantic conflict'
      else 'No size satisfies comparison authorization and measurement minimums' end,
    'reference_closet_item_id', reference_row.id,
    'target_product_id', p_target_product_id,
    'target_variant_id', p_target_variant_id,
    'manual_explicit', p_manual_explicit,
    'classification_source', effective_value->>'effective_source',
    'effective_authority_fingerprint',
      effective_value->>'effective_authority_fingerprint',
    'override_revision', effective_value->'override_revision',
    'authorized_candidate_product_size_ids', coalesce((
      select jsonb_agg(candidate->'product_size_id')
      from jsonb_array_elements(candidates_value) candidate
    ), '[]'::jsonb),
    'candidates', candidates_value,
    'target_comparison_group', context_value->'target_comparison_group',
    'candidate_authority_fingerprint', authority_fingerprint_value,
    'candidate_authority_version', authority_version_value,
    'diagnostics', jsonb_build_object(
      'semantic_conflict_count', semantic_conflict_count_value,
      'inventory_ignored_for_eligibility', true
    )
  );
end
$$;

create or replace function fitmatch_vnext.find_reference_candidates(
  p_target_product_id uuid,
  p_target_variant_id uuid,
  p_requested_group_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  context_value jsonb;
  target_group_code text;
  closet_row fitmatch_vnext.closet_items%rowtype;
  closet_group jsonb;
  eligible_value jsonb;
  item_value jsonb;
  candidates_value jsonb := '[]'::jsonb;
  blocked_value jsonb := '[]'::jsonb;
begin
  if p_requested_group_code is null then
    return fitmatch_vnext.find_reference_candidates(
      p_target_product_id, p_target_variant_id
    );
  end if;
  if caller_id is null then raise exception 'Authentication required'; end if;
  context_value := fitmatch_vnext.comparison_target_context(
    p_target_product_id, p_target_variant_id, p_requested_group_code
  );
  target_group_code := context_value->'target_comparison_group'->>'group_code';
  if target_group_code is null then
    raise exception 'Requested comparison group was not validated';
  end if;

  for closet_row in
    select * from fitmatch_vnext.closet_items ci
    where ci.user_id = caller_id and ci.deleted_at is null
    order by ci.updated_at desc, ci.id
  loop
    closet_group := fitmatch_vnext.closet_comparison_group(closet_row.id);
    if closet_group->>'group_code' is distinct from target_group_code then
      item_value := jsonb_build_object(
        'closet_item_id', closet_row.id,
        'item_name', closet_row.item_name,
        'size_label', closet_row.size_label,
        'product_id', closet_row.product_id,
        'variant_id', closet_row.product_variant_id,
        'product_size_id', closet_row.product_size_id,
        'is_current_reference', closet_row.is_reference,
        'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
        'manual_explicit_required', true,
        'reason_code', 'INCOMPATIBLE_BODY_REGION',
        'reason', 'Reference comparison group does not match requested group',
        'common_measurement_count', 0,
        'eligible_product_size_ids', '[]'::jsonb,
        'comparison_group', closet_group,
        'same_comparison_group', false
      );
      blocked_value := blocked_value || jsonb_build_array(item_value);
      continue;
    end if;

    eligible_value := fitmatch_vnext.eligible_candidate_sizes(
      closet_row.id, p_target_product_id, p_target_variant_id,
      true, p_requested_group_code
    );
    item_value := jsonb_build_object(
      'closet_item_id', closet_row.id,
      'item_name', closet_row.item_name,
      'size_label', closet_row.size_label,
      'product_id', closet_row.product_id,
      'variant_id', closet_row.product_variant_id,
      'product_size_id', closet_row.product_size_id,
      'is_current_reference', closet_row.is_reference,
      'decision', eligible_value->>'decision',
      'allowed', coalesce((eligible_value->>'allowed')::boolean, false),
      'mode', eligible_value->>'mode',
      'manual_explicit_required', true,
      'reason_code', eligible_value->>'reason_code',
      'reason', eligible_value->>'reason',
      'common_measurement_count', case
        when jsonb_array_length(coalesce(eligible_value->'candidates','[]'::jsonb)) > 0
        then jsonb_array_length(coalesce(
          eligible_value->'candidates'->0->'comparison_measurements','[]'::jsonb
        )) else 0 end,
      'eligible_product_size_ids', coalesce(
        eligible_value->'authorized_candidate_product_size_ids','[]'::jsonb
      ),
      'comparison_group', closet_group,
      'same_comparison_group', true
    );
    if coalesce((eligible_value->>'allowed')::boolean, false) then
      candidates_value := candidates_value || jsonb_build_array(item_value);
    else
      blocked_value := blocked_value || jsonb_build_array(item_value);
    end if;
  end loop;

  return jsonb_build_object(
    'target_product_id', p_target_product_id,
    'target_variant_id', p_target_variant_id,
    'effective_classification', context_value->'effective_classification',
    'comparison_group', context_value->'target_comparison_group',
    'target_comparison_group', context_value->'target_comparison_group',
    'candidates', candidates_value,
    'blocked', blocked_value,
    'candidate_count', jsonb_array_length(candidates_value),
    'blocked_count', jsonb_array_length(blocked_value),
    'status', case when jsonb_array_length(candidates_value) > 0
      then 'READY' else 'NO_REFERENCE_CANDIDATE' end,
    'selection_policy', 'SESSION_REQUESTED_GROUP_ONLY',
    'measurements_used_for_candidate_selection', true,
    'reference_candidate_version',
      'fitmatch-vnext-session-group-candidates-v1'
  );
end
$$;

create or replace function public.fitmatch_vnext_find_reference_candidates(
  p_target_product_id uuid,
  p_target_variant_id uuid,
  p_requested_group_code text
)
returns jsonb
language sql
set search_path = ''
as $$
  select fitmatch_vnext.find_reference_candidates(
    p_target_product_id, p_target_variant_id, p_requested_group_code
  )
$$;

create or replace function public.fitmatch_vnext_eligible_candidate_sizes(
  p_reference_closet_item_id uuid,
  p_target_product_id uuid,
  p_target_variant_id uuid,
  p_manual_explicit boolean,
  p_requested_group_code text
)
returns jsonb
language sql
set search_path = ''
as $$
  select fitmatch_vnext.eligible_candidate_sizes(
    p_reference_closet_item_id, p_target_product_id, p_target_variant_id,
    p_manual_explicit, p_requested_group_code
  )
$$;

alter function fitmatch_vnext.begin_comparison(jsonb)
  rename to begin_comparison_legacy_20260914;

create or replace function fitmatch_vnext.begin_comparison(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  requested_code text := nullif(upper(btrim(
    p_request->>'requested_comparison_group_code'
  )), '');
  client_id uuid;
  ref_id uuid;
  target_id uuid;
  target_variant uuid;
  authorization_size uuid;
  manual_explicit boolean;
  request_hash text;
  existing fitmatch_vnext.comparisons%rowtype;
  ref fitmatch_vnext.closet_items%rowtype;
  reference_product fitmatch_vnext.products%rowtype;
  target fitmatch_vnext.products%rowtype;
  context_value jsonb;
  effective_value jsonb;
  candidate_authority jsonb;
  candidates jsonb;
  authz jsonb;
  authorized_ids uuid[];
  authorized_ids_sorted uuid[];
  client_candidate_ids uuid[];
  client_candidate_ids_sorted uuid[];
  comparison_id uuid;
  policy_data jsonb;
  reference_data jsonb;
  target_data jsonb;
begin
  if requested_code is null then
    return fitmatch_vnext.begin_comparison_legacy_20260914(p_request);
  end if;
  if caller_id is null then raise exception 'Authentication required'; end if;
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Request must be a JSON object';
  end if;
  if requested_code not in ('A','B','C','D','E','F','G') then
    raise exception 'Invalid requested comparison group';
  end if;
  if p_request ?| array[
    'garment_type_code','audience_code','category_code','sleeve_length_code',
    'lower_length_code','body_length_code','comparison_policy_code','override_id'
  ] then
    raise exception 'Raw classification authority is not accepted at begin';
  end if;

  client_id := (p_request->>'client_comparison_id')::uuid;
  ref_id := (p_request->>'reference_closet_item_id')::uuid;
  target_id := (p_request->>'target_product_id')::uuid;
  target_variant := (p_request->>'target_variant_id')::uuid;
  authorization_size := nullif(
    btrim(p_request->>'authorization_product_size_id'), ''
  )::uuid;
  manual_explicit := coalesce((p_request->>'manual_explicit')::boolean, false);
  if client_id is null or ref_id is null or target_id is null
     or target_variant is null then
    raise exception 'Comparison identity, reference, target, and variant are required';
  end if;

  request_hash := encode(extensions.digest(p_request::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    caller_id::text || ':' || client_id::text, 0
  ));
  select * into existing from fitmatch_vnext.comparisons
  where user_id = caller_id and client_comparison_id = client_id for update;
  if found then
    if existing.request_payload_hash is distinct from request_hash then
      raise exception 'Idempotency conflict for client_comparison_id';
    end if;
    return jsonb_build_object(
      'comparison_id', existing.id, 'created', false, 'idempotent', true,
      'result_status', existing.result_status,
      'authorized_candidate_product_size_ids',
        existing.target_snapshot->'authorized_candidate_product_size_ids'
    );
  end if;

  select * into ref from fitmatch_vnext.closet_items
  where id = ref_id and user_id = caller_id and deleted_at is null;
  if not found then raise exception 'Reference is missing or not owned'; end if;
  if ref.product_id is not null then
    select * into reference_product from fitmatch_vnext.products
    where id = ref.product_id;
  end if;
  select * into target from fitmatch_vnext.products where id = target_id;
  if not found then raise exception 'Target product not found'; end if;

  context_value := fitmatch_vnext.comparison_target_context(
    target.id, target_variant, requested_code
  );
  effective_value := context_value->'effective_classification';
  if nullif(p_request->>'effective_authority_fingerprint', '')
     is distinct from effective_value->>'effective_authority_fingerprint' then
    raise exception 'Stale requested comparison group authority fingerprint';
  end if;
  if context_value->'target_comparison_group'->>'group_code'
     is distinct from requested_code then
    raise exception 'Requested comparison group authority mismatch';
  end if;

  candidate_authority := fitmatch_vnext.eligible_candidate_sizes(
    ref_id, target_id, target_variant, manual_explicit, requested_code
  );
  if not coalesce((candidate_authority->>'allowed')::boolean, false) then
    raise exception 'Comparison has no eligible candidate sizes: %',
      candidate_authority->>'reason';
  end if;
  if nullif(p_request->>'candidate_authority_fingerprint', '')
     is distinct from candidate_authority->>'candidate_authority_fingerprint' then
    raise exception 'Stale candidate authority fingerprint';
  end if;
  if candidate_authority->'target_comparison_group'->>'group_code'
     is distinct from requested_code then
    raise exception 'Candidate authority comparison group mismatch';
  end if;
  candidates := candidate_authority->'candidates';
  select coalesce(array_agg(value::uuid order by ordinal), '{}'::uuid[])
    into authorized_ids
  from jsonb_array_elements_text(
    candidate_authority->'authorized_candidate_product_size_ids'
  ) with ordinality item(value, ordinal);
  select coalesce(array_agg(id order by id), '{}'::uuid[])
    into authorized_ids_sorted from unnest(authorized_ids) id;
  if cardinality(authorized_ids) = 0 then
    raise exception 'Candidate authority returned an empty set';
  end if;
  if p_request ? 'candidate_product_size_ids' then
    select coalesce(array_agg(value::uuid order by ordinal), '{}'::uuid[])
      into client_candidate_ids
    from jsonb_array_elements_text(p_request->'candidate_product_size_ids')
      with ordinality item(value, ordinal);
    select coalesce(array_agg(id order by id), '{}'::uuid[])
      into client_candidate_ids_sorted from unnest(client_candidate_ids) id;
    if client_candidate_ids_sorted is distinct from authorized_ids_sorted then
      raise exception 'Client candidate sizes do not equal the DB-authorized set';
    end if;
  end if;
  if authorization_size is null then
    authorization_size := authorized_ids[1];
  elsif not authorization_size = any(authorized_ids) then
    raise exception 'authorization_product_size_id is not DB-authorized';
  end if;
  select candidate->'authorization' into authz
  from jsonb_array_elements(candidates) candidate
  where (candidate->>'product_size_id')::uuid = authorization_size limit 1;
  if authz is null or not coalesce((authz->>'allowed')::boolean, false) then
    raise exception 'Selected authorization is invalid';
  end if;

  reference_data := jsonb_build_object(
    'closet_item_id', ref.id,
    'source_code', reference_product.source_code,
    'source_product_key', reference_product.source_product_key,
    'product_id', ref.product_id,
    'variant_id', ref.product_variant_id,
    'product_size_id', ref.product_size_id,
    'item_name', ref.item_name,
    'size_label', ref.size_label,
    'garment_type_code', ref.garment_type_code,
    'audience_code', ref.audience_code,
    'classification_source', ref.classification_source,
    'classification_fingerprint', ref.classification_fingerprint,
    'measurements', coalesce((select jsonb_agg(jsonb_build_object(
      'fitmatch_measurement_code', cm.fitmatch_measurement_code,
      'value', cm.value, 'unit_code', cm.unit_code,
      'value_source', cm.value_source,
      'raw_label_snapshot', cm.raw_label_snapshot
    ) order by cm.fitmatch_measurement_code)
    from fitmatch_vnext.closet_item_measurements cm
    where cm.closet_item_id = ref.id), '[]'::jsonb)
  );
  target_data := jsonb_build_object(
    'product_id', target.id, 'source_code', target.source_code,
    'source_product_key', target.source_product_key,
    'variant_id', target_variant,
    'candidate_product_size_ids', to_jsonb(authorized_ids),
    'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
    'candidate_authority_fingerprint',
      candidate_authority->>'candidate_authority_fingerprint',
    'candidate_authority_version',
      candidate_authority->>'candidate_authority_version',
    'classification_status', effective_value->>'classification_status',
    'classification_source', effective_value->>'effective_source',
    'category_code', effective_value->>'category_code',
    'product_structure_code', target.product_structure_code,
    'garment_type_code', effective_value->>'garment_type_code',
    'audience_code', effective_value->>'audience_code',
    'classification_fingerprint',
      effective_value->>'effective_authority_fingerprint',
    'comparison_group', context_value->'target_comparison_group',
    'candidates', candidates
  );
  select to_jsonb(cp) || jsonb_build_object(
    'metrics', coalesce((select jsonb_agg(jsonb_build_object(
      'metric_mode', cm.metric_mode,
      'fitmatch_measurement_code', cm.fitmatch_measurement_code,
      'source_measurement_code', cm.source_measurement_code,
      'weight', cm.weight, 'requirement_mode', cm.requirement_mode,
      'priority', cm.priority, 'is_active', cm.is_active
    ) order by cm.priority, cm.fitmatch_measurement_code,
      cm.source_measurement_code)
    from fitmatch_vnext.comparison_metrics cm
    where cm.comparison_policy_code = cp.policy_code and cm.is_active),
      '[]'::jsonb)
  ) into policy_data from fitmatch_vnext.comparison_policies cp
  where cp.policy_code = authz->>'policy_code' and cp.is_active;
  if policy_data is null then
    raise exception 'Active policy disappeared during comparison begin';
  end if;

  insert into fitmatch_vnext.comparisons (
    user_id, client_comparison_id, reference_closet_item_id,
    target_product_id, target_variant_id,
    comparison_policy_code_snapshot, comparison_mode,
    reference_source_code_snapshot, target_source_code_snapshot,
    reference_item_name_snapshot, target_product_name_snapshot,
    target_image_url_snapshot, reference_garment_type_snapshot,
    target_garment_type_snapshot, reference_audience_snapshot,
    target_audience_snapshot, reference_sleeve_length_snapshot,
    target_sleeve_length_snapshot, reference_lower_length_snapshot,
    target_lower_length_snapshot, reference_body_length_snapshot,
    target_body_length_snapshot, result_status, engine_version,
    snapshot_schema_version, detail_snapshot, request_payload_hash,
    authorization_mode, excluded_measurement_codes, reference_snapshot,
    target_snapshot, authority_snapshot, policy_snapshot,
    authorization_snapshot, input_snapshot
  ) values (
    caller_id, client_id, ref.id, target.id, target_variant,
    authz->>'policy_code', 'CANONICAL',
    coalesce(reference_product.source_code, ref.source_code_snapshot),
    target.source_code, ref.item_name, target.product_name, target.image_url,
    ref.garment_type_code, effective_value->>'garment_type_code',
    ref.audience_code, effective_value->>'audience_code',
    ref.sleeve_length_code, effective_value->>'sleeve_length_code',
    ref.lower_length_code, effective_value->>'lower_length_code',
    ref.body_length_code, effective_value->>'body_length_code',
    'PENDING', 'pending', 4,
    jsonb_build_object('phase', 'BEGIN'), request_hash,
    authz->>'mode', array(select jsonb_array_elements_text(
      authz->'excluded_measurement_codes'
    )), reference_data, target_data,
    jsonb_build_object(
      'effective_classification_at_begin', effective_value,
      'comparison_group_at_begin', context_value->'target_comparison_group',
      'authority_version',
        context_value->'target_comparison_group'->>'authority_version',
      'authority_fingerprint',
        context_value->'target_comparison_group'->>'authority_fingerprint'
    ),
    policy_data, authz,
    jsonb_build_object(
      'client_request', p_request,
      'candidate_authority_fingerprint',
        candidate_authority->>'candidate_authority_fingerprint',
      'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
      'effective_authority_fingerprint',
        effective_value->>'effective_authority_fingerprint',
      'requested_comparison_group_code', requested_code,
      'began_at', now()
    )
  ) returning id into comparison_id;

  return jsonb_build_object(
    'comparison_id', comparison_id, 'created', true, 'idempotent', false,
    'result_status', 'PENDING', 'authorization', authz,
    'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
    'candidate_authority_fingerprint',
      candidate_authority->>'candidate_authority_fingerprint',
    'effective_authority_fingerprint',
      effective_value->>'effective_authority_fingerprint',
    'target_comparison_group', context_value->'target_comparison_group',
    'snapshot_schema_version', 4
  );
end
$$;

revoke all on function fitmatch_vnext.comparison_target_context(uuid,uuid,text)
  from public, anon;
grant execute on function fitmatch_vnext.comparison_target_context(uuid,uuid,text)
  to authenticated, service_role;
revoke all on function fitmatch_vnext.canonical_measurements_for_session_group(
  uuid,jsonb
) from public, anon, authenticated;
grant execute on function fitmatch_vnext.canonical_measurements_for_session_group(
  uuid,jsonb
) to service_role;
revoke all on function fitmatch_vnext.authorize_comparison_with_context_v1(
  uuid,uuid,uuid,boolean,jsonb,text
) from public, anon;
grant execute on function fitmatch_vnext.authorize_comparison_with_context_v1(
  uuid,uuid,uuid,boolean,jsonb,text
) to authenticated, service_role;
revoke all on function fitmatch_vnext.authorize_comparison_with_context(
  uuid,uuid,uuid,boolean,jsonb,text
) from public, anon;
grant execute on function fitmatch_vnext.authorize_comparison_with_context(
  uuid,uuid,uuid,boolean,jsonb,text
) to authenticated, service_role;
revoke all on function fitmatch_vnext.eligible_candidate_sizes(
  uuid,uuid,uuid,boolean,text
) from public, anon;
grant execute on function fitmatch_vnext.eligible_candidate_sizes(
  uuid,uuid,uuid,boolean,text
) to authenticated, service_role;
revoke all on function fitmatch_vnext.find_reference_candidates(uuid,uuid,text)
  from public, anon;
grant execute on function fitmatch_vnext.find_reference_candidates(uuid,uuid,text)
  to authenticated, service_role;
revoke all on function fitmatch_vnext.begin_comparison(jsonb) from public, anon;
grant execute on function fitmatch_vnext.begin_comparison(jsonb)
  to authenticated, service_role;

revoke all on function public.fitmatch_vnext_find_reference_candidates(
  uuid,uuid,text
) from public, anon;
grant execute on function public.fitmatch_vnext_find_reference_candidates(
  uuid,uuid,text
) to authenticated, service_role;
revoke all on function public.fitmatch_vnext_eligible_candidate_sizes(
  uuid,uuid,uuid,boolean,text
) from public, anon;
grant execute on function public.fitmatch_vnext_eligible_candidate_sizes(
  uuid,uuid,uuid,boolean,text
) to authenticated, service_role;

comment on function fitmatch_vnext.comparison_target_context(uuid,uuid,text) is
  'Builds a non-persistent, server-validated target context for a mapped or session-requested A-G comparison group.';
