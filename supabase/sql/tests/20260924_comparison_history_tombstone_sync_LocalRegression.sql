\set ON_ERROR_STOP on

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create schema auth;
create schema fitmatch_vnext;

create function auth.uid()
returns uuid
language sql
stable
as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table fitmatch_vnext.comparisons (
    id uuid primary key,
    user_id uuid not null,
    client_comparison_id uuid not null,
    result_status text not null,
    deleted_at timestamptz,
    created_at timestamptz not null default now()
);

create function fitmatch_vnext.comparison_history()
returns jsonb
language sql
security definer
set search_path to ''
as $$
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id', comparison_value.id,
                'client_comparison_id', comparison_value.client_comparison_id,
                'result_status', comparison_value.result_status
            )
            order by comparison_value.created_at desc, comparison_value.id
        ),
        '[]'::jsonb
    )
    from fitmatch_vnext.comparisons comparison_value
    where comparison_value.user_id = auth.uid()
      and comparison_value.deleted_at is null
$$;

create function public.fitmatch_vnext_comparison_history()
returns jsonb
language sql
security invoker
set search_path to ''
as $$ select fitmatch_vnext.comparison_history() $$;

\ir ../../migrations/20260924102000_comparison_history_tombstone_sync.sql

do $$
declare
    owner_id uuid := '11111111-1111-1111-1111-111111111111';
    other_id uuid := '22222222-2222-2222-2222-222222222222';
    active_client_id uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    hidden_client_id uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    foreign_hidden_client_id uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    result_value jsonb;
begin
    perform set_config('TimeZone', 'UTC', true);
    insert into fitmatch_vnext.comparisons (
        id, user_id, client_comparison_id, result_status, deleted_at, created_at
    ) values
        ('10000000-0000-0000-0000-000000000001', owner_id, active_client_id,
         'COMPLETED', null, '2026-09-24T00:00:00Z'),
        ('10000000-0000-0000-0000-000000000002', owner_id, hidden_client_id,
         'COMPLETED', '2026-09-24T00:01:00Z', '2026-09-24T00:00:01Z'),
        ('20000000-0000-0000-0000-000000000001', other_id, foreign_hidden_client_id,
         'COMPLETED', '2026-09-24T00:02:00Z', '2026-09-24T00:00:02Z');

    perform set_config('request.jwt.claim.sub', owner_id::text, true);
    result_value := public.fitmatch_vnext_comparison_history_sync();

    if result_value #>> '{histories,0,client_comparison_id}' <> active_client_id::text
       or jsonb_array_length(result_value -> 'histories') <> 1
       or result_value #>> '{tombstones,0,client_comparison_id}' <> hidden_client_id::text
       or result_value #>> '{tombstones,0,hidden_at}' <> '2026-09-24T00:01:00+00:00'
       or jsonb_array_length(result_value -> 'tombstones') <> 1 then
        raise exception 'FM_HISTORY_SYNC_LOCAL_CONTRACT_FAILED: %', result_value;
    end if;

    if position(foreign_hidden_client_id::text in result_value::text) <> 0 then
        raise exception 'FM_HISTORY_SYNC_FOREIGN_TOMBSTONE_LEAKED: %', result_value;
    end if;
end;
$$;

do $$
begin
    if not has_function_privilege(
        'authenticated',
        'public.fitmatch_vnext_comparison_history_sync()',
        'EXECUTE'
    ) or has_function_privilege(
        'anon',
        'public.fitmatch_vnext_comparison_history_sync()',
        'EXECUTE'
    ) then
        raise exception 'FM_HISTORY_SYNC_GRANT_CONTRACT_FAILED';
    end if;
end;
$$;

\ir ../20260924102000_comparison_history_tombstone_sync_Rollback.sql

do $$
begin
    if to_regprocedure('fitmatch_vnext.comparison_history_sync()') is not null
       or to_regprocedure('public.fitmatch_vnext_comparison_history_sync()') is not null then
        raise exception 'FM_HISTORY_SYNC_ROLLBACK_FAILED';
    end if;
end;
$$;

\echo 20260924_comparison_history_tombstone_sync_local_regression_passed
