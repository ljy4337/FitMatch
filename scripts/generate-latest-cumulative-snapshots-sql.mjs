#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const repo = path.resolve(import.meta.dirname, "..");
const uniqloRoot = "/Users/jinyoung/Desktop/유니클로_배치결과";
const uniqloRunId = "20260815-181456";
const uniqloRunDir = path.join(uniqloRoot, uniqloRunId);
const musinsaRunId = "20260815-120901";
const musinsaRunDir = "/Users/jinyoung/Desktop/무신사_배치결과/20260815-120901";
const output = path.join(repo, "Docs/FitMatch_LatestCumulativeSnapshots_20260815.sql.txt");

function csvFirstColumn(file) {
  return fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "").trim().split(/\r?\n/).slice(1)
    .map((line) => line.slice(0, line.indexOf(",")));
}

function audience(value) {
  const text = String(value ?? "");
  if (/여성|WOMEN|\bW\b/i.test(text)) return "WOMEN";
  if (/남성|MEN|\bM\b/i.test(text)) return "MEN";
  if (/키즈|아동|KIDS/i.test(text)) return "KIDS";
  return "UNKNOWN";
}

const discoveredUniqlo = csvFirstColumn(path.join(uniqloRunDir, "discovered_products.csv"));
const pendingUniqlo = new Set(["E479751"]);
const usableUniqlo = discoveredUniqlo.filter((id) => !pendingUniqlo.has(id));
const localUniqloById = new Map();
for (const entry of fs.readdirSync(uniqloRoot, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const input = path.join(uniqloRoot, entry.name, "new_product_inputs.json");
  if (!fs.existsSync(input)) continue;
  for (const row of JSON.parse(fs.readFileSync(input, "utf8"))) {
    localUniqloById.set(row.product_id, { batchId: entry.name, row });
  }
}
const uniqloPayload = usableUniqlo.filter((id) => localUniqloById.has(id)).map((id) => {
  const { batchId, row } = localUniqloById.get(id);
  return {
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
      incremental_run_id: batchId,
      cumulative_source: "local_incremental_detail",
    },
  };
});

const musinsaInputs = JSON.parse(fs.readFileSync(path.join(musinsaRunDir, "new_product_inputs.json"), "utf8"));
if (musinsaInputs.length !== 1 || String(musinsaInputs[0].product_id) !== "6842888") {
  throw new Error(`Expected only Musinsa 6842888, got ${musinsaInputs.length}`);
}
const musinsaInput = musinsaInputs[0];
const musinsaRaw = JSON.parse(fs.readFileSync(musinsaInput.product.path, "utf8")).data || {};
const musinsaCategory = musinsaRaw.category || {};
const musinsaCodes = [1, 2, 3, 4]
  .map((depth) => musinsaCategory[`categoryDepth${depth}Code`]).filter(Boolean).map(String);
const thumbnail = musinsaRaw.thumbnailImageUrl || "";
const musinsaPayload = [{
  external_product_id: String(musinsaInput.product_id),
  product_name: musinsaInput.product_name,
  canonical_url: `https://www.musinsa.com/products/${musinsaInput.product_id}`,
  audience: audience(musinsaRaw.sex || musinsaRaw.genders || []),
  observed_ids: [String(musinsaInput.product_id)],
  source_category_path: musinsaInput.category_path,
  source_category_codes: musinsaCodes,
  size_count: musinsaInput.size_row_count,
  image_url: thumbnail ? (thumbnail.startsWith("http") ? thumbnail : `https://image.msscdn.net${thumbnail}`) : null,
  raw_summary: {
    cumulative_source: "incremental_batch",
    incremental_run_id: musinsaRunId,
    brand: musinsaInput.brand,
    size_type: musinsaInput.size_type,
    product_sha256: musinsaInput.product.sha256,
    actual_size_sha256: musinsaInput.actual_size.sha256,
    options_sha256: musinsaInput.options.sha256,
  },
}];

