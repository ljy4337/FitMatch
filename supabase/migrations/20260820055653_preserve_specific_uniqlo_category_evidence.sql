begin;

-- A retailer page can temporarily expose a parent navigation path even when a
-- previously observed leaf path is still supported by the same category IDs.
-- Do not let that weaker observation invalidate a reviewed product decision.
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
    source_category_path = case
      when excluded.source_category_path is not null
       and fitmatch_catalog.products.source_category_path is not null
       and fitmatch_catalog.runtime_normalized_category_path(
             fitmatch_catalog.products.source_category_path
           ) like fitmatch_catalog.runtime_normalized_category_path(
             excluded.source_category_path
           ) || ' > %'
       and (
         cardinality(excluded.source_category_codes) = 0
         or cardinality(fitmatch_catalog.products.source_category_codes) = 0
         or excluded.source_category_codes = fitmatch_catalog.products.source_category_codes
       )
      then fitmatch_catalog.products.source_category_path
      else coalesce(excluded.source_category_path, fitmatch_catalog.products.source_category_path)
    end,
    source_category_codes = case
      when cardinality(excluded.source_category_codes) > 0
      then excluded.source_category_codes
      else fitmatch_catalog.products.source_category_codes
    end,
    image_url = coalesce(excluded.image_url, fitmatch_catalog.products.image_url),
    raw_payload = fitmatch_catalog.products.raw_payload || excluded.raw_payload,
    input_fingerprint = fitmatch_catalog.runtime_product_fingerprint(
      excluded.product_name,
      case
        when excluded.source_category_path is not null
         and fitmatch_catalog.products.source_category_path is not null
         and fitmatch_catalog.runtime_normalized_category_path(
               fitmatch_catalog.products.source_category_path
             ) like fitmatch_catalog.runtime_normalized_category_path(
               excluded.source_category_path
             ) || ' > %'
         and (
           cardinality(excluded.source_category_codes) = 0
           or cardinality(fitmatch_catalog.products.source_category_codes) = 0
           or excluded.source_category_codes = fitmatch_catalog.products.source_category_codes
         )
        then fitmatch_catalog.products.source_category_path
        else coalesce(excluded.source_category_path, fitmatch_catalog.products.source_category_path)
      end
    ),
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

comment on function fitmatch_catalog.runtime_upsert_product(jsonb) is
  'Upserts retailer product evidence while preserving a compatible, more-specific existing category path.';

-- Repair the one production product whose current page breadcrumb lost its
-- official leaf even though an existing reviewed decision already contains it.
do $$
declare
  v_product fitmatch_catalog.products%rowtype;
  v_decision fitmatch_catalog.product_classification_decisions%rowtype;
  v_result jsonb;
begin
  select * into strict v_product
  from fitmatch_catalog.products
  where source = 'uniqlo' and external_product_id = 'E485454';

  select * into strict v_decision
  from fitmatch_catalog.product_classification_decisions
  where source = v_product.source
    and external_product_id = v_product.external_product_id
    and source_category_path = 'Special Collaborations > UNIQLO and JW ANDERSON > Cut & Sewn'
    and category_code = 'tops'
    and detail_code = 'short_sleeve'
    and comparison_family = 'tshirt'
    and length_type = 'short_sleeve'
    and not requires_user_confirmation;

  v_result := fitmatch_catalog.runtime_resolve_and_promote_product(
    jsonb_build_object(
      'source', v_product.source,
      'external_product_id', v_product.external_product_id,
      'product_name', v_product.product_name,
      'canonical_url', v_product.canonical_url,
      'audience', v_product.audience,
      'source_category_path', v_decision.source_category_path,
      'source_category_codes', to_jsonb(v_product.source_category_codes),
      'image_url', v_product.image_url,
      'raw_payload', jsonb_build_object(
        'category_evidence_repair', 'preserve-specific-path-2026-08-20-v1'
      ),
      'observed_at', v_product.last_seen_at
    )
  );

  if v_result->'classification'->>'classification_status' <> 'confirmed'
     or v_result->'classification'->>'category_code' <> 'tops'
     or v_result->'classification'->>'detail_code' <> 'short_sleeve'
     or v_result->'classification'->>'family_code' <> 'tshirt'
     or v_result->'classification'->>'length_code' <> 'short_sleeve'
     or coalesce(
       (v_result->'classification'->>'requires_user_confirmation')::boolean,
       true
     ) then
    raise exception 'E485454 canonical repair failed: %', v_result;
  end if;
end $$;

commit;
;
