// Isolated PostgreSQL/WASM contract test. No live credentials or user rows.
// npm install --prefix /tmp/fitmatch-sql-check @electric-sql/pglite
// node supabase/sql/tests/comparison_preview_20260928.mjs /tmp/fitmatch-sql-check/node_modules/@electric-sql/pglite/dist/index.js
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const u = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const baseline = await readFile(new URL('./comparison_preview_20260928_baseline.sql', import.meta.url), 'utf8');
const patch = await readFile(new URL('../comparison_preview_evidence_20260928.sql', import.meta.url), 'utf8');
await db.exec(`
create schema auth; create schema fitmatch_vnext;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table fitmatch_vnext.products(id uuid primary key);
create table fitmatch_vnext.product_variants(id uuid primary key, product_id uuid, sort_order int);
create table fitmatch_vnext.closet_items(id uuid primary key, user_id uuid, deleted_at timestamptz,
 updated_at timestamptz, comparison_group_code text, item_name text, size_label text,
 product_id uuid, product_variant_id uuid, product_size_id uuid, is_reference boolean);
create table fitmatch_vnext.test_eligibility(closet_id uuid, variant_id uuid, payload jsonb);
create table fitmatch_vnext.test_calls(closet_id uuid, variant_id uuid);
create function fitmatch_vnext.product_comparison_group(uuid) returns jsonb language sql as
 $$select '{"group_code":"A"}'::jsonb$$;
create function fitmatch_vnext.closet_comparison_group(uuid) returns jsonb language sql as
 $$select jsonb_build_object('group_code',comparison_group_code) from fitmatch_vnext.closet_items where id=$1$$;
create function fitmatch_vnext.effective_target_classification(uuid) returns jsonb language sql as
 $$select '{"classification_status":"CONFIRMED"}'::jsonb$$;
create function fitmatch_vnext.comparison_target_context(uuid,uuid,text) returns jsonb language sql as
 $$select jsonb_build_object('target_comparison_group', jsonb_build_object('group_code',$3),
 'effective_classification','{"classification_status":"CONFIRMED"}'::jsonb)$$;
create function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean) returns jsonb language plpgsql as $$
begin insert into fitmatch_vnext.test_calls values($1,$3);
return (select payload from fitmatch_vnext.test_eligibility where closet_id=$1 and variant_id=$3); end$$;
create function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean,text) returns jsonb language sql as
 $$select fitmatch_vnext.eligible_candidate_sizes($1,$2,$3,$4)$$;
insert into fitmatch_vnext.products values('${u(10)}');
insert into fitmatch_vnext.product_variants values('${u(11)}','${u(10)}',1),('${u(12)}','${u(10)}',2);
select set_config('test.uid','${u(99)}',false);
`);
for (const [id, group, owner, deleted] of [[1,'A',99,false],[2,'B',99,false],[3,'A',99,false],[4,'A',98,false],[5,'A',99,true]]) {
 await db.query(`insert into fitmatch_vnext.closet_items values($1,$2,$3,now(),$4,'fixture','M',null,null,null,false)`,
 [u(id),u(owner),deleted?'2026-01-01':null,group]);
 for (const variant of [11,12]) {
  const allowed=id!==3 && variant===11;
  const payload={allowed, decision:allowed?'MANUAL_EXTENDED':'BLOCKED',mode:allowed?'MANUAL_EXTENDED':'NONE',
   reason_code:allowed?'USER_SELECTED_REFERENCE':'NO_ELIGIBLE_TARGET_SIZE',manual_explicit:true,
   reference_closet_item_id:u(id),target_product_id:u(10),target_variant_id:u(variant),
   authorized_candidate_product_size_ids:allowed?[u(20)]:[],candidate_authority_fingerprint:`evidence-${id}-${variant}`,
   candidates:allowed?[{product_size_id:u(20),comparison_measurements:[{measurement_code:'chest_width',reference_value:50,target_value:51}]}]:[]};
  await db.query('insert into fitmatch_vnext.test_eligibility values($1,$2,$3)',[u(id),u(variant),JSON.stringify(payload)]);
 }
}
await db.exec(baseline);
const cases=[
 [null,11,null], [null,11,1], [null,11,2], [null,11,3], [null,11,4], [null,11,5], [null,11,100],
 [null,null,null], ['A',11,null], ['A',11,1], ['A',11,2], ['A',11,3], ['A',11,4], ['A',11,5]
];
async function run([group,variant,closet]) {
 await db.exec('truncate fitmatch_vnext.test_calls');
 const sql=group===null?'select fitmatch_vnext.find_reference_candidates_filtered($1::uuid,$2::uuid,$3::uuid) as data':
 'select fitmatch_vnext.find_reference_candidates_filtered($1::uuid,$2::uuid,$4::text,$3::uuid) as data';
 const args=[u(10),variant===null?null:u(variant),closet===null?null:u(closet)];
 if(group!==null) args.push(group);
 const { rows }=await db.query(sql,args);
 const calls=(await db.query('select * from fitmatch_vnext.test_calls order by closet_id,variant_id')).rows;
 return {data:rows[0].data,calls};
}
const before=[];
for(const c of cases) before.push(await run(c));
await db.exec(patch);
function withoutPreview(x) {
 if(Array.isArray(x)) return x.map(withoutPreview);
 if(x!==null && typeof x==='object') return Object.fromEntries(Object.entries(x)
  .filter(([key])=>key!=='comparison_preview').map(([key,value])=>[key,withoutPreview(value)]));
 return x;
}
for (let i=0;i<cases.length;i++) {
 const after=await run(cases[i]);
 assert.deepEqual(withoutPreview(after.data),before[i].data,`existing JSON parity ${i}`);
 assert.deepEqual(after.calls,before[i].calls,`no added eligibility calls ${i}`);
 for(const item of after.data.candidates) {
  if(cases[i][1]===null) {assert.equal(item.comparison_preview,null);continue;}
  const expected=(await db.query('select payload from fitmatch_vnext.test_eligibility where closet_id=$1 and variant_id=$2',
   [item.closet_item_id,u(cases[i][1])])).rows[0].payload;
  assert.deepEqual(item.comparison_preview,expected,`exact evidence ${i}`);
 }
 for(const item of after.data.blocked) assert.ok(item.comparison_preview==null,'blocked has no prior-row evidence');
}
await db.exec("select set_config('test.uid','',false)");
for(const group of [null,'A']) await assert.rejects(()=>run([group,11,null]),/Authentication required/);
await db.exec(`select set_config('test.uid','${u(99)}',false)`);
await assert.rejects(()=>run([null,999,null]),/Target variant hierarchy mismatch/);
await db.exec(baseline);
for(let i=0;i<cases.length;i++) assert.deepEqual(await run(cases[i]),before[i],`rollback parity ${i}`);
await db.close();
console.log('PASS: 14 mapped/session/full/selected/owner/deleted/blocked/multivariant cases; exact evidence, unchanged existing JSON and eligibility calls; authentication/variant rejection; rollback parity. Policy/eligibility helpers are stubs, not live E2E.');
