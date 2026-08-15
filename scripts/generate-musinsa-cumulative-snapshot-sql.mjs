#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const repo = path.resolve(import.meta.dirname, "..");
const batchId = "20260815-115051";
const runDir = path.join(repo, "Docs/TestEvidence/MusinsaCatalogIncremental/runs", batchId);
const baselinePath = path.join(repo, "Docs/Research/CategoryCorpus-bootstrap/product_manifest.json");
const output = path.join(repo, "Docs/FitMatch_MusinsaCumulativeSnapshot_20260815_115051.sql.txt");

const baseline = JSON.parse(fs.readFileSync(baselinePath, "utf8")).products
  .filter((row) => row.source === "musinsa");
const newInputs = JSON.parse(fs.readFileSync(path.join(runDir, "new_product_inputs.json"), "utf8"));

function audience(value) {
  const text = String(value ?? "");
  if (/여성|WOMEN/i.test(text)) return "WOMEN";
  if (/남성|MEN/i.test(text)) return "MEN";
  if (/키즈|아동|KIDS/i.test(text)) return "KIDS";
  return "UNKNOWN";
}

const records = new Map();
for (const row of baseline) {
  records.set(String(row.product_key), {
    external_product_id: String(row.product_key),
    product_name: row.product_name || `(musinsa ${row.product_key})`,
    canonical_url: row.product_url || `https://www.musinsa.com/products/${row.product_key}`,
    audience: audience(row.audience),
    observed_ids: (row.observed_ids || [String(row.product_key)]).map(String),
    source_category_path: (row.exposure_paths || [""])[0],
    source_category_codes: [],
    size_count: null,
    image_url: null,
    raw_summary: { cumulative_source: "baseline_manifest", batch_id: batchId },
  });
}

for (const row of newInputs) {
  const raw = JSON.parse(fs.readFileSync(row.product.path, "utf8")).data || {};
  const category = raw.category || {};
  const codes = [1, 2, 3, 4]
    .map((depth) => category[`categoryDepth${depth}Code`])
    .filter(Boolean)
    .map(String);
  const thumbnail = raw.thumbnailImageUrl || "";
  records.set(String(row.product_id), {
    external_product_id: String(row.product_id),
    product_name: row.product_name,
    canonical_url: `https://www.musinsa.com/products/${row.product_id}`,
    audience: audience((raw.sex || []).join(" ")),
    observed_ids: [String(row.product_id)],
    source_category_path: row.category_path,
    source_category_codes: codes,
    size_count: row.size_row_count,
    image_url: thumbnail ? (thumbnail.startsWith("http") ? thumbnail : `https://image.msscdn.net${thumbnail}`) : null,
    raw_summary: {
      cumulative_source: "incremental_batch",
      batch_id: batchId,
      brand: row.brand,
      size_type: row.size_type,
      product_sha256: row.product.sha256,
      actual_size_sha256: row.actual_size.sha256,
      options_sha256: row.options.sha256,
    },
  });
}

const payload = [...records.values()].sort((a, b) => Number(a.external_product_id) - Number(b.external_product_id));
if (baseline.length !== 200 || newInputs.length !== 183 || payload.length !== 383) {
  throw new Error(`count mismatch: baseline=${baseline.length}, new=${newInputs.length}, payload=${payload.length}`);
}

