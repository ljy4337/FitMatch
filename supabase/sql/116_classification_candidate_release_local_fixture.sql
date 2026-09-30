-- LOCAL DISPOSABLE POSTGRESQL 17 ONLY.
-- Builds a production-shaped, non-user classification fixture from the
-- SELECT-only snapshot files in /tmp. Never run this file in production.

\set ON_ERROR_STOP on
\ir 115_authoritative_classification_foundation_local_fixture.sql

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- Replace the compact 115 synthetic helpers with the production contracts
-- used to create stored product fingerprints and classifier profile keys.
create or replace function fitmatch_catalog.runtime_product_fingerprint(
  p_name text,
  p_path text
) returns text
language sql
immutable
security invoker
set search_path = pg_catalog
as $$
  select md5(
    lower(btrim(coalesce(p_name, ''))) || E'\n' ||
    lower(btrim(coalesce(p_path, '')))
  )
$$;

create or replace function fitmatch_catalog.runtime_product_name_signature(
  p_name text
) returns text
language sql
immutable
security invoker
set search_path = pg_catalog
as $$
  with n as (
    select lower(regexp_replace(
      btrim(coalesce(p_name, '')), E'\\s+', ' ', 'g'
    )) value
  )
  select concat_ws('|',
    case when value ~ '(세트|set([[:space:][:punct:]]|$))' then 'set' end,
    case when value ~ '(후드[[:space:]]*집업|집업[[:space:]]*후드|zip[- ]?hood)' then 'zip_hoodie' end,
    case when value ~ '(후디|후드[[:space:]]*티|hoodie)' then 'hoodie' end,
    case when value ~ '(스웨트[[:space:]]*셔츠|맨투맨|sweatshirt)' then 'sweatshirt' end,
    case when value ~ '(가디건|카디건|cardigan)' then 'cardigan' end,
    case when value ~ '(니트|스웨터|knit|sweater)' then 'knit' end,
    case when value ~ '(폴로[[:space:]]*셔츠|카라[[:space:]]*티|polo[[:space:]]*shirt)' then 'polo' end,
    case when value ~ '(블라우스|blouse)' then 'blouse' end,
    case when value ~ '(셔츠|남방|(^|[^[:alpha:]])shirt([^[:alpha:]]|$))' then 'shirt' end,
    case when value ~ '(민소매|나시|슬리브리스|sleeveless)' then 'sleeveless' end,
    case when value ~ '(반팔|반소매|숏[ -]?슬리브|short[ -]?sleeve|s/s([[:space:][:punct:]]|$))' then 'short_sleeve' end,
    case when value ~ '(긴팔|긴소매|롱[ -]?슬리브|long[ -]?sleeve|l/s([[:space:][:punct:]]|$))' then 'long_sleeve' end,
    case when value ~ '(레깅스|타이즈|타이츠|leggings)' then 'leggings' end,
    case when value ~ '(스코츠|스커트|치마|skorts?|skirt)' then 'skirt' end,
    case when value ~ '(반바지|숏[[:space:]]*팬츠|쇼트[[:space:]]*팬츠|쇼츠|버뮤다|shorts)' then 'shorts' end,
    case when value ~ '(데님|청바지|denim|jeans)' then 'denim' end,
    case when value ~ '(슬랙스|slacks|trousers)' then 'slacks' end,
    case when value ~ '(팬츠|바지|(^|[^[:alpha:]])pants([^[:alpha:]]|$))' then 'pants' end,
    case when value ~ '(원피스|(^|[^[:alpha:]])dress([^[:alpha:]]|$))' then 'dress' end,
    case when value ~ '(바람막이|윈드브레이커|windbreaker)' then 'windbreaker' end,
    case when value ~ '(아노락|anorak)' then 'anorak' end,
    case when value ~ '(블레이저|blazer)' then 'blazer' end,
    case when value ~ '(블루종|ma-1|blouson)' then 'blouson' end,
    case when value ~ '(플리스|후리스|fleece)' then 'fleece' end,
    case when value ~ '(패딩|다운[[:space:]]*(재킷|자켓|파카)|puffer|padding)' then 'padding' end,
    case when value ~ '(트렌치|코트|trench|(^|[^[:alpha:]])coat([^[:alpha:]]|$))' then 'coat' end,
    case when value ~ '(재킷|자켓|jacket)' then 'jacket' end,
    case when value ~ '(조끼|베스트|(^|[^[:alpha:]])vest([^[:alpha:]]|$))' then 'vest' end,
    case when value ~ '(브라탑|브라렛|브래지어|(^|[^[:alpha:]])bra([^[:alpha:]]|$))' then 'bra' end,
    case when value ~ '(복서[[:space:]]*브리프|브리프|(^|[^[:alpha:]])briefs?([^[:alpha:]]|$))' then 'briefs' end,
    case when value ~ '(트렁크|trunks?)' then 'trunks' end,
    case when value ~ '(캐미솔|캐미숄|camisole)' then 'camisole' end,
    case when value ~ '(라운지|파자마|lounge|pajama|pyjama)' then 'loungewear' end
  )
  from n
