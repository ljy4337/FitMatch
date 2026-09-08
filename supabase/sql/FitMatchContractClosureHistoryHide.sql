-- FitMatch Contract Closure: manual, production-operator SQL only.
--
-- This file is intentionally NOT a migration and is not executed by the iOS
-- app or this change. Apply it manually only after reviewing the target
-- database. It preserves the existing deleted_at visibility model; it never
-- changes comparison evidence, snapshot, category, or policy data.

begin;

-- Do not replace an unrelated implementation which may already be deployed.
-- The existing repository implementation is recognized by all of the stable
-- semantic fragments below; anything else stops before CREATE OR REPLACE.
do $fitmatch_history_install_guard$
declare
    existing_definition text;
begin
    select pg_get_functiondef(p.oid)
    into existing_definition
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'fitmatch_vnext'
      and p.proname = 'hide_comparison_history'
      and pg_get_function_identity_arguments(p.oid) = 'p_client_comparison_ids uuid[]';

    if existing_definition is not null
       and (
           position('auth.uid()' in existing_definition) = 0
           or position('client_comparison_id' in existing_definition) = 0
           or position('deleted_at = now()' in existing_definition) = 0
           or position('array_ndims(p_client_comparison_ids)' in existing_definition) = 0
           or position('One or more completed comparisons are unavailable' in existing_definition) = 0
       ) then
        raise exception 'FM_HISTORY_INSTALL_CONFLICT'
            using errcode = 'P0001';
    end if;

    select pg_get_functiondef(p.oid)
    into existing_definition
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'fitmatch_vnext_hide_comparison_history'
      and pg_get_function_identity_arguments(p.oid) = 'p_client_comparison_ids uuid[]';

    if existing_definition is not null
       and position('fitmatch_vnext.hide_comparison_history' in existing_definition) = 0 then
        raise exception 'FM_HISTORY_INSTALL_CONFLICT'
            using errcode = 'P0001';
    end if;
end;
$fitmatch_history_install_guard$;

create or replace function fitmatch_vnext.hide_comparison_history(
    p_client_comparison_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    caller_id uuid := auth.uid();
    requested_ids uuid[];
    owned_count integer;
    changed_count integer;
begin
    if caller_id is null then
        raise exception 'FM_HISTORY_AUTH_REQUIRED'
            using errcode = '42501';
    end if;

    if p_client_comparison_ids is null
       or coalesce(array_ndims(p_client_comparison_ids), 1) <> 1
       or array_position(p_client_comparison_ids, null) is not null then
        raise exception 'FM_HISTORY_INVALID_IDS'
            using errcode = '22023';
    end if;

    select coalesce(
        array_agg(ids.id order by ids.id),
        array[]::uuid[]
    )
    into requested_ids
    from (
        select distinct unnest(p_client_comparison_ids) as id
    ) ids;

    -- Lock only the exact candidate set before checking availability. This
    -- makes a mixed valid/invalid request atomic and repeated concurrent
    -- hides deterministic without rewriting an existing deleted_at value.
    perform c.id
    from fitmatch_vnext.comparisons c
    where c.user_id = caller_id
      and c.client_comparison_id = any(requested_ids)
      and c.result_status = 'COMPLETED'
    order by c.id
    for update;

    select count(*)
    into owned_count
    from fitmatch_vnext.comparisons c
    where c.user_id = caller_id
      and c.client_comparison_id = any(requested_ids)
      and c.result_status = 'COMPLETED';

    if owned_count <> cardinality(requested_ids) then
        raise exception 'FM_HISTORY_UNAVAILABLE'
            using errcode = '42501';
    end if;

    update fitmatch_vnext.comparisons c
    set deleted_at = now()
    where c.user_id = caller_id
      and c.client_comparison_id = any(requested_ids)
      and c.result_status = 'COMPLETED'
      and c.deleted_at is null;

    get diagnostics changed_count = row_count;

    return jsonb_build_object(
        'client_comparison_ids', to_jsonb(requested_ids),
        'hidden', true,
        'idempotent', changed_count = 0
    );
end;
$function$;

create or replace function public.fitmatch_vnext_hide_comparison_history(
    p_client_comparison_ids uuid[]
)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
    select fitmatch_vnext.hide_comparison_history(
        p_client_comparison_ids
    );
$function$;

revoke all on function fitmatch_vnext.hide_comparison_history(uuid[])
from public, anon, authenticated, service_role;
revoke all on function public.fitmatch_vnext_hide_comparison_history(uuid[])
from public, anon, authenticated, service_role;
grant execute on function public.fitmatch_vnext_hide_comparison_history(uuid[])
to authenticated;

-- Installation itself verifies the expected public surface. A failure rolls
-- back this transaction instead of leaving a callable, wrongly-permissioned
-- RPC behind.
do $fitmatch_history_privilege_guard$
begin
    if not has_function_privilege(
        'authenticated',
        'public.fitmatch_vnext_hide_comparison_history(uuid[])',
        'EXECUTE'
    ) or has_function_privilege(
        'anon',
        'public.fitmatch_vnext_hide_comparison_history(uuid[])',
        'EXECUTE'
    ) then
        raise exception 'FM_HISTORY_INSTALL_PRIVILEGE_CHECK_FAILED'
            using errcode = '42501';
    end if;
end;
$fitmatch_history_privilege_guard$;

notify pgrst, 'reload schema';

commit;
