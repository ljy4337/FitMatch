\set ON_ERROR_STOP on

-- Isolated PostgreSQL fixture. It uses the deployed public → private group
-- bridge names and exercises the replacement migration without production
-- data, credentials, or Supabase writes.
create schema auth;
create schema fitmatch_vnext;
create role anon;
create role authenticated;
create role service_role;

create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.user_id', true), '')::uuid
$$;

create table fitmatch_vnext.products (
  id uuid primary key, source_code text not null, garment_type_code text
);
create table fitmatch_vnext.product_variants (
  id uuid primary key, product_id uuid not null references fitmatch_vnext.products,
  source_variant_key text not null
);
create table fitmatch_vnext.product_sizes (
  id uuid primary key, variant_id uuid not null references fitmatch_vnext.product_variants,
  source_size_key text not null
);
create table fitmatch_vnext.product_ingestion_receipts (
  id uuid primary key, product_id uuid not null references fitmatch_vnext.products,
  source_code text not null, retailer_facts jsonb not null, observed_at timestamptz not null,
  processing_status text not null
);
create table fitmatch_vnext.product_size_measurements (
  id uuid primary key, product_size_id uuid not null references fitmatch_vnext.product_sizes,
  raw_value numeric not null, is_current boolean not null default true
);
create table fitmatch_vnext.garment_types (
  garment_type_code text primary key, category_code text
);
create table fitmatch_vnext.closet_items (
  id uuid primary key, user_id uuid not null, deleted_at timestamptz,
  comparison_group_code text, created_at timestamptz not null default now()
);

create function fitmatch_vnext.resolve_measurement(
  text,text,text,text,text,text,numeric
) returns jsonb language sql stable as $$
  select jsonb_build_object('resolution_status','UNMAPPED','resolver_version','fixture-v1')
$$;

-- The two canonical functions deliberately contain migration preimages.
create function fitmatch_vnext.canonical_measurements_for_size(p_product_size_id uuid)
returns jsonb language sql stable as $$
  with raw_rows as (
    select m.* from fitmatch_vnext.product_size_measurements m
    where m.product_size_id = p_product_size_id
      and m.is_current
  )
  select jsonb_build_object('measurements', coalesce((
    select jsonb_agg(jsonb_build_object('product_size_measurement_id', id)) from raw_rows
  ), '[]'::jsonb))
$$;
create function fitmatch_vnext.canonical_measurements_for_size_with_context(
  p_product_size_id uuid, p_context jsonb
) returns jsonb language sql stable as $$
  with raw_rows as (
    select m.* from fitmatch_vnext.product_size_measurements m
    where m.product_size_id = p_product_size_id
      and m.is_current
  )
  select jsonb_build_object('measurements', coalesce((
    select jsonb_agg(jsonb_build_object('product_size_measurement_id', id)) from raw_rows
  ), '[]'::jsonb))
$$;

-- Fixture ingress retains the supplied receipt only after its historical
-- positive-only validation. The migration must alter this real function body
-- and the assertion below proves zero survives only as raw evidence.
create function fitmatch_vnext.ingest_product_observation_v2(p_payload jsonb, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare raw_value_value numeric := (p_payload->>'raw_value')::numeric;
begin
  if raw_value_value is null or raw_value_value <= 0
     or nullif(btrim(p_payload->>'raw_code'),'') is null then
    raise exception 'Measurement requires a positive value and code or label';
  end if;
  return jsonb_build_object('accepted', true);
end
$fn$;

-- Existing group owner: it represents the deployed linked path and returns
-- `closet_item_id`, while the regression also verifies that `item_id` is
-- accepted by the migration contract.
create function fitmatch_vnext.upsert_closet_item_with_group_for_swift(p_request jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare item_id_value uuid := (p_request->>'client_item_id')::uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into fitmatch_vnext.closet_items(id,user_id,comparison_group_code)
  values (item_id_value,auth.uid(),nullif(p_request->>'comparison_group_code',''))
  on conflict (id) do nothing;
  if not exists (select 1 from fitmatch_vnext.closet_items
                 where id=item_id_value and user_id=auth.uid()) then
    raise exception 'Closet item is missing or not owned';
  end if;
  return jsonb_build_object('closet_item_id',item_id_value,
    'comparison_group',jsonb_build_object('group_code',
      coalesce(nullif(p_request->>'comparison_group_code',''),'A')));
end
$fn$;

create function fitmatch_vnext.list_closet_items()
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',ci.id,'product_size_id','30000000-0000-0000-0000-000000000001'::uuid,
    'measurements','[]'::jsonb
  ) order by ci.created_at), '[]'::jsonb)
  from fitmatch_vnext.closet_items ci
  where ci.user_id=auth.uid() and ci.deleted_at is null
