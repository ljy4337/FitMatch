-- LOCAL/DISPOSABLE POSTGRESQL 17 ONLY.
--
-- Prerequisites, in this order:
--   124_vnext_review_required_recovery_local_fixture.sql
--   126_live_retailer_general_contract_local_fixture.sql
--   20260829012117_vnext_classifier_resolver.sql
--   20260829031514_vnext_ingestion_contract.sql
--   20260829043247_vnext_ingestion_postgrest_bridge.sql
--   20260830090000_vnext_leaf_specificity_correction.sql
--   20260830091000_vnext_review_required_recovery.sql
--   20260902031749_live_retailer_structure_and_adult_audience_policy.sql
--
-- Every row below is synthetic and rolled back. Assertions invoke the actual
-- migration-owned ingestion, classification, and authorization actions; they
-- do not reimplement a classifier, mapping selector, or audience gate.

begin;
select set_config('request.jwt.claim.role', 'service_role', true);

-- Existing verified authorities used by general retailer inputs. No Golden
-- product ID is used here.
insert into fitmatch_vnext.source_classification_signals(
    id, source_code, signal_kind, external_key, audience_code,
    signal_name, signal_path, parent_signal_id
) values
    ('d1000000-0000-0000-0000-000000000001', 'musinsa', 'CATEGORY', '001010', 'MEN',
        '긴소매 티셔츠', '상의 > 긴소매 티셔츠', null),
    ('d2000000-0000-0000-0000-000000000001', 'uniqlo', 'CATEGORY', '95355', 'MEN',
        '니트 & 가디건', '니트 & 가디건', null),
    ('d2000000-0000-0000-0000-000000000002', 'uniqlo', 'CATEGORY', '95357', 'MEN',
        '니트', '니트 & 가디건 > 니트', 'd2000000-0000-0000-0000-000000000001'),
    ('d2000000-0000-0000-0000-000000000003', 'uniqlo', 'CATEGORY', '100315', 'MEN',
        '긴팔', '니트 & 가디건 > 니트 > 긴팔', 'd2000000-0000-0000-0000-000000000002'),
    ('d2000000-0000-0000-0000-000000000004', 'uniqlo', 'CATEGORY', '95405', 'MEN',
        '크루넥 니트', '니트 & 가디건 > 니트 > 크루넥 니트', 'd2000000-0000-0000-0000-000000000002'),
    ('d2000000-0000-0000-0000-000000000005', 'uniqlo', 'CATEGORY', '95406', 'MEN',
        '크루넥 니트 후보', '니트 & 가디건 > 니트 > 크루넥 니트 > 후보', 'd2000000-0000-0000-0000-000000000004'),
    ('d2000000-0000-0000-0000-000000000104', 'uniqlo', 'CATEGORY', '95405', 'UNISEX',
        '크루넥 니트', '니트 & 가디건 > 니트 > 크루넥 니트', null),
    ('d2000000-0000-0000-0000-000000000105', 'uniqlo', 'CATEGORY', '95406', 'UNISEX',
        '크루넥 니트 후보', '니트 & 가디건 > 니트 > 크루넥 니트 > 후보', 'd2000000-0000-0000-0000-000000000104')
on conflict do nothing;

insert into fitmatch_vnext.classification_signal_mappings(
    source_signal_id, audience_code, garment_type_code, resolution_mode,
    sleeve_length_code, priority, is_verified, is_active, mapping_version,
    mapping_checksum
) values
    ('d1000000-0000-0000-0000-000000000001', 'MEN', 'tshirt', 'DIRECT',
        'long_sleeve', 40, true, true, 'fixture-direct-v1', repeat('0', 64)),
    ('d2000000-0000-0000-0000-000000000003', 'MEN', 'knit_sweater', 'DIRECT',
        'long_sleeve', 40, true, true, 'fixture-direct-v1', repeat('0', 64)),
    ('d2000000-0000-0000-0000-000000000004', 'MEN', null, 'PRODUCT_REQUIRED',
        null, 40, true, true, 'fixture-product-required-v1', repeat('0', 64)),
    ('d2000000-0000-0000-0000-000000000005', 'MEN', 'knit_sweater', 'DIRECT',
        'long_sleeve', 40, true, true, 'fixture-recovery-direct-v1', repeat('0', 64)),
    ('d2000000-0000-0000-0000-000000000104', 'UNISEX', null, 'PRODUCT_REQUIRED',
        null, 40, true, true, 'fixture-product-required-v1', repeat('0', 64)),
    ('d2000000-0000-0000-0000-000000000105', 'UNISEX', 'knit_sweater', 'DIRECT',
        'long_sleeve', 40, true, true, 'fixture-recovery-direct-v1', repeat('0', 64));

do $ingestion_contract$
declare
    bridge_result jsonb;
    first_result jsonb;
    missing_result jsonb;
    unknown_result jsonb;
    result_value jsonb;
    recovery_value jsonb;
    first_structure_observed_at timestamptz;
    preserved_structure_observed_at timestamptz;
    product_id_value uuid;
