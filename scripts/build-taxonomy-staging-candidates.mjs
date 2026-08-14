import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const dir = join(root, "Docs/Research/OfficialTaxonomySnapshot-20260803");
const musinsa = JSON.parse(await readFile(join(dir, "musinsa-official-taxonomy-snapshot.json"))).nodes;
const uniqlo = JSON.parse(await readFile(join(dir, "uniqlo-official-taxonomy-snapshot.json"))).nodes;

function seed(path) {
  return readFile(path, "utf8").then(text => {
    const marker = "$fitmatch_source_categories$";
    const start = text.indexOf(marker) + marker.length;
    return JSON.parse(text.slice(start, text.indexOf(marker, start)));
  });
}
const db = [...await seed(join(root, "fitmatch_supabase_seed_musinsa_categories.sql")), ...await seed(join(root, "fitmatch_supabase_seed_uniqlo_categories.sql"))]
  .map((row, index) => ({ ...row, db_identity: `${row.source_code}:${row.audience ?? "NULL"}:${row.external_category_id}:${index}` }));
const snapshot = [...musinsa, ...uniqlo].map((row, index) => ({ ...row, snapshot_identity: `${row.source}:${row.target}:${row.external_category_id}:${index}` }));
const norm = value => value.normalize("NFC").trim().replace(/\s+/g, " ").toLocaleLowerCase("en-US");
const group = (rows, key) => Map.groupBy(rows, key);
const dbIdTarget = group(db, r => `${r.source_code}|${r.external_category_id}|${r.audience ?? "UNKNOWN"}`);
const dbId = group(db, r => `${r.source_code}|${r.external_category_id}`);
const dbPathTarget = group(db, r => `${r.source_code}|${norm(r.original_path)}|${r.audience ?? "UNKNOWN"}`);
const dbPath = group(db, r => `${r.source_code}|${norm(r.original_path)}`);
const edges = [];
for (const node of snapshot) {
  const stages = [
    ["id_target", dbIdTarget.get(`${node.source}|${node.external_category_id}|${node.target}`)],
    ["id", dbId.get(`${node.source}|${node.external_category_id}`)],
    ["path_target", dbPathTarget.get(`${node.source}|${norm(node.normalized_full_path)}|${node.target}`)],
    ["path", dbPath.get(`${node.source}|${norm(node.normalized_full_path)}`)]
  ];
  const [method, matches] = stages.find(([, values]) => values?.length) ?? [];
  for (const row of matches ?? []) edges.push({ db_identity: row.db_identity, snapshot_identity: node.snapshot_identity, source: node.source, method, db_external_id: row.external_category_id, db_target: row.audience, db_path: row.original_path, snapshot_id: node.external_category_id, snapshot_target: node.target, snapshot_path: node.raw_full_path });
}

const dbEdges = group(edges, e => e.db_identity);
const snapEdges = group(edges, e => e.snapshot_identity);
const seenD = new Set(), seenS = new Set();
const components = [];
for (const edge of edges) {
  if (seenD.has(edge.db_identity) || seenS.has(edge.snapshot_identity)) continue;
  const ds = new Set(), ss = new Set(), queue = [{ side: "d", id: edge.db_identity }];
  while (queue.length) {
    const { side, id } = queue.shift();
    if (side === "d") {
      if (ds.has(id)) continue; ds.add(id); seenD.add(id);
      for (const e of dbEdges.get(id) ?? []) queue.push({ side: "s", id: e.snapshot_identity });
    } else {
      if (ss.has(id)) continue; ss.add(id); seenS.add(id);
      for (const e of snapEdges.get(id) ?? []) queue.push({ side: "d", id: e.db_identity });
    }
  }
  components.push({ db_count: ds.size, snapshot_count: ss.size, relation: ds.size === 1 && ss.size === 1 ? "1:1" : ds.size === 1 ? "1:N" : ss.size === 1 ? "N:1" : "N:N", db_identities: [...ds], snapshot_identities: [...ss] });
}

const matchedSnapshot = new Set(edges.map(e => e.snapshot_identity));
const matchedDb = new Set(edges.map(e => e.db_identity));
const missing = snapshot.filter(n => !matchedSnapshot.has(n.snapshot_identity));

