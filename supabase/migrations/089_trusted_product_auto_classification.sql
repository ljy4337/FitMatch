begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:trusted-product-auto-classification-v2'));

insert into fitmatch_taxonomy.policy_versions (
  code,schema_version,taxonomy_version,manifest_checksum,status,validated_at
) values (
  'db-auto-classifier-2026-08-18-v2','2.1','fitmatch-runtime-2026-08-18',
  '9bd720f6e2a5c4b3e5a6be0c804d8f98b8db17b684cab78636d844d471240928',
  'validated',now()
)
on conflict (code) do nothing;

-- A compact, deterministic structural signature. It is not itself a
-- classifier: it only selects a unanimous, parity-verified Gold profile.
create or replace function fitmatch_catalog.runtime_product_name_signature(
  p_product_name text
) returns text
language sql
immutable
security invoker
set search_path=pg_catalog
as $$
  with n as (
    select lower(regexp_replace(btrim(coalesce(p_product_name,'')), E'\\s+', ' ', 'g')) v
  )
  select concat_ws('|',
    case when v ~ '(세트|set([[:space:][:punct:]]|$))' then 'set' end,
    case when v ~ '(후드[[:space:]]*집업|집업[[:space:]]*후드|zip[- ]?hood)' then 'zip_hoodie' end,
    case when v ~ '(후디|후드[[:space:]]*티|hoodie)' then 'hoodie' end,
    case when v ~ '(스웨트[[:space:]]*셔츠|맨투맨|sweatshirt)' then 'sweatshirt' end,
    case when v ~ '(가디건|카디건|cardigan)' then 'cardigan' end,
    case when v ~ '(니트|스웨터|knit|sweater)' then 'knit' end,
    case when v ~ '(폴로[[:space:]]*셔츠|카라[[:space:]]*티|polo[[:space:]]*shirt)' then 'polo' end,
    case when v ~ '(블라우스|blouse)' then 'blouse' end,
    case when v ~ '(셔츠|남방|(^|[^[:alpha:]])shirt([^[:alpha:]]|$))' then 'shirt' end,
    case when v ~ '(민소매|나시|슬리브리스|sleeveless)' then 'sleeveless' end,
    case when v ~ '(반팔|반소매|숏[ -]?슬리브|short[ -]?sleeve|s/s([[:space:][:punct:]]|$))' then 'short_sleeve' end,
    case when v ~ '(긴팔|긴소매|롱[ -]?슬리브|long[ -]?sleeve|l/s([[:space:][:punct:]]|$))' then 'long_sleeve' end,
    case when v ~ '(레깅스|타이즈|타이츠|leggings)' then 'leggings' end,
    case when v ~ '(스코츠|스커트|치마|skorts?|skirt)' then 'skirt' end,
    case when v ~ '(반바지|숏[[:space:]]*팬츠|쇼트[[:space:]]*팬츠|쇼츠|버뮤다|shorts)' then 'shorts' end,
    case when v ~ '(데님|청바지|denim|jeans)' then 'denim' end,
    case when v ~ '(슬랙스|slacks|trousers)' then 'slacks' end,
    case when v ~ '(팬츠|바지|(^|[^[:alpha:]])pants([^[:alpha:]]|$))' then 'pants' end,
    case when v ~ '(원피스|(^|[^[:alpha:]])dress([^[:alpha:]]|$))' then 'dress' end,
    case when v ~ '(바람막이|윈드브레이커|windbreaker)' then 'windbreaker' end,
    case when v ~ '(아노락|anorak)' then 'anorak' end,
    case when v ~ '(블레이저|blazer)' then 'blazer' end,
    case when v ~ '(블루종|ma-1|blouson)' then 'blouson' end,
    case when v ~ '(플리스|후리스|fleece)' then 'fleece' end,
    case when v ~ '(패딩|다운[[:space:]]*(재킷|자켓|파카)|puffer|padding)' then 'padding' end,
    case when v ~ '(트렌치|코트|trench|(^|[^[:alpha:]])coat([^[:alpha:]]|$))' then 'coat' end,
    case when v ~ '(재킷|자켓|jacket)' then 'jacket' end,
    case when v ~ '(조끼|베스트|(^|[^[:alpha:]])vest([^[:alpha:]]|$))' then 'vest' end,
    case when v ~ '(브라탑|브라렛|브래지어|(^|[^[:alpha:]])bra([^[:alpha:]]|$))' then 'bra' end,
    case when v ~ '(복서[[:space:]]*브리프|브리프|(^|[^[:alpha:]])briefs?([^[:alpha:]]|$))' then 'briefs' end,
    case when v ~ '(트렁크|trunks?)' then 'trunks' end,
    case when v ~ '(캐미솔|캐미숄|camisole)' then 'camisole' end,
    case when v ~ '(라운지|파자마|lounge|pajama|pyjama)' then 'loungewear' end
  )
  from n
