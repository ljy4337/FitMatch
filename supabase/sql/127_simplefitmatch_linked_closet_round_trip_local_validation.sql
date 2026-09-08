-- CANDIDATE VALIDATION ONLY — run only after applying
-- 127_simplefitmatch_linked_closet_round_trip_candidate.sql to a disposable
-- local Supabase database with a known canonical Product / variant / size
-- fixture.  This script contains no Production identifiers and rolls every
-- synthetic Closet write back.

begin;

do $shape$
begin
    if to_regprocedure(
        'fitmatch_vnext.apply_linked_closet_snapshot_for_swift(jsonb,uuid)'
    ) is null then
        raise exception 'Simple FitMatch linked snapshot helper is missing';
    end if;
    if not exists (
        select 1
        from information_schema.columns
        where table_schema = 'fitmatch_vnext'
          and table_name = 'closet_items'
          and column_name = 'measurement_mode'
    ) or not exists (
        select 1
        from information_schema.columns
        where table_schema = 'fitmatch_vnext'
          and table_name = 'closet_item_measurements'
          and column_name = 'value_source'
    ) then
        raise exception 'Existing Closet-local provenance columns are missing';
    end if;
    if not has_function_privilege(
        'authenticated',
        'public.fitmatch_vnext_upsert_closet_item(jsonb)',
        'EXECUTE'
    ) or has_function_privilege(
        'anon',
        'public.fitmatch_vnext_upsert_closet_item(jsonb)',
        'EXECUTE'
    ) then
        raise exception 'upsert bridge privilege matrix changed';
    end if;
end
$shape$;

-- Replace the three fixture UUIDs below only in a disposable database.  The
-- fixture must have at least chest_width=55 and shoulder_width=47 canonical
-- rows for its selected ProductSize.  The assertions intentionally exercise
-- the public RPC bridge, then the list/read path, without mutating Products,
-- ProductSizes, or a second user.
--
-- select set_config('request.jwt.claim.sub', '<local fixture user uuid>', true);
-- select set_config('request.jwt.claim.role', 'authenticated', true);
--
-- do $round_trip$
-- declare
--     first_result jsonb;
--     listed jsonb;
--     item_id uuid;
-- begin
--     first_result := public.fitmatch_vnext_upsert_closet_item(jsonb_build_object(
--         'client_item_id', '<new local client uuid>',
--         'product_id', '<fixture product uuid>',
--         'product_variant_id', '<fixture variant uuid>',
--         'product_size_id', '<fixture size uuid>',
--         'satisfaction', 3,
--         'measurements', jsonb_build_array(
--             jsonb_build_object('fitmatch_measurement_code','chest_width',
--                 'value',56,'unit_code','cm','value_source','USER_MANUAL',
--                 'raw_label','가슴'),
--             jsonb_build_object('fitmatch_measurement_code','shoulder_width',
--                 'value',47,'unit_code','cm','value_source','RETAILER_SNAPSHOT',
--                 'raw_label','어깨')
--         ),
--         'closet_classification_override', jsonb_build_object(
--             'audience_code','MEN','category_code','tops',
--             'garment_type_code','tshirt','sleeve_length_code','short_sleeve',
--             'lower_length_code',null,'body_length_code',null
--         )
--     ));
--     item_id := (first_result ->> 'item_id')::uuid;
--     listed := public.fitmatch_vnext_list_closet_items();
--     if not exists (
--         select 1 from jsonb_array_elements(listed) as value(item)
--         where (item ->> 'id')::uuid = item_id
--           and item ->> 'classification_source' = 'USER_EXPLICIT'
--           and exists (
--               select 1 from jsonb_array_elements(item -> 'measurements') as value(m)
--               where m ->> 'fitmatch_measurement_code' = 'chest_width'
--                 and (m ->> 'value')::numeric = 56
--                 and m ->> 'value_source' = 'USER_MANUAL'
--           )
--           and exists (
--               select 1 from jsonb_array_elements(item -> 'measurements') as value(m)
--               where m ->> 'fitmatch_measurement_code' = 'shoulder_width'
--                 and (m ->> 'value')::numeric = 47
--                 and m ->> 'value_source' = 'RETAILER_SNAPSHOT'
--           )
--     ) then
--         raise exception 'mixed provenance list round-trip failed';
--     end if;
-- end
-- $round_trip$;

rollback;
