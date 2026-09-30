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
DROP FUNCTION public.fitmatch_vnext_get_closet_item(uuid);
DROP FUNCTION fitmatch_vnext.list_closet_items(uuid);
DROP FUNCTION fitmatch_vnext.list_closet_items_detail_snapshot_base(uuid);
DROP FUNCTION fitmatch_vnext.list_closet_items_snapshot_receipt_base(uuid);
DROP FUNCTION fitmatch_vnext.list_closet_items_snapshot_base(uuid);