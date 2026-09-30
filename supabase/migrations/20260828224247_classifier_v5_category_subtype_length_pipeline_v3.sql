create or replace function fitmatch_catalog.runtime_source_category_hint_v5(
  p_source text,
  p_source_category_path text,
  p_payload jsonb default '{}'::jsonb,
  p_release_id uuid default null
)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_source text := lower(btrim(coalesce(p_source,'')));
  v_path text := fitmatch_catalog.runtime_normalized_category_path(p_source_category_path);
  v_target text := fitmatch_catalog.runtime_normalize_product_audience_v1(p_payload->>'audience');
  v_release_id uuid;
  v_mapping fitmatch_catalog.source_category_mappings%rowtype;
  v_mapping_count integer := 0;
  v_mapping_identity text;
  v_scope text;
begin
  if p_release_id is null then
    select id into v_release_id
    from fitmatch_catalog.releases
    where status='active'
    order by activated_at desc nulls last, created_at desc
    limit 1;
  else
    v_release_id := p_release_id;
  end if;
  if v_release_id is null then
    return jsonb_build_object('found',false,'reason','active_release_missing');
  end if;

  if jsonb_typeof(p_payload->'source_category_codes')='array'
     and jsonb_array_length(p_payload->'source_category_codes')>0 then
    with codes as (
      select value code, ordinality
      from jsonb_array_elements_text(p_payload->'source_category_codes')
        with ordinality item(value,ordinality)
    ), candidates as (
      select mapping.source_identity,codes.ordinality,
        max(codes.ordinality) over() max_ordinality,
        case
          when upper(btrim(mapping.target))=v_target then 0
          when fitmatch_catalog.runtime_normalize_mapping_target_v1(mapping.target)=v_target then 1
          else 2
        end audience_priority,
        jsonb_build_object(
          'scope',lower(coalesce(mapping.raw_record#>>'{authorityContract,resolutionScope}',mapping.raw_record->>'resolutionScope','')),
          'category',mapping.semantic_category_code,
          'detail',mapping.raw_record#>>'{appMapping,detailCode}',
          'garment',mapping.semantic_garment_type,
          'family',mapping.comparison_family,
          'length_axes',mapping.raw_record->'lengthAxes'
        )::text semantic_signature
      from codes
      join fitmatch_catalog.source_category_mappings mapping
        on mapping.release_id=v_release_id
       and mapping.source=v_source
       and mapping.external_category_id=codes.code
       and mapping.runtime_lookup_eligible
       and mapping.eligibility
       and lower(coalesce(mapping.raw_record#>>'{authorityContract,authorityStatus}',mapping.raw_record->>'authorityStatus',''))='verified'
       and fitmatch_catalog.runtime_normalize_mapping_target_v1(mapping.target) in (v_target,'GENERIC')
    ), leaf as (
      select candidates.*, min(audience_priority) over() min_audience_priority
      from candidates where ordinality=max_ordinality
    ), selected as (
      select * from leaf where audience_priority=min_audience_priority
    )
    select count(distinct semantic_signature),min(source_identity)
    into v_mapping_count,v_mapping_identity
    from selected;
  end if;

  if v_mapping_count=0 and v_path<>'' then
    with candidates as (
      select mapping.source_identity,
        case
          when upper(btrim(mapping.target))=v_target then 0
          when fitmatch_catalog.runtime_normalize_mapping_target_v1(mapping.target)=v_target then 1
          else 2
        end audience_priority,
        jsonb_build_object(
          'scope',lower(coalesce(mapping.raw_record#>>'{authorityContract,resolutionScope}',mapping.raw_record->>'resolutionScope','')),
          'category',mapping.semantic_category_code,
          'detail',mapping.raw_record#>>'{appMapping,detailCode}',
          'garment',mapping.semantic_garment_type,
          'family',mapping.comparison_family,
          'length_axes',mapping.raw_record->'lengthAxes'
        )::text semantic_signature
      from fitmatch_catalog.source_category_mappings mapping
      where mapping.release_id=v_release_id and mapping.source=v_source
        and fitmatch_catalog.runtime_normalized_category_path(mapping.normalized_path)=v_path
        and mapping.runtime_lookup_eligible and mapping.eligibility
        and lower(coalesce(mapping.raw_record#>>'{authorityContract,authorityStatus}',mapping.raw_record->>'authorityStatus',''))='verified'
        and fitmatch_catalog.runtime_normalize_mapping_target_v1(mapping.target) in (v_target,'GENERIC')
    ), ranked as (
      select candidates.*,min(audience_priority) over() min_audience_priority from candidates
    ), selected as (
      select * from ranked where audience_priority=min_audience_priority
    )
    select count(distinct semantic_signature),min(source_identity)
    into v_mapping_count,v_mapping_identity from selected;
  end if;

  if v_mapping_count>1 then
    return jsonb_build_object('found',false,'ambiguous',true,'candidate_count',v_mapping_count,'audience_target',v_target,'normalized_path',v_path);
  end if;
  if v_mapping_count=0 or v_mapping_identity is null then
    return jsonb_build_object('found',false,'ambiguous',false,'candidate_count',0,'audience_target',v_target,'normalized_path',v_path);
  end if;

  select * into v_mapping
  from fitmatch_catalog.source_category_mappings
  where release_id=v_release_id and source_identity=v_mapping_identity;
  v_scope := lower(coalesce(nullif(v_mapping.raw_record#>>'{authorityContract,resolutionScope}',''),nullif(v_mapping.raw_record->>'resolutionScope',''),''));

  return jsonb_build_object(
    'found',true,'source_identity',v_mapping.source_identity,'scope',v_scope,
    'category_code',v_mapping.semantic_category_code,
    'detail_code',v_mapping.raw_record#>>'{appMapping,detailCode}',
    'comparison_family',v_mapping.comparison_family,
    'garment_type_code',case when v_scope='category_direct' then v_mapping.semantic_garment_type else null end,
    'stored_garment_hint',v_mapping.semantic_garment_type,
    'length_axes',coalesce(v_mapping.raw_record->'lengthAxes','{}'::jsonb),
    'product_required',v_scope='product_required','audience_target',v_target,'normalized_path',v_path
  );
end
$function$;

create or replace function fitmatch_catalog.runtime_resolve_product_classification_v5(
  p_source text,p_external_product_id text,p_product_name text,p_source_category_path text,
  p_payload jsonb default '{}'::jsonb,p_release_id uuid default null
)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_base jsonb; v_hint jsonb; v_pipeline jsonb; v_evidence jsonb;
  v_method text; v_status text; v_garment text; v_release_id uuid;
begin
  if p_release_id is null then
    select id into v_release_id from fitmatch_catalog.releases where status='active' order by activated_at desc nulls last,created_at desc limit 1;
  else v_release_id:=p_release_id; end if;
  v_hint:=fitmatch_catalog.runtime_source_category_hint_v5(p_source,p_source_category_path,p_payload,v_release_id);
  v_base:=fitmatch_catalog.runtime_resolve_product_classification_v4(p_source,p_external_product_id,p_product_name,p_source_category_path,p_payload,v_release_id);
  v_method:=coalesce(v_base->>'classification_method','unknown');
  v_status:=coalesce(v_base->>'classification_status','review_required');
  v_garment:=nullif(lower(btrim(coalesce(v_base->>'garment_type_code',''))),'');

  if v_status='confirmed' and v_garment='other_standard_pants' then
    return jsonb_build_object(
      'category_code',null,'detail_code',null,'garment_type_code',null,'family_code',null,'length_code',null,'body_length_code',null,
      'classification_status','review_required','classification_method','v5_policy_guard','authority_status',null,'confidence',null,
      'requires_user_confirmation',true,'mapping_release_id',v_release_id,'decision_version',null,'tuple_validation',null,
      'authority_conflicts',coalesce(v_base->'authority_conflicts','[]'::jsonb),
      'evidence',coalesce(v_base->'evidence','{}'::jsonb)||jsonb_build_object('pipeline_version','v5','unresolved_reasons',jsonb_build_array('deprecated_other_standard_pants_requires_subtype'),'category_hint',v_hint,'policy','category_then_subtype_then_length_then_validation'),
      'classifier_policy_version',v_base->>'classifier_policy_version','pipeline_version','v5'
    );
  end if;

  v_pipeline:=jsonb_build_object(
    'stage_1_exclusion',jsonb_build_object('status',case when v_status='not_comparable' then 'excluded' else 'passed' end,'method',case when v_status='not_comparable' then v_method else null end),
    'stage_2_source_category',jsonb_build_object('status',case when coalesce((v_hint->>'found')::boolean,false) then 'resolved' else 'unresolved' end,'hint',v_hint),
    'stage_3_garment_subtype',jsonb_build_object('status',case when v_garment is not null then 'resolved' else 'unresolved' end,'garment_type_code',v_base->>'garment_type_code','authority_source',v_method),
    'stage_4_length_axis',jsonb_build_object('status',case when nullif(v_base->>'length_code','') is not null or nullif(v_base->>'body_length_code','') is not null then 'resolved' else 'unresolved' end,'length_code',v_base->>'length_code','body_length_code',v_base->>'body_length_code','category_length_hint',coalesce(v_hint->'length_axes','{}'::jsonb)),
    'stage_5_validation',jsonb_build_object('status',case when coalesce((v_base->'tuple_validation'->>'valid')::boolean,false) then 'passed' when v_status='not_comparable' then 'not_applicable' else 'unresolved' end,'tuple_validation',v_base->'tuple_validation')
  );
  v_evidence:=coalesce(v_base->'evidence','{}'::jsonb)||jsonb_build_object('pipeline_version','v5','pipeline',v_pipeline,'policy','exclusion -> source_category -> garment_subtype -> length_axis -> tuple_validation','product_required_never_confirms_subtype_alone',true,'raw_name_heuristic_forbidden',true);
  v_base:=jsonb_set(v_base,'{evidence}',v_evidence,true);
  v_base:=jsonb_set(v_base,'{pipeline_version}','"v5"'::jsonb,true);
  return v_base;
end
$function$;

comment on function fitmatch_catalog.runtime_resolve_product_classification_v5(text,text,text,text,jsonb,uuid)
is 'FitMatch v5 classifier: exclusion -> source category -> verified product subtype -> length axis -> tuple validation. PRODUCT_REQUIRED category mappings never confirm a subtype alone.';

create or replace function fitmatch_catalog.runtime_classifier_v5_release_gate_v1(p_release_id uuid)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_release fitmatch_catalog.releases%rowtype; v_parent_id uuid;
  v_mapping_count integer; v_parent_parity integer; v_modified_runtime integer; v_rule_count integer; v_rule_parity integer;
  v_history_count integer; v_confirmed integer; v_review integer; v_not_comparable integer; v_history_parity integer; v_fingerprint_parity integer;
  v_core_invalid integer; v_set_leaks integer; v_history_other integer; v_vnext_other integer; v_vnext_subtype_required integer;
  v_legacy_other integer; v_legacy_subtype_required integer; v_runtime_other integer; v_policy jsonb; v_wrapper_v5 integer;
  v_vnext_axis_mode text; v_compat_length_required boolean; v_mapping_checksum text; v_history_checksum text; v_bundle_checksum text;
  v_blockers jsonb:='[]'::jsonb;
begin
  select * into v_release from fitmatch_catalog.releases where id=p_release_id;
  if not found then raise exception using errcode='P0002',message='release_not_found'; end if;
  v_parent_id:=nullif(v_release.metadata->>'parent_release_id','')::uuid;
  if v_release.release_key<>'fitmatch-classifier-v5-category-subtype-length-2026-08-29-v1'
     or v_release.validation_contract_version<>'fitmatch-release-gate-v6-classifier-v5'
     or v_release.status not in ('validated','active') or v_release.expected_mapping_count<>3510 or v_release.expected_qa_count<>1608 or v_release.validated_at is null then
    v_blockers:=v_blockers||jsonb_build_array('release_identity_or_contract_mismatch'); end if;

  select count(*) into v_mapping_count from fitmatch_catalog.source_category_mappings where release_id=p_release_id;
  select count(*) into v_parent_parity from fitmatch_catalog.source_category_mappings parent
  join fitmatch_catalog.source_category_mappings child on child.release_id=p_release_id and child.source_identity=parent.source_identity
  where parent.release_id=v_parent_id and parent.semantic_garment_type is distinct from 'other_standard_pants'
    and (to_jsonb(child)-'release_id'-'created_at') is not distinct from (to_jsonb(parent)-'release_id'-'created_at');
  select count(*) into v_modified_runtime from fitmatch_catalog.source_category_mappings where release_id=p_release_id and raw_record#>>'{v5Policy,deprecatedGarmentType}'='other_standard_pants' and semantic_garment_type is null;
  select count(*) into v_runtime_other from fitmatch_catalog.source_category_mappings where release_id=p_release_id and semantic_garment_type='other_standard_pants';
  if v_mapping_count<>3510 or v_modified_runtime<>coalesce((v_release.metadata->>'runtime_other_mapping_cleanup_count')::integer,-1) or v_parent_parity<>3510-v_modified_runtime or v_runtime_other<>0 then
    v_blockers:=v_blockers||jsonb_build_array('runtime_mapping_cleanup_or_parity_failed'); end if;

  select count(*) into v_rule_count from fitmatch_catalog.classification_structured_discriminator_rules where release_id=p_release_id;
  select count(*) into v_rule_parity from fitmatch_catalog.classification_structured_discriminator_rules parent
  join fitmatch_catalog.classification_structured_discriminator_rules child on child.release_id=p_release_id and child.rule_id=parent.rule_id
  where parent.release_id=v_parent_id and (to_jsonb(child)-'release_id'-'created_at') is not distinct from (to_jsonb(parent)-'release_id'-'created_at');
  if v_rule_count<>21 or v_rule_parity<>21 then v_blockers:=v_blockers||jsonb_build_array('structured_rule_parity_failed'); end if;

  select count(*),count(*) filter(where classification_status='confirmed'),count(*) filter(where classification_status='review_required'),count(*) filter(where classification_status='not_comparable')
  into v_history_count,v_confirmed,v_review,v_not_comparable from fitmatch_catalog.product_classification_history
  where is_current and mapping_release_id=p_release_id and taxonomy_policy_version='db-classifier-2026-08-29-v5';
  if v_history_count<>1608 or v_confirmed<>1421 or v_review<>0 or v_not_comparable<>187 then v_blockers:=v_blockers||jsonb_build_array('current_history_population_failed'); end if;

  select count(*) into v_fingerprint_parity from fitmatch_catalog.product_classification_history h join fitmatch_catalog.products p on p.id=h.product_id
  where h.is_current and h.mapping_release_id=p_release_id and h.taxonomy_policy_version='db-classifier-2026-08-29-v5' and h.input_fingerprint=p.input_fingerprint;
  if v_fingerprint_parity<>1608 then v_blockers:=v_blockers||jsonb_build_array('fingerprint_parity_failed'); end if;

  select count(*) into v_history_parity from fitmatch_catalog.product_classification_history h join fitmatch_vnext.products v on v.id=h.product_id
  left join fitmatch_vnext.garment_types gt on gt.garment_type_code=v.garment_type_code
  where h.is_current and h.mapping_release_id=p_release_id and (
    (v.classification_status='CONFIRMED' and h.classification_status='confirmed' and h.garment_type_code is not distinct from v.garment_type_code
      and h.length_code is not distinct from case when gt.uses_sleeve_length then v.sleeve_length_code when gt.uses_lower_length then v.lower_length_code else null end
      and h.body_length_code is not distinct from case when gt.uses_body_length then v.body_length_code else null end)
    or (v.classification_status='NOT_APPLICABLE' and h.classification_status='not_comparable' and h.category_code is null and h.detail_code is null and h.garment_type_code is null and h.comparison_family_code is null and h.length_code is null and h.body_length_code is null));
  if v_history_parity<>1608 then v_blockers:=v_blockers||jsonb_build_array('vnext_history_parity_failed'); end if;

  select count(*) into v_core_invalid from fitmatch_catalog.product_classification_history h
  left join public.garment_types g on g.code=h.garment_type_code and g.is_active
  left join public.app_categories parent on parent.code=h.category_code and parent.depth=0 and parent.parent_id is null and parent.is_active
  left join public.app_categories detail on detail.code=h.detail_code and detail.depth=1 and detail.parent_id=parent.id and detail.is_active
  left join public.comparison_groups family on family.code=h.comparison_family_code and family.is_active
  where h.is_current and h.mapping_release_id=p_release_id and h.classification_status='confirmed'
    and (g.code is null or parent.id is null or detail.id is null or family.code is null or g.major_category_code is distinct from h.category_code or g.comparison_group_code is distinct from h.comparison_family_code);
  if v_core_invalid<>0 then v_blockers:=v_blockers||jsonb_build_array('confirmed_core_tuple_invalid'); end if;

  select count(*) into v_set_leaks from fitmatch_catalog.product_classification_history h join fitmatch_vnext.products v on v.id=h.product_id
  where h.is_current and h.mapping_release_id=p_release_id and v.product_structure_code='SET' and h.classification_status<>'not_comparable';
  if v_set_leaks<>0 then v_blockers:=v_blockers||jsonb_build_array('set_comparison_leak'); end if;

  select count(*) into v_history_other from fitmatch_catalog.product_classification_history where is_current and garment_type_code='other_standard_pants';
  select count(*) into v_vnext_other from fitmatch_vnext.classification_signal_mappings where is_active and garment_type_code='other_standard_pants';
  select count(*) into v_vnext_subtype_required from fitmatch_vnext.classification_signal_mappings where is_active and resolution_mode='PRODUCT_REQUIRED' and garment_type_code is null and not is_verified;
  select count(*) into v_legacy_other from public.source_category_mappings scm join public.garment_types g on g.id=scm.garment_type_id where g.code='other_standard_pants';
  select count(*) into v_legacy_subtype_required from public.source_category_mappings where garment_type_id is null and mapping_status='review_required'
    and evidence->>'deprecated_garment_type'='other_standard_pants' and coalesce((evidence->>'v5_subtype_required')::boolean,false);
  if v_history_other<>0 or v_vnext_other<>0 or v_legacy_other<>0 or v_legacy_subtype_required<>coalesce((v_release.metadata->>'source_truth_other_cleanup_count')::integer,-1)
     or v_vnext_subtype_required<coalesce((v_release.metadata->>'source_truth_other_cleanup_count')::integer,999999) then
    v_blockers:=v_blockers||jsonb_build_array('deprecated_other_standard_pants_not_closed'); end if;

  select lower_length_mismatch_policy into v_vnext_axis_mode from fitmatch_vnext.comparison_policies where policy_code='standard_pants';
  select length_match_required into v_compat_length_required from fitmatch_taxonomy.comparison_compatibility_rules
  where policy_version='db-comparison-2026-08-26-final' and from_family_code='standard_pants' and to_family_code='standard_pants';
  if v_vnext_axis_mode<>'REQUIRE_MATCH' or coalesce(v_compat_length_required,false)<>true then v_blockers:=v_blockers||jsonb_build_array('automatic_bottom_length_policy_mismatch'); end if;

  v_policy:=fitmatch_catalog.runtime_policy_contract_report_v1(p_release_id);
  if not coalesce((v_policy->>'eligible')::boolean,false) then v_blockers:=v_blockers||coalesce(v_policy->'blockers','[]'::jsonb); end if;

  select count(*) into v_wrapper_v5 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prokind='f' and ((n.nspname='fitmatch_catalog' and p.proname='runtime_resolve_and_promote_product') or (n.nspname='public' and p.proname in ('fitmatch_get_product_runtime','fitmatch_resolve_product')))
    and pg_get_functiondef(p.oid) like '%runtime_resolve_product_classification_v5%' and pg_get_functiondef(p.oid) not like '%runtime_resolve_product_classification_v4%';
  if v_wrapper_v5<>3 then v_blockers:=v_blockers||jsonb_build_array('runtime_wrappers_not_on_v5'); end if;
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='fitmatch_catalog' and p.proname='runtime_resolve_product_classification_v5') then v_blockers:=v_blockers||jsonb_build_array('v5_resolver_missing'); end if;

  select encode(extensions.digest(coalesce(string_agg(jsonb_build_object('source_identity',m.source_identity,'source',m.source,'snapshot_id',m.snapshot_id,'external_category_id',m.external_category_id,'target',m.target,'normalized_path',m.normalized_path,'decision_status',m.decision_status,'mapping_status',m.mapping_status,'runtime_lookup_eligible',m.runtime_lookup_eligible,'eligibility',m.eligibility,'semantic_category_code',m.semantic_category_code,'semantic_garment_type',m.semantic_garment_type,'comparison_family',m.comparison_family,'source_external_key',m.source_external_key,'source_external_target_key',m.source_external_target_key,'source_path_key',m.source_path_key,'source_target_path_key',m.source_target_path_key,'raw_record',m.raw_record)::text,E'\n' order by m.source_identity),''),'sha256'),'hex') into v_mapping_checksum
  from fitmatch_catalog.source_category_mappings m where m.release_id=p_release_id;
  select encode(extensions.digest(coalesce(string_agg(p.source||'|'||p.external_product_id||'|'||h.input_fingerprint||'|'||h.classification_status||'|'||coalesce(h.garment_type_code,'')||'|'||coalesce(h.length_code,'')||'|'||coalesce(h.body_length_code,'')||'|'||coalesce(h.taxonomy_policy_version,''),E'\n' order by p.source,p.external_product_id),''),'sha256'),'hex') into v_history_checksum
  from fitmatch_catalog.product_classification_history h join fitmatch_catalog.products p on p.id=h.product_id where h.is_current and h.mapping_release_id=p_release_id;
  v_bundle_checksum:=encode(extensions.digest(v_mapping_checksum||'|'||v_history_checksum||'|'||v_rule_count::text||'|db-classifier-2026-08-29-v5','sha256'),'hex');
  if v_release.validation_report->>'source_mapping_checksum' is distinct from v_mapping_checksum or v_release.validation_report->>'exact_authority_checksum' is distinct from v_history_checksum or v_release.bundle_checksum is distinct from v_bundle_checksum then v_blockers:=v_blockers||jsonb_build_array('release_checksum_mismatch'); end if;

  return jsonb_build_object('contract_version','fitmatch-release-gate-v6-classifier-v5','release_id',v_release.id,'release_key',v_release.release_key,'eligible',jsonb_array_length(v_blockers)=0,'blockers',v_blockers,
    'mapping_count',v_mapping_count,'parent_mapping_parity',v_parent_parity,'runtime_other_mapping_cleanup_count',v_modified_runtime,'structured_rule_count',v_rule_count,'structured_rule_parity',v_rule_parity,
    'history_count',v_history_count,'confirmed_count',v_confirmed,'review_required_count',v_review,'not_comparable_count',v_not_comparable,'history_parity_count',v_history_parity,'fingerprint_parity_count',v_fingerprint_parity,
    'core_tuple_invalid_count',v_core_invalid,'set_leak_count',v_set_leaks,'other_standard_pants_history_count',v_history_other,'other_standard_pants_runtime_mapping_count',v_runtime_other,
    'other_standard_pants_vnext_mapping_count',v_vnext_other,'other_standard_pants_legacy_mapping_count',v_legacy_other,'legacy_subtype_required_count',v_legacy_subtype_required,
    'vnext_length_policy',v_vnext_axis_mode,'compatibility_length_match_required',v_compat_length_required,'runtime_wrapper_v5_count',v_wrapper_v5,'runtime_policy_contract',v_policy,
    'source_mapping_checksum',v_mapping_checksum,'exact_authority_checksum',v_history_checksum,'bundle_checksum',v_bundle_checksum);
end
$function$;

create or replace function fitmatch_catalog.runtime_release_gate_report(p_release_id uuid)
returns jsonb language plpgsql set search_path to '' as $function$
declare v_release_key text;
begin
  select release_key into v_release_key from fitmatch_catalog.releases where id=p_release_id;
  if v_release_key='fitmatch-classifier-v5-category-subtype-length-2026-08-29-v1' then return fitmatch_catalog.runtime_classifier_v5_release_gate_v1(p_release_id); end if;
  if v_release_key='fitmatch-bottom-other-reclassification-2026-08-29-v1' then return fitmatch_catalog.runtime_bottom_reclassification_gate_v1(p_release_id); end if;
  if v_release_key='fitmatch-camisole-mapping-correction-2026-08-29-v1' then return fitmatch_catalog.runtime_camisole_mapping_correction_gate_v1(p_release_id); end if;
  if p_release_id='12100000-0000-4000-8000-000000000121'::uuid then return fitmatch_catalog.runtime_review_zero_gate_v1(p_release_id); end if;
  if p_release_id='12000000-0000-4000-8000-000000000120'::uuid then return fitmatch_catalog.runtime_audience_scope_correction_gate_v1(p_release_id); end if;
  return fitmatch_catalog.runtime_release_gate_report_pre120_v2(p_release_id);
end
$function$;

do $migration$
declare
  v_parent fitmatch_catalog.releases%rowtype; v_new_id uuid:=gen_random_uuid();
  v_old_classifier text:='db-classifier-2026-08-26-final'; v_new_classifier text:='db-classifier-2026-08-29-v5';
  v_vnext_changed integer; v_legacy_changed integer; v_runtime_changed integer; v_profile_old integer; v_profile_new integer; v_profile_manifest_checksum text;
  v_policy_report jsonb; v_mapping_checksum text; v_history_checksum text; v_bundle_checksum text; v_rule_count integer; v_gate jsonb; v_def text; r record;
begin
  select * into v_parent from fitmatch_catalog.releases where status='active' order by activated_at desc nulls last,created_at desc limit 1;
  if not found then raise exception 'active_release_missing'; end if;
  if v_parent.release_key<>'fitmatch-bottom-other-reclassification-2026-08-29-v1' then raise exception 'unexpected_parent_release:%',v_parent.release_key; end if;
  if exists(select 1 from fitmatch_taxonomy.policy_versions where code=v_new_classifier) then raise exception 'v5_policy_version_already_exists'; end if;

  insert into fitmatch_taxonomy.policy_versions(code,schema_version,taxonomy_version,manifest_checksum,status,created_at,validated_at)
  select v_new_classifier,'5.0',v_parent.taxonomy_version,manifest_checksum,'loading',now(),null from fitmatch_taxonomy.policy_versions where code=v_old_classifier;
  if not found then raise exception 'source_policy_version_missing'; end if;

  select count(*) into v_profile_old from (
    select 1 from fitmatch_catalog.classification_name_profiles where policy_version=v_old_classifier
    union all select 1 from fitmatch_catalog.classification_path_profiles where policy_version=v_old_classifier
    union all select 1 from fitmatch_catalog.classification_exclusion_profiles where policy_version=v_old_classifier
  ) q;
  if v_profile_old=0 then raise exception 'source_classifier_profiles_missing'; end if;

  insert into fitmatch_catalog.classification_name_profiles(policy_version,source,normalized_path,name_signature,category_code,detail_code,comparison_family_code,length_code,sample_count,review_count,distinct_decision_count,auto_eligible,evidence,created_at)
  select v_new_classifier,source,normalized_path,name_signature,category_code,detail_code,comparison_family_code,length_code,sample_count,review_count,distinct_decision_count,auto_eligible,evidence,now() from fitmatch_catalog.classification_name_profiles where policy_version=v_old_classifier;
  insert into fitmatch_catalog.classification_path_profiles(policy_version,source,normalized_path,category_code,detail_code,comparison_family_code,length_code,sample_count,review_count,distinct_decision_count,auto_eligible,evidence,created_at)
  select v_new_classifier,source,normalized_path,category_code,detail_code,comparison_family_code,length_code,sample_count,review_count,distinct_decision_count,auto_eligible,evidence,now() from fitmatch_catalog.classification_path_profiles where policy_version=v_old_classifier;
  insert into fitmatch_catalog.classification_exclusion_profiles(policy_version,source,normalized_path,sample_count,auto_eligible,reason_code,evidence,created_at)
  select v_new_classifier,source,normalized_path,sample_count,auto_eligible,reason_code,evidence,now() from fitmatch_catalog.classification_exclusion_profiles where policy_version=v_old_classifier;

  select count(*) into v_profile_new from (
    select 1 from fitmatch_catalog.classification_name_profiles where policy_version=v_new_classifier
    union all select 1 from fitmatch_catalog.classification_path_profiles where policy_version=v_new_classifier
    union all select 1 from fitmatch_catalog.classification_exclusion_profiles where policy_version=v_new_classifier
  ) q;
  if v_profile_new<>v_profile_old then raise exception 'classifier_profile_clone_mismatch:%/%',v_profile_new,v_profile_old; end if;

  with policy_rows as (
    select concat('name|',source,'|',normalized_path,'|',name_signature) key,jsonb_build_object('kind','name','source',source,'normalized_path',normalized_path,'name_signature',name_signature,'category_code',category_code,'detail_code',detail_code,'comparison_family_code',comparison_family_code,'length_code',length_code,'sample_count',sample_count,'review_count',review_count,'distinct_decision_count',distinct_decision_count,'auto_eligible',auto_eligible,'evidence',evidence) value from fitmatch_catalog.classification_name_profiles where policy_version=v_new_classifier
    union all select concat('path|',source,'|',normalized_path),jsonb_build_object('kind','path','source',source,'normalized_path',normalized_path,'category_code',category_code,'detail_code',detail_code,'comparison_family_code',comparison_family_code,'length_code',length_code,'sample_count',sample_count,'review_count',review_count,'distinct_decision_count',distinct_decision_count,'auto_eligible',auto_eligible,'evidence',evidence) from fitmatch_catalog.classification_path_profiles where policy_version=v_new_classifier
    union all select concat('exclusion|',source,'|',normalized_path),jsonb_build_object('kind','exclusion','source',source,'normalized_path',normalized_path,'sample_count',sample_count,'auto_eligible',auto_eligible,'reason_code',reason_code,'evidence',evidence) from fitmatch_catalog.classification_exclusion_profiles where policy_version=v_new_classifier
  ) select encode(extensions.digest(coalesce(string_agg(value::text,E'\n' order by key),''),'sha256'),'hex') into v_profile_manifest_checksum from policy_rows;
  update fitmatch_taxonomy.policy_versions set manifest_checksum=v_profile_manifest_checksum,status='validated',validated_at=now() where code=v_new_classifier;

  update fitmatch_vnext.classification_signal_mappings set garment_type_code=null,resolution_mode='PRODUCT_REQUIRED',is_verified=false,updated_at=now() where garment_type_code='other_standard_pants';
  get diagnostics v_vnext_changed=row_count;
  if v_vnext_changed<>93 then raise exception 'unexpected_vnext_other_cleanup_count:%',v_vnext_changed; end if;

  update public.source_category_mappings scm set garment_type_id=null,mapping_status='review_required',evidence=coalesce(scm.evidence,'{}'::jsonb)||jsonb_build_object('deprecated_garment_type','other_standard_pants','v5_subtype_required',true,'resolution_scope','product_required','authority_status','unverified'),updated_at=now()
  where scm.garment_type_id=(select id from public.garment_types where code='other_standard_pants');
  get diagnostics v_legacy_changed=row_count;
  if v_legacy_changed<>93 then raise exception 'unexpected_legacy_other_cleanup_count:%',v_legacy_changed; end if;

  insert into fitmatch_catalog.releases(id,release_key,taxonomy_version,policy_version,status,bundle_checksum,app_taxonomy_checksum,expected_mapping_count,expected_qa_count,metadata,validation_contract_version,validation_report,release_gate_result)
  values(v_new_id,'fitmatch-classifier-v5-category-subtype-length-2026-08-29-v1',v_parent.taxonomy_version,v_parent.policy_version,'loading',v_parent.bundle_checksum,v_parent.app_taxonomy_checksum,3510,1608,
    jsonb_build_object('parent_release_id',v_parent.id,'classifier_pipeline_version','v5','pipeline',jsonb_build_array('exclusion','source_category','garment_subtype','length_axis','tuple_validation'),'source_truth_other_cleanup_count',v_vnext_changed,'runtime_other_mapping_cleanup_count',56,'product_required_policy','category_and_length_hint_only; subtype authority required'),
    'fitmatch-release-gate-v6-classifier-v5',jsonb_build_object('runtime_policy_contract',jsonb_build_object('classifier_policy_version',v_new_classifier,'comparison_policy_version','v1','compatibility_rule_version','db-comparison-2026-08-26-final','measurement_policy_version','2026.07.1'),'runtime_policy_contract_validated',false,'classifier_pipeline_version','v5'),'{}'::jsonb);

  insert into fitmatch_catalog.source_category_mappings(release_id,source_identity,source,snapshot_id,external_category_id,target,normalized_path,decision_status,mapping_status,runtime_lookup_eligible,eligibility,semantic_category_code,semantic_garment_type,comparison_family,source_external_key,source_external_target_key,source_path_key,source_target_path_key,raw_record,created_at)
  select v_new_id,source_identity,source,snapshot_id,external_category_id,target,normalized_path,decision_status,mapping_status,runtime_lookup_eligible,eligibility,semantic_category_code,semantic_garment_type,comparison_family,source_external_key,source_external_target_key,source_path_key,source_target_path_key,raw_record,now() from fitmatch_catalog.source_category_mappings where release_id=v_parent.id;

  update fitmatch_catalog.source_category_mappings set semantic_garment_type=null,raw_record=jsonb_set(raw_record-'semanticGarmentType','{v5Policy}',jsonb_build_object('deprecatedGarmentType','other_standard_pants','subtypeRequired',lower(coalesce(raw_record#>>'{authorityContract,resolutionScope}',raw_record->>'resolutionScope',''))='product_required','categoryProvidesFamily',true,'lengthAxesRemainHints',true),true)
  where release_id=v_new_id and semantic_garment_type='other_standard_pants';
  get diagnostics v_runtime_changed=row_count;
  if v_runtime_changed<>56 then raise exception 'unexpected_runtime_other_cleanup_count:%',v_runtime_changed; end if;

  insert into fitmatch_catalog.classification_structured_discriminator_rules(release_id,rule_id,source,discriminator_key,discriminator_value,external_category_id,normalized_path,target,outcome,category_code,detail_code,garment_type_code,family_code,length_code,body_length_code,exclusion_reason_code,authority_status,resolution_scope,runtime_eligible,evidence,policy_version,created_at)
  select v_new_id,rule_id,source,discriminator_key,discriminator_value,external_category_id,normalized_path,target,outcome,category_code,detail_code,garment_type_code,family_code,length_code,body_length_code,exclusion_reason_code,authority_status,resolution_scope,runtime_eligible,evidence,policy_version,now() from fitmatch_catalog.classification_structured_discriminator_rules where release_id=v_parent.id;

  with old as (update fitmatch_catalog.product_classification_history set is_current=false,superseded_at=now() where is_current returning *)
  insert into fitmatch_catalog.product_classification_history(product_id,input_fingerprint,category_code,detail_code,comparison_family_code,length_code,classification_status,classification_method,confidence,requires_user_confirmation,taxonomy_policy_version,mapping_release_id,decision_version,evidence,is_current,reviewed_by,reviewed_at,superseded_at,created_at,body_length_code,garment_type_code)
  select product_id,input_fingerprint,category_code,detail_code,comparison_family_code,length_code,classification_status,classification_method,confidence,requires_user_confirmation,v_new_classifier,v_new_id,v_new_classifier,coalesce(evidence,'{}'::jsonb)||jsonb_build_object('pipeline_version','v5','release_transition','classifier_v5_category_subtype_length'),true,reviewed_by,reviewed_at,null,now(),body_length_code,garment_type_code from old;

  for r in select p.oid,n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prokind='f' and ((n.nspname='fitmatch_catalog' and p.proname='runtime_resolve_and_promote_product') or (n.nspname='public' and p.proname in ('fitmatch_get_product_runtime','fitmatch_resolve_product')))
  loop
    v_def:=pg_get_functiondef(r.oid);
    if position('runtime_resolve_product_classification_v4' in v_def)=0 then raise exception 'wrapper_missing_v4_reference:%.%',r.nspname,r.proname; end if;
    v_def:=replace(v_def,'runtime_resolve_product_classification_v4','runtime_resolve_product_classification_v5');
    v_def:=replace(v_def,'active_v4_contract_missing','active_v5_contract_missing');
    execute v_def;
  end loop;

  v_policy_report:=fitmatch_catalog.runtime_policy_contract_report_v1(v_new_id);
  update fitmatch_catalog.releases set validation_report=validation_report||jsonb_build_object('classifier_policy_checksum',v_policy_report->>'classifier_policy_checksum','comparison_policy_checksum',v_policy_report->>'comparison_policy_checksum','compatibility_rule_checksum',v_policy_report->>'compatibility_rule_checksum','measurement_policy_checksum',v_policy_report->>'measurement_policy_checksum','runtime_policy_contract_validated',true,'classifier_profile_count',v_profile_new,'source_truth_other_cleanup_count',v_vnext_changed,'legacy_other_cleanup_count',v_legacy_changed,'runtime_other_mapping_cleanup_count',v_runtime_changed) where id=v_new_id;
  v_policy_report:=fitmatch_catalog.runtime_policy_contract_report_v1(v_new_id);
  if not coalesce((v_policy_report->>'eligible')::boolean,false) then raise exception 'runtime_policy_contract_failed:%',v_policy_report; end if;

  select count(*) into v_rule_count from fitmatch_catalog.classification_structured_discriminator_rules where release_id=v_new_id;
  select encode(extensions.digest(coalesce(string_agg(jsonb_build_object('source_identity',m.source_identity,'source',m.source,'snapshot_id',m.snapshot_id,'external_category_id',m.external_category_id,'target',m.target,'normalized_path',m.normalized_path,'decision_status',m.decision_status,'mapping_status',m.mapping_status,'runtime_lookup_eligible',m.runtime_lookup_eligible,'eligibility',m.eligibility,'semantic_category_code',m.semantic_category_code,'semantic_garment_type',m.semantic_garment_type,'comparison_family',m.comparison_family,'source_external_key',m.source_external_key,'source_external_target_key',m.source_external_target_key,'source_path_key',m.source_path_key,'source_target_path_key',m.source_target_path_key,'raw_record',m.raw_record)::text,E'\n' order by m.source_identity),''),'sha256'),'hex') into v_mapping_checksum from fitmatch_catalog.source_category_mappings m where m.release_id=v_new_id;
  select encode(extensions.digest(coalesce(string_agg(p.source||'|'||p.external_product_id||'|'||h.input_fingerprint||'|'||h.classification_status||'|'||coalesce(h.garment_type_code,'')||'|'||coalesce(h.length_code,'')||'|'||coalesce(h.body_length_code,'')||'|'||coalesce(h.taxonomy_policy_version,''),E'\n' order by p.source,p.external_product_id),''),'sha256'),'hex') into v_history_checksum from fitmatch_catalog.product_classification_history h join fitmatch_catalog.products p on p.id=h.product_id where h.is_current and h.mapping_release_id=v_new_id;
  v_bundle_checksum:=encode(extensions.digest(v_mapping_checksum||'|'||v_history_checksum||'|'||v_rule_count::text||'|'||v_new_classifier,'sha256'),'hex');
  update fitmatch_catalog.releases set bundle_checksum=v_bundle_checksum,validation_report=validation_report||jsonb_build_object('source_mapping_checksum',v_mapping_checksum,'exact_authority_checksum',v_history_checksum,'classifier_pipeline_version','v5','classification_process',jsonb_build_array('structured_exclusion','source_category_authority','verified_product_subtype','length_axis','tuple_validation'),'product_required_never_confirms_subtype_alone',true,'other_standard_pants_deprecated',true),status='validated',validated_at=now() where id=v_new_id;

  v_gate:=fitmatch_catalog.runtime_classifier_v5_release_gate_v1(v_new_id);
  if not coalesce((v_gate->>'eligible')::boolean,false) then raise exception 'classifier_v5_gate_failed:%',v_gate; end if;
  perform fitmatch_catalog.runtime_activate_validated_release(v_new_id);
  if not exists(select 1 from fitmatch_catalog.releases where id=v_new_id and status='active') then raise exception 'classifier_v5_activation_failed'; end if;
end
$migration$;;
