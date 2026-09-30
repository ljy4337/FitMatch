-- Non-destructive rollback for 20260924102000.
-- Apply only after clients no longer call the additive sync RPC. Existing
-- comparison rows and deleted_at timestamps are intentionally preserved.
begin;

revoke all on function public.fitmatch_vnext_comparison_history_sync()
from public, anon, authenticated, service_role;
revoke all on function fitmatch_vnext.comparison_history_sync()
from public, anon, authenticated, service_role;

drop function if exists public.fitmatch_vnext_comparison_history_sync();
drop function if exists fitmatch_vnext.comparison_history_sync();

notify pgrst, 'reload schema';

commit;
