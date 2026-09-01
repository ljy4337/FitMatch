-- Transactional validation for REVIEW_REQUIRED recovery migrations.
-- Requires 124 local fixture, then migrations 20260830090000 and
-- 20260830091000. Every synthetic mutation is rolled back.

begin;
select set_config(
    'request.jwt.claim.sub',
    '11111111-1111-1111-1111-111111111111',
    true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $phase_zero$
declare
    decision_value jsonb;
begin
    select fitmatch_vnext.classification_decision(
        'fixture', 'false-review'
    ) into decision_value;
    if decision_value ->> 'classification_status' <> 'CONFIRMED'
       or decision_value ->> 'garment_type_code' <> 'tshirt'
       or coalesce((decision_value ->> 'hierarchy_pruned_ancestor_count')::integer, 0) <> 1
       or (select classification_status from fitmatch_vnext.products
           where source_product_key = 'false-review') <> 'CONFIRMED'
       or (select classification_status from fitmatch_vnext.products
           where source_product_key = 'confirmed') <> 'CONFIRMED'
       or (select classification_status from fitmatch_vnext.products
           where source_product_key = 'recovery') <> 'REVIEW_REQUIRED' then
        raise exception 'Phase 0 hierarchy correction regression';
    end if;
end
$phase_zero$;

do $recovery_contract$
declare
    options_value jsonb;
begin
    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000002'
    );
    if options_value ->> 'recoverability' <> 'RECOVERABLE'
       or (options_value ->> 'candidate_count')::integer <> 3
       or options_value -> 'fixed_facts' ->> 'category_code' <> 'tops'
       or options_value -> 'fixed_facts' ->> 'sleeve_length_code' <>
          'short_sleeve'
       or not (options_value -> 'unknown_fields') ? 'garment_type'
       or jsonb_array_length(options_value -> 'candidates') > 3
       or exists (
           select 1 from jsonb_array_elements(options_value -> 'candidates') c
           where not coalesce((fitmatch_vnext.classification_tuple_validation(
               c ->> 'garment_type_code', 'SINGLE', 'MEN',
               c ->> 'sleeve_length_code', c ->> 'lower_length_code',
               c ->> 'body_length_code'
           ) ->> 'valid')::boolean, false)
       ) then
        raise exception 'Recovery candidate envelope regression: %', options_value;
    end if;

    update fitmatch_vnext.products
    set product_structure_code = 'UNKNOWN'
    where id = 'c0000000-0000-0000-0000-000000000002';
    if fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000002'
    ) ->> 'recoverability' <> 'UNRECOVERABLE' then
        raise exception 'UNKNOWN structure became recoverable';
    end if;
    update fitmatch_vnext.products
    set product_structure_code = 'SINGLE'
    where id = 'c0000000-0000-0000-0000-000000000002';

    update fitmatch_vnext.classification_signal_mappings
    set is_active = false
    where id in (
        'b1000000-0000-0000-0000-000000000002',
        'b1000000-0000-0000-0000-000000000003',
        'b1000000-0000-0000-0000-000000000004'
    );
    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000002'
    );
    if options_value ->> 'recoverability' <> 'UNRECOVERABLE'
       or options_value ->> 'unrecoverable_reason' <>
          'NO_VERIFIED_DESCENDANT_DIRECT_CANDIDATE'
       or jsonb_array_length(options_value -> 'candidates') <> 0 then
        raise exception 'No verified candidate did not fail closed: %',
            options_value;
    end if;
    update fitmatch_vnext.classification_signal_mappings
    set is_active = true
    where id in (
        'b1000000-0000-0000-0000-000000000002',
        'b1000000-0000-0000-0000-000000000003',
        'b1000000-0000-0000-0000-000000000004'
    );
end
$recovery_contract$;

do $set_and_security$
declare
    options_value jsonb;
    candidate_value jsonb;
    result_value jsonb;
    input_value text;
    evidence_value text;
