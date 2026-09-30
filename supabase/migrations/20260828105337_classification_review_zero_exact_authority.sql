begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';
select pg_advisory_xact_lock(hashtext('fitmatch-runtime-review-zero-121-2026-08-28'));

-- Preimage: the review-zero vNext state must be complete, identity-stable, and
-- the currently active Production release must still be 120.
do $preimage$
begin
  if not exists (
    select 1 from fitmatch_catalog.releases
    where id='12000000-0000-4000-8000-000000000120'::uuid
      and status='active'
  ) then
    raise exception '121_active_release_120_preimage_missing';
  end if;

  if exists (
    select 1 from fitmatch_catalog.releases
    where id='12100000-0000-4000-8000-000000000121'::uuid
       or release_key='fitmatch-vnext-exact-authority-review-zero-2026-08-28-v1'
  ) then
    raise exception '121_release_already_exists';
  end if;

  if (select count(*) from fitmatch_vnext.products)<>1608
    or (select count(*) from fitmatch_vnext.products
        where classification_status='CONFIRMED')<>1421
    or (select count(*) from fitmatch_vnext.products
        where classification_status='REVIEW_REQUIRED')<>0
    or (select count(*) from fitmatch_vnext.products
        where classification_status='NOT_APPLICABLE')<>187
  then
    raise exception '121_vnext_review_zero_preimage_changed';
  end if;

  if (select count(*)
      from fitmatch_vnext.products v
      join fitmatch_catalog.products p
        on p.source=v.source_code
       and p.external_product_id=v.source_product_key
      where v.source_extra->>'_legacy_input_fingerprint'=p.input_fingerprint
     )<>1608
  then
    raise exception '121_product_fingerprint_parity_failed';
  end if;

  if (select count(*) from fitmatch_catalog.product_classification_history
      where is_current)<>1608
  then
    raise exception '121_current_history_preimage_cardinality_changed';
  end if;
end
$preimage$;

-- Exact-authority histories must preserve vNext optional axes. The legacy
-- body-length trigger inferred body length for every outerwear row, even for
-- garments whose comparison contract does not use body length. Keep legacy
-- behavior for ordinary classification writes, but never mutate an exact
-- product-authority snapshot.
create or replace function fitmatch_catalog.sync_product_body_length()
returns trigger
language plpgsql
set search_path to 'pg_catalog','fitmatch_catalog'
as $function$
declare
  v_product fitmatch_catalog.products%rowtype;
begin
  if new.body_length_code is null
    and new.category_code='outerwear'
    and not (coalesce(new.evidence,'{}'::jsonb)
      @> '{"exact_product_authority":true}'::jsonb)
  then
    select * into v_product
    from fitmatch_catalog.products
    where id=new.product_id;

    new.body_length_code:=fitmatch_catalog.runtime_infer_body_length_code(
      new.category_code,
      v_product.product_name,
      v_product.source_category_path
    );
  end if;
  return new;
end
$function$;

comment on function fitmatch_catalog.sync_product_body_length()
is 'Legacy outerwear body-length inference, except immutable exact-product authority snapshots which preserve their explicitly materialized optional axes.';

