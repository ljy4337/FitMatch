-- Local/disposable runtime validation for 20260829050000.
-- All synthetic user-owned writes are inside this transaction and rolled back.

begin;

do $contract_shape$
declare
    signature text;
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'fitmatch_vnext'
          and table_name = 'closet_items'
          and column_name = 'satisfaction'
          and data_type = 'smallint'
    ) then
        raise exception 'satisfaction column contract missing';
    end if;
    if not exists (
        select 1 from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = 'fitmatch_vnext'
          and t.relname = 'closet_items'
          and c.conname = 'closet_items_satisfaction_chk'
    ) then
        raise exception 'satisfaction check contract missing';
    end if;

    foreach signature in array array[
        'fitmatch_vnext.get_product_runtime_for_swift(text,text)',
        'fitmatch_vnext.upsert_closet_item_for_swift(jsonb)',
        'fitmatch_vnext.update_closet_item(uuid,jsonb)',
        'fitmatch_vnext.soft_delete_closet_item(uuid)',
        'fitmatch_vnext.unset_closet_reference(uuid)',
        'fitmatch_vnext.set_closet_classification_override(uuid,jsonb)',
        'fitmatch_vnext.clear_closet_classification_override(uuid)',
        'public.fitmatch_vnext_get_product_runtime(text,text)',
        'public.fitmatch_vnext_upsert_closet_item(jsonb)',
        'public.fitmatch_vnext_update_closet_item(uuid,jsonb)',
        'public.fitmatch_vnext_list_closet_items()',
        'public.fitmatch_vnext_set_closet_reference(uuid)',
        'public.fitmatch_vnext_unset_closet_reference(uuid)',
        'public.fitmatch_vnext_delete_closet_item(uuid)',
        'public.fitmatch_vnext_set_closet_classification_override(uuid,jsonb)',
        'public.fitmatch_vnext_clear_closet_classification_override(uuid)',
        'public.fitmatch_vnext_find_reference_candidates(uuid,uuid)',
        'public.fitmatch_vnext_authorize_comparison(uuid,uuid,uuid,boolean)',
        'public.fitmatch_vnext_eligible_candidate_sizes(uuid,uuid,uuid,boolean)',
        'public.fitmatch_vnext_begin_comparison(jsonb)',
        'public.fitmatch_vnext_complete_comparison(uuid,jsonb)',
        'public.fitmatch_vnext_comparison_history()'
    ] loop
        if to_regprocedure(signature) is null then
            raise exception 'required function missing: %', signature;
        end if;
        if not exists (
            select 1 from pg_proc
            where oid = to_regprocedure(signature)
              and coalesce(array_to_string(proconfig, ','), '')
                  like '%search_path=""%'
        ) then
            raise exception 'fixed search_path missing: %', signature;
        end if;
    end loop;

    foreach signature in array array[
        'public.fitmatch_vnext_get_product_runtime(text,text)',
        'public.fitmatch_vnext_upsert_closet_item(jsonb)',
        'public.fitmatch_vnext_update_closet_item(uuid,jsonb)',
        'public.fitmatch_vnext_list_closet_items()',
        'public.fitmatch_vnext_set_closet_reference(uuid)',
        'public.fitmatch_vnext_unset_closet_reference(uuid)',
        'public.fitmatch_vnext_delete_closet_item(uuid)',
        'public.fitmatch_vnext_set_closet_classification_override(uuid,jsonb)',
        'public.fitmatch_vnext_clear_closet_classification_override(uuid)',
        'public.fitmatch_vnext_find_reference_candidates(uuid,uuid)',
        'public.fitmatch_vnext_authorize_comparison(uuid,uuid,uuid,boolean)',
        'public.fitmatch_vnext_eligible_candidate_sizes(uuid,uuid,uuid,boolean)',
        'public.fitmatch_vnext_begin_comparison(jsonb)',
        'public.fitmatch_vnext_complete_comparison(uuid,jsonb)',
        'public.fitmatch_vnext_comparison_history()'
    ] loop
        if not has_function_privilege('authenticated', signature, 'EXECUTE')
           or has_function_privilege('anon', signature, 'EXECUTE')
           or exists (
                select 1
                from pg_proc p
                cross join lateral aclexplode(
                    coalesce(p.proacl, acldefault('f', p.proowner))
                ) acl
                where p.oid = to_regprocedure(signature)
                  and acl.grantee = 0
                  and acl.privilege_type = 'EXECUTE'
           ) then
            raise exception 'public bridge grant matrix invalid: %', signature;
        end if;
        if (select prosecdef from pg_proc where oid = to_regprocedure(signature)) then
            raise exception 'public bridge must remain SECURITY INVOKER: %', signature;
        end if;
    end loop;
end
$contract_shape$;

select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-00000000a001',
    true
);

do $user_owned_runtime$
declare
    manual_item uuid;
    product_item uuid;
    result_value jsonb;
    listed jsonb;
    product_hash_before text;
    product_hash_after text;