begin
    -- The Edge Function's existing PostgREST transport reaches the new public
    -- ingress wrapper, rather than retaining the renamed v1 function OID.
    bridge_result := public.fitmatch_vnext_ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'bridge-single',
            'product_name', '브리지 단품', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object('product_structure', 'single'),
            'observed_at', '2026-09-02T00:00:30Z', 'variants', jsonb_build_array()
        ), null
    );
    if bridge_result -> 'runtime' -> 'product' ->> 'classification_status' <> 'CONFIRMED'
       or bridge_result -> 'structure_contract' ->> 'state' <> 'EXPLICIT_VALUE' then
        raise exception 'PostgREST transport did not reach the current ingress wrapper: %', bridge_result;
    end if;

    -- A. Explicit SINGLE works through the existing MUSINSA category authority.
    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'general-single',
            'product_name', '일반 긴소매 티셔츠', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(
                'product_structure', 'single',
                'product_structure_source', 'retailer_parser',
                'product_structure_evidence', 'fixture_positive_provider_contract'
            ),
            'observed_at', '2026-09-02T00:00:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'CONFIRMED'
       or result_value -> 'runtime' -> 'product' ->> 'product_structure_code' <> 'SINGLE' then
        raise exception 'Explicit SINGLE did not reach existing server authority: %', result_value;
    end if;

    -- B. Missing retains a real prior SINGLE fact, not a newly invented one.
    first_result := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'preserve-structure',
            'product_name', '기존 단품', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(
                'product_structure', 'single',
                'product_structure_source', 'retailer_parser',
                'product_structure_evidence', 'fixture_first_observation'
            ),
            'observed_at', '2026-09-02T00:01:00Z', 'variants', jsonb_build_array()
        ), null
    );
    product_id_value := (first_result -> 'processing' ->> 'product_id')::uuid;
    select pcs.observed_at into first_structure_observed_at
    from fitmatch_vnext.product_classification_signals pcs
    join fitmatch_vnext.source_classification_signals s on s.id = pcs.source_signal_id
    where pcs.product_id = product_id_value
      and s.signal_kind = 'PRODUCT_STRUCTURE'
      and s.external_key = 'SINGLE';

    missing_result := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'preserve-structure',
            'product_name', '기존 단품', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(),
            'observed_at', '2026-09-02T00:02:00Z', 'variants', jsonb_build_array()
        ), null
    );
    select pcs.observed_at into preserved_structure_observed_at
    from fitmatch_vnext.product_classification_signals pcs
    join fitmatch_vnext.source_classification_signals s on s.id = pcs.source_signal_id
    where pcs.product_id = product_id_value
      and s.signal_kind = 'PRODUCT_STRUCTURE'
      and s.external_key = 'SINGLE';
    if missing_result -> 'runtime' -> 'product' ->> 'product_structure_code' <> 'SINGLE'
       or missing_result -> 'structure_contract' ->> 'state' <> 'MISSING'
       or not coalesce((missing_result -> 'structure_contract' ->>
           'preserved_existing_fact')::boolean, false)
       or preserved_structure_observed_at is distinct from first_structure_observed_at
       or (select r.retailer_facts -> 'structured_facts' ? 'product_structure'
           from fitmatch_vnext.product_ingestion_receipts r
           where r.product_id = product_id_value
           order by r.observed_at desc, r.id desc limit 1) then
        raise exception 'Missing structure preservation fabricated or lost evidence: %', missing_result;
    end if;

    -- C. Explicit UNKNOWN is a new safety observation and intentionally erases
    -- the effective SINGLE value, returning the product to REVIEW_REQUIRED.
    unknown_result := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'preserve-structure',
            'product_name', '기존 단품', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(
                'product_structure', 'unknown',
                'product_structure_source', 'retailer_parser',
                'product_structure_evidence', 'fixture_explicit_unknown'
            ),
            'observed_at', '2026-09-02T00:03:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if unknown_result -> 'runtime' -> 'product' ->> 'product_structure_code' <> 'UNKNOWN'
       or unknown_result -> 'runtime' -> 'product' ->> 'classification_status' <> 'REVIEW_REQUIRED'
       or unknown_result -> 'structure_contract' ->> 'state' <> 'EXPLICIT_UNKNOWN'
       or exists (
           select 1 from fitmatch_vnext.product_classification_signals pcs
           join fitmatch_vnext.source_classification_signals s on s.id = pcs.source_signal_id
           where pcs.product_id = product_id_value and s.signal_kind = 'PRODUCT_STRUCTURE'
       ) then
        raise exception 'Explicit UNKNOWN did not remain fail-closed: %', unknown_result;
    end if;

    -- D. A brand-new observation without structure stays UNKNOWN and review.
    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'missing-new',
            'product_name', '근거 없는 신규 상품', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(),
            'observed_at', '2026-09-02T00:04:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'product_structure_code' <> 'UNKNOWN'
       or result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'REVIEW_REQUIRED'
       or result_value -> 'structure_contract' ->> 'state' <> 'MISSING' then
        raise exception 'New missing structure did not fail closed: %', result_value;
    end if;

    -- E. Structure and comparison unit are independent. A mixed SET or
    -- multiple component table is blocked; a homogeneous MULTIPACK and an
    -- UNKNOWN product with one coherent provider contract remain structurally
    -- eligible without ever being rewritten as SINGLE.
    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'set-contract',
            'product_name', '명시적 상의 하의 세트', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(
                'product_structure', 'set',
                'comparison_measurement_contract', 'multiple_component'
            ),
            'observed_at', '2026-09-02T00:05:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'NOT_APPLICABLE'
       or coalesce((result_value -> 'classification' ->>
            'comparison_unit_eligible')::boolean, true) then
        raise exception 'Mixed SET bypassed the structural comparison-unit gate: %', result_value;
    end if;

    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'multipack-contract',
            'product_name', '동일 티셔츠 3PACK', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(
                'product_structure', 'multipack',
                'comparison_measurement_contract', 'single_coherent',
                'comparison_measurement_contract_source', 'retailer_size_table',
                'comparison_measurement_contract_evidence', 'fixture_one_schema'
            ),
            'observed_at', '2026-09-02T00:06:00Z',
            'variants', jsonb_build_array(jsonb_build_object(
                'external_variant_id', 'adult-default',
                'sizes', jsonb_build_array(jsonb_build_object(
                    'size_identity', 'M', 'size_label', 'M',
                    'availability_status', 'AVAILABLE',
                    'valid_until', '2027-09-02T00:00:00Z',
                    'measurements', jsonb_build_array(jsonb_build_object(
                        'measurement_identity', 'chest',
                        'raw_code', 'chest_width', 'raw_label', 'Chest',
                        'raw_value', 50, 'raw_unit', 'cm'
                    ))
                ))
            ))
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'CONFIRMED'
       or result_value -> 'runtime' -> 'product' ->> 'product_structure_code' <> 'MULTIPACK'
       or not coalesce((result_value -> 'classification' ->>
            'comparison_unit_eligible')::boolean, false) then
        raise exception 'Homogeneous MULTIPACK was not eligible as its own structure: %', result_value;
    end if;

    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'unknown-coherent-contract',
            'product_name', '구조 미확인 티셔츠', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(
                'comparison_measurement_contract', 'single_coherent',
                'comparison_measurement_contract_source', 'retailer_size_table',
                'comparison_measurement_contract_evidence', 'fixture_one_schema'
            ),
            'observed_at', '2026-09-02T00:06:30Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'CONFIRMED'
       or result_value -> 'runtime' -> 'product' ->> 'product_structure_code' <> 'UNKNOWN'
       or not coalesce((result_value -> 'classification' ->>
            'comparison_unit_eligible')::boolean, false) then
        raise exception 'UNKNOWN structure was rewritten or wrongly blocked despite one coherent contract: %', result_value;
    end if;

    -- F. Both audiences first record the same immutable, complete official
    -- path. Only then can the sole verified DIRECT mapping be copied to the
    -- target audience; parent pointers and a matching leaf alone are not proof.
    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'uniqlo', 'external_product_id', 'general-men-knit',
            'product_name', '일반 남성 니트', 'audience', 'MEN',
            'source_category_path', '니트 & 가디건 > 니트 > 긴팔 니트',
            'source_category_codes', jsonb_build_array('95355', '95357', '100315'),
            'structured_facts', jsonb_build_object(
                'comparison_measurement_contract', 'single_coherent'
            ),
            'observed_at', '2026-09-02T00:06:45Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'CONFIRMED' then
        raise exception 'Verified UNIQLO peer did not retain its own authority: %', result_value;
    end if;

    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'uniqlo', 'external_product_id', 'general-unisex-knit',
            'product_name', '일반 유니섹스 니트', 'audience', 'UNISEX',
            'source_category_path', '니트 & 가디건 > 니트 > 긴팔 니트',
            'source_category_codes', jsonb_build_array('95355', '95357', '100315'),
            'structured_facts', jsonb_build_object(
                'comparison_measurement_contract', 'single_coherent'
            ),
            'observed_at', '2026-09-02T00:07:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'CONFIRMED'
       or result_value -> 'runtime' -> 'product' ->> 'garment_type_code' <> 'knit_sweater'
       or result_value -> 'runtime' -> 'product' ->> 'sleeve_length_code' <> 'long_sleeve'
       or coalesce((result_value -> 'comparison_unit_contract' ->>
            'uniqlo_audience_mapping_promoted')::integer, 0) <= 0 then
        raise exception 'Equivalent UNIQLO audience authority was not resolved: %', result_value;
    end if;

    -- G. PRODUCT_REQUIRED is not copied merely because audience differs.
    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'uniqlo', 'external_product_id', 'product-required-knit',
            'product_name', '정확한 상품 근거 필요 니트', 'audience', 'UNISEX',
            'source_category_path', '니트 & 가디건 > 니트 > 크루넥 니트',
            'source_category_codes', jsonb_build_array('95355', '95357', '95405'),
            'structured_facts', jsonb_build_object(
                'comparison_measurement_contract', 'single_coherent'
            ),
            'observed_at', '2026-09-02T00:08:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'REVIEW_REQUIRED'
       or result_value -> 'runtime' -> 'product' ->> 'garment_type_code' is not null then
        raise exception 'PRODUCT_REQUIRED audience signal was auto-promoted: %', result_value;
    end if;

    -- Golden regressions use the real observed provider IDs only after the
    -- general contract above has already proved the rule. They are inputs to
    -- the same production action, never branches in production SQL.
    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', '6976301',
            'product_name', '26 FW 유넥 롱슬리브 크롭 티셔츠 (3컬러)', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(
                'comparison_measurement_contract', 'single_coherent'
            ),
            'observed_at', '2026-09-02T00:09:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'CONFIRMED'
       or result_value -> 'runtime' -> 'product' ->> 'garment_type_code' <> 'tshirt'
       or result_value -> 'runtime' -> 'product' ->> 'sleeve_length_code' <> 'long_sleeve' then
        raise exception 'Golden MUSINSA 6976301 did not use the general structure rule: %', result_value;
    end if;

    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'uniqlo', 'external_product_id', 'E486080',
            'product_name', '수플레얀크루넥스웨터', 'audience', 'UNISEX',
            'source_category_path', '니트 & 가디건 > 니트 > 긴팔 니트',
            'source_category_codes', jsonb_build_array('95355', '95357', '100315'),
            'structured_facts', jsonb_build_object(
                'comparison_measurement_contract', 'single_coherent'
            ),
            'observed_at', '2026-09-02T00:10:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'CONFIRMED'
       or result_value -> 'runtime' -> 'product' ->> 'garment_type_code' <> 'knit_sweater'
       or result_value -> 'runtime' -> 'product' ->> 'sleeve_length_code' <> 'long_sleeve' then
        raise exception 'Golden UNIQLO E486080 did not use the general audience authority rule: %', result_value;
    end if;

    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'uniqlo', 'external_product_id', 'E453754',
            'product_name', '워셔블밀라노립크루넥스웨터', 'audience', 'UNISEX',
            'source_category_path', '니트 & 가디건 > 니트 > 크루넥 니트',
            'source_category_codes', jsonb_build_array('95355', '95357', '95405'),
            'structured_facts', jsonb_build_object(
                'comparison_measurement_contract', 'single_coherent'
            ),
            'observed_at', '2026-09-02T00:11:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'REVIEW_REQUIRED'
       or result_value -> 'runtime' -> 'product' ->> 'garment_type_code' is not null then
        raise exception 'Golden UNIQLO E453754 bypassed PRODUCT_REQUIRED: %', result_value;
    end if;
    recovery_value := fitmatch_vnext.classification_recovery_options(
        (result_value -> 'processing' ->> 'product_id')::uuid
    );
    if recovery_value ->> 'recoverability' <> 'RECOVERABLE'
       or recovery_value ->> 'unrecoverable_reason' is not null then
        raise exception 'PRODUCT_REQUIRED lost the bounded recovery contract: %', recovery_value;
    end if;

    -- E485393 is a provider-faithful KIDS regression: 3P remains MULTIPACK,
    -- yet one coherent size table is structurally eligible. This does not
    -- broaden the adult-only audience policy.
    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'uniqlo', 'external_product_id', 'E485393',
            'product_name', 'BOYS AIRism복서브리프3P', 'audience', 'KIDS',
            'source_category_codes', jsonb_build_array('boys', 'innerwear', 'briefs'),
            'structured_facts', jsonb_build_object(
                'product_structure', 'multipack',
                'product_structure_source', 'uniqlo_pdp_entity',
                'product_structure_evidence', 'pdp_long_description:3장_세트',
                'comparison_measurement_contract', 'single_coherent',
                'comparison_measurement_contract_source', 'uniqlo_size_chart'
            ),
            'observed_at', '2026-09-02T00:11:30Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'product_structure_code' <> 'MULTIPACK'
       or not coalesce((result_value -> 'classification' ->>
            'comparison_unit_eligible')::boolean, false)
       or result_value -> 'runtime' -> 'product' ->> 'audience_code' <> 'KIDS' then
        raise exception 'E485393 did not preserve homogeneous MULTIPACK semantics: %', result_value;
    end if;
