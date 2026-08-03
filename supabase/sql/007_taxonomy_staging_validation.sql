begin;

update fitmatch_staging.import_runs
set status='validating', failure_reason=null
where id='40677f85-e8a0-4a72-ad27-45524f385bcf' and status in ('loading','incomplete','validating');

do $$
declare
  run_id constant uuid := '40677f85-e8a0-4a72-ad27-45524f385bcf';
begin
  if (select count(*) from fitmatch_staging.source_category_nodes n join fitmatch_staging.source_snapshots s on s.id=n.source_snapshot_id where s.import_run_id=run_id) <> 4008 then raise exception 'snapshot_nodes'; end if;
  if (select count(distinct snapshot_node_id) from fitmatch_staging.identity_matching_edges where import_run_id=run_id) <> 2032 then raise exception 'matched_snapshot_nodes'; end if;
  if (select count(*) from fitmatch_staging.classification_candidates where import_run_id=run_id) <> 1976 then raise exception 'candidates'; end if;
  if (select count(*) from fitmatch_staging.identity_matching_edges where import_run_id=run_id) <> 2034 then raise exception 'edges'; end if;
  if (select count(*) from fitmatch_staging.identity_components where import_run_id=run_id and relation_type='N:N') <> 1 then raise exception 'nn_component'; end if;
  if (select count(*) from fitmatch_staging.classification_candidates where import_run_id=run_id and provisional_classification_status='provisional_confirmed') <> 170 then raise exception 'provisional_confirmed'; end if;
  if (select count(*) from fitmatch_staging.classification_candidates where import_run_id=run_id and provisional_classification_status='review_required') <> 839 then raise exception 'review_required'; end if;
  if (select count(*) from fitmatch_staging.classification_candidates where import_run_id=run_id and provisional_classification_status='provisional_rejected') <> 927 then raise exception 'provisional_rejected'; end if;
  if (select count(*) from fitmatch_staging.classification_candidates where import_run_id=run_id and provisional_classification_status='provisional_unsupported') <> 40 then raise exception 'provisional_unsupported'; end if;
  if (select count(*) from fitmatch_staging.classification_candidates where import_run_id=run_id and candidate_group in ('A','B','C','D','E','F')) <> 1976 then raise exception 'group_total'; end if;
  if (select count(*) from fitmatch_staging.classification_candidates where import_run_id=run_id and product_observation_status in ('product_observed','navigation_only','no_product_observed','collection_failed','activity_unknown')) <> 1976 then raise exception 'product_status_total'; end if;
  if (select count(*) from fitmatch_staging.sampled_category_results r join fitmatch_staging.sampling_runs s on s.id=r.sampling_run_id where s.import_run_id=run_id) <> 100 then raise exception 'sample_categories'; end if;
  if (select count(*) from fitmatch_staging.sampled_product_evidence e join fitmatch_staging.sampling_runs s on s.id=e.sampling_run_id where s.import_run_id=run_id) <> 906 then raise exception 'sample_products'; end if;
  if (select count(*) from fitmatch_staging.classification_candidates where import_run_id=run_id and canonical_promotion_status in ('approved','promoted')) <> 0 then raise exception 'canonical_promotion'; end if;
  if (select count(*) from fitmatch_staging.identity_matching_edges e left join public.source_categories c on c.id=e.source_db_record_id where e.import_run_id=run_id and c.id is null) <> 0 then raise exception 'edge_orphan'; end if;
end $$;

insert into fitmatch_staging.validation_results(id,import_run_id,rule_code,severity,passed,affected_count,expected_value,actual_value)
select gen_random_uuid(),'40677f85-e8a0-4a72-ad27-45524f385bcf',v.rule_code,'error',true,0,to_jsonb(v.expected),to_jsonb(v.expected)
from (values
 ('snapshot_nodes',4008),('matched_snapshot_nodes',2032),('staging_candidates',1976),('matching_edges',2034),
 ('nn_components',1),('provisional_confirmed',170),('review_required',839),('provisional_rejected',927),
 ('provisional_unsupported',40),('candidate_group_total',1976),('product_status_total',1976),
 ('sampled_categories',100),('sampled_products',906),('canonical_promoted',0),('orphan_fk',0)
) v(rule_code,expected)
on conflict (import_run_id,rule_code) do update set passed=true,affected_count=0,expected_value=excluded.expected_value,actual_value=excluded.actual_value,validated_at=now();

with values_to_hash as (
  select 'node:'||n.id::text||':'||n.raw_hash value
  from fitmatch_staging.source_category_nodes n join fitmatch_staging.source_snapshots s on s.id=n.source_snapshot_id
  where s.import_run_id='40677f85-e8a0-4a72-ad27-45524f385bcf'
  union all
  select 'candidate:'||id::text||':'||provisional_classification_status from fitmatch_staging.classification_candidates where import_run_id='40677f85-e8a0-4a72-ad27-45524f385bcf'
  union all
  select 'edge:'||id::text||':'||matching_method from fitmatch_staging.identity_matching_edges where import_run_id='40677f85-e8a0-4a72-ad27-45524f385bcf'
  union all
  select 'product:'||e.id::text||':'||e.raw_evidence_hash from fitmatch_staging.sampled_product_evidence e join fitmatch_staging.sampling_runs s on s.id=e.sampling_run_id where s.import_run_id='40677f85-e8a0-4a72-ad27-45524f385bcf'
), digest as (select md5(string_agg(value,'|' order by value)) checksum from values_to_hash)
update fitmatch_staging.import_runs r
set status='completed',completed_at=now(),output_checksum=digest.checksum
from digest
where r.id='40677f85-e8a0-4a72-ad27-45524f385bcf' and r.status='validating';

commit;