$$;
create function fitmatch_vnext.closet_comparison_group(p_id uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object('group_code',comparison_group_code)
  from fitmatch_vnext.closet_items where id=p_id and user_id=auth.uid()
$$;
create function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select fitmatch_vnext.upsert_closet_item_with_group_for_swift(p_request)
$$;
create function public.fitmatch_vnext_list_closet_items()
returns jsonb language plpgsql set search_path = '' as $fn$
declare result_value jsonb;
begin
  result_value := fitmatch_vnext.list_closet_items();
  return coalesce((select jsonb_agg(item || jsonb_build_object(
    'comparison_group',fitmatch_vnext.closet_comparison_group((item->>'id')::uuid)
  ) order by ordinal)
  from jsonb_array_elements(result_value) with ordinality rows(item,ordinal)),'[]'::jsonb);
end
$fn$;

create function pg_temp.assert_true(p_value boolean, p_message text)
returns void language plpgsql as $$
begin if p_value is distinct from true then raise exception 'ASSERT: %',p_message; end if; end $$;

insert into fitmatch_vnext.products values
  ('10000000-0000-0000-0000-000000000001','zara','fixture_top');
insert into fitmatch_vnext.garment_types values ('fixture_top','tops');
insert into fitmatch_vnext.product_variants values
  ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','black');
insert into fitmatch_vnext.product_sizes values
  ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','M');
insert into fitmatch_vnext.product_size_measurements values
  ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',50,true),
  ('40000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001',0,true);

\i :migration_file

-- 0 is retained by ingress after the migration but absent from both canonical
-- outputs.
select pg_temp.assert_true(
  fitmatch_vnext.ingest_product_observation_v2(
    '{"raw_value":0,"raw_code":"unknown-zero"}'::jsonb,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid
  )->>'accepted' = 'true', 'zero raw receipt fact is retained'
);
select pg_temp.assert_true(
  jsonb_array_length(fitmatch_vnext.canonical_measurements_for_size(
    '30000000-0000-0000-0000-000000000001'::uuid)->'measurements') = 1,
  'zero raw fact is not canonical'
);
select pg_temp.assert_true(
  jsonb_array_length(fitmatch_vnext.canonical_measurements_for_size_with_context(
    '30000000-0000-0000-0000-000000000001'::uuid,'{}'::jsonb)->'measurements') = 1,
  'zero raw fact is not contextual canonical'
);

insert into fitmatch_vnext.product_ingestion_receipts values (
  '50000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001','zara',
  '{"variants":[{"external_variant_id":"black","sizes":[{"size_identity":"M","measurements":[
    {"measurement_identity":"chest","parser_code":"zara_fixture","raw_code":"chest","raw_label":"가슴","raw_value":50,"raw_value_text":"50.0","raw_unit":"cm","evidence":{"origin":"first"}},
    {"measurement_identity":"unknown-zero","parser_code":"zara_fixture","raw_code":"unknown-zero","raw_label":"","raw_value":0,"raw_value_text":"0","evidence":{"origin":"first"}}
  ]}]}]}'::jsonb,'2026-09-21T00:00:00Z','PROCESSED'
);