end
$ingestion_contract$;

-- Exact duplicate and stale receipts are observational only. They must not
-- rewrite the current effective structure, provenance, signal projection, or
-- category authority.
do $receipt_idempotency_and_stale$
declare
    payload_value jsonb := jsonb_build_object(
        'source', 'musinsa', 'external_product_id', 'receipt-safety',
        'product_name', '영수증 안전 티셔츠', 'audience', 'MEN',
        'source_category_codes', jsonb_build_array('001010'),
        'structured_facts', jsonb_build_object(
            'product_structure', 'single',
            'product_structure_source', 'retailer_parser',
            'product_structure_evidence', 'fixture_observed_single',
            'comparison_measurement_contract', 'single_coherent'
        ),
        'observed_at', '2026-09-02T00:20:00Z', 'variants', jsonb_build_array()
    );
    first_result jsonb;
    duplicate_result jsonb;
    stale_result jsonb;
    product_id_value uuid;
    before_extra jsonb;
    after_extra jsonb;
    before_signal_count integer;
    after_signal_count integer;
    before_last_seen timestamptz;
    after_last_seen timestamptz;
begin
    first_result := fitmatch_vnext.ingest_product_observation(payload_value, null);
    product_id_value := (first_result -> 'processing' ->> 'product_id')::uuid;
    select source_extra, last_seen_at into before_extra, before_last_seen
    from fitmatch_vnext.products where id = product_id_value;
    select count(*) into before_signal_count
    from fitmatch_vnext.product_classification_signals
    where product_id = product_id_value;

    duplicate_result := fitmatch_vnext.ingest_product_observation(payload_value, null);
    select source_extra, last_seen_at into after_extra, after_last_seen
    from fitmatch_vnext.products where id = product_id_value;
    select count(*) into after_signal_count
    from fitmatch_vnext.product_classification_signals
    where product_id = product_id_value;
    if not coalesce((duplicate_result -> 'processing' ->>
            'idempotent')::boolean, false)
       or after_extra is distinct from before_extra
       or after_last_seen is distinct from before_last_seen
       or after_signal_count <> before_signal_count then
        raise exception 'Exact duplicate mutated current retailer authority: %', duplicate_result;
    end if;

    stale_result := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'musinsa', 'external_product_id', 'receipt-safety',
            'product_name', '영수증 안전 티셔츠', 'audience', 'MEN',
            'source_category_codes', jsonb_build_array('001010'),
            'structured_facts', jsonb_build_object(
                'product_structure', 'set',
                'comparison_measurement_contract', 'multiple_component'
            ),
            'observed_at', '2026-09-02T00:19:00Z', 'variants', jsonb_build_array()
        ), null
    );
    select source_extra, last_seen_at into after_extra, after_last_seen
    from fitmatch_vnext.products where id = product_id_value;
    select count(*) into after_signal_count
    from fitmatch_vnext.product_classification_signals
    where product_id = product_id_value;
    if stale_result -> 'processing' ->> 'status' <> 'ignored_stale'
       or after_extra is distinct from before_extra
       or after_last_seen is distinct from before_last_seen
       or after_signal_count <> before_signal_count then
        raise exception 'Stale receipt mutated current retailer authority: %', stale_result;
    end if;