-- Materialize the complete 1,608-row exact authority candidate.
create temporary table fitmatch_121_exact on commit drop as
with detail_map(garment_type_code,detail_code) as (values
 ('anorak','anorak'),
 ('base_layer_top','base_layer_top'),
 ('blazer','blazer'),
 ('blouson','blouson'),
 ('bodysuit_top','bodysuit_top'),
 ('cardigan','cardigan'),
 ('cargo_pants','cargo_utility'),
 ('casual_pants','casual_pants'),
 ('chino_cotton_pants','chino_cotton'),
 ('coat','coat'),
 ('denim_pants','jeans'),
 ('dress','one_piece'),
 ('fleece_jacket','fleece'),
 ('homewear_bottom','homewear_bottom'),
 ('hoodie','hoodie'),
 ('jacket','jacket'),
 ('knit_sweater','knit_sweater'),
 ('leggings','leggings'),
 ('men_briefs','men_briefs'),
 ('men_trunks','men_trunks'),
 ('mouton','mouton'),
 ('other_standard_pants','long_pants'),
 ('polo_shirt','polo_shirt'),
 ('puffer_jacket','padding'),
 ('puffer_vest','padded_vest'),
 ('shirt_blouse','shirt_blouse'),
 ('shorts','shorts'),
 ('skirt','skirt'),
 ('slacks_trousers','slacks_trousers'),
 ('sleeveless_tshirt','sleeveless_tshirt'),
 ('sports_bottom','sports_bottom'),
 ('sweat_jogger_pants','sweat_jogger'),
 ('sweatshirt','sweatshirt'),
 ('tank_top','sleeveless'),
 ('trench_coat','trench_coat'),
 ('tshirt','tshirt'),
 ('windbreaker','windbreaker'),
 ('women_bra','women_bra'),
 ('women_camisole','women_camisole'),
 ('women_panty','women_panty'),
 ('zip_hoodie','zip_hoodie')
)
select
  p.id product_id,
  p.source,
  p.external_product_id,
  p.input_fingerprint,
  case v.classification_status
    when 'CONFIRMED' then 'confirmed'
    else 'not_comparable'
  end classification_status,
  case when v.classification_status='CONFIRMED'
    then gt.category_code end category_code,
  case when v.classification_status='CONFIRMED'
    then dm.detail_code end detail_code,
  case when v.classification_status='CONFIRMED'
    then v.garment_type_code end garment_type_code,
  case when v.classification_status='CONFIRMED'
    then pg.comparison_group_code end comparison_family_code,
  case
    when v.classification_status='CONFIRMED' and gt.uses_sleeve_length
      then v.sleeve_length_code
    when v.classification_status='CONFIRMED' and gt.uses_lower_length
      then v.lower_length_code
    else null
  end length_code,
  case when v.classification_status='CONFIRMED' and gt.uses_body_length
    then v.body_length_code end body_length_code,
  v.classification_source vnext_classification_source,
  v.product_structure_code,
  v.source_extra->>'_review_zero_resolution' review_zero_resolution,
  v.source_extra->>'_review_zero_basis' review_zero_basis
from fitmatch_vnext.products v
join fitmatch_catalog.products p
  on p.source=v.source_code
 and p.external_product_id=v.source_product_key
left join fitmatch_vnext.garment_types gt
  on gt.garment_type_code=v.garment_type_code
left join public.garment_types pg
  on pg.code=v.garment_type_code and pg.is_active
left join detail_map dm
  on dm.garment_type_code=v.garment_type_code;

do $candidate_gate$
declare
  v_bad integer;
  v_checksum text;
