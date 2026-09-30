-- Abort on concurrent deployed-contract changes; reviewed against this exact version.
DO $preflight$
BEGIN
 IF md5(pg_get_functiondef('fitmatch_vnext.apply_linked_closet_snapshot_for_swift(jsonb,uuid)'::regprocedure)) <> 'c6fac6011023c6150518dc4a3cf87e9f'
 OR md5(pg_get_functiondef('fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure)) <> '5b3ea037cae6fafdd164028f6620e1dd'
 THEN RAISE EXCEPTION 'Deployed contract changed since review'; END IF;
END
$preflight$;

-- Target hnkplvyegonlhumlejst: owner-authorized development environment.
-- Preserve existing SECURITY DEFINER checks, ACLs, identities and update contract.
CREATE OR REPLACE FUNCTION fitmatch_vnext.apply_linked_closet_snapshot_for_swift(p_request jsonb, p_existing_closet_item_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
    client_id uuid;
    linked_product_id uuid;
    linked_variant_id uuid;
    linked_size_id uuid;
    target_item fitmatch_vnext.closet_items%rowtype;
    product_row fitmatch_vnext.products%rowtype;
    item_id uuid;
    is_create boolean := p_existing_closet_item_id is null;
    request_hash text;
    canonical_payload jsonb;
    effective_measurement_context jsonb;
    measurement_payload jsonb;
    normalized_measurement_payload jsonb := '[]'::jsonb;
    override_payload jsonb;
    is_explicit_closet_classification boolean := false;
    effective_audience_code text;
    effective_category_code text;
    effective_garment_type_code text;
    effective_sleeve_length_code text;
    effective_lower_length_code text;
    effective_body_length_code text;
    effective_classification_source text;
    effective_classification_fingerprint text;
    effective_resolver_version text;
    requested_detail_code text;
    requested_satisfaction smallint;
    measurement_value jsonb;
    requested_measurement_code text;
    measurement_source text;
    measurement_unit text;
    measurement_text text;
    numeric_measurement numeric;
    requested_source_measurement_code text;
    effective_source_measurement_code text;
    owned_source_measurement_code text;
    canonical_source_identity_count integer;
    is_same_owned_size boolean := false;
    matches_owned_retailer_snapshot boolean := false;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;

    client_id := nullif(btrim(p_request ->> 'client_item_id'), '')::uuid;
    linked_product_id := nullif(btrim(p_request ->> 'product_id'), '')::uuid;
    linked_variant_id := nullif(btrim(p_request ->> 'product_variant_id'), '')::uuid;
    linked_size_id := nullif(btrim(p_request ->> 'product_size_id'), '')::uuid;
    requested_detail_code := lower(nullif(btrim(p_request ->> 'closet_detail_code'), ''));
    if client_id is null then
        raise exception 'client_item_id is required';
    end if;
    if linked_product_id is null or linked_variant_id is null or linked_size_id is null then
        raise exception 'Product-linked closet registration requires product, variant, and size';
    end if;
    if requested_detail_code is not null
       and (length(requested_detail_code) > 80
            or requested_detail_code !~ '^[a-z0-9_]+$') then
        raise exception 'Invalid Closet detail snapshot format';
    end if;

    -- Match the established linked upsert idempotency contract: reference
    -- selection is an independent atomic concern and must not make the same
    -- immutable registration retry look like a conflicting request.
    request_hash := encode(extensions.digest((p_request - 'is_reference')::text, 'sha256'), 'hex');
    if is_create then
        -- Preserve existing retry/idempotency semantics for a new linked row.
        perform pg_advisory_xact_lock(
            hashtextextended(caller_id::text || ':' || client_id::text, 0)
        );
        select * into target_item
        from fitmatch_vnext.closet_items ci
        where ci.user_id = caller_id
          and ci.client_item_id = client_id
        for update;
        if found then
            if target_item.request_fingerprint is distinct from request_hash then
                raise exception 'Idempotency conflict for client_item_id';
            end if;
            return jsonb_build_object(
                'item_id', target_item.id,
                'created', false,
                'idempotent', true
            );
        end if;
    else
        -- This ownership predicate is intentionally in the SECURITY DEFINER
        -- helper too; the public bridge must never be a cross-user update path.
        select * into target_item
        from fitmatch_vnext.closet_items ci
        where ci.id = p_existing_closet_item_id
          and ci.user_id = caller_id
          and ci.deleted_at is null
        for update;
        if not found then
            raise exception 'Closet item not found or not owned';
        end if;
        if target_item.client_item_id <> client_id then
            raise exception 'client_item_id does not match owned Closet item';
        end if;
    end if;

    -- Exact hierarchy validation stays mandatory.  No display label, colour,
    -- or inferred size identity participates in this branch.
    select * into product_row
    from fitmatch_vnext.products p
    where p.id = linked_product_id;
    if not found then
        raise exception 'Linked Product not found';
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
    is_same_owned_size := not is_create
        and target_item.product_id = linked_product_id
        and target_item.product_variant_id = linked_variant_id
        and target_item.product_size_id = linked_size_id;

    override_payload := p_request -> 'closet_classification_override';
    if override_payload is not null then
        if jsonb_typeof(override_payload) <> 'object' then
            raise exception 'closet_classification_override must be an object';
        end if;
        is_explicit_closet_classification := true;
        effective_audience_code := nullif(btrim(override_payload ->> 'audience_code'), '');
        effective_category_code := nullif(btrim(override_payload ->> 'category_code'), '');
        effective_garment_type_code := nullif(btrim(override_payload ->> 'garment_type_code'), '');
        effective_sleeve_length_code := nullif(btrim(override_payload ->> 'sleeve_length_code'), '');
        effective_lower_length_code := nullif(btrim(override_payload ->> 'lower_length_code'), '');
        effective_body_length_code := nullif(btrim(override_payload ->> 'body_length_code'), '');

        if effective_audience_code is null
           or effective_category_code is null
           or effective_garment_type_code is null then
            raise exception 'Explicit Closet classification is incomplete';
        end if;
        if not exists (
            select 1
            from fitmatch_vnext.garment_types gt
            where gt.garment_type_code = effective_garment_type_code
              and gt.category_code = effective_category_code
              and gt.is_active
        ) then
            raise exception 'Explicit Closet category and garment type mismatch';
        end if;
        if not coalesce((fitmatch_vnext.classification_tuple_validation(
            effective_garment_type_code,
            'SINGLE',
            effective_audience_code,
            effective_sleeve_length_code,
            effective_lower_length_code,
            effective_body_length_code
        ) ->> 'valid')::boolean, false) then
            raise exception 'Explicit Closet classification tuple is invalid';
        end if;
        effective_classification_source := 'USER_EXPLICIT';
        effective_classification_fingerprint := encode(extensions.digest(
            concat_ws('|', effective_audience_code, effective_category_code,
                effective_garment_type_code, effective_sleeve_length_code,
                effective_lower_length_code, effective_body_length_code),
            'sha256'
        ), 'hex');
        effective_resolver_version := 'simplefitmatch-closet-user-v1';
    else
        -- Automatic Closet classification retains the existing Product gate.
        -- The exception is strictly the explicit Closet tuple above; it never
        -- relaxes product identity or hierarchy validation.
        if product_row.classification_status <> 'CONFIRMED' then
            raise exception 'Product requires CONFIRMED classification without a Closet override';
        end if;
        if not coalesce((fitmatch_vnext.classification_tuple_validation(
            product_row.garment_type_code,
            product_row.product_structure_code,
            product_row.audience_code,
            product_row.sleeve_length_code,
            product_row.lower_length_code,
            product_row.body_length_code
        ) ->> 'valid')::boolean, false) then
            raise exception 'Product classification tuple is invalid';
        end if;
        effective_audience_code := product_row.audience_code;
        effective_garment_type_code := product_row.garment_type_code;
        effective_sleeve_length_code := product_row.sleeve_length_code;
        effective_lower_length_code := product_row.lower_length_code;
        effective_body_length_code := product_row.body_length_code;
        effective_classification_source := 'RETAILER_SNAPSHOT';
        effective_classification_fingerprint := product_row.input_fingerprint;
        effective_resolver_version := product_row.resolver_version;
    end if;

    -- The selected personal Closet category is authoritative for measurement
    -- resolution too. The context-aware resolver is the existing server
    -- mechanism; it preserves the global resolver for CONFIRMED products and
    -- never asks the client to guess a mapping from a label or display axis.
    effective_measurement_context := jsonb_build_object(
        'product_id', linked_product_id,
        'effective_source', case when is_explicit_closet_classification
            then 'USER_EXPLICIT' else 'GLOBAL_CONFIRMED' end,
        'category_code', effective_category_code,
        'garment_type_code', effective_garment_type_code
    );
    canonical_payload := fitmatch_vnext.canonical_measurements_for_size_with_context(
        linked_size_id,
        effective_measurement_context
    );
    if coalesce((canonical_payload ->> 'semantic_conflict_count')::integer, 0) > 0 then
        raise exception 'Canonical measurement semantics are ambiguous';
    end if;
    if jsonb_array_length(coalesce(canonical_payload -> 'measurements', '[]'::jsonb)) = 0
       and not (
           is_same_owned_size
           and exists (
               select 1
               from fitmatch_vnext.closet_item_measurements cm
               where cm.closet_item_id = target_item.id
           )
       ) then
        raise exception 'Verified canonical measurements are required';
    end if;

    -- Opt-in create contract: raw display facts remain in the product observation.
    -- Identity/ownership/group/semantic checks above remain mandatory. The request
    -- hash above still uses the original immutable request, preserving retries.
    if p_request -> 'use_server_measurements' = 'true'::jsonb then
        if not is_create then
            raise exception 'Server size snapshot is only supported for linked creation';
        end if;
        select coalesce(jsonb_agg(distinct jsonb_build_object(
            'fitmatch_measurement_code', m->>'fitmatch_measurement_code',
            'value', (m->>'value')::numeric,
            'unit_code', m->>'unit_code',
            'source_measurement_code', m->>'source_measurement_code',
            'raw_label', m->>'source_measurement_code',
            'value_source', 'RETAILER_SNAPSHOT'
        )), '[]'::jsonb) into measurement_payload
        from jsonb_array_elements(canonical_payload->'measurements') m;
    else
        measurement_payload := p_request -> 'measurements';
    end if;
    if jsonb_typeof(measurement_payload) <> 'array'
       or jsonb_array_length(measurement_payload) = 0 then
        raise exception 'Linked Closet snapshot requires canonical measurements';
    end if;
    if exists (
        select 1
        from (
            select measurement ->> 'fitmatch_measurement_code' as code,
                   count(*) as code_count
            from jsonb_array_elements(measurement_payload) as value(measurement)
            group by measurement ->> 'fitmatch_measurement_code'
        ) duplicates
        where duplicates.code is null or duplicates.code_count <> 1
    ) then
        raise exception 'Linked Closet snapshot has duplicate or missing measurement codes';
    end if;

    -- Validate and normalize the full snapshot before deleting any existing
    -- owned rows. A retailer row must exactly match the selected ProductSize's
    -- canonical fact; only USER_MANUAL may differ or add an active FitMatch
    -- definition. A known source identity may never be re-attached to an
    -- unrelated canonical row or selected size. An unregistered client raw
    -- code is not treated as source identity (this is how a user-added
    -- FitMatch definition remains source-null without a string heuristic).
    for measurement_value in
        select value from jsonb_array_elements(measurement_payload)
    loop
        requested_measurement_code := nullif(
            btrim(measurement_value ->> 'fitmatch_measurement_code'), ''
        );
        measurement_source := upper(coalesce(
            nullif(btrim(measurement_value ->> 'value_source'), ''),
            'RETAILER_SNAPSHOT'
        ));
        measurement_unit := lower(coalesce(
            nullif(btrim(measurement_value ->> 'unit_code'), ''),
            ''
        ));
        measurement_text := lower(coalesce(
            nullif(btrim(measurement_value ->> 'value'), ''),
            ''
        ));
        if measurement_text in ('nan', 'infinity', '+infinity', '-infinity') then
            raise exception 'Measurement value must be finite';
        end if;
        numeric_measurement := (measurement_value ->> 'value')::numeric;
        -- Preserve the existing Closet transport's bounded numeric contract;
        -- the client additionally applies the stricter selected FitMatch
        -- definition range before this RPC is reached.
        if numeric_measurement <= 0
           or numeric_measurement = 'NaN'::numeric
           or numeric_measurement > 1000 then
            raise exception 'Measurement value must be positive, finite, and in range';
        end if;
        if measurement_unit <> 'cm' then
            raise exception 'Measurement unit must be cm';
        end if;
        if measurement_source not in ('RETAILER_SNAPSHOT', 'USER_MANUAL') then
            raise exception 'Unsupported Closet measurement value_source';
        end if;
        if requested_measurement_code is null or not exists (
            select 1
            from fitmatch_vnext.fitmatch_measurements fm
            where fm.measurement_code = requested_measurement_code
              and fm.is_active
        ) then
            raise exception 'Invalid active FitMatch measurement code';
        end if;

        requested_source_measurement_code := nullif(
            btrim(measurement_value ->> 'source_measurement_code'), ''
        );
        effective_source_measurement_code := null;
        owned_source_measurement_code := null;
        matches_owned_retailer_snapshot := false;
        if is_same_owned_size then
            select coalesce(
                       cm.source_measurement_code_snapshot,
                       cm.source_measurement_code
                   )
            into owned_source_measurement_code
            from fitmatch_vnext.closet_item_measurements cm
            where cm.closet_item_id = target_item.id
              and cm.fitmatch_measurement_code = requested_measurement_code
            limit 1;

            select exists (
                select 1
                from fitmatch_vnext.closet_item_measurements cm
                where cm.closet_item_id = target_item.id
                  and cm.fitmatch_measurement_code = requested_measurement_code
                  and cm.value_source = 'RETAILER_SNAPSHOT'
                  and cm.value = numeric_measurement
                  and lower(cm.unit_code) = measurement_unit
                  and (
                      requested_source_measurement_code is null
                      or coalesce(
                          cm.source_measurement_code_snapshot,
                          cm.source_measurement_code
                      ) = requested_source_measurement_code
                  )
            ) into matches_owned_retailer_snapshot;
        end if;
        if requested_source_measurement_code is not null then
            if exists (
                select 1
                from jsonb_array_elements(canonical_payload -> 'measurements')
                    as value(canonical_measurement)
                where canonical_measurement ->> 'fitmatch_measurement_code'
                    = requested_measurement_code
                  and canonical_measurement ->> 'source_measurement_code'
                    = requested_source_measurement_code
            ) then
                effective_source_measurement_code := requested_source_measurement_code;
            elsif is_same_owned_size
                  and owned_source_measurement_code = requested_source_measurement_code then
                effective_source_measurement_code := owned_source_measurement_code;
            elsif exists (
                select 1
                from fitmatch_vnext.source_measurements sm
                where sm.source_measurement_code = requested_source_measurement_code
            ) then
                raise exception 'Source measurement identity does not belong to selected ProductSize canonical measurement';
            end if;
        end if;

        if measurement_source = 'RETAILER_SNAPSHOT'
           and not matches_owned_retailer_snapshot
           and not exists (
               select 1
               from jsonb_array_elements(canonical_payload -> 'measurements')
                   as value(canonical_measurement)
               where canonical_measurement ->> 'fitmatch_measurement_code'
                   = requested_measurement_code
                 and (canonical_measurement ->> 'value')::numeric = numeric_measurement
                 and lower(canonical_measurement ->> 'unit_code') = measurement_unit
           ) then
            raise exception 'Retailer snapshot does not match selected ProductSize';
        end if;

        -- If an older client omitted source identity (or a user-added local
        -- code is not a registered source identity), recover it only where the
        -- selected ProductSize has exactly one verified source for this
        -- canonical meaning. Never choose one arbitrarily.
        if effective_source_measurement_code is null then
            if is_same_owned_size and owned_source_measurement_code is not null then
                effective_source_measurement_code := owned_source_measurement_code;
            end if;
        end if;
        if effective_source_measurement_code is null
           and measurement_source = 'RETAILER_SNAPSHOT' then
            select count(distinct nullif(
                       canonical_measurement ->> 'source_measurement_code', ''
                   ))::integer,
                   min(nullif(
                       canonical_measurement ->> 'source_measurement_code', ''
                   ))
            into canonical_source_identity_count,
                 effective_source_measurement_code
            from jsonb_array_elements(canonical_payload -> 'measurements')
                as value(canonical_measurement)
            where canonical_measurement ->> 'fitmatch_measurement_code'
                = requested_measurement_code
              and (canonical_measurement ->> 'value')::numeric = numeric_measurement
              and lower(canonical_measurement ->> 'unit_code') = measurement_unit;

            if canonical_source_identity_count > 1 then
                raise exception 'Selected ProductSize canonical measurement has ambiguous source identity';
            end if;
        end if;
        if measurement_source = 'RETAILER_SNAPSHOT'
           and effective_source_measurement_code is null then
            raise exception 'Retailer snapshot is missing verified source identity';
        end if;

        normalized_measurement_payload := normalized_measurement_payload
            || jsonb_build_array(jsonb_set(
                measurement_value,
                '{source_measurement_code_snapshot}',
                coalesce(to_jsonb(effective_source_measurement_code), 'null'::jsonb),
                true
            ));
    end loop;

    -- A user override may replace a canonical fact, but it may not make a
    -- selected size chart silently disappear from this Closet-local snapshot.
    -- `canonical_measurements_for_size` can contain duplicate raw rows with
    -- the same resolved code, so compare the distinct canonical identity.
    if is_same_owned_size then
        if exists (
            select 1
            from fitmatch_vnext.closet_item_measurements cm
            where cm.closet_item_id = target_item.id
              and not exists (
                  select 1
                  from jsonb_array_elements(measurement_payload) as value(measurement)
                  where measurement ->> 'fitmatch_measurement_code'
                      = cm.fitmatch_measurement_code
              )
        ) then
            raise exception 'Linked Closet snapshot is missing an owned measurement';
        end if;
    elsif exists (
        select 1
        from (
            select distinct canonical_measurement ->> 'fitmatch_measurement_code' as code
            from jsonb_array_elements(canonical_payload -> 'measurements')
                as value(canonical_measurement)
        ) canonical_code
        where not exists (
            select 1
            from jsonb_array_elements(measurement_payload) as value(measurement)
            where measurement ->> 'fitmatch_measurement_code' = canonical_code.code
        )
    ) then
        raise exception 'Linked Closet snapshot is missing a selected ProductSize measurement';
    end if;

    -- An omitted rating means “not rated yet”, not a fabricated neutral 3.
    -- The existing schema's check explicitly permits NULL.  On update an
    -- omitted key preserves the existing rating; an explicit JSON null clears
    -- it, matching the nullable contract.
    if p_request ? 'satisfaction' then
        requested_satisfaction := nullif(
            btrim(p_request ->> 'satisfaction'), ''
        )::smallint;
    elsif is_create then
        requested_satisfaction := null;
    else
        requested_satisfaction := target_item.satisfaction;
    end if;
    if requested_satisfaction is not null
       and requested_satisfaction not between 1 and 5 then
        raise exception 'satisfaction must be between 1 and 5';
    end if;

    if is_create then
        insert into fitmatch_vnext.closet_items (
            user_id, client_item_id, product_id, product_variant_id, product_size_id,
            item_name, brand_name, image_url, product_url, size_label,
            audience_code, closet_detail_code_snapshot,
            garment_type_code, sleeve_length_code,
            lower_length_code, body_length_code, classification_source,
            measurement_mode, source_code_snapshot, is_reference,
            fit_preference_code, notes, satisfaction, request_fingerprint,
            classification_fingerprint, classification_resolver_version
        )
        select caller_id, client_id, linked_product_id, linked_variant_id, linked_size_id,
               product_row.product_name, product_row.brand_name, product_row.image_url,
               product_row.canonical_url, ps.size_label,
               effective_audience_code,
               coalesce(requested_detail_code, effective_garment_type_code),
               effective_garment_type_code,
               effective_sleeve_length_code, effective_lower_length_code,
               effective_body_length_code, effective_classification_source,
               'CANONICAL', null, false,
               p_request ->> 'fit_preference_code', p_request ->> 'notes',
               requested_satisfaction, request_hash,
               effective_classification_fingerprint, effective_resolver_version
        from fitmatch_vnext.product_sizes ps
        where ps.id = linked_size_id
        returning id into item_id;
    else
        item_id := target_item.id;
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
            audience_code = effective_audience_code,
            closet_detail_code_snapshot = coalesce(
                requested_detail_code,
                ci.closet_detail_code_snapshot,
                effective_garment_type_code
            ),
            garment_type_code = effective_garment_type_code,
            sleeve_length_code = effective_sleeve_length_code,
            lower_length_code = effective_lower_length_code,
            body_length_code = effective_body_length_code,
            classification_source = effective_classification_source,
            measurement_mode = 'CANONICAL',
            classification_fingerprint = effective_classification_fingerprint,
            classification_resolver_version = effective_resolver_version,
            fit_preference_code = case when p_request ? 'fit_preference_code'
                then nullif(btrim(p_request ->> 'fit_preference_code'), '')
                else ci.fit_preference_code end,
            notes = case when p_request ? 'notes' then p_request ->> 'notes' else ci.notes end,
            satisfaction = requested_satisfaction,
            request_fingerprint = request_hash,
            updated_at = now()
        where ci.id = item_id
          and ci.user_id = caller_id
          and ci.deleted_at is null;
        if not found then
            raise exception 'Closet item not found or not owned';
        end if;
    end if;

    delete from fitmatch_vnext.closet_item_measurements cm
    where cm.closet_item_id = item_id;
    for measurement_value in
        select value from jsonb_array_elements(normalized_measurement_payload)
    loop
        requested_measurement_code := measurement_value ->> 'fitmatch_measurement_code';
        measurement_source := upper(coalesce(
            nullif(btrim(measurement_value ->> 'value_source'), ''),
            'RETAILER_SNAPSHOT'
        ));
        insert into fitmatch_vnext.closet_item_measurements (
            closet_item_id, source_measurement_code, fitmatch_measurement_code,
            value, unit_code, value_source, raw_label_snapshot,
            source_measurement_code_snapshot
        ) values (
            item_id,
            null,
            requested_measurement_code,
            (measurement_value ->> 'value')::numeric,
            'cm',
            measurement_source,
            coalesce(
                nullif(btrim(measurement_value ->> 'raw_label'), ''),
                requested_measurement_code
            ),
            nullif(
                btrim(measurement_value ->> 'source_measurement_code_snapshot'),
                ''
            )
        );
    end loop;

    if is_create then
        return jsonb_build_object(
            'item_id', item_id,
            'created', true,
            'idempotent', false
        );
    end if;
    return jsonb_build_object(
        'closet_item_id', item_id,
        'updated', true,
        'product_id', linked_product_id,
        'product_variant_id', linked_variant_id,
        'product_size_id', linked_size_id
    );
end
$function$
;

CREATE OR REPLACE FUNCTION fitmatch_vnext.find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  eligible_value jsonb;
  eligible_size_ids_value jsonb;
  eligible_common_count integer;
  checked_variant record;
  eligibility_reason text;
  caller_id uuid := auth.uid();
  target_row fitmatch_vnext.products%rowtype;
  target_group jsonb;
  target_group_code text;
  closet_row fitmatch_vnext.closet_items%rowtype;
  closet_group jsonb;
  closet_group_code text;
  same_group_count integer;
  decision_value text;
  allowed_value boolean;
  reason_code_value text;
  reason_value text;
  item_value jsonb;
  candidates_value jsonb := '[]'::jsonb;
  blocked_value jsonb := '[]'::jsonb;
  all_items_value jsonb := '[]'::jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select * into target_row from fitmatch_vnext.products p
  where p.id=p_target_product_id;
  if not found then raise exception 'Target product not found'; end if;

  if p_target_variant_id is not null and not exists (
    select 1 from fitmatch_vnext.product_variants pv
    where pv.id=p_target_variant_id and pv.product_id=target_row.id
  ) then
    raise exception 'Target variant hierarchy mismatch';
  end if;

  target_group := fitmatch_vnext.product_comparison_group(target_row.id);
  target_group_code := target_group->>'group_code';

  select count(*) into same_group_count
  from fitmatch_vnext.closet_items ci
  where ci.user_id=caller_id and ci.deleted_at is null
    and ci.comparison_group_code=target_group_code;

  for closet_row in
    select * from fitmatch_vnext.closet_items ci
    where ci.user_id=caller_id and ci.deleted_at is null
    order by ci.is_reference desc,ci.updated_at desc,ci.id
  loop
    closet_group := fitmatch_vnext.closet_comparison_group(closet_row.id);
    closet_group_code := closet_group->>'group_code';

    if target_group_code is null then
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'COMPARISON_GROUP_REQUIRED';
      reason_value := '상품의 비교 그룹을 먼저 선택해 주세요.';
    elsif closet_group_code=target_group_code and closet_row.is_reference then
      decision_value := 'AUTOMATIC';
      allowed_value := true;
      reason_code_value := 'AUTOMATIC_MATCH';
      reason_value := '같은 그룹의 기준 옷입니다.';
    elsif closet_group_code=target_group_code then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '같은 그룹에서 직접 선택할 수 있습니다.';
    elsif (target_group_code='A' and closet_group_code='B')
       or (target_group_code='B' and closet_group_code='A') then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '상의와 아우터를 직접 선택해 비교할 수 있습니다.';
    else
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'INCOMPATIBLE_BODY_REGION';
      reason_value := '측정하는 신체 부위가 달라 비교할 수 없습니다.';
    end if;

    eligible_size_ids_value := '[]'::jsonb;
    eligible_common_count := 0;
    eligibility_reason := null;
    if allowed_value then
      for checked_variant in
        select pv.id from fitmatch_vnext.product_variants pv
        where pv.product_id=target_row.id
          and (p_target_variant_id is null or pv.id=p_target_variant_id)
        order by pv.sort_order,pv.id
      loop
        eligible_value := fitmatch_vnext.eligible_candidate_sizes(
          closet_row.id,target_row.id,checked_variant.id,decision_value<>'AUTOMATIC'
        );
        if coalesce((eligible_value->>'allowed')::boolean,false) then
          eligible_size_ids_value := eligible_size_ids_value ||
            coalesce(eligible_value->'authorized_candidate_product_size_ids','[]'::jsonb);
          eligible_common_count := greatest(eligible_common_count,
            jsonb_array_length(coalesce(
              eligible_value->'candidates'->0->'comparison_measurements','[]'::jsonb)));
        else
          eligibility_reason := coalesce(eligibility_reason,eligible_value->>'reason_code');
        end if;
      end loop;
      if jsonb_array_length(eligible_size_ids_value)=0 then
        allowed_value := false;
        decision_value := 'BLOCKED';
        reason_code_value := coalesce(eligibility_reason,'NO_ELIGIBLE_TARGET_SIZE');
        reason_value := '공통 실측 등 비교 조건을 충족하는 사이즈가 없습니다.';
      end if;
    end if;

    item_value := jsonb_build_object(
      'closet_item_id',closet_row.id,
      'item_name',closet_row.item_name,
      'size_label',closet_row.size_label,
      'product_id',closet_row.product_id,
      'variant_id',closet_row.product_variant_id,
      'product_size_id',closet_row.product_size_id,
      'is_current_reference',closet_row.is_reference,
      'decision',decision_value,
      'allowed',allowed_value,
      'mode',case when decision_value='AUTOMATIC' then 'AUTOMATIC'
                  when decision_value='MANUAL_EXTENDED' then 'MANUAL_EXTENDED'
                  else 'NONE' end,
      'manual_explicit_required',decision_value='MANUAL_EXTENDED',
      'reason_code',reason_code_value,
      'reason',reason_value,
      'common_measurement_count',eligible_common_count,
      'excluded_measurement_codes','[]'::jsonb,
      'required_measurement_codes','[]'::jsonb,
      'eligible_product_size_ids',case when allowed_value
        then eligible_size_ids_value else '[]'::jsonb end,
      'comparison_group',closet_group,
      'same_comparison_group',closet_group_code=target_group_code
    );

    all_items_value := all_items_value || jsonb_build_array(item_value);
    if allowed_value then
      candidates_value := candidates_value || jsonb_build_array(item_value);
    else
      blocked_value := blocked_value || jsonb_build_array(item_value);
    end if;
  end loop;

  return jsonb_build_object(
    'target_product_id',target_row.id,
    'target_variant_id',p_target_variant_id,
    'effective_classification',fitmatch_vnext.effective_target_classification(target_row.id),
    'comparison_group',target_group,
    'candidates',candidates_value,
    'blocked',blocked_value,
    'fallback_closet_items',case when same_group_count=0
      then all_items_value else '[]'::jsonb end,
    'candidate_count',jsonb_array_length(candidates_value),
    'blocked_count',jsonb_array_length(blocked_value),
    'same_group_count',same_group_count,
    'status',case when jsonb_array_length(candidates_value)>0
      then 'READY' else 'NO_REFERENCE_CANDIDATE' end,
    'selection_policy','CATEGORY_GROUP_ONLY',
    'measurements_used_for_candidate_selection',true,
    'reference_candidate_version','fitmatch-vnext-group-candidates-v1'
  );
end
$function$
;
