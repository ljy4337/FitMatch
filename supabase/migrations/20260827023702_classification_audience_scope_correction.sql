begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';
select pg_advisory_xact_lock(
  hashtext('fitmatch:classification-audience-scope-2026-08-27-v1')
);

-- 118/119 are immutable Production history. This migration creates one
-- inactive successor and one inactive rollback successor. It never changes
-- the active pointer, product decisions, classification history, or products.
do $preimage$
declare
  v_parent fitmatch_catalog.releases%rowtype;
  v_resolver_checksum text;
begin
  select * into v_parent
  from fitmatch_catalog.releases
  where id='11800000-0000-4000-8000-000000000118'::uuid
  for update;

  select encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex')
  into v_resolver_checksum;

  if v_parent.id is null
    or v_parent.status not in ('validated','active')
    or v_parent.expected_mapping_count<>3509
    or v_parent.expected_qa_count<>1608
    or v_parent.bundle_checksum<>
      'f21e61545f194347aec02f620daefc9ea5dd56645fd1b9a77b0bc56f897163be'
    or v_parent.validation_report->>'measurement_policy_checksum'<>
      '42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0'
    or v_resolver_checksum<>
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21'
  then
    raise exception
      '120_parent_or_resolver_preimage_mismatch:status=%,mappings=%,resolver=%',
      v_parent.status,v_parent.expected_mapping_count,v_resolver_checksum;
  end if;
end
$preimage$;

create or replace function
fitmatch_catalog.runtime_normalize_product_audience_v1(
  p_audience text
) returns text
language sql
immutable
parallel safe
security invoker
set search_path=''
as $function$
  select case upper(regexp_replace(
    btrim(coalesce(p_audience,'')),E'\\s+','','g'
  ))
    when 'M' then 'MEN'
    when 'MEN' then 'MEN'
    when 'MAN' then 'MEN'
    when 'MALE' then 'MEN'
    when '남성' then 'MEN'
    when 'W' then 'WOMEN'
    when 'WOMEN' then 'WOMEN'
    when 'WOMAN' then 'WOMEN'
    when 'FEMALE' then 'WOMEN'
    when '여성' then 'WOMEN'
    when 'M,W' then 'UNISEX'
    when 'UNISEX' then 'UNISEX'
    when 'COMMON' then 'UNISEX'
    when 'U' then 'UNISEX'
    when '공용' then 'UNISEX'
    when '젠더리스' then 'UNISEX'
    when 'KID' then 'KIDS'
    when 'KIDS' then 'KIDS'
    when 'BABY' then 'BABY'
    else 'UNKNOWN'
  end
$function$;

create or replace function
fitmatch_catalog.runtime_normalize_mapping_target_v1(
  p_target text
) returns text
language sql
immutable
parallel safe
security invoker
set search_path=''
as $function$
  select case
    when upper(btrim(coalesce(p_target,'')))='GENERIC' then 'GENERIC'
    else fitmatch_catalog.runtime_normalize_product_audience_v1(p_target)
  end
$function$;

comment on function
  fitmatch_catalog.runtime_normalize_product_audience_v1(text)
is 'Canonical product audience. Missing or unrecognized evidence is exact UNKNOWN; GENERIC is never accepted as a product audience.';
comment on function
  fitmatch_catalog.runtime_normalize_mapping_target_v1(text)
is 'Canonical source mapping target. GENERIC is an explicit verified mapping scope only.';

