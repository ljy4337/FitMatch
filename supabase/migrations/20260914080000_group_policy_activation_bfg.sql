-- Activates only the existing B/F/G group policies for the current
-- group-first comparison contract. Apply before
-- 20260914090000_session_requested_comparison_group_authority.sql.
-- Prepared migration: do not apply to Production from this repository.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '60s';

do $preflight$
begin
  if (select count(*) from fitmatch_vnext.garment_types gt
      where (gt.garment_type_code, gt.category_code, gt.comparison_policy_code)
        in (
          ('comparison_group_outerwear', 'outerwear', 'unclassified_outerwear'),
          ('comparison_group_innerwear', 'underwear', 'generic_underwear'),
          ('comparison_group_homewear', 'homewear', 'homewear_set')
        )
        and gt.is_active) <> 3 then
    raise exception 'Expected active B/F/G group garment types are missing';
  end if;

  if (select count(*) from fitmatch_vnext.comparison_policies cp
      where cp.policy_code in (
        'unclassified_outerwear', 'generic_underwear', 'homewear_set'
      )) <> 3 then
    raise exception 'Expected B/F/G comparison policies are missing';
  end if;

  if exists (
    select 1
    from fitmatch_vnext.comparison_policies cp
    where cp.policy_code in (
      'unclassified_outerwear', 'generic_underwear', 'homewear_set'
    )
      and not exists (
        select 1
        from fitmatch_vnext.comparison_metrics cm
        where cm.comparison_policy_code = cp.policy_code
          and cm.is_active
      )
  ) then
    raise exception 'B/F/G policy has no active comparison metric';
  end if;
end
$preflight$;

-- The current group contract permits an explicit, same-group reference when
-- at least one canonical measurement is common. Keep the existing metrics and
-- mismatch exclusions; only repair the stale inactive/gating policy fields.
update fitmatch_vnext.comparison_policies cp
set is_active = true,
    min_common_measurements = 1,
    required_any_min = 0,
    audience_policy_code = 'ADULT_ANY',
    allow_manual_extended = true,
    policy_version = 'vnext-policy-20260914-group-session-v1',
    updated_at = now()
where cp.policy_code in (
  'unclassified_outerwear', 'generic_underwear', 'homewear_set'
);

update fitmatch_vnext.comparison_policies cp
set policy_checksum = encode(extensions.digest(concat_ws('|', cp.policy_code,
  cp.min_common_measurements::text, cp.required_any_min::text,
  cp.audience_policy_code, cp.sleeve_mismatch_policy,
  cp.lower_length_mismatch_policy, cp.body_length_mismatch_policy,
  cp.allow_manual_extended::text, cp.sleeve_mismatch_excluded_codes::text,
  cp.lower_mismatch_excluded_codes::text, cp.body_mismatch_excluded_codes::text,
  cp.policy_version, cp.is_active::text), 'sha256'), 'hex')
where cp.policy_code in (
  'unclassified_outerwear', 'generic_underwear', 'homewear_set'
);

do $postflight$
begin
  if exists (
    select 1
    from fitmatch_vnext.comparison_policies cp
    where cp.policy_code in (
      'unclassified_outerwear', 'generic_underwear', 'homewear_set'
    )
      and (
        not cp.is_active
        or cp.min_common_measurements <> 1
        or cp.required_any_min <> 0
        or cp.audience_policy_code <> 'ADULT_ANY'
        or not cp.allow_manual_extended
        or cp.policy_version <> 'vnext-policy-20260914-group-session-v1'
        or nullif(cp.policy_checksum, '') is null
      )
  ) then
    raise exception 'B/F/G policy activation postflight failed';
  end if;
end
$postflight$;

commit;
