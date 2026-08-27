-- CONTROLLED PRODUCTION ARTIFACT.
-- One atomic v4 cutover. Requires migrations 113--118, a gated inactive final
-- candidate, and the gated inactive rollback successor. No history backfill.

begin;

set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtext('fitmatch:release-activation'));

create temporary table fitmatch_activation_guard(
  history_count bigint not null,
  current_history_count bigint not null,
  decision_count bigint not null,
  active_release_id uuid not null
) on commit drop;

do $guard$
declare
  v_candidate_gate jsonb;
  v_successor_gate jsonb;
  v_decision_preimage_checksum text;
begin
  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or not exists (
      select 1 from fitmatch_catalog.releases
      where id='65d72393-4a40-4e99-b701-fdc1ff865774'::uuid
        and status='active'
        and release_key=
          'fitmatch-active-with-zara-official-tree-2026-08-13-v1__zara-sample30-2026-08-21'
        and bundle_checksum=
          'c996dacd2c91d12b80ae36fb215001d8fad4d5ef8cbfde762f5248cd8f22fbda'
        and app_taxonomy_checksum=
          '123c693fc38c01d8edf877dbe9b651a6c40451a06752eed4bca3d14c2ac3bd57'
        and expected_mapping_count=3492
    )
  then
    raise exception 'activation_active_release_preimage_mismatch';
  end if;

  perform 1 from fitmatch_catalog.releases
  where id in (
    '65d72393-4a40-4e99-b701-fdc1ff865774'::uuid,
    '11800000-0000-4000-8000-000000000118'::uuid,
    '11800000-0000-4000-8000-00000000b001'::uuid
  ) for update;
  if not found or (
    select count(*) from fitmatch_catalog.releases
    where id in (
      '65d72393-4a40-4e99-b701-fdc1ff865774'::uuid,
      '11800000-0000-4000-8000-000000000118'::uuid,
      '11800000-0000-4000-8000-00000000b001'::uuid
    )
  )<>3 then
    raise exception 'activation_release_lock_set_incomplete';
  end if;

  v_candidate_gate:=fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-000000000118'::uuid
  );
  v_successor_gate:=fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-00000000b001'::uuid
  );
  if not coalesce((v_candidate_gate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_candidate_gate->'blockers','[]'::jsonb))<>0
  then raise exception 'activation_candidate_gate_failed:%',v_candidate_gate; end if;
  if not coalesce((v_successor_gate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_successor_gate->'blockers','[]'::jsonb))<>0
  then raise exception 'activation_rollback_successor_gate_failed:%',v_successor_gate; end if;

  if (select count(*) from fitmatch_catalog.products)<>1608
    or (select count(distinct(source,external_product_id))
        from fitmatch_catalog.products)<>1608
    or (select encode(sha256(convert_to(string_agg(
          source||E'\t'||external_product_id||E'\t'||input_fingerprint,
          E'\n' order by source,external_product_id)||E'\n','UTF8')),'hex')
        from fitmatch_catalog.products)<>
      'c1ed8a45c6548149b1b434c3551a4a674b41e627a642f6ed72db7ea55bee061a'
  then raise exception 'activation_product_snapshot_drift'; end if;

  select encode(sha256(convert_to(string_agg(
    decision.source||E'\t'||decision.external_product_id||E'\t'||
      decision.xmin::text,E'\n' order by decision.source,
      decision.external_product_id)||E'\n','UTF8')),'hex')
  into v_decision_preimage_checksum
  from fitmatch_catalog.product_classification_decisions decision
  join fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
    manifest using(source,external_product_id);
  if (select count(*)
      from fitmatch_catalog.product_classification_decisions decision
      join fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
        manifest using(source,external_product_id))<>121
    or v_decision_preimage_checksum<>
      '9d15941dd7fc4dd2221f76c9d2392ff4676474cea6f8e10602d1f1dbd79e25d8'
  then
    raise exception 'activation_decision_preimage_drift:%',
      v_decision_preimage_checksum;
  end if;

  insert into fitmatch_activation_guard
  select
    (select count(*) from fitmatch_catalog.product_classification_history),
    (select count(*) from fitmatch_catalog.product_classification_history
      where is_current),
    (select count(*) from fitmatch_catalog.product_classification_decisions),
    (select id from fitmatch_catalog.releases where status='active');
end
$guard$;

insert into fitmatch_catalog.product_classification_decisions(
  source,external_product_id,product_name,source_category_path,
  input_fingerprint,category_code,detail_code,comparison_family,length_type,
  requires_user_confirmation,release_id,decision_version,evidence,
  garment_type_code,authority_status
)
select source,external_product_id,product_name,source_category_path,
  input_fingerprint,category_code,detail_code,family_code,length_code,
  requires_user_confirmation,
  '11800000-0000-4000-8000-000000000118'::uuid,
  decision_version,evidence,garment_type_code,authority_status
from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
on conflict(source,external_product_id) do update set
  product_name=excluded.product_name,
  source_category_path=excluded.source_category_path,
  input_fingerprint=excluded.input_fingerprint,
  category_code=excluded.category_code,
  detail_code=excluded.detail_code,
  comparison_family=excluded.comparison_family,
  length_type=excluded.length_type,
  requires_user_confirmation=excluded.requires_user_confirmation,
  release_id=excluded.release_id,
  decision_version=excluded.decision_version,
  evidence=excluded.evidence,
  garment_type_code=excluded.garment_type_code,
  authority_status=excluded.authority_status,
  updated_at=now();