begin
    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000002'
    );
    select c into candidate_value
    from jsonb_array_elements(options_value -> 'candidates') c
    where c ->> 'garment_type_code' = 'polo_shirt';
    input_value := options_value ->> 'product_input_fingerprint';
    evidence_value := options_value ->> 'product_evidence_fingerprint';

    begin
        perform fitmatch_vnext.set_user_product_classification(
            'c0000000-0000-0000-0000-000000000002',
            repeat('0',64), options_value ->> 'candidate_set_hash',
            input_value, evidence_value,
            '90000000-0000-0000-0000-000000000001', 0
        );
        raise exception 'Invalid candidate fingerprint was accepted';
    exception when others then
        if sqlerrm = 'Invalid candidate fingerprint was accepted' then raise; end if;
    end;

    begin
        perform fitmatch_vnext.set_user_product_classification(
            'c0000000-0000-0000-0000-000000000002',
            candidate_value ->> 'candidate_fingerprint', repeat('1',64),
            input_value, evidence_value,
            '90000000-0000-0000-0000-000000000002', 0
        );
        raise exception 'Stale candidate hash was accepted';
    exception when others then
        if sqlerrm = 'Stale candidate hash was accepted' then raise; end if;
    end;

    begin
        update fitmatch_vnext.products set input_fingerprint = 'changed-input'
        where id = 'c0000000-0000-0000-0000-000000000002';
        perform fitmatch_vnext.set_user_product_classification(
            'c0000000-0000-0000-0000-000000000002',
            candidate_value ->> 'candidate_fingerprint',
            options_value ->> 'candidate_set_hash', input_value, evidence_value,
            '90000000-0000-0000-0000-000000000003', 0
        );
        raise exception 'Stale product fingerprint was accepted';
    exception when others then
        if sqlerrm = 'Stale product fingerprint was accepted' then raise; end if;
    end;

    begin
        update fitmatch_vnext.products
        set evidence_fingerprint = 'changed-evidence'
        where id = 'c0000000-0000-0000-0000-000000000002';
        perform fitmatch_vnext.set_user_product_classification(
            'c0000000-0000-0000-0000-000000000002',
            candidate_value ->> 'candidate_fingerprint',
            options_value ->> 'candidate_set_hash', input_value, evidence_value,
            '90000000-0000-0000-0000-000000000007', 0
        );
        raise exception 'Stale evidence fingerprint was accepted';
    exception when others then
        if sqlerrm = 'Stale evidence fingerprint was accepted' then raise; end if;
    end;

    result_value := fitmatch_vnext.set_user_product_classification(
        'c0000000-0000-0000-0000-000000000002',
        candidate_value ->> 'candidate_fingerprint',
        options_value ->> 'candidate_set_hash', input_value, evidence_value,
        '90000000-0000-0000-0000-000000000004', 0
    );
    if result_value -> 'effective_classification' ->> 'state' <>
       'PERSONAL_CONFIRMED'
       or result_value -> 'effective_classification' ->>
          'effective_source' <> 'USER_EXPLICIT'
       or result_value -> 'effective_classification' ->>
          'garment_type_code' <> 'polo_shirt'
       or (select classification_status from fitmatch_vnext.products
           where id = 'c0000000-0000-0000-0000-000000000002') <>
          'REVIEW_REQUIRED'
       or (select count(*) from
           fitmatch_vnext.user_classification_feedback_evidence) <> 1 then
        raise exception 'USER_EXPLICIT projection/global separation regression';
    end if;

    result_value := fitmatch_vnext.set_user_product_classification(
        'c0000000-0000-0000-0000-000000000002',
        candidate_value ->> 'candidate_fingerprint',
        options_value ->> 'candidate_set_hash', input_value, evidence_value,
        '90000000-0000-0000-0000-000000000004', 0
    );
    if not (result_value ->> 'idempotent')::boolean
       or (select count(*) from
           fitmatch_vnext.user_classification_feedback_evidence) <> 1 then
        raise exception 'Set idempotency regression';
    end if;

    begin
        perform fitmatch_vnext.set_user_product_classification(
            'c0000000-0000-0000-0000-000000000002',
            candidate_value ->> 'candidate_fingerprint',
            options_value ->> 'candidate_set_hash', input_value, evidence_value,
            '90000000-0000-0000-0000-000000000005', 0
        );
        raise exception 'Stale revision was accepted';
    exception when others then
        if sqlerrm = 'Stale revision was accepted' then raise; end if;
    end;
