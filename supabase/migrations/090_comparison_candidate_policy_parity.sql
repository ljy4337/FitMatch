begin;

set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtext('fitmatch:comparison-candidate-policy-v2'));

insert into fitmatch_taxonomy.policy_versions (
  code,schema_version,taxonomy_version,manifest_checksum,status,validated_at
) values (
  'db-comparison-2026-08-18-v2','2.2','fitmatch-runtime-2026-08-18',
  '0369c6aa56010c67a1fbf6ee7bc8a335475ec061ce48ddf14db1745d8de2dd43',
  'validated',now()
)
on conflict (code) do nothing;

-- The local matcher treats outer body length as a separate axis from sleeve
-- or pants length. Preserve that distinction in shared and user snapshots.
alter table fitmatch_catalog.product_classification_history
  add column if not exists body_length_code text;
alter table public.closet_items
  add column if not exists comparison_body_length_code text;
alter table public.closet_item_classification_overrides
  add column if not exists body_length_code text;

create or replace function fitmatch_catalog.runtime_infer_body_length_code(
  p_category_code text,p_product_name text,p_source_category_path text
) returns text
language sql
immutable
security invoker
set search_path=pg_catalog
as $$
  with n as (
    select lower(coalesce(p_product_name,'')||' '||coalesce(p_source_category_path,'')) v
  )
  select case
    when p_category_code<>'outerwear' then null
    when v ~ '(크롭|cropped?[ -]?(jacket|coat|cardigan))' then 'cropped'
    when v ~ '(숏|쇼트|short)[ -]?(재킷|자켓|코트|패딩|파카|jacket|coat|parka|padding)'
      then 'short'
    when v ~ '(하프|미디|half|midi)[ -]?(재킷|자켓|코트|jacket|coat)'
      then 'three_quarter'
    when v ~ '(롱|맥시|long|maxi)[ -]?(재킷|자켓|코트|패딩|파카|jacket|coat|parka)'
      then 'long'
    else null end
  from n
$$;

create or replace function fitmatch_catalog.sync_product_body_length()
returns trigger
language plpgsql
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare v_product fitmatch_catalog.products%rowtype;
begin
  if new.body_length_code is null and new.category_code='outerwear' then
    select * into v_product from fitmatch_catalog.products where id=new.product_id;
    new.body_length_code:=fitmatch_catalog.runtime_infer_body_length_code(
      new.category_code,v_product.product_name,v_product.source_category_path
    );
  end if;
  return new;
end $$;

drop trigger if exists product_classification_sync_body_length
  on fitmatch_catalog.product_classification_history;
create trigger product_classification_sync_body_length
before insert or update of product_id,category_code,body_length_code
on fitmatch_catalog.product_classification_history
for each row execute function fitmatch_catalog.sync_product_body_length();

update fitmatch_catalog.product_classification_history h
set body_length_code=fitmatch_catalog.runtime_infer_body_length_code(
  h.category_code,p.product_name,p.source_category_path
)
from fitmatch_catalog.products p
where p.id=h.product_id and h.category_code='outerwear'
  and h.body_length_code is null;

update public.closet_items c
set comparison_body_length_code=h.body_length_code
from fitmatch_catalog.product_classification_history h
where h.id=c.canonical_classification_id
  and c.comparison_body_length_code is null;

create or replace function fitmatch_catalog.sync_closet_body_length()
returns trigger
language plpgsql
security invoker
set search_path=pg_catalog,public,fitmatch_catalog
as $$
declare v_history_body text; v_product fitmatch_catalog.products%rowtype;
begin
  if new.comparison_body_length_code is null then
    select body_length_code into v_history_body
    from fitmatch_catalog.product_classification_history
    where id=new.canonical_classification_id;
    new.comparison_body_length_code:=v_history_body;
  end if;
  if new.comparison_body_length_code is null and new.product_id is not null then
    select * into v_product from fitmatch_catalog.products where id=new.product_id;
    new.comparison_body_length_code:=fitmatch_catalog.runtime_infer_body_length_code(
      coalesce(new.canonical_category_code,new.app_category),
      v_product.product_name,v_product.source_category_path
    );
  end if;
  return new;
