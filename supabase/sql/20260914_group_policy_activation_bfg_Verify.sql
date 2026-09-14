-- Read-only postflight for 20260914080000_group_policy_activation_bfg.sql.
select gt.garment_type_code,
  gt.category_code,
  gt.is_active as garment_type_active,
  cp.policy_code,
  cp.is_active as policy_active,
  cp.min_common_measurements,
  cp.required_any_min,
  cp.audience_policy_code,
  cp.allow_manual_extended,
  cp.sleeve_mismatch_policy,
  cp.lower_length_mismatch_policy,
  cp.body_length_mismatch_policy,
  cp.policy_version,
  cp.policy_checksum,
  count(cm.id) filter (where cm.is_active) as active_metric_count
from fitmatch_vnext.garment_types gt
join fitmatch_vnext.comparison_policies cp
  on cp.policy_code = gt.comparison_policy_code
left join fitmatch_vnext.comparison_metrics cm
  on cm.comparison_policy_code = cp.policy_code
where gt.garment_type_code in (
  'comparison_group_outerwear',
  'comparison_group_innerwear',
  'comparison_group_homewear'
)
group by gt.garment_type_code, gt.category_code, gt.is_active,
  cp.policy_code, cp.is_active, cp.min_common_measurements,
  cp.required_any_min, cp.audience_policy_code, cp.allow_manual_extended,
  cp.sleeve_mismatch_policy, cp.lower_length_mismatch_policy,
  cp.body_length_mismatch_policy, cp.policy_version, cp.policy_checksum
order by gt.garment_type_code;
