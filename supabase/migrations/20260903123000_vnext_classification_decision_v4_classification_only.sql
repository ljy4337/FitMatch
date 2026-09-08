-- GIT REPRODUCIBILITY ONLY
-- Current Production already has this v4 classification-only function.
-- Add this as a forward migration so a clean migration replay reproduces Production.

begin;

do $preflight$
declare
    definition text;
begin
    if to_regprocedure(
        'fitmatch_vnext.classification_decision(text,text)'
    ) is null then
        raise exception 'classification_decision is missing';
    end if;

    definition := pg_get_functiondef(
        'fitmatch_vnext.classification_decision(text,text)'::regprocedure
    );

    if position(
        'fitmatch-vnext-resolver-v3'
        in definition
    ) = 0
    and position(
        'fitmatch-vnext-resolver-v4-classification-only'
        in definition
    ) = 0 then
        raise exception 'Unexpected classification_decision preimage';
    end if;
end
$preflight$;

create or replace function fitmatch_vnext.classification_decision(
    p_source_code text,
    p_source_product_key text
)
returns jsonb
language sql
stable
set search_path = ''
as $function$

with recursive product_row as (
    select p.*
    from fitmatch_vnext.products p
    where p.source_code = p_source_code
      and p.source_product_key = p_source_product_key
),

comparison_unit as (
    -- Diagnostic only. Measurement readiness must not decide classification.
    select
        p.id,
        fitmatch_vnext.product_comparison_unit_decision(p.id) unit
    from product_row p
),

evidence as (
    select
        p.id product_id,
        pcs.source_signal_id,
        pcs.evidence_order,
        ss.signal_kind,
        ss.external_key,
        case ss.signal_kind
            when 'PRODUCT_EXACT' then 600
            when 'PRODUCT_STRUCTURE' then 500
            when 'PRODUCT_TYPE' then 400
            when 'SUBFAMILY' then 300
            when 'FAMILY' then 250
            when 'CATEGORY' then 200
            when 'SECTION' then 150
            else 100
        end evidence_rank
    from product_row p
    join fitmatch_vnext.product_classification_signals pcs
      on pcs.product_id = p.id
    join fitmatch_vnext.source_classification_signals ss
      on ss.id = pcs.source_signal_id
     and ss.source_code = p.source_code
     and ss.is_active
),

raw_candidates as (
    select
        e.*,
        m.id mapping_id,
        m.resolution_mode,
        m.garment_type_code,
        m.sleeve_length_code,
        m.lower_length_code,
        m.body_length_code,
        m.priority,
        m.mapping_version,
        m.mapping_checksum
    from evidence e
    join product_row p
      on p.id = e.product_id
    join fitmatch_vnext.classification_signal_mappings m
      on m.source_signal_id = e.source_signal_id
     and m.is_active
     and m.is_verified
     and (
         m.audience_code = 'ANY'
         or m.audience_code = p.audience_code
     )
     and (
         coalesce(m.mapping_version, '')
             <> 'vnext-uniqlo-complete-path-20260902-v3'
         or fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current(m.id)
     )
),

signal_ancestry(
    descendant_id,
    ancestor_id,
    depth
) as (
    select
        s.id,
        s.parent_signal_id,
        1
    from fitmatch_vnext.source_classification_signals s
    where s.parent_signal_id is not null

    union all

    select
        a.descendant_id,
        s.parent_signal_id,
        a.depth + 1
    from signal_ancestry a
    join fitmatch_vnext.source_classification_signals s
      on s.id = a.ancestor_id
    where s.parent_signal_id is not null
      and a.depth < 16
),

candidates as (
    select
        c.*,
        max(c.evidence_rank) over () max_evidence_rank
    from raw_candidates c
    where not exists (
        select 1
        from raw_candidates d
        join signal_ancestry a
          on a.descendant_id = d.source_signal_id
         and a.ancestor_id = c.source_signal_id
        where d.product_id = c.product_id
          and c.resolution_mode = 'PRODUCT_REQUIRED'
          and d.resolution_mode = 'DIRECT'
          and d.evidence_rank = c.evidence_rank
          and d.priority = c.priority
    )
),

ranked as (
    select
        c.*,
        max(priority) over () max_priority
    from candidates c
    where evidence_rank = max_evidence_rank
),

top_candidates as (
    select *
    from ranked
    where priority = max_priority
),

summary as (
    select
        count(*) candidate_count,
        count(
            distinct concat_ws(
                '|',
                resolution_mode,
                coalesce(garment_type_code, '∅'),
                coalesce(sleeve_length_code, '∅'),
                coalesce(lower_length_code, '∅'),
                coalesce(body_length_code, '∅')
            )
        ) outcome_count
    from top_candidates
),

chosen as (
    select *
    from top_candidates
    order by evidence_order, source_signal_id, mapping_id
    limit 1
),

resolved as (
    select
        p.*,
        unit.unit comparison_unit,
        c.source_signal_id,
        c.mapping_id,
        c.resolution_mode mapping_resolution_mode,
        c.garment_type_code mapped_garment_type_code,
        c.sleeve_length_code mapped_sleeve_length_code,
        c.lower_length_code mapped_lower_length_code,
        c.body_length_code mapped_body_length_code,
        c.mapping_version,
        c.mapping_checksum,
        coalesce(s.candidate_count, 0) candidate_count,
        coalesce(s.outcome_count, 0) outcome_count
    from product_row p
    left join comparison_unit unit
      on unit.id = p.id
    left join summary s
      on true
    left join chosen c
      on true
),

