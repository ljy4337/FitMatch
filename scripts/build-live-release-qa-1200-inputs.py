#!/usr/bin/env python3
"""Select a deterministic, category-stratified fresh 600+600 live QA corpus."""

from __future__ import annotations

import hashlib
import json
from collections import defaultdict, deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLASSIFICATIONS = ROOT / "Docs/TestEvidence/CategoryValidation-20260813T153530+0900/category-5026/results.json"
PREVIOUS_CASES = ROOT / "Docs/TestEvidence/ReleaseQA-1200-20260813/cases.json"
PREVIOUS_COMBINATIONS = ROOT / "Docs/TestEvidence/OfficialMeasurementComparison-20260813/combinations.json"
OUTPUT = ROOT / "FitMatchTests/LiveReleaseQA1200Inputs.json"


def load(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def stable_key(row: dict) -> str:
    identity = f"{row.get('source')}|{row.get('productID')}|{row.get('productURL')}"
    return hashlib.sha256(identity.encode()).hexdigest()


def select_balanced(rows: list[dict], count: int) -> list[dict]:
    buckets: dict[str, deque[dict]] = {}
    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        grouped[row.get("finalDetailCode") or "unresolved"].append(row)
    for detail, values in grouped.items():
        buckets[detail] = deque(sorted(values, key=stable_key))

    selected: list[dict] = []
    details = sorted(buckets)
    while len(selected) < count:
        progressed = False
        for detail in details:
            if buckets[detail]:
                selected.append(buckets[detail].popleft())
                progressed = True
                if len(selected) == count:
                    break
        if not progressed:
            break
    return selected


def main() -> None:
    previous_ids: set[str] = set()
    for row in load(PREVIOUS_CASES):
        previous_ids.add(str(row.get("reference_product_id", "")))
        previous_ids.add(str(row.get("comparison_product_id", "")))
    for row in load(PREVIOUS_COMBINATIONS):
        previous_ids.add(str(row.get("referenceID", "")))
        previous_ids.add(str(row.get("targetID", "")))
    previous_ids.discard("")

    classifications = [
        row for row in load(CLASSIFICATIONS)
        if str(row.get("productID", "")) not in previous_ids
        and row.get("productURL")
    ]
    selected: list[dict] = []
    for source in ("musinsa", "uniqlo"):
        candidates = [row for row in classifications if row.get("source") == source]
        source_selected = select_balanced(candidates, 600)
        if len(source_selected) != 600:
            raise SystemExit(f"Expected 600 {source} candidates, got {len(source_selected)}")
        selected.extend(source_selected)

    target_ids = {str(row["productID"]) for row in selected}
    reference_pool = [
        row for row in classifications if str(row["productID"]) not in target_ids
    ]
    by_detail: dict[tuple[str, str], list[dict]] = defaultdict(list)
    by_category: dict[str, list[dict]] = defaultdict(list)
    for row in sorted(reference_pool, key=stable_key):
        by_detail[(row.get("finalCategoryCode") or "", row.get("finalDetailCode") or "")].append(row)
        by_category[row.get("finalCategoryCode") or ""].append(row)
    used_reference_ids: set[str] = set()

    def choose_reference(target: dict, scenario: str) -> dict:
        target_category = target.get("finalCategoryCode") or ""
        target_detail = target.get("finalDetailCode") or ""
        if scenario == "incompatible_reference":
            candidates = [
                row for category, rows in sorted(by_category.items())
                if category and category != target_category
                for row in rows
            ]
        else:
            candidates = by_detail.get((target_category, target_detail), [])
            if not candidates:
                candidates = by_category.get(target_category, [])
            if not candidates:
                candidates = [
                    row for row in selected
                    if str(row["productID"]) != str(target["productID"])
                    and row.get("finalCategoryCode") == target_category
                    and row.get("finalDetailCode") == target_detail
                ]
            if not candidates:
                candidates = [
                    row for row in selected
                    if str(row["productID"]) != str(target["productID"])
                    and row.get("finalCategoryCode") == target_category
                ]
        for row in candidates:
            if str(row["productID"]) not in used_reference_ids:
                used_reference_ids.add(str(row["productID"]))
                return row
        if not candidates:
            raise SystemExit(
                f"No reference candidate for {target.get('productID')} {target_category}/{target_detail}"
            )
        return candidates[0]

    output = []
    for index, row in enumerate(selected, start=1):
        scenario_slot = (index - 1) % 3
        scenario = ("reference_on" if scenario_slot == 0 else
                    "reference_off" if scenario_slot == 1 else
                    "incompatible_reference")
        reference = choose_reference(row, scenario)
        output.append({
            "case_number": index,
            "source": row["source"],
            "product_id": str(row["productID"]),
            "product_name": row.get("productName", ""),
            "product_url": row["productURL"],
            "shopping_mall_category": row.get("sourcePath", ""),
            "prior_fitmatch_category": row.get("finalCategoryCode"),
            "prior_fitmatch_detail": row.get("finalDetailCode"),
            "planned_scenario": scenario,
            "reference_source": reference["source"],
            "reference_product_id": str(reference["productID"]),
            "reference_product_name": reference.get("productName", ""),
            "reference_product_url": reference["productURL"],
            "reference_shopping_mall_category": reference.get("sourcePath", ""),
            "reference_prior_fitmatch_category": reference.get("finalCategoryCode"),
            "reference_prior_fitmatch_detail": reference.get("finalDetailCode"),
        })

    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    counts = defaultdict(int)
    for row in output:
        counts[(row["source"], row["planned_scenario"])] += 1
    print(json.dumps({
        "total": len(output),
        "excluded_previous_product_ids": len(previous_ids),
        "unique_reference_product_ids": len({row["reference_product_id"] for row in output}),
        "counts": {f"{key[0]}:{key[1]}": value for key, value in sorted(counts.items())},
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
