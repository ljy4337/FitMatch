-- User-approved policy, 2026-09-16: explicit comparisons across groups use
-- >=1 common canonical policy measurement. Identity/auth/unit/audience/semantic
-- checks remain intact. Target: hnkplvyegonlhumlejst (user-designated dev DB).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $patch_0$
declare definition text;
begin
 if md5(pg_get_functiondef('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure)) <> 'a4975338645f210bc4f9f3b74339de8b' then
  raise exception 'Function changed since reviewed preflight: fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)';
 end if;
 definition := replace(pg_get_functiondef('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure), E'\r\n', E'\n');
 definition := replace(definition, $old_0$IF ref_gt.comparison_policy_code IS DISTINCT FROM target_gt.comparison_policy_code$old_0$, $new_0$-- Explicit cross-group choice is evaluated by common canonical evidence below.
  IF NOT coalesce(p_manual_explicit,false)
     AND ref_gt.comparison_policy_code IS DISTINCT FROM target_gt.comparison_policy_code$new_0$);
 execute definition;
end $patch_0$;

do $patch_1$
declare definition text;
begin
 if md5(pg_get_functiondef('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure)) <> '7bc50170473cbd59e52c10f42607b4cf' then
  raise exception 'Function changed since reviewed preflight: fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)';
 end if;
 definition := replace(pg_get_functiondef('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure), E'\r\n', E'\n');
 definition := replace(definition, $old_0$if fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then$old_0$, $new_0$if not coalesce(p_manual_explicit, false) and
       fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then$new_0$);
 definition := replace(definition, $old_1$if ref_gt.comparison_policy_code is distinct from target_gt.comparison_policy_code$old_1$, $new_1$-- Explicit cross-group choice is evaluated by common canonical evidence below.
    if not coalesce(p_manual_explicit, false)
       and ref_gt.comparison_policy_code is distinct from target_gt.comparison_policy_code$new_1$);
 execute definition;
end $patch_1$;

do $patch_2$
declare definition text;
begin
 if md5(pg_get_functiondef('fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure)) <> '35eb381d953adca14bb192bb9187d7cc' then
  raise exception 'Function changed since reviewed preflight: fitmatch_vnext.find_reference_candidates(uuid,uuid)';
 end if;
 definition := replace(pg_get_functiondef('fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure), E'\r\n', E'\n');
 definition := replace(definition, $old_0$elsif (target_group_code='A' and closet_group_code='B')
       or (target_group_code='B' and closet_group_code='A') then$old_0$, $new_0$elsif target_group_code in ('A','B','C','D','E','F','G')
       and closet_group_code in ('A','B','C','D','E','F','G') then$new_0$);
 definition := replace(definition, $old_1$상의와 아우터를 직접 선택해 비교할 수 있습니다.$old_1$, $new_1$다른 그룹의 옷도 공통 실측으로 직접 선택해 비교할 수 있습니다.$new_1$);
 definition := replace(definition, $old_2$reason_code_value := 'INCOMPATIBLE_BODY_REGION';$old_2$, $new_2$reason_code_value := 'COMPARISON_GROUP_REQUIRED';$new_2$);
 definition := replace(definition, $old_3$측정하는 신체 부위가 달라 비교할 수 없습니다.$old_3$, $new_3$옷의 비교 그룹을 먼저 확인해 주세요.$new_3$);
 definition := replace(definition, $old_4$'CATEGORY_GROUP_ONLY'$old_4$, $new_4$'GROUP_WITH_EXPLICIT_CROSS_GROUP'$new_4$);
 definition := replace(definition, $old_5$'fitmatch-vnext-group-candidates-v1'$old_5$, $new_5$'fitmatch-vnext-cross-group-candidates-v2'$new_5$);
 execute definition;
end $patch_2$;

do $patch_3$
declare definition text;
begin
 if md5(pg_get_functiondef('fitmatch_vnext.find_reference_candidates(uuid,uuid,text)'::regprocedure)) <> 'cf96a2a6370a49f57990babd0568adc7' then
  raise exception 'Function changed since reviewed preflight: fitmatch_vnext.find_reference_candidates(uuid,uuid,text)';
 end if;
 definition := replace(pg_get_functiondef('fitmatch_vnext.find_reference_candidates(uuid,uuid,text)'::regprocedure), E'\r\n', E'\n');
 definition := replace(definition, $old_0$if closet_group->>'group_code' is distinct from target_group_code then$old_0$, $new_0$if closet_group->>'group_code' is null
       or closet_group->>'group_code' not in ('A','B','C','D','E','F','G') then$new_0$);
 definition := replace(definition, $old_1$'reason_code', 'INCOMPATIBLE_BODY_REGION'$old_1$, $new_1$'reason_code', 'COMPARISON_GROUP_REQUIRED'$new_1$);
 definition := replace(definition, $old_2$'reason', 'Reference comparison group does not match requested group'$old_2$, $new_2$'reason', 'Reference comparison group is missing or invalid'$new_2$);
 definition := replace(definition, $old_3$'same_comparison_group', true$old_3$, $new_3$'same_comparison_group', closet_group->>'group_code' = target_group_code$new_3$);
 definition := replace(definition, $old_4$'SESSION_REQUESTED_GROUP_ONLY'$old_4$, $new_4$'SESSION_GROUP_WITH_EXPLICIT_CROSS_GROUP'$new_4$);
 definition := replace(definition, $old_5$'fitmatch-vnext-session-group-candidates-v1'$old_5$, $new_5$'fitmatch-vnext-session-cross-group-candidates-v2'$new_5$);
 execute definition;
end $patch_3$;

commit;
