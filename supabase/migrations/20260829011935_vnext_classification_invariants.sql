-- fitmatch_vnext P0-1: classification tuple and provenance invariants.

alter table fitmatch_vnext.products
    add column if not exists primary_source_signal_id uuid,
    add column if not exists classification_mapping_id uuid,
    add column if not exists resolution_mode text,
    add column if not exists resolver_version text,
    add column if not exists input_fingerprint text,
    add column if not exists evidence_fingerprint text,
    add column if not exists classification_evidence jsonb not null default '{}'::jsonb,
    add column if not exists classification_reason text,
    add column if not exists override_reason text,
    add column if not exists override_evidence jsonb,
    add column if not exists override_actor_id uuid,
    add column if not exists override_authority_source text,
    add column if not exists override_version text;

do $migration$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'products_primary_source_signal_fkey'
          and conrelid = 'fitmatch_vnext.products'::regclass
    ) then
        alter table fitmatch_vnext.products
            add constraint products_primary_source_signal_fkey
            foreign key (primary_source_signal_id)
            references fitmatch_vnext.source_classification_signals(id)
            on delete restrict;
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'products_classification_mapping_fkey'
          and conrelid = 'fitmatch_vnext.products'::regclass
    ) then
        alter table fitmatch_vnext.products
            add constraint products_classification_mapping_fkey
            foreign key (classification_mapping_id)
            references fitmatch_vnext.classification_signal_mappings(id)
            on delete restrict;
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'products_classification_evidence_object_chk'
          and conrelid = 'fitmatch_vnext.products'::regclass
    ) then
        alter table fitmatch_vnext.products
            add constraint products_classification_evidence_object_chk
            check (jsonb_typeof(classification_evidence) = 'object');
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'products_resolution_mode_chk'
          and conrelid = 'fitmatch_vnext.products'::regclass
    ) then
        alter table fitmatch_vnext.products
            add constraint products_resolution_mode_chk
            check (resolution_mode is null or resolution_mode in (
                'DIRECT', 'PRODUCT_REQUIRED', 'REVIEW_REQUIRED',
                'NOT_APPLICABLE', 'ADMIN_OVERRIDE'
            ));
    end if;
end
$migration$;

create unique index if not exists product_classification_signals_one_primary_uidx
    on fitmatch_vnext.product_classification_signals (product_id)
    where is_primary;

create index if not exists products_primary_source_signal_idx
    on fitmatch_vnext.products (primary_source_signal_id)
    where primary_source_signal_id is not null;

create index if not exists products_classification_mapping_idx
    on fitmatch_vnext.products (classification_mapping_id)
    where classification_mapping_id is not null;

create table if not exists fitmatch_vnext.classification_remediation_audit (
    id bigint generated always as identity primary key,
    product_id uuid not null references fitmatch_vnext.products(id) on delete restrict,
    remediation_version text not null,
    old_status text not null,
    old_tuple jsonb not null,
    evidence_source jsonb not null,
    selected_mapping_id uuid references fitmatch_vnext.classification_signal_mappings(id) on delete restrict,
    new_status text not null,
    new_tuple jsonb not null,
    resolution_reason text not null,
    applied_at timestamptz not null default now(),
    unique (product_id, remediation_version)
);

alter table fitmatch_vnext.classification_remediation_audit enable row level security;
revoke all on table fitmatch_vnext.classification_remediation_audit from public, anon, authenticated;
grant select, insert on table fitmatch_vnext.classification_remediation_audit to service_role;

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
    with gt as (
        select garment_type_code, is_active, uses_sleeve_length,
               uses_lower_length, uses_body_length
        from fitmatch_vnext.garment_types
        where garment_type_code = p_garment_type_code
    ), checks as (
        select
            gt.garment_type_code is not null as garment_exists,
            coalesce(gt.is_active, false) as garment_active,
            p_product_structure_code = 'SINGLE' as structure_valid,
            p_audience_code is not null and p_audience_code <> 'UNKNOWN' as audience_valid,
            case when coalesce(gt.uses_sleeve_length, false)
                then p_sleeve_length_code is not null and p_sleeve_length_code <> 'UNKNOWN'
                else p_sleeve_length_code is null end as sleeve_valid,
            case when coalesce(gt.uses_lower_length, false)
                then p_lower_length_code is not null and p_lower_length_code <> 'UNKNOWN'
                else p_lower_length_code is null end as lower_valid,
            case when coalesce(gt.uses_body_length, false)
                then p_body_length_code is not null and p_body_length_code <> 'UNKNOWN'
                else p_body_length_code is null end as body_valid
        from (select 1) seed left join gt on true
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
    from checks;
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
        raise exception 'Unknown or inactive garment_type_code %', new.garment_type_code;
    end if;

    if not gt.uses_sleeve_length and new.sleeve_length_code is not null then
        raise exception 'garment_type % does not use sleeve_length_code', new.garment_type_code;
    end if;
    if not gt.uses_lower_length and new.lower_length_code is not null then
        raise exception 'garment_type % does not use lower_length_code', new.garment_type_code;
    end if;
    if not gt.uses_body_length and new.body_length_code is not null then
        raise exception 'garment_type % does not use body_length_code', new.garment_type_code;
    end if;

    if tg_table_name = 'products' then
        enforce_complete := new.classification_status = 'CONFIRMED';
        structure_code := new.product_structure_code;
        audience := new.audience_code;
    elsif tg_table_name = 'closet_items' then
        enforce_complete := true;
        structure_code := 'SINGLE';
        audience := new.audience_code;
    end if;

    if enforce_complete then
        if structure_code <> 'SINGLE' then
            raise exception 'comparable classification requires product_structure_code SINGLE';
        end if;
        if audience is null or audience = 'UNKNOWN' then
            raise exception 'comparable classification requires known audience_code';
        end if;
        if gt.uses_sleeve_length and
           (new.sleeve_length_code is null or new.sleeve_length_code = 'UNKNOWN') then
            raise exception 'garment_type % requires a known sleeve_length_code', new.garment_type_code;
        end if;
        if gt.uses_lower_length and
           (new.lower_length_code is null or new.lower_length_code = 'UNKNOWN') then
            raise exception 'garment_type % requires a known lower_length_code', new.garment_type_code;
        end if;
        if gt.uses_body_length and
           (new.body_length_code is null or new.body_length_code = 'UNKNOWN') then
            raise exception 'garment_type % requires a known body_length_code', new.garment_type_code;
        end if;
    end if;

    return new;
end
$function$;

drop trigger if exists products_validate_garment_axes on fitmatch_vnext.products;
create trigger products_validate_garment_axes
before insert or update of classification_status, product_structure_code, audience_code,
    garment_type_code, sleeve_length_code, lower_length_code, body_length_code
on fitmatch_vnext.products
for each row execute function fitmatch_vnext.validate_garment_axis_values();

drop trigger if exists closet_items_validate_garment_axes on fitmatch_vnext.closet_items;
create trigger closet_items_validate_garment_axes
before insert or update of audience_code, garment_type_code, sleeve_length_code,
    lower_length_code, body_length_code
on fitmatch_vnext.closet_items
for each row execute function fitmatch_vnext.validate_garment_axis_values();

revoke all on function fitmatch_vnext.classification_tuple_validation(text,text,text,text,text,text)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.classification_tuple_validation(text,text,text,text,text,text)
    to service_role;
