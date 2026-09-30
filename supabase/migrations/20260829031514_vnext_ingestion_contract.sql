-- Purpose: ingest previously unseen retailer products directly into fitmatch_vnext.
-- Data impact: additive receipt provenance plus idempotent upserts into the existing
-- products/signals/variants/sizes/raw-measurements/availability authorities.
-- Rollback: revoke/drop ingest_product_observation, then drop the receipt table and
-- the three additive raw-measurement provenance columns. Existing ingested domain
-- rows are intentionally not deleted by rollback.
-- Verification: call ingest_product_observation twice with the same JSON payload;
-- product/variant/size/measurement counts and IDs must remain stable.

create table if not exists fitmatch_vnext.product_ingestion_receipts (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null
        references fitmatch_vnext.products(id) on delete restrict,
    source_code text not null
        references fitmatch_vnext.sources(source_code) on update cascade on delete restrict,
    source_product_key text not null,
    payload_fingerprint text not null,
    retailer_facts jsonb not null check (jsonb_typeof(retailer_facts) = 'object'),
    observed_at timestamptz not null,
    actor_id_snapshot uuid,
    processing_status text not null
        check (processing_status in ('PROCESSING','PROCESSED','IGNORED_STALE')),
    result_summary jsonb not null default '{}'::jsonb
        check (jsonb_typeof(result_summary) = 'object'),
    submission_count integer not null default 1 check (submission_count >= 1),
    first_submitted_at timestamptz not null default now(),
    last_submitted_at timestamptz not null default now(),
    unique (source_code, source_product_key, payload_fingerprint)
);

create index if not exists product_ingestion_receipts_product_idx
    on fitmatch_vnext.product_ingestion_receipts (product_id, observed_at desc);

alter table fitmatch_vnext.product_ingestion_receipts enable row level security;
revoke all on table fitmatch_vnext.product_ingestion_receipts
    from public, anon, authenticated;
grant select, insert, update on table fitmatch_vnext.product_ingestion_receipts
    to service_role;

alter table fitmatch_vnext.product_size_measurements
    add column if not exists evidence_payload jsonb not null default '{}'::jsonb,
    add column if not exists evidence_fingerprint text,
    add column if not exists is_current boolean not null default true;

alter table fitmatch_vnext.product_size_measurements
    drop constraint if exists product_size_measurements_evidence_object_chk;
alter table fitmatch_vnext.product_size_measurements
    add constraint product_size_measurements_evidence_object_chk
    check (jsonb_typeof(evidence_payload) = 'object');

create index if not exists product_size_measurements_current_size_idx
    on fitmatch_vnext.product_size_measurements (product_size_id)
    where is_current;

create or replace function fitmatch_vnext.protect_product_ingestion_receipt()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if new.id is distinct from old.id
       or new.product_id is distinct from old.product_id
       or new.source_code is distinct from old.source_code
       or new.source_product_key is distinct from old.source_product_key
       or new.payload_fingerprint is distinct from old.payload_fingerprint
       or new.retailer_facts is distinct from old.retailer_facts
       or new.observed_at is distinct from old.observed_at
       or new.actor_id_snapshot is distinct from old.actor_id_snapshot
       or new.first_submitted_at is distinct from old.first_submitted_at then
        raise exception 'Ingestion receipt evidence is immutable';
    end if;
    return new;
end
$function$;

drop trigger if exists product_ingestion_receipts_protect_evidence
    on fitmatch_vnext.product_ingestion_receipts;
create trigger product_ingestion_receipts_protect_evidence
before update on fitmatch_vnext.product_ingestion_receipts
for each row execute function fitmatch_vnext.protect_product_ingestion_receipt();

