
create view fitmatch_catalog.source_to_fitmatch_mappings
with (security_invoker=true) as
select
 m.release_id,
 m.source_identity,
 m.source,
 m.snapshot_id,
 m.external_category_id,
 m.target,
 m.normalized_path,
 m.decision_status,
 m.runtime_lookup_eligible,
 case when m.decision_status='confirmed' then m.semantic_category_code end as app_category_code,
 null::text as app_detail_code,
 case when m.decision_status='confirmed' then m.semantic_garment_type end as semantic_garment_type,
 case when m.decision_status='confirmed' then m.comparison_family end as comparison_family,
 case
  when m.decision_status='confirmed' then 'product_classifier_required'
  when m.decision_status='review_required' then 'user_or_product_review_required'
  else 'not_applicable'
 end as detail_resolution_strategy,
 m.raw_record->'appMapping' as legacy_app_mapping
from fitmatch_catalog.source_category_mappings m;

revoke all on fitmatch_catalog.source_to_fitmatch_mappings from public,anon,authenticated;
grant select on fitmatch_catalog.source_to_fitmatch_mappings to service_role;
;
