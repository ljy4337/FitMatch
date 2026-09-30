-- Isolated PostgreSQL regression.  Run against an empty disposable database:
--   psql -v ON_ERROR_STOP=1 -f supabase/sql/tests/measurement_semantic_context_separation_LocalRegression.sql
-- It installs the actual resolver/context/readiness bodies from the prepared
-- migration, not mocked replacements of those functions.

create schema fitmatch_vnext;

create table fitmatch_vnext.source_measurements (
  source_measurement_code text primary key,
  source_code text not null,
  is_active boolean not null,
  is_comparable boolean not null,
  measurement_basis_code text,
  representation_code text
);
create table fitmatch_vnext.fitmatch_measurements (
  measurement_code text primary key,
  canonical_unit_code text,
  canonical_basis_code text,
  representation_code text,
  body_region_code text,
  is_active boolean not null
);
create table fitmatch_vnext.source_measurement_mappings (
  source_measurement_code text primary key,
  fitmatch_measurement_code text not null,
  scale_factor numeric not null,
  offset_value numeric not null,
  is_active boolean not null,
  is_verified boolean not null
);
create table fitmatch_vnext.source_measurement_aliases (
  id uuid primary key,
  source_code text not null,
  parser_code text not null,
  raw_code text,
  raw_label text,
  normalized_label text,
  garment_type_code text,
  fitmatch_category_code text,
  source_measurement_code text not null,
  priority smallint not null,
  is_active boolean not null,
  is_verified boolean not null
);
create table fitmatch_vnext.garment_types (
  garment_type_code text primary key,
  category_code text,
  comparison_policy_code text,
  is_active boolean not null
);
create table fitmatch_vnext.products (
  id uuid primary key,
  source_code text not null,
  garment_type_code text
);
create table fitmatch_vnext.product_variants (id uuid primary key, product_id uuid not null);
create table fitmatch_vnext.product_sizes (id uuid primary key, variant_id uuid not null, size_label text);
create table fitmatch_vnext.product_size_measurements (
  id uuid primary key,
  product_size_id uuid not null,
  parser_code text not null,
  raw_code text,
  raw_label text,
  raw_value numeric,
  evidence_fingerprint text,
  is_current boolean not null
);
create table fitmatch_vnext.comparison_policies (policy_code text primary key, is_active boolean not null);
create table fitmatch_vnext.comparison_metrics (
  comparison_policy_code text not null,
  fitmatch_measurement_code text not null,
  metric_mode text not null,
  is_active boolean not null
);

create function fitmatch_vnext.normalize_measurement_label(p_label text)
returns text language sql immutable set search_path='' as $$
  select nullif(lower(regexp_replace(btrim(coalesce(p_label, '')), '\s+', ' ', 'g')), '');
$$;
create function fitmatch_vnext.resolve_measurement(text,text,text,text,text,text,numeric)
returns jsonb language sql stable set search_path='' as $$ select '{}'::jsonb $$;
create function fitmatch_vnext.canonical_measurements_for_size(p_product_size_id uuid)
returns jsonb language sql stable set search_path='' as $$
with raw_rows as (
  select m.*,p.source_code,p.garment_type_code,gt.category_code
  from fitmatch_vnext.product_size_measurements m
  join fitmatch_vnext.product_sizes ps on ps.id=m.product_size_id
  join fitmatch_vnext.product_variants pv on pv.id=ps.variant_id
  join fitmatch_vnext.products p on p.id=pv.product_id
  left join fitmatch_vnext.garment_types gt on gt.garment_type_code=p.garment_type_code
  where m.product_size_id=p_product_size_id and m.is_current
), d as (
  select r.*,fitmatch_vnext.resolve_measurement(r.source_code,r.parser_code,r.raw_code,r.raw_label,r.garment_type_code,r.category_code,r.raw_value) decision from raw_rows r
)
select jsonb_build_object('product_size_id',p_product_size_id,'measurements',coalesce(jsonb_agg(jsonb_build_object(
  'fitmatch_measurement_code',decision->>'fitmatch_measurement_code','value',(decision->>'canonical_value')::numeric,
  'basis_code',decision->>'canonical_basis_code','source_measurement_code',decision->>'source_measurement_code'
) order by decision->>'fitmatch_measurement_code') filter (where decision->>'resolution_status'='RESOLVED'),'[]'::jsonb)) from d;
$$;
create function fitmatch_vnext.product_comparison_unit_decision(uuid)
returns jsonb language sql stable set search_path='' as $$ select '{"eligible":true}'::jsonb $$;

