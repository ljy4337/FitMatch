begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:product-observation-pipeline-v1'));

-- Immutable retailer observations. A repeated identical payload increments the
-- counters, while a changed payload creates a new auditable observation.
create table if not exists fitmatch_catalog.product_observations (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  external_product_id text not null,
  payload_fingerprint text not null,
  observation_origin text not null default 'ios',
  raw_payload jsonb not null,
  processing_status text not null default 'pending',
  resolved_product_id uuid
    references fitmatch_catalog.products(id) on delete set null,
  normalization_summary jsonb not null default '{}',
  error_code text,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  observation_count integer not null default 1,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint product_observations_source_check
    check (source in ('uniqlo','musinsa')),
  constraint product_observations_external_id_check
    check (btrim(external_product_id) <> ''),
  constraint product_observations_fingerprint_check
    check (payload_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint product_observations_origin_check
    check (observation_origin in ('ios','batch','backend')),
  constraint product_observations_payload_check
    check (jsonb_typeof(raw_payload) = 'object'),
  constraint product_observations_status_check
    check (processing_status in ('pending','processing','promoted','rejected')),
  constraint product_observations_summary_check
    check (jsonb_typeof(normalization_summary) = 'object'),
  constraint product_observations_count_check
    check (observation_count > 0),
  constraint product_observations_identity_unique
    unique (source, external_product_id, payload_fingerprint)
);

create index if not exists product_observations_processing_idx
  on fitmatch_catalog.product_observations
    (processing_status, created_at)
  where processing_status in ('pending','rejected');
create index if not exists product_observations_product_history_idx
  on fitmatch_catalog.product_observations
    (source, external_product_id, first_observed_at desc);
create index if not exists product_observations_resolved_product_idx
  on fitmatch_catalog.product_observations
    (resolved_product_id, first_observed_at desc)
  where resolved_product_id is not null;

-- A global observation may be submitted by more than one signed-in user.
-- User attribution is kept separately so deduplication never loses ownership.
create table if not exists fitmatch_catalog.product_observation_submissions (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null
    references fitmatch_catalog.product_observations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  first_submitted_at timestamptz not null default now(),
  last_submitted_at timestamptz not null default now(),
  submission_count integer not null default 1,
  constraint product_observation_submissions_count_check
    check (submission_count > 0),
  constraint product_observation_submissions_identity_unique
    unique (observation_id, user_id)
);

create index if not exists product_observation_submissions_user_idx
  on fitmatch_catalog.product_observation_submissions
    (user_id, last_submitted_at desc);

-- Raw measurement rows are copied out of the JSON for inspection and audit.
-- Normalized current values continue to live in product_measurements.
create table if not exists fitmatch_catalog.product_observation_measurements (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null
    references fitmatch_catalog.product_observations(id) on delete cascade,
  external_variant_id text not null,
  size_identity text not null,
  size_label text not null,
  measurement_ordinal integer not null,
  measurement_identity text not null,
  raw_code text,
  raw_label text not null,
  raw_value numeric not null,
  raw_unit text not null,
  raw_representation text,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint product_observation_measurements_variant_check
    check (btrim(external_variant_id) <> ''),
  constraint product_observation_measurements_size_check
    check (btrim(size_identity) <> '' and btrim(size_label) <> ''),
  constraint product_observation_measurements_ordinal_check
    check (measurement_ordinal >= 0),
  constraint product_observation_measurements_identity_check
    check (btrim(measurement_identity) <> ''),
  constraint product_observation_measurements_label_check
    check (btrim(raw_label) <> ''),
  constraint product_observation_measurements_value_check
    check (raw_value > 0),
  constraint product_observation_measurements_unit_check
    check (btrim(raw_unit) <> ''),
  constraint product_observation_measurements_evidence_check
    check (jsonb_typeof(evidence) = 'object'),
  constraint product_observation_measurements_identity_unique
    unique (observation_id, external_variant_id, size_identity, measurement_ordinal)
);

create index if not exists product_observation_measurements_observation_idx
  on fitmatch_catalog.product_observation_measurements
    (observation_id, external_variant_id, size_identity, measurement_ordinal);

alter table fitmatch_catalog.product_observations enable row level security;
alter table fitmatch_catalog.product_observation_submissions enable row level security;
alter table fitmatch_catalog.product_observation_measurements enable row level security;

revoke all on fitmatch_catalog.product_observations
  from public, anon, authenticated;
revoke all on fitmatch_catalog.product_observation_submissions
  from public, anon, authenticated;
revoke all on fitmatch_catalog.product_observation_measurements
  from public, anon, authenticated;
grant select, insert, update, delete on fitmatch_catalog.product_observations
  to service_role;
grant select, insert, update, delete on fitmatch_catalog.product_observation_submissions
  to service_role;
grant select, insert, update, delete on fitmatch_catalog.product_observation_measurements
  to service_role;

create or replace function public.fitmatch_submit_product_observation(
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_source text := lower(btrim(coalesce(p_payload->>'source','')));
  v_external_id text := btrim(coalesce(p_payload->>'external_product_id',''));
  v_product_name text := btrim(coalesce(p_payload->>'product_name',''));
  v_fingerprint text;
  v_observation_id uuid;
  v_variants jsonb;
  v_variant jsonb;
  v_size jsonb;
  v_measurement jsonb;
  v_variant_id text;
  v_size_identity text;
  v_size_label text;
  v_measurement_identity text;
  v_raw_label text;
  v_raw_value_text text;
  v_raw_value numeric;
  v_measurement_ordinal integer;
  v_variant_count integer;
  v_size_count integer := 0;
  v_measurement_count integer := 0;
  v_observation_count integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'payload_must_be_object';
  end if;
  if octet_length(p_payload::text) > 5242880 then
    raise exception using errcode = '22023', message = 'payload_too_large';
  end if;
  if v_source not in ('uniqlo','musinsa') then
    raise exception using errcode = '22023', message = 'unsupported_source';
  end if;
  if v_external_id = '' or length(v_external_id) > 200 then
    raise exception using errcode = '22023', message = 'invalid_external_product_id';
  end if;
  if v_product_name = '' or length(v_product_name) > 1000 then
    raise exception using errcode = '22023', message = 'invalid_product_name';
  end if;

  v_variants := case
    when jsonb_typeof(p_payload->'variants') = 'array' then p_payload->'variants'
    when jsonb_typeof(p_payload->'sizes') = 'array' then jsonb_build_array(
      jsonb_build_object(
        'external_variant_id','__default__',
        'variant_name','기본 옵션',
        'sizes',p_payload->'sizes'
      )
    )
    else '[]'::jsonb
  end;
  v_variant_count := jsonb_array_length(v_variants);
  if v_variant_count > 100 then
    raise exception using errcode = '22023', message = 'too_many_variants';
  end if;

  -- JSONB has deterministic key ordering, so the text hash is stable for the
  -- same semantic payload regardless of request key order.
  v_fingerprint := md5(p_payload::text);
  insert into fitmatch_catalog.product_observations (
    source, external_product_id, payload_fingerprint, observation_origin,
    raw_payload
  ) values (
    v_source, v_external_id, v_fingerprint, 'ios', p_payload
  )
  on conflict (source, external_product_id, payload_fingerprint) do update set
    last_observed_at = now(),
    observation_count = fitmatch_catalog.product_observations.observation_count + 1
  returning id, observation_count into v_observation_id, v_observation_count;

  insert into fitmatch_catalog.product_observation_submissions (
    observation_id, user_id
  ) values (v_observation_id, v_user_id)
  on conflict (observation_id, user_id) do update set
    last_submitted_at = now(),
    submission_count = fitmatch_catalog.product_observation_submissions.submission_count + 1;

  -- Only the first identical payload needs row extraction. Repeated requests
  -- retain their counts without duplicating raw measurement rows.
  if not exists (
    select 1
    from fitmatch_catalog.product_observation_measurements
    where observation_id = v_observation_id
  ) then
    for v_variant in select value from jsonb_array_elements(v_variants)
    loop
      if jsonb_typeof(v_variant) <> 'object' then
        raise exception using errcode = '22023', message = 'variant_must_be_object';
      end if;
      v_variant_id := btrim(coalesce(nullif(v_variant->>'external_variant_id',''),'__default__'));
      if length(v_variant_id) > 300 then
        raise exception using errcode = '22023', message = 'invalid_external_variant_id';
      end if;
      if v_variant->'sizes' is not null and jsonb_typeof(v_variant->'sizes') <> 'array' then
        raise exception using errcode = '22023', message = 'sizes_must_be_array';
      end if;

      for v_size in
        select value from jsonb_array_elements(coalesce(v_variant->'sizes','[]'::jsonb))
      loop
        v_size_count := v_size_count + 1;
        if v_size_count > 2000 then
          raise exception using errcode = '22023', message = 'too_many_sizes';
        end if;
        if jsonb_typeof(v_size) <> 'object' then
          raise exception using errcode = '22023', message = 'size_must_be_object';
        end if;
        v_size_label := btrim(coalesce(v_size->>'size_label',''));
        v_size_identity := btrim(coalesce(
          nullif(v_size->>'size_identity',''),
          nullif(v_size->>'external_size_id',''),
          lower(v_size_label)
        ));
        if v_size_label = '' or v_size_identity = ''
           or length(v_size_label) > 300 or length(v_size_identity) > 300 then
          raise exception using errcode = '22023', message = 'invalid_size_identity';
        end if;
        if v_size->'measurements' is not null
           and jsonb_typeof(v_size->'measurements') <> 'array' then
          raise exception using errcode = '22023', message = 'measurements_must_be_array';
        end if;

        v_measurement_ordinal := 0;
        for v_measurement in
          select value from jsonb_array_elements(coalesce(v_size->'measurements','[]'::jsonb))
        loop
          v_measurement_count := v_measurement_count + 1;
          if v_measurement_count > 20000 then
            raise exception using errcode = '22023', message = 'too_many_measurements';
          end if;
          if jsonb_typeof(v_measurement) <> 'object' then
            raise exception using errcode = '22023', message = 'measurement_must_be_object';
          end if;
          v_raw_label := btrim(coalesce(v_measurement->>'raw_label',''));
          v_raw_value_text := btrim(coalesce(v_measurement->>'raw_value',''));
          if v_raw_label = '' or length(v_raw_label) > 500
             or v_raw_value_text !~ '^[0-9]+([.][0-9]+)?$' then
            raise exception using errcode = '22023', message = 'invalid_measurement';
          end if;
          v_raw_value := v_raw_value_text::numeric;
          if v_raw_value <= 0 or v_raw_value > 10000 then
            raise exception using errcode = '22023', message = 'invalid_measurement_value';
          end if;
          v_measurement_identity := btrim(coalesce(
            nullif(v_measurement->>'measurement_identity',''),
            nullif(v_measurement->>'raw_code',''),
            lower(v_raw_label)
          ));
          if v_measurement_identity = '' or length(v_measurement_identity) > 500 then
            raise exception using errcode = '22023', message = 'invalid_measurement_identity';
          end if;

          insert into fitmatch_catalog.product_observation_measurements (
            observation_id, external_variant_id, size_identity, size_label,
            measurement_ordinal, measurement_identity, raw_code, raw_label,
            raw_value, raw_unit, raw_representation, evidence
          ) values (
            v_observation_id, v_variant_id, v_size_identity, v_size_label,
            v_measurement_ordinal, v_measurement_identity,
            nullif(btrim(coalesce(v_measurement->>'raw_code','')),''),
            v_raw_label, v_raw_value,
            coalesce(nullif(btrim(coalesce(v_measurement->>'raw_unit','')),''),'cm'),
            nullif(btrim(coalesce(v_measurement->>'raw_representation','')),''),
            case when jsonb_typeof(v_measurement->'evidence') = 'object'
              then v_measurement->'evidence' else '{}'::jsonb end
          );
          v_measurement_ordinal := v_measurement_ordinal + 1;
        end loop;
      end loop;
    end loop;
  else
    select count(distinct (external_variant_id, size_identity)), count(*)
    into v_size_count, v_measurement_count
    from fitmatch_catalog.product_observation_measurements
    where observation_id = v_observation_id;
  end if;

  return jsonb_build_object(
    'observation_id', v_observation_id,
    'status', (select processing_status
      from fitmatch_catalog.product_observations where id = v_observation_id),
    'payload_fingerprint', v_fingerprint,
    'observation_count', v_observation_count,
    'variant_count', v_variant_count,
    'size_count', v_size_count,
    'raw_measurement_count', v_measurement_count
  );
end $$;

create or replace function public.fitmatch_process_product_observation(
  p_observation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_observation fitmatch_catalog.product_observations%rowtype;
  v_promotion jsonb;
  v_ingest jsonb;
  v_summary jsonb;
begin
  select * into v_observation
  from fitmatch_catalog.product_observations
  where id = p_observation_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'observation_not_found';
  end if;

  if v_observation.processing_status = 'promoted' then
    return jsonb_build_object(
      'observation_id', v_observation.id,
      'status', v_observation.processing_status,
      'product_id', v_observation.resolved_product_id,
      'summary', v_observation.normalization_summary,
      'idempotent', true
    );
  end if;

  update fitmatch_catalog.product_observations
  set processing_status = 'processing', error_code = null
  where id = v_observation.id;

  begin
    -- Classification must exist before measurement normalization because some
    -- retailer labels require a canonical major-category scope.
    v_promotion := fitmatch_catalog.runtime_resolve_and_promote_product(
      v_observation.raw_payload
    );
    v_ingest := fitmatch_catalog.runtime_ingest_product_payload(
      v_observation.raw_payload
    );
    v_summary := v_promotion || jsonb_build_object(
      'variants_processed', coalesce((v_ingest->>'variants_processed')::integer, 0),
      'sizes_processed', coalesce((v_ingest->>'sizes_processed')::integer, 0),
      'measurements_processed', coalesce((v_ingest->>'measurements_processed')::integer, 0)
    );

    update fitmatch_catalog.product_observations
    set processing_status = 'promoted',
        resolved_product_id = (v_promotion->>'product_id')::uuid,
        normalization_summary = v_summary,
        error_code = null,
        processed_at = now()
    where id = v_observation.id;

    return jsonb_build_object(
      'observation_id', v_observation.id,
      'status', 'promoted',
      'product_id', (v_promotion->>'product_id')::uuid,
      'summary', v_summary,
      'idempotent', false
    );
  exception when others then
    update fitmatch_catalog.product_observations
    set processing_status = 'rejected',
        error_code = left(sqlstate || ':' || sqlerrm, 500),
        processed_at = now()
    where id = v_observation.id;
    return jsonb_build_object(
      'observation_id', v_observation.id,
      'status', 'rejected',
      'error_code', left(sqlstate || ':' || sqlerrm, 500),
      'idempotent', false
    );
  end;
end $$;

comment on table fitmatch_catalog.product_observations is
  'Immutable deduplicated retailer payload history; never used directly for comparison.';
comment on table fitmatch_catalog.product_observation_measurements is
  'Immutable raw measurement evidence extracted from each retailer observation.';
comment on function public.fitmatch_submit_product_observation(jsonb) is
  'Authenticated client boundary: validate and preserve a raw retailer product observation.';
comment on function public.fitmatch_process_product_observation(uuid) is
  'Backend-only boundary: promote a validated observation into canonical runtime tables.';

revoke all on function public.fitmatch_submit_product_observation(jsonb)
  from public, anon, service_role;
grant execute on function public.fitmatch_submit_product_observation(jsonb)
  to authenticated;
revoke all on function public.fitmatch_process_product_observation(uuid)
  from public, anon, authenticated;
grant execute on function public.fitmatch_process_product_observation(uuid)
  to service_role;

commit;
