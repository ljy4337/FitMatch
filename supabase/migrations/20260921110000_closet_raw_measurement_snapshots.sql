-- Preserve the exact selected-observation retailer facts beside the existing
-- canonical linked-Closet snapshot. This is intentionally additive: group
-- authority, linked snapshot creation, and comparison evidence stay owned by
-- their deployed functions.

begin;

create table if not exists fitmatch_vnext.closet_item_source_measurement_snapshots (
    closet_item_id uuid primary key
        references fitmatch_vnext.closet_items(id) on delete cascade,
    source_observation_id uuid not null
        references fitmatch_vnext.product_ingestion_receipts(id),
    product_id uuid not null references fitmatch_vnext.products(id),
    product_variant_id uuid not null references fitmatch_vnext.product_variants(id),
    product_size_id uuid not null references fitmatch_vnext.product_sizes(id),
    source_measurement_count integer not null check (source_measurement_count >= 0),
    created_at timestamptz not null default now()
);

create table if not exists fitmatch_vnext.closet_item_source_measurements (
    closet_item_id uuid not null
        references fitmatch_vnext.closet_items(id) on delete cascade,
    raw_measurement_key text not null,
    source_code text not null,
    parser_code text not null,
    raw_code text,
    raw_label text,
    raw_value numeric,
    raw_value_text text,
    raw_unit_code text,
    raw_representation text,
    source_measurement_code text,
    resolution_status text not null,
    mapping_version text,
    evidence_payload jsonb not null default '{}'::jsonb,
    source_observed_at timestamptz,
    created_at timestamptz not null default now(),
    primary key (closet_item_id, parser_code, raw_measurement_key),
    constraint closet_item_source_measurements_key_not_blank
        check (btrim(raw_measurement_key) <> ''),
    constraint closet_item_source_measurements_evidence_object
        check (jsonb_typeof(evidence_payload) = 'object')
);

create index if not exists closet_item_source_measurement_snapshots_observation_idx
    on fitmatch_vnext.closet_item_source_measurement_snapshots(source_observation_id);

alter table fitmatch_vnext.closet_item_source_measurement_snapshots enable row level security;
alter table fitmatch_vnext.closet_item_source_measurements enable row level security;
revoke all on table fitmatch_vnext.closet_item_source_measurement_snapshots,
    fitmatch_vnext.closet_item_source_measurements from public, anon, authenticated;
grant select, insert, update, delete on table
    fitmatch_vnext.closet_item_source_measurement_snapshots,
    fitmatch_vnext.closet_item_source_measurements to service_role;

-- Keep zero/negative retailer facts as raw evidence in the exact receipt. The
-- canonical functions below exclude them, so this never promotes them into a
-- comparison input. Numeric but semantically unknown codes already pass this
-- contract and remain raw-only.
do $allow_nonpositive_raw_receipts$
declare
    definition text;
begin
    select pg_get_functiondef(
        'fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)'::regprocedure
    ) into definition;
    if position('if raw_value_value is null or raw_value_value <= 0' in definition) = 0
       or position('Measurement requires a positive value and code or label' in definition) = 0 then
        raise exception 'Unexpected ingestion preimage for raw snapshot preservation';
    end if;
    definition := replace(definition,
        'if raw_value_value is null or raw_value_value <= 0',
        'if raw_value_value is null');
    definition := replace(definition,
        'Measurement requires a positive value and code or label',
        'Measurement requires a numeric value and code or label');
    execute definition;
end
$allow_nonpositive_raw_receipts$;

-- A nonpositive raw fact is retained but can never become canonical/scoring
-- evidence. Amend existing implementations without copying policy bodies.
do $exclude_nonpositive_canonical$
declare
    procedure_name regprocedure;
    definition text;
    multiline_clause text := 'where m.product_size_id = p_product_size_id' || E'\n'
        || '      and m.is_current';
    inline_clause text := 'where m.product_size_id = p_product_size_id and m.is_current';
begin
    foreach procedure_name in array array[
        'fitmatch_vnext.canonical_measurements_for_size(uuid)'::regprocedure,
        'fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)'::regprocedure
    ] loop
        select pg_get_functiondef(procedure_name) into definition;
        if position('m.raw_value > 0' in definition) > 0 then
            continue;
        end if;
        if position(multiline_clause in definition) > 0 then
            definition := replace(definition, multiline_clause,
                multiline_clause || E'\n' || '      and m.raw_value > 0');
        elsif position(inline_clause in definition) > 0 then
            -- The deployed contextual function keeps these predicates on one
            -- line. Preserve that implementation rather than replacing its
            -- policy body with the local formatting.
            definition := replace(definition, inline_clause,
                inline_clause || E'\n' || '      and m.raw_value > 0');
        else
            raise exception 'Unexpected canonical preimage for %', procedure_name;
        end if;
        execute definition;
    end loop;
end
$exclude_nonpositive_canonical$;

