-- fitmatch_vnext P0-3: evidence-backed availability and product runtime.

create table if not exists fitmatch_vnext.size_availability_observations (
    id bigint generated always as identity primary key,
    product_size_id uuid not null references fitmatch_vnext.product_sizes(id) on delete cascade,
    source_code text not null references fitmatch_vnext.sources(source_code) on update cascade on delete restrict,
    availability_status text not null check (availability_status in ('AVAILABLE', 'SOLD_OUT', 'UNKNOWN')),
    evidence_kind text not null,
    evidence_payload jsonb not null default '{}'::jsonb
        check (jsonb_typeof(evidence_payload) = 'object'),
    evidence_fingerprint text not null,
    observed_at timestamptz not null,
    valid_until timestamptz,
    created_at timestamptz not null default now(),
    unique (product_size_id, evidence_fingerprint)
);

create index if not exists size_availability_latest_idx
    on fitmatch_vnext.size_availability_observations
        (product_size_id, observed_at desc, id desc);

alter table fitmatch_vnext.size_availability_observations enable row level security;
revoke all on table fitmatch_vnext.size_availability_observations from public, anon, authenticated;
grant select, insert, update on table fitmatch_vnext.size_availability_observations to service_role;

create or replace function fitmatch_vnext.validate_size_availability_observation()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    actual_source text;
begin
    select p.source_code into actual_source
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    where ps.id = new.product_size_id;

    if actual_source is null or actual_source <> new.source_code then
        raise exception 'Availability observation source does not match product hierarchy';
    end if;
    if new.valid_until is not null and new.valid_until < new.observed_at then
        raise exception 'Availability valid_until cannot precede observed_at';
    end if;
    return new;
end
$function$;

drop trigger if exists size_availability_observations_validate
    on fitmatch_vnext.size_availability_observations;
create trigger size_availability_observations_validate
before insert or update on fitmatch_vnext.size_availability_observations
for each row execute function fitmatch_vnext.validate_size_availability_observation();

-- Preserve the 12 explicit current AVAILABLE states as legacy retailer
-- observations. UNKNOWN is intentionally not promoted.
insert into fitmatch_vnext.size_availability_observations (
    product_size_id, source_code, availability_status, evidence_kind,
    evidence_payload, evidence_fingerprint, observed_at, valid_until
)
select ps.id, p.source_code, 'AVAILABLE', 'LEGACY_RETAILER_OBSERVATION',
       jsonb_build_object(
           'source_size_key', ps.source_size_key,
           'source_variant_key', pv.source_variant_key,
           'product_last_fetched_at', p.last_fetched_at,
           'migration_basis', 'pre-vnext explicit AVAILABLE state'
       ),
       encode(extensions.digest(concat_ws('|', p.source_code, p.source_product_key,
           pv.source_variant_key, ps.source_size_key, ps.last_seen_at::text,
           'AVAILABLE'), 'sha256'), 'hex'),
       ps.last_seen_at,
       ps.last_seen_at + interval '30 days'
from fitmatch_vnext.product_sizes ps
join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
join fitmatch_vnext.products p on p.id = pv.product_id
where ps.availability_status = 'AVAILABLE'
on conflict (product_size_id, evidence_fingerprint) do nothing;

create or replace function fitmatch_vnext.record_size_availability(
    p_product_size_id uuid,
    p_availability_status text,
    p_evidence_kind text,
    p_evidence_payload jsonb,
    p_observed_at timestamptz,
    p_valid_until timestamptz default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
    source_value text;
    fingerprint_value text;
    observation_id bigint;
begin
    if p_availability_status not in ('AVAILABLE', 'SOLD_OUT', 'UNKNOWN') then
        raise exception 'Unsupported availability status';
    end if;
    if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) <> 'object' then
        raise exception 'Availability evidence must be a JSON object';
    end if;

    select p.source_code into source_value
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    where ps.id = p_product_size_id;

    if source_value is null then
        raise exception 'Unknown product_size_id';
    end if;

    fingerprint_value := encode(extensions.digest(concat_ws('|',
        p_product_size_id::text, p_availability_status, p_evidence_kind,
        p_evidence_payload::text, p_observed_at::text), 'sha256'), 'hex');

    insert into fitmatch_vnext.size_availability_observations (
        product_size_id, source_code, availability_status, evidence_kind,
        evidence_payload, evidence_fingerprint, observed_at, valid_until
    ) values (
        p_product_size_id, source_value, p_availability_status, p_evidence_kind,
        p_evidence_payload, fingerprint_value, p_observed_at, p_valid_until
    )
    on conflict (product_size_id, evidence_fingerprint)
    do update set evidence_payload = excluded.evidence_payload
    returning id into observation_id;

    update fitmatch_vnext.product_sizes
    set availability_status = p_availability_status,
        last_seen_at = greatest(last_seen_at, p_observed_at)
    where id = p_product_size_id;

    return jsonb_build_object(
        'observation_id', observation_id,
        'product_size_id', p_product_size_id,
        'availability_status', p_availability_status,
        'evidence_fingerprint', fingerprint_value
    );
end
$function$;

