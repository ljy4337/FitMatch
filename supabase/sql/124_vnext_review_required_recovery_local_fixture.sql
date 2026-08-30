-- Disposable PostgreSQL 17 production-shaped fixture for migrations
-- 20260830090000 and 20260830091000. Contains synthetic non-user data only.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema extensions;
create schema fitmatch_vnext;
create extension if not exists pgcrypto with schema extensions;

create table auth.users (
    id uuid primary key,
    email text
);

create or replace function auth.uid() returns uuid
language sql stable set search_path = ''
as $function$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

create or replace function auth.jwt() returns jsonb
language sql stable set search_path = ''
as $function$
    select jsonb_build_object(
        'role', nullif(current_setting('request.jwt.claim.role', true), '')
    )
$function$;

create table fitmatch_vnext.sources (
    source_code text primary key
);

create table fitmatch_vnext.garment_types (
    garment_type_code text primary key,
    category_code text not null,
    comparison_policy_code text not null,
    display_name text not null,
    uses_sleeve_length boolean not null default false,
    uses_lower_length boolean not null default false,
    uses_body_length boolean not null default false,
    sort_order integer not null default 0,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table fitmatch_vnext.comparison_policies (
    policy_code text primary key,
    display_name text not null,
    min_common_measurements smallint not null default 1,
    required_any_min smallint not null default 1,
    native_default_weight numeric not null default 1,
    audience_policy_code text not null default 'SAME_OR_UNISEX',
    sleeve_mismatch_policy text not null default 'REQUIRE_MATCH',
    lower_length_mismatch_policy text not null default 'IGNORE',
    body_length_mismatch_policy text not null default 'IGNORE',
    is_active boolean not null default true,
    allow_manual_extended boolean not null default true,
    sleeve_mismatch_excluded_codes text[] not null default '{}',
    lower_mismatch_excluded_codes text[] not null default '{}',
    body_mismatch_excluded_codes text[] not null default '{}',
    policy_version text not null default 'fixture-policy-v1',
    policy_checksum text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table fitmatch_vnext.comparison_metrics (
    id uuid primary key default gen_random_uuid(),
    comparison_policy_code text not null,
    metric_mode text not null default 'CANONICAL',
    fitmatch_measurement_code text,
    source_measurement_code text,
    weight numeric not null default 1,
    requirement_mode text not null default 'REQUIRED_ANY',
    priority smallint not null default 1,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table fitmatch_vnext.source_classification_signals (
    id uuid primary key default gen_random_uuid(),
    source_code text not null references fitmatch_vnext.sources(source_code),
    signal_kind text not null,
    external_key text not null,
    external_id text,
    audience_code text not null default 'ANY',
    signal_name text,
    signal_path text,
    parent_signal_id uuid references fitmatch_vnext.source_classification_signals(id),
    is_active boolean not null default true,
    first_seen_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table fitmatch_vnext.classification_signal_mappings (
    id uuid primary key default gen_random_uuid(),
    source_signal_id uuid not null
        references fitmatch_vnext.source_classification_signals(id),
    audience_code text not null default 'ANY',
    garment_type_code text references fitmatch_vnext.garment_types(garment_type_code),
    resolution_mode text not null,
    sleeve_length_code text,
    lower_length_code text,
    body_length_code text,
    priority smallint not null default 20,
    is_verified boolean not null default true,
    is_active boolean not null default true,
    mapping_version text not null default 'fixture-mapping-v1',
    mapping_checksum text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table fitmatch_vnext.products (
    id uuid primary key default gen_random_uuid(),
    source_code text not null references fitmatch_vnext.sources(source_code),
    source_product_key text not null,
    product_name text not null,
    brand_name text,
    canonical_url text,
    image_url text,
    price_amount numeric,
    currency_code text,
    audience_code text not null default 'UNKNOWN',
    product_structure_code text not null default 'UNKNOWN',
    garment_type_code text references fitmatch_vnext.garment_types(garment_type_code),
    sleeve_length_code text,
    lower_length_code text,
    body_length_code text,
    classification_status text not null default 'REVIEW_REQUIRED',
    classification_source text not null default 'UNCLASSIFIED',
    classified_at timestamptz,
    source_status text not null default 'UNKNOWN',
    source_extra jsonb not null default '{}',
    first_seen_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    last_fetched_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary_source_signal_id uuid,
    classification_mapping_id uuid,
    resolution_mode text,
    resolver_version text,
    input_fingerprint text,
    evidence_fingerprint text,
    classification_evidence jsonb not null default '{}',
    classification_reason text,
    override_reason text,
    override_evidence jsonb,
    override_actor_id uuid,
    override_authority_source text,
    override_version text,
    unique (source_code, source_product_key)
);

create table fitmatch_vnext.product_classification_signals (
    product_id uuid not null references fitmatch_vnext.products(id),
    source_signal_id uuid not null
        references fitmatch_vnext.source_classification_signals(id),
    evidence_order integer not null default 0,
    primary key (product_id, source_signal_id)
);

create table fitmatch_vnext.classification_remediation_audit (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references fitmatch_vnext.products(id),
    remediation_version text not null,
    old_status text not null,
    old_tuple jsonb not null,
    evidence_source jsonb not null,
    selected_mapping_id uuid,
    new_status text not null,
    new_tuple jsonb not null,
    resolution_reason text not null,
    created_at timestamptz not null default now(),
    unique (product_id, remediation_version)
);

create table fitmatch_vnext.product_variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references fitmatch_vnext.products(id),
    source_variant_key text not null,
    variant_label text,
    color_code text,
    color_name text,
    image_url text,
    availability_status text not null default 'UNKNOWN',
    sort_order integer not null default 0,
    last_seen_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table fitmatch_vnext.product_sizes (
    id uuid primary key default gen_random_uuid(),
    variant_id uuid not null references fitmatch_vnext.product_variants(id),
    source_size_key text not null,
    size_label text not null,
    normalized_size_label text,
    availability_status text not null default 'UNKNOWN',
    sort_order integer not null default 0,
    last_seen_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table fitmatch_vnext.product_size_measurements (
    id uuid primary key default gen_random_uuid(),
    product_size_id uuid not null references fitmatch_vnext.product_sizes(id),
    parser_code text not null default 'fixture',
    raw_code text,
    raw_label text,
    raw_value numeric not null,
    raw_unit_code text not null default 'cm',
    evidence_payload jsonb not null default '{}',
    evidence_fingerprint text,
    is_current boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table fitmatch_vnext.size_availability_observations (
    id bigint generated always as identity primary key,
    product_size_id uuid not null references fitmatch_vnext.product_sizes(id),
    source_code text not null,
    availability_status text not null,
    evidence_kind text not null,
    evidence_payload jsonb not null default '{}',
    evidence_fingerprint text not null,
    observed_at timestamptz not null,
    valid_until timestamptz,
    created_at timestamptz not null default now()
);

create table fitmatch_vnext.closet_items (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id),
    client_item_id uuid not null,
    product_id uuid,
    product_variant_id uuid,
    product_size_id uuid,
    item_name text not null,
    brand_name text,
    image_url text,
    product_url text,
    size_label text,
    audience_code text not null default 'UNKNOWN',
    garment_type_code text not null,
    sleeve_length_code text,
    lower_length_code text,
    body_length_code text,
    classification_source text not null,
    measurement_mode text not null default 'CANONICAL',
    source_code_snapshot text,
    is_reference boolean not null default false,
    fit_preference_code text,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    request_fingerprint text,
    classification_fingerprint text,
    classification_resolver_version text,
    satisfaction smallint
);

create table fitmatch_vnext.closet_item_measurements (
    id uuid primary key default gen_random_uuid(),
    closet_item_id uuid not null references fitmatch_vnext.closet_items(id),
    source_measurement_code text,
    fitmatch_measurement_code text,
    value numeric not null,
    unit_code text not null default 'cm',
    value_source text not null,
    raw_label_snapshot text
);

create table fitmatch_vnext.manual_cross_comparison_rules (
    policy_code_a text not null,
    policy_code_b text not null,
    reason text not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    require_same_sleeve boolean not null default true,
    primary key (policy_code_a, policy_code_b),
    check (policy_code_a < policy_code_b)
);

create table fitmatch_vnext.comparisons (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id),
    client_comparison_id uuid not null,
    reference_closet_item_id uuid,
    target_product_id uuid,
    target_variant_id uuid,
    comparison_policy_code_snapshot text,
    comparison_mode text not null,
    reference_source_code_snapshot text,
    target_source_code_snapshot text,
    reference_item_name_snapshot text not null,
    target_product_name_snapshot text not null,
    target_image_url_snapshot text,
    reference_garment_type_snapshot text not null,
    target_garment_type_snapshot text not null,
    reference_audience_snapshot text not null,
    target_audience_snapshot text not null,
    reference_sleeve_length_snapshot text,
    target_sleeve_length_snapshot text,
    reference_lower_length_snapshot text,
    target_lower_length_snapshot text,
    reference_body_length_snapshot text,
    target_body_length_snapshot text,
    result_status text not null,
    engine_version text not null,
    snapshot_schema_version integer not null default 3,
    detail_snapshot jsonb not null default '{}',
    request_payload_hash text not null,
    authorization_mode text,
    excluded_measurement_codes text[] not null default '{}',
    reference_snapshot jsonb not null default '{}',
    target_snapshot jsonb not null default '{}',
    authority_snapshot jsonb not null default '{}',
    policy_snapshot jsonb not null default '{}',
    authorization_snapshot jsonb not null default '{}',
    input_snapshot jsonb not null default '{}',
    recommended_product_size_id uuid,
    ranking_snapshot jsonb,
    result_snapshot jsonb,
    completed_at timestamptz,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, client_comparison_id)
);

create or replace function fitmatch_vnext.classification_tuple_validation(
    p_garment_type_code text,
    p_product_structure_code text,
    p_audience_code text,
    p_sleeve_length_code text,
    p_lower_length_code text,
    p_body_length_code text
)
returns jsonb language sql stable set search_path = ''
as $function$
select jsonb_build_object(
    'valid', exists (
        select 1 from fitmatch_vnext.garment_types gt
        where gt.garment_type_code = p_garment_type_code and gt.is_active
          and p_product_structure_code = 'SINGLE'
          and p_audience_code <> 'UNKNOWN'
          and (not gt.uses_sleeve_length or p_sleeve_length_code is not null)
          and (not gt.uses_lower_length or p_lower_length_code is not null)
          and (not gt.uses_body_length or p_body_length_code is not null)
    )
)
$function$;

create or replace function fitmatch_vnext.resolve_measurement(
    p_source_code text,
    p_parser_code text,
    p_raw_measurement_code text,
    p_raw_label text,
    p_garment_type_code text default null,
    p_fitmatch_category_code text default null,
    p_raw_value numeric default null
)
returns jsonb language sql stable set search_path = ''
as $function$
select jsonb_build_object(
    'resolution_status', case when p_raw_measurement_code = 'chest_width'
        then 'RESOLVED' else 'UNMAPPED' end,
    'fitmatch_measurement_code', case when p_raw_measurement_code = 'chest_width'
        then 'chest_width' end,
    'canonical_value', p_raw_value,
    'canonical_unit_code', 'cm',
    'canonical_basis_code', 'FLAT',
    'source_measurement_code', p_raw_measurement_code,
    'resolution_path', 'FIXTURE_VERIFIED'
)
$function$;

create or replace function fitmatch_vnext.canonical_measurements_for_size(
    p_product_size_id uuid
)
returns jsonb language sql stable set search_path = ''
as $function$
select jsonb_build_object(
    'product_size_id', p_product_size_id,
    'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
    'measurements', coalesce((select jsonb_agg(jsonb_build_object(
        'product_size_measurement_id', m.id,
        'fitmatch_measurement_code', m.raw_code,
        'value', m.raw_value,
        'unit_code', 'cm',
        'basis_code', 'FLAT',
        'source_measurement_code', m.raw_code,
        'resolution_path', 'FIXTURE_VERIFIED',
        'raw_evidence_fingerprint', m.evidence_fingerprint
    ) order by m.id)
    from fitmatch_vnext.product_size_measurements m
    where m.product_size_id = p_product_size_id and m.is_current), '[]'::jsonb),
    'raw_measurement_count', (select count(*)
        from fitmatch_vnext.product_size_measurements m
        where m.product_size_id = p_product_size_id and m.is_current),
    'unresolved_count', 0,
    'semantic_conflict_count', 0
)
$function$;

create or replace function fitmatch_vnext.product_readiness(p_product_id uuid)
returns jsonb language sql stable set search_path = ''
as $function$
select jsonb_build_object(
    'product_id', p.id,
    'ready', p.classification_status = 'CONFIRMED',
    'status', case when p.classification_status = 'CONFIRMED'
        then 'READY' when p.classification_status = 'NOT_APPLICABLE'
        then 'NOT_APPLICABLE' else 'CLASSIFICATION_REQUIRED' end,
    'readiness_version', 'fitmatch-vnext-readiness-v2'
) from fitmatch_vnext.products p where p.id = p_product_id
$function$;

create or replace function fitmatch_vnext.get_product_runtime(
    p_source_code text,
    p_source_product_key text
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare p fitmatch_vnext.products%rowtype;
begin
    select * into p from fitmatch_vnext.products
    where source_code = p_source_code and source_product_key = p_source_product_key;
    if not found then return jsonb_build_object('found', false); end if;
    return jsonb_build_object(
        'found', true,
        'product', jsonb_build_object(
            'id', p.id, 'source_code', p.source_code,
            'source_product_key', p.source_product_key,
            'product_name', p.product_name,
            'classification_status', p.classification_status,
            'product_structure_code', p.product_structure_code,
            'audience_code', p.audience_code,
            'garment_type_code', p.garment_type_code,
            'sleeve_length_code', p.sleeve_length_code,
            'lower_length_code', p.lower_length_code,
            'body_length_code', p.body_length_code,
            'resolver_version', p.resolver_version,
            'input_fingerprint', p.input_fingerprint
        ),
        'readiness', fitmatch_vnext.product_readiness(p.id),
        'variants', coalesce((select jsonb_agg(jsonb_build_object(
            'id', pv.id,
            'source_variant_key', pv.source_variant_key,
            'variant_label', pv.variant_label,
            'color_name', pv.color_name,
            'sizes', coalesce((select jsonb_agg(jsonb_build_object(
                'id', ps.id,
                'source_size_key', ps.source_size_key,
                'size_label', ps.size_label,
                'availability', jsonb_build_object('status', ps.availability_status),
                'canonical_measurements',
                    fitmatch_vnext.canonical_measurements_for_size(ps.id)
            ) order by ps.sort_order, ps.id)
            from fitmatch_vnext.product_sizes ps
            where ps.variant_id = pv.id), '[]'::jsonb)
        ) order by pv.sort_order, pv.id)
        from fitmatch_vnext.product_variants pv
        where pv.product_id = p.id), '[]'::jsonb)
    );
end
$function$;

-- Signatures already present in Production before the recovery migration.
create or replace function fitmatch_vnext.authorize_comparison(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_product_size_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.eligible_candidate_sizes(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_variant_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.find_reference_candidates(
    p_target_product_id uuid,
    p_target_variant_id uuid default null
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.begin_comparison(p_request jsonb)
returns jsonb language sql security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

insert into auth.users(id,email) values
('11111111-1111-1111-1111-111111111111','audit-a@example.invalid'),
('22222222-2222-2222-2222-222222222222','audit-b@example.invalid');

insert into fitmatch_vnext.sources values ('fixture');
insert into fitmatch_vnext.comparison_policies(
    policy_code,display_name,policy_checksum
) values
('tshirt','티셔츠','policy-tshirt'),
('polo_shirt','폴로','policy-polo'),
('shirt_blouse','셔츠','policy-shirt');
insert into fitmatch_vnext.garment_types(
    garment_type_code,category_code,comparison_policy_code,display_name,
    uses_sleeve_length,sort_order
) values
('tshirt','tops','tshirt','티셔츠',true,10),
('polo_shirt','tops','polo_shirt','폴로/카라 티셔츠',true,20),
('shirt_blouse','tops','shirt_blouse','셔츠/블라우스',true,30);
insert into fitmatch_vnext.comparison_metrics(
    comparison_policy_code,fitmatch_measurement_code
) values ('tshirt','chest_width'),('polo_shirt','chest_width'),
         ('shirt_blouse','chest_width');

insert into fitmatch_vnext.source_classification_signals(
    id,source_code,signal_kind,external_key,parent_signal_id
) values
('a0000000-0000-0000-0000-000000000001','fixture','CATEGORY','false-root',null),
('a0000000-0000-0000-0000-000000000002','fixture','CATEGORY','false-leaf',
 'a0000000-0000-0000-0000-000000000001'),
('b0000000-0000-0000-0000-000000000001','fixture','CATEGORY','recovery-root',null),
('b0000000-0000-0000-0000-000000000002','fixture','CATEGORY','recovery-tshirt',
 'b0000000-0000-0000-0000-000000000001'),
('b0000000-0000-0000-0000-000000000003','fixture','CATEGORY','recovery-polo',
 'b0000000-0000-0000-0000-000000000001'),
('b0000000-0000-0000-0000-000000000004','fixture','CATEGORY','recovery-shirt',
 'b0000000-0000-0000-0000-000000000001');

insert into fitmatch_vnext.classification_signal_mappings(
    id,source_signal_id,garment_type_code,resolution_mode,
    sleeve_length_code,priority,mapping_checksum
) values
('a1000000-0000-0000-0000-000000000001',
 'a0000000-0000-0000-0000-000000000001',null,'PRODUCT_REQUIRED',null,20,'a-root'),
('a1000000-0000-0000-0000-000000000002',
 'a0000000-0000-0000-0000-000000000002','tshirt','DIRECT','short_sleeve',20,'a-leaf'),
('b1000000-0000-0000-0000-000000000001',
 'b0000000-0000-0000-0000-000000000001',null,'PRODUCT_REQUIRED',null,20,'b-root'),
('b1000000-0000-0000-0000-000000000002',
 'b0000000-0000-0000-0000-000000000002','tshirt','DIRECT','short_sleeve',20,'b-tshirt'),
('b1000000-0000-0000-0000-000000000003',
 'b0000000-0000-0000-0000-000000000003','polo_shirt','DIRECT','short_sleeve',20,'b-polo'),
('b1000000-0000-0000-0000-000000000004',
 'b0000000-0000-0000-0000-000000000004','shirt_blouse','DIRECT','short_sleeve',20,'b-shirt');

insert into fitmatch_vnext.products(
    id,source_code,source_product_key,product_name,audience_code,
    product_structure_code,garment_type_code,sleeve_length_code,
    classification_status,classification_source,resolver_version,
    input_fingerprint,evidence_fingerprint
) values
('c0000000-0000-0000-0000-000000000001','fixture','false-review','False review',
 'MEN','SINGLE',null,null,'REVIEW_REQUIRED','SOURCE_SIGNAL',
 'fitmatch-vnext-resolver-v1','false-input','false-evidence'),
('c0000000-0000-0000-0000-000000000002','fixture','recovery','Recovery target',
 'MEN','SINGLE',null,null,'REVIEW_REQUIRED','SOURCE_SIGNAL',
 'fitmatch-vnext-resolver-v2','recovery-input','recovery-evidence'),
('c0000000-0000-0000-0000-000000000003','fixture','confirmed','Confirmed polo',
 'MEN','SINGLE','polo_shirt','short_sleeve','CONFIRMED','SOURCE_DIRECT',
 'fitmatch-vnext-resolver-v2','confirmed-input','confirmed-evidence');

insert into fitmatch_vnext.product_classification_signals values
('c0000000-0000-0000-0000-000000000001',
 'a0000000-0000-0000-0000-000000000001',1),
('c0000000-0000-0000-0000-000000000001',
 'a0000000-0000-0000-0000-000000000002',2),
('c0000000-0000-0000-0000-000000000002',
 'b0000000-0000-0000-0000-000000000001',1),
('c0000000-0000-0000-0000-000000000003',
 'b0000000-0000-0000-0000-000000000003',1);

insert into fitmatch_vnext.product_variants(id,product_id,source_variant_key)
values
('d0000000-0000-0000-0000-000000000001',
 'c0000000-0000-0000-0000-000000000002','recovery-variant'),
('d0000000-0000-0000-0000-000000000002',
 'c0000000-0000-0000-0000-000000000003','confirmed-variant');
insert into fitmatch_vnext.product_sizes(
    id,variant_id,source_size_key,size_label,availability_status
) values
('e0000000-0000-0000-0000-000000000001',
 'd0000000-0000-0000-0000-000000000001','M','M','AVAILABLE'),
('e0000000-0000-0000-0000-000000000002',
 'd0000000-0000-0000-0000-000000000002','M','M','AVAILABLE');
insert into fitmatch_vnext.product_size_measurements(
    product_size_id,raw_code,raw_label,raw_value,evidence_fingerprint
) values
('e0000000-0000-0000-0000-000000000001','chest_width','가슴',50,'raw-recovery'),
('e0000000-0000-0000-0000-000000000002','chest_width','가슴',50,'raw-global');
insert into fitmatch_vnext.size_availability_observations(
    product_size_id,source_code,availability_status,evidence_kind,
    evidence_fingerprint,observed_at,valid_until
) values
('e0000000-0000-0000-0000-000000000001','fixture','AVAILABLE','FIXTURE',
 'available-recovery',now(),now()+interval '1 day'),
('e0000000-0000-0000-0000-000000000002','fixture','AVAILABLE','FIXTURE',
 'available-global',now(),now()+interval '1 day');

insert into fitmatch_vnext.closet_items(
    id,user_id,client_item_id,item_name,size_label,audience_code,
    garment_type_code,sleeve_length_code,classification_source,is_reference
) values
('f0000000-0000-0000-0000-000000000001',
 '11111111-1111-1111-1111-111111111111',
 'f1000000-0000-0000-0000-000000000001','Short polo','M','MEN',
 'polo_shirt','short_sleeve','USER_EXPLICIT',true),
('f0000000-0000-0000-0000-000000000002',
 '11111111-1111-1111-1111-111111111111',
 'f1000000-0000-0000-0000-000000000002','Short tee','M','MEN',
 'tshirt','short_sleeve','USER_EXPLICIT',false),
('f0000000-0000-0000-0000-000000000003',
 '11111111-1111-1111-1111-111111111111',
 'f1000000-0000-0000-0000-000000000003','Long tee','M','MEN',
 'tshirt','long_sleeve','USER_EXPLICIT',false);
insert into fitmatch_vnext.closet_item_measurements(
    closet_item_id,fitmatch_measurement_code,value,value_source
) values
('f0000000-0000-0000-0000-000000000001','chest_width',50,'USER_MANUAL'),
('f0000000-0000-0000-0000-000000000002','chest_width',50,'USER_MANUAL'),
('f0000000-0000-0000-0000-000000000003','chest_width',50,'USER_MANUAL');

insert into fitmatch_vnext.manual_cross_comparison_rules(
    policy_code_a,policy_code_b,reason,require_same_sleeve
) values (
    least('tshirt','polo_shirt'), greatest('tshirt','polo_shirt'),
    'Explicit manual comparison fixture', true
);

grant usage on schema fitmatch_vnext, public to authenticated, service_role;
grant usage on schema auth to authenticated, service_role;
