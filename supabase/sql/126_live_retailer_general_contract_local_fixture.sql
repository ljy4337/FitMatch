-- LOCAL/DISPOSABLE POSTGRESQL 17 ONLY.
--
-- Prerequisite: 124_vnext_review_required_recovery_local_fixture.sql.
-- This additive fixture extension supplies only the pre-ingress tables and
-- columns that existed before vNext ingestion. It contains synthetic data
-- only, lets the real repository migrations define the production functions,
-- and is not a Production migration or seed.

alter table fitmatch_vnext.sources
    add column if not exists is_active boolean not null default true;

alter table fitmatch_vnext.product_classification_signals
    add column if not exists is_primary boolean not null default false,
    add column if not exists observed_at timestamptz not null default now();

alter table fitmatch_vnext.product_variants
    add constraint product_variants_product_source_key_unique
    unique (product_id, source_variant_key);

alter table fitmatch_vnext.product_sizes
    add constraint product_sizes_variant_source_key_unique
    unique (variant_id, source_size_key);

alter table fitmatch_vnext.product_size_measurements
    add column if not exists raw_measurement_key text not null default 'fixture',
    add column if not exists raw_representation text,
    add column if not exists observed_at timestamptz not null default now();

alter table fitmatch_vnext.product_size_measurements
    add constraint product_size_measurements_raw_identity_unique
    unique (product_size_id, parser_code, raw_measurement_key);

alter table fitmatch_vnext.size_availability_observations
    add constraint size_availability_observations_fingerprint_unique
    unique (product_size_id, evidence_fingerprint);

alter table fitmatch_vnext.source_classification_signals
    add constraint source_classification_signals_identity_unique
    unique (source_code, signal_kind, external_key, audience_code);

create table fitmatch_vnext.source_identifiers (
    id bigint generated always as identity primary key,
    source_code text not null references fitmatch_vnext.sources(source_code),
    entity_scope text not null,
    product_id uuid references fitmatch_vnext.products(id),
    variant_id uuid references fitmatch_vnext.product_variants(id),
    product_size_id uuid references fitmatch_vnext.product_sizes(id),
    identifier_type_code text not null,
    identifier_value text not null,
    unique (source_code, entity_scope, identifier_type_code, identifier_value)
);

create table fitmatch_vnext.source_measurement_aliases (
    id bigint generated always as identity primary key,
    source_code text not null references fitmatch_vnext.sources(source_code),
    parser_code text not null,
    is_active boolean not null default true,
    is_verified boolean not null default true
);

