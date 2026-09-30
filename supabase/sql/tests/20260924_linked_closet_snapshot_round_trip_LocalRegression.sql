\set ON_ERROR_STOP on

-- Isolated contract harness for the two forward migrations. It deliberately
-- supplies only the deployed owners/tables these wrappers call, then exercises
-- the public RPC boundary rather than calling the new private owner directly.

create schema auth;
create schema fitmatch_vnext;
create role anon;
create role authenticated;
create role service_role;

create function auth.uid()
returns uuid
language sql
stable
as $$
    select nullif(current_setting('app.user_id', true), '')::uuid
$$;

create table fitmatch_vnext.garment_types (
    garment_type_code text primary key,
    category_code text not null
);

create table fitmatch_vnext.products (
    id uuid primary key,
    source_code text not null,
    garment_type_code text not null references fitmatch_vnext.garment_types(garment_type_code)
);

create table fitmatch_vnext.product_variants (
    id uuid primary key,
    product_id uuid not null references fitmatch_vnext.products(id),
    source_variant_key text not null
);

create table fitmatch_vnext.product_sizes (
    id uuid primary key,
    variant_id uuid not null references fitmatch_vnext.product_variants(id),
    source_size_key text not null,
    size_label text not null
);

create table fitmatch_vnext.product_ingestion_receipts (
    id uuid primary key,
    product_id uuid not null references fitmatch_vnext.products(id),
    source_code text not null,
    processing_status text not null,
    retailer_facts jsonb not null,
    observed_at timestamptz not null
);

create table fitmatch_vnext.closet_items (
    id uuid primary key,
    user_id uuid not null,
    client_item_id uuid not null,
    product_id uuid,
    product_variant_id uuid,
    product_size_id uuid,
    garment_type_code text,
    closet_detail_code_snapshot text,
    classification_source text,
    classification_resolver_version text,
    notes text,
    deleted_at timestamptz
);

create table fitmatch_vnext.closet_canonical_measurements (
    closet_item_id uuid primary key references fitmatch_vnext.closet_items(id),
    product_size_id uuid not null,
    value numeric not null
);

create table fitmatch_vnext.closet_item_source_measurement_snapshots (
    closet_item_id uuid primary key references fitmatch_vnext.closet_items(id),
    source_observation_id uuid not null,
    product_id uuid not null,
    product_variant_id uuid not null,
    product_size_id uuid not null,
    source_measurement_count integer not null
);

create table fitmatch_vnext.closet_item_source_measurements (
    closet_item_id uuid not null references fitmatch_vnext.closet_items(id),
    raw_measurement_key text not null,
    source_code text not null,
    parser_code text not null,
    raw_code text,
    raw_label text,
    raw_value numeric,
    raw_value_text text,
    raw_unit_code text,
    raw_representation text,
    source_measurement_code text,
    resolution_status text not null,
    mapping_version text,
    evidence_payload jsonb not null,
    source_observed_at timestamptz,
    primary key (closet_item_id, raw_measurement_key)
);

create function fitmatch_vnext.resolve_measurement(
    p_source_code text,
    p_parser_code text,
    p_raw_code text,
    p_raw_label text,
    p_garment_type_code text,
    p_category_code text,
    p_raw_value numeric
)
returns table(value jsonb)
language sql
stable
as $$
    select jsonb_build_object(
        'source_measurement_code', coalesce(p_raw_code, p_raw_label, 'unknown'),
        'resolution_status', 'UNMAPPED',
        'resolver_version', 'local-harness'
    )
$$;

create function fitmatch_vnext.update_closet_item(
    p_closet_item_id uuid,
    p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    next_size_id uuid;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = p_closet_item_id and user_id = caller_id and deleted_at is null
    ) then
        raise exception 'Closet item not found or not owned';
    end if;

    next_size_id := coalesce(
        nullif(btrim(p_request ->> 'product_size_id'), '')::uuid,
        (select product_size_id from fitmatch_vnext.closet_items where id = p_closet_item_id)
    );
    update fitmatch_vnext.closet_items
       set product_id = coalesce(nullif(btrim(p_request ->> 'product_id'), '')::uuid, product_id),
           product_variant_id = coalesce(nullif(btrim(p_request ->> 'product_variant_id'), '')::uuid, product_variant_id),
           product_size_id = next_size_id,
           notes = coalesce(p_request ->> 'notes', notes)
     where id = p_closet_item_id;
    insert into fitmatch_vnext.closet_canonical_measurements(
        closet_item_id, product_size_id, value
    ) values (
        p_closet_item_id,
        next_size_id,
        case when next_size_id = '00000000-0000-0000-0000-000000000202'::uuid then 56 else 54 end
    ) on conflict (closet_item_id) do update
        set product_size_id = excluded.product_size_id,
            value = excluded.value;
    return jsonb_build_object('closet_item_id', p_closet_item_id, 'item_id', p_closet_item_id);
