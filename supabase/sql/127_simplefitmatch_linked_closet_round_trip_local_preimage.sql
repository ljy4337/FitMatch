-- LOCAL TEST PREIMAGE ONLY — NOT A MIGRATION.
--
-- Run this after 124_vnext_review_required_recovery_local_fixture.sql and
-- 20260829012836_vnext_closet_reference_api.sql, and before
-- 20260829110853_vnext_swift_user_contract.sql plus the candidate. The
-- production contract already refers to fitmatch_vnext.fitmatch_measurements;
-- the older recovery fixture intentionally omits that catalog table, so this
-- file supplies the smallest active-code fixture needed to execute the
-- candidate against real PostgreSQL.

begin;

create table if not exists fitmatch_vnext.fitmatch_measurements (
    measurement_code text primary key,
    is_active boolean not null default true
);

insert into fitmatch_vnext.fitmatch_measurements(measurement_code, is_active)
values
    ('chest_width', true),
    ('chest_circumference', true),
    ('shoulder_width', true),
    ('back_length', true),
    ('sleeve_length', true),
    ('hem_width', true)
on conflict (measurement_code) do update
set is_active = excluded.is_active;

-- Production currently has a registered source-measurement catalog and a
-- before-write measurement-mode trigger. Mirror that pre-candidate contract
-- locally so this validation proves the candidate's narrow extension rather
-- than accidentally testing against the older permissive fixture table.
create table if not exists fitmatch_vnext.source_measurements (
    source_measurement_code text primary key,
    source_code text not null references fitmatch_vnext.sources(source_code)
);

insert into fitmatch_vnext.source_measurements(
    source_measurement_code,
    source_code
) values
    ('fixture.chest_width.chest_pit_to_pit', 'fixture'),
    ('fixture.chest_circumference.garment', 'fixture'),
    ('fixture.shoulder_width.shoulder_seam_to_seam', 'fixture'),
    ('fixture.back_length.back_neck_to_hem', 'fixture'),
    ('fixture.sleeve_length.shoulder_seam_to_cuff', 'fixture')
on conflict (source_measurement_code) do update
set source_code = excluded.source_code;

alter table fitmatch_vnext.closet_item_measurements
    add constraint closet_item_measurements_source_measurement_code_fkey
    foreign key (source_measurement_code)
    references fitmatch_vnext.source_measurements(source_measurement_code);
alter table fitmatch_vnext.closet_item_measurements
    add constraint closet_item_measurements_fitmatch_measurement_code_fkey
    foreign key (fitmatch_measurement_code)
    references fitmatch_vnext.fitmatch_measurements(measurement_code);
alter table fitmatch_vnext.closet_item_measurements
    add constraint closet_item_measurements_one_semantic_chk
    check (
        source_measurement_code is not null
        and fitmatch_measurement_code is null
        or source_measurement_code is null
        and fitmatch_measurement_code is not null
    );

create or replace function fitmatch_vnext.validate_closet_measurement_mode()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    parent_mode text;
    parent_source text;
    native_source text;
begin
    select measurement_mode, source_code_snapshot
    into parent_mode, parent_source
    from fitmatch_vnext.closet_items
    where id = new.closet_item_id;

    if parent_mode is null then
        raise exception 'closet item % does not exist', new.closet_item_id;
    end if;

    if parent_mode = 'SOURCE_NATIVE' then
        if new.source_measurement_code is null
           or new.fitmatch_measurement_code is not null then
            raise exception 'SOURCE_NATIVE closet item requires source_measurement_code only';
        end if;

        select source_code into native_source
        from fitmatch_vnext.source_measurements
        where source_measurement_code = new.source_measurement_code;

        if native_source is distinct from parent_source then
            raise exception 'closet native measurement source % does not match closet source snapshot %',
                native_source, parent_source;
        end if;
    elsif parent_mode = 'CANONICAL' then
        if new.fitmatch_measurement_code is null
           or new.source_measurement_code is not null then
            raise exception 'CANONICAL closet item requires fitmatch_measurement_code only';
        end if;
    end if;

    return new;
