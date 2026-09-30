begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:product-runtime-policy-v1'));

insert into fitmatch_taxonomy.policy_versions (
  code,schema_version,taxonomy_version,manifest_checksum,status,validated_at
) values (
  'db-runtime-2026-08-18-v1','2.0','fitmatch-runtime-2026-08-18',
  'c053dd2f0b6a5170726107322c26f7188b259f5cbbb042f5d6878c7479ce9cb0',
  'validated',now()
)
on conflict (code) do nothing;

insert into fitmatch_taxonomy.comparison_families (
  code,minimum_comparable_measurements,current_app_family_code,
  is_active,policy_version
) values (
  'underwear',2,'underwear',true,'db-runtime-2026-08-18-v1'
)
on conflict (code) do update set
  minimum_comparable_measurements=excluded.minimum_comparable_measurements,
  current_app_family_code=excluded.current_app_family_code,
  is_active=excluded.is_active,
  policy_version=excluded.policy_version;

insert into fitmatch_taxonomy.measurement_definitions (
  code,display_name,unit,representation,preserve_raw,policy_version
) values
  ('foot_length','발길이','cm','linear',true,'db-runtime-2026-08-18-v1'),
  ('upper_abdomen_width','복부단면','cm','linear',true,'db-runtime-2026-08-18-v1'),
  ('upper_waist_width','상의 허리단면','cm','linear',true,'db-runtime-2026-08-18-v1')
on conflict (code) do nothing;

alter table fitmatch_taxonomy.comparison_compatibility_rules
  add column if not exists required_any_measurements text[] not null default '{}',
  add column if not exists minimum_required_any smallint not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='comparison_compatibility_minimum_required_any_check'
      and conrelid='fitmatch_taxonomy.comparison_compatibility_rules'::regclass
  ) then
    alter table fitmatch_taxonomy.comparison_compatibility_rules
      add constraint comparison_compatibility_minimum_required_any_check
      check (minimum_required_any >= 0
        and minimum_required_any <= cardinality(required_any_measurements));
  end if;
end $$;

create table if not exists fitmatch_taxonomy.comparison_detail_compatibility_rules (
  from_family_code text not null
    references fitmatch_taxonomy.comparison_families(code) on delete restrict,
  from_detail_code text not null,
  to_family_code text not null
    references fitmatch_taxonomy.comparison_families(code) on delete restrict,
  to_detail_code text not null,
  allowed boolean not null,
  directional boolean not null default false,
  excluded_measurements text[] not null default '{}',
  reason_code text not null,
  policy_version text not null
    references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  primary key (
    from_family_code,from_detail_code,to_family_code,to_detail_code,policy_version
  ),
  constraint comparison_detail_codes_not_blank_check
    check (btrim(from_detail_code)<>'' and btrim(to_detail_code)<>''),
  constraint comparison_detail_reason_not_blank_check
    check (btrim(reason_code)<>'')
);

alter table fitmatch_taxonomy.comparison_detail_compatibility_rules
  enable row level security;
revoke all on fitmatch_taxonomy.comparison_detail_compatibility_rules
  from public,anon,authenticated;
grant select,insert,update,delete
  on fitmatch_taxonomy.comparison_detail_compatibility_rules to service_role;

alter table fitmatch_catalog.product_measurements
  add column if not exists measurement_kind text;
create index if not exists product_measurements_comparison_basis_idx
  on fitmatch_catalog.product_measurements
    (product_size_id,comparison_basis,measurement_kind)
  where is_comparable and comparison_basis is not null;

create or replace function fitmatch_catalog.runtime_measurement_kind(
  p_measurement_code text,
  p_comparison_basis text
) returns text
language sql
immutable
security invoker
set search_path=pg_catalog
as $$
  select case
    when p_comparison_basis like 'shoulder_%' then 'shoulder'
    when p_comparison_basis like 'chest_%' then 'chest'
    when p_comparison_basis in (
      'back_neck_to_hem','hps_to_hem_front','waist_to_skirt_hem',
      'waist_to_outer_hem','crotch_to_inner_hem'
    ) then 'total_length'
    when p_comparison_basis like 'sleeve_%' then 'sleeve_length'
    when p_comparison_basis='upper_abdomen_edge_to_edge' then 'upper_abdomen'
    when p_comparison_basis='upper_waist_edge_to_edge' then 'upper_waist'
    when p_comparison_basis='waist_edge_to_edge' then 'waist'
    when p_comparison_basis='hip_at_widest' then 'hip'
    when p_comparison_basis='thigh_crotch_to_outer' then 'thigh'
    when p_comparison_basis='front_crotch_to_waist' then 'rise'
    when p_comparison_basis='hem_edge_to_edge' then 'hem'
    when p_comparison_basis='heel_to_toe' then 'foot_length'
    when p_comparison_basis='under_bust_edge_to_edge' then 'under_bust'
    when p_measurement_code in ('shoulder','shoulder_width') then 'shoulder'
    when p_measurement_code in ('chest','chest_width') then 'chest'
    when p_measurement_code in ('back_length','total_length','inseam') then 'total_length'
    when p_measurement_code='sleeve_length' then 'sleeve_length'
    when p_measurement_code in ('waist','waist_width','waist_circumference') then 'waist'
    when p_measurement_code in ('hip','hip_width','hip_circumference') then 'hip'
    when p_measurement_code in ('thigh','thigh_width') then 'thigh'
    when p_measurement_code in ('rise','front_rise') then 'rise'
    when p_measurement_code in ('hem','hem_width') then 'hem'
    when p_measurement_code='foot_length' then 'foot_length'
    when p_measurement_code='under_bust' then 'under_bust'
    else null
  end
