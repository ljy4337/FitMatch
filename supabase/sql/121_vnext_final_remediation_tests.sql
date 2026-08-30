-- FitMatch vNext final-remediation transactional regression suite.
-- Target: hnkplvyegonlhumlejst / fitmatch_vnext
-- Every fixture is rolled back. Any failed assertion aborts the script.

begin;
set local statement_timeout = '120s';

do $tests$
declare
    user_value uuid;
    other_user_value uuid;
    product_value uuid;
    variant_value uuid;
    size_value uuid;
    closet_value uuid;
    second_closet_value uuid;
    comparison_value uuid;
    client_item_value uuid;
    request_value jsonb;
    response_value jsonb;
    retry_value jsonb;
    candidates_value jsonb;
    discovery_value jsonb;
    comparison_row fitmatch_vnext.comparisons%rowtype;
    ranking_value jsonb;
    evidence_value jsonb;
    completion_value jsonb;
    recommended_value uuid;
    coverage_value numeric;
    policy_metric_count integer;
    recommended_metric_count integer;
    fixture record;
    fixture_key text;
    fixture_payload jsonb;
    ingestion_one jsonb;
    ingestion_two jsonb;
    legacy_observation_count bigint;
    no_observation_size uuid;
    sold_out_size uuid;
    expired_size uuid;
    blocked boolean;
    golden_pass_count integer := 0;