do $decision_check$
begin
  if (select count(*) from fitmatch_catalog.product_classification_decisions)<>
      (select decision_count from fitmatch_activation_guard)
    or (select count(*)
      from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
        manifest
      join fitmatch_catalog.product_classification_decisions decision
        using(source,external_product_id)
      where decision.product_name is not distinct from manifest.product_name
        and decision.source_category_path is not distinct from
          manifest.source_category_path
        and decision.input_fingerprint is not distinct from
          manifest.input_fingerprint
        and decision.category_code is not distinct from manifest.category_code
        and decision.detail_code is not distinct from manifest.detail_code
        and decision.garment_type_code is not distinct from
          manifest.garment_type_code
        and decision.comparison_family is not distinct from manifest.family_code
        and decision.length_type is not distinct from manifest.length_code
        and decision.requires_user_confirmation is not distinct from
          manifest.requires_user_confirmation
        and decision.release_id=
          '11800000-0000-4000-8000-000000000118'::uuid
        and decision.decision_version is not distinct from
          manifest.decision_version
        and decision.evidence is not distinct from manifest.evidence
        and decision.authority_status is not distinct from
          manifest.authority_status)<>121
  then raise exception 'activation_decision_manifest_materialization_failed'; end if;
end
$decision_check$;

-- Recorder contract stays v2. Only the v4 resolver's explicit method
-- vocabulary is added; validation, tuple checks, and history semantics remain.
create or replace function fitmatch_catalog.runtime_record_product_classification_v2(
  p_product_id uuid,p_resolution jsonb
) returns uuid
language plpgsql
security invoker
set search_path=''
as $function$
declare
  v_product fitmatch_catalog.products%rowtype;
  v_history_id uuid;
  v_status text:=coalesce(nullif(p_resolution->>'classification_status',''),
    'unclassified');
  v_method text:=coalesce(nullif(p_resolution->>'classification_method',''),
    'unknown');
  v_confirmation boolean:=coalesce(
    (p_resolution->>'requires_user_confirmation')::boolean,
    v_status<>'confirmed');
  v_release_id uuid:=nullif(p_resolution->>'mapping_release_id','')::uuid;
  v_decision_version text:=coalesce(
    nullif(p_resolution->>'decision_version',''),'classification-tuple-v1');
  v_confidence numeric:=nullif(p_resolution->>'confidence','')::numeric;
  v_tuple_validation jsonb;
  v_evidence jsonb;
begin
  if jsonb_typeof(coalesce(p_resolution,'{}'::jsonb))<>'object' then
    raise exception using errcode='22023',
      message='classification_resolution_must_be_object';
  end if;
  select product.* into v_product
  from fitmatch_catalog.products product
  where product.id=p_product_id for update;
  if not found then
    raise exception using errcode='P0002',message='product_not_found';
  end if;
  if v_status not in (
    'confirmed','review_required','not_comparable','unclassified'
  ) then
    raise exception using errcode='22023',message='invalid_classification_status';
  end if;
  if v_method not in (
    'canonical_product_decision','category_mapping','product_classifier',
    'manual_review','user_override','migration','unknown',
    'structured_exclusion','verified_exclusion_profile',
    'structured_discriminator','verified_path_profile',
    'verified_name_signature_profile'
  ) then
    raise exception using errcode='22023',message='invalid_classification_method';
  end if;
  if v_confidence is not null and (v_confidence<0 or v_confidence>1) then
    raise exception using errcode='22023',message='invalid_confidence';
  end if;
  v_tuple_validation:=fitmatch_catalog.runtime_validate_classification_tuple_v1(
    p_resolution->>'category_code',p_resolution->>'detail_code',
    p_resolution->>'garment_type_code',p_resolution->>'family_code',
    p_resolution->>'length_code',p_resolution->>'body_length_code');
  if v_status='confirmed' and (
    v_confirmation or
    not coalesce((v_tuple_validation->>'valid')::boolean,false)
  ) then
    raise exception using errcode='22023',
      message='confirmed_classification_tuple_invalid',
      detail=v_tuple_validation::text;
  end if;
  v_evidence:=case when jsonb_typeof(p_resolution->'evidence')='object'
    then p_resolution->'evidence' else '{}'::jsonb end||jsonb_build_object(
      'tuple_validation',v_tuple_validation,
      'authority_status',p_resolution->>'authority_status',
      'authority_conflicts',coalesce(
        p_resolution->'authority_conflicts','[]'::jsonb),
      'recorder_contract_version','classification-recorder-v2');
  update fitmatch_catalog.product_classification_history
  set is_current=false,superseded_at=now()
  where product_id=p_product_id and is_current;
  insert into fitmatch_catalog.product_classification_history(
    product_id,input_fingerprint,category_code,detail_code,garment_type_code,
    comparison_family_code,length_code,body_length_code,
    classification_status,classification_method,confidence,
    requires_user_confirmation,taxonomy_policy_version,mapping_release_id,
    decision_version,evidence,reviewed_by,reviewed_at
  ) values (
    p_product_id,v_product.input_fingerprint,
    nullif(p_resolution->>'category_code',''),
    nullif(p_resolution->>'detail_code',''),
    nullif(p_resolution->>'garment_type_code',''),
    nullif(p_resolution->>'family_code',''),
    nullif(p_resolution->>'length_code',''),
    nullif(p_resolution->>'body_length_code',''),
    v_status,v_method,v_confidence,v_confirmation,
    nullif(p_resolution->>'classifier_policy_version',''),v_release_id,
    v_decision_version,v_evidence,
    nullif(p_resolution->>'reviewed_by','')::uuid,
    nullif(p_resolution->>'reviewed_at','')::timestamptz
  ) returning id into v_history_id;
  if (select count(*) from fitmatch_catalog.product_classification_history
      where product_id=p_product_id and is_current)<>1 then
    raise exception using errcode='23514',
      message='product_current_classification_invariant_failed';
  end if;
  return v_history_id;
end
$function$;