const obviousNonGarment = /(뷰티|메이크업|스킨케어|향수|식품|푸드|전자|디지털|가전|생활용품|주방|가구|인테리어|도서|책|반려|펫|장비|기구|용품|공|라켓|보드|캠핑|낚시|자전거|시계|주얼리|안경|선글라스|가방|백팩|지갑|모자|신발|슈즈|양말|삭스|액세서리|잡화)/i;
const unsupportedGarment = /(수영복|비치웨어|유니폼|코스튬|보호대|바디수트|커버올|롬퍼|세트|셋업|올인원)/i;
const clearGarment = /(티셔츠|셔츠|블라우스|폴로|니트|스웨터|가디건|카디건|맨투맨|스웨트|후드|탱크탑|민소매|팬츠|바지|데님|진\b|슬랙스|치노|카고|조거|레깅스|스커트|재킷|자켓|블루종|아노락|윈드브레이커|후리스|플리스|패딩|코트|무스탕|원피스|드레스|브라|팬티|브리프|내의|잠옷|파자마)/i;
const mixed = /(기타|그 외|전체|&|\/|상의|하의|아우터|이너웨어|홈웨어|컬렉션|collection|collaboration|genderless|유니섹스)/i;
const highRisk = /(상의|아우터|하의|레깅스|스커트|키즈|baby|kids|바디수트|커버올|세트|셋업|민소매|반팔|긴팔|크롭|7부|9부|쇼트|롱|기타|그 외|&|\/)/i;

function inferGarment(path) {
  const rules = [[/레깅스/i,"leggings"],[/스커트/i,"skirt"],[/원피스|드레스/i,"dress"],[/데님|청바지|진\b/i,"denim_pants"],[/슬랙스|트라우저/i,"slacks_trousers"],[/치노/i,"chino_cotton_pants"],[/카고/i,"cargo_pants"],[/조거|스웨트 팬츠/i,"sweat_jogger_pants"],[/팬츠|바지/i,"casual_pants"],[/후드 집업/i,"zip_hoodie"],[/후드/i,"hoodie"],[/맨투맨|스웨트/i,"sweatshirt"],[/가디건|카디건/i,"cardigan"],[/니트|스웨터/i,"knit_sweater"],[/폴로|피케/i,"polo_shirt"],[/셔츠|블라우스/i,"shirt_blouse"],[/민소매|탱크탑/i,"tank_top"],[/티셔츠/i,"tshirt"],[/블레이저/i,"blazer"],[/블루종/i,"blouson"],[/아노락/i,"anorak"],[/윈드|바람막이/i,"windbreaker"],[/후리스|플리스/i,"fleece_jacket"],[/패딩 베스트|패딩 조끼/i,"puffer_vest"],[/패딩/i,"puffer_jacket"],[/코트/i,"coat"],[/무스탕/i,"mouton"],[/재킷|자켓/i,"jacket"],[/바디수트/i,"bodysuit"],[/커버올|롬퍼/i,"coverall_romper"],[/브라/i,"bra"],[/팬티|브리프/i,"briefs"]];
  return rules.find(([r]) => r.test(path))?.[1] ?? null;
}
function lengths(path) {
  return { sleeve: /민소매|슬리브리스/i.test(path)?"sleeveless":/반팔|반소매/i.test(path)?"short_sleeve":/7부.*소매/i.test(path)?"three_quarter_sleeve":/긴팔|긴소매/i.test(path)?"long_sleeve":"unknown", pants: /반바지|쇼트팬츠|숏 팬츠/i.test(path)?"short_length":/크롭/i.test(path)?"cropped_length":/7부/i.test(path)?"three_quarter_length":/9부|앵클/i.test(path)?"ankle_length":/긴바지|롱팬츠/i.test(path)?"long_length":"unknown", leggings: /레깅스/i.test(path)?(/크롭|7부/i.test(path)?"three_quarter_length":/10부|롱/i.test(path)?"long_length":"unknown"):"not_applicable", skirt: /스커트/i.test(path)?(/미니/i.test(path)?"mini":/미디/i.test(path)?"midi":/롱|맥시/i.test(path)?"maxi":"unknown"):"not_applicable", body: "unknown" };
}
function classify(node) {
  const path = node.raw_full_path;
  let groupCode, reason;
  if (!node.is_leaf) { groupCode="F"; reason="navigation grouping/non-leaf"; }
  else if (/(^| > )(가방|지갑\/가방)( > |$)|브리프\s*케이스|briefcase/i.test(path)) { groupCode="A"; reason="path denotes a bag/briefcase, not underwear"; }
  else if (obviousNonGarment.test(path) && !clearGarment.test(path)) { groupCode="A"; reason="path denotes non-garment merchandise"; }
  else if (unsupportedGarment.test(path)) { groupCode="B"; reason="garment requires FitMatch support review"; }
  else if (clearGarment.test(path) && !mixed.test(node.raw_name)) { groupCode="C"; reason="leaf path has stable garment term"; }
  else if (clearGarment.test(path)) { groupCode="D"; reason="garment path mixes type or length semantics"; }
  else { groupCode="E"; reason="leaf meaning requires product evidence"; }
  const garment = inferGarment(path);
  const priority = ["A","F"].includes(groupCode) ? 4 : (highRisk.test(path) || ["B","D"].includes(groupCode)) ? 1 : groupCode === "E" ? 2 : groupCode === "C" ? 3 : 4;
  const productCount = node.source === "musinsa" ? node.source_evidence.product_count : null;
  const observation = !node.is_leaf ? "navigation_only" : productCount > 0 ? "product_observed" : productCount === 0 ? "no_product_observed" : "activity_unknown";
  const preliminaryStatus = groupCode === "A" ? "rejected" : groupCode === "B" ? "unsupported" : groupCode === "C" && garment ? "confirmed_candidate" : "review_required";
  return { group:groupCode, group_reason:reason, sampling_priority:priority, product_observation_status:observation, observed_product_count:productCount, semantic_garment_type:garment, length_axes:lengths(path), comparison_family:garment, status:preliminaryStatus, confidence:groupCode === "A" ? 0.95 : groupCode === "C" && garment ? 0.85 : 0.5, reason, current_app_support:groupCode === "B" ? "unsupported_or_transform_required" : groupCode === "A" ? "not_applicable" : "unreviewed", manual_review_flag:!["A","C"].includes(groupCode) };
}

