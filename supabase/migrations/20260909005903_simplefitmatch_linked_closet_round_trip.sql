-- Migration 20260909005903: Simple FitMatch V1 Goal 1 linked Closet round trip.
--
-- Simple FitMatch Phase 1 linked Closet round-trip contract.
--
-- The existing `closet_items.measurement_mode` and per-row
-- `closet_item_measurements.value_source` already express a Closet-local
-- mixed snapshot:
--   * RETAILER_SNAPSHOT: exact canonical fact for the selected ProductSize
--   * USER_MANUAL: one value measured or entered by the owning user
--
-- Production read-only inspection found that the current
-- `closet_item_measurements_one_semantic_chk` and
-- `validate_closet_measurement_mode` contract reject a canonical row that
-- also retains its verified `source_measurement_code`.  That makes it
-- impossible to round-trip an edited imported value with both its canonical
-- FitMatch meaning and its original parser identity.  This candidate adds a
-- separate canonical-row source snapshot field instead of deleting or
-- weakening that existing constraint: `source_measurement_code` keeps its
-- current SOURCE_NATIVE-only meaning and `source_measurement_code_snapshot`
-- stores the verified origin of a CANONICAL Closet-local snapshot row.
--
-- Validated against a disposable PostgreSQL preimage before DEV application.
-- This migration is additive and preserves legacy/manual public RPC routing.

begin;

-- Preserve the live mutually-exclusive semantic columns and trigger exactly
-- as they are. This additive field is the smallest representation that can
-- retain source provenance on an otherwise canonical Closet-local row.
alter table fitmatch_vnext.closet_item_measurements
    add column if not exists source_measurement_code_snapshot text;

create index if not exists closet_item_measurements_source_snapshot_idx
    on fitmatch_vnext.closet_item_measurements(source_measurement_code_snapshot)
    where source_measurement_code_snapshot is not null;

-- The vNext comparison tuple intentionally stores garment type and length
-- axes, but those values are not a lossless representation of the app's
-- user-selected Closet detail (several active details share one tuple). Keep
-- that personal taxonomy identity as a snapshot; it never changes Product
-- classification or participates in comparison policy.
alter table fitmatch_vnext.closet_items
    add column if not exists closet_detail_code_snapshot text;

do $closet_detail_snapshot_check$
begin
    if not exists (
        select 1
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = 'fitmatch_vnext'
          and t.relname = 'closet_items'
          and c.conname = 'closet_items_detail_snapshot_format_chk'
    ) then
        alter table fitmatch_vnext.closet_items
            add constraint closet_items_detail_snapshot_format_chk
            check (
                closet_detail_code_snapshot is null
                or (
                    length(closet_detail_code_snapshot) between 1 and 80
                    and closet_detail_code_snapshot ~ '^[a-z0-9_]+$'
                )
            );
    end if;
end
$closet_detail_snapshot_check$;

