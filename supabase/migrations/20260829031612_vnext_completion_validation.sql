-- Purpose: reject structurally invalid or snapshot-inconsistent comparison results
-- before immutable completion.
-- Data impact: strengthens the COMPLETED-row constraint and replaces the completion
-- transition function. No existing completed vNext rows exist at migration time.
-- Rollback: restore the prior constraint/function from 20260829013409.
-- Verification: empty evidence, unauthorized sizes, duplicate ranks/evidence,
-- excluded metrics, wrong values/weights/differences, and conflicting retries fail.

alter table fitmatch_vnext.comparisons
    drop constraint if exists comparisons_recommended_authority_chk;
alter table fitmatch_vnext.comparisons
    add constraint comparisons_recommended_authority_chk
    check (
        (
            result_status = 'COMPLETED'
            and recommended_product_size_id is not null
            and recommended_size_label is not null
            and fit_score is not null
            and reliability_level is not null
            and coverage_ratio is not null
            and nullif(btrim(engine_version), '') is not null
            and result_payload_hash is not null
            and completed_at is not null
            and jsonb_typeof(result_evidence) = 'object'
            and jsonb_typeof(result_evidence -> 'candidate_size_ranking') = 'array'
            and jsonb_array_length(result_evidence -> 'candidate_size_ranking') > 0
            and jsonb_typeof(result_evidence -> 'metric_evidence') = 'array'
            and jsonb_array_length(result_evidence -> 'metric_evidence') > 0
            and jsonb_typeof(reference_snapshot) = 'object'
            and reference_snapshot <> '{}'::jsonb
            and jsonb_typeof(target_snapshot) = 'object'
            and target_snapshot <> '{}'::jsonb
            and jsonb_typeof(authority_snapshot) = 'object'
            and authority_snapshot <> '{}'::jsonb
            and jsonb_typeof(policy_snapshot) = 'object'
            and policy_snapshot <> '{}'::jsonb
        )
        or
        (
            result_status <> 'COMPLETED'
            and recommended_product_size_id is null
            and recommended_size_label is null
        )
    );