insert into fitmatch_vnext.fitmatch_measurements values
 ('front_length','cm','front_neck_to_hem','LENGTH','LENGTH',true),
 ('back_length','cm','back_neck_to_hem','LENGTH','LENGTH',true),
 ('chest_width','cm','chest_pit_to_pit','FLAT_WIDTH','CHEST',true),
 ('gathered_body_width','cm','body_width_including_gather_and_tack','FLAT_WIDTH','CHEST',true),
 ('shoulder_width','cm','shoulder_point_to_point','FLAT_WIDTH','SHOULDER',true),
 ('sleeve_center_back_length','cm','sleeve_center_back_to_cuff','LENGTH','SLEEVE',true),
 ('petticoat_length','cm','petticoat_waist_to_hem','LENGTH','LENGTH',true),
 ('petticoat_waist_circumference','cm','petticoat_garment_waist_circumference','CIRCUMFERENCE','WAIST',true);
insert into fitmatch_vnext.source_measurements values
 ('uniqlo.front_length.front_neck_to_hem','uniqlo',true,true,'front_neck_to_hem','LENGTH'),
 ('uniqlo.back_length.back_neck_to_hem','uniqlo',true,true,'back_neck_to_hem','LENGTH'),
 ('uniqlo.chest_width.chest_pit_to_pit','uniqlo',true,true,'chest_pit_to_pit','FLAT_WIDTH'),
 ('uniqlo.gathered_body_width.body_width_including_gather_and_tack','uniqlo',true,false,'body_width_including_gather_and_tack','FLAT_WIDTH'),
 ('uniqlo.shoulder_width.shoulder_point_to_point','uniqlo',true,true,'shoulder_point_to_point','FLAT_WIDTH'),
 ('uniqlo.sleeve_length.sleeve_center_back_to_cuff','uniqlo',true,true,'sleeve_center_back_to_cuff','LENGTH'),
 ('uniqlo.petticoat_length.petticoat_waist_to_hem','uniqlo',true,false,'petticoat_waist_to_hem','LENGTH'),
 ('uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference','uniqlo',true,false,'petticoat_garment_waist_circumference','CIRCUMFERENCE');
insert into fitmatch_vnext.source_measurement_mappings
select 'uniqlo.' || suffix, code, 1, 0, true, true from (values
 ('front_length.front_neck_to_hem','front_length'),('back_length.back_neck_to_hem','back_length'),
 ('chest_width.chest_pit_to_pit','chest_width'),('gathered_body_width.body_width_including_gather_and_tack','gathered_body_width'),
 ('shoulder_width.shoulder_point_to_point','shoulder_width'),('sleeve_length.sleeve_center_back_to_cuff','sleeve_center_back_length'),
 ('petticoat_length.petticoat_waist_to_hem','petticoat_length'),
 ('petticoat_waist_circumference.petticoat_garment_waist_circumference','petticoat_waist_circumference')
) v(suffix,code);