const sql = `-- FitMatch MUSINSA cumulative snapshot: existing baseline 200 + new 183 = 383
-- Batch ${batchId}. The 195 products absent from this shallow discovery are retained.
-- Safe to rerun: only this batch-scoped run is rebuilt inside a transaction.

begin;

do $preflight$
declare v_release_count integer;
begin
  select count(*) into v_release_count
  from fitmatch_catalog.releases where status='active';
  if v_release_count<>1 then
    raise exception 'Expected exactly one active mapping release, got %',v_release_count;
  end if;
end
$preflight$;

with existing as (
  select id
  from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${batchId}'
  order by created_at desc limit 1
), inserted as (
  insert into fitmatch_catalog.product_collection_runs (
    source,run_kind,status,snapshot_date,mapping_release_id,
    expected_count,discovered_count,stored_count,failed_count,
    cursor,metadata,started_at,finished_at
  )
  select 'musinsa','manual','running',date '2026-08-15',
         (select id from fitmatch_catalog.releases where status='active'),
         383,188,0,0,'{}'::jsonb,
         jsonb_build_object(
           'incremental_run_id','${batchId}',
           'snapshot_mode','cumulative_known_products',
           'baseline_retained',200,
           'new_inserted',183,
           'discovered_this_run',188,
           'shallow_discovery_missing_not_deleted',195
         ),
         timestamptz '2026-08-15 11:50:51+09',null
  where not exists(select 1 from existing)
  returning id
), target as (
  select id from existing union all select id from inserted limit 1
)
update fitmatch_catalog.product_collection_runs r
set status='running',mapping_release_id=(select id from fitmatch_catalog.releases where status='active'),
    expected_count=383,discovered_count=188,stored_count=0,failed_count=0,
    error_summary=null,finished_at=null
where r.id=(select id from target);

delete from fitmatch_catalog.source_product_snapshots p
where p.run_id=(
  select id from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${batchId}'
  order by created_at desc limit 1
);

with payload as (
  select * from jsonb_to_recordset($musinsa_products$${JSON.stringify(payload)}$musinsa_products$::jsonb) as x(
    external_product_id text,product_name text,canonical_url text,audience text,
    observed_ids text[],source_category_path text,source_category_codes text[],
    size_count integer,image_url text,raw_summary jsonb
  )
), target_run as (
  select id,mapping_release_id
  from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${batchId}'
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
      and x.source='musinsa'
      and (
        (cardinality(p.source_category_codes)>0
         and x.external_category_id=p.source_category_codes[cardinality(p.source_category_codes)])
        or x.normalized_path=p.source_category_path
        or x.normalized_path=regexp_replace(p.source_category_path,'^Clothing > ','')
      )
    order by
      (x.external_category_id=p.source_category_codes[cardinality(p.source_category_codes)]) desc,
      (x.target=p.audience) desc,
      (x.target in ('UNKNOWN','NULL')) desc,
      x.runtime_lookup_eligible desc,
      x.source_identity
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
select run_id,'musinsa',external_product_id,product_name,canonical_url,audience,
       observed_ids,source_category_path,source_category_codes,
       case when decision_status='confirmed' then category_display_name end,
       null,
       case
         when decision_status='confirmed' then 'conditional'
         when decision_status in ('rejected','excluded') then 'excluded_review'
         else 'unclassified'
       end,
       size_count,image_url,
       raw_summary || jsonb_build_object(
         'db_category_resolution',coalesce(decision_status,'no_mapping'),
         'detail_resolution','product_classifier_required'
       ),
       now(),mapping_release_id,source_identity
from resolved;

do $verify$
declare v_run uuid; v_total integer; v_new integer; v_distinct integer;
begin
  select id into v_run
  from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${batchId}'
  order by created_at desc limit 1;

  select count(*),count(distinct external_product_id),
         count(*) filter(where raw_summary->>'cumulative_source'='incremental_batch')
  into v_total,v_distinct,v_new
  from fitmatch_catalog.source_product_snapshots where run_id=v_run;

  if v_total<>383 or v_distinct<>383 or v_new<>183 then
    raise exception 'MUSINSA verification failed: total %, distinct %, new %',v_total,v_distinct,v_new;
  end if;

  update fitmatch_catalog.product_collection_runs
  set status='succeeded',stored_count=383,failed_count=0,
      finished_at=timestamptz '2026-08-15 11:54:05.836432+09'
  where id=v_run;
end
$verify$;

commit;

select r.id run_id,r.status,r.expected_count,r.discovered_count,r.stored_count,
       count(p.*) snapshot_rows,
       count(*) filter(where p.raw_summary->>'cumulative_source'='baseline_manifest') retained_baseline,
       count(*) filter(where p.raw_summary->>'cumulative_source'='incremental_batch') inserted_new,
       count(*) filter(where p.classification_status='conditional') conditional,
       count(*) filter(where p.classification_status='excluded_review') excluded_review,
       count(*) filter(where p.classification_status='unclassified') unclassified,
       count(*) filter(where p.source_mapping_identity is null) mapping_gaps
from fitmatch_catalog.product_collection_runs r
join fitmatch_catalog.source_product_snapshots p on p.run_id=r.id
where r.source='musinsa' and r.metadata->>'incremental_run_id'='${batchId}'
group by r.id,r.status,r.expected_count,r.discovered_count,r.stored_count;
`;

fs.writeFileSync(output,sql,"utf8");
console.log(JSON.stringify({output,baseline:baseline.length,new:newInputs.length,total:payload.length},null,2));
