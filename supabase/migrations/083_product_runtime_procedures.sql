begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:product-runtime-procedures-v1'));

create or replace function fitmatch_catalog.runtime_product_fingerprint(
  p_product_name text,
  p_source_category_path text
) returns text
language sql
immutable
security invoker
set search_path = pg_catalog
as $$
  select md5(
    lower(btrim(coalesce(p_product_name,''))) || E'\n' ||
    lower(btrim(coalesce(p_source_category_path,'')))
  )
$$;

create or replace function fitmatch_catalog.runtime_upsert_product(
  p_payload jsonb
) returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_source text := lower(btrim(coalesce(p_payload->>'source','')));
  v_external_id text := btrim(coalesce(p_payload->>'external_product_id',''));
  v_name text := btrim(coalesce(p_payload->>'product_name',''));
  v_path text := nullif(btrim(coalesce(p_payload->>'source_category_path','')), '');
  v_product_id uuid;
begin
  if jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode='22023', message='payload_must_be_object';
  end if;
  if v_source !~ '^[a-z][a-z0-9_]*$' then
    raise exception using errcode='22023', message='invalid_source';
  end if;
  if v_external_id = '' or length(v_external_id) > 200 then
    raise exception using errcode='22023', message='invalid_external_product_id';
  end if;
  if v_name = '' or length(v_name) > 1000 then
    raise exception using errcode='22023', message='invalid_product_name';
  end if;

  insert into fitmatch_catalog.products (
    source, external_product_id, product_name, canonical_url, audience,
    source_category_path, source_category_codes, image_url, raw_payload,
    input_fingerprint, lifecycle_status, first_seen_at, last_seen_at
  ) values (
    v_source,
    v_external_id,
    v_name,
    nullif(btrim(coalesce(p_payload->>'canonical_url','')), ''),
    nullif(btrim(coalesce(p_payload->>'audience','')), ''),
    v_path,
    case
      when jsonb_typeof(p_payload->'source_category_codes') = 'array'
      then array(select jsonb_array_elements_text(p_payload->'source_category_codes'))
      else '{}'::text[]
    end,
    nullif(btrim(coalesce(p_payload->>'image_url','')), ''),
    case when jsonb_typeof(p_payload->'raw_payload') = 'object'
      then p_payload->'raw_payload' else '{}'::jsonb end,
    fitmatch_catalog.runtime_product_fingerprint(v_name, v_path),
    case when p_payload->>'lifecycle_status' in ('active','unavailable','unknown')
      then p_payload->>'lifecycle_status' else 'active' end,
    coalesce((p_payload->>'observed_at')::timestamptz, now()),
    coalesce((p_payload->>'observed_at')::timestamptz, now())
  )
  on conflict (source, external_product_id) do update set
    product_name = excluded.product_name,
    canonical_url = coalesce(excluded.canonical_url, fitmatch_catalog.products.canonical_url),
    audience = coalesce(excluded.audience, fitmatch_catalog.products.audience),
    source_category_path = coalesce(excluded.source_category_path, fitmatch_catalog.products.source_category_path),
    source_category_codes = case
      when cardinality(excluded.source_category_codes) > 0
      then excluded.source_category_codes
      else fitmatch_catalog.products.source_category_codes
    end,
    image_url = coalesce(excluded.image_url, fitmatch_catalog.products.image_url),
    raw_payload = fitmatch_catalog.products.raw_payload || excluded.raw_payload,
    input_fingerprint = excluded.input_fingerprint,
    lifecycle_status = excluded.lifecycle_status,
    last_seen_at = greatest(fitmatch_catalog.products.last_seen_at, excluded.last_seen_at),
    updated_at = now()
  returning id into v_product_id;

  insert into fitmatch_catalog.product_variants (
    product_id, external_variant_id, variant_name, raw_payload
  ) values (v_product_id, '__default__', '기본 옵션', '{}'::jsonb)
  on conflict (product_id, external_variant_id) do nothing;

  return v_product_id;
end $$;

create or replace function fitmatch_catalog.sync_product_from_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
begin
  new.product_id := fitmatch_catalog.runtime_upsert_product(
    jsonb_build_object(
      'source', new.source,
      'external_product_id', new.external_product_id,
      'product_name', new.product_name,
      'canonical_url', new.canonical_url,
      'audience', new.audience,
      'source_category_path', new.source_category_path,
      'source_category_codes', to_jsonb(new.source_category_codes),
      'image_url', new.image_url,
      'raw_payload', new.raw_summary,
      'observed_at', new.collected_at
    )
  );
  return new;
end $$;

drop trigger if exists source_product_snapshots_sync_product
  on fitmatch_catalog.source_product_snapshots;
create trigger source_product_snapshots_sync_product
before insert or update of product_name, source_category_path, raw_summary
on fitmatch_catalog.source_product_snapshots
for each row execute function fitmatch_catalog.sync_product_from_snapshot();

create or replace function fitmatch_catalog.runtime_record_product_classification(
  p_product_id uuid,
  p_decision jsonb
) returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_product fitmatch_catalog.products%rowtype;
  v_history_id uuid;
  v_status text := coalesce(p_decision->>'classification_status','unclassified');
  v_method text := coalesce(p_decision->>'classification_method','unknown');
  v_confirmation boolean := coalesce(
    (p_decision->>'requires_user_confirmation')::boolean,
    v_status <> 'confirmed'
  );
  v_release_id uuid := nullif(p_decision->>'mapping_release_id','')::uuid;
  v_decision_version text := coalesce(
    nullif(p_decision->>'decision_version',''),
    'runtime-unversioned'
  );
