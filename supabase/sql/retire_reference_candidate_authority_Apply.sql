-- User-confirmed development project hnkplvyegonlhumlejst.
-- Retire legacy reference decision authority; preserve auth/identity/evidence gates.

DO $guard$ BEGIN IF md5(pg_get_functiondef('fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure)) NOT IN ('26c8a4e2d3b797280accc26135e848c9','f41bff3567974479e72bc9f989aa7fbb') THEN RAISE EXCEPTION 'Candidate function drift: fitmatch_vnext.find_reference_candidates(uuid,uuid)'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION fitmatch_vnext.find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  eligible_value jsonb;
  eligible_size_ids_value jsonb;
  eligible_common_count integer;
  checked_variant record;
  eligibility_reason text;
  caller_id uuid := auth.uid();
  target_row fitmatch_vnext.products%rowtype;
  target_group jsonb;
  target_group_code text;
  closet_row fitmatch_vnext.closet_items%rowtype;
  closet_group jsonb;
  closet_group_code text;
  same_group_count integer;
  decision_value text;
  allowed_value boolean;
  reason_code_value text;
  reason_value text;
  item_value jsonb;
  candidates_value jsonb := '[]'::jsonb;
  blocked_value jsonb := '[]'::jsonb;
  all_items_value jsonb := '[]'::jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select * into target_row from fitmatch_vnext.products p
  where p.id=p_target_product_id;
  if not found then raise exception 'Target product not found'; end if;

  if p_target_variant_id is not null and not exists (
    select 1 from fitmatch_vnext.product_variants pv
    where pv.id=p_target_variant_id and pv.product_id=target_row.id
  ) then
    raise exception 'Target variant hierarchy mismatch';
  end if;

  target_group := fitmatch_vnext.product_comparison_group(target_row.id);
  target_group_code := target_group->>'group_code';

  select count(*) into same_group_count
  from fitmatch_vnext.closet_items ci
  where ci.user_id=caller_id and ci.deleted_at is null
    and ci.comparison_group_code=target_group_code;

  for closet_row in
    select * from fitmatch_vnext.closet_items ci
    where ci.user_id=caller_id and ci.deleted_at is null
    order by ci.updated_at desc,ci.id
  loop
    closet_group := fitmatch_vnext.closet_comparison_group(closet_row.id);
    closet_group_code := closet_group->>'group_code';

    if target_group_code is null then
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'COMPARISON_GROUP_REQUIRED';
      reason_value := '상품의 비교 그룹을 먼저 선택해 주세요.';
    elsif closet_group_code=target_group_code then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '같은 그룹에서 직접 선택할 수 있습니다.';
    elsif target_group_code in ('A','B','C','D','E','F','G')
       and closet_group_code in ('A','B','C','D','E','F','G') then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '다른 그룹의 옷도 공통 실측으로 직접 선택해 비교할 수 있습니다.';
    else
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'COMPARISON_GROUP_REQUIRED';
      reason_value := '옷의 비교 그룹을 먼저 확인해 주세요.';
    end if;

    eligible_size_ids_value := '[]'::jsonb;
    eligible_common_count := 0;
    eligibility_reason := null;
    if allowed_value then
      for checked_variant in
        select pv.id from fitmatch_vnext.product_variants pv
        where pv.product_id=target_row.id
          and (p_target_variant_id is null or pv.id=p_target_variant_id)
        order by pv.sort_order,pv.id
      loop
        eligible_value := fitmatch_vnext.eligible_candidate_sizes(
          closet_row.id,target_row.id,checked_variant.id,true
        );
        if coalesce((eligible_value->>'allowed')::boolean,false) then
          eligible_size_ids_value := eligible_size_ids_value ||
            coalesce(eligible_value->'authorized_candidate_product_size_ids','[]'::jsonb);
          eligible_common_count := greatest(eligible_common_count,
            jsonb_array_length(coalesce(
              eligible_value->'candidates'->0->'comparison_measurements','[]'::jsonb)));
        else
          eligibility_reason := coalesce(eligibility_reason,eligible_value->>'reason_code');
        end if;
      end loop;
      if jsonb_array_length(eligible_size_ids_value)=0 then
        allowed_value := false;
        decision_value := 'BLOCKED';
        reason_code_value := coalesce(eligibility_reason,'NO_ELIGIBLE_TARGET_SIZE');
        reason_value := '공통 실측 등 비교 조건을 충족하는 사이즈가 없습니다.';
      end if;
    end if;

    item_value := jsonb_build_object(
      'closet_item_id',closet_row.id,
      'item_name',closet_row.item_name,
      'size_label',closet_row.size_label,
      'product_id',closet_row.product_id,
      'variant_id',closet_row.product_variant_id,
      'product_size_id',closet_row.product_size_id,
      'is_current_reference',closet_row.is_reference,
      'decision',decision_value,
      'allowed',allowed_value,
      'mode',case when decision_value='AUTOMATIC' then 'AUTOMATIC'
                  when decision_value='MANUAL_EXTENDED' then 'MANUAL_EXTENDED'
                  else 'NONE' end,
      'manual_explicit_required',decision_value='MANUAL_EXTENDED',
      'reason_code',reason_code_value,
      'reason',reason_value,
      'common_measurement_count',eligible_common_count,
      'excluded_measurement_codes','[]'::jsonb,
      'required_measurement_codes','[]'::jsonb,
      'eligible_product_size_ids',case when allowed_value
        then eligible_size_ids_value else '[]'::jsonb end,
      'comparison_group',closet_group,
      'same_comparison_group',closet_group_code=target_group_code
    );

    all_items_value := all_items_value || jsonb_build_array(item_value);
    if allowed_value then
      candidates_value := candidates_value || jsonb_build_array(item_value);
    else
      blocked_value := blocked_value || jsonb_build_array(item_value);
    end if;
  end loop;

  return jsonb_build_object(
    'target_product_id',target_row.id,
    'target_variant_id',p_target_variant_id,
    'effective_classification',fitmatch_vnext.effective_target_classification(target_row.id),
    'comparison_group',target_group,
    'candidates',candidates_value,
    'blocked',blocked_value,
    'fallback_closet_items',case when same_group_count=0
      then all_items_value else '[]'::jsonb end,
    'candidate_count',jsonb_array_length(candidates_value),
    'blocked_count',jsonb_array_length(blocked_value),
    'same_group_count',same_group_count,
    'status',case when jsonb_array_length(candidates_value)>0
      then 'READY' else 'NO_REFERENCE_CANDIDATE' end,
    'selection_policy','GROUP_WITH_EXPLICIT_CROSS_GROUP',
    'measurements_used_for_candidate_selection',true,
    'reference_candidate_version','fitmatch-vnext-explicit-candidates-v3'
  );
end
$function$
;

DO $guard$ BEGIN IF md5(pg_get_functiondef('public.fitmatch_vnext_find_reference_candidates(uuid,uuid)'::regprocedure)) NOT IN ('7cca325d4e90fb7b1ddef1f37f0cdc0d','310b3e76f4dfc6a80268d07347397325') THEN RAISE EXCEPTION 'Candidate function drift: public.fitmatch_vnext_find_reference_candidates(uuid,uuid)'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION public.fitmatch_vnext_find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  result_value jsonb;
  target_group jsonb;
  candidates_value jsonb;
  blocked_value jsonb;
begin
  result_value := fitmatch_vnext.find_reference_candidates(
    p_target_product_id,p_target_variant_id
  );
  target_group := fitmatch_vnext.product_comparison_group(p_target_product_id);

  select coalesce(jsonb_agg(enriched order by
      case when enriched->'comparison_group'->>'group_code'=target_group->>'group_code'
           then 0 else 1 end,
      ordinal), '[]'::jsonb)
    into candidates_value
  from (
    select item || jsonb_build_object(
      'comparison_group',fitmatch_vnext.closet_comparison_group(
        (item->>'closet_item_id')::uuid
      ),
      'same_comparison_group',
        fitmatch_vnext.closet_comparison_group((item->>'closet_item_id')::uuid)
          ->>'group_code'=target_group->>'group_code'
    ) as enriched, ordinal
    from jsonb_array_elements(coalesce(result_value->'candidates','[]'::jsonb))
      with ordinality rows(item,ordinal)
  ) q;

  select coalesce(jsonb_agg(item || jsonb_build_object(
      'comparison_group',fitmatch_vnext.closet_comparison_group(
        (item->>'closet_item_id')::uuid
      )
    ) order by ordinal),'[]'::jsonb)
    into blocked_value
  from jsonb_array_elements(coalesce(result_value->'blocked','[]'::jsonb))
    with ordinality rows(item,ordinal);

  return result_value || jsonb_build_object(
    'comparison_group',target_group,
    'candidates',candidates_value,
    'blocked',blocked_value,
    'group_selection_policy','same_group_then_all_explicit'
  );
end
$function$
;
