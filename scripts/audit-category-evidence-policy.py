#!/usr/bin/env python3
import argparse, json, re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
R = ROOT / "Docs/Research"
OUT = R / "CategoryEvidencePolicyAudit-20260813"

FILES = [
    R / "NewClothingCorpus-1280-FifthEighth-20260806/swift_production_classification_results_cumulative_2560.json",
    R / "NewClothingCorpus-2000-20260810/classification_inputs.json",
    R / "NewClothingCorpus-Fresh-20260810/classification_results.json",
]
SUPPLEMENT = R / "NewClothingCorpus-2000-20260810-supplement/classification_inputs.json"
MAPPINGS = R / "CanonicalTaxonomyBundle-20260803/FitMatchSourceCategoryMappings.json"

GROUPS = {
    "underwear": ("속옷", "언더웨어", "이너웨어", "innerwear", "underwear", "브라", "팬티", "브리프", "트렁크"),
    "homewear": ("홈웨어", "라운지", "라운지웨어", "파자마", "잠옷", "homewear", "loungewear", "pajama"),
    "dresses": ("원피스", "드레스", "dress"),
    "skirts": ("스커트", "치마", "skirt", "skort", "스코트"),
    "leggings": ("레깅스", "타이즈", "leggings", "tights"),
    "bottoms": ("하의", "바지", "팬츠", "슬랙스", "쇼츠", "데님 팬츠", "점프 슈트", "점프수트", "오버올", "pants", "trousers", "bottoms", "jeans", "shorts", "jumpsuit", "overall"),
    "outerwear": ("아우터", "재킷", "자켓", "코트", "점퍼", "패딩", "파카", "블루종", "바람막이", "카디건", "가디건", "베스트", "조끼", "무스탕", "outerwear", "jacket", "coat", "parka", "cardigan", "vest", "mouton"),
    "tops": ("상의", "티셔츠", "셔츠", "블라우스", "스웨트셔츠", "후드", "니트", "스웨터", "tops", "t-shirt", "shirt", "blouse", "sweatshirt", "hoodie", "knit", "sweater"),
}
UMBRELLA = ("원피스/스커트", "원피스 & 스커트", "티셔츠 & 스웨트셔츠", "셔츠 & 블라우스", "니트 & 가디건", "속옷/홈웨어", "의류", "clothing", "sportswear")

def load(path):
    return json.loads(path.read_text(encoding="utf-8"))

def core_id(source, value):
    value = str(value).strip()
    if source == "uniqlo":
        value = re.sub(r"^E", "", value, flags=re.I)
        value = re.sub(r"-\d{3}(?:-\d{2})?$", "", value)
    return value

def segments(path):
    return [x.strip() for x in re.split(r"\s*>\s*|\s*/\s*", path or "") if x.strip()]

def matches(segment):
    low = segment.lower()
    return {g for g, terms in GROUPS.items() if any(t.lower() in low for t in terms)}

def garment_matches(segment):
    low = segment.lower()
    found = matches(segment)
    # A zip hoodie is an outer layer in FitMatch. The old heuristic saw only
    # the bare "hood" token and produced false top-vs-outerwear reversals.
    if any(token in low for token in (
        "후드 집업", "후드집업", "집업 후드", "집업후드",
        "zip hoodie", "zip-up hoodie", "hoodie zip-up", "full zip hoodie",
    )):
        # A mixed provider bucket such as "스웨트셔츠 & 후드집업" must remain
        # mixed so a deeper leaf/product can decide. A bare zip hoodie is outer.
        if not any(token in low for token in ("스웨트", "스웻", "sweatshirt")):
            found.discard("tops")
        found.add("outerwear")
    return found

def path_decision(path):
    segs = segments(path)
    evidence=[]
    for i, seg in enumerate(segs):
        found=garment_matches(seg)
        if found:
            evidence.append((i,seg,found))
    if not evidence:
        return "UNRESOLVED", None, []
    union=set().union(*(x[2] for x in evidence))
    structural=union.intersection({"underwear","homewear"})
    if len(structural)==1:
        # Purpose-level provider nodes (underwear/homewear) own their garment
        # form leaves, e.g. underwear > shorts or loungewear > long pants.
        return "LOCKED", next(iter(structural)), evidence
    # Most specific official garment node wins only when it points to one family.
    for i,seg,found in reversed(evidence):
        if len(found)==1:
            return "LOCKED", next(iter(found)), evidence
    if len(union)==1:
        return "LOCKED", next(iter(union)), evidence
    return "CONFLICT", None, evidence

