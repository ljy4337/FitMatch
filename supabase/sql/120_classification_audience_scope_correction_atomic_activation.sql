-- CONTROLLED PRODUCTION ARTIFACT. Do not run before owner approval.
-- Resolver replacement and release activation are one PostgreSQL transaction.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';

select pg_advisory_xact_lock(hashtext('fitmatch:release-activation'));
select pg_advisory_xact_lock(
  hashtext('fitmatch:classification-audience-scope-2026-08-27-v1')
);

create temporary table fitmatch_120_activation_guard on commit drop as
select
  (select count(*) from fitmatch_catalog.product_classification_history)
    history_count,
  (select count(*) from fitmatch_catalog.product_classification_history
    where is_current) current_history_count,
  encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex') resolver_checksum,
  procedure.proowner resolver_owner,
  procedure.proacl resolver_acl,
  procedure.prosecdef resolver_security_definer,
  procedure.proconfig resolver_config
from pg_catalog.pg_proc procedure
where procedure.oid=
  'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
    ::regprocedure;

select 1
from fitmatch_catalog.releases
where id in (
  '11800000-0000-4000-8000-000000000118'::uuid,
  '12000000-0000-4000-8000-000000000120'::uuid,
  '12000000-0000-4000-8000-00000000b001'::uuid
)
for update;

do $preflight$
declare
  v_candidate jsonb;
  v_successor jsonb;
begin
  v_candidate:=fitmatch_catalog.runtime_release_gate_report(
    '12000000-0000-4000-8000-000000000120'::uuid
  );
  v_successor:=fitmatch_catalog.runtime_release_gate_report(
    '12000000-0000-4000-8000-00000000b001'::uuid
  );

  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or (select id from fitmatch_catalog.releases where status='active')<>
      '11800000-0000-4000-8000-000000000118'::uuid
    or (select status from fitmatch_catalog.releases
        where id='12000000-0000-4000-8000-000000000120'::uuid)<>'validated'
    or (select status from fitmatch_catalog.releases
        where id='12000000-0000-4000-8000-00000000b001'::uuid)<>'validated'
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id='11800000-0000-4000-8000-000000000118'::uuid)<>3509
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id='12000000-0000-4000-8000-000000000120'::uuid)<>3510
    or (select resolver_checksum from fitmatch_120_activation_guard)<>
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21'
    or not coalesce((v_candidate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_candidate->'blockers','[]'::jsonb))<>0
    or not coalesce((v_successor->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_successor->'blockers','[]'::jsonb))<>0
  then
    raise exception
      '120_atomic_activation_preflight_failed:candidate=%,successor=%,resolver=%',
      v_candidate,v_successor,
      (select resolver_checksum from fitmatch_120_activation_guard);
  end if;
end
$preflight$;

-- Patch only the audience declaration and mapping lookup inside the deployed
-- resolver v4. The exact preimage above is mandatory, and the whole CREATE OR
-- REPLACE is rolled back if any later release or smoke assertion fails.
do $resolver_patch$
declare
  v_definition text;
  v_declaration text :=
    '  v_target text := upper(nullif(btrim(coalesce(p_payload->>''audience'','''')),''''));';
  v_start integer;
  v_end integer;