-- Current-only raw rows make changed retailer observations replace the runtime
-- view without deleting historical raw evidence.
create or replace function fitmatch_vnext.canonical_measurements_for_size(
    p_product_size_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with raw_rows as (
    select m.*, p.source_code, p.garment_type_code, gt.category_code
    from fitmatch_vnext.product_size_measurements m
    join fitmatch_vnext.product_sizes ps on ps.id = m.product_size_id
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    left join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code
    where m.product_size_id = p_product_size_id
      and m.is_current
), decisions as (
    select r.*,
           fitmatch_vnext.resolve_measurement(
               r.source_code, r.parser_code, r.raw_code, r.raw_label,
               r.garment_type_code, r.category_code, r.raw_value
           ) decision
    from raw_rows r
), resolved as (
    select *, decision ->> 'fitmatch_measurement_code' canonical_code,
           (decision ->> 'canonical_value')::numeric canonical_value
    from decisions
    where decision ->> 'resolution_status' = 'RESOLVED'
), conflicts as (
    select canonical_code
    from resolved
    group by canonical_code
    having count(distinct canonical_value) > 1
)
select jsonb_build_object(
    'product_size_id', p_product_size_id,
    'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
    'measurements', coalesce((
        select jsonb_agg(
            jsonb_build_object(
                'product_size_measurement_id', r.id,
                'fitmatch_measurement_code', r.canonical_code,
                'value', r.canonical_value,
                'unit_code', r.decision ->> 'canonical_unit_code',
                'basis_code', r.decision ->> 'canonical_basis_code',
                'source_measurement_code', r.decision ->> 'source_measurement_code',
                'resolution_path', r.decision ->> 'resolution_path',
                'raw_evidence_fingerprint', r.evidence_fingerprint
            ) order by r.canonical_code, r.id
        )
        from resolved r
        where not exists (
            select 1 from conflicts c where c.canonical_code = r.canonical_code
        )
    ), '[]'::jsonb),
    'raw_measurement_count', (select count(*) from raw_rows),
    'unresolved_count', (select count(*) from decisions
        where decision ->> 'resolution_status' <> 'RESOLVED'),
    'semantic_conflict_count', (select count(*) from conflicts)
);
$function$;

create or replace function fitmatch_vnext.get_product_runtime(
    p_source_code text,
    p_source_product_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    product_row fitmatch_vnext.products%rowtype;
begin
    if caller_id is null
       and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Authentication required';
    end if;

    select * into product_row
    from fitmatch_vnext.products p
    where p.source_code = lower(btrim(p_source_code))
      and p.source_product_key = btrim(p_source_product_key);
    if not found then
        return jsonb_build_object('found', false);
    end if;

    return jsonb_build_object(
        'found', true,
        'product', jsonb_build_object(
            'id', product_row.id,
            'source_code', product_row.source_code,
            'source_product_key', product_row.source_product_key,
            'product_name', product_row.product_name,
            'brand_name', product_row.brand_name,
            'canonical_url', product_row.canonical_url,
            'image_url', product_row.image_url,
            'classification_status', product_row.classification_status,
            'product_structure_code', product_row.product_structure_code,
            'audience_code', product_row.audience_code,
            'garment_type_code', product_row.garment_type_code,
            'sleeve_length_code', product_row.sleeve_length_code,
            'lower_length_code', product_row.lower_length_code,
            'body_length_code', product_row.body_length_code,
            'resolver_version', product_row.resolver_version,
            'input_fingerprint', product_row.input_fingerprint,
            'latest_ingestion_fingerprint',
                product_row.source_extra ->> 'latest_ingestion_fingerprint'
        ),
        'readiness', fitmatch_vnext.product_readiness(product_row.id),
        'variants', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', pv.id,
                'source_variant_key', pv.source_variant_key,
                'variant_label', pv.variant_label,
                'color_name', pv.color_name,
                'sizes', coalesce((
                    select jsonb_agg(jsonb_build_object(
                        'id', ps.id,
                        'source_size_key', ps.source_size_key,
                        'size_label', ps.size_label,
                        'availability', coalesce((
                            select jsonb_build_object(
                                'status', o.availability_status,
                                'observed_at', o.observed_at,
                                'valid_until', o.valid_until,
                                'evidence_fingerprint', o.evidence_fingerprint
                            ) from fitmatch_vnext.size_availability_observations o
                            where o.product_size_id = ps.id
                            order by o.observed_at desc, o.id desc limit 1
                        ), jsonb_build_object('status', 'UNKNOWN')),
                        'canonical_measurements',
                            fitmatch_vnext.canonical_measurements_for_size(ps.id)
                    ) order by ps.sort_order, ps.id)
                    from fitmatch_vnext.product_sizes ps
                    where ps.variant_id = pv.id
                ), '[]'::jsonb)
            ) order by pv.sort_order, pv.id)
            from fitmatch_vnext.product_variants pv
            where pv.product_id = product_row.id
        ), '[]'::jsonb)
    );
end
$function$;

