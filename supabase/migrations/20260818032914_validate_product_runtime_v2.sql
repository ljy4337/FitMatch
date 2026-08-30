begin;

set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtext('fitmatch:product-runtime-v2-validation'));

create table if not exists fitmatch_catalog.classification_exclusion_profiles (
  policy_version text not null
    references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  source text not null,
  normalized_path text not null,
  sample_count integer not null,
  auto_eligible boolean not null,
  reason_code text not null,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  primary key (policy_version,source,normalized_path),
  constraint classification_exclusion_profiles_sample_check check (sample_count>=2),
  constraint classification_exclusion_profiles_reason_check check (btrim(reason_code)<>''),
  constraint classification_exclusion_profiles_evidence_check
    check (jsonb_typeof(evidence)='object')
);
create index if not exists classification_exclusion_profiles_runtime_idx
  on fitmatch_catalog.classification_exclusion_profiles
    (source,normalized_path,policy_version)
  where auto_eligible;
alter table fitmatch_catalog.classification_exclusion_profiles enable row level security;
revoke all on fitmatch_catalog.classification_exclusion_profiles
  from public,anon,authenticated;
grant select,insert,update,delete
  on fitmatch_catalog.classification_exclusion_profiles to service_role;

with per_product as (
  select distinct on (source,external_product_id)
    source,external_product_id,
    fitmatch_catalog.runtime_normalized_category_path(source_category_path) normalized_path,
    classification_status,fitmatch_category_label,fitmatch_detail_label,collected_at
  from fitmatch_catalog.source_product_snapshots
  order by source,external_product_id,collected_at desc
), grouped as (
  select source,normalized_path,count(*) sample_count,
    bool_and(classification_status='excluded_review'
      and fitmatch_category_label is null and fitmatch_detail_label is null) all_excluded
  from per_product where normalized_path<>'' group by 1,2
)
insert into fitmatch_catalog.classification_exclusion_profiles (
  policy_version,source,normalized_path,sample_count,auto_eligible,reason_code,evidence
)
select 'db-auto-classifier-2026-08-18-v2',source,normalized_path,sample_count,
  all_excluded,'not_fitmatch_comparable',
  jsonb_build_object('source','latest_source_product_snapshots',
    'required_unanimous_status','excluded_review')
from grouped where sample_count>=2
on conflict (policy_version,source,normalized_path) do update set
  sample_count=excluded.sample_count,auto_eligible=excluded.auto_eligible,
  reason_code=excluded.reason_code,evidence=excluded.evidence;