insert into fitmatch_catalog.releases(
  id,release_key,taxonomy_version,policy_version,status,bundle_checksum,
  app_taxonomy_checksum,expected_mapping_count,expected_qa_count,metadata,
  validated_at,validation_contract_version,validation_report
)
select
  '12000000-0000-4000-8000-000000000120'::uuid,
  'fitmatch-classification-audience-scope-correction-2026-08-27-v1',
  parent.taxonomy_version,parent.policy_version,'validated',
  'a0187a78ccf8465ecbf755e9f18955799fb7ae6bf1e6ed2b1578784fdf7625c5',
  parent.app_taxonomy_checksum,3510,1608,
  jsonb_build_object(
    'phase','P0 Audience Mapping Regression Fix',
    'candidate_only',true,
    'parent_release_id',parent.id,
    'approved_production_apply',false,
    'production_activation_performed',false,
    'history_backfill_performed',false,
    'lookup_contract','classification-audience-scope-v1'
  ),now(),'fitmatch-release-gate-v2',
  parent.validation_report||jsonb_build_object(
    'manifest_checksum',
      'a0187a78ccf8465ecbf755e9f18955799fb7ae6bf1e6ed2b1578784fdf7625c5',
    'parent_release_id',parent.id,
    'source_mapping_count',3510,
    'category_direct_count',56,
    'product_required_count',1019,
    'revoked_count',2435,
    'audience_scope_correction_count',1,
    'audience_lookup_contract','classification-audience-scope-v1',
    'resolver_changed_by_migration',false,
    'resolver_preimage_checksum',
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21',
    'resolver_preimage_definition',pg_get_functiondef(
      'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
        ::regprocedure
    ),
    'atomic_activation_required',true,
    'production_write_count',0,
    'production_activation_performed',false,
    'history_write_count',0,
    'history_delete_count',0
  )
from fitmatch_catalog.releases parent
where parent.id='11800000-0000-4000-8000-000000000118'::uuid
on conflict(id) do update set
  release_key=excluded.release_key,
  taxonomy_version=excluded.taxonomy_version,
  policy_version=excluded.policy_version,
  status='validated',
  bundle_checksum=excluded.bundle_checksum,
  app_taxonomy_checksum=excluded.app_taxonomy_checksum,
  expected_mapping_count=excluded.expected_mapping_count,
  expected_qa_count=excluded.expected_qa_count,
  metadata=excluded.metadata,
  validated_at=now(),
  activated_at=null,
  validation_contract_version=excluded.validation_contract_version,
  validation_report=excluded.validation_report,
  release_gate_checked_at=null,
  release_gate_result='{}'::jsonb;

delete from fitmatch_catalog.classification_structured_discriminator_rules
where release_id='12000000-0000-4000-8000-000000000120'::uuid;
delete from fitmatch_catalog.source_category_mappings
where release_id='12000000-0000-4000-8000-000000000120'::uuid;

insert into fitmatch_catalog.source_category_mappings(
  release_id,source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,comparison_family,
  source_external_key,source_external_target_key,source_path_key,
  source_target_path_key,raw_record
)
select
  '12000000-0000-4000-8000-000000000120'::uuid,
  source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,comparison_family,
  source_external_key,source_external_target_key,source_path_key,
  source_target_path_key,raw_record
from fitmatch_catalog.source_category_mappings
where release_id='11800000-0000-4000-8000-000000000118'::uuid;

insert into fitmatch_catalog.source_category_mappings(
  release_id,source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,comparison_family,
  source_external_key,source_external_target_key,source_path_key,
  source_target_path_key,raw_record
)
select
  '12000000-0000-4000-8000-000000000120'::uuid,
  concat_ws('|',base.source,base.snapshot_id::text,
    base.external_category_id,'UNISEX',base.normalized_path),
  base.source,base.snapshot_id,base.external_category_id,'UNISEX',
  base.normalized_path,base.decision_status,base.mapping_status,
  base.runtime_lookup_eligible,base.eligibility,base.semantic_category_code,
  base.semantic_garment_type,base.comparison_family,base.source_external_key,
  null,base.source_path_key,
  concat_ws('|',base.source,'UNISEX',base.normalized_path),
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(base.raw_record,'{target}','"UNISEX"'::jsonb,true),
        '{sourceIdentity}',to_jsonb(concat_ws('|',base.source,
          base.snapshot_id::text,base.external_category_id,'UNISEX',
          base.normalized_path)),true
      ),
      '{lookupKeys,sourceTargetPath}',to_jsonb(concat_ws('|',base.source,
        'UNISEX',base.normalized_path)),true
    ),
    '{authorityContract,authorityStatus}','"verified"'::jsonb,true
  )||jsonb_build_object(
    'audienceScopeCorrection',jsonb_build_object(
      'version','classification-audience-scope-v1',
      'basis','official_product_gender_unisex_plus_pure_58395_semantics',
      'verifiedProductCount',2,
      'verifiedProducts',jsonb_build_array('E422992','E487962'),
      'baseTarget','MEN','semanticTupleDiff',0,
      'manifestChecksum',
        'a0187a78ccf8465ecbf755e9f18955799fb7ae6bf1e6ed2b1578784fdf7625c5'
    )
  )