$$;

create or replace function fitmatch_catalog.runtime_normalized_category_path(
  p_path text
) returns text
language sql
immutable
security invoker
set search_path=pg_catalog
as $$
  select lower(regexp_replace(btrim(coalesce(p_path,'')), E'\\s*>\\s*', ' > ', 'g'))
$$;

create table if not exists fitmatch_catalog.classification_path_profiles (
  policy_version text not null
    references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  source text not null,
  normalized_path text not null,
  category_code text,
  detail_code text,
  comparison_family_code text,
  length_code text,
  sample_count integer not null,
  review_count integer not null,
  distinct_decision_count integer not null,
  auto_eligible boolean not null,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  primary key (policy_version,source,normalized_path),
  constraint classification_path_profiles_counts_check check (
    sample_count > 0 and review_count >= 0 and distinct_decision_count >= 0
  ),
  constraint classification_path_profiles_evidence_check
    check (jsonb_typeof(evidence)='object')
);

create table if not exists fitmatch_catalog.classification_name_profiles (
  policy_version text not null
    references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  source text not null,
  normalized_path text not null,
  name_signature text not null,
  category_code text,
  detail_code text,
  comparison_family_code text,
  length_code text,
  sample_count integer not null,
  review_count integer not null,
  distinct_decision_count integer not null,
  auto_eligible boolean not null,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  primary key (policy_version,source,normalized_path,name_signature),
  constraint classification_name_profiles_signature_check
    check (btrim(name_signature)<>''),
  constraint classification_name_profiles_counts_check check (
    sample_count > 0 and review_count >= 0 and distinct_decision_count >= 0
  ),
  constraint classification_name_profiles_evidence_check
    check (jsonb_typeof(evidence)='object')
);

create index if not exists classification_path_profiles_runtime_idx
  on fitmatch_catalog.classification_path_profiles
    (source,normalized_path,policy_version)
  where auto_eligible;
create index if not exists classification_name_profiles_runtime_idx
  on fitmatch_catalog.classification_name_profiles
    (source,normalized_path,name_signature,policy_version)
  where auto_eligible;

alter table fitmatch_catalog.classification_path_profiles enable row level security;
alter table fitmatch_catalog.classification_name_profiles enable row level security;
revoke all on fitmatch_catalog.classification_path_profiles,
  fitmatch_catalog.classification_name_profiles from public,anon,authenticated;
grant select,insert,update,delete on fitmatch_catalog.classification_path_profiles,
  fitmatch_catalog.classification_name_profiles to service_role;

with grouped as (
  select
    source,
    fitmatch_catalog.runtime_normalized_category_path(source_category_path) normalized_path,
    count(*) sample_count,
    count(*) filter (where requires_user_confirmation) review_count,
    count(distinct row(category_code,detail_code,comparison_family,length_type))
      filter (where not requires_user_confirmation) distinct_decision_count,
    min(category_code) filter (where not requires_user_confirmation) category_code,
    min(detail_code) filter (where not requires_user_confirmation) detail_code,
    min(comparison_family) filter (where not requires_user_confirmation) comparison_family_code,
    min(length_type) filter (where not requires_user_confirmation) length_code
  from fitmatch_catalog.product_classification_decisions
  group by 1,2
)
insert into fitmatch_catalog.classification_path_profiles (
  policy_version,source,normalized_path,category_code,detail_code,
  comparison_family_code,length_code,sample_count,review_count,
  distinct_decision_count,auto_eligible,evidence
)
select
  'db-auto-classifier-2026-08-18-v2',source,normalized_path,
  category_code,detail_code,comparison_family_code,length_code,
  sample_count,review_count,distinct_decision_count,
  sample_count>=2 and review_count=0 and distinct_decision_count=1
    and category_code is not null and detail_code is not null
    and comparison_family_code is not null
    and category_code<>'other' and detail_code<>'other',
  jsonb_build_object('source','product_classification_decisions',
    'minimum_samples',2,'gold_policy','swift-production-2026-08-16-v3')