$$;

create or replace function fitmatch_catalog.runtime_normalized_category_path(
  p_path text
) returns text
language sql
immutable
security invoker
set search_path = pg_catalog
as $$
  select lower(regexp_replace(
    btrim(coalesce(p_path, '')), E'\\s*>\\s*', ' > ', 'g'
  ))
$$;

-- Match the production comparison boundary rather than the intentionally
-- compact gender helper in the 115 contract fixture.
create or replace function fitmatch_catalog.runtime_normalize_gender(
  p_gender text
) returns text
language sql
immutable
security invoker
set search_path = pg_catalog
as $$
  select case upper(btrim(coalesce(p_gender, '')))
    when 'MEN' then 'male' when 'MALE' then 'male'
    when 'WOMEN' then 'female' when 'FEMALE' then 'female'
    when 'BOYS' then 'boys' when 'BOY' then 'boys'
    when 'GIRLS' then 'girls' when 'GIRL' then 'girls'
    when 'KIDS' then 'kids_unisex'
    when 'KIDS_UNISEX' then 'kids_unisex'
    when 'BABY' then 'baby' when 'UNISEX' then 'unisex'
    else 'unknown'
  end
$$;

create or replace function fitmatch_catalog.runtime_genders_are_compatible(
  p_reference_gender text,
  p_target_gender text,
  p_group text
) returns boolean
language sql
immutable
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
  with gender_pair as (
    select
      fitmatch_catalog.runtime_normalize_gender(p_reference_gender) reference,
      fitmatch_catalog.runtime_normalize_gender(p_target_gender) target
  )
  select case
    when reference = 'unknown' or target = 'unknown' then true
    when reference in ('boys', 'girls', 'kids_unisex')
      or target in ('boys', 'girls', 'kids_unisex')
      then reference in ('boys', 'girls', 'kids_unisex')
        and target in ('boys', 'girls', 'kids_unisex')
    when reference = 'baby' or target = 'baby'
      then reference = 'baby' and target = 'baby'
    when reference = 'unisex' or target = 'unisex' then true
    when reference in ('male', 'female')
      and target in ('male', 'female') then
      reference = target or p_group in (
        'knit_cardigan', 'tshirt', 'shirt', 'sweatshirt', 'hoodie',
        'pants', 'denim', 'leggings', 'skirt', 'outerwear',
        'leather_jacket', 'shoes'
      )
    else reference = target
  end
  from gender_pair
$$;

-- The base fixture contains only synthetic non-user rows. Replace them with
-- the production-shaped classification snapshot before migrations 113-116.
delete from fitmatch_catalog.data_quality_issues;
delete from fitmatch_catalog.product_classification_history;
delete from fitmatch_catalog.product_observation_measurements;
delete from fitmatch_catalog.product_observations;
delete from fitmatch_catalog.product_classification_decisions;
delete from fitmatch_catalog.products;
delete from fitmatch_catalog.classification_name_profiles;
delete from fitmatch_catalog.classification_path_profiles;
delete from fitmatch_catalog.classification_exclusion_profiles;
delete from fitmatch_catalog.source_category_mappings;
delete from fitmatch_catalog.releases;
delete from public.app_category_measurement_policies;
delete from public.comparison_policies;
delete from fitmatch_taxonomy.comparison_compatibility_rules;
delete from public.measurement_items;
delete from public.garment_types;
delete from public.comparison_groups;
delete from public.comparison_length_classes;
delete from public.app_categories;

create temp table _phase1b2_jsonl(line text not null);

\copy _phase1b2_jsonl(line) from '/tmp/FitMatchPhase1B2-policy.jsonl'