end
$receipt_idempotency_and_stale$;

-- Audience generalization is fail-closed when a complete immutable path is
-- absent, hierarchy is cyclic/depth-truncated, or peers disagree semantically.
do $uniqlo_hierarchy_fail_closed$
declare
    result_value jsonb;
    cycle_a uuid := gen_random_uuid();
    cycle_b uuid := gen_random_uuid();
    prior_id uuid := null;
    depth_id uuid;
    index_value integer;
begin
    result_value := fitmatch_vnext.ingest_product_observation(
        jsonb_build_object(
            'source', 'uniqlo', 'external_product_id', 'truncated-women-knit',
            'product_name', '잘린 경로 니트', 'audience', 'WOMEN',
            'source_category_codes', jsonb_build_array('100315'),
            'structured_facts', jsonb_build_object(
                'comparison_measurement_contract', 'single_coherent'
            ),
            'observed_at', '2026-09-02T00:21:00Z', 'variants', jsonb_build_array()
        ), null
    );
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'REVIEW_REQUIRED'
       or coalesce((result_value -> 'comparison_unit_contract' ->>
            'uniqlo_audience_mapping_promoted')::integer, 0) <> 0 then
        raise exception 'Truncated UNIQLO hierarchy was promoted: %', result_value;
    end if;

    insert into fitmatch_vnext.source_classification_signals(
        id, source_code, signal_kind, external_key, audience_code,
        signal_name, signal_path, parent_signal_id
    ) values
        (cycle_a, 'uniqlo', 'CATEGORY', 'fixture-cycle-a', 'MEN',
            'cycle a', 'cycle', null),
        (cycle_b, 'uniqlo', 'CATEGORY', 'fixture-cycle-b', 'MEN',
            'cycle b', 'cycle', cycle_a);
    update fitmatch_vnext.source_classification_signals
    set parent_signal_id = cycle_b where id = cycle_a;
    if fitmatch_vnext.uniqlo_category_parent_chain_safe(cycle_a) then
        raise exception 'Cyclic UNIQLO hierarchy was treated as safe';
    end if;

    for index_value in 1..18 loop
        depth_id := gen_random_uuid();
        insert into fitmatch_vnext.source_classification_signals(
            id, source_code, signal_kind, external_key, audience_code,
            signal_name, signal_path, parent_signal_id
        ) values (
            depth_id, 'uniqlo', 'CATEGORY',
            'fixture-depth-' || index_value::text, 'MEN',
            'depth', 'depth', prior_id
        );
        prior_id := depth_id;
    end loop;
    if fitmatch_vnext.uniqlo_category_parent_chain_safe(prior_id) then
        raise exception 'Depth-truncated UNIQLO hierarchy was treated as safe';
    end if;

    insert into fitmatch_vnext.source_classification_signals(
        id, source_code, signal_kind, external_key, audience_code,
        signal_name, signal_path, parent_signal_id
    ) values
        ('d3000000-0000-0000-0000-000000000001', 'uniqlo', 'CATEGORY', 'conf-root', 'MEN',
            'root', 'root > middle > leaf', null),
        ('d3000000-0000-0000-0000-000000000002', 'uniqlo', 'CATEGORY', 'conf-middle', 'MEN',
            'middle', 'root > middle > leaf', 'd3000000-0000-0000-0000-000000000001'),
        ('d3000000-0000-0000-0000-000000000003', 'uniqlo', 'CATEGORY', 'conf-leaf', 'MEN',
            'leaf', 'root > middle > leaf', 'd3000000-0000-0000-0000-000000000002'),
        ('d3000000-0000-0000-0000-000000000101', 'uniqlo', 'CATEGORY', 'conf-root', 'WOMEN',
            'root', 'root > middle > leaf', null),
        ('d3000000-0000-0000-0000-000000000102', 'uniqlo', 'CATEGORY', 'conf-middle', 'WOMEN',
            'middle', 'root > middle > leaf', 'd3000000-0000-0000-0000-000000000101'),
        ('d3000000-0000-0000-0000-000000000103', 'uniqlo', 'CATEGORY', 'conf-leaf', 'WOMEN',
            'leaf', 'root > middle > leaf', 'd3000000-0000-0000-0000-000000000102');
    insert into fitmatch_vnext.classification_signal_mappings(
        source_signal_id, audience_code, garment_type_code, resolution_mode,
        sleeve_length_code, priority, is_verified, is_active, mapping_version,
        mapping_checksum
    ) values
        ('d3000000-0000-0000-0000-000000000003', 'MEN', 'tshirt', 'DIRECT',
            'long_sleeve', 40, true, true, 'fixture-conflict-v1', repeat('0', 64)),
        ('d3000000-0000-0000-0000-000000000103', 'WOMEN', 'knit_sweater', 'DIRECT',
            'long_sleeve', 40, true, true, 'fixture-conflict-v1', repeat('0', 64));

    perform fitmatch_vnext.ingest_product_observation(jsonb_build_object(
        'source', 'uniqlo', 'external_product_id', 'conflict-men',
        'product_name', 'conflict men', 'audience', 'MEN',
        'source_category_codes', jsonb_build_array('conf-root','conf-middle','conf-leaf'),
        'structured_facts', jsonb_build_object(
            'comparison_measurement_contract', 'single_coherent'
        ), 'observed_at', '2026-09-02T00:22:00Z', 'variants', jsonb_build_array()
    ), null);
    perform fitmatch_vnext.ingest_product_observation(jsonb_build_object(
        'source', 'uniqlo', 'external_product_id', 'conflict-women',
        'product_name', 'conflict women', 'audience', 'WOMEN',
        'source_category_codes', jsonb_build_array('conf-root','conf-middle','conf-leaf'),
        'structured_facts', jsonb_build_object(
            'comparison_measurement_contract', 'single_coherent'
        ), 'observed_at', '2026-09-02T00:22:30Z', 'variants', jsonb_build_array()
    ), null);
    result_value := fitmatch_vnext.ingest_product_observation(jsonb_build_object(
        'source', 'uniqlo', 'external_product_id', 'conflict-unisex',
        'product_name', 'conflict unisex', 'audience', 'UNISEX',
        'source_category_codes', jsonb_build_array('conf-root','conf-middle','conf-leaf'),
        'structured_facts', jsonb_build_object(
            'comparison_measurement_contract', 'single_coherent'
        ), 'observed_at', '2026-09-02T00:23:00Z', 'variants', jsonb_build_array()
    ), null);
    if result_value -> 'runtime' -> 'product' ->> 'classification_status' <> 'REVIEW_REQUIRED'
       or coalesce((result_value -> 'comparison_unit_contract' ->>
            'uniqlo_audience_mapping_promoted')::integer, 0) <> 0 then
        raise exception 'Conflicting UNIQLO audience tuples were generalized: %', result_value;
    end if;