end
$function$;

drop trigger if exists closet_item_measurements_validate_mode
    on fitmatch_vnext.closet_item_measurements;
create trigger closet_item_measurements_validate_mode
before insert or update of closet_item_id, source_measurement_code,
    fitmatch_measurement_code
on fitmatch_vnext.closet_item_measurements
for each row execute function fitmatch_vnext.validate_closet_measurement_mode();

-- Give the existing canonical-size fixture the same registered source
-- identities that production runtime returns. The candidate must retain
-- these identities for imported and user-adjusted source-backed rows.
create or replace function fitmatch_vnext.canonical_measurements_for_size(
    p_product_size_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
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
        'source_measurement_code', case m.raw_code
            when 'chest_width' then 'fixture.chest_width.chest_pit_to_pit'
            when 'chest_circumference' then 'fixture.chest_circumference.garment'
            when 'shoulder_width' then 'fixture.shoulder_width.shoulder_seam_to_seam'
            when 'back_length' then 'fixture.back_length.back_neck_to_hem'
            when 'sleeve_length' then 'fixture.sleeve_length.shoulder_seam_to_cuff'
            else null
        end,
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

-- Mirror the live context-aware resolver entry point. The fixture's mapping
-- is intentionally simple, but this still proves the candidate passes the
-- user-selected category tuple to the server rather than silently resolving
-- a REVIEW_REQUIRED Product under its global classification.
create or replace function fitmatch_vnext.canonical_measurements_for_size_with_context(
    p_product_size_id uuid,
    p_effective_classification jsonb
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
    actual_product_id uuid;
    effective_source text;
begin
    select pv.product_id into actual_product_id
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where ps.id = p_product_size_id;

    if actual_product_id is null then
        raise exception 'Product size not found';
    end if;
    if actual_product_id is distinct from
       (p_effective_classification ->> 'product_id')::uuid then
        raise exception 'Measurement context product mismatch';
    end if;

    effective_source := p_effective_classification ->> 'effective_source';
    if effective_source = 'USER_EXPLICIT' then
        if nullif(p_effective_classification ->> 'category_code', '') is null
           or nullif(p_effective_classification ->> 'garment_type_code', '') is null then
            raise exception 'User measurement context is incomplete';
        end if;
        return fitmatch_vnext.canonical_measurements_for_size(p_product_size_id)
            || jsonb_build_object('classification_context_source', 'USER_EXPLICIT');
    end if;
    if effective_source = 'GLOBAL_CONFIRMED' then
        return fitmatch_vnext.canonical_measurements_for_size(p_product_size_id);
    end if;

    return jsonb_build_object(
        'product_size_id', p_product_size_id,
        'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
        'measurements', '[]'::jsonb,
        'raw_measurement_count', 0,
        'unresolved_count', 0,
        'semantic_conflict_count', 0,
        'classification_context_source', effective_source
    );
end
$function$;

-- The existing Swift-user migration exposes a public wrapper around this
-- pre-existing comparison function. The linked-Closet recovery fixture is
-- intentionally narrower than comparison history, so supply only its
-- signature locally to allow the untouched migration source to load end to
-- end. The validation never invokes this shim.
create or replace function fitmatch_vnext.complete_comparison(
    p_comparison_id uuid,
    p_result jsonb
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
    select jsonb_build_object(
        'comparison_id', p_comparison_id,
        'local_fixture', true,
        'result', p_result
    )
$function$;

-- This is the nullable 1...5 contract from the existing Swift-user
-- migration. It makes the local candidate test exercise the same unrated
-- representation without touching any non-disposable database.
do $satisfaction_contract$
begin
    if not exists (
        select 1
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = 'fitmatch_vnext'
          and t.relname = 'closet_items'
          and c.conname = 'closet_items_satisfaction_chk'
    ) then
        alter table fitmatch_vnext.closet_items
            add constraint closet_items_satisfaction_chk
            check (satisfaction is null or satisfaction between 1 and 5);
    end if;
end
$satisfaction_contract$;

commit;