from grouped
where normalized_path<>''
on conflict (policy_version,source,normalized_path) do update set
  category_code=excluded.category_code,detail_code=excluded.detail_code,
  comparison_family_code=excluded.comparison_family_code,
  length_code=excluded.length_code,sample_count=excluded.sample_count,
  review_count=excluded.review_count,
  distinct_decision_count=excluded.distinct_decision_count,
  auto_eligible=excluded.auto_eligible,evidence=excluded.evidence;

with decisions as (
  select
    source,
    fitmatch_catalog.runtime_normalized_category_path(source_category_path) normalized_path,
    fitmatch_catalog.runtime_product_name_signature(product_name) name_signature,
    category_code,detail_code,comparison_family,length_type,
    requires_user_confirmation
  from fitmatch_catalog.product_classification_decisions
), grouped as (
  select source,normalized_path,name_signature,count(*) sample_count,
    count(*) filter (where requires_user_confirmation) review_count,
    count(distinct row(category_code,detail_code,comparison_family,length_type))
      filter (where not requires_user_confirmation) distinct_decision_count,
    min(category_code) filter (where not requires_user_confirmation) category_code,
    min(detail_code) filter (where not requires_user_confirmation) detail_code,
    min(comparison_family) filter (where not requires_user_confirmation) comparison_family_code,
    min(length_type) filter (where not requires_user_confirmation) length_code
  from decisions
  where normalized_path<>'' and name_signature<>''
  group by 1,2,3
)
insert into fitmatch_catalog.classification_name_profiles (
  policy_version,source,normalized_path,name_signature,category_code,detail_code,
  comparison_family_code,length_code,sample_count,review_count,
  distinct_decision_count,auto_eligible,evidence
)
select
  'db-auto-classifier-2026-08-18-v2',source,normalized_path,name_signature,
  category_code,detail_code,comparison_family_code,length_code,
  sample_count,review_count,distinct_decision_count,
  sample_count>=2 and review_count=0 and distinct_decision_count=1
    and category_code is not null and detail_code is not null
    and comparison_family_code is not null
    and category_code<>'other' and detail_code<>'other',
  jsonb_build_object('source','product_classification_decisions',
    'minimum_samples',2,'gold_policy','swift-production-2026-08-16-v3')
from grouped
on conflict (policy_version,source,normalized_path,name_signature) do update set
  category_code=excluded.category_code,detail_code=excluded.detail_code,
  comparison_family_code=excluded.comparison_family_code,
  length_code=excluded.length_code,sample_count=excluded.sample_count,
  review_count=excluded.review_count,
  distinct_decision_count=excluded.distinct_decision_count,
  auto_eligible=excluded.auto_eligible,evidence=excluded.evidence;

