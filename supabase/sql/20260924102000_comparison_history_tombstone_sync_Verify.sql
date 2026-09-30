-- Read-only post-apply checks for 20260924102000. Run as a privileged
-- migration verifier; this script does not create, update, or delete data.
select
    to_regprocedure('fitmatch_vnext.comparison_history_sync()')
        as private_sync_function,
    to_regprocedure('public.fitmatch_vnext_comparison_history_sync()')
        as public_sync_function,
    has_function_privilege(
        'authenticated',
        'public.fitmatch_vnext_comparison_history_sync()',
        'EXECUTE'
    ) as authenticated_can_sync,
    has_function_privilege(
        'anon',
        'public.fitmatch_vnext_comparison_history_sync()',
        'EXECUTE'
    ) as anon_can_sync,
    has_function_privilege(
        'authenticated',
        'fitmatch_vnext.comparison_history_sync()',
        'EXECUTE'
    ) as authenticated_can_call_private;

select
    procedure.prosecdef as private_security_definer,
    procedure.proconfig @> array['search_path=""']::text[] as fixed_search_path
from pg_proc procedure
where procedure.oid = 'fitmatch_vnext.comparison_history_sync()'::regprocedure;