create or replace function fitmatch_catalog.runtime_resolve_product_classification_v3(
  p_source text,p_external_product_id text,p_product_name text,
  p_source_category_path text,p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare
  v_result jsonb;
  v_snapshot fitmatch_catalog.source_product_snapshots%rowtype;
  v_exclusion fitmatch_catalog.classification_exclusion_profiles%rowtype;
  v_fingerprint text:=fitmatch_catalog.runtime_product_fingerprint(
    p_product_name,p_source_category_path
  );
  v_path text:=fitmatch_catalog.runtime_normalized_category_path(p_source_category_path);
begin
  v_result:=fitmatch_catalog.runtime_resolve_product_classification_v2(
    p_source,p_external_product_id,p_product_name,p_source_category_path,p_payload
  );
  if v_result->>'classification_status' in ('confirmed','not_comparable')
     or v_result->>'decision_source'='canonical_product_decision' then
    return v_result;
  end if;

  select * into v_snapshot
  from fitmatch_catalog.source_product_snapshots
  where source=lower(p_source) and external_product_id=p_external_product_id
    and fitmatch_catalog.runtime_product_fingerprint(
      product_name,source_category_path
    )=v_fingerprint
  order by collected_at desc limit 1;
  if v_snapshot.run_id is not null
     and v_snapshot.classification_status='excluded_review'
     and v_snapshot.fitmatch_category_label is null
     and v_snapshot.fitmatch_detail_label is null then
    return jsonb_build_object(
      'category_code',null,'detail_code',null,'family_code',null,'length_code',null,
      'requires_user_confirmation',false,'comparable',false,
      'classification_status','not_comparable','classification_method','category_mapping',
      'decision_source','verified_product_exclusion_snapshot',
      'decision_version','db-auto-classifier-2026-08-18-v2',
      'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
      'confidence',1,'exclusion_reason','not_fitmatch_comparable',
      'snapshot_id',v_snapshot.id
    );
  end if;

  select * into v_exclusion
  from fitmatch_catalog.classification_exclusion_profiles
  where policy_version='db-auto-classifier-2026-08-18-v2'
    and source=lower(p_source) and normalized_path=v_path and auto_eligible;
  if v_exclusion.policy_version is not null then
    return jsonb_build_object(
      'category_code',null,'detail_code',null,'family_code',null,'length_code',null,
      'requires_user_confirmation',false,'comparable',false,
      'classification_status','not_comparable','classification_method','category_mapping',
      'decision_source','verified_path_exclusion_profile',
      'decision_version','db-auto-classifier-2026-08-18-v2',
      'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
      'confidence',1,'exclusion_reason',v_exclusion.reason_code,
      'sample_count',v_exclusion.sample_count,'evidence',v_exclusion.evidence
    );
  end if;
  return v_result;
end $$;

create or replace function fitmatch_catalog.runtime_resolve_and_promote_product(
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare
  v_source text:=lower(btrim(coalesce(p_payload->>'source','')));
  v_external_id text:=btrim(coalesce(p_payload->>'external_product_id',''));
  v_product_id uuid;
  v_product fitmatch_catalog.products%rowtype;
  v_resolution jsonb;
  v_history_id uuid;
begin
  if jsonb_typeof(p_payload)<>'object' or v_source='' or v_external_id='' then
    raise exception using errcode='22023',message='invalid_product_payload';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_source||E'\n'||v_external_id,0));
  v_product_id:=fitmatch_catalog.runtime_upsert_product(p_payload);
  select * into v_product from fitmatch_catalog.products where id=v_product_id;
  select id into v_history_id
  from fitmatch_catalog.product_classification_history
  where product_id=v_product_id and is_current
    and input_fingerprint=v_product.input_fingerprint;
  if v_history_id is null then
    v_resolution:=fitmatch_catalog.runtime_resolve_product_classification_v3(
      v_product.source,v_product.external_product_id,v_product.product_name,
      coalesce(v_product.source_category_path,''),p_payload
    );
    v_history_id:=fitmatch_catalog.runtime_record_product_classification(
      v_product_id,jsonb_build_object(
        'category_code',v_resolution->>'category_code',
        'detail_code',v_resolution->>'detail_code',
        'family_code',v_resolution->>'family_code',
        'length_code',v_resolution->>'length_code',
        'classification_status',v_resolution->>'classification_status',
        'classification_method',v_resolution->>'classification_method',
        'confidence',v_resolution->>'confidence',
        'requires_user_confirmation',
          coalesce((v_resolution->>'requires_user_confirmation')::boolean,true),
        'taxonomy_policy_version',v_resolution->>'classifier_policy_version',
        'mapping_release_id',v_resolution->'source_mapping'->>'release_id',
        'decision_version',v_resolution->>'decision_version',
        'evidence',jsonb_build_object('resolution',v_resolution)
      )
    );
  else
    select jsonb_build_object(
      'category_code',category_code,'detail_code',detail_code,
      'family_code',comparison_family_code,'length_code',length_code,
      'body_length_code',body_length_code,
      'classification_status',classification_status,
      'classification_method',classification_method,
      'requires_user_confirmation',requires_user_confirmation,
      'decision_version',decision_version,'evidence',evidence
    ) into v_resolution
    from fitmatch_catalog.product_classification_history where id=v_history_id;
  end if;
  update public.product_intake_requests
  set status=case when v_resolution->>'classification_status' in ('confirmed','not_comparable')
      then 'resolved' else 'pending' end,
    resolved_product_id=v_product_id,resolution=v_resolution,
    resolved_at=case when v_resolution->>'classification_status' in ('confirmed','not_comparable')
      then now() else null end,updated_at=now()
  where source=v_source and external_product_id=v_external_id
    and input_fingerprint=v_product.input_fingerprint;
  return jsonb_build_object(
    'product_id',v_product_id,'classification_id',v_history_id,
    'catalog_state','promoted','classification',v_resolution,
    'comparison_ready',v_resolution->>'classification_status'='confirmed' and exists (
      select 1 from fitmatch_catalog.product_variants v
      join fitmatch_catalog.product_sizes s on s.variant_id=v.id and s.is_active
      join fitmatch_catalog.product_measurements m
        on m.product_size_id=s.id and m.is_comparable
      where v.product_id=v_product_id and v.is_active
    )
  );
