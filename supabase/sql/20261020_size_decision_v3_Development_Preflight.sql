-- Read-only preflight for development hnkplvyegonlhumlejst.
-- Applying the v3 migration requires separate authorization.
begin transaction read only;

with completion as (
  select pg_get_functiondef('fitmatch_vnext.complete_comparison(uuid,jsonb)'::regprocedure) definition
)
select
  to_regprocedure('fitmatch_vnext.validate_size_decision_v3(jsonb,jsonb)') is not null as validator_exists,
  position('fitmatch_vnext.validate_size_decision_v3(row_value.target_snapshot, p_result)' in definition) > 0 as validator_connected,
  (length(definition) - length(replace(definition, '    select count(*) into policy_metric_count', '')))
    / length('    select count(*) into policy_metric_count') as patch_anchor_count,
  position('recommended_user_recovery_size_id' in definition) > 0 as recovery_identity_supported
from completion;

select measurement_code, canonical_unit_code, canonical_basis_code, is_active
from fitmatch_vnext.fitmatch_measurements
where measurement_code = 'front_length_shoulder_to_hem';

select m.comparison_policy_code, m.fitmatch_measurement_code, m.weight, m.is_active
from fitmatch_vnext.comparison_metrics m
join fitmatch_vnext.comparison_policies p on p.policy_code = m.comparison_policy_code
where p.policy_code in ('tshirt', 'unclassified_outerwear')
  and p.is_active
  and m.fitmatch_measurement_code in ('back_length', 'front_length_shoulder_to_hem')
order by 1, 2;

rollback;