create or replace function public.fitmatch_find_reference_candidates(
  p_target_product_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=(select auth.uid());
  v_release_id uuid;
  v_classifier_version text;
  v_target fitmatch_catalog.product_classification_history%rowtype;
  v_product fitmatch_catalog.products%rowtype;
  v_candidates jsonb;
  v_auto_count integer;
  v_manual_count integer;
  v_structural_count integer;
begin
  if v_user_id is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  select id,validation_report#>>'{runtime_policy_contract,classifier_policy_version}'
  into v_release_id,v_classifier_version
  from fitmatch_catalog.releases where status='active';
  if v_release_id is null or v_classifier_version is null then
    raise exception using errcode='55000',message='active_v4_contract_missing';
  end if;
  select * into v_product from fitmatch_catalog.products
  where id=p_target_product_id;
  if not found then
    raise exception using errcode='P0002',message='target_product_not_found';
  end if;
  select * into v_target
  from fitmatch_catalog.product_classification_history
  where product_id=p_target_product_id and is_current
    and taxonomy_policy_version=v_classifier_version;
  if not found or v_target.classification_status<>'confirmed' then
    return jsonb_build_object(
      'state','target_classification_required','automatic_count',0,
      'manual_count',0,'structural_count',0,'candidates','[]'::jsonb,
      'policy_version','classification-comparison-v4',
      'active_release_id',v_release_id);
  end if;
  with evaluated as (
    select closet.id,closet.product_name,closet.size_name,closet.gender,
      closet.is_reference,closet.updated_at,
      coalesce(override.category_code,closet.canonical_category_code,
        closet.app_category) category_code,
      coalesce(override.detail_code,closet.canonical_detail_code,
        closet.app_detail_category) detail_code,
      coalesce(override.comparison_family_code,
        closet.comparison_family_code) family_code,
      coalesce(override.length_code,
        closet.comparison_length_code) length_code,
      coalesce(override.body_length_code,
        closet.comparison_body_length_code) body_length_code,
      garment.code garment_type_code
    from public.closet_items closet
    left join public.closet_item_classification_overrides override
      on override.closet_item_id=closet.id
     and override.user_id=closet.user_id
    left join public.garment_types garment
      on garment.id=closet.garment_type_id and garment.is_active
    where closet.user_id=v_user_id and closet.deleted_at is null
      and coalesce(override.comparison_family_code,
        closet.comparison_family_code) is not null
  ),compat as (
    select evaluated.*,
      fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
        evaluated.category_code,evaluated.gender,evaluated.family_code,
        evaluated.detail_code,evaluated.length_code,
        evaluated.body_length_code,v_target.category_code,v_product.audience,
        v_target.comparison_family_code,v_target.detail_code,
        v_target.length_code,v_target.body_length_code,
        evaluated.garment_type_code,v_target.garment_type_code,false,
        v_release_id) automatic,
      fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
        evaluated.category_code,evaluated.gender,evaluated.family_code,
        evaluated.detail_code,evaluated.length_code,
        evaluated.body_length_code,v_target.category_code,v_product.audience,
        v_target.comparison_family_code,v_target.detail_code,
        v_target.length_code,v_target.body_length_code,
        evaluated.garment_type_code,v_target.garment_type_code,true,
        v_release_id) manual
    from evaluated
  ),measured as (
    select compat.*,
      fitmatch_catalog.runtime_closet_measurement_overlap(
        compat.id,p_target_product_id,
        compat.manual->'excluded_measurements') overlap_count
    from compat
  ),ranked as (
    select *,
      coalesce((automatic->>'allowed')::boolean,false)
        and automatic->>'level'='direct'
        and overlap_count>=coalesce(nullif(
          automatic->>'minimum_common_measurements','')::integer,2)
        as automatic_ready,
      coalesce((manual->>'allowed')::boolean,false)
        and overlap_count>=coalesce(nullif(
          manual->>'minimum_common_measurements','')::integer,2)
        as manual_ready,
      coalesce((manual->>'allowed')::boolean,false) as structurally_compatible
    from measured
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'closet_item_id',id,'product_name',product_name,'size_name',size_name,
      'is_reference',is_reference,'automatic_ready',automatic_ready,
      'manual_ready',manual_ready,'measurement_overlap_count',overlap_count,
      'automatic_compatibility',automatic,'manual_compatibility',manual)
      order by automatic_ready desc,manual_ready desc,is_reference desc,
        updated_at desc,id),'[]'::jsonb),
    count(*) filter(where automatic_ready),
    count(*) filter(where manual_ready),
    count(*) filter(where structurally_compatible)
  into v_candidates,v_auto_count,v_manual_count,v_structural_count
  from ranked where automatic_ready or manual_ready or structurally_compatible;
  return jsonb_build_object(
    'state',case when v_auto_count>0 then 'automatic'
      when v_manual_count>0 then 'manual_selection'
      when v_structural_count>0 then 'measurements_required'
      else 'no_compatible_garment' end,
    'automatic_count',v_auto_count,'manual_count',v_manual_count,
    'structural_count',v_structural_count,'candidates',v_candidates,
    'policy_version','classification-comparison-v4',
    'active_release_id',v_release_id);
end
$function$;