end $$;

drop trigger if exists closet_items_sync_body_length on public.closet_items;
create trigger closet_items_sync_body_length
before insert or update of product_id,canonical_classification_id,
  canonical_category_code,comparison_body_length_code
on public.closet_items
for each row execute function fitmatch_catalog.sync_closet_body_length();

create or replace function public.fitmatch_set_closet_classification_override(
  p_closet_item_id uuid,p_override jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_user_id uuid:=(select auth.uid());
begin
  if v_user_id is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  if jsonb_typeof(p_override)<>'object'
     or nullif(p_override->>'category_code','') is null
     or nullif(p_override->>'detail_code','') is null
     or nullif(p_override->>'family_code','') is null then
    raise exception using errcode='22023',message='invalid_override';
  end if;
  if not exists(select 1 from public.closet_items
    where id=p_closet_item_id and user_id=v_user_id and deleted_at is null) then
    raise exception using errcode='P0002',message='closet_item_not_found';
  end if;
  insert into public.closet_item_classification_overrides (
    closet_item_id,user_id,category_code,detail_code,comparison_family_code,
    length_code,body_length_code,reason,evidence
  ) values (
    p_closet_item_id,v_user_id,p_override->>'category_code',p_override->>'detail_code',
    nullif(p_override->>'family_code',''),nullif(p_override->>'length_code',''),
    nullif(p_override->>'body_length_code',''),nullif(p_override->>'reason',''),
    case when jsonb_typeof(p_override->'evidence')='object'
      then p_override->'evidence' else '{}'::jsonb end
  )
  on conflict (closet_item_id,user_id) do update set
    category_code=excluded.category_code,detail_code=excluded.detail_code,
    comparison_family_code=excluded.comparison_family_code,
    length_code=excluded.length_code,body_length_code=excluded.body_length_code,
    reason=excluded.reason,evidence=excluded.evidence,updated_at=now();
  update public.closet_items set
    app_category=p_override->>'category_code',
    app_detail_category=p_override->>'detail_code',
    classification_source='manual_override',updated_at=now()
  where id=p_closet_item_id and user_id=v_user_id;
  return jsonb_build_object(
    'closet_item_id',p_closet_item_id,
    'category_code',p_override->>'category_code',
    'detail_code',p_override->>'detail_code',
    'family_code',p_override->>'family_code',
    'length_code',p_override->>'length_code',
    'body_length_code',p_override->>'body_length_code'
  );
end $$;

-- Expression index keeps trusted batch/category lookup bounded even when a
-- whole corpus is resolved in one job.
create index if not exists source_category_mappings_normalized_runtime_idx
  on fitmatch_catalog.source_category_mappings (
    release_id,source,
    fitmatch_catalog.runtime_normalized_category_path(normalized_path),target
  );

-- Cross-family pairs explicitly supported by the production matcher.
insert into fitmatch_taxonomy.comparison_compatibility_rules (
  from_family_code,to_family_code,allowed,directional,length_match_required,
  length_mismatch_excluded_measurements,minimum_common_measurements,
  required_measurements,required_any_measurements,minimum_required_any,
  measurement_weights,fallback_allowed,policy_version
) values
  ('sweatshirt','hoodie',true,false,true,array['sleeve_length'],2,
   array[]::text[],array['shoulder','chest'],1,
   '{"shoulder":1.2,"chest":1.4,"total_length":1.0,"sleeve_length":0.8}',
   true,'db-comparison-2026-08-18-v2'),
  ('outerwear','hoodie',true,false,true,array['sleeve_length'],2,
   array['chest'],array[]::text[],0,
   '{"shoulder":1.1,"chest":1.5,"total_length":0.8,"sleeve_length":1.0,"hem":0.6}',
   true,'db-comparison-2026-08-18-v2')
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

create or replace function fitmatch_catalog.runtime_normalize_gender(
  p_gender text
) returns text
language sql
immutable
security invoker
set search_path=pg_catalog
as $$
  select case upper(btrim(coalesce(p_gender,'')))
    when 'MEN' then 'male' when 'MALE' then 'male'
    when 'WOMEN' then 'female' when 'FEMALE' then 'female'
    when 'BOYS' then 'boys' when 'BOY' then 'boys'
    when 'GIRLS' then 'girls' when 'GIRL' then 'girls'
    when 'KIDS' then 'kids_unisex' when 'KIDS_UNISEX' then 'kids_unisex'
    when 'BABY' then 'baby' when 'UNISEX' then 'unisex'
    else 'unknown' end
$$;

create or replace function fitmatch_catalog.runtime_genders_are_compatible(
  p_reference_gender text,p_target_gender text,p_family text
) returns boolean
language sql
immutable
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
  with g as (
    select fitmatch_catalog.runtime_normalize_gender(p_reference_gender) r,
      fitmatch_catalog.runtime_normalize_gender(p_target_gender) t
  )
  select case
    when r='unknown' or t='unknown' then true
    when r in ('boys','girls','kids_unisex') or t in ('boys','girls','kids_unisex')
      then r in ('boys','girls','kids_unisex') and t in ('boys','girls','kids_unisex')
    when r='baby' or t='baby' then r='baby' and t='baby'
    when r='unisex' or t='unisex' then true
    when r in ('male','female') and t in ('male','female') then
      r=t or p_family in ('knit_cardigan','tshirt','shirt','sweatshirt','hoodie',
        'pants','denim','leggings','skirt','outerwear','leather_jacket','shoes')
    else r=t end
  from g
$$;

create or replace function fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
  p_reference_category text,p_reference_gender text,p_reference_family text,
  p_reference_detail text,p_reference_length text,p_reference_body_length text,
  p_target_category text,p_target_gender text,p_target_family text,
  p_target_detail text,p_target_length text,p_target_body_length text,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_taxonomy,fitmatch_catalog
as $$
declare
  v_rule fitmatch_taxonomy.comparison_compatibility_rules%rowtype;
  v_family_pair text[];
  v_family_compatible boolean:=false;
  v_detail_direct boolean:=false;
  v_manual_expansion boolean:=false;
  v_length_required boolean:=false;
  v_length_mismatch boolean:=false;
  v_body_mismatch boolean:=false;
  v_level text;
  v_excluded text[]:='{}'::text[];
begin
  if p_reference_category is null or p_target_category is null
     or p_reference_category<>p_target_category then
    return jsonb_build_object('allowed',false,'level','incompatible',
      'reason','major_category_incompatible');
  end if;
  if p_reference_family is null or p_target_family is null
     or p_reference_family='unknown' or p_target_family='unknown' then
    return jsonb_build_object('allowed',false,'level','incompatible',
      'reason','comparison_family_missing');
  end if;
  if p_reference_detail is null or p_target_detail is null then
    return jsonb_build_object('allowed',false,'level','incompatible',
      'reason','comparison_detail_missing');
  end if;
  if not fitmatch_catalog.runtime_genders_are_compatible(
    p_reference_gender,p_target_gender,p_target_family
  ) then
    return jsonb_build_object('allowed',false,'level','incompatible',
      'reason','gender_incompatible');
  end if;

  v_family_pair:=array(select x from unnest(array[p_reference_family,p_target_family]) x order by x);
  v_family_compatible:=p_reference_family=p_target_family
    or v_family_pair=array['denim','pants']
    or v_family_pair=array['hoodie','sweatshirt']
    or v_family_pair=array['hoodie','outerwear'];

  if v_family_pair=array['denim','pants']
     or v_family_pair=array['hoodie','sweatshirt'] then
    v_detail_direct:=true;
  elsif p_reference_family=p_target_family and p_reference_detail=p_target_detail then
    v_detail_direct:=true;
  elsif p_reference_family=p_target_family and p_reference_category='tops' then
    v_detail_direct:=not (
      p_reference_detail in ('sleeveless','short_sleeve','three_quarter_sleeve','long_sleeve')
      and p_target_detail in ('sleeveless','short_sleeve','three_quarter_sleeve','long_sleeve')
    );
  elsif p_reference_category='bottoms'
    and p_reference_family in ('pants','denim') and p_target_family in ('pants','denim') then
    v_detail_direct:=(array[p_reference_detail,p_target_detail] <@ array['short_pants','shorts'])
      or (array[p_reference_detail,p_target_detail] <@ array[
        'long_pants','slacks','denim','training_pants'
      ]);
  end if;

  v_length_required:=p_reference_family in (
      'knit_cardigan','tshirt','shirt','sweatshirt','hoodie','pants','denim',
      'leggings','outerwear','leather_jacket','skirt','dress'
    ) or p_target_family in (
      'knit_cardigan','tshirt','shirt','sweatshirt','hoodie','pants','denim',
      'leggings','outerwear','leather_jacket','skirt','dress'
    );
  if v_length_required and (p_reference_length is null or p_target_length is null
    or p_reference_length='unknown' or p_target_length='unknown') then
    return jsonb_build_object('allowed',false,'level','incompatible',
      'reason','length_classification_missing');
  end if;
  v_length_mismatch:=v_length_required and p_reference_length<>p_target_length;

  if p_reference_category='outerwear' then
    if p_reference_body_length is null or p_target_body_length is null
       or p_reference_body_length='unknown' or p_target_body_length='unknown' then
      return jsonb_build_object('allowed',false,'level','incompatible',
        'reason','body_length_classification_missing');
    end if;
    v_body_mismatch:=p_reference_body_length<>p_target_body_length;
  end if;

  if p_allow_extended then
    v_manual_expansion:=
      (p_reference_category='tops' and p_reference_length in ('sleeveless','short_sleeve')
        and p_target_length in ('sleeveless','short_sleeve'))
      or (p_reference_category='tops'
        and array[p_reference_length,p_target_length] @> array['short_sleeve','long_sleeve'])
      or (p_reference_category='bottoms'
        and p_reference_family in ('pants','denim') and p_target_family in ('pants','denim')
        and v_length_mismatch)
      or (p_reference_category='outerwear' and (
        array[p_reference_detail,p_target_detail] <@ array[
          'jumper','jacket','windbreaker','anorak','blouson','fleece','hoodie'
        ] or array[p_reference_detail,p_target_detail] <@ array['jacket','blazer','blouson']
        or array[p_reference_detail,p_target_detail] <@ array[
          'padding','light_padding','short_padding','long_padding','padded_vest'
        ] or array[p_reference_detail,p_target_detail] <@ array['coat','trench_coat','mouton']
      ));
  end if;

  if not ((v_family_compatible and v_detail_direct and not v_length_mismatch
      and not v_body_mismatch) or v_manual_expansion) then
    return jsonb_build_object('allowed',false,'level','incompatible',
      'reason',case
        when not v_family_compatible then 'family_incompatible'
        when not v_detail_direct then 'detail_incompatible'
        when v_length_mismatch then 'length_mismatch'
        when v_body_mismatch then 'body_length_mismatch'
        else 'compatibility_rule_missing' end);
  end if;

  if v_length_mismatch and p_reference_category='tops' then
    v_excluded:=array_append(v_excluded,'sleeve_length');
  elsif v_length_mismatch and p_reference_category='bottoms' then
    v_excluded:=array['total_length','hem'];
  end if;
  v_level:=case when v_manual_expansion or v_length_mismatch or v_body_mismatch
    then 'extended' else 'direct' end;

  select r.* into v_rule
  from fitmatch_taxonomy.comparison_compatibility_rules r
  left join fitmatch_taxonomy.policy_versions pv on pv.code=r.policy_version
  where (r.from_family_code=p_reference_family and r.to_family_code=p_target_family)
     or (not r.directional and r.from_family_code=p_target_family
       and r.to_family_code=p_reference_family)
  order by pv.created_at desc nulls last limit 1;

  return jsonb_build_object(
    'allowed',true,'level',v_level,'reason',null,
    'reference_category',p_reference_category,'target_category',p_target_category,
    'reference_family',p_reference_family,'target_family',p_target_family,
    'reference_detail',p_reference_detail,'target_detail',p_target_detail,
    'reference_length',p_reference_length,'target_length',p_target_length,
    'reference_body_length',p_reference_body_length,
    'target_body_length',p_target_body_length,
    'length_mismatch',v_length_mismatch,'body_length_mismatch',v_body_mismatch,
    'excluded_measurements',to_jsonb(v_excluded),
    'minimum_common_measurements',coalesce(v_rule.minimum_common_measurements,2),
    'required_measurements',to_jsonb(coalesce(v_rule.required_measurements,'{}'::text[])),
    'required_any_measurements',to_jsonb(coalesce(v_rule.required_any_measurements,'{}'::text[])),
    'minimum_required_any',coalesce(v_rule.minimum_required_any,0),
    'measurement_weights',coalesce(v_rule.measurement_weights,'{}'::jsonb),
    'policy_version','db-comparison-2026-08-18-v2'
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
  vr fitmatch_catalog.product_classification_history%rowtype;
  vt fitmatch_catalog.product_classification_history%rowtype;
  pr fitmatch_catalog.products%rowtype;
  pt fitmatch_catalog.products%rowtype;
begin
  select * into vr from fitmatch_catalog.product_classification_history
    where product_id=p_reference_product_id and is_current;
  select * into vt from fitmatch_catalog.product_classification_history
    where product_id=p_target_product_id and is_current;
  select * into pr from fitmatch_catalog.products where id=p_reference_product_id;
  select * into pt from fitmatch_catalog.products where id=p_target_product_id;
  if vr.id is null or vt.id is null then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','classification_missing');
  end if;
  if vr.classification_status<>'confirmed' or vt.classification_status<>'confirmed' then
    return jsonb_build_object('allowed',false,'level','incompatible','reason','classification_not_confirmed');
  end if;
  return fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    vr.category_code,pr.audience,vr.comparison_family_code,vr.detail_code,
    vr.length_code,vr.body_length_code,
    vt.category_code,pt.audience,vt.comparison_family_code,vt.detail_code,
    vt.length_code,vt.body_length_code,p_allow_extended
  );
end $$;

create or replace function fitmatch_catalog.runtime_max_measurement_overlap(
  p_reference_size_id uuid,p_target_product_id uuid,p_excluded jsonb default '[]'::jsonb
) returns integer
language sql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
  with overlap_counts as (
    select ts.id,count(*) n
    from fitmatch_catalog.product_measurements r
    join fitmatch_catalog.product_variants tv on tv.product_id=p_target_product_id and tv.is_active
    join fitmatch_catalog.product_sizes ts on ts.variant_id=tv.id and ts.is_active
    join fitmatch_catalog.product_measurements t
      on t.product_size_id=ts.id and t.is_comparable
     and t.measurement_kind=r.measurement_kind
     and t.comparison_basis=r.comparison_basis
    where r.product_size_id=p_reference_size_id and r.is_comparable
      and r.measurement_kind is not null and r.comparison_basis is not null
      and not (coalesce(p_excluded,'[]'::jsonb) ? r.measurement_kind)
    group by ts.id
  )
  select coalesce(max(n),0)::integer from overlap_counts
$$;

create or replace function public.fitmatch_find_reference_candidates(
  p_target_product_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid:=(select auth.uid());
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
  select * into v_product from fitmatch_catalog.products where id=p_target_product_id;
  if not found then raise exception using errcode='P0002',message='target_product_not_found'; end if;
  select * into v_target from fitmatch_catalog.product_classification_history
  where product_id=p_target_product_id and is_current;
  if not found or v_target.classification_status<>'confirmed' then
    return jsonb_build_object('state','target_classification_required','candidates','[]'::jsonb);
  end if;

  with evaluated as (
    select c.id,c.product_name,c.size_name,c.gender,c.is_reference,c.updated_at,
      c.product_size_id,
      coalesce(o.category_code,c.canonical_category_code) category_code,
      coalesce(o.detail_code,c.canonical_detail_code) detail_code,
      coalesce(o.comparison_family_code,c.comparison_family_code) family_code,
      coalesce(o.length_code,c.comparison_length_code) length_code,
      coalesce(o.body_length_code,c.comparison_body_length_code) body_length_code
    from public.closet_items c
    left join public.closet_item_classification_overrides o
      on o.closet_item_id=c.id and o.user_id=c.user_id
    where c.user_id=v_user_id and c.deleted_at is null
      and coalesce(o.comparison_family_code,c.comparison_family_code) is not null
  ), compat as (
    select e.*,
      fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
        e.category_code,e.gender,e.family_code,e.detail_code,e.length_code,e.body_length_code,
        v_target.category_code,v_product.audience,v_target.comparison_family_code,
        v_target.detail_code,v_target.length_code,v_target.body_length_code,false
      ) automatic,
      fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
        e.category_code,e.gender,e.family_code,e.detail_code,e.length_code,e.body_length_code,
        v_target.category_code,v_product.audience,v_target.comparison_family_code,
        v_target.detail_code,v_target.length_code,v_target.body_length_code,true
      ) manual
    from evaluated e
  ), measured as (
    select c.*,
      fitmatch_catalog.runtime_max_measurement_overlap(
        c.product_size_id,p_target_product_id,c.manual->'excluded_measurements'
      ) overlap_count
    from compat c
  ), ranked as (
    select *,
      coalesce((automatic->>'allowed')::boolean,false)
        and automatic->>'level'='direct'
        and overlap_count>=coalesce(nullif(automatic->>'minimum_common_measurements','')::integer,2)
        as automatic_ready,
      coalesce((manual->>'allowed')::boolean,false)
        and overlap_count>=coalesce(nullif(manual->>'minimum_common_measurements','')::integer,2)
        as manual_ready,
      coalesce((manual->>'allowed')::boolean,false) as structurally_compatible
    from measured
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'closet_item_id',id,'product_name',product_name,'size_name',size_name,
      'is_reference',is_reference,'automatic_ready',automatic_ready,
      'manual_ready',manual_ready,'measurement_overlap_count',overlap_count,
      'automatic_compatibility',automatic,'manual_compatibility',manual
    ) order by automatic_ready desc,manual_ready desc,is_reference desc,updated_at desc,id),'[]'::jsonb),
    count(*) filter(where automatic_ready),count(*) filter(where manual_ready),
    count(*) filter(where structurally_compatible)
  into v_candidates,v_auto_count,v_manual_count,v_structural_count
  from ranked
  where automatic_ready or manual_ready or structurally_compatible;

  return jsonb_build_object(
    'state',case when v_auto_count>0 then 'automatic'
      when v_manual_count>0 then 'manual_selection'
      when v_structural_count>0 then 'measurements_required'
      else 'no_compatible_garment' end,
    'automatic_count',v_auto_count,'manual_count',v_manual_count,
    'structural_count',v_structural_count,'candidates',v_candidates,
    'policy_version','db-comparison-2026-08-18-v2'
  );
