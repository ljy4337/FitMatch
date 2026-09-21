-- Preserve the exact selected-size retailer facts separately from canonical
-- Closet measurements.  This migration does not alter comparison evidence,
-- mappings, product classifications, or historical comparison snapshots.

begin;

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

alter table fitmatch_vnext.closet_item_source_measurements enable row level security;
revoke all on table fitmatch_vnext.closet_item_source_measurements
    from public, anon, authenticated;
grant select, insert, update, delete on table fitmatch_vnext.closet_item_source_measurements
    to service_role;

-- Keep the deployed public contract stable while extending the existing
-- server-first linked upsert.  A retry never refreshes a saved raw snapshot:
-- later product observations must not rewrite the user's historical Closet
-- measurement facts.
do $rename_upsert$
begin
    if to_regprocedure('fitmatch_vnext.upsert_closet_item_for_swift_v1(jsonb)') is null then
        alter function fitmatch_vnext.upsert_closet_item_for_swift(jsonb)
            rename to upsert_closet_item_for_swift_v1;
    end if;
end
$rename_upsert$;

create or replace function fitmatch_vnext.upsert_closet_item_for_swift(
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
    product_size_id_value uuid;
begin
    result_value := fitmatch_vnext.upsert_closet_item_for_swift_v1(p_request);
    closet_item_id_value := (result_value ->> 'item_id')::uuid;
    product_size_id_value := nullif(p_request ->> 'product_size_id', '')::uuid;

    if closet_item_id_value is not null and product_size_id_value is not null then
        insert into fitmatch_vnext.closet_item_source_measurements (
            closet_item_id, raw_measurement_key, source_code, parser_code,
            raw_code, raw_label, raw_value, raw_value_text, raw_unit_code,
            raw_representation, source_measurement_code, resolution_status,
            mapping_version, evidence_payload, source_observed_at
        )
        -- The receipt is the exact API observation Swift submitted.  Do not
        -- reconstruct raw facts from canonical product rows: that would lose
        -- original text/unit/provenance and can reflect a later re-ingestion.
        select
            closet_item_id_value,
            btrim(measurement.value ->> 'measurement_identity'),
            p.source_code,
            coalesce(nullif(btrim(measurement.value ->> 'parser_code'), ''), 'ingestion_unmapped'),
            nullif(btrim(measurement.value ->> 'raw_code'), ''),
            measurement.value ->> 'raw_label',
            (measurement.value ->> 'raw_value')::numeric,
            measurement.value ->> 'raw_value_text',
            measurement.value ->> 'raw_unit',
            measurement.value ->> 'raw_representation',
            decision.value ->> 'source_measurement_code',
            coalesce(decision.value ->> 'resolution_status', 'UNMAPPED'),
            decision.value ->> 'resolver_version',
            coalesce(measurement.value -> 'evidence', '{}'::jsonb),
            receipt.observed_at
        from fitmatch_vnext.product_sizes ps
        join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
        join fitmatch_vnext.products p on p.id = pv.product_id
        left join fitmatch_vnext.garment_types gt
          on gt.garment_type_code = p.garment_type_code
        join lateral (
            select r.retailer_facts, r.observed_at
            from fitmatch_vnext.product_ingestion_receipts r
            where r.product_id = p.id
              and exists (
                  select 1
                  from jsonb_array_elements(coalesce(r.retailer_facts -> 'variants', '[]'::jsonb)) v(value)
                  where btrim(v.value ->> 'external_variant_id') = pv.source_variant_key
                    and exists (
                        select 1
                        from jsonb_array_elements(coalesce(v.value -> 'sizes', '[]'::jsonb)) s(value)
                        where btrim(s.value ->> 'size_identity') = ps.source_size_key
                    )
              )
            order by r.observed_at desc, r.id desc
            limit 1
        ) receipt on true
        cross join lateral jsonb_array_elements(receipt.retailer_facts -> 'variants') variant(value)
        cross join lateral jsonb_array_elements(variant.value -> 'sizes') size(value)
        cross join lateral jsonb_array_elements(size.value -> 'measurements') measurement(value)
        cross join lateral fitmatch_vnext.resolve_measurement(
            p.source_code,
            coalesce(nullif(btrim(measurement.value ->> 'parser_code'), ''), 'ingestion_unmapped'),
            nullif(btrim(measurement.value ->> 'raw_code'), ''),
            coalesce(measurement.value ->> 'raw_label', ''),
            p.garment_type_code,
            gt.category_code,
            (measurement.value ->> 'raw_value')::numeric
        ) decision(value)
        where ps.id = product_size_id_value
          and btrim(variant.value ->> 'external_variant_id') = pv.source_variant_key
          and btrim(size.value ->> 'size_identity') = ps.source_size_key
          and btrim(measurement.value ->> 'measurement_identity') <> ''
        on conflict (closet_item_id, parser_code, raw_measurement_key) do nothing;

        if not exists (
            select 1
            from fitmatch_vnext.closet_item_source_measurements sm
            where sm.closet_item_id = closet_item_id_value
        ) then
            raise exception
                'Exact retailer observation receipt is required for linked Closet source snapshot';
        end if;
    end if;

    return result_value;
end
$function$;

-- Preserve the existing payload shape and add `source_measurements` only.
-- Renaming avoids copying a long, version-sensitive list implementation.
do $rename_list$
begin
    if to_regprocedure('fitmatch_vnext.list_closet_items_v1()') is null then
        alter function fitmatch_vnext.list_closet_items()
            rename to list_closet_items_v1;
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
    prior_items := fitmatch_vnext.list_closet_items_v1();
    return coalesce((
        select jsonb_agg(
            item || jsonb_build_object(
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
            )
            order by item ->> 'created_at' desc, item ->> 'id' desc
        )
        from jsonb_array_elements(prior_items) item
    ), '[]'::jsonb);
end
$function$;

create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.upsert_closet_item_for_swift(p_request)
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.list_closet_items()
$function$;

revoke all on function fitmatch_vnext.upsert_closet_item_for_swift(jsonb)
    from public, anon;
grant execute on function fitmatch_vnext.upsert_closet_item_for_swift(jsonb)
    to authenticated, service_role;
revoke all on function fitmatch_vnext.list_closet_items()
    from public, anon;
grant execute on function fitmatch_vnext.list_closet_items()
    to authenticated, service_role;
revoke all on function public.fitmatch_vnext_upsert_closet_item(jsonb)
    from public, anon;
grant execute on function public.fitmatch_vnext_upsert_closet_item(jsonb)
    to authenticated;
revoke all on function public.fitmatch_vnext_list_closet_items()
    from public, anon;
grant execute on function public.fitmatch_vnext_list_closet_items()
    to authenticated;

commit;
