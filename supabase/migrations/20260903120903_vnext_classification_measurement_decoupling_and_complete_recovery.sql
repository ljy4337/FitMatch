-- Classification answers what the garment is. Measurement readiness answers
-- whether that complete classification can currently be compared. Keep those
-- contracts independent and issue only complete canonical recovery tuples.

begin;

do $preflight$
declare
    trigger_definition text;
    recovery_definition text;
    effective_definition text;
begin
    if to_regprocedure(
           'fitmatch_vnext.validate_garment_axis_values()'
       ) is null
       or to_regprocedure(
           'fitmatch_vnext.classification_tuple_validation(text,text,text,text,text,text)'
       ) is null
       or to_regprocedure(
           'fitmatch_vnext.classification_recovery_options(uuid)'
       ) is null
       or to_regprocedure(
           'fitmatch_vnext.exact_product_authority_recovery_options(uuid)'
       ) is null
       or to_regprocedure(
           'fitmatch_vnext.effective_target_classification(uuid)'
       ) is null
       or to_regclass(
           'fitmatch_catalog.current_product_classifications'
       ) is null then
        raise exception 'Required classification authority is missing';
    end if;

    trigger_definition := pg_get_functiondef(
        'fitmatch_vnext.validate_garment_axis_values()'::regprocedure
    );
    recovery_definition := pg_get_functiondef(
        'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
    );
    effective_definition := pg_get_functiondef(
        'fitmatch_vnext.effective_target_classification(uuid)'::regprocedure
    );

    if position('comparison_measurement_contract' in trigger_definition) = 0
       or (
           position(
               'fitmatch-vnext-recovery-v5-garment-type-first' in
               recovery_definition
           ) = 0
           and position(
               'fitmatch-vnext-recovery-candidates-v2-comparison-unit' in
               recovery_definition
           ) = 0
       )
       or position(
           'fitmatch-vnext-effective-target-v1' in
           effective_definition
       ) = 0 then
        raise exception 'Unexpected classification contract preimage';
    end if;
end
$preflight$;

create or replace function fitmatch_vnext.validate_garment_axis_values()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    gt fitmatch_vnext.garment_types%rowtype;
    enforce_complete boolean := false;
    structure_code text;
    audience text;
begin
    if new.garment_type_code is null then
        if tg_table_name = 'products'
           and new.classification_status = 'CONFIRMED' then
            raise exception 'CONFIRMED product requires garment_type_code';
        end if;
        return new;
    end if;

    select * into gt
    from fitmatch_vnext.garment_types
    where garment_type_code = new.garment_type_code;

    if not found or not gt.is_active then
        raise exception 'Unknown or inactive garment_type_code %',
            new.garment_type_code;
    end if;
    if not gt.uses_sleeve_length and new.sleeve_length_code is not null then
        raise exception 'garment_type % does not use sleeve_length_code',
            new.garment_type_code;
    end if;
    if not gt.uses_lower_length and new.lower_length_code is not null then
        raise exception 'garment_type % does not use lower_length_code',
            new.garment_type_code;
    end if;
    if not gt.uses_body_length and new.body_length_code is not null then
        raise exception 'garment_type % does not use body_length_code',
            new.garment_type_code;
    end if;

    if tg_table_name = 'products' then
        enforce_complete := new.classification_status = 'CONFIRMED';
        structure_code := upper(coalesce(
            new.product_structure_code,
            'UNKNOWN'
        ));
        audience := new.audience_code;
    elsif tg_table_name = 'closet_items' then
        enforce_complete := true;
        structure_code := 'SINGLE';
        audience := new.audience_code;
    end if;

    if enforce_complete then
        if structure_code = 'SET'
           or structure_code not in ('SINGLE', 'MULTIPACK', 'UNKNOWN') then
            raise exception 'comparable classification requires an eligible product structure';
        end if;
        if audience is null or audience = 'UNKNOWN' then
            raise exception 'comparable classification requires known audience_code';
        end if;
        if gt.uses_sleeve_length
           and (
               new.sleeve_length_code is null
               or new.sleeve_length_code = 'UNKNOWN'
           ) then
            raise exception 'garment_type % requires a known sleeve_length_code',
                new.garment_type_code;
        end if;
        if gt.uses_lower_length
           and (
               new.lower_length_code is null
               or new.lower_length_code = 'UNKNOWN'
           ) then
            raise exception 'garment_type % requires a known lower_length_code',
                new.garment_type_code;
        end if;
        if gt.uses_body_length
           and (
               new.body_length_code is null
               or new.body_length_code = 'UNKNOWN'
           ) then
            raise exception 'garment_type % requires a known body_length_code',
                new.garment_type_code;
        end if;
    end if;

    return new;
end
$function$;