$$;

update fitmatch_catalog.product_measurements
set measurement_kind=fitmatch_catalog.runtime_measurement_kind(
  measurement_code,comparison_basis
)
where measurement_kind is null;

-- Missing UNIQLO keys used by the production parser. Category scope is
-- mandatory for scoped aliases; ambiguous measurements fail closed.
insert into fitmatch_taxonomy.source_measurement_aliases (
  source_code,parser_code,raw_code,raw_label,normalized_raw_label,
  measurement_code,raw_representation,comparison_basis,
  conversion_multiplier,category_scopes,is_comparable,evidence,policy_version
) values
  ('uniqlo','size_chart','shoulder-width','어깨너비','어깨너비',
   'shoulder_width','shoulder_seam_to_seam','shoulder_seam_to_seam',
   1,array['tops','outerwear'],'true','Production parser parity: shoulder-width.',
   'db-runtime-2026-08-18-v1'),
  ('uniqlo','size_chart','body-width','몸폭','몸폭',
   'chest_width','chest_pit_to_pit','chest_pit_to_pit',
   1,array['tops','outerwear','dresses','underwear','homewear'],'true',
   'Production parser parity: body-width.','db-runtime-2026-08-18-v1'),
  ('uniqlo','size_chart','body-length','옷길이','옷길이',
   'back_length','back_neck_to_hem','back_neck_to_hem',
   1,array['tops','outerwear','dresses','underwear','homewear'],'true',
   'Production parser parity: body-length.','db-runtime-2026-08-18-v1'),
  ('uniqlo','size_chart','body-length-back','뒷기장','뒷기장',
   'back_length','back_neck_to_hem','back_neck_to_hem',
   1,array['tops','outerwear','dresses','underwear','homewear'],'true',
   'Production parser parity: body-length-back.','db-runtime-2026-08-18-v1'),
  ('uniqlo','size_chart','knit-body-length-front','앞기장','앞기장',
   'back_length','back_neck_to_hem','back_neck_to_hem',
   1,array['tops','outerwear','dresses','underwear','homewear'],'true',
   'Production parser v7 canonicalizes knit front length to body length.',
   'db-runtime-2026-08-18-v1'),
  ('uniqlo','size_chart','waist-product-size-bottoms','허리둘레','허리둘레',
   'waist_circumference','garment_waist_circumference','waist_edge_to_edge',
   0.5,array['bottoms','skirts'],'true',
   'Production parser parity: waist-product-size-bottoms.',
   'db-runtime-2026-08-18-v1'),
  ('musinsa','actual_size','','복부단면','복부단면',
   'upper_abdomen_width','upper_abdomen_edge_to_edge','upper_abdomen_edge_to_edge',
   1,array['tops'],'true','Production parser parity: upper abdomen.',
   'db-runtime-2026-08-18-v1'),
  ('musinsa','actual_size','','허리단면','허리단면',
   'upper_waist_width','upper_waist_edge_to_edge','upper_waist_edge_to_edge',
   1,array['tops'],'true','Production parser parity: upper waist.',
   'db-runtime-2026-08-18-v1'),
  ('musinsa','actual_size','','발길이','발길이',
   'foot_length','heel_to_toe','heel_to_toe',
   1,array['shoes'],'true','FitMatch shoe comparison basis.',
   'db-runtime-2026-08-18-v1'),
  ('musinsa','actual_size','','밑가슴단면','밑가슴단면',
   'under_bust','under_bust_edge_to_edge','under_bust_edge_to_edge',
   1,array['underwear'],'true','FitMatch underwear comparison basis.',
   'db-runtime-2026-08-18-v1')