create or replace function public.fitmatch_begin_comparison(
  p_reference_item_id uuid,p_target_product_id uuid,
  p_allow_extended boolean default false,p_client_history_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=(select auth.uid());
  v_release_id uuid;
  v_classifier_version text;
  v_reference record;
  v_target fitmatch_catalog.product_classification_history%rowtype;
  v_product fitmatch_catalog.products%rowtype;
  v_existing public.comparison_runs%rowtype;
  v_compatibility jsonb;
  v_run_id uuid;
  v_status text;
begin
  if v_user_id is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  if p_client_history_id is null then
    raise exception using errcode='22023',message='client_history_id_required';
  end if;
  select id,validation_report#>>'{runtime_policy_contract,classifier_policy_version}'
  into v_release_id,v_classifier_version
  from fitmatch_catalog.releases where status='active';
  if v_release_id is null or v_classifier_version is null then
    raise exception using errcode='55000',message='active_v4_contract_missing';
  end if;
  select * into v_existing from public.comparison_runs
  where user_id=v_user_id and client_history_id=p_client_history_id;
  if found then
    if v_existing.reference_item_id<>p_reference_item_id
      or v_existing.target_product_id<>p_target_product_id then
      raise exception using errcode='22023',
        message='client_history_identity_conflict';
    end if;
    return jsonb_build_object('run_id',v_existing.id,'status',v_existing.status,
      'compatibility',coalesce(
        v_existing.input_snapshot->'compatibility','{}'::jsonb));
  end if;
  select closet.id,closet.gender,
    coalesce(override.category_code,closet.canonical_category_code,
      closet.app_category) category_code,
    coalesce(override.detail_code,closet.canonical_detail_code,
      closet.app_detail_category) detail_code,
    coalesce(override.comparison_family_code,
      closet.comparison_family_code) family_code,
    coalesce(override.length_code,
      closet.comparison_length_code) length_code,
    coalesce(override.body_length_code,
      closet.comparison_body_length_code) body_length_code,
    garment.code garment_type_code
  into v_reference
  from public.closet_items closet
  left join public.closet_item_classification_overrides override
    on override.closet_item_id=closet.id and override.user_id=closet.user_id
  left join public.garment_types garment
    on garment.id=closet.garment_type_id and garment.is_active
  where closet.id=p_reference_item_id and closet.user_id=v_user_id
    and closet.deleted_at is null;
  if not found then
    raise exception using errcode='P0002',message='reference_item_not_found';
  end if;
  select * into v_product from fitmatch_catalog.products
  where id=p_target_product_id;
  if not found then
    raise exception using errcode='P0002',message='target_product_not_found';
  end if;
  select * into v_target
  from fitmatch_catalog.product_classification_history
  where product_id=p_target_product_id and is_current
    and taxonomy_policy_version=v_classifier_version;
  if not found or v_target.classification_status<>'confirmed' then
    v_compatibility:=jsonb_build_object(
      'allowed',false,'level','incompatible',
      'reason','target_classification_not_confirmed',
      'excluded_measurements','[]'::jsonb,'release_id',v_release_id);
  elsif v_reference.family_code is null
    or v_reference.garment_type_code is null then
    v_compatibility:=jsonb_build_object(
      'allowed',false,'level','incompatible',
      'reason','reference_classification_not_confirmed',
      'excluded_measurements','[]'::jsonb,'release_id',v_release_id);
  else
    v_compatibility:=fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
      v_reference.category_code,v_reference.gender,v_reference.family_code,
      v_reference.detail_code,v_reference.length_code,
      v_reference.body_length_code,v_target.category_code,v_product.audience,
      v_target.comparison_family_code,v_target.detail_code,
      v_target.length_code,v_target.body_length_code,
      v_reference.garment_type_code,v_target.garment_type_code,
      p_allow_extended,v_release_id);
    if coalesce((v_compatibility->>'allowed')::boolean,false)
      and fitmatch_catalog.runtime_closet_measurement_overlap(
        p_reference_item_id,p_target_product_id,
        v_compatibility->'excluded_measurements')<coalesce(nullif(
          v_compatibility->>'minimum_common_measurements','')::integer,2)
    then
      v_compatibility:=v_compatibility||jsonb_build_object(
        'allowed',false,'level','insufficient_data',
        'reason','insufficient_common_measurements');
    end if;
  end if;
  v_status:=case when coalesce(
    (v_compatibility->>'allowed')::boolean,false) then 'pending'
    else 'blocked' end;
  insert into public.comparison_runs(
    user_id,client_history_id,reference_item_id,target_product_id,status,
    comparison_level,block_reason,comparison_policy_version,input_snapshot,
    completed_at
  ) values(
    v_user_id,p_client_history_id,p_reference_item_id,p_target_product_id,
    v_status,v_compatibility->>'level',v_compatibility->>'reason',
    'classification-comparison-v4',jsonb_build_object(
      'compatibility',v_compatibility,
      'client_history_id',p_client_history_id,
      'allow_extended',p_allow_extended,
      'active_release_id',v_release_id),
    case when v_status='blocked' then now() else null end
  ) returning id into v_run_id;
  return jsonb_build_object('run_id',v_run_id,'status',v_status,
    'compatibility',v_compatibility);
end
$function$;


