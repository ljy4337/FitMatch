-- READ ONLY postflight: no user RPC execution or data mutations.
select to_regprocedure('public.fitmatch_vnext_find_selected_reference_candidate(uuid,uuid,uuid,text)') is not null as endpoint_exists,
 has_function_privilege('authenticated','public.fitmatch_vnext_find_selected_reference_candidate(uuid,uuid,uuid,text)','EXECUTE') as authenticated_allowed,
 not has_function_privilege('anon','public.fitmatch_vnext_find_selected_reference_candidate(uuid,uuid,uuid,text)','EXECUTE') as anon_denied,
 not has_function_privilege('authenticated','fitmatch_vnext.find_reference_candidates_filtered(uuid,uuid,uuid)','EXECUTE') as mapped_helper_private,
 not has_function_privilege('authenticated','fitmatch_vnext.find_reference_candidates_filtered(uuid,uuid,text,uuid)','EXECUTE') as session_helper_private;
select p.proname,pg_get_function_identity_arguments(p.oid) args,md5(pg_get_functiondef(p.oid)) definition_hash
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='fitmatch_vnext' and p.proname in
('eligible_candidate_sizes','authorize_comparison_with_context','begin_comparison','complete_comparison');
