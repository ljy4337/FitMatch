-- Authenticated, read-only product runtime contract for the iOS/domain client.
-- Keeps private catalog tables inaccessible while returning the exact IDs and
-- normalized measurements required by closet registration and comparison.

create or replace function public.fitmatch_get_product_runtime(
  p_payload jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_source text := lower(btrim(coalesce(p_payload->>'source', '')));
  v_external_id text := btrim(coalesce(p_payload->>'external_product_id', ''));
  v_name text := btrim(coalesce(p_payload->>'product_name', ''));
  v_path text := nullif(btrim(coalesce(p_payload->>'source_category_path', '')), '');
  v_audience text := nullif(btrim(coalesce(p_payload->>'audience', '')), '');
  v_codes text[] := case
    when jsonb_typeof(p_payload->'source_category_codes') = 'array'
      then array(select jsonb_array_elements_text(p_payload->'source_category_codes'))
    else '{}'::text[]
  end;
  v_fingerprint text;
  v_product fitmatch_catalog.products%rowtype;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if jsonb_typeof(p_payload) <> 'object'
     or v_source !~ '^[a-z][a-z0-9_]*$'
     or v_external_id = '' or length(v_external_id) > 200
     or v_name = '' or length(v_name) > 1000
     or (p_payload ? 'source_category_codes'
       and jsonb_typeof(p_payload->'source_category_codes') <> 'array') then
    raise exception using errcode = '22023', message = 'invalid_product_payload';
  end if;

  v_fingerprint := fitmatch_catalog.runtime_product_fingerprint(v_name, v_path);
  select * into v_product
  from fitmatch_catalog.products p
  where p.source = v_source and p.external_product_id = v_external_id;

  if not found
     or v_product.input_fingerprint <> v_fingerprint
     or (v_audience is not null
       and upper(coalesce(v_product.audience, '')) <> upper(v_audience))
     or (cardinality(v_codes) > 0
       and v_product.source_category_codes <> v_codes) then
    raise exception using errcode = 'P0002', message = 'product_evidence_mismatch';
  end if;

  select jsonb_build_object(
    'runtime_state',
      case
        when c.id is null or c.classification_status = 'review_required'
          then 'classification_required'
        when c.classification_status = 'not_comparable'
          then 'not_comparable'
        when c.classification_status <> 'confirmed'
          then 'classification_required'
        when not exists (
          select 1
          from fitmatch_catalog.product_variants v
          join fitmatch_catalog.product_sizes s on s.variant_id = v.id
          where v.product_id = p.id and v.is_active and s.is_active
        ) then 'sizes_required'
        when not exists (
          select 1
          from fitmatch_catalog.product_variants v
          join fitmatch_catalog.product_sizes s on s.variant_id = v.id
          join fitmatch_catalog.product_measurements m on m.product_size_id = s.id
          where v.product_id = p.id and v.is_active and s.is_active
            and m.is_comparable
            and m.measurement_code is not null
            and m.normalized_value is not null
        ) then 'measurements_required'
        else 'ready'
      end,
    'comparison_ready',
      c.classification_status = 'confirmed'
      and exists (
        select 1
        from fitmatch_catalog.product_variants v
        join fitmatch_catalog.product_sizes s on s.variant_id = v.id
        join fitmatch_catalog.product_measurements m on m.product_size_id = s.id
        where v.product_id = p.id and v.is_active and s.is_active
          and m.is_comparable
          and m.measurement_code is not null
          and m.normalized_value is not null
      ),
    'product', jsonb_build_object(
      'product_id', p.id,
      'source', p.source,
      'external_product_id', p.external_product_id,
      'product_name', p.product_name,
      'canonical_url', p.canonical_url,
      'audience', p.audience,
      'source_category_path', p.source_category_path,
      'source_category_codes', to_jsonb(p.source_category_codes),
      'image_url', p.image_url,
      'lifecycle_status', p.lifecycle_status,
      'input_fingerprint', p.input_fingerprint
    ),
    'classification',
      case when c.id is null then null else jsonb_build_object(
        'classification_id', c.id,
        'category_code', c.category_code,
        'detail_code', c.detail_code,
        'family_code', c.comparison_family_code,
        'length_code', c.length_code,
        'body_length_code', c.body_length_code,
        'status', c.classification_status,
        'method', c.classification_method,
        'confidence', c.confidence,
        'requires_user_confirmation', c.requires_user_confirmation,
        'taxonomy_policy_version', c.taxonomy_policy_version,
        'decision_version', c.decision_version,
        'evidence', c.evidence
      ) end,
    'variants', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'variant_id', v.id,
          'external_variant_id', v.external_variant_id,
          'variant_name', v.variant_name,
          'color_code', v.color_code,
          'color_name', v.color_name,
          'sizes', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'product_size_id', s.id,
                'external_size_id', s.external_size_id,
                'size_label', s.size_label,
                'normalized_size_label', s.normalized_size_label,
                'display_order', s.display_order,
                'stock_status', s.stock_status,
                'measurements', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'measurement_code', m.measurement_code,
                      'raw_label', m.raw_label,
                      'raw_value', m.raw_value,
                      'raw_unit', m.raw_unit,
                      'normalized_value', m.normalized_value,
                      'normalized_unit', m.normalized_unit,
                      'comparison_basis', m.comparison_basis,
                      'is_comparable', m.is_comparable,
                      'exclusion_reason', m.exclusion_reason,
                      'policy_version', m.policy_version
                    ) order by m.measurement_code nulls last, m.raw_label, m.id
                  )
                  from fitmatch_catalog.product_measurements m
                  where m.product_size_id = s.id
                ), '[]'::jsonb)
              ) order by s.display_order, s.normalized_size_label, s.id
            )
            from fitmatch_catalog.product_sizes s
            where s.variant_id = v.id and s.is_active
          ), '[]'::jsonb)
        ) order by v.color_code nulls last, v.variant_name nulls last, v.id
      )
      from fitmatch_catalog.product_variants v
      where v.product_id = p.id and v.is_active
    ), '[]'::jsonb)
  ) into v_result
  from fitmatch_catalog.products p
  left join fitmatch_catalog.product_classification_history c
    on c.product_id = p.id and c.is_current
  where p.id = v_product.id;

  if v_result is null then
    raise exception using errcode = 'P0002', message = 'product_not_found';
  end if;

  return v_result;
end
$$;

revoke all on function public.fitmatch_get_product_runtime(jsonb)
  from public, anon;
grant execute on function public.fitmatch_get_product_runtime(jsonb)
  to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon',
       'public.fitmatch_get_product_runtime(jsonb)', 'EXECUTE') then
    raise exception 'anon must not execute fitmatch_get_product_runtime';
  end if;
  if not has_function_privilege('authenticated',
       'public.fitmatch_get_product_runtime(jsonb)', 'EXECUTE') then
    raise exception 'authenticated must execute fitmatch_get_product_runtime';
  end if;
end
$$;