begin
    select id into user_value from auth.users order by created_at, id limit 1;
    select id into other_user_value
    from auth.users where id <> user_value order by created_at, id limit 1;
    if user_value is null then
        raise exception 'No auth fixture user is available';
    end if;

    -- New-product ingestion: direct vNext identity, raw evidence, signal,
    -- availability, classification, readiness, runtime, and idempotency.
    perform set_config('request.jwt.claims', jsonb_build_object(
        'sub', user_value, 'role', 'service_role'
    )::text, true);
    fixture_key := 'vnext-final-regression-' || replace(gen_random_uuid()::text, '-', '');
    select count(*) into legacy_observation_count
    from fitmatch_catalog.product_observations;
    fixture_payload := jsonb_build_object(
        'source', 'musinsa',
        'external_product_id', fixture_key,
        'product_name', 'vNext isolated ingestion regression fixture',
        'audience', 'WOMEN',
        'product_structure', 'SINGLE',
        'observed_at', now(),
        'source_category_codes', jsonb_build_array('001001'),
        'source_category_path', 'fixture > tshirt',
        'structured_facts', jsonb_build_object(
            'product_structure', 'SINGLE',
            'measurement_parser_code', 'actual_size'
        ),
        'variants', jsonb_build_array(jsonb_build_object(
            'external_variant_id', '__fixture__',
            'variant_name', 'fixture',
            'sizes', jsonb_build_array(jsonb_build_object(
                'size_identity', 'XS',
                'size_label', 'XS',
                'availability_status', 'AVAILABLE',
                'valid_until', now() + interval '1 hour',
                'measurements', jsonb_build_array(
                    jsonb_build_object('measurement_identity', 'chest',
                        'parser_code', 'actual_size', 'raw_label', '가슴단면',
                        'raw_value', 42.5, 'raw_unit', 'cm'),
                    jsonb_build_object('measurement_identity', 'shoulder',
                        'parser_code', 'actual_size', 'raw_label', '어깨너비',
                        'raw_value', 35, 'raw_unit', 'cm'),
                    jsonb_build_object('measurement_identity', 'length',
                        'parser_code', 'actual_size', 'raw_label', '총장',
                        'raw_value', 45.5, 'raw_unit', 'cm'),
                    jsonb_build_object('measurement_identity', 'sleeve',
                        'parser_code', 'actual_size', 'raw_label', '소매길이',
                        'raw_value', 16.5, 'raw_unit', 'cm')
                )
            ))
        ))
    );
    ingestion_one := fitmatch_vnext.ingest_product_observation(
        fixture_payload, user_value
    );
    ingestion_two := fitmatch_vnext.ingest_product_observation(
        fixture_payload, user_value
    );
    if ingestion_one -> 'classification' ->> 'classification_status' <> 'CONFIRMED'
       or ingestion_one -> 'readiness' ->> 'status' <> 'READY'
       or not coalesce((ingestion_two -> 'observation' ->> 'idempotent')::boolean, false)
       or ingestion_one -> 'processing' ->> 'product_id'
            is distinct from ingestion_two -> 'processing' ->> 'product_id'
       or (select count(*) from fitmatch_catalog.product_observations)
            <> legacy_observation_count then
        raise exception 'New-product vNext ingestion regression';
    end if;
    if (select count(*) from fitmatch_vnext.products
        where source_code = 'musinsa' and source_product_key = fixture_key) <> 1
       or (select count(*) from fitmatch_vnext.product_ingestion_receipts
           where source_code = 'musinsa' and source_product_key = fixture_key) <> 1
       or (select count(*) from fitmatch_vnext.product_ingestion_receipts
           where source_code = 'musinsa' and source_product_key = fixture_key
             and submission_count = 2) <> 1 then
        raise exception 'Ingestion identity or receipt idempotency regression';
    end if;

    -- Explicit exact/structure signals cannot contradict their product facts.
    select * into fixture
    from fitmatch_vnext.products order by id limit 1;
    blocked := false;
    begin
        insert into fitmatch_vnext.product_ingestion_receipts (
            product_id, source_code, source_product_key, payload_fingerprint,
            retailer_facts, observed_at, processing_status
        ) values (
            fixture.id, fixture.source_code, fixture.source_product_key,
            gen_random_uuid()::text,
            jsonb_build_object('source', fixture.source_code,
                'external_product_id', fixture.source_product_key,
                'product_structure', 'SINGLE',
                'classification_signals', jsonb_build_array(jsonb_build_object(
                    'kind', 'PRODUCT_EXACT',
                    'external_key', fixture.source_product_key || '-spoof'))),
            now(), 'PROCESSING'
        );
    exception when others then
        blocked := sqlerrm like 'PRODUCT_EXACT signal must match%';
    end;
    if not blocked then raise exception 'Spoofed PRODUCT_EXACT was accepted'; end if;

    blocked := false;
    begin
        insert into fitmatch_vnext.product_ingestion_receipts (
            product_id, source_code, source_product_key, payload_fingerprint,
            retailer_facts, observed_at, processing_status
        ) values (
            fixture.id, fixture.source_code, fixture.source_product_key,
            gen_random_uuid()::text,
            jsonb_build_object('source', fixture.source_code,
                'external_product_id', fixture.source_product_key,
                'product_structure', 'SINGLE',
                'classification_signals', jsonb_build_array(jsonb_build_object(
                    'kind', 'PRODUCT_STRUCTURE', 'external_key', 'SET'))),
            now(), 'PROCESSING'
        );
    exception when others then
        blocked := sqlerrm like 'PRODUCT_STRUCTURE signal must match%';
    end;
    if not blocked then raise exception 'Spoofed PRODUCT_STRUCTURE was accepted'; end if;

    -- Run the complete domain path for each provider Golden fixture.
    perform set_config('request.jwt.claims', jsonb_build_object(
        'sub', user_value, 'role', 'authenticated'
    )::text, true);
    for fixture in
        select * from (values
            ('musinsa'::text, '6805433'::text, 'XS'::text),
            ('uniqlo'::text, 'E482856'::text, '28'::text),
            ('zara'::text, '561264931'::text, 'EU 38 (KR 30)'::text)
        ) golden(source_code, source_product_key, preferred_size_label)
    loop
        select p.id, pv.id, ps.id
        into product_value, variant_value, size_value
        from fitmatch_vnext.products p
        join fitmatch_vnext.product_variants pv on pv.product_id = p.id
        join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
        join lateral (
            select o.* from fitmatch_vnext.size_availability_observations o
            where o.product_size_id = ps.id
            order by o.observed_at desc, o.id desc limit 1
        ) availability on true
        where p.source_code = fixture.source_code
          and p.source_product_key = fixture.source_product_key
          and ps.size_label = fixture.preferred_size_label
          and availability.availability_status = 'AVAILABLE'
          and availability.valid_until is not null
          and availability.valid_until >= now()
        order by pv.sort_order, ps.sort_order, ps.id
        limit 1;
        if product_value is null
           or fitmatch_vnext.product_readiness(product_value) ->> 'status' <> 'READY' then
            raise exception 'Golden fixture is not READY: %/%',
                fixture.source_code, fixture.source_product_key;
        end if;

        client_item_value := gen_random_uuid();
        request_value := jsonb_build_object(
            'client_item_id', client_item_value,
            'product_id', product_value,
            'product_variant_id', variant_value,
            'product_size_id', size_value,
            'is_reference', true
        );
        response_value := fitmatch_vnext.upsert_closet_item(request_value);
        retry_value := fitmatch_vnext.upsert_closet_item(request_value);
        closet_value := (response_value ->> 'item_id')::uuid;
        if not coalesce((response_value ->> 'created')::boolean, false)
           or not coalesce((retry_value ->> 'idempotent')::boolean, false) then
            raise exception 'Closet idempotency regression';
        end if;
        perform fitmatch_vnext.set_closet_reference(closet_value);

        discovery_value := fitmatch_vnext.find_reference_candidates(
            product_value, variant_value
        );
        if not exists (
            select 1 from jsonb_array_elements(discovery_value -> 'candidates') c
            where (c ->> 'closet_item_id')::uuid = closet_value
              and c ->> 'decision' = 'AUTOMATIC'
        ) then
            raise exception 'Reference discovery regression for %', fixture.source_code;
        end if;

        candidates_value := fitmatch_vnext.eligible_candidate_sizes(
            closet_value, product_value, variant_value, false
        );
        if candidates_value ->> 'decision' <> 'AUTOMATIC'
           or not coalesce((candidates_value ->> 'allowed')::boolean, false)
           or not exists (
               select 1 from jsonb_array_elements_text(
                   candidates_value -> 'authorized_candidate_product_size_ids'
               ) id where id::uuid = size_value
           ) then
            raise exception 'DB candidate authority regression for %', fixture.source_code;
        end if;

        -- UNKNOWN/no observation, SOLD_OUT, and expired AVAILABLE are never candidates.
        insert into fitmatch_vnext.product_sizes (
            variant_id, source_size_key, size_label, availability_status, sort_order
        ) values (
            variant_value, '__no_obs__' || gen_random_uuid(), 'NO_OBS', 'UNKNOWN', 9001
        ) returning id into no_observation_size;
        insert into fitmatch_vnext.product_sizes (
            variant_id, source_size_key, size_label, availability_status, sort_order
        ) values (
            variant_value, '__sold_out__' || gen_random_uuid(), 'SOLD_OUT', 'UNKNOWN', 9002
        ) returning id into sold_out_size;
        insert into fitmatch_vnext.product_sizes (
            variant_id, source_size_key, size_label, availability_status, sort_order
        ) values (
            variant_value, '__expired__' || gen_random_uuid(), 'EXPIRED', 'UNKNOWN', 9003
        ) returning id into expired_size;
        perform fitmatch_vnext.record_size_availability(sold_out_size, 'SOLD_OUT',
            'REGRESSION_FIXTURE', '{}'::jsonb, now(), now() + interval '1 hour');
        perform fitmatch_vnext.record_size_availability(expired_size, 'AVAILABLE',
            'REGRESSION_FIXTURE', '{}'::jsonb,
            now() - interval '2 hours', now() - interval '1 hour');
        candidates_value := fitmatch_vnext.eligible_candidate_sizes(
            closet_value, product_value, variant_value, false
        );
        if exists (
            select 1 from jsonb_array_elements_text(
                candidates_value -> 'authorized_candidate_product_size_ids'
            ) id where id::uuid in (no_observation_size, sold_out_size, expired_size)
        ) then
            raise exception 'Unavailable or expired size entered candidate authority';
        end if;

        request_value := jsonb_build_object(
            'client_comparison_id', gen_random_uuid(),
            'reference_closet_item_id', closet_value,
            'target_product_id', product_value,
            'target_variant_id', variant_value,
            'manual_explicit', false
        );
        response_value := fitmatch_vnext.begin_comparison(request_value);
        retry_value := fitmatch_vnext.begin_comparison(request_value);
        comparison_value := (response_value ->> 'comparison_id')::uuid;
        if not coalesce((response_value ->> 'created')::boolean, false)
           or not coalesce((retry_value ->> 'idempotent')::boolean, false) then
            raise exception 'Comparison begin idempotency regression';
        end if;
        select * into comparison_row
        from fitmatch_vnext.comparisons where id = comparison_value;
        if comparison_row.snapshot_schema_version <> 3
           or comparison_row.reference_snapshot ->> 'source_code' is null
           or comparison_row.reference_snapshot ->> 'source_product_key' is null
           or comparison_row.authority_snapshot ->> 'mapping_authority_checksum' is null
           or comparison_row.authority_snapshot ->> 'taxonomy_checksum' is null
           or jsonb_array_length(comparison_row.policy_snapshot -> 'metrics') = 0
           or exists (
               select 1 from jsonb_array_elements(
                   comparison_row.target_snapshot -> 'candidates'
               ) c where c -> 'availability' ->> 'evidence_fingerprint' is null
           ) then
            raise exception 'Comparison begin provenance regression';
        end if;

        select (c ->> 'product_size_id')::uuid into recommended_value
        from jsonb_array_elements(comparison_row.target_snapshot -> 'candidates')
             with ordinality candidate(c, ordinal)
        order by ordinal limit 1;
        select jsonb_agg(jsonb_build_object(
            'product_size_id', c ->> 'product_size_id',
            'rank', ordinal, 'score', 90
        ) order by ordinal)
        into ranking_value
        from jsonb_array_elements(comparison_row.target_snapshot -> 'candidates')
             with ordinality candidate(c, ordinal);
        select jsonb_agg(jsonb_build_object(
            'product_size_id', c ->> 'product_size_id',
            'measurement_code', m ->> 'measurement_code',
            'reference_value', (m ->> 'reference_value')::numeric,
            'target_value', (m ->> 'target_value')::numeric,
            'difference', (m ->> 'difference')::numeric,
            'absolute_difference', (m ->> 'absolute_difference')::numeric,
            'weight', (m ->> 'weight')::numeric
        ) order by c ->> 'product_size_id', m ->> 'measurement_code')
        into evidence_value
        from jsonb_array_elements(comparison_row.target_snapshot -> 'candidates') c
        cross join jsonb_array_elements(c -> 'comparison_measurements') m;
        select count(*) into recommended_metric_count
        from jsonb_array_elements(comparison_row.target_snapshot -> 'candidates') c
        cross join jsonb_array_elements(c -> 'comparison_measurements') m
        where (c ->> 'product_size_id')::uuid = recommended_value;
        select count(*) into policy_metric_count
        from jsonb_array_elements(comparison_row.policy_snapshot -> 'metrics') m
        where m ->> 'metric_mode' = 'CANONICAL'
          and coalesce((m ->> 'is_active')::boolean, false)
          and not (m ->> 'fitmatch_measurement_code' =
              any(comparison_row.excluded_measurement_codes));
        coverage_value := round(
            recommended_metric_count::numeric / policy_metric_count::numeric, 5
        );
        completion_value := jsonb_build_object(
            'recommended_product_size_id', recommended_value,
            'score', 90,
            'reliability', 3,
            'coverage', coverage_value,
            'engine_version', 'vnext-final-regression-v1',
            'candidate_size_ranking', ranking_value,
            'metric_evidence', evidence_value
        );
        if fixture.source_code = 'musinsa' then
            blocked := false;
            begin
                perform fitmatch_vnext.complete_comparison(comparison_value,
                    jsonb_set(completion_value, '{metric_evidence}', '[{}]'::jsonb));
            exception when others then
                blocked := sqlerrm like 'Metric evidence is missing required semantic fields%';
            end;
            if not blocked then raise exception 'Meaningless metric evidence was accepted'; end if;

            blocked := false;
            begin
                perform fitmatch_vnext.complete_comparison(comparison_value,
                    jsonb_set(completion_value, '{metric_evidence}',
                        evidence_value || jsonb_build_array(evidence_value -> 0)));
            exception when others then
                blocked := sqlerrm like 'Duplicate size and metric evidence%';
            end;
            if not blocked then raise exception 'Duplicate metric evidence was accepted'; end if;

            blocked := false;
            begin
                perform fitmatch_vnext.complete_comparison(comparison_value,
                    jsonb_set(completion_value, '{metric_evidence,0,weight}',
                        to_jsonb((evidence_value -> 0 ->> 'weight')::numeric + 1)));
            exception when others then
                blocked := sqlerrm like 'Metric evidence does not match%';
            end;
            if not blocked then raise exception 'Wrong policy weight was accepted'; end if;

            blocked := false;
            begin
                perform fitmatch_vnext.complete_comparison(comparison_value,
                    jsonb_set(completion_value, '{metric_evidence,0,target_value}',
                        to_jsonb((evidence_value -> 0 ->> 'target_value')::numeric + 1)));
            exception when others then
                blocked := sqlerrm like 'Metric evidence does not match%';
            end;
            if not blocked then raise exception 'Snapshot value mismatch was accepted'; end if;

            blocked := false;
            begin
                perform fitmatch_vnext.complete_comparison(comparison_value,
                    jsonb_set(completion_value, '{recommended_product_size_id}',
                        to_jsonb(no_observation_size)));
            exception when others then
                blocked := sqlerrm like 'Recommended size must be rank one%';
            end;
            if not blocked then raise exception 'Unauthorized recommendation was accepted'; end if;

            blocked := false;
            begin
                perform fitmatch_vnext.complete_comparison(comparison_value,
                    jsonb_set(completion_value, '{candidate_size_ranking}',
                        ranking_value || jsonb_build_array(ranking_value -> 0)));
            exception when others then
                blocked := sqlerrm like 'Ranking set must exactly cover%';
            end;
            if not blocked then raise exception 'Duplicate ranking set was accepted'; end if;
        end if;
        response_value := fitmatch_vnext.complete_comparison(
            comparison_value, completion_value
        );
        retry_value := fitmatch_vnext.complete_comparison(
            comparison_value, completion_value
        );
        if not coalesce((response_value ->> 'completed')::boolean, false)
           or not coalesce((retry_value ->> 'idempotent')::boolean, false) then
            raise exception 'Comparison completion/idempotency regression';
        end if;
        blocked := false;
        begin
            perform fitmatch_vnext.complete_comparison(comparison_value,
                jsonb_set(completion_value, '{engine_version}',
                    to_jsonb('conflicting-engine-v2'::text)));
        exception when others then
            blocked := sqlerrm like 'Completion idempotency conflict%';
        end;
        if not blocked then raise exception 'Conflicting completion retry was accepted'; end if;
        blocked := false;
        begin
            update fitmatch_vnext.comparisons
            set fit_score = fit_score + 1 where id = comparison_value;
        exception when others then
            blocked := sqlerrm like 'Completed comparison core history is immutable%';
        end;
        if not blocked then raise exception 'Completed history mutation was accepted'; end if;
        golden_pass_count := golden_pass_count + 1;
    end loop;
    if golden_pass_count <> 3 then
        raise exception 'Expected three Golden flows, got %', golden_pass_count;
    end if;

    -- Long/short mismatch is blocked automatically, but an explicit manual
    -- selection can use the policy-defined extended mode and exclusions.
    select p.id, pv.id, ps.id
    into product_value, variant_value, size_value
    from fitmatch_vnext.products p
    join fitmatch_vnext.product_variants pv on pv.product_id = p.id
    join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
    where p.source_code = 'zara' and p.source_product_key = '561264931'
      and ps.size_label = 'EU 38 (KR 30)'
    order by pv.sort_order, ps.sort_order, ps.id limit 1;
    response_value := fitmatch_vnext.upsert_closet_item(jsonb_build_object(
        'client_item_id', gen_random_uuid(),
        'item_name', 'manual short pants regression reference',
        'size_label', 'MANUAL',
        'audience_code', 'MEN',
        'garment_type_code', 'chino_cotton_pants',
        'lower_length_code', 'short_length',
        'measurements', jsonb_build_array(
            jsonb_build_object('fitmatch_measurement_code', 'waist_width',
                'value', 40, 'unit_code', 'cm'),
            jsonb_build_object('fitmatch_measurement_code', 'hip_width',
                'value', 49.5, 'unit_code', 'cm')
        )
    ));
    closet_value := (response_value ->> 'item_id')::uuid;
    perform fitmatch_vnext.set_closet_reference(closet_value);
    response_value := fitmatch_vnext.authorize_comparison(
        closet_value, product_value, size_value, false
    );
    if response_value ->> 'decision' <> 'BLOCKED'
       or coalesce((response_value ->> 'allowed')::boolean, false) then
        raise exception 'Automatic length mismatch was not blocked';
    end if;
    response_value := fitmatch_vnext.authorize_comparison(
        closet_value, product_value, size_value, true
    );
    if response_value ->> 'decision' <> 'MANUAL_EXTENDED'
       or not coalesce((response_value ->> 'allowed')::boolean, false)
       or not (response_value -> 'excluded_measurement_codes' ? 'total_length')
       or not (response_value -> 'excluded_measurement_codes' ? 'hem_width') then
        raise exception 'Manual extended authorization/exclusions regression';
    end if;
    discovery_value := fitmatch_vnext.find_reference_candidates(
        product_value, variant_value
    );
    if not exists (
        select 1 from jsonb_array_elements(discovery_value -> 'candidates') c
        where (c ->> 'closet_item_id')::uuid = closet_value
          and c ->> 'decision' = 'MANUAL_EXTENDED'
          and coalesce((c ->> 'manual_explicit_required')::boolean, false)
    ) then
        raise exception 'Manual reference candidate discovery regression';
    end if;

    request_value := jsonb_build_object(
        'client_comparison_id', gen_random_uuid(),
        'reference_closet_item_id', closet_value,
        'target_product_id', product_value,
        'target_variant_id', variant_value,
        'manual_explicit', false
    );
    blocked := false;
    begin
        perform fitmatch_vnext.begin_comparison(request_value);
    exception when others then
        blocked := sqlerrm like 'Comparison has no eligible candidate sizes%';
    end;
    if not blocked then raise exception 'Manual mismatch began without explicit selection'; end if;

    request_value := jsonb_set(request_value, '{client_comparison_id}',
        to_jsonb(gen_random_uuid()));
    request_value := jsonb_set(request_value, '{manual_explicit}', 'true'::jsonb);
    response_value := fitmatch_vnext.begin_comparison(request_value);
    comparison_value := (response_value ->> 'comparison_id')::uuid;
    select * into comparison_row
    from fitmatch_vnext.comparisons where id = comparison_value;
    select (c ->> 'product_size_id')::uuid into recommended_value
    from jsonb_array_elements(comparison_row.target_snapshot -> 'candidates')
         with ordinality candidate(c, ordinal)
    order by ordinal limit 1;
    select jsonb_agg(jsonb_build_object(
        'product_size_id', c ->> 'product_size_id',
        'rank', ordinal, 'score', 90
    ) order by ordinal) into ranking_value
    from jsonb_array_elements(comparison_row.target_snapshot -> 'candidates')
         with ordinality candidate(c, ordinal);
    select jsonb_agg(jsonb_build_object(
        'product_size_id', c ->> 'product_size_id',
        'measurement_code', m ->> 'measurement_code',
        'reference_value', (m ->> 'reference_value')::numeric,
        'target_value', (m ->> 'target_value')::numeric,
        'difference', (m ->> 'difference')::numeric,
        'absolute_difference', (m ->> 'absolute_difference')::numeric,
        'weight', (m ->> 'weight')::numeric
    )) into evidence_value
    from jsonb_array_elements(comparison_row.target_snapshot -> 'candidates') c
    cross join jsonb_array_elements(c -> 'comparison_measurements') m;
    select count(*) into recommended_metric_count
    from jsonb_array_elements(comparison_row.target_snapshot -> 'candidates') c
    cross join jsonb_array_elements(c -> 'comparison_measurements') m
    where (c ->> 'product_size_id')::uuid = recommended_value;
    select count(*) into policy_metric_count
    from jsonb_array_elements(comparison_row.policy_snapshot -> 'metrics') m
    where m ->> 'metric_mode' = 'CANONICAL'
      and coalesce((m ->> 'is_active')::boolean, false)
      and not (m ->> 'fitmatch_measurement_code' =
          any(comparison_row.excluded_measurement_codes));
    coverage_value := round(
        recommended_metric_count::numeric / policy_metric_count::numeric, 5
    );
    completion_value := jsonb_build_object(
        'recommended_product_size_id', recommended_value,
        'score', 90, 'reliability', 3, 'coverage', coverage_value,
        'engine_version', 'manual-extended-regression-v1',
        'candidate_size_ranking', ranking_value,
        'metric_evidence', evidence_value || jsonb_build_array(jsonb_build_object(
            'product_size_id', recommended_value,
            'measurement_code', 'total_length',
            'reference_value', 1, 'target_value', 1,
            'difference', 0, 'absolute_difference', 0, 'weight', 1
        ))
    );
    blocked := false;
    begin
        perform fitmatch_vnext.complete_comparison(comparison_value, completion_value);
    exception when others then
        blocked := sqlerrm like 'Excluded measurement evidence is forbidden%';
    end;
    if not blocked then raise exception 'Excluded manual metric evidence was accepted'; end if;

    -- Completion hardening catches fractional values before PostgreSQL can round.
    select p.id, pv.id, ps.id into product_value, variant_value, size_value
    from fitmatch_vnext.products p
    join fitmatch_vnext.product_variants pv on pv.product_id = p.id
    join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
    order by p.id, pv.id, ps.id limit 1;
    completion_value := jsonb_build_object(
        'recommended_product_size_id', size_value, 'score', 90,
        'reliability', 2, 'coverage', 0.5,
        'engine_version', 'integer-boundary-v1',
        'candidate_size_ranking', jsonb_build_array(jsonb_build_object(
            'product_size_id', size_value, 'rank', 1, 'score', 90)),
        'metric_evidence', jsonb_build_array(jsonb_build_object(
            'product_size_id', size_value, 'measurement_code', 'fixture',
            'reference_value', 1, 'target_value', 1, 'difference', 0,
            'absolute_difference', 0, 'weight', 1))
    );
    blocked := false;
    begin
        insert into fitmatch_vnext.comparisons (
            user_id, client_comparison_id, target_product_id, target_variant_id,
            comparison_mode, reference_item_name_snapshot,
            target_product_name_snapshot, reference_garment_type_snapshot,
            target_garment_type_snapshot, reference_audience_snapshot,
            target_audience_snapshot, recommended_size_label, fit_score,
            reliability_level, coverage_ratio, result_status, engine_version,
            snapshot_schema_version, recommended_product_size_id,
            result_payload_hash, reference_snapshot, target_snapshot,
            authority_snapshot, policy_snapshot, result_evidence, completed_at
        ) values (
            user_value, gen_random_uuid(), product_value, variant_value,
            'CANONICAL', 'fixture', 'fixture', 'fixture', 'fixture',
            'UNISEX', 'UNISEX', 'fixture', 90, 2, 0.5, 'COMPLETED',
            'integer-boundary-v1', 3, size_value, repeat('f', 64),
            '{"fixture":true}', '{"fixture":true}',
            '{"fixture":true}', '{"fixture":true}',
            jsonb_set(completion_value, '{reliability}', '1.5'), now()
        );
    exception when others then
        blocked := sqlerrm like 'Completion reliability must be an integer%';
    end;
    if not blocked then raise exception 'Fractional reliability was accepted'; end if;
    blocked := false;
    begin
        insert into fitmatch_vnext.comparisons (
            user_id, client_comparison_id, target_product_id, target_variant_id,
            comparison_mode, reference_item_name_snapshot,
            target_product_name_snapshot, reference_garment_type_snapshot,
            target_garment_type_snapshot, reference_audience_snapshot,
            target_audience_snapshot, recommended_size_label, fit_score,
            reliability_level, coverage_ratio, result_status, engine_version,
            snapshot_schema_version, recommended_product_size_id,
            result_payload_hash, reference_snapshot, target_snapshot,
            authority_snapshot, policy_snapshot, result_evidence, completed_at
        ) values (
            user_value, gen_random_uuid(), product_value, variant_value,
            'CANONICAL', 'fixture', 'fixture', 'fixture', 'fixture',
            'UNISEX', 'UNISEX', 'fixture', 90, 2, 0.5, 'COMPLETED',
            'integer-boundary-v1', 3, size_value, repeat('g', 64),
            '{"fixture":true}', '{"fixture":true}',
            '{"fixture":true}', '{"fixture":true}',
            jsonb_set(completion_value, '{candidate_size_ranking,0,rank}', '1.5'), now()
        );
    exception when others then
        blocked := sqlerrm like 'Candidate ranks must be positive integers%';
    end;
    if not blocked then raise exception 'Fractional rank was accepted'; end if;

    -- Anonymous and cross-user calls fail closed.
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    blocked := false;
    begin
        perform fitmatch_vnext.begin_comparison('{}'::jsonb);
    exception when others then blocked := sqlerrm like 'Authentication required%'; end;
    if not blocked then raise exception 'Anonymous comparison begin was accepted'; end if;
    if other_user_value is not null then
        perform set_config('request.jwt.claims', jsonb_build_object(
            'sub', other_user_value, 'role', 'authenticated'
        )::text, true);
        blocked := false;
        begin
            perform fitmatch_vnext.eligible_candidate_sizes(
                closet_value, product_value, variant_value, false
            );
        exception when others then
            blocked := sqlerrm like 'Reference is missing or not owned%';
        end;
        if not blocked then raise exception 'Cross-user candidate access was accepted'; end if;
    end if;

    raise notice 'PASS: ingestion, Golden=%, candidate authority, provenance, completion, security',
        golden_pass_count;
end
$tests$;

rollback;

-- Persistent-state pollution guard. The dynamic fixture key is rolled back;
-- these global tables must retain their pre-test state.
select
    count(*) filter (where source_product_key like 'vnext-final-regression-%')
        as fixture_products,
    (select count(*) from fitmatch_vnext.comparisons) as comparison_rows,
    (select count(*) from fitmatch_vnext.product_ingestion_receipts)
        as ingestion_receipt_rows
from fitmatch_vnext.products;