end
$set_and_security$;

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '22222222-2222-2222-2222-222222222222',
    true
);

do $two_user_isolation$
declare
    options_value jsonb;
    candidate_value jsonb;
    result_value jsonb;
begin
    if exists (
        select 1
        from fitmatch_vnext.user_product_classification_overrides o
        where o.garment_type_code = 'polo_shirt'
    ) or exists (
        select 1
        from fitmatch_vnext.user_classification_feedback_evidence e
        where e.user_id = '11111111-1111-1111-1111-111111111111'
    ) then
        raise exception 'User B can read user A recovery authority/evidence';
    end if;

    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000002'
    );
    select c into candidate_value
    from jsonb_array_elements(options_value -> 'candidates') c
    where c ->> 'garment_type_code' = 'tshirt';
    result_value := fitmatch_vnext.set_user_product_classification(
        'c0000000-0000-0000-0000-000000000002',
        candidate_value ->> 'candidate_fingerprint',
        options_value ->> 'candidate_set_hash',
        options_value ->> 'product_input_fingerprint',
        options_value ->> 'product_evidence_fingerprint',
        '90000000-0000-0000-0000-000000000006', 0
    );
    if result_value -> 'effective_classification' ->>
       'garment_type_code' <> 'tshirt'
       or (select count(*)
           from fitmatch_vnext.user_product_classification_overrides) <> 1 then
        raise exception 'Two-user independent recovery projection regression';
    end if;
end
$two_user_isolation$;

reset role;
select set_config(
    'request.jwt.claim.sub',
    '11111111-1111-1111-1111-111111111111',
    true
);

do $global_authority_unchanged$
begin
    if (select classification_status from fitmatch_vnext.products
        where id = 'c0000000-0000-0000-0000-000000000002') <>
       'REVIEW_REQUIRED'
       or (select count(*) from
           fitmatch_vnext.user_product_classification_overrides) <> 2 then
        raise exception 'Per-user choices changed global Product authority';
    end if;
end
$global_authority_unchanged$;

set local role authenticated;

do $user_a_rls$
begin
    if (select count(*)
        from fitmatch_vnext.user_product_classification_overrides) <> 1
       or not exists (
           select 1
           from fitmatch_vnext.user_product_classification_overrides o
           where o.garment_type_code = 'polo_shirt'
       )
       or (select count(*)
           from fitmatch_vnext.user_classification_feedback_evidence) <> 1 then
        raise exception 'User A RLS projection/evidence isolation regression';
    end if;
end
$user_a_rls$;

reset role;

do $measurement_equivalence$
declare
    personal_value jsonb;
    global_value jsonb;
    personal_semantic jsonb;
    global_semantic jsonb;
    personal_candidates jsonb;
    global_candidates jsonb;