create or replace function fitmatch_vnext.record_size_availability(
    p_product_size_id uuid,
    p_availability_status text,
    p_evidence_kind text,
    p_evidence_payload jsonb,
    p_observed_at timestamptz,
    p_valid_until timestamptz default null
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
    fingerprint_value text;
    observation_id bigint;
begin
    fingerprint_value := encode(extensions.digest(concat_ws('|',
        p_product_size_id::text, p_availability_status, p_evidence_kind,
        p_evidence_payload::text, p_observed_at::text
    ), 'sha256'), 'hex');
    insert into fitmatch_vnext.size_availability_observations (
        product_size_id, source_code, availability_status, evidence_kind,
        evidence_payload, evidence_fingerprint, observed_at, valid_until
    )
    select p_product_size_id, p.source_code, p_availability_status,
           p_evidence_kind, p_evidence_payload, fingerprint_value,
           p_observed_at, p_valid_until
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    where ps.id = p_product_size_id
    on conflict (product_size_id, evidence_fingerprint) do update
    set evidence_payload = excluded.evidence_payload
    returning id into observation_id;

    update fitmatch_vnext.product_sizes
    set availability_status = p_availability_status,
        last_seen_at = greatest(last_seen_at, p_observed_at)
    where id = p_product_size_id;

    return jsonb_build_object(
        'observation_id', observation_id,
        'product_size_id', p_product_size_id,
        'availability_status', p_availability_status,
        'evidence_fingerprint', fingerprint_value
    );
end
$function$;

insert into fitmatch_vnext.sources(source_code, is_active) values
    ('musinsa', true),
    ('uniqlo', true)
on conflict (source_code) do update set is_active = true;

-- The migration closes policy scope against all 39 active codes. These rows
-- model that existing catalog; only the small subset below gets a synthetic
-- garment type/mapping for runtime assertions.
insert into fitmatch_vnext.comparison_policies(
    policy_code, display_name, policy_checksum
) values
    ('anorak', 'Anorak', 'fixture-anorak'),
    ('base_layer_top', 'Base layer', 'fixture-base-layer'),
    ('blazer', 'Blazer', 'fixture-blazer'),
    ('blouson', 'Blouson', 'fixture-blouson'),
    ('bodysuit_top', 'Bodysuit', 'fixture-bodysuit'),
    ('cardigan', 'Cardigan', 'fixture-cardigan'),
    ('coat', 'Coat', 'fixture-coat'),
    ('dress', 'Dress', 'fixture-dress'),
    ('fleece_jacket', 'Fleece', 'fixture-fleece'),
    ('homewear_bottom', 'Homewear bottom', 'fixture-homewear-bottom'),
    ('homewear_top', 'Homewear top', 'fixture-homewear-top'),
    ('hoodie', 'Hoodie', 'fixture-hoodie'),
    ('jacket', 'Jacket', 'fixture-jacket'),
    ('knit_sweater', 'Knit sweater', 'fixture-knit-sweater'),
    ('knit_vest', 'Knit vest', 'fixture-knit-vest'),
    ('leggings', 'Leggings', 'fixture-leggings'),
    ('ma1', 'MA-1', 'fixture-ma1'),
    ('men_briefs', 'Men briefs', 'fixture-men-briefs'),
    ('men_trunks', 'Men trunks', 'fixture-men-trunks'),
    ('men_undershirt', 'Men undershirt', 'fixture-men-undershirt'),
    ('mouton', 'Mouton', 'fixture-mouton'),
    ('outer_vest', 'Outer vest', 'fixture-outer-vest'),
    ('puffer_jacket', 'Puffer jacket', 'fixture-puffer-jacket'),
    ('puffer_vest', 'Puffer vest', 'fixture-puffer-vest'),
    ('skirt', 'Skirt', 'fixture-skirt'),
    ('sleeveless_tshirt', 'Sleeveless t-shirt', 'fixture-sleeveless-tshirt'),
    ('sports_top', 'Sports top', 'fixture-sports-top'),
    ('standard_pants', 'Standard pants', 'fixture-standard-pants'),
    ('sweatshirt', 'Sweatshirt', 'fixture-sweatshirt'),
    ('tank_top', 'Tank top', 'fixture-tank-top'),
    ('windbreaker', 'Windbreaker', 'fixture-windbreaker'),
    ('women_bra', 'Women bra', 'fixture-women-bra'),
    ('women_camisole', 'Women camisole', 'fixture-women-camisole'),
    ('women_panty', 'Women panty', 'fixture-women-panty'),
    ('women_slip', 'Women slip', 'fixture-women-slip'),
    ('zip_hoodie', 'Zip hoodie', 'fixture-zip-hoodie')
on conflict (policy_code) do nothing;

insert into fitmatch_vnext.garment_types(
    garment_type_code, category_code, comparison_policy_code, display_name,
    uses_sleeve_length, sort_order
) values
    ('knit_sweater', 'tops', 'knit_sweater', 'Knit sweater', true, 40),
    ('standard_pants', 'bottoms', 'standard_pants', 'Standard pants', false, 50),
    ('men_briefs', 'underwear', 'men_briefs', 'Men briefs', false, 60),
    ('women_bra', 'underwear', 'women_bra', 'Women bra', false, 70)
on conflict (garment_type_code) do nothing;

insert into fitmatch_vnext.comparison_metrics(
    comparison_policy_code, fitmatch_measurement_code
) values
    ('knit_sweater', 'chest_width'),
    ('standard_pants', 'chest_width'),
    ('men_briefs', 'chest_width'),
    ('women_bra', 'chest_width')
on conflict do nothing;