begin
  if (select count(*) from fitmatch_121_exact)<>1608
    or (select count(distinct(source,external_product_id))
        from fitmatch_121_exact)<>1608
    or (select count(*) from fitmatch_121_exact
        where classification_status='confirmed')<>1421
    or (select count(*) from fitmatch_121_exact
        where classification_status='not_comparable')<>187
  then
    raise exception '121_exact_candidate_cardinality_or_status_failed';
  end if;

  select count(*) into v_bad
  from fitmatch_121_exact e
  left join public.garment_types g
    on g.code=e.garment_type_code and g.is_active
  left join public.app_categories parent
    on parent.code=e.category_code
   and parent.depth=0 and parent.parent_id is null and parent.is_active
  left join public.app_categories detail
    on detail.code=e.detail_code
   and detail.depth=1 and detail.parent_id=parent.id and detail.is_active
  left join public.comparison_groups family
    on family.code=e.comparison_family_code and family.is_active
  where e.classification_status='confirmed'
    and (
      g.code is null or parent.id is null or detail.id is null
      or family.code is null
      or g.major_category_code is distinct from e.category_code
      or g.comparison_group_code is distinct from e.comparison_family_code
    );
  if v_bad<>0 then
    raise exception '121_exact_core_tuple_invalid:%',v_bad;
  end if;

  if exists (
    select 1 from fitmatch_121_exact e
    where e.length_code is not null
      and not exists (
        select 1
        from public.comparison_length_classes lc
        join public.garment_types g on g.code=e.garment_type_code
        where lc.code=e.length_code and lc.is_active
          and (
            (g.requires_sleeve_class and lc.axis_code='sleeve')
            or (g.requires_pants_length and lc.axis_code='leg')
          )
      )
  ) then
    raise exception '121_exact_length_axis_invalid';
  end if;

  if exists (
    select 1 from fitmatch_121_exact e
    where e.body_length_code is not null
      and not exists (
        select 1 from public.comparison_length_classes lc
        where lc.code=e.body_length_code
          and lc.axis_code='body' and lc.is_active
      )
  ) then
    raise exception '121_exact_body_axis_invalid';
  end if;

  if exists (
    select 1 from fitmatch_121_exact
    where product_structure_code='SET'
      and classification_status<>'not_comparable'
  ) then
    raise exception '121_exact_set_leak';
  end if;

  select encode(extensions.digest(coalesce(string_agg(
    source||'|'||external_product_id||'|'||input_fingerprint||'|'||
    classification_status||'|'||coalesce(garment_type_code,'')||'|'||
    coalesce(length_code,'')||'|'||coalesce(body_length_code,''),
    E'\n' order by source,external_product_id),''),'sha256'),'hex')
  into v_checksum
  from fitmatch_121_exact;

  if v_checksum<>'dc1747287b4fbf3cb66a8a8cdc103ae7e588c24dba5245db06f6120d9625bc2d'
  then
    raise exception '121_exact_checksum_changed:%',v_checksum;
  end if;
end
$candidate_gate$;

-- Preserve the exact pre-121 current-history identities for rollback evidence.
create temporary table fitmatch_121_pre_history on commit drop as
select id,product_id
from fitmatch_catalog.product_classification_history
where is_current;

-- Successor release keeps all 120 fallback mappings/rules. Existing 1,608
-- products are materialized as exact current history; future/changed products
-- continue through the pre-existing v4 fail-closed classifier.
insert into fitmatch_catalog.releases(
  id,release_key,taxonomy_version,policy_version,status,bundle_checksum,
  app_taxonomy_checksum,expected_mapping_count,expected_qa_count,metadata,
  validated_at,validation_contract_version,validation_report
)
select
  '12100000-0000-4000-8000-000000000121'::uuid,
  'fitmatch-vnext-exact-authority-review-zero-2026-08-28-v1',
  parent.taxonomy_version,parent.policy_version,'validated',
  '0275d651d5bf100a69af042fd475249b859b51f4e901b939eaa608aa56e2e7b1',
  parent.app_taxonomy_checksum,3510,1608,
  jsonb_build_object(
    'phase','Review Zero Exact Product Authority',
    'parent_release_id',parent.id,
    'rollback_source_release_id',parent.id,
    'review_zero',true,
    'materialization_source','fitmatch_vnext.products',
    'future_product_fallback','runtime_resolve_product_classification_v4'
  ),
  now(),'fitmatch-release-gate-v3-review-zero',
  parent.validation_report||jsonb_build_object(
    'parent_release_id',parent.id,
    'exact_authority_checksum',
      'dc1747287b4fbf3cb66a8a8cdc103ae7e588c24dba5245db06f6120d9625bc2d',
    'exact_authority_product_count',1608,
    'materialized_current_history_count',1608,
    'confirmed_count',1421,
    'review_required_count',0,
    'not_comparable_count',187,
    'set_product_count',30,
    'set_leak_count',0,
    'fingerprint_parity_count',1608,
    'core_tuple_invalid_count',0,
    'nonconfirmed_tuple_leak_count',0,
    'pre121_current_history_count',1608,
    'history_delete_count',0,
    'review_zero_passed',true,
    'runtime_policy_contract',parent.validation_report->'runtime_policy_contract'
  )