begin
    personal_value := fitmatch_vnext.canonical_measurements_for_size_with_context(
        'e0000000-0000-0000-0000-000000000001',
        fitmatch_vnext.effective_target_classification(
            'c0000000-0000-0000-0000-000000000002'
        )
    );
    personal_candidates := fitmatch_vnext.eligible_candidate_sizes(
        'f0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000001', false
    );

    update fitmatch_vnext.products
    set classification_status = 'CONFIRMED',
        garment_type_code = 'polo_shirt',
        sleeve_length_code = 'short_sleeve'
    where id = 'c0000000-0000-0000-0000-000000000002';
    global_value := fitmatch_vnext.canonical_measurements_for_size(
        'e0000000-0000-0000-0000-000000000001'
    );
    global_candidates := fitmatch_vnext.eligible_candidate_sizes(
        'f0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000001', false
    );
    select jsonb_agg(jsonb_build_object(
        'code', m ->> 'fitmatch_measurement_code',
        'value', m ->> 'value',
        'unit', m ->> 'unit_code',
        'basis', m ->> 'basis_code'
    ) order by m ->> 'fitmatch_measurement_code')
    into personal_semantic
    from jsonb_array_elements(personal_value -> 'measurements') m;
    select jsonb_agg(jsonb_build_object(
        'code', m ->> 'fitmatch_measurement_code',
        'value', m ->> 'value',
        'unit', m ->> 'unit_code',
        'basis', m ->> 'basis_code'
    ) order by m ->> 'fitmatch_measurement_code')
    into global_semantic
    from jsonb_array_elements(global_value -> 'measurements') m;
    if personal_semantic is distinct from global_semantic
       or personal_candidates -> 'authorized_candidate_product_size_ids'
          is distinct from
          global_candidates -> 'authorized_candidate_product_size_ids'
       or personal_candidates ->> 'decision' is distinct from
          global_candidates ->> 'decision'
       or personal_candidates -> 'candidates' -> 0 -> 'comparison_measurements'
          is distinct from
          global_candidates -> 'candidates' -> 0 -> 'comparison_measurements'
       or personal_candidates -> 'candidates' -> 0 -> 'authorization'
          ->> 'policy_code' is distinct from
          global_candidates -> 'candidates' -> 0 -> 'authorization'
          ->> 'policy_code'
       or personal_candidates -> 'candidates' -> 0 -> 'authorization'
          -> 'excluded_measurement_codes' is distinct from
          global_candidates -> 'candidates' -> 0 -> 'authorization'
          -> 'excluded_measurement_codes' then
        raise exception 'Effective-context comparison input mismatch';
    end if;

    update fitmatch_vnext.products
    set classification_status = 'REVIEW_REQUIRED',
        garment_type_code = null,
        sleeve_length_code = null
    where id = 'c0000000-0000-0000-0000-000000000002';
end
$measurement_equivalence$;

do $comparison_contract$
declare
    value jsonb;
    request_value jsonb;
    replay_value jsonb;
    candidate_ids jsonb;
    authority_fingerprint text;
    effective_fingerprint text;
    override_revision integer;
    comparison_id uuid;
