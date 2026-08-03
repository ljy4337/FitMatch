select jsonb_build_object(
  'source_nodes',(select count(*) from fitmatch_taxonomy.source_categories),
  'decisions',(select count(*) from fitmatch_taxonomy.classification_decisions),
  'statuses',(select jsonb_object_agg(decision_status,n) from (select decision_status,count(*) n from fitmatch_taxonomy.classification_decisions group by decision_status) s),
  'app_mappings',(select count(*) from fitmatch_taxonomy.category_app_mappings),
  'mapping_statuses',(select jsonb_object_agg(mapping_status,n) from (select mapping_status,count(*) n from fitmatch_taxonomy.category_app_mappings group by mapping_status) s),
  'activity_unknown',(select count(*) from fitmatch_taxonomy.source_categories where activity_state='unknown'),
  'extensions',(select count(*) from fitmatch_taxonomy.extension_registry),
  'orphan_hierarchy',(select count(*) from fitmatch_taxonomy.category_hierarchy h left join fitmatch_taxonomy.source_categories p on p.id=h.parent_category_id left join fitmatch_taxonomy.source_categories c on c.id=h.child_category_id where p.id is null or c.id is null),
  'confirmed_missing_required',(select count(*) from fitmatch_taxonomy.classification_decisions d left join fitmatch_taxonomy.category_app_mappings a on a.decision_id=d.id where d.decision_status='confirmed' and (d.garment_type_code is null or d.comparison_family_code is null or a.id is null)),
  'rejected_policy_or_mapping',(select count(*) from fitmatch_taxonomy.classification_decisions d left join fitmatch_taxonomy.category_app_mappings a on a.decision_id=d.id where d.decision_status='rejected' and (d.comparison_family_code is not null or a.id is not null)),
  'review_forced_mapping',(select count(*) from fitmatch_taxonomy.classification_decisions d join fitmatch_taxonomy.category_app_mappings a on a.decision_id=d.id where d.decision_status='review_required'),
  'missing_policy_or_snapshot',(select count(*) from fitmatch_taxonomy.classification_decisions d join fitmatch_taxonomy.source_categories c on c.id=d.source_category_id where d.policy_version is null or c.source_snapshot_id is null)
) result;