const candidates = missing.map(node => ({ source_identity:node.snapshot_identity, snapshot_version:"observed-2026-08-03T02:01:21.580Z", source:node.source, external_category_id:node.external_category_id, parent_external_category_id:node.parent_external_category_id, raw_path:node.raw_full_path, normalized_path:node.normalized_full_path, target:node.target, tree_metadata:{depth:node.depth,is_leaf:node.is_leaf}, activity_status:"activity_unknown", evidence:{source_url:node.source_url,raw_response_hash:node.raw_response_hash,sample_product_ids:node.source_evidence.sample_product_ids??[]}, ...classify(node), sampling_status:"not_sampled", sampled_product_count:0, observed_garment_type_distribution:{}, observed_length_distribution:{}, exception_count:0, exception_rate:null, category_level_confirmed:false, reviewed_at:null }));

const dbLookup=new Map(db.map(d=>[d.db_identity,d]));
const snapLookup=new Map(snapshot.map(s=>[s.snapshot_identity,s]));
const adjudications=[];
for(const edge of edges){
  const d=dbLookup.get(edge.db_identity), s=snapLookup.get(edge.snapshot_identity);
  if(edge.source==="musinsa"&&s.target==="KIDS"&&d.audience==null) adjudications.push({...edge,conflict_type:"target_enrichment",current_official_identity:s.external_category_id,past_identity:d.external_category_id,alias_relationship:false,target_separation_required:true,snapshot_version_change:true,parent_change:false,rename:false,id_reissued:false,manual_review:true,canonical_action:"same source category; preserve NULL audience history and add versioned KIDS audience assignment"});
  if(edge.method.startsWith("id")&&norm(d.original_path)!==norm(s.normalized_full_path)) adjudications.push({...edge,conflict_type:d.parent_external_category_id!==s.parent_external_category_id?"parent_or_path_change":"rename",current_official_identity:s.external_category_id,past_identity:d.external_category_id,alias_relationship:true,target_separation_required:false,snapshot_version_change:true,parent_change:d.parent_external_category_id!==s.parent_external_category_id,rename:true,id_reissued:false,manual_review:true,canonical_action:"keep one source category by stable ID; append path/parent history"});
}
for(const component of components.filter(c=>c.relation!=="1:1")){
  adjudications.push({source:"uniqlo",conflict_type:"coexisting_same_path_multiple_ids",current_official_identity:component.snapshot_identities.join("|"),past_identity:component.db_identities.join("|"),alias_relationship:false,target_separation_required:true,snapshot_version_change:true,parent_change:false,rename:false,id_reissued:false,manual_review:true,canonical_action:"preserve separate source categories; shared path is not identity and no alias is proven"});
}

