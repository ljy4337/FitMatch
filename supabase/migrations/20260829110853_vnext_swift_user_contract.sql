-- FitMatch vNext Swift production integration contract.
--
-- Scope:
--   * complete the user-owned closet mutation surface (edit, soft delete,
--     reference unset, and personal classification override), and
--   * expose thin public-schema bridges for the non-public fitmatch_vnext API.
--
-- Global product classification, mappings, retailer measurements, and release
-- authority are never mutated by this migration.

alter table fitmatch_vnext.closet_items
    add column if not exists satisfaction smallint;

do $constraint$
begin
    if not exists (
        select 1
        from pg_catalog.pg_constraint c
        where c.conrelid = 'fitmatch_vnext.closet_items'::regclass
          and c.conname = 'closet_items_satisfaction_chk'
    ) then
        alter table fitmatch_vnext.closet_items
            add constraint closet_items_satisfaction_chk
            check (satisfaction is null or satisfaction between 1 and 5);
    end if;
end
$constraint$;

create or replace function fitmatch_vnext.list_closet_items()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;

    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', ci.id,
            'client_item_id', ci.client_item_id,
            'product_id', ci.product_id,
            'product_variant_id', ci.product_variant_id,
            'product_size_id', ci.product_size_id,
            'item_name', ci.item_name,
            'brand_name', ci.brand_name,
            'image_url', ci.image_url,
            'product_url', ci.product_url,
            'size_label', ci.size_label,
            'audience_code', ci.audience_code,
            'category_code', gt.category_code,
            'garment_type_code', ci.garment_type_code,
            'sleeve_length_code', ci.sleeve_length_code,
            'lower_length_code', ci.lower_length_code,
            'body_length_code', ci.body_length_code,
            'classification_source', ci.classification_source,
            'classification_fingerprint', ci.classification_fingerprint,
            'classification_resolver_version', ci.classification_resolver_version,
            'measurement_mode', ci.measurement_mode,
            'source_code', coalesce(p.source_code, ci.source_code_snapshot, 'manual'),
            'source_product_key', p.source_product_key,
            'source_category_path', p.source_extra ->> 'source_category_path',
            'is_reference', ci.is_reference,
            'fit_preference_code', ci.fit_preference_code,
            'notes', ci.notes,
            'satisfaction', ci.satisfaction,
            'created_at', ci.created_at,
            'updated_at', ci.updated_at,
            'measurements', coalesce((
                select jsonb_agg(jsonb_build_object(
                    'fitmatch_measurement_code', cm.fitmatch_measurement_code,
                    'value', cm.value,
                    'unit_code', cm.unit_code,
                    'value_source', cm.value_source,
                    'raw_label_snapshot', cm.raw_label_snapshot
                ) order by cm.fitmatch_measurement_code)
                from fitmatch_vnext.closet_item_measurements cm
                where cm.closet_item_id = ci.id
            ), '[]'::jsonb)
        ) order by ci.created_at desc, ci.id)
        from fitmatch_vnext.closet_items ci
        left join fitmatch_vnext.products p on p.id = ci.product_id
        left join fitmatch_vnext.garment_types gt
          on gt.garment_type_code = ci.garment_type_code
        where ci.user_id = caller_id and ci.deleted_at is null
    ), '[]'::jsonb);
end
$function$;

