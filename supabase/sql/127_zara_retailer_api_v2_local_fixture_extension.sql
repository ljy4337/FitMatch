-- LOCAL/DISPOSABLE POSTGRESQL 17 ONLY.
-- Extends the existing 124 + 126 synthetic fixture to the production-shaped
-- preimage required by 20260902031749. It contains no user or Production data.

create schema if not exists fitmatch_catalog;

create table if not exists fitmatch_catalog.current_product_classifications (
    product_id uuid,
    source text not null,
    external_product_id text not null,
    product_name text,
    classification_id uuid not null default gen_random_uuid(),
    category_code text,
    detail_code text,
    comparison_family_code text,
    length_code text,
    classification_status text,
    confidence numeric,
    evidence jsonb not null default '{}'::jsonb
);

alter table fitmatch_vnext.source_measurement_aliases
    add column if not exists source_measurement_code text,
    add column if not exists raw_code text;

create table if not exists fitmatch_vnext.source_measurement_mappings (
    source_measurement_code text primary key,
    is_active boolean not null default true,
    is_verified boolean not null default true
);

insert into fitmatch_vnext.source_measurement_mappings(
    source_measurement_code, is_active, is_verified
) values
    ('uniqlo-body-width', true, true),
    ('uniqlo-shoulder-width', true, true),
    ('uniqlo-body-length-back', true, true),
    ('uniqlo-knit-body-length-front', true, true)
on conflict (source_measurement_code) do nothing;

insert into fitmatch_vnext.source_measurement_aliases(
    source_code, parser_code, source_measurement_code, raw_code,
    is_active, is_verified
) values
    ('uniqlo', 'size_chart', 'uniqlo-body-width', 'body-width', true, true),
    ('uniqlo', 'size_chart', 'uniqlo-shoulder-width', 'shoulder-width', true, true),
    ('uniqlo', 'size_chart', 'uniqlo-body-length-back', 'body-length-back', true, true),
    ('uniqlo', 'size_chart', 'uniqlo-knit-body-length-front', 'knit-body-length-front', true, true);

create table if not exists fitmatch_vnext.classification_axis_value_authority (
    axis_code text not null,
    value_code text not null,
    is_active boolean not null default true,
    is_verified boolean not null default true,
    primary key (axis_code, value_code)
);

insert into fitmatch_vnext.classification_axis_value_authority(
    axis_code, value_code
) values
    ('sleeve_length', 'sleeveless'),
    ('sleeve_length', 'short_sleeve'),
    ('sleeve_length', 'three_quarter_sleeve'),
    ('sleeve_length', 'long_sleeve'),
    ('lower_length', 'short_length'),
    ('lower_length', 'three_quarter_length'),
    ('lower_length', 'full_length'),
    ('body_length', 'short_body'),
    ('body_length', 'medium_body'),
    ('body_length', 'long_body')
on conflict do nothing;

-- The older shared fixture intentionally contains only four garment types.
-- This one existing production code is enough to exercise the sample's
-- three server-issued lower-length candidates without inventing a new tuple.
insert into fitmatch_vnext.garment_types(
    garment_type_code, category_code, comparison_policy_code, display_name,
    uses_lower_length, sort_order
) values (
    'other_standard_pants', 'bottoms', 'standard_pants',
    '기타 스탠다드 팬츠', true, 55
)
on conflict do nothing;