begin
  select pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ) into v_definition;

  if position(v_declaration in v_definition)=0 then
    raise exception '120_resolver_audience_declaration_not_found';
  end if;

  v_definition:=replace(
    v_definition,
    v_declaration,
    '  v_target text := fitmatch_catalog.runtime_normalize_product_audience_v1('
      ||'p_payload->>''audience'');'
  );
  v_definition:=replace(
    v_definition,
    '  v_mapping_count integer := 0;'||E'\n'||'  v_mapping_scope text;',
    '  v_mapping_count integer := 0;'||E'\n'
      ||'  v_mapping_identity text;'||E'\n'||'  v_mapping_scope text;'
  );

  v_start:=position(
    '  -- Mapping lookup only considers verified, runtime-eligible direct/required'
    in v_definition
  );
  v_end:=position('  if v_mapping_found then' in v_definition);
  if v_start=0 or v_end<=v_start then
    raise exception '120_resolver_mapping_block_not_found';
  end if;

  v_definition:=substr(v_definition,1,v_start-1)
    ||$mapping_block$  -- Audience-aware mapping lookup: category exact -> category GENERIC
  -- -> path exact -> path GENERIC. UNKNOWN and UNISEX remain exact values.
  -- Mapping target aliases are canonicalized, but GENERIC is never inferred.
  if jsonb_typeof(p_payload->'source_category_codes')='array'
    and jsonb_array_length(p_payload->'source_category_codes')>0 then
    with codes as (
      select value code,ordinality
      from jsonb_array_elements_text(p_payload->'source_category_codes')
        with ordinality item(value,ordinality)
    ), candidates as (
      select mapping.source_identity,codes.ordinality,
        max(codes.ordinality) over() max_ordinality,
        case
          when upper(btrim(mapping.target))=v_target then 0
          when fitmatch_catalog.runtime_normalize_mapping_target_v1(
            mapping.target)=v_target then 1
          else 2
        end audience_priority,
        jsonb_build_object(
          'scope',lower(coalesce(
            mapping.raw_record#>>'{authorityContract,resolutionScope}',
            mapping.raw_record->>'resolutionScope','')),
          'category',mapping.semantic_category_code,
          'detail',mapping.raw_record#>>'{appMapping,detailCode}',
          'garment',mapping.semantic_garment_type,
          'family',mapping.comparison_family,
          'length_axes',mapping.raw_record->'lengthAxes'
        )::text semantic_signature
      from codes join fitmatch_catalog.source_category_mappings mapping
        on mapping.release_id=v_release_id and mapping.source=v_source
       and mapping.external_category_id=codes.code
       and mapping.runtime_lookup_eligible and mapping.eligibility
       and lower(coalesce(
         mapping.raw_record#>>'{authorityContract,authorityStatus}',
         mapping.raw_record->>'authorityStatus',''))='verified'
       and fitmatch_catalog.runtime_normalize_mapping_target_v1(mapping.target)
         in (v_target,'GENERIC')
    ), leaf as (
      select candidates.*,
        min(audience_priority) over() min_audience_priority
      from candidates where ordinality=max_ordinality
    ), selected as (
      select * from leaf where audience_priority=min_audience_priority
    )
    select count(distinct semantic_signature),min(source_identity)
    into v_mapping_count,v_mapping_identity
    from selected;

    if v_mapping_count=1 then
      select mapping.* into v_mapping
      from fitmatch_catalog.source_category_mappings mapping
      where mapping.release_id=v_release_id
        and mapping.source_identity=v_mapping_identity;
      v_mapping_found:=found;
    elsif v_mapping_count>1 then
      v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object(
        'code','source_mapping_ambiguous','candidate_count',v_mapping_count));
    end if;
  end if;

  if not v_mapping_found and v_mapping_count=0 and v_path<>'' then
    with candidates as (
      select mapping.source_identity,
        case
          when upper(btrim(mapping.target))=v_target then 0
          when fitmatch_catalog.runtime_normalize_mapping_target_v1(
            mapping.target)=v_target then 1
          else 2
        end audience_priority,
        jsonb_build_object(
          'scope',lower(coalesce(
            mapping.raw_record#>>'{authorityContract,resolutionScope}',
            mapping.raw_record->>'resolutionScope','')),
          'category',mapping.semantic_category_code,
          'detail',mapping.raw_record#>>'{appMapping,detailCode}',
          'garment',mapping.semantic_garment_type,
          'family',mapping.comparison_family,
          'length_axes',mapping.raw_record->'lengthAxes'
        )::text semantic_signature
      from fitmatch_catalog.source_category_mappings mapping
      where mapping.release_id=v_release_id and mapping.source=v_source
        and fitmatch_catalog.runtime_normalized_category_path(
          mapping.normalized_path)=v_path
        and mapping.runtime_lookup_eligible and mapping.eligibility
        and lower(coalesce(
          mapping.raw_record#>>'{authorityContract,authorityStatus}',
          mapping.raw_record->>'authorityStatus',''))='verified'
        and fitmatch_catalog.runtime_normalize_mapping_target_v1(mapping.target)
          in (v_target,'GENERIC')
    ), selected as (
      select candidates.*,
        min(audience_priority) over() min_audience_priority
      from candidates
    )
    select count(distinct semantic_signature),min(source_identity)
    into v_mapping_count,v_mapping_identity
    from selected
    where audience_priority=min_audience_priority;

    if v_mapping_count=1 then
      select mapping.* into v_mapping
      from fitmatch_catalog.source_category_mappings mapping
      where mapping.release_id=v_release_id
        and mapping.source_identity=v_mapping_identity;
      v_mapping_found:=found;
    elsif v_mapping_count>1 then
      v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object(
        'code','source_mapping_ambiguous','candidate_count',v_mapping_count));
    end if;
  end if;

$mapping_block$
    ||substr(v_definition,v_end);

  execute v_definition;
end
$resolver_patch$;

do $resolver_postcondition$
declare
  v_checksum text;
  v_owner oid;
  v_acl aclitem[];
  v_security_definer boolean;
  v_config text[];
begin
  select encode(extensions.digest(pg_get_functiondef(procedure.oid),
      'sha256'),'hex'),procedure.proowner,procedure.proacl,
    procedure.prosecdef,procedure.proconfig
  into v_checksum,v_owner,v_acl,v_security_definer,v_config
  from pg_catalog.pg_proc procedure
  where procedure.oid=
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure;

  if v_checksum<>'3e99c584285b249c9adca76e1b8c0c8b68ec3f10f38dced306e392ef4a48b604'
    or v_owner is distinct from
      (select resolver_owner from fitmatch_120_activation_guard)
    or v_acl is distinct from
      (select resolver_acl from fitmatch_120_activation_guard)
    or v_security_definer is distinct from
      (select resolver_security_definer from fitmatch_120_activation_guard)
    or v_config is distinct from
      (select resolver_config from fitmatch_120_activation_guard)
  then
    raise exception
      '120_resolver_postimage_mismatch:checksum=%,owner=%,acl=%,security=%,config=%',
      v_checksum,v_owner,v_acl,v_security_definer,v_config;
  end if;