insert into fitmatch_catalog.releases
select (jsonb_populate_record(
  null::fitmatch_catalog.releases,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'release';

insert into public.app_categories
select (jsonb_populate_record(
  null::public.app_categories,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'app_category';

insert into public.comparison_groups
select (jsonb_populate_record(
  null::public.comparison_groups,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'comparison_group';

insert into public.garment_types
select (jsonb_populate_record(
  null::public.garment_types,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'garment_type';

insert into public.comparison_length_classes
select (jsonb_populate_record(
  null::public.comparison_length_classes,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'length_class';

insert into public.measurement_items
select (jsonb_populate_record(
  null::public.measurement_items,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'measurement_item';

insert into public.comparison_policies
select (jsonb_populate_record(
  null::public.comparison_policies,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'comparison_policy';

insert into public.app_category_measurement_policies
select (jsonb_populate_record(
  null::public.app_category_measurement_policies,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'measurement_policy';

insert into fitmatch_taxonomy.comparison_compatibility_rules
select (jsonb_populate_record(
  null::fitmatch_taxonomy.comparison_compatibility_rules,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'compatibility_rule';

truncate _phase1b2_jsonl;
\copy _phase1b2_jsonl(line) from '/tmp/FitMatchPhase1B2-mappings.jsonl'

insert into fitmatch_catalog.source_category_mappings
select (jsonb_populate_record(
  null::fitmatch_catalog.source_category_mappings,
  line::jsonb - 'record_type'
)).*
from _phase1b2_jsonl;

truncate _phase1b2_jsonl;
\copy _phase1b2_jsonl(line) from '/tmp/FitMatchPhase1B2-decisions.jsonl'

insert into fitmatch_catalog.product_classification_decisions
select (jsonb_populate_record(
  null::fitmatch_catalog.product_classification_decisions,
  line::jsonb - 'record_type'
)).*
from _phase1b2_jsonl;

truncate _phase1b2_jsonl;
\copy _phase1b2_jsonl(line) from '/tmp/FitMatchPhase1B2-profiles.jsonl'

insert into fitmatch_catalog.classification_name_profiles
select (jsonb_populate_record(
  null::fitmatch_catalog.classification_name_profiles,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'classification_name_profile';

insert into fitmatch_catalog.classification_path_profiles
select (jsonb_populate_record(
  null::fitmatch_catalog.classification_path_profiles,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'classification_path_profile';

insert into fitmatch_catalog.classification_exclusion_profiles
select (jsonb_populate_record(
  null::fitmatch_catalog.classification_exclusion_profiles,
  line::jsonb->'row'
)).*
from _phase1b2_jsonl
where line::jsonb->>'record_type' = 'classification_exclusion_profile';

truncate _phase1b2_jsonl;
\copy _phase1b2_jsonl(line) from '/tmp/FitMatchPhase1B2-products.jsonl'

create temp table _phase1b2_baseline(line text not null);
\copy _phase1b2_baseline(line) from '/Users/jinyoung/Documents/Projects/FitMatch/FitMatch/Docs/FitMatchClassificationGlobalBaseline-20260825.jsonl'

insert into fitmatch_catalog.products (
  id, source, external_product_id, product_name, audience,
  source_category_path, source_category_codes, raw_payload,
  input_fingerprint, lifecycle_status
)
select
  (product->>'id')::uuid,
  product->>'source',
  product->>'external_product_id',
  product->>'product_name',
  product->>'audience',
  product->>'source_category_path',
  array(
    select jsonb_array_elements_text(product->'source_category_codes')
  ),
  jsonb_build_object(
    'phase1b2_current', baseline->'current',
    'phase1b2_proposed', baseline->'proposed',
    'phase1b2_mapping_source_identity',
      baseline#>>'{evidence,source_mapping,source_identity}',
    'phase1b2_comparison_readiness', baseline->'comparison_readiness',
    'phase1b2_change_type', baseline->>'change_type',
    'phase1b2_requires_manual_review', baseline->'requires_manual_review',
    'phase1b2_conflict_dimensions', baseline->'conflict_dimensions'
  ),
  product->>'input_fingerprint',
  product->>'lifecycle_status'
from (
  select line::jsonb - 'record_type' product
  from _phase1b2_jsonl
) product_rows
join lateral (
  select line::jsonb baseline
  from _phase1b2_baseline
  where line::jsonb->>'source' = product->>'source'
    and line::jsonb->>'external_product_id' =
      product->>'external_product_id'
) baseline_row on true;

-- Preserve the independent expected rows verbatim as local-only product
-- evidence. This never changes or regenerates the expected values.
truncate _phase1b2_baseline;
\copy _phase1b2_baseline(line) from '/Users/jinyoung/Documents/Projects/FitMatch/FitMatch/Docs/FitMatchClassificationPhase1A5Adjudication-20260825.jsonl'

update fitmatch_catalog.products product
set raw_payload = product.raw_payload || jsonb_build_object(
  'phase1b2_independent_adjudication', adjudication.line::jsonb
)
from _phase1b2_baseline adjudication
where adjudication.line::jsonb->>'record_type' = 'adjudicated_product'
  and adjudication.line::jsonb->>'source' = product.source
  and adjudication.line::jsonb->>'external_product_id' =
    product.external_product_id;

do $$
begin
  if (select count(*) from fitmatch_catalog.products) <> 1608
    or (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id = '65d72393-4a40-4e99-b701-fdc1ff865774') <> 3492
    or (select count(*) from fitmatch_catalog.product_classification_decisions) <> 5056
    or (select count(*) from fitmatch_catalog.classification_name_profiles
      where policy_version = 'db-auto-classifier-2026-08-18-v2') <> 839
    or (select count(*) from fitmatch_catalog.classification_path_profiles
      where policy_version = 'db-auto-classifier-2026-08-18-v2') <> 420
    or (select count(*) from fitmatch_catalog.classification_exclusion_profiles
      where policy_version = 'db-auto-classifier-2026-08-18-v2') <> 273 then
    raise exception 'phase1b2_production_shaped_fixture_count_mismatch';
  end if;
end
$$;

comment on schema fitmatch_catalog is
  'Disposable local classification snapshot; contains no auth, closet, user measurement, or comparison-history data.';
