import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const dir = join(root,"Docs/Research/OfficialTaxonomySnapshot-20260803");
const queue = JSON.parse(await readFile(join(dir,"sampling-queue.json")));
const staging = JSON.parse(await readFile(join(dir,"staging-candidates.json")));
const reviewedAt = new Date().toISOString();
const sleep = ms => new Promise(r=>setTimeout(r,ms));

function garment(text) {
  const rules=[[/레깅스/i,"leggings"],[/스커트/i,"skirt"],[/원피스|드레스/i,"dress"],[/데님|청바지|\b진\b/i,"denim_pants"],[/슬랙스|트라우저/i,"slacks_trousers"],[/치노/i,"chino_cotton_pants"],[/카고/i,"cargo_pants"],[/조거|스웨트.?팬츠/i,"sweat_jogger_pants"],[/팬츠|바지/i,"casual_pants"],[/후드.?집업/i,"zip_hoodie"],[/후드/i,"hoodie"],[/맨투맨|스웨트/i,"sweatshirt"],[/가디건|카디건/i,"cardigan"],[/니트|스웨터/i,"knit_sweater"],[/폴로|피케/i,"polo_shirt"],[/셔츠|블라우스/i,"shirt_blouse"],[/민소매|탱크.?탑|슬리브리스/i,"tank_top"],[/티셔츠|티셔츠|\bT\b/i,"tshirt"],[/블레이저/i,"blazer"],[/블루종|MA-1/i,"blouson"],[/아노락/i,"anorak"],[/윈드|바람막이|코치.?재킷/i,"windbreaker"],[/후리스|플리스/i,"fleece_jacket"],[/패딩.?베스트|패딩.?조끼/i,"puffer_vest"],[/패딩/i,"puffer_jacket"],[/코트/i,"coat"],[/무스탕/i,"mouton"],[/재킷|자켓/i,"jacket"],[/바디수트/i,"bodysuit"],[/커버올|롬퍼/i,"coverall_romper"],[/브라/i,"bra"],[/팬티|브리프/i,"briefs"]];
  return rules.find(([r])=>r.test(text))?.[1]??"unknown";
}
function length(text) {
  if (/민소매|슬리브리스/i.test(text)) return "sleeveless";
  if (/반팔|반소매/i.test(text)) return "short_sleeve";
  if (/긴팔|긴소매/i.test(text)) return "long_sleeve";
  if (/반바지|쇼트|숏/i.test(text)) return "short_length";
  if (/크롭/i.test(text)) return "cropped_length";
  if (/7부/i.test(text)) return "three_quarter_length";
  if (/9부|앵클/i.test(text)) return "ankle_length";
  if (/10부|롱/i.test(text)) return "long_length";
  if (/미니/i.test(text)) return "mini";
  if (/미디/i.test(text)) return "midi";
  if (/맥시/i.test(text)) return "maxi";
  return "unknown";
}
async function detail(id) {
  const url=`https://goods-detail.musinsa.com/api2/goods/${id}`;
  try {
    const response=await fetch(url,{headers:{"user-agent":"Mozilla/5.0 FitMatch taxonomy audit"},signal:AbortSignal.timeout(15000)});
    if(!response.ok) return {id,url,error:`HTTP ${response.status}`};
    const json=await response.json(); const data=json.data??{};
    return {id,url,name:data.goodsNm??"",category_path:data.baseCategoryFullPath??"",genders:data.genders??[],garment_type:garment(`${data.goodsNm??""} ${data.baseCategoryFullPath??""}`),length_class:length(`${data.goodsNm??""} ${data.baseCategoryFullPath??""}`)};
  } catch(error) { return {id,url,error:String(error)}; }
}
const selected=queue.filter(c=>c.sampling_priority===1).slice(0,100);
const results=[];
for(let offset=0;offset<selected.length;offset+=5){
  const categories=selected.slice(offset,offset+5);
  const batch=await Promise.all(categories.map(async category=>{
    const ids=(category.evidence.sample_product_ids??[]).slice(0,10);
    const products=[];
    for(let i=0;i<ids.length;i+=10) products.push(...await Promise.all(ids.slice(i,i+10).map(detail)));
    const valid=products.filter(p=>!p.error); const failed=products.length-valid.length;
    const gd=Object.fromEntries([...Map.groupBy(valid,p=>p.garment_type)].map(([k,v])=>[k,v.length]));
    const ld=Object.fromEntries([...Map.groupBy(valid,p=>p.length_class)].map(([k,v])=>[k,v.length]));
    const dominant=Object.entries(gd).sort((a,b)=>b[1]-a[1])[0];
    const exceptions=dominant?valid.length-dominant[1]:0;
    const mixedGarment=Object.keys(gd).filter(k=>k!=="unknown").length>1;
    const mixedLength=Object.keys(ld).filter(k=>k!=="unknown").length>1;
    const confirmed=valid.length>=5&&!mixedGarment&&!mixedLength&&!gd.unknown;
    return {source_identity:category.source_identity,external_category_id:category.external_category_id,raw_path:category.raw_path,sampling_status:failed?"sampled_with_failures":"sampled",requested_product_count:ids.length,sampled_product_count:valid.length,collection_failure_count:failed,observed_garment_type_distribution:gd,observed_length_distribution:ld,exception_count:exceptions,exception_rate:valid.length?exceptions/valid.length:null,category_level_confirmed:confirmed,review_required:!confirmed,confidence:confirmed?0.95:valid.length>=5?0.75:0.4,evidence:products,reviewed_at:reviewedAt};
  }));
  results.push(...batch); await sleep(100);
}
const byIdentity=new Map(results.map(r=>[r.source_identity,r]));
for(const candidate of staging.candidates){
  const sample=byIdentity.get(candidate.source_identity); if(!sample) continue;
  Object.assign(candidate,sample);
  if(!["unsupported","rejected"].includes(candidate.status)) {
    candidate.status=sample.category_level_confirmed?"confirmed_candidate":"review_required";
  }
  candidate.manual_review_flag=candidate.status==="review_required"||candidate.status==="unsupported";
}
const summary={selected_categories:selected.length,sampled_categories:results.length,products_requested:results.reduce((s,r)=>s+r.requested_product_count,0),products_sampled:results.reduce((s,r)=>s+r.sampled_product_count,0),collection_failures:results.reduce((s,r)=>s+r.collection_failure_count,0),category_confirmed_candidates:results.filter(r=>r.category_level_confirmed).length,category_review_required:results.filter(r=>r.review_required).length};
await writeFile(join(dir,"risk-sampling-results.json"),JSON.stringify({summary,results},null,2)+"\n");
await writeFile(join(dir,"staging-candidates-reviewed.json"),JSON.stringify({summary:{...staging.summary,sampling:summary},candidates:staging.candidates},null,2)+"\n");
console.log(JSON.stringify(summary,null,2));