create or replace function public.fitmatch_resolve_product(
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=(select auth.uid());
  v_source text:=lower(btrim(coalesce(p_payload->>'source','')));
  v_external_id text:=btrim(coalesce(p_payload->>'external_product_id',''));
  v_name text:=btrim(coalesce(p_payload->>'product_name',''));
  v_path text:=nullif(btrim(coalesce(p_payload->>'source_category_path','')),'');
  v_audience text:=nullif(btrim(coalesce(p_payload->>'audience','')),'');
  v_codes text[]:=case
    when jsonb_typeof(p_payload->'source_category_codes')='array'
      then array(select jsonb_array_elements_text(
        p_payload->'source_category_codes'))
    else '{}'::text[] end;
  v_fingerprint text;
  v_release_id uuid;
  v_classifier_version text;
  v_product fitmatch_catalog.products%rowtype;
  v_history fitmatch_catalog.product_classification_history%rowtype;
  v_resolution jsonb;
  v_request_id uuid;
  v_category_evidence_matches boolean;
begin
  if v_user_id is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  if jsonb_typeof(p_payload)<>'object'
    or v_source !~ '^[a-z][a-z0-9_]*$'
    or v_external_id='' or length(v_external_id)>200
    or v_name='' or length(v_name)>1000
    or (p_payload?'source_category_codes'
      and jsonb_typeof(p_payload->'source_category_codes')<>'array')
  then
    raise exception using errcode='22023',message='invalid_product_payload';
  end if;
  select id,validation_report#>>'{runtime_policy_contract,classifier_policy_version}'
  into v_release_id,v_classifier_version
  from fitmatch_catalog.releases where status='active';
  if v_release_id is null or v_classifier_version is null then
    raise exception using errcode='55000',message='active_v4_contract_missing';
  end if;
  v_fingerprint:=fitmatch_catalog.runtime_product_fingerprint(v_name,v_path);
  select * into v_product from fitmatch_catalog.products
  where source=v_source and external_product_id=v_external_id;
  v_category_evidence_matches:=found
    and (v_audience is null
      or upper(coalesce(v_product.audience,''))=upper(v_audience))
    and (cardinality(v_codes)=0 or v_product.source_category_codes=v_codes);
  if found and v_product.input_fingerprint=v_fingerprint
    and v_category_evidence_matches then
    select * into v_history
    from fitmatch_catalog.product_classification_history
    where product_id=v_product.id and input_fingerprint=v_fingerprint
      and is_current and taxonomy_policy_version=v_classifier_version;
    if found then
      return jsonb_build_object(
        'product_id',v_product.id,'intake_request_id',null,
        'catalog_state','current','category_evidence_matches',true,
        'active_release_id',v_release_id,'authority_persisted',true,
        'classification',jsonb_build_object(
          'classification_id',v_history.id,
          'category_code',v_history.category_code,
          'detail_code',v_history.detail_code,
          'garment_type_code',v_history.garment_type_code,
          'family_code',v_history.comparison_family_code,
          'length_code',v_history.length_code,
          'body_length_code',v_history.body_length_code,
          'status',v_history.classification_status,
          'method',v_history.classification_method,
          'requires_user_confirmation',v_history.requires_user_confirmation,
          'taxonomy_policy_version',v_history.taxonomy_policy_version,
          'decision_version',v_history.decision_version,
          'evidence',v_history.evidence),
        'comparison_ready',v_history.classification_status='confirmed'
          and exists(
            select 1 from fitmatch_catalog.product_variants variant
            join fitmatch_catalog.product_sizes size
              on size.variant_id=variant.id and size.is_active
            join fitmatch_catalog.product_measurements measurement
              on measurement.product_size_id=size.id
             and measurement.is_comparable
            where variant.product_id=v_product.id and variant.is_active));
    end if;
  end if;
  v_resolution:=fitmatch_catalog.runtime_resolve_product_classification_v4(
    v_source,v_external_id,v_name,coalesce(v_path,''),p_payload,v_release_id);
  insert into public.product_intake_requests(
    user_id,source,external_product_id,input_fingerprint,submitted_payload
  ) values(v_user_id,v_source,v_external_id,v_fingerprint,p_payload)
  on conflict(user_id,source,external_product_id,input_fingerprint)
  do update set submitted_payload=excluded.submitted_payload,updated_at=now()
  returning id into v_request_id;
  return jsonb_build_object(
    'product_id',v_product.id,'intake_request_id',v_request_id,
    'catalog_state',case when v_product.id is null then 'new' else 'changed' end,
    'category_evidence_matches',coalesce(v_category_evidence_matches,false),
    'active_release_id',v_release_id,'authority_persisted',false,
    'classification',jsonb_build_object(
      'classification_id',null,
      'category_code',v_resolution->>'category_code',
      'detail_code',v_resolution->>'detail_code',
      'garment_type_code',v_resolution->>'garment_type_code',
      'family_code',v_resolution->>'family_code',
      'length_code',v_resolution->>'length_code',
      'body_length_code',v_resolution->>'body_length_code',
      'status',v_resolution->>'classification_status',
      'method',v_resolution->>'classification_method',
      'authority_status',v_resolution->>'authority_status',
      'requires_user_confirmation',coalesce(
        (v_resolution->>'requires_user_confirmation')::boolean,true),
      'taxonomy_policy_version',v_resolution->>'classifier_policy_version',
      'decision_version',v_resolution->>'decision_version',
      'evidence',v_resolution->'evidence',
      'authority_conflicts',coalesce(
        v_resolution->'authority_conflicts','[]'::jsonb)),
    'comparison_ready',false);
end
$function$;

create or replace function public.fitmatch_get_product_runtime(
  p_payload jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=(select auth.uid());
  v_source text:=lower(btrim(coalesce(p_payload->>'source','')));
  v_external_id text:=btrim(coalesce(p_payload->>'external_product_id',''));
  v_name text:=btrim(coalesce(p_payload->>'product_name',''));
  v_path text:=nullif(btrim(coalesce(p_payload->>'source_category_path','')),'');
  v_audience text:=nullif(btrim(coalesce(p_payload->>'audience','')),'');
  v_codes text[]:=case
    when jsonb_typeof(p_payload->'source_category_codes')='array'
      then array(select jsonb_array_elements_text(
        p_payload->'source_category_codes'))
    else '{}'::text[] end;
  v_fingerprint text;
  v_release_id uuid;
  v_classifier_version text;
  v_product fitmatch_catalog.products%rowtype;
  v_history fitmatch_catalog.product_classification_history%rowtype;
  v_preview jsonb;
  v_active_history boolean:=false;
  v_has_sizes boolean:=false;
  v_has_measurements boolean:=false;
  v_variants jsonb;
begin
  if v_user_id is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  if jsonb_typeof(p_payload)<>'object'
    or v_source !~ '^[a-z][a-z0-9_]*$'
    or v_external_id='' or length(v_external_id)>200
    or v_name='' or length(v_name)>1000
    or (p_payload?'source_category_codes'
      and jsonb_typeof(p_payload->'source_category_codes')<>'array')
  then
    raise exception using errcode='22023',message='invalid_product_payload';
  end if;
  select id,validation_report#>>'{runtime_policy_contract,classifier_policy_version}'
  into v_release_id,v_classifier_version
  from fitmatch_catalog.releases where status='active';
  if v_release_id is null or v_classifier_version is null then
    raise exception using errcode='55000',message='active_v4_contract_missing';
  end if;
  v_fingerprint:=fitmatch_catalog.runtime_product_fingerprint(v_name,v_path);
  select * into v_product from fitmatch_catalog.products
  where source=v_source and external_product_id=v_external_id;
  if not found or v_product.input_fingerprint<>v_fingerprint
    or (v_audience is not null
      and upper(coalesce(v_product.audience,''))<>upper(v_audience))
    or (cardinality(v_codes)>0 and v_product.source_category_codes<>v_codes)
  then
    raise exception using errcode='P0002',message='product_evidence_mismatch';
  end if;
  select * into v_history
  from fitmatch_catalog.product_classification_history
  where product_id=v_product.id and is_current
    and input_fingerprint=v_fingerprint
    and taxonomy_policy_version=v_classifier_version;
  v_active_history:=found;
  if not v_active_history then
    v_preview:=fitmatch_catalog.runtime_resolve_product_classification_v4(
      v_source,v_external_id,v_name,coalesce(v_path,''),p_payload,v_release_id);
  end if;
  select exists(
    select 1 from fitmatch_catalog.product_variants variant
    join fitmatch_catalog.product_sizes size
      on size.variant_id=variant.id and size.is_active
    where variant.product_id=v_product.id and variant.is_active
  ),exists(
    select 1 from fitmatch_catalog.product_variants variant
    join fitmatch_catalog.product_sizes size
      on size.variant_id=variant.id and size.is_active
    join fitmatch_catalog.product_measurements measurement
      on measurement.product_size_id=size.id
    where variant.product_id=v_product.id and variant.is_active
      and measurement.is_comparable and measurement.measurement_code is not null
      and measurement.normalized_value is not null
  ) into v_has_sizes,v_has_measurements;
  select coalesce(jsonb_agg(jsonb_build_object(
    'variant_id',variant.id,'external_variant_id',variant.external_variant_id,
    'variant_name',variant.variant_name,'color_code',variant.color_code,
    'color_name',variant.color_name,'sizes',coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_size_id',size.id,'external_size_id',size.external_size_id,
        'size_label',size.size_label,
        'normalized_size_label',size.normalized_size_label,
        'display_order',size.display_order,'stock_status',size.stock_status,
        'measurements',coalesce((select jsonb_agg(jsonb_build_object(
          'measurement_code',measurement.measurement_code,
          'raw_label',measurement.raw_label,'raw_value',measurement.raw_value,
          'raw_unit',measurement.raw_unit,
          'normalized_value',measurement.normalized_value,
          'normalized_unit',measurement.normalized_unit,
          'comparison_basis',measurement.comparison_basis,
          'is_comparable',measurement.is_comparable,
          'exclusion_reason',measurement.exclusion_reason,
          'policy_version',measurement.policy_version)
          order by measurement.measurement_code nulls last,
            measurement.raw_label,measurement.id)
          from fitmatch_catalog.product_measurements measurement
          where measurement.product_size_id=size.id),'[]'::jsonb))
        order by size.display_order,size.normalized_size_label,size.id)
      from fitmatch_catalog.product_sizes size
      where size.variant_id=variant.id and size.is_active),'[]'::jsonb))
    order by variant.color_code nulls last,variant.variant_name nulls last,
      variant.id),'[]'::jsonb)
  into v_variants
  from fitmatch_catalog.product_variants variant
  where variant.product_id=v_product.id and variant.is_active;
  return jsonb_build_object(
    'runtime_state',case
      when not v_active_history and v_preview->>'classification_status'=
        'not_comparable' then 'not_comparable'
      when not v_active_history and v_preview->>'classification_status'=
        'confirmed' then 'classification_promotion_required'
      when not v_active_history then 'classification_required'
      when v_history.classification_status='not_comparable' then 'not_comparable'
      when v_history.classification_status<>'confirmed' then 'classification_required'
      when not v_has_sizes then 'sizes_required'
      when not v_has_measurements then 'measurements_required'
      else 'ready' end,
    'comparison_ready',v_active_history
      and v_history.classification_status='confirmed' and v_has_measurements,
    'active_release_id',v_release_id,
    'authority_persisted',v_active_history,
    'product',jsonb_build_object(
      'product_id',v_product.id,'source',v_product.source,
      'external_product_id',v_product.external_product_id,
      'product_name',v_product.product_name,
      'canonical_url',v_product.canonical_url,'audience',v_product.audience,
      'source_category_path',v_product.source_category_path,
      'source_category_codes',to_jsonb(v_product.source_category_codes),
      'image_url',v_product.image_url,'lifecycle_status',v_product.lifecycle_status,
      'input_fingerprint',v_product.input_fingerprint),
    'classification',case when v_active_history then jsonb_build_object(
      'classification_id',v_history.id,'category_code',v_history.category_code,
      'detail_code',v_history.detail_code,
      'garment_type_code',v_history.garment_type_code,
      'family_code',v_history.comparison_family_code,
      'length_code',v_history.length_code,
      'body_length_code',v_history.body_length_code,
      'status',v_history.classification_status,
      'method',v_history.classification_method,
      'confidence',v_history.confidence,
      'requires_user_confirmation',v_history.requires_user_confirmation,
      'taxonomy_policy_version',v_history.taxonomy_policy_version,
      'decision_version',v_history.decision_version,'evidence',v_history.evidence)
    else jsonb_build_object(
      'classification_id',null,'category_code',v_preview->>'category_code',
      'detail_code',v_preview->>'detail_code',
      'garment_type_code',v_preview->>'garment_type_code',
      'family_code',v_preview->>'family_code',
      'length_code',v_preview->>'length_code',
      'body_length_code',v_preview->>'body_length_code',
      'status',v_preview->>'classification_status',
      'method',v_preview->>'classification_method',
      'confidence',nullif(v_preview->>'confidence','')::numeric,
      'requires_user_confirmation',coalesce(
        (v_preview->>'requires_user_confirmation')::boolean,true),
      'taxonomy_policy_version',v_preview->>'classifier_policy_version',
      'decision_version',v_preview->>'decision_version',
      'evidence',v_preview->'evidence') end,
    'variants',v_variants);
