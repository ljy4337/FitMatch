-- Superseded BEFORE application by 20260915064910_cleanup_retired_paths_and_align_group_readiness.
-- The original proposal could mislabel an unverified measurement contract as
-- NOT_APPLICABLE and rewrite existing ACLs. It must not overwrite the repaired
-- wrapper. Kept as a read-only compatibility gate for pending migration replay.
-- Historical proposal is retained in CleanupArchive/20260915.
do $verify_current_contract$
declare
    body text;
begin
    select prosrc into body from pg_proc
    where oid=to_regprocedure('fitmatch_vnext.product_readiness_with_context(uuid,jsonb)');
    if body is null
       or body not like '%product_measurement_readiness(%'
       or body not like '%product_comparison_unit_decision(%'
       or body like '%product_readiness_with_context_v1(%' then
        raise exception 'Apply the reviewed group-readiness cleanup before replaying this superseded proposal';
    end if;
end
$verify_current_contract$;
