// Isolated Postgres runtime: synthetic users/products only, no live credentials.
// node supabase/sql/tests/size_decision_20261012.mjs <path-to-pglite/dist/index.js>
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const read=name=>readFile(new URL(name,import.meta.url),'utf8');
const u=n=>`abcdefab-0000-0000-0000-${String(n).padStart(12,'0')}`;
let checks=0;
await db.exec(`
create schema auth; create schema fitmatch_vnext; create schema extensions;
create role anon; create role authenticated;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
-- Hash stand-in is confined to this disposable DB; tests exercise equality/idempotency, not crypto.
create function extensions.digest(text,text) returns bytea language sql immutable as $$select convert_to(md5($1),'UTF8')$$;
create table fitmatch_vnext.comparisons(id uuid primary key,user_id uuid,result_status text,
 result_payload_hash text,recommended_product_size_id uuid,recommended_user_recovery_size_id uuid,
 recommended_size_label text,target_snapshot jsonb,policy_snapshot jsonb,excluded_measurement_codes text[],
 target_variant_id uuid,target_product_id uuid,fit_score numeric,reliability_level smallint,coverage_ratio numeric,
 engine_version text,detail_snapshot jsonb,result_evidence jsonb,completed_at timestamptz,snapshot_schema_version integer);
create table fitmatch_vnext.product_variants(id uuid primary key,product_id uuid);
create table fitmatch_vnext.product_sizes(id uuid primary key,variant_id uuid,size_label text);
create function fitmatch_vnext.comparison_product_sizes(boolean) returns setof fitmatch_vnext.product_sizes
 language sql as $$select * from fitmatch_vnext.product_sizes$$;
insert into fitmatch_vnext.product_variants values('${u(10)}','${u(11)}');
insert into fitmatch_vnext.product_sizes values('${u(1)}','${u(10)}','M'),('${u(2)}','${u(10)}','L');
select set_config('test.uid','${u(99)}',false);
`);
const baseline=await read(process.argv[3] || './size_decision_20261012_completion_baseline.sql');
await db.exec(baseline);
const before=(await db.query(`select pg_get_functiondef('fitmatch_vnext.complete_comparison(uuid,jsonb)'::regprocedure) d`)).rows[0].d;
const patch=await read('../../migrations/20261012230000_size_decision_v3.sql');
await db.exec(patch);
const after=(await db.query(`select pg_get_functiondef('fitmatch_vnext.complete_comparison(uuid,jsonb)'::regprocedure) d`)).rows[0].d;
const added=`    if p_result ->> 'engine_version' = 'fitmatch-ios-vnext-snapshot-v3' then
        recommended_evidence_count := fitmatch_vnext.validate_size_decision_v3(row_value.target_snapshot, p_result);
    end if;
`;
assert.equal(after.replace(added,''),before); checks++;
await db.exec(patch); // Safe reapplication of the guarded seam.
assert.equal((await db.query(`select pg_get_functiondef('fitmatch_vnext.complete_comparison(uuid,jsonb)'::regprocedure) d`)).rows[0].d,after);checks++;
const metric=(code,ref,target,weight=1)=>({measurement_code:code,reference_value:ref,target_value:target,
 difference:target-ref,absolute_difference:Math.abs(target-ref),weight,unit_code:'cm',basis_code:code,priority:1,requirement_mode:'OPTIONAL'});
const chest=metric('chest_width',50,50),length=metric('back_length',60,70);
const target={authorized_candidate_product_size_ids:[u(1),u(2)],candidates:[
 {product_size_id:u(1),comparison_measurements:[chest,length]},
 {product_size_id:u(2),comparison_measurements:[metric('chest_width',50,53)]}]};
const evidence=t=>t.candidates.flatMap(c=>c.comparison_measurements.map(m=>({product_size_id:c.product_size_id,
 measurement_code:m.measurement_code,reference_value:m.reference_value,target_value:m.target_value,
 difference:m.difference,absolute_difference:m.absolute_difference,weight:m.weight})));
const result={recommended_product_size_id:u(1),score:100,reliability:1,coverage:0.5,
 engine_version:'fitmatch-ios-vnext-snapshot-v3',ranking_measurement_codes:['chest_width'],
 candidate_size_ranking:[{product_size_id:u(1),rank:1,score:100},{product_size_id:u(2),rank:2,score:85}],metric_evidence:evidence(target)};