def name_candidates(name):
    low=(name or "").lower()
    # Compound garment expressions must be resolved before bare tokens.
    if any(x in low for x in ("아노락 팬츠","아노락팬츠","드레스 팬츠","드레스팬츠")): return {"bottoms"}
    if any(x in low for x in ("스웨트셔츠","스웨트 셔츠","스웻셔츠","sweatshirt")): return {"tops"}
    if any(x in low for x in ("셔츠 재킷","셔츠 자켓","shirt jacket")): return {"outerwear"}
    return garment_matches(low)

def normalized_records(records, origin):
    rows=[]
    for row in records:
        source=str(row.get("source","")).lower()
        rows.append({
            "source":source,
            "product_id":core_id(source,row.get("product_id",row.get("productID",""))),
            "product_name":str(row.get("product_name",row.get("productName",""))),
            "source_path":str(row.get("effectiveSourcePath",row.get("source_path",row.get("sourcePath",row.get("original_category_path",""))))),
            "current_category":row.get("effectiveCategoryCode",row.get("category_code",row.get("finalCategoryCode"))),
            "current_detail":row.get("effectiveDetailCode",row.get("detail_code",row.get("finalDetailCode"))),
            "external_category_id":str(row.get("discovery_category_code",row.get("external_category_id",row.get("externalCategoryID","")))),
            "origin":origin,
        })
    return rows

def normalized_rows(paths):
    rows=[]
    for path in paths:
        rows += normalized_records(load(path), path.parent.name)
    return rows

def effective_results(primary_path, live_path):
    records=load(primary_path)
    if live_path is None:
        return records, {"overlay_count":0,"succeeded_count":0,"failed_count":0}
    live=load(live_path)
    by_key={(str(row.get("source","")).lower(),str(row.get("productID",""))):row for row in live}
    merged=[]
    for row in records:
        item=dict(row)
        overlay=by_key.get((str(row.get("source","")).lower(),str(row.get("productID",""))))
        if overlay:
            item["effectiveSourcePath"]=overlay.get("liveSourceCategoryPath") or row.get("sourcePath")
            item["effectiveCategoryCode"]=overlay.get("liveFinalCategoryCode")
            item["effectiveDetailCode"]=overlay.get("liveFinalDetailCode")
            item["effectiveUserConfirmationRequired"]=bool(overlay.get("liveUserConfirmationRequired"))
            item["liveParsingSucceeded"]=bool(overlay.get("liveParsingSucceeded"))
            item["liveRegistrationAvailable"]=bool(overlay.get("liveRegistrationAvailable"))
        else:
            item["effectiveSourcePath"]=row.get("sourcePath")
            item["effectiveCategoryCode"]=row.get("finalCategoryCode")
            item["effectiveDetailCode"]=row.get("finalDetailCode")
            item["effectiveUserConfirmationRequired"]=bool(row.get("userConfirmationRequired"))
        merged.append(item)
    return merged, {
        "overlay_count":len(live),
        "succeeded_count":sum(bool(row.get("liveParsingSucceeded")) for row in live),
        "failed_count":sum(not bool(row.get("liveParsingSucceeded")) for row in live),
    }

def audit(rows):
    by_key=defaultdict(list)
    for r in rows: by_key[(r["source"],r["product_id"])].append(r)
    unique=[]; path_conflicts=[]
    for key, variants in by_key.items():
        variants=sorted(variants,key=lambda x:(bool(x["current_category"]),len(x["source_path"])),reverse=True)
        chosen=variants[0]
        unique.append(chosen)
        distinct={(v["source_path"],v["product_name"]) for v in variants}
        if len(distinct)>1: path_conflicts.append((key,variants))
    states=Counter(); locked=Counter(); current_compare=Counter(); name_conflicts=[]; unresolved=[]; conflicts=[]; current_mismatches=[]
    for r in unique:
        state, group, evidence=path_decision(r["source_path"])
        states[state]+=1
        if group: locked[group]+=1
        name=name_candidates(r["product_name"])
        if state=="LOCKED" and name and group not in name:
            name_conflicts.append({**r,"official_group":group,"name_groups":sorted(name)})
        if state=="UNRESOLVED": unresolved.append(r)
        if state=="CONFLICT": conflicts.append(r)
        if r["current_category"]:
            current_compare[(state,group,r["current_category"])]+=1
            if state=="LOCKED" and group != r["current_category"]:
                current_mismatches.append({**r,"official_group":group})
    return {
        "input_rows":len(rows),"unique_products":len(unique),"duplicate_rows":len(rows)-len(unique),
        "identity_with_multiple_inputs":len(path_conflicts),"states":states,"locked_groups":locked,
        "name_conflicts":name_conflicts,"unresolved":unresolved,"path_conflicts":conflicts,
        "current_compare":current_compare,"current_mismatches":current_mismatches,
    }

