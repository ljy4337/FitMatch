-- Read-only verification for 20260928100000_align_top_comparison_policy.sql.
select cp.policy_code,
  cp.is_active,
  cp.min_common_measurements,
  cp.required_any_min,
  cp.policy_version,
  cp.policy_checksum,
  cm.metric_mode,
  cm.fitmatch_measurement_code,
  cm.source_measurement_code,
  cm.weight,
  cm.requirement_mode,
  cm.is_active as metric_is_active
from fitmatch_vnext.comparison_policies cp
join fitmatch_vnext.comparison_metrics cm
  on cm.comparison_policy_code = cp.policy_code
where cp.policy_code = 'tshirt'
order by cm.metric_mode, cm.fitmatch_measurement_code nulls last,
  cm.source_measurement_code nulls last;
