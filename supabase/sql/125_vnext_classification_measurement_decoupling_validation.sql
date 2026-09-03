-- Transactional regression for migration 20260903120903.
-- Run after 124 local fixture, 125 local preimage, and the new migration.
-- Every synthetic mutation in this file is rolled back.

begin;

select set_config(
    'request.jwt.claim.sub',
    '11111111-1111-1111-1111-111111111111',
    true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $classification_measurement_boundary$
declare
    readiness_value jsonb;
    authorization_value jsonb;
begin
    -- TEST 1: a complete CONFIRMED classification with ABSENT measurements
    -- is valid classification state.
    insert into fitmatch_vnext.products(
        id, source_code, source_product_key, product_name, audience_code,
        product_structure_code, garment_type_code, sleeve_length_code,
        classification_status, classification_source, resolver_version,
        input_fingerprint, evidence_fingerprint, source_extra
    ) values (
        'c0000000-0000-0000-0000-000000000101', 'fixture',
        'confirmed-absent', 'Confirmed without measurements', 'MEN',
        'SINGLE', 'tshirt', 'short_sleeve', 'CONFIRMED',
        'SOURCE_DIRECT', 'fixture-resolver-v6', 'absent-input',
        'absent-evidence', '{}'::jsonb
    );

    -- TEST 2: INCOHERENT measurements are also outside the classification
    -- trigger's responsibility.
    insert into fitmatch_vnext.products(
        id, source_code, source_product_key, product_name, audience_code,
        product_structure_code, garment_type_code, sleeve_length_code,
        classification_status, classification_source, resolver_version,
        input_fingerprint, evidence_fingerprint, source_extra
    ) values (
        'c0000000-0000-0000-0000-000000000102', 'fixture',
        'confirmed-incoherent', 'Confirmed incoherent measurements', 'MEN',
        'SINGLE', 'tshirt', 'short_sleeve', 'CONFIRMED',
        'SOURCE_DIRECT', 'fixture-resolver-v6', 'incoherent-input',
        'incoherent-evidence',
        '{"comparison_measurement_contract":{"effective_value":"INCOHERENT"}}'
    );

    -- TEST 3: the unchanged readiness and authorization boundary still
    -- rejects both products.
    readiness_value := fitmatch_vnext.product_readiness(
        'c0000000-0000-0000-0000-000000000101'
    );
    authorization_value := fitmatch_vnext.authorize_comparison(
        'f0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000101',
        null,
        false
    );
    if coalesce((readiness_value ->> 'ready')::boolean, false)
       or readiness_value ->> 'status' <> 'MEASUREMENT_NOT_READY'
       or coalesce((authorization_value ->> 'allowed')::boolean, false)
       or authorization_value ->> 'block_reason' <> 'TARGET_NOT_READY'
       or position('fixture-measurement-boundary-v1' in pg_get_functiondef(
           'fitmatch_vnext.product_readiness(uuid)'::regprocedure
       )) = 0
       or position('fixture-measurement-boundary-v1' in pg_get_functiondef(
           'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure
       )) = 0 then
        raise exception 'ABSENT readiness/authorization boundary weakened: %, %',
            readiness_value, authorization_value;
    end if;

    readiness_value := fitmatch_vnext.product_readiness(
        'c0000000-0000-0000-0000-000000000102'
    );
    if coalesce((readiness_value ->> 'ready')::boolean, false)
       or readiness_value ->> 'status' <> 'MEASUREMENT_NOT_READY' then
        raise exception 'INCOHERENT measurement became ready: %',
            readiness_value;
    end if;
end
$classification_measurement_boundary$;

do $classification_invariants$
declare
    was_rejected boolean;
begin
    -- TEST 4: required sleeve NULL remains invalid.
    was_rejected := false;
    begin
        insert into fitmatch_vnext.products(
            source_code, source_product_key, product_name, audience_code,
            product_structure_code, garment_type_code, sleeve_length_code,
            classification_status
        ) values (
            'fixture', 'invalid-null-sleeve', 'Invalid null sleeve', 'MEN',
            'SINGLE', 'tshirt', null, 'CONFIRMED'
        );
    exception when others then
        was_rejected := true;
    end;
    if not was_rejected then
        raise exception 'Required NULL sleeve was accepted';
    end if;

    -- TEST 5: required sleeve UNKNOWN remains invalid.
    was_rejected := false;
    begin
        insert into fitmatch_vnext.products(
            source_code, source_product_key, product_name, audience_code,
            product_structure_code, garment_type_code, sleeve_length_code,
            classification_status
        ) values (
            'fixture', 'invalid-unknown-sleeve', 'Invalid unknown sleeve',
            'MEN', 'SINGLE', 'tshirt', 'UNKNOWN', 'CONFIRMED'
        );
    exception when others then
        was_rejected := true;
    end;
    if not was_rejected then
        raise exception 'Required UNKNOWN sleeve was accepted';
    end if;

    -- TEST 6: an unused axis remains invalid.
    was_rejected := false;
    begin
        insert into fitmatch_vnext.products(
            source_code, source_product_key, product_name, audience_code,
            product_structure_code, garment_type_code, sleeve_length_code,
            classification_status
        ) values (
            'fixture', 'invalid-unused-axis', 'Invalid unused axis', 'MEN',
            'SINGLE', 'no_axis_top', 'long_sleeve', 'CONFIRMED'
        );
    exception when others then
        was_rejected := true;
    end;
    if not was_rejected then
        raise exception 'Unused sleeve axis was accepted';
    end if;

    -- TEST 7: unknown and inactive garment types remain invalid.
    was_rejected := false;
    begin
        insert into fitmatch_vnext.products(
            source_code, source_product_key, product_name, audience_code,
            product_structure_code, garment_type_code,
            classification_status
        ) values (
            'fixture', 'invalid-unknown-garment', 'Unknown garment', 'MEN',
            'SINGLE', 'not_a_garment', 'CONFIRMED'
        );
    exception when others then
        was_rejected := true;
    end;
    if not was_rejected then
        raise exception 'Unknown garment type was accepted';
    end if;

    was_rejected := false;
    begin
        insert into fitmatch_vnext.products(
            source_code, source_product_key, product_name, audience_code,
            product_structure_code, garment_type_code,
            classification_status
        ) values (
            'fixture', 'invalid-inactive-garment', 'Inactive garment', 'MEN',
            'SINGLE', 'inactive_top', 'CONFIRMED'
        );
    exception when others then
        was_rejected := true;
    end;
    if not was_rejected then
        raise exception 'Inactive garment type was accepted';
    end if;

    -- TEST 8: SET remains structurally ineligible.
    was_rejected := false;
    begin
        insert into fitmatch_vnext.products(
            source_code, source_product_key, product_name, audience_code,
            product_structure_code, garment_type_code, sleeve_length_code,
            classification_status
        ) values (
            'fixture', 'invalid-set', 'Invalid set', 'MEN', 'SET',
            'tshirt', 'short_sleeve', 'CONFIRMED'
        );
    exception when others then
        was_rejected := true;
    end;
    if not was_rejected then
        raise exception 'SET structure was accepted';
    end if;

    -- Existing closet complete-tuple validation remains in force.
    was_rejected := false;
    begin
        insert into fitmatch_vnext.closet_items(
            user_id, client_item_id, item_name, audience_code,
            garment_type_code, sleeve_length_code, classification_source
        ) values (
            '11111111-1111-1111-1111-111111111111', gen_random_uuid(),
            'Incomplete closet item', 'MEN', 'tshirt', null, 'USER_EXPLICIT'
        );
    exception when others then
        was_rejected := true;
    end;
    if not was_rejected then
        raise exception 'Incomplete closet tuple was accepted';
    end if;
end
$classification_invariants$;

do $complete_recovery$
declare
    options_value jsonb;
    candidate_value jsonb;
    expected_fingerprint text;
    expected_set_hash text;
begin
    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000002'
    );

    if options_value ->> 'recoverability' <> 'RECOVERABLE'
       or options_value ->> 'candidate_contract_version' <>
          'fitmatch-vnext-recovery-v6-complete-tuple-garment-first'
       or (options_value ->> 'candidate_count')::integer <> 2
       or options_value -> 'fixed_facts' ->> 'sleeve_length_code' <>
          'long_sleeve'
       or not (options_value -> 'unknown_fields') ? 'garment_type'
       or (select count(distinct c ->> 'garment_type_code')
           from jsonb_array_elements(options_value -> 'candidates') c) <> 2
       or exists (
           select 1
           from jsonb_array_elements(options_value -> 'candidates') c
           where c ->> 'garment_type_code' not in (
               'knit_sweater', 'cardigan'
           )
              or c ->> 'sleeve_length_code' <> 'long_sleeve'
              or not coalesce((
                  fitmatch_vnext.classification_tuple_validation(
                      c ->> 'garment_type_code', 'SINGLE', 'MEN',
                      c ->> 'sleeve_length_code',
                      c ->> 'lower_length_code',
                      c ->> 'body_length_code'
                  ) ->> 'valid'
              )::boolean, false)
       ) then
        raise exception 'Complete garment-first recovery regression: %',
            options_value;
    end if;

    for candidate_value in
        select c
        from jsonb_array_elements(options_value -> 'candidates') c
    loop
        expected_fingerprint := encode(extensions.digest(concat_ws('|',
            'c0000000-0000-0000-0000-000000000002',
            'recovery-input',
            'recovery-evidence',
            'fitmatch-vnext-resolver-v2',
            candidate_value ->> 'category_code',
            candidate_value ->> 'garment_type_code',
            coalesce(candidate_value ->> 'sleeve_length_code', '∅'),
            coalesce(candidate_value ->> 'lower_length_code', '∅'),
            coalesce(candidate_value ->> 'body_length_code', '∅'),
            candidate_value ->> 'comparison_policy_code',
            'fitmatch-vnext-recovery-v6-complete-tuple-garment-first'
        ), 'sha256'), 'hex');
        if candidate_value ->> 'candidate_fingerprint' <>
           expected_fingerprint
           or candidate_value ->> 'candidate_id' <> expected_fingerprint then
            raise exception 'Candidate fingerprint is not complete-tuple based';
        end if;
    end loop;

    select encode(extensions.digest(string_agg(
        c ->> 'candidate_fingerprint', E'\n'
        order by c ->> 'candidate_fingerprint'
    ), 'sha256'), 'hex')
    into expected_set_hash
    from jsonb_array_elements(options_value -> 'candidates') c;
    if options_value ->> 'candidate_set_hash' <> expected_set_hash then
        raise exception 'Candidate set hash mismatch';
    end if;

    -- A genuinely unknown required axis with no product-bound complete
    -- evidence remains unrecoverable; no taxonomy-wide expansion occurs.
    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000004'
    );
    if options_value ->> 'recoverability' <> 'UNRECOVERABLE'
       or options_value ->> 'unrecoverable_reason' <>
          'NO_COMPLETE_CANONICAL_TUPLE_CANDIDATE'
       or jsonb_array_length(options_value -> 'candidates') <> 0 then
        raise exception 'Incomplete candidate escaped fail-closed: %',
            options_value;
    end if;

    -- Existing exact-product authority remains first and is normalized into
    -- the v6 complete-tuple fingerprint without mixing fallback candidates.
    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000005'
    );
    if options_value ->> 'recoverability' <> 'RECOVERABLE'
       or (options_value ->> 'candidate_count')::integer <> 1
       or options_value -> 'candidates' -> 0 ->> 'garment_type_code' <>
          'tshirt'
       or options_value -> 'candidates' -> 0 ->> 'sleeve_length_code' <>
          'short_sleeve'
       or options_value -> 'candidates' -> 0 ->> 'candidate_fingerprint' =
          'legacy-exact-candidate' then
        raise exception 'Exact-product precedence regression: %',
            options_value;
    end if;

    -- Four evidence-bound tuples are not arbitrarily truncated to three.
    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000006'
    );
    if options_value ->> 'recoverability' <> 'UNRECOVERABLE'
       or options_value ->> 'unrecoverable_reason' <>
          'COMPLETE_TUPLE_CANDIDATE_SET_NOT_BOUNDED'
       or (options_value ->> 'candidate_count')::integer <> 0
       or jsonb_array_length(options_value -> 'candidates') <> 0 then
        raise exception 'Unsafe candidate cap/expansion regression: %',
            options_value;
    end if;