begin
    value := fitmatch_vnext.find_reference_candidates(
        'c0000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000001'
    );
    if value ->> 'status' <> 'READY'
       or not exists (
           select 1 from jsonb_array_elements(value -> 'candidates') c
           where c ->> 'closet_item_id' =
                 'f0000000-0000-0000-0000-000000000001'
             and c ->> 'decision' = 'AUTOMATIC'
             and not (c ->> 'manual_explicit_required')::boolean
       )
       or not exists (
           select 1 from jsonb_array_elements(value -> 'candidates') c
           where c ->> 'closet_item_id' =
                 'f0000000-0000-0000-0000-000000000002'
             and c ->> 'decision' = 'MANUAL_EXTENDED'
             and (c ->> 'manual_explicit_required')::boolean
       )
       or not exists (
           select 1 from jsonb_array_elements(value -> 'blocked') c
           where c ->> 'closet_item_id' =
                 'f0000000-0000-0000-0000-000000000003'
             and c ->> 'decision' = 'BLOCKED'
       ) then
        raise exception 'Reference discovery recovery contract regression: %', value;
    end if;

    value := fitmatch_vnext.authorize_comparison(
        'f0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000002',
        'e0000000-0000-0000-0000-000000000001', false
    );
    if value ->> 'decision' <> 'AUTOMATIC' then
        raise exception 'USER_EXPLICIT polo + short polo is not AUTOMATIC: %', value;
    end if;
    value := fitmatch_vnext.authorize_comparison(
        'f0000000-0000-0000-0000-000000000002',
        'c0000000-0000-0000-0000-000000000002',
        'e0000000-0000-0000-0000-000000000001', false
    );
    if value ->> 'decision' <> 'BLOCKED' then
        raise exception 'Automatic manual-cross leakage';
    end if;
    value := fitmatch_vnext.authorize_comparison(
        'f0000000-0000-0000-0000-000000000002',
        'c0000000-0000-0000-0000-000000000002',
        'e0000000-0000-0000-0000-000000000001', true
    );
    if value ->> 'decision' <> 'MANUAL_EXTENDED'
       or value -> 'manual_cross_rule' ->> 'require_same_sleeve' <> 'true' then
        raise exception 'Explicit same-sleeve manual cross regression: %', value;
    end if;
    value := fitmatch_vnext.authorize_comparison(
        'f0000000-0000-0000-0000-000000000003',
        'c0000000-0000-0000-0000-000000000002',
        'e0000000-0000-0000-0000-000000000001', true
    );
    if value ->> 'decision' <> 'BLOCKED' then
        raise exception 'Same-sleeve manual-cross guard regression';
    end if;

    value := fitmatch_vnext.eligible_candidate_sizes(
        'f0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000001', false
    );
    if not (value ->> 'allowed')::boolean
       or value -> 'authorized_candidate_product_size_ids' <>
          '["e0000000-0000-0000-0000-000000000001"]'::jsonb then
        raise exception 'Eligible size authority regression: %', value;
    end if;
    candidate_ids := value -> 'authorized_candidate_product_size_ids';
    authority_fingerprint := value ->> 'candidate_authority_fingerprint';
    effective_fingerprint := value ->> 'effective_authority_fingerprint';
    override_revision := (value ->> 'override_revision')::integer;

    update fitmatch_vnext.size_availability_observations
    set valid_until = now() - interval '1 minute'
    where product_size_id = 'e0000000-0000-0000-0000-000000000001';
    value := fitmatch_vnext.eligible_candidate_sizes(
        'f0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000001', false
    );
    if coalesce((value ->> 'allowed')::boolean, false)
       or jsonb_array_length(value ->
          'authorized_candidate_product_size_ids') <> 0 then
        raise exception 'Expired availability became an eligible candidate';
    end if;
    update fitmatch_vnext.size_availability_observations
    set valid_until = now() + interval '1 day'
    where product_size_id = 'e0000000-0000-0000-0000-000000000001';

    update fitmatch_vnext.product_size_measurements
    set is_current = false
    where product_size_id = 'e0000000-0000-0000-0000-000000000001';
    value := fitmatch_vnext.authorize_comparison(
        'f0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000002',
        'e0000000-0000-0000-0000-000000000001', false
    );
    if value ->> 'decision' <> 'MEASUREMENTS_REQUIRED'
       or coalesce((value ->> 'allowed')::boolean, false) then
        raise exception 'Insufficient measurements did not fail closed: %', value;
    end if;
    update fitmatch_vnext.product_size_measurements
    set is_current = true
    where product_size_id = 'e0000000-0000-0000-0000-000000000001';

    begin
        perform fitmatch_vnext.begin_comparison(jsonb_build_object(
            'client_comparison_id','91000000-0000-0000-0000-000000000001',
            'reference_closet_item_id','f0000000-0000-0000-0000-000000000001',
            'target_product_id','c0000000-0000-0000-0000-000000000002',
            'target_variant_id','d0000000-0000-0000-0000-000000000001',
            'authorization_product_size_id',
                'e0000000-0000-0000-0000-000000000001',
            'candidate_product_size_ids','[]'::jsonb,
            'effective_authority_fingerprint',effective_fingerprint,
            'personal_override_revision',override_revision
        ));
        raise exception 'Candidate subset was accepted';
    exception when others then
        if sqlerrm = 'Candidate subset was accepted' then raise; end if;
    end;

    begin
        perform fitmatch_vnext.begin_comparison(jsonb_build_object(
            'client_comparison_id','91000000-0000-0000-0000-000000000004',
            'reference_closet_item_id','f0000000-0000-0000-0000-000000000001',
            'target_product_id','c0000000-0000-0000-0000-000000000002',
            'target_variant_id','d0000000-0000-0000-0000-000000000001',
            'candidate_product_size_ids',candidate_ids || jsonb_build_array(
                'e0000000-0000-0000-0000-000000000099'
            ),
            'effective_authority_fingerprint',effective_fingerprint,
            'personal_override_revision',override_revision
        ));
        raise exception 'Candidate superset was accepted';
    exception when others then
        if sqlerrm = 'Candidate superset was accepted' then raise; end if;
    end;

    begin
        perform fitmatch_vnext.begin_comparison(jsonb_build_object(
            'client_comparison_id','91000000-0000-0000-0000-000000000005',
            'reference_closet_item_id','f0000000-0000-0000-0000-000000000001',
            'target_product_id','c0000000-0000-0000-0000-000000000002',
            'target_variant_id','d0000000-0000-0000-0000-000000000001',
            'candidate_product_size_ids',candidate_ids,
            'effective_authority_fingerprint',effective_fingerprint,
            'personal_override_revision',override_revision,
            'garment_type_code','polo_shirt'
        ));
        raise exception 'Raw classification tuple was accepted at begin';
    exception when others then
        if sqlerrm = 'Raw classification tuple was accepted at begin' then raise; end if;
    end;

    begin
        perform fitmatch_vnext.begin_comparison(jsonb_build_object(
            'client_comparison_id','91000000-0000-0000-0000-000000000002',
            'reference_closet_item_id','f0000000-0000-0000-0000-000000000001',
            'target_product_id','c0000000-0000-0000-0000-000000000002',
            'target_variant_id','d0000000-0000-0000-0000-000000000001',
            'candidate_product_size_ids',candidate_ids || candidate_ids,
            'effective_authority_fingerprint',effective_fingerprint,
            'personal_override_revision',override_revision
        ));
        raise exception 'Duplicate candidate IDs were accepted';
    exception when others then
        if sqlerrm = 'Duplicate candidate IDs were accepted' then raise; end if;
    end;

    request_value := jsonb_build_object(
        'client_comparison_id','91000000-0000-0000-0000-000000000003',
        'reference_closet_item_id','f0000000-0000-0000-0000-000000000001',
        'target_product_id','c0000000-0000-0000-0000-000000000002',
        'target_variant_id','d0000000-0000-0000-0000-000000000001',
        'authorization_product_size_id',
            'e0000000-0000-0000-0000-000000000001',
        'candidate_product_size_ids',candidate_ids,
        'effective_authority_fingerprint',effective_fingerprint,
        'personal_override_revision',override_revision,
        'manual_explicit',false
    );
    value := fitmatch_vnext.begin_comparison(request_value);
    comparison_id := (value ->> 'comparison_id')::uuid;
    if (select snapshot_schema_version from fitmatch_vnext.comparisons
        where id = comparison_id) <> 4
       or (select authority_snapshot -> 'personal_projection_at_begin' ->>
           'classification_source' from fitmatch_vnext.comparisons
           where id = comparison_id) <> 'USER_EXPLICIT' then
        raise exception 'Snapshot v4 personal provenance regression';
    end if;

    replay_value := fitmatch_vnext.begin_comparison(request_value);
    if replay_value ->> 'comparison_id' <> comparison_id::text
       or coalesce((replay_value ->> 'created')::boolean, true)
       or not coalesce((replay_value ->> 'idempotent')::boolean, false)
       or (select count(*) from fitmatch_vnext.comparisons
           where user_id = '11111111-1111-1111-1111-111111111111'
             and client_comparison_id =
                 '91000000-0000-0000-0000-000000000003'::uuid) <> 1 then
        raise exception 'Same client comparison begin replay was not idempotent: %',
            replay_value;
    end if;

    begin
        perform fitmatch_vnext.begin_comparison(
            request_value || jsonb_build_object('manual_explicit', true)
        );
        raise exception 'Changed request payload was accepted for an existing client comparison ID';
    exception when others then
        if sqlerrm = 'Changed request payload was accepted for an existing client comparison ID' then
            raise;
        end if;
    end;
