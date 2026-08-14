#!/usr/bin/env python3
"""Build the first-pass reference closet: one product for each of 43 details.

Only locally stored products with an official measurement table are eligible.
This script is setup-only; comparison pairs are intentionally not generated.
"""
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806"
OUTPUT = ROOT / "FitMatchTests/ReferenceClosetCandidates.json"

MUSINSA_CORPUS = ROOT / "Docs/Research/NewClothingCorpus-1037-MusinsaFifthEighth-20260806"
UNIQLO_CORPORA = (
    ROOT / "Docs/Research/NewClothingCorpus-300-UniqloFifth-20260806",
    ROOT / "Docs/Research/NewClothingCorpus-320-20260806",
    ROOT / "Docs/Research/NewClothingCorpus-320-Third-20260806",
    ROOT / "Docs/Research/NewClothingCorpus-320-Retest-20260806",
)

# User-approved first pass: tops 9 + bottoms 7 + leggings 5 + outerwear 18
# + skirts 2 + dresses 2. `other_tops` is deliberately not in this 43 set.
TARGET_DETAILS = {
    "sleeveless", "short_sleeve", "three_quarter_sleeve", "long_sleeve",
    "shirt", "blouse", "knit_top", "sweatshirt", "hoodie",
    "short_pants", "shorts", "cropped_pants", "three_quarter_pants",
    "nine_tenths_pants", "long_pants", "other_bottoms",
    "short_leggings", "three_quarter_leggings", "nine_tenths_leggings",
    "long_leggings", "other_leggings",
    "cardigan", "windbreaker", "anorak", "jacket", "blazer", "jumper",
    "blouson", "fleece", "light_padding", "short_padding", "padding",
    "long_padding", "coat", "trench_coat", "mouton", "vest", "padded_vest",
    "other_outerwear", "skirt", "other_skirts", "one_piece", "other_dresses",
}


def candidates(source: str, official_ids: set[str], classifications: list[dict]) -> list[dict]:
    by_detail: dict[str, list[dict]] = {}
    for row in classifications:
        if row["source"] != source or str(row["product_id"]) not in official_ids:
            continue
        detail = row["detail_code"]
        if detail in TARGET_DETAILS:
            by_detail.setdefault(detail, []).append(row)

    selected = []
    for detail, group in sorted(by_detail.items()):
        row = min(group, key=lambda value: str(value["product_id"]))
        product_id = str(row["product_id"])
        selected.append({
            "source": source,
            "product_id": product_id,
            "product_name": row["product_name"],
            "target_category": row["category_code"],
            "target_detail": detail,
            "url": (
                f"https://www.musinsa.com/products/{product_id}"
                if source == "musinsa"
                else f"https://www.uniqlo.com/kr/ko/products/{product_id}-000/00"
            ),
        })
    return selected


classifications = json.loads(
    (RESEARCH / "swift_production_classification_results_cumulative_2560.json").read_text(encoding="utf-8")
)


def musinsa_ids_with_official_measurements() -> set[str]:
    ids = set()
    for path in (MUSINSA_CORPUS / "raw/musinsa/actual_size").glob("*.json"):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if (payload.get("data") or {}).get("sizes"):
            ids.add(path.stem)
    return ids


def uniqlo_ids_with_official_product_pages() -> set[str]:
    ids = set()
    for corpus in UNIQLO_CORPORA:
        for path in (corpus / "raw/uniqlo/products").glob("*.html"):
            ids.add(path.stem.removesuffix("-000"))
    return ids


sources = (
    ("musinsa", musinsa_ids_with_official_measurements()),
    ("uniqlo", uniqlo_ids_with_official_product_pages()),
)
all_candidates = []
for source, official_ids in sources:
    all_candidates.extend(candidates(source, official_ids, classifications))

covered_details = {candidate["target_detail"] for candidate in all_candidates}
OUTPUT.write_text(json.dumps({
    "generated_from": [
        str((RESEARCH / "swift_production_classification_results_cumulative_2560.json").relative_to(ROOT)),
        str(MUSINSA_CORPUS.relative_to(ROOT) / "raw/musinsa/actual_size"),
        *[str(corpus.relative_to(ROOT) / "raw/uniqlo/products") for corpus in UNIQLO_CORPORA],
    ],
    "selection_policy": "one deterministic product per user-approved 43 detail codes, intersected with local official-measurement products; setup only, no comparisons",
    "target_detail_count": len(TARGET_DETAILS),
    "uncovered_target_details": sorted(TARGET_DETAILS - covered_details),
    "candidates": all_candidates,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

counts = {source: sum(item["source"] == source for item in all_candidates) for source, _ in sources}
print(json.dumps({
    "candidates": len(all_candidates), **counts,
    "covered_details": len(covered_details),
    "uncovered": len(TARGET_DETAILS - covered_details),
}, ensure_ascii=False))