decision as (
    select
        r.*,

        case
            when upper(coalesce(r.product_structure_code, 'UNKNOWN')) = 'SET'
                then 'NOT_APPLICABLE'
            when r.candidate_count = 0
                then 'REVIEW_REQUIRED'
            when r.outcome_count > 1
                then 'REVIEW_REQUIRED'
            when r.mapping_resolution_mode = 'NOT_APPLICABLE'
                then 'NOT_APPLICABLE'
            when r.mapping_resolution_mode = 'DIRECT'
             and coalesce(
                (
                    fitmatch_vnext.classification_tuple_validation(
                        r.mapped_garment_type_code,
                        r.product_structure_code,
                        r.audience_code,
                        r.mapped_sleeve_length_code,
                        r.mapped_lower_length_code,
                        r.mapped_body_length_code
                    ) ->> 'valid'
                )::boolean,
                false
             )
                then 'CONFIRMED'
            else 'REVIEW_REQUIRED'
        end decision_status,

        case
            when upper(coalesce(r.product_structure_code, 'UNKNOWN')) = 'SET'
                then 'Product structure is SET'
            when r.candidate_count = 0
                then 'No active verified mapping candidate'
            when r.outcome_count > 1
                then 'Equal-top candidates have different outcomes'
            when r.mapping_resolution_mode = 'NOT_APPLICABLE'
                then 'Mapping is NOT_APPLICABLE'
            when r.mapping_resolution_mode = 'DIRECT'
             and coalesce(
                (
                    fitmatch_vnext.classification_tuple_validation(
                        r.mapped_garment_type_code,
                        r.product_structure_code,
                        r.audience_code,
                        r.mapped_sleeve_length_code,
                        r.mapped_lower_length_code,
                        r.mapped_body_length_code
                    ) ->> 'valid'
                )::boolean,
                false
             )
                then 'Complete verified DIRECT classification mapping'
            when r.mapping_resolution_mode = 'DIRECT'
                then 'DIRECT classification tuple is invalid'
            when r.mapping_resolution_mode = 'PRODUCT_REQUIRED'
                then 'Product-exact verified evidence is required'
            else 'Mapping requires review'
        end decision_reason
    from resolved r
)

select case
    when not exists (select 1 from product_row)
    then jsonb_build_object(
        'found', false,
        'classification_status', 'REVIEW_REQUIRED',
        'resolution_mode', 'REVIEW_REQUIRED',
        'reason', 'Unknown source product identity',
        'resolver_version', 'fitmatch-vnext-resolver-v4-classification-only'
    )
    else (
        select jsonb_strip_nulls(
            jsonb_build_object(
                'found', true,
                'product_id', d.id,
                'source_code', d.source_code,
                'source_product_key', d.source_product_key,
                'classification_status', d.decision_status,
                'resolution_mode', case
                    when d.decision_status = 'CONFIRMED' then 'DIRECT'
                    when d.decision_status = 'NOT_APPLICABLE' then 'NOT_APPLICABLE'
                    else coalesce(d.mapping_resolution_mode, 'REVIEW_REQUIRED')
                end,
                'garment_type_code', case
                    when d.decision_status = 'CONFIRMED'
                    then d.mapped_garment_type_code
                end,
                'product_structure_code', d.product_structure_code,

                -- Diagnostic only. Not part of classification decision.
                'comparison_measurement_contract',
                    d.comparison_unit ->> 'measurement_contract',
                'comparison_unit_eligible',
                    d.comparison_unit -> 'eligible',

                'audience_code', d.audience_code,
                'sleeve_length_code', case
                    when d.decision_status = 'CONFIRMED'
                    then d.mapped_sleeve_length_code
                end,
                'lower_length_code', case
                    when d.decision_status = 'CONFIRMED'
                    then d.mapped_lower_length_code
                end,
                'body_length_code', case
                    when d.decision_status = 'CONFIRMED'
                    then d.mapped_body_length_code
                end,
                'primary_source_signal_id', d.source_signal_id,
                'mapping_id', d.mapping_id,
                'mapping_version', d.mapping_version,
                'mapping_checksum', d.mapping_checksum,
                'reason', d.decision_reason,
                'resolver_version',
                    'fitmatch-vnext-resolver-v4-classification-only',

                -- Measurement contract deliberately excluded from fingerprint.
                'input_fingerprint',
                    encode(
                        extensions.digest(
                            concat_ws(
                                '|',
                                d.source_code,
                                d.source_product_key,
                                d.audience_code,
                                d.product_structure_code,
                                coalesce(d.source_signal_id::text, '∅'),
                                coalesce(d.mapping_checksum, '∅'),
                                'fitmatch-vnext-resolver-v4-classification-only'
                            ),
                            'sha256'
                        ),
                        'hex'
                    )
            )
        )
        from decision d
    )
end;

$function$;

revoke all
on function fitmatch_vnext.classification_decision(text,text)
from public;

grant execute
on function fitmatch_vnext.classification_decision(text,text)
to anon, authenticated, service_role;

do $postflight$
declare
    definition text;
begin
    definition := pg_get_functiondef(
        'fitmatch_vnext.classification_decision(text,text)'::regprocedure
    );

    if position(
        'fitmatch-vnext-resolver-v4-classification-only'
        in definition
    ) = 0
       or position(
           'comparison_unit_tuple_validation'
           in definition
       ) > 0 then
        raise exception 'classification-only resolver postflight failed';
    end if;
end
$postflight$;

commit;
