\set ON_ERROR_STOP on

-- Local/disposable classification audit. The payload CSV must contain one
-- JSON request wrapper per row, exactly as encoded by Swift.
begin;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claim.sub', :'fixture_actor_id', true);
select set_config('fitmatch.fixture_check_retry', :'fixture_check_retry', true);

create temp table fitmatch_fixture_payload_lines (
    fixture_index bigint generated always as identity primary key,
    request_text text not null
) on commit drop;

\copy fitmatch_fixture_payload_lines(request_text) from '/tmp/fitmatch-fixture-payloads.csv' with (format csv)

create temp table fitmatch_classification_audit (
    fixture_index bigint primary key,
    source_code text,
    source_product_key text,
    product_name text,
    classification_status text,
    garment_type_code text,
    sleeve_length_code text,
    lower_length_code text,
    body_length_code text,
    audience_code text,
    product_structure_code text,
    comparison_measurement_contract text,
    comparison_unit_eligible boolean,
    readiness_status text,
    readiness_reason_code text,
    fact_proposal_status text,
    reason_codes jsonb,
    evidence jsonb,
    candidate_count integer,
    observed_partial_facts jsonb,
    idempotent_retry boolean,
    first_payload_fingerprint text,
    retry_payload_fingerprint text,
    error_message text
) on commit drop;

do $fixture_audit$
declare
    fixture record;
    payload_value jsonb;
    first_value jsonb;
    retry_value jsonb;
    classification_value jsonb;
    fact_value jsonb;
    runtime_value jsonb;
begin
    for fixture in
        select fixture_index, request_text::jsonb as request_value
        from fitmatch_fixture_payload_lines
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
            if current_setting('fitmatch.fixture_check_retry')::boolean then
                retry_value := public.fitmatch_vnext_ingest_product_observation(
                    payload_value,
                    current_setting('request.jwt.claim.sub')::uuid
                );
            else
                retry_value := null;
            end if;
            runtime_value := public.fitmatch_vnext_get_product_runtime(
                payload_value ->> 'source',
                payload_value ->> 'external_product_id'
            );
            classification_value := first_value -> 'classification';
            fact_value := classification_value -> 'retailer_fact_decision';

            insert into fitmatch_classification_audit (
                fixture_index,
                source_code,
                source_product_key,
                product_name,
                classification_status,
                garment_type_code,
                sleeve_length_code,
                lower_length_code,
                body_length_code,
                audience_code,
                product_structure_code,
                comparison_measurement_contract,
                comparison_unit_eligible,
                readiness_status,
                readiness_reason_code,
                fact_proposal_status,
                reason_codes,
                evidence,
                candidate_count,
                observed_partial_facts,
                idempotent_retry,
                first_payload_fingerprint,
                retry_payload_fingerprint
            ) values (
                fixture.fixture_index,
                payload_value ->> 'source',
                payload_value ->> 'external_product_id',
                payload_value ->> 'product_name',
                classification_value ->> 'classification_status',
                classification_value ->> 'garment_type_code',
                classification_value ->> 'sleeve_length_code',
                classification_value ->> 'lower_length_code',
                classification_value ->> 'body_length_code',
                classification_value ->> 'audience_code',
                classification_value ->> 'product_structure_code',
                classification_value ->> 'comparison_measurement_contract',
                coalesce((classification_value ->> 'comparison_unit_eligible')::boolean, false),
                first_value -> 'readiness' ->> 'status',
                first_value -> 'readiness' ->> 'reason_code',
                fact_value ->> 'fact_proposal_status',
                coalesce(fact_value -> 'reason_codes', '[]'::jsonb),
                coalesce(fact_value -> 'evidence', '[]'::jsonb),
                coalesce((fact_value ->> 'candidate_count')::integer, 0),
                coalesce(fact_value -> 'observed_partial_facts', '{}'::jsonb),
                coalesce((retry_value -> 'processing' ->> 'idempotent')::boolean, false),
                first_value -> 'observation' ->> 'payload_fingerprint',
                retry_value -> 'observation' ->> 'payload_fingerprint'
            );
        exception when others then
            insert into fitmatch_classification_audit (
                fixture_index,
                source_code,
                source_product_key,
                product_name,
                error_message
            ) values (
                fixture.fixture_index,
                payload_value ->> 'source',
                payload_value ->> 'external_product_id',
                payload_value ->> 'product_name',
                sqlstate || ': ' || sqlerrm
            );
        end;
    end loop;
end
$fixture_audit$;

\copy (select * from fitmatch_classification_audit order by fixture_index) to '/tmp/fitmatch-classification-audit.csv' with (format csv, header true)

select
    source_code,
    count(*) as fixture_count,
    count(*) filter (where error_message is null) as completed_count,
    count(*) filter (where error_message is not null) as failed_count,
    count(*) filter (where classification_status = 'CONFIRMED') as confirmed_count,
    count(*) filter (where classification_status = 'REVIEW_REQUIRED') as review_required_count,
    count(*) filter (where classification_status = 'NOT_APPLICABLE') as not_applicable_count,
    count(*) filter (where comparison_unit_eligible) as comparison_eligible_count,
    count(*) filter (where readiness_status = 'READY') as ready_count,
    count(*) filter (
        where idempotent_retry
          and first_payload_fingerprint = retry_payload_fingerprint
    ) as stable_retry_count
from fitmatch_classification_audit
group by source_code
order by source_code;

rollback;