-- New Swift requests carry the exact app taxonomy detail separately from the
-- vNext comparison tuple. This narrow helper lets the established manual
-- upsert/update functions remain byte-for-byte untouched while persisting the
-- new optional field. Legacy requests omit the key and remain a no-op.
create or replace function fitmatch_vnext.set_closet_detail_snapshot_for_swift(
    p_closet_item_id uuid,
    p_request jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    requested_detail_code text;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;
    if not (p_request ? 'closet_detail_code') then
        return;
    end if;

    requested_detail_code := lower(nullif(
        btrim(p_request ->> 'closet_detail_code'),
        ''
    ));
    if requested_detail_code is null
       or length(requested_detail_code) > 80
       or requested_detail_code !~ '^[a-z0-9_]+$' then
        raise exception 'Invalid Closet detail snapshot format';
    end if;

    update fitmatch_vnext.closet_items ci
    set closet_detail_code_snapshot = requested_detail_code,
        updated_at = case
            when ci.closet_detail_code_snapshot is distinct from requested_detail_code
                then now()
            else ci.updated_at
        end
    where ci.id = p_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null;
    if not found then
        raise exception 'Closet item not found or not owned';
    end if;
end
$function$;

do $source_snapshot_fk$
begin
    if not exists (
        select 1
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = 'fitmatch_vnext'
          and t.relname = 'closet_item_measurements'
          and c.conname = 'closet_item_measurements_source_snapshot_fkey'
    ) then
        alter table fitmatch_vnext.closet_item_measurements
            add constraint closet_item_measurements_source_snapshot_fkey
            foreign key (source_measurement_code_snapshot)
            references fitmatch_vnext.source_measurements(source_measurement_code);
    end if;
end
$source_snapshot_fk$;

-- Add a distinct integrity trigger rather than replacing the existing
-- measurement-mode trigger. A source snapshot is permitted only on a
-- CANONICAL row linked to a Product of the same registered source.
create or replace function fitmatch_vnext.validate_closet_measurement_source_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    parent_mode text;
    parent_product_id uuid;
    linked_product_source text;
    snapshot_source text;
begin
    if new.source_measurement_code_snapshot is null then
        return new;
    end if;

    select ci.measurement_mode,
           ci.product_id,
           p.source_code
    into parent_mode,
         parent_product_id,
         linked_product_source
    from fitmatch_vnext.closet_items ci
    left join fitmatch_vnext.products p on p.id = ci.product_id
    where ci.id = new.closet_item_id;

    if parent_mode is null then
        raise exception 'closet item % does not exist', new.closet_item_id;
    end if;
    if parent_mode <> 'CANONICAL'
       or new.fitmatch_measurement_code is null
       or new.source_measurement_code is not null then
        raise exception 'source measurement snapshot requires a CANONICAL Closet measurement';
    end if;
    if parent_product_id is null or linked_product_source is null then
        raise exception 'source measurement snapshot requires a linked Product';
    end if;

    select sm.source_code into snapshot_source
    from fitmatch_vnext.source_measurements sm
    where sm.source_measurement_code = new.source_measurement_code_snapshot;

    if snapshot_source is distinct from linked_product_source then
        raise exception 'Closet source measurement snapshot % does not match linked Product source %',
            snapshot_source, linked_product_source;
    end if;

    return new;
end
$function$;

drop trigger if exists closet_item_measurements_validate_source_snapshot
    on fitmatch_vnext.closet_item_measurements;
create trigger closet_item_measurements_validate_source_snapshot
before insert or update of closet_item_id, source_measurement_code,
    fitmatch_measurement_code, source_measurement_code_snapshot
on fitmatch_vnext.closet_item_measurements
for each row execute function fitmatch_vnext.validate_closet_measurement_source_snapshot();

-- The helper is intentionally limited to product-linked requests which carry
-- the new `measurements` payload.  All legacy/manual mutation paths continue
-- to use their existing functions unchanged.
create or replace function fitmatch_vnext.apply_linked_closet_snapshot_for_swift(
    p_request jsonb,
    p_existing_closet_item_id uuid default null
)
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

    measurement_payload := p_request -> 'measurements';
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
$function$;

-- The existing list DTO already returns `value_source`.  Add the separate
-- source-measurement identity too, so hydration does not replace a retailer's
-- raw code with the canonical FitMatch code merely because the item is
-- linked. Legacy rows decode with null and keep their established behavior.
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
            'closet_detail_code', coalesce(
                ci.closet_detail_code_snapshot,
                ci.garment_type_code
            ),
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
                    -- Preserve the existing public DTO key. SOURCE_NATIVE
                    -- rows expose their semantic source code; CANONICAL rows
                    -- expose their immutable source snapshot instead.
                    'source_measurement_code', coalesce(
                        cm.source_measurement_code_snapshot,
                        cm.source_measurement_code
                    ),
                    'source_measurement_code_snapshot',
                        cm.source_measurement_code_snapshot,
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
        where ci.user_id = caller_id
          and ci.deleted_at is null
    ), '[]'::jsonb);
end
$function$;

-- Keep the authenticated public list bridge aligned with the enriched
-- internal DTO (including source_measurement_code). Existing deployments
-- already have this signature; recreating the thin bridge prevents a stale
-- body from hiding the per-row provenance source during hydration.
create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.list_closet_items()
$function$;

-- Route only the Phase 1 linked snapshot shape through the helper.  Manual
-- Closet registration and every existing legacy linked request keep the
-- already-shipped contract unchanged.
create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
    result_value jsonb;
begin
    if p_request is not null
       and nullif(btrim(p_request ->> 'product_id'), '') is not null
       and p_request ? 'measurements' then
        return fitmatch_vnext.apply_linked_closet_snapshot_for_swift(p_request);
    end if;
    result_value := fitmatch_vnext.upsert_closet_item_for_swift(p_request);
    perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
        (result_value ->> 'item_id')::uuid,
        p_request
    );
    return result_value;
end
$function$;

create or replace function public.fitmatch_vnext_update_closet_item(
    p_closet_item_id uuid,
    p_request jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
    result_value jsonb;
begin
    if p_request is not null
       and nullif(btrim(p_request ->> 'product_id'), '') is not null
       and p_request ? 'measurements' then
        return fitmatch_vnext.apply_linked_closet_snapshot_for_swift(
            p_request,
            p_closet_item_id
        );
    end if;
    result_value := fitmatch_vnext.update_closet_item(p_closet_item_id, p_request);
    perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
        p_closet_item_id,
        p_request
    );
    return result_value;
end
$function$;

revoke all on function fitmatch_vnext.set_closet_detail_snapshot_for_swift(uuid, jsonb)
    from public, anon;
grant execute on function fitmatch_vnext.set_closet_detail_snapshot_for_swift(uuid, jsonb)
    to authenticated, service_role;
revoke all on function fitmatch_vnext.apply_linked_closet_snapshot_for_swift(jsonb, uuid)
    from public, anon;
grant execute on function fitmatch_vnext.apply_linked_closet_snapshot_for_swift(jsonb, uuid)
    to authenticated, service_role;
revoke all on function public.fitmatch_vnext_upsert_closet_item(jsonb)
    from public, anon;
grant execute on function public.fitmatch_vnext_upsert_closet_item(jsonb)
    to authenticated, service_role;
revoke all on function public.fitmatch_vnext_update_closet_item(uuid, jsonb)
    from public, anon;
grant execute on function public.fitmatch_vnext_update_closet_item(uuid, jsonb)
    to authenticated, service_role;
revoke all on function public.fitmatch_vnext_list_closet_items()
    from public, anon;
grant execute on function public.fitmatch_vnext_list_closet_items()
    to authenticated, service_role;

commit;
