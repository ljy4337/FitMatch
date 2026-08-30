-- fitmatch_vnext P0 closet and atomic reference APIs.

alter table fitmatch_vnext.closet_items
    add column if not exists request_fingerprint text,
    add column if not exists classification_fingerprint text,
    add column if not exists classification_resolver_version text;

create or replace function fitmatch_vnext.upsert_closet_item(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    client_id uuid;
    linked_product_id uuid;
    linked_variant_id uuid;
    linked_size_id uuid;
    request_hash text;
    existing_item fitmatch_vnext.closet_items%rowtype;
    product_row fitmatch_vnext.products%rowtype;
    item_id uuid;
    measurement_payload jsonb;
    m jsonb;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;

    client_id := (p_request ->> 'client_item_id')::uuid;
    linked_product_id := (p_request ->> 'product_id')::uuid;
    linked_variant_id := (p_request ->> 'product_variant_id')::uuid;
    linked_size_id := (p_request ->> 'product_size_id')::uuid;
    if client_id is null then raise exception 'client_item_id is required'; end if;

    request_hash := encode(extensions.digest((p_request - 'is_reference')::text,
        'sha256'), 'hex');
    perform pg_advisory_xact_lock(hashtextextended(caller_id::text || ':' || client_id::text, 0));

    select * into existing_item
    from fitmatch_vnext.closet_items
    where user_id = caller_id and client_item_id = client_id
    for update;
    if found then
        if existing_item.request_fingerprint is distinct from request_hash then
            raise exception 'Idempotency conflict for client_item_id';
        end if;
        return jsonb_build_object('item_id', existing_item.id, 'created', false,
            'idempotent', true);
    end if;

    if linked_product_id is not null then
        if linked_variant_id is null or linked_size_id is null then
            raise exception 'Product-linked closet registration requires product, variant, and size';
        end if;

        select * into product_row from fitmatch_vnext.products where id = linked_product_id;
        if not found or product_row.classification_status <> 'CONFIRMED' then
            raise exception 'Product requires CONFIRMED classification';
        end if;
        if not (fitmatch_vnext.classification_tuple_validation(
            product_row.garment_type_code, product_row.product_structure_code,
            product_row.audience_code, product_row.sleeve_length_code,
            product_row.lower_length_code, product_row.body_length_code
        ) ->> 'valid')::boolean then
            raise exception 'Product classification tuple is invalid';
        end if;
        if not exists (
            select 1 from fitmatch_vnext.product_variants pv
            join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
            where pv.id = linked_variant_id and pv.product_id = linked_product_id
              and ps.id = linked_size_id
        ) then
            raise exception 'Product, variant, and size hierarchy mismatch';
        end if;

        measurement_payload := fitmatch_vnext.canonical_measurements_for_size(linked_size_id);
        if (measurement_payload ->> 'semantic_conflict_count')::integer > 0 then
            raise exception 'Canonical measurement semantics are ambiguous';
        end if;
        if jsonb_array_length(measurement_payload -> 'measurements') = 0 then
            raise exception 'Verified canonical measurements are required';
        end if;

        insert into fitmatch_vnext.closet_items (
            user_id, client_item_id, product_id, product_variant_id, product_size_id,
            item_name, brand_name, image_url, product_url, size_label,
            audience_code, garment_type_code, sleeve_length_code,
            lower_length_code, body_length_code, classification_source,
            measurement_mode, source_code_snapshot, is_reference,
            fit_preference_code, notes, request_fingerprint,
            classification_fingerprint, classification_resolver_version
        )
        select caller_id, client_id, linked_product_id, linked_variant_id, linked_size_id,
               product_row.product_name, product_row.brand_name, product_row.image_url,
               product_row.canonical_url, ps.size_label,
               product_row.audience_code, product_row.garment_type_code,
               product_row.sleeve_length_code, product_row.lower_length_code,
               product_row.body_length_code, 'RETAILER_SNAPSHOT',
               'CANONICAL', null, false,
               p_request ->> 'fit_preference_code', p_request ->> 'notes', request_hash,
               product_row.input_fingerprint, product_row.resolver_version
        from fitmatch_vnext.product_sizes ps where ps.id = linked_size_id
        returning id into item_id;

        for m in select * from jsonb_array_elements(measurement_payload -> 'measurements')
        loop
            insert into fitmatch_vnext.closet_item_measurements (
                closet_item_id, source_measurement_code, fitmatch_measurement_code,
                value, unit_code, value_source, raw_label_snapshot
            ) values (
                item_id, null, m ->> 'fitmatch_measurement_code',
                (m ->> 'value')::numeric, m ->> 'unit_code',
                'RETAILER_SNAPSHOT', m ->> 'source_measurement_code'
            ) on conflict (closet_item_id, fitmatch_measurement_code)
                where fitmatch_measurement_code is not null
                do update set value = excluded.value, unit_code = excluded.unit_code,
                    value_source = excluded.value_source,
                    raw_label_snapshot = excluded.raw_label_snapshot;
        end loop;
    else
        if linked_variant_id is not null or linked_size_id is not null then
            raise exception 'Manual closet item cannot reference a variant or size';
        end if;
        if not (fitmatch_vnext.classification_tuple_validation(
            p_request ->> 'garment_type_code', 'SINGLE', p_request ->> 'audience_code',
            p_request ->> 'sleeve_length_code', p_request ->> 'lower_length_code',
            p_request ->> 'body_length_code'
        ) ->> 'valid')::boolean then
            raise exception 'Manual closet item requires an explicit valid tuple';
        end if;
        measurement_payload := coalesce(p_request -> 'measurements', '[]'::jsonb);
        if jsonb_typeof(measurement_payload) <> 'array'
           or jsonb_array_length(measurement_payload) = 0 then
            raise exception 'Manual closet item requires canonical measurements';
        end if;

        insert into fitmatch_vnext.closet_items (
            user_id, client_item_id, item_name, brand_name, image_url, product_url,
            size_label, audience_code, garment_type_code, sleeve_length_code,
            lower_length_code, body_length_code, classification_source,
            measurement_mode, source_code_snapshot, is_reference,
            fit_preference_code, notes, request_fingerprint,
            classification_fingerprint, classification_resolver_version
        ) values (
            caller_id, client_id, coalesce(nullif(p_request ->> 'item_name', ''), 'Manual item'),
            p_request ->> 'brand_name', p_request ->> 'image_url', p_request ->> 'product_url',
            p_request ->> 'size_label', p_request ->> 'audience_code',
            p_request ->> 'garment_type_code', p_request ->> 'sleeve_length_code',
            p_request ->> 'lower_length_code', p_request ->> 'body_length_code',
            'USER_EXPLICIT', 'CANONICAL', null, false,
            p_request ->> 'fit_preference_code', p_request ->> 'notes', request_hash,
            encode(extensions.digest(concat_ws('|', p_request ->> 'audience_code',
                p_request ->> 'garment_type_code', p_request ->> 'sleeve_length_code',
                p_request ->> 'lower_length_code', p_request ->> 'body_length_code'),
                'sha256'), 'hex'),
            'user-explicit-v1'
        ) returning id into item_id;

        for m in select * from jsonb_array_elements(measurement_payload)
        loop
            if (m ->> 'value')::numeric <= 0 or not exists (
                select 1 from fitmatch_vnext.fitmatch_measurements fm
                where fm.measurement_code = m ->> 'fitmatch_measurement_code' and fm.is_active
            ) then
                raise exception 'Invalid manual canonical measurement';
            end if;
            insert into fitmatch_vnext.closet_item_measurements (
                closet_item_id, source_measurement_code, fitmatch_measurement_code,
                value, unit_code, value_source, raw_label_snapshot
            ) values (
                item_id, null, m ->> 'fitmatch_measurement_code',
                (m ->> 'value')::numeric, coalesce(m ->> 'unit_code', 'cm'),
                'USER_MANUAL', m ->> 'raw_label'
            );
        end loop;
    end if;

    return jsonb_build_object('item_id', item_id, 'created', true, 'idempotent', false);
end
$function$;

create or replace function fitmatch_vnext.list_closet_items()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare caller_id uuid := auth.uid();
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', ci.id, 'client_item_id', ci.client_item_id,
            'product_id', ci.product_id, 'product_variant_id', ci.product_variant_id,
            'product_size_id', ci.product_size_id, 'item_name', ci.item_name,
            'brand_name', ci.brand_name, 'size_label', ci.size_label,
            'audience_code', ci.audience_code,
            'garment_type_code', ci.garment_type_code,
            'sleeve_length_code', ci.sleeve_length_code,
            'lower_length_code', ci.lower_length_code,
            'body_length_code', ci.body_length_code,
            'classification_source', ci.classification_source,
            'is_reference', ci.is_reference,
            'measurements', coalesce((select jsonb_agg(jsonb_build_object(
                'fitmatch_measurement_code', cm.fitmatch_measurement_code,
                'value', cm.value, 'unit_code', cm.unit_code,
                'value_source', cm.value_source
            ) order by cm.fitmatch_measurement_code)
            from fitmatch_vnext.closet_item_measurements cm
            where cm.closet_item_id = ci.id), '[]'::jsonb)
        ) order by ci.created_at desc, ci.id)
        from fitmatch_vnext.closet_items ci
        where ci.user_id = caller_id and ci.deleted_at is null
    ), '[]'::jsonb);
