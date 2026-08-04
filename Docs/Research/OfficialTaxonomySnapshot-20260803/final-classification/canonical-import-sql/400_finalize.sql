begin;
do $$
begin
 if (select count(*) from fitmatch_taxonomy.source_categories)<>4008 then raise exception 'source count mismatch'; end if;
 if (select count(*) from fitmatch_taxonomy.classification_decisions)<>4008 then raise exception 'decision count mismatch'; end if;
 if (select count(*) from fitmatch_taxonomy.category_app_mappings)<>1089 then raise exception 'app mapping count mismatch'; end if;
 if (select count(*) from fitmatch_taxonomy.extension_registry)<>54 then raise exception 'extension count mismatch'; end if;
 if (select count(*) from public.source_categories)<>2031 then raise exception 'legacy source changed'; end if;
 if (select md5(string_agg(md5(to_jsonb(x)::text),'|' order by x.id::text)) from (select * from public.source_categories)x)<>'b23741a3e93e1ed0b92bd21c2cdb389e' then raise exception 'legacy source checksum changed'; end if;
 if (select md5(string_agg(md5(to_jsonb(x)::text),'|' order by x.source_category_id::text)) from (select * from public.source_category_mappings)x)<>'779b908ab43f923618e40d2c32c6bfbb' then raise exception 'legacy mapping checksum changed'; end if;
end $$;
update fitmatch_taxonomy.policy_versions set status='validated',validated_at=now() where code='taxonomy-final-2026-08-03';
update fitmatch_taxonomy.promotion_manifests set status='validated',validated_at=now(),
 actual_counts='{"source_nodes":4008,"hierarchy_edges":3978,"decisions":4008,"navigation_only":582,"confirmed":1089,"review_required":894,"rejected":1403,"unsupported":40,"app_mappings":1089,"direct":1075,"transform_required":14,"activity_unknown":4008,"extensions":54,"audit_rows":2034,"decision_evidence":4008,"compatibility_rules":14,"measurement_policies":14,"source_aliases":21}'::jsonb,
 inserted_counts='{"snapshots":2,"source_nodes":4008,"hierarchy_edges":3978,"legacy_identity_links":2034,"decisions":4008,"decision_length_axes":4008,"app_mappings":1089,"extensions":54,"audit_rows":2034,"decision_evidence":4008,"compatibility_rules":14,"measurement_policies":14,"source_aliases":21}'::jsonb,
 skipped_counts='{"decision_retry_idempotent":100}'::jsonb,
 conflict_counts='{"data_conflicts":0,"identity_nn_components_preserved":1}'::jsonb,
 validation_result='{"passed":true,"orphan_category":0,"orphan_hierarchy":0,"hierarchy_cycle":0,"duplicate_source_identity":0,"duplicate_normalized_conflict":0,"identity_unresolved":0,"status_missing":0,"confirmed_missing_required":0,"rejected_invalid":0,"review_forced_mapping":0,"policy_missing":0,"snapshot_missing":0,"evidence_fk_error":0,"source_raw_hash_mismatch":0,"legacy_changed":0}'::jsonb
where id='8f717eed-176f-43fc-91e9-838f88ab38ac';
commit;