end
$function$;


create or replace function fitmatch_catalog.runtime_resolve_and_promote_product(
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $function$
declare
  v_source text:=lower(btrim(coalesce(p_payload->>'source','')));
  v_external_id text:=btrim(coalesce(p_payload->>'external_product_id',''));
  v_product_id uuid;
  v_product fitmatch_catalog.products%rowtype;
  v_release_id uuid;
  v_classifier_version text;
  v_resolution jsonb;
  v_history_id uuid;
begin
  if jsonb_typeof(p_payload)<>'object' or v_source='' or v_external_id='' then
    raise exception using errcode='22023',message='invalid_product_payload';
  end if;
  select id,validation_report#>>'{runtime_policy_contract,classifier_policy_version}'
  into v_release_id,v_classifier_version
  from fitmatch_catalog.releases where status='active';
  if v_release_id is null or v_classifier_version is null then
    raise exception using errcode='55000',message='active_v4_contract_missing';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    v_source||E'\n'||v_external_id,0));
  v_product_id:=fitmatch_catalog.runtime_upsert_product(p_payload);
  select * into v_product from fitmatch_catalog.products where id=v_product_id;
  select id into v_history_id
  from fitmatch_catalog.product_classification_history
  where product_id=v_product_id and is_current
    and input_fingerprint=v_product.input_fingerprint
    and taxonomy_policy_version=v_classifier_version;
  if v_history_id is null then
    v_resolution:=fitmatch_catalog.runtime_resolve_product_classification_v4(
      v_product.source,v_product.external_product_id,v_product.product_name,
      coalesce(v_product.source_category_path,''),p_payload,v_release_id);
    v_history_id:=fitmatch_catalog.runtime_record_product_classification_v2(
      v_product_id,v_resolution);
  else
    select jsonb_build_object(
      'category_code',category_code,'detail_code',detail_code,
      'garment_type_code',garment_type_code,
      'family_code',comparison_family_code,'length_code',length_code,
      'body_length_code',body_length_code,
      'classification_status',classification_status,
      'classification_method',classification_method,
      'authority_status',evidence->>'authority_status',
      'confidence',confidence,
      'requires_user_confirmation',requires_user_confirmation,
      'mapping_release_id',mapping_release_id,
      'classifier_policy_version',taxonomy_policy_version,
      'decision_version',decision_version,'evidence',evidence
    ) into v_resolution
    from fitmatch_catalog.product_classification_history where id=v_history_id;
  end if;
  update public.product_intake_requests
  set status=case when v_resolution->>'classification_status' in(
      'confirmed','not_comparable') then 'resolved' else 'pending' end,
    resolved_product_id=v_product_id,resolution=v_resolution,
    resolved_at=case when v_resolution->>'classification_status' in(
      'confirmed','not_comparable') then now() else null end,
    updated_at=now()
  where source=v_source and external_product_id=v_external_id
    and input_fingerprint=v_product.input_fingerprint;
  return jsonb_build_object(
    'product_id',v_product_id,'classification_id',v_history_id,
    'catalog_state','promoted','classification',v_resolution,
    'active_release_id',v_release_id,
    'comparison_ready',v_resolution->>'classification_status'='confirmed'
      and exists(
        select 1 from fitmatch_catalog.product_variants variant
        join fitmatch_catalog.product_sizes size
          on size.variant_id=variant.id and size.is_active
        join fitmatch_catalog.product_measurements measurement
          on measurement.product_size_id=size.id and measurement.is_comparable
        where variant.product_id=v_product_id and variant.is_active));