def canonical_mapping_audit(rows):
    records=load(MAPPINGS)["records"]
    lookup=defaultdict(list)
    id_lookup=defaultdict(list)
    for rec in records:
        lookup[(rec["source"],rec["normalizedPath"])].append(rec)
        if rec.get("externalCategoryID"): id_lookup[(rec["source"],str(rec["externalCategoryID"]))].append(rec)
    def variants(source,path):
        out=[path]
        if source=="musinsa":
            out += [re.sub(r"^(Clothing|Sportswear)\s*>\s*", "", path, flags=re.I)]
        return list(dict.fromkeys(out))
    counts=Counter(); outcomes=Counter(); mapped_groups=Counter(); unmatched=[]; ambiguous=[]; current_mismatches=[]
    for r in rows:
        candidates=list(id_lookup.get((r["source"],r.get("external_category_id","")),[]))
        for path in variants(r["source"],r["source_path"]): candidates += lookup.get((r["source"],path),[])
        candidates=list({x["sourceIdentity"]:x for x in candidates}.values())
        if not candidates:
            counts["unmatched"]+=1; unmatched.append(r); continue
        signatures={(x.get("decisionStatus"),(x.get("appMapping") or {}).get("categoryCode"),(x.get("appMapping") or {}).get("detailCode")) for x in candidates}
        if len(signatures)>1:
            counts["ambiguous"]+=1; ambiguous.append({**r,"mapping_signatures":sorted(map(str,signatures))}); continue
        status,category,detail=next(iter(signatures)); counts["matched"]+=1; outcomes[status]+=1
        if category: mapped_groups[category]+=1
        if r.get("current_category") and category and r["current_category"] != category:
            current_mismatches.append({**r,"mapping_status":status,"mapped_category":category,"mapped_detail":detail})
    return {"counts":counts,"decision_status":outcomes,"mapped_groups":mapped_groups,"unmatched":unmatched,"ambiguous":ambiguous,"current_mismatches":current_mismatches}

