-- Disposable PostgreSQL assertion for the current vNext manual-cross contract.
--
-- Prerequisite: 124_vnext_review_required_recovery_local_fixture.sql, then
-- migrations 20260830090000 and 20260830091000.  This file creates only
-- synthetic local rows and rolls every row back.  It deliberately asks the
-- deployed-shaped SQL functions for each answer; it does not reproduce the
-- manual-cross policy in test code.

begin;
select set_config(
    'request.jwt.claim.sub',
    '11111111-1111-1111-1111-111111111111',
    true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into fitmatch_vnext.comparison_policies(
    policy_code, display_name, policy_checksum
) values
    ('sweatshirt', '스웨트셔츠', 'policy-sweatshirt'),
    ('hoodie', '후디', 'policy-hoodie'),
    ('knit_sweater', '니트 스웨터', 'policy-knit-sweater')
on conflict (policy_code) do nothing;

insert into fitmatch_vnext.garment_types(
    garment_type_code, category_code, comparison_policy_code, display_name,
    uses_sleeve_length, sort_order
) values
    ('sweatshirt', 'tops', 'sweatshirt', '스웨트셔츠', true, 40),
    ('hoodie', 'tops', 'hoodie', '후디', true, 50),
    ('knit_sweater', 'tops', 'knit_sweater', '니트 스웨터', true, 60)
on conflict (garment_type_code) do nothing;

insert into fitmatch_vnext.comparison_metrics(
    comparison_policy_code, fitmatch_measurement_code
) values
    ('sweatshirt', 'chest_width'),
    ('hoodie', 'chest_width'),
    ('knit_sweater', 'chest_width');

insert into fitmatch_vnext.manual_cross_comparison_rules(
    policy_code_a, policy_code_b, reason, require_same_sleeve
) values
    (least('sweatshirt', 'hoodie'), greatest('sweatshirt', 'hoodie'),
        'Synthetic local contract assertion', true),
    (least('sweatshirt', 'knit_sweater'), greatest('sweatshirt', 'knit_sweater'),
        'Synthetic local contract assertion', true)
on conflict (policy_code_a, policy_code_b) do nothing;

insert into fitmatch_vnext.products(
    id, source_code, source_product_key, product_name, audience_code,
    product_structure_code, garment_type_code, sleeve_length_code,
    classification_status, classification_source, resolver_version,
    input_fingerprint, evidence_fingerprint
) values
    ('c0000000-0000-0000-0000-000000000010', 'fixture', 'manual-tshirt',
        'Manual T-shirt', 'MEN', 'SINGLE', 'tshirt', 'short_sleeve',
        'CONFIRMED', 'SOURCE_DIRECT', 'fixture-v1', 'input-tshirt', 'evidence-tshirt'),
    ('c0000000-0000-0000-0000-000000000011', 'fixture', 'manual-polo',
        'Manual Polo', 'MEN', 'SINGLE', 'polo_shirt', 'short_sleeve',
        'CONFIRMED', 'SOURCE_DIRECT', 'fixture-v1', 'input-polo', 'evidence-polo'),
    ('c0000000-0000-0000-0000-000000000012', 'fixture', 'manual-sweatshirt',
        'Manual Sweatshirt', 'MEN', 'SINGLE', 'sweatshirt', 'short_sleeve',
        'CONFIRMED', 'SOURCE_DIRECT', 'fixture-v1', 'input-sweatshirt', 'evidence-sweatshirt'),
    ('c0000000-0000-0000-0000-000000000013', 'fixture', 'manual-hoodie',
        'Manual Hoodie', 'MEN', 'SINGLE', 'hoodie', 'short_sleeve',
        'CONFIRMED', 'SOURCE_DIRECT', 'fixture-v1', 'input-hoodie', 'evidence-hoodie'),
    ('c0000000-0000-0000-0000-000000000014', 'fixture', 'manual-knit',
        'Manual Knit', 'MEN', 'SINGLE', 'knit_sweater', 'short_sleeve',
        'CONFIRMED', 'SOURCE_DIRECT', 'fixture-v1', 'input-knit', 'evidence-knit');

insert into fitmatch_vnext.product_variants(id, product_id, source_variant_key)
values
    ('d0000000-0000-0000-0000-000000000010', 'c0000000-0000-0000-0000-000000000010', 'M'),
    ('d0000000-0000-0000-0000-000000000011', 'c0000000-0000-0000-0000-000000000011', 'M'),
    ('d0000000-0000-0000-0000-000000000012', 'c0000000-0000-0000-0000-000000000012', 'M'),
    ('d0000000-0000-0000-0000-000000000013', 'c0000000-0000-0000-0000-000000000013', 'M'),
    ('d0000000-0000-0000-0000-000000000014', 'c0000000-0000-0000-0000-000000000014', 'M');

insert into fitmatch_vnext.product_sizes(
    id, variant_id, source_size_key, size_label, availability_status
) values
    ('e0000000-0000-0000-0000-000000000010', 'd0000000-0000-0000-0000-000000000010', 'M', 'M', 'AVAILABLE'),
    ('e0000000-0000-0000-0000-000000000011', 'd0000000-0000-0000-0000-000000000011', 'M', 'M', 'AVAILABLE'),
    ('e0000000-0000-0000-0000-000000000012', 'd0000000-0000-0000-0000-000000000012', 'M', 'M', 'AVAILABLE'),
    ('e0000000-0000-0000-0000-000000000013', 'd0000000-0000-0000-0000-000000000013', 'M', 'M', 'AVAILABLE'),
    ('e0000000-0000-0000-0000-000000000014', 'd0000000-0000-0000-0000-000000000014', 'M', 'M', 'AVAILABLE');

insert into fitmatch_vnext.product_size_measurements(
    product_size_id, raw_code, raw_label, raw_value, evidence_fingerprint
) values
    ('e0000000-0000-0000-0000-000000000010', 'chest_width', '가슴', 50, 'manual-tshirt'),
    ('e0000000-0000-0000-0000-000000000011', 'chest_width', '가슴', 50, 'manual-polo'),
    ('e0000000-0000-0000-0000-000000000012', 'chest_width', '가슴', 50, 'manual-sweatshirt'),
    ('e0000000-0000-0000-0000-000000000013', 'chest_width', '가슴', 50, 'manual-hoodie'),
    ('e0000000-0000-0000-0000-000000000014', 'chest_width', '가슴', 50, 'manual-knit');

insert into fitmatch_vnext.size_availability_observations(
    product_size_id, source_code, availability_status, evidence_kind,
    evidence_fingerprint, observed_at, valid_until
) values
    ('e0000000-0000-0000-0000-000000000010', 'fixture', 'AVAILABLE', 'FIXTURE', 'available-tshirt', now(), now() + interval '1 day'),
    ('e0000000-0000-0000-0000-000000000011', 'fixture', 'AVAILABLE', 'FIXTURE', 'available-polo', now(), now() + interval '1 day'),
    ('e0000000-0000-0000-0000-000000000012', 'fixture', 'AVAILABLE', 'FIXTURE', 'available-sweatshirt', now(), now() + interval '1 day'),
    ('e0000000-0000-0000-0000-000000000013', 'fixture', 'AVAILABLE', 'FIXTURE', 'available-hoodie', now(), now() + interval '1 day'),
    ('e0000000-0000-0000-0000-000000000014', 'fixture', 'AVAILABLE', 'FIXTURE', 'available-knit', now(), now() + interval '1 day');

insert into fitmatch_vnext.closet_items(
    id, user_id, client_item_id, item_name, size_label, audience_code,
    garment_type_code, sleeve_length_code, classification_source
) values
    ('f0000000-0000-0000-0000-000000000010', '11111111-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000010', 'T-shirt ref', 'M', 'MEN', 'tshirt', 'short_sleeve', 'USER_EXPLICIT'),
    ('f0000000-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000011', 'Polo ref', 'M', 'MEN', 'polo_shirt', 'short_sleeve', 'USER_EXPLICIT'),
    ('f0000000-0000-0000-0000-000000000012', '11111111-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000012', 'Sweatshirt ref', 'M', 'MEN', 'sweatshirt', 'short_sleeve', 'USER_EXPLICIT'),
    ('f0000000-0000-0000-0000-000000000013', '11111111-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000013', 'Hoodie ref', 'M', 'MEN', 'hoodie', 'short_sleeve', 'USER_EXPLICIT'),
    ('f0000000-0000-0000-0000-000000000014', '11111111-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000014', 'Knit ref', 'M', 'MEN', 'knit_sweater', 'short_sleeve', 'USER_EXPLICIT');

insert into fitmatch_vnext.closet_item_measurements(
    closet_item_id, fitmatch_measurement_code, value, value_source
) values
    ('f0000000-0000-0000-0000-000000000010', 'chest_width', 50, 'USER_MANUAL'),
    ('f0000000-0000-0000-0000-000000000011', 'chest_width', 50, 'USER_MANUAL'),
    ('f0000000-0000-0000-0000-000000000012', 'chest_width', 50, 'USER_MANUAL'),
    ('f0000000-0000-0000-0000-000000000013', 'chest_width', 50, 'USER_MANUAL'),
    ('f0000000-0000-0000-0000-000000000014', 'chest_width', 50, 'USER_MANUAL');

do $manual_cross_contract$
declare
    case_row record;
    automatic_value jsonb;
    explicit_value jsonb;
    sleeve_mismatch_value jsonb;
    insufficient_value jsonb;
    unavailable_value jsonb;
    stale_reference_value jsonb;
begin
    for case_row in
        select * from (values
            ('tshirt', 'polo_shirt',
                'c0000000-0000-0000-0000-000000000010'::uuid,
                'd0000000-0000-0000-0000-000000000010'::uuid,
                'e0000000-0000-0000-0000-000000000010'::uuid,
                'f0000000-0000-0000-0000-000000000011'::uuid),
            ('polo_shirt', 'tshirt',
                'c0000000-0000-0000-0000-000000000011'::uuid,
                'd0000000-0000-0000-0000-000000000011'::uuid,
                'e0000000-0000-0000-0000-000000000011'::uuid,
                'f0000000-0000-0000-0000-000000000010'::uuid),
            ('sweatshirt', 'hoodie',
                'c0000000-0000-0000-0000-000000000012'::uuid,
                'd0000000-0000-0000-0000-000000000012'::uuid,
                'e0000000-0000-0000-0000-000000000012'::uuid,
                'f0000000-0000-0000-0000-000000000013'::uuid),
            ('hoodie', 'sweatshirt',
                'c0000000-0000-0000-0000-000000000013'::uuid,
                'd0000000-0000-0000-0000-000000000013'::uuid,
                'e0000000-0000-0000-0000-000000000013'::uuid,
                'f0000000-0000-0000-0000-000000000012'::uuid),
            ('sweatshirt', 'knit_sweater',
                'c0000000-0000-0000-0000-000000000012'::uuid,
                'd0000000-0000-0000-0000-000000000012'::uuid,
                'e0000000-0000-0000-0000-000000000012'::uuid,
                'f0000000-0000-0000-0000-000000000014'::uuid),
            ('knit_sweater', 'sweatshirt',
                'c0000000-0000-0000-0000-000000000014'::uuid,
                'd0000000-0000-0000-0000-000000000014'::uuid,
                'e0000000-0000-0000-0000-000000000014'::uuid,
                'f0000000-0000-0000-0000-000000000012'::uuid)
        ) as cases(target_code, reference_code, target_product_id,
                   target_variant_id, target_size_id, reference_id)
    loop
        automatic_value := fitmatch_vnext.authorize_comparison(
            case_row.reference_id, case_row.target_product_id,
            case_row.target_size_id, false
        );
        if automatic_value ->> 'decision' <> 'BLOCKED'
           or coalesce((automatic_value ->> 'allowed')::boolean, false) then
            raise exception 'Automatic manual-cross leakage for % -> %: %',
                case_row.target_code, case_row.reference_code, automatic_value;
        end if;

        explicit_value := fitmatch_vnext.authorize_comparison(
            case_row.reference_id, case_row.target_product_id,
            case_row.target_size_id, true
        );
        if explicit_value ->> 'decision' <> 'MANUAL_EXTENDED'
           or not coalesce((explicit_value ->> 'allowed')::boolean, false)
           or explicit_value -> 'manual_cross_rule' ->> 'require_same_sleeve' <> 'true' then
            raise exception 'Explicit same-sleeve manual cross failed for % -> %: %',
                case_row.target_code, case_row.reference_code, explicit_value;
        end if;

        update fitmatch_vnext.closet_items
        set sleeve_length_code = 'long_sleeve'
        where id = case_row.reference_id;
        sleeve_mismatch_value := fitmatch_vnext.authorize_comparison(
            case_row.reference_id, case_row.target_product_id,
            case_row.target_size_id, true
        );
        if sleeve_mismatch_value ->> 'decision' <> 'BLOCKED'
           or coalesce((sleeve_mismatch_value ->> 'allowed')::boolean, false) then
            raise exception 'Sleeve mismatch manual cross leaked for % -> %: %',
                case_row.target_code, case_row.reference_code, sleeve_mismatch_value;
        end if;
        update fitmatch_vnext.closet_items
        set sleeve_length_code = 'short_sleeve'
        where id = case_row.reference_id;

        delete from fitmatch_vnext.closet_item_measurements
        where closet_item_id = case_row.reference_id;
        insufficient_value := fitmatch_vnext.authorize_comparison(
            case_row.reference_id, case_row.target_product_id,
            case_row.target_size_id, true
        );
        if insufficient_value ->> 'decision' <> 'MEASUREMENTS_REQUIRED'
           or coalesce((insufficient_value ->> 'allowed')::boolean, false) then
            raise exception 'Measurement reason was lost for % -> %: %',
                case_row.target_code, case_row.reference_code, insufficient_value;
        end if;
        insert into fitmatch_vnext.closet_item_measurements(
            closet_item_id, fitmatch_measurement_code, value, value_source
        ) values (case_row.reference_id, 'chest_width', 50, 'USER_MANUAL');
    end loop;

    update fitmatch_vnext.size_availability_observations
    set valid_until = now() - interval '1 minute'
    where product_size_id = 'e0000000-0000-0000-0000-000000000011';
    unavailable_value := fitmatch_vnext.eligible_candidate_sizes(
        'f0000000-0000-0000-0000-000000000010',
        'c0000000-0000-0000-0000-000000000011',
        'd0000000-0000-0000-0000-000000000011', true
    );
    if coalesce((unavailable_value ->> 'allowed')::boolean, false)
       or jsonb_array_length(coalesce(
            unavailable_value -> 'authorized_candidate_product_size_ids',
            '[]'::jsonb
          )) <> 0 then
        raise exception 'Unavailable manual-cross size was eligible: %', unavailable_value;
    end if;

    update fitmatch_vnext.closet_items
    set deleted_at = now()
    where id = 'f0000000-0000-0000-0000-000000000010';
    stale_reference_value := fitmatch_vnext.authorize_comparison(
        'f0000000-0000-0000-0000-000000000010',
        'c0000000-0000-0000-0000-000000000011',
        'e0000000-0000-0000-0000-000000000011', true
    );
    if stale_reference_value ->> 'decision' <> 'BLOCKED'
       or coalesce((stale_reference_value ->> 'allowed')::boolean, false) then
        raise exception 'Deleted manual reference was accepted: %', stale_reference_value;
    end if;
end
$manual_cross_contract$;

select 'MANUAL_CROSS_CONTRACT_PASS' result;
rollback;