end $$;

create or replace function fitmatch_qa.validate_product_runtime_v2()
returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog,fitmatch_qa,fitmatch_taxonomy
as $$
declare
  v_base jsonb:=fitmatch_qa.validate_product_runtime();
  v_auto_profiles integer;
  v_auto_wrong integer;
  v_exclusion_profiles integer;
  v_detail_rules integer;
  v_cross_major_blocked boolean;
  v_manual_extended boolean;
  v_candidate_rpc_anon boolean;
begin
  with d as (
    select d.*,
      fitmatch_catalog.runtime_normalized_category_path(source_category_path) path_key,
      fitmatch_catalog.runtime_product_name_signature(product_name) signature
    from fitmatch_catalog.product_classification_decisions d
  ), picked as (
    select d.*,
      coalesce(n.category_code,p.category_code) a_category,
      coalesce(n.detail_code,p.detail_code) a_detail,
      coalesce(n.comparison_family_code,p.comparison_family_code) a_family,
      coalesce(n.length_code,p.length_code) a_length,
      n.source is not null or p.source is not null selected
    from d
    left join fitmatch_catalog.classification_name_profiles n
      on n.policy_version='db-auto-classifier-2026-08-18-v2'
     and n.source=d.source and n.normalized_path=d.path_key
     and n.name_signature=d.signature and n.auto_eligible
    left join fitmatch_catalog.classification_path_profiles p
      on p.policy_version='db-auto-classifier-2026-08-18-v2'
     and p.source=d.source and p.normalized_path=d.path_key and p.auto_eligible
  )
  select count(*) filter(where selected),count(*) filter(where selected and
    (a_category,a_detail,a_family,a_length) is distinct from
    (category_code,detail_code,comparison_family,length_type))
  into v_auto_profiles,v_auto_wrong from picked;

  select count(*) into v_exclusion_profiles
  from fitmatch_catalog.classification_exclusion_profiles where auto_eligible;
  select count(*) into v_detail_rules
  from fitmatch_taxonomy.comparison_detail_compatibility_rules;
  v_cross_major_blocked:=not coalesce((
    fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
      'tops','MEN','tshirt','short_sleeve','short_sleeve',null,
      'bottoms','MEN','pants','long_pants','long_sleeve',null,true
    )->>'allowed')::boolean,false);
  v_manual_extended:=coalesce((
    fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
      'tops','MEN','tshirt','short_sleeve','short_sleeve',null,
      'tops','MEN','hoodie','hoodie','long_sleeve',null,true
    )->>'level')='extended',false);
  select has_function_privilege('anon',
    'public.fitmatch_find_reference_candidates(uuid)','EXECUTE')
  into v_candidate_rpc_anon;

  return v_base||jsonb_build_object(
    'passed',coalesce((v_base->>'passed')::boolean,false)
      and v_auto_wrong=0 and v_cross_major_blocked and v_manual_extended
      and not v_candidate_rpc_anon,
    'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
    'comparison_policy_version','db-comparison-2026-08-18-v2',
    'new_product_auto_profile_cases',v_auto_profiles,
    'new_product_auto_profile_mismatches',v_auto_wrong,
    'automatic_exclusion_paths',v_exclusion_profiles,
    'detail_rule_rows',v_detail_rules,
    'cross_major_blocked',v_cross_major_blocked,
    'manual_extended_supported',v_manual_extended,
    'candidate_rpc_anon_execute',v_candidate_rpc_anon
  );
end $$;

revoke all on function fitmatch_catalog.runtime_resolve_product_classification_v3(
  text,text,text,text,jsonb
) from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_qa.validate_product_runtime_v2()
  from public,anon,authenticated;
grant execute on function fitmatch_catalog.runtime_resolve_product_classification_v3(
  text,text,text,text,jsonb
),fitmatch_catalog.runtime_resolve_and_promote_product(jsonb),
  fitmatch_qa.validate_product_runtime_v2() to service_role;

do $$
declare v_result jsonb;
begin
  v_result:=fitmatch_qa.validate_product_runtime_v2();
  if not coalesce((v_result->>'passed')::boolean,false) then
    raise exception 'product runtime v2 validation failed: %',v_result;
  end if;
end $$;

commit;
;
