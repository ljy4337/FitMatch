-- Separate rollout step AFTER the installed client minimum supports the exact
-- front_length_shoulder_to_hem code. Older clients reject unknown metric codes.
-- Do not include this activation in automatic migrations before that gate.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
do $preflight$
begin
 if not exists (select 1 from fitmatch_vnext.fitmatch_measurements
   where measurement_code='front_length_shoulder_to_hem' and is_active
     and canonical_unit_code='cm' and canonical_basis_code='front_shoulder_to_hem') then
   raise exception 'Exact front-length canonical semantics are missing or changed';
 end if;
 if (select count(*) from fitmatch_vnext.comparison_metrics m
     join fitmatch_vnext.comparison_policies p on p.policy_code=m.comparison_policy_code
     where p.is_active and m.is_active and m.metric_mode='CANONICAL'
       and m.fitmatch_measurement_code='back_length'
       and p.policy_code in ('tshirt','unclassified_outerwear')) <> 2 then
   raise exception 'Expected A/B group length policies are missing';
 end if;
 if exists (select 1 from fitmatch_vnext.comparison_metrics
     where comparison_policy_code in ('tshirt','unclassified_outerwear')
       and fitmatch_measurement_code='front_length_shoulder_to_hem') then
   raise exception 'Front-length policy already exists; inspect before reapplying';
 end if;
end
$preflight$;
insert into fitmatch_vnext.comparison_metrics
 (comparison_policy_code, metric_mode, fitmatch_measurement_code, weight, requirement_mode, priority, is_active)
select comparison_policy_code,'CANONICAL','front_length_shoulder_to_hem',weight,'OPTIONAL',priority,true
from fitmatch_vnext.comparison_metrics
where comparison_policy_code in ('tshirt','unclassified_outerwear')
  and metric_mode='CANONICAL' and fitmatch_measurement_code='back_length' and is_active;
update fitmatch_vnext.comparison_policies
set policy_version=policy_version || '+front-20261012-v1', updated_at=now()
where policy_code in ('tshirt','unclassified_outerwear');
update fitmatch_vnext.comparison_policies cp
set policy_checksum=encode(extensions.digest(concat_ws('|', cp.policy_code,
  cp.min_common_measurements::text,cp.required_any_min::text,
  cp.audience_policy_code,cp.sleeve_mismatch_policy,
  cp.lower_length_mismatch_policy,cp.body_length_mismatch_policy,
  cp.allow_manual_extended::text,cp.sleeve_mismatch_excluded_codes::text,
  cp.lower_mismatch_excluded_codes::text,cp.body_mismatch_excluded_codes::text,
  cp.policy_version,cp.is_active::text),'sha256'),'hex')
where cp.policy_code in ('tshirt','unclassified_outerwear');
commit;