create or replace function fitmatch_vnext.classification_recovery_options(
    p_product_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    product_row fitmatch_vnext.products%rowtype;
    current_decision jsonb;
    exact_recovery_value jsonb := '{}'::jsonb;
    exact_has_precedence boolean := false;
    exact_contract_invalid boolean := false;
    exact_candidate_count_value integer := 0;
    invalid_exact_candidate_count_value integer := 0;
    raw_evidence_count_value integer := 0;
    candidate_count_value integer := 0;
    category_count_value integer := 0;
    garment_count_value integer := 0;
    sleeve_count_value integer := 0;
    lower_count_value integer := 0;
    body_count_value integer := 0;
    sleeve_follow_up_value boolean := false;
    lower_follow_up_value boolean := false;
    body_follow_up_value boolean := false;
    category_value text;
    garment_value text;
    policy_value text;
    sleeve_value text;
    lower_value text;
    body_value text;
    candidates_value jsonb := '[]'::jsonb;
    fixed_facts_value jsonb := '{}'::jsonb;
    unknown_fields_value jsonb := '[]'::jsonb;
    candidate_set_hash_value text;
    recoverability_value text := 'UNRECOVERABLE';
    unrecoverable_reason_value text;
    contract_version_value constant text :=
        'fitmatch-vnext-recovery-v6-complete-tuple-garment-first';
begin
    if caller_id is null
       and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Authentication required';
    end if;

    select * into product_row
    from fitmatch_vnext.products p
    where p.id = p_product_id;

    if not found then
        raise exception 'Product not found';
    end if;

    current_decision := fitmatch_vnext.classification_decision(
        product_row.source_code,
        product_row.source_product_key
    );

    if product_row.classification_status <> 'REVIEW_REQUIRED' then
        unrecoverable_reason_value := 'GLOBAL_STATUS_NOT_REVIEW_REQUIRED';
    elsif current_decision ->> 'reason'
          <> 'Product-exact verified evidence is required' then
        unrecoverable_reason_value := 'REVIEW_REASON_NOT_PRODUCT_REQUIRED';
    else
        -- Existing exact-product authority remains first. Its candidates are
        -- revalidated and re-fingerprinted under this complete-tuple contract.
        exact_recovery_value :=
            fitmatch_vnext.exact_product_authority_recovery_options(
                product_row.id
            );
        exact_has_precedence :=
            exact_recovery_value ->> 'recoverability' = 'RECOVERABLE';
        exact_candidate_count_value := jsonb_array_length(
            coalesce(exact_recovery_value -> 'candidates', '[]'::jsonb)
        );
        exact_contract_invalid := exact_has_precedence and (
            exact_candidate_count_value not between 1 and 3
            or exact_candidate_count_value <> coalesce(
                (exact_recovery_value ->> 'candidate_count')::integer,
                -1
            )
        );

        with
        terminal_signal as (
            select s.id, s.parent_signal_id,
                   case when lower(btrim(coalesce(s.signal_name, ''))) in (
                       '유니섹스', 'unisex', 'gu', '기타', 'other'
                   ) then true else false end is_generic_leaf
            from fitmatch_vnext.product_classification_signals pcs
            join fitmatch_vnext.source_classification_signals s
              on s.id = pcs.source_signal_id
             and s.source_code = product_row.source_code
             and s.signal_kind = 'CATEGORY'
             and s.is_active
            where pcs.product_id = product_row.id
            order by pcs.evidence_order desc, s.id
            limit 1
        ),
        legacy_exact_raw as (
            select legacy.classification_id,
                   case legacy.detail_code
                       when 'padding' then 'puffer_jacket'
                       when 'padded_vest' then 'puffer_vest'
                       when 'jeans' then 'denim_pants'
                       when 'fleece' then 'fleece_jacket'
                       when 'sweat_jogger' then 'sweat_jogger_pants'
                       when 'cargo_utility' then 'cargo_pants'
                       when 'chino_cotton' then 'chino_cotton_pants'
                       else legacy.detail_code
                   end garment_type_code,
                   nullif(legacy.length_code, 'UNKNOWN') length_code,
                   legacy.comparison_family_code
            from fitmatch_catalog.current_product_classifications legacy
            where lower(legacy.source) = lower(product_row.source_code)
              and legacy.external_product_id =
                  product_row.source_product_key
              and lower(legacy.classification_status) = 'confirmed'
              and coalesce(legacy.confidence, 0) = 1
              and coalesce(
                  (legacy.evidence ->> 'exact_product_authority')::boolean,
                  false
              )
              and legacy.evidence ->> 'authority_status' = 'verified'
        ),
        legacy_exact as (
            select legacy.*, gt.uses_sleeve_length,
                   gt.uses_lower_length, gt.uses_body_length
            from legacy_exact_raw legacy
            join fitmatch_vnext.garment_types gt
              on gt.garment_type_code = legacy.garment_type_code
             and gt.is_active
             and gt.comparison_policy_code =
                 legacy.comparison_family_code
        ),
        legacy_axis_facts as (
            select
                case when count(distinct length_code) filter (
                        where length_code in (
                            'short_sleeve', 'long_sleeve', 'sleeveless'
                        )
                    ) = 1
                    then min(length_code) filter (
                        where length_code in (
                            'short_sleeve', 'long_sleeve', 'sleeveless'
                        )
                    ) end sleeve_length_code,
                case when count(distinct length_code) filter (
                        where uses_lower_length
                          and not uses_sleeve_length
                          and not uses_body_length
                    ) = 1
                    then min(length_code) filter (
                        where uses_lower_length
                          and not uses_sleeve_length
                          and not uses_body_length
                    ) end lower_length_code,
                case when count(distinct length_code) filter (
                        where uses_body_length
                          and not uses_sleeve_length
                          and not uses_lower_length
                    ) = 1
                    then min(length_code) filter (
                        where uses_body_length
                          and not uses_sleeve_length
                          and not uses_lower_length
                    ) end body_length_code
            from legacy_exact
        ),
        known_axes as (
            select coalesce(
                       nullif(product_row.sleeve_length_code, 'UNKNOWN'),
                       legacy.sleeve_length_code
                   ) sleeve_length_code,
                   coalesce(
                       nullif(product_row.lower_length_code, 'UNKNOWN'),
                       legacy.lower_length_code
                   ) lower_length_code,
                   coalesce(
                       nullif(product_row.body_length_code, 'UNKNOWN'),
                       legacy.body_length_code
                   ) body_length_code
            from legacy_axis_facts legacy
        ),
        exact_contract_evidence as (
            select 'exact-contract:' ||
                       (candidate ->> 'candidate_fingerprint') evidence_id,
                   0 source_priority,
                   candidate ->> 'category_code' category_code,
                   candidate ->> 'garment_type_code' garment_type_code,
                   nullif(candidate ->> 'sleeve_length_code', 'UNKNOWN')
                       sleeve_length_code,
                   nullif(candidate ->> 'lower_length_code', 'UNKNOWN')
                       lower_length_code,
                   nullif(candidate ->> 'body_length_code', 'UNKNOWN')
                       body_length_code,
                   candidate ->> 'comparison_policy_code'
                       comparison_policy_code
            from jsonb_array_elements(
                case when exact_has_precedence
                    then coalesce(
                        exact_recovery_value -> 'candidates',
                        '[]'::jsonb
                    )
                    else '[]'::jsonb
                end
            ) candidate
        ),
        invalid_exact_contract_candidates as (
            select count(*)::integer candidate_count
            from exact_contract_evidence candidate
            where not exists (
                select 1
                from fitmatch_vnext.garment_types gt
                join fitmatch_vnext.comparison_policies policy
                  on policy.policy_code = gt.comparison_policy_code
                 and policy.is_active
                where gt.garment_type_code =
                      candidate.garment_type_code
                  and gt.is_active
                  and gt.category_code = candidate.category_code
                  and gt.comparison_policy_code =
                      candidate.comparison_policy_code
                  and coalesce((
                      fitmatch_vnext.classification_tuple_validation(
                          candidate.garment_type_code,
                          product_row.product_structure_code,
                          product_row.audience_code,
                          candidate.sleeve_length_code,
                          candidate.lower_length_code,
                          candidate.body_length_code
                      ) ->> 'valid'
                  )::boolean, false)
            )
        ),
        product_evidence as (
            select 'product:' || product_row.id::text evidence_id,
                   10 source_priority,
                   null::text category_code,
                   product_row.garment_type_code,
                   nullif(product_row.sleeve_length_code, 'UNKNOWN')
                       sleeve_length_code,
                   nullif(product_row.lower_length_code, 'UNKNOWN')
                       lower_length_code,
                   nullif(product_row.body_length_code, 'UNKNOWN')
                       body_length_code,
                   null::text comparison_policy_code
            where not exact_has_precedence
              and product_row.garment_type_code is not null
        ),
        exact_legacy_evidence as (
            select 'legacy-exact:' || classification_id::text evidence_id,
                   20 source_priority,
                   null::text category_code,
                   garment_type_code,
                   null::text sleeve_length_code,
                   null::text lower_length_code,
                   null::text body_length_code,
                   comparison_family_code comparison_policy_code
            from legacy_exact
            where not exact_has_precedence
        ),
        terminal_historical_evidence as (
            select 'terminal-mapping:' || m.id::text evidence_id,
                   30 source_priority,
                   null::text category_code,
                   m.garment_type_code,
                   nullif(m.sleeve_length_code, 'UNKNOWN')
                       sleeve_length_code,
                   nullif(m.lower_length_code, 'UNKNOWN')
                       lower_length_code,
                   nullif(m.body_length_code, 'UNKNOWN')
                       body_length_code,
                   null::text comparison_policy_code
            from terminal_signal terminal
            join fitmatch_vnext.classification_signal_mappings m
              on m.source_signal_id = terminal.id
             and m.is_verified
             and not m.is_active
             and m.resolution_mode = 'DIRECT'
             and m.garment_type_code is not null
             and (
                 m.audience_code = 'ANY'
                 or m.audience_code = product_row.audience_code
             )
            where not exact_has_precedence
              and not terminal.is_generic_leaf
        ),
        generic_sibling_evidence as (
            select 'sibling-mapping:' || m.id::text evidence_id,
                   40 source_priority,
                   null::text category_code,
                   m.garment_type_code,
                   nullif(m.sleeve_length_code, 'UNKNOWN')
                       sleeve_length_code,
                   nullif(m.lower_length_code, 'UNKNOWN')
                       lower_length_code,
                   nullif(m.body_length_code, 'UNKNOWN')
                       body_length_code,
                   null::text comparison_policy_code
            from terminal_signal terminal
            join fitmatch_vnext.source_classification_signals sibling
              on sibling.parent_signal_id = terminal.parent_signal_id
             and sibling.source_code = product_row.source_code
             and sibling.signal_kind = 'CATEGORY'
             and sibling.is_active
            join fitmatch_vnext.classification_signal_mappings m
              on m.source_signal_id = sibling.id
             and m.is_verified
             and not m.is_active
             and m.resolution_mode = 'DIRECT'
             and m.garment_type_code is not null
             and (
                 m.audience_code = 'ANY'
                 or m.audience_code = product_row.audience_code
             )
            where not exact_has_precedence
              and terminal.is_generic_leaf
        ),
        evidence_rows as (
            select * from exact_contract_evidence
            union all select * from product_evidence
            union all select * from exact_legacy_evidence
            union all select * from terminal_historical_evidence
            union all select * from generic_sibling_evidence
        ),
        completed_evidence as (
            select evidence.evidence_id, evidence.source_priority,
                   gt.category_code, gt.garment_type_code,
                   case when gt.uses_sleeve_length then coalesce(
                       axes.sleeve_length_code,
                       evidence.sleeve_length_code
                   ) end sleeve_length_code,
                   case when gt.uses_lower_length then coalesce(
                       axes.lower_length_code,
                       evidence.lower_length_code
                   ) end lower_length_code,
                   case when gt.uses_body_length then coalesce(
                       axes.body_length_code,
                       evidence.body_length_code
                   ) end body_length_code,
                   gt.comparison_policy_code, gt.display_name,
                   gt.sort_order
            from evidence_rows evidence
            cross join known_axes axes
            join fitmatch_vnext.garment_types gt
              on gt.garment_type_code = evidence.garment_type_code
             and gt.is_active
            join fitmatch_vnext.comparison_policies policy
              on policy.policy_code = gt.comparison_policy_code
             and policy.is_active
            where (
                    evidence.category_code is null
                    or evidence.category_code = gt.category_code
                  )
              and (
                    evidence.comparison_policy_code is null
                    or evidence.comparison_policy_code =
                       gt.comparison_policy_code
                  )
              and (
                    gt.uses_sleeve_length
                    or evidence.sleeve_length_code is null
                  )
              and (
                    gt.uses_lower_length
                    or evidence.lower_length_code is null
                  )
              and (
                    gt.uses_body_length
                    or evidence.body_length_code is null
                  )
              and (
                    axes.sleeve_length_code is null
                    or evidence.sleeve_length_code is null
                    or axes.sleeve_length_code =
                       evidence.sleeve_length_code
                  )
              and (
                    axes.lower_length_code is null
                    or evidence.lower_length_code is null
                    or axes.lower_length_code = evidence.lower_length_code
                  )
              and (
                    axes.body_length_code is null
                    or evidence.body_length_code is null
                    or axes.body_length_code = evidence.body_length_code
                  )
        ),
        canonical_candidates as (
            select distinct on (
                category_code, garment_type_code,
                coalesce(sleeve_length_code, '∅'),
                coalesce(lower_length_code, '∅'),
                coalesce(body_length_code, '∅'),
                comparison_policy_code
            ) *
            from completed_evidence candidate
            where coalesce((
                fitmatch_vnext.classification_tuple_validation(
                    candidate.garment_type_code,
                    product_row.product_structure_code,
                    product_row.audience_code,
                    candidate.sleeve_length_code,
                    candidate.lower_length_code,
                    candidate.body_length_code
                ) ->> 'valid'
            )::boolean, false)
            order by category_code, garment_type_code,
                     coalesce(sleeve_length_code, '∅'),
                     coalesce(lower_length_code, '∅'),
                     coalesce(body_length_code, '∅'),
                     comparison_policy_code, source_priority, evidence_id
        ),
        fingerprinted as (
            select candidate.*,
                   encode(extensions.digest(concat_ws('|',
                       product_row.id::text,
                       product_row.input_fingerprint,
                       product_row.evidence_fingerprint,
                       product_row.resolver_version,
                       candidate.category_code,
                       candidate.garment_type_code,
                       coalesce(candidate.sleeve_length_code, '∅'),
                       coalesce(candidate.lower_length_code, '∅'),
                       coalesce(candidate.body_length_code, '∅'),
                       candidate.comparison_policy_code,
                       contract_version_value
                   ), 'sha256'), 'hex') candidate_fingerprint
            from canonical_candidates candidate
        ),
        aggregate_value as (
            select
                (select count(*)::integer from evidence_rows)
                    raw_evidence_count,
                (select candidate_count
                 from invalid_exact_contract_candidates)
                    invalid_exact_candidate_count,
                count(*)::integer candidate_count,
                count(distinct category_code)::integer category_count,
                count(distinct garment_type_code)::integer garment_count,
                count(distinct coalesce(sleeve_length_code, '∅'))::integer
                    sleeve_count,
                count(distinct coalesce(lower_length_code, '∅'))::integer
                    lower_count,
                count(distinct coalesce(body_length_code, '∅'))::integer
                    body_count,
                min(category_code) category_code,
                min(garment_type_code) garment_type_code,
                min(comparison_policy_code) comparison_policy_code,
                min(sleeve_length_code) sleeve_length_code,
                min(lower_length_code) lower_length_code,
                min(body_length_code) body_length_code,
                coalesce(jsonb_agg(jsonb_build_object(
                    'candidate_id', candidate_fingerprint,
                    'candidate_fingerprint', candidate_fingerprint,
                    'display_name', display_name,
                    'category_code', category_code,
                    'garment_type_code', garment_type_code,
                    'sleeve_length_code', sleeve_length_code,
                    'lower_length_code', lower_length_code,
                    'body_length_code', body_length_code,
                    'comparison_policy_code', comparison_policy_code
                ) order by sort_order, garment_type_code,
                    coalesce(sleeve_length_code, '∅'),
                    coalesce(lower_length_code, '∅'),
                    coalesce(body_length_code, '∅')),
                    '[]'::jsonb) candidates,
                encode(extensions.digest(coalesce(string_agg(
                    candidate_fingerprint,
                    E'\n' order by candidate_fingerprint
                ), ''), 'sha256'), 'hex') candidate_set_hash
            from fingerprinted
        )
        select raw_evidence_count, invalid_exact_candidate_count,
               candidate_count, category_count,
               garment_count, sleeve_count, lower_count, body_count,
               category_code, garment_type_code, comparison_policy_code,
               sleeve_length_code, lower_length_code, body_length_code,
               candidates, candidate_set_hash
        into raw_evidence_count_value, invalid_exact_candidate_count_value,
             candidate_count_value,
             category_count_value, garment_count_value,
             sleeve_count_value, lower_count_value, body_count_value,
             category_value, garment_value, policy_value,
             sleeve_value, lower_value, body_value,
             candidates_value, candidate_set_hash_value
        from aggregate_value;

        if exact_contract_invalid
           or invalid_exact_candidate_count_value > 0 then
            unrecoverable_reason_value := 'EXACT_PRODUCT_CONTRACT_INVALID';
        elsif raw_evidence_count_value = 0 then
            unrecoverable_reason_value := 'NO_SAFE_GARMENT_TYPE_CANDIDATE';
        elsif candidate_count_value = 0 then
            unrecoverable_reason_value :=
                'NO_COMPLETE_CANONICAL_TUPLE_CANDIDATE';
        elsif candidate_count_value > 3 then
            unrecoverable_reason_value :=
                'COMPLETE_TUPLE_CANDIDATE_SET_NOT_BOUNDED';
        elsif category_count_value <> 1 then
            unrecoverable_reason_value :=
                'COMPLETE_TUPLE_CANDIDATES_CROSS_CATEGORIES';
        else
            recoverability_value := 'RECOVERABLE';
            unrecoverable_reason_value := null;
            select
                coalesce(bool_or(
                    grouped.candidate_count > 1
                    and grouped.sleeve_count > 1
                ), false),
                coalesce(bool_or(
                    grouped.candidate_count > 1
                    and grouped.lower_count > 1
                ), false),
                coalesce(bool_or(
                    grouped.candidate_count > 1
                    and grouped.body_count > 1
                ), false)
            into sleeve_follow_up_value, lower_follow_up_value,
                 body_follow_up_value
            from (
                select c ->> 'garment_type_code' garment_type_code,
                       count(*)::integer candidate_count,
                       count(distinct c ->> 'sleeve_length_code')::integer
                           sleeve_count,
                       count(distinct c ->> 'lower_length_code')::integer
                           lower_count,
                       count(distinct c ->> 'body_length_code')::integer
                           body_count
                from jsonb_array_elements(candidates_value) c
                group by c ->> 'garment_type_code'
            ) grouped;
            fixed_facts_value := jsonb_strip_nulls(jsonb_build_object(
                'audience_code', product_row.audience_code,
                'product_structure_code', product_row.product_structure_code,
                'category_code', case when category_count_value = 1
                    then category_value end,
                'garment_type_code', case when garment_count_value = 1
                    then garment_value end,
                'sleeve_length_code', case when sleeve_count_value = 1
                    then sleeve_value end,
                'lower_length_code', case when lower_count_value = 1
                    then lower_value end,
                'body_length_code', case when body_count_value = 1
                    then body_value end,
                'comparison_policy_code', case when garment_count_value = 1
                    then policy_value end
            ));
            select coalesce(
                jsonb_agg(field_name order by field_order),
                '[]'::jsonb
            )
            into unknown_fields_value
            from (values
                ('garment_type', 1, garment_count_value > 1),
                ('sleeve_length', 2, sleeve_follow_up_value),
                ('lower_length', 3, lower_follow_up_value),
                ('body_length', 4, body_follow_up_value)
            ) fields(field_name, field_order, is_unknown)
            where is_unknown;
        end if;
    end if;

    if recoverability_value <> 'RECOVERABLE' then
        candidates_value := '[]'::jsonb;
        candidate_set_hash_value := null;
        fixed_facts_value := jsonb_strip_nulls(jsonb_build_object(
            'audience_code', product_row.audience_code,
            'product_structure_code', product_row.product_structure_code
        ));
        unknown_fields_value := '[]'::jsonb;
    end if;

    return jsonb_build_object(
        'product_id', product_row.id,
        'global_status', product_row.classification_status,
        'recoverability', recoverability_value,
        'unrecoverable_reason', unrecoverable_reason_value,
        'fixed_facts', fixed_facts_value,
        'unknown_fields', unknown_fields_value,
        'candidates', candidates_value,
        'candidate_count', jsonb_array_length(candidates_value),
        'product_input_fingerprint', product_row.input_fingerprint,
        'product_evidence_fingerprint', product_row.evidence_fingerprint,
        'resolver_version', product_row.resolver_version,
        'candidate_contract_version', contract_version_value,
        'candidate_set_hash', candidate_set_hash_value,
        'current_review_reason', current_decision ->> 'reason'
    );
end
$function$;

create or replace function fitmatch_vnext.effective_target_classification(
    p_product_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    product_row fitmatch_vnext.products%rowtype;
    override_row fitmatch_vnext.user_product_classification_overrides%rowtype;
    recovery_value jsonb;
    selected_candidate jsonb;
    state_value text;
    status_value text;
    source_value text;
    category_value text;
    policy_value text;
    garment_value text;
    sleeve_value text;
    lower_value text;
    body_value text;
    override_valid boolean := false;
    tuple_matches boolean := false;
    authority_fingerprint_value text;
    personal_snapshot jsonb;
begin
    if caller_id is null
       and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Authentication required';
    end if;

    select * into product_row
    from fitmatch_vnext.products p
    where p.id = p_product_id;
    if not found then
        raise exception 'Product not found';
    end if;

    if caller_id is not null then
        select * into override_row
        from fitmatch_vnext.user_product_classification_overrides o
        where o.user_id = caller_id
          and o.product_id = product_row.id
          and o.cleared_at is null;
    end if;

    if override_row.id is not null then
        personal_snapshot := jsonb_build_object(
            'override_id', override_row.id,
            'revision', override_row.revision,
            'classification_source', override_row.classification_source,
            'category_code', override_row.category_code,
            'garment_type_code', override_row.garment_type_code,
            'audience_code', override_row.audience_code,
            'sleeve_length_code', override_row.sleeve_length_code,
            'lower_length_code', override_row.lower_length_code,
            'body_length_code', override_row.body_length_code,
            'comparison_policy_code', override_row.comparison_policy_code,
            'selected_candidate_fingerprint',
                override_row.selected_candidate_fingerprint,
            'candidate_contract_version',
                override_row.candidate_contract_version,
            'candidate_set_hash', override_row.candidate_set_hash,
            'base_product_input_fingerprint',
                override_row.base_product_input_fingerprint,
            'base_product_evidence_fingerprint',
                override_row.base_product_evidence_fingerprint,
            'base_resolver_version', override_row.base_resolver_version,
            'cleared_at', override_row.cleared_at,
            'created_at', override_row.created_at,
            'updated_at', override_row.updated_at
        );
    end if;

    if product_row.classification_status = 'CONFIRMED' then
        select gt.category_code, gt.comparison_policy_code
        into category_value, policy_value
        from fitmatch_vnext.garment_types gt
        where gt.garment_type_code = product_row.garment_type_code
          and gt.is_active;
        status_value := 'CONFIRMED';
        source_value := 'GLOBAL_CONFIRMED';
        garment_value := product_row.garment_type_code;
        sleeve_value := product_row.sleeve_length_code;
        lower_value := product_row.lower_length_code;
        body_value := product_row.body_length_code;
        if override_row.id is null then
            state_value := 'GLOBAL_CONFIRMED';
        else
            tuple_matches :=
                override_row.audience_code = product_row.audience_code
                and override_row.garment_type_code =
                    product_row.garment_type_code
                and override_row.sleeve_length_code is not distinct from
                    product_row.sleeve_length_code
                and override_row.lower_length_code is not distinct from
                    product_row.lower_length_code
                and override_row.body_length_code is not distinct from
                    product_row.body_length_code;
            state_value := case when tuple_matches
                then 'SUPERSEDED_MATCH' else 'SUPERSEDED_CONFLICT' end;
        end if;
    elsif product_row.classification_status = 'NOT_APPLICABLE' then
        state_value := 'GLOBAL_NOT_APPLICABLE';
        status_value := 'NOT_APPLICABLE';
        source_value := 'GLOBAL_NOT_APPLICABLE';
    elsif override_row.id is null or override_row.cleared_at is not null then
        state_value := 'REVIEW_REQUIRED';
        status_value := 'REVIEW_REQUIRED';
        source_value := 'NONE';
    else
        recovery_value := fitmatch_vnext.classification_recovery_options(
            product_row.id
        );
        select candidate into selected_candidate
        from jsonb_array_elements(recovery_value -> 'candidates') candidate
        where candidate ->> 'candidate_fingerprint' =
              override_row.selected_candidate_fingerprint
        limit 1;

        override_valid :=
            recovery_value ->> 'recoverability' = 'RECOVERABLE'
            and recovery_value ->> 'candidate_set_hash' =
                override_row.candidate_set_hash
            and recovery_value ->> 'candidate_contract_version' =
                override_row.candidate_contract_version
            and product_row.input_fingerprint =
                override_row.base_product_input_fingerprint
            and product_row.evidence_fingerprint =
                override_row.base_product_evidence_fingerprint
            and product_row.resolver_version =
                override_row.base_resolver_version
            and selected_candidate is not null
            and selected_candidate ->> 'garment_type_code' =
                override_row.garment_type_code
            and selected_candidate ->> 'category_code' =
                override_row.category_code
            and selected_candidate ->> 'comparison_policy_code' =
                override_row.comparison_policy_code
            and (selected_candidate ->> 'sleeve_length_code')
                is not distinct from override_row.sleeve_length_code
            and (selected_candidate ->> 'lower_length_code')
                is not distinct from override_row.lower_length_code
            and (selected_candidate ->> 'body_length_code')
                is not distinct from override_row.body_length_code
            and override_row.audience_code = product_row.audience_code
            and coalesce((
                fitmatch_vnext.classification_tuple_validation(
                    override_row.garment_type_code,
                    product_row.product_structure_code,
                    override_row.audience_code,
                    override_row.sleeve_length_code,
                    override_row.lower_length_code,
                    override_row.body_length_code
                ) ->> 'valid'
            )::boolean, false);

        -- A contract-version bump alone must not discard an otherwise fresh,
        -- canonical legacy exact-product choice. This is deliberately narrow:
        -- it requires current verified exact authority, exact tuple metadata,
        -- and all three original freshness fingerprints.
        if not override_valid
           and override_row.candidate_contract_version in (
               'fitmatch-vnext-recovery-candidates-v1',
               'fitmatch-vnext-recovery-candidates-v2-comparison-unit',
               'fitmatch-vnext-recovery-candidates-v3-exact-product',
               'fitmatch-vnext-recovery-candidates-v4-exact-product-classification-only'
           )
           and override_row.classification_source = 'USER_EXPLICIT'
           and override_row.audience_code = product_row.audience_code
           and product_row.input_fingerprint =
               override_row.base_product_input_fingerprint
           and product_row.evidence_fingerprint =
               override_row.base_product_evidence_fingerprint
           and product_row.resolver_version =
               override_row.base_resolver_version
           and coalesce((
               fitmatch_vnext.classification_tuple_validation(
                   override_row.garment_type_code,
                   product_row.product_structure_code,
                   override_row.audience_code,
                   override_row.sleeve_length_code,
                   override_row.lower_length_code,
                   override_row.body_length_code
               ) ->> 'valid'
           )::boolean, false) then
            select exists (
                select 1
                from fitmatch_catalog.current_product_classifications legacy
                join fitmatch_vnext.garment_types gt
                  on gt.garment_type_code = case legacy.detail_code
                      when 'padding' then 'puffer_jacket'
                      when 'padded_vest' then 'puffer_vest'
                      when 'jeans' then 'denim_pants'
                      when 'fleece' then 'fleece_jacket'
                      when 'sweat_jogger' then 'sweat_jogger_pants'
                      when 'cargo_utility' then 'cargo_pants'
                      when 'chino_cotton' then 'chino_cotton_pants'
                      else legacy.detail_code
                  end
                 and gt.is_active
                where lower(legacy.source) = lower(product_row.source_code)
                  and legacy.external_product_id =
                      product_row.source_product_key
                  and lower(legacy.classification_status) = 'confirmed'
                  and coalesce(legacy.confidence, 0) = 1
                  and coalesce((
                      legacy.evidence ->> 'exact_product_authority'
                  )::boolean, false)
                  and legacy.evidence ->> 'authority_status' = 'verified'
                  and gt.garment_type_code =
                      override_row.garment_type_code
                  and gt.category_code = override_row.category_code
                  and gt.comparison_policy_code =
                      override_row.comparison_policy_code
                  and legacy.comparison_family_code =
                      override_row.comparison_policy_code
            ) into override_valid;
        end if;

        if override_valid then
            state_value := 'PERSONAL_CONFIRMED';
            status_value := 'CONFIRMED';
            source_value := 'USER_EXPLICIT';
            category_value := override_row.category_code;
            policy_value := override_row.comparison_policy_code;
            garment_value := override_row.garment_type_code;
            sleeve_value := override_row.sleeve_length_code;
            lower_value := override_row.lower_length_code;
            body_value := override_row.body_length_code;
        else
            state_value := 'STALE_RECONFIRM_REQUIRED';
            status_value := 'REVIEW_REQUIRED';
            source_value := 'NONE';
        end if;
    end if;

    authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
        product_row.id::text,
        state_value,
        status_value,
        source_value,
        product_row.input_fingerprint,
        product_row.evidence_fingerprint,
        product_row.resolver_version,
        coalesce(override_row.id::text, '∅'),
        coalesce(override_row.revision::text, '∅'),
        coalesce(garment_value, '∅'),
        coalesce(sleeve_value, '∅'),
        coalesce(lower_value, '∅'),
        coalesce(body_value, '∅'),
        'fitmatch-vnext-effective-target-v1'
    ), 'sha256'), 'hex');

    return jsonb_strip_nulls(jsonb_build_object(
        'product_id', product_row.id,
        'state', state_value,
        'classification_status', status_value,
        'effective_source', source_value,
        'category_code', category_value,
        'garment_type_code', garment_value,
        'audience_code', product_row.audience_code,
        'sleeve_length_code', sleeve_value,
        'lower_length_code', lower_value,
        'body_length_code', body_value,
        'comparison_policy_code', policy_value,
        'product_structure_code', product_row.product_structure_code,
        'global_classification', jsonb_build_object(
            'status', product_row.classification_status,
            'garment_type_code', product_row.garment_type_code,
            'audience_code', product_row.audience_code,
            'sleeve_length_code', product_row.sleeve_length_code,
            'lower_length_code', product_row.lower_length_code,
            'body_length_code', product_row.body_length_code,
            'input_fingerprint', product_row.input_fingerprint,
            'evidence_fingerprint', product_row.evidence_fingerprint,
            'resolver_version', product_row.resolver_version
        ),
        'personal_projection', personal_snapshot,
        'override_revision', override_row.revision,
        'effective_authority_fingerprint', authority_fingerprint_value,
        'effective_contract_version',
            'fitmatch-vnext-effective-target-v1'
    ));