select set_config('test.user_id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);
select pg_temp.assert_true(
  (public.fitmatch_vnext_upsert_closet_item(
    '{"client_item_id":"60000000-0000-0000-0000-000000000001","product_id":"10000000-0000-0000-0000-000000000001","product_variant_id":"20000000-0000-0000-0000-000000000001","product_size_id":"30000000-0000-0000-0000-000000000001","source_observation_id":"50000000-0000-0000-0000-000000000001","measurements":[],"comparison_group_code":"B"}'::jsonb
  )->'comparison_group'->>'group_code') = 'B', 'group owner result is retained'
);
select pg_temp.assert_true(
  (select source_measurement_count=2 from fitmatch_vnext.closet_item_source_measurement_snapshots
   where closet_item_id='60000000-0000-0000-0000-000000000001'),
  'first observation freezes all two raw rows'
);
select pg_temp.assert_true(
  (select raw_value=0 and raw_unit_code is null and raw_label='' from
   fitmatch_vnext.closet_item_source_measurements
   where closet_item_id='60000000-0000-0000-0000-000000000001'
     and raw_measurement_key='unknown-zero'),
  'zero unknown raw fact retains original label and unknown unit'
);
select pg_temp.assert_true(
  (public.fitmatch_vnext_list_closet_items()->0 ? 'comparison_group')
  and (public.fitmatch_vnext_list_closet_items()->0 ? 'source_measurements')
  and jsonb_array_length(public.fitmatch_vnext_list_closet_items()->0->'source_measurements')=2,
  'public list preserves group and adds source rows'
);

-- A later current receipt has a third row. Retrying the original request does
-- not append it; using that new receipt for the same client item fails closed.
insert into fitmatch_vnext.product_ingestion_receipts values (
  '50000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000001','zara',
  '{"variants":[{"external_variant_id":"black","sizes":[{"size_identity":"M","measurements":[
    {"measurement_identity":"chest","parser_code":"zara_fixture","raw_code":"chest","raw_label":"가슴","raw_value":51},
    {"measurement_identity":"unknown-zero","parser_code":"zara_fixture","raw_code":"unknown-zero","raw_label":"","raw_value":0},
    {"measurement_identity":"new-row","parser_code":"zara_fixture","raw_code":"new-row","raw_label":"새 항목","raw_value":9}
  ]}]}]}'::jsonb,'2026-09-21T01:00:00Z','PROCESSED'
);
select public.fitmatch_vnext_upsert_closet_item(
  '{"client_item_id":"60000000-0000-0000-0000-000000000001","product_id":"10000000-0000-0000-0000-000000000001","product_variant_id":"20000000-0000-0000-0000-000000000001","product_size_id":"30000000-0000-0000-0000-000000000001","source_observation_id":"50000000-0000-0000-0000-000000000001","measurements":[],"comparison_group_code":"B"}'::jsonb
);
select pg_temp.assert_true((select count(*)=2 from fitmatch_vnext.closet_item_source_measurements
  where closet_item_id='60000000-0000-0000-0000-000000000001'),
  'retry after re-ingestion does not append source rows');
do $$ begin
  begin
    perform public.fitmatch_vnext_upsert_closet_item(
      '{"client_item_id":"60000000-0000-0000-0000-000000000001","product_id":"10000000-0000-0000-0000-000000000001","product_variant_id":"20000000-0000-0000-0000-000000000001","product_size_id":"30000000-0000-0000-0000-000000000001","source_observation_id":"50000000-0000-0000-0000-000000000002","measurements":[]}'::jsonb
    );
    raise exception 'ASSERT: changed receipt was accepted';
  exception when others then
    if position('immutable Closet snapshot' in sqlerrm)=0 then raise; end if;
  end;
end $$;

select set_config('test.user_id','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',false);
select pg_temp.assert_true(public.fitmatch_vnext_list_closet_items()='[]'::jsonb,
  'other user cannot read source snapshot through public list');

-- Rollback is allowed only after explicit fixture cleanup. It restores the
-- group-aware public routes, not the older non-group private functions.
delete from fitmatch_vnext.closet_item_source_measurements;
delete from fitmatch_vnext.closet_item_source_measurement_snapshots;
delete from fitmatch_vnext.product_size_measurements where raw_value <= 0;
\i :rollback_file
select pg_temp.assert_true(
  to_regclass('fitmatch_vnext.closet_item_source_measurements') is null
  and position('upsert_closet_item_with_group_for_swift(p_request)' in
    pg_get_functiondef('public.fitmatch_vnext_upsert_closet_item(jsonb)'::regprocedure)) > 0
  and position('closet_comparison_group' in
    pg_get_functiondef('public.fitmatch_vnext_list_closet_items()'::regprocedure)) > 0,
  'rollback restores group-aware public routes'
);
select pg_temp.assert_true(position('raw_value_value <= 0' in
  pg_get_functiondef('fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)'::regprocedure)) > 0,
  'rollback restores positive-only ingress validation'
);

\echo LOCAL_REGRESSION_PASS
