-- CANDIDATE VALIDATION ONLY — run only on a disposable local PostgreSQL /
-- Supabase database. Run order:
--   1. 124_vnext_review_required_recovery_local_fixture.sql
--   2. migrations/20260829012836_vnext_closet_reference_api.sql
--   3. 127_simplefitmatch_linked_closet_round_trip_local_preimage.sql
--   4. migrations/20260829110853_vnext_swift_user_contract.sql
--   5. 127_simplefitmatch_linked_closet_round_trip_candidate.sql
--   6. this file
--
-- It exercises the public RPC bridge and list read-back, then rolls every
-- synthetic linked Closet write back. It contains no Production identifiers.

begin;

do $shape$
begin
    if to_regprocedure(
        'fitmatch_vnext.apply_linked_closet_snapshot_for_swift(jsonb,uuid)'
    ) is null then
        raise exception 'Simple FitMatch linked snapshot helper is missing';
    end if;
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'fitmatch_vnext'
          and table_name = 'closet_items'
          and column_name = 'measurement_mode'
    ) or not exists (
        select 1 from information_schema.columns
        where table_schema = 'fitmatch_vnext'
          and table_name = 'closet_item_measurements'
          and column_name = 'value_source'
    ) or not exists (
        select 1 from information_schema.columns
        where table_schema = 'fitmatch_vnext'
          and table_name = 'closet_item_measurements'
          and column_name = 'source_measurement_code_snapshot'
    ) then
        raise exception 'Required Closet-local provenance columns are missing';
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

do $round_trip$
declare
    user_a constant uuid := '11111111-1111-1111-1111-111111111111';
    user_b constant uuid := '22222222-2222-2222-2222-222222222222';
    fixture_product_id constant uuid := 'c0000000-0000-0000-0000-000000000002';
    fixture_variant_id constant uuid := 'd0000000-0000-0000-0000-000000000001';
    fixture_size_id constant uuid := 'e0000000-0000-0000-0000-000000000001';
    fixture_client_item_id constant uuid := 'f1000000-0000-0000-0000-000000000127';
    created jsonb;
    updated jsonb;
    listed jsonb;
    listed_item jsonb;
    closet_item_id uuid;
    product_before jsonb;
    product_after jsonb;
    size_before jsonb;
    size_after jsonb;
    retailer_rows jsonb;
    mixed_rows jsonb;