if (discoveredUniqlo.length !== 1157 || usableUniqlo.length !== 1156 || uniqloPayload.length !== 52) {
  throw new Error(`UNIQLO counts changed: discovered=${discoveredUniqlo.length}, usable=${usableUniqlo.length}, local=${uniqloPayload.length}`);
}
if (new Set(usableUniqlo).size !== usableUniqlo.length) throw new Error("Duplicate UNIQLO ID");

const sql = `-- FitMatch latest cumulative product snapshots
-- UNIQLO ${uniqloRunId}: discovered 1,157; stored 1,156; pending E479751
-- MUSINSA ${musinsaRunId}: prior cumulative 383 + product 6842888 = 384
-- Run the whole file in Supabase SQL Editor. Any failed assertion rolls everything back.

begin;
select pg_advisory_xact_lock(hashtext('fitmatch_catalog_product_snapshot_update'));

do $preflight$
declare
  v_release_count integer;
  v_uniqlo_current integer;
  v_musinsa_current integer;
begin
  select count(*) into v_release_count from fitmatch_catalog.releases where status='active';
  if v_release_count <> 1 then
    raise exception 'Expected exactly one active release, got %', v_release_count;
  end if;
  select count(*) into v_uniqlo_current from fitmatch_catalog.current_source_products where source='uniqlo';
  select count(*) into v_musinsa_current from fitmatch_catalog.current_source_products where source='musinsa';
  if v_uniqlo_current not in (1039,1156) then
    raise exception 'Expected UNIQLO current count 1039 (before) or 1156 (rerun), got %',v_uniqlo_current;
  end if;
  if v_musinsa_current not in (383,384) then
    raise exception 'Expected MUSINSA current count 383 (before) or 384 (rerun), got %',v_musinsa_current;
  end if;
end
$preflight$;

-- Create or reset the batch-scoped UNIQLO run.
with existing as (
  select id from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${uniqloRunId}'
  order by created_at desc limit 1
), inserted as (
  insert into fitmatch_catalog.product_collection_runs (
    source,run_kind,status,snapshot_date,mapping_release_id,
    expected_count,discovered_count,stored_count,failed_count,cursor,metadata,started_at
  )
  select 'uniqlo','manual','running',date '2026-08-15',
         (select id from fitmatch_catalog.releases where status='active'),
         1157,1157,0,1,'{}'::jsonb,
         jsonb_build_object(
           'incremental_run_id','${uniqloRunId}',
           'snapshot_mode','complete_current_catalog',
           'locally_detailed_rows',52,
           'carried_from_database_history',1104,
           'pending_retry',jsonb_build_array('E479751'),
           'not_seen_not_deleted',2
         ),timestamptz '2026-08-15 18:14:56+09'
  where not exists(select 1 from existing)
  returning id
), target as (
  select id from existing union all select id from inserted limit 1
)
update fitmatch_catalog.product_collection_runs r
set status='running',mapping_release_id=(select id from fitmatch_catalog.releases where status='active'),
    expected_count=1157,discovered_count=1157,stored_count=0,failed_count=1,
    error_summary=null,finished_at=null
where r.id=(select id from target);

delete from fitmatch_catalog.source_product_snapshots
where run_id=(
  select id from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${uniqloRunId}'
  order by created_at desc limit 1
);

-- Restore current IDs from their newest successful historical DB row.
with current_ids as (
  select jsonb_array_elements_text($uniqlo_ids$${JSON.stringify(usableUniqlo)}$uniqlo_ids$::jsonb) external_product_id
), local_ids as (
  select x->>'external_product_id' external_product_id
  from jsonb_array_elements($uniqlo_local$${JSON.stringify(uniqloPayload)}$uniqlo_local$::jsonb) x
), target as (
  select id,mapping_release_id from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${uniqloRunId}'
  order by created_at desc limit 1
), history as (
  select p.*,row_number() over(
    partition by p.external_product_id
    order by r.snapshot_date desc,r.created_at desc,p.collected_at desc
  ) position
  from fitmatch_catalog.source_product_snapshots p
  join fitmatch_catalog.product_collection_runs r on r.id=p.run_id
  cross join target t
  where p.source='uniqlo' and r.status in ('succeeded','partial') and r.id<>t.id
)
insert into fitmatch_catalog.source_product_snapshots (
  run_id,source,external_product_id,product_name,canonical_url,audience,observed_ids,
  source_category_path,source_category_codes,fitmatch_category_label,fitmatch_detail_label,
  classification_status,size_count,image_url,raw_summary,collected_at,
  mapping_release_id,source_mapping_identity
)
select t.id,h.source,h.external_product_id,h.product_name,h.canonical_url,h.audience,h.observed_ids,
       h.source_category_path,h.source_category_codes,h.fitmatch_category_label,h.fitmatch_detail_label,
       h.classification_status,h.size_count,h.image_url,
       h.raw_summary || jsonb_build_object('carried_forward_from_run_id',h.run_id),now(),
       t.mapping_release_id,h.source_mapping_identity
from current_ids c
join history h on h.external_product_id=c.external_product_id and h.position=1
cross join target t
where not exists(select 1 from local_ids l where l.external_product_id=c.external_product_id);

-- Insert locally collected UNIQLO details, resolving them against the active mapping release.
with payload as (
  select * from jsonb_to_recordset($uniqlo_payload$${JSON.stringify(uniqloPayload)}$uniqlo_payload$::jsonb) as x(
    external_product_id text,product_name text,canonical_url text,audience text,
    observed_ids text[],source_category_path text,source_category_codes text[],size_count integer,raw_summary jsonb
  )
), target as (
  select id,mapping_release_id from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${uniqloRunId}'
  order by created_at desc limit 1
), resolved as (
  select p.*,t.id run_id,t.mapping_release_id,m.source_identity,m.decision_status,
         m.semantic_category_code,c.display_name category_display_name
  from payload p cross join target t
  left join lateral (
    select x.source_identity,x.decision_status,x.semantic_category_code
    from fitmatch_catalog.source_category_mappings x
    where x.release_id=t.mapping_release_id and x.source='uniqlo'
      and x.external_category_id=p.source_category_codes[cardinality(p.source_category_codes)]
    order by (x.target=p.audience) desc,x.runtime_lookup_eligible desc,x.source_identity
    limit 1
  ) m on true
  left join fitmatch_catalog.app_categories c
    on c.release_id=t.mapping_release_id and c.code=m.semantic_category_code
)
insert into fitmatch_catalog.source_product_snapshots (
  run_id,source,external_product_id,product_name,canonical_url,audience,observed_ids,
  source_category_path,source_category_codes,fitmatch_category_label,fitmatch_detail_label,
  classification_status,size_count,image_url,raw_summary,collected_at,
  mapping_release_id,source_mapping_identity
)
select run_id,'uniqlo',external_product_id,product_name,canonical_url,audience,observed_ids,
       source_category_path,source_category_codes,
       case when decision_status='confirmed' then category_display_name end,null,
       case when decision_status='confirmed' then 'conditional'
            when decision_status in ('rejected','excluded') then 'excluded_review'
            else 'unclassified' end,
       size_count,null,
       raw_summary || jsonb_build_object('db_category_resolution',coalesce(decision_status,'no_mapping')),
       now(),mapping_release_id,source_identity
from resolved;

do $verify_uniqlo$
declare v_run uuid; v_total integer; v_distinct integer; v_local integer;
begin
  select id into v_run from fitmatch_catalog.product_collection_runs
  where source='uniqlo' and metadata->>'incremental_run_id'='${uniqloRunId}'
  order by created_at desc limit 1;
  select count(*),count(distinct external_product_id),
         count(*) filter(where raw_summary->>'cumulative_source'='local_incremental_detail')
  into v_total,v_distinct,v_local
  from fitmatch_catalog.source_product_snapshots where run_id=v_run;
  if v_total<>1156 or v_distinct<>1156 or v_local<>52 then
    raise exception 'UNIQLO verification failed: total %, distinct %, local %',v_total,v_distinct,v_local;
  end if;
  update fitmatch_catalog.product_collection_runs
  set status='partial',stored_count=1156,failed_count=1,
      error_summary='pending_retry: E479751',
      finished_at=timestamptz '2026-08-15 18:20:49.207778+09'
  where id=v_run;
end
$verify_uniqlo$;

-- Create or reset the cumulative MUSINSA run.
with existing as (
  select id from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${musinsaRunId}'
  order by created_at desc limit 1
), inserted as (
  insert into fitmatch_catalog.product_collection_runs (
    source,run_kind,status,snapshot_date,mapping_release_id,
    expected_count,discovered_count,stored_count,failed_count,cursor,metadata,started_at
  )
  select 'musinsa','manual','running',date '2026-08-15',
         (select id from fitmatch_catalog.releases where status='active'),
         384,188,0,0,'{}'::jsonb,
         jsonb_build_object(
           'incremental_run_id','${musinsaRunId}',
           'snapshot_mode','cumulative_known_products',
           'prior_retained',383,'new_inserted',1,'new_product_id','6842888'
         ),timestamptz '2026-08-15 12:09:01+09'
  where not exists(select 1 from existing)
  returning id
), target as (
  select id from existing union all select id from inserted limit 1
)
update fitmatch_catalog.product_collection_runs r
set status='running',mapping_release_id=(select id from fitmatch_catalog.releases where status='active'),
    expected_count=384,discovered_count=188,stored_count=0,failed_count=0,error_summary=null,finished_at=null
where r.id=(select id from target);

delete from fitmatch_catalog.source_product_snapshots
where run_id=(
  select id from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${musinsaRunId}'
  order by created_at desc limit 1
);

with target as (
  select id,mapping_release_id from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${musinsaRunId}'
  order by created_at desc limit 1
), previous as (
  select r.id from fitmatch_catalog.product_collection_runs r cross join target t
  where r.source='musinsa' and r.status in ('succeeded','partial') and r.id<>t.id
  order by r.snapshot_date desc,r.created_at desc limit 1
)
insert into fitmatch_catalog.source_product_snapshots (
  run_id,source,external_product_id,product_name,canonical_url,audience,observed_ids,
  source_category_path,source_category_codes,fitmatch_category_label,fitmatch_detail_label,
  classification_status,size_count,image_url,raw_summary,collected_at,
  mapping_release_id,source_mapping_identity
)
select t.id,p.source,p.external_product_id,p.product_name,p.canonical_url,p.audience,p.observed_ids,
       p.source_category_path,p.source_category_codes,p.fitmatch_category_label,p.fitmatch_detail_label,
       p.classification_status,p.size_count,p.image_url,
       p.raw_summary || jsonb_build_object('carried_forward_from_run_id',p.run_id),now(),
       t.mapping_release_id,p.source_mapping_identity
from previous old
join fitmatch_catalog.source_product_snapshots p on p.run_id=old.id
cross join target t
where p.external_product_id<>'6842888';

with payload as (
  select * from jsonb_to_recordset($musinsa_payload$${JSON.stringify(musinsaPayload)}$musinsa_payload$::jsonb) as x(
    external_product_id text,product_name text,canonical_url text,audience text,observed_ids text[],
    source_category_path text,source_category_codes text[],size_count integer,image_url text,raw_summary jsonb
  )
), target as (
  select id,mapping_release_id from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${musinsaRunId}'
  order by created_at desc limit 1
), resolved as (
  select p.*,t.id run_id,t.mapping_release_id,m.source_identity,m.decision_status,
         m.semantic_category_code,c.display_name category_display_name
  from payload p cross join target t
  left join lateral (
    select x.source_identity,x.decision_status,x.semantic_category_code
    from fitmatch_catalog.source_category_mappings x
    where x.release_id=t.mapping_release_id and x.source='musinsa'
      and (x.external_category_id=p.source_category_codes[cardinality(p.source_category_codes)]
           or x.normalized_path=p.source_category_path
           or x.normalized_path=regexp_replace(p.source_category_path,'^Clothing > ',''))
    order by (x.external_category_id=p.source_category_codes[cardinality(p.source_category_codes)]) desc,
             (x.target=p.audience) desc,x.runtime_lookup_eligible desc,x.source_identity
    limit 1
  ) m on true
  left join fitmatch_catalog.app_categories c
    on c.release_id=t.mapping_release_id and c.code=m.semantic_category_code
)
insert into fitmatch_catalog.source_product_snapshots (
  run_id,source,external_product_id,product_name,canonical_url,audience,observed_ids,
  source_category_path,source_category_codes,fitmatch_category_label,fitmatch_detail_label,
  classification_status,size_count,image_url,raw_summary,collected_at,
  mapping_release_id,source_mapping_identity
)
select run_id,'musinsa',external_product_id,product_name,canonical_url,audience,observed_ids,
       source_category_path,source_category_codes,
       case when decision_status='confirmed' then category_display_name end,null,
       case when decision_status='confirmed' then 'conditional'
            when decision_status in ('rejected','excluded') then 'excluded_review'
            else 'unclassified' end,
       size_count,image_url,
       raw_summary || jsonb_build_object('db_category_resolution',coalesce(decision_status,'no_mapping')),
       now(),mapping_release_id,source_identity
from resolved;

do $verify_musinsa$
declare v_run uuid; v_total integer; v_distinct integer; v_new integer;
begin
  select id into v_run from fitmatch_catalog.product_collection_runs
  where source='musinsa' and metadata->>'incremental_run_id'='${musinsaRunId}'
  order by created_at desc limit 1;
  select count(*),count(distinct external_product_id),count(*) filter(where external_product_id='6842888')
  into v_total,v_distinct,v_new
  from fitmatch_catalog.source_product_snapshots where run_id=v_run;
  if v_total<>384 or v_distinct<>384 or v_new<>1 then
    raise exception 'MUSINSA verification failed: total %, distinct %, new %',v_total,v_distinct,v_new;
  end if;
  update fitmatch_catalog.product_collection_runs
  set status='succeeded',stored_count=384,failed_count=0,
      finished_at=timestamptz '2026-08-15 12:09:04.572773+09'
  where id=v_run;
end
$verify_musinsa$;

commit;

select source,count(*) total,count(distinct external_product_id) distinct_products,
       count(*) filter(where source_mapping_identity is null) mapping_gaps,
       count(*) filter(where classification_status='conditional') conditional,
       count(*) filter(where classification_status='excluded_review') excluded_review,
       count(*) filter(where classification_status='unclassified') unclassified
from fitmatch_catalog.current_source_products
where source in ('uniqlo','musinsa')
group by source order by source;

select source,external_product_id,product_name,source_category_path,classification_status,
       source_mapping_identity is not null mapping_linked
from fitmatch_catalog.current_source_products
where (source='uniqlo' and raw_summary->>'cumulative_source'='local_incremental_detail')
   or (source='musinsa' and external_product_id='6842888')
order by source,external_product_id;
`;

fs.writeFileSync(output, sql, "utf8");
console.log(JSON.stringify({
  output,
  uniqlo: { discovered: discoveredUniqlo.length, stored: usableUniqlo.length, localPayload: uniqloPayload.length },
  musinsa: { stored: 384, inserted: 1 },
}, null, 2));
