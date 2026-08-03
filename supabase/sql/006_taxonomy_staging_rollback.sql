-- Recovery is scoped to one import run and relies on ON DELETE CASCADE only
-- inside fitmatch_staging. Existing public source_categories and mappings are
-- referenced with ON DELETE RESTRICT and are never deleted or updated.
begin;
update fitmatch_staging.import_runs
set status = 'rolled_back', completed_at = null,
    failure_reason = coalesce(failure_reason, 'operator-requested staging rollback')
where id = :'import_run_id'::uuid and status <> 'completed';
delete from fitmatch_staging.import_runs
where id = :'import_run_id'::uuid and status = 'rolled_back';
commit;