create or replace function fitmatch_vnext.product_readiness(p_product_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with product_row as (
    select p.*, gt.comparison_policy_code, gt.is_active garment_active
    from fitmatch_vnext.products p
    left join fitmatch_vnext.garment_types gt on gt.garment_type_code = p.garment_type_code
    where p.id = p_product_id
), policy as (
    select cp.*
    from product_row p
    join fitmatch_vnext.comparison_policies cp
      on cp.policy_code = p.comparison_policy_code and cp.is_active
), latest_availability as (
    select distinct on (o.product_size_id)
           o.product_size_id, o.availability_status, o.observed_at,
           o.valid_until, o.evidence_fingerprint
    from fitmatch_vnext.size_availability_observations o
    join fitmatch_vnext.product_sizes ps on ps.id = o.product_size_id
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where pv.product_id = p_product_id
    order by o.product_size_id, o.observed_at desc, o.id desc
), usable_sizes as (
    select ps.id product_size_id, ps.size_label, la.evidence_fingerprint
    from latest_availability la
    join fitmatch_vnext.product_sizes ps on ps.id = la.product_size_id
    where la.availability_status = 'AVAILABLE'
      and (la.valid_until is null or la.valid_until >= now())
), measurement_counts as (
    select u.product_size_id, u.size_label, u.evidence_fingerprint,
           count(distinct e ->> 'fitmatch_measurement_code') resolved_count,
           count(distinct e ->> 'fitmatch_measurement_code') filter (
               where cm.requirement_mode = 'REQUIRED_ANY'
           ) required_any_count
    from usable_sizes u
    cross join lateral jsonb_array_elements(
        fitmatch_vnext.canonical_measurements_for_size(u.product_size_id)
        -> 'measurements'
    ) e
    left join product_row pr on true
    left join fitmatch_vnext.comparison_metrics cm
      on cm.comparison_policy_code = pr.comparison_policy_code
     and cm.metric_mode = 'CANONICAL'
     and cm.fitmatch_measurement_code = e ->> 'fitmatch_measurement_code'
     and cm.is_active
    group by u.product_size_id, u.size_label, u.evidence_fingerprint
), ready_sizes as (
    select mc.*
    from measurement_counts mc cross join policy cp
    where mc.resolved_count >= cp.min_common_measurements
      and mc.required_any_count >= cp.required_any_min
)
select case when not exists (select 1 from product_row) then
    jsonb_build_object('status', 'CLASSIFICATION_REQUIRED', 'ready', false,
        'reason', 'Unknown product')
else (
    select jsonb_build_object(
        'product_id', p.id,
        'ready', case
            when p.classification_status = 'CONFIRMED'
             and exists (select 1 from ready_sizes) then true else false end,
        'status', case
            when p.classification_status = 'NOT_APPLICABLE' then 'NOT_APPLICABLE'
            when p.classification_status <> 'CONFIRMED' then 'CLASSIFICATION_REQUIRED'
            when not (fitmatch_vnext.classification_tuple_validation(
                p.garment_type_code, p.product_structure_code, p.audience_code,
                p.sleeve_length_code, p.lower_length_code, p.body_length_code
              ) ->> 'valid')::boolean then 'CLASSIFICATION_REQUIRED'
            when not exists (select 1 from policy) then 'POLICY_UNAVAILABLE'
            when not exists (select 1 from usable_sizes) then 'NO_AVAILABLE_SIZE'
            when not exists (select 1 from measurement_counts) then 'NO_MEASUREMENT_DATA'
            when not exists (select 1 from ready_sizes) then 'INSUFFICIENT_MEASUREMENTS'
            else 'READY' end,
        'reason', case
            when p.classification_status = 'NOT_APPLICABLE'
                then 'Product is not a comparable single garment'
            when p.classification_status <> 'CONFIRMED'
                then 'Classification is not CONFIRMED'
            when not exists (select 1 from policy)
                then 'No active comparison policy'
            when not exists (select 1 from usable_sizes)
                then 'No evidence-backed AVAILABLE size'
            when not exists (select 1 from measurement_counts)
                then 'Available size has no verified canonical measurements'
            when not exists (select 1 from ready_sizes)
                then 'Policy minimum measurements are not satisfied'
            else 'Classification, availability, measurements, and policy are ready' end,
        'comparison_policy_code', p.comparison_policy_code,
        'ready_sizes', coalesce((select jsonb_agg(jsonb_build_object(
            'product_size_id', r.product_size_id,
            'size_label', r.size_label,
            'resolved_measurement_count', r.resolved_count,
            'required_any_count', r.required_any_count,
            'availability_evidence_fingerprint', r.evidence_fingerprint
        ) order by r.size_label, r.product_size_id) from ready_sizes r), '[]'::jsonb),
        'readiness_version', 'fitmatch-vnext-readiness-v1'
    ) from product_row p
)
end;
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
    if caller_id is null then
        raise exception 'Authentication required';
    end if;

    select * into product_row
    from fitmatch_vnext.products p
    where p.source_code = p_source_code
      and p.source_product_key = p_source_product_key;
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
            'input_fingerprint', product_row.input_fingerprint
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

revoke all on function fitmatch_vnext.record_size_availability(uuid,text,text,jsonb,timestamptz,timestamptz)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.record_size_availability(uuid,text,text,jsonb,timestamptz,timestamptz)
    to service_role;
revoke all on function fitmatch_vnext.product_readiness(uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.product_readiness(uuid) to service_role;
revoke all on function fitmatch_vnext.get_product_runtime(text,text)
    from public, anon;
grant execute on function fitmatch_vnext.get_product_runtime(text,text)
    to authenticated, service_role;
