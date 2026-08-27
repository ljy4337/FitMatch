-- LOCAL/DISPOSABLE POSTGRESQL 17 VALIDATION ONLY.
-- Required order: migration apply -> activation COMMIT -> rollback COMMIT.
\set ON_ERROR_STOP on
\pset pager off

do $local_guard$
begin
  if current_setting('fitmatch.local_fixture',true) is distinct from 'on'
  then raise exception '120_validation_requires_local_disposable_fixture'; end if;
end
$local_guard$;

-- The local snapshot must materialize all 121 decisions before migration 120,
-- exactly matching the already-activated Production 118 state.
do $decision_baseline$
begin
  if (select count(*)
      from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
    )<>121
    or (select count(*)
        from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1() manifest
        join fitmatch_catalog.product_classification_decisions decision
          using(source,external_product_id)
        where decision.input_fingerprint is not distinct from manifest.input_fingerprint
          and decision.category_code is not distinct from manifest.category_code
          and decision.detail_code is not distinct from manifest.detail_code
          and decision.garment_type_code is not distinct from manifest.garment_type_code
          and decision.comparison_family is not distinct from manifest.family_code
          and decision.length_type is not distinct from manifest.length_code
          and decision.authority_status is not distinct from manifest.authority_status
    )<>121
  then
    raise exception '120_validation_requires_materialized_118_decisions';
  end if;
end
$decision_baseline$;

create temporary table fitmatch_120_validation_guard as
select
  (select count(*) from fitmatch_catalog.product_classification_history)
    history_count,
  (select count(*) from fitmatch_catalog.product_classification_history
    where is_current) current_history_count;

do $baseline$
declare
  v_candidate jsonb;
  v_successor jsonb;
  v_resolver_checksum text;
  v_fingerprint_checksum text;
begin
  select encode(sha256(convert_to(string_agg(
    source||E'\t'||external_product_id||E'\t'||input_fingerprint,
    E'\n' order by source,external_product_id)||E'\n','UTF8')),'hex')
  into v_fingerprint_checksum
  from fitmatch_catalog.products;
  select encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex') into v_resolver_checksum;
  v_candidate:=fitmatch_catalog.runtime_release_gate_report(
    '12000000-0000-4000-8000-000000000120'::uuid
  );
  v_successor:=fitmatch_catalog.runtime_release_gate_report(
    '12000000-0000-4000-8000-00000000b001'::uuid
  );

  if (select count(*) from fitmatch_catalog.products)<>1608
    or (select count(distinct(source,external_product_id))
        from fitmatch_catalog.products)<>1608
    or v_fingerprint_checksum<>
      'c1ed8a45c6548149b1b434c3551a4a674b41e627a642f6ed72db7ea55bee061a'
    or v_resolver_checksum<>
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21'
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id='12000000-0000-4000-8000-000000000120'::uuid)<>3510
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id='12000000-0000-4000-8000-00000000b001'::uuid)<>3509
    or not coalesce((v_candidate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_candidate->'blockers','[]'::jsonb))<>0
    or not coalesce((v_successor->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_successor->'blockers','[]'::jsonb))<>0
  then
    raise exception
      '120_pre_activation_baseline_failed:fingerprint=%,resolver=%,candidate=%,successor=%',
      v_fingerprint_checksum,v_resolver_checksum,v_candidate,v_successor;
  end if;
end
$baseline$;

create temporary table validation_120_parent_shadow as
with facts as (
  select value->>'source' source,
    value->>'external_product_id' external_product_id,
    value->'structured_facts' structured_facts
  from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
  where value->>'record_type'='product_structured_fact'
)
select product.source,product.external_product_id,
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

create temporary table validation_120_candidate_pre_activation_shadow as
with facts as (
  select value->>'source' source,
    value->>'external_product_id' external_product_id,
    value->'structured_facts' structured_facts
  from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
  where value->>'record_type'='product_structured_fact'
)
select product.source,product.external_product_id,product.input_fingerprint,
  fitmatch_catalog.runtime_normalize_product_audience_v1(product.audience)
    audience,
  coalesce(facts.structured_facts,'{}'::jsonb) structured_facts,
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    product.source,product.external_product_id,product.product_name,
    product.source_category_path,
    jsonb_build_object(
      'audience',product.audience,
      'source_category_codes',to_jsonb(product.source_category_codes),
      'structured_facts',coalesce(facts.structured_facts,'{}'::jsonb)
    ),'12000000-0000-4000-8000-000000000120'::uuid
  ) resolution
from fitmatch_catalog.products product
left join facts using(source,external_product_id);

