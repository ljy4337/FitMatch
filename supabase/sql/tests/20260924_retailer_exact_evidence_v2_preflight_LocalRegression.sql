\set ON_ERROR_STOP on

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create schema if not exists auth;
create schema if not exists fitmatch_vnext;

create or replace function auth.uid()
returns uuid
language sql
stable
as $$ select nullif(current_setting('app.test_user_id', true), '')::uuid $$;

create table fitmatch_vnext.products (
    id uuid primary key,
    source_code text not null
);
create table fitmatch_vnext.product_variants (
    id uuid primary key,
    product_id uuid not null references fitmatch_vnext.products(id)
);
create table fitmatch_vnext.product_sizes (
    id uuid primary key,
    variant_id uuid not null references fitmatch_vnext.product_variants(id)
);
create table fitmatch_vnext.closet_items (
    id uuid primary key,
    user_id uuid not null,
    product_id uuid,
    product_variant_id uuid,
    product_size_id uuid,
    deleted_at timestamptz
);
create table fitmatch_vnext.closet_item_source_measurement_snapshots (
    closet_item_id uuid primary key,
    source_observation_id uuid not null,
    product_id uuid not null,
    product_variant_id uuid not null,
    product_size_id uuid not null
);
create table fitmatch_vnext.closet_item_source_measurements (
    closet_item_id uuid not null,
    source_code text not null,
    parser_code text not null,
    raw_measurement_key text not null,
    raw_code text,
    raw_value numeric,
    raw_unit_code text,
    raw_representation text,
    evidence_payload jsonb not null default '{}'::jsonb
);
create table fitmatch_vnext.product_size_measurements (
    product_size_id uuid not null,
    parser_code text not null,
    raw_measurement_key text not null,
    raw_code text,
    raw_value numeric,
    raw_unit_code text,
    evidence_payload jsonb not null default '{}'::jsonb,
    is_current boolean not null
);

\ir ../../migrations/20260924103000_retailer_exact_evidence_v2_preflight.sql

insert into fitmatch_vnext.products values
  ('00000000-0000-0000-0000-000000000001', 'uniqlo'),
  ('00000000-0000-0000-0000-000000000002', 'uniqlo'),
  ('00000000-0000-0000-0000-000000000003', 'zara');
insert into fitmatch_vnext.product_variants values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000003');
insert into fitmatch_vnext.product_sizes values
  ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000011'),
  ('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000012'),
  ('00000000-0000-0000-0000-000000000023', '00000000-0000-0000-0000-000000000013');
insert into fitmatch_vnext.closet_items values
  ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000041',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011',
   '00000000-0000-0000-0000-000000000021', null),
  ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000042',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011',
   '00000000-0000-0000-0000-000000000021', null);
insert into fitmatch_vnext.closet_item_source_measurement_snapshots values
  ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000051',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011',
   '00000000-0000-0000-0000-000000000021'),
  ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000052',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011',
   '00000000-0000-0000-0000-000000000021');
insert into fitmatch_vnext.closet_item_source_measurements values
  ('00000000-0000-0000-0000-000000000031', 'uniqlo', 'size_chart', 'body-width',
   'body-width', 54, 'cm', 'flat_width',
   '{"measurement_semantics":{"schema_version":"uniqlo-size-chart-v1","basis_code":"pit_to_pit","representation_code":"flat_width","component_code":"shell"}}'),
  ('00000000-0000-0000-0000-000000000032', 'uniqlo', 'size_chart', 'body-width',
   'body-width', 54, 'cm', 'flat_width',
   '{"measurement_semantics":{"schema_version":"uniqlo-size-chart-v1","basis_code":"pit_to_pit","representation_code":"flat_width","component_code":"shell"}}');
insert into fitmatch_vnext.product_size_measurements values
  ('00000000-0000-0000-0000-000000000022', 'size_chart', 'body-width', 'body-width',
   56, 'cm',
   '{"raw_representation":"flat_width","retailer_evidence":{"measurement_semantics":{"schema_version":"uniqlo-size-chart-v1","basis_code":"pit_to_pit","representation_code":"flat_width","component_code":"shell"}}}', true),
  ('00000000-0000-0000-0000-000000000023', 'size_chart', 'body-width', 'body-width',
   56, 'cm',
   '{"raw_representation":"flat_width","retailer_evidence":{"measurement_semantics":{"schema_version":"zara-size-chart-v1","basis_code":"pit_to_pit","representation_code":"flat_width","component_code":"shell"}}}', true);

select set_config('app.test_user_id', '00000000-0000-0000-0000-000000000041', false);

do $assert_exact_only$
declare valid_evidence jsonb;
begin
  select fitmatch_vnext.retailer_exact_evidence_v2(
    '00000000-0000-0000-0000-000000000031',
    '00000000-0000-0000-0000-000000000022'
  ) into valid_evidence;
  if jsonb_array_length(valid_evidence) <> 1
     or valid_evidence->0->>'mode' <> 'RETAILER_EXACT'
     or coalesce((valid_evidence->0->>'score_included')::boolean, true) then
    raise exception 'Expected one unscored exact evidence row: %', valid_evidence;
  end if;

  if fitmatch_vnext.retailer_exact_evidence_v2(
       '00000000-0000-0000-0000-000000000031',
       '00000000-0000-0000-0000-000000000023'
     ) <> '[]'::jsonb then
    raise exception 'Cross-retailer raw exact must fail closed';
  end if;

  update fitmatch_vnext.product_size_measurements
  set evidence_payload = jsonb_set(
    evidence_payload,
    '{retailer_evidence,measurement_semantics,component_code}',
    '"lining"'::jsonb
  )
  where product_size_id = '00000000-0000-0000-0000-000000000022';
  if fitmatch_vnext.retailer_exact_evidence_v2(
       '00000000-0000-0000-0000-000000000031',
       '00000000-0000-0000-0000-000000000022'
     ) <> '[]'::jsonb then
    raise exception 'Component mismatch must fail closed';
  end if;

  if fitmatch_vnext.retailer_exact_evidence_v2(
       '00000000-0000-0000-0000-000000000032',
       '00000000-0000-0000-0000-000000000022'
     ) <> '[]'::jsonb then
    raise exception 'Other users must not obtain evidence';
  end if;
end
$assert_exact_only$;

\ir ../20260924103000_retailer_exact_evidence_v2_preflight_Rollback.sql

do $assert_rollback$
begin
  if to_regprocedure('fitmatch_vnext.retailer_exact_evidence_v2(uuid,uuid)') is not null
     or to_regprocedure('fitmatch_vnext.retailer_exact_semantic_contract_v2(jsonb)') is not null then
    raise exception 'Retailer-exact v2 rollback left a function behind';
  end if;
end
$assert_rollback$;

select '20260924_retailer_exact_evidence_v2_preflight_local_regression_passed' as result;
