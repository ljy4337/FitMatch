#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806"
OUTPUT = ROOT / "FitMatchTests/CategoryLiveComparisonInputs.json"


def unique_products(path: Path, source: str) -> list[dict]:
    rows = json.loads(path.read_text())
    products = {}
    for row in rows:
        product_id = str(row["comparison_product_id"])
        category = row.get("comparison_detail_code") or row.get("detail_code")
        products.setdefault(product_id, {
            "source": source,
            "product_id": product_id,
            "product_name": row["comparison_product_name"],
            "expected_detail": category,
            "url": row.get("comparison_url") or (
                f"https://www.musinsa.com/products/{product_id}"
                if source == "musinsa"
                else f"https://www.uniqlo.com/kr/ko/products/{product_id}-000/00"
            ),
        })
    return sorted(products.values(), key=lambda item: item["product_id"])


def select(products: list[dict], source: str) -> tuple[list[dict], list[dict]]:
    groups = {}
    for product in products:
        groups.setdefault(product["expected_detail"], []).append(product)

    selected = []
    gaps = []
    for category, candidates in sorted(groups.items()):
        required = 10 if category == "기타" else 3
        if len(candidates) < required:
            gaps.append({
                "source": source,
                "expected_detail": category,
                "available": len(candidates),
                "required": required,
            })
            continue
        chosen = candidates[:required]
        for product in chosen:
            product["sample_kind"] = "other_focus" if category == "기타" else "category_three"
        selected.extend(chosen)
    return selected, gaps


musinsa = unique_products(
    RESEARCH / "musinsa_actual_measurement_pair_results_real_flow_after_fix.json",
    "musinsa",
)
uniqlo = unique_products(
    RESEARCH / "uniqlo_actual_measurement_pair_results.json",
    "uniqlo",
)
musinsa_selected, musinsa_gaps = select(musinsa, "musinsa")
uniqlo_selected, uniqlo_gaps = select(uniqlo, "uniqlo")

OUTPUT.write_text(json.dumps({
    "generated_from": [
        "musinsa_actual_measurement_pair_results_real_flow_after_fix.json",
        "uniqlo_actual_measurement_pair_results.json",
    ],
    "selection_policy": "3 per measured detail category; 10 for other; deterministic product_id order",
    "products": musinsa_selected + uniqlo_selected,
    "coverage_gaps": musinsa_gaps + uniqlo_gaps,
}, ensure_ascii=False, indent=2) + "\n")

print(json.dumps({
    "products": len(musinsa_selected) + len(uniqlo_selected),
    "musinsa": len(musinsa_selected),
    "uniqlo": len(uniqlo_selected),
    "coverage_gaps": len(musinsa_gaps) + len(uniqlo_gaps),
}, ensure_ascii=False))
