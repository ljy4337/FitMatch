begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:briefcase-correction-v1'));

update fitmatch_taxonomy.classification_decisions d set
  decision_status=b.decision_before->>'decision_status',
  decision_method=b.decision_before->>'decision_method',
  confidence=(b.decision_before->>'confidence')::numeric,
  decision_reason=b.decision_before->>'decision_reason',
  semantic_category_code=b.decision_before->>'semantic_category_code',
  garment_type_code=b.decision_before->>'garment_type_code',
  comparison_family_code=b.decision_before->>'comparison_family_code',
  app_support_status=b.decision_before->>'app_support_status',
  fallback_required=(b.decision_before->>'fallback_required')::boolean,
  fallback_inputs=array(select jsonb_array_elements_text(b.decision_before->'fallback_inputs')),
  canonical_default_allowed=(b.decision_before->>'canonical_default_allowed')::boolean
from fitmatch_taxonomy.classification_correction_backups b
where b.correction_code='briefcase-not-underwear-v1' and d.id=b.decision_id;

insert into fitmatch_taxonomy.category_app_mappings
select (jsonb_populate_record(null::fitmatch_taxonomy.category_app_mappings,b.app_mapping_before)).*
from fitmatch_taxonomy.classification_correction_backups b
where b.correction_code='briefcase-not-underwear-v1' and b.app_mapping_before is not null
on conflict (decision_id) do nothing;

insert into fitmatch_taxonomy.extension_registry
select (jsonb_populate_record(null::fitmatch_taxonomy.extension_registry,b.extension_before)).*
from fitmatch_taxonomy.classification_correction_backups b
where b.correction_code='briefcase-not-underwear-v1' and b.extension_before is not null
on conflict (decision_id) do nothing;

commit;
