begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:add-cos-observation-source-v1'));

-- Keep the accepted retailer list explicit. COS is added only at the existing
-- authenticated observation and backend-batch boundaries; no catalog mapping
-- is implied by this migration.
alter table fitmatch_catalog.product_observations
  drop constraint if exists product_observations_source_check;
alter table fitmatch_catalog.product_observations
  add constraint product_observations_source_check
  check (source in ('uniqlo', 'musinsa', 'cos'));

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
  if v_source not in ('uniqlo', 'musinsa', 'cos') then
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
      jsonb_build_object('external_variant_id','__default__','variant_name','기본 옵션','sizes',p_payload->'sizes')
    )
    else '[]'::jsonb
  end;
  v_variant_count := jsonb_array_length(v_variants);
  if v_variant_count > 100 then
    raise exception using errcode = '22023', message = 'too_many_variants';
  end if;

  v_fingerprint := md5(p_payload::text);
  insert into fitmatch_catalog.product_observations (
    source, external_product_id, payload_fingerprint, observation_origin, raw_payload
  ) values (
    v_source, v_external_id, v_fingerprint, 'ios', p_payload
  )
  on conflict (source, external_product_id, payload_fingerprint) do update set
    last_observed_at = now(),
    observation_count = fitmatch_catalog.product_observations.observation_count + 1
  returning id, observation_count into v_observation_id, v_observation_count;

  insert into fitmatch_catalog.product_observation_submissions (observation_id, user_id)
  values (v_observation_id, v_user_id)
  on conflict (observation_id, user_id) do update set
    last_submitted_at = now(),
    submission_count = fitmatch_catalog.product_observation_submissions.submission_count + 1;

  if not exists (
    select 1 from fitmatch_catalog.product_observation_measurements where observation_id = v_observation_id
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

      for v_size in select value from jsonb_array_elements(coalesce(v_variant->'sizes','[]'::jsonb))
      loop
        v_size_count := v_size_count + 1;
        if v_size_count > 2000 then
          raise exception using errcode = '22023', message = 'too_many_sizes';
        end if;
        if jsonb_typeof(v_size) <> 'object' then
          raise exception using errcode = '22023', message = 'size_must_be_object';
        end if;
        v_size_label := btrim(coalesce(v_size->>'size_label',''));
        v_size_identity := btrim(coalesce(nullif(v_size->>'size_identity',''), nullif(v_size->>'external_size_id',''), lower(v_size_label)));
        if v_size_label = '' or v_size_identity = '' or length(v_size_label) > 300 or length(v_size_identity) > 300 then
          raise exception using errcode = '22023', message = 'invalid_size_identity';
        end if;
        if v_size->'measurements' is not null and jsonb_typeof(v_size->'measurements') <> 'array' then
          raise exception using errcode = '22023', message = 'measurements_must_be_array';
        end if;

        v_measurement_ordinal := 0;
        for v_measurement in select value from jsonb_array_elements(coalesce(v_size->'measurements','[]'::jsonb))
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
          if v_raw_label = '' or length(v_raw_label) > 500 or v_raw_value_text !~ '^[0-9]+([.][0-9]+)?$' then
            raise exception using errcode = '22023', message = 'invalid_measurement';
          end if;
          v_raw_value := v_raw_value_text::numeric;
          if v_raw_value <= 0 or v_raw_value > 10000 then
            raise exception using errcode = '22023', message = 'invalid_measurement_value';
          end if;
          v_measurement_identity := btrim(coalesce(nullif(v_measurement->>'measurement_identity',''), nullif(v_measurement->>'raw_code',''), lower(v_raw_label)));
          if v_measurement_identity = '' or length(v_measurement_identity) > 500 then
            raise exception using errcode = '22023', message = 'invalid_measurement_identity';
          end if;
          insert into fitmatch_catalog.product_observation_measurements (
            observation_id, external_variant_id, size_identity, size_label, measurement_ordinal,
            measurement_identity, raw_code, raw_label, raw_value, raw_unit, raw_representation, evidence
          ) values (
            v_observation_id, v_variant_id, v_size_identity, v_size_label, v_measurement_ordinal,
            v_measurement_identity, nullif(btrim(coalesce(v_measurement->>'raw_code','')),''),
            v_raw_label, v_raw_value, coalesce(nullif(btrim(coalesce(v_measurement->>'raw_unit','')),''),'cm'),
            nullif(btrim(coalesce(v_measurement->>'raw_representation','')),''),
            case when jsonb_typeof(v_measurement->'evidence') = 'object' then v_measurement->'evidence' else '{}'::jsonb end
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
    'status', (select processing_status from fitmatch_catalog.product_observations where id = v_observation_id),
    'payload_fingerprint', v_fingerprint,
    'observation_count', v_observation_count,
    'variant_count', v_variant_count,
    'size_count', v_size_count,
    'raw_measurement_count', v_measurement_count
  );
end $$;

create or replace function public.fitmatch_batch_products_needing_ingest(
  p_source text,
  p_external_ids text[],
  p_batch_version text
) returns table(external_product_id text)
language plpgsql
stable
security invoker
set search_path = pg_catalog
as $$
declare
  v_source text := lower(btrim(coalesce(p_source, '')));
  v_version text := btrim(coalesce(p_batch_version, ''));
begin
  if v_source not in ('uniqlo', 'musinsa', 'cos') then
    raise exception using errcode = '22023', message = 'unsupported_batch_source';
  end if;
  if v_version = '' or length(v_version) > 100 then
    raise exception using errcode = '22023', message = 'invalid_batch_version';
  end if;
  if p_external_ids is null or cardinality(p_external_ids) = 0 or cardinality(p_external_ids) > 5000 then
    raise exception using errcode = '22023', message = 'external_id_chunk_must_contain_1_to_5000_items';
  end if;
  return query
  select distinct btrim(i.external_id)
  from unnest(p_external_ids) as i(external_id)
  left join fitmatch_catalog.products p
    on p.source = v_source and p.external_product_id = btrim(i.external_id)
  where btrim(coalesce(i.external_id, '')) <> ''
    and (
      p.id is null
      or coalesce(p.raw_payload->>'batch_ingest_version', '') <> v_version
      or not exists (
        select 1 from fitmatch_catalog.product_classification_history h
        where h.product_id = p.id and h.is_current
      )
    );
end $$;

revoke all on function public.fitmatch_submit_product_observation(jsonb)
  from public, anon, service_role;
grant execute on function public.fitmatch_submit_product_observation(jsonb)
  to authenticated;
revoke all on function public.fitmatch_batch_products_needing_ingest(text,text[],text)
  from public, anon, authenticated;
grant execute on function public.fitmatch_batch_products_needing_ingest(text,text[],text)
  to service_role;

commit;
;