def pct(n,d): return round(100*n/d,2) if d else 0

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--primary", type=Path)
    parser.add_argument("--live", type=Path)
    parser.add_argument("--output", type=Path)
    args=parser.parse_args()
    out=args.output or OUT
    effective=None; live_stats=None
    if args.primary:
        effective,live_stats=effective_results(args.primary,args.live)
        primary_rows=normalized_records(effective,args.primary.parent.name)
        supplement_rows=[]
    else:
        primary_rows=normalized_rows(FILES)
        supplement_rows=normalized_rows([SUPPLEMENT])
    primary=audit(primary_rows); supplement=audit(supplement_rows); mapping=canonical_mapping_audit(primary_rows)
    out.mkdir(parents=True,exist_ok=True)
    if effective is not None:
        (out/"effective-results.json").write_text(json.dumps(effective,ensure_ascii=False,indent=2),encoding="utf-8")
    examples={
        "official_path_vs_name_conflicts":primary["name_conflicts"][:200],
        "official_path_unresolved":primary["unresolved"][:200],
        "official_path_internal_conflicts":primary["path_conflicts"][:200],
        "official_path_vs_current_classifier":primary["current_mismatches"][:300],
        "canonical_mapping_unmatched":mapping["unmatched"][:300],
        "canonical_mapping_ambiguous":mapping["ambiguous"][:300],
        "canonical_mapping_vs_current_classifier":mapping["current_mismatches"][:500],
    }
    (out/"examples.json").write_text(json.dumps(examples,ensure_ascii=False,indent=2),encoding="utf-8")
    summary={k:(dict(v) if isinstance(v,Counter) else v) for k,v in primary.items() if k not in ("name_conflicts","unresolved","path_conflicts","current_compare","current_mismatches")}
    summary["name_conflict_count"]=len(primary["name_conflicts"])
    summary["unresolved_count"]=len(primary["unresolved"])
    summary["path_conflict_count"]=len(primary["path_conflicts"])
    summary["current_classifier_mismatch_count"]=len(primary["current_mismatches"])
    summary["canonical_mapping"]={
        "counts":dict(mapping["counts"]),"decision_status":dict(mapping["decision_status"]),
        "mapped_groups":dict(mapping["mapped_groups"]),
        "current_classifier_mismatch_count":len(mapping["current_mismatches"]),
    }
    summary["supplement"]={k:(dict(v) if isinstance(v,Counter) else v) for k,v in supplement.items() if k not in ("name_conflicts","unresolved","path_conflicts","current_compare","current_mismatches")}
    summary["supplement"].update(name_conflict_count=len(supplement["name_conflicts"]),unresolved_count=len(supplement["unresolved"]),path_conflict_count=len(supplement["path_conflicts"]))
    if effective is not None:
        confirmation_count=sum(bool(row.get("effectiveUserConfirmationRequired")) for row in effective)
        dangerous_count=sum(
            not bool(row.get("effectiveUserConfirmationRequired"))
            and (not row.get("effectiveCategoryCode") or not row.get("effectiveDetailCode")
                 or row.get("effectiveCategoryCode")=="other" or row.get("effectiveDetailCode")=="other")
            for row in effective
        )
        summary["production_effective"]={
            **live_stats,
            "user_confirmation_required_count":confirmation_count,
            "auto_confirmation_count":len(effective)-confirmation_count,
            "dangerous_placeholder_auto_confirmation_count":dangerous_count,
        }
    (out/"summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
    n=primary["unique_products"]; locked=primary["states"]["LOCKED"]
    lines=["# FitMatch category evidence policy audit","",f"- Primary raw rows: {primary['input_rows']:,}",f"- Unique source products: {n:,}",f"- Duplicate rows removed: {primary['duplicate_rows']:,}",f"- Heuristic official-path lock candidates: {locked:,} ({pct(locked,n)}%)",f"- Heuristic official-path conflict: {primary['states']['CONFLICT']:,} ({pct(primary['states']['CONFLICT'],n)}%)",f"- Heuristic official-path unresolved: {primary['states']['UNRESOLVED']:,} ({pct(primary['states']['UNRESOLVED'],n)}%)",f"- Candidate locked path vs product-name family conflict: {len(primary['name_conflicts']):,} ({pct(len(primary['name_conflicts']),n)}%)","","These heuristic counts are coverage estimates, not verified accuracy. Exact provider category IDs and the adjudicated canonical decision bundle are stronger evidence.","","## Heuristic lock-candidate distribution",""]
    lines += [f"- {k}: {v:,}" for k,v in primary["locked_groups"].most_common()]
    cm=summary["canonical_mapping"]
    lines += ["","## Existing canonical decision bundle cross-check","",f"- Matched by official ID/path: {cm['counts'].get('matched',0):,} ({pct(cm['counts'].get('matched',0),n)}%)",f"- Unmatched: {cm['counts'].get('unmatched',0):,}",f"- Confirmed decisions: {cm['decision_status'].get('confirmed',0):,}",f"- Review-required decisions: {cm['decision_status'].get('review_required',0):,}",f"- Rejected decisions: {cm['decision_status'].get('rejected',0):,}",f"- Existing runtime classification differs from bundle mapping: {cm['current_classifier_mismatch_count']:,}","","The canonical decision bundle is evidence, not ground truth. Representative mismatches show stale or over-broad decisions such as knit/sweater paths mapped to outerwear/cardigan, while the current product policy keeps knit tops distinct. These require policy adjudication before code changes.","","## Interpretation","","- Official source paths can lock the major category for most observed products, but this audit does not treat current FitMatch classifications as ground truth.","- Product-name disagreement is a conflict signal, not permission to overwrite a locked official major category.","- Unresolved/conflicting official paths require provider-ID mapping, source recheck, or user confirmation before comparison.","- Measurements should validate or narrow candidates; they should not silently flip a locked major category.","- User confirmation should be reserved for unresolved or genuinely contradictory evidence, not every lexical mismatch.","","## Artifacts","","- `summary.json`: complete counts","- `examples.json`: representative rows per exception class"]
    if effective is not None:
        pe=summary["production_effective"]
        lines += ["","## Current production effective result","",f"- Live parser overlays: {pe['overlay_count']:,}",f"- Live parser success/failure: {pe['succeeded_count']:,}/{pe['failed_count']:,}",f"- User confirmation required: {pe['user_confirmation_required_count']:,}",f"- Safe automatic confirmations: {pe['auto_confirmation_count']:,}",f"- Dangerous placeholder automatic confirmations: {pe['dangerous_placeholder_auto_confirmation_count']:,}","","Heuristic mismatches remain review candidates, not verified production bugs."]
    (out/"report.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
    print(json.dumps(summary,ensure_ascii=False,indent=2))

if __name__=="__main__": main()
