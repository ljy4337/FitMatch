begin;

delete from fitmatch_taxonomy.classification_audit_history
where canonical_policy_version = 'taxonomy-corrected-2026-08-14';
delete from fitmatch_taxonomy.decision_evidence
where policy_version = 'taxonomy-corrected-2026-08-14';
delete from fitmatch_taxonomy.category_app_mappings
where comparison_policy_version = 'taxonomy-corrected-2026-08-14';
delete from fitmatch_taxonomy.decision_length_axes
where policy_version = 'taxonomy-corrected-2026-08-14';
delete from fitmatch_taxonomy.classification_decisions
where policy_version = 'taxonomy-corrected-2026-08-14';
delete from fitmatch_taxonomy.policy_versions
where code = 'taxonomy-corrected-2026-08-14';

drop view if exists fitmatch_catalog.source_to_fitmatch_mappings;
drop table if exists fitmatch_catalog.app_category_details;
drop table if exists fitmatch_catalog.app_categories;

commit;
