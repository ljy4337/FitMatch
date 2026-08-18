-- FitMatch product runtime safe rollback (manual operation only)
--
-- Purpose: stop all new client traffic without deleting shared/user data.
-- This is intentionally not a migration and must not be run during normal
-- deployment. Re-enable by reapplying the grants in migration 083/084.

begin;

set local lock_timeout='10s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtext('fitmatch:product-runtime-safe-rollback'));

-- Stop authenticated clients from entering the new runtime.
revoke execute on function public.fitmatch_resolve_product(jsonb)
  from authenticated,service_role;
revoke execute on function public.fitmatch_register_closet_item(uuid,uuid,boolean,jsonb)
  from authenticated,service_role;
revoke execute on function public.fitmatch_set_closet_classification_override(uuid,jsonb)
  from authenticated,service_role;
revoke execute on function public.fitmatch_clear_closet_classification_override(uuid)
  from authenticated,service_role;
revoke execute on function public.fitmatch_begin_comparison(uuid,uuid,boolean)
  from authenticated,service_role;
revoke execute on function public.fitmatch_complete_comparison(uuid,jsonb)
  from authenticated,service_role;
revoke execute on function public.fitmatch_find_reference_candidates(uuid)
  from authenticated,service_role;

-- Stop trusted batch promotion as well. Existing catalog/history remains.
revoke execute on function fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)
  from service_role;

-- Stop future collection rows from mutating the operational product layer.
-- Existing source snapshots and all runtime data remain recoverable.
drop trigger if exists source_product_snapshots_sync_product
  on fitmatch_catalog.source_product_snapshots;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'fitmatch_%'
      and p.prosecdef
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
  ) then
    raise exception 'authenticated runtime RPC execute privilege remains';
  end if;
end $$;

commit;

-- No DROP TABLE / DELETE is included. Full teardown is deliberately omitted:
-- after user writes exist, dropping these relations would be destructive and
-- must be designed against a confirmed backup and an explicit maintenance
-- window.
