-- Deployed definitions captured read-only 2026-09-24. Regression oracle only.
CREATE OR REPLACE FUNCTION fitmatch_vnext.list_closet_items_snapshot_base()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION fitmatch_vnext.list_closet_items_snapshot_receipt_base()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    prior_items jsonb;
begin
    prior_items := fitmatch_vnext.list_closet_items_snapshot_base();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'source_measurements', coalesce((
                select jsonb_agg(jsonb_build_object(
                    'raw_measurement_key', sm.raw_measurement_key,
                    'source_code', sm.source_code,
                    'parser_code', sm.parser_code,
                    'raw_code', sm.raw_code,
                    'raw_label', sm.raw_label,
                    'raw_value', sm.raw_value,
                    'raw_value_text', sm.raw_value_text,
                    'raw_unit_code', sm.raw_unit_code,
                    'raw_representation', sm.raw_representation,
                    'source_measurement_code', sm.source_measurement_code,
                    'resolution_status', sm.resolution_status,
                    'mapping_version', sm.mapping_version,
                    'evidence', sm.evidence_payload,
                    'observed_at', sm.source_observed_at
                ) order by sm.parser_code, sm.raw_measurement_key)
                from fitmatch_vnext.closet_item_source_measurements sm
                where sm.closet_item_id = (item ->> 'id')::uuid
            ), '[]'::jsonb)
        ) order by ordinal)
        from jsonb_array_elements(coalesce(prior_items, '[]'::jsonb))
            with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$
;
CREATE OR REPLACE FUNCTION fitmatch_vnext.list_closet_items_detail_snapshot_base()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    prior_items jsonb;
begin
    prior_items := fitmatch_vnext.list_closet_items_snapshot_receipt_base();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'source_measurement_snapshot', (
                select jsonb_build_object(
                    'source_observation_id', ss.source_observation_id,
                    'product_id', ss.product_id,
                    'product_variant_id', ss.product_variant_id,
                    'product_size_id', ss.product_size_id,
                    'source_measurement_count', ss.source_measurement_count
                )
                from fitmatch_vnext.closet_item_source_measurement_snapshots ss
                where ss.closet_item_id = (item ->> 'id')::uuid
            )
        ) order by ordinal)
        from jsonb_array_elements(coalesce(prior_items, '[]'::jsonb))
            with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$
;
CREATE OR REPLACE FUNCTION fitmatch_vnext.list_closet_items()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    prior_items jsonb;
begin
    prior_items := fitmatch_vnext.list_closet_items_detail_snapshot_base();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'closet_detail_code_snapshot', (
                select nullif(btrim(ci.closet_detail_code_snapshot), '')
                from fitmatch_vnext.closet_items ci
                where ci.id = (item ->> 'id')::uuid
            )
        ) order by ordinal)
        from jsonb_array_elements(coalesce(prior_items, '[]'::jsonb))
            with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$
;
CREATE OR REPLACE FUNCTION public.fitmatch_vnext_list_closet_items()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
    result_value jsonb;
begin
    result_value := fitmatch_vnext.list_closet_items();
    return coalesce((
        select jsonb_agg(item || jsonb_build_object(
            'comparison_group', fitmatch_vnext.closet_comparison_group((item ->> 'id')::uuid)
        ) order by ordinal)
        from jsonb_array_elements(result_value) with ordinality rows(item, ordinal)
    ), '[]'::jsonb);
end
$function$
;
CREATE OR REPLACE FUNCTION fitmatch_vnext.product_readiness(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  effective_value jsonb;
begin
  effective_value:=fitmatch_vnext.effective_target_classification(p_product_id);
  return fitmatch_vnext.product_measurement_readiness(
    p_product_id,coalesce(effective_value,'{}'::jsonb)
  );
end
$function$
;
CREATE OR REPLACE FUNCTION fitmatch_vnext.product_readiness_with_context(p_product_id uuid, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
    unit_value jsonb;
begin
    unit_value := fitmatch_vnext.product_comparison_unit_decision(p_product_id);
    if not coalesce((unit_value ->> 'eligible')::boolean, false) then
        return jsonb_build_object(
            'product_id', p_product_id,
            'ready', false,
            'status', case when unit_value ->> 'reason' in (
              'MIXED_GARMENT_SET','MULTIPLE_COMPONENT_MEASUREMENT_CONTRACT'
            ) then 'NOT_APPLICABLE' else 'CLASSIFICATION_REQUIRED' end,
            'reason', unit_value ->> 'reason',
            'comparison_unit', unit_value,
            'readiness_version', 'fitmatch-vnext-readiness-v3'
        );
    end if;
    return fitmatch_vnext.product_measurement_readiness(
        p_product_id, p_effective_classification
    );
end
$function$
;
CREATE OR REPLACE FUNCTION fitmatch_vnext.effective_product_readiness(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    effective_value jsonb;
begin
    effective_value := fitmatch_vnext.effective_target_classification(
        p_product_id
    );
    if effective_value ->> 'effective_source' = 'GLOBAL_CONFIRMED' then
        return fitmatch_vnext.product_readiness(p_product_id);
    end if;
    return fitmatch_vnext.product_readiness_with_context(
        p_product_id, effective_value
    );
end
$function$
;
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