end $$;

create or replace function public.fitmatch_begin_comparison(
  p_reference_item_id uuid,p_target_product_id uuid,
  p_allow_extended boolean default false
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid:=(select auth.uid());
  vr record; vt fitmatch_catalog.product_classification_history%rowtype;
  vp fitmatch_catalog.products%rowtype;
  v_compatibility jsonb; v_run_id uuid; v_status text;
begin
  if v_user_id is null then raise exception using errcode='42501',message='authentication_required'; end if;
  select c.product_id,c.gender,c.product_size_id,
    coalesce(o.category_code,c.canonical_category_code) category_code,
    coalesce(o.detail_code,c.canonical_detail_code) detail_code,
    coalesce(o.comparison_family_code,c.comparison_family_code) family_code,
    coalesce(o.length_code,c.comparison_length_code) length_code,
    coalesce(o.body_length_code,c.comparison_body_length_code) body_length_code
  into vr from public.closet_items c
  left join public.closet_item_classification_overrides o
    on o.closet_item_id=c.id and o.user_id=c.user_id
  where c.id=p_reference_item_id and c.user_id=v_user_id and c.deleted_at is null;
  if vr.product_id is null then raise exception using errcode='P0002',message='reference_product_not_linked'; end if;
  select * into vp from fitmatch_catalog.products where id=p_target_product_id;
  if not found then raise exception using errcode='P0002',message='target_product_not_found'; end if;
  select * into vt from fitmatch_catalog.product_classification_history
    where product_id=p_target_product_id and is_current;
  if not found or vt.classification_status<>'confirmed' then
    v_compatibility:=jsonb_build_object('allowed',false,'level','incompatible',
      'reason','target_classification_not_confirmed');
  else
    v_compatibility:=fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
      vr.category_code,vr.gender,vr.family_code,vr.detail_code,vr.length_code,vr.body_length_code,
      vt.category_code,vp.audience,vt.comparison_family_code,vt.detail_code,
      vt.length_code,vt.body_length_code,p_allow_extended
    );
    if coalesce((v_compatibility->>'allowed')::boolean,false)
       and fitmatch_catalog.runtime_max_measurement_overlap(
         vr.product_size_id,p_target_product_id,v_compatibility->'excluded_measurements'
       )<coalesce(nullif(v_compatibility->>'minimum_common_measurements','')::integer,2) then
      v_compatibility:=v_compatibility||jsonb_build_object(
        'allowed',false,'level','insufficient_data','reason','insufficient_common_measurements'
      );
    end if;
  end if;
  v_status:=case when coalesce((v_compatibility->>'allowed')::boolean,false)
    then 'pending' else 'blocked' end;
  insert into public.comparison_runs (
    user_id,reference_item_id,target_product_id,status,comparison_level,
    block_reason,comparison_policy_version,input_snapshot,completed_at
  ) values (
    v_user_id,p_reference_item_id,p_target_product_id,v_status,
    v_compatibility->>'level',v_compatibility->>'reason',
    'db-comparison-2026-08-18-v2',jsonb_build_object('compatibility',v_compatibility),
    case when v_status='blocked' then now() else null end
  ) returning id into v_run_id;
  return jsonb_build_object('run_id',v_run_id,'status',v_status,'compatibility',v_compatibility);
