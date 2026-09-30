-- 2026-09-23 product-comparison policy: only the same FitMatch comparison
-- group may be selected. This reverses the explicit cross-group allowance from
-- 20260916000904 without changing measurement, ownership, or score policy.
--
-- Preflight is intentionally definition-specific. Do not apply this migration
-- if a function has changed since the reviewed cross-group version.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $patch_native_authorization$
declare
  definition text;
  old_fragment constant text := $old$-- Explicit cross-group choice is evaluated by common canonical evidence below.
  IF NOT coalesce(p_manual_explicit,false)
     AND ref_gt.comparison_policy_code IS DISTINCT FROM target_gt.comparison_policy_code
     AND NOT (ref_domain=target_domain AND ref_domain IN ('UPPER_BODY','LOWER_BODY')) THEN$old$;
  new_fragment constant text := $new$-- Same FitMatch comparison group is required before policy evidence is evaluated.
  IF fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       IS DISTINCT FROM effective_value->>'comparison_group_code' THEN
    reason_code_value := 'COMPARISON_GROUP_REQUIRED';
    reason_value := 'Reference comparison group does not match target group';
    EXIT evaluate_pair;
  END IF;
  IF ref_gt.comparison_policy_code IS DISTINCT FROM target_gt.comparison_policy_code
     AND NOT (ref_domain=target_domain AND ref_domain IN ('UPPER_BODY','LOWER_BODY')) THEN$new$;
begin
  if md5(pg_get_functiondef(
    'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure
  )) <> 'f836b497b0a9536ecd86e5205b234b7f' then
    raise exception 'Function changed since reviewed preflight: fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)';
  end if;
  definition := replace(pg_get_functiondef(
    'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure
  ), E'\r\n', E'\n');
  if position(old_fragment in definition) = 0
     or position(
       old_fragment in substring(
         definition from position(old_fragment in definition) + char_length(old_fragment)
       )
     ) <> 0 then
    raise exception 'Expected one native cross-group authorization fragment';
  end if;
  definition := replace(definition, old_fragment, new_fragment);
  execute definition;
end $patch_native_authorization$;

do $patch_session_authorization$
declare
  definition text;
  old_group_fragment constant text := $old$if not coalesce(p_manual_explicit, false) and
       fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then$old$;
  new_group_fragment constant text := $new$if fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then$new$;
  old_policy_fragment constant text := $old$-- Explicit cross-group choice is evaluated by common canonical evidence below.
    if not coalesce(p_manual_explicit, false)
       and ref_gt.comparison_policy_code is distinct from target_gt.comparison_policy_code
       and not (ref_domain = target_domain and ref_domain in ('UPPER_BODY','LOWER_BODY')) then$old$;
  new_policy_fragment constant text := $new$if ref_gt.comparison_policy_code is distinct from target_gt.comparison_policy_code
       and not (ref_domain = target_domain and ref_domain in ('UPPER_BODY','LOWER_BODY')) then$new$;
begin
  if md5(pg_get_functiondef(
    'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure
  )) <> 'fa7f2992178f1f7f9936197cf889addd' then
    raise exception 'Function changed since reviewed preflight: fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)';
  end if;
  definition := replace(pg_get_functiondef(
    'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure
  ), E'\r\n', E'\n');
  if position(old_group_fragment in definition) = 0
     or position(old_policy_fragment in definition) = 0 then
    raise exception 'Expected session cross-group authorization fragments';
  end if;
  definition := replace(definition, old_group_fragment, new_group_fragment);
  definition := replace(definition, old_policy_fragment, new_policy_fragment);
  execute definition;
end $patch_session_authorization$;

do $patch_native_candidates$
declare
  definition text;
  old_fragment constant text := $old$elsif target_group_code in ('A','B','C','D','E','F','G')
       and closet_group_code in ('A','B','C','D','E','F','G') then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '다른 그룹의 옷도 공통 실측으로 직접 선택해 비교할 수 있습니다.';$old$;
  new_fragment constant text := $new$elsif closet_group_code is distinct from target_group_code then
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'COMPARISON_GROUP_REQUIRED';
      reason_value := 'Reference comparison group does not match target group';$new$;
begin
  if md5(pg_get_functiondef(
    'fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure
  )) not in (
    '26c8a4e2d3b797280accc26135e848c9', -- reviewed local regression predecessor
    'f41bff3567974479e72bc9f989aa7fbb'  -- deployed predecessor: retains eligible-size validation
  ) then
    raise exception 'Function changed since reviewed preflight: fitmatch_vnext.find_reference_candidates(uuid,uuid)';
  end if;
  definition := replace(pg_get_functiondef(
    'fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure
  ), E'\r\n', E'\n');
  if position(old_fragment in definition) = 0 then
    raise exception 'Expected native cross-group candidate fragment';
  end if;
  definition := replace(definition, old_fragment, new_fragment);
  execute definition;
end $patch_native_candidates$;

do $patch_session_candidates$
declare
  definition text;
  old_group_fragment constant text := $old$if closet_group->>'group_code' is null
       or closet_group->>'group_code' not in ('A','B','C','D','E','F','G') then$old$;
  new_group_fragment constant text := $new$if closet_group->>'group_code' is distinct from target_group_code then$new$;
begin
  if md5(pg_get_functiondef(
    'fitmatch_vnext.find_reference_candidates(uuid,uuid,text)'::regprocedure
  )) <> '01e858c178895e6aa9f88a3a84a16943' then
    raise exception 'Function changed since reviewed preflight: fitmatch_vnext.find_reference_candidates(uuid,uuid,text)';
  end if;
  definition := replace(pg_get_functiondef(
    'fitmatch_vnext.find_reference_candidates(uuid,uuid,text)'::regprocedure
  ), E'\r\n', E'\n');
  if position(old_group_fragment in definition) = 0 then
    raise exception 'Expected session cross-group candidate fragment';
  end if;
  definition := replace(definition, old_group_fragment, new_group_fragment);
  definition := replace(definition,
    $old$'reason_code', 'COMPARISON_GROUP_REQUIRED'$old$,
    $new$'reason_code', 'INCOMPATIBLE_BODY_REGION'$new$
  );
  definition := replace(definition,
    $old$'reason', 'Reference comparison group is missing or invalid'$old$,
    $new$'reason', 'Reference comparison group does not match requested group'$new$
  );
  definition := replace(definition,
    $old$'same_comparison_group', closet_group->>'group_code' = target_group_code$old$,
    $new$'same_comparison_group', true$new$
  );
  definition := replace(definition,
    $old$'SESSION_GROUP_WITH_EXPLICIT_CROSS_GROUP'$old$,
    $new$'SESSION_REQUESTED_GROUP_ONLY'$new$
  );
  definition := replace(definition,
    $old$'fitmatch-vnext-session-cross-group-candidates-v2'$old$,
    $new$'fitmatch-vnext-session-group-candidates-v1'$new$
  );
  execute definition;
end $patch_session_candidates$;

commit;
