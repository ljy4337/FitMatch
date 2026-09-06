-- History visibility is a soft hide on the immutable comparison row itself.
-- This migration is intentionally not applied by the iOS client.

begin;

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
        raise exception 'Authentication required'
            using errcode = '42501';
    end if;

    if p_client_comparison_ids is null
       or coalesce(array_ndims(p_client_comparison_ids), 1) <> 1 then
        raise exception 'A one-dimensional UUID array is required'
            using errcode = '22023';
    end if;

    if array_position(p_client_comparison_ids, null) is not null then
        raise exception 'Comparison IDs must not contain null'
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

    -- Lock every requested owned completed row before the all-or-nothing
    -- availability check. This leaves immutable evidence untouched and makes
    -- concurrent repeated hides deterministic.
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
        raise exception 'One or more completed comparisons are unavailable'
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

notify pgrst, 'reload schema';

commit;
