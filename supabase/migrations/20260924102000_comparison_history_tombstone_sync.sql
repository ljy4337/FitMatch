-- Add an explicit, owner-scoped tombstone envelope for History sync.  An
-- absent active-history row is intentionally not a deletion signal.
begin;

do $preflight$
begin
    if to_regprocedure('fitmatch_vnext.comparison_history()') is null
       or to_regprocedure('public.fitmatch_vnext_comparison_history()') is null then
        raise exception 'FM_HISTORY_SYNC_REQUIRES_COMPARISON_HISTORY'
            using errcode = 'P0001';
    end if;

    if not exists (
        select 1
        from pg_attribute attribute
        join pg_class relation on relation.oid = attribute.attrelid
        join pg_namespace namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'fitmatch_vnext'
          and relation.relname = 'comparisons'
          and attribute.attname = 'deleted_at'
          and attribute.attnum > 0
          and not attribute.attisdropped
    ) then
        raise exception 'FM_HISTORY_SYNC_REQUIRES_COMPARISON_TOMBSTONE'
            using errcode = 'P0001';
    end if;
end;
$preflight$;

create or replace function fitmatch_vnext.comparison_history_sync()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then
        raise exception 'FM_HISTORY_AUTH_REQUIRED'
            using errcode = '42501';
    end if;

    return jsonb_build_object(
        -- Retain the existing active-history projection exactly.  The new
        -- envelope does not reinterpret ordinary omission as a tombstone.
        'histories', fitmatch_vnext.comparison_history(),
        'tombstones', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'client_comparison_id', comparison_value.client_comparison_id,
                    'hidden_at', comparison_value.deleted_at
                )
                order by comparison_value.deleted_at asc, comparison_value.id
            )
            from fitmatch_vnext.comparisons comparison_value
            where comparison_value.user_id = caller_id
              and comparison_value.result_status = 'COMPLETED'
              and comparison_value.deleted_at is not null
        ), '[]'::jsonb)
    );
end;
$function$;

create or replace function public.fitmatch_vnext_comparison_history_sync()
returns jsonb
language sql
security invoker
set search_path to ''
as $function$
    select fitmatch_vnext.comparison_history_sync()
$function$;

revoke all on function fitmatch_vnext.comparison_history_sync()
from public, anon, authenticated, service_role;
revoke all on function public.fitmatch_vnext_comparison_history_sync()
from public, anon, authenticated, service_role;

grant execute on function fitmatch_vnext.comparison_history_sync()
to authenticated, service_role;
grant execute on function public.fitmatch_vnext_comparison_history_sync()
to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
