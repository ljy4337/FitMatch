-- Reactivate the logically rolled-back refinement only after 013 succeeds.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:taxonomy-refined-2026-08-03'));

do $$
declare
  v_counts jsonb;
begin
  if not exists (
    select 1
    from fitmatch_taxonomy.policy_versions
    where code = 'taxonomy-refined-2026-08-03' and status = 'rolled_back'
  ) then
    raise exception 'Refined policy is absent or is not rolled_back';
  end if;

  if (select count(*) from fitmatch_taxonomy.promotion_manifests
      where policy_version = 'taxonomy-refined-2026-08-03'
        and manifest_checksum = '1e3e31c248f9d28ebea1c5cbb32d4f0a4fa00830d17f094caa92cb8a31f8d59b'
        and status = 'rolled_back') <> 1 then
    raise exception 'Expected one rolled-back refinement manifest with the approved checksum';
  end if;

  select jsonb_object_agg(decision_status, n) into v_counts
  from (
    select decision_status, count(*)::integer n
    from fitmatch_taxonomy.classification_decisions
    where policy_version = 'taxonomy-refined-2026-08-03'
    group by decision_status
  ) s;

  if v_counts <> '{"confirmed":1331,"review_required":608,"rejected":1447,"unsupported":40,"navigation_only":582}'::jsonb then
    raise exception 'Unexpected refined status counts: %', v_counts;
  end if;

  if (select count(*) from fitmatch_taxonomy.category_app_mappings
      where comparison_policy_version = 'taxonomy-refined-2026-08-03') <> 1331
     or (select count(*) from fitmatch_taxonomy.classification_audit_history
         where canonical_policy_version = 'taxonomy-refined-2026-08-03') <> 4008
     or (select count(*) from fitmatch_taxonomy.comparison_compatibility_rules
         where policy_version = 'taxonomy-refined-2026-08-03') <> 19
     or (select count(*) from fitmatch_taxonomy.garment_measurement_policies
         where policy_version = 'taxonomy-refined-2026-08-03') <> 15 then
    raise exception 'Refined policy dependent-row counts are incomplete';
  end if;
end $$;

update fitmatch_taxonomy.promotion_manifests
set status = 'validated',
    validated_at = transaction_timestamp(),
    validation_result = (coalesce(validation_result, '{}'::jsonb)
      - 'logical_rollback' - 'physical_delete')
      || '{"passed":true,"reactivated_after_validation":true}'::jsonb
where policy_version = 'taxonomy-refined-2026-08-03'
  and status = 'rolled_back';

update fitmatch_taxonomy.policy_versions
set status = 'validated', validated_at = transaction_timestamp()
where code = 'taxonomy-refined-2026-08-03'
  and status = 'rolled_back';

commit;
