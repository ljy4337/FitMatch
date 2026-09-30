CREATE OR REPLACE FUNCTION fitmatch_vnext.get_product_runtime(p_source_code text, p_source_product_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION fitmatch_vnext.get_product_runtime_for_swift(p_source_code text, p_source_product_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    runtime_value jsonb;
    effective_value jsonb;
    product_id_value uuid;
    category_value text;
    policy_value text;
    variant_value jsonb;
    size_value jsonb;
    variants_value jsonb := '[]'::jsonb;
    sizes_value jsonb;
begin
    runtime_value := fitmatch_vnext.get_product_runtime(
        p_source_code, p_source_product_key
    );
    if not coalesce((runtime_value ->> 'found')::boolean, false) then
        return runtime_value;
    end if;
    product_id_value := (runtime_value -> 'product' ->> 'id')::uuid;
    effective_value := fitmatch_vnext.effective_target_classification(
        product_id_value
    );

    select gt.category_code, gt.comparison_policy_code
    into category_value, policy_value
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code =
          runtime_value -> 'product' ->> 'garment_type_code'
      and gt.is_active;
    runtime_value := jsonb_set(runtime_value, '{product}',
        runtime_value -> 'product' || jsonb_build_object(
            'category_code', category_value,
            'comparison_policy_code', policy_value
        )
    );

    for variant_value in
        select value from jsonb_array_elements(runtime_value -> 'variants')
    loop
        sizes_value := '[]'::jsonb;
        for size_value in
            select value from jsonb_array_elements(variant_value -> 'sizes')
        loop
            size_value := jsonb_set(
                size_value,
                '{canonical_measurements}',
                fitmatch_vnext.canonical_measurements_for_size_with_context(
                    (size_value ->> 'id')::uuid,
                    effective_value
                )
            );
            sizes_value := sizes_value || jsonb_build_array(size_value);
        end loop;
        variant_value := jsonb_set(variant_value, '{sizes}', sizes_value);
        variants_value := variants_value || jsonb_build_array(variant_value);
    end loop;

    runtime_value := jsonb_set(runtime_value, '{variants}', variants_value);
    runtime_value := jsonb_set(
        runtime_value,
        '{readiness}',
        fitmatch_vnext.effective_product_readiness(product_id_value)
    );
    return runtime_value || jsonb_build_object(
        'effective_classification', effective_value
    );
end
$function$
;
DROP FUNCTION fitmatch_vnext.get_product_runtime_base(text,text,boolean);