begin
    -- The recovery fixture intentionally begins REVIEW_REQUIRED. A complete
    -- user Closet tuple must be sufficient here without changing the Product's
    -- automatic classification or any ProductSize fact.
    update fitmatch_vnext.product_size_measurements psm
    set raw_value = 55.25
    where psm.product_size_id = fixture_size_id
      and psm.raw_code = 'chest_width';
    insert into fitmatch_vnext.product_size_measurements(
        product_size_id, raw_code, raw_label, raw_value, evidence_fingerprint
    ) values
        (fixture_size_id, 'shoulder_width', '어깨', 47, 'fixture-shoulder'),
        (fixture_size_id, 'back_length', '총장', 70, 'fixture-length'),
        (fixture_size_id, 'sleeve_length', '소매', 23, 'fixture-sleeve');

    select to_jsonb(p) into product_before
    from fitmatch_vnext.products p where p.id = fixture_product_id;
    select jsonb_agg(to_jsonb(psm) order by psm.id) into size_before
    from fitmatch_vnext.product_size_measurements psm
    where psm.product_size_id = fixture_size_id;

    retailer_rows := jsonb_build_array(
        jsonb_build_object('fitmatch_measurement_code','chest_width',
            'source_measurement_code','fixture.chest_width.chest_pit_to_pit','value',55.25,
            'unit_code','cm','value_source','RETAILER_SNAPSHOT','raw_label','가슴'),
        jsonb_build_object('fitmatch_measurement_code','shoulder_width',
            'source_measurement_code','fixture.shoulder_width.shoulder_seam_to_seam','value',47,
            'unit_code','cm','value_source','RETAILER_SNAPSHOT','raw_label','어깨'),
        jsonb_build_object('fitmatch_measurement_code','back_length',
            'source_measurement_code','fixture.back_length.back_neck_to_hem','value',70,
            'unit_code','cm','value_source','RETAILER_SNAPSHOT','raw_label','총장'),
        jsonb_build_object('fitmatch_measurement_code','sleeve_length',
            'source_measurement_code','fixture.sleeve_length.shoulder_seam_to_cuff','value',23,
            'unit_code','cm','value_source','RETAILER_SNAPSHOT','raw_label','소매')
    );

    perform set_config('request.jwt.claim.sub', user_a::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);

    -- T1: untouched imported snapshot, exact IDs, and NULL (unrated)
    -- satisfaction all round-trip through the public bridge.
    created := public.fitmatch_vnext_upsert_closet_item(jsonb_build_object(
        'client_item_id', fixture_client_item_id,
        'product_id', fixture_product_id,
        'product_variant_id', fixture_variant_id,
        'product_size_id', fixture_size_id,
        'measurements', retailer_rows,
        'closet_classification_override', jsonb_build_object(
            'audience_code','MEN','category_code','tops',
            'garment_type_code','tshirt','sleeve_length_code','short_sleeve',
            'lower_length_code',null,'body_length_code',null
        )
    ));
    closet_item_id := (created ->> 'item_id')::uuid;
    if closet_item_id is null or created ->> 'created' <> 'true' then
        raise exception 'linked create did not return a new item receipt';
    end if;
    listed := public.fitmatch_vnext_list_closet_items();
    select entry.value into listed_item
    from jsonb_array_elements(listed) as entry(value)
    where (entry.value ->> 'id')::uuid = closet_item_id;
    if listed_item is null
       or listed_item ->> 'product_id' <> fixture_product_id::text
       or listed_item ->> 'product_variant_id' <> fixture_variant_id::text
       or listed_item ->> 'product_size_id' <> fixture_size_id::text
       or listed_item ->> 'classification_source' <> 'USER_EXPLICIT'
       or listed_item -> 'satisfaction' <> 'null'::jsonb
       or not exists (
           select 1 from jsonb_array_elements(listed_item -> 'measurements') as entry(value)
           where entry.value ->> 'fitmatch_measurement_code' = 'chest_width'
             and (entry.value ->> 'value')::numeric = 55.25
             and entry.value ->> 'value_source' = 'RETAILER_SNAPSHOT'
             and entry.value ->> 'source_measurement_code'
                 = 'fixture.chest_width.chest_pit_to_pit'
       ) then
        raise exception 'T1 imported linked snapshot/list round-trip failed';
    end if;
    if not exists (
        select 1
        from fitmatch_vnext.closet_item_measurements cm
        where cm.closet_item_id = (created ->> 'item_id')::uuid
          and cm.fitmatch_measurement_code = 'chest_width'
          and cm.source_measurement_code is null
          and cm.source_measurement_code_snapshot
              = 'fixture.chest_width.chest_pit_to_pit'
    ) then
        raise exception 'T1 canonical row did not retain its source snapshot separately';
    end if;

    -- T2: change only chest. The remaining retailer facts keep their value
    -- and provenance after the server update and list read-back.
    mixed_rows := jsonb_build_array(
        jsonb_build_object('fitmatch_measurement_code','chest_width',
            'source_measurement_code','fixture.chest_width.chest_pit_to_pit','value',56,
            'unit_code','cm','value_source','USER_MANUAL','raw_label','가슴'),
        jsonb_build_object('fitmatch_measurement_code','shoulder_width',
            'source_measurement_code','fixture.shoulder_width.shoulder_seam_to_seam','value',47,
            'unit_code','cm','value_source','RETAILER_SNAPSHOT','raw_label','어깨'),
        jsonb_build_object('fitmatch_measurement_code','back_length',
            'source_measurement_code','fixture.back_length.back_neck_to_hem','value',70,
            'unit_code','cm','value_source','RETAILER_SNAPSHOT','raw_label','총장'),
        jsonb_build_object('fitmatch_measurement_code','sleeve_length',
            'source_measurement_code','fixture.sleeve_length.shoulder_seam_to_cuff','value',23,
            'unit_code','cm','value_source','RETAILER_SNAPSHOT','raw_label','소매')
    );
    updated := public.fitmatch_vnext_update_closet_item(
        closet_item_id,
        jsonb_build_object(
            'client_item_id', fixture_client_item_id,
            'product_id', fixture_product_id,
            'product_variant_id', fixture_variant_id,
            'product_size_id', fixture_size_id,
            'measurements', mixed_rows,
            'closet_classification_override', jsonb_build_object(
                'audience_code','MEN','category_code','tops',
                'garment_type_code','tshirt','sleeve_length_code','short_sleeve',
                'lower_length_code',null,'body_length_code',null
            )
        )
    );
    if (updated ->> 'closet_item_id')::uuid <> closet_item_id then
        raise exception 'T2 linked update receipt mismatch';
    end if;
    listed := public.fitmatch_vnext_list_closet_items();
    select entry.value into listed_item from jsonb_array_elements(listed) as entry(value)
    where (entry.value ->> 'id')::uuid = closet_item_id;
    if not exists (
        select 1 from jsonb_array_elements(listed_item -> 'measurements') as entry(value)
        where entry.value ->> 'fitmatch_measurement_code' = 'chest_width'
          and (entry.value ->> 'value')::numeric = 56
          and entry.value ->> 'value_source' = 'USER_MANUAL'
          and entry.value ->> 'source_measurement_code'
              = 'fixture.chest_width.chest_pit_to_pit'
    ) or not exists (
        select 1 from jsonb_array_elements(listed_item -> 'measurements') as entry(value)
        where entry.value ->> 'fitmatch_measurement_code' = 'shoulder_width'
          and (entry.value ->> 'value')::numeric = 47
          and entry.value ->> 'value_source' = 'RETAILER_SNAPSHOT'
          and entry.value ->> 'source_measurement_code'
              = 'fixture.shoulder_width.shoulder_seam_to_seam'
    ) or not exists (
        select 1 from jsonb_array_elements(listed_item -> 'measurements') as entry(value)
        where entry.value ->> 'fitmatch_measurement_code' = 'back_length'
          and (entry.value ->> 'value')::numeric = 70
          and entry.value ->> 'value_source' = 'RETAILER_SNAPSHOT'
    ) or not exists (
        select 1 from jsonb_array_elements(listed_item -> 'measurements') as entry(value)
        where entry.value ->> 'fitmatch_measurement_code' = 'sleeve_length'
          and (entry.value ->> 'value')::numeric = 23
          and entry.value ->> 'value_source' = 'RETAILER_SNAPSHOT'
    ) then
        raise exception 'T2 mixed provenance list round-trip failed';
    end if;

    -- T3: add a missing active FitMatch measurement without changing the
    -- existing API and user rows. A new direct FitMatch definition has no
    -- source identity, so the server must retain the user value with source
    -- NULL.
    mixed_rows := mixed_rows || jsonb_build_array(jsonb_build_object(
        'fitmatch_measurement_code','hem_width','value',24,
        'unit_code','cm','value_source','USER_MANUAL','raw_label','밑단'
    ));
    perform public.fitmatch_vnext_update_closet_item(
        closet_item_id,
        jsonb_build_object(
            'client_item_id', fixture_client_item_id,
            'product_id', fixture_product_id,
            'product_variant_id', fixture_variant_id,
            'product_size_id', fixture_size_id,
            'measurements', mixed_rows,
            'closet_classification_override', jsonb_build_object(
                'audience_code','MEN','category_code','tops',
                'garment_type_code','tshirt','sleeve_length_code','short_sleeve',
                'lower_length_code',null,'body_length_code',null
            )
        )
    );

    -- T5/T6: category-only edit changes only the personal Closet tuple. It
    -- retains the mixed snapshot and never asks Product classification again.
    perform public.fitmatch_vnext_update_closet_item(
        closet_item_id,
        jsonb_build_object(
            'client_item_id', fixture_client_item_id,
            'product_id', fixture_product_id,
            'product_variant_id', fixture_variant_id,
            'product_size_id', fixture_size_id,
            'measurements', mixed_rows,
            'closet_classification_override', jsonb_build_object(
                'audience_code','MEN','category_code','tops',
                'garment_type_code','polo_shirt','sleeve_length_code','short_sleeve',
                'lower_length_code',null,'body_length_code',null
            )
        )
    );

    -- T4: re-edit after save. The prior user row remains the only changed
    -- record; all other rows retain their separate provenance.
    mixed_rows := jsonb_set(mixed_rows, '{0,value}', to_jsonb(57::numeric));
    perform public.fitmatch_vnext_update_closet_item(
        closet_item_id,
        jsonb_build_object(
            'client_item_id', fixture_client_item_id,
            'product_id', fixture_product_id,
            'product_variant_id', fixture_variant_id,
            'product_size_id', fixture_size_id,
            'measurements', mixed_rows,
            'closet_classification_override', jsonb_build_object(
                'audience_code','MEN','category_code','tops',
                'garment_type_code','polo_shirt','sleeve_length_code','short_sleeve',
                'lower_length_code',null,'body_length_code',null
            )
        )
    );
    listed := public.fitmatch_vnext_list_closet_items();
    select entry.value into listed_item from jsonb_array_elements(listed) as entry(value)
    where (entry.value ->> 'id')::uuid = closet_item_id;
    if listed_item ->> 'garment_type_code' <> 'polo_shirt'
       or not exists (
           select 1 from jsonb_array_elements(listed_item -> 'measurements') as entry(value)
           where entry.value ->> 'fitmatch_measurement_code' = 'chest_width'
             and (entry.value ->> 'value')::numeric = 57
             and entry.value ->> 'value_source' = 'USER_MANUAL'
       ) or not exists (
        select 1 from jsonb_array_elements(listed_item -> 'measurements') as entry(value)
        where entry.value ->> 'fitmatch_measurement_code' = 'hem_width'
          and (entry.value ->> 'value')::numeric = 24
          and entry.value ->> 'value_source' = 'USER_MANUAL'
          and entry.value -> 'source_measurement_code' = 'null'::jsonb
       ) or not exists (
           select 1 from jsonb_array_elements(listed_item -> 'measurements') as entry(value)
           where entry.value ->> 'fitmatch_measurement_code' = 'shoulder_width'
             and (entry.value ->> 'value')::numeric = 47
             and entry.value ->> 'value_source' = 'RETAILER_SNAPSHOT'
    ) then
        raise exception 'T3/T4/T5 category-only mixed snapshot round-trip failed';
    end if;
    if not exists (
        select 1
        from fitmatch_vnext.closet_item_measurements cm
        where cm.closet_item_id = (created ->> 'item_id')::uuid
          and cm.fitmatch_measurement_code = 'chest_width'
          and cm.value = 57
          and cm.value_source = 'USER_MANUAL'
          and cm.source_measurement_code is null
          and cm.source_measurement_code_snapshot
              = 'fixture.chest_width.chest_pit_to_pit'
    ) or exists (
        select 1
        from fitmatch_vnext.closet_item_measurements cm
        where cm.closet_item_id = (created ->> 'item_id')::uuid
          and cm.fitmatch_measurement_code = 'hem_width'
          and cm.source_measurement_code_snapshot is not null
    ) then
        raise exception 'T3/T4 source snapshot separation failed';
    end if;

    -- T8: a second account cannot read or mutate the first account's row.
    perform set_config('request.jwt.claim.sub', user_b::text, true);
    if public.fitmatch_vnext_list_closet_items() <> '[]'::jsonb then
        raise exception 'cross-user Closet list leaked a row';
    end if;
    begin
        perform public.fitmatch_vnext_update_closet_item(
            closet_item_id,
            jsonb_build_object(
                'client_item_id', fixture_client_item_id,
                'product_id', fixture_product_id,
                'product_variant_id', fixture_variant_id,
                'product_size_id', fixture_size_id,
                'measurements', mixed_rows
            )
        );
        raise exception 'cross-user linked Closet update unexpectedly succeeded';
    exception when others then
        if position('not owned' in sqlerrm) = 0 then
            raise;
        end if;
    end;
    perform set_config('request.jwt.claim.sub', user_a::text, true);

    -- T9: an invalid unit must fail before the snapshot replacement. The
    -- nested exception block rolls the attempted mutation back.
    begin
        perform public.fitmatch_vnext_update_closet_item(
            closet_item_id,
            jsonb_build_object(
                'client_item_id', fixture_client_item_id,
                'product_id', fixture_product_id,
                'product_variant_id', fixture_variant_id,
                'product_size_id', fixture_size_id,
                'measurements', jsonb_set(
                    mixed_rows,
                    '{0,unit_code}',
                    to_jsonb('in'::text)
                ),
                'closet_classification_override', jsonb_build_object(
                    'audience_code','MEN','category_code','tops',
                    'garment_type_code','polo_shirt','sleeve_length_code','short_sleeve',
                    'lower_length_code',null,'body_length_code',null
                )
            )
        );
        raise exception 'invalid unit unexpectedly saved';
    exception when others then
        if position('unit must be cm' in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    -- The RPC repeats the non-finite and bounded-range guards; a malformed
    -- caller cannot bypass the editor's category-definition validation.
    begin
        perform public.fitmatch_vnext_update_closet_item(
            closet_item_id,
            jsonb_build_object(
                'client_item_id', fixture_client_item_id,
                'product_id', fixture_product_id,
                'product_variant_id', fixture_variant_id,
                'product_size_id', fixture_size_id,
                'measurements', jsonb_set(
                    mixed_rows,
                    '{0,value}',
                    to_jsonb('NaN'::text)
                ),
                'closet_classification_override', jsonb_build_object(
                    'audience_code','MEN','category_code','tops',
                    'garment_type_code','polo_shirt','sleeve_length_code','short_sleeve',
                    'lower_length_code',null,'body_length_code',null
                )
            )
        );
        raise exception 'NaN measurement unexpectedly saved';
    exception when others then
        if position('measurement value must be finite' in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    begin
        perform public.fitmatch_vnext_update_closet_item(
            closet_item_id,
            jsonb_build_object(
                'client_item_id', fixture_client_item_id,
                'product_id', fixture_product_id,
                'product_variant_id', fixture_variant_id,
                'product_size_id', fixture_size_id,
                'measurements', jsonb_set(
                    mixed_rows,
                    '{0,value}',
                    to_jsonb('Infinity'::text)
                ),
                'closet_classification_override', jsonb_build_object(
                    'audience_code','MEN','category_code','tops',
                    'garment_type_code','polo_shirt','sleeve_length_code','short_sleeve',
                    'lower_length_code',null,'body_length_code',null
                )
            )
        );
        raise exception 'infinite measurement unexpectedly saved';
    exception when others then
        if position('measurement value must be finite' in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    begin
        perform public.fitmatch_vnext_update_closet_item(
            closet_item_id,
            jsonb_build_object(
                'client_item_id', fixture_client_item_id,
                'product_id', fixture_product_id,
                'product_variant_id', fixture_variant_id,
                'product_size_id', fixture_size_id,
                'measurements', jsonb_set(
                    mixed_rows,
                    '{0,value}',
                    to_jsonb('1001'::text)
                ),
                'closet_classification_override', jsonb_build_object(
                    'audience_code','MEN','category_code','tops',
                    'garment_type_code','polo_shirt','sleeve_length_code','short_sleeve',
                    'lower_length_code',null,'body_length_code',null
                )
            )
        );
        raise exception 'out-of-range measurement unexpectedly saved';
    exception when others then
        if position('positive, finite, and in range' in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    -- A registered source identity from the selected size may not be forged
    -- onto a different canonical measurement. This is distinct from a
    -- user-added local rawCode (which is unregistered and normalizes to NULL).
    begin
        perform public.fitmatch_vnext_update_closet_item(
            closet_item_id,
            jsonb_build_object(
                'client_item_id', fixture_client_item_id,
                'product_id', fixture_product_id,
                'product_variant_id', fixture_variant_id,
                'product_size_id', fixture_size_id,
                'measurements', jsonb_set(
                    mixed_rows,
                    '{0,source_measurement_code}',
                    to_jsonb('fixture.shoulder_width.shoulder_seam_to_seam'::text)
                ),
                'closet_classification_override', jsonb_build_object(
                    'audience_code','MEN','category_code','tops',
                    'garment_type_code','polo_shirt','sleeve_length_code','short_sleeve',
                    'lower_length_code',null,'body_length_code',null
                )
            )
        );
        raise exception 'wrong selected-size source identity unexpectedly saved';
    exception when others then
        if position('does not belong to selected productsize canonical measurement'
            in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    -- The pre-existing mutually-exclusive semantic contract must remain
    -- intact: the candidate stores origin in the new snapshot column instead
    -- of allowing both original semantic columns on a CANONICAL row.
    begin
        insert into fitmatch_vnext.closet_item_measurements (
            closet_item_id, source_measurement_code, fitmatch_measurement_code,
            value, unit_code, value_source, raw_label_snapshot
        ) values (
            closet_item_id,
            'fixture.chest_width.chest_pit_to_pit',
            'hem_width',
            1,
            'cm',
            'USER_MANUAL',
            'must-fail'
        );
        raise exception 'existing canonical semantic exclusivity unexpectedly weakened';
    exception when others then
        if position('canonical closet item requires fitmatch_measurement_code only'
            in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    select to_jsonb(p) into product_after
    from fitmatch_vnext.products p where p.id = fixture_product_id;
    select jsonb_agg(to_jsonb(psm) order by psm.id) into size_after
    from fitmatch_vnext.product_size_measurements psm
    where psm.product_size_id = fixture_size_id;
    if product_after is distinct from product_before
       or size_after is distinct from size_before then
        raise exception 'linked Closet mutation changed shared Product or ProductSize facts';
    end if;
end
$round_trip$;

rollback;