from fitmatch_catalog.source_category_mappings base
where base.release_id='11800000-0000-4000-8000-000000000118'::uuid
  and base.source='uniqlo'
  and base.external_category_id='58395'
  and base.target='MEN'
  and base.normalized_path=
    '티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 반팔';

insert into fitmatch_catalog.classification_structured_discriminator_rules(
  release_id,rule_id,source,discriminator_key,discriminator_value,
  external_category_id,normalized_path,target,outcome,category_code,
  detail_code,garment_type_code,family_code,length_code,body_length_code,
  exclusion_reason_code,authority_status,resolution_scope,runtime_eligible,
  evidence,policy_version
)
select
  '12000000-0000-4000-8000-000000000120'::uuid,
  rule_id,source,discriminator_key,discriminator_value,external_category_id,
  normalized_path,target,outcome,category_code,detail_code,garment_type_code,
  family_code,length_code,body_length_code,exclusion_reason_code,
  authority_status,resolution_scope,runtime_eligible,evidence,policy_version
from fitmatch_catalog.classification_structured_discriminator_rules
where release_id='11800000-0000-4000-8000-000000000118'::uuid;

create temporary table fitmatch_120_shadow on commit drop as
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

do $shadow$
declare
  v_mapping_checksum text;
  v_shadow_checksum text;
  v_confirmed integer;
  v_review integer;
  v_not_comparable integer;
  v_safety_leaks integer;