create or replace function fitmatch_vnext.complete_comparison(
    p_comparison_id uuid,
    p_result jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    row_value fitmatch_vnext.comparisons%rowtype;
    result_hash text;
    recommended_id uuid;
    recommended_label text;
    score_value numeric;
    reliability_value smallint;
    coverage_value numeric;
    expected_coverage numeric;
    authorized_count integer;
    ranking_count integer;
    expected_evidence_count integer;
    recommended_evidence_count integer;
    policy_metric_count integer;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_result is null or jsonb_typeof(p_result) <> 'object' then
        raise exception 'Result must be a JSON object';
    end if;

    result_hash := encode(extensions.digest(p_result::text, 'sha256'), 'hex');
    select * into row_value
    from fitmatch_vnext.comparisons
    where id = p_comparison_id and user_id = caller_id
    for update;
    if not found then
        raise exception 'Comparison not found or not owned';
    end if;
    if row_value.result_status = 'COMPLETED' then
        if row_value.result_payload_hash is distinct from result_hash then
            raise exception 'Completion idempotency conflict';
        end if;
        return jsonb_build_object(
            'comparison_id', row_value.id,
            'completed', true,
            'idempotent', true,
            'recommended_product_size_id', row_value.recommended_product_size_id,
            'recommended_size_label', row_value.recommended_size_label
        );
    end if;
    if row_value.result_status <> 'PENDING' then
        raise exception 'Comparison is not pending';
    end if;

    if jsonb_typeof(p_result -> 'recommended_product_size_id') <> 'string'
       or jsonb_typeof(p_result -> 'score') <> 'number'
       or jsonb_typeof(p_result -> 'reliability') <> 'number'
       or jsonb_typeof(p_result -> 'coverage') <> 'number'
       or nullif(btrim(p_result ->> 'engine_version'), '') is null then
        raise exception 'Recommendation, score, reliability, coverage, and engine_version are required';
    end if;
    recommended_id := (p_result ->> 'recommended_product_size_id')::uuid;
    score_value := (p_result ->> 'score')::numeric;
    reliability_value := (p_result ->> 'reliability')::smallint;
    coverage_value := (p_result ->> 'coverage')::numeric;
    if score_value < 0 or score_value > 100
       or reliability_value < 1 or reliability_value > 5
       or coverage_value < 0 or coverage_value > 1
       or length(p_result ->> 'engine_version') > 128 then
        raise exception 'Result summary values are outside the engine contract';
    end if;

    if jsonb_typeof(row_value.target_snapshot ->
           'authorized_candidate_product_size_ids') <> 'array'
       or jsonb_array_length(row_value.target_snapshot ->
           'authorized_candidate_product_size_ids') = 0 then
        raise exception 'Begin snapshot has no authorized candidate set';
    end if;
    if jsonb_typeof(p_result -> 'candidate_size_ranking') <> 'array'
       or jsonb_array_length(p_result -> 'candidate_size_ranking') = 0
       or jsonb_typeof(p_result -> 'metric_evidence') <> 'array'
       or jsonb_array_length(p_result -> 'metric_evidence') = 0 then
        raise exception 'Candidate ranking and metric evidence are required';
    end if;

    if exists (
        select 1 from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        where jsonb_typeof(ranking) <> 'object'
           or jsonb_typeof(ranking -> 'product_size_id') <> 'string'
           or jsonb_typeof(ranking -> 'rank') <> 'number'
           or jsonb_typeof(ranking -> 'score') <> 'number'
           or (ranking ->> 'rank')::integer < 1
           or (ranking ->> 'score')::numeric < 0
           or (ranking ->> 'score')::numeric > 100
    ) then
        raise exception 'Every ranking entry needs product_size_id, positive rank, and score';
    end if;

    authorized_count := jsonb_array_length(
        row_value.target_snapshot -> 'authorized_candidate_product_size_ids'
    );
    ranking_count := jsonb_array_length(p_result -> 'candidate_size_ranking');
    if ranking_count <> authorized_count then
        raise exception 'Ranking set must exactly cover the authorized candidate set';
    end if;
    if exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        group by ranking ->> 'product_size_id'
        having count(*) > 1
    ) or exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        group by (ranking ->> 'rank')::integer
        having count(*) > 1
    ) then
        raise exception 'Duplicate candidate size or rank';
    end if;
    if (
        select min((ranking ->> 'rank')::integer) <> 1
            or max((ranking ->> 'rank')::integer) <> ranking_count
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
    ) then
        raise exception 'Ranks must be contiguous from one';
    end if;
    if exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') higher
        cross join jsonb_array_elements(p_result -> 'candidate_size_ranking') lower
        where (higher ->> 'rank')::integer < (lower ->> 'rank')::integer
          and (higher ->> 'score')::numeric < (lower ->> 'score')::numeric
    ) then
        raise exception 'Candidate ranking order contradicts candidate scores';
    end if;
    if exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        where not exists (
            select 1
            from jsonb_array_elements_text(row_value.target_snapshot ->
                'authorized_candidate_product_size_ids') authorized(id)
            where authorized.id::uuid = (ranking ->> 'product_size_id')::uuid
        )
    ) or exists (
        select 1
        from jsonb_array_elements_text(row_value.target_snapshot ->
            'authorized_candidate_product_size_ids') authorized(id)
        where not exists (
            select 1
            from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
            where (ranking ->> 'product_size_id')::uuid = authorized.id::uuid
        )
    ) then
        raise exception 'Ranking contains an unauthorized or missing candidate';
    end if;
    if not exists (
        select 1
        from jsonb_array_elements(p_result -> 'candidate_size_ranking') ranking
        where (ranking ->> 'product_size_id')::uuid = recommended_id
          and (ranking ->> 'rank')::integer = 1
          and (ranking ->> 'score')::numeric = score_value
    ) then
        raise exception 'Recommended size must be rank one and match the result score';
    end if;

    select ps.size_label into recommended_label
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where ps.id = recommended_id
      and pv.id = row_value.target_variant_id
      and pv.product_id = row_value.target_product_id;
    if recommended_label is null then
        raise exception 'Recommended size hierarchy mismatch';
    end if;

    if exists (
        select 1 from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        where jsonb_typeof(evidence) <> 'object'
           or jsonb_typeof(evidence -> 'product_size_id') <> 'string'
           or nullif(btrim(evidence ->> 'measurement_code'), '') is null
           or jsonb_typeof(evidence -> 'reference_value') <> 'number'
           or jsonb_typeof(evidence -> 'target_value') <> 'number'
           or jsonb_typeof(evidence -> 'difference') <> 'number'
           or jsonb_typeof(evidence -> 'absolute_difference') <> 'number'
           or jsonb_typeof(evidence -> 'weight') <> 'number'
    ) then
        raise exception 'Metric evidence is missing required semantic fields';
    end if;
    if exists (
        select 1
        from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        group by evidence ->> 'product_size_id', evidence ->> 'measurement_code'
        having count(*) > 1
    ) then
        raise exception 'Duplicate size and metric evidence';
    end if;
    if exists (
        select 1 from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        where evidence ->> 'measurement_code' = any(row_value.excluded_measurement_codes)
    ) then
        raise exception 'Excluded measurement evidence is forbidden';
    end if;

    with expected as (
        select (candidate ->> 'product_size_id')::uuid product_size_id,
               metric ->> 'measurement_code' measurement_code,
               (metric ->> 'reference_value')::numeric reference_value,
               (metric ->> 'target_value')::numeric target_value,
               (metric ->> 'difference')::numeric difference,
               (metric ->> 'absolute_difference')::numeric absolute_difference,
               (metric ->> 'weight')::numeric weight
        from jsonb_array_elements(row_value.target_snapshot -> 'candidates') candidate
        cross join jsonb_array_elements(candidate -> 'comparison_measurements') metric
    ), evidence as (
        select (item ->> 'product_size_id')::uuid product_size_id,
               item ->> 'measurement_code' measurement_code,
               (item ->> 'reference_value')::numeric reference_value,
               (item ->> 'target_value')::numeric target_value,
               (item ->> 'difference')::numeric difference,
               (item ->> 'absolute_difference')::numeric absolute_difference,
               (item ->> 'weight')::numeric weight
        from jsonb_array_elements(p_result -> 'metric_evidence') item
    )
    select count(*) into expected_evidence_count from expected;
    if expected_evidence_count = 0 then
        raise exception 'Begin snapshot contains no comparable metric evidence';
    end if;
    if jsonb_array_length(p_result -> 'metric_evidence') <> expected_evidence_count then
        raise exception 'Metric evidence set must exactly match the begin snapshot';
    end if;
    if exists (
        with expected as (
            select (candidate ->> 'product_size_id')::uuid product_size_id,
                   metric ->> 'measurement_code' measurement_code,
                   (metric ->> 'reference_value')::numeric reference_value,
                   (metric ->> 'target_value')::numeric target_value,
                   (metric ->> 'weight')::numeric weight
            from jsonb_array_elements(row_value.target_snapshot -> 'candidates') candidate
            cross join jsonb_array_elements(candidate -> 'comparison_measurements') metric
        )
        select 1
        from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        left join expected on expected.product_size_id =
                (evidence ->> 'product_size_id')::uuid
            and expected.measurement_code = evidence ->> 'measurement_code'
        where expected.product_size_id is null
           or (evidence ->> 'reference_value')::numeric <> expected.reference_value
           or (evidence ->> 'target_value')::numeric <> expected.target_value
           or (evidence ->> 'weight')::numeric <> expected.weight
           or (evidence ->> 'difference')::numeric <>
                expected.target_value - expected.reference_value
           or (evidence ->> 'absolute_difference')::numeric <>
                abs(expected.target_value - expected.reference_value)
    ) then
        raise exception 'Metric evidence does not match begin values, policy weight, or difference';
    end if;
    if exists (
        with supplied as (
            select (evidence ->> 'product_size_id')::uuid product_size_id,
                   evidence ->> 'measurement_code' measurement_code
            from jsonb_array_elements(p_result -> 'metric_evidence') evidence
        )
        select 1
        from jsonb_array_elements(row_value.target_snapshot -> 'candidates') candidate
        cross join jsonb_array_elements(candidate -> 'comparison_measurements') metric
        where not exists (
            select 1 from supplied
            where supplied.product_size_id = (candidate ->> 'product_size_id')::uuid
              and supplied.measurement_code = metric ->> 'measurement_code'
        )
    ) then
        raise exception 'Metric evidence omits a begin-snapshot metric';
    end if;

    select count(*) into recommended_evidence_count
    from jsonb_array_elements(p_result -> 'metric_evidence') evidence
    where (evidence ->> 'product_size_id')::uuid = recommended_id;
    select count(*) into policy_metric_count
    from jsonb_array_elements(row_value.policy_snapshot -> 'metrics') metric
    where metric ->> 'metric_mode' = 'CANONICAL'
      and coalesce((metric ->> 'is_active')::boolean, false)
      and not (metric ->> 'fitmatch_measurement_code' =
          any(row_value.excluded_measurement_codes));
    if policy_metric_count = 0 then
        raise exception 'Policy snapshot has no active canonical metrics';
    end if;
    expected_coverage := round(
        recommended_evidence_count::numeric / policy_metric_count::numeric, 5
    );
    if round(coverage_value, 5) <> expected_coverage then
        raise exception 'Coverage does not match begin-snapshot metric coverage';
    end if;

    update fitmatch_vnext.comparisons
    set recommended_product_size_id = recommended_id,
        recommended_size_label = recommended_label,
        fit_score = score_value,
        reliability_level = reliability_value,
        coverage_ratio = coverage_value,
        result_status = 'COMPLETED',
        engine_version = p_result ->> 'engine_version',
        detail_snapshot = jsonb_build_object(
            'phase', 'COMPLETED',
            'result', p_result,
            'validated_against_snapshot_schema_version', row_value.snapshot_schema_version
        ),
        result_evidence = p_result,
        result_payload_hash = result_hash,
        completed_at = now()
    where id = row_value.id;

    return jsonb_build_object(
        'comparison_id', row_value.id,
        'completed', true,
        'idempotent', false,
        'recommended_product_size_id', recommended_id,
        'recommended_size_label', recommended_label,
        'validated_evidence_count', expected_evidence_count,
        'coverage', expected_coverage
    );
end
$function$;

revoke all on function fitmatch_vnext.complete_comparison(uuid,jsonb)
    from public, anon;
grant execute on function fitmatch_vnext.complete_comparison(uuid,jsonb)
    to authenticated, service_role;

-- Verification query is exercised transactionally by
-- supabase/sql/121_vnext_final_remediation_tests.sql.
