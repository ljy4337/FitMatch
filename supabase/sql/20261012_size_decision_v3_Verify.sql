-- Read-only checks. Execute after the v3 migration on each environment.
select position('fitmatch_vnext.validate_size_decision_v3(row_value.target_snapshot, p_result)'
  in pg_get_functiondef('fitmatch_vnext.complete_comparison(uuid,jsonb)'::regprocedure)) > 0 as validator_connected,
  has_function_privilege('authenticated','fitmatch_vnext.validate_size_decision_v3(jsonb,jsonb)','EXECUTE') as helper_exposed_to_authenticated,
  has_function_privilege('anon','fitmatch_vnext.validate_size_decision_v3(jsonb,jsonb)','EXECUTE') as helper_exposed_to_anon;