const policy={metrics:['chest_width','back_length'].map(code=>({metric_mode:'CANONICAL',is_active:true,fitmatch_measurement_code:code}))};
async function seed(id=20,t=target){await db.query(`insert into fitmatch_vnext.comparisons
 (id,user_id,result_status,target_snapshot,policy_snapshot,excluded_measurement_codes,target_variant_id,target_product_id,snapshot_schema_version)
 values($1,$2,'PENDING',$3,$4,'{}',$5,$6,4)`,[u(id),u(99),t,policy,u(10),u(11)]);}
async function complete(id,p){return (await db.query('select fitmatch_vnext.complete_comparison($1,$2) r',[u(id),p])).rows[0].r;}
const clone=x=>structuredClone(x);
const reject=async(p,pattern=/V3/,t=target)=>{
 await seed(21,t);
 await assert.rejects(()=>complete(21,p),pattern);
 assert.equal((await db.query('select result_status from fitmatch_vnext.comparisons where id=$1',[u(21)])).rows[0].result_status,'PENDING');
 await db.query('delete from fitmatch_vnext.comparisons where id=$1',[u(21)]);checks++;
};
await seed();const completed=await complete(20,result);
assert.equal(completed.completed,true);assert.equal(completed.coverage,0.5);assert.equal(completed.validated_evidence_count,3);checks++;
assert.equal((await complete(20,result)).idempotent,true);checks++;
await assert.rejects(()=>complete(20,{...result,score:99}),/idempotency conflict/);checks++;
for(const codeSet of [[],['back_length'],['chest_width','back_length'],['chest_width','chest_width']])
 await reject({...result,ranking_measurement_codes:codeSet});
let p=clone(result);delete p.ranking_measurement_codes;await reject(p);
p=clone(result);p.score=99;p.candidate_size_ranking[0].score=99;await reject(p);
p=clone(result);p.reliability=2;await reject(p);
p=clone(result);p.coverage=1;await reject(p,/Coverage/);
p=clone(result);p.metric_evidence[0].target_value=55;await reject(p,/Metric evidence/);
for(const key of ['unit_code','basis_code','reference_value','weight']){
 const t=clone(target);t.candidates[1].comparison_measurements[0][key]=key==='weight'?2:key==='reference_value'?49:'other';
 if(key==='reference_value'){t.candidates[1].comparison_measurements[0].difference=4;t.candidates[1].comparison_measurements[0].absolute_difference=4;}
 await reject({...result,metric_evidence:evidence(t)},/V3 common measurement/,t);
}
await db.exec(`select set_config('test.uid','${u(98)}',false)`);
await assert.rejects(()=>complete(20,result),/not owned/);checks++;
await db.exec(`select set_config('test.uid','',false)`);
await assert.rejects(()=>complete(20,result),/Authentication required/);checks++;
await db.exec(`select set_config('test.uid','${u(99)}',false)`);
// Old clients keep full-evidence rankings and coverage, with no v3 codes field.
for(const version of ['v1','v2']){
 await seed(30+(version==='v2'?1:0));
 const old={...result,recommended_product_size_id:u(2),score:85,engine_version:`fitmatch-ios-vnext-snapshot-${version}`,
 candidate_size_ranking:[{product_size_id:u(2),rank:1,score:85},{product_size_id:u(1),rank:2,score:75}]};
 delete old.ranking_measurement_codes;
 assert.equal((await complete(30+(version==='v2'?1:0),old)).completed,true);checks++;
}
// Half-point rounding and deterministic UUID tie order.
const t=clone(target);t.candidates.forEach(c=>c.comparison_measurements=[metric('chest_width',43,42.5,2)]);
p={...result,score:98,candidate_size_ranking:[{product_size_id:u(1),rank:1,score:98},{product_size_id:u(2),rank:2,score:98}],metric_evidence:evidence(t)};
await seed(40,t);assert.equal((await complete(40,p)).completed,true);checks++;
const wrongTie=clone(p);wrongTie.recommended_product_size_id=u(2);wrongTie.candidate_size_ranking.reverse();wrongTie.candidate_size_ranking.forEach((x,i)=>x.rank=i+1);
await reject(wrongTie,/V3 score/,t);
// Real Swift payloads use uppercase UUID strings.
const uppercase=clone(p);
uppercase.recommended_product_size_id=uppercase.recommended_product_size_id.toUpperCase();
uppercase.candidate_size_ranking.forEach(x=>x.product_size_id=x.product_size_id.toUpperCase());
uppercase.metric_evidence.forEach(x=>x.product_size_id=x.product_size_id.toUpperCase());
await seed(41,t);assert.equal((await complete(41,uppercase)).completed,true);checks++;
const permissions=(await db.query(`select has_function_privilege('anon','fitmatch_vnext.validate_size_decision_v3(jsonb,jsonb)','EXECUTE') a,
 has_function_privilege('authenticated','fitmatch_vnext.validate_size_decision_v3(jsonb,jsonb)','EXECUTE') b`)).rows[0];