end
$comparison_contract$;

do $clear_and_precedence$
declare
    value jsonb;
    options_value jsonb;
    candidate_value jsonb;
    feedback_count_before integer;
    feedback_count_after_clear integer;
begin
    select count(*) into feedback_count_before
    from fitmatch_vnext.user_classification_feedback_evidence
    where user_id = '11111111-1111-1111-1111-111111111111';

    options_value := fitmatch_vnext.classification_recovery_options(
        'c0000000-0000-0000-0000-000000000002'
    );
    select c into candidate_value
    from jsonb_array_elements(options_value -> 'candidates') c
    where c ->> 'garment_type_code' = 'tshirt';
    value := fitmatch_vnext.set_user_product_classification(
        'c0000000-0000-0000-0000-000000000002',
        candidate_value ->> 'candidate_fingerprint',
        options_value ->> 'candidate_set_hash',
        options_value ->> 'product_input_fingerprint',
        options_value ->> 'product_evidence_fingerprint',
        '92100000-0000-0000-0000-000000000001', 1
    );
    if value ->> 'event' <> 'EDITED'
       or (value -> 'override' ->> 'revision')::integer <> 2
       or value -> 'effective_classification' ->> 'garment_type_code' <>
          'tshirt'
       or value -> 'effective_classification' ->> 'effective_source' <>
          'USER_EXPLICIT'
       or (select classification_status from fitmatch_vnext.products
           where id = 'c0000000-0000-0000-0000-000000000002') <>
          'REVIEW_REQUIRED'
       or (select count(*)
           from fitmatch_vnext.user_classification_feedback_evidence
           where user_id = '11111111-1111-1111-1111-111111111111') <>
          feedback_count_before + 1 then
        raise exception 'USER_EXPLICIT reselection/revision evidence regression';
    end if;

    begin
        perform fitmatch_vnext.set_user_product_classification(
            'c0000000-0000-0000-0000-000000000002',
            candidate_value ->> 'candidate_fingerprint',
            options_value ->> 'candidate_set_hash',
            options_value ->> 'product_input_fingerprint',
            options_value ->> 'product_evidence_fingerprint',
            '92100000-0000-0000-0000-000000000002', 1
        );
        raise exception 'Stale pre-reselection revision was accepted';
    exception when others then
        if sqlerrm = 'Stale pre-reselection revision was accepted' then raise; end if;
    end;

    update fitmatch_vnext.products
    set classification_status='CONFIRMED', garment_type_code='tshirt',
        sleeve_length_code='short_sleeve'
    where id='c0000000-0000-0000-0000-000000000002';
    value := fitmatch_vnext.effective_target_classification(
        'c0000000-0000-0000-0000-000000000002'
    );
    if value ->> 'state' <> 'SUPERSEDED_MATCH'
       or value ->> 'effective_source' <> 'GLOBAL_CONFIRMED' then
        raise exception 'Active matching personal projection precedence regression';
    end if;
    update fitmatch_vnext.products set garment_type_code='polo_shirt'
    where id='c0000000-0000-0000-0000-000000000002';
    if fitmatch_vnext.effective_target_classification(
        'c0000000-0000-0000-0000-000000000002'
    ) ->> 'state' <> 'SUPERSEDED_CONFLICT' then
        raise exception 'Active conflicting personal projection precedence regression';
    end if;
    update fitmatch_vnext.products
    set classification_status='REVIEW_REQUIRED', garment_type_code=null,
        sleeve_length_code=null
    where id='c0000000-0000-0000-0000-000000000002';

    value := fitmatch_vnext.clear_user_product_classification(
        'c0000000-0000-0000-0000-000000000002',
        '92000000-0000-0000-0000-000000000001', 2
    );
    if value -> 'effective_classification' ->> 'state' <> 'REVIEW_REQUIRED'
       or (select count(*) from fitmatch_vnext.comparisons
           where snapshot_schema_version = 4) <> 1 then
        raise exception 'Clear/history immutability regression';
    end if;
    select count(*) into feedback_count_after_clear
    from fitmatch_vnext.user_classification_feedback_evidence
    where user_id = '11111111-1111-1111-1111-111111111111';
    if feedback_count_after_clear <> feedback_count_before + 2
       or not exists (
           select 1
           from fitmatch_vnext.user_classification_feedback_evidence e
           where e.user_id = '11111111-1111-1111-1111-111111111111'
             and e.event_code = 'CLEARED'
             and e.override_revision = 3
       ) then
        raise exception 'Clear did not preserve append-only feedback evidence';
    end if;

    begin
        perform fitmatch_vnext.begin_comparison(jsonb_build_object(
            'client_comparison_id','91000000-0000-0000-0000-000000000006',
            'reference_closet_item_id','f0000000-0000-0000-0000-000000000001',
            'target_product_id','c0000000-0000-0000-0000-000000000002',
            'target_variant_id','d0000000-0000-0000-0000-000000000001',
            'candidate_product_size_ids',jsonb_build_array(
                'e0000000-0000-0000-0000-000000000001'
            ),
            'effective_authority_fingerprint','stale-personal-authority',
            'personal_override_revision',1
        ));
        raise exception 'Cleared personal authority was accepted at begin';
    exception when others then
        if sqlerrm = 'Cleared personal authority was accepted at begin' then raise; end if;
    end;

    update fitmatch_vnext.products
    set classification_status='CONFIRMED', garment_type_code='tshirt',
        sleeve_length_code='short_sleeve'
    where id='c0000000-0000-0000-0000-000000000002';
    value := fitmatch_vnext.effective_target_classification(
        'c0000000-0000-0000-0000-000000000002'
    );
    if value ->> 'state' <> 'GLOBAL_CONFIRMED'
       or value ->> 'effective_source' <> 'GLOBAL_CONFIRMED'
       or value ? 'personal_projection'
       or (select count(*)
           from fitmatch_vnext.user_classification_feedback_evidence
           where user_id = '11111111-1111-1111-1111-111111111111') <>
          feedback_count_after_clear then
        raise exception 'Cleared personal projection leaked into Global CONFIRMED state';
    end if;
    update fitmatch_vnext.products
    set classification_status='NOT_APPLICABLE', garment_type_code=null,
        sleeve_length_code=null
    where id='c0000000-0000-0000-0000-000000000002';
    value := fitmatch_vnext.effective_target_classification(
        'c0000000-0000-0000-0000-000000000002'
    );
    if value ->> 'state' <> 'GLOBAL_NOT_APPLICABLE'
       or value ->> 'classification_status' <> 'NOT_APPLICABLE' then
        raise exception 'Global NOT_APPLICABLE precedence regression';
    end if;
