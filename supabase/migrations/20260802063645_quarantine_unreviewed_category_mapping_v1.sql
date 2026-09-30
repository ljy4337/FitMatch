
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.source_category_mappings_pre_taxonomy_audit_20260802
as table public.source_category_mappings;

alter table private.source_category_mappings_pre_taxonomy_audit_20260802
  add primary key (source_category_id);

revoke all on table private.source_category_mappings_pre_taxonomy_audit_20260802
  from public, anon, authenticated;

update public.source_category_mappings
set mapping_status = 'review_required',
    evidence = evidence || jsonb_build_object(
      'taxonomy_audit_status', 'quarantined',
      'taxonomy_audit_reason', 'Prior automatic classification used broad ancestor-path or legacy category matching and was not manually verified.',
      'taxonomy_audit_at', '2026-08-02'
    ),
    policy_version = 'v1_quarantined',
    updated_at = now()
where mapping_status = 'confirmed'
  and resolution_mode in ('explicit_original_path', 'legacy_app_category');

update public.client_source_category_mappings client
set garment_type_id = admin.garment_type_id,
    default_sleeve_class_code = admin.default_sleeve_class_code,
    default_pants_length_code = admin.default_pants_length_code,
    default_body_length_code = admin.default_body_length_code,
    mapping_status = admin.mapping_status,
    policy_version = admin.policy_version,
    updated_at = admin.updated_at
from public.source_category_mappings admin
where admin.source_category_id = client.source_category_id;
;