end
$function$;

revoke all on function
  fitmatch_catalog.runtime_record_product_classification_v2(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function
  fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)
  from public,anon,authenticated;
grant execute on function
  fitmatch_catalog.runtime_record_product_classification_v2(uuid,jsonb),
  fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)
  to service_role;
revoke all on function public.fitmatch_resolve_product(jsonb)
  from public,anon;
revoke all on function public.fitmatch_get_product_runtime(jsonb)
  from public,anon;
revoke all on function public.fitmatch_find_reference_candidates(uuid)
  from public,anon;
revoke all on function
  public.fitmatch_begin_comparison(uuid,uuid,boolean,uuid)
  from public,anon;
grant execute on function public.fitmatch_resolve_product(jsonb),
  public.fitmatch_get_product_runtime(jsonb),
  public.fitmatch_find_reference_candidates(uuid),
  public.fitmatch_begin_comparison(uuid,uuid,boolean,uuid)
  to authenticated,service_role;

do $function_guard$
begin
  if not exists (
    select 1 from pg_proc function_row
    join pg_namespace schema_row on schema_row.oid=function_row.pronamespace
    where schema_row.nspname='public'
      and function_row.proname='fitmatch_process_product_observation'
      and pg_get_function_identity_arguments(function_row.oid)=
        'p_observation_id uuid'
      and pg_get_functiondef(function_row.oid) like
        '%runtime_resolve_and_promote_product%'
  ) then
    raise exception 'activation_observation_promoter_call_path_missing';
  end if;
  if exists (
    select 1 from pg_proc function_row
    join pg_namespace schema_row on schema_row.oid=function_row.pronamespace
    where (
      (schema_row.nspname='fitmatch_catalog' and function_row.proname in(
        'runtime_record_product_classification_v2',
        'runtime_resolve_and_promote_product'))
      or (schema_row.nspname='public' and function_row.proname in(
        'fitmatch_resolve_product','fitmatch_get_product_runtime',
        'fitmatch_find_reference_candidates','fitmatch_begin_comparison')))
      and pg_get_userbyid(function_row.proowner)<>'postgres'
  ) then raise exception 'activation_function_owner_regression'; end if;
  if exists (
    select 1 from pg_proc function_row
    join pg_namespace schema_row on schema_row.oid=function_row.pronamespace
    where schema_row.nspname='public'
      and function_row.proname in(
        'fitmatch_resolve_product','fitmatch_get_product_runtime',
        'fitmatch_find_reference_candidates','fitmatch_begin_comparison')
      and (not function_row.prosecdef
        or not coalesce(
          'search_path=""'=any(function_row.proconfig),false))
  ) then raise exception 'activation_public_function_security_regression'; end if;
  if has_function_privilege('anon','public.fitmatch_resolve_product(jsonb)',
      'EXECUTE')
    or has_function_privilege('anon',
      'public.fitmatch_get_product_runtime(jsonb)','EXECUTE')
    or has_function_privilege('anon',
      'public.fitmatch_find_reference_candidates(uuid)','EXECUTE')
    or has_function_privilege('anon',
      'public.fitmatch_begin_comparison(uuid,uuid,boolean,uuid)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.fitmatch_resolve_product(jsonb)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.fitmatch_get_product_runtime(jsonb)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.fitmatch_find_reference_candidates(uuid)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.fitmatch_begin_comparison(uuid,uuid,boolean,uuid)','EXECUTE')
  then raise exception 'activation_public_function_grant_regression'; end if;
