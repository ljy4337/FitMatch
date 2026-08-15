#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const repo = path.resolve(import.meta.dirname, "..");
const runId = "20260815-111623";
const runDir = path.join(repo, "Docs/TestEvidence/UniqloCatalogIncremental/runs", runId);
const output = path.join(repo, "Docs/FitMatch_UniqloCurrentSnapshot_20260815_111623.sql.txt");

const csvLines = fs.readFileSync(path.join(runDir, "discovered_products.csv"), "utf8")
  .replace(/^\uFEFF/, "")
  .trim()
  .split(/\r?\n/);
const currentIds = csvLines.slice(1).map((line) => line.slice(0, line.indexOf(",")));
const newInputs = JSON.parse(fs.readFileSync(path.join(runDir, "new_product_inputs.json"), "utf8"));
const newIds = new Set(newInputs.map((row) => row.product_id));

if (currentIds.length !== 1039 || newInputs.length !== 226) {
  throw new Error(`unexpected counts: current=${currentIds.length}, new=${newInputs.length}`);
}
if (new Set(currentIds).size !== currentIds.length) throw new Error("duplicate current product ID");
if ([...newIds].some((id) => !currentIds.includes(id))) throw new Error("new product absent from current discovery");

const payload = newInputs.map((row) => ({
  external_product_id: row.product_id,
  product_name: row.product_name,
  canonical_url: row.canonical_url,
  audience: row.audience,
  observed_ids: row.observed_ids,
  source_category_path: row.source_path,
  source_category_codes: row.source_depth_codes,
  size_count: row.size_count_official,
  raw_summary: {
    gender_name: row.gender_name,
    gender_category: row.gender_category,
    product_type: row.product_type,
    product_type_kr: row.product_type_kr,
    incremental_run_id: runId,
  },
}));