insert into fitmatch_vnext.source_measurement_aliases values
 ('9156094f-2e30-4d6d-913a-0081f5169ad5','uniqlo','official_size_chart','chest-width-html','몸 너비<br>(주름 및 박음질 포함)','몸 너비 (주름 및 박음질 포함)',null,'tops','uniqlo.chest_width.chest_pit_to_pit',30,true,true),
 ('3e5b0fba-7f41-4c7c-b904-b66b8127e41b','uniqlo','official_size_chart','chest-width-html','몸 너비<br>(주름 및 박음질 포함)','몸 너비 (주름 및 박음질 포함)',null,'outerwear','uniqlo.chest_width.chest_pit_to_pit',30,true,true),
 ('2f5985d0-df46-4847-a2e5-0855df03c0af','uniqlo','official_size_chart','chest-width-html','몸 너비<br>(주름 및 박음질 포함)','몸 너비 (주름 및 박음질 포함)',null,'dresses','uniqlo.chest_width.chest_pit_to_pit',30,true,true),
 ('8f95a832-e2c3-4e3a-bc46-eb7b562ce93b','uniqlo','official_size_chart','chest-width-html','몸 너비<br>(주름 및 박음질 포함)','몸 너비 (주름 및 박음질 포함)',null,'underwear','uniqlo.chest_width.chest_pit_to_pit',30,true,true),
 ('8f16f198-16ad-4ee6-984a-627d7d76a920','uniqlo','official_size_chart','chest-width-html','몸 너비<br>(주름 및 박음질 포함)','몸 너비 (주름 및 박음질 포함)',null,'homewear','uniqlo.chest_width.chest_pit_to_pit',30,true,true),
 ('6dbe0706-4ffa-4509-8b7e-b283f1fb71e3','uniqlo','official_size_chart','waist-petticoat-html','허리 둘레 (상품 사이즈)<br> [페티코트]','허리 둘레 [페티코트]',null,'skirts','uniqlo.chest_width.chest_pit_to_pit',30,true,true),
 ('9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc','uniqlo','size_chart','knit-body-length-front','앞기장','앞기장',null,'dresses','uniqlo.back_length.back_neck_to_hem',30,true,true),
 ('74df726e-e236-4019-9548-6bc371ce5ad9','uniqlo','size_chart','knit-body-length-front','앞기장','앞기장',null,'underwear','uniqlo.back_length.back_neck_to_hem',30,true,true),
 ('5e8e11ea-27c4-47db-8dd2-0c9ba9513f46','uniqlo','size_chart','knit-body-length-front','앞기장','앞기장',null,'homewear','uniqlo.back_length.back_neck_to_hem',30,true,true),
 ('b86f0d4a-c767-43fd-8349-265e9ea123b6','uniqlo','official_size_chart','skirt-length-html','치마 길이<br> [페티코트]','치마 길이 [페티코트]',null,'skirts','uniqlo.chest_width.chest_pit_to_pit',30,true,true),
 ('00000000-0000-0000-0000-000000000101','uniqlo','size_chart','body-length-back','뒷기장','뒷기장',null,'tops','uniqlo.back_length.back_neck_to_hem',30,true,true),
 ('00000000-0000-0000-0000-000000000102','uniqlo','size_chart','body-width','몸 너비','몸 너비',null,'tops','uniqlo.chest_width.chest_pit_to_pit',30,true,true),
 ('00000000-0000-0000-0000-000000000103','uniqlo','size_chart','shoulder-width','어깨 너비','어깨 너비',null,'tops','uniqlo.shoulder_width.shoulder_point_to_point',30,true,true),
 ('00000000-0000-0000-0000-000000000104','uniqlo','size_chart','sleeve-length-cb','등 중심부터 소매까지 길이','등 중심부터 소매까지 길이',null,'tops','uniqlo.sleeve_length.sleeve_center_back_to_cuff',30,true,true);

insert into fitmatch_vnext.garment_types values
 ('base_layer_top','tops','policy_top',true),('comparison_group_innerwear','underwear','policy_inner',true),('comparison_group_top','tops','policy_top',true);
