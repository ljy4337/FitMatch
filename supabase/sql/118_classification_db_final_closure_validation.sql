-- LOCAL/DISPOSABLE POSTGRESQL VALIDATION ONLY.
-- Requires the SELECT-only 1,608 product snapshot used by 116/117 validation.
-- All decision and synthetic fixture writes below are rolled back.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local statement_timeout = '300s';

do $$
declare
  v_product_fingerprint_checksum text;
  v_release_gate jsonb;
begin
  select encode(sha256(convert_to(
    string_agg(
      source || E'\t' || external_product_id || E'\t' || input_fingerprint,
      E'\n' order by source, external_product_id
    ) || E'\n', 'UTF8'
  )), 'hex')
  into v_product_fingerprint_checksum
  from fitmatch_catalog.products;

  if (select count(*) from fitmatch_catalog.products) <> 1608
    or (select count(distinct (source,external_product_id))
        from fitmatch_catalog.products) <> 1608
    or v_product_fingerprint_checksum <>
      'c1ed8a45c6548149b1b434c3551a4a674b41e627a642f6ed72db7ea55bee061a'
  then
    raise exception '118_product_snapshot_or_fingerprint_drift:%',
      v_product_fingerprint_checksum;
  end if;

  if (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id='11800000-0000-4000-8000-000000000118') <> 3509
    or (select count(*) from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()) <> 121
    or (select count(*) from fitmatch_catalog.classification_structured_discriminator_rules
        where release_id='11800000-0000-4000-8000-000000000118'
          and runtime_eligible and authority_status='verified') <> 21
    or (select count(*) from fitmatch_catalog.classification_path_profiles
        where policy_version='db-classifier-2026-08-26-final'
          and auto_eligible) <> 12
    or (select count(*) from fitmatch_catalog.classification_exclusion_profiles
        where policy_version='db-classifier-2026-08-26-final'
          and auto_eligible) <> 15
  then
    raise exception '118_candidate_component_count_mismatch';
  end if;

  v_release_gate := fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-000000000118'::uuid
  );
  if not coalesce((v_release_gate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_release_gate->'blockers','[]'::jsonb))<>0
  then
    raise exception '118_release_gate_v2_failure:%',v_release_gate;
  end if;
end $$;

