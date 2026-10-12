-- Read-only deployed development definitions captured 2026-10-12. Isolated test only.
CREATE OR REPLACE FUNCTION fitmatch_vnext.authorize_comparison_with_context_v1(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 caller_id uuid := auth.uid();
 ref fitmatch_vnext.closet_items%rowtype;
 target fitmatch_vnext.products%rowtype;
 ref_gt fitmatch_vnext.garment_types%rowtype;
 target_gt fitmatch_vnext.garment_types%rowtype;
 policy fitmatch_vnext.comparison_policies%rowtype;
 effective_value jsonb;
 unit_value jsonb;
 canonical_value jsonb;
 evidence_value jsonb;
 ref_domain text;
 target_domain text;
 audience_ok boolean;
 common_count integer := 0;
 required_count integer := 0;
 reason_code_value text := 'INVALID_AUTHORITY';
 reason_value text := 'Invalid comparison authority';
 decision_value text := 'BLOCKED';
 result_value jsonb;
BEGIN
 IF caller_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 <<evaluate_pair>>
 BEGIN
  SELECT * INTO ref FROM fitmatch_vnext.closet_items ci
  WHERE ci.id=p_reference_closet_item_id AND ci.user_id=caller_id AND ci.deleted_at IS NULL;
  IF NOT FOUND THEN
   reason_value := 'Reference is missing or not owned'; EXIT evaluate_pair;
  END IF;
  SELECT * INTO target FROM fitmatch_vnext.products p WHERE p.id=p_target_product_id;
  IF NOT FOUND THEN reason_value := 'Target product not found'; EXIT evaluate_pair; END IF;
  -- Reject forged context even when this internal entry point is called directly.
  effective_value := fitmatch_vnext.effective_target_classification(target.id);
  IF p_effective_classification IS DISTINCT FROM effective_value THEN
   reason_value := 'Stale or invalid effective classification context'; EXIT evaluate_pair;
  END IF;
  IF effective_value->>'classification_status' IS DISTINCT FROM 'CONFIRMED' THEN
   reason_code_value := 'CLASSIFICATION_REQUIRED';
   reason_value := 'Target effective classification is not CONFIRMED'; EXIT evaluate_pair;
  END IF;
  unit_value := fitmatch_vnext.product_comparison_unit_decision(target.id);
  IF NOT coalesce((unit_value->>'eligible')::boolean,false) THEN
   reason_code_value := 'STRUCTURALLY_NOT_COMPARABLE';
   reason_value := unit_value->>'reason'; EXIT evaluate_pair;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.product_sizes ps
   JOIN fitmatch_vnext.product_variants pv ON pv.id=ps.variant_id
   WHERE ps.id=p_target_product_size_id AND pv.product_id=target.id) THEN
   reason_code_value := 'NO_ELIGIBLE_TARGET_SIZE';
   reason_value := 'Target size hierarchy mismatch'; EXIT evaluate_pair;
  END IF;
  SELECT * INTO ref_gt FROM fitmatch_vnext.garment_types
  WHERE garment_type_code=ref.garment_type_code AND is_active;
  SELECT * INTO target_gt FROM fitmatch_vnext.garment_types
  WHERE garment_type_code=effective_value->>'garment_type_code' AND is_active;
  IF ref_gt.garment_type_code IS NULL OR target_gt.garment_type_code IS NULL THEN
   reason_value := 'Unsupported garment'; EXIT evaluate_pair;
  END IF;
  SELECT * INTO policy FROM fitmatch_vnext.comparison_policies
  WHERE policy_code=target_gt.comparison_policy_code AND is_active;
  IF NOT FOUND THEN reason_value := 'Comparison policy unavailable'; EXIT evaluate_pair; END IF;
  ref_domain := fitmatch_vnext.comparison_domain_20260908(ref_gt.comparison_policy_code);
  target_domain := fitmatch_vnext.comparison_domain_20260908(target_gt.comparison_policy_code);
  -- Same FitMatch comparison group is required before policy evidence is evaluated.
  IF fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       IS DISTINCT FROM effective_value->>'comparison_group_code' THEN
    reason_code_value := 'COMPARISON_GROUP_REQUIRED';
    reason_value := 'Reference comparison group does not match target group';
    EXIT evaluate_pair;
  END IF;
  IF ref_gt.comparison_policy_code IS DISTINCT FROM target_gt.comparison_policy_code
     AND NOT (ref_domain=target_domain AND ref_domain IN ('UPPER_BODY','LOWER_BODY')) THEN
   reason_code_value := 'INCOMPATIBLE_BODY_REGION';
   reason_value := 'Comparison domains are incompatible'; EXIT evaluate_pair;
  END IF;
  -- Existing audience policy remains in force; no new audience policy is invented.
  audience_ok := CASE policy.audience_policy_code
   WHEN 'IGNORE' THEN true
   WHEN 'ADULT_ANY' THEN ref.audience_code IN ('MEN','WOMEN','UNISEX')
     AND effective_value->>'audience_code' IN ('MEN','WOMEN','UNISEX')
   WHEN 'SAME_ONLY' THEN ref.audience_code=effective_value->>'audience_code'
   ELSE ref.audience_code=effective_value->>'audience_code'
     OR ref.audience_code='UNISEX' OR effective_value->>'audience_code'='UNISEX' END;
  IF NOT coalesce(audience_ok,false) THEN
   reason_code_value := 'INCOMPATIBLE_AUDIENCE';
   reason_value := 'Audience is incompatible'; EXIT evaluate_pair;
  END IF;
  canonical_value := fitmatch_vnext.canonical_measurements_for_size_with_context(
    p_target_product_size_id,effective_value);
  IF coalesce((canonical_value->>'semantic_conflict_count')::integer,0)>0 THEN
   reason_value := 'Canonical measurement semantic conflict'; EXIT evaluate_pair;
  END IF;
  evidence_value := fitmatch_vnext.comparison_evidence_20260908(ref.id,policy.policy_code,canonical_value);
  common_count := jsonb_array_length(evidence_value);
  SELECT count(*) INTO required_count FROM jsonb_array_elements(evidence_value) e
   WHERE e->>'requirement_mode'='REQUIRED_ANY';
  IF common_count<1 THEN
   decision_value := 'MEASUREMENTS_REQUIRED'; reason_code_value := 'NO_COMMON_MEASUREMENTS';
   reason_value := 'No usable common canonical policy measurement'; EXIT evaluate_pair;
  END IF;
  -- Automatic mode requires a designated reference in the existing policy family.
  -- Axis differences are scored, not excluded or blocked, in BOTH modes.
  IF NOT coalesce(p_manual_explicit,false) AND
    (NOT coalesce(ref.is_reference,false) OR ref_gt.comparison_policy_code<>target_gt.comparison_policy_code) THEN
   reason_code_value := 'NO_AUTOMATIC_REFERENCE';
   reason_value := 'Explicit user selection is required'; EXIT evaluate_pair;
  END IF;
  IF coalesce(p_manual_explicit,false) THEN
   decision_value := 'MANUAL_EXTENDED'; reason_code_value := 'USER_SELECTED_REFERENCE';
   reason_value := 'User-selected comparison with at least one common canonical measurement';
  ELSE
   decision_value := 'AUTOMATIC'; reason_code_value := 'AUTOMATIC_MATCH';
   reason_value := 'Designated reference with at least one common canonical measurement';
  END IF;
 END evaluate_pair;
 result_value := jsonb_build_object(
  'decision',decision_value,'allowed',decision_value IN ('AUTOMATIC','MANUAL_EXTENDED'),
  'mode',CASE WHEN decision_value IN ('AUTOMATIC','MANUAL_EXTENDED') THEN decision_value ELSE 'NONE' END,
  'reason_code',reason_code_value,'reason',reason_value,
  'reference_measurement_domain',ref_domain,'target_measurement_domain',target_domain,
  'excluded_measurement_codes','[]'::jsonb,'excluded_measurement_reasons','[]'::jsonb,
  'required_measurement_codes','[]'::jsonb,'minimum_common',1,
  'common_measurement_count',common_count,'required_any_count',required_count,
  'required_any_min',0,'policy_minimum_common',policy.min_common_measurements,
  'policy_required_any_min',policy.required_any_min,
  'used_measurement_codes',coalesce((SELECT jsonb_agg(e->'measurement_code' ORDER BY e->>'measurement_code')
    FROM jsonb_array_elements(coalesce(evidence_value,'[]'::jsonb)) e),'[]'::jsonb),
  'policy_code',policy.policy_code,'policy_version',policy.policy_version,'policy_checksum',policy.policy_checksum,
  'authorization_version','fitmatch-vnext-authorization-20260908-user-policy-v1');
 IF effective_value->>'effective_source'='USER_EXPLICIT' THEN
  result_value := result_value || jsonb_build_object('classification_source','USER_EXPLICIT',
   'effective_authority_fingerprint',effective_value->>'effective_authority_fingerprint',
   'override_revision',effective_value->'override_revision');
 END IF;
 RETURN result_value;