begin
  select * into v_product
  from fitmatch_catalog.products
  where id = p_product_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='product_not_found';
  end if;

  if v_status not in ('confirmed','review_required','not_comparable','unclassified') then
    raise exception using errcode='22023', message='invalid_classification_status';
  end if;
  if v_method not in (
    'canonical_product_decision','category_mapping','product_classifier',
    'manual_review','user_override','migration','unknown'
  ) then
    raise exception using errcode='22023', message='invalid_classification_method';
  end if;
  if v_status = 'confirmed' and (
    nullif(p_decision->>'category_code','') is null
    or nullif(p_decision->>'detail_code','') is null
    or v_confirmation
  ) then
    raise exception using errcode='22023', message='confirmed_classification_incomplete';
  end if;

  update fitmatch_catalog.product_classification_history
  set is_current = false,
      superseded_at = now()
  where product_id = p_product_id and is_current;

  insert into fitmatch_catalog.product_classification_history (
    product_id, input_fingerprint, category_code, detail_code,
    comparison_family_code, length_code, classification_status,
    classification_method, confidence, requires_user_confirmation,
    taxonomy_policy_version, mapping_release_id, decision_version,
    evidence, reviewed_by, reviewed_at
  ) values (
    p_product_id,
    v_product.input_fingerprint,
    nullif(p_decision->>'category_code',''),
    nullif(p_decision->>'detail_code',''),
    nullif(p_decision->>'family_code',''),
    nullif(p_decision->>'length_code',''),
    v_status,
    v_method,
    nullif(p_decision->>'confidence','')::numeric,
    v_confirmation,
    nullif(p_decision->>'taxonomy_policy_version',''),
    v_release_id,
    v_decision_version,
    case when jsonb_typeof(p_decision->'evidence') = 'object'
      then p_decision->'evidence' else '{}'::jsonb end,
    nullif(p_decision->>'reviewed_by','')::uuid,
    nullif(p_decision->>'reviewed_at','')::timestamptz
  ) returning id into v_history_id;

  if coalesce((p_decision->>'write_canonical_cache')::boolean, false) then
    if v_release_id is null then
      raise exception using errcode='22023', message='canonical_cache_requires_release_id';
    end if;
    insert into fitmatch_catalog.product_classification_decisions (
      source, external_product_id, product_name, source_category_path,
      input_fingerprint, category_code, detail_code, comparison_family,
      length_type, requires_user_confirmation, release_id,
      decision_version, evidence
    ) values (
      v_product.source,
      v_product.external_product_id,
      v_product.product_name,
      coalesce(v_product.source_category_path,''),
      v_product.input_fingerprint,
      nullif(p_decision->>'category_code',''),
      nullif(p_decision->>'detail_code',''),
      nullif(p_decision->>'family_code',''),
      nullif(p_decision->>'length_code',''),
      v_confirmation,
      v_release_id,
      v_decision_version,
      case when jsonb_typeof(p_decision->'evidence') = 'object'
        then p_decision->'evidence' else '{}'::jsonb end
    )
    on conflict (source, external_product_id) do update set
      product_name = excluded.product_name,
      source_category_path = excluded.source_category_path,
      input_fingerprint = excluded.input_fingerprint,
      category_code = excluded.category_code,
      detail_code = excluded.detail_code,
      comparison_family = excluded.comparison_family,
      length_type = excluded.length_type,
      requires_user_confirmation = excluded.requires_user_confirmation,
      release_id = excluded.release_id,
      decision_version = excluded.decision_version,
      evidence = excluded.evidence,
      updated_at = now();
  end if;

  return v_history_id;
end $$;

