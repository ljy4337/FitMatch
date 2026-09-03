-- Add the minimum Production-shaped preimage needed to apply migration
-- 20260903120903 after 124_vnext_review_required_recovery_local_fixture.sql.
-- Synthetic data only; intended for a disposable PostgreSQL 17 cluster.

create schema fitmatch_catalog;

create table fitmatch_catalog.current_product_classifications (
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

create table fitmatch_vnext.user_product_classification_overrides (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id),
    product_id uuid not null references fitmatch_vnext.products(id),
    product_variant_id uuid,
    classification_source text not null default 'USER_EXPLICIT',
    audience_code text not null,
    category_code text not null,
    garment_type_code text not null,
    comparison_policy_code text not null,
    sleeve_length_code text,
    lower_length_code text,
    body_length_code text,
    base_global_status text not null default 'REVIEW_REQUIRED',
    base_product_input_fingerprint text not null,
    base_product_evidence_fingerprint text not null,
    base_resolver_version text not null,
    selected_candidate_fingerprint text not null,
    candidate_contract_version text not null,
    candidate_set_hash text not null,
    revision integer not null default 1,
    last_mutation_id uuid not null default gen_random_uuid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    cleared_at timestamptz,
    unique (user_id, product_id)
);

create or replace function fitmatch_vnext.classification_tuple_validation(
    p_garment_type_code text,
    p_product_structure_code text,
    p_audience_code text,
    p_sleeve_length_code text,
    p_lower_length_code text,
    p_body_length_code text
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with garment as (
    select gt.*
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code = p_garment_type_code
), checks as (
    select
        exists (select 1 from garment) garment_exists,
        coalesce((select is_active from garment), false) garment_active,
        upper(coalesce(p_product_structure_code, 'UNKNOWN')) in (
            'SINGLE', 'MULTIPACK', 'UNKNOWN'
        ) structure_valid,
        p_audience_code is not null
            and p_audience_code <> 'UNKNOWN' audience_valid,
        coalesce((select case when uses_sleeve_length
            then p_sleeve_length_code is not null
                 and p_sleeve_length_code <> 'UNKNOWN'
            else p_sleeve_length_code is null end from garment), false)
            sleeve_valid,
        coalesce((select case when uses_lower_length
            then p_lower_length_code is not null
                 and p_lower_length_code <> 'UNKNOWN'
            else p_lower_length_code is null end from garment), false)
            lower_valid,
        coalesce((select case when uses_body_length
            then p_body_length_code is not null
                 and p_body_length_code <> 'UNKNOWN'
            else p_body_length_code is null end from garment), false)
            body_valid
)
select jsonb_build_object(
    'valid', garment_exists and garment_active and structure_valid
        and audience_valid and sleeve_valid and lower_valid and body_valid,
    'garment_exists', garment_exists,
    'garment_active', garment_active,
    'structure_valid', structure_valid,
    'audience_valid', audience_valid,
    'sleeve_valid', sleeve_valid,
    'lower_valid', lower_valid,
    'body_valid', body_valid
)
from checks
$function$;

create or replace function fitmatch_vnext.classification_decision(
    p_source_code text,
    p_source_product_key text
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
select jsonb_build_object(
    'classification_status', p.classification_status,
    'reason', case when p.classification_status = 'REVIEW_REQUIRED'
        then 'Product-exact verified evidence is required'
        else 'Fixture global classification' end
)
from fitmatch_vnext.products p
where p.source_code = p_source_code
  and p.source_product_key = p_source_product_key
$function$;

create or replace function fitmatch_vnext.exact_product_authority_recovery_options(
    p_product_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
select case when p_product_id =
    'c0000000-0000-0000-0000-000000000005'::uuid then
    jsonb_build_object(
        'recoverability', 'RECOVERABLE',
        'unrecoverable_reason', null,
        'fixed_facts', jsonb_build_object(
            'audience_code', 'MEN',
            'product_structure_code', 'SINGLE',
            'category_code', 'tops',
            'garment_type_code', 'tshirt',
            'sleeve_length_code', 'short_sleeve',
            'comparison_policy_code', 'tshirt'
        ),
        'unknown_fields', '[]'::jsonb,
        'candidates', jsonb_build_array(jsonb_build_object(
            'candidate_id', 'legacy-exact-candidate',
            'candidate_fingerprint', 'legacy-exact-candidate',
            'display_name', '티셔츠',
            'category_code', 'tops',
            'garment_type_code', 'tshirt',
            'sleeve_length_code', 'short_sleeve',
            'lower_length_code', null,
            'body_length_code', null,
            'comparison_policy_code', 'tshirt'
        )),
        'candidate_count', 1,
        'candidate_set_hash', 'legacy-exact-set',
        'candidate_contract_version',
            'fitmatch-vnext-recovery-candidates-v4-exact-product-classification-only'
    )
else jsonb_build_object(
    'recoverability', 'UNRECOVERABLE',
    'unrecoverable_reason', 'NO_EXACT_PRODUCT_CLASSIFICATION_CANDIDATE',
    'fixed_facts', '{}'::jsonb,
    'unknown_fields', '[]'::jsonb,
    'candidates', '[]'::jsonb,
    'candidate_count', 0,
    'candidate_set_hash', null,
    'candidate_contract_version',
        'fitmatch-vnext-recovery-candidates-v4-exact-product-classification-only'
)
end
$function$;

create or replace function fitmatch_vnext.classification_recovery_options(
    p_product_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
select jsonb_build_object(
    'product_id', p_product_id,
    'candidate_contract_version',
        'fitmatch-vnext-recovery-v5-garment-type-first'
)
$function$;

create or replace function fitmatch_vnext.effective_target_classification(
    p_product_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
select jsonb_build_object(
    'product_id', p_product_id,
    'effective_contract_version', 'fitmatch-vnext-effective-target-v1'
)
$function$;

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
    comparison_contract text := 'ABSENT';
begin
    if new.garment_type_code is null then
        if tg_table_name = 'products'
           and new.classification_status = 'CONFIRMED' then
            raise exception 'CONFIRMED product requires garment_type_code';
        end if;
        return new;
    end if;
    select * into gt from fitmatch_vnext.garment_types
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
        structure_code := upper(coalesce(new.product_structure_code, 'UNKNOWN'));
        audience := new.audience_code;
        comparison_contract := upper(coalesce(
            new.source_extra -> 'comparison_measurement_contract'
                ->> 'effective_value',
            new.source_extra -> 'structured_facts'
                ->> 'comparison_measurement_contract',
            'ABSENT'
        ));
    elsif tg_table_name = 'closet_items' then
        enforce_complete := true;
        structure_code := 'SINGLE';
        audience := new.audience_code;
    end if;
    if enforce_complete then
        if structure_code = 'SET'
           or structure_code not in ('SINGLE', 'MULTIPACK', 'UNKNOWN')
           or (tg_table_name = 'products'
               and comparison_contract <> 'SINGLE_COHERENT') then
            raise exception 'comparable classification requires an eligible comparison unit';
        end if;
        if audience is null or audience = 'UNKNOWN' then
            raise exception 'comparable classification requires known audience_code';
        end if;
        if gt.uses_sleeve_length and (
            new.sleeve_length_code is null
            or new.sleeve_length_code = 'UNKNOWN'
        ) then
            raise exception 'garment_type % requires a known sleeve_length_code',
                new.garment_type_code;
        end if;
        if gt.uses_lower_length and (
            new.lower_length_code is null
            or new.lower_length_code = 'UNKNOWN'
        ) then
            raise exception 'garment_type % requires a known lower_length_code',
                new.garment_type_code;
        end if;
        if gt.uses_body_length and (
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

create trigger products_validate_garment_axes
before insert or update of classification_status, product_structure_code,
    audience_code, garment_type_code, sleeve_length_code,
    lower_length_code, body_length_code
on fitmatch_vnext.products
for each row execute function fitmatch_vnext.validate_garment_axis_values();

create trigger closet_items_validate_garment_axes
before insert or update of audience_code, garment_type_code,
    sleeve_length_code, lower_length_code, body_length_code
on fitmatch_vnext.closet_items
for each row execute function fitmatch_vnext.validate_garment_axis_values();

-- These test doubles represent the unchanged downstream boundary. The new
-- migration must neither replace them nor allow an ABSENT contract through.
create or replace function fitmatch_vnext.product_readiness(p_product_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
select jsonb_build_object(
    'product_id', p.id,
    'ready', p.classification_status = 'CONFIRMED'
        and coalesce(
            p.source_extra -> 'comparison_measurement_contract'
                ->> 'effective_value',
            'ABSENT'
        ) = 'SINGLE_COHERENT',
    'status', case when p.classification_status <> 'CONFIRMED'
        then 'CLASSIFICATION_REQUIRED'
        when coalesce(
            p.source_extra -> 'comparison_measurement_contract'
                ->> 'effective_value',
            'ABSENT'
        ) <> 'SINGLE_COHERENT' then 'MEASUREMENT_NOT_READY'
        else 'READY' end,
    'readiness_version', 'fixture-measurement-boundary-v1'
)
from fitmatch_vnext.products p
where p.id = p_product_id
$function$;

create or replace function fitmatch_vnext.authorize_comparison(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_product_size_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
select jsonb_build_object(
    'allowed', coalesce((
        fitmatch_vnext.product_readiness(p_target_product_id) ->> 'ready'
    )::boolean, false),
    'block_reason', case when coalesce((
        fitmatch_vnext.product_readiness(p_target_product_id) ->> 'ready'
    )::boolean, false) then null else 'TARGET_NOT_READY' end,
    'authorization_version', 'fixture-measurement-boundary-v1'
)
$function$;

insert into fitmatch_vnext.comparison_policies(
    policy_code, display_name, policy_checksum
) values
    ('knit_sweater', '니트/스웨터', 'policy-knit'),
    ('cardigan', '가디건', 'policy-cardigan'),
    ('hoodie', '후드', 'policy-hoodie'),
    ('no_axis_top', '축 없는 상의', 'policy-no-axis'),
    ('inactive_top', '비활성 상의', 'policy-inactive');

insert into fitmatch_vnext.garment_types(
    garment_type_code, category_code, comparison_policy_code,
    display_name, uses_sleeve_length, sort_order, is_active
) values
    ('knit_sweater', 'tops', 'knit_sweater', '니트/스웨터', true, 40, true),
    ('cardigan', 'tops', 'cardigan', '가디건', true, 50, true),
    ('hoodie', 'tops', 'hoodie', '후드', true, 60, true),
    ('no_axis_top', 'tops', 'no_axis_top', '축 없는 상의', false, 70, true),
    ('inactive_top', 'tops', 'inactive_top', '비활성 상의', false, 80, false);

insert into fitmatch_vnext.source_classification_signals(
    id, source_code, signal_kind, external_key, signal_name,
    parent_signal_id
) values
    ('b0000000-0000-0000-0000-000000000010', 'fixture', 'CATEGORY',
     'unknown-axis', '니트', null),
    ('b0000000-0000-0000-0000-000000000011', 'fixture', 'CATEGORY',
     'bounded-four', '상의', null);

insert into fitmatch_vnext.classification_signal_mappings(
    id, source_signal_id, garment_type_code, resolution_mode,
    sleeve_length_code, priority, is_verified, is_active,
    mapping_checksum
) values
    ('b1000000-0000-0000-0000-000000000010',
     'b0000000-0000-0000-0000-000000000001', 'knit_sweater',
     'DIRECT', null, 20, true, false, 'recovery-knit'),
    ('b1000000-0000-0000-0000-000000000011',
     'b0000000-0000-0000-0000-000000000001', 'cardigan',
     'DIRECT', null, 20, true, false, 'recovery-cardigan'),
    ('b1000000-0000-0000-0000-000000000012',
     'b0000000-0000-0000-0000-000000000010', 'knit_sweater',
     'DIRECT', null, 20, true, false, 'unknown-knit'),
    ('b1000000-0000-0000-0000-000000000013',
     'b0000000-0000-0000-0000-000000000011', 'tshirt',
     'DIRECT', 'long_sleeve', 20, true, false, 'bounded-tshirt'),
    ('b1000000-0000-0000-0000-000000000014',
     'b0000000-0000-0000-0000-000000000011', 'polo_shirt',
     'DIRECT', 'long_sleeve', 20, true, false, 'bounded-polo'),
    ('b1000000-0000-0000-0000-000000000015',
     'b0000000-0000-0000-0000-000000000011', 'shirt_blouse',
     'DIRECT', 'long_sleeve', 20, true, false, 'bounded-shirt'),
    ('b1000000-0000-0000-0000-000000000016',
     'b0000000-0000-0000-0000-000000000011', 'hoodie',
     'DIRECT', 'long_sleeve', 20, true, false, 'bounded-hoodie');

insert into fitmatch_vnext.products(
    id, source_code, source_product_key, product_name, audience_code,
    product_structure_code, garment_type_code, sleeve_length_code,
    classification_status, classification_source, resolver_version,
    input_fingerprint, evidence_fingerprint, source_extra
) values
    ('c0000000-0000-0000-0000-000000000004', 'fixture',
     'unknown-axis', 'Unknown sleeve knit', 'MEN', 'SINGLE', null, null,
     'REVIEW_REQUIRED', 'SOURCE_SIGNAL', 'fixture-resolver-v6',
     'unknown-input', 'unknown-evidence', '{}'::jsonb),
    ('c0000000-0000-0000-0000-000000000005', 'fixture',
     'exact-precedence', 'Exact tee', 'MEN', 'SINGLE', null, null,
     'REVIEW_REQUIRED', 'SOURCE_SIGNAL', 'fixture-resolver-v6',
     'exact-input', 'exact-evidence', '{}'::jsonb),
    ('c0000000-0000-0000-0000-000000000006', 'fixture',
     'bounded-four', 'Unsafe four candidates', 'MEN', 'SINGLE', null, null,
     'REVIEW_REQUIRED', 'SOURCE_SIGNAL', 'fixture-resolver-v6',
     'bounded-input', 'bounded-evidence', '{}'::jsonb);

insert into fitmatch_vnext.product_classification_signals values
    ('c0000000-0000-0000-0000-000000000004',
     'b0000000-0000-0000-0000-000000000010', 1),
    ('c0000000-0000-0000-0000-000000000005',
     'b0000000-0000-0000-0000-000000000001', 1),
    ('c0000000-0000-0000-0000-000000000006',
     'b0000000-0000-0000-0000-000000000011', 1);

insert into fitmatch_catalog.current_product_classifications(
    product_id, source, external_product_id, product_name,
    category_code, detail_code, comparison_family_code, length_code,
    classification_status, confidence, evidence
) values
    ('c0000000-0000-0000-0000-000000000002', 'fixture', 'recovery',
     'Recovery target', 'tops', 'knit_sweater', 'knit_sweater',
     'long_sleeve', 'confirmed', 1,
     '{"exact_product_authority":true,"authority_status":"verified"}'),
    ('c0000000-0000-0000-0000-000000000005', 'fixture',
     'exact-precedence', 'Exact tee', 'tops', 'tshirt', 'tshirt',
     'short_sleeve', 'confirmed', 1,
     '{"exact_product_authority":true,"authority_status":"verified"}');

grant usage on schema fitmatch_catalog to service_role;
grant select on fitmatch_catalog.current_product_classifications
    to service_role;
