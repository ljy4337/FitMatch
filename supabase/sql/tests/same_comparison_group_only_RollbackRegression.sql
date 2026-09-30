-- LOCAL ONLY: verifies that the recovery SQL restores the exact immediate
-- predecessor (the explicit-cross-group migration), not an older baseline.
\set ON_ERROR_STOP on
\ir explicit_cross_group_comparison_Regression.sql
\ir ../../migrations/20260923110000_same_comparison_group_only.sql
\ir ../20260923_same_comparison_group_only_Rollback.sql

do $$
begin
  if exists (
    select 1
    from (
      values
        ('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)', 'f836b497b0a9536ecd86e5205b234b7f'),
        ('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)', 'fa7f2992178f1f7f9936197cf889addd'),
        ('fitmatch_vnext.find_reference_candidates(uuid,uuid)', '26c8a4e2d3b797280accc26135e848c9'),
        ('fitmatch_vnext.find_reference_candidates(uuid,uuid,text)', '01e858c178895e6aa9f88a3a84a16943')
    ) as expected(signature, definition_hash)
    where md5(pg_get_functiondef(signature::regprocedure)) is distinct from definition_hash
  ) then
    raise exception 'Rollback did not restore the reviewed cross-group function definitions';
  end if;
end
$$;

select 'PASS: same-group migration rollback restores reviewed predecessor' as result;