end
$uniqlo_hierarchy_fail_closed$;

-- Actual post-migration authorization path: ADULT_ANY removes only the adult
-- audience gate. Structural mismatch and retained anatomy-specific policies
-- still block before a comparison can begin.
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub',
    '11111111-1111-1111-1111-111111111111', true);

do $adult_audience_authorization$
declare
    tshirt_target uuid := 'e0000000-0000-0000-0000-000000000001';
    knit_target uuid := 'e0000000-0000-0000-0000-000000000002';
    pants_target uuid := 'e0000000-0000-0000-0000-000000000003';
    bra_target uuid := 'e0000000-0000-0000-0000-000000000004';
    tshirt_size uuid := 'e1000000-0000-0000-0000-000000000001';
    knit_size uuid := 'e1000000-0000-0000-0000-000000000002';
    pants_size uuid := 'e1000000-0000-0000-0000-000000000003';
    bra_size uuid := 'e1000000-0000-0000-0000-000000000004';
    tshirt_ref uuid := 'e2000000-0000-0000-0000-000000000001';
    knit_ref uuid := 'e2000000-0000-0000-0000-000000000002';
    pants_ref uuid := 'e2000000-0000-0000-0000-000000000003';
    briefs_ref uuid := 'e2000000-0000-0000-0000-000000000004';
    multipack_target uuid;
    multipack_variant uuid;
    set_target uuid;
    decision_value jsonb;
    eligible_value jsonb;