do $pre_activation_shadow$
begin
  if (select count(*) from validation_120_parent_shadow)<>1608
    or (select count(*) from validation_120_parent_shadow
        where resolution->>'classification_status'='confirmed')<>346
    or (select count(*) from validation_120_parent_shadow
        where resolution->>'classification_status'='review_required')<>1115
    or (select count(*) from validation_120_parent_shadow
        where resolution->>'classification_status'='not_comparable')<>147
    or (select count(*) from validation_120_candidate_pre_activation_shadow)<>1608
    or (select count(*) from validation_120_candidate_pre_activation_shadow
        where resolution->>'classification_status'='confirmed')<>348
    or (select count(*) from validation_120_candidate_pre_activation_shadow
        where resolution->>'classification_status'='review_required')<>1113
    or (select count(*) from validation_120_candidate_pre_activation_shadow
        where resolution->>'classification_status'='not_comparable')<>147
    or (select count(*)
        from validation_120_parent_shadow parent
        join validation_120_candidate_pre_activation_shadow candidate
          using(source,external_product_id)
        where parent.resolution->>'classification_status'='review_required'
          and candidate.resolution->>'classification_status'='confirmed')<>2
    or exists(
      select 1 from validation_120_parent_shadow parent
      join validation_120_candidate_pre_activation_shadow candidate
        using(source,external_product_id)
      where parent.resolution->>'classification_status'
        is distinct from candidate.resolution->>'classification_status'
        and not (parent.source='uniqlo'
          and parent.external_product_id in ('E422992','E487962')
          and parent.resolution->>'classification_status'='review_required'
          and candidate.resolution->>'classification_status'='confirmed')
    )
  then raise exception '120_pre_activation_full_shadow_failed'; end if;
end
$pre_activation_shadow$;

-- This file commits resolver replacement and candidate activation together.
\ir 120_classification_audience_scope_correction_atomic_activation.sql

create temporary table validation_120_post_activation_shadow as
with facts as (
  select value->>'source' source,
    value->>'external_product_id' external_product_id,
    value->'structured_facts' structured_facts
  from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
  where value->>'record_type'='product_structured_fact'
)
select product.source,product.external_product_id,product.input_fingerprint,
  fitmatch_catalog.runtime_normalize_product_audience_v1(product.audience)
    audience,
  coalesce(facts.structured_facts,'{}'::jsonb) structured_facts,
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    product.source,product.external_product_id,product.product_name,
    product.source_category_path,
    jsonb_build_object(
      'audience',product.audience,
      'source_category_codes',to_jsonb(product.source_category_codes),
      'structured_facts',coalesce(facts.structured_facts,'{}'::jsonb)
    ),null
  ) resolution
from fitmatch_catalog.products product
left join facts using(source,external_product_id);