on conflict (source_code,raw_label,measurement_code,policy_version)
do update set
  parser_code=excluded.parser_code,
  raw_code=excluded.raw_code,
  normalized_raw_label=excluded.normalized_raw_label,
  raw_representation=excluded.raw_representation,
  comparison_basis=excluded.comparison_basis,
  conversion_multiplier=excluded.conversion_multiplier,
  category_scopes=excluded.category_scopes,
  is_comparable=excluded.is_comparable,
  evidence=excluded.evidence;

create or replace function fitmatch_catalog.runtime_normalize_measurement_v2(
  p_source text,
  p_parser_code text,
  p_raw_code text,
  p_raw_label text,
  p_raw_value numeric,
  p_raw_unit text default 'cm',
  p_category_scope text default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_taxonomy,fitmatch_catalog
as $$
declare
  v_alias fitmatch_taxonomy.source_measurement_aliases%rowtype;
  v_label text:=lower(regexp_replace(btrim(coalesce(p_raw_label,'')),E'\\s+',' ','g'));
  v_code text:=lower(regexp_replace(btrim(coalesce(p_raw_code,'')),'[ _-]+','','g'));
  v_unit_multiplier numeric;
  v_multiplier numeric;
  v_kind text;
begin
  if p_raw_value is null or p_raw_value<=0 then
    return jsonb_build_object('mapped',false,'comparable',false,'reason','invalid_raw_value');
  end if;
  v_unit_multiplier:=case lower(btrim(coalesce(p_raw_unit,'cm')))
    when 'cm' then 1 when 'mm' then 0.1 when 'in' then 2.54
    when 'inch' then 2.54 else null end;
  if v_unit_multiplier is null then
    return jsonb_build_object('mapped',false,'comparable',false,'reason','unsupported_unit');
  end if;

  select a.* into v_alias
  from fitmatch_taxonomy.source_measurement_aliases a
  left join fitmatch_taxonomy.policy_versions pv on pv.code=a.policy_version
  where a.source_code=lower(p_source)
    and (a.parser_code is null or p_parser_code is null or a.parser_code=p_parser_code)
    and (
      (v_code<>'' and lower(regexp_replace(btrim(coalesce(a.raw_code,'')),'[ _-]+','','g'))=v_code)
      or (v_code='' and (
        a.normalized_raw_label=v_label
        or lower(regexp_replace(btrim(a.raw_label),E'\\s+',' ','g'))=v_label
      ))
    )
    and (
      a.category_scopes is null or cardinality(a.category_scopes)=0
      or (p_category_scope is not null and p_category_scope=any(a.category_scopes))
    )
  order by pv.created_at desc nulls last,
    (a.raw_code is not null and btrim(a.raw_code)<>'') desc,a.id
  limit 1;

  if not found then
    return jsonb_build_object(
      'mapped',false,'comparable',false,'reason','measurement_alias_not_found',
      'raw_code',p_raw_code,'raw_label',p_raw_label,'category_scope',p_category_scope
    );
  end if;
  v_multiplier:=coalesce(v_alias.conversion_multiplier,1)*v_unit_multiplier;
  v_kind:=fitmatch_catalog.runtime_measurement_kind(
    v_alias.measurement_code,v_alias.comparison_basis
  );
  return jsonb_build_object(
    'mapped',true,'source_alias_id',v_alias.id,
    'measurement_code',v_alias.measurement_code,'measurement_kind',v_kind,
    'raw_representation',v_alias.raw_representation,
    'comparison_basis',v_alias.comparison_basis,
    'conversion_multiplier',v_multiplier,
    'normalized_value',case when v_alias.is_comparable
      and v_alias.comparison_basis is not null and v_kind is not null
      then p_raw_value*v_multiplier else null end,
    'normalized_unit','cm',
    'comparable',v_alias.is_comparable
      and v_alias.comparison_basis is not null and v_kind is not null,
    'reason',case
      when not v_alias.is_comparable then 'alias_marked_not_comparable'
      when v_alias.comparison_basis is null then 'comparison_basis_missing'
      when v_kind is null then 'measurement_kind_missing'
      else null end,
    'policy_version',v_alias.policy_version,'evidence',v_alias.evidence
  );
end $$;

create or replace function fitmatch_catalog.runtime_upsert_measurement(
  p_product_size_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare
  v_source text;
  v_raw_label text:=btrim(coalesce(p_payload->>'raw_label',''));
  v_raw_value numeric:=nullif(p_payload->>'raw_value','')::numeric;
  v_raw_unit text:=coalesce(nullif(p_payload->>'raw_unit',''),'cm');
  v_identity text;
  v_normalized jsonb;
  v_id uuid;
begin
  select p.source into v_source
  from fitmatch_catalog.product_sizes s
  join fitmatch_catalog.product_variants v on v.id=s.variant_id
  join fitmatch_catalog.products p on p.id=v.product_id
  where s.id=p_product_size_id;
  if not found then raise exception using errcode='P0002',message='product_size_not_found'; end if;
  if v_raw_label='' or v_raw_value is null or v_raw_value<=0 then
    raise exception using errcode='22023',message='invalid_measurement';
  end if;
  v_identity:=btrim(coalesce(nullif(p_payload->>'measurement_identity',''),
    nullif(p_payload->>'raw_code',''),lower(v_raw_label)));
  v_normalized:=fitmatch_catalog.runtime_normalize_measurement_v2(
    v_source,nullif(p_payload->>'parser_code',''),nullif(p_payload->>'raw_code',''),
    v_raw_label,v_raw_value,v_raw_unit,nullif(p_payload->>'category_scope','')
  );

  insert into fitmatch_catalog.product_measurements (
    product_size_id,measurement_identity,measurement_code,measurement_kind,raw_code,
    raw_label,raw_value,raw_unit,raw_representation,normalized_value,
    normalized_unit,comparison_basis,conversion_multiplier,is_comparable,
    exclusion_reason,source_alias_id,policy_version,evidence,observed_at
  ) values (
    p_product_size_id,v_identity,nullif(v_normalized->>'measurement_code',''),
    nullif(v_normalized->>'measurement_kind',''),nullif(p_payload->>'raw_code',''),
    v_raw_label,v_raw_value,v_raw_unit,nullif(v_normalized->>'raw_representation',''),
    nullif(v_normalized->>'normalized_value','')::numeric,
    nullif(v_normalized->>'normalized_unit',''),nullif(v_normalized->>'comparison_basis',''),
    nullif(v_normalized->>'conversion_multiplier','')::numeric,
    coalesce((v_normalized->>'comparable')::boolean,false),
    nullif(v_normalized->>'reason',''),nullif(v_normalized->>'source_alias_id','')::uuid,
    nullif(v_normalized->>'policy_version',''),
    jsonb_build_object('normalization',v_normalized,'source_payload',
      case when jsonb_typeof(p_payload->'evidence')='object'
        then p_payload->'evidence' else '{}'::jsonb end),
    coalesce(nullif(p_payload->>'observed_at','')::timestamptz,now())
  )
  on conflict (product_size_id,measurement_identity) do update set
    measurement_code=excluded.measurement_code,measurement_kind=excluded.measurement_kind,
    raw_code=excluded.raw_code,raw_label=excluded.raw_label,raw_value=excluded.raw_value,
    raw_unit=excluded.raw_unit,raw_representation=excluded.raw_representation,
    normalized_value=excluded.normalized_value,normalized_unit=excluded.normalized_unit,
    comparison_basis=excluded.comparison_basis,
    conversion_multiplier=excluded.conversion_multiplier,
    is_comparable=excluded.is_comparable,exclusion_reason=excluded.exclusion_reason,
    source_alias_id=excluded.source_alias_id,policy_version=excluded.policy_version,
    evidence=excluded.evidence,observed_at=excluded.observed_at,updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

-- Runtime policy mirrors the current engine's minimum/required-any semantics.
insert into fitmatch_taxonomy.comparison_compatibility_rules (
  from_family_code,to_family_code,allowed,directional,length_match_required,
  length_mismatch_excluded_measurements,minimum_common_measurements,
  required_measurements,required_any_measurements,minimum_required_any,
  measurement_weights,fallback_allowed,policy_version
) values
  ('tshirt','tshirt',true,false,true,array['sleeve_length'],2,array[]::text[],array['shoulder','chest'],1,
   '{"shoulder":1.2,"chest":1.4,"total_length":1.0,"sleeve_length":0.8}',true,'db-runtime-2026-08-18-v1'),
  ('shirt','shirt',true,false,true,array['sleeve_length'],2,array[]::text[],array['shoulder','chest'],1,
   '{"shoulder":1.2,"chest":1.4,"total_length":1.0,"sleeve_length":0.8}',true,'db-runtime-2026-08-18-v1'),
  ('knit_cardigan','knit_cardigan',true,false,true,array['sleeve_length'],2,array[]::text[],array['shoulder','chest'],1,
   '{"shoulder":1.2,"chest":1.4,"total_length":1.0,"sleeve_length":0.8}',true,'db-runtime-2026-08-18-v1'),
  ('sweatshirt','sweatshirt',true,false,true,array['sleeve_length'],2,array[]::text[],array['shoulder','chest'],1,
   '{"shoulder":1.2,"chest":1.4,"total_length":1.0,"sleeve_length":0.8}',true,'db-runtime-2026-08-18-v1'),
  ('hoodie','hoodie',true,false,true,array['sleeve_length'],2,array[]::text[],array['shoulder','chest'],1,
   '{"shoulder":1.2,"chest":1.4,"total_length":1.0,"sleeve_length":0.8}',true,'db-runtime-2026-08-18-v1'),
  ('outerwear','outerwear',true,false,true,array['sleeve_length'],2,array['chest'],array[]::text[],0,
   '{"shoulder":1.1,"chest":1.5,"total_length":0.8,"sleeve_length":1.0,"hem":0.6}',false,'db-runtime-2026-08-18-v1'),
  ('leather_jacket','leather_jacket',true,false,true,array['sleeve_length'],2,array['chest'],array[]::text[],0,
   '{"shoulder":1.1,"chest":1.5,"total_length":0.8,"sleeve_length":1.0,"hem":0.6}',false,'db-runtime-2026-08-18-v1'),
  ('pants','pants',true,false,true,array['total_length'],2,array[]::text[],array['waist','hip','thigh'],2,
   '{"waist":1.4,"hip":1.2,"thigh":0.9,"rise":0.7,"hem":0.6,"total_length":1.0}',true,'db-runtime-2026-08-18-v1'),
  ('denim','denim',true,false,true,array['total_length'],2,array[]::text[],array['waist','hip','thigh'],2,
   '{"waist":1.4,"hip":1.2,"thigh":0.9,"rise":0.7,"hem":0.6,"total_length":1.0}',true,'db-runtime-2026-08-18-v1'),
  ('pants','denim',true,true,true,array['total_length'],2,array[]::text[],array['waist','hip','thigh'],2,
   '{"waist":1.4,"hip":1.2,"thigh":0.9,"rise":0.7,"hem":0.6,"total_length":1.0}',true,'db-runtime-2026-08-18-v1'),
  ('denim','pants',true,true,true,array['total_length'],2,array[]::text[],array['waist','hip','thigh'],2,
   '{"waist":1.4,"hip":1.2,"thigh":0.9,"rise":0.7,"hem":0.6,"total_length":1.0}',true,'db-runtime-2026-08-18-v1'),
  ('leggings','leggings',true,false,true,array['total_length'],2,array[]::text[],array['waist','hip','thigh'],2,
   '{"waist":1.4,"hip":1.2,"total_length":1.0}',true,'db-runtime-2026-08-18-v1'),
  ('skirt','skirt',true,false,true,array['total_length'],2,array[]::text[],array['waist','hip'],1,
   '{"waist":1.4,"hip":1.2,"total_length":1.0}',true,'db-runtime-2026-08-18-v1'),
  ('dress','dress',true,false,true,array['sleeve_length'],2,array[]::text[],array['chest','waist','hip'],1,
   '{"shoulder":1.0,"chest":1.2,"total_length":1.0,"waist":1.0,"hip":0.9}',true,'db-runtime-2026-08-18-v1'),
  ('underwear','underwear',true,false,false,array[]::text[],2,array[]::text[],
   array['chest','waist','hip','under_bust','foot_length'],1,
   '{"chest":1.1,"total_length":0.7,"waist":1.3,"hip":1.2,"under_bust":1.4,"foot_length":1.0}',false,'db-runtime-2026-08-18-v1')
on conflict (from_family_code,to_family_code,policy_version) do update set
  allowed=excluded.allowed,directional=excluded.directional,
  length_match_required=excluded.length_match_required,
  length_mismatch_excluded_measurements=excluded.length_mismatch_excluded_measurements,
  minimum_common_measurements=excluded.minimum_common_measurements,
  required_measurements=excluded.required_measurements,
  required_any_measurements=excluded.required_any_measurements,
  minimum_required_any=excluded.minimum_required_any,
  measurement_weights=excluded.measurement_weights,
  fallback_allowed=excluded.fallback_allowed;

create or replace function fitmatch_catalog.runtime_evaluate_comparison_profiles_v2(
  p_reference_family text,p_reference_detail text,p_reference_length text,
  p_target_family text,p_target_detail text,p_target_length text,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_taxonomy
as $$
declare
  v_rule fitmatch_taxonomy.comparison_compatibility_rules%rowtype;
  v_detail_rule fitmatch_taxonomy.comparison_detail_compatibility_rules%rowtype;
  v_length_mismatch boolean;
begin
  if p_reference_family is null or p_target_family is null then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','comparison_family_missing');
  end if;
  if p_reference_detail is null or p_target_detail is null then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','comparison_detail_missing');
  end if;
  select r.* into v_rule
  from fitmatch_taxonomy.comparison_compatibility_rules r
  left join fitmatch_taxonomy.policy_versions pv on pv.code=r.policy_version
  where (r.from_family_code=p_reference_family and r.to_family_code=p_target_family)
     or (not r.directional and r.from_family_code=p_target_family and r.to_family_code=p_reference_family)
  order by (r.from_family_code=p_reference_family and r.to_family_code=p_target_family) desc,
    pv.created_at desc nulls last
  limit 1;
  if not found then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','compatibility_rule_missing',
      'reference_family',p_reference_family,'target_family',p_target_family);
  end if;
  if not v_rule.allowed then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','compatibility_rule_denied',
      'policy_version',v_rule.policy_version);
  end if;

  if p_reference_detail<>p_target_detail then
    if not p_allow_extended then
      return jsonb_build_object('allowed',false,'level','incompatible','reason','detail_mismatch');
    end if;
    select d.* into v_detail_rule
    from fitmatch_taxonomy.comparison_detail_compatibility_rules d
    left join fitmatch_taxonomy.policy_versions pv on pv.code=d.policy_version
    where (d.from_family_code=p_reference_family and d.from_detail_code=p_reference_detail
      and d.to_family_code=p_target_family and d.to_detail_code=p_target_detail)
      or (not d.directional and d.from_family_code=p_target_family and d.from_detail_code=p_target_detail
      and d.to_family_code=p_reference_family and d.to_detail_code=p_reference_detail)
    order by pv.created_at desc nulls last limit 1;
    if not found or not v_detail_rule.allowed then
      return jsonb_build_object('allowed',false,'level','incompatible','reason','detail_rule_missing_or_denied');
    end if;
  end if;

  if v_rule.length_match_required and (
    p_reference_length is null or p_target_length is null
    or p_reference_length='unknown' or p_target_length='unknown'
  ) then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','length_classification_missing',
      'policy_version',v_rule.policy_version);
  end if;
  v_length_mismatch:=p_reference_length is not null and p_target_length is not null
    and p_reference_length<>p_target_length;
  if v_rule.length_match_required and v_length_mismatch
     and not (p_allow_extended and v_rule.fallback_allowed) then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','length_mismatch',
      'policy_version',v_rule.policy_version);
  end if;
  return jsonb_build_object(
    'allowed',true,'level',case when p_reference_detail<>p_target_detail
      or (v_rule.length_match_required and v_length_mismatch) then 'extended' else 'direct' end,
    'reason',null,'reference_family',p_reference_family,'target_family',p_target_family,
    'reference_detail',p_reference_detail,'target_detail',p_target_detail,
    'reference_length',p_reference_length,'target_length',p_target_length,
    'length_mismatch',v_length_mismatch,
    'excluded_measurements',to_jsonb(
      case when v_length_mismatch then v_rule.length_mismatch_excluded_measurements
        else array[]::text[] end
      || case when v_detail_rule.from_family_code is not null
        then v_detail_rule.excluded_measurements else array[]::text[] end),
    'minimum_common_measurements',v_rule.minimum_common_measurements,
    'required_measurements',to_jsonb(v_rule.required_measurements),
    'required_any_measurements',to_jsonb(v_rule.required_any_measurements),
    'minimum_required_any',v_rule.minimum_required_any,
    'measurement_weights',v_rule.measurement_weights,
    'policy_version',v_rule.policy_version
  );
