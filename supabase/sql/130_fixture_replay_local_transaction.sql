\set ON_ERROR_STOP on

begin;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claim.sub', :'fixture_actor_id', true);

create temp table fitmatch_fixture_payload_lines (
    fixture_index bigint generated always as identity primary key,
    request_text text not null
) on commit drop;

\copy fitmatch_fixture_payload_lines(request_text) from '/tmp/fitmatch-fixture-payloads.csv' with (format csv)

create temp table fitmatch_fixture_payloads on commit drop as
select fixture_index, request_text::jsonb as request_value
from fitmatch_fixture_payload_lines;

create temp table fitmatch_fixture_results (
    fixture_index bigint primary key,
    source_code text,
    source_product_key text,
    first_result jsonb,
    retry_result jsonb,
    runtime_result jsonb,
    recovery_result jsonb,
    user_selection_result jsonb,
    post_selection_runtime_result jsonb,
    post_selection_retry_result jsonb,
    error_message text
) on commit drop;

do $fixture_replay$
declare
    fixture record;
    payload_value jsonb;
    first_value jsonb;
    retry_value jsonb;
    runtime_value jsonb;
    recovery_value jsonb;
    selection_value jsonb;
    post_selection_runtime_value jsonb;
    post_selection_retry_value jsonb;
    candidate_value jsonb;
    mutation_id_value uuid;
    expected_revision_value integer;
    product_id_value uuid;
begin
    for fixture in
        select fixture_index, request_value
        from fitmatch_fixture_payloads
        order by fixture_index
    loop
        payload_value := fixture.request_value -> 'payload';
        begin
            if payload_value is null or jsonb_typeof(payload_value) <> 'object' then
                raise exception 'Swift request wrapper does not contain an object payload';
            end if;

            first_value := public.fitmatch_vnext_ingest_product_observation(
                payload_value,
                current_setting('request.jwt.claim.sub')::uuid
            );
            retry_value := public.fitmatch_vnext_ingest_product_observation(
                payload_value,
                current_setting('request.jwt.claim.sub')::uuid
            );
            runtime_value := public.fitmatch_vnext_get_product_runtime(
                payload_value ->> 'source',
                payload_value ->> 'external_product_id'
            );
            product_id_value := nullif(
                first_value -> 'processing' ->> 'product_id',
                ''
            )::uuid;
            recovery_value := case
                when product_id_value is null then null
                else public.fitmatch_vnext_get_classification_recovery_options(
                    product_id_value
                )
            end;

            selection_value := null;
            post_selection_runtime_value := null;
            post_selection_retry_value := null;
            if recovery_value ->> 'recoverability' = 'RECOVERABLE'
               and jsonb_array_length(coalesce(recovery_value -> 'candidates', '[]'::jsonb)) between 1 and 64 then
                candidate_value := recovery_value -> 'candidates' -> 0;
                mutation_id_value := gen_random_uuid();
                expected_revision_value := coalesce(
                    (runtime_value -> 'vnext' -> 'effective_classification' ->> 'override_revision')::integer,
                    0
                );
                selection_value := public.fitmatch_vnext_set_user_product_classification(
                    product_id_value,
                    candidate_value ->> 'candidate_fingerprint',
                    recovery_value ->> 'candidate_set_hash',
                    recovery_value ->> 'product_input_fingerprint',
                    recovery_value ->> 'product_evidence_fingerprint',
                    mutation_id_value,
                    expected_revision_value
                );
                post_selection_runtime_value := public.fitmatch_vnext_get_product_runtime(
                    payload_value ->> 'source',
                    payload_value ->> 'external_product_id'
                );
                post_selection_retry_value := public.fitmatch_vnext_ingest_product_observation(
                    payload_value,
                    current_setting('request.jwt.claim.sub')::uuid
                );
            end if;

            insert into fitmatch_fixture_results(
                fixture_index,
                source_code,
                source_product_key,
                first_result,
                retry_result,
                runtime_result,
                recovery_result,
                user_selection_result,
                post_selection_runtime_result,
                post_selection_retry_result
            ) values (
                fixture.fixture_index,
                payload_value ->> 'source',
                payload_value ->> 'external_product_id',
                first_value,
                retry_value,
                runtime_value,
                recovery_value,
                selection_value,
                post_selection_runtime_value,
                post_selection_retry_value
            );
        exception when others then
            insert into fitmatch_fixture_results(
                fixture_index,
                source_code,
                source_product_key,
                error_message
            ) values (
                fixture.fixture_index,
                payload_value ->> 'source',
                payload_value ->> 'external_product_id',
                sqlstate || ': ' || sqlerrm
            );
        end;
    end loop;
end
$fixture_replay$;

copy (
    select
        fixture_index,
        source_code,
        source_product_key,
        first_result,
        retry_result,
        runtime_result,
        recovery_result,
        user_selection_result,
        post_selection_runtime_result,
        post_selection_retry_result,
        error_message
    from fitmatch_fixture_results
    order by fixture_index
) to stdout with (format csv, header true);

select
    source_code,
    count(*) as fixture_count,
    count(*) filter (where error_message is null) as completed_count,
    count(*) filter (where error_message is not null) as failed_count,
    count(*) filter (
        where retry_result -> 'processing' ->> 'idempotent' = 'true'
    ) as idempotent_retry_count,
    count(*) filter (
        where upper(coalesce(runtime_result -> 'classification' ->> 'status', '')) = 'CONFIRMED'
           or upper(coalesce(runtime_result -> 'product' ->> 'classification_status', '')) = 'CONFIRMED'
    ) as confirmed_count,
    count(*) filter (
        where upper(coalesce(runtime_result -> 'classification' ->> 'status', '')) = 'REVIEW_REQUIRED'
           or upper(coalesce(runtime_result -> 'product' ->> 'classification_status', '')) = 'REVIEW_REQUIRED'
    ) as review_required_count
    , count(*) filter (
        where user_selection_result -> 'effective_classification' ->> 'state' = 'PERSONAL_CONFIRMED'
    ) as personal_selection_count
    , count(*) filter (
        where post_selection_retry_result -> 'processing' ->> 'idempotent' = 'true'
    ) as post_selection_idempotent_retry_count
from fitmatch_fixture_results
group by source_code
order by source_code;

rollback;