begin
    insert into fitmatch_vnext.products(
        id, source_code, source_product_key, product_name, audience_code,
        product_structure_code, garment_type_code, sleeve_length_code,
        classification_status, classification_source, resolver_version,
        input_fingerprint, evidence_fingerprint
    ) values
        (tshirt_target, 'fixture', 'adult-women-tshirt', 'Women T-shirt', 'WOMEN',
            'SINGLE', 'tshirt', 'long_sleeve', 'CONFIRMED', 'SOURCE_DIRECT',
            'fixture', 'fixture', 'fixture'),
        (knit_target, 'fixture', 'adult-men-knit', 'Men Knit', 'MEN',
            'SINGLE', 'knit_sweater', 'long_sleeve', 'CONFIRMED', 'SOURCE_DIRECT',
            'fixture', 'fixture', 'fixture'),
        (pants_target, 'fixture', 'adult-women-pants', 'Women Pants', 'WOMEN',
            'SINGLE', 'standard_pants', null, 'CONFIRMED', 'SOURCE_DIRECT',
            'fixture', 'fixture', 'fixture'),
        (bra_target, 'fixture', 'adult-women-bra', 'Women Bra', 'WOMEN',
            'SINGLE', 'women_bra', null, 'CONFIRMED', 'SOURCE_DIRECT',
            'fixture', 'fixture', 'fixture');

    insert into fitmatch_vnext.product_variants(
        id, product_id, source_variant_key, sort_order
    ) values
        ('e0100000-0000-0000-0000-000000000001', tshirt_target, 'default', 0),
        ('e0100000-0000-0000-0000-000000000002', knit_target, 'default', 0),
        ('e0100000-0000-0000-0000-000000000003', pants_target, 'default', 0),
        ('e0100000-0000-0000-0000-000000000004', bra_target, 'default', 0);

    insert into fitmatch_vnext.product_sizes(
        id, variant_id, source_size_key, size_label, sort_order
    ) values
        (tshirt_size, 'e0100000-0000-0000-0000-000000000001', 'M', 'M', 0),
        (knit_size, 'e0100000-0000-0000-0000-000000000002', 'M', 'M', 0),
        (pants_size, 'e0100000-0000-0000-0000-000000000003', 'M', 'M', 0),
        (bra_size, 'e0100000-0000-0000-0000-000000000004', 'M', 'M', 0);

    insert into fitmatch_vnext.product_size_measurements(
        product_size_id, parser_code, raw_measurement_key, raw_code, raw_label,
        raw_value, raw_unit_code
    ) values
        (tshirt_size, 'fixture', 'chest', 'chest_width', 'Chest', 50, 'cm'),
        (knit_size, 'fixture', 'chest', 'chest_width', 'Chest', 50, 'cm'),
        (pants_size, 'fixture', 'chest', 'chest_width', 'Chest', 50, 'cm'),
        (bra_size, 'fixture', 'chest', 'chest_width', 'Chest', 50, 'cm');

    insert into fitmatch_vnext.closet_items(
        id, user_id, client_item_id, item_name, audience_code,
        garment_type_code, sleeve_length_code, classification_source,
        measurement_mode
    ) values
        (tshirt_ref, '11111111-1111-1111-1111-111111111111', gen_random_uuid(),
            'Men T-shirt', 'MEN', 'tshirt', 'long_sleeve', 'SOURCE_DIRECT', 'CANONICAL'),
        (knit_ref, '11111111-1111-1111-1111-111111111111', gen_random_uuid(),
            'Women Knit', 'WOMEN', 'knit_sweater', 'long_sleeve', 'SOURCE_DIRECT', 'CANONICAL'),
        (pants_ref, '11111111-1111-1111-1111-111111111111', gen_random_uuid(),
            'Men Pants', 'MEN', 'standard_pants', null, 'SOURCE_DIRECT', 'CANONICAL'),
        (briefs_ref, '11111111-1111-1111-1111-111111111111', gen_random_uuid(),
            'Men Briefs', 'MEN', 'men_briefs', null, 'SOURCE_DIRECT', 'CANONICAL');

    insert into fitmatch_vnext.closet_item_measurements(
        closet_item_id, fitmatch_measurement_code, value, unit_code, value_source
    ) values
        (tshirt_ref, 'chest_width', 50, 'cm', 'fixture'),
        (knit_ref, 'chest_width', 50, 'cm', 'fixture'),
        (pants_ref, 'chest_width', 50, 'cm', 'fixture'),
        (briefs_ref, 'chest_width', 50, 'cm', 'fixture');

    -- This is the real ingress-produced adult homogeneous MULTIPACK from the
    -- preceding block. It must pass the same authorization/size path as an
    -- explicit SINGLE; no local test policy decides the result.
    select p.id, pv.id into multipack_target, multipack_variant
    from fitmatch_vnext.products p
    join fitmatch_vnext.product_variants pv on pv.product_id = p.id
    where p.source_code = 'musinsa'
      and p.source_product_key = 'multipack-contract';
    eligible_value := fitmatch_vnext.eligible_candidate_sizes(
        tshirt_ref, multipack_target, multipack_variant, false
    );
    if not coalesce((eligible_value ->> 'allowed')::boolean, false)
       or jsonb_array_length(coalesce(
            eligible_value -> 'authorized_candidate_product_size_ids',
            '[]'::jsonb
       )) = 0 then
        raise exception 'Adult homogeneous MULTIPACK did not reach eligible size authorization: %', eligible_value;
    end if;

    -- The mixed SET is rejected by the production structure gate before the
    -- legacy authorization implementation can evaluate a size or policy.
    select id into set_target
    from fitmatch_vnext.products
    where source_code = 'musinsa' and source_product_key = 'set-contract';
    decision_value := fitmatch_vnext.authorize_comparison_with_context(
        tshirt_ref, set_target, null, true,
        jsonb_build_object('product_id', set_target,
            'classification_status', 'NOT_APPLICABLE')
    );
    if coalesce((decision_value ->> 'allowed')::boolean, false)
       or decision_value ->> 'reason' <> 'MIXED_GARMENT_SET' then
        raise exception 'Mixed SET reached comparison authorization: %', decision_value;
    end if;

    decision_value := fitmatch_vnext.authorize_comparison_with_context(
        tshirt_ref, tshirt_target, tshirt_size, false,
        jsonb_build_object('product_id', tshirt_target,
            'classification_status', 'CONFIRMED', 'garment_type_code', 'tshirt',
            'audience_code', 'WOMEN', 'sleeve_length_code', 'long_sleeve')
    );
    if not coalesce((decision_value ->> 'allowed')::boolean, false) then
        raise exception 'MEN t-shirt to WOMEN t-shirt remained blocked: %', decision_value;
    end if;

    foreach decision_value in array array[
        fitmatch_vnext.authorize_comparison_with_context(
            tshirt_ref, tshirt_target, tshirt_size, false,
            jsonb_build_object('product_id', tshirt_target,
                'classification_status', 'CONFIRMED', 'garment_type_code', 'tshirt',
                'audience_code', 'KIDS', 'sleeve_length_code', 'long_sleeve')
        ),
        fitmatch_vnext.authorize_comparison_with_context(
            tshirt_ref, tshirt_target, tshirt_size, false,
            jsonb_build_object('product_id', tshirt_target,
                'classification_status', 'CONFIRMED', 'garment_type_code', 'tshirt',
                'audience_code', 'BABY', 'sleeve_length_code', 'long_sleeve')
        ),
        fitmatch_vnext.authorize_comparison_with_context(
            tshirt_ref, tshirt_target, tshirt_size, false,
            jsonb_build_object('product_id', tshirt_target,
                'classification_status', 'CONFIRMED', 'garment_type_code', 'tshirt',
                'audience_code', 'UNKNOWN', 'sleeve_length_code', 'long_sleeve')
        )
    ] loop
        if decision_value ->> 'reason' <> 'Audience is incompatible' then
            raise exception 'ADULT_ANY leaked to a non-adult audience: %', decision_value;
        end if;
    end loop;

    decision_value := fitmatch_vnext.authorize_comparison_with_context(
        knit_ref, knit_target, knit_size, false,
        jsonb_build_object('product_id', knit_target,
            'classification_status', 'CONFIRMED', 'garment_type_code', 'knit_sweater',
            'audience_code', 'MEN', 'sleeve_length_code', 'long_sleeve')
    );
    if not coalesce((decision_value ->> 'allowed')::boolean, false) then
        raise exception 'WOMEN knit to MEN knit remained blocked: %', decision_value;
    end if;

    decision_value := fitmatch_vnext.authorize_comparison_with_context(
        pants_ref, pants_target, pants_size, false,
        jsonb_build_object('product_id', pants_target,
            'classification_status', 'CONFIRMED', 'garment_type_code', 'standard_pants',
            'audience_code', 'WOMEN')
    );
    if not coalesce((decision_value ->> 'allowed')::boolean, false) then
        raise exception 'MEN pants to WOMEN pants remained blocked: %', decision_value;
    end if;

    decision_value := fitmatch_vnext.authorize_comparison_with_context(
        tshirt_ref, pants_target, pants_size, false,
        jsonb_build_object('product_id', pants_target,
            'classification_status', 'CONFIRMED', 'garment_type_code', 'standard_pants',
            'audience_code', 'WOMEN')
    );
    if decision_value ->> 'reason' <> 'Structural comparison policies are incompatible' then
        raise exception 'Adult audience policy bypassed structural mismatch: %', decision_value;
    end if;

    decision_value := fitmatch_vnext.authorize_comparison_with_context(
        briefs_ref, bra_target, bra_size, false,
        jsonb_build_object('product_id', bra_target,
            'classification_status', 'CONFIRMED', 'garment_type_code', 'women_bra',
            'audience_code', 'WOMEN')
    );
    if decision_value ->> 'reason' <> 'Audience is incompatible' then
        raise exception 'Anatomy-specific policy unexpectedly received ADULT_ANY: %', decision_value;
    end if;
end
$adult_audience_authorization$;

rollback;
select 'LIVE_RETAILER_GENERAL_CONTRACT_PASS' as result;
