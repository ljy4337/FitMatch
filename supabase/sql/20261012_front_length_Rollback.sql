-- A policy rollback affects new comparisons only. Completed snapshots stay intact.
begin;
do $guard$
begin
 if (select count(*) from fitmatch_vnext.comparison_policies
     where policy_code in ('tshirt','unclassified_outerwear')
       and policy_version like '%+front-20261012-v1') <> 2 then
   raise exception 'Front policy version changed; inspect before rollback';
 end if;
end
$guard$;
delete from fitmatch_vnext.comparison_metrics
where comparison_policy_code in ('tshirt','unclassified_outerwear')
  and metric_mode='CANONICAL' and fitmatch_measurement_code='front_length_shoulder_to_hem';
update fitmatch_vnext.comparison_policies
set policy_version=regexp_replace(policy_version,'\+front-20261012-v1$',''),updated_at=now()
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