end
$function$;

create function fitmatch_vnext.apply_linked_closet_snapshot_for_swift(
    p_request jsonb,
    p_closet_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
    -- Match the deployed helper: server snapshots are creation-only here.
    -- The new update wrapper must not route metadata-only edits through it.
    if p_request -> 'use_server_measurements' = 'true'::jsonb then
        raise exception 'Server size snapshot is only supported for linked creation';
    end if;
    return fitmatch_vnext.update_closet_item(p_closet_item_id, p_request);
end
$$;

create function fitmatch_vnext.set_closet_detail_snapshot_for_swift(
    p_closet_item_id uuid,
    p_request jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
    if p_request ? 'closet_detail_code' then
        update fitmatch_vnext.closet_items
           set closet_detail_code_snapshot = nullif(btrim(p_request ->> 'closet_detail_code'), '')
         where id = p_closet_item_id
           and user_id = auth.uid();
    end if;
end
$function$;

create function fitmatch_vnext.comparison_group_tuple(p_product_id uuid, p_requested_group_code text)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'audience_code', 'MEN',
        'category_code', 'bottoms',
        'garment_type_code', 'pants'
    )
$$;

create function fitmatch_vnext.apply_closet_comparison_group(
    p_closet_item_id uuid,
    p_requested_group_code text,
    p_is_explicit boolean
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object('group_code', coalesce(p_requested_group_code, 'C'))
$$;

create function fitmatch_vnext.closet_comparison_group(p_closet_item_id uuid)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object('group_code', 'C')
$$;

create function fitmatch_vnext.list_closet_items()
returns jsonb
language sql
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', ci.id,
        'client_item_id', ci.client_item_id,
        'product_id', ci.product_id,
        'product_variant_id', ci.product_variant_id,
        'product_size_id', ci.product_size_id,
        'detail_code', coalesce(ci.closet_detail_code_snapshot, ci.garment_type_code),
        'source_measurements', coalesce((
            select jsonb_agg(jsonb_build_object(
                'raw_measurement_key', sm.raw_measurement_key,
                'raw_value', sm.raw_value,
                'raw_unit_code', sm.raw_unit_code
            ) order by sm.raw_measurement_key)
            from fitmatch_vnext.closet_item_source_measurements sm
            where sm.closet_item_id = ci.id
        ), '[]'::jsonb)
    ) order by ci.id), '[]'::jsonb)
    from fitmatch_vnext.closet_items ci
    where ci.user_id = auth.uid()
      and ci.deleted_at is null
$$;

