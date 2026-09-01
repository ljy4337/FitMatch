\set ON_ERROR_STOP on

create temporary table comparison_preimage as
select id, md5(to_jsonb(c)::text) as row_hash
from fitmatch_vnext.comparisons c
order by id;

do $contract$
declare
    response jsonb;
begin
    if has_table_privilege(
        'authenticated',
        'fitmatch_vnext.user_comparison_history_visibility',
        'SELECT, INSERT, UPDATE, DELETE'
    ) then
        raise exception 'authenticated received raw visibility table privileges';
    end if;

    if has_function_privilege(
        'anon',
        'public.fitmatch_vnext_hide_comparison_history(uuid[])',
        'EXECUTE'
    ) then
        raise exception 'anon can execute the history hide wrapper';
    end if;

    perform set_config(
        'request.jwt.claim.sub',
        '10000000-0000-0000-0000-000000000001',
        true
    );

    response := public.fitmatch_vnext_hide_comparison_history(array[
        '70000000-0000-0000-0000-000000000001'::uuid,
        '70000000-0000-0000-0000-000000000001'::uuid
    ]);
    if response->>'hidden' <> 'true'
       or response->>'idempotent' <> 'false'
       or jsonb_array_length(response->'client_comparison_ids') <> 1 then
        raise exception 'first hide receipt is invalid: %', response;
    end if;

    response := public.fitmatch_vnext_hide_comparison_history(array[
        '70000000-0000-0000-0000-000000000001'::uuid
    ]);
    if response->>'idempotent' <> 'true' then
        raise exception 'duplicate hide is not idempotent: %', response;
    end if;

    begin
        perform public.fitmatch_vnext_hide_comparison_history(array[
            '70000000-0000-0000-0000-000000000002'::uuid
        ]);
        raise exception 'cross-user hide unexpectedly succeeded';
    exception
        when others then
            if sqlerrm = 'cross-user hide unexpectedly succeeded' then
                raise;
            end if;
    end;

    begin
        perform public.fitmatch_vnext_hide_comparison_history(array[
            '70000000-0000-0000-0000-000000000003'::uuid
        ]);
        raise exception 'pending comparison hide unexpectedly succeeded';
    exception
        when others then
            if sqlerrm = 'pending comparison hide unexpectedly succeeded' then
                raise;
            end if;
    end;
end
$contract$;

do $projection$
declare
    history jsonb;
begin
    perform set_config(
        'request.jwt.claim.sub',
        '10000000-0000-0000-0000-000000000001',
        true
    );
    history := fitmatch_vnext.comparison_history();
    if jsonb_array_length(history) <> 1 then
        raise exception 'history projection did not hide only the completed row: %', history;
    end if;
    if history->0->>'client_comparison_id'
       <> '70000000-0000-0000-0000-000000000003' then
        raise exception 'unexpected remaining history projection: %', history;
    end if;

    perform set_config(
        'request.jwt.claim.sub',
        '10000000-0000-0000-0000-000000000002',
        true
    );
    history := fitmatch_vnext.comparison_history();
    if jsonb_array_length(history) <> 1
       or history->0->>'client_comparison_id'
          <> '70000000-0000-0000-0000-000000000002' then
        raise exception 'other user history was affected: %', history;
    end if;
end
$projection$;

do $immutability$
begin
    if exists (
        select 1
        from comparison_preimage before
        full join (
            select id, md5(to_jsonb(c)::text) as row_hash
            from fitmatch_vnext.comparisons c
        ) after using (id)
        where before.id is null
           or after.id is null
           or before.row_hash is distinct from after.row_hash
    ) then
        raise exception 'immutable comparison evidence changed during hide';
    end if;

    if (
        select count(*)
        from fitmatch_vnext.user_comparison_history_visibility
    ) <> 1 then
        raise exception 'expected exactly one durable visibility row';
    end if;
end
$immutability$;

select 'HISTORY_VISIBILITY_LOCAL_CONTRACT_PASS' as result;