end $$;

create or replace function fitmatch_catalog.runtime_evaluate_product_compatibility(
  p_reference_product_id uuid,p_target_product_id uuid,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare
  v_reference fitmatch_catalog.product_classification_history%rowtype;
  v_target fitmatch_catalog.product_classification_history%rowtype;
begin
  select * into v_reference from fitmatch_catalog.product_classification_history
  where product_id=p_reference_product_id and is_current;
  select * into v_target from fitmatch_catalog.product_classification_history
  where product_id=p_target_product_id and is_current;
  if v_reference.id is null or v_target.id is null then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','classification_missing');
  end if;
  if v_reference.classification_status<>'confirmed' or v_target.classification_status<>'confirmed' then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','classification_not_confirmed');
  end if;
  return fitmatch_catalog.runtime_evaluate_comparison_profiles_v2(
    v_reference.comparison_family_code,v_reference.detail_code,v_reference.length_code,
    v_target.comparison_family_code,v_target.detail_code,v_target.length_code,p_allow_extended
  );
end $$;

create or replace function fitmatch_catalog.runtime_prepare_size_comparison(
  p_reference_size_id uuid,p_target_size_id uuid,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare
  v_reference_product_id uuid; v_target_product_id uuid;
  v_compatibility jsonb; v_pairs jsonb; v_pair_count integer;
  v_missing_required text[]; v_required_any_count integer; v_minimum integer;
  v_minimum_required_any integer;
begin
  select v.product_id into v_reference_product_id
  from fitmatch_catalog.product_sizes s join fitmatch_catalog.product_variants v on v.id=s.variant_id
  where s.id=p_reference_size_id;
  select v.product_id into v_target_product_id
  from fitmatch_catalog.product_sizes s join fitmatch_catalog.product_variants v on v.id=s.variant_id
  where s.id=p_target_size_id;
  if v_reference_product_id is null or v_target_product_id is null then
    return jsonb_build_object('ready',false,'reason','product_size_not_found','pairs','[]'::jsonb);
  end if;
  v_compatibility:=fitmatch_catalog.runtime_evaluate_product_compatibility(
    v_reference_product_id,v_target_product_id,p_allow_extended);
  if not coalesce((v_compatibility->>'allowed')::boolean,false) then
    return jsonb_build_object('ready',false,'reason',v_compatibility->>'reason',
      'compatibility',v_compatibility,'pairs','[]'::jsonb);
  end if;

  with pairs as (
    select r.measurement_kind as measurement_code,r.comparison_basis,
      r.normalized_value reference_value,t.normalized_value target_value,
      t.normalized_value-r.normalized_value signed_difference,
      abs(t.normalized_value-r.normalized_value) absolute_difference,
      coalesce(nullif(v_compatibility->'measurement_weights'->>r.measurement_kind,'')::numeric,1) weight
    from fitmatch_catalog.product_measurements r
    join fitmatch_catalog.product_measurements t
      on t.product_size_id=p_target_size_id and t.comparison_basis=r.comparison_basis
      and t.is_comparable and t.measurement_kind=r.measurement_kind
    where r.product_size_id=p_reference_size_id and r.is_comparable
      and r.comparison_basis is not null and r.measurement_kind is not null
      and not ((v_compatibility->'excluded_measurements') ? r.measurement_kind)
  )
  select coalesce(jsonb_agg(to_jsonb(p) order by p.measurement_code),'[]'::jsonb),count(*)
  into v_pairs,v_pair_count from pairs p;

  select coalesce(array_agg(required_code order by required_code),'{}'::text[])
  into v_missing_required
  from jsonb_array_elements_text(coalesce(v_compatibility->'required_measurements','[]'))
    as required(required_code)
  where not exists (select 1 from jsonb_array_elements(v_pairs) as pairs(pair)
    where pair->>'measurement_code'=required_code);
  select count(*) into v_required_any_count
  from jsonb_array_elements_text(coalesce(v_compatibility->'required_any_measurements','[]'))
    as required_any(required_code)
  where exists (select 1 from jsonb_array_elements(v_pairs) as pairs(pair)
    where pair->>'measurement_code'=required_code);
  v_minimum:=coalesce(nullif(v_compatibility->>'minimum_common_measurements','')::integer,1);
  v_minimum_required_any:=coalesce(nullif(v_compatibility->>'minimum_required_any','')::integer,0);
  return jsonb_build_object(
    'ready',v_pair_count>=v_minimum and cardinality(v_missing_required)=0
      and v_required_any_count>=v_minimum_required_any,
    'reason',case when v_pair_count<v_minimum then 'insufficient_common_measurements'
      when cardinality(v_missing_required)>0 then 'required_measurements_missing'
      when v_required_any_count<v_minimum_required_any then 'required_any_measurements_missing'
      else null end,
    'compatibility',v_compatibility,'common_measurement_count',v_pair_count,
    'minimum_common_measurements',v_minimum,
    'missing_required_measurements',to_jsonb(v_missing_required),
    'required_any_available_count',v_required_any_count,
    'minimum_required_any',v_minimum_required_any,'pairs',v_pairs);
end $$;

create or replace function public.fitmatch_begin_comparison(
  p_reference_item_id uuid,
  p_target_product_id uuid,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_reference_product_id uuid;
  v_reference_family text; v_reference_detail text; v_reference_length text;
  v_target_family text; v_target_detail text; v_target_length text; v_target_status text;
  v_compatibility jsonb; v_run_id uuid; v_status text;
begin
  if v_user_id is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  select c.product_id,
    case when o.id is not null then o.comparison_family_code else c.comparison_family_code end,
    case when o.id is not null then o.detail_code else c.canonical_detail_code end,
    case when o.id is not null then o.length_code else c.comparison_length_code end
  into v_reference_product_id,v_reference_family,v_reference_detail,v_reference_length
  from public.closet_items c
  left join public.closet_item_classification_overrides o
    on o.closet_item_id=c.id and o.user_id=c.user_id
  where c.id=p_reference_item_id and c.user_id=v_user_id and c.deleted_at is null;
  if v_reference_product_id is null then
    raise exception using errcode='P0002',message='reference_product_not_linked';
  end if;
  if not exists(select 1 from fitmatch_catalog.products where id=p_target_product_id) then
    raise exception using errcode='P0002',message='target_product_not_found';
  end if;
  select classification_status,comparison_family_code,detail_code,length_code
  into v_target_status,v_target_family,v_target_detail,v_target_length
  from fitmatch_catalog.product_classification_history
  where product_id=p_target_product_id and is_current;
  if not found or v_target_status<>'confirmed' then
    v_compatibility:=jsonb_build_object('allowed',false,'level','incompatible',
      'reason','target_classification_not_confirmed','target_status',v_target_status);
  else
    v_compatibility:=fitmatch_catalog.runtime_evaluate_comparison_profiles_v2(
      v_reference_family,v_reference_detail,v_reference_length,
      v_target_family,v_target_detail,v_target_length,p_allow_extended);
  end if;
  v_status:=case when coalesce((v_compatibility->>'allowed')::boolean,false)
    then 'pending' else 'blocked' end;
  insert into public.comparison_runs (
    user_id,reference_item_id,target_product_id,status,comparison_level,
    block_reason,comparison_policy_version,input_snapshot,completed_at
  ) values (
    v_user_id,p_reference_item_id,p_target_product_id,v_status,
    v_compatibility->>'level',v_compatibility->>'reason',
    v_compatibility->>'policy_version',jsonb_build_object('compatibility',v_compatibility),
    case when v_status='blocked' then now() else null end
  ) returning id into v_run_id;
  return jsonb_build_object('run_id',v_run_id,'status',v_status,'compatibility',v_compatibility);
end $$;

-- Correct four currently sold products whose category/detail and family axes
-- contradicted each other. Preserve the previous rows as immutable history.
do $$
declare r record; v_family text; v_length text;
begin
  for r in
    select p.id product_id,p.source,p.external_product_id,h.id history_id,
      h.category_code,h.detail_code,h.decision_version,h.evidence
    from fitmatch_catalog.products p
    join fitmatch_catalog.product_classification_history h on h.product_id=p.id and h.is_current
    where (p.source,p.external_product_id) in (
      ('uniqlo','E482204'),('uniqlo','E489180'),
      ('uniqlo','E488163'),('uniqlo','E488426')
    )
  loop
    v_family:=case when r.category_code='underwear' then 'underwear' else 'pants' end;
    v_length:=case when r.category_code='bottoms' then 'long_sleeve' else 'unknown' end;
    update fitmatch_catalog.product_classification_history
      set is_current=false,superseded_at=now() where id=r.history_id;
    insert into fitmatch_catalog.product_classification_history (
      product_id,input_fingerprint,category_code,detail_code,comparison_family_code,
      length_code,classification_status,classification_method,confidence,
      requires_user_confirmation,mapping_release_id,decision_version,evidence
    )
    select p.id,p.input_fingerprint,r.category_code,r.detail_code,v_family,v_length,
      'confirmed','manual_review',1,false,d.release_id,
      'db-runtime-2026-08-18-v1',r.evidence||jsonb_build_object(
        'correction','category_detail_family_consistency','previous_history_id',r.history_id)
    from fitmatch_catalog.products p
    join fitmatch_catalog.product_classification_decisions d
      on d.source=p.source and d.external_product_id=p.external_product_id
    where p.id=r.product_id;
    update fitmatch_catalog.product_classification_decisions
      set comparison_family=v_family,length_type=v_length,
        decision_version='db-runtime-2026-08-18-v1',
        evidence=evidence||jsonb_build_object('correction','category_detail_family_consistency'),
        updated_at=now()
      where source=r.source and external_product_id=r.external_product_id;
  end loop;
end $$;

revoke all on function fitmatch_catalog.runtime_measurement_kind(text,text)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_normalize_measurement_v2(text,text,text,text,numeric,text,text)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_evaluate_comparison_profiles_v2(text,text,text,text,text,text,boolean)
  from public,anon,authenticated;
grant execute on function fitmatch_catalog.runtime_measurement_kind(text,text) to service_role;
grant execute on function fitmatch_catalog.runtime_normalize_measurement_v2(text,text,text,text,numeric,text,text) to service_role;
grant execute on function fitmatch_catalog.runtime_evaluate_comparison_profiles_v2(text,text,text,text,text,text,boolean) to service_role;

do $$
begin
  if exists (
    select 1 from fitmatch_catalog.product_classification_history
    where is_current group by product_id having count(*)>1
  ) then raise exception 'multiple current classifications detected'; end if;
  if exists (
    select 1 from fitmatch_catalog.product_classification_history
    where is_current and classification_status='confirmed'
      and ((category_code='underwear' and comparison_family_code<>'underwear')
        or (category_code='bottoms' and comparison_family_code='tshirt'))
  ) then raise exception 'category-family contradiction remains'; end if;
end $$;

commit;
;
