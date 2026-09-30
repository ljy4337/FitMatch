-- Linked Closet size edits must replace parent, canonical, and raw retailer
-- snapshots together.  This is a forward-only wrapper around the deployed
-- update owner; it preserves the group-aware upsert/list contracts.

begin;

do $rename_update_owner$
begin
    if to_regprocedure(
        'fitmatch_vnext.update_closet_item_snapshot_base(uuid,jsonb)'
    ) is null then
        if to_regprocedure('fitmatch_vnext.update_closet_item(uuid,jsonb)') is null then
            raise exception 'Missing Closet update preimage';
        end if;
        alter function fitmatch_vnext.update_closet_item(uuid,jsonb)
            rename to update_closet_item_snapshot_base;
    end if;
end
$rename_update_owner$;

create or replace function fitmatch_vnext.update_closet_item(
    p_closet_item_id uuid,
    p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    current_item fitmatch_vnext.closet_items%rowtype;
    result_value jsonb;
    result_item_id uuid;
    linked_product_id uuid;
    linked_variant_id uuid;
    linked_size_id uuid;
    source_observation_id_value uuid;
    source_code_value text;
    source_variant_key_value text;
    source_size_key_value text;
    garment_type_code_value text;
    category_code_value text;
    receipt_value fitmatch_vnext.product_ingestion_receipts%rowtype;
    source_measurement_count_value integer;
    base_request jsonb;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;

    select * into current_item
    from fitmatch_vnext.closet_items ci
    where ci.id = p_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null
    for update;
    if not found then
        raise exception 'Closet item not found or not owned';
    end if;

    linked_product_id := coalesce(
        nullif(btrim(p_request ->> 'product_id'), '')::uuid,
        current_item.product_id
    );
    linked_variant_id := coalesce(
        nullif(btrim(p_request ->> 'product_variant_id'), '')::uuid,
        current_item.product_variant_id
    );
    linked_size_id := coalesce(
        nullif(btrim(p_request ->> 'product_size_id'), '')::uuid,
        current_item.product_size_id
    );
    source_observation_id_value := nullif(
        btrim(p_request ->> 'source_observation_id'), ''
    )::uuid;

    -- The existing base owner remains responsible for manual rows and all
    -- metadata/classification semantics.  A linked size switch is the only
    -- path that additionally replaces immutable source rows.
    if current_item.product_id is null
       or linked_size_id is not distinct from current_item.product_size_id then
        if source_observation_id_value is not null then
            -- An ambiguous client retry arrives after the parent already says
            -- L. It is safe only when the immutable snapshot proves this is
            -- exactly the same completed L request; a new receipt on M→M is
            -- still rejected rather than silently replacing raw facts.
            if current_item.product_id is null
               or not exists (
                    select 1
                    from fitmatch_vnext.closet_item_source_measurement_snapshots ss
                    where ss.closet_item_id = p_closet_item_id
                      and ss.source_observation_id = source_observation_id_value
                      and ss.product_id = linked_product_id
                      and ss.product_variant_id = linked_variant_id
                      and ss.product_size_id = linked_size_id
               ) then
                raise exception 'Source observation is only valid for the exact completed linked product-size request';
            end if;
        end if;
        if current_item.product_id is not null
           and coalesce((p_request ->> 'use_server_measurements')::boolean, false) then
            -- Swift intentionally sends an empty server-measurement marker for
            -- a metadata-only linked edit.  Do not let the legacy owner treat
            -- that marker as an empty manual canonical replacement.
            base_request := p_request - 'measurements' - 'use_server_measurements'
                - 'source_observation_id';
        else
            base_request := p_request;
        end if;
        return fitmatch_vnext.update_closet_item_snapshot_base(
            p_closet_item_id,
            base_request
        );
    end if;

    if linked_product_id is null
       or linked_variant_id is null
       or linked_size_id is null
       or source_observation_id_value is null then
        raise exception 'Linked product-size changes require exact product, variant, size, and observation identities';
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
    where ps.id = linked_size_id
      and pv.id = linked_variant_id
      and p.id = linked_product_id;
    if not found then
        raise exception 'Product, variant, and size identities do not match';
    end if;

    select * into receipt_value
    from fitmatch_vnext.product_ingestion_receipts r
    where r.id = source_observation_id_value
      and r.product_id = linked_product_id
      and r.source_code = source_code_value
      and r.processing_status = 'PROCESSED';
    if not found then
        raise exception 'Exact retailer observation is unavailable';
    end if;

    if not exists (
        select 1
        from jsonb_array_elements(
            coalesce(receipt_value.retailer_facts -> 'variants', '[]'::jsonb)
        ) variant(value)
        cross join lateral jsonb_array_elements(
            coalesce(variant.value -> 'sizes', '[]'::jsonb)
        ) size(value)
        where btrim(variant.value ->> 'external_variant_id') = source_variant_key_value
          and btrim(size.value ->> 'size_identity') = source_size_key_value
    ) then
        raise exception 'Observation does not contain the selected variant and size';
    end if;

    -- The base owner keeps all parent and canonical measurement validation.
    -- Strip transport-only keys so its legacy empty-array branch cannot be
    -- mistaken for a manual canonical edit.
    base_request := p_request - 'measurements' - 'use_server_measurements'
        - 'source_observation_id';
    result_value := fitmatch_vnext.update_closet_item_snapshot_base(
        p_closet_item_id,
        base_request
    );
    result_item_id := nullif(result_value ->> 'closet_item_id', '')::uuid;
    if result_item_id is distinct from p_closet_item_id then
        raise exception 'Closet update returned a conflicting item identity';
    end if;

    -- Replacing raw rows inside this same function makes any raw/canonical
    -- failure roll back the parent and canonical update above as well.
    delete from fitmatch_vnext.closet_item_source_measurements sm
    where sm.closet_item_id = p_closet_item_id;
    delete from fitmatch_vnext.closet_item_source_measurement_snapshots ss
    where ss.closet_item_id = p_closet_item_id;

    insert into fitmatch_vnext.closet_item_source_measurements (
        closet_item_id, raw_measurement_key, source_code, parser_code,
        raw_code, raw_label, raw_value, raw_value_text, raw_unit_code,
        raw_representation, source_measurement_code, resolution_status,
        mapping_version, evidence_payload, source_observed_at
    )
    select
        p_closet_item_id,
        coalesce(
            nullif(btrim(measurement.value ->> 'measurement_identity'), ''),
            'receipt_measurement_' || measurement.ordinal::text
        ),
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
    cross join lateral jsonb_array_elements(
        coalesce(size.value -> 'measurements', '[]'::jsonb)
    ) with ordinality measurement(value, ordinal)
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
      and (
          nullif(btrim(measurement.value ->> 'measurement_identity'), '') is not null
          or nullif(btrim(measurement.value ->> 'raw_code'), '') is not null
          or nullif(btrim(measurement.value ->> 'raw_label'), '') is not null
      );

    get diagnostics source_measurement_count_value = row_count;
    if source_measurement_count_value = 0 then
        raise exception 'Exact retailer observation contains no selected-size source measurements';
    end if;

    insert into fitmatch_vnext.closet_item_source_measurement_snapshots (
        closet_item_id, source_observation_id, product_id, product_variant_id,
        product_size_id, source_measurement_count
    ) values (
        p_closet_item_id, source_observation_id_value, linked_product_id,
        linked_variant_id, linked_size_id, source_measurement_count_value
    );

    return result_value;
end
$function$;

-- SQL-language public bridges bind function OIDs at creation. Recreate both
-- bridges after the private rename so update/list traffic cannot retain the
-- old function OIDs and bypass this wrapper or comparison-group projection.
create or replace function public.fitmatch_vnext_update_closet_item(
    p_closet_item_id uuid,
    p_request jsonb
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
    request_value jsonb := p_request;
    result_value jsonb;
    product_id_value uuid;
    group_tuple jsonb;
    generated_group_tuple boolean := false;
    group_value jsonb;
begin
    -- Preserve the deployed public group authority wrapper. Only an exact
    -- observation-backed linked size switch is routed to the new private
    -- owner; all other paths retain their existing linked snapshot/manual
    -- behavior and the comparison-group projection.
    if request_value is not null
       and nullif(btrim(request_value ->> 'product_id'), '') is not null
       and request_value ? 'measurements' then
        product_id_value := (request_value ->> 'product_id')::uuid;
        if not request_value ? 'closet_classification_override' then
            group_tuple := fitmatch_vnext.comparison_group_tuple(
                product_id_value,
                nullif(btrim(request_value ->> 'comparison_group_code'), '')
            );
            if group_tuple is null then
                raise exception 'Comparison group selection required';
            end if;
            request_value := jsonb_set(
                request_value,
                '{closet_classification_override}',
                jsonb_build_object(
                    'audience_code', group_tuple ->> 'audience_code',
                    'category_code', group_tuple ->> 'category_code',
                    'garment_type_code', group_tuple ->> 'garment_type_code'
                ),
                true
            );
            generated_group_tuple := true;
        end if;

        -- Server-backed edits belong to the update owner, including same-size
        -- metadata edits. The legacy snapshot helper is creation-only.
        if nullif(btrim(request_value ->> 'source_observation_id'), '') is not null
           or coalesce((request_value ->> 'use_server_measurements')::boolean, false) then
            result_value := fitmatch_vnext.update_closet_item(
                p_closet_item_id,
                request_value
            );
        else
            result_value := fitmatch_vnext.apply_linked_closet_snapshot_for_swift(
                request_value,
                p_closet_item_id
            );
        end if;
    else
        result_value := fitmatch_vnext.update_closet_item(
            p_closet_item_id,
            request_value
        );
        perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
            p_closet_item_id,
            request_value
        );
    end if;

    if generated_group_tuple then
        update fitmatch_vnext.closet_items
           set classification_source = case when p_request ? 'comparison_group_code'
                    then 'USER_EDITED' else 'BACKEND' end,
               classification_resolver_version = 'comparison-group-v3',
               closet_detail_code_snapshot = null
         where id = p_closet_item_id
           and user_id = auth.uid();
    end if;

    group_value := fitmatch_vnext.apply_closet_comparison_group(
        p_closet_item_id,
        nullif(btrim(p_request ->> 'comparison_group_code'), ''),
        p_request ? 'comparison_group_code'
    );
    return result_value || jsonb_build_object('comparison_group', group_value);
end
$function$;

do $rename_list_owner$
begin
    if to_regprocedure('fitmatch_vnext.list_closet_items_snapshot_receipt_base()') is null then
        if to_regprocedure('fitmatch_vnext.list_closet_items()') is null then
            raise exception 'Missing Closet list preimage';
        end if;
        alter function fitmatch_vnext.list_closet_items()
            rename to list_closet_items_snapshot_receipt_base;
    end if;
end
$rename_list_owner$;

create or replace function fitmatch_vnext.list_closet_items()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    prior_items jsonb;
begin
    prior_items := fitmatch_vnext.list_closet_items_snapshot_receipt_base();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'source_measurement_snapshot', (
                select jsonb_build_object(
                    'source_observation_id', ss.source_observation_id,
                    'product_id', ss.product_id,
                    'product_variant_id', ss.product_variant_id,
                    'product_size_id', ss.product_size_id,
                    'source_measurement_count', ss.source_measurement_count
                )
                from fitmatch_vnext.closet_item_source_measurement_snapshots ss
                where ss.closet_item_id = (item ->> 'id')::uuid
            )
        ) order by ordinal)
        from jsonb_array_elements(coalesce(prior_items, '[]'::jsonb))
            with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
    result_value jsonb;
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

revoke all on function fitmatch_vnext.update_closet_item(uuid,jsonb)
    from public, anon;
grant execute on function fitmatch_vnext.update_closet_item(uuid,jsonb)
    to authenticated, service_role;
revoke all on function fitmatch_vnext.list_closet_items() from public, anon;
grant execute on function fitmatch_vnext.list_closet_items() to authenticated, service_role;
revoke all on function public.fitmatch_vnext_update_closet_item(uuid,jsonb)
    from public, anon;
grant execute on function public.fitmatch_vnext_update_closet_item(uuid,jsonb)
    to authenticated, service_role;
revoke all on function public.fitmatch_vnext_list_closet_items() from public, anon;
grant execute on function public.fitmatch_vnext_list_closet_items()
    to authenticated, service_role;

commit;
