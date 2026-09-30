-- Roll back only 20260928100000_align_top_comparison_policy.sql.
-- Do not run while active comparison traffic depends on the newer policy.

begin;

update fitmatch_vnext.comparison_policies cp
set min_common_measurements = 2,
    required_any_min = 1,
    policy_version = 'vnext-policy-20260902-adult-any-v1',
    policy_checksum = '7f9ad432607553a54d1eaa9b7f836c45fc5f16d07eed38764ddaba607205b1dc',
    updated_at = now()
where cp.policy_code = 'tshirt';

update fitmatch_vnext.comparison_metrics cm
set weight = case
      when cm.fitmatch_measurement_code in ('chest_width', 'chest_circumference') then 1.4
      when cm.fitmatch_measurement_code = 'shoulder_width' then 1.2
      when cm.fitmatch_measurement_code = 'sleeve_length' then 0.8
      when cm.fitmatch_measurement_code in ('total_length', 'back_length') then 1.0
      when cm.source_measurement_code like '%.chest_width.%' then 1.4
      when cm.source_measurement_code like '%.shoulder_width.%' then 1.2
      when cm.source_measurement_code like '%.sleeve_length.%' then 0.8
      when cm.source_measurement_code like '%.back_length.%' then 1.0
      else cm.weight
    end,
    requirement_mode = case
      when cm.metric_mode = 'CANONICAL'
       and cm.fitmatch_measurement_code in ('chest_width', 'chest_circumference', 'shoulder_width')
        then 'REQUIRED_ANY'
      else 'OPTIONAL'
    end,
    updated_at = now()
where cm.comparison_policy_code = 'tshirt'
  and cm.is_active;

commit;