create function public.fitmatch_vnext_update_closet_item(
    p_closet_item_id uuid,
    p_request jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select fitmatch_vnext.update_closet_item(p_closet_item_id, p_request)
$$;

create function public.fitmatch_vnext_list_closet_items()
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select fitmatch_vnext.list_closet_items()
$$;

insert into fitmatch_vnext.garment_types values ('pants', 'bottoms'), ('shirt_blouse', 'tops');
insert into fitmatch_vnext.products values ('00000000-0000-0000-0000-000000000101', 'UNIQLO', 'pants');
insert into fitmatch_vnext.product_variants values ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000101', 'variant-blue');
insert into fitmatch_vnext.product_sizes values
    ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000102', 'size-M', 'M'),
    ('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000102', 'size-L', 'L');

insert into fitmatch_vnext.product_ingestion_receipts values
(
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000101',
    'UNIQLO',
    'PROCESSED',
    jsonb_build_object('variants', jsonb_build_array(jsonb_build_object(
        'external_variant_id', 'variant-blue',
        'sizes', jsonb_build_array(jsonb_build_object(
            'size_identity', 'size-M',
            'measurements', jsonb_build_array(jsonb_build_object(
                'measurement_identity', 'm-chest', 'parser_code', 'uniqlo',
                'raw_code', 'chest-width', 'raw_label', '가슴',
                'raw_value', '54', 'raw_value_text', '54.0', 'raw_unit', 'cm'
            ))
        ))
    ))),
    '2026-09-24T00:00:00Z'
),
(
    '00000000-0000-0000-0000-000000000302',
    '00000000-0000-0000-0000-000000000101',
    'UNIQLO',
    'PROCESSED',
    jsonb_build_object('variants', jsonb_build_array(jsonb_build_object(
        'external_variant_id', 'variant-blue',
        'sizes', jsonb_build_array(jsonb_build_object(
            'size_identity', 'size-L',
            'measurements', jsonb_build_array(
                jsonb_build_object(
                    'measurement_identity', 'l-chest', 'parser_code', 'uniqlo',
                    'raw_code', 'chest-width', 'raw_label', '가슴',
                    'raw_value', '56', 'raw_value_text', '56.0', 'raw_unit', 'cm'
                ),
                jsonb_build_object(
                    'measurement_identity', 'l-length', 'parser_code', 'uniqlo',
                    'raw_code', 'total-length', 'raw_label', '총장',
                    'raw_value', '101', 'raw_value_text', '101.0', 'raw_unit', 'cm'
                )
            )
        ))
    ))),
    '2026-09-24T00:01:00Z'
),
(
    '00000000-0000-0000-0000-000000000303',
    '00000000-0000-0000-0000-000000000101',
    'UNIQLO',
    'PROCESSED',
    jsonb_build_object('variants', jsonb_build_array(jsonb_build_object(
        'external_variant_id', 'variant-other',
        'sizes', jsonb_build_array(jsonb_build_object(
            'size_identity', 'size-L', 'measurements', jsonb_build_array(
                jsonb_build_object('measurement_identity', 'wrong', 'raw_code', 'chest-width', 'raw_value', '999')
            )
        ))
    ))),
    '2026-09-24T00:02:00Z'
);

insert into fitmatch_vnext.closet_items values (
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000102',
    '00000000-0000-0000-0000-000000000201',
    'pants', null, null, null, 'M memo', null
);
insert into fitmatch_vnext.closet_canonical_measurements values (
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000201', 54
);
insert into fitmatch_vnext.closet_item_source_measurement_snapshots values (
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000102',
    '00000000-0000-0000-0000-000000000201', 1
);
insert into fitmatch_vnext.closet_item_source_measurements (
    closet_item_id, raw_measurement_key, source_code, parser_code, raw_code,
    raw_label, raw_value, raw_value_text, raw_unit_code, raw_representation,
    source_measurement_code, resolution_status, mapping_version, evidence_payload, source_observed_at
) values (
    '00000000-0000-0000-0000-000000000401', 'm-chest', 'UNIQLO', 'uniqlo',
    'chest-width', '가슴', 54, '54.0', 'cm', null, 'chest-width',
    'UNMAPPED', 'old', '{}'::jsonb, '2026-09-24T00:00:00Z'
);

select set_config('app.user_id', '00000000-0000-0000-0000-000000000001', false);

\ir ../../migrations/20260924100000_linked_closet_size_snapshot_updates.sql
\ir ../../migrations/20260924101000_closet_detail_snapshot_round_trip.sql

select public.fitmatch_vnext_update_closet_item(
    '00000000-0000-0000-0000-000000000401',
    jsonb_build_object(
        'product_id', '00000000-0000-0000-0000-000000000101',
        'product_variant_id', '00000000-0000-0000-0000-000000000102',
        'product_size_id', '00000000-0000-0000-0000-000000000202',
        'source_observation_id', '00000000-0000-0000-0000-000000000302',
        'use_server_measurements', true,
        'measurements', '[]'::jsonb
    )
);

do $assert_m_to_l$
begin
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = '00000000-0000-0000-0000-000000000401'
          and product_size_id = '00000000-0000-0000-0000-000000000202'
    ) or not exists (
        select 1 from fitmatch_vnext.closet_canonical_measurements
        where closet_item_id = '00000000-0000-0000-0000-000000000401'
          and product_size_id = '00000000-0000-0000-0000-000000000202'
          and value = 56
    ) or not exists (
        select 1 from fitmatch_vnext.closet_item_source_measurement_snapshots
        where closet_item_id = '00000000-0000-0000-0000-000000000401'
          and source_observation_id = '00000000-0000-0000-0000-000000000302'
          and product_size_id = '00000000-0000-0000-0000-000000000202'
          and source_measurement_count = 2
    ) or (select count(*) from fitmatch_vnext.closet_item_source_measurements
          where closet_item_id = '00000000-0000-0000-0000-000000000401') <> 2 then
        raise exception 'M→L parent/canonical/raw snapshot assertion failed';
    end if;
end
$assert_m_to_l$;