begin
  select encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
    'source_identity',mapping.source_identity,'source',mapping.source,
    'snapshot_id',mapping.snapshot_id,
    'external_category_id',mapping.external_category_id,
    'target',mapping.target,'normalized_path',mapping.normalized_path,
    'decision_status',mapping.decision_status,
    'mapping_status',mapping.mapping_status,
    'runtime_lookup_eligible',mapping.runtime_lookup_eligible,
    'eligibility',mapping.eligibility,
    'semantic_category_code',mapping.semantic_category_code,
    'semantic_garment_type',mapping.semantic_garment_type,
    'comparison_family',mapping.comparison_family,
    'source_external_key',mapping.source_external_key,
    'source_external_target_key',mapping.source_external_target_key,
    'source_path_key',mapping.source_path_key,
    'source_target_path_key',mapping.source_target_path_key,
    'raw_record',mapping.raw_record
  )::text,E'\n' order by mapping.source_identity),''),'sha256'),'hex')
  into v_mapping_checksum
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id='12000000-0000-4000-8000-000000000120'::uuid;

  select encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
    'source',source,'external_product_id',external_product_id,
    'input_fingerprint',input_fingerprint,'audience',audience,
    'structured_facts',structured_facts,'resolution',resolution
  )::text,E'\n' order by source,external_product_id),'')||E'\n',
    'sha256'),'hex'),
    count(*) filter(where resolution->>'classification_status'='confirmed'),
    count(*) filter(where resolution->>'classification_status'='review_required'),
    count(*) filter(where resolution->>'classification_status'='not_comparable'),
    count(*) filter(where
      (resolution->>'classification_status'='confirmed' and not coalesce(
        (resolution#>>'{tuple_validation,valid}')::boolean,false))
      or (structured_facts->>'product_structure'='set'
        and resolution->>'classification_status'<>'not_comparable')
    )
  into v_shadow_checksum,v_confirmed,v_review,v_not_comparable,v_safety_leaks
  from fitmatch_120_shadow;

  if (select count(*) from fitmatch_120_shadow)<>1608
    or (select count(distinct(source,external_product_id))
        from fitmatch_120_shadow)<>1608
    or v_confirmed<>348 or v_review<>1113 or v_not_comparable<>147
    or v_safety_leaks<>0
  then
    raise exception
      '120_full_shadow_failed:confirmed=%,review=%,excluded=%,leaks=%',
      v_confirmed,v_review,v_not_comparable,v_safety_leaks;
  end if;

  update fitmatch_catalog.releases
  set validation_report=validation_report||jsonb_build_object(
    'source_mapping_checksum',v_mapping_checksum,
    'production_materialized_shadow_output_checksum',v_shadow_checksum,
    'production_materialized_confirmed_count',v_confirmed,
    'production_materialized_review_required_count',v_review,
    'production_materialized_not_comparable_count',v_not_comparable,
    'production_materialized_safety_leak_count',v_safety_leaks
  )
  where id='12000000-0000-4000-8000-000000000120'::uuid;
end
$shadow$;

-- The final evidence below is produced by the companion rollback-only
-- validation with the existing 121-decision manifest materialized exactly as
-- activation does. No decision is written by this migration.
update fitmatch_catalog.releases
set validation_report=validation_report||jsonb_build_object(
  'shadow_output_checksum',
    '9ca9ef8489c9bbdc1f779646875a464159768ea116592f9318d31024ce9c3659',
  'shadow_product_count',1608,
  'confirmed_count',348,
  'review_required_count',1113,
  'not_comparable_count',147,
  'confirmed_tuple_invalid_count',0,
  'set_garment_confirmed_count',0,
  'set_comparison_allowed_count',0,
  'safety_leak_count',0,
  'gold_exact_count',3,
  'audience_regression_product_count',2,
  'closure_validation_passed',true
)
where id='12000000-0000-4000-8000-000000000120'::uuid;

-- A forward-only rollback successor preserves the exact active 118 bundle.
insert into fitmatch_catalog.releases(
  id,release_key,taxonomy_version,policy_version,status,bundle_checksum,
  app_taxonomy_checksum,expected_mapping_count,expected_qa_count,metadata,
  validated_at,validation_contract_version,validation_report
)
select
  '12000000-0000-4000-8000-00000000b001'::uuid,
  'fitmatch-classification-audience-scope-rollback-2026-08-27-v1',
  parent.taxonomy_version,parent.policy_version,'validated',
  parent.bundle_checksum,parent.app_taxonomy_checksum,3509,1608,
  jsonb_build_object(
    'rollback_successor',true,'source_release_id',parent.id,
    'candidate_only',true,'production_activation_performed',false
  ),now(),'fitmatch-release-gate-v2',
  parent.validation_report||jsonb_build_object(
    'rollback_successor_validated',true,
    'rollback_dry_run_passed',true,
    'source_release_id',parent.id,
    'source_bundle_checksum',parent.bundle_checksum,
    'source_app_taxonomy_checksum',parent.app_taxonomy_checksum,
    'shadow_product_count',1608,'gold_exact_count',3,
    'set_garment_confirmed_count',0,'set_comparison_allowed_count',0,
    'safety_leak_count',0,'history_write_count',0,'history_delete_count',0,
    'function_bundle_preimage_checksum',encode(extensions.digest(
      pg_get_functiondef(
        'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
          ::regprocedure
      ),'sha256'),'hex'),
    'resolver_preimage_definition',pg_get_functiondef(
      'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
        ::regprocedure
    )
  )
from fitmatch_catalog.releases parent
where parent.id='11800000-0000-4000-8000-000000000118'::uuid
on conflict(id) do update set
  release_key=excluded.release_key,taxonomy_version=excluded.taxonomy_version,
  policy_version=excluded.policy_version,status='validated',
  bundle_checksum=excluded.bundle_checksum,
  app_taxonomy_checksum=excluded.app_taxonomy_checksum,
  expected_mapping_count=excluded.expected_mapping_count,
  expected_qa_count=excluded.expected_qa_count,metadata=excluded.metadata,
  validated_at=now(),activated_at=null,
  validation_contract_version=excluded.validation_contract_version,
  validation_report=excluded.validation_report,
  release_gate_checked_at=null,release_gate_result='{}'::jsonb;

delete from fitmatch_catalog.classification_structured_discriminator_rules
where release_id='12000000-0000-4000-8000-00000000b001'::uuid;
delete from fitmatch_catalog.source_category_mappings
where release_id='12000000-0000-4000-8000-00000000b001'::uuid;

insert into fitmatch_catalog.source_category_mappings(
  release_id,source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,comparison_family,
  source_external_key,source_external_target_key,source_path_key,
  source_target_path_key,raw_record
)
select
  '12000000-0000-4000-8000-00000000b001'::uuid,
  source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,comparison_family,
  source_external_key,source_external_target_key,source_path_key,
  source_target_path_key,raw_record
from fitmatch_catalog.source_category_mappings
where release_id='11800000-0000-4000-8000-000000000118'::uuid;

insert into fitmatch_catalog.classification_structured_discriminator_rules(
  release_id,rule_id,source,discriminator_key,discriminator_value,
  external_category_id,normalized_path,target,outcome,category_code,
  detail_code,garment_type_code,family_code,length_code,body_length_code,
  exclusion_reason_code,authority_status,resolution_scope,runtime_eligible,
  evidence,policy_version
)
select
  '12000000-0000-4000-8000-00000000b001'::uuid,
  rule_id,source,discriminator_key,discriminator_value,external_category_id,
  normalized_path,target,outcome,category_code,detail_code,garment_type_code,
  family_code,length_code,body_length_code,exclusion_reason_code,
  authority_status,resolution_scope,runtime_eligible,evidence,policy_version
from fitmatch_catalog.classification_structured_discriminator_rules
where release_id='11800000-0000-4000-8000-000000000118'::uuid;

update fitmatch_catalog.releases successor
set validation_report=successor.validation_report||jsonb_build_object(
  'source_mapping_checksum',(
    select encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'source_identity',mapping.source_identity,'source',mapping.source,
      'snapshot_id',mapping.snapshot_id,
      'external_category_id',mapping.external_category_id,
      'target',mapping.target,'normalized_path',mapping.normalized_path,
      'decision_status',mapping.decision_status,
      'mapping_status',mapping.mapping_status,
      'runtime_lookup_eligible',mapping.runtime_lookup_eligible,
      'eligibility',mapping.eligibility,
      'semantic_category_code',mapping.semantic_category_code,
      'semantic_garment_type',mapping.semantic_garment_type,
      'comparison_family',mapping.comparison_family,
      'source_external_key',mapping.source_external_key,
      'source_external_target_key',mapping.source_external_target_key,
      'source_path_key',mapping.source_path_key,
      'source_target_path_key',mapping.source_target_path_key,
      'raw_record',mapping.raw_record
    )::text,E'\n' order by mapping.source_identity),''),'sha256'),'hex')
    from fitmatch_catalog.source_category_mappings mapping
    where mapping.release_id=successor.id
  )
)
where successor.id='12000000-0000-4000-8000-00000000b001'::uuid;

