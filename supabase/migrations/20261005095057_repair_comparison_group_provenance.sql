-- Preserve the deployed signature, owner, ACL and search_path.
-- Only mapping provenance changes; groups, scoring and user data are untouched.
do $preflight$
begin
  if md5(regexp_replace(pg_get_functiondef(
      'fitmatch_vnext.comparison_target_context(uuid,uuid,text)'::regprocedure
    ), '\s+', ' ', 'g')) <> '653383c60fe7336c529b267b1cb4eac3' then
    raise exception 'Comparison context changed since audit; review migration before applying';
  end if;
end
$preflight$;

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
