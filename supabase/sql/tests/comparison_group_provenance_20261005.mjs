// Executes the real context function with isolated dependency fixtures, not live user E2E.
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const root = new URL('../../', import.meta.url);
const baseline = await readFile(new URL('migrations/20260914090000_session_requested_comparison_group_authority.sql', root), 'utf8');
const original = baseline.slice(baseline.indexOf('create or replace function fitmatch_vnext.comparison_target_context('), baseline.indexOf('create or replace function fitmatch_vnext.canonical_measurements_for_session_group('));
const migration = process.argv[3] === '--baseline' ? null : await readFile(new URL('migrations/20261005095057_repair_comparison_group_provenance.sql', root), 'utf8');
const product = '00000000-0000-0000-0000-000000000001';
const variant = '00000000-0000-0000-0000-000000000002';
await db.exec(`
create schema fitmatch_vnext; create schema extensions;
create role anon; create role authenticated; create role service_role;
create table fitmatch_vnext.products(
 id uuid primary key, audience_code text, product_structure_code text,
 input_fingerprint text, evidence_fingerprint text, resolved jsonb, eligible boolean);
create table fitmatch_vnext.product_variants(id uuid primary key,product_id uuid);
create table fitmatch_vnext.garment_types(
 garment_type_code text,category_code text,comparison_policy_code text,is_active boolean);
create table fitmatch_vnext.comparison_policies(
 policy_code text,policy_version text,policy_checksum text,is_active boolean);
create function fitmatch_vnext.product_comparison_group(uuid) returns jsonb language sql as
 $$select resolved from fitmatch_vnext.products where id=$1$$;
create function fitmatch_vnext.comparison_group_tuple(uuid,text) returns jsonb language sql as $$
 select case when coalesce($2,resolved->>'group_code') in ('A','C') then
 jsonb_build_object('group_code',coalesce($2,resolved->>'group_code'),
 'garment_type_code',case coalesce($2,resolved->>'group_code') when 'A' then 'top' else 'pants' end,
 'category_code',case coalesce($2,resolved->>'group_code') when 'A' then 'top' else 'bottom' end) end
 from fitmatch_vnext.products where id=$1$$;
create function fitmatch_vnext.effective_target_classification(uuid) returns jsonb language sql as
 $$select jsonb_build_object('classification_status','CONFIRMED')$$;
create function fitmatch_vnext.product_comparison_unit_decision(uuid) returns jsonb language sql as
 $$select jsonb_build_object('eligible',eligible) from fitmatch_vnext.products where id=$1$$;
-- Digest is a deterministic isolated fixture; this test does not certify production SHA-256.
create function extensions.digest(text,text) returns bytea language sql as
 $$select decode(md5($1),'hex')$$;
insert into fitmatch_vnext.products values ('${product}','MEN','SINGLE','input','evidence',
 '{"status":"COMPARABLE","group_code":"A","mapping_source":"RETAILER_CATEGORY"}',true);
insert into fitmatch_vnext.product_variants values ('${variant}','${product}');
insert into fitmatch_vnext.garment_types values ('top','top','top_policy',true),('pants','bottom','pants_policy',true);
insert into fitmatch_vnext.comparison_policies values ('top_policy','v1','top-checksum',true),('pants_policy','v1','pants-checksum',true);
`);
await db.exec(original);
await db.exec(`revoke all on function fitmatch_vnext.comparison_target_context(uuid,uuid,text) from public,anon;
grant execute on function fitmatch_vnext.comparison_target_context(uuid,uuid,text) to authenticated,service_role;`);
const permissions = async () => (await db.query("select proacl::text acl,prosecdef,proconfig from pg_proc where oid='fitmatch_vnext.comparison_target_context(uuid,uuid,text)'::regprocedure")).rows;
const initialPermissions = await permissions();
const context = async group => (await db.query('select fitmatch_vnext.comparison_target_context($1::uuid,$2::uuid,$3::text) value',[product,variant,group])).rows[0].value;
const setResolved = async value => db.query('update fitmatch_vnext.products set resolved=$1::jsonb where id=$2',[JSON.stringify(value),product]);
const retailerBefore = await context(null);
await setResolved({status:'COMPARABLE',group_code:'A',mapping_source:'PRODUCT_OVERRIDE'});
const overrideBefore = await context(null);
if (migration) await db.exec(migration);
assert.equal((await context(null)).target_comparison_group.source,'PRODUCT_OVERRIDE','override must retain actual mapping provenance');
if (migration) assert.notEqual((await context(null)).target_comparison_group.authority_fingerprint,overrideBefore.target_comparison_group.authority_fingerprint,'old override fingerprint is stale');
await setResolved({status:'COMPARABLE',group_code:'A',mapping_source:'RETAILER_CATEGORY'});
assert.deepEqual(await context(null),retailerBefore,'mapped category context must be unchanged');
await assert.rejects(()=>context('C'),/allowed only when retailer mapping is missing/);
await setResolved({status:'REVIEW',group_code:null,mapping_source:'UNMAPPED'});
assert.equal((await context(null)).status,'COMPARISON_GROUP_REQUIRED');
const session = await context('C');
assert.equal(session.target_comparison_group.source,'SESSION_USER_SELECTED');
assert.equal(session.target_comparison_group.group_code,'C');
assert.equal(session.effective_classification.requested_comparison_group_code,'C');
assert.notEqual((await context('A')).target_comparison_group.authority_fingerprint,session.target_comparison_group.authority_fingerprint);
for (const source of [null,'UNKNOWN','SESSION_USER_SELECTED','']) {
 await setResolved({status:'COMPARABLE',group_code:'A',mapping_source:source});
 await assert.rejects(()=>context(null),/Invalid comparison group mapping source/);
}
await setResolved({status:'EXCLUDED',group_code:null,mapping_source:'UNMAPPED'});
await assert.rejects(()=>context('C'),/not applicable/);
await setResolved({status:'COMPARABLE',group_code:'A',mapping_source:'RETAILER_CATEGORY'});
await db.exec('update fitmatch_vnext.products set eligible=false');
await assert.rejects(()=>context(null),/structure is not comparable/);
await db.exec('update fitmatch_vnext.products set eligible=true');
await assert.rejects(()=>db.query('select fitmatch_vnext.comparison_target_context($1::uuid,$2::uuid,null)',[product,'00000000-0000-0000-0000-000000000099']),/hierarchy mismatch/);
await db.exec("update fitmatch_vnext.comparison_policies set is_active=false");
await assert.rejects(()=>context(null),/Active comparison policy is missing/);
assert.deepEqual(await permissions(),initialPermissions,'signature/security/search_path/ACL must remain unchanged');
await db.exec("update fitmatch_vnext.comparison_policies set is_active=true");
const rollback = await readFile(new URL('sql/20261005_comparison_group_provenance_Rollback.sql', root),'utf8');
await db.exec(rollback);
await setResolved({status:'COMPARABLE',group_code:'A',mapping_source:'PRODUCT_OVERRIDE'});
assert.equal((await context(null)).target_comparison_group.source,'RETAILER_CATEGORY','rollback restores the actual old behavior');
assert.deepEqual(await permissions(),initialPermissions);
await db.close();
console.log('PASS: real context SQL provenance, unmapped/session, stale fingerprint, safety rejects, unchanged mapped response/ACL and rollback. Isolated dependency fixtures; no authenticated E2E.');