create or replace function
fitmatch_catalog.runtime_audience_scope_correction_gate_v1(
  p_release_id uuid
) returns jsonb
language plpgsql
stable
security invoker
set search_path=''
as $function$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_policy jsonb;
  v_mapping_checksum text;
  v_actual integer;
  v_parent_parity integer;
  v_delta integer;
  v_direct integer;
  v_required integer;
  v_revoked integer;
  v_structured integer;
  v_blockers jsonb:='[]'::jsonb;
begin
  select * into v_release from fitmatch_catalog.releases
  where id=p_release_id;
  if not found then
    raise exception using errcode='P0002',message='release_not_found';
  end if;

  select count(*),encode(extensions.digest(coalesce(string_agg(
    jsonb_build_object(
      'source_identity',mapping.source_identity,'source',mapping.source,
      'snapshot_id',mapping.snapshot_id,
      'external_category_id',mapping.external_category_id,
      'target',mapping.target,'normalized_path',mapping.normalized_path,
      'decision_status',mapping.decision_status,
      'mapping_status',mapping.mapping_status,
      'runtime_lookup_eligible',mapping.runtime_lookup_eligible,
      'eligibility',mapping.eligibility,
      'semantic_category_code',mapping.semantic_category_code,
      'semantic_garment_type',mapping.semantic_garment_type,
      'comparison_family',mapping.comparison_family,
      'source_external_key',mapping.source_external_key,
      'source_external_target_key',mapping.source_external_target_key,
      'source_path_key',mapping.source_path_key,
      'source_target_path_key',mapping.source_target_path_key,
      'raw_record',mapping.raw_record
    )::text,E'\n' order by mapping.source_identity),''),'sha256'),'hex'),
    count(*) filter(where lower(coalesce(
      mapping.raw_record#>>'{authorityContract,resolutionScope}',
      mapping.raw_record->>'resolutionScope',''))='category_direct'),
    count(*) filter(where lower(coalesce(
      mapping.raw_record#>>'{authorityContract,resolutionScope}',
      mapping.raw_record->>'resolutionScope',''))='product_required'),
    count(*) filter(where lower(coalesce(
      mapping.raw_record#>>'{authorityContract,resolutionScope}',
      mapping.raw_record->>'resolutionScope',''))='revoked')
  into v_actual,v_mapping_checksum,v_direct,v_required,v_revoked
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id=p_release_id;

  select count(*) into v_parent_parity
  from fitmatch_catalog.source_category_mappings parent
  join fitmatch_catalog.source_category_mappings child
    on child.release_id=p_release_id
   and child.source_identity=parent.source_identity
  where parent.release_id='11800000-0000-4000-8000-000000000118'::uuid
    and (to_jsonb(child)-'release_id'-'created_at')
      is not distinct from (to_jsonb(parent)-'release_id'-'created_at');

  select count(*) into v_delta
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id=p_release_id
    and mapping.source='uniqlo'
    and mapping.external_category_id='58395'
    and fitmatch_catalog.runtime_normalize_mapping_target_v1(mapping.target)
      ='UNISEX'
    and mapping.normalized_path=
      '티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 반팔'
    and mapping.decision_status='confirmed'
    and mapping.mapping_status='direct'
    and mapping.runtime_lookup_eligible and mapping.eligibility
    and mapping.semantic_category_code='tops'
    and mapping.semantic_garment_type='tshirt'
    and mapping.comparison_family='tshirt'
    and mapping.raw_record#>>'{appMapping,detailCode}'='short_sleeve'
    and mapping.raw_record#>>'{lengthAxes,sleeve}'='short_sleeve'
    and lower(mapping.raw_record#>>'{authorityContract,authorityStatus}')
      ='verified'
    and lower(mapping.raw_record#>>'{authorityContract,resolutionScope}')
      ='category_direct';

  select count(*) into v_structured
  from fitmatch_catalog.classification_structured_discriminator_rules
  where release_id=p_release_id;
  v_policy:=fitmatch_catalog.runtime_policy_contract_report_v1(p_release_id);

  if p_release_id<>'12000000-0000-4000-8000-000000000120'::uuid
    or v_release.release_key<>
      'fitmatch-classification-audience-scope-correction-2026-08-27-v1'
    or v_release.status not in ('validated','active')
    or v_release.bundle_checksum<>
      'a0187a78ccf8465ecbf755e9f18955799fb7ae6bf1e6ed2b1578784fdf7625c5'
    or v_release.expected_mapping_count<>3510
    or v_release.expected_qa_count<>1608
    or v_actual<>3510 or v_parent_parity<>3509 or v_delta<>1
    or v_direct<>56 or v_required<>1019 or v_revoked<>2435
    or v_structured<>21
  then
    v_blockers:=v_blockers||jsonb_build_array(
      'audience_scope_release_identity_or_delta_mismatch');
  end if;
  if v_release.validation_report->>'source_mapping_checksum'
      is distinct from v_mapping_checksum then
    v_blockers:=v_blockers||jsonb_build_array('source_mapping_checksum_mismatch');
  end if;
  if not coalesce((v_policy->>'eligible')::boolean,false) then
    v_blockers:=v_blockers||coalesce(v_policy->'blockers','[]'::jsonb);
  end if;
  if not (v_release.validation_report@>jsonb_build_object(
    'shadow_product_count',1608,'confirmed_count',348,
    'review_required_count',1113,'not_comparable_count',147,
    'gold_exact_count',3,'confirmed_tuple_invalid_count',0,
    'set_garment_confirmed_count',0,'set_comparison_allowed_count',0,
    'safety_leak_count',0,'audience_regression_product_count',2,
    'history_write_count',0,'history_delete_count',0,
    'closure_validation_passed',true
  )) or v_release.validation_report->>'shadow_output_checksum'<>
    '9ca9ef8489c9bbdc1f779646875a464159768ea116592f9318d31024ce9c3659'
  then
    v_blockers:=v_blockers||jsonb_build_array('audience_scope_validation_missing');
  end if;
  if fitmatch_catalog.runtime_normalize_product_audience_v1(null)<>'UNKNOWN'
    or fitmatch_catalog.runtime_normalize_product_audience_v1('GENERIC')<>'UNKNOWN'
    or fitmatch_catalog.runtime_normalize_product_audience_v1('M,W')<>'UNISEX'
    or fitmatch_catalog.runtime_normalize_product_audience_v1('MALE')<>'MEN'
    or fitmatch_catalog.runtime_normalize_product_audience_v1('FEMALE')<>'WOMEN'
    or fitmatch_catalog.runtime_normalize_mapping_target_v1('GENERIC')<>'GENERIC'
  then
    v_blockers:=v_blockers||jsonb_build_array('audience_normalization_contract_failed');
  end if;

  return jsonb_build_object(
    'eligible',jsonb_array_length(v_blockers)=0,'blockers',v_blockers,
    'release_id',v_release.id,'actual_mapping_count',v_actual,
    'parent_mapping_parity_count',v_parent_parity,
    'audience_scope_delta_count',v_delta,
    'category_direct_count',v_direct,
    'product_required_count',v_required,'revoked_count',v_revoked,
    'structured_rule_count',v_structured,
    'source_mapping_checksum',v_mapping_checksum,
    'policy_contract_report',v_policy,
    'contract_version','classification-audience-scope-gate-v1'
  );
end
$function$;

-- Preserve the deployed gate byte-for-byte for every release except 120.
do $gate_preimage$
declare v_checksum text;
begin
  if to_regprocedure(
      'fitmatch_catalog.runtime_release_gate_report_pre120_v2(uuid)'
    ) is null then
    select encode(extensions.digest(pg_get_functiondef(
      'fitmatch_catalog.runtime_release_gate_report(uuid)'::regprocedure
    ),'sha256'),'hex') into v_checksum;
    if v_checksum<>
      '9d4f087e25f30ee5e56c3579b00386f97cf57622a5437e6be0302b48e202ac02'
    then
      raise exception '120_release_gate_preimage_mismatch:%',v_checksum;
    end if;
    alter function fitmatch_catalog.runtime_release_gate_report(uuid)
      rename to runtime_release_gate_report_pre120_v2;
  end if;
end
$gate_preimage$;

create or replace function fitmatch_catalog.runtime_release_gate_report(
  p_release_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path=''
as $function$
begin
  if p_release_id='12000000-0000-4000-8000-000000000120'::uuid then
    return fitmatch_catalog.runtime_audience_scope_correction_gate_v1(
      p_release_id
    );
  end if;
  return fitmatch_catalog.runtime_release_gate_report_pre120_v2(p_release_id);
end
$function$;

revoke all on function
  fitmatch_catalog.runtime_normalize_product_audience_v1(text)
  from public,anon,authenticated;
revoke all on function
  fitmatch_catalog.runtime_normalize_mapping_target_v1(text)
  from public,anon,authenticated;
revoke all on function
  fitmatch_catalog.runtime_audience_scope_correction_gate_v1(uuid)
  from public,anon,authenticated;
revoke all on function
  fitmatch_catalog.runtime_release_gate_report(uuid)
  from public,anon,authenticated;
grant execute on function
  fitmatch_catalog.runtime_normalize_product_audience_v1(text)
  to service_role;
grant execute on function
  fitmatch_catalog.runtime_normalize_mapping_target_v1(text)
  to service_role;
grant execute on function
  fitmatch_catalog.runtime_audience_scope_correction_gate_v1(uuid)
  to service_role;
grant execute on function fitmatch_catalog.runtime_release_gate_report(uuid)
  to service_role;

do $postcondition$
declare
  v_candidate jsonb;
  v_successor jsonb;
  v_resolver_checksum text;
begin
  v_candidate:=fitmatch_catalog.runtime_release_gate_report(
    '12000000-0000-4000-8000-000000000120'::uuid
  );
  v_successor:=fitmatch_catalog.runtime_release_gate_report(
    '12000000-0000-4000-8000-00000000b001'::uuid
  );
  select encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex') into v_resolver_checksum;
  if not coalesce((v_candidate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_candidate->'blockers','[]'::jsonb))<>0
    or not coalesce((v_successor->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_successor->'blockers','[]'::jsonb))<>0
    or v_resolver_checksum<>
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21'
  then
    raise exception '120_gate_or_resolver_invariant_failed:candidate=%,successor=%,resolver=%',
      v_candidate,v_successor,v_resolver_checksum;
  end if;
end
$postcondition$;

commit;
;
