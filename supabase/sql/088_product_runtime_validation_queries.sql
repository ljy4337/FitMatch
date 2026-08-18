-- FitMatch product runtime read-only validation queries

-- 1. One-line release gate. passed must be true.
select fitmatch_qa.validate_product_runtime_v3() as validation;

-- 2. Operational row counts.
select
  (select count(*) from fitmatch_catalog.products) products,
  (select count(*) from fitmatch_catalog.source_product_snapshots) snapshots,
  (select count(*) from fitmatch_catalog.source_product_snapshots where product_id is not null) linked_snapshots,
  (select count(*) from fitmatch_catalog.product_classification_history where is_current) current_classifications,
  (select count(*) from fitmatch_catalog.product_variants) variants,
  (select count(*) from fitmatch_catalog.product_sizes) sizes,
  (select count(*) from fitmatch_catalog.product_measurements) measurements,
  (select count(*) from fitmatch_catalog.classification_path_profiles
    where auto_eligible) automatic_path_profiles,
  (select count(*) from fitmatch_catalog.classification_name_profiles
    where auto_eligible) automatic_name_profiles,
  (select count(*) from fitmatch_catalog.classification_exclusion_profiles
    where auto_eligible) automatic_exclusion_profiles,
  (select count(*) from public.product_intake_requests where status='pending') pending_intake_requests;

-- 3. Current product classification coverage by source/status.
select source,classification_status,count(*) products
from fitmatch_catalog.current_product_classifications
group by source,classification_status
order by source,classification_status;

-- 4. Twenty current samples per retailer.
with ranked as (
  select c.*,
    row_number() over(partition by source order by external_product_id) sample_rank
  from fitmatch_catalog.current_product_classifications c
)
select source,external_product_id,product_name,source_category_path,
  category_code,detail_code,comparison_family_code,length_code,
  classification_status,decision_version
from ranked where sample_rank<=20
order by source,sample_rank;

-- 5. Intentional fail-safe states that require review.
select source,external_product_id,product_name,source_category_path,
  classification_status,requires_user_confirmation,decision_version
from fitmatch_catalog.current_product_classifications
where classification_status is distinct from 'confirmed'
order by source,external_product_id
limit 200;

-- 6. Confirm no current category/family contradiction.
select source,external_product_id,product_name,category_code,detail_code,
  comparison_family_code
from fitmatch_catalog.current_product_classifications
where classification_status='confirmed' and (
  (category_code='underwear' and comparison_family_code<>'underwear')
  or (category_code='bottoms' and comparison_family_code='tshirt')
);

-- 7. Verify client privileges and private catalog isolation.
select n.nspname,c.relname,c.relrowsecurity,
  has_table_privilege('anon',c.oid,'SELECT') anon_select,
  has_table_privilege('authenticated',c.oid,'SELECT') authenticated_select,
  has_table_privilege('authenticated',c.oid,'INSERT') authenticated_insert,
  has_table_privilege('authenticated',c.oid,'UPDATE') authenticated_update
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where (n.nspname,c.relname) in (
  ('fitmatch_catalog','products'),
  ('fitmatch_catalog','product_sizes'),
  ('fitmatch_catalog','product_measurements'),
  ('public','product_intake_requests'),
  ('public','closet_item_classification_overrides'),
  ('public','comparison_runs'),
  ('public','comparison_results')
)
order by n.nspname,c.relname;

-- 8. Public RPCs: anon_execute must be false, authenticated_execute true.
with rpc(signature) as (values
  ('public.fitmatch_resolve_product(jsonb)'),
  ('public.fitmatch_register_closet_item(uuid,uuid,boolean,jsonb)'),
  ('public.fitmatch_set_closet_classification_override(uuid,jsonb)'),
  ('public.fitmatch_clear_closet_classification_override(uuid)'),
  ('public.fitmatch_find_reference_candidates(uuid)'),
  ('public.fitmatch_begin_comparison(uuid,uuid,boolean)'),
  ('public.fitmatch_complete_comparison(uuid,jsonb)')
)
select signature,
  has_function_privilege('anon',signature,'EXECUTE') anon_execute,
  has_function_privilege('authenticated',signature,'EXECUTE') authenticated_execute
from rpc order by signature;

-- 9. New-product replay coverage. mismatches must remain 0.
with d as (
  select d.*,
    fitmatch_catalog.runtime_normalized_category_path(source_category_path) path_key,
    fitmatch_catalog.runtime_product_name_signature(product_name) signature
  from fitmatch_catalog.product_classification_decisions d
), picked as (
  select d.*,
    coalesce(n.category_code,p.category_code) actual_category,
    coalesce(n.detail_code,p.detail_code) actual_detail,
    coalesce(n.comparison_family_code,p.comparison_family_code) actual_family,
    coalesce(n.length_code,p.length_code) actual_length,
    case when n.source is not null then 'name_profile'
      when p.source is not null then 'path_profile' end resolution_method
  from d
  left join fitmatch_catalog.classification_name_profiles n
    on n.policy_version='db-auto-classifier-2026-08-18-v2'
   and n.source=d.source and n.normalized_path=d.path_key
   and n.name_signature=d.signature and n.auto_eligible
  left join fitmatch_catalog.classification_path_profiles p
    on p.policy_version='db-auto-classifier-2026-08-18-v2'
   and p.source=d.source and p.normalized_path=d.path_key and p.auto_eligible
)
select source,count(*) total,
  count(*) filter(where resolution_method is not null) automatic_coverage,
  count(*) filter(where resolution_method is not null and
    (actual_category,actual_detail,actual_family,actual_length) is distinct from
    (category_code,detail_code,comparison_family,length_type)) mismatches
from picked group by source order by source;

-- 10. Comparison policy smoke cases.
select
  fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    'tops','MEN','tshirt','short_sleeve','short_sleeve',null,
    'bottoms','MEN','pants','long_pants','long_sleeve',null,true
  ) as cross_major_blocked,
  fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    'tops','MEN','sweatshirt','sweatshirt','long_sleeve',null,
    'tops','MEN','hoodie','hoodie','long_sleeve',null,false
  ) as sweatshirt_hoodie_direct,
  fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
    'tops','MEN','tshirt','short_sleeve','short_sleeve',null,
    'tops','MEN','hoodie','hoodie','long_sleeve',null,true
  ) as short_long_manual_extended;