end
$complete_recovery$;

do $legacy_override_compatibility$
declare
    effective_value jsonb;
begin
    insert into fitmatch_vnext.user_product_classification_overrides(
        user_id, product_id, classification_source, audience_code,
        category_code, garment_type_code, comparison_policy_code,
        sleeve_length_code, base_product_input_fingerprint,
        base_product_evidence_fingerprint, base_resolver_version,
        selected_candidate_fingerprint, candidate_contract_version,
        candidate_set_hash, revision
    ) values (
        '11111111-1111-1111-1111-111111111111',
        'c0000000-0000-0000-0000-000000000005', 'USER_EXPLICIT',
        'MEN', 'tops', 'tshirt', 'tshirt', 'short_sleeve',
        'exact-input', 'exact-evidence', 'fixture-resolver-v6',
        'legacy-exact-candidate',
        'fitmatch-vnext-recovery-candidates-v3-exact-product',
        'legacy-exact-set', 1
    );

    effective_value := fitmatch_vnext.effective_target_classification(
        'c0000000-0000-0000-0000-000000000005'
    );
    if effective_value ->> 'state' <> 'PERSONAL_CONFIRMED'
       or effective_value ->> 'classification_status' <> 'CONFIRMED'
       or effective_value ->> 'effective_source' <> 'USER_EXPLICIT'
       or effective_value ->> 'sleeve_length_code' <> 'short_sleeve' then
        raise exception 'Fresh canonical legacy exact override was lost: %',
            effective_value;
    end if;

    insert into fitmatch_vnext.user_product_classification_overrides(
        user_id, product_id, classification_source, audience_code,
        category_code, garment_type_code, comparison_policy_code,
        sleeve_length_code, base_product_input_fingerprint,
        base_product_evidence_fingerprint, base_resolver_version,
        selected_candidate_fingerprint, candidate_contract_version,
        candidate_set_hash, revision
    ) values (
        '11111111-1111-1111-1111-111111111111',
        'c0000000-0000-0000-0000-000000000002', 'USER_EXPLICIT',
        'MEN', 'tops', 'knit_sweater', 'knit_sweater', 'long_sleeve',
        'stale-input', 'stale-evidence', 'stale-resolver',
        'legacy-stale-candidate',
        'fitmatch-vnext-recovery-candidates-v1', 'legacy-stale-set', 1
    );

    effective_value := fitmatch_vnext.effective_target_classification(
        'c0000000-0000-0000-0000-000000000002'
    );
    if effective_value ->> 'state' <> 'STALE_RECONFIRM_REQUIRED'
       or effective_value ->> 'classification_status' <> 'REVIEW_REQUIRED'
       or effective_value ->> 'effective_source' <> 'NONE' then
        raise exception 'Stale override was incorrectly preserved: %',
            effective_value;
    end if;
end
$legacy_override_compatibility$;

do $postflight_contract$
declare
    trigger_definition text := pg_get_functiondef(
        'fitmatch_vnext.validate_garment_axis_values()'::regprocedure
    );
begin
    if position('comparison_measurement_contract' in trigger_definition) > 0
       or position('classification_tuple_validation' in pg_get_functiondef(
           'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
       )) = 0
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
        raise exception 'Final classification contract postflight failed';
    end if;
end
$postflight_contract$;

rollback;

select 'CLASSIFICATION_MEASUREMENT_DECOUPLING_V6_PASS' status;