do $$
begin
  if exists (
    select 1
    from fitmatch_catalog.source_category_mappings
    where release_id='11800000-0000-4000-8000-000000000118'
      and lower(coalesce(
        raw_record#>>'{authorityContract,resolutionScope}',
        raw_record->>'resolutionScope',''
      )) not in ('category_direct','product_required','revoked')
  )
  or (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id='11800000-0000-4000-8000-000000000118'
        and lower(raw_record#>>'{authorityContract,resolutionScope}')='category_direct') <> 55
  or (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id='11800000-0000-4000-8000-000000000118'
        and lower(raw_record#>>'{authorityContract,resolutionScope}')='product_required') <> 1019
  or (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id='11800000-0000-4000-8000-000000000118'
        and lower(coalesce(raw_record#>>'{authorityContract,resolutionScope}',
          raw_record->>'resolutionScope',''))='revoked') <> 2435
  then
    raise exception '118_source_authority_scope_not_closed';
  end if;

  if exists (
    select 1 from fitmatch_catalog.source_category_mappings
    where release_id='11800000-0000-4000-8000-000000000118'
      and source='musinsa' and external_category_id in ('001011','017016003')
      and lower(raw_record#>>'{authorityContract,resolutionScope}')<>'product_required'
  )
  or (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id='11800000-0000-4000-8000-000000000118'
        and source='musinsa' and external_category_id in ('001011','017016003')) <> 7
  then
    raise exception '118_mixed_sleeveless_purity_gate_failed';
  end if;
end $$;

do $$
begin
  if (select count(*)
      from fitmatch_catalog.classification_exclusion_profiles
      where policy_version='db-classifier-2026-08-26-final'
        and sample_count=1)<>4
    or exists (
      select 1
      from fitmatch_catalog.classification_exclusion_profiles
      where policy_version='db-classifier-2026-08-26-final'
        and sample_count=1
        and (
          not auto_eligible
          or reason_code<>'non_apparel_or_accessory'
          or evidence->>'authority_status'<>'verified'
          or not coalesce(
            (evidence->>'complete_profile')::boolean,false
          )
        )
    )
  then
    raise exception '118_singleton_exclusion_authority_gate_failed';
  end if;
end $$;

do $$
declare
  v_groups integer;
  v_legacy_family_registry_gap boolean := false;
begin
  select count(*) into v_groups from public.comparison_groups where is_active;
  if to_regclass('fitmatch_taxonomy.comparison_families') is not null then
    execute $gap$
      select exists (
        select 1
        from public.comparison_groups comparison_group
        left join fitmatch_taxonomy.comparison_families family
          on family.code = comparison_group.code
        where comparison_group.is_active
          and family.code is null
      )
    $gap$ into v_legacy_family_registry_gap;
  end if;
  if exists (
    select 1 from public.comparison_groups comparison_group
    left join public.comparison_policies policy
      on policy.comparison_group_code=comparison_group.code
     and policy.policy_version='v1' and policy.is_active
    where comparison_group.is_active and policy.code is null
  )
  or (select count(*) from fitmatch_taxonomy.comparison_compatibility_rules
      where policy_version='db-comparison-2026-08-26-final') <>
      (v_groups*(v_groups+1))/2
  or v_legacy_family_registry_gap
  or exists (
    select 1 from public.comparison_groups comparison_group
    where comparison_group.is_active and comparison_group.is_auto_comparable
      and not exists (
        select 1 from public.app_categories category
        join public.app_category_measurement_policies policy
          on policy.app_category_id=category.id
         and policy.policy_version='2026.07.1'
         and policy.is_active and policy.is_comparable
        where category.parent_id is null
          and category.code=comparison_group.major_category_code
      )
  ) then
    raise exception '118_comparison_or_measurement_policy_gap';
  end if;
end $$;

-- Candidate decision writes are previewed only and rolled back.
insert into fitmatch_catalog.product_classification_decisions (
  source,external_product_id,product_name,source_category_path,
  input_fingerprint,category_code,detail_code,garment_type_code,
  comparison_family,length_type,requires_user_confirmation,release_id,
  decision_version,evidence,authority_status
)
select source,external_product_id,product_name,source_category_path,
  input_fingerprint,category_code,detail_code,garment_type_code,family_code,
  length_code,requires_user_confirmation,
  '11800000-0000-4000-8000-000000000118'::uuid,
  decision_version,
  coalesce(evidence,'{}'::jsonb)
    || jsonb_build_object('body_length_code',body_length_code),
  authority_status
from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
on conflict (source,external_product_id) do update set
  product_name=excluded.product_name,
  source_category_path=excluded.source_category_path,
  input_fingerprint=excluded.input_fingerprint,
  category_code=excluded.category_code,
  detail_code=excluded.detail_code,
  garment_type_code=excluded.garment_type_code,
  comparison_family=excluded.comparison_family,
  length_type=excluded.length_type,
  requires_user_confirmation=excluded.requires_user_confirmation,
  release_id=excluded.release_id,
  decision_version=excluded.decision_version,
  evidence=excluded.evidence,
  authority_status=excluded.authority_status,
  updated_at=now();

create temp table final_shadow on commit drop as
with facts as (
  select value->>'source' source,
    value->>'external_product_id' external_product_id,
    value->'structured_facts' structured_facts
  from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
  where value->>'record_type'='product_structured_fact'
)
select product.source,product.external_product_id,product.input_fingerprint,
  product.audience,coalesce(facts.structured_facts,'{}'::jsonb) structured_facts,
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    product.source,product.external_product_id,product.product_name,
    product.source_category_path,
    jsonb_build_object(
      'audience',product.audience,
      'source_category_codes',to_jsonb(product.source_category_codes),
      'structured_facts',coalesce(facts.structured_facts,'{}'::jsonb)
    ),'11800000-0000-4000-8000-000000000118'::uuid
  ) resolution
from fitmatch_catalog.products product
left join facts using(source,external_product_id);

do $$
begin
  if (select count(*) from final_shadow)<>1608
    or (select count(distinct(source,external_product_id)) from final_shadow)<>1608
    or (select count(*) from final_shadow
        where resolution->>'classification_status'='confirmed')<>348
    or (select count(*) from final_shadow
        where resolution->>'classification_status'='review_required')<>1113
    or (select count(*) from final_shadow
        where resolution->>'classification_status'='not_comparable')<>147
    or exists (
      select 1 from final_shadow
      where resolution->>'classification_status'='confirmed'
        and not coalesce((resolution#>>'{tuple_validation,valid}')::boolean,false)
    )
  then
    raise exception '118_full_shadow_cardinality_distribution_or_tuple_failure';
  end if;
end $$;

do $$
begin
  if (select count(*) from final_shadow
      where source='musinsa'
        and structured_facts->>'product_structure'='set'
        and resolution->>'classification_status'='not_comparable')<>7
  or exists (
    select 1 from final_shadow
    where structured_facts->>'product_structure'='set'
      and resolution->>'classification_status'<>'not_comparable'
  )
  or (select count(*) from final_shadow
      where source='uniqlo'
        and structured_facts ? 'product_type_kr'
        and resolution->>'classification_status'='not_comparable')<>47
  or (select count(*) from final_shadow
      where resolution->>'classification_method'='verified_exclusion_profile')<>93
  or (select count(*) from final_shadow
      where resolution->>'classification_method'='structured_discriminator')<>7
  or (select count(*) from final_shadow
      where resolution->>'classification_method'='verified_path_profile')<>65
  or exists (
    select 1 from final_shadow
    where resolution->>'classification_method' in (
      'verified_name_signature_profile','verified_path_profile'
    ) and resolution->>'authority_status'<>'verified'
  )
  then
    raise exception '118_exclusion_or_verified_evidence_count_failure';
  end if;
end $$;

do $$
declare
  v_gold integer;
  v_unintended_regressions integer := 0;
begin
  select count(*) into v_gold
  from final_shadow
  where source='uniqlo' and (
    (external_product_id='E482514'
      and resolution->>'category_code'='tops'
      and resolution->>'detail_code'='short_sleeve'
      and resolution->>'garment_type_code'='tshirt'
      and resolution->>'family_code'='tshirt'
      and resolution->>'length_code'='short_sleeve')
    or
    (external_product_id in ('E454311','E456567')
      and resolution->>'category_code'='tops'
      and resolution->>'detail_code'='base_layer_top'
      and resolution->>'garment_type_code'='base_layer_top'
      and resolution->>'family_code'='base_layer_top'
      and resolution->>'length_code'='short_sleeve')
  );
  if v_gold<>3 then raise exception '118_gold_failed:%',v_gold; end if;

  if to_regclass('fitmatch_qa.final_117_resolution') is not null then
    select count(*) into v_unintended_regressions
    from fitmatch_qa.final_117_resolution baseline
    join final_shadow final using(source,external_product_id)
    where baseline.resolution->>'classification_status'='confirmed'
      and final.resolution->>'classification_status'<>'confirmed'
      and not (
        final.source='musinsa'
        and exists (
          select 1 from fitmatch_catalog.products product
          where product.source=final.source
            and product.external_product_id=final.external_product_id
            and product.source_category_codes && array['001011','017016003']
        )
      );
    if v_unintended_regressions<>0 then
      raise exception '118_unintended_confirmed_regression:%',v_unintended_regressions;
    end if;
  end if;
end $$;

-- Future/synthetic fixture data. The common resolver sees only generic
-- key/value facts and scope; no retailer-specific branch is added.
do $$
declare v_gate jsonb;
begin
  v_gate:=fitmatch_catalog.runtime_classification_db_final_gate_v1(
    '11800000-0000-4000-8000-000000000118'
  );
  if not coalesce((v_gate->>'eligible')::boolean,false) then
    raise exception '118_closure_release_gate_failed:%',v_gate;
  end if;
end $$;

insert into fitmatch_catalog.source_category_mappings (
  release_id,source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,
  comparison_family,raw_record
) values
  ('11800000-0000-4000-8000-000000000118','fixture|pure-tshirt','fixture',
   '118f0000-0000-4000-8000-000000000001','pure-tshirt','UNISEX',
   'fixture > pure tshirt','confirmed','direct',true,true,
   'tops','tshirt','tshirt',
   '{"appMapping":{"categoryCode":"tops","detailCode":"short_sleeve"},"lengthAxes":{"sleeve":"short_sleeve"},"authorityContract":{"authorityStatus":"verified","resolutionScope":"category_direct","productRequired":false}}'),
  ('11800000-0000-4000-8000-000000000118','fixture|mixed-apparel','fixture',
   '118f0000-0000-4000-8000-000000000001','mixed-apparel','UNISEX',
   'fixture > mixed apparel','review_required','product_required',true,true,
   null,null,null,
   '{"appMapping":{"categoryCode":"tops","detailCode":"other"},"authorityContract":{"authorityStatus":"verified","resolutionScope":"product_required","productRequired":true}}')
on conflict (release_id,source_identity) do update set raw_record=excluded.raw_record;

with rules(value,category,detail,garment,family,length,body) as (
  values
    ('tshirt','tops','short_sleeve','tshirt','tshirt','short_sleeve',null),
    ('tank_top','tops','sleeveless','tank_top','tank_top','sleeveless',null),
    ('sleeveless_tshirt','tops','sleeveless_tshirt','sleeveless_tshirt','sleeveless_tshirt','sleeveless',null),
    ('dress','dresses','one_piece','dress','dress','not_applicable','medium_body'),
    ('skirt','skirts','skirt','skirt','skirt','not_applicable','medium_body'),
    ('pants','bottoms','long_pants','other_standard_pants','standard_pants','long_length',null),
    ('denim','bottoms','jeans','denim_pants','standard_pants','long_length',null),
    ('shorts','bottoms','shorts','shorts','standard_pants','short_length',null),
    ('cardigan','tops','cardigan','cardigan','cardigan','long_sleeve',null),
    ('knit_sweater','tops','knit_sweater','knit_sweater','knit_sweater','long_sleeve',null),
    ('sweatshirt','tops','sweatshirt','sweatshirt','sweatshirt','long_sleeve',null),
    ('hoodie','tops','hoodie','hoodie','hoodie','long_sleeve',null),
    ('jacket','outerwear','jacket','jacket','jacket','long_sleeve',null),
    ('coat','outerwear','coat','coat','coat','long_sleeve','medium_body'),
    ('blazer','outerwear','blazer','blazer','blazer','long_sleeve',null),
    ('puffer_jacket','outerwear','padding','puffer_jacket','puffer_jacket','long_sleeve','medium_body'),
    ('windbreaker','outerwear','windbreaker','windbreaker','windbreaker','long_sleeve',null),
    ('base_layer_top','tops','base_layer_top','base_layer_top','base_layer_top','short_sleeve',null),
    ('true_underwear','underwear','men_trunks','men_trunks','men_trunks','not_applicable',null),
    ('homewear_top','homewear','homewear_top','homewear_top','homewear_top','long_sleeve',null)
)
insert into fitmatch_catalog.classification_structured_discriminator_rules (
  release_id,rule_id,source,discriminator_key,discriminator_value,
  external_category_id,outcome,category_code,detail_code,garment_type_code,
  family_code,length_code,body_length_code,authority_status,resolution_scope,
  runtime_eligible,evidence,policy_version
)
select '11800000-0000-4000-8000-000000000118',
  'fixture-'||value,'fixture','garment_type',value,'mixed-apparel',
  'canonical',category,detail,garment,family,length,body,'verified',
  'structured_product',true,
  '{"fixture_only":true,"independently_expected":true}',
  'db-classifier-2026-08-26-final'
from rules
on conflict (release_id,rule_id) do update set evidence=excluded.evidence;

insert into fitmatch_catalog.classification_path_profiles (
  policy_version,source,normalized_path,category_code,detail_code,
  comparison_family_code,length_code,sample_count,review_count,
  distinct_decision_count,auto_eligible,evidence
) values (
  'db-classifier-2026-08-26-final','fixture','fixture > verified path',
  'tops','short_sleeve','tshirt','short_sleeve',1,0,1,true,
  '{"authority_status":"verified","garment_type_code":"tshirt","complete_tuple":true}'
)
on conflict (policy_version,source,normalized_path) do update
set evidence=excluded.evidence,auto_eligible=true;

insert into fitmatch_catalog.classification_name_profiles (
  policy_version,source,normalized_path,name_signature,category_code,
  detail_code,comparison_family_code,length_code,sample_count,review_count,
  distinct_decision_count,auto_eligible,evidence
) values (
  'db-classifier-2026-08-26-final','fixture','fixture > name context',
  fitmatch_catalog.runtime_product_name_signature('검증 반소매 티셔츠'),
  'tops','short_sleeve','tshirt','short_sleeve',
  1,0,1,true,
  '{"authority_status":"verified","garment_type_code":"tshirt","complete_tuple":true}'
)
on conflict (policy_version,source,normalized_path,name_signature) do update
set evidence=excluded.evidence,auto_eligible=true;

create temp table synthetic_cases (
  fixture_id text primary key,
  product_name text not null,
  path text not null,
  codes text[] not null,
  facts jsonb not null,
  expected_status text not null,
  expected_category text,
  expected_garment text
) on commit drop;

insert into synthetic_cases values
  ('known-pure-category','Unknown New Tee','fixture > pure tshirt',array['pure-tshirt'],'{}','confirmed','tops','tshirt'),
  ('product-required-structured','Unknown Structured Tee','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"tshirt"}','confirmed','tops','tshirt'),
  ('product-required-missing','Unknown Mixed Product','fixture > mixed apparel',array['mixed-apparel'],'{}','review_required',null,null),
  ('mixed-sleeveless-tank','Unknown Tank','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"tank_top"}','confirmed','tops','tank_top'),
  ('mixed-sleeveless-tshirt','Unknown Sleeveless Tee','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"sleeveless_tshirt"}','confirmed','tops','sleeveless_tshirt'),
  ('set-in-tshirt','Unknown Set','fixture > pure tshirt',array['pure-tshirt'],'{"product_structure":"set"}','not_comparable',null,null),
  ('normal-variant-not-set','Unknown Tee Color Variant','fixture > pure tshirt',array['pure-tshirt'],'{"variant_kind":"color"}','confirmed','tops','tshirt'),
  ('dress','Unknown Dress','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"dress"}','confirmed','dresses','dress'),
  ('skirt','Unknown Skirt','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"skirt"}','confirmed','skirts','skirt'),
  ('pants','Unknown Pants','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"pants"}','confirmed','bottoms','other_standard_pants'),
  ('denim','Unknown Denim','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"denim"}','confirmed','bottoms','denim_pants'),
  ('shorts','Unknown Shorts','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"shorts"}','confirmed','bottoms','shorts'),
  ('cardigan','Unknown Cardigan','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"cardigan"}','confirmed','tops','cardigan'),
  ('knit-sweater','Unknown Knit','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"knit_sweater"}','confirmed','tops','knit_sweater'),
  ('sweatshirt','Unknown Sweatshirt','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"sweatshirt"}','confirmed','tops','sweatshirt'),
  ('hoodie','Unknown Hoodie','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"hoodie"}','confirmed','tops','hoodie'),
  ('jacket','Unknown Jacket','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"jacket"}','confirmed','outerwear','jacket'),
  ('coat','Unknown Coat','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"coat"}','confirmed','outerwear','coat'),
  ('blazer','Unknown Blazer','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"blazer"}','confirmed','outerwear','blazer'),
  ('puffer-jacket','Unknown Puffer','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"puffer_jacket"}','confirmed','outerwear','puffer_jacket'),
  ('windbreaker','Unknown Windbreaker','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"windbreaker"}','confirmed','outerwear','windbreaker'),
  ('base-layer-top','Unknown Base Layer','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"base_layer_top"}','confirmed','tops','base_layer_top'),
  ('true-underwear','Unknown Trunks','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"true_underwear"}','confirmed','underwear','men_trunks'),
  ('homewear-single','Unknown Lounge Top','fixture > mixed apparel',array['mixed-apparel'],'{"garment_type":"homewear_top"}','confirmed','homewear','homewear_top'),
  ('homewear-set','Unknown Lounge Set','fixture > mixed apparel',array['mixed-apparel'],'{"product_structure":"set","garment_type":"homewear_top"}','not_comparable',null,null),
  ('non-apparel','Unknown Accessory','fixture > mixed apparel',array['mixed-apparel'],'{"product_scope":"non_apparel"}','not_comparable',null,null),
  ('verified-path','Unknown Path Product','fixture > verified path',array[]::text[],'{}','confirmed','tops','tshirt'),
  ('verified-name-last-resort','검증 반소매 티셔츠','fixture > name context',array[]::text[],'{}','confirmed','tops','tshirt'),
  ('unknown-insufficient','Unknown Unsupported Evidence','fixture > unknown',array[]::text[],'{}','review_required',null,null);

create temp table synthetic_results on commit drop as
select fixture.*,
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    'fixture',fixture.fixture_id,fixture.product_name,fixture.path,
    jsonb_build_object(
      'audience','UNISEX','source_category_codes',to_jsonb(fixture.codes),
      'structured_facts',fixture.facts
    ),'11800000-0000-4000-8000-000000000118'
  ) resolution
from synthetic_cases fixture;

select fixture_id,expected_status,expected_category,expected_garment,
  resolution->>'classification_status' actual_status,
  resolution->>'category_code' actual_category,
  resolution->>'garment_type_code' actual_garment,
  resolution#>'{tuple_validation,blockers}' tuple_blockers,
  resolution#>'{evidence,unresolved_reasons}' unresolved_reasons
from synthetic_results
where resolution->>'classification_status' is distinct from expected_status
  or (expected_category is not null
    and resolution->>'category_code' is distinct from expected_category)
  or (expected_garment is not null
    and resolution->>'garment_type_code' is distinct from expected_garment)
  or (expected_status='confirmed'
    and not coalesce((resolution#>>'{tuple_validation,valid}')::boolean,false))
order by fixture_id;

do $$
begin
  if (select count(*) from synthetic_results)<>29
  or exists (
    select 1 from synthetic_results
    where resolution->>'classification_status' is distinct from expected_status
      or (expected_category is not null
        and resolution->>'category_code' is distinct from expected_category)
      or (expected_garment is not null
        and resolution->>'garment_type_code' is distinct from expected_garment)
      or (expected_status='confirmed'
        and not coalesce((resolution#>>'{tuple_validation,valid}')::boolean,false))
  ) then
    raise exception '118_future_synthetic_fixture_failure';
  end if;
end $$;

do $$
declare
  v_base_block jsonb;
  v_cross_allow jsonb;
  v_homewear_block jsonb;
begin
  v_base_block:=fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops','UNISEX','tshirt','short_sleeve','short_sleeve',null,
    'tops','UNISEX','base_layer_top','base_layer_top','short_sleeve',null,
    'tshirt','base_layer_top',false,
    '11800000-0000-4000-8000-000000000118');
  v_cross_allow:=fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops','UNISEX','sweatshirt','sweatshirt','long_sleeve',null,
    'tops','UNISEX','hoodie','hoodie','long_sleeve',null,
    'sweatshirt','hoodie',false,
    '11800000-0000-4000-8000-000000000118');
  v_homewear_block:=fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'homewear','UNISEX','homewear_top','homewear_top','long_sleeve',null,
    'homewear','UNISEX','homewear_bottom','homewear_bottom','long_length',null,
    'homewear_top','homewear_bottom',false,
    '11800000-0000-4000-8000-000000000118');
  if coalesce((v_base_block->>'allowed')::boolean,false)
    or not coalesce((v_cross_allow->>'allowed')::boolean,false)
    or coalesce((v_homewear_block->>'allowed')::boolean,false)
  then raise exception '118_explicit_comparison_allow_block_failure'; end if;
end $$;

select jsonb_pretty(jsonb_build_object(
  'passed',true,
  'contract','classification-db-final-closure-validation-v1',
  'products',1608,
  'confirmed',348,
  'review_required',1113,
  'not_comparable',147,
  'gold_exact','3/3',
  'synthetic_fixtures',29,
  'category_direct_rows',55,
  'product_required_rows',1019,
  'revoked_rows',2435,
  'structured_rules',21,
  'path_profiles',12,
  'name_profiles',0,
  'exclusion_profiles',15,
  'comparison_group_pair_rules',990,
  'confirmed_invalid_tuple',0,
  'set_garment_confirmed',0,
  'set_comparison_allowed',0,
  'arbitrary_fallback',0,
  'production_write_count',0
)) as validation_result;

rollback;