insert into fitmatch_vnext.comparison_policies values ('policy_top',true),('policy_inner',true);
insert into fitmatch_vnext.comparison_metrics values ('policy_inner','chest_width','CANONICAL',true),('policy_top','chest_width','CANONICAL',true);
insert into fitmatch_vnext.products values
 ('00000000-0000-0000-0000-000000000201','uniqlo','base_layer_top'),
 ('00000000-0000-0000-0000-000000000202','uniqlo',null);
insert into fitmatch_vnext.product_variants values
 ('00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000201'),
 ('00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000000202');
insert into fitmatch_vnext.product_sizes values
 ('00000000-0000-0000-0000-000000000401','00000000-0000-0000-0000-000000000301','M'),
 ('00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000302','M');
insert into fitmatch_vnext.product_size_measurements values
 ('00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000401','size_chart','body-length-back','뒷기장',68,'a',true),
 ('00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000401','size_chart','body-width','몸 너비',54,'b',true),
 ('00000000-0000-0000-0000-000000000503','00000000-0000-0000-0000-000000000401','size_chart','shoulder-width','어깨 너비',44,'c',true),
 ('00000000-0000-0000-0000-000000000504','00000000-0000-0000-0000-000000000401','size_chart','sleeve-length-cb','등 중심부터 소매까지 길이',65,'d',true),
 ('00000000-0000-0000-0000-000000000505','00000000-0000-0000-0000-000000000402','size_chart','body-width','몸 너비',50,'e',true);

\i supabase/migrations/20260921090000_measurement_semantic_context_separation.sql

do $assert$
declare
  f_context jsonb := jsonb_build_object('product_id','00000000-0000-0000-0000-000000000201','effective_source','CATEGORY_GROUP','garment_type_code','comparison_group_innerwear','category_code','underwear','comparison_policy_code','policy_inner','classification_status','CONFIRMED');
  a_context jsonb := jsonb_build_object('product_id','00000000-0000-0000-0000-000000000201','effective_source','CATEGORY_GROUP','garment_type_code','comparison_group_top','category_code','tops','comparison_policy_code','policy_top','classification_status','CONFIRMED');
  missing_context jsonb := jsonb_build_object('product_id','00000000-0000-0000-0000-000000000202','effective_source','CATEGORY_GROUP','garment_type_code','comparison_group_top','category_code','tops','comparison_policy_code','policy_top','classification_status','CONFIRMED');
  f_result jsonb;
  a_result jsonb;
  missing_result jsonb;
  readiness jsonb;