begin
    result_value := public.fitmatch_vnext_upsert_closet_item(jsonb_build_object(
        'client_item_id', '00000000-0000-0000-0000-000000004001',
        'item_name', 'Manual audit T-shirt',
        'brand_name', 'Audit',
        'size_label', 'M',
        'audience_code', 'UNISEX',
        'garment_type_code', 'tshirt',
        'sleeve_length_code', 'SHORT',
        'fit_preference_code', 'regular',
        'notes', 'initial',
        'satisfaction', 4,
        'measurements', jsonb_build_array(jsonb_build_object(
            'fitmatch_measurement_code', 'chest_width',
            'value', 50.0,
            'unit_code', 'cm',
            'raw_label', 'Chest'
        ))
    ));
    manual_item := (result_value ->> 'item_id')::uuid;
    if manual_item is null then raise exception 'manual upsert failed'; end if;

    listed := public.fitmatch_vnext_list_closet_items();
    if jsonb_array_length(listed) <> 1
       or (listed -> 0 ->> 'satisfaction')::integer <> 4 then
        raise exception 'manual closet list/hydration failed';
    end if;

    perform public.fitmatch_vnext_update_closet_item(
        manual_item,
        jsonb_build_object(
            'item_name', 'Manual audit T-shirt',
            'audience_code', 'UNISEX',
            'garment_type_code', 'tshirt',
            'sleeve_length_code', 'SHORT',
            'notes', 'updated',
            'satisfaction', 5,
            'measurements', jsonb_build_array(jsonb_build_object(
                'fitmatch_measurement_code', 'chest_width',
                'value', 51.0,
                'unit_code', 'cm',
                'raw_label', 'Chest'
            ))
        )
    );
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = manual_item and notes = 'updated' and satisfaction = 5
    ) then
        raise exception 'closet edit failed';
    end if;

    perform public.fitmatch_vnext_set_closet_reference(manual_item);
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = manual_item and is_reference
    ) then
        raise exception 'reference set failed';
    end if;
    perform public.fitmatch_vnext_unset_closet_reference(manual_item);
    if exists (
        select 1 from fitmatch_vnext.closet_items
        where id = manual_item and is_reference
    ) then
        raise exception 'reference unset failed';
    end if;

    result_value := public.fitmatch_vnext_upsert_closet_item(jsonb_build_object(
        'client_item_id', '00000000-0000-0000-0000-000000004002',
        'product_id', '00000000-0000-0000-0000-000000001001',
        'product_variant_id', '00000000-0000-0000-0000-000000002001',
        'product_size_id', '00000000-0000-0000-0000-000000003001',
        'satisfaction', 3
    ));
    product_item := (result_value ->> 'item_id')::uuid;
    select md5(to_jsonb(p)::text) into product_hash_before
    from fitmatch_vnext.products p
    where p.id = '00000000-0000-0000-0000-000000001001';

    perform public.fitmatch_vnext_set_closet_classification_override(
        product_item,
        jsonb_build_object(
            'audience_code', 'WOMEN',
            'garment_type_code', 'tshirt',
            'sleeve_length_code', 'LONG'
        )
    );
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = product_item
          and classification_source = 'USER_EDITED'
          and audience_code = 'WOMEN'
          and sleeve_length_code = 'LONG'
    ) then
        raise exception 'personal classification override failed';
    end if;
    select md5(to_jsonb(p)::text) into product_hash_after
    from fitmatch_vnext.products p
    where p.id = '00000000-0000-0000-0000-000000001001';
    if product_hash_before is distinct from product_hash_after then
        raise exception 'personal override mutated global Product';
    end if;

    perform public.fitmatch_vnext_clear_closet_classification_override(product_item);
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = product_item
          and classification_source = 'RETAILER_SNAPSHOT'
          and audience_code = 'UNISEX'
          and sleeve_length_code = 'SHORT'
    ) then
        raise exception 'personal override clear failed';
    end if;

    perform public.fitmatch_vnext_delete_closet_item(manual_item);
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = manual_item and deleted_at is not null and not is_reference
    ) then
        raise exception 'soft delete failed';
    end if;
end
$user_owned_runtime$;

select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-00000000b001',
    true
);

do $ownership_negative$
declare
    target_id uuid;
    operation_succeeded boolean;
begin
    select id into target_id from fitmatch_vnext.closet_items
    where client_item_id = '00000000-0000-0000-0000-000000004002';

    operation_succeeded := true;
    begin
        perform public.fitmatch_vnext_update_closet_item(
            target_id,
            jsonb_build_object(
                'audience_code', 'UNISEX',
                'garment_type_code', 'tshirt',
                'sleeve_length_code', 'SHORT'
            )
        );
    exception when others then operation_succeeded := false;
    end;
    if operation_succeeded then raise exception 'cross-user edit was allowed'; end if;

    operation_succeeded := true;
    begin
        perform public.fitmatch_vnext_unset_closet_reference(target_id);
    exception when others then operation_succeeded := false;
    end;
    if operation_succeeded then raise exception 'cross-user reference unset was allowed'; end if;

    operation_succeeded := true;
    begin
        perform public.fitmatch_vnext_set_closet_classification_override(
            target_id,
            jsonb_build_object(
                'audience_code', 'UNISEX',
                'garment_type_code', 'tshirt',
                'sleeve_length_code', 'SHORT'
            )
        );
    exception when others then operation_succeeded := false;
    end;
    if operation_succeeded then raise exception 'cross-user override was allowed'; end if;

    operation_succeeded := true;
    begin
        perform public.fitmatch_vnext_delete_closet_item(target_id);
    exception when others then operation_succeeded := false;
    end;
    if operation_succeeded then raise exception 'cross-user delete was allowed'; end if;
end
$ownership_negative$;

select 'PASS vNext Swift user contract runtime and ownership checks' as validation_result;

rollback;