from fitmatch_catalog.releases parent
where parent.id='12000000-0000-4000-8000-000000000120'::uuid;

insert into fitmatch_catalog.source_category_mappings(
  release_id,source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,comparison_family,
  source_external_key,source_external_target_key,source_path_key,
  source_target_path_key,raw_record
)
select
  '12100000-0000-4000-8000-000000000121'::uuid,
  source_identity,source,snapshot_id,external_category_id,target,
  normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
  eligibility,semantic_category_code,semantic_garment_type,comparison_family,
  source_external_key,source_external_target_key,source_path_key,
  source_target_path_key,raw_record
from fitmatch_catalog.source_category_mappings
where release_id='12000000-0000-4000-8000-000000000120'::uuid;

insert into fitmatch_catalog.classification_structured_discriminator_rules(
  release_id,rule_id,source,discriminator_key,discriminator_value,
  external_category_id,normalized_path,target,outcome,category_code,
  detail_code,garment_type_code,family_code,length_code,body_length_code,
  exclusion_reason_code,authority_status,resolution_scope,runtime_eligible,
  evidence,policy_version
)
select
  '12100000-0000-4000-8000-000000000121'::uuid,
  rule_id,source,discriminator_key,discriminator_value,external_category_id,
  normalized_path,target,outcome,category_code,detail_code,garment_type_code,
  family_code,length_code,body_length_code,exclusion_reason_code,
  authority_status,resolution_scope,runtime_eligible,evidence,policy_version
from fitmatch_catalog.classification_structured_discriminator_rules
where release_id='12000000-0000-4000-8000-000000000120'::uuid;

-- New release gate: exact 1,608-row materialization + unchanged 120 fallback
-- artifacts + set safety + identity parity + ZARA owner adjudications.
create or replace function fitmatch_catalog.runtime_review_zero_gate_v1(
  p_release_id uuid
) returns jsonb
language plpgsql
stable
security invoker
set search_path=''
as $function$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_mapping_count integer;
  v_mapping_parity integer;
  v_rule_count integer;
  v_rule_parity integer;
  v_history_count integer;
  v_confirmed integer;
  v_review integer;
  v_not_comparable integer;
  v_history_parity integer;
  v_fingerprint_parity integer;
  v_set_leaks integer;
  v_core_invalid integer;
  v_checksum text;
  v_blockers jsonb:='[]'::jsonb;