create or replace function fitmatch_vnext.ingest_product_observation(
    p_payload jsonb,
    p_actor_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    source_value text;
    product_key text;
    product_name_value text;
    audience_value text;
    structure_value text;
    observed_value timestamptz;
    payload_fingerprint_value text;
    product_id_value uuid;
    receipt_id_value uuid;
    existing_receipt fitmatch_vnext.product_ingestion_receipts%rowtype;
    existing_product fitmatch_vnext.products%rowtype;
    signal_id_value uuid;
    variant_id_value uuid;
    size_id_value uuid;
    variant_value jsonb;
    size_value jsonb;
    measurement_value jsonb;
    signal_value jsonb;
    category_value text;
    category_index integer := 0;
    parser_value text;
    default_parser_value text;
    raw_key_value text;
    raw_code_value text;
    raw_label_value text;
    raw_value_value numeric;
    measurement_fingerprint_value text;
    availability_value text;
    valid_until_value timestamptz;
    classification_value jsonb;
    readiness_value jsonb;
    runtime_value jsonb;
    raw_measurement_count_value integer := 0;
    signal_order_value integer := 0;
begin
    if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'service_role is required for global ingestion';
    end if;
    if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
        raise exception 'Retailer observation payload must be a JSON object';
    end if;

    source_value := lower(btrim(p_payload ->> 'source'));
    product_key := btrim(p_payload ->> 'external_product_id');
    product_name_value := btrim(p_payload ->> 'product_name');
    if source_value is null or source_value = ''
       or product_key is null or product_key = ''
       or product_name_value is null or product_name_value = '' then
        raise exception 'source, external_product_id, and product_name are required';
    end if;
    if length(source_value) > 64 or length(product_key) > 256
       or length(product_name_value) > 1000 then
        raise exception 'Retailer observation identity exceeds contract limits';
    end if;
    if not exists (
        select 1 from fitmatch_vnext.sources s
        where s.source_code = source_value and s.is_active
    ) then
        raise exception 'Unsupported or inactive source';
    end if;

    begin
        observed_value := (p_payload ->> 'observed_at')::timestamptz;
    exception when others then
        raise exception 'observed_at must be an ISO-8601 timestamp';
    end;
    if observed_value is null or observed_value > now() + interval '5 minutes' then
        raise exception 'observed_at is required and cannot be in the future';
    end if;

    if jsonb_typeof(coalesce(p_payload -> 'variants', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_payload -> 'variants', '[]'::jsonb)) > 100 then
        raise exception 'variants must be an array with at most 100 entries';
    end if;
    if jsonb_typeof(coalesce(p_payload -> 'source_category_codes', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_payload -> 'source_category_codes', '[]'::jsonb)) > 32 then
        raise exception 'source_category_codes must be an array with at most 32 entries';
    end if;
    if jsonb_typeof(coalesce(p_payload -> 'classification_signals', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_payload -> 'classification_signals', '[]'::jsonb)) > 64 then
        raise exception 'classification_signals must be an array with at most 64 entries';
    end if;
    if jsonb_typeof(coalesce(p_payload -> 'raw_payload', '{}'::jsonb)) <> 'object'
       or jsonb_typeof(coalesce(p_payload -> 'structured_facts', '{}'::jsonb)) <> 'object' then
        raise exception 'raw_payload and structured_facts must be JSON objects';
    end if;

    audience_value := upper(btrim(coalesce(p_payload ->> 'audience', 'UNKNOWN')));
    audience_value := case audience_value
        when 'M' then 'MEN' when 'MAN' then 'MEN' when 'MALE' then 'MEN'
        when 'W' then 'WOMEN' when 'WOMAN' then 'WOMEN' when 'FEMALE' then 'WOMEN'
        when 'U' then 'UNISEX' when 'COMMON' then 'UNISEX' when 'M,W' then 'UNISEX'
        when 'KID' then 'KIDS'
        when 'MEN' then 'MEN' when 'WOMEN' then 'WOMEN' when 'UNISEX' then 'UNISEX'
        when 'KIDS' then 'KIDS' when 'BABY' then 'BABY'
        else 'UNKNOWN' end;

    structure_value := upper(btrim(coalesce(
        p_payload ->> 'product_structure',
        p_payload -> 'structured_facts' ->> 'product_structure',
        'UNKNOWN'
    )));
    if structure_value not in ('SINGLE','SET','MULTIPACK','UNKNOWN') then
        structure_value := 'UNKNOWN';
    end if;

    payload_fingerprint_value := encode(
        extensions.digest(p_payload::text, 'sha256'), 'hex'
    );
    perform pg_advisory_xact_lock(hashtextextended(
        source_value || ':' || product_key, 0
    ));

    select * into existing_receipt
    from fitmatch_vnext.product_ingestion_receipts r
    where r.source_code = source_value
      and r.source_product_key = product_key
      and r.payload_fingerprint = payload_fingerprint_value
    for update;
    if found then
        update fitmatch_vnext.product_ingestion_receipts
        set submission_count = submission_count + 1,
            last_submitted_at = now()
        where id = existing_receipt.id;
        runtime_value := fitmatch_vnext.get_product_runtime(source_value, product_key);
        return jsonb_build_object(
            'observation', jsonb_build_object(
                'observation_id', existing_receipt.id,
                'status', 'accepted',
                'raw_measurement_count', coalesce(
                    (existing_receipt.result_summary ->> 'raw_measurement_count')::integer, 0
                ),
                'idempotent', true,
                'payload_fingerprint', payload_fingerprint_value
            ),
            'processing', jsonb_build_object(
                'observation_id', existing_receipt.id,
                'status', lower(existing_receipt.processing_status),
                'product_id', existing_receipt.product_id,
                'idempotent', true
            ),
            'runtime', runtime_value
        );
    end if;

    select * into existing_product
    from fitmatch_vnext.products p
    where p.source_code = source_value and p.source_product_key = product_key
    for update;

    if found and observed_value < existing_product.last_seen_at then
        insert into fitmatch_vnext.product_ingestion_receipts (
            product_id, source_code, source_product_key, payload_fingerprint,
            retailer_facts, observed_at, actor_id_snapshot, processing_status,
            result_summary
        ) values (
            existing_product.id, source_value, product_key, payload_fingerprint_value,
            p_payload, observed_value, p_actor_id, 'IGNORED_STALE',
            jsonb_build_object('reason', 'Older than current product evidence',
                'raw_measurement_count', 0)
        ) returning id into receipt_id_value;
        runtime_value := fitmatch_vnext.get_product_runtime(source_value, product_key);
        return jsonb_build_object(
            'observation', jsonb_build_object(
                'observation_id', receipt_id_value, 'status', 'ignored_stale',
                'raw_measurement_count', 0, 'idempotent', false,
                'payload_fingerprint', payload_fingerprint_value
            ),
            'processing', jsonb_build_object(
                'observation_id', receipt_id_value, 'status', 'ignored_stale',
                'product_id', existing_product.id, 'idempotent', false
            ),
            'runtime', runtime_value
        );
    end if;

    if existing_product.id is null then
        insert into fitmatch_vnext.products (
            source_code, source_product_key, product_name, brand_name,
            canonical_url, image_url, audience_code, product_structure_code,
            classification_status, classification_source, source_status,
            source_extra, first_seen_at, last_seen_at, last_fetched_at
        ) values (
            source_value, product_key, product_name_value,
            nullif(btrim(coalesce(p_payload ->> 'brand_name',
                p_payload -> 'raw_payload' ->> 'brand_name')), ''),
            nullif(btrim(p_payload ->> 'canonical_url'), ''),
            nullif(btrim(p_payload ->> 'image_url'), ''),
            audience_value, structure_value, 'REVIEW_REQUIRED', 'BACKEND',
            case upper(btrim(coalesce(p_payload ->> 'source_status', 'UNKNOWN')))
                when 'ACTIVE' then 'ACTIVE' when 'SOLD_OUT' then 'SOLD_OUT'
                when 'DELETED' then 'DELETED' else 'UNKNOWN' end,
            jsonb_build_object(
                'latest_ingestion_fingerprint', payload_fingerprint_value,
                'latest_ingestion_observed_at', observed_value,
                'source_category_path', p_payload ->> 'source_category_path',
                'structured_facts', coalesce(p_payload -> 'structured_facts', '{}'::jsonb)
            ),
            observed_value, observed_value, observed_value
        ) returning id into product_id_value;
    else
        product_id_value := existing_product.id;
        update fitmatch_vnext.products
        set product_name = product_name_value,
            brand_name = coalesce(nullif(btrim(coalesce(p_payload ->> 'brand_name',
                p_payload -> 'raw_payload' ->> 'brand_name')), ''), brand_name),
            canonical_url = coalesce(nullif(btrim(p_payload ->> 'canonical_url'), ''), canonical_url),
            image_url = coalesce(nullif(btrim(p_payload ->> 'image_url'), ''), image_url),
            audience_code = audience_value,
            product_structure_code = structure_value,
            classification_status = 'REVIEW_REQUIRED',
            classification_source = 'BACKEND',
            garment_type_code = null,
            sleeve_length_code = null,
            lower_length_code = null,
            body_length_code = null,
            classified_at = null,
            primary_source_signal_id = null,
            classification_mapping_id = null,
            resolution_mode = null,
            resolver_version = null,
            input_fingerprint = null,
            evidence_fingerprint = null,
            classification_evidence = '{}'::jsonb,
            classification_reason = 'Awaiting deterministic replay after new retailer evidence',
            source_status = case upper(btrim(coalesce(p_payload ->> 'source_status', 'UNKNOWN')))
                when 'ACTIVE' then 'ACTIVE' when 'SOLD_OUT' then 'SOLD_OUT'
                when 'DELETED' then 'DELETED' else source_status end,
            source_extra = source_extra || jsonb_build_object(
                'latest_ingestion_fingerprint', payload_fingerprint_value,
                'latest_ingestion_observed_at', observed_value,
                'source_category_path', p_payload ->> 'source_category_path',
                'structured_facts', coalesce(p_payload -> 'structured_facts', '{}'::jsonb)
            ),
            last_seen_at = observed_value,
            last_fetched_at = observed_value
        where id = product_id_value;
    end if;

    insert into fitmatch_vnext.product_ingestion_receipts (
        product_id, source_code, source_product_key, payload_fingerprint,
        retailer_facts, observed_at, actor_id_snapshot, processing_status
    ) values (
        product_id_value, source_value, product_key, payload_fingerprint_value,
        p_payload, observed_value, p_actor_id, 'PROCESSING'
    ) returning id into receipt_id_value;

    insert into fitmatch_vnext.source_identifiers (
        source_code, entity_scope, product_id, identifier_type_code, identifier_value
    ) values (
        source_value, 'PRODUCT', product_id_value, 'source_product_key', product_key
    ) on conflict do nothing;

    delete from fitmatch_vnext.product_classification_signals
    where product_id = product_id_value;

    -- Product-exact is observed evidence. It only classifies when an existing
    -- active, verified mapping grants that exact signal authority.
    select s.id into signal_id_value
    from fitmatch_vnext.source_classification_signals s
    where s.source_code = source_value and s.signal_kind = 'PRODUCT_EXACT'
      and s.external_key = product_key
      and s.audience_code in (audience_value, 'ANY')
    order by (s.audience_code = audience_value) desc, s.id
    limit 1;
    if signal_id_value is null then
        insert into fitmatch_vnext.source_classification_signals (
            source_code, signal_kind, external_key, external_id, audience_code,
            signal_name, signal_path, is_active, first_seen_at, last_seen_at
        ) values (
            source_value, 'PRODUCT_EXACT', product_key, product_key, audience_value,
            product_name_value, 'product:' || product_key, true,
            observed_value, observed_value
        ) returning id into signal_id_value;
    else
        update fitmatch_vnext.source_classification_signals
        set last_seen_at = greatest(last_seen_at, observed_value),
            signal_name = coalesce(signal_name, product_name_value),
            signal_path = coalesce(signal_path, 'product:' || product_key)
        where id = signal_id_value;
    end if;
    insert into fitmatch_vnext.product_classification_signals (
        product_id, source_signal_id, is_primary, evidence_order, observed_at
    ) values (product_id_value, signal_id_value, false, signal_order_value, observed_value);

    if structure_value <> 'UNKNOWN' then
        signal_order_value := signal_order_value + 1;
        signal_id_value := null;
        select s.id into signal_id_value
        from fitmatch_vnext.source_classification_signals s
        where s.source_code = source_value and s.signal_kind = 'PRODUCT_STRUCTURE'
          and s.external_key = structure_value
          and s.audience_code in (audience_value, 'ANY')
        order by (s.audience_code = audience_value) desc, s.id
        limit 1;
        if signal_id_value is null then
            insert into fitmatch_vnext.source_classification_signals (
                source_code, signal_kind, external_key, external_id, audience_code,
                signal_name, signal_path, is_active, first_seen_at, last_seen_at
            ) values (
                source_value, 'PRODUCT_STRUCTURE', structure_value, structure_value,
                audience_value, structure_value, 'structure:' || structure_value,
                true, observed_value, observed_value
            ) returning id into signal_id_value;
        else
            update fitmatch_vnext.source_classification_signals
            set last_seen_at = greatest(last_seen_at, observed_value)
            where id = signal_id_value;
        end if;
        insert into fitmatch_vnext.product_classification_signals (
            product_id, source_signal_id, is_primary, evidence_order, observed_at
        ) values (product_id_value, signal_id_value, false,
            signal_order_value, observed_value)
        on conflict (product_id, source_signal_id) do update
        set evidence_order = excluded.evidence_order,
            observed_at = excluded.observed_at;
    end if;

    for category_value in
        select btrim(value)
        from jsonb_array_elements_text(
            coalesce(p_payload -> 'source_category_codes', '[]'::jsonb)
        ) with ordinality c(value, ordinal)
        where btrim(value) <> ''
        order by ordinal
    loop
        category_index := category_index + 1;
        signal_order_value := signal_order_value + 1;
        signal_id_value := null;
        select s.id into signal_id_value
        from fitmatch_vnext.source_classification_signals s
        where s.source_code = source_value and s.signal_kind = 'CATEGORY'
          and s.external_key = category_value
          and s.audience_code in (audience_value, 'ANY')
        order by (s.audience_code = audience_value) desc, s.id
        limit 1;
        if signal_id_value is null then
            insert into fitmatch_vnext.source_classification_signals (
                source_code, signal_kind, external_key, external_id, audience_code,
                signal_name, signal_path, is_active, first_seen_at, last_seen_at
            ) values (
                source_value, 'CATEGORY', category_value, category_value, audience_value,
                null, nullif(btrim(p_payload ->> 'source_category_path'), ''),
                true, observed_value, observed_value
            ) returning id into signal_id_value;
        else
            update fitmatch_vnext.source_classification_signals
            set last_seen_at = greatest(last_seen_at, observed_value),
                signal_path = coalesce(signal_path,
                    nullif(btrim(p_payload ->> 'source_category_path'), ''))
            where id = signal_id_value;
        end if;
        insert into fitmatch_vnext.product_classification_signals (
            product_id, source_signal_id, is_primary, evidence_order, observed_at
        ) values (product_id_value, signal_id_value, false,
            signal_order_value, observed_value)
        on conflict (product_id, source_signal_id) do update
        set evidence_order = excluded.evidence_order,
            observed_at = excluded.observed_at;
    end loop;

    for signal_value in
        select value from jsonb_array_elements(
            coalesce(p_payload -> 'classification_signals', '[]'::jsonb)
        )
    loop
        if jsonb_typeof(signal_value) <> 'object'
           or upper(btrim(signal_value ->> 'kind')) not in (
               'PRODUCT_EXACT','PRODUCT_STRUCTURE','PRODUCT_TYPE',
               'SUBFAMILY','FAMILY','CATEGORY','SECTION','SIZE_TYPE'
           )
           or nullif(btrim(coalesce(signal_value ->> 'external_key',
                signal_value ->> 'key')), '') is null then
            raise exception 'Invalid explicit classification signal';
        end if;
        signal_order_value := signal_order_value + 1;
        signal_id_value := null;
        select s.id into signal_id_value
        from fitmatch_vnext.source_classification_signals s
        where s.source_code = source_value
          and s.signal_kind = upper(btrim(signal_value ->> 'kind'))
          and s.external_key = btrim(coalesce(signal_value ->> 'external_key',
                signal_value ->> 'key'))
          and s.audience_code in (audience_value, 'ANY')
        order by (s.audience_code = audience_value) desc, s.id
        limit 1;
        if signal_id_value is null then
            insert into fitmatch_vnext.source_classification_signals (
                source_code, signal_kind, external_key, external_id, audience_code,
                signal_name, signal_path, is_active, first_seen_at, last_seen_at
            ) values (
                source_value, upper(btrim(signal_value ->> 'kind')),
                btrim(coalesce(signal_value ->> 'external_key', signal_value ->> 'key')),
                nullif(btrim(signal_value ->> 'external_id'), ''), audience_value,
                nullif(btrim(signal_value ->> 'name'), ''),
                nullif(btrim(signal_value ->> 'path'), ''), true,
                observed_value, observed_value
            ) returning id into signal_id_value;
        else
            update fitmatch_vnext.source_classification_signals
            set last_seen_at = greatest(last_seen_at, observed_value),
                signal_name = coalesce(signal_name,
                    nullif(btrim(signal_value ->> 'name'), '')),
                signal_path = coalesce(signal_path,
                    nullif(btrim(signal_value ->> 'path'), ''))
            where id = signal_id_value;
        end if;
        insert into fitmatch_vnext.product_classification_signals (
            product_id, source_signal_id, is_primary, evidence_order, observed_at
        ) values (product_id_value, signal_id_value, false,
            signal_order_value, observed_value)
        on conflict (product_id, source_signal_id) do update
        set evidence_order = excluded.evidence_order,
            observed_at = excluded.observed_at;
    end loop;

    select case when count(distinct a.parser_code) = 1 then min(a.parser_code) end
    into default_parser_value
    from fitmatch_vnext.source_measurement_aliases a
    where a.source_code = source_value and a.is_active and a.is_verified;

    if exists (
        select 1
        from jsonb_array_elements(coalesce(p_payload -> 'variants', '[]'::jsonb)) v
        group by btrim(v ->> 'external_variant_id')
        having btrim(v ->> 'external_variant_id') is null
            or btrim(v ->> 'external_variant_id') = '' or count(*) > 1
    ) then
        raise exception 'Variant identities must be non-empty and unique';
    end if;

    for variant_value in
        select value from jsonb_array_elements(
            coalesce(p_payload -> 'variants', '[]'::jsonb)
        )
    loop
        if jsonb_typeof(variant_value) <> 'object'
           or jsonb_typeof(coalesce(variant_value -> 'sizes', '[]'::jsonb)) <> 'array'
           or jsonb_array_length(coalesce(variant_value -> 'sizes', '[]'::jsonb)) > 200 then
            raise exception 'Each variant must contain a sizes array of at most 200 entries';
        end if;

        insert into fitmatch_vnext.product_variants (
            product_id, source_variant_key, variant_label, color_code, color_name,
            image_url, availability_status, sort_order, last_seen_at
        ) values (
            product_id_value, btrim(variant_value ->> 'external_variant_id'),
            nullif(btrim(variant_value ->> 'variant_name'), ''),
            nullif(btrim(variant_value ->> 'color_code'), ''),
            nullif(btrim(variant_value ->> 'color_name'), ''),
            nullif(btrim(variant_value ->> 'image_url'), ''), 'UNKNOWN',
            coalesce((variant_value ->> 'display_order')::integer, 0), observed_value
        )
        on conflict (product_id, source_variant_key) do update
        set variant_label = coalesce(excluded.variant_label,
                fitmatch_vnext.product_variants.variant_label),
            color_code = coalesce(excluded.color_code,
                fitmatch_vnext.product_variants.color_code),
            color_name = coalesce(excluded.color_name,
                fitmatch_vnext.product_variants.color_name),
            image_url = coalesce(excluded.image_url,
                fitmatch_vnext.product_variants.image_url),
            last_seen_at = greatest(fitmatch_vnext.product_variants.last_seen_at,
                excluded.last_seen_at)
        returning id into variant_id_value;

        insert into fitmatch_vnext.source_identifiers (
            source_code, entity_scope, variant_id, identifier_type_code, identifier_value
        ) values (
            source_value, 'VARIANT', variant_id_value,
            'source_variant_key', btrim(variant_value ->> 'external_variant_id')
        ) on conflict do nothing;

        if exists (
            select 1
            from jsonb_array_elements(coalesce(variant_value -> 'sizes', '[]'::jsonb)) s
            group by btrim(s ->> 'size_identity')
            having btrim(s ->> 'size_identity') is null
                or btrim(s ->> 'size_identity') = '' or count(*) > 1
        ) then
            raise exception 'Size identities must be non-empty and unique within a variant';
        end if;

        for size_value in
            select value from jsonb_array_elements(
                coalesce(variant_value -> 'sizes', '[]'::jsonb)
            )
        loop
            if jsonb_typeof(size_value) <> 'object'
               or nullif(btrim(size_value ->> 'size_label'), '') is null
               or jsonb_typeof(coalesce(size_value -> 'measurements', '[]'::jsonb)) <> 'array'
               or jsonb_array_length(coalesce(size_value -> 'measurements', '[]'::jsonb)) > 100 then
                raise exception 'Each size needs a label and at most 100 measurements';
            end if;

            insert into fitmatch_vnext.product_sizes (
                variant_id, source_size_key, size_label, normalized_size_label,
                availability_status, sort_order, last_seen_at
            ) values (
                variant_id_value, btrim(size_value ->> 'size_identity'),
                btrim(size_value ->> 'size_label'),
                nullif(btrim(size_value ->> 'normalized_size_label'), ''),
                'UNKNOWN', coalesce((size_value ->> 'display_order')::integer, 0),
                observed_value
            )
            on conflict (variant_id, source_size_key) do update
            set size_label = excluded.size_label,
                normalized_size_label = coalesce(excluded.normalized_size_label,
                    fitmatch_vnext.product_sizes.normalized_size_label),
                sort_order = excluded.sort_order,
                last_seen_at = greatest(fitmatch_vnext.product_sizes.last_seen_at,
                    excluded.last_seen_at)
            returning id into size_id_value;

            insert into fitmatch_vnext.source_identifiers (
                source_code, entity_scope, product_size_id,
                identifier_type_code, identifier_value
            ) values (
                source_value, 'SIZE', size_id_value,
                'source_size_key', btrim(size_value ->> 'size_identity')
            ) on conflict do nothing;

            update fitmatch_vnext.product_size_measurements
            set is_current = false
            where product_size_id = size_id_value and is_current;

            if exists (
                select 1
                from jsonb_array_elements(
                    coalesce(size_value -> 'measurements', '[]'::jsonb)
                ) m
                group by btrim(m ->> 'measurement_identity')
                having btrim(m ->> 'measurement_identity') is null
                    or btrim(m ->> 'measurement_identity') = '' or count(*) > 1
            ) then
                raise exception 'Measurement identities must be non-empty and unique within a size';
            end if;

            for measurement_value in
                select value from jsonb_array_elements(
                    coalesce(size_value -> 'measurements', '[]'::jsonb)
                )
            loop
                if jsonb_typeof(measurement_value) <> 'object' then
                    raise exception 'Measurement evidence must be a JSON object';
                end if;
                raw_key_value := btrim(measurement_value ->> 'measurement_identity');
                raw_code_value := nullif(btrim(measurement_value ->> 'raw_code'), '');
                raw_label_value := nullif(btrim(measurement_value ->> 'raw_label'), '');
                begin
                    raw_value_value := (measurement_value ->> 'raw_value')::numeric;
                exception when others then
                    raise exception 'raw_value must be numeric';
                end;
                if raw_value_value is null or raw_value_value <= 0
                   or (raw_code_value is null and raw_label_value is null) then
                    raise exception 'Measurement requires a positive value and code or label';
                end if;

                parser_value := coalesce(
                    nullif(btrim(measurement_value ->> 'parser_code'), ''),
                    nullif(btrim(measurement_value -> 'evidence' ->> 'parser_code'), ''),
                    nullif(btrim(size_value ->> 'parser_code'), ''),
                    nullif(btrim(variant_value ->> 'parser_code'), ''),
                    nullif(btrim(p_payload -> 'structured_facts' ->> 'measurement_parser_code'), ''),
                    default_parser_value,
                    'ingestion_unmapped'
                );
                measurement_fingerprint_value := encode(extensions.digest(
                    concat_ws('|', payload_fingerprint_value, variant_id_value::text,
                        size_id_value::text, measurement_value::text), 'sha256'
                ), 'hex');

                insert into fitmatch_vnext.product_size_measurements (
                    product_size_id, parser_code, raw_measurement_key, raw_code,
                    raw_label, raw_value, raw_unit_code, observed_at,
                    evidence_payload, evidence_fingerprint, is_current
                ) values (
                    size_id_value, parser_value, raw_key_value, raw_code_value,
                    raw_label_value, raw_value_value,
                    coalesce(nullif(btrim(measurement_value ->> 'raw_unit'), ''), 'cm'),
                    observed_value,
                    jsonb_build_object(
                        'ingestion_receipt_id', receipt_id_value,
                        'retailer_evidence', coalesce(measurement_value -> 'evidence', '{}'::jsonb),
                        'raw_representation', measurement_value ->> 'raw_representation'
                    ),
                    measurement_fingerprint_value, true
                )
                on conflict (product_size_id, parser_code, raw_measurement_key)
                do update set
                    raw_code = excluded.raw_code,
                    raw_label = excluded.raw_label,
                    raw_value = excluded.raw_value,
                    raw_unit_code = excluded.raw_unit_code,
                    observed_at = excluded.observed_at,
                    evidence_payload = excluded.evidence_payload,
                    evidence_fingerprint = excluded.evidence_fingerprint,
                    is_current = true;
                raw_measurement_count_value := raw_measurement_count_value + 1;
            end loop;

            availability_value := upper(btrim(coalesce(
                size_value ->> 'availability_status', size_value ->> 'stock_status', 'UNKNOWN'
            )));
            availability_value := case availability_value
                when 'AVAILABLE' then 'AVAILABLE' when 'IN_STOCK' then 'AVAILABLE'
                when 'SOLD_OUT' then 'SOLD_OUT' when 'OUT_OF_STOCK' then 'SOLD_OUT'
                else 'UNKNOWN' end;
            begin
                valid_until_value := nullif(btrim(size_value ->> 'valid_until'), '')::timestamptz;
            exception when others then
                raise exception 'Size valid_until must be an ISO-8601 timestamp';
            end;
            if valid_until_value is null and availability_value <> 'UNKNOWN' then
                valid_until_value := observed_value + interval '24 hours';
            end if;
            perform fitmatch_vnext.record_size_availability(
                size_id_value, availability_value, 'RETAILER_OBSERVATION',
                jsonb_build_object(
                    'ingestion_receipt_id', receipt_id_value,
                    'payload_fingerprint', payload_fingerprint_value,
                    'source_variant_key', variant_value ->> 'external_variant_id',
                    'source_size_key', size_value ->> 'size_identity',
                    'retailer_stock_status', size_value ->> 'stock_status'
                ),
                observed_value, valid_until_value
            );
        end loop;
    end loop;

    classification_value := fitmatch_vnext.resolve_product_classification(
        source_value, product_key, true
    );
    update fitmatch_vnext.product_classification_signals
    set is_primary = coalesce(source_signal_id =
        (classification_value ->> 'primary_source_signal_id')::uuid, false)
    where product_id = product_id_value;

    readiness_value := fitmatch_vnext.product_readiness(product_id_value);
    update fitmatch_vnext.product_ingestion_receipts
    set processing_status = 'PROCESSED',
        result_summary = jsonb_build_object(
            'raw_measurement_count', raw_measurement_count_value,
            'classification', classification_value,
            'readiness', readiness_value
        )
    where id = receipt_id_value;

    runtime_value := fitmatch_vnext.get_product_runtime(source_value, product_key);
    return jsonb_build_object(
        'observation', jsonb_build_object(
            'observation_id', receipt_id_value,
            'status', 'accepted',
            'raw_measurement_count', raw_measurement_count_value,
            'idempotent', false,
            'payload_fingerprint', payload_fingerprint_value
        ),
        'processing', jsonb_build_object(
            'observation_id', receipt_id_value,
            'status', 'processed',
            'product_id', product_id_value,
            'idempotent', false
        ),
        'classification', classification_value,
        'readiness', readiness_value,
        'runtime', runtime_value
    );
end
$function$;

revoke all on function fitmatch_vnext.protect_product_ingestion_receipt() from public;
revoke all on function fitmatch_vnext.ingest_product_observation(jsonb,uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.ingest_product_observation(jsonb,uuid)
    to service_role;

revoke all on function fitmatch_vnext.get_product_runtime(text,text) from public, anon;
grant execute on function fitmatch_vnext.get_product_runtime(text,text)
    to authenticated, service_role;

-- Verification query (read-only after deployment):
-- select count(*) from fitmatch_vnext.product_ingestion_receipts
-- where processing_status not in ('PROCESSED','IGNORED_STALE');
;