const sql = `-- FitMatch UNIQLO current 1,039-product snapshot
-- Batch: ${runId}; current=1,039; new=226; missing historical=67; retries=0
-- Safe to rerun: only this batch run is rebuilt, and the transaction rolls back on verification failure.

begin;

do $preflight$
declare
  v_active_release uuid;
  v_previous_count integer;
  v_batch_exists boolean;
begin
  select id into v_active_release
  from fitmatch_catalog.releases
  where status = 'active';
  if v_active_release is null then
    raise exception 'No active mapping release';
  end if;

  select count(*) into v_previous_count
  from fitmatch_catalog.current_source_products
  where source = 'uniqlo';
  select exists(
    select 1 from fitmatch_catalog.product_collection_runs
    where source='uniqlo' and metadata->>'incremental_run_id'='${runId}'
  ) into v_batch_exists;
  if v_previous_count <> 880 and not (v_batch_exists and v_previous_count = 1039) then
    raise exception 'Expected prior 880 rows or rerunnable batch 1039 rows, got %', v_previous_count;
  end if;
end
$preflight$;

with existing as (
  select id
  from fitmatch_catalog.product_collection_runs
  where source = 'uniqlo'
    and metadata->>'incremental_run_id' = '${runId}'
  order by created_at desc
  limit 1
), inserted as (
  insert into fitmatch_catalog.product_collection_runs (
    source, run_kind, status, snapshot_date, mapping_release_id,
    expected_count, discovered_count, stored_count, failed_count,
    cursor, metadata, started_at, finished_at
  )
  select
    'uniqlo', 'manual', 'running', date '2026-08-15',
    (select id from fitmatch_catalog.releases where status='active'),
    1039, 1039, 0, 0, '{}'::jsonb,
    jsonb_build_object(
      'incremental_run_id','${runId}',
      'source_file','discovered_products.csv',
      'new_product_file','new_product_inputs.json',
      'current_count',1039,
      'new_count',226,
      'missing_historical_count',67
    ),
    timestamptz '2026-08-15 11:16:23+09', null
  where not exists (select 1 from existing)
  returning id
), target_run as (
  select id from existing
  union all
  select id from inserted
  limit 1
)
update fitmatch_catalog.product_collection_runs r
set status='running', mapping_release_id=(select id from fitmatch_catalog.releases where status='active'),
    expected_count=1039, discovered_count=1039, stored_count=0, failed_count=0,
    error_summary=null, finished_at=null
where r.id=(select id from target_run);

delete from fitmatch_catalog.source_product_snapshots p
where p.run_id = (
  select id from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${runId}'
  order by created_at desc limit 1
);

with current_ids as (
  select jsonb_array_elements_text($current_ids$${JSON.stringify(currentIds)}$current_ids$::jsonb) external_product_id
), target_run as (
  select id, mapping_release_id
  from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${runId}'
  order by created_at desc limit 1
), previous_run as (
  select r.id
  from fitmatch_catalog.product_collection_runs r, target_run t
  where r.source='uniqlo' and r.status in ('succeeded','partial') and r.id<>t.id
  order by r.snapshot_date desc,r.created_at desc
  limit 1
)
insert into fitmatch_catalog.source_product_snapshots (
  run_id,source,external_product_id,product_name,canonical_url,audience,
  observed_ids,source_category_path,source_category_codes,
  fitmatch_category_label,fitmatch_detail_label,classification_status,
  size_count,image_url,raw_summary,collected_at,
  mapping_release_id,source_mapping_identity
)
select t.id,p.source,p.external_product_id,p.product_name,p.canonical_url,p.audience,
       p.observed_ids,p.source_category_path,p.source_category_codes,
       p.fitmatch_category_label,p.fitmatch_detail_label,p.classification_status,
       p.size_count,p.image_url,
       p.raw_summary || jsonb_build_object('carried_forward_from_run_id',p.run_id),
       now(),t.mapping_release_id,p.source_mapping_identity
from current_ids c
join fitmatch_catalog.source_product_snapshots p on p.external_product_id=c.external_product_id
join previous_run old on old.id=p.run_id
cross join target_run t;

with payload as (
  select * from jsonb_to_recordset($new_products$${JSON.stringify(payload)}$new_products$::jsonb) as x(
    external_product_id text, product_name text, canonical_url text, audience text,
    observed_ids text[], source_category_path text, source_category_codes text[],
    size_count integer, raw_summary jsonb
  )
), target_run as (
  select id,mapping_release_id
  from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${runId}'
  order by created_at desc limit 1
), resolved as (
  select p.*,t.id run_id,t.mapping_release_id,
         m.source_identity,m.decision_status,m.semantic_category_code,
         c.display_name category_display_name
  from payload p cross join target_run t
  left join lateral (
    select x.source_identity,x.decision_status,x.semantic_category_code
    from fitmatch_catalog.source_category_mappings x
    where x.release_id=t.mapping_release_id
      and x.source='uniqlo'
      and x.external_category_id=p.source_category_codes[cardinality(p.source_category_codes)]
    order by (x.target=p.audience) desc,x.runtime_lookup_eligible desc,x.source_identity
    limit 1
  ) m on true
  left join fitmatch_catalog.app_categories c
    on c.release_id=t.mapping_release_id and c.code=m.semantic_category_code
)
insert into fitmatch_catalog.source_product_snapshots (
  run_id,source,external_product_id,product_name,canonical_url,audience,
  observed_ids,source_category_path,source_category_codes,
  fitmatch_category_label,fitmatch_detail_label,classification_status,
  size_count,image_url,raw_summary,collected_at,
  mapping_release_id,source_mapping_identity
)
select run_id,'uniqlo',external_product_id,product_name,canonical_url,audience,
       observed_ids,source_category_path,source_category_codes,
       case when decision_status='confirmed' then category_display_name end,
       null,
       case
         when decision_status='confirmed' then 'conditional'
         when decision_status in ('rejected','excluded') then 'excluded_review'
         else 'unclassified'
       end,
       size_count,null,
       raw_summary || jsonb_build_object(
         'db_category_resolution',coalesce(decision_status,'no_mapping'),
         'detail_resolution','product_classifier_required'
       ),
       now(),mapping_release_id,source_identity
from resolved;

do $verify$
declare
  v_run uuid;
  v_total integer;
  v_new integer;
  v_distinct integer;
begin
  select id into v_run
  from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${runId}'
  order by created_at desc limit 1;

  select count(*),count(distinct external_product_id),
         count(*) filter (where raw_summary->>'incremental_run_id'='${runId}')
  into v_total,v_distinct,v_new
  from fitmatch_catalog.source_product_snapshots where run_id=v_run;

  if v_total<>1039 or v_distinct<>1039 or v_new<>226 then
    raise exception 'Snapshot verification failed: total %, distinct %, new %',v_total,v_distinct,v_new;
  end if;

  update fitmatch_catalog.product_collection_runs
  set status='succeeded',stored_count=1039,failed_count=0,
      finished_at=timestamptz '2026-08-15 11:41:44.477694+09'
  where id=v_run;
end
$verify$;

commit;

select r.id run_id,r.status,r.discovered_count,r.stored_count,r.failed_count,
       count(p.*) snapshot_rows,
       count(*) filter(where p.classification_status='comparable') comparable,
       count(*) filter(where p.classification_status='conditional') conditional,
       count(*) filter(where p.classification_status='excluded_review') excluded_review,
       count(*) filter(where p.classification_status='unclassified') unclassified,
       count(*) filter(where p.source_mapping_identity is null) mapping_gaps
from fitmatch_catalog.product_collection_runs r
join fitmatch_catalog.source_product_snapshots p on p.run_id=r.id
where r.source='uniqlo' and r.metadata->>'incremental_run_id'='${runId}'
group by r.id,r.status,r.discovered_count,r.stored_count,r.failed_count;
`;

fs.writeFileSync(output, sql, "utf8");
console.log(JSON.stringify({ output, current: currentIds.length, new: payload.length }, null, 2));