end
$function_guard$;

do $pointer_switch$
begin
  update fitmatch_catalog.releases set status='retired'
  where id='65d72393-4a40-4e99-b701-fdc1ff865774'::uuid
    and status='active';
  if not found then
    raise exception 'activation_parent_retire_preimage_mismatch';
  end if;
  update fitmatch_catalog.releases
  set status='active',activated_at=now(),
      metadata=metadata||jsonb_build_object(
        'candidate_only',false,
        'production_activation_performed',true,
        'activated_from_release_id',
          '65d72393-4a40-4e99-b701-fdc1ff865774',
        'rollback_successor_release_id',
          '11800000-0000-4000-8000-00000000b001'),
      validation_report=validation_report||jsonb_build_object(
        'production_activation_performed',true,
        'activation_history_backfill_count',0)
  where id='11800000-0000-4000-8000-000000000118'::uuid
    and status='validated';
  if not found then
    raise exception 'activation_candidate_pointer_switch_failed';
  end if;
end
$pointer_switch$;

create temporary table fitmatch_activation_shadow on commit drop as
with structured as (
  select value->>'source' source,
    value->>'external_product_id' external_product_id,
    value->'structured_facts' structured_facts
  from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
  where value->>'record_type'='product_structured_fact'
)
select product.source,product.external_product_id,
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    product.source,product.external_product_id,product.product_name,
    coalesce(product.source_category_path,''),jsonb_build_object(
      'source',product.source,
      'external_product_id',product.external_product_id,
      'product_name',product.product_name,
      'source_category_path',coalesce(product.source_category_path,''),
      'source_category_codes',to_jsonb(product.source_category_codes),
      'audience',product.audience,
      'structured_facts',coalesce(structured.structured_facts,'{}'::jsonb)),
    '11800000-0000-4000-8000-000000000118'::uuid) resolution
from fitmatch_catalog.products product
left join structured using(source,external_product_id);

do $smoke$
declare
  v_release_gate jsonb;
  v_base_block jsonb;
  v_cross_allow jsonb;
begin
  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or (select id from fitmatch_catalog.releases where status='active')<>
      '11800000-0000-4000-8000-000000000118'::uuid
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id=
          '11800000-0000-4000-8000-000000000118'::uuid)<>3509
  then raise exception 'activation_active_release_postcondition_failed'; end if;
  v_release_gate:=fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-000000000118'::uuid);
  if not coalesce((v_release_gate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_release_gate->'blockers','[]'::jsonb))<>0
  then raise exception 'activation_post_switch_gate_failed:%',v_release_gate; end if;
  if (select count(*) from fitmatch_activation_shadow)<>1608
    or (select count(*) from fitmatch_activation_shadow
        where resolution->>'classification_status'='confirmed')<>348
    or (select count(*) from fitmatch_activation_shadow
        where resolution->>'classification_status'='review_required')<>1113
    or (select count(*) from fitmatch_activation_shadow
        where resolution->>'classification_status'='not_comparable')<>147
    or exists(select 1 from fitmatch_activation_shadow
      where resolution->>'classification_status'='confirmed'
        and not coalesce((resolution#>>'{tuple_validation,valid}')::boolean,false))
  then raise exception 'activation_full_shadow_distribution_or_tuple_failure'; end if;
  if (select count(*) from fitmatch_activation_shadow
      where source='uniqlo' and (
        (external_product_id='E482514' and resolution @>
          '{"classification_status":"confirmed","category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve"}'::jsonb)
        or (external_product_id in('E454311','E456567') and resolution @>
          '{"classification_status":"confirmed","category_code":"tops","detail_code":"base_layer_top","garment_type_code":"base_layer_top","family_code":"base_layer_top","length_code":"short_sleeve"}'::jsonb)
      ))<>3
  then raise exception 'activation_gold_mismatch'; end if;
  if (select count(*) from fitmatch_activation_shadow
      where source='musinsa' and external_product_id in(
        '4800605','5982920','6593581','6786576',
        '6797265','6797266','6797271')
        and resolution->>'classification_status'='not_comparable')<>7
  then raise exception 'activation_set_exclusion_mismatch'; end if;
  if exists(select 1 from fitmatch_activation_shadow
      where resolution->>'classification_method' in(
        'verified_path_profile','verified_name_signature_profile')
        and resolution->>'authority_status'<>'verified')
    or exists(select 1 from fitmatch_activation_shadow
      where resolution->>'classification_status'='confirmed'
        and jsonb_array_length(coalesce(
          resolution->'authority_conflicts','[]'::jsonb))>0)
  then raise exception 'activation_authority_safety_leak'; end if;
  v_base_block:=fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops','UNISEX','tshirt','short_sleeve','short_sleeve',null,
    'tops','UNISEX','base_layer_top','base_layer_top','short_sleeve',null,
    'tshirt','base_layer_top',false,
    '11800000-0000-4000-8000-000000000118'::uuid);
  v_cross_allow:=fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
    'tops','UNISEX','sweatshirt','sweatshirt','long_sleeve',null,
    'tops','UNISEX','hoodie','hoodie','long_sleeve',null,
    'sweatshirt','hoodie',false,
    '11800000-0000-4000-8000-000000000118'::uuid);
  if coalesce((v_base_block->>'allowed')::boolean,false)
    or not coalesce((v_cross_allow->>'allowed')::boolean,false)
  then raise exception 'activation_comparison_policy_smoke_failed'; end if;
  if (select count(*) from fitmatch_catalog.product_classification_history)<>
      (select history_count from fitmatch_activation_guard)
    or (select count(*) from fitmatch_catalog.product_classification_history
        where is_current)<>
      (select current_history_count from fitmatch_activation_guard)
  then raise exception 'activation_history_write_detected'; end if;
end
$smoke$;

commit;