end
$resolver_postcondition$;

select fitmatch_catalog.runtime_activate_validated_release(
  '12000000-0000-4000-8000-000000000120'::uuid
);

create temporary table fitmatch_120_activation_smoke on commit drop as
with facts as (
  select value->>'source' source,
    value->>'external_product_id' external_product_id,
    value->'structured_facts' structured_facts
  from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
  where value->>'record_type'='product_structured_fact'
)
select product.source,product.external_product_id,product.audience,
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
left join facts using(source,external_product_id)
where product.source='uniqlo'
  and product.external_product_id in (
    'E422992','E487962','E455365','E465187','E475376','E487898','E489013'
  );

do $smoke$
declare
  v_women jsonb;
  v_unknown jsonb;
  v_set jsonb;
begin
  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or (select id from fitmatch_catalog.releases where status='active')<>
      '12000000-0000-4000-8000-000000000120'::uuid
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id=(select id from fitmatch_catalog.releases
          where status='active'))<>3510
    or (select count(*) from fitmatch_120_activation_smoke
        where external_product_id in ('E422992','E487962')
          and audience='UNISEX'
          and resolution->>'classification_status'='confirmed'
          and resolution->>'classification_method'='category_mapping'
          and resolution->>'category_code'='tops'
          and resolution->>'detail_code'='short_sleeve'
          and resolution->>'garment_type_code'='tshirt'
          and resolution->>'family_code'='tshirt'
          and resolution->>'length_code'='short_sleeve')<>2
    or (select count(*) from fitmatch_120_activation_smoke
        where external_product_id in (
          'E455365','E465187','E475376','E487898','E489013'
        ) and audience='MEN'
          and resolution->>'classification_status'='confirmed'
          and resolution->>'category_code'='tops'
          and resolution->>'detail_code'='short_sleeve'
          and resolution->>'garment_type_code'='tshirt'
          and resolution->>'family_code'='tshirt'
          and resolution->>'length_code'='short_sleeve')<>5
  then
    raise exception '120_atomic_activation_release_or_product_smoke_failed';
  end if;

  v_women:=fitmatch_catalog.runtime_resolve_product_classification_v4(
    'uniqlo','future-women-58395','Future garment',
    '티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 반팔',
    jsonb_build_object('audience','WOMEN','source_category_codes',
      jsonb_build_array('57967','58039','58395')),null
  );
  v_unknown:=fitmatch_catalog.runtime_resolve_product_classification_v4(
    'uniqlo','future-unknown-58395','Future garment',
    '티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 반팔',
    jsonb_build_object('audience','UNKNOWN','source_category_codes',
      jsonb_build_array('57967','58039','58395')),null
  );
  v_set:=fitmatch_catalog.runtime_resolve_product_classification_v4(
    'uniqlo','future-set-58395','Future set garment',
    '티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 반팔',
    jsonb_build_object(
      'audience','UNISEX',
      'source_category_codes',jsonb_build_array('57967','58039','58395'),
      'structured_facts',jsonb_build_object('product_structure','set')
    ),null
  );

  if v_women->>'classification_status'<>'review_required'
    or v_unknown->>'classification_status'<>'review_required'
    or v_set->>'classification_status'<>'not_comparable'
    or fitmatch_catalog.runtime_normalize_product_audience_v1('GENERIC')<>'UNKNOWN'
    or fitmatch_catalog.runtime_normalize_mapping_target_v1('GENERIC')<>'GENERIC'
    or (select count(*) from fitmatch_catalog.product_classification_history)<>
      (select history_count from fitmatch_120_activation_guard)
    or (select count(*) from fitmatch_catalog.product_classification_history
        where is_current)<>
      (select current_history_count from fitmatch_120_activation_guard)
  then
    raise exception
      '120_atomic_activation_safety_or_history_smoke_failed:women=%,unknown=%,set=%',
      v_women,v_unknown,v_set;
  end if;
end
$smoke$;

select jsonb_build_object(
  'atomic_activation','PASS',
  'active_release_id',
    (select id from fitmatch_catalog.releases where status='active'),
  'active_mapping_count',
    (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id=(select id from fitmatch_catalog.releases
        where status='active')),
  'resolver_preimage_checksum',
    (select resolver_checksum from fitmatch_120_activation_guard),
  'resolver_postimage_checksum',encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex'),
  'audience_products','2/2',
  'men_regression','5/5',
  'safety_smoke','PASS',
  'history_write_count',0,
  'history_delete_count',0
) activation_result;

commit;
