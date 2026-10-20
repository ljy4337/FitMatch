-- Deploy before the v3 client. Backwards compatible with v1/v2 completions.
-- Does not modify measurements, Closet records, completed History or RLS.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';

create or replace function fitmatch_vnext.validate_size_decision_v3(p_target jsonb, p_result jsonb)
returns integer
language plpgsql immutable
set search_path = ''
as $function$
declare
    candidate_count integer;
    common_codes jsonb;
    expected_ranking jsonb;
    supplied_ranking jsonb;
    expected_score numeric;
    expected_id uuid;
begin
    if jsonb_typeof(p_target->'candidates') is distinct from 'array'
       or jsonb_typeof(p_result->'ranking_measurement_codes') is distinct from 'array' then
        raise exception 'V3 requires candidates and ranking measurement codes';
    end if;
    candidate_count := jsonb_array_length(p_target->'candidates');
    if candidate_count = 0 then raise exception 'V3 has no candidates'; end if;

    if exists (
        select 1 from jsonb_array_elements(p_target->'candidates') c
        cross join jsonb_array_elements(c->'comparison_measurements') m
        group by c->>'product_size_id', m->>'measurement_code'
        having count(*) <> 1
    ) then raise exception 'V3 duplicate candidate measurement'; end if;

    with common as (
        select m->>'measurement_code' code
        from jsonb_array_elements(p_target->'candidates') c
        cross join jsonb_array_elements(c->'comparison_measurements') m
        group by m->>'measurement_code'
        having count(distinct c->>'product_size_id') = candidate_count
    )
    select coalesce(jsonb_agg(code order by code), '[]'::jsonb) into common_codes from common;
    if jsonb_array_length(common_codes) = 0 or
       common_codes is distinct from p_result->'ranking_measurement_codes' then
        raise exception 'V3 ranking codes must equal the full common intersection';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_target->'candidates') c
        cross join jsonb_array_elements(c->'comparison_measurements') m
        where common_codes ? (m->>'measurement_code')
        group by m->>'measurement_code'
        having count(distinct lower(m->>'unit_code')) <> 1
            or count(distinct m->>'basis_code') <> 1
            or count(distinct (m->>'weight')::numeric) <> 1
            or count(distinct (m->>'reference_value')::numeric) <> 1
            or count(m->>'unit_code') <> candidate_count
            or count(m->>'basis_code') <> candidate_count
            or min((m->>'weight')::numeric) <= 0
    ) then raise exception 'V3 common measurement semantics differ between sizes'; end if;

    with values_to_score as (
        select (c->>'product_size_id')::uuid size_id,
               (m->>'weight')::numeric weight,
               abs((m->>'target_value')::numeric - (m->>'reference_value')::numeric) delta
        from jsonb_array_elements(p_target->'candidates') c
        cross join jsonb_array_elements(c->'comparison_measurements') m
        where common_codes ? (m->>'measurement_code')
    ), scores as (
        select size_id,
               round(sum(weight * greatest(0, least(100, round(100 - 5 * delta)))) / sum(weight)) score,
               round(sum(weight * delta) / sum(weight), 6) mean_difference
        from values_to_score group by size_id
    ), ranked as (
        select *, row_number() over(order by score desc, mean_difference asc, size_id asc) rank
        from scores
    )
    select jsonb_agg(jsonb_build_object('product_size_id', size_id, 'rank', rank, 'score', score) order by rank)
    into expected_ranking from ranked;

    expected_id := (expected_ranking->0->>'product_size_id')::uuid;
    expected_score := (expected_ranking->0->>'score')::numeric;
    -- Swift encodes UUID strings in uppercase; compare UUID identities, not
    -- textual casing, and normalize array order to the explicit ranks.
    select jsonb_agg(jsonb_build_object(
        'product_size_id', (r->>'product_size_id')::uuid,
        'rank', (r->>'rank')::numeric, 'score', (r->>'score')::numeric
    ) order by (r->>'rank')::numeric)
    into supplied_ranking from jsonb_array_elements(p_result->'candidate_size_ranking') r;
    if expected_ranking is distinct from supplied_ranking
       or expected_id is distinct from (p_result->>'recommended_product_size_id')::uuid
       or expected_score is distinct from (p_result->>'score')::numeric
       or least(5, jsonb_array_length(common_codes))::numeric is distinct from (p_result->>'reliability')::numeric then
        raise exception 'V3 score, rank or summary differs from the immutable common evidence';
    end if;
    return jsonb_array_length(common_codes);
end
$function$;
revoke all on function fitmatch_vnext.validate_size_decision_v3(jsonb,jsonb) from public, anon, authenticated;

-- Preserve environment-specific completion ownership/recovery logic and ACLs.
-- Fail closed when the expected seam changes; never overwrite a full function
-- from one environment onto the other.
do $patch$
declare
    definition text := pg_get_functiondef('fitmatch_vnext.complete_comparison(uuid,jsonb)'::regprocedure);
    anchor text := '    select count(*) into policy_metric_count';
    addition text := $addition$    if p_result ->> 'engine_version' = 'fitmatch-ios-vnext-snapshot-v3' then
        recommended_evidence_count := fitmatch_vnext.validate_size_decision_v3(row_value.target_snapshot, p_result);
    end if;
$addition$;
begin
    if position('fitmatch_vnext.validate_size_decision_v3(row_value.target_snapshot, p_result)' in definition) > 0 then
        return;
    end if;
    if (length(definition) - length(replace(definition, anchor, ''))) / length(anchor) <> 1 then
        raise exception 'Completion policy-count seam changed; inspect before applying';
    end if;
    execute replace(definition, anchor, addition || anchor);
end
$patch$;
commit;