begin
  select * into v_release
  from fitmatch_catalog.releases
  where id=p_release_id;
  if not found then
    raise exception using errcode='P0002',message='release_not_found';
  end if;

  if p_release_id<>'12100000-0000-4000-8000-000000000121'::uuid
    or v_release.release_key<>
      'fitmatch-vnext-exact-authority-review-zero-2026-08-28-v1'
    or v_release.status not in ('validated','active')
    or v_release.validation_contract_version<>
      'fitmatch-release-gate-v3-review-zero'
    or v_release.bundle_checksum<>
      '0275d651d5bf100a69af042fd475249b859b51f4e901b939eaa608aa56e2e7b1'
    or v_release.app_taxonomy_checksum<>
      'eebfa19d3d38993c00540e44410c8815ada1a0162c7856f9d414105f6d2c5c09'
    or v_release.expected_mapping_count<>3510
    or v_release.expected_qa_count<>1608
    or v_release.validated_at is null
  then
    v_blockers:=v_blockers||jsonb_build_array('release_identity_or_contract_mismatch');
  end if;

  select count(*) into v_mapping_count
  from fitmatch_catalog.source_category_mappings
  where release_id=p_release_id;

  select count(*) into v_mapping_parity
  from fitmatch_catalog.source_category_mappings parent
  join fitmatch_catalog.source_category_mappings child
    on child.release_id=p_release_id
   and child.source_identity=parent.source_identity
  where parent.release_id='12000000-0000-4000-8000-000000000120'::uuid
    and (to_jsonb(child)-'release_id'-'created_at')
      is not distinct from (to_jsonb(parent)-'release_id'-'created_at');

  select count(*) into v_rule_count
  from fitmatch_catalog.classification_structured_discriminator_rules
  where release_id=p_release_id;

  select count(*) into v_rule_parity
  from fitmatch_catalog.classification_structured_discriminator_rules parent
  join fitmatch_catalog.classification_structured_discriminator_rules child
    on child.release_id=p_release_id and child.rule_id=parent.rule_id
  where parent.release_id='12000000-0000-4000-8000-000000000120'::uuid
    and (to_jsonb(child)-'release_id'-'created_at')
      is not distinct from (to_jsonb(parent)-'release_id'-'created_at');

  if v_mapping_count<>3510 or v_mapping_parity<>3510
    or v_rule_count<>21 or v_rule_parity<>21
  then
    v_blockers:=v_blockers||jsonb_build_array('fallback_artifact_parity_failed');
  end if;

  select count(*),
    count(*) filter(where classification_status='confirmed'),
    count(*) filter(where classification_status='review_required'),
    count(*) filter(where classification_status='not_comparable')
  into v_history_count,v_confirmed,v_review,v_not_comparable
  from fitmatch_catalog.product_classification_history
  where is_current
    and mapping_release_id=p_release_id
    and evidence @> '{"exact_product_authority":true}'::jsonb;

  if v_history_count<>1608 or v_confirmed<>1421 or v_review<>0
    or v_not_comparable<>187
  then
    v_blockers:=v_blockers||jsonb_build_array('current_history_review_zero_failed');
  end if;

  select count(*) into v_fingerprint_parity
  from fitmatch_catalog.product_classification_history h
  join fitmatch_catalog.products p on p.id=h.product_id
  where h.is_current and h.mapping_release_id=p_release_id
    and h.evidence @> '{"exact_product_authority":true}'::jsonb
    and h.input_fingerprint=p.input_fingerprint
    and h.taxonomy_policy_version='db-classifier-2026-08-26-final';
  if v_fingerprint_parity<>1608 then
    v_blockers:=v_blockers||jsonb_build_array('runtime_fingerprint_parity_failed');
  end if;

  select count(*) into v_history_parity
  from fitmatch_catalog.product_classification_history h
  join fitmatch_vnext.products v on v.id=h.product_id
  left join fitmatch_vnext.garment_types gt
    on gt.garment_type_code=v.garment_type_code
  where h.is_current and h.mapping_release_id=p_release_id
    and (
      (
        v.classification_status='CONFIRMED'
        and h.classification_status='confirmed'
        and h.garment_type_code is not distinct from v.garment_type_code
        and h.length_code is not distinct from case
          when gt.uses_sleeve_length then v.sleeve_length_code
          when gt.uses_lower_length then v.lower_length_code
          else null end
        and h.body_length_code is not distinct from case
          when gt.uses_body_length then v.body_length_code else null end
      )
      or (
        v.classification_status='NOT_APPLICABLE'
        and h.classification_status='not_comparable'
        and h.category_code is null and h.detail_code is null
        and h.garment_type_code is null and h.comparison_family_code is null
        and h.length_code is null and h.body_length_code is null
      )
    );
  if v_history_parity<>1608 then
    v_blockers:=v_blockers||jsonb_build_array('vnext_history_exact_parity_failed');
  end if;

  select count(*) into v_core_invalid
  from fitmatch_catalog.product_classification_history h
  left join public.garment_types g
    on g.code=h.garment_type_code and g.is_active
  left join public.app_categories parent
    on parent.code=h.category_code
   and parent.depth=0 and parent.parent_id is null and parent.is_active
  left join public.app_categories detail
    on detail.code=h.detail_code
   and detail.depth=1 and detail.parent_id=parent.id and detail.is_active
  left join public.comparison_groups family
    on family.code=h.comparison_family_code and family.is_active
  where h.is_current and h.mapping_release_id=p_release_id
    and h.classification_status='confirmed'
    and (
      g.code is null or parent.id is null or detail.id is null
      or family.code is null
      or g.major_category_code is distinct from h.category_code
      or g.comparison_group_code is distinct from h.comparison_family_code
    );
  if v_core_invalid<>0 then
    v_blockers:=v_blockers||jsonb_build_array('confirmed_core_tuple_invalid');
  end if;

  select count(*) into v_set_leaks
  from fitmatch_catalog.product_classification_history h
  join fitmatch_vnext.products v on v.id=h.product_id
  where h.is_current and h.mapping_release_id=p_release_id
    and v.product_structure_code='SET'
    and h.classification_status<>'not_comparable';
  if v_set_leaks<>0 then
    v_blockers:=v_blockers||jsonb_build_array('set_comparison_leak');
  end if;

  if (select count(*) from fitmatch_vnext.products)<>1608
    or (select count(*) from fitmatch_vnext.products
        where classification_status='REVIEW_REQUIRED')<>0
    or (select count(*) from fitmatch_vnext.products
        where classification_status='CONFIRMED')<>1421
    or (select count(*) from fitmatch_vnext.products
        where classification_status='NOT_APPLICABLE')<>187
  then
    v_blockers:=v_blockers||jsonb_build_array('vnext_review_zero_preimage_changed');
  end if;

  select encode(extensions.digest(coalesce(string_agg(
    p.source||'|'||p.external_product_id||'|'||p.input_fingerprint||'|'||
    case v.classification_status when 'CONFIRMED' then 'confirmed'
      else 'not_comparable' end||'|'||coalesce(v.garment_type_code,'')||'|'||
    coalesce(case when gt.uses_sleeve_length then v.sleeve_length_code
      when gt.uses_lower_length then v.lower_length_code end,'')||'|'||
    coalesce(case when gt.uses_body_length then v.body_length_code end,''),
    E'\n' order by p.source,p.external_product_id),''),'sha256'),'hex')
  into v_checksum
  from fitmatch_vnext.products v
  join fitmatch_catalog.products p
    on p.source=v.source_code and p.external_product_id=v.source_product_key
  left join fitmatch_vnext.garment_types gt
    on gt.garment_type_code=v.garment_type_code;

  if v_checksum<>'dc1747287b4fbf3cb66a8a8cdc103ae7e588c24dba5245db06f6120d9625bc2d'
    or v_release.validation_report->>'exact_authority_checksum'<>
      'dc1747287b4fbf3cb66a8a8cdc103ae7e588c24dba5245db06f6120d9625bc2d'
  then
    v_blockers:=v_blockers||jsonb_build_array('exact_authority_checksum_mismatch');
  end if;

  if not exists (
    select 1
    from fitmatch_catalog.product_classification_history h
    join fitmatch_catalog.products p on p.id=h.product_id
    where h.is_current and h.mapping_release_id=p_release_id
      and p.source='zara' and p.external_product_id='545427337'
      and h.classification_status='confirmed'
      and h.garment_type_code='jacket'
  ) then
    v_blockers:=v_blockers||jsonb_build_array('zara_07782343_adjudication_missing');
  end if;

  if not exists (
    select 1 from fitmatch_catalog.data_quality_issues
    where source_code='zara'
      and issue_code='pending_owner_product_adjudication'
      and raw_signature='01934230'
      and status='acknowledged'
  ) then
    v_blockers:=v_blockers||jsonb_build_array('zara_01934230_pending_adjudication_missing');
  end if;

  return jsonb_build_object(
    'contract_version','fitmatch-release-gate-v3-review-zero',
    'release_id',v_release.id,
    'release_key',v_release.release_key,
    'eligible',jsonb_array_length(v_blockers)=0,
    'blockers',v_blockers,
    'expected_mapping_count',3510,
    'actual_mapping_count',v_mapping_count,
    'structured_rule_count',v_rule_count,
    'current_history_count',v_history_count,
    'confirmed_count',v_confirmed,
    'review_required_count',v_review,
    'not_comparable_count',v_not_comparable,
    'history_parity_count',v_history_parity,
    'fingerprint_parity_count',v_fingerprint_parity,
    'set_leak_count',v_set_leaks,
    'core_tuple_invalid_count',v_core_invalid,
    'exact_authority_checksum',v_checksum
  );