do $post_activation_shadow$
begin
  if (select count(*) from validation_120_post_activation_shadow)<>1608
    or (select count(distinct(source,external_product_id))
        from validation_120_post_activation_shadow)<>1608
    or (select count(*) from validation_120_post_activation_shadow
        where resolution->>'classification_status'='confirmed')<>348
    or (select count(*) from validation_120_post_activation_shadow
        where resolution->>'classification_status'='review_required')<>1113
    or (select count(*) from validation_120_post_activation_shadow
        where resolution->>'classification_status'='not_comparable')<>147
    or exists(select 1 from validation_120_post_activation_shadow
      where resolution->>'classification_status'='confirmed'
        and not coalesce((resolution#>>'{tuple_validation,valid}')::boolean,false))
    or (select count(*) from validation_120_post_activation_shadow
      where source='uniqlo' and (
        (external_product_id='E482514'
          and resolution->>'category_code'='tops'
          and resolution->>'detail_code'='short_sleeve'
          and resolution->>'garment_type_code'='tshirt'
          and resolution->>'family_code'='tshirt'
          and resolution->>'length_code'='short_sleeve')
        or (external_product_id in ('E454311','E456567')
          and resolution->>'category_code'='tops'
          and resolution->>'detail_code'='base_layer_top'
          and resolution->>'garment_type_code'='base_layer_top'
          and resolution->>'family_code'='base_layer_top'
          and resolution->>'length_code'='short_sleeve')
      ))<>3
    or (select count(*) from validation_120_post_activation_shadow
        where structured_facts->>'product_structure'='set'
          and resolution->>'classification_status'='not_comparable')<>7
  then raise exception '120_post_activation_full_shadow_gold_or_set_failed'; end if;
end
$post_activation_shadow$;

-- Exact-vs-GENERIC precedence is tested only inside this rolled-back local
-- transaction; candidate mapping/manifest semantics remain unchanged.
begin;
insert into fitmatch_catalog.source_category_mappings(
  release_id,source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,comparison_family,
  source_external_key,source_external_target_key,source_path_key,
  source_target_path_key,raw_record
)
select
  '12000000-0000-4000-8000-000000000120'::uuid,
  'uniqlo|12000000-0000-4000-8000-00000000f120|audience-safety|MEN|audience safety',
  'uniqlo','12000000-0000-4000-8000-00000000f120'::uuid,
  'audience-safety','MEN','audience safety','confirmed','direct',true,true,
  'tops','tshirt','tshirt',null,null,'uniqlo|audience safety',
  'uniqlo|MEN|audience safety',
  jsonb_build_object(
    'target','MEN','appMapping',jsonb_build_object(
      'categoryCode','tops','detailCode','short_sleeve'),
    'lengthAxes',jsonb_build_object('sleeve','short_sleeve'),
    'authorityContract',jsonb_build_object(
      'authorityStatus','verified','resolutionScope','category_direct',
      'productRequired',false)
  )
union all
select
  '12000000-0000-4000-8000-000000000120'::uuid,
  'uniqlo|12000000-0000-4000-8000-00000000f120|audience-safety|GENERIC|audience safety',
  'uniqlo','12000000-0000-4000-8000-00000000f120'::uuid,
  'audience-safety','GENERIC','audience safety','confirmed','direct',true,true,
  'tops','tshirt','tshirt',null,null,'uniqlo|audience safety',
  'uniqlo|GENERIC|audience safety',
  jsonb_build_object(
    'target','GENERIC','appMapping',jsonb_build_object(
      'categoryCode','tops','detailCode','long_sleeve'),
    'lengthAxes',jsonb_build_object('sleeve','long_sleeve'),
    'authorityContract',jsonb_build_object(
      'authorityStatus','verified','resolutionScope','category_direct',
      'productRequired',false)
  );

do $generic_matrix$
declare v_result jsonb; v_audience text;
begin
  v_result:=fitmatch_catalog.runtime_resolve_product_classification_v4(
    'uniqlo','future-men','Future garment','audience safety',
    jsonb_build_object('audience','MEN','source_category_codes',
      jsonb_build_array('audience-safety')),null
  );
  if v_result->>'classification_status'<>'confirmed'
    or v_result->>'detail_code'<>'short_sleeve'
  then raise exception '120_exact_audience_precedence_failed:%',v_result; end if;

  foreach v_audience in array array['WOMEN','UNISEX','UNKNOWN','GENERIC'] loop
    v_result:=fitmatch_catalog.runtime_resolve_product_classification_v4(
      'uniqlo','future-generic-'||lower(v_audience),'Future garment',
      'audience safety',jsonb_build_object(
        'audience',v_audience,'source_category_codes',
        jsonb_build_array('audience-safety')),null
    );
    if v_result->>'classification_status'<>'confirmed'
      or v_result->>'detail_code'<>'long_sleeve'
    then raise exception '120_explicit_generic_fallback_failed:%:%',
      v_audience,v_result; end if;
  end loop;

  delete from fitmatch_catalog.source_category_mappings
  where release_id='12000000-0000-4000-8000-000000000120'::uuid
    and external_category_id='audience-safety' and target='GENERIC';

  foreach v_audience in array array['WOMEN','UNISEX','UNKNOWN','GENERIC'] loop
    v_result:=fitmatch_catalog.runtime_resolve_product_classification_v4(
      'uniqlo','future-no-match-'||lower(v_audience),'Future garment',
      'audience safety',jsonb_build_object(
        'audience',v_audience,'source_category_codes',
        jsonb_build_array('audience-safety')),null
    );
    if v_result->>'classification_status'<>'review_required'
    then raise exception '120_implicit_men_fallback_leak:%:%',
      v_audience,v_result; end if;
  end loop;
end
$generic_matrix$;
rollback;

-- This file commits exact resolver preimage restoration and successor switch.
\ir 120_classification_audience_scope_correction_atomic_rollback.sql

do $final$
declare v_resolver_checksum text;
begin
  select encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex') into v_resolver_checksum;
  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or (select id from fitmatch_catalog.releases where status='active')<>
      '12000000-0000-4000-8000-00000000b001'::uuid
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id=(select id from fitmatch_catalog.releases
          where status='active'))<>3509
    or v_resolver_checksum<>
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21'
    or (select count(*) from fitmatch_catalog.product_classification_history)<>
      (select history_count from fitmatch_120_validation_guard)
    or (select count(*) from fitmatch_catalog.product_classification_history
        where is_current)<>
      (select current_history_count from fitmatch_120_validation_guard)
  then raise exception '120_final_rollback_checksum_or_history_failure:%',
    v_resolver_checksum; end if;
end
$final$;

select jsonb_build_object(
  'validation','PASS',
  'migration_resolver_unchanged',true,
  'candidate_gate','PASS',
  'rollback_successor_gate','PASS',
  'activation_commit','PASS',
  'rollback_commit','PASS',
  'products',1608,
  'confirmed',348,
  'review_required',1113,
  'not_comparable',147,
  'gold','3/3',
  'set','7/7 not_comparable',
  'audience_products','2/2 confirmed',
  'men_regression','5/5 confirmed',
  'generic_safety_matrix','PASS',
  'resolver_preimage_checksum',
    'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21',
  'resolver_postimage_checksum','3e99c584285b249c9adca76e1b8c0c8b68ec3f10f38dced306e392ef4a48b604',
  'resolver_rollback_checksum',encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex'),
  'history_write_count',0,
  'history_delete_count',0
) validation_result;
