begin;

set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtext('fitmatch:product-runtime-fk-indexes-v1'));

create index if not exists product_classification_mapping_release_fk_idx
  on fitmatch_catalog.product_classification_history(mapping_release_id)
  where mapping_release_id is not null;
create index if not exists product_classification_reviewed_by_fk_idx
  on fitmatch_catalog.product_classification_history(reviewed_by)
  where reviewed_by is not null;
create index if not exists product_measurements_source_alias_fk_idx
  on fitmatch_catalog.product_measurements(source_alias_id)
  where source_alias_id is not null;

create index if not exists comparison_detail_to_family_fk_idx
  on fitmatch_taxonomy.comparison_detail_compatibility_rules(to_family_code);
create index if not exists comparison_detail_policy_version_fk_idx
  on fitmatch_taxonomy.comparison_detail_compatibility_rules(policy_version);

create index if not exists closet_items_brand_fk_idx
  on public.closet_items(brand_id) where brand_id is not null;
create index if not exists closet_items_source_fk_idx
  on public.closet_items(source_id) where source_id is not null;
create index if not exists closet_items_shared_product_fk_idx
  on public.closet_items(product_id) where product_id is not null;
create index if not exists closet_items_variant_fk_idx
  on public.closet_items(variant_id) where variant_id is not null;

create index if not exists comparison_measurement_result_owner_fk_idx
  on public.comparison_measurement_results(result_id,user_id);
create index if not exists comparison_results_run_owner_fk_idx
  on public.comparison_results(run_id,user_id);
create index if not exists comparison_results_target_size_fk_idx
  on public.comparison_results(target_size_id) where target_size_id is not null;
create index if not exists comparison_runs_target_variant_fk_idx
  on public.comparison_runs(target_variant_id) where target_variant_id is not null;
create index if not exists product_intake_resolved_product_fk_idx
  on public.product_intake_requests(resolved_product_id)
  where resolved_product_id is not null;

commit;
;