end
$function$;

comment on function fitmatch_catalog.runtime_review_zero_gate_v1(uuid)
is 'Release 121 activation gate. Requires exact 1,608 product history materialization with REVIEW_REQUIRED=0, vNext parity, unchanged 120 fallback mappings/rules, identity parity, and zero set leaks.';

create or replace function fitmatch_catalog.runtime_release_gate_report(
  p_release_id uuid
) returns jsonb
language plpgsql
set search_path to ''
as $function$
begin
  if p_release_id='12100000-0000-4000-8000-000000000121'::uuid then
    return fitmatch_catalog.runtime_review_zero_gate_v1(p_release_id);
  end if;
  if p_release_id='12000000-0000-4000-8000-000000000120'::uuid then
    return fitmatch_catalog.runtime_audience_scope_correction_gate_v1(p_release_id);
  end if;
  return fitmatch_catalog.runtime_release_gate_report_pre120_v2(p_release_id);
end
$function$;

-- Replace current history atomically; previous rows are superseded, never
-- deleted, and remain available as rollback evidence.
update fitmatch_catalog.product_classification_history
set is_current=false,superseded_at=now()
where is_current;

insert into fitmatch_catalog.product_classification_history(
  product_id,input_fingerprint,category_code,detail_code,garment_type_code,
  comparison_family_code,length_code,body_length_code,
  classification_status,classification_method,confidence,
  requires_user_confirmation,taxonomy_policy_version,mapping_release_id,
  decision_version,evidence,is_current,reviewed_at
)
select
  e.product_id,e.input_fingerprint,e.category_code,e.detail_code,
  e.garment_type_code,e.comparison_family_code,e.length_code,
  e.body_length_code,e.classification_status,'migration',1,false,
  'db-classifier-2026-08-26-final',
  '12100000-0000-4000-8000-000000000121'::uuid,
  'vnext-exact-authority-review-zero-2026-08-28-v1',
  jsonb_build_object(
    'authority_status','verified',
    'authority_source','fitmatch_vnext.products',
    'exact_product_authority',true,
    'release_id','12100000-0000-4000-8000-000000000121',
    'vnext_classification_source',e.vnext_classification_source,
    'review_zero_resolution',e.review_zero_resolution,
    'review_zero_basis',e.review_zero_basis,
    'product_structure_code',e.product_structure_code,
    'axis_contract','optional-unless-present-valid-v1'
  ),
  true,now()