end
$function$;

revoke all on function fitmatch_vnext.classification_recovery_options(uuid)
    from public, anon;
grant execute on function fitmatch_vnext.classification_recovery_options(uuid)
    to authenticated, service_role;

revoke all on function fitmatch_vnext.effective_target_classification(uuid)
    from public, anon;
grant execute on function fitmatch_vnext.effective_target_classification(uuid)
    to authenticated, service_role;

do $postflight$
declare
    trigger_definition text := pg_get_functiondef(
        'fitmatch_vnext.validate_garment_axis_values()'::regprocedure
    );
    recovery_definition text := pg_get_functiondef(
        'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
    );
begin
    if position('comparison_measurement_contract' in trigger_definition) > 0
       or position('comparison_unit_tuple_validation' in trigger_definition) > 0
       or position(
           'fitmatch-vnext-recovery-v6-complete-tuple-garment-first' in
           recovery_definition
       ) = 0
       or position(
           'classification_tuple_validation' in
           recovery_definition
       ) = 0
       or has_function_privilege(
           'anon',
           'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure,
           'EXECUTE'
       )
       or not has_function_privilege(
           'authenticated',
           'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure,
           'EXECUTE'
       ) then
        raise exception 'Classification decoupling postflight failed';
    end if;
end
$postflight$;

commit;
