-- Recovery for 20260914090000_session_requested_comparison_group_authority.sql.
-- Apply in one transaction while comparison traffic is stopped.
begin;

drop function if exists public.fitmatch_vnext_find_reference_candidates(
  uuid,uuid,text
);
drop function if exists public.fitmatch_vnext_eligible_candidate_sizes(
  uuid,uuid,uuid,boolean,text
);
drop function if exists fitmatch_vnext.find_reference_candidates(uuid,uuid,text);
drop function if exists fitmatch_vnext.eligible_candidate_sizes(
  uuid,uuid,uuid,boolean,text
);
drop function if exists fitmatch_vnext.authorize_comparison_with_context_v1(
  uuid,uuid,uuid,boolean,jsonb,text
);
drop function if exists fitmatch_vnext.authorize_comparison_with_context(
  uuid,uuid,uuid,boolean,jsonb,text
);
drop function if exists fitmatch_vnext.comparison_target_context(uuid,uuid,text);
drop function if exists fitmatch_vnext.canonical_measurements_for_session_group(
  uuid,jsonb
);
drop function if exists fitmatch_vnext.begin_comparison(jsonb);
alter function fitmatch_vnext.begin_comparison_legacy_20260914(jsonb)
  rename to begin_comparison;
revoke all on function fitmatch_vnext.begin_comparison(jsonb) from public, anon;
grant execute on function fitmatch_vnext.begin_comparison(jsonb)
  to authenticated, service_role;

commit;