end $$;

revoke all on function fitmatch_catalog.runtime_infer_body_length_code(text,text,text),
  fitmatch_catalog.runtime_normalize_gender(text),
  fitmatch_catalog.runtime_genders_are_compatible(text,text,text),
  fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    text,text,text,text,text,text,text,text,text,text,text,text,boolean
  ),fitmatch_catalog.runtime_max_measurement_overlap(uuid,uuid,jsonb)
  from public,anon,authenticated;
grant execute on function fitmatch_catalog.runtime_infer_body_length_code(text,text,text),
  fitmatch_catalog.runtime_normalize_gender(text),
  fitmatch_catalog.runtime_genders_are_compatible(text,text,text),
  fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    text,text,text,text,text,text,text,text,text,text,text,text,boolean
  ),fitmatch_catalog.runtime_max_measurement_overlap(uuid,uuid,jsonb)
  to service_role;
revoke all on function public.fitmatch_find_reference_candidates(uuid) from public,anon;
grant execute on function public.fitmatch_find_reference_candidates(uuid) to authenticated;

do $$
begin
  if fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    'tops','male','tshirt','short_sleeve','short_sleeve',null,
    'bottoms','male','pants','long_pants','long_sleeve',null,true
  )->>'reason'<>'major_category_incompatible' then
    raise exception 'cross-major comparison was not blocked';
  end if;
  if not coalesce((fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    'tops','male','hoodie','hoodie','long_sleeve',null,
    'tops','male','sweatshirt','sweatshirt','long_sleeve',null,false
  )->>'allowed')::boolean,false) then
    raise exception 'sweatshirt hoodie direct comparison missing';
  end if;
  if fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    'tops','male','tshirt','short_sleeve','short_sleeve',null,
    'tops','male','hoodie','hoodie','long_sleeve',null,false
  )->>'reason' is null then
    raise exception 'short-long automatic comparison was not blocked';
  end if;
  if fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    'tops','male','tshirt','short_sleeve','short_sleeve',null,
    'tops','male','hoodie','hoodie','long_sleeve',null,true
  )->>'level'<>'extended' then
    raise exception 'short-long manual expansion missing';
  end if;
end $$;

commit;