from fitmatch_121_exact e;

-- Pre-activation materialization gate.
do $materialization_gate$
declare
  v_confirmed integer;
  v_review integer;
  v_not_comparable integer;
  v_parity integer;
begin
  select
    count(*) filter(where classification_status='confirmed'),
    count(*) filter(where classification_status='review_required'),
    count(*) filter(where classification_status='not_comparable')
  into v_confirmed,v_review,v_not_comparable
  from fitmatch_catalog.product_classification_history
  where is_current;

  if (select count(*) from fitmatch_catalog.product_classification_history
      where is_current)<>1608
    or v_confirmed<>1421 or v_review<>0 or v_not_comparable<>187
  then
    raise exception '121_materialized_history_counts_failed:c=%,r=%,n=%',
      v_confirmed,v_review,v_not_comparable;
  end if;

  select count(*) into v_parity
  from fitmatch_catalog.product_classification_history h
  join fitmatch_vnext.products v on v.id=h.product_id
  left join fitmatch_vnext.garment_types gt
    on gt.garment_type_code=v.garment_type_code
  where h.is_current
    and h.mapping_release_id='12100000-0000-4000-8000-000000000121'::uuid
    and (
      (
        v.classification_status='CONFIRMED'
        and h.classification_status='confirmed'
        and h.garment_type_code is not distinct from v.garment_type_code
        and h.length_code is not distinct from case
          when gt.uses_sleeve_length then v.sleeve_length_code
          when gt.uses_lower_length then v.lower_length_code
          else null end
        and h.body_length_code is not distinct from case
          when gt.uses_body_length then v.body_length_code else null end
      )
      or (
        v.classification_status='NOT_APPLICABLE'
        and h.classification_status='not_comparable'
        and h.category_code is null and h.detail_code is null
        and h.garment_type_code is null and h.comparison_family_code is null
        and h.length_code is null and h.body_length_code is null
      )
    );
  if v_parity<>1608 then
    raise exception '121_materialized_history_parity_failed:%',v_parity;
  end if;

  if (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id='12100000-0000-4000-8000-000000000121'::uuid)<>3510
    or (select count(*)
        from fitmatch_catalog.classification_structured_discriminator_rules
        where release_id='12100000-0000-4000-8000-000000000121'::uuid)<>21
  then
    raise exception '121_fallback_artifact_copy_failed';
  end if;
