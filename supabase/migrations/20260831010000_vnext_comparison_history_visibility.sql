-- PC-HISTORY-001: durable, user-owned presentation suppression for immutable
-- vNext completed comparisons. This never updates or deletes comparison
-- evidence; it only excludes a user's explicitly hidden rows from history.

create table if not exists fitmatch_vnext.user_comparison_history_visibility (
    user_id uuid not null,
    comparison_id uuid not null,
    hidden_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    primary key (user_id, comparison_id),
    constraint user_comparison_history_visibility_comparison_fkey
        foreign key (comparison_id)
        references fitmatch_vnext.comparisons(id)
        on delete restrict
);

alter table fitmatch_vnext.user_comparison_history_visibility
    enable row level security;

drop policy if exists user_comparison_history_visibility_select_own
    on fitmatch_vnext.user_comparison_history_visibility;
create policy user_comparison_history_visibility_select_own
    on fitmatch_vnext.user_comparison_history_visibility
    for select
    to authenticated
    using (user_id = (select auth.uid()));

-- Client mutations are RPC-only. No raw visibility state is exposed to anon
-- or authenticated roles; service_role remains available for operations.
revoke all on table fitmatch_vnext.user_comparison_history_visibility
    from public, anon, authenticated;
grant select, insert, update, delete
    on table fitmatch_vnext.user_comparison_history_visibility
    to service_role;

create or replace function fitmatch_vnext.hide_comparison_history(
    p_client_comparison_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    requested_ids uuid[];
    matched_count integer;
    inserted_count integer;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;

    if p_client_comparison_ids is null
       or cardinality(p_client_comparison_ids) = 0
       or array_position(p_client_comparison_ids, null) is not null then
        raise exception 'At least one client comparison id is required';
    end if;

    select array_agg(distinct request_value order by request_value)
    into requested_ids
    from unnest(p_client_comparison_ids) as request_values(request_value);

    if requested_ids is null or cardinality(requested_ids) = 0 then
        raise exception 'At least one client comparison id is required';
    end if;

    select count(*)
    into matched_count
    from fitmatch_vnext.comparisons c
    where c.user_id = caller_id
      and c.client_comparison_id = any(requested_ids)
      and c.result_status = 'COMPLETED'
      and c.deleted_at is null;

    if matched_count <> cardinality(requested_ids) then
        raise exception 'Completed comparison is not owned or visible';
    end if;

    insert into fitmatch_vnext.user_comparison_history_visibility (
        user_id,
        comparison_id
    )
    select caller_id, c.id
    from fitmatch_vnext.comparisons c
    where c.user_id = caller_id
      and c.client_comparison_id = any(requested_ids)
      and c.result_status = 'COMPLETED'
      and c.deleted_at is null
    on conflict (user_id, comparison_id) do nothing;

    get diagnostics inserted_count = row_count;

    return jsonb_build_object(
        'client_comparison_ids', to_jsonb(requested_ids),
        'hidden', true,
        'idempotent', inserted_count = 0
    );
end
$function$;

create or replace function public.fitmatch_vnext_hide_comparison_history(
    p_client_comparison_ids uuid[]
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.hide_comparison_history(p_client_comparison_ids)
$function$;

-- History remains immutable in fitmatch_vnext. The user-owned suppression
-- table changes only whether the current user hydrates/presents a row.
create or replace function fitmatch_vnext.comparison_history()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    return coalesce((
        select jsonb_agg(
            to_jsonb(c) || jsonb_build_object(
                'reference_client_item_id', ci.client_item_id,
                'target_source_product_key', p.source_product_key,
                'target_category_code', gt.category_code
            )
            order by c.created_at desc, c.id
        )
        from fitmatch_vnext.comparisons c
        left join fitmatch_vnext.closet_items ci
          on ci.id = c.reference_closet_item_id
         and ci.user_id = c.user_id
        left join fitmatch_vnext.products p
          on p.id = c.target_product_id
        left join fitmatch_vnext.garment_types gt
          on gt.garment_type_code = p.garment_type_code
        where c.user_id = caller_id
          and c.deleted_at is null
          and not exists (
              select 1
              from fitmatch_vnext.user_comparison_history_visibility visibility
              where visibility.user_id = caller_id
                and visibility.comparison_id = c.id
          )
    ), '[]'::jsonb);
end
$function$;

revoke all on function fitmatch_vnext.hide_comparison_history(uuid[])
    from public, anon;
grant execute on function fitmatch_vnext.hide_comparison_history(uuid[])
    to authenticated, service_role;

revoke all on function public.fitmatch_vnext_hide_comparison_history(uuid[])
    from public, anon;
grant execute on function public.fitmatch_vnext_hide_comparison_history(uuid[])
    to authenticated, service_role;

revoke all on function fitmatch_vnext.comparison_history()
    from public, anon;
grant execute on function fitmatch_vnext.comparison_history()
    to authenticated, service_role;

do $security_contract$
begin
    if not exists (
        select 1
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'fitmatch_vnext'
          and c.relname = 'user_comparison_history_visibility'
          and c.relrowsecurity
    ) then
        raise exception 'History visibility RLS is required';
    end if;

    if has_table_privilege(
        'authenticated',
        'fitmatch_vnext.user_comparison_history_visibility',
        'INSERT, UPDATE, DELETE'
    ) then
        raise exception 'Authenticated history visibility writes must be RPC-only';
    end if;

    if has_function_privilege(
        'anon',
        'fitmatch_vnext.hide_comparison_history(uuid[])',
        'EXECUTE'
    ) or has_function_privilege(
        'anon',
        'public.fitmatch_vnext_hide_comparison_history(uuid[])',
        'EXECUTE'
    ) then
        raise exception 'Anonymous history visibility mutation must be denied';
    end if;

    if not exists (
        select 1
        from pg_proc p
        where p.oid = 'fitmatch_vnext.hide_comparison_history(uuid[])'::regprocedure
          and p.prosecdef
          and p.proconfig @> array['search_path=""']::text[]
    ) then
        raise exception 'History visibility SECURITY DEFINER search_path regression';
    end if;
end
$security_contract$;
