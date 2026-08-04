-- Logical rollback only: no physical DELETE and no predecessor mutation.
begin;
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:taxonomy-refined-2026-08-03'));
do $$
begin
  if not exists (select 1 from fitmatch_taxonomy.policy_versions where code='taxonomy-refined-2026-08-03') then
    raise exception 'Policy taxonomy-refined-2026-08-03 does not exist';
  end if;
  if not exists (select 1 from fitmatch_taxonomy.policy_versions where code='taxonomy-final-2026-08-03' and status='validated') then
    raise exception 'Validated predecessor policy is unavailable';
  end if;
end $$;
update fitmatch_taxonomy.promotion_manifests
set status='rolled_back', validation_result=coalesce(validation_result,'{}'::jsonb) || '{"logical_rollback":true,"physical_delete":false}'::jsonb
where policy_version='taxonomy-refined-2026-08-03' and status <> 'rolled_back';
update fitmatch_taxonomy.policy_versions set status='rolled_back' where code='taxonomy-refined-2026-08-03';
commit;