end
$materialization_gate$;

-- Atomic active-pointer switch. The AFTER UPDATE activation trigger calls the
-- new review-zero gate before this transaction can commit.
update fitmatch_catalog.releases
set status='retired'
where id='12000000-0000-4000-8000-000000000120'::uuid
  and status='active';

update fitmatch_catalog.releases
set status='active',activated_at=now()
where id='12100000-0000-4000-8000-000000000121'::uuid
  and status='validated';

-- Independent postflight inside the same transaction.
do $postflight$
declare
  v_gate jsonb;
  v_confirmed integer;
  v_review integer;
  v_not_comparable integer;
begin
  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or not exists (
      select 1 from fitmatch_catalog.releases
      where id='12100000-0000-4000-8000-000000000121'::uuid
        and status='active'
    )
  then
    raise exception '121_active_pointer_failed';
  end if;

  select release_gate_result into v_gate
  from fitmatch_catalog.releases
  where id='12100000-0000-4000-8000-000000000121'::uuid;
  if not coalesce((v_gate->>'eligible')::boolean,false) then
    raise exception '121_activation_gate_not_eligible:%',v_gate;
  end if;

  select
    count(*) filter(where classification_status='confirmed'),
    count(*) filter(where classification_status='review_required'),
    count(*) filter(where classification_status='not_comparable')
  into v_confirmed,v_review,v_not_comparable
  from fitmatch_catalog.current_product_classifications;

  if v_confirmed<>1421 or v_review<>0 or v_not_comparable<>187
  then
    raise exception '121_current_view_failed:c=%,r=%,n=%',
      v_confirmed,v_review,v_not_comparable;
  end if;

  if (select count(*)
      from fitmatch_catalog.product_classification_history h
      join fitmatch_catalog.products p on p.id=h.product_id
      where h.is_current
        and h.mapping_release_id='12100000-0000-4000-8000-000000000121'::uuid
        and h.taxonomy_policy_version='db-classifier-2026-08-26-final'
        and h.input_fingerprint=p.input_fingerprint)<>1608
  then
    raise exception '121_runtime_history_reuse_failed';
  end if;

  if (select count(*)
      from fitmatch_catalog.product_classification_history h
      join fitmatch_121_pre_history old on old.id=h.id
      where not h.is_current)<>1608
  then
    raise exception '121_pre_history_preservation_failed';
  end if;

  if exists (
    select 1
    from fitmatch_catalog.product_classification_history h
    join fitmatch_vnext.products v on v.id=h.product_id
    where h.is_current and v.product_structure_code='SET'
      and h.classification_status<>'not_comparable'
  ) then
    raise exception '121_postflight_set_leak';
  end if;

  if not exists (
    select 1
    from fitmatch_catalog.product_classification_history h
    join fitmatch_catalog.products p on p.id=h.product_id
    where h.is_current and p.source='zara'
      and p.external_product_id='545427337'
      and h.classification_status='confirmed'
      and h.garment_type_code='jacket'
  ) then
    raise exception '121_postflight_zara_jacket_failed';
  end if;
end
$postflight$;

commit;;