-- Keep the existing group-aware linked mutation as the owner. The public
-- bridge is recreated after the rename because Postgres dependencies follow
-- function OIDs through renames.
do $rename_group_upsert$
begin
    if to_regprocedure(
        'fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base(jsonb)'
    ) is null then
        if to_regprocedure(
            'fitmatch_vnext.upsert_closet_item_with_group_for_swift(jsonb)'
        ) is null then
            raise exception 'Missing group-aware Closet upsert preimage';
        end if;
        alter function fitmatch_vnext.upsert_closet_item_with_group_for_swift(jsonb)
            rename to upsert_closet_item_with_group_for_swift_snapshot_base;
    end if;
end
$rename_group_upsert$;

create or replace function fitmatch_vnext.upsert_closet_item_with_group_for_swift(
    p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    result_value jsonb;
    closet_item_id_value uuid;
    result_closet_item_id uuid;
    result_item_id uuid;
    product_id_value uuid;
    product_variant_id_value uuid;
    product_size_id_value uuid;
    source_observation_id_value uuid;
    source_code_value text;
    source_variant_key_value text;
    source_size_key_value text;
    garment_type_code_value text;
    category_code_value text;
    receipt_value fitmatch_vnext.product_ingestion_receipts%rowtype;
    existing_snapshot fitmatch_vnext.closet_item_source_measurement_snapshots%rowtype;
    source_measurement_count_value integer;
begin
    result_value := fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base(
        p_request
    );

    result_closet_item_id := nullif(result_value ->> 'closet_item_id', '')::uuid;
    result_item_id := nullif(result_value ->> 'item_id', '')::uuid;
    if result_closet_item_id is not null
       and result_item_id is not null
       and result_closet_item_id <> result_item_id then
        raise exception 'Closet mutation returned conflicting item identities';
    end if;
    closet_item_id_value := coalesce(result_closet_item_id, result_item_id);
    if closet_item_id_value is null then
        raise exception 'Closet mutation did not return an item identity';
    end if;

    -- Same linked branch as the preserved group owner. Manual creation and
    -- linked updates retain their established contracts and never overwrite a
    -- raw snapshot.
    if p_request is null
       or nullif(btrim(p_request ->> 'product_id'), '') is null
       or not (p_request ? 'measurements') then
        return result_value;
    end if;

    product_id_value := nullif(p_request ->> 'product_id', '')::uuid;
    product_variant_id_value := nullif(p_request ->> 'product_variant_id', '')::uuid;
    product_size_id_value := nullif(p_request ->> 'product_size_id', '')::uuid;
    source_observation_id_value := nullif(p_request ->> 'source_observation_id', '')::uuid;
    if product_variant_id_value is null or product_size_id_value is null
       or source_observation_id_value is null then
        raise exception 'Exact observation, product variant, and size identities are required';
    end if;

    perform 1 from fitmatch_vnext.closet_items ci
    where ci.id = closet_item_id_value and ci.user_id = auth.uid() and ci.deleted_at is null
    for update;
    if not found then
        raise exception 'Closet item is missing or not owned';
    end if;

    select * into existing_snapshot
    from fitmatch_vnext.closet_item_source_measurement_snapshots s
    where s.closet_item_id = closet_item_id_value;
    if found then
        if existing_snapshot.source_observation_id <> source_observation_id_value
           or existing_snapshot.product_id <> product_id_value
           or existing_snapshot.product_variant_id <> product_variant_id_value
           or existing_snapshot.product_size_id <> product_size_id_value then
            raise exception 'Source observation does not match the immutable Closet snapshot';
        end if;
        return result_value;
    end if;

    select p.source_code, pv.source_variant_key, ps.source_size_key,
           p.garment_type_code, gt.category_code
      into source_code_value, source_variant_key_value, source_size_key_value,
           garment_type_code_value, category_code_value
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    left join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code
    where ps.id = product_size_id_value
      and pv.id = product_variant_id_value
      and p.id = product_id_value;
    if not found then
        raise exception 'Product, variant, and size identities do not match';
    end if;

    select * into receipt_value
    from fitmatch_vnext.product_ingestion_receipts r
    where r.id = source_observation_id_value
      and r.product_id = product_id_value
      and r.source_code = source_code_value
      and r.processing_status = 'PROCESSED';
    if not found then
        raise exception 'Exact retailer observation is unavailable';
    end if;

    if not exists (
        select 1
        from jsonb_array_elements(coalesce(receipt_value.retailer_facts -> 'variants', '[]'::jsonb)) variant(value)
        cross join lateral jsonb_array_elements(coalesce(variant.value -> 'sizes', '[]'::jsonb)) size(value)
        where btrim(variant.value ->> 'external_variant_id') = source_variant_key_value
          and btrim(size.value ->> 'size_identity') = source_size_key_value
    ) then
        raise exception 'Observation does not contain the selected variant and size';
    end if;

    insert into fitmatch_vnext.closet_item_source_measurements (
        closet_item_id, raw_measurement_key, source_code, parser_code,
        raw_code, raw_label, raw_value, raw_value_text, raw_unit_code,
        raw_representation, source_measurement_code, resolution_status,
        mapping_version, evidence_payload, source_observed_at
    )
    select
        closet_item_id_value,
        btrim(measurement.value ->> 'measurement_identity'),
        source_code_value,
        coalesce(nullif(btrim(measurement.value ->> 'parser_code'), ''), 'ingestion_unmapped'),
        nullif(btrim(measurement.value ->> 'raw_code'), ''),
        measurement.value ->> 'raw_label',
        nullif(measurement.value ->> 'raw_value', '')::numeric,
        measurement.value ->> 'raw_value_text',
        nullif(btrim(measurement.value ->> 'raw_unit'), ''),
        measurement.value ->> 'raw_representation',
        decision.value ->> 'source_measurement_code',
        coalesce(decision.value ->> 'resolution_status', 'UNMAPPED'),
        decision.value ->> 'resolver_version',
        coalesce(measurement.value -> 'evidence', '{}'::jsonb),
        receipt_value.observed_at
    from jsonb_array_elements(receipt_value.retailer_facts -> 'variants') variant(value)
    cross join lateral jsonb_array_elements(variant.value -> 'sizes') size(value)
    cross join lateral jsonb_array_elements(size.value -> 'measurements') measurement(value)
    cross join lateral fitmatch_vnext.resolve_measurement(
        source_code_value,
        coalesce(nullif(btrim(measurement.value ->> 'parser_code'), ''), 'ingestion_unmapped'),
        nullif(btrim(measurement.value ->> 'raw_code'), ''),
        coalesce(measurement.value ->> 'raw_label', ''),
        garment_type_code_value,
        category_code_value,
        nullif(measurement.value ->> 'raw_value', '')::numeric
    ) decision(value)
    where btrim(variant.value ->> 'external_variant_id') = source_variant_key_value
      and btrim(size.value ->> 'size_identity') = source_size_key_value
      and btrim(measurement.value ->> 'measurement_identity') <> '';

    get diagnostics source_measurement_count_value = row_count;
    if source_measurement_count_value = 0 then
        raise exception 'Exact retailer observation contains no selected-size source measurements';
    end if;

    insert into fitmatch_vnext.closet_item_source_measurement_snapshots (
        closet_item_id, source_observation_id, product_id, product_variant_id,
        product_size_id, source_measurement_count
    ) values (
        closet_item_id_value, source_observation_id_value, product_id_value,
        product_variant_id_value, product_size_id_value, source_measurement_count_value
    );

    return result_value;
end
$function$;

do $rename_list$
begin
    if to_regprocedure('fitmatch_vnext.list_closet_items_snapshot_base()') is null then
        if to_regprocedure('fitmatch_vnext.list_closet_items()') is null then
            raise exception 'Missing Closet list preimage';
        end if;
        alter function fitmatch_vnext.list_closet_items()
            rename to list_closet_items_snapshot_base;
    end if;
end
$rename_list$;

create or replace function fitmatch_vnext.list_closet_items()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    prior_items jsonb;
begin
    prior_items := fitmatch_vnext.list_closet_items_snapshot_base();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'source_measurements', coalesce((
                select jsonb_agg(jsonb_build_object(
                    'raw_measurement_key', sm.raw_measurement_key,
                    'source_code', sm.source_code,
                    'parser_code', sm.parser_code,
                    'raw_code', sm.raw_code,
                    'raw_label', sm.raw_label,
                    'raw_value', sm.raw_value,
                    'raw_value_text', sm.raw_value_text,
                    'raw_unit_code', sm.raw_unit_code,
                    'raw_representation', sm.raw_representation,
                    'source_measurement_code', sm.source_measurement_code,
                    'resolution_status', sm.resolution_status,
                    'mapping_version', sm.mapping_version,
                    'evidence', sm.evidence_payload,
                    'observed_at', sm.source_observed_at
                ) order by sm.parser_code, sm.raw_measurement_key)
                from fitmatch_vnext.closet_item_source_measurements sm
                where sm.closet_item_id = (item ->> 'id')::uuid
            ), '[]'::jsonb)
        ) order by ordinal)
        from jsonb_array_elements(coalesce(prior_items, '[]'::jsonb))
            with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$;

-- Preserve deployed public group/result contracts; source_measurements is the
-- only additive list key.
create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.upsert_closet_item_with_group_for_swift(p_request)
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare result_value jsonb;
begin
    result_value := fitmatch_vnext.list_closet_items();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'comparison_group', fitmatch_vnext.closet_comparison_group((item ->> 'id')::uuid)
        ) order by ordinal)
        from jsonb_array_elements(result_value) with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$;

revoke all on function fitmatch_vnext.upsert_closet_item_with_group_for_swift(jsonb)
    from public, anon;
grant execute on function fitmatch_vnext.upsert_closet_item_with_group_for_swift(jsonb)
    to authenticated, service_role;
revoke all on function fitmatch_vnext.list_closet_items() from public, anon;
grant execute on function fitmatch_vnext.list_closet_items() to authenticated, service_role;
revoke all on function public.fitmatch_vnext_upsert_closet_item(jsonb) from public, anon;
grant execute on function public.fitmatch_vnext_upsert_closet_item(jsonb)
    to authenticated, service_role;
revoke all on function public.fitmatch_vnext_list_closet_items() from public, anon;
grant execute on function public.fitmatch_vnext_list_closet_items()
    to authenticated, service_role;

commit;