create or replace function fitmatch_catalog.runtime_resolve_source_mapping(
  p_payload jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare
  v_source text:=lower(btrim(coalesce(p_payload->>'source','')));
  v_target text:=upper(nullif(btrim(coalesce(p_payload->>'audience','')),''));
  v_path text:=fitmatch_catalog.runtime_normalized_category_path(
    p_payload->>'source_category_path'
  );
  v_release_id uuid;
  v_result jsonb;
begin
  select id into v_release_id from fitmatch_catalog.releases
  where status='active' order by activated_at desc nulls last,created_at desc limit 1;

  if jsonb_typeof(p_payload->'source_category_codes')='array'
     and jsonb_array_length(p_payload->'source_category_codes')>0 then
    with codes as (
      select value code,ordinality
      from jsonb_array_elements_text(p_payload->'source_category_codes')
        with ordinality
    ), candidates as (
      select m.*,c.ordinality,
        max(c.ordinality) over () max_ordinality
      from codes c
      join fitmatch_catalog.source_category_mappings m
        on m.release_id=v_release_id and m.source=v_source
       and m.external_category_id=c.code
       and (v_target is null or m.target=v_target)
    ), leaf as (
      select * from candidates where ordinality=max_ordinality
    )
    select case when count(*)=0 then null else jsonb_build_object(
      'found',true,
      'ambiguous',count(distinct row(decision_status,semantic_category_code,
        semantic_garment_type,comparison_family,eligibility))>1,
      'release_id',v_release_id,
      'source_identity',min(source_identity),
      'external_category_id',min(external_category_id),
      'target',min(target),
      'normalized_path',min(normalized_path),
      'decision_status',min(decision_status),
      'runtime_lookup_eligible',bool_and(runtime_lookup_eligible),
      'eligibility',bool_and(coalesce(eligibility,false)),
      'semantic_category_code',min(semantic_category_code),
      'semantic_garment_type',min(semantic_garment_type),
      'comparison_family',min(comparison_family),
      'match_method','external_category_id'
    ) end into v_result from leaf;
  end if;

  if v_result is null and v_path<>'' then
    with candidates as (
      select * from fitmatch_catalog.source_category_mappings
      where release_id=v_release_id and source=v_source
        and fitmatch_catalog.runtime_normalized_category_path(normalized_path)=v_path
        and (v_target is null or target=v_target)
    )
    select case when count(*)=0 then null else jsonb_build_object(
      'found',true,
      'ambiguous',count(distinct row(decision_status,semantic_category_code,
        semantic_garment_type,comparison_family,eligibility))>1,
      'release_id',v_release_id,
      'source_identity',min(source_identity),
      'external_category_id',min(external_category_id),
      'target',min(target),
      'normalized_path',min(normalized_path),
      'decision_status',min(decision_status),
      'runtime_lookup_eligible',bool_and(runtime_lookup_eligible),
      'eligibility',bool_and(coalesce(eligibility,false)),
      'semantic_category_code',min(semantic_category_code),
      'semantic_garment_type',min(semantic_garment_type),
      'comparison_family',min(comparison_family),
      'match_method','normalized_path'
    ) end into v_result from candidates;
  end if;

  return coalesce(v_result,jsonb_build_object('found',false,'ambiguous',false,
    'release_id',v_release_id));
end $$;

create or replace function fitmatch_catalog.runtime_resolve_product_classification_v2(
  p_source text,
  p_external_product_id text,
  p_product_name text,
  p_source_category_path text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare
  v_exact jsonb;
  v_path text:=fitmatch_catalog.runtime_normalized_category_path(p_source_category_path);
  v_signature text:=fitmatch_catalog.runtime_product_name_signature(p_product_name);
  v_name_profile fitmatch_catalog.classification_name_profiles%rowtype;
  v_path_profile fitmatch_catalog.classification_path_profiles%rowtype;
  v_mapping jsonb;
  v_status text;
begin
  v_exact:=fitmatch_catalog.resolve_product_classification(
    lower(p_source),p_external_product_id,p_product_name,p_source_category_path
  );
  if v_exact->>'decision_source'='canonical_product_decision' then
    v_status:=case
      when coalesce((v_exact->>'requires_user_confirmation')::boolean,true)
        then 'review_required'
      when v_exact->>'category_code' is null or v_exact->>'detail_code' is null
        then 'unclassified'
      else 'confirmed' end;
    return v_exact||jsonb_build_object(
      'classification_status',v_status,
      'classification_method','canonical_product_decision',
      'confidence',case when v_status='confirmed' then 1 else null end,
      'classifier_policy_version','db-auto-classifier-2026-08-18-v2'
    );
  end if;

  if v_signature<>'' then
    select * into v_name_profile
    from fitmatch_catalog.classification_name_profiles
    where policy_version='db-auto-classifier-2026-08-18-v2'
      and source=lower(p_source) and normalized_path=v_path
      and name_signature=v_signature and auto_eligible;
  end if;
  if v_name_profile.policy_version is not null then
    return jsonb_build_object(
      'category_code',v_name_profile.category_code,
      'detail_code',v_name_profile.detail_code,
      'family_code',v_name_profile.comparison_family_code,
      'length_code',v_name_profile.length_code,
      'requires_user_confirmation',false,'comparable',true,
      'classification_status','confirmed','classification_method','product_classifier',
      'decision_source','verified_name_signature_profile',
      'decision_version','db-auto-classifier-2026-08-18-v2',
      'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
      'confidence',case when v_name_profile.sample_count>=5 then 0.99 else 0.96 end,
      'name_signature',v_signature,'sample_count',v_name_profile.sample_count,
      'evidence',v_name_profile.evidence
    );
  end if;

  select * into v_path_profile
  from fitmatch_catalog.classification_path_profiles
  where policy_version='db-auto-classifier-2026-08-18-v2'
    and source=lower(p_source) and normalized_path=v_path and auto_eligible;
  if v_path_profile.policy_version is not null then
    return jsonb_build_object(
      'category_code',v_path_profile.category_code,
      'detail_code',v_path_profile.detail_code,
      'family_code',v_path_profile.comparison_family_code,
      'length_code',v_path_profile.length_code,
      'requires_user_confirmation',false,'comparable',true,
      'classification_status','confirmed','classification_method','product_classifier',
      'decision_source','verified_path_profile',
      'decision_version','db-auto-classifier-2026-08-18-v2',
      'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
      'confidence',case when v_path_profile.sample_count>=5 then 0.98 else 0.95 end,
      'sample_count',v_path_profile.sample_count,'evidence',v_path_profile.evidence
    );
  end if;

  v_mapping:=fitmatch_catalog.runtime_resolve_source_mapping(
    coalesce(p_payload,'{}'::jsonb)||jsonb_build_object(
      'source',lower(p_source),'source_category_path',p_source_category_path
    )
  );
  if coalesce((v_mapping->>'found')::boolean,false)
     and not coalesce((v_mapping->>'ambiguous')::boolean,false)
     and (v_mapping->>'decision_status' in ('rejected','unsupported')
       or not coalesce((v_mapping->>'eligibility')::boolean,false)) then
    return jsonb_build_object(
      'category_code',null,'detail_code',null,'family_code',null,'length_code',null,
      'requires_user_confirmation',false,'comparable',false,
      'classification_status','not_comparable','classification_method','category_mapping',
      'decision_source','verified_category_exclusion',
      'decision_version','db-auto-classifier-2026-08-18-v2',
      'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
      'confidence',1,'source_mapping',v_mapping
    );
  end if;

  return jsonb_build_object(
    'category_code',null,'detail_code',null,'family_code',null,'length_code',null,
    'requires_user_confirmation',true,'comparable',false,
    'classification_status','review_required','classification_method','unknown',
    'decision_source','no_unanimous_verified_profile',
    'decision_version','db-auto-classifier-2026-08-18-v2',
    'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
    'name_signature',v_signature,'source_mapping',v_mapping,
    'legacy_suggestion',v_exact->'suggestion'
  );
end $$;

-- Trusted fetchers/batches call this after obtaining retailer data themselves.
-- It is deliberately unavailable to anon/authenticated clients.
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
    v_resolution:=fitmatch_catalog.runtime_resolve_product_classification_v2(
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
    'comparison_ready',
      v_resolution->>'classification_status'='confirmed' and exists (
        select 1 from fitmatch_catalog.product_variants v
        join fitmatch_catalog.product_sizes s on s.variant_id=v.id and s.is_active
        join fitmatch_catalog.product_measurements m
          on m.product_size_id=s.id and m.is_comparable
        where v.product_id=v_product_id and v.is_active
      )
  );
end $$;

-- Public lookup now compares the retailer category evidence when supplied.
-- It still cannot promote shared data; the trusted function above does that.
create or replace function public.fitmatch_resolve_product(
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_source text:=lower(btrim(coalesce(p_payload->>'source','')));
  v_external_id text:=btrim(coalesce(p_payload->>'external_product_id',''));
  v_name text:=btrim(coalesce(p_payload->>'product_name',''));
  v_path text:=nullif(btrim(coalesce(p_payload->>'source_category_path','')),'');
  v_audience text:=nullif(btrim(coalesce(p_payload->>'audience','')),'');
  v_codes text[]:=case when jsonb_typeof(p_payload->'source_category_codes')='array'
    then array(select jsonb_array_elements_text(p_payload->'source_category_codes'))
    else '{}'::text[] end;
  v_fingerprint text;
  v_product fitmatch_catalog.products%rowtype;
  v_history fitmatch_catalog.product_classification_history%rowtype;
  v_resolution jsonb;
  v_request_id uuid;
  v_category_evidence_matches boolean;
begin
  if v_user_id is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  if jsonb_typeof(p_payload)<>'object' or v_source !~ '^[a-z][a-z0-9_]*$'
     or v_external_id='' or length(v_external_id)>200
     or v_name='' or length(v_name)>1000
     or (p_payload ? 'source_category_codes'
       and jsonb_typeof(p_payload->'source_category_codes')<>'array') then
    raise exception using errcode='22023',message='invalid_product_payload';
  end if;

  v_fingerprint:=fitmatch_catalog.runtime_product_fingerprint(v_name,v_path);
  select * into v_product from fitmatch_catalog.products
  where source=v_source and external_product_id=v_external_id;
  v_category_evidence_matches:=found
    and (v_audience is null or upper(coalesce(v_product.audience,''))=upper(v_audience))
    and (cardinality(v_codes)=0 or v_product.source_category_codes=v_codes);

  if found and v_product.input_fingerprint=v_fingerprint
     and v_category_evidence_matches then
    select * into v_history from fitmatch_catalog.product_classification_history
    where product_id=v_product.id and input_fingerprint=v_fingerprint and is_current;
    if found then
      return jsonb_build_object(
        'product_id',v_product.id,'intake_request_id',null,'catalog_state','current',
        'category_evidence_matches',true,
        'classification',jsonb_build_object(
          'classification_id',v_history.id,'category_code',v_history.category_code,
          'detail_code',v_history.detail_code,'family_code',v_history.comparison_family_code,
          'length_code',v_history.length_code,'status',v_history.classification_status,
          'requires_user_confirmation',v_history.requires_user_confirmation,
          'decision_version',v_history.decision_version,'evidence',v_history.evidence
        ),
        'comparison_ready',v_history.classification_status='confirmed' and exists (
          select 1 from fitmatch_catalog.product_variants v
          join fitmatch_catalog.product_sizes s on s.variant_id=v.id and s.is_active
          join fitmatch_catalog.product_measurements m
            on m.product_size_id=s.id and m.is_comparable
          where v.product_id=v_product.id and v.is_active
        )
      );
    end if;
  end if;

  v_resolution:=fitmatch_catalog.runtime_resolve_product_classification_v2(
    v_source,v_external_id,v_name,coalesce(v_path,''),p_payload
  );
  insert into public.product_intake_requests (
    user_id,source,external_product_id,input_fingerprint,submitted_payload
  ) values (v_user_id,v_source,v_external_id,v_fingerprint,p_payload)
  on conflict (user_id,source,external_product_id,input_fingerprint)
  do update set submitted_payload=excluded.submitted_payload,updated_at=now()
  returning id into v_request_id;

  return jsonb_build_object(
    'product_id',case when v_product.id is null then null else v_product.id end,
    'intake_request_id',v_request_id,
    'catalog_state',case when v_product.id is null then 'new' else 'changed' end,
    'category_evidence_matches',coalesce(v_category_evidence_matches,false),
    'classification',jsonb_build_object(
      'classification_id',null,'category_code',null,'detail_code',null,
      'family_code',null,'length_code',null,'status','review_required',
      'requires_user_confirmation',true,'decision_version',null,
      'evidence',jsonb_build_object('trusted_backend_candidate',v_resolution)
    ),
    'comparison_ready',false
  );
end $$;

revoke all on fitmatch_catalog.classification_path_profiles,
  fitmatch_catalog.classification_name_profiles from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_product_name_signature(text)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_normalized_category_path(text)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_resolve_source_mapping(jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_resolve_product_classification_v2(text,text,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)
  from public,anon,authenticated;
grant execute on function fitmatch_catalog.runtime_product_name_signature(text),
  fitmatch_catalog.runtime_normalized_category_path(text),
  fitmatch_catalog.runtime_resolve_source_mapping(jsonb),
  fitmatch_catalog.runtime_resolve_product_classification_v2(text,text,text,text,jsonb),
  fitmatch_catalog.runtime_resolve_and_promote_product(jsonb) to service_role;

do $$
begin
  if exists (
    select 1 from fitmatch_catalog.classification_path_profiles
    where auto_eligible and (sample_count<2 or review_count<>0
      or distinct_decision_count<>1 or category_code is null
      or detail_code is null or comparison_family_code is null)
  ) then raise exception 'unsafe automatic path profile'; end if;
  if exists (
    select 1 from fitmatch_catalog.classification_name_profiles
    where auto_eligible and (sample_count<2 or review_count<>0
      or distinct_decision_count<>1 or category_code is null
      or detail_code is null or comparison_family_code is null)
  ) then raise exception 'unsafe automatic name profile'; end if;
end $$;

commit;