END;
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.authorize_comparison_with_context_v1(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb, p_requested_group_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.begin_comparison_legacy_20260914(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
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
    selected_mapping fitmatch_vnext.classification_signal_mappings%rowtype;
    effective_value jsonb;
    candidate_authority jsonb;
    candidates jsonb;
    authz jsonb;
    authorized_ids uuid[];
    authorized_ids_sorted uuid[];
    client_candidate_ids uuid[];
    client_candidate_ids_sorted uuid[];
    comparison_id uuid;
    taxonomy_checksum text;
    mapping_authority_checksum text;
    reference_data jsonb;
    target_data jsonb;
    policy_data jsonb;
    global_classification_snapshot jsonb;
    personal_projection_snapshot jsonb;
    effective_classification_snapshot jsonb;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;
    if p_request ?| array[
        'garment_type_code', 'audience_code', 'category_code',
        'sleeve_length_code', 'lower_length_code', 'body_length_code',
        'comparison_policy_code', 'override_id'
    ] then
        raise exception 'Raw classification authority is not accepted at begin';
    end if;

    client_id := (p_request ->> 'client_comparison_id')::uuid;
    ref_id := (p_request ->> 'reference_closet_item_id')::uuid;
    target_id := (p_request ->> 'target_product_id')::uuid;
    target_variant := (p_request ->> 'target_variant_id')::uuid;
    authorization_size := nullif(
        btrim(p_request ->> 'authorization_product_size_id'), ''
    )::uuid;
    manual_explicit := coalesce(
        (p_request ->> 'manual_explicit')::boolean, false
    );
    if client_id is null or ref_id is null or target_id is null
       or target_variant is null then
        raise exception 'Comparison identity, reference, target, and variant are required';
    end if;

    request_hash := encode(extensions.digest(p_request::text, 'sha256'), 'hex');
    perform pg_advisory_xact_lock(hashtextextended(
        caller_id::text || ':' || client_id::text, 0
    ));
    select * into existing from fitmatch_vnext.comparisons
    where user_id = caller_id and client_comparison_id = client_id
    for update;
    if found then
        if existing.request_payload_hash is distinct from request_hash then
            raise exception 'Idempotency conflict for client_comparison_id';
        end if;
        return jsonb_build_object(
            'comparison_id', existing.id,
            'created', false,
            'idempotent', true,
            'result_status', existing.result_status,
            'authorized_candidate_product_size_ids',
                existing.target_snapshot ->
                    'authorized_candidate_product_size_ids'
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
    if not exists (
        select 1 from fitmatch_vnext.product_variants pv
        where pv.id = target_variant and pv.product_id = target_id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    effective_value := fitmatch_vnext.effective_target_classification(target.id);
    if effective_value ->> 'classification_status' <> 'CONFIRMED' then
        raise exception 'Target effective classification is not confirmed';
    end if;
    if effective_value ->> 'effective_source' = 'USER_EXPLICIT' then
        if nullif(p_request ->> 'effective_authority_fingerprint', '')
           is distinct from
           effective_value ->> 'effective_authority_fingerprint' then
            raise exception 'Stale personal classification authority fingerprint';
        end if;
        if nullif(p_request ->> 'personal_override_revision', '')::integer
           is distinct from
           (effective_value ->> 'override_revision')::integer then
            raise exception 'Stale personal classification revision';
        end if;
    end if;

    candidate_authority := fitmatch_vnext.eligible_candidate_sizes(
        ref_id, target_id, target_variant, manual_explicit
    );
    if not coalesce((candidate_authority ->> 'allowed')::boolean, false) then
        raise exception 'Comparison has no eligible candidate sizes: %',
            candidate_authority ->> 'reason';
    end if;
    if candidate_authority ->> 'effective_authority_fingerprint'
       is distinct from effective_value ->> 'effective_authority_fingerprint' then
        raise exception 'Candidate authority classification drift';
    end if;
    candidates := candidate_authority -> 'candidates';
    select coalesce(array_agg(value::uuid order by ordinal), '{}'::uuid[])
    into authorized_ids
    from jsonb_array_elements_text(
        candidate_authority -> 'authorized_candidate_product_size_ids'
    ) with ordinality item(value, ordinal);
    select coalesce(array_agg(id order by id), '{}'::uuid[])
    into authorized_ids_sorted from unnest(authorized_ids) id;
    if cardinality(authorized_ids) = 0 then
        raise exception 'Candidate authority returned an empty set';
    end if;

    if p_request ? 'candidate_product_size_ids' then
        if jsonb_typeof(p_request -> 'candidate_product_size_ids') <> 'array' then
            raise exception 'candidate_product_size_ids must be an array';
        end if;
        select coalesce(array_agg(value::uuid order by ordinal), '{}'::uuid[])
        into client_candidate_ids
        from jsonb_array_elements_text(
            p_request -> 'candidate_product_size_ids'
        ) with ordinality item(value, ordinal);
        if cardinality(client_candidate_ids) <>
           (select count(distinct id) from unnest(client_candidate_ids) id) then
            raise exception 'Client candidate sizes contain duplicates';
        end if;
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
    select candidate -> 'authorization' into authz
    from jsonb_array_elements(candidates) candidate
    where (candidate ->> 'product_size_id')::uuid = authorization_size
    limit 1;
    if authz is null or not coalesce((authz ->> 'allowed')::boolean, false) then
        raise exception 'Selected authorization is invalid';
    end if;

    select * into selected_mapping
    from fitmatch_vnext.classification_signal_mappings m
    where m.id = target.classification_mapping_id;
    select encode(extensions.digest(coalesce(string_agg(concat_ws('|',
        gt.garment_type_code, gt.category_code, gt.comparison_policy_code,
        gt.uses_sleeve_length::text, gt.uses_lower_length::text,
        gt.uses_body_length::text, gt.is_active::text
    ), E'\n' order by gt.garment_type_code), ''), 'sha256'), 'hex')
    into taxonomy_checksum from fitmatch_vnext.garment_types gt;
    select encode(extensions.digest(coalesce(string_agg(concat_ws('|',
        m.id::text, m.mapping_version, m.mapping_checksum
    ), E'\n' order by m.id), ''), 'sha256'), 'hex')
    into mapping_authority_checksum
    from fitmatch_vnext.classification_signal_mappings m
    where m.is_active and m.is_verified;

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
        'sleeve_length_code', ref.sleeve_length_code,
        'lower_length_code', ref.lower_length_code,
        'body_length_code', ref.body_length_code,
        'classification_source', ref.classification_source,
        'classification_fingerprint', ref.classification_fingerprint,
        'classification_resolver_version', ref.classification_resolver_version,
        'measurements', coalesce((select jsonb_agg(jsonb_build_object(
            'fitmatch_measurement_code', cm.fitmatch_measurement_code,
            'value', cm.value,
            'unit_code', cm.unit_code,
            'value_source', cm.value_source,
            'raw_label_snapshot', cm.raw_label_snapshot
        ) order by cm.fitmatch_measurement_code)
        from fitmatch_vnext.closet_item_measurements cm
        where cm.closet_item_id = ref.id), '[]'::jsonb)
    );
    target_data := jsonb_build_object(
        'product_id', target.id,
        'source_code', target.source_code,
        'source_product_key', target.source_product_key,
        'variant_id', target_variant,
        'candidate_product_size_ids', to_jsonb(authorized_ids),
        'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
        'candidate_authority_fingerprint',
            candidate_authority ->> 'candidate_authority_fingerprint',
        'candidate_authority_version',
            candidate_authority ->> 'candidate_authority_version',
        'classification_status',
            effective_value ->> 'classification_status',
        'classification_source', effective_value ->> 'effective_source',
        'product_structure_code', target.product_structure_code,
        'garment_type_code', effective_value ->> 'garment_type_code',
        'audience_code', effective_value ->> 'audience_code',
        'sleeve_length_code', effective_value ->> 'sleeve_length_code',
        'lower_length_code', effective_value ->> 'lower_length_code',
        'body_length_code', effective_value ->> 'body_length_code',
        'classification_fingerprint',
            effective_value ->> 'effective_authority_fingerprint',
        'global_classification_fingerprint', target.input_fingerprint,
        'classification_evidence_fingerprint', target.evidence_fingerprint,
        'resolver_version', target.resolver_version,
        'ingestion_evidence_fingerprint',
            target.source_extra ->> 'latest_ingestion_fingerprint',
        'candidates', candidates
    );

    select to_jsonb(cp) || jsonb_build_object(
        'metrics', coalesce((select jsonb_agg(jsonb_build_object(
            'metric_mode', cm.metric_mode,
            'fitmatch_measurement_code', cm.fitmatch_measurement_code,
            'source_measurement_code', cm.source_measurement_code,
            'weight', cm.weight,
            'requirement_mode', cm.requirement_mode,
            'priority', cm.priority,
            'is_active', cm.is_active
        ) order by cm.priority, cm.fitmatch_measurement_code,
                 cm.source_measurement_code)
        from fitmatch_vnext.comparison_metrics cm
        where cm.comparison_policy_code = cp.policy_code and cm.is_active),
            '[]'::jsonb)
    ) into policy_data from fitmatch_vnext.comparison_policies cp
    where cp.policy_code = authz ->> 'policy_code' and cp.is_active;
    if policy_data is null then
        raise exception 'Active policy disappeared during comparison begin';
    end if;

    global_classification_snapshot :=
        effective_value -> 'global_classification';
    personal_projection_snapshot :=
        effective_value -> 'personal_projection';
    effective_classification_snapshot := jsonb_strip_nulls(jsonb_build_object(
        'source', effective_value ->> 'effective_source',
        'state', effective_value ->> 'state',
        'category_code', effective_value ->> 'category_code',
        'garment_type_code', effective_value ->> 'garment_type_code',
        'audience_code', effective_value ->> 'audience_code',
        'sleeve_length_code', effective_value ->> 'sleeve_length_code',
        'lower_length_code', effective_value ->> 'lower_length_code',
        'body_length_code', effective_value ->> 'body_length_code',
        'comparison_policy_code', effective_value ->> 'comparison_policy_code',
        'effective_authority_fingerprint',
            effective_value ->> 'effective_authority_fingerprint'
    ));

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
        authz ->> 'policy_code', 'CANONICAL',
        coalesce(reference_product.source_code, ref.source_code_snapshot),
        target.source_code, ref.item_name, target.product_name, target.image_url,
        ref.garment_type_code, effective_value ->> 'garment_type_code',
        ref.audience_code, effective_value ->> 'audience_code',
        ref.sleeve_length_code, effective_value ->> 'sleeve_length_code',
        ref.lower_length_code, effective_value ->> 'lower_length_code',
        ref.body_length_code, effective_value ->> 'body_length_code',
        'PENDING', 'pending', 4, jsonb_build_object('phase', 'BEGIN'),
        request_hash, authz ->> 'mode',
        array(select jsonb_array_elements_text(
            authz -> 'excluded_measurement_codes'
        )),
        reference_data, target_data,
        jsonb_build_object(
            'global_classification_at_begin', global_classification_snapshot,
            'personal_projection_at_begin', personal_projection_snapshot,
            'effective_classification_at_begin',
                effective_classification_snapshot,
            'classification_resolver_version', target.resolver_version,
            'classification_fingerprint', target.input_fingerprint,
            'classification_evidence_fingerprint', target.evidence_fingerprint,
            'classification_mapping_id', target.classification_mapping_id,
            'selected_mapping_version', selected_mapping.mapping_version,
            'selected_mapping_checksum', selected_mapping.mapping_checksum,
            'mapping_authority_checksum', mapping_authority_checksum,
            'taxonomy_schema_version', 'fitmatch-vnext-taxonomy-v1',
            'taxonomy_checksum', taxonomy_checksum,
            'ingestion_evidence_fingerprint',
                target.source_extra ->> 'latest_ingestion_fingerprint',
            'manual_cross_rule_at_begin', authz -> 'manual_cross_rule'
        ),
        policy_data, authz,
        jsonb_build_object(
            'client_request', p_request,
            'candidate_authority_fingerprint',
                candidate_authority ->> 'candidate_authority_fingerprint',
            'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
            'effective_authority_fingerprint',
                effective_value ->> 'effective_authority_fingerprint',
            'personal_override_revision', effective_value -> 'override_revision',
            'began_at', now()
        )
    ) returning id into comparison_id;

    return jsonb_build_object(
        'comparison_id', comparison_id,
        'created', true,
        'idempotent', false,
        'result_status', 'PENDING',
        'authorization', authz,
        'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
        'candidate_authority_fingerprint',
            candidate_authority ->> 'candidate_authority_fingerprint',
        'effective_authority_fingerprint',
            effective_value ->> 'effective_authority_fingerprint',
        'snapshot_schema_version', 4
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.comparison_evidence_20260908(p_reference_closet_item_id uuid, p_policy text, p_canonical jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with target_rows as (
    select e->>'fitmatch_measurement_code' code,
           e->>'source_measurement_code' source_code,
           (e->>'value')::numeric value,
           lower(e->>'unit_code') unit,
           e->>'basis_code' basis
    from jsonb_array_elements(coalesce(p_canonical->'measurements','[]'::jsonb)) e
    where coalesce((p_canonical->>'semantic_conflict_count')::integer,0)=0
), targets as (
    select code, min(source_code) source_code,
           count(distinct source_code) source_count, min(value) value,
           min(unit) unit, min(basis) basis
    from target_rows
    group by code
    having count(distinct (value,unit,basis))=1
), canonical_evidence as (
    select cm.fitmatch_measurement_code measurement_code,
           r.value reference_value, t.value target_value,
           t.value-r.value difference, abs(t.value-r.value) absolute_difference,
           fm.canonical_unit_code unit_code, fm.canonical_basis_code basis_code,
           cm.weight, cm.requirement_mode, cm.priority,
           fm.body_region_code
    from fitmatch_vnext.comparison_metrics cm
    join fitmatch_vnext.fitmatch_measurements fm
      on fm.measurement_code=cm.fitmatch_measurement_code and fm.is_active
    join fitmatch_vnext.closet_item_measurements r
      on r.closet_item_id=p_reference_closet_item_id
     and r.fitmatch_measurement_code=cm.fitmatch_measurement_code
    join targets t on t.code=cm.fitmatch_measurement_code
    where cm.comparison_policy_code=p_policy and cm.is_active
      and cm.metric_mode='CANONICAL'
      and r.value>0 and r.value::text not in ('NaN','Infinity','-Infinity')
      and t.value>0 and t.value::text not in ('NaN','Infinity','-Infinity')
      and cm.weight>0 and cm.weight::text not in ('NaN','Infinity','-Infinity')
      and lower(r.unit_code)=lower(fm.canonical_unit_code)
      and t.unit=lower(fm.canonical_unit_code)
      and t.basis=fm.canonical_basis_code
), native_candidates as (
    select smm.fitmatch_measurement_code measurement_code,
           r.value reference_value, t.value target_value,
           t.value-r.value difference, abs(t.value-r.value) absolute_difference,
           fm.canonical_unit_code unit_code, fm.canonical_basis_code basis_code,
           cm.weight, cm.requirement_mode, cm.priority,
           fm.body_region_code,
           row_number() over (
               partition by fm.body_region_code
               order by cm.priority, cm.source_measurement_code
           ) choice_rank
    from fitmatch_vnext.comparison_metrics cm
    join fitmatch_vnext.source_measurements sm
      on sm.source_measurement_code=cm.source_measurement_code
     and sm.is_active and sm.is_comparable
    join fitmatch_vnext.source_measurement_mappings smm
      on smm.source_measurement_code=sm.source_measurement_code
     and smm.is_active and smm.is_verified
     and smm.scale_factor=1 and smm.offset_value=0
    join fitmatch_vnext.fitmatch_measurements fm
      on fm.measurement_code=smm.fitmatch_measurement_code and fm.is_active
     and fm.canonical_basis_code=sm.measurement_basis_code
     and fm.representation_code=sm.representation_code
    join fitmatch_vnext.closet_item_measurements r
      on r.closet_item_id=p_reference_closet_item_id
     and r.fitmatch_measurement_code=smm.fitmatch_measurement_code
     and coalesce(r.source_measurement_code_snapshot,
                  r.source_measurement_code)=cm.source_measurement_code
    join fitmatch_vnext.closet_items ci
      on ci.id=r.closet_item_id and ci.deleted_at is null
     and ci.user_id=auth.uid()
    join fitmatch_vnext.products reference_product
      on reference_product.id=ci.product_id
     and reference_product.source_code=sm.source_code
    join fitmatch_vnext.product_sizes target_size
      on target_size.id=(p_canonical->>'product_size_id')::uuid
    join fitmatch_vnext.product_variants target_variant
      on target_variant.id=target_size.variant_id
    join fitmatch_vnext.products target_product
      on target_product.id=target_variant.product_id
     and target_product.source_code=sm.source_code
    join targets t
      on t.code=smm.fitmatch_measurement_code
     and t.source_code=cm.source_measurement_code
     and t.source_count=1
    where cm.comparison_policy_code=p_policy and cm.is_active
      and cm.metric_mode='SOURCE_NATIVE_OVERRIDE'
      and r.value>0 and r.value::text not in ('NaN','Infinity','-Infinity')
      and t.value>0 and t.value::text not in ('NaN','Infinity','-Infinity')
      and cm.weight>0 and cm.weight::text not in ('NaN','Infinity','-Infinity')
      and lower(r.unit_code)=lower(fm.canonical_unit_code)
      and t.unit=lower(fm.canonical_unit_code)
      and t.basis=fm.canonical_basis_code
      and exists (
          select 1
          from fitmatch_vnext.comparison_metrics policy_metric
          join fitmatch_vnext.fitmatch_measurements policy_measurement
            on policy_measurement.measurement_code=policy_metric.fitmatch_measurement_code
           and policy_measurement.is_active
          where policy_metric.comparison_policy_code=p_policy
            and policy_metric.metric_mode='CANONICAL'
            and policy_metric.is_active
            and policy_measurement.body_region_code=fm.body_region_code
      )
      and not exists (
          select 1 from canonical_evidence existing
          where existing.body_region_code=fm.body_region_code
      )
), evidence as (
    select measurement_code, reference_value, target_value, difference,
           absolute_difference, unit_code, basis_code, weight,
           requirement_mode, priority
    from canonical_evidence
    union all
    select measurement_code, reference_value, target_value, difference,
           absolute_difference, unit_code, basis_code, weight,
           requirement_mode, priority
    from native_candidates where choice_rank=1
)
select coalesce(jsonb_agg(to_jsonb(e) order by priority,measurement_code),'[]'::jsonb)
from evidence e;
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.complete_comparison(p_comparison_id uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
    row_value fitmatch_vnext.comparisons%rowtype;
    result_hash text;
    recommended_id uuid;
    recommended_label text;
    score_value numeric;
    reliability_value smallint;
    coverage_value numeric;
    expected_coverage numeric;
    authorized_count integer;
    ranking_count integer;
    expected_evidence_count integer;
    recommended_evidence_count integer;
    policy_metric_count integer;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_result is null or jsonb_typeof(p_result) <> 'object' then
        raise exception 'Result must be a JSON object';
    end if;

    result_hash := encode(extensions.digest(p_result::text, 'sha256'), 'hex');
    select * into row_value
    from fitmatch_vnext.comparisons
    where id = p_comparison_id and user_id = caller_id
    for update;
    if not found then
        raise exception 'Comparison not found or not owned';
    end if;
    if row_value.result_status = 'COMPLETED' then
        if row_value.result_payload_hash is distinct from result_hash then
            raise exception 'Completion idempotency conflict';
        end if;
        return jsonb_build_object(
            'comparison_id', row_value.id,
            'completed', true,
            'idempotent', true,
            'recommended_product_size_id', row_value.recommended_product_size_id,
            'recommended_size_label', row_value.recommended_size_label
        );
    end if;
    if row_value.result_status <> 'PENDING' then
        raise exception 'Comparison is not pending';
    end if;

    if jsonb_typeof(p_result -> 'recommended_product_size_id') <> 'string'
       or jsonb_typeof(p_result -> 'score') <> 'number'
       or jsonb_typeof(p_result -> 'reliability') <> 'number'
       or jsonb_typeof(p_result -> 'coverage') <> 'number'
       or nullif(btrim(p_result ->> 'engine_version'), '') is null then
        raise exception 'Recommendation, score, reliability, coverage, and engine_version are required';
    end if;
    recommended_id := (p_result ->> 'recommended_product_size_id')::uuid;
    score_value := (p_result ->> 'score')::numeric;
    reliability_value := (p_result ->> 'reliability')::smallint;
    coverage_value := (p_result ->> 'coverage')::numeric;
    if score_value < 0 or score_value > 100
       or reliability_value < 1 or reliability_value > 5
       or coverage_value < 0 or coverage_value > 1
       or length(p_result ->> 'engine_version') > 128 then
        raise exception 'Result summary values are outside the engine contract';
    end if;

    if jsonb_typeof(row_value.target_snapshot ->
           'authorized_candidate_product_size_ids') <> 'array'
       or jsonb_array_length(row_value.target_snapshot ->
           'authorized_candidate_product_size_ids') = 0 then
        raise exception 'Begin snapshot has no authorized candidate set';
    end if;
    if jsonb_typeof(p_result -> 'candidate_size_ranking') <> 'array'
       or jsonb_array_length(p_result -> 'candidate_size_ranking') = 0
       or jsonb_typeof(p_result -> 'metric_evidence') <> 'array'
       or jsonb_array_length(p_result -> 'metric_evidence') = 0 then
        raise exception 'Candidate ranking and metric evidence are required';
    end if;

    if exists (
        select 1 from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        where jsonb_typeof(ranking) <> 'object'
           or jsonb_typeof(ranking -> 'product_size_id') <> 'string'
           or jsonb_typeof(ranking -> 'rank') <> 'number'
           or jsonb_typeof(ranking -> 'score') <> 'number'
           or (ranking ->> 'rank')::integer < 1
           or (ranking ->> 'score')::numeric < 0
           or (ranking ->> 'score')::numeric > 100
    ) then
        raise exception 'Every ranking entry needs product_size_id, positive rank, and score';
    end if;

    authorized_count := jsonb_array_length(
        row_value.target_snapshot -> 'authorized_candidate_product_size_ids'
    );
    ranking_count := jsonb_array_length(p_result -> 'candidate_size_ranking');
    if ranking_count <> authorized_count then
        raise exception 'Ranking set must exactly cover the authorized candidate set';
    end if;
    if exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        group by ranking ->> 'product_size_id'
        having count(*) > 1
    ) or exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        group by (ranking ->> 'rank')::integer
        having count(*) > 1
    ) then
        raise exception 'Duplicate candidate size or rank';
    end if;
    if (
        select min((ranking ->> 'rank')::integer) <> 1
            or max((ranking ->> 'rank')::integer) <> ranking_count
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
    ) then
        raise exception 'Ranks must be contiguous from one';
    end if;
    if exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') higher
        cross join jsonb_array_elements(p_result -> 'candidate_size_ranking') lower
        where (higher ->> 'rank')::integer < (lower ->> 'rank')::integer
          and (higher ->> 'score')::numeric < (lower ->> 'score')::numeric
    ) then
        raise exception 'Candidate ranking order contradicts candidate scores';
    end if;
    if exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        where not exists (
            select 1
            from jsonb_array_elements_text(row_value.target_snapshot ->
                'authorized_candidate_product_size_ids') authorized(id)
            where authorized.id::uuid = (ranking ->> 'product_size_id')::uuid
        )
    ) or exists (
        select 1
        from jsonb_array_elements_text(row_value.target_snapshot ->
            'authorized_candidate_product_size_ids') authorized(id)
        where not exists (
            select 1
            from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
            where (ranking ->> 'product_size_id')::uuid = authorized.id::uuid
        )
    ) then
        raise exception 'Ranking contains an unauthorized or missing candidate';
    end if;
    if not exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        where (ranking ->> 'product_size_id')::uuid = recommended_id
          and (ranking ->> 'rank')::integer = 1
          and (ranking ->> 'score')::numeric = score_value
    ) then
        raise exception 'Recommended size must be rank one and match the result score';
    end if;

    select ps.size_label into recommended_label
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where ps.id = recommended_id
      and pv.id = row_value.target_variant_id
      and pv.product_id = row_value.target_product_id;
    if recommended_label is null then
        raise exception 'Recommended size hierarchy mismatch';
    end if;

    if exists (
        select 1 from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        where jsonb_typeof(evidence) <> 'object'
           or jsonb_typeof(evidence -> 'product_size_id') <> 'string'
           or nullif(btrim(evidence ->> 'measurement_code'), '') is null
           or jsonb_typeof(evidence -> 'reference_value') <> 'number'
           or jsonb_typeof(evidence -> 'target_value') <> 'number'
           or jsonb_typeof(evidence -> 'difference') <> 'number'
           or jsonb_typeof(evidence -> 'absolute_difference') <> 'number'
           or jsonb_typeof(evidence -> 'weight') <> 'number'
    ) then
        raise exception 'Metric evidence is missing required semantic fields';
    end if;
    if exists (
        select 1
        from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        group by evidence ->> 'product_size_id', evidence ->> 'measurement_code'
        having count(*) > 1
    ) then
        raise exception 'Duplicate size and metric evidence';
    end if;
    if exists (
        select 1 from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        where evidence ->> 'measurement_code' = any(row_value.excluded_measurement_codes)
    ) then
        raise exception 'Excluded measurement evidence is forbidden';
    end if;

    with expected as (
        select (candidate ->> 'product_size_id')::uuid product_size_id,
               metric ->> 'measurement_code' measurement_code,
               (metric ->> 'reference_value')::numeric reference_value,
               (metric ->> 'target_value')::numeric target_value,
               (metric ->> 'difference')::numeric difference,
               (metric ->> 'absolute_difference')::numeric absolute_difference,
               (metric ->> 'weight')::numeric weight
        from jsonb_array_elements(row_value.target_snapshot -> 'candidates') candidate
        cross join jsonb_array_elements(candidate -> 'comparison_measurements') metric
    ), evidence as (
        select (item ->> 'product_size_id')::uuid product_size_id,
               item ->> 'measurement_code' measurement_code,
               (item ->> 'reference_value')::numeric reference_value,
               (item ->> 'target_value')::numeric target_value,
               (item ->> 'difference')::numeric difference,
               (item ->> 'absolute_difference')::numeric absolute_difference,
               (item ->> 'weight')::numeric weight
        from jsonb_array_elements(p_result -> 'metric_evidence') item
    )
    select count(*) into expected_evidence_count from expected;
    if expected_evidence_count = 0 then
        raise exception 'Begin snapshot contains no comparable metric evidence';
    end if;
    if jsonb_array_length(p_result -> 'metric_evidence') <> expected_evidence_count then
        raise exception 'Metric evidence set must exactly match the begin snapshot';
    end if;
    if exists (
        with expected as (
            select (candidate ->> 'product_size_id')::uuid product_size_id,
                   metric ->> 'measurement_code' measurement_code,
                   (metric ->> 'reference_value')::numeric reference_value,
                   (metric ->> 'target_value')::numeric target_value,
                   (metric ->> 'weight')::numeric weight
            from jsonb_array_elements(row_value.target_snapshot -> 'candidates') candidate
            cross join jsonb_array_elements(candidate -> 'comparison_measurements') metric
        )
        select 1
        from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        left join expected on expected.product_size_id =
                (evidence ->> 'product_size_id')::uuid
            and expected.measurement_code = evidence ->> 'measurement_code'
        where expected.product_size_id is null
           or (evidence ->> 'reference_value')::numeric <> expected.reference_value
           or (evidence ->> 'target_value')::numeric <> expected.target_value
           or (evidence ->> 'weight')::numeric <> expected.weight
           or (evidence ->> 'difference')::numeric <>
                expected.target_value - expected.reference_value
           or (evidence ->> 'absolute_difference')::numeric <>
                abs(expected.target_value - expected.reference_value)
    ) then
        raise exception 'Metric evidence does not match begin values, policy weight, or difference';
    end if;
    if exists (
        with supplied as (
            select (evidence ->> 'product_size_id')::uuid product_size_id,
                   evidence ->> 'measurement_code' measurement_code
            from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        )
        select 1
        from jsonb_array_elements(row_value.target_snapshot -> 'candidates') candidate
        cross join jsonb_array_elements(candidate -> 'comparison_measurements') metric
        where not exists (
            select 1 from supplied
            where supplied.product_size_id = (candidate ->> 'product_size_id')::uuid
              and supplied.measurement_code = metric ->> 'measurement_code'
        )
    ) then
        raise exception 'Metric evidence omits a begin-snapshot metric';
    end if;

    select count(*) into recommended_evidence_count
    from jsonb_array_elements(p_result -> 'metric_evidence') evidence
    where (evidence ->> 'product_size_id')::uuid = recommended_id;
    select count(*) into policy_metric_count
    from jsonb_array_elements(row_value.policy_snapshot -> 'metrics') metric
    where metric ->> 'metric_mode' = 'CANONICAL'
      and coalesce((metric ->> 'is_active')::boolean, false)
      and not (metric ->> 'fitmatch_measurement_code' =
          any(row_value.excluded_measurement_codes));
    if policy_metric_count = 0 then
        raise exception 'Policy snapshot has no active canonical metrics';
    end if;
    expected_coverage := round(
        recommended_evidence_count::numeric / policy_metric_count::numeric, 5
    );
    if round(coverage_value, 5) <> expected_coverage then
        raise exception 'Coverage does not match begin-snapshot metric coverage';
    end if;

    update fitmatch_vnext.comparisons
    set recommended_product_size_id = recommended_id,
        recommended_size_label = recommended_label,
        fit_score = score_value,
        reliability_level = reliability_value,
        coverage_ratio = coverage_value,
        result_status = 'COMPLETED',
        engine_version = p_result ->> 'engine_version',
        detail_snapshot = jsonb_build_object(
            'phase', 'COMPLETED',
            'result', p_result,
            'validated_against_snapshot_schema_version', row_value.snapshot_schema_version
        ),
        result_evidence = p_result,
        result_payload_hash = result_hash,
        completed_at = now()
    where id = row_value.id;

    return jsonb_build_object(
        'comparison_id', row_value.id,
        'completed', true,
        'idempotent', false,
        'recommended_product_size_id', recommended_id,
        'recommended_size_label', recommended_label,
        'validated_evidence_count', expected_evidence_count,
        'coverage', expected_coverage
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.effective_product_readiness(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    effective_value jsonb;
begin
    effective_value := fitmatch_vnext.effective_target_classification(
        p_product_id
    );
    if effective_value ->> 'effective_source' = 'GLOBAL_CONFIRMED' then
        return fitmatch_vnext.product_readiness(p_product_id);
    end if;
    return fitmatch_vnext.product_readiness_with_context(
        p_product_id, effective_value
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.get_product_runtime_base(p_source_code text, p_source_product_key text, p_include_derived boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
    product_row fitmatch_vnext.products%rowtype;
begin
    if caller_id is null
       and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Authentication required';
    end if;

    select * into product_row
    from fitmatch_vnext.products p
    where p.source_code = lower(btrim(p_source_code))
      and p.source_product_key = btrim(p_source_product_key);
    if not found then
        return jsonb_build_object('found', false);
    end if;

    return jsonb_build_object(
        'found', true,
        'product', jsonb_build_object(
            'id', product_row.id,
            'source_code', product_row.source_code,
            'source_product_key', product_row.source_product_key,
            'product_name', product_row.product_name,
            'brand_name', product_row.brand_name,
            'canonical_url', product_row.canonical_url,
            'image_url', product_row.image_url,
            'classification_status', product_row.classification_status,
            'product_structure_code', product_row.product_structure_code,
            'audience_code', product_row.audience_code,
            'garment_type_code', product_row.garment_type_code,
            'sleeve_length_code', product_row.sleeve_length_code,
            'lower_length_code', product_row.lower_length_code,
            'body_length_code', product_row.body_length_code,
            'resolver_version', product_row.resolver_version,
            'input_fingerprint', product_row.input_fingerprint,
            'latest_ingestion_fingerprint',
                product_row.source_extra ->> 'latest_ingestion_fingerprint'
        ),
        'readiness', CASE WHEN p_include_derived THEN fitmatch_vnext.product_readiness(product_row.id) ELSE null::jsonb END,
        'variants', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', pv.id,
                'source_variant_key', pv.source_variant_key,
                'variant_label', pv.variant_label,
                'color_name', pv.color_name,
                'sizes', coalesce((
                    select jsonb_agg(jsonb_build_object(
                        'id', ps.id,
                        'source_size_key', ps.source_size_key,
                        'size_label', ps.size_label,
                        'availability', coalesce((
                            select jsonb_build_object(
                                'status', o.availability_status,
                                'observed_at', o.observed_at,
                                'valid_until', o.valid_until,
                                'evidence_fingerprint', o.evidence_fingerprint
                            ) from fitmatch_vnext.size_availability_observations o
                            where o.product_size_id = ps.id
                            order by o.observed_at desc, o.id desc limit 1
                        ), jsonb_build_object('status', 'UNKNOWN')),
                        'canonical_measurements',
                            CASE WHEN p_include_derived THEN fitmatch_vnext.canonical_measurements_for_size(ps.id) ELSE null::jsonb END
                    ) order by ps.sort_order, ps.id)
                    from fitmatch_vnext.product_sizes ps
                    where ps.variant_id = pv.id
                ), '[]'::jsonb)
            ) order by pv.sort_order, pv.id)
            from fitmatch_vnext.product_variants pv
            where pv.product_id = product_row.id
        ), '[]'::jsonb)
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.authorize_comparison_with_context(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    unit_value jsonb;
begin
    unit_value := fitmatch_vnext.product_comparison_unit_decision(
        p_target_product_id
    );
    if not coalesce((unit_value ->> 'eligible')::boolean, false) then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'STRUCTURALLY_NOT_COMPARABLE',
            'excluded_measurement_codes', '[]'::jsonb,
            'excluded_measurement_reasons', '[]'::jsonb,
            'reason', unit_value ->> 'reason',
            'comparison_unit', unit_value
        );
    end if;
    return fitmatch_vnext.authorize_comparison_with_context_v1(
        p_reference_closet_item_id, p_target_product_id,
        p_target_product_size_id, p_manual_explicit, p_effective_classification
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.authorize_comparison_with_context(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb, p_requested_group_code text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select fitmatch_vnext.authorize_comparison_with_context_v1(
    p_reference_closet_item_id, p_target_product_id,
    p_target_product_size_id, p_manual_explicit,
    p_effective_classification, p_requested_group_code
  )
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.begin_comparison(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.canonical_measurements_for_session_group(p_product_size_id uuid, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.canonical_measurements_for_size_with_context(p_product_size_id uuid, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
    actual_product_id uuid;
    context_source text;
begin
    select pv.product_id into actual_product_id
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where ps.id = p_product_size_id;

    if actual_product_id is null then
        raise exception 'Product size not found';
    end if;

    if actual_product_id is distinct from
       (p_effective_classification ->> 'product_id')::uuid then
        raise exception 'Measurement context product mismatch';
    end if;

    context_source := p_effective_classification ->> 'effective_source';
    if context_source = 'GLOBAL_CONFIRMED' then
        return fitmatch_vnext.canonical_measurements_for_size(p_product_size_id);
    end if;

    if context_source not in ('USER_EXPLICIT', 'CATEGORY_GROUP') then
        return jsonb_build_object(
            'product_size_id', p_product_size_id,
            'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
            'measurements', '[]'::jsonb,
            'raw_measurement_count', 0,
            'unresolved_count', 0,
            'semantic_conflict_count', 0,
            'classification_context_source', context_source
        );
    end if;

    -- Product-native aliases decide semantics first.  A verified context
    -- fallback is retained only for truly UNMAPPED native rows, preserving
    -- the existing detailed-category-missing recovery path without allowing a
    -- comparison group to overwrite a resolved raw measurement.
    return (
        with raw_rows as (
            select m.*, p.source_code,
                   p.garment_type_code native_garment_type_code,
                   native_gt.category_code native_category_code,
                   p_effective_classification ->> 'garment_type_code' context_garment_type_code,
                   p_effective_classification ->> 'category_code' context_category_code
            from fitmatch_vnext.product_size_measurements m
            join fitmatch_vnext.product_sizes ps on ps.id = m.product_size_id
            join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
            join fitmatch_vnext.products p on p.id = pv.product_id
            left join fitmatch_vnext.garment_types native_gt
              on native_gt.garment_type_code = p.garment_type_code
            where m.product_size_id = p_product_size_id and m.is_current
      and m.raw_value > 0
        ), decisions as (
            select r.*,
                   fitmatch_vnext.resolve_measurement(
                     r.source_code, r.parser_code, r.raw_code, r.raw_label,
                     r.native_garment_type_code, r.native_category_code, r.raw_value
                   ) native_decision,
                   fitmatch_vnext.resolve_measurement(
                     r.source_code, r.parser_code, r.raw_code, r.raw_label,
                     r.context_garment_type_code, r.context_category_code, r.raw_value
                   ) context_decision
            from raw_rows r
        ), selected as (
            select d.*,
                   case when d.native_decision ->> 'resolution_status' = 'UNMAPPED'
                         and d.context_decision ->> 'resolution_status' = 'RESOLVED'
                        then d.context_decision
                        else d.native_decision
                   end decision
            from decisions d
        ), resolved as (
            select *, decision ->> 'fitmatch_measurement_code' canonical_code,
                   (decision ->> 'canonical_value')::numeric canonical_value
            from selected
            where decision ->> 'resolution_status' = 'RESOLVED'
        ), conflicts as (
            select canonical_code from resolved group by canonical_code
            having count(distinct canonical_value) > 1
        )
        select jsonb_build_object(
            'product_size_id', p_product_size_id,
            'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
            'measurements', coalesce((select jsonb_agg(jsonb_build_object(
                'product_size_measurement_id', r.id,
                'fitmatch_measurement_code', r.canonical_code,
                'value', r.canonical_value,
                'unit_code', r.decision ->> 'canonical_unit_code',
                'basis_code', r.decision ->> 'canonical_basis_code',
                'source_measurement_code', r.decision ->> 'source_measurement_code',
                'resolution_path', r.decision ->> 'resolution_path',
                'raw_evidence_fingerprint', r.evidence_fingerprint
            ) order by r.canonical_code, r.id)
            from resolved r
            where not exists (select 1 from conflicts c
                              where c.canonical_code = r.canonical_code)),
                '[]'::jsonb),
            'raw_measurement_count', (select count(*) from raw_rows),
            'unresolved_count', (select count(*) from selected
                where decision ->> 'resolution_status' <> 'RESOLVED'),
            'semantic_conflict_count', (select count(*) from conflicts),
            'classification_context_source', context_source
        )
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.comparison_target_context(p_target_product_id uuid, p_target_variant_id uuid, p_requested_group_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  if requested_code is null then
    source_value := resolved->>'mapping_source';
    if source_value is null
       or source_value not in ('RETAILER_CATEGORY', 'PRODUCT_OVERRIDE') then
      raise exception 'Invalid comparison group mapping source' using errcode = '22023';
    end if;
  else
    source_value := 'SESSION_USER_SELECTED';
  end if;
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
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.eligible_candidate_sizes(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_variant_id uuid, p_manual_explicit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
    reference_row fitmatch_vnext.closet_items%rowtype;
    target_row fitmatch_vnext.products%rowtype;
    effective_value jsonb;
    size_row record;
    canonical_value jsonb;
    authorization_value jsonb;
    comparison_measurements_value jsonb;
    candidates_value jsonb := '[]'::jsonb;
    fingerprint_candidates_value jsonb := '[]'::jsonb;
    candidate_value jsonb;
    total_size_count_value integer := 0;
    available_count_value integer := 0;
    sold_out_count_value integer := 0;
    unknown_count_value integer := 0;
    expired_available_count_value integer := 0;
    semantic_conflict_count_value integer := 0;
    authorization_rejected_count_value integer := 0;
    authority_fingerprint_value text;
    authority_version_value text;
    rejected_reason_code_value text;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;

    select * into reference_row
    from fitmatch_vnext.closet_items ci
    where ci.id = p_reference_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null;

    if not found then
        raise exception 'Reference is missing or not owned';
    end if;

    select * into target_row
    from fitmatch_vnext.products p
    where p.id = p_target_product_id;

    if not found then
        raise exception 'Target product not found';
    end if;

    effective_value := fitmatch_vnext.effective_target_classification(
        target_row.id
    );

    if effective_value ->> 'classification_status' <> 'CONFIRMED' then
        return jsonb_build_object(
            'allowed', false,
            'decision', 'BLOCKED',
            'reason', 'Target effective classification is not CONFIRMED',
            'effective_classification', effective_value,
            'authorized_candidate_product_size_ids', '[]'::jsonb,
            'candidates', '[]'::jsonb,
            'candidate_authority_version', 'fitmatch-vnext-candidates-20260908-effective-v1'
        );
    end if;

    if not exists (
        select 1
        from fitmatch_vnext.product_variants pv
        where pv.id = p_target_variant_id
          and pv.product_id = p_target_product_id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    for size_row in
        select
            ps.id as product_size_id,
            ps.size_label,
            ps.sort_order,
            availability.availability_status,
            availability.observed_at as availability_observed_at,
            availability.valid_until as availability_valid_until,
            availability.evidence_fingerprint as availability_evidence_fingerprint
        from fitmatch_vnext.product_sizes ps
        left join lateral (
            select
                o.availability_status,
                o.observed_at,
                o.valid_until,
                o.evidence_fingerprint
            from fitmatch_vnext.size_availability_observations o
            where o.product_size_id = ps.id
            order by o.observed_at desc, o.id desc
            limit 1
        ) availability on true
        where ps.variant_id = p_target_variant_id
        order by ps.sort_order, ps.id
    loop
        total_size_count_value := total_size_count_value + 1;

        -- Inventory is diagnostic/presentation data only.
        -- IMPORTANT: no inventory state below is allowed to `continue` the loop.
        case size_row.availability_status
            when 'AVAILABLE' then
                available_count_value := available_count_value + 1;
            when 'SOLD_OUT' then
                sold_out_count_value := sold_out_count_value + 1;
            else
                unknown_count_value := unknown_count_value + 1;
        end case;

        if size_row.availability_status = 'AVAILABLE'
           and (
               size_row.availability_valid_until is null
               or size_row.availability_valid_until < now()
           ) then
            expired_available_count_value := expired_available_count_value + 1;
        end if;

        canonical_value :=
            fitmatch_vnext.canonical_measurements_for_size_with_context(
                size_row.product_size_id,
                effective_value
            );

        if coalesce(
            (canonical_value ->> 'semantic_conflict_count')::integer,
            0
        ) > 0 then
            semantic_conflict_count_value :=
                semantic_conflict_count_value + 1;
            continue;
        end if;

        authorization_value :=
            fitmatch_vnext.authorize_comparison_with_context(
                reference_row.id,
                target_row.id,
                size_row.product_size_id,
                p_manual_explicit,
                effective_value
            );

        if not coalesce(
            (authorization_value ->> 'allowed')::boolean,
            false
        ) then
            rejected_reason_code_value := coalesce(rejected_reason_code_value, authorization_value->>'reason_code');
            authorization_rejected_count_value :=
                authorization_rejected_count_value + 1;
            continue;
        end if;

        comparison_measurements_value :=
            fitmatch_vnext.comparison_evidence_20260908(
                reference_row.id, authorization_value ->> 'policy_code', canonical_value
            );
        if jsonb_array_length(comparison_measurements_value) < 1 then
            authorization_rejected_count_value := authorization_rejected_count_value + 1;
            continue;
        end if;

        candidate_value := jsonb_build_object(
            'product_size_id', size_row.product_size_id,
            'size_label', size_row.size_label,
            'availability', jsonb_build_object(
                'status', size_row.availability_status,
                'observed_at', size_row.availability_observed_at,
                'valid_until', size_row.availability_valid_until,
                'evidence_fingerprint',
                    size_row.availability_evidence_fingerprint
            ),
            'canonical_measurements', canonical_value,
            'comparison_measurements', comparison_measurements_value,
            'authorization', authorization_value
        );

        candidates_value :=
            candidates_value || jsonb_build_array(candidate_value);

        -- Candidate authority intentionally excludes inventory metadata.
        -- A SOLD_OUT <-> AVAILABLE change must not invalidate fit authority.
        fingerprint_candidates_value :=
            fingerprint_candidates_value || jsonb_build_array(
                jsonb_build_object(
                    'product_size_id', size_row.product_size_id,
                    'size_label', size_row.size_label,
                    'canonical_measurements', canonical_value,
                    'comparison_measurements', comparison_measurements_value,
                    'authorization', authorization_value
                )
            );
    end loop;

    if effective_value ->> 'effective_source' = 'GLOBAL_CONFIRMED' then
        authority_version_value := 'fitmatch-vnext-candidates-20260908-global-v1';
        authority_fingerprint_value := encode(
            extensions.digest(
                concat_ws(
                    '|',
                    reference_row.id::text,
                    target_row.id::text,
                    p_target_variant_id::text,
                    p_manual_explicit::text,
                    fingerprint_candidates_value::text,
                    authority_version_value
                ),
                'sha256'
            ),
            'hex'
        );
    else
        authority_version_value := 'fitmatch-vnext-candidates-20260908-effective-v1';
        authority_fingerprint_value := encode(
            extensions.digest(
                concat_ws(
                    '|',
                    reference_row.id::text,
                    target_row.id::text,
                    p_target_variant_id::text,
                    p_manual_explicit::text,
                    effective_value ->> 'effective_authority_fingerprint',
                    effective_value ->> 'override_revision',
                    fingerprint_candidates_value::text,
                    authority_version_value
                ),
                'sha256'
            ),
            'hex'
        );
    end if;

    return jsonb_build_object(
        'allowed', jsonb_array_length(candidates_value) > 0,
        'decision', case
            when jsonb_array_length(candidates_value) > 0 then
                coalesce(
                    candidates_value -> 0 -> 'authorization' ->> 'decision',
                    'BLOCKED'
                )
            else 'BLOCKED'
        end,
        'reason_code', case when jsonb_array_length(candidates_value)>0
            then candidates_value->0->'authorization'->>'reason_code'
            else coalesce(rejected_reason_code_value,'NO_ELIGIBLE_TARGET_SIZE') end,
        'mode', case
            when jsonb_array_length(candidates_value) > 0 then
                coalesce(
                    candidates_value -> 0 -> 'authorization' ->> 'mode',
                    'NONE'
                )
            else 'NONE'
        end,
        'reason', case
            when jsonb_array_length(candidates_value) > 0
                then 'Database-generated eligible candidate set'
            when total_size_count_value = 0
                then 'Target variant has no sizes'
            when semantic_conflict_count_value > 0
                then 'Canonical measurement semantic conflict'
            else 'No size satisfies comparison authorization and measurement minimums'
        end,
        'reference_closet_item_id', reference_row.id,
        'target_product_id', target_row.id,
        'target_variant_id', p_target_variant_id,
        'manual_explicit', p_manual_explicit,
        'classification_source', effective_value ->> 'effective_source',
        'effective_authority_fingerprint',
            effective_value ->> 'effective_authority_fingerprint',
        'override_revision', effective_value -> 'override_revision',
        'authorized_candidate_product_size_ids', coalesce((
            select jsonb_agg(candidate -> 'product_size_id')
            from jsonb_array_elements(candidates_value) candidate
        ), '[]'::jsonb),
        'candidates', candidates_value,
        'diagnostics', jsonb_build_object(
            'total_size_count', total_size_count_value,
            'latest_available_count', available_count_value,
            'latest_sold_out_count', sold_out_count_value,
            'latest_unknown_or_missing_count', unknown_count_value,
            'expired_or_unbounded_available_count',
                expired_available_count_value,
            'semantic_conflict_count', semantic_conflict_count_value,
            'authorization_rejected_count',
                authorization_rejected_count_value,
            'inventory_ignored_for_eligibility', true
        ),
        'candidate_authority_fingerprint', authority_fingerprint_value,
        'candidate_authority_version', authority_version_value
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.eligible_candidate_sizes(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_variant_id uuid, p_manual_explicit boolean, p_requested_group_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.get_product_runtime_for_swift(p_source_code text, p_source_product_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    runtime_value jsonb;
    effective_value jsonb;
    product_id_value uuid;
    category_value text;
    policy_value text;
    variant_value jsonb;
    size_value jsonb;
    variants_value jsonb := '[]'::jsonb;
    sizes_value jsonb;
begin
    runtime_value := fitmatch_vnext.get_product_runtime_base(
        p_source_code, p_source_product_key, false
    );
    if not coalesce((runtime_value ->> 'found')::boolean, false) then
        return runtime_value;
    end if;
    product_id_value := (runtime_value -> 'product' ->> 'id')::uuid;
    effective_value := fitmatch_vnext.effective_target_classification(
        product_id_value
    );

    select gt.category_code, gt.comparison_policy_code
    into category_value, policy_value
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code =
          runtime_value -> 'product' ->> 'garment_type_code'
      and gt.is_active;
    runtime_value := jsonb_set(runtime_value, '{product}',
        runtime_value -> 'product' || jsonb_build_object(
            'category_code', category_value,
            'comparison_policy_code', policy_value
        )
    );

    for variant_value in
        select value from jsonb_array_elements(runtime_value -> 'variants')
    loop
        sizes_value := '[]'::jsonb;
        for size_value in
            select value from jsonb_array_elements(variant_value -> 'sizes')
        loop
            size_value := jsonb_set(
                size_value,
                '{canonical_measurements}',
                fitmatch_vnext.canonical_measurements_for_size_with_context(
                    (size_value ->> 'id')::uuid,
                    effective_value
                )
            );
            sizes_value := sizes_value || jsonb_build_array(size_value);
        end loop;
        variant_value := jsonb_set(variant_value, '{sizes}', sizes_value);
        variants_value := variants_value || jsonb_build_array(variant_value);
    end loop;

    runtime_value := jsonb_set(runtime_value, '{variants}', variants_value);
    runtime_value := jsonb_set(
        runtime_value,
        '{readiness}',
        fitmatch_vnext.effective_product_readiness(product_id_value)
    );
    return runtime_value || jsonb_build_object(
        'effective_classification', effective_value
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.product_measurement_readiness(p_product_id uuid, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with product_row as (
  select p.*,
    p_effective_classification->>'classification_status' effective_status,
    p_effective_classification->>'comparison_policy_code' effective_policy_code,
    fitmatch_vnext.product_comparison_unit_decision(p.id) comparison_unit
  from fitmatch_vnext.products p where p.id=p_product_id
), policy_metrics as (
  select cm.fitmatch_measurement_code
  from product_row p
  join fitmatch_vnext.comparison_policies cp
    on cp.policy_code=p.effective_policy_code and cp.is_active
  join fitmatch_vnext.comparison_metrics cm
    on cm.comparison_policy_code=cp.policy_code
   and cm.metric_mode='CANONICAL' and cm.is_active
), size_diagnostics as (
  select ps.id product_size_id,ps.size_label,
    coalesce((canonical.payload->>'raw_measurement_count')::integer,0) raw_measurement_count,
    coalesce((canonical.payload->>'semantic_conflict_count')::integer,0) semantic_conflict_count,
    count(distinct measurement->>'fitmatch_measurement_code') canonical_measurement_count,
    count(distinct pm.fitmatch_measurement_code) policy_measurement_count
  from product_row p
  join fitmatch_vnext.product_variants pv on pv.product_id=p.id
  join fitmatch_vnext.product_sizes ps on ps.variant_id=pv.id
  cross join lateral (
    select fitmatch_vnext.canonical_measurements_for_size_with_context(
      ps.id,p_effective_classification
    ) payload
  ) canonical
  left join lateral jsonb_array_elements(canonical.payload->'measurements') measurement on true
  left join policy_metrics pm
    on pm.fitmatch_measurement_code=measurement->>'fitmatch_measurement_code'
  group by ps.id,ps.size_label,canonical.payload
), ready_sizes as (
  select * from size_diagnostics
  where semantic_conflict_count=0 and policy_measurement_count>=1
)
select case when not exists(select 1 from product_row) then
  jsonb_build_object(
    'status','CLASSIFICATION_REQUIRED','ready',false,
    'reason_code','CLASSIFICATION_REQUIRED','reason','Unknown product',
    'readiness_version','fitmatch-vnext-readiness-group-only-v1',
    'inventory_ignored_for_readiness',true
  )
else (
  select jsonb_build_object(
    'product_id',p.id,
    'ready',p.effective_status='CONFIRMED'
      and coalesce((p.comparison_unit->>'eligible')::boolean,false)
      and exists(select 1 from ready_sizes),
    'status',case
      when p.effective_status<>'CONFIRMED' then 'CLASSIFICATION_REQUIRED'
      when not coalesce((p.comparison_unit->>'eligible')::boolean,false) then 'NOT_APPLICABLE'
      when not exists(select 1 from policy_metrics) then 'POLICY_UNAVAILABLE'
      when not exists(select 1 from size_diagnostics) then 'NO_AVAILABLE_SIZE'
      when not exists(select 1 from size_diagnostics where raw_measurement_count>0)
        then 'NO_MEASUREMENT_DATA'
      when not exists(select 1 from size_diagnostics
        where semantic_conflict_count=0 and policy_measurement_count>0)
        then 'INSUFFICIENT_MEASUREMENTS'
      else 'READY' end,
    'reason',case
      when p.effective_status<>'CONFIRMED' then 'Comparison group is required'
      when not coalesce((p.comparison_unit->>'eligible')::boolean,false)
        then p.comparison_unit->>'reason'
      when not exists(select 1 from policy_metrics) then 'No active comparison group policy metrics'
      when not exists(select 1 from size_diagnostics) then 'Product has no size rows'
      when not exists(select 1 from size_diagnostics where raw_measurement_count>0)
        then 'Product sizes have no raw measurement evidence'
      when not exists(select 1 from size_diagnostics
        where semantic_conflict_count=0 and policy_measurement_count>0)
        then 'No semantically usable group-policy measurement'
      else 'Comparison group and measurement evidence are ready' end,
    'comparison_policy_code',p.effective_policy_code,
    'comparison_unit',p.comparison_unit,
    'ready_sizes',coalesce((select jsonb_agg(jsonb_build_object(
      'product_size_id',r.product_size_id,'size_label',r.size_label,
      'resolved_measurement_count',r.policy_measurement_count,
      'canonical_measurement_count',r.canonical_measurement_count,
      'required_any_count',0,'semantic_conflict_count',r.semantic_conflict_count,
      'availability_status','UNKNOWN'
    ) order by r.size_label,r.product_size_id) from ready_sizes r),'[]'::jsonb),
    'size_diagnostics',coalesce((select jsonb_agg(jsonb_build_object(
      'product_size_id',d.product_size_id,'size_label',d.size_label,
      'raw_measurement_count',d.raw_measurement_count,
      'canonical_measurement_count',d.canonical_measurement_count,
      'policy_measurement_count',d.policy_measurement_count,
      'required_any_count',0,'semantic_conflict_count',d.semantic_conflict_count,
      'availability_status','UNKNOWN'
    ) order by d.size_label,d.product_size_id) from size_diagnostics d),'[]'::jsonb),
    'readiness_version','fitmatch-vnext-readiness-group-only-v1',
    'inventory_ignored_for_readiness',true,'minimum_common',1,'required_any_min',0
  ) from product_row p
)
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.protect_completed_comparison()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
    if old.result_status = 'COMPLETED' and (
        new.user_id is distinct from old.user_id
        or new.client_comparison_id is distinct from old.client_comparison_id
        or new.reference_closet_item_id is distinct from old.reference_closet_item_id
        or new.target_product_id is distinct from old.target_product_id
        or new.target_variant_id is distinct from old.target_variant_id
        or new.comparison_policy_code_snapshot is distinct from old.comparison_policy_code_snapshot
        or new.comparison_mode is distinct from old.comparison_mode
        or new.recommended_product_size_id is distinct from old.recommended_product_size_id
        or new.recommended_size_label is distinct from old.recommended_size_label
        or new.fit_score is distinct from old.fit_score
        or new.reliability_level is distinct from old.reliability_level
        or new.coverage_ratio is distinct from old.coverage_ratio
        or new.result_status is distinct from old.result_status
        or new.engine_version is distinct from old.engine_version
        or new.detail_snapshot is distinct from old.detail_snapshot
        or new.request_payload_hash is distinct from old.request_payload_hash
        or new.result_payload_hash is distinct from old.result_payload_hash
        or new.authorization_mode is distinct from old.authorization_mode
        or new.excluded_measurement_codes is distinct from old.excluded_measurement_codes
        or new.reference_snapshot is distinct from old.reference_snapshot
        or new.target_snapshot is distinct from old.target_snapshot
        or new.authority_snapshot is distinct from old.authority_snapshot
        or new.policy_snapshot is distinct from old.policy_snapshot
        or new.authorization_snapshot is distinct from old.authorization_snapshot
        or new.input_snapshot is distinct from old.input_snapshot
        or new.result_evidence is distinct from old.result_evidence
        or new.completed_at is distinct from old.completed_at
    ) then
        raise exception 'Completed comparison core history is immutable';
    end if;
    return new;
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.hide_comparison_history(p_client_comparison_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
    requested_ids uuid[];
    owned_comparison_ids uuid[];
    changed_count integer;
begin
    if caller_id is null then
        raise exception 'FM_HISTORY_AUTH_REQUIRED'
            using errcode = '42501';
    end if;

    if p_client_comparison_ids is null then
        raise exception 'FM_HISTORY_INVALID_IDS'
            using errcode = '22023';
    end if;

    if coalesce(array_ndims(p_client_comparison_ids), 1) <> 1 then
        raise exception 'FM_HISTORY_INVALID_IDS'
            using errcode = '22023';
    end if;

    if array_position(p_client_comparison_ids, null) is not null then
        raise exception 'FM_HISTORY_INVALID_IDS'
            using errcode = '22023';
    end if;

    select coalesce(
        array_agg(ids.id order by ids.id),
        array[]::uuid[]
    )
    into requested_ids
    from (
        select distinct unnest(p_client_comparison_ids) as id
    ) ids;


    -- 현재 로그인 사용자가 소유한 COMPLETED 기록만 허용
    select coalesce(
        array_agg(locked.id order by locked.id),
        array[]::uuid[]
    )
    into owned_comparison_ids
    from (
        select c.id
        from fitmatch_vnext.comparisons c
        where c.user_id = caller_id
          and c.client_comparison_id = any(requested_ids)
          and c.result_status = 'COMPLETED'
        order by c.id
        for update
    ) locked;


    -- 존재하지 않거나,
    -- 다른 사용자 기록이거나,
    -- COMPLETED가 아닌 ID가 하나라도 있으면 전체 실패
    if cardinality(owned_comparison_ids)
        <> cardinality(requested_ids) then

        raise exception 'FM_HISTORY_UNAVAILABLE'
            using errcode = '42501';
    end if;


    -- 실제 삭제가 아니라 soft-hide
    update fitmatch_vnext.comparisons c
    set deleted_at = now()
    where c.id = any(owned_comparison_ids)
      and c.user_id = caller_id
      and c.result_status = 'COMPLETED'
      and c.deleted_at is null;

    get diagnostics changed_count = row_count;


    return jsonb_build_object(
        'client_comparison_ids',
            to_jsonb(requested_ids),

        'hidden',
            true,

        'idempotent',
            changed_count = 0
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.comparison_history_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then
        raise exception 'FM_HISTORY_AUTH_REQUIRED'
            using errcode = '42501';
    end if;

    return jsonb_build_object(
        -- Retain the existing active-history projection exactly.  The new
        -- envelope does not reinterpret ordinary omission as a tombstone.
        'histories', fitmatch_vnext.comparison_history(),
        'tombstones', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'client_comparison_id', comparison_value.client_comparison_id,
                    'hidden_at', comparison_value.deleted_at
                )
                order by comparison_value.deleted_at asc, comparison_value.id
            )
            from fitmatch_vnext.comparisons comparison_value
            where comparison_value.user_id = caller_id
              and comparison_value.result_status = 'COMPLETED'
              and comparison_value.deleted_at is not null
        ), '[]'::jsonb)
    );
end;
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.comparison_history()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    return coalesce((
        select jsonb_agg(
            to_jsonb(comparison_value) || jsonb_build_object(
                'reference_client_item_id', closet_value.client_item_id,
                'target_source_product_key', product_value.source_product_key,
                'target_category_code', garment_value.category_code
            )
            order by comparison_value.created_at desc, comparison_value.id
        )
        from fitmatch_vnext.comparisons comparison_value
        left join fitmatch_vnext.comparison_result_heads head
          on head.user_id = comparison_value.user_id
         and head.target_product_id = comparison_value.target_product_id
         and head.comparison_id = comparison_value.id
        left join fitmatch_vnext.closet_items closet_value
          on closet_value.id = comparison_value.reference_closet_item_id
         and closet_value.user_id = comparison_value.user_id
        left join fitmatch_vnext.products product_value
          on product_value.id = comparison_value.target_product_id
        left join fitmatch_vnext.garment_types garment_value
          on garment_value.garment_type_code = product_value.garment_type_code
        where comparison_value.user_id = caller_id
          and comparison_value.deleted_at is null
          and (
              comparison_value.result_status <> 'COMPLETED'
              or head.comparison_id is not null
          )
    ), '[]'::jsonb);
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.validate_comparison_completion_payload()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
    reliability_value numeric;
begin
    if new.result_status <> 'COMPLETED' then
        return new;
    end if;

    reliability_value := (new.result_evidence ->> 'reliability')::numeric;
    if reliability_value <> trunc(reliability_value)
       or reliability_value <> new.reliability_level::numeric then
        raise exception 'Completion reliability must be an integer matching the stored summary';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(
            new.result_evidence -> 'candidate_size_ranking'
        ) ranking
        where (ranking ->> 'rank')::numeric < 1
           or (ranking ->> 'rank')::numeric <>
                trunc((ranking ->> 'rank')::numeric)
    ) then
        raise exception 'Candidate ranks must be positive integers';
    end if;

    if (new.result_evidence ->> 'recommended_product_size_id')::uuid
            is distinct from new.recommended_product_size_id
       or (new.result_evidence ->> 'score')::numeric is distinct from new.fit_score
       or (new.result_evidence ->> 'coverage')::numeric
            is distinct from new.coverage_ratio
       or new.result_evidence ->> 'engine_version' is distinct from new.engine_version then
        raise exception 'Completion evidence summary must match stored comparison columns';
    end if;

    return new;
end
$function$
;