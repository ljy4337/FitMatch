#!/usr/bin/env python3
"""Select one source-path-backed candidate per requested reference detail.

Candidates are intentionally selected from official source paths, then the
Simulator test decides whether the production parser actually stores the
requested taxonomy code. A keyword hit is not treated as validation.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "FitMatchTests/ReferenceClosetTargetCandidates.json"
TARGETS = {
    "tops": ["sleeveless", "short_sleeve", "three_quarter_sleeve", "long_sleeve", "shirt", "blouse", "knit_top", "sweatshirt", "hoodie"],
    "bottoms": ["short_pants", "shorts", "cropped_pants", "three_quarter_pants", "nine_tenths_pants", "long_pants", "other_bottoms"],
    "leggings": ["short_leggings", "three_quarter_leggings", "nine_tenths_leggings", "long_leggings", "other_leggings"],
    "outerwear": ["cardigan", "windbreaker", "anorak", "jacket", "blazer", "jumper", "blouson", "fleece", "light_padding", "short_padding", "padding", "long_padding", "coat", "trench_coat", "mouton", "vest", "padded_vest", "other_outerwear"],
    "skirts": ["skirt", "other_skirts"],
    "dresses": ["one_piece", "other_dresses"],
}

# Source-path evidence is stronger than a product name. Patterns are ordered
# from specific to broad; all results still require production parser proof.
PATTERNS = {
    "sleeveless": r"민소매|나시|슬리브리스|sleeveless|tank",
    "short_sleeve": r"반팔|반소매|short.?sleeve",
    "three_quarter_sleeve": r"7부|6부|8부|three.?quarter|3/4",
    "long_sleeve": r"긴팔|긴소매|long.?sleeve",
    "shirt": r"셔츠|남방",
    "blouse": r"블라우스",
    "knit_top": r"니트|스웨터",
    "sweatshirt": r"맨투맨|스웨트",
    "hoodie": r"후드",
    "short_pants": r"숏.?팬츠|쇼트.?팬츠",
    "shorts": r"반바지|쇼츠|shorts",
    "cropped_pants": r"크롭|카프리|cropped",
    "three_quarter_pants": r"7부|6부|8부|three.?quarter|3/4",
    "nine_tenths_pants": r"9부|ankle|nine.?tenths",
    "long_pants": r"긴바지|슬랙스|데님|청바지|트레이닝|조거|팬츠|바지",
    "other_bottoms": r"기타.?바지|점프.?수트|오버올",
    "short_leggings": r"숏.?레깅스|쇼트.?레깅스|바이커|4\.5부|5부",
    "three_quarter_leggings": r"7부.?레깅스|카프리.?레깅스|6부.?레깅스|8부.?레깅스",
    "nine_tenths_leggings": r"9부.?레깅스|ankle",
    "long_leggings": r"롱.?레깅스|레깅스",
    "other_leggings": r"기타.?레깅스",
    "cardigan": r"가디건|카디건",
    "windbreaker": r"바람막이|윈드브레이커|나일론/코치",
    "anorak": r"아노락",
    "jacket": r"재킷|자켓|라이더|사파리|헌팅",
    "blazer": r"블레이저|테일러드",
    "jumper": r"점퍼|스타디움",
    "blouson": r"블루종|ma-1|항공",
    "fleece": r"플리스|후리스|뽀글이",
    "light_padding": r"경량.?패딩|라이트.?패딩",
    "short_padding": r"숏.?패딩|숏.?다운",
    # Do not let a shirt's `버튼다운` collar count as a down jacket.
    "padding": r"패딩|(?:^|[\s(])다운(?:[\s)]|$)",
    "long_padding": r"롱.?패딩|롱.?다운",
    "coat": r"코트",
    "trench_coat": r"트렌치",
    "mouton": r"무스탕|mustang|mouton",
    "vest": r"베스트|조끼",
    "padded_vest": r"패딩.?베스트|패딩.?조끼",
    "other_outerwear": r"기타.?아우터|기타.?점퍼|기타.?재킷",
    "skirt": r"스커트|치마",
    "other_skirts": r"기타.?스커트|기타.?치마",
    "one_piece": r"원피스|드레스",
    "other_dresses": r"기타.?원피스|기타.?드레스",
}


def load_inputs() -> list[dict]:
    files = [
        ROOT / "Docs/Research/NewClothingCorpus-2000-20260810/classification_inputs.json",
        ROOT / "Docs/Research/NewClothingCorpus-2000-20260810-supplement/classification_inputs.json",
    ]
    files += list((ROOT / "Docs/Research").glob("NewClothingCorpus-*/production_classification_inputs.json"))
    seen, rows = set(), []
    for path in files:
        if not path.exists():
            continue
        for row in json.loads(path.read_text(encoding="utf-8")):
            key = (row["source"], str(row["product_id"]))
            if key not in seen:
                seen.add(key)
                rows.append(row)
    return rows


def path_has_explicit_detail(target: str, source_path: str) -> bool:
    """Only accept a source-path match when a path *segment* denotes it.

    Uniqlo's parent labels such as `티셔츠 (반팔 & 긴팔)` and
    `원피스 & 스커트` must not make one product a candidate for both details.
    """
    segments = [segment.strip() for segment in re.split(r">|/", source_path) if segment.strip()]
    pattern = PATTERNS[target]
    return any(re.fullmatch(rf".*(?:{pattern}).*", segment, re.I) for segment in segments)


def score(target: str, source_path: str, product_name: str) -> int:
    # The product title is the primary evidence. A source path is accepted only
    # where an individual path segment explicitly contains the target, never
    # merely because a broad parent group lists several garment types.
    if not re.search(PATTERNS[target], product_name, re.I) and not path_has_explicit_detail(target, source_path):
        return -1
    value = 1
    # Prevent broad fallback details from stealing candidates belonging to a
    # more specific code.
    text = f"{source_path} {product_name}"
    if target == "shirt" and re.search(r"블라우스", text, re.I): return -1
    if target == "padding" and re.search(r"경량|숏|롱|베스트", text, re.I): return -1
    if target == "jacket" and re.search(r"블레이저|트렌치|플리스|블루종", text, re.I): return -1
    if target == "vest" and re.search(r"패딩", text, re.I): return -1
    if target == "long_leggings" and re.search(r"숏|쇼트|7부|6부|8부|9부|바이커|카프리", text, re.I): return -1
    return value


def candidate_quality(category: str, detail: str, row: dict) -> int:
    path = row.get("source_path", "").lower()
    name = row.get("product_name", "").lower()
    text = f"{path} {name}"
    value = 0
    # Adult / unisex reference garments are useful for the intended first pass.
    # Keep children and innerwear in the corpus, but do not select them as a
    # surrogate for a missing adult reference category.
    if not re.search(r"baby|kids|girls|boys|유아|키즈|아동|신생아|이너웨어|속옷|언더웨어|브라|팬티", text, re.I):
        value += 20
    if "[set]" not in name and "셋업" not in name and "세트" not in name:
        value += 5
    if category == "tops" and re.search(r"상의|티셔츠|셔츠|블라우스|니트|스웨트|후드", path, re.I):
        value += 10
    if category == "bottoms" and re.search(r"하의|바지|팬츠", path, re.I):
        value += 10
    if category == "outerwear" and re.search(r"아우터|재킷|점퍼|코트|파카", path, re.I):
        value += 10
    if category == "leggings" and "레깅스" in path:
        value += 10
    if category == "skirts" and re.search(r"스커트|치마", path, re.I):
        value += 10
    if category == "dresses" and re.search(r"원피스|드레스", path, re.I):
        value += 10
    if re.search(PATTERNS[detail], path, re.I):
        value += 5
    return value


def choose(rows: list[dict], source: str, category: str, detail: str, limit: int) -> list[dict]:
    candidates = []
    for row in rows:
        if row["source"] != source:
            continue
        source_path = row.get("source_path", "")
        text = f"{source_path} {row.get('product_name', '')}"
        path = source_path.lower()
        # A reference garment must represent an adult/unisex single garment.
        # Do not let a child, innerwear, or set listing pretend to fill a core
        # taxonomy gap just because its title contains the same length word.
        if re.search(r"baby|kids|girls|boys|유아|키즈|아동|신생아|이너웨어|속옷|언더웨어|브라|팬티", text, re.I):
            continue
        if re.search(r"\[set\]|셋업|세트", row.get("product_name", ""), re.I):
            continue
        # A short/three-quarter sleeve keyword inside innerwear (for example
        # HEATTECH 8부) is not an upper-garment reference candidate.
        if category == "tops" and re.search(r"이너웨어|속옷|언더웨어|브라|팬티", source_path, re.I):
            continue
        if category == "tops" and re.search(r"원피스|드레스|스커트|치마|레깅스|바지|팬츠", source_path, re.I):
            continue
        if category == "outerwear" and ("하의" in path or "바지" in path or "팬츠" in path):
            continue
        if category == "bottoms" and not re.search(r"하의|바지|팬츠|레깅스|스커트|원피스", source_path, re.I):
            continue
        if category == "bottoms" and re.search(r"레깅스|스커트|치마|원피스|드레스", source_path, re.I):
            continue
        if category == "leggings" and "레깅스" not in text:
            continue
        if category == "skirts" and not re.search(r"스커트|치마", text, re.I):
            continue
        if category == "dresses" and not re.search(r"원피스|드레스", text, re.I):
            continue
        if score(detail, source_path, row.get("product_name", "")) >= 0:
            candidates.append(row)
    result = []
    seen = set()
    for rank, row in enumerate(sorted(
        candidates,
        key=lambda item: (-candidate_quality(category, detail, item), str(item["product_id"]))
    ), start=1):
        product_id = str(row["product_id"])
        if product_id in seen:
            continue
        seen.add(product_id)
        result.append({
            "source": source,
            "product_id": product_id,
            "product_name": row["product_name"],
            "source_path": row.get("source_path", ""),
            "target_category": category,
            "target_detail": detail,
            "selection_rank": rank,
            "url": row.get("product_url") or (
                f"https://www.musinsa.com/products/{product_id}" if source == "musinsa"
                else f"https://www.uniqlo.com/kr/ko/products/{product_id}-000/00"
            ),
        })
        if len(result) == limit:
            break
    return result


per_target = int(sys.argv[1]) if len(sys.argv) > 1 else 1
source_filter = sys.argv[2] if len(sys.argv) > 2 else None
output_path = Path(sys.argv[3]) if len(sys.argv) > 3 else OUT
rows = load_inputs()
candidates, gaps = [], []
for source in ("uniqlo", "musinsa"):
    if source_filter and source != source_filter:
        continue
    for category, details in TARGETS.items():
        for detail in details:
            selected = choose(rows, source, category, detail, per_target)
            if selected:
                candidates.extend(selected)
            else:
                gaps.append({"source": source, "target_category": category, "target_detail": detail})

output_path.write_text(json.dumps({
    "selection_policy": "official source-path candidate; production parser and actual size table must still validate",
    "target_count_per_source": 43,
    "candidates_per_target": per_target,
    "candidates": candidates,
    "gaps": gaps,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({
    "candidates": len(candidates),
    "uniqlo": sum(c["source"] == "uniqlo" for c in candidates),
    "musinsa": sum(c["source"] == "musinsa" for c in candidates),
    "gaps": len(gaps),
}, ensure_ascii=False))