const summary = {
  db: { physical_rows:db.length, unique_identity:new Set(db.map(d=>d.db_identity)).size, by_source:Object.fromEntries([...group(db,d=>d.source_code)].map(([k,v])=>[k,{physical:v.length,unique_external_id:new Set(v.map(x=>x.external_category_id)).size,unique_id_target:new Set(v.map(x=>`${x.external_category_id}|${x.audience??""}`)).size,unique_path_target:new Set(v.map(x=>`${norm(x.original_path)}|${x.audience??""}`)).size}])) },
  snapshot:{nodes:snapshot.length,unique_identity:new Set(snapshot.map(s=>s.snapshot_identity)).size,by_source:Object.fromEntries([...group(snapshot,s=>s.source)].map(([k,v])=>[k,v.length]))},
  graph:{edges:edges.length,matched_db:matchedDb.size,matched_snapshot:matchedSnapshot.size,unmatched_db:db.length-matchedDb.size,unmatched_snapshot:missing.length,components:components.length,component_types:Object.fromEntries([...group(components,c=>c.relation)].map(([k,v])=>[k,v.length]))},
  candidates:{total:candidates.length,by_source:Object.fromEntries([...group(candidates,c=>c.source)].map(([k,v])=>[k,v.length])),by_group:Object.fromEntries([...group(candidates,c=>`${c.source}:${c.group}`)].map(([k,v])=>[k,v.length])),by_observation:Object.fromEntries([...group(candidates,c=>c.product_observation_status)].map(([k,v])=>[k,v.length])),by_status:Object.fromEntries([...group(candidates,c=>c.status)].map(([k,v])=>[k,v.length]))}
};
const csv = (rows, fields) => [fields.join(","),...rows.map(r=>fields.map(f=>`"${String(typeof r[f]==="object"?JSON.stringify(r[f]):r[f]??"").replaceAll('"','""')}"`).join(","))].join("\n")+"\n";
await writeFile(join(dir,"identity-matching-graph.json"),JSON.stringify({summary,components,edges},null,2)+"\n");
await writeFile(join(dir,"staging-candidates.json"),JSON.stringify({summary:candidates.length,candidates},null,2)+"\n");
await writeFile(join(dir,"staging-candidates.csv"),csv(candidates,["source_identity","source","external_category_id","parent_external_category_id","raw_path","normalized_path","target","tree_metadata","product_observation_status","observed_product_count","group","sampling_priority","sampling_status","sampled_product_count","semantic_garment_type","length_axes","comparison_family","status","confidence","reason","current_app_support","manual_review_flag","evidence"]));
await writeFile(join(dir,"sampling-queue.json"),JSON.stringify(candidates.filter(c=>c.tree_metadata.is_leaf&&c.product_observation_status==="product_observed").sort((a,b)=>a.sampling_priority-b.sampling_priority||a.source_identity.localeCompare(b.source_identity)).slice(0,100),null,2)+"\n");
await writeFile(join(dir,"identity-conflict-adjudications.csv"),csv(adjudications,["source","conflict_type","db_identity","db_external_id","db_target","db_path","snapshot_identity","snapshot_id","snapshot_target","snapshot_path","method","current_official_identity","past_identity","alias_relationship","target_separation_required","snapshot_version_change","parent_change","rename","id_reissued","manual_review","canonical_action"]));
console.log(JSON.stringify(summary,null,2));