create or replace function fitmatch_catalog.runtime_normalize_measurement(
  p_source text,
  p_raw_label text,
  p_raw_value numeric,
  p_raw_unit text default 'cm',
  p_category_scope text default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, fitmatch_taxonomy
as $$
declare
  v_alias fitmatch_taxonomy.source_measurement_aliases%rowtype;
  v_normalized_label text := lower(regexp_replace(btrim(coalesce(p_raw_label,'')), E'\\s+', ' ', 'g'));
begin
  if p_raw_value is null or p_raw_value <= 0 then
    return jsonb_build_object(
      'mapped',false,'comparable',false,'reason','invalid_raw_value'
    );
  end if;

  select a.* into v_alias
  from fitmatch_taxonomy.source_measurement_aliases a
  left join fitmatch_taxonomy.policy_versions pv on pv.code = a.policy_version
  where a.source_code = lower(p_source)
    and (
      a.normalized_raw_label = v_normalized_label
      or lower(regexp_replace(btrim(a.raw_label), E'\\s+', ' ', 'g')) = v_normalized_label
    )
    and (
      p_category_scope is null
      or a.category_scopes is null
      or cardinality(a.category_scopes) = 0
      or p_category_scope = any(a.category_scopes)
    )
  order by pv.created_at desc nulls last, a.id
  limit 1;

  if not found then
    return jsonb_build_object(
      'mapped',false,
      'comparable',false,
      'reason','measurement_alias_not_found',
      'raw_label',p_raw_label,
      'raw_value',p_raw_value,
      'raw_unit',coalesce(p_raw_unit,'cm')
    );
  end if;

  return jsonb_build_object(
    'mapped',true,
    'source_alias_id',v_alias.id,
    'measurement_code',v_alias.measurement_code,
    'raw_representation',v_alias.raw_representation,
    'comparison_basis',v_alias.comparison_basis,
    'conversion_multiplier',coalesce(v_alias.conversion_multiplier,1),
    'normalized_value',case when v_alias.is_comparable
      then p_raw_value * coalesce(v_alias.conversion_multiplier,1)
      else null end,
    'normalized_unit',coalesce(p_raw_unit,'cm'),
    'comparable',v_alias.is_comparable,
    'reason',case when v_alias.is_comparable then null else 'alias_marked_not_comparable' end,
    'policy_version',v_alias.policy_version,
    'evidence',v_alias.evidence
  );
end $$;

create or replace function fitmatch_catalog.runtime_upsert_variant(
  p_product_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_external_id text := btrim(coalesce(p_payload->>'external_variant_id','__default__'));
  v_id uuid;
begin
  if not exists (select 1 from fitmatch_catalog.products where id=p_product_id) then
    raise exception using errcode='P0002', message='product_not_found';
  end if;
  if v_external_id = '' then v_external_id := '__default__'; end if;

  insert into fitmatch_catalog.product_variants (
    product_id, external_variant_id, variant_name, color_code, color_name,
    sku, raw_payload, input_fingerprint, is_active
  ) values (
    p_product_id,
    v_external_id,
    nullif(p_payload->>'variant_name',''),
    nullif(p_payload->>'color_code',''),
    nullif(p_payload->>'color_name',''),
    nullif(p_payload->>'sku',''),
    case when jsonb_typeof(p_payload->'raw_payload')='object'
      then p_payload->'raw_payload' else '{}'::jsonb end,
    nullif(p_payload->>'input_fingerprint',''),
    coalesce((p_payload->>'is_active')::boolean,true)
  )
  on conflict (product_id, external_variant_id) do update set
    variant_name=excluded.variant_name,
    color_code=excluded.color_code,
    color_name=excluded.color_name,
    sku=excluded.sku,
    raw_payload=fitmatch_catalog.product_variants.raw_payload || excluded.raw_payload,
    input_fingerprint=excluded.input_fingerprint,
    is_active=excluded.is_active,
    updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

create or replace function fitmatch_catalog.runtime_upsert_size(
  p_variant_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_label text := btrim(coalesce(p_payload->>'size_label',''));
  v_identity text := btrim(coalesce(
    nullif(p_payload->>'size_identity',''),
    nullif(p_payload->>'external_size_id',''),
    lower(v_label)
  ));
  v_id uuid;
begin
  if not exists (select 1 from fitmatch_catalog.product_variants where id=p_variant_id) then
    raise exception using errcode='P0002', message='variant_not_found';
  end if;
  if v_label = '' or v_identity = '' then
    raise exception using errcode='22023', message='invalid_size_identity';
  end if;

  insert into fitmatch_catalog.product_sizes (
    variant_id, size_identity, external_size_id, size_label,
    normalized_size_label, display_order, stock_status, raw_payload,
    input_fingerprint, is_active
  ) values (
    p_variant_id,
    v_identity,
    nullif(p_payload->>'external_size_id',''),
    v_label,
    nullif(p_payload->>'normalized_size_label',''),
    nullif(p_payload->>'display_order','')::integer,
    case when p_payload->>'stock_status' in ('in_stock','out_of_stock','unknown')
      then p_payload->>'stock_status' else 'unknown' end,
    case when jsonb_typeof(p_payload->'raw_payload')='object'
      then p_payload->'raw_payload' else '{}'::jsonb end,
    nullif(p_payload->>'input_fingerprint',''),
    coalesce((p_payload->>'is_active')::boolean,true)
  )
  on conflict (variant_id, size_identity) do update set
    external_size_id=excluded.external_size_id,
    size_label=excluded.size_label,
    normalized_size_label=excluded.normalized_size_label,
    display_order=excluded.display_order,
    stock_status=excluded.stock_status,
    raw_payload=fitmatch_catalog.product_sizes.raw_payload || excluded.raw_payload,
    input_fingerprint=excluded.input_fingerprint,
    is_active=excluded.is_active,
    updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

create or replace function fitmatch_catalog.runtime_upsert_measurement(
  p_product_size_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_source text;
  v_raw_label text := btrim(coalesce(p_payload->>'raw_label',''));
  v_raw_value numeric := nullif(p_payload->>'raw_value','')::numeric;
  v_raw_unit text := coalesce(nullif(p_payload->>'raw_unit',''),'cm');
  v_identity text;
  v_normalized jsonb;
  v_id uuid;
begin
  select p.source into v_source
  from fitmatch_catalog.product_sizes s
  join fitmatch_catalog.product_variants v on v.id=s.variant_id
  join fitmatch_catalog.products p on p.id=v.product_id
  where s.id=p_product_size_id;
  if not found then
    raise exception using errcode='P0002', message='product_size_not_found';
  end if;
  if v_raw_label='' or v_raw_value is null or v_raw_value <= 0 then
    raise exception using errcode='22023', message='invalid_measurement';
  end if;

  v_identity := btrim(coalesce(
    nullif(p_payload->>'measurement_identity',''),
    nullif(p_payload->>'raw_code',''),
    lower(v_raw_label)
  ));
  v_normalized := fitmatch_catalog.runtime_normalize_measurement(
    v_source, v_raw_label, v_raw_value, v_raw_unit,
    nullif(p_payload->>'category_scope','')
  );

  insert into fitmatch_catalog.product_measurements (
    product_size_id, measurement_identity, measurement_code, raw_code,
    raw_label, raw_value, raw_unit, raw_representation,
    normalized_value, normalized_unit, comparison_basis,
    conversion_multiplier, is_comparable, exclusion_reason,
    source_alias_id, policy_version, evidence, observed_at
  ) values (
    p_product_size_id,
    v_identity,
    nullif(v_normalized->>'measurement_code',''),
    nullif(p_payload->>'raw_code',''),
    v_raw_label,
    v_raw_value,
    v_raw_unit,
    nullif(v_normalized->>'raw_representation',''),
    nullif(v_normalized->>'normalized_value','')::numeric,
    nullif(v_normalized->>'normalized_unit',''),
    nullif(v_normalized->>'comparison_basis',''),
    nullif(v_normalized->>'conversion_multiplier','')::numeric,
    coalesce((v_normalized->>'comparable')::boolean,false),
    nullif(v_normalized->>'reason',''),
    nullif(v_normalized->>'source_alias_id','')::uuid,
    nullif(v_normalized->>'policy_version',''),
    jsonb_build_object(
      'normalization',v_normalized,
      'source_payload',case when jsonb_typeof(p_payload->'evidence')='object'
        then p_payload->'evidence' else '{}'::jsonb end
    ),
    coalesce(nullif(p_payload->>'observed_at','')::timestamptz,now())
  )
  on conflict (product_size_id, measurement_identity) do update set
    measurement_code=excluded.measurement_code,
    raw_code=excluded.raw_code,
    raw_label=excluded.raw_label,
    raw_value=excluded.raw_value,
    raw_unit=excluded.raw_unit,
    raw_representation=excluded.raw_representation,
    normalized_value=excluded.normalized_value,
    normalized_unit=excluded.normalized_unit,
    comparison_basis=excluded.comparison_basis,
    conversion_multiplier=excluded.conversion_multiplier,
    is_comparable=excluded.is_comparable,
    exclusion_reason=excluded.exclusion_reason,
    source_alias_id=excluded.source_alias_id,
    policy_version=excluded.policy_version,
    evidence=excluded.evidence,
    observed_at=excluded.observed_at,
    updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

create or replace function fitmatch_catalog.runtime_ingest_product_payload(
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_product_id uuid;
  v_variant jsonb;
  v_size jsonb;
  v_measurement jsonb;
  v_variant_id uuid;
  v_size_id uuid;
  v_variants integer := 0;
  v_sizes integer := 0;
  v_measurements integer := 0;
begin
  v_product_id := fitmatch_catalog.runtime_upsert_product(p_payload);

  for v_variant in
    select value from jsonb_array_elements(
      case when jsonb_typeof(p_payload->'variants')='array'
        then p_payload->'variants'
        else jsonb_build_array(jsonb_build_object(
          'external_variant_id','__default__',
          'sizes',coalesce(p_payload->'sizes','[]'::jsonb)
        )) end
    )
  loop
    v_variant_id := fitmatch_catalog.runtime_upsert_variant(v_product_id,v_variant);
    v_variants := v_variants + 1;
    for v_size in
      select value from jsonb_array_elements(
        case when jsonb_typeof(v_variant->'sizes')='array'
          then v_variant->'sizes' else '[]'::jsonb end
      )
    loop
      v_size_id := fitmatch_catalog.runtime_upsert_size(v_variant_id,v_size);
      v_sizes := v_sizes + 1;
      for v_measurement in
        select value from jsonb_array_elements(
          case when jsonb_typeof(v_size->'measurements')='array'
            then v_size->'measurements' else '[]'::jsonb end
        )
      loop
        perform fitmatch_catalog.runtime_upsert_measurement(v_size_id,v_measurement);
        v_measurements := v_measurements + 1;
      end loop;
    end loop;
  end loop;

  return jsonb_build_object(
    'product_id',v_product_id,
    'variants_processed',v_variants,
    'sizes_processed',v_sizes,
    'measurements_processed',v_measurements
  );
end $$;

create or replace function fitmatch_catalog.runtime_resolve_product(
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog, fitmatch_taxonomy
as $$
declare
  v_product_id uuid;
  v_product fitmatch_catalog.products%rowtype;
  v_history fitmatch_catalog.product_classification_history%rowtype;
  v_resolution jsonb;
  v_history_id uuid;
  v_status text;
begin
  v_product_id := fitmatch_catalog.runtime_upsert_product(p_payload);
  select * into v_product from fitmatch_catalog.products where id=v_product_id;

  select * into v_history
  from fitmatch_catalog.product_classification_history
  where product_id=v_product_id
    and is_current
    and input_fingerprint=v_product.input_fingerprint;

  if not found then
    v_resolution := fitmatch_catalog.resolve_product_classification(
      v_product.source,
      v_product.external_product_id,
      v_product.product_name,
      coalesce(v_product.source_category_path,'')
    );
    v_status := case
      when coalesce((v_resolution->>'requires_user_confirmation')::boolean,true)
        then 'review_required'
      when v_resolution->>'category_code' is null
        or v_resolution->>'detail_code' is null
        then 'unclassified'
      else 'confirmed'
    end;
    v_history_id := fitmatch_catalog.runtime_record_product_classification(
      v_product_id,
      jsonb_build_object(
        'category_code',v_resolution->>'category_code',
        'detail_code',v_resolution->>'detail_code',
        'family_code',v_resolution->>'family_code',
        'length_code',v_resolution->>'length_code',
        'classification_status',v_status,
        'classification_method',case
          when v_resolution->>'decision_source'='canonical_product_decision'
            then 'canonical_product_decision'
          else 'unknown' end,
        'requires_user_confirmation',coalesce(
          (v_resolution->>'requires_user_confirmation')::boolean,true
        ),
        'decision_version',coalesce(
          v_resolution->>'decision_version','runtime-review-v1'
        ),
        'evidence',jsonb_build_object('resolution',v_resolution)
      )
    );
    select * into v_history
    from fitmatch_catalog.product_classification_history
    where id=v_history_id;
  end if;

  return jsonb_build_object(
    'product_id',v_product.id,
    'source',v_product.source,
    'external_product_id',v_product.external_product_id,
    'input_fingerprint',v_product.input_fingerprint,
    'classification',jsonb_build_object(
      'classification_id',v_history.id,
      'category_code',v_history.category_code,
      'detail_code',v_history.detail_code,
      'family_code',v_history.comparison_family_code,
      'length_code',v_history.length_code,
      'status',v_history.classification_status,
      'requires_user_confirmation',v_history.requires_user_confirmation,
      'decision_version',v_history.decision_version,
      'evidence',v_history.evidence
    ),
    'comparison_ready',
      v_history.classification_status='confirmed'
      and exists (
        select 1
        from fitmatch_catalog.product_variants v
        join fitmatch_catalog.product_sizes s on s.variant_id=v.id and s.is_active
        join fitmatch_catalog.product_measurements m
          on m.product_size_id=s.id and m.is_comparable
        where v.product_id=v_product_id and v.is_active
      )
  );
end $$;

create or replace function fitmatch_catalog.runtime_evaluate_comparison_profiles(
  p_reference_family text,
  p_reference_length text,
  p_target_family text,
  p_target_length text,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, fitmatch_taxonomy
as $$
declare
  v_rule fitmatch_taxonomy.comparison_compatibility_rules%rowtype;
  v_length_mismatch boolean;
begin
  if p_reference_family is null or p_target_family is null then
    return jsonb_build_object(
      'allowed',false,'level','incompatible','reason','comparison_family_missing'
    );
  end if;

  select r.* into v_rule
  from fitmatch_taxonomy.comparison_compatibility_rules r
  left join fitmatch_taxonomy.policy_versions pv on pv.code=r.policy_version
  where (
    r.from_family_code=p_reference_family
    and r.to_family_code=p_target_family
  ) or (
    not r.directional
    and r.from_family_code=p_target_family
    and r.to_family_code=p_reference_family
  )
  order by
    (r.from_family_code=p_reference_family
      and r.to_family_code=p_target_family) desc,
    pv.created_at desc nulls last
  limit 1;

  if not found then
    return jsonb_build_object(
      'allowed',false,'level','incompatible','reason','compatibility_rule_missing',
      'reference_family',p_reference_family,
      'target_family',p_target_family
    );
  end if;
  if not v_rule.allowed then
    return jsonb_build_object(
      'allowed',false,'level','incompatible','reason','compatibility_rule_denied',
      'policy_version',v_rule.policy_version
    );
  end if;

  if v_rule.length_match_required
     and (p_reference_length is null or p_target_length is null) then
    return jsonb_build_object(
      'allowed',false,'level','incompatible',
      'reason','length_classification_missing',
      'reference_length',p_reference_length,
      'target_length',p_target_length,
      'policy_version',v_rule.policy_version
    );
  end if;

  v_length_mismatch := p_reference_length is not null
    and p_target_length is not null
    and p_reference_length <> p_target_length;

  if v_rule.length_match_required and v_length_mismatch
     and not (p_allow_extended and v_rule.fallback_allowed) then
    return jsonb_build_object(
      'allowed',false,'level','incompatible','reason','length_mismatch',
      'reference_length',p_reference_length,
      'target_length',p_target_length,
      'policy_version',v_rule.policy_version
    );
  end if;

  return jsonb_build_object(
    'allowed',true,
    'level',case
      when v_rule.length_match_required and v_length_mismatch
        then 'extended' else 'direct' end,
    'reason',null,
    'reference_family',p_reference_family,
    'target_family',p_target_family,
    'reference_length',p_reference_length,
    'target_length',p_target_length,
    'length_mismatch',v_length_mismatch,
    'excluded_measurements',case
      when v_length_mismatch then to_jsonb(v_rule.length_mismatch_excluded_measurements)
      else '[]'::jsonb end,
    'minimum_common_measurements',v_rule.minimum_common_measurements,
    'required_measurements',to_jsonb(v_rule.required_measurements),
    'measurement_weights',v_rule.measurement_weights,
    'policy_version',v_rule.policy_version
  );
end $$;

create or replace function fitmatch_catalog.runtime_evaluate_product_compatibility(
  p_reference_product_id uuid,
  p_target_product_id uuid,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_reference fitmatch_catalog.product_classification_history%rowtype;
  v_target fitmatch_catalog.product_classification_history%rowtype;
begin
  select * into v_reference
  from fitmatch_catalog.product_classification_history
  where product_id=p_reference_product_id and is_current;
  select * into v_target
  from fitmatch_catalog.product_classification_history
  where product_id=p_target_product_id and is_current;

  if v_reference.id is null or v_target.id is null then
    return jsonb_build_object(
      'allowed',false,'level','incompatible','reason','classification_missing'
    );
  end if;
  if v_reference.classification_status <> 'confirmed'
     or v_target.classification_status <> 'confirmed' then
    return jsonb_build_object(
      'allowed',false,'level','incompatible','reason','classification_not_confirmed',
      'reference_status',v_reference.classification_status,
      'target_status',v_target.classification_status
    );
  end if;

  return fitmatch_catalog.runtime_evaluate_comparison_profiles(
    v_reference.comparison_family_code,
    v_reference.length_code,
    v_target.comparison_family_code,
    v_target.length_code,
    p_allow_extended
  );
end $$;

create or replace function fitmatch_catalog.runtime_prepare_size_comparison(
  p_reference_size_id uuid,
  p_target_size_id uuid,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_reference_product_id uuid;
  v_target_product_id uuid;
  v_compatibility jsonb;
  v_pairs jsonb;
  v_pair_count integer;
  v_missing_required text[];
  v_minimum integer;
begin
  select v.product_id into v_reference_product_id
  from fitmatch_catalog.product_sizes s
  join fitmatch_catalog.product_variants v on v.id=s.variant_id
  where s.id=p_reference_size_id;
  select v.product_id into v_target_product_id
  from fitmatch_catalog.product_sizes s
  join fitmatch_catalog.product_variants v on v.id=s.variant_id
  where s.id=p_target_size_id;
  if v_reference_product_id is null or v_target_product_id is null then
    return jsonb_build_object(
      'ready',false,'reason','product_size_not_found','pairs','[]'::jsonb
    );
  end if;

  v_compatibility := fitmatch_catalog.runtime_evaluate_product_compatibility(
    v_reference_product_id,v_target_product_id,p_allow_extended
  );
  if not coalesce((v_compatibility->>'allowed')::boolean,false) then
    return jsonb_build_object(
      'ready',false,
      'reason',v_compatibility->>'reason',
      'compatibility',v_compatibility,
      'pairs','[]'::jsonb
    );
  end if;

  with pairs as (
    select
      r.measurement_code,
      r.normalized_value as reference_value,
      t.normalized_value as target_value,
      t.normalized_value-r.normalized_value as signed_difference,
      abs(t.normalized_value-r.normalized_value) as absolute_difference,
      coalesce(
        nullif(v_compatibility->'measurement_weights'->>r.measurement_code,'')::numeric,
        1
      ) as weight
    from fitmatch_catalog.product_measurements r
    join fitmatch_catalog.product_measurements t
      on t.product_size_id=p_target_size_id
     and t.measurement_code=r.measurement_code
     and t.is_comparable
    where r.product_size_id=p_reference_size_id
      and r.is_comparable
      and r.measurement_code is not null
      and not (
        (v_compatibility->'excluded_measurements') ? r.measurement_code
      )
  )
  select coalesce(jsonb_agg(to_jsonb(p) order by p.measurement_code),'[]'::jsonb),
         count(*)
    into v_pairs,v_pair_count
  from pairs p;

  select coalesce(array_agg(required_code order by required_code),'{}'::text[])
    into v_missing_required
  from jsonb_array_elements_text(
    coalesce(v_compatibility->'required_measurements','[]'::jsonb)
  ) as required(required_code)
  where not exists (
    select 1 from jsonb_array_elements(v_pairs) as pairs(pair)
    where pair->>'measurement_code'=required_code
  );

  v_minimum := coalesce(
    nullif(v_compatibility->>'minimum_common_measurements','')::integer,1
  );

  return jsonb_build_object(
    'ready',v_pair_count >= v_minimum and cardinality(v_missing_required)=0,
    'reason',case
      when v_pair_count < v_minimum then 'insufficient_common_measurements'
      when cardinality(v_missing_required)>0 then 'required_measurements_missing'
      else null end,
    'compatibility',v_compatibility,
    'common_measurement_count',v_pair_count,
    'minimum_common_measurements',v_minimum,
    'missing_required_measurements',to_jsonb(v_missing_required),
    'pairs',v_pairs
  );
end $$;

-- Authenticated RPC: resolve or stage a product without exposing private
-- catalog tables. SECURITY DEFINER is bounded by auth.uid(), fixed search_path,
-- strict payload validation, no dynamic SQL, and explicit EXECUTE grants.
create or replace function public.fitmatch_resolve_product(
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_source text := lower(btrim(coalesce(p_payload->>'source','')));
  v_external_id text := btrim(coalesce(p_payload->>'external_product_id',''));
  v_name text := btrim(coalesce(p_payload->>'product_name',''));
  v_path text := nullif(btrim(coalesce(p_payload->>'source_category_path','')), '');
  v_fingerprint text;
  v_product fitmatch_catalog.products%rowtype;
  v_history fitmatch_catalog.product_classification_history%rowtype;
  v_resolution jsonb;
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode='42501', message='authentication_required';
  end if;
  if jsonb_typeof(p_payload)<>'object'
     or v_source !~ '^[a-z][a-z0-9_]*$'
     or v_external_id=''
     or length(v_external_id)>200
     or v_name=''
     or length(v_name)>1000 then
    raise exception using errcode='22023', message='invalid_product_payload';
  end if;

  v_fingerprint := fitmatch_catalog.runtime_product_fingerprint(v_name,v_path);
  select * into v_product
  from fitmatch_catalog.products
  where source=v_source and external_product_id=v_external_id;

  if found and v_product.input_fingerprint=v_fingerprint then
    select * into v_history
    from fitmatch_catalog.product_classification_history
    where product_id=v_product.id
      and input_fingerprint=v_fingerprint
      and is_current;
    if found then
      return jsonb_build_object(
        'product_id',v_product.id,
        'intake_request_id',null,
        'catalog_state','current',
        'classification',jsonb_build_object(
          'classification_id',v_history.id,
          'category_code',v_history.category_code,
          'detail_code',v_history.detail_code,
          'family_code',v_history.comparison_family_code,
          'length_code',v_history.length_code,
          'status',v_history.classification_status,
          'requires_user_confirmation',v_history.requires_user_confirmation,
          'decision_version',v_history.decision_version,
          'evidence',v_history.evidence
        ),
        'comparison_ready',
          v_history.classification_status='confirmed'
          and exists (
            select 1
            from fitmatch_catalog.product_variants v
            join fitmatch_catalog.product_sizes s
              on s.variant_id=v.id and s.is_active
            join fitmatch_catalog.product_measurements m
              on m.product_size_id=s.id and m.is_comparable
            where v.product_id=v_product.id and v.is_active
          )
      );
    end if;
  end if;

  v_resolution := fitmatch_catalog.resolve_product_classification(
    v_source,v_external_id,v_name,coalesce(v_path,'')
  );
  insert into public.product_intake_requests (
    user_id,source,external_product_id,input_fingerprint,submitted_payload
  ) values (
    v_user_id,v_source,v_external_id,v_fingerprint,p_payload
  )
  on conflict (user_id,source,external_product_id,input_fingerprint)
  do update set submitted_payload=excluded.submitted_payload,updated_at=now()
  returning id into v_request_id;

  return jsonb_build_object(
    'product_id',case when v_product.id is null then null else v_product.id end,
    'intake_request_id',v_request_id,
    'catalog_state',case when v_product.id is null then 'new' else 'changed' end,
    'classification',jsonb_build_object(
      'classification_id',null,
      'category_code',null,
      'detail_code',null,
      'family_code',null,
      'length_code',null,
      'status','review_required',
      'requires_user_confirmation',true,
      'decision_version',null,
      'evidence',jsonb_build_object('resolution',v_resolution)
    ),
    'comparison_ready',false
  );
end $$;

create or replace function public.fitmatch_register_closet_item(
  p_product_id uuid,
  p_product_size_id uuid default null,
  p_is_reference boolean default false,
  p_override jsonb default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_product fitmatch_catalog.products%rowtype;
  v_classification fitmatch_catalog.product_classification_history%rowtype;
  v_size fitmatch_catalog.product_sizes%rowtype;
  v_variant_id uuid;
  v_source_id uuid;
  v_category text;
  v_detail text;
  v_family text;
  v_length text;
  v_item_id uuid;
  v_measurements jsonb;
begin
  if v_user_id is null then
    raise exception using errcode='42501', message='authentication_required';
  end if;
  select * into v_product from fitmatch_catalog.products where id=p_product_id;
  if not found then
    raise exception using errcode='P0002', message='product_not_found';
  end if;
  select * into v_classification
  from fitmatch_catalog.product_classification_history
  where product_id=p_product_id and is_current;
  if not found then
    raise exception using errcode='P0002', message='classification_not_found';
  end if;
  if p_override is null and v_classification.classification_status <> 'confirmed' then
    raise exception using errcode='22023', message='user_classification_required';
  end if;

  if p_product_size_id is not null then
    select s.* into v_size
    from fitmatch_catalog.product_sizes s
    join fitmatch_catalog.product_variants v on v.id=s.variant_id
    where s.id=p_product_size_id and v.product_id=p_product_id;
    if not found then
      raise exception using errcode='22023', message='product_size_mismatch';
    end if;
    v_variant_id := v_size.variant_id;
  end if;

  if p_override is not null and (
    jsonb_typeof(p_override)<>'object'
    or nullif(p_override->>'category_code','') is null
    or nullif(p_override->>'detail_code','') is null
    or nullif(p_override->>'family_code','') is null
  ) then
    raise exception using errcode='22023', message='invalid_override';
  end if;
  v_category := coalesce(nullif(p_override->>'category_code',''),v_classification.category_code);
  v_detail := coalesce(nullif(p_override->>'detail_code',''),v_classification.detail_code);
  v_family := case when p_override is null
    then v_classification.comparison_family_code
    else nullif(p_override->>'family_code','') end;
  v_length := case when p_override is null
    then v_classification.length_code
    else nullif(p_override->>'length_code','') end;
  if v_category is null or v_detail is null then
    raise exception using errcode='22023', message='user_classification_required';
  end if;

  select id into v_source_id from public.sources where code=v_product.source;
  select coalesce(jsonb_object_agg(m.measurement_code,m.normalized_value),'{}'::jsonb)
    into v_measurements
  from fitmatch_catalog.product_measurements m
  where m.product_size_id=p_product_size_id
    and m.is_comparable and m.measurement_code is not null;

  if p_is_reference then
    update public.closet_items
    set is_reference=false,updated_at=now()
    where user_id=v_user_id and deleted_at is null and is_reference
      and app_category=v_category
      and app_detail_category=v_detail;
  end if;

  insert into public.closet_items (
    user_id, source_id, brand, product_name, size_name, gender,
    app_category, app_detail_category, original_category_path, source,
    product_url, image_url, measurements, is_reference,
    classification_status, classification_source, comparison_policy_version,
    product_id, variant_id, product_size_id, canonical_classification_id,
    canonical_category_code, canonical_detail_code, comparison_family_code,
    comparison_length_code, classification_snapshot
  ) values (
    v_user_id,v_source_id,v_product.raw_payload->>'brand',v_product.product_name,
    v_size.size_label,v_product.audience,v_category,v_detail,
    v_product.source_category_path,v_product.source,v_product.canonical_url,
    v_product.image_url,coalesce(v_measurements,'{}'::jsonb),p_is_reference,
    'confirmed',case when p_override is null then 'product_metadata' else 'manual_override' end,
    v_classification.decision_version,p_product_id,v_variant_id,p_product_size_id,
    v_classification.id,v_classification.category_code,v_classification.detail_code,
    v_classification.comparison_family_code,v_classification.length_code,
    jsonb_build_object(
      'classification_id',v_classification.id,
      'category_code',v_classification.category_code,
      'detail_code',v_classification.detail_code,
      'family_code',v_classification.comparison_family_code,
      'length_code',v_classification.length_code,
      'decision_version',v_classification.decision_version
    )
  ) returning id into v_item_id;

  if p_override is not null then
    insert into public.closet_item_classification_overrides (
      closet_item_id,user_id,category_code,detail_code,
      comparison_family_code,length_code,reason,evidence
    ) values (
      v_item_id,v_user_id,v_category,v_detail,v_family,v_length,
      nullif(p_override->>'reason',''),
      case when jsonb_typeof(p_override->'evidence')='object'
        then p_override->'evidence' else '{}'::jsonb end
    );
  end if;
  return v_item_id;
end $$;

create or replace function public.fitmatch_set_closet_classification_override(
  p_closet_item_id uuid,
  p_override jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using errcode='42501', message='authentication_required';
  end if;
  if jsonb_typeof(p_override)<>'object'
     or nullif(p_override->>'category_code','') is null
     or nullif(p_override->>'detail_code','') is null
     or nullif(p_override->>'family_code','') is null then
    raise exception using errcode='22023', message='invalid_override';
  end if;
  if not exists (
    select 1 from public.closet_items
    where id=p_closet_item_id and user_id=v_user_id and deleted_at is null
  ) then
    raise exception using errcode='P0002', message='closet_item_not_found';
  end if;

  insert into public.closet_item_classification_overrides (
    closet_item_id,user_id,category_code,detail_code,
    comparison_family_code,length_code,reason,evidence
  ) values (
    p_closet_item_id,v_user_id,p_override->>'category_code',p_override->>'detail_code',
    nullif(p_override->>'family_code',''),nullif(p_override->>'length_code',''),
    nullif(p_override->>'reason',''),
    case when jsonb_typeof(p_override->'evidence')='object'
      then p_override->'evidence' else '{}'::jsonb end
  )
  on conflict (closet_item_id,user_id) do update set
    category_code=excluded.category_code,
    detail_code=excluded.detail_code,
    comparison_family_code=excluded.comparison_family_code,
    length_code=excluded.length_code,
    reason=excluded.reason,
    evidence=excluded.evidence,
    updated_at=now();

  update public.closet_items
  set app_category=p_override->>'category_code',
      app_detail_category=p_override->>'detail_code',
      classification_source='manual_override',
      updated_at=now()
  where id=p_closet_item_id and user_id=v_user_id;

  return jsonb_build_object(
    'closet_item_id',p_closet_item_id,
    'category_code',p_override->>'category_code',
    'detail_code',p_override->>'detail_code'
  );
end $$;

create or replace function public.fitmatch_clear_closet_classification_override(
  p_closet_item_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_category text;
  v_detail text;
begin
  if v_user_id is null then
    raise exception using errcode='42501', message='authentication_required';
  end if;
  select canonical_category_code,canonical_detail_code
    into v_category,v_detail
  from public.closet_items
  where id=p_closet_item_id and user_id=v_user_id and deleted_at is null
  for update;
  if not found then
    raise exception using errcode='P0002', message='closet_item_not_found';
  end if;
  if v_category is null or v_detail is null then
    raise exception using errcode='22023', message='canonical_classification_missing';
  end if;

  delete from public.closet_item_classification_overrides
  where closet_item_id=p_closet_item_id and user_id=v_user_id;
  update public.closet_items
  set app_category=v_category,
      app_detail_category=v_detail,
      classification_source='product_metadata',
      updated_at=now()
  where id=p_closet_item_id and user_id=v_user_id;

  return jsonb_build_object(
    'closet_item_id',p_closet_item_id,
    'category_code',v_category,
    'detail_code',v_detail,
    'has_user_override',false
  );
end $$;

create or replace function public.fitmatch_begin_comparison(
  p_reference_item_id uuid,
  p_target_product_id uuid,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_reference_product_id uuid;
  v_reference_family text;
  v_reference_length text;
  v_target_family text;
  v_target_length text;
  v_target_status text;
  v_compatibility jsonb;
  v_run_id uuid;
  v_status text;
begin
  if v_user_id is null then
    raise exception using errcode='42501', message='authentication_required';
  end if;
  select
    c.product_id,
    case when o.id is not null
      then o.comparison_family_code else c.comparison_family_code end,
    case when o.id is not null
      then o.length_code else c.comparison_length_code end
  into v_reference_product_id,v_reference_family,v_reference_length
  from public.closet_items c
  left join public.closet_item_classification_overrides o
    on o.closet_item_id=c.id and o.user_id=c.user_id
  where c.id=p_reference_item_id
    and c.user_id=v_user_id
    and c.deleted_at is null;
  if v_reference_product_id is null then
    raise exception using errcode='P0002', message='reference_product_not_linked';
  end if;
  if not exists (select 1 from fitmatch_catalog.products where id=p_target_product_id) then
    raise exception using errcode='P0002', message='target_product_not_found';
  end if;

  select classification_status,comparison_family_code,length_code
    into v_target_status,v_target_family,v_target_length
  from fitmatch_catalog.product_classification_history
  where product_id=p_target_product_id and is_current;
  if not found or v_target_status <> 'confirmed' then
    v_compatibility := jsonb_build_object(
      'allowed',false,'level','incompatible',
      'reason','target_classification_not_confirmed',
      'target_status',v_target_status
    );
  else
    v_compatibility := fitmatch_catalog.runtime_evaluate_comparison_profiles(
      v_reference_family,v_reference_length,
      v_target_family,v_target_length,p_allow_extended
    );
  end if;
  v_status := case when coalesce((v_compatibility->>'allowed')::boolean,false)
    then 'pending' else 'blocked' end;

  insert into public.comparison_runs (
    user_id,reference_item_id,target_product_id,status,comparison_level,
    block_reason,comparison_policy_version,input_snapshot,
    completed_at
  ) values (
    v_user_id,p_reference_item_id,p_target_product_id,v_status,
    v_compatibility->>'level',v_compatibility->>'reason',
    v_compatibility->>'policy_version',
    jsonb_build_object('compatibility',v_compatibility),
    case when v_status='blocked' then now() else null end
  ) returning id into v_run_id;

  return jsonb_build_object(
    'run_id',v_run_id,
    'status',v_status,
    'compatibility',v_compatibility
  );
end $$;

create or replace function public.fitmatch_complete_comparison(
  p_run_id uuid,
  p_result_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_run public.comparison_runs%rowtype;
  v_result jsonb;
  v_measurement jsonb;
  v_result_id uuid;
  v_target_size_id uuid;
  v_result_count integer := 0;
begin
  if v_user_id is null then
    raise exception using errcode='42501', message='authentication_required';
  end if;
  if jsonb_typeof(p_result_payload)<>'object'
     or jsonb_typeof(p_result_payload->'results')<>'array'
     or jsonb_array_length(p_result_payload->'results')=0 then
    raise exception using errcode='22023', message='invalid_result_payload';
  end if;
  select * into v_run
  from public.comparison_runs
  where id=p_run_id and user_id=v_user_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='comparison_run_not_found';
  end if;
  if v_run.status='blocked' then
    raise exception using errcode='22023', message='blocked_run_cannot_complete';
  end if;

  for v_result in select value from jsonb_array_elements(p_result_payload->'results')
  loop
    v_target_size_id := nullif(v_result->>'target_size_id','')::uuid;
    if v_target_size_id is null or not exists (
      select 1
      from fitmatch_catalog.product_sizes s
      join fitmatch_catalog.product_variants v on v.id=s.variant_id
      where s.id=v_target_size_id and v.product_id=v_run.target_product_id
    ) then
      raise exception using errcode='22023', message='target_size_mismatch';
    end if;
    insert into public.comparison_results (
      run_id,user_id,target_size_id,similarity_score,rank,confidence_code,
      is_recommended,is_comparable,exclusion_reason,result_snapshot
    ) values (
      p_run_id,v_user_id,v_target_size_id,
      nullif(v_result->>'similarity_score','')::numeric,
      nullif(v_result->>'rank','')::integer,
      nullif(v_result->>'confidence_code',''),
      coalesce((v_result->>'is_recommended')::boolean,false),
      coalesce((v_result->>'is_comparable')::boolean,false),
      nullif(v_result->>'exclusion_reason',''),
      case when jsonb_typeof(v_result->'snapshot')='object'
        then v_result->'snapshot' else '{}'::jsonb end
    )
    on conflict (run_id,target_size_id) do update set
      similarity_score=excluded.similarity_score,
      rank=excluded.rank,
      confidence_code=excluded.confidence_code,
      is_recommended=excluded.is_recommended,
      is_comparable=excluded.is_comparable,
      exclusion_reason=excluded.exclusion_reason,
      result_snapshot=excluded.result_snapshot
    returning id into v_result_id;

    delete from public.comparison_measurement_results
    where result_id=v_result_id and user_id=v_user_id;
    for v_measurement in select value from jsonb_array_elements(
      case when jsonb_typeof(v_result->'measurements')='array'
        then v_result->'measurements' else '[]'::jsonb end
    )
    loop
      if nullif(v_measurement->>'measurement_code','') is null then
        raise exception using errcode='22023', message='measurement_code_required';
      end if;
      insert into public.comparison_measurement_results (
        result_id,user_id,measurement_code,reference_value,target_value,
        signed_difference,absolute_difference,weight,included,
        exclusion_reason,evidence
      ) values (
        v_result_id,v_user_id,v_measurement->>'measurement_code',
        nullif(v_measurement->>'reference_value','')::numeric,
        nullif(v_measurement->>'target_value','')::numeric,
        nullif(v_measurement->>'signed_difference','')::numeric,
        nullif(v_measurement->>'absolute_difference','')::numeric,
        nullif(v_measurement->>'weight','')::numeric,
        coalesce((v_measurement->>'included')::boolean,true),
        nullif(v_measurement->>'exclusion_reason',''),
        case when jsonb_typeof(v_measurement->'evidence')='object'
          then v_measurement->'evidence' else '{}'::jsonb end
      );
    end loop;
    v_result_count := v_result_count + 1;
  end loop;

  update public.comparison_runs
  set status='completed',
      result_summary=case when jsonb_typeof(p_result_payload->'summary')='object'
        then p_result_payload->'summary' else '{}'::jsonb end,
      completed_at=now()
  where id=p_run_id and user_id=v_user_id;

  insert into public.comparison_history (
    user_id,reference_item_id,product_snapshot,result_snapshot,comparison_run_id
  ) values (
    v_user_id,v_run.reference_item_id,
    jsonb_build_object('target_product_id',v_run.target_product_id),
    p_result_payload,p_run_id
  );

  return jsonb_build_object(
    'run_id',p_run_id,'status','completed','result_count',v_result_count
  );
end $$;

-- Effective classification view keeps shared canonical truth and per-user
-- presentation overrides visible as separate fields.
create or replace view public.closet_items_effective
with (security_invoker = true)
as
select
  c.*,
  coalesce(o.category_code,c.canonical_category_code,c.app_category)
    as effective_category_code,
  coalesce(o.detail_code,c.canonical_detail_code,c.app_detail_category)
    as effective_detail_code,
  case when o.id is not null
    then o.comparison_family_code else c.comparison_family_code end
    as effective_family_code,
  case when o.id is not null
    then o.length_code else c.comparison_length_code end
    as effective_length_code,
  (o.id is not null) as has_user_override,
  o.reason as user_override_reason,
  o.updated_at as user_override_updated_at
from public.closet_items c
left join public.closet_item_classification_overrides o
  on o.closet_item_id=c.id and o.user_id=c.user_id;

revoke all on public.closet_items_effective from anon;
grant select on public.closet_items_effective to authenticated;
revoke insert,update,delete on public.closet_item_classification_overrides
  from public,anon,authenticated;

-- Internal functions are never client-callable.
revoke all on function fitmatch_catalog.runtime_product_fingerprint(text,text)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_upsert_product(jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_record_product_classification(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_normalize_measurement(text,text,numeric,text,text)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_upsert_variant(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_upsert_size(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_upsert_measurement(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_ingest_product_payload(jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_resolve_product(jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_evaluate_comparison_profiles(text,text,text,text,boolean)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_evaluate_product_compatibility(uuid,uuid,boolean)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_prepare_size_comparison(uuid,uuid,boolean)
  from public,anon,authenticated;

grant execute on function fitmatch_catalog.runtime_product_fingerprint(text,text)
  to service_role;
grant execute on function fitmatch_catalog.runtime_upsert_product(jsonb)
  to service_role;
grant execute on function fitmatch_catalog.runtime_record_product_classification(uuid,jsonb)
  to service_role;
grant execute on function fitmatch_catalog.runtime_normalize_measurement(text,text,numeric,text,text)
  to service_role;
grant execute on function fitmatch_catalog.runtime_upsert_variant(uuid,jsonb)
  to service_role;
grant execute on function fitmatch_catalog.runtime_upsert_size(uuid,jsonb)
  to service_role;
grant execute on function fitmatch_catalog.runtime_upsert_measurement(uuid,jsonb)
  to service_role;
grant execute on function fitmatch_catalog.runtime_ingest_product_payload(jsonb)
  to service_role;
grant execute on function fitmatch_catalog.runtime_resolve_product(jsonb)
  to service_role;
grant execute on function fitmatch_catalog.runtime_evaluate_comparison_profiles(text,text,text,text,boolean)
  to service_role;
grant execute on function fitmatch_catalog.runtime_evaluate_product_compatibility(uuid,uuid,boolean)
  to service_role;
grant execute on function fitmatch_catalog.runtime_prepare_size_comparison(uuid,uuid,boolean)
  to service_role;

-- Public RPCs default to PUBLIC execution unless explicitly revoked.
revoke all on function public.fitmatch_resolve_product(jsonb)
  from public,anon;
revoke all on function public.fitmatch_register_closet_item(uuid,uuid,boolean,jsonb)
  from public,anon;
revoke all on function public.fitmatch_set_closet_classification_override(uuid,jsonb)
  from public,anon;
revoke all on function public.fitmatch_clear_closet_classification_override(uuid)
  from public,anon;
revoke all on function public.fitmatch_begin_comparison(uuid,uuid,boolean)
  from public,anon;
revoke all on function public.fitmatch_complete_comparison(uuid,jsonb)
  from public,anon;

grant execute on function public.fitmatch_resolve_product(jsonb)
  to authenticated,service_role;
grant execute on function public.fitmatch_register_closet_item(uuid,uuid,boolean,jsonb)
  to authenticated,service_role;
grant execute on function public.fitmatch_set_closet_classification_override(uuid,jsonb)
  to authenticated,service_role;
grant execute on function public.fitmatch_clear_closet_classification_override(uuid)
  to authenticated,service_role;
grant execute on function public.fitmatch_begin_comparison(uuid,uuid,boolean)
  to authenticated,service_role;
grant execute on function public.fitmatch_complete_comparison(uuid,jsonb)
  to authenticated,service_role;

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    cross join lateral aclexplode(
      coalesce(p.proacl,acldefault('f',p.proowner))
    ) acl
    where p.prosecdef
      and n.nspname='public'
      and p.proname like 'fitmatch_%'
      and acl.grantee=0
      and acl.privilege_type='EXECUTE'
  ) then
    raise exception 'public execute remains on a FitMatch security-definer RPC';
  end if;
end $$;

commit;
