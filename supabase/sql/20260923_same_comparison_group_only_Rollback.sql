-- Recovery for 20260923110000_same_comparison_group_only.sql only.
-- Apply only while comparison traffic is stopped and only after confirming the
-- exact marker fragments below. This restores the immediately preceding
-- explicit-cross-group behavior; it does not roll back older migrations.
begin;

do $rollback_native_authorization$
declare definition text;
begin
  definition := replace(pg_get_functiondef(
    'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure
  ), E'\r\n', E'\n');
  if position('Same FitMatch comparison group is required before policy evidence is evaluated.' in definition) = 0 then
    raise exception 'Expected same-group native authorization marker';
  end if;
  definition := replace(definition, $old$-- Same FitMatch comparison group is required before policy evidence is evaluated.
  IF fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       IS DISTINCT FROM effective_value->>'comparison_group_code' THEN
    reason_code_value := 'COMPARISON_GROUP_REQUIRED';
    reason_value := 'Reference comparison group does not match target group';
    EXIT evaluate_pair;
  END IF;
  IF ref_gt.comparison_policy_code IS DISTINCT FROM target_gt.comparison_policy_code
     AND NOT (ref_domain=target_domain AND ref_domain IN ('UPPER_BODY','LOWER_BODY')) THEN$old$, $new$-- Explicit cross-group choice is evaluated by common canonical evidence below.
  IF NOT coalesce(p_manual_explicit,false)
     AND ref_gt.comparison_policy_code IS DISTINCT FROM target_gt.comparison_policy_code
     AND NOT (ref_domain=target_domain AND ref_domain IN ('UPPER_BODY','LOWER_BODY')) THEN$new$);
  if position('Same FitMatch comparison group is required before policy evidence is evaluated.' in definition) <> 0 then
    raise exception 'Native authorization rollback replacement did not apply';
  end if;
  execute definition;
end $rollback_native_authorization$;

do $rollback_session_authorization$
declare definition text;
begin
  definition := replace(pg_get_functiondef(
    'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure
  ), E'\r\n', E'\n');
  if position($old$if fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then$old$ in definition) = 0 then
    raise exception 'Expected same-group session authorization marker';
  end if;
  definition := replace(definition, $old$if fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then$old$, $new$if not coalesce(p_manual_explicit, false) and
       fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then$new$);
  definition := replace(definition, $old$if ref_gt.comparison_policy_code is distinct from target_gt.comparison_policy_code
       and not (ref_domain = target_domain and ref_domain in ('UPPER_BODY','LOWER_BODY')) then$old$, $new$-- Explicit cross-group choice is evaluated by common canonical evidence below.
    if not coalesce(p_manual_explicit, false)
       and ref_gt.comparison_policy_code is distinct from target_gt.comparison_policy_code
       and not (ref_domain = target_domain and ref_domain in ('UPPER_BODY','LOWER_BODY')) then$new$);
  execute definition;
end $rollback_session_authorization$;

do $rollback_native_candidates$
declare definition text;
begin
  definition := replace(pg_get_functiondef(
    'fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure
  ), E'\r\n', E'\n');
  if position($old$elsif closet_group_code is distinct from target_group_code then
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'COMPARISON_GROUP_REQUIRED';
      reason_value := 'Reference comparison group does not match target group';$old$ in definition) = 0 then
    raise exception 'Expected same-group native candidate marker';
  end if;
  definition := replace(definition, $old$elsif closet_group_code is distinct from target_group_code then
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'COMPARISON_GROUP_REQUIRED';
      reason_value := 'Reference comparison group does not match target group';$old$, $new$elsif target_group_code in ('A','B','C','D','E','F','G')
       and closet_group_code in ('A','B','C','D','E','F','G') then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '다른 그룹의 옷도 공통 실측으로 직접 선택해 비교할 수 있습니다.';$new$);
  execute definition;
end $rollback_native_candidates$;

do $rollback_session_candidates$
declare definition text;
begin
  definition := replace(pg_get_functiondef(
    'fitmatch_vnext.find_reference_candidates(uuid,uuid,text)'::regprocedure
  ), E'\r\n', E'\n');
  if position($old$if closet_group->>'group_code' is distinct from target_group_code then$old$ in definition) = 0 then
    raise exception 'Expected same-group session candidate marker';
  end if;
  definition := replace(definition, $old$if closet_group->>'group_code' is distinct from target_group_code then$old$, $new$if closet_group->>'group_code' is null
       or closet_group->>'group_code' not in ('A','B','C','D','E','F','G') then$new$);
  definition := replace(definition, $old$'reason_code', 'INCOMPATIBLE_BODY_REGION'$old$, $new$'reason_code', 'COMPARISON_GROUP_REQUIRED'$new$);
  definition := replace(definition, $old$'reason', 'Reference comparison group does not match requested group'$old$, $new$'reason', 'Reference comparison group is missing or invalid'$new$);
  definition := replace(definition, $old$'same_comparison_group', true$old$, $new$'same_comparison_group', closet_group->>'group_code' = target_group_code$new$);
  definition := replace(definition, $old$'SESSION_REQUESTED_GROUP_ONLY'$old$, $new$'SESSION_GROUP_WITH_EXPLICIT_CROSS_GROUP'$new$);
  definition := replace(definition, $old$'fitmatch-vnext-session-group-candidates-v1'$old$, $new$'fitmatch-vnext-session-cross-group-candidates-v2'$new$);
  execute definition;
end $rollback_session_candidates$;

commit;