end
$clear_and_precedence$;

do $append_only$
begin
    begin
        update fitmatch_vnext.user_classification_feedback_evidence
        set event_code = 'EDITED';
        raise exception 'Feedback evidence UPDATE was accepted';
    exception when others then
        if sqlerrm = 'Feedback evidence UPDATE was accepted' then raise; end if;
    end;
    if has_table_privilege('authenticated',
        'fitmatch_vnext.user_product_classification_overrides','INSERT')
       or has_table_privilege('authenticated',
        'fitmatch_vnext.user_classification_feedback_evidence','INSERT')
       or has_function_privilege('anon',
        'public.fitmatch_vnext_set_user_product_classification(uuid,text,text,text,text,uuid,integer)',
        'EXECUTE')
       or not has_function_privilege('authenticated',
        'public.fitmatch_vnext_set_user_product_classification(uuid,text,text,text,text,uuid,integer)',
        'EXECUTE') then
        raise exception 'Recovery grant boundary regression';
    end if;
end
$append_only$;

select 'RECOVERY_VALIDATION_PASS' result;
rollback;

select case
    when (select count(*) from fitmatch_vnext.user_product_classification_overrides) = 0
     and (select count(*) from fitmatch_vnext.user_classification_feedback_evidence) = 0
     and (select count(*) from fitmatch_vnext.comparisons) = 0
    then 'ROLLBACK_PASS' else 'ROLLBACK_FAIL' end result;
