\set ON_ERROR_STOP on

-- The history command is a soft hide on comparisons.deleted_at. Every
-- immutable comparison-evidence column must remain byte-for-byte stable.
create temporary table comparison_preimage as
select
    id,
    md5((to_jsonb(c) - 'deleted_at')::text) as evidence_hash
from fitmatch_vnext.comparisons c
order by id;

do $contract$
declare
    response jsonb;
begin
    if has_function_privilege(
        'anon',
        'public.fitmatch_vnext_hide_comparison_history(uuid[])',
        'EXECUTE'
    ) then
        raise exception 'anon can execute the history hide wrapper';
    end if;

    if has_function_privilege(
        'authenticated',
        'fitmatch_vnext.hide_comparison_history(uuid[])',
        'EXECUTE'
    ) then
        raise exception 'authenticated can bypass the public history wrapper';
    end if;

    -- H1: no JWT identity is never accepted.
    perform set_config('request.jwt.claim.sub', '', true);
    begin
        perform public.fitmatch_vnext_hide_comparison_history(array[
            '70000000-0000-0000-0000-000000000001'::uuid
        ]);
        raise exception 'unauthenticated hide unexpectedly succeeded';
    exception when others then
        if sqlerrm = 'unauthenticated hide unexpectedly succeeded' then
            raise;
        end if;
    end;

    perform set_config(
        'request.jwt.claim.sub',
        '10000000-0000-0000-0000-000000000001',
        true
    );

    -- H2/H3: duplicate IDs are deduplicated and repeated soft hides are
    -- idempotent without deleting or re-writing comparison evidence.
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
    if response->>'hidden' <> 'true'
       or response->>'idempotent' <> 'true' then
        raise exception 'duplicate hide is not idempotent: %', response;
    end if;

    -- H7: an empty one-dimensional request is a harmless success.
    response := public.fitmatch_vnext_hide_comparison_history(array[]::uuid[]);
    if response->>'hidden' <> 'true'
       or response->>'idempotent' <> 'true'
       or jsonb_array_length(response->'client_comparison_ids') <> 0 then
        raise exception 'empty hide receipt is invalid: %', response;
    end if;

    -- H4/H5/H6: ownership, inexistence, and non-COMPLETED status all reject
    -- the entire request; no partial update is legal.
    begin
        perform public.fitmatch_vnext_hide_comparison_history(array[
            '70000000-0000-0000-0000-000000000002'::uuid
        ]);
        raise exception 'cross-user hide unexpectedly succeeded';
    exception when others then
        if sqlerrm = 'cross-user hide unexpectedly succeeded' then
            raise;
        end if;
    end;

    begin
        perform public.fitmatch_vnext_hide_comparison_history(array[
            '70000000-0000-0000-0000-000000000003'::uuid
        ]);
        raise exception 'pending comparison hide unexpectedly succeeded';
    exception when others then
        if sqlerrm = 'pending comparison hide unexpectedly succeeded' then
            raise;
        end if;
    end;

    begin
        perform public.fitmatch_vnext_hide_comparison_history(array[
            '70000000-0000-0000-0000-000000000099'::uuid
        ]);
        raise exception 'missing comparison hide unexpectedly succeeded';
    exception when others then
        if sqlerrm = 'missing comparison hide unexpectedly succeeded' then
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
            select id, md5((to_jsonb(c) - 'deleted_at')::text) as evidence_hash
            from fitmatch_vnext.comparisons c
        ) after using (id)
        where before.id is null
           or after.id is null
           or before.evidence_hash is distinct from after.evidence_hash
    ) then
        raise exception 'immutable comparison evidence changed during hide';
    end if;

    if not exists (
        select 1
        from fitmatch_vnext.comparisons c
        where c.client_comparison_id
              = '70000000-0000-0000-0000-000000000001'::uuid
          and c.deleted_at is not null
    ) then
        raise exception 'completed comparison was not soft hidden';
    end if;
end
$immutability$;

select 'HISTORY_VISIBILITY_LOCAL_CONTRACT_PASS' as result;