begin
  if exists (
    with expected(id, source_measurement_code, fitmatch_measurement_code, canonical_unit_code, canonical_basis_code, representation_code) as (
      values
        ('9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'::uuid,'uniqlo.front_length.front_neck_to_hem','front_length','cm','front_neck_to_hem','LENGTH'),
        ('74df726e-e236-4019-9548-6bc371ce5ad9'::uuid,'uniqlo.front_length.front_neck_to_hem','front_length','cm','front_neck_to_hem','LENGTH'),
        ('5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'::uuid,'uniqlo.front_length.front_neck_to_hem','front_length','cm','front_neck_to_hem','LENGTH'),
        ('9156094f-2e30-4d6d-913a-0081f5169ad5'::uuid,'uniqlo.gathered_body_width.body_width_including_gather_and_tack','gathered_body_width','cm','body_width_including_gather_and_tack','FLAT_WIDTH'),
        ('3e5b0fba-7f41-4c7c-b904-b66b8127e41b'::uuid,'uniqlo.gathered_body_width.body_width_including_gather_and_tack','gathered_body_width','cm','body_width_including_gather_and_tack','FLAT_WIDTH'),
        ('2f5985d0-df46-4847-a2e5-0855df03c0af'::uuid,'uniqlo.gathered_body_width.body_width_including_gather_and_tack','gathered_body_width','cm','body_width_including_gather_and_tack','FLAT_WIDTH'),
        ('8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'::uuid,'uniqlo.gathered_body_width.body_width_including_gather_and_tack','gathered_body_width','cm','body_width_including_gather_and_tack','FLAT_WIDTH'),
        ('8f16f198-16ad-4ee6-984a-627d7d76a920'::uuid,'uniqlo.gathered_body_width.body_width_including_gather_and_tack','gathered_body_width','cm','body_width_including_gather_and_tack','FLAT_WIDTH'),
        ('6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'::uuid,'uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference','petticoat_waist_circumference','cm','petticoat_garment_waist_circumference','CIRCUMFERENCE'),
        ('b86f0d4a-c767-43fd-8349-265e9ea123b6'::uuid,'uniqlo.petticoat_length.petticoat_waist_to_hem','petticoat_length','cm','petticoat_waist_to_hem','LENGTH')
    )
    select 1 from expected e
    left join fitmatch_vnext.source_measurement_aliases a on a.id=e.id
    left join fitmatch_vnext.source_measurement_mappings smm on smm.source_measurement_code=a.source_measurement_code
    left join fitmatch_vnext.fitmatch_measurements fm on fm.measurement_code=smm.fitmatch_measurement_code
    where a.source_measurement_code is distinct from e.source_measurement_code
       or smm.fitmatch_measurement_code is distinct from e.fitmatch_measurement_code
       or fm.canonical_unit_code is distinct from e.canonical_unit_code
       or fm.canonical_basis_code is distinct from e.canonical_basis_code
       or fm.representation_code is distinct from e.representation_code
  ) then
    raise exception 'A repaired alias has the wrong canonical semantics or representation';
  end if;
  if fitmatch_vnext.resolve_measurement('uniqlo','size_chart','uniqlo.gathered_body_width.body_width_including_gather_and_tack','',null,null,54)->>'fitmatch_measurement_code' <> 'gathered_body_width' then
    raise exception 'Exact non-comparable source must normalize for preservation';
  end if;
  if fitmatch_vnext.resolve_measurement('uniqlo','size_chart','unknown','unknown',null,null,54)->>'resolution_status' <> 'UNMAPPED' then
    raise exception 'Unknown raw measurement must remain unmapped';
  end if;
  f_result := fitmatch_vnext.canonical_measurements_for_size_with_context('00000000-0000-0000-0000-000000000401',f_context);
  a_result := fitmatch_vnext.canonical_measurements_for_size_with_context('00000000-0000-0000-0000-000000000401',a_context);
  if f_result->'measurements' is distinct from a_result->'measurements'
     or jsonb_array_length(f_result->'measurements') <> 4 then
    raise exception 'Comparison group changed canonical semantics: F %, A %',f_result,a_result;
  end if;
  if not exists (select 1 from jsonb_array_elements(f_result->'measurements') m
    where m->>'fitmatch_measurement_code'='sleeve_center_back_length'
      and m->>'basis_code'='sleeve_center_back_to_cuff' and (m->>'value')::numeric=65) then
    raise exception 'Center-back sleeve must remain distinct and preserved';
  end if;
  missing_result := fitmatch_vnext.canonical_measurements_for_size_with_context('00000000-0000-0000-0000-000000000402',missing_context);
  if jsonb_array_length(missing_result->'measurements') <> 1
     or missing_result->'measurements'->0->>'fitmatch_measurement_code' <> 'chest_width' then
    raise exception 'Existing group-only recovery must remain available';
  end if;
  readiness := fitmatch_vnext.product_measurement_readiness('00000000-0000-0000-0000-000000000201',f_context);
  if readiness->>'status' <> 'READY'
     or (readiness->'size_diagnostics'->0->>'canonical_measurement_count')::int <> 4
     or (readiness->'size_diagnostics'->0->>'policy_measurement_count')::int <> 1 then
    raise exception 'Readiness must distinguish all canonical facts from policy-selected facts: %',readiness;
  end if;
end
$assert$;

select 'PASS: aliases, exact/alias preservation, native-first group invariance, group-only fallback, readiness counts' as result;