-- Exact retry succeeds without adding raw rows.
select public.fitmatch_vnext_update_closet_item(
    '00000000-0000-0000-0000-000000000401',
    jsonb_build_object(
        'product_id', '00000000-0000-0000-0000-000000000101',
        'product_variant_id', '00000000-0000-0000-0000-000000000102',
        'product_size_id', '00000000-0000-0000-0000-000000000202',
        'source_observation_id', '00000000-0000-0000-0000-000000000302',
        'use_server_measurements', true,
        'measurements', '[]'::jsonb
    )
);

do $assert_retry$
begin
    if (select count(*) from fitmatch_vnext.closet_item_source_measurements
        where closet_item_id = '00000000-0000-0000-0000-000000000401') <> 2 then
        raise exception 'idempotent retry appended raw source rows';
    end if;
end
$assert_retry$;

-- M→M metadata update stays on the existing snapshot rather than replacing it.
select public.fitmatch_vnext_update_closet_item(
    '00000000-0000-0000-0000-000000000401',
    jsonb_build_object(
        'product_id', '00000000-0000-0000-0000-000000000101',
        'product_variant_id', '00000000-0000-0000-0000-000000000102',
        'product_size_id', '00000000-0000-0000-0000-000000000202',
        'notes', 'L memo',
        'use_server_measurements', true,
        'measurements', '[]'::jsonb
    )
);

do $assert_metadata_only$
begin
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = '00000000-0000-0000-0000-000000000401' and notes = 'L memo'
    ) or not exists (
        select 1 from fitmatch_vnext.closet_item_source_measurement_snapshots
        where closet_item_id = '00000000-0000-0000-0000-000000000401'
          and source_observation_id = '00000000-0000-0000-0000-000000000302'
    ) then
        raise exception 'metadata-only update replaced the immutable source snapshot';
    end if;
end
$assert_metadata_only$;

-- A receipt for another variant fails before it can change parent/canonical/raw.
do $assert_wrong_observation$
begin
    begin
        perform public.fitmatch_vnext_update_closet_item(
            '00000000-0000-0000-0000-000000000401',
            jsonb_build_object(
                'product_id', '00000000-0000-0000-0000-000000000101',
                'product_variant_id', '00000000-0000-0000-0000-000000000102',
                'product_size_id', '00000000-0000-0000-0000-000000000201',
                'source_observation_id', '00000000-0000-0000-0000-000000000303',
                'use_server_measurements', true,
                'measurements', '[]'::jsonb
            )
        );
        raise exception 'wrong-variant observation unexpectedly succeeded';
    exception when others then
        if sqlerrm = 'wrong-variant observation unexpectedly succeeded' then
            raise;
        end if;
    end;
    if not exists (
        select 1 from fitmatch_vnext.closet_items
        where id = '00000000-0000-0000-0000-000000000401'
          and product_size_id = '00000000-0000-0000-0000-000000000202'
    ) or not exists (
        select 1 from fitmatch_vnext.closet_item_source_measurement_snapshots
        where closet_item_id = '00000000-0000-0000-0000-000000000401'
          and source_observation_id = '00000000-0000-0000-0000-000000000302'
    ) then
        raise exception 'failed update did not roll back all linked identities';
    end if;
end
$assert_wrong_observation$;

-- Public list exposes snapshot separately from legacy detail tuple output.
update fitmatch_vnext.closet_items
   set garment_type_code = 'shirt_blouse',
       closet_detail_code_snapshot = 'blouse'
 where id = '00000000-0000-0000-0000-000000000401';

do $assert_detail_round_trip$
declare
    rows jsonb;
begin
    rows := public.fitmatch_vnext_list_closet_items();
    if rows -> 0 ->> 'closet_detail_code_snapshot' <> 'blouse'
       or rows -> 0 -> 'source_measurement_snapshot' ->> 'source_observation_id'
            <> '00000000-0000-0000-0000-000000000302' then
        raise exception 'list did not preserve exact detail/source snapshot';
    end if;
end
$assert_detail_round_trip$;

select set_config('app.user_id', '00000000-0000-0000-0000-000000000099', false);
do $assert_owner$
begin
    begin
        perform public.fitmatch_vnext_update_closet_item(
            '00000000-0000-0000-0000-000000000401',
            jsonb_build_object('notes', 'other user')
        );
        raise exception 'other user update unexpectedly succeeded';
    exception when others then
        if sqlerrm = 'other user update unexpectedly succeeded' then
            raise;
        end if;
    end;
end
$assert_owner$;

select '20260924_linked_closet_snapshot_round_trip_local_regression_passed' as result;
