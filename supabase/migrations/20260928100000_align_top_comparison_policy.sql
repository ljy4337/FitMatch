-- Align the server-owned top-group policy with the approved FitMatch contract.
-- This changes policy metadata only. It does not rewrite products, Closet rows,
-- measurements, comparison history, mappings, or user selections.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '60s';

do $preflight$
begin
  if not exists (
    select 1
    from fitmatch_vnext.comparison_policies cp
    where cp.policy_code = 'tshirt'
      and cp.is_active
  ) then
    raise exception 'Expected active tshirt comparison policy is missing';
  end if;

  if (
    select count(*)
    from fitmatch_vnext.comparison_metrics cm
    where cm.comparison_policy_code = 'tshirt'
      and cm.metric_mode = 'CANONICAL'
      and cm.is_active
      and cm.fitmatch_measurement_code in (
        'chest_width',
        'chest_circumference',
        'shoulder_width',
        'total_length',
        'sleeve_length'
      )
  ) <> 5 then
    raise exception 'Expected active top canonical metric set is missing';
  end if;
end
$preflight$;

-- A single approved common canonical measurement is enough to compare.
-- All top metrics are optional candidates; no individual item is mandatory.
update fitmatch_vnext.comparison_policies cp
set min_common_measurements = 1,
    required_any_min = 0,
    policy_version = 'vnext-policy-20260928-top-one-common-v1',
    updated_at = now()
where cp.policy_code = 'tshirt';

update fitmatch_vnext.comparison_metrics cm
set weight = case
      when cm.fitmatch_measurement_code in ('chest_width', 'chest_circumference') then 2.0
      when cm.fitmatch_measurement_code = 'shoulder_width' then 1.5
      when cm.fitmatch_measurement_code = 'total_length' then 1.0
      when cm.fitmatch_measurement_code = 'sleeve_length' then 1.0
      when cm.source_measurement_code like '%.chest_width.%' then 2.0
      when cm.source_measurement_code like '%.shoulder_width.%' then 1.5
      when cm.source_measurement_code like '%.sleeve_length.%' then 1.0
      when cm.source_measurement_code like '%.back_length.%' then 1.0
      else cm.weight
    end,
    requirement_mode = 'OPTIONAL',
    updated_at = now()
where cm.comparison_policy_code = 'tshirt'
  and cm.is_active;

update fitmatch_vnext.comparison_policies cp
set policy_checksum = encode(extensions.digest(concat_ws('|', cp.policy_code,
  cp.min_common_measurements::text, cp.required_any_min::text,
  cp.audience_policy_code, cp.sleeve_mismatch_policy,
  cp.lower_length_mismatch_policy, cp.body_length_mismatch_policy,
  cp.allow_manual_extended::text, cp.sleeve_mismatch_excluded_codes::text,
  cp.lower_mismatch_excluded_codes::text, cp.body_mismatch_excluded_codes::text,
  cp.policy_version, cp.is_active::text), 'sha256'), 'hex')
where cp.policy_code = 'tshirt';

do $postflight$
begin
  if exists (
    select 1
    from fitmatch_vnext.comparison_policies cp
    where cp.policy_code = 'tshirt'
      and (
        not cp.is_active
        or cp.min_common_measurements <> 1
        or cp.required_any_min <> 0
        or cp.policy_version <> 'vnext-policy-20260928-top-one-common-v1'
        or nullif(cp.policy_checksum, '') is null
      )
  ) then
    raise exception 'Top comparison policy postflight failed';
  end if;

  if exists (
    select 1
    from fitmatch_vnext.comparison_metrics cm
    where cm.comparison_policy_code = 'tshirt'
      and cm.is_active
      and (
        cm.requirement_mode <> 'OPTIONAL'
        or (cm.fitmatch_measurement_code in ('chest_width', 'chest_circumference') and cm.weight <> 2.0)
        or (cm.fitmatch_measurement_code = 'shoulder_width' and cm.weight <> 1.5)
        or (cm.fitmatch_measurement_code in ('total_length', 'sleeve_length') and cm.weight <> 1.0)
        or (cm.source_measurement_code like '%.chest_width.%' and cm.weight <> 2.0)
        or (cm.source_measurement_code like '%.shoulder_width.%' and cm.weight <> 1.5)
        or (cm.source_measurement_code like '%.sleeve_length.%' and cm.weight <> 1.0)
        or (cm.source_measurement_code like '%.back_length.%' and cm.weight <> 1.0)
      )
  ) then
    raise exception 'Top comparison metrics postflight failed';
  end if;
end
$postflight$;

commit;
