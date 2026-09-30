-- Category-group-first reference discovery.
-- Measurements never hide or classify a Closet candidate here.

begin;

create or replace function fitmatch_vnext.find_reference_candidates(
  p_target_product_id uuid,
  p_target_variant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  target_row fitmatch_vnext.products%rowtype;
  target_group jsonb;
  target_group_code text;
  closet_row fitmatch_vnext.closet_items%rowtype;
  closet_group jsonb;
  closet_group_code text;
  all_target_size_ids uuid[];
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

  select coalesce(array_agg(ps.id order by pv.sort_order,ps.sort_order,ps.id),'{}'::uuid[])
    into all_target_size_ids
  from fitmatch_vnext.product_variants pv
  join fitmatch_vnext.product_sizes ps on ps.variant_id=pv.id
  where pv.product_id=target_row.id
    and (p_target_variant_id is null or pv.id=p_target_variant_id);

  select count(*) into same_group_count
  from fitmatch_vnext.closet_items ci
  where ci.user_id=caller_id and ci.deleted_at is null
    and ci.comparison_group_code=target_group_code;

  for closet_row in
    select * from fitmatch_vnext.closet_items ci
    where ci.user_id=caller_id and ci.deleted_at is null
    order by ci.is_reference desc,ci.updated_at desc,ci.id
  loop
    closet_group := fitmatch_vnext.closet_comparison_group(closet_row.id);
    closet_group_code := closet_group->>'group_code';

    if target_group_code is null then
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'COMPARISON_GROUP_REQUIRED';
      reason_value := '상품의 비교 그룹을 먼저 선택해 주세요.';
    elsif closet_group_code=target_group_code and closet_row.is_reference then
      decision_value := 'AUTOMATIC';
      allowed_value := true;
      reason_code_value := 'AUTOMATIC_MATCH';
      reason_value := '같은 그룹의 기준 옷입니다.';
    elsif closet_group_code=target_group_code then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '같은 그룹에서 직접 선택할 수 있습니다.';
    elsif (target_group_code='A' and closet_group_code='B')
       or (target_group_code='B' and closet_group_code='A') then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '상의와 아우터를 직접 선택해 비교할 수 있습니다.';
    else
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'INCOMPATIBLE_BODY_REGION';
      reason_value := '측정하는 신체 부위가 달라 비교할 수 없습니다.';
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
      'common_measurement_count',null,
      'excluded_measurement_codes','[]'::jsonb,
      'required_measurement_codes','[]'::jsonb,
      'eligible_product_size_ids',case when allowed_value
        then to_jsonb(all_target_size_ids) else '[]'::jsonb end,
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
    'selection_policy','CATEGORY_GROUP_ONLY',
    'measurements_used_for_candidate_selection',false,
    'reference_candidate_version','fitmatch-vnext-group-candidates-v1'
  );
end
$function$;

update fitmatch_catalog.comparison_group_policies
set metadata=jsonb_set(metadata,'{candidate_selection}','"CATEGORY_GROUP_ONLY"'::jsonb,true)
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