create or replace function fitmatch_vnext.upsert_closet_item_for_swift(
    p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    result_value jsonb;
    requested_satisfaction smallint;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;

    result_value := fitmatch_vnext.upsert_closet_item(p_request);
    if p_request ? 'satisfaction' then
        requested_satisfaction := (p_request ->> 'satisfaction')::smallint;
        update fitmatch_vnext.closet_items ci
        set satisfaction = requested_satisfaction,
            updated_at = case
                when ci.satisfaction is distinct from requested_satisfaction
                    then now()
                else ci.updated_at
            end
        where ci.id = (result_value ->> 'item_id')::uuid
          and ci.user_id = caller_id
          and ci.deleted_at is null;
        if not found then
            raise exception 'Closet item not found or not owned';
        end if;
    end if;

    return result_value;
end
$function$;

create or replace function fitmatch_vnext.get_product_runtime_for_swift(
    p_source_code text,
    p_source_product_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    runtime_value jsonb;
    category_value text;
    policy_value text;
begin
    runtime_value := fitmatch_vnext.get_product_runtime(
        p_source_code,
        p_source_product_key
    );
    if not coalesce((runtime_value ->> 'found')::boolean, false) then
        return runtime_value;
    end if;

    select gt.category_code, gt.comparison_policy_code
    into category_value, policy_value
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code =
          runtime_value -> 'product' ->> 'garment_type_code'
      and gt.is_active;

    return jsonb_set(
        runtime_value,
        '{product}',
        runtime_value -> 'product' || jsonb_build_object(
            'category_code', category_value,
            'comparison_policy_code', policy_value
        )
    );
end
$function$;

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
    linked_product fitmatch_vnext.products%rowtype;
    linked_product_id uuid;
    linked_variant_id uuid;
    linked_size_id uuid;
    measurement_payload jsonb;
    measurement_value jsonb;
    request_hash text;
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

    if linked_product_id is not null then
        if linked_variant_id is null or linked_size_id is null then
            raise exception 'Product-linked closet update requires product, variant, and size';
        end if;
        select * into linked_product
        from fitmatch_vnext.products p
        where p.id = linked_product_id;
        if not found or linked_product.classification_status <> 'CONFIRMED' then
            raise exception 'Product requires CONFIRMED classification';
        end if;
        if not coalesce((fitmatch_vnext.classification_tuple_validation(
            linked_product.garment_type_code,
            linked_product.product_structure_code,
            linked_product.audience_code,
            linked_product.sleeve_length_code,
            linked_product.lower_length_code,
            linked_product.body_length_code
        ) ->> 'valid')::boolean, false) then
            raise exception 'Product classification tuple is invalid';
        end if;
        if not exists (
            select 1
            from fitmatch_vnext.product_variants pv
            join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
            where pv.id = linked_variant_id
              and pv.product_id = linked_product_id
              and ps.id = linked_size_id
        ) then
            raise exception 'Product, variant, and size hierarchy mismatch';
        end if;
    else
        if linked_variant_id is not null or linked_size_id is not null then
            raise exception 'Manual closet item cannot reference a variant or size';
        end if;
        if not coalesce((fitmatch_vnext.classification_tuple_validation(
            p_request ->> 'garment_type_code',
            'SINGLE',
            coalesce(p_request ->> 'audience_code', current_item.audience_code),
            p_request ->> 'sleeve_length_code',
            p_request ->> 'lower_length_code',
            p_request ->> 'body_length_code'
        ) ->> 'valid')::boolean, false) then
            raise exception 'Manual closet edit requires an explicit valid tuple';
        end if;
    end if;

    request_hash := encode(extensions.digest(p_request::text, 'sha256'), 'hex');

    update fitmatch_vnext.closet_items ci
    set product_id = linked_product_id,
        product_variant_id = linked_variant_id,
        product_size_id = linked_size_id,
        item_name = coalesce(nullif(btrim(p_request ->> 'item_name'), ''), ci.item_name),
        brand_name = case when p_request ? 'brand_name'
            then nullif(btrim(p_request ->> 'brand_name'), '') else ci.brand_name end,
        image_url = case when p_request ? 'image_url'
            then nullif(btrim(p_request ->> 'image_url'), '') else ci.image_url end,
        product_url = case when p_request ? 'product_url'
            then nullif(btrim(p_request ->> 'product_url'), '') else ci.product_url end,
        size_label = coalesce(
            nullif(btrim(p_request ->> 'size_label'), ''),
            (select ps.size_label from fitmatch_vnext.product_sizes ps
             where ps.id = linked_size_id),
            ci.size_label
        ),
        audience_code = case when linked_product_id is not null
            then linked_product.audience_code
            else coalesce(nullif(btrim(p_request ->> 'audience_code'), ''), ci.audience_code)
        end,
        garment_type_code = case when linked_product_id is not null
            then linked_product.garment_type_code
            else p_request ->> 'garment_type_code'
        end,
        sleeve_length_code = case when linked_product_id is not null
            then linked_product.sleeve_length_code
            else nullif(btrim(p_request ->> 'sleeve_length_code'), '')
        end,
        lower_length_code = case when linked_product_id is not null
            then linked_product.lower_length_code
            else nullif(btrim(p_request ->> 'lower_length_code'), '')
        end,
        body_length_code = case when linked_product_id is not null
            then linked_product.body_length_code
            else nullif(btrim(p_request ->> 'body_length_code'), '')
        end,
        classification_source = case when linked_product_id is not null
            then 'RETAILER_SNAPSHOT' else 'USER_EDITED' end,
        classification_fingerprint = case when linked_product_id is not null
            then linked_product.input_fingerprint
            else encode(extensions.digest(concat_ws('|',
                coalesce(p_request ->> 'audience_code', ci.audience_code),
                p_request ->> 'garment_type_code',
                p_request ->> 'sleeve_length_code',
                p_request ->> 'lower_length_code',
                p_request ->> 'body_length_code'
            ), 'sha256'), 'hex')
        end,
        classification_resolver_version = case when linked_product_id is not null
            then linked_product.resolver_version else 'user-closet-edit-v1' end,
        fit_preference_code = case when p_request ? 'fit_preference_code'
            then nullif(btrim(p_request ->> 'fit_preference_code'), '')
            else ci.fit_preference_code end,
        notes = case when p_request ? 'notes' then p_request ->> 'notes' else ci.notes end,
        satisfaction = case when p_request ? 'satisfaction'
            then (p_request ->> 'satisfaction')::smallint else ci.satisfaction end,
        request_fingerprint = request_hash,
        updated_at = now()
    where ci.id = current_item.id;

    if p_request ? 'measurements' then
        measurement_payload := p_request -> 'measurements';
        if jsonb_typeof(measurement_payload) <> 'array'
           or jsonb_array_length(measurement_payload) = 0 then
            raise exception 'Edited canonical measurements must be a non-empty array';
        end if;
        delete from fitmatch_vnext.closet_item_measurements cm
        where cm.closet_item_id = current_item.id;

        for measurement_value in
            select value from jsonb_array_elements(measurement_payload)
        loop
            if coalesce((measurement_value ->> 'value')::numeric, 0) <= 0
               or not exists (
                    select 1 from fitmatch_vnext.fitmatch_measurements fm
                    where fm.measurement_code =
                          measurement_value ->> 'fitmatch_measurement_code'
                      and fm.is_active
               ) then
                raise exception 'Invalid edited canonical measurement';
            end if;
            insert into fitmatch_vnext.closet_item_measurements (
                closet_item_id,
                source_measurement_code,
                fitmatch_measurement_code,
                value,
                unit_code,
                value_source,
                raw_label_snapshot
            ) values (
                current_item.id,
                null,
                measurement_value ->> 'fitmatch_measurement_code',
                (measurement_value ->> 'value')::numeric,
                coalesce(nullif(measurement_value ->> 'unit_code', ''), 'cm'),
                'USER_MANUAL',
                measurement_value ->> 'raw_label'
            );
        end loop;
    elsif linked_size_id is distinct from current_item.product_size_id then
        measurement_payload := fitmatch_vnext.canonical_measurements_for_size(linked_size_id);
        if coalesce((measurement_payload ->> 'semantic_conflict_count')::integer, 0) > 0
           or jsonb_array_length(coalesce(
               measurement_payload -> 'measurements', '[]'::jsonb
           )) = 0 then
            raise exception 'Selected product size has no unambiguous canonical measurements';
        end if;
        delete from fitmatch_vnext.closet_item_measurements cm
        where cm.closet_item_id = current_item.id;
        for measurement_value in
            select value from jsonb_array_elements(measurement_payload -> 'measurements')
        loop
            insert into fitmatch_vnext.closet_item_measurements (
                closet_item_id,
                source_measurement_code,
                fitmatch_measurement_code,
                value,
                unit_code,
                value_source,
                raw_label_snapshot
            ) values (
                current_item.id,
                measurement_value ->> 'source_measurement_code',
                measurement_value ->> 'fitmatch_measurement_code',
                (measurement_value ->> 'value')::numeric,
                measurement_value ->> 'unit_code',
                'RETAILER_SNAPSHOT',
                measurement_value ->> 'source_measurement_code'
            );
        end loop;
    end if;

    return jsonb_build_object(
        'closet_item_id', current_item.id,
        'updated', true,
        'product_id', linked_product_id,
        'product_variant_id', linked_variant_id,
        'product_size_id', linked_size_id
    );
end
$function$;

create or replace function fitmatch_vnext.soft_delete_closet_item(
    p_closet_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    deleted_value timestamptz := now();
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    update fitmatch_vnext.closet_items ci
    set deleted_at = deleted_value,
        is_reference = false,
        updated_at = deleted_value
    where ci.id = p_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null;
    if not found then
        raise exception 'Closet item not found or not owned';
    end if;
    return jsonb_build_object(
        'closet_item_id', p_closet_item_id,
        'deleted_at', deleted_value
    );
end
$function$;

create or replace function fitmatch_vnext.unset_closet_reference(
    p_closet_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    update fitmatch_vnext.closet_items ci
    set is_reference = false,
        updated_at = now()
    where ci.id = p_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null;
    if not found then
        raise exception 'Closet item not found or not owned';
    end if;
    return jsonb_build_object(
        'closet_item_id', p_closet_item_id,
        'is_reference', false
    );
end
$function$;

create or replace function fitmatch_vnext.set_closet_classification_override(
    p_closet_item_id uuid,
    p_override jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    target fitmatch_vnext.closet_items%rowtype;
    override_hash text;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_override is null or jsonb_typeof(p_override) <> 'object' then
        raise exception 'Override must be a JSON object';
    end if;
    select * into target
    from fitmatch_vnext.closet_items ci
    where ci.id = p_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null
    for update;
    if not found then
        raise exception 'Closet item not found or not owned';
    end if;
    if not coalesce((fitmatch_vnext.classification_tuple_validation(
        p_override ->> 'garment_type_code',
        'SINGLE',
        p_override ->> 'audience_code',
        p_override ->> 'sleeve_length_code',
        p_override ->> 'lower_length_code',
        p_override ->> 'body_length_code'
    ) ->> 'valid')::boolean, false) then
        raise exception 'Personal classification override tuple is invalid';
    end if;

    override_hash := encode(extensions.digest(p_override::text, 'sha256'), 'hex');
    update fitmatch_vnext.closet_items ci
    set audience_code = p_override ->> 'audience_code',
        garment_type_code = p_override ->> 'garment_type_code',
        sleeve_length_code = nullif(btrim(p_override ->> 'sleeve_length_code'), ''),
        lower_length_code = nullif(btrim(p_override ->> 'lower_length_code'), ''),
        body_length_code = nullif(btrim(p_override ->> 'body_length_code'), ''),
        classification_source = 'USER_EDITED',
        classification_fingerprint = override_hash,
        classification_resolver_version = 'user-closet-override-v1',
        updated_at = now()
    where ci.id = target.id;

    return jsonb_build_object(
        'closet_item_id', target.id,
        'classification_source', 'USER_EDITED',
        'classification_fingerprint', override_hash
    );
end
$function$;

create or replace function fitmatch_vnext.clear_closet_classification_override(
    p_closet_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    target fitmatch_vnext.closet_items%rowtype;
    product_value fitmatch_vnext.products%rowtype;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    select * into target
    from fitmatch_vnext.closet_items ci
    where ci.id = p_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null
    for update;
    if not found then
        raise exception 'Closet item not found or not owned';
    end if;
    if target.product_id is null then
        raise exception 'Manual closet classification is the personal source of truth';
    end if;
    select * into product_value
    from fitmatch_vnext.products p
    where p.id = target.product_id;
    if not found or product_value.classification_status <> 'CONFIRMED' then
        raise exception 'Global product classification cannot restore this closet item';
    end if;

    update fitmatch_vnext.closet_items ci
    set audience_code = product_value.audience_code,
        garment_type_code = product_value.garment_type_code,
        sleeve_length_code = product_value.sleeve_length_code,
        lower_length_code = product_value.lower_length_code,
        body_length_code = product_value.body_length_code,
        classification_source = 'RETAILER_SNAPSHOT',
        classification_fingerprint = product_value.input_fingerprint,
        classification_resolver_version = product_value.resolver_version,
        updated_at = now()
    where ci.id = target.id;

    return jsonb_build_object(
        'closet_item_id', target.id,
        'classification_source', 'RETAILER_SNAPSHOT',
        'classification_fingerprint', product_value.input_fingerprint
    );
end
$function$;

revoke all on function fitmatch_vnext.get_product_runtime_for_swift(text,text)
    from public, anon;
revoke all on function fitmatch_vnext.list_closet_items()
    from public, anon;
revoke all on function fitmatch_vnext.upsert_closet_item_for_swift(jsonb)
    from public, anon;
revoke all on function fitmatch_vnext.update_closet_item(uuid,jsonb)
    from public, anon;
revoke all on function fitmatch_vnext.soft_delete_closet_item(uuid)
    from public, anon;
revoke all on function fitmatch_vnext.unset_closet_reference(uuid)
    from public, anon;
revoke all on function fitmatch_vnext.set_closet_classification_override(uuid,jsonb)
    from public, anon;
revoke all on function fitmatch_vnext.clear_closet_classification_override(uuid)
    from public, anon;
grant execute on function fitmatch_vnext.get_product_runtime_for_swift(text,text),
    fitmatch_vnext.list_closet_items(),
    fitmatch_vnext.upsert_closet_item_for_swift(jsonb),
    fitmatch_vnext.update_closet_item(uuid,jsonb),
    fitmatch_vnext.soft_delete_closet_item(uuid),
    fitmatch_vnext.unset_closet_reference(uuid),
    fitmatch_vnext.set_closet_classification_override(uuid,jsonb),
    fitmatch_vnext.clear_closet_classification_override(uuid)
    to authenticated, service_role;

-- Public Data API bridges. These contain no classification or comparison
-- policy; they delegate to the fitmatch_vnext authority with caller identity
-- intact. All are SECURITY INVOKER and explicitly deny anon/PUBLIC.

create or replace function public.fitmatch_vnext_get_product_runtime(
    p_source_code text,
    p_source_product_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.get_product_runtime_for_swift(
        p_source_code,
        p_source_product_key
    )
$function$;

create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.upsert_closet_item_for_swift(p_request)
$function$;

create or replace function public.fitmatch_vnext_update_closet_item(
    p_closet_item_id uuid,
    p_request jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.update_closet_item(p_closet_item_id, p_request)
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.list_closet_items()
$function$;

create or replace function public.fitmatch_vnext_set_closet_reference(
    p_closet_item_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.set_closet_reference(p_closet_item_id)
$function$;

create or replace function public.fitmatch_vnext_unset_closet_reference(
    p_closet_item_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.unset_closet_reference(p_closet_item_id)
$function$;

create or replace function public.fitmatch_vnext_delete_closet_item(
    p_closet_item_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.soft_delete_closet_item(p_closet_item_id)
$function$;

create or replace function public.fitmatch_vnext_set_closet_classification_override(
    p_closet_item_id uuid,
    p_override jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.set_closet_classification_override(
        p_closet_item_id, p_override
    )
$function$;

create or replace function public.fitmatch_vnext_clear_closet_classification_override(
    p_closet_item_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.clear_closet_classification_override(p_closet_item_id)
$function$;

create or replace function public.fitmatch_vnext_find_reference_candidates(
    p_target_product_id uuid,
    p_target_variant_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.find_reference_candidates(
        p_target_product_id, p_target_variant_id
    )
$function$;

create or replace function public.fitmatch_vnext_authorize_comparison(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_product_size_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.authorize_comparison(
        p_reference_closet_item_id,
        p_target_product_id,
        p_target_product_size_id,
        p_manual_explicit
    )
$function$;

create or replace function public.fitmatch_vnext_eligible_candidate_sizes(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_variant_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.eligible_candidate_sizes(
        p_reference_closet_item_id,
        p_target_product_id,
        p_target_variant_id,
        p_manual_explicit
    )
$function$;

create or replace function public.fitmatch_vnext_begin_comparison(p_request jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    result_value jsonb;
    comparison_value fitmatch_vnext.comparisons%rowtype;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    result_value := fitmatch_vnext.begin_comparison(p_request);
    select * into comparison_value
    from fitmatch_vnext.comparisons c
    where c.id = (result_value ->> 'comparison_id')::uuid
      and c.user_id = caller_id;
    if not found then raise exception 'Comparison snapshot is not owned'; end if;

    return result_value || jsonb_build_object(
        'snapshot', jsonb_build_object(
            'snapshot_schema_version', comparison_value.snapshot_schema_version,
            'reference_snapshot', comparison_value.reference_snapshot,
            'target_snapshot', comparison_value.target_snapshot,
            'authority_snapshot', comparison_value.authority_snapshot,
            'policy_snapshot', comparison_value.policy_snapshot,
            'authorization_snapshot', comparison_value.authorization_snapshot,
            'input_snapshot', comparison_value.input_snapshot,
            'excluded_measurement_codes',
                to_jsonb(comparison_value.excluded_measurement_codes)
        )
    );
end
$function$;

create or replace function public.fitmatch_vnext_complete_comparison(
    p_comparison_id uuid,
    p_result jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.complete_comparison(p_comparison_id, p_result)
$function$;

-- History remains immutable in fitmatch_vnext. These additive identity fields
-- let Swift rebuild its offline cache without consulting current retailer or
-- classification state. The historical comparison row is still the authority.
create or replace function fitmatch_vnext.comparison_history()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    return coalesce((
        select jsonb_agg(
            to_jsonb(c) || jsonb_build_object(
                'reference_client_item_id', ci.client_item_id,
                'target_source_product_key', p.source_product_key,
                'target_category_code', gt.category_code
            )
            order by c.created_at desc, c.id
        )
        from fitmatch_vnext.comparisons c
        left join fitmatch_vnext.closet_items ci
          on ci.id = c.reference_closet_item_id
         and ci.user_id = c.user_id
        left join fitmatch_vnext.products p
          on p.id = c.target_product_id
        left join fitmatch_vnext.garment_types gt
          on gt.garment_type_code = p.garment_type_code
        where c.user_id = caller_id
          and c.deleted_at is null
    ), '[]'::jsonb);
end
$function$;

create or replace function public.fitmatch_vnext_comparison_history()
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.comparison_history()
$function$;

revoke all on function fitmatch_vnext.comparison_history()
    from public, anon;
grant execute on function fitmatch_vnext.comparison_history()
    to authenticated, service_role;

do $grant_contract$
declare
    function_signature text;
begin
    foreach function_signature in array array[
        'public.fitmatch_vnext_get_product_runtime(text,text)',
        'public.fitmatch_vnext_upsert_closet_item(jsonb)',
        'public.fitmatch_vnext_update_closet_item(uuid,jsonb)',
        'public.fitmatch_vnext_list_closet_items()',
        'public.fitmatch_vnext_set_closet_reference(uuid)',
        'public.fitmatch_vnext_unset_closet_reference(uuid)',
        'public.fitmatch_vnext_delete_closet_item(uuid)',
        'public.fitmatch_vnext_set_closet_classification_override(uuid,jsonb)',
        'public.fitmatch_vnext_clear_closet_classification_override(uuid)',
        'public.fitmatch_vnext_find_reference_candidates(uuid,uuid)',
        'public.fitmatch_vnext_authorize_comparison(uuid,uuid,uuid,boolean)',
        'public.fitmatch_vnext_eligible_candidate_sizes(uuid,uuid,uuid,boolean)',
        'public.fitmatch_vnext_begin_comparison(jsonb)',
        'public.fitmatch_vnext_complete_comparison(uuid,jsonb)',
        'public.fitmatch_vnext_comparison_history()'
    ]
    loop
        execute format('revoke all on function %s from public, anon',
            function_signature);
        execute format('grant execute on function %s to authenticated, service_role',
            function_signature);
    end loop;
end
$grant_contract$;
;