end
$function$;

create or replace function fitmatch_vnext.set_closet_reference(p_closet_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare caller_id uuid := auth.uid(); target fitmatch_vnext.closet_items%rowtype;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    select * into target from fitmatch_vnext.closet_items
    where id = p_closet_item_id and user_id = caller_id and deleted_at is null
    for update;
    if not found then raise exception 'Closet item not found or not owned'; end if;

    perform pg_advisory_xact_lock(hashtextextended(concat_ws('|', caller_id::text,
        target.garment_type_code, target.audience_code,
        coalesce(target.sleeve_length_code, '∅'), coalesce(target.lower_length_code, '∅'),
        coalesce(target.body_length_code, '∅')), 0));

    update fitmatch_vnext.closet_items ci set is_reference = false
    where ci.user_id = caller_id and ci.deleted_at is null and ci.is_reference
      and ci.garment_type_code = target.garment_type_code
      and ci.audience_code = target.audience_code
      and ci.sleeve_length_code is not distinct from target.sleeve_length_code
      and ci.lower_length_code is not distinct from target.lower_length_code
      and ci.body_length_code is not distinct from target.body_length_code
      and ci.id <> target.id;
    update fitmatch_vnext.closet_items set is_reference = true where id = target.id;

    return jsonb_build_object('closet_item_id', target.id, 'is_reference', true);
end
$function$;

revoke all on function fitmatch_vnext.upsert_closet_item(jsonb) from public, anon;
revoke all on function fitmatch_vnext.list_closet_items() from public, anon;
revoke all on function fitmatch_vnext.set_closet_reference(uuid) from public, anon;
grant execute on function fitmatch_vnext.upsert_closet_item(jsonb),
    fitmatch_vnext.list_closet_items(), fitmatch_vnext.set_closet_reference(uuid)
    to authenticated, service_role;