assert.deepEqual(permissions,{a:false,b:false});checks++;
await db.exec(await read('../20261012_size_decision_v3_Rollback.sql'));
assert.equal((await db.query(`select pg_get_functiondef('fitmatch_vnext.complete_comparison(uuid,jsonb)'::regprocedure) d`)).rows[0].d,before);checks++;
// Exact Zara front length activation, inherited A/B weights, and rollback.
await db.exec(`
create table fitmatch_vnext.fitmatch_measurements(measurement_code text primary key,is_active boolean,
 canonical_unit_code text,canonical_basis_code text);
insert into fitmatch_vnext.fitmatch_measurements values('front_length_shoulder_to_hem',true,'cm','front_shoulder_to_hem');
create table fitmatch_vnext.comparison_policies(policy_code text primary key,display_name text,policy_version text,
 policy_checksum text,min_common_measurements int,required_any_min int,audience_policy_code text,
 sleeve_mismatch_policy text,lower_length_mismatch_policy text,body_length_mismatch_policy text,
 allow_manual_extended boolean,sleeve_mismatch_excluded_codes text[],lower_mismatch_excluded_codes text[],
 body_mismatch_excluded_codes text[],is_active boolean,updated_at timestamptz);
create table fitmatch_vnext.comparison_metrics(id uuid default gen_random_uuid(),comparison_policy_code text,
 metric_mode text,fitmatch_measurement_code text,weight numeric,requirement_mode text,priority int,is_active boolean);
insert into fitmatch_vnext.comparison_metrics(comparison_policy_code,metric_mode,fitmatch_measurement_code,weight,requirement_mode,priority,is_active)
 values('tshirt','CANONICAL','back_length',1,'OPTIONAL',0,true),('unclassified_outerwear','CANONICAL','back_length',0.8,'OPTIONAL',0,true);
`);
const policies=JSON.parse(await read('./size_decision_20261012_policy_fixture.json'));
for(const row of policies)await db.query('insert into fitmatch_vnext.comparison_policies select * from jsonb_populate_record(null::fitmatch_vnext.comparison_policies,$1)',[row]);
await db.exec(await read('../20261012_front_length_Activate.sql'));
const fronts=(await db.query("select comparison_policy_code,weight::float8 as weight from fitmatch_vnext.comparison_metrics where fitmatch_measurement_code='front_length_shoulder_to_hem' order by 1")).rows;
assert.deepEqual(fronts,[{comparison_policy_code:'tshirt',weight:1},{comparison_policy_code:'unclassified_outerwear',weight:0.8}]);checks++;
const frontActivation = await read('../20261012_front_length_Activate.sql');
await assert.rejects(()=>db.exec(frontActivation),/already exists/);
await db.exec('rollback');checks++;
await db.exec(await read('../20261012_front_length_Rollback.sql'));
assert.equal((await db.query("select count(*)::int n from fitmatch_vnext.comparison_metrics where fitmatch_measurement_code='front_length_shoulder_to_hem'")).rows[0].n,0);checks++;
const restored=(await db.query('select policy_code,policy_version from fitmatch_vnext.comparison_policies order by 1')).rows;
assert.deepEqual(restored,policies.map(x=>({policy_code:x.policy_code,policy_version:x.policy_version})).sort((a,b)=>a.policy_code.localeCompare(b.policy_code)));checks++;
console.log(`Verified ${checks} SQL scenarios: v3 scores/ranks, missing-data fairness, spoof rejection, ownership, old clients, idempotency, ACLs and exact rollback.`);
await db.close();
