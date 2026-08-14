#!/usr/bin/env python3
"""Build a deterministic 1,200-case release QA ledger from executed evidence."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MUSINSA_PAIRS = ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/musinsa_actual_measurement_pair_results_real_flow_after_fix.json"
MUSINSA_PAIRS_EXTENDED = ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/musinsa_actual_measurement_pair_results_914.json"
UNIQLO_PAIRS = ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/uniqlo_actual_measurement_pair_results.json"
BLOCKED_PAIRS = ROOT / "Docs/TestEvidence/OfficialMeasurementComparison-20260813/combinations.json"
CURRENT_CLASSIFICATIONS = ROOT / "Docs/TestEvidence/CategoryValidation-20260813T153530+0900/category-5026/results.json"


def load(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def positive_case(
    row: dict,
    source: str,
    number: int,
    current: dict[str, dict],
    reference_on: bool,
) -> dict:
    errors: list[str] = []
    status = row.get("status")
    compared = int(row.get("compared_item_count", 0))
    minimum = int(row.get("minimum_comparable_count", 0))
    score = row.get("score")
    coverage = row.get("coverage")
    reference_category = row.get("reference_category_code", row.get("category_code", ""))
    comparison_category = row.get("comparison_category_code", row.get("category_code", ""))
    comparison_id = str(row.get("comparison_product_id", ""))
    reference_id = str(row.get("reference_product_id", ""))

    if status not in {"confirmed", "insufficient_evidence"}:
        errors.append("unexpected_comparison_status")
    if status == "insufficient_evidence" and not row.get("exclusion_reasons"):
        errors.append("insufficient_evidence_without_exclusion_reason")
    if status == "confirmed" and compared < minimum:
        errors.append("minimum_measurement_count_not_met")
    if not isinstance(score, (int, float)) or not 0 <= score <= 100:
        errors.append("invalid_score")
    if not isinstance(coverage, (int, float)) or not 0 <= coverage <= 1.000001:
        errors.append("invalid_coverage")
    if reference_category != comparison_category:
        errors.append("major_category_mismatch")

    current_row = current.get(comparison_id)
    current_category = current_row.get("finalCategoryCode", "") if current_row else ""
    current_detail = current_row.get("finalDetailCode", "") if current_row else ""
    if current_category and comparison_category and current_category != comparison_category:
        errors.append("current_category_changed")

    required = set(row.get("required_kinds", []))
    required_all = set(row.get("required_all_kinds", []))
    compared_kinds = {item.get("kind") for item in row.get("compared_items", [])}
    if status == "confirmed" and compared_kinds:
        if required and not required.intersection(compared_kinds):
            errors.append("required_measurement_missing")
        if required_all and not required_all.issubset(compared_kinds):
            errors.append("required_all_measurement_missing")

    flow = "automatic_reference" if reference_on else "manual_reference_selection"
    return {
        "case_number": number,
        "platform": source,
        "target_platform": source,
        "evidence_level": "executed_comparison_engine_result",
        "closet_reference_on": reference_on,
        "flow": flow,
        "reference_product_id": reference_id,
        "reference_product_name": row.get("reference_product_name", ""),
        "reference_source_path": row.get("reference_source_path", ""),
        "reference_fitmatch_category": reference_category,
        "reference_fitmatch_detail": row.get("reference_detail_code", row.get("detail_code", "")),
        "comparison_product_id": comparison_id,
        "comparison_product_name": row.get("comparison_product_name", ""),
        "comparison_source_path": row.get("comparison_source_path", ""),
        "comparison_fitmatch_category_at_execution": comparison_category,
        "comparison_fitmatch_detail_at_execution": row.get("comparison_detail_code", row.get("detail_code", "")),
        "comparison_fitmatch_category_current": current_category,
        "comparison_fitmatch_detail_current": current_detail,
        "expected_outcome": (
            "insufficient_evidence"
            if status == "insufficient_evidence"
            else ("automatic_compare" if reference_on else "manual_reference_selection")
        ),
        "actual_pair_outcome": status,
        "block_reason": "",
        "compared_item_count": compared,
        "minimum_comparable_count": minimum,
        "score": score,
        "coverage": coverage,
        "errors": errors,
        "result": "PASS" if not errors else "FAIL",
        "reference_url": row.get("reference_url", ""),
        "comparison_url": row.get("comparison_url", ""),
    }


def allowed_matcher_case(
    row: dict,
    number: int,
    current: dict[str, dict],
    reference_on: bool,
) -> dict:
    errors: list[str] = []
    if row.get("pairComparisonLevel") == "blocked":
        errors.append("allowed_pair_was_blocked")
    if not row.get("recommendationGenerated"):
        errors.append("recommendation_not_generated")
    comparison_id = str(row.get("targetID", ""))
    current_row = current.get(comparison_id)
    current_category = current_row.get("finalCategoryCode", "") if current_row else ""
    current_detail = current_row.get("finalDetailCode", "") if current_row else ""
    return {
        "case_number": number,
        "platform": row.get("targetSource", ""),
        "target_platform": row.get("targetSource", ""),
        "evidence_level": "executed_production_matcher_allowed",
        "closet_reference_on": reference_on,
        "flow": "automatic_reference" if reference_on else "manual_reference_selection",
        "reference_product_id": str(row.get("referenceID", "")),
        "reference_product_name": row.get("referenceName", ""),
        "reference_source_path": "",
        "reference_fitmatch_category": row.get("referenceCategory", ""),
        "reference_fitmatch_detail": row.get("referenceDetail", ""),
        "comparison_product_id": comparison_id,
        "comparison_product_name": row.get("targetName", ""),
        "comparison_source_path": "",
        "comparison_fitmatch_category_at_execution": row.get("targetCategory", ""),
        "comparison_fitmatch_detail_at_execution": row.get("targetDetail", ""),
        "comparison_fitmatch_category_current": current_category,
        "comparison_fitmatch_detail_current": current_detail,
        "expected_outcome": "automatic_compare" if reference_on else "manual_reference_selection",
        "actual_pair_outcome": "confirmed",
        "block_reason": "",
        "compared_item_count": 0,
        "minimum_comparable_count": 0,
        "score": None,
        "coverage": None,
        "errors": errors,
        "result": "PASS" if not errors else "FAIL",
        "reference_url": (
            f"https://www.musinsa.com/products/{row.get('referenceID')}"
            if row.get("referenceSource") == "musinsa"
            else f"https://www.uniqlo.com/kr/ko/products/{row.get('referenceID')}-000"
        ),
        "comparison_url": (
            f"https://www.musinsa.com/products/{row.get('targetID')}"
            if row.get("targetSource") == "musinsa"
            else f"https://www.uniqlo.com/kr/ko/products/{row.get('targetID')}-000"
        ),
    }


def blocked_case(
    row: dict,
    number: int,
    current: dict[str, dict],
    reference_on: bool,
) -> dict:
    errors: list[str] = []
    if row.get("pairComparisonLevel") != "blocked":
        errors.append("pair_not_blocked")
    if row.get("recommendationGenerated"):
        errors.append("recommendation_generated_for_blocked_pair")
    if not row.get("unavailableReason"):
        errors.append("block_reason_missing")
    if not row.get("recoveryPathAvailable"):
        errors.append("recovery_path_missing")

    comparison_id = str(row.get("targetID", ""))
    current_row = current.get(comparison_id)
    current_category = current_row.get("finalCategoryCode", "") if current_row else ""
    current_detail = current_row.get("finalDetailCode", "") if current_row else ""
    return {
        "case_number": number,
        "platform": f"{row.get('referenceSource', '')}->{row.get('targetSource', '')}",
        "target_platform": row.get("targetSource", ""),
        "evidence_level": "executed_production_matcher_block",
        "closet_reference_on": reference_on,
        "flow": "blocked_with_reference" if reference_on else "no_automatic_reference",
        "reference_product_id": str(row.get("referenceID", "")),
        "reference_product_name": row.get("referenceName", ""),
        "reference_source_path": "",
        "reference_fitmatch_category": row.get("referenceCategory", ""),
        "reference_fitmatch_detail": row.get("referenceDetail", ""),
        "comparison_product_id": comparison_id,
        "comparison_product_name": row.get("targetName", ""),
        "comparison_source_path": "",
        "comparison_fitmatch_category_at_execution": row.get("targetCategory", ""),
        "comparison_fitmatch_detail_at_execution": row.get("targetDetail", ""),
        "comparison_fitmatch_category_current": current_category,
        "comparison_fitmatch_detail_current": current_detail,
        "expected_outcome": "blocked",
        "actual_pair_outcome": "blocked",
        "block_reason": row.get("unavailableReason", ""),
        "compared_item_count": 0,
        "minimum_comparable_count": 0,
        "score": None,
        "coverage": None,
        "errors": errors,
        "result": "PASS" if not errors else "FAIL",
        "reference_url": (
            f"https://www.musinsa.com/products/{row.get('referenceID')}"
            if row.get("referenceSource") == "musinsa"
            else f"https://www.uniqlo.com/kr/ko/products/{row.get('referenceID')}-000"
        ),
        "comparison_url": (
            f"https://www.musinsa.com/products/{row.get('targetID')}"
            if row.get("targetSource") == "musinsa"
            else f"https://www.uniqlo.com/kr/ko/products/{row.get('targetID')}-000"
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    classifications = load(CURRENT_CLASSIFICATIONS)
    current = {str(row["productID"]): row for row in classifications}
    musinsa = load(MUSINSA_PAIRS)
    musinsa_extended = load(MUSINSA_PAIRS_EXTENDED)
    uniqlo = load(UNIQLO_PAIRS)
    blocked = load(BLOCKED_PAIRS)

    if len(musinsa) != 597 or len(uniqlo) != 180:
        raise SystemExit("Unexpected positive evidence counts")

    excluded_stale: list[dict] = []
    def current_engine_rows(source: str, collections: list[list[dict]]) -> list[dict]:
        accepted: list[dict] = []
        seen: set[tuple[str, str]] = set()
        for rows in collections:
          for row in rows:
            comparison_id = str(row.get("comparison_product_id", ""))
            pair_key = (str(row.get("reference_product_id", "")), comparison_id)
            if pair_key in seen:
                continue
            seen.add(pair_key)
            current_row = current.get(comparison_id)
            execution_category = row.get("comparison_category_code", row.get("category_code", ""))
            current_category = current_row.get("finalCategoryCode", "") if current_row else ""
            if current_category and execution_category and current_category != execution_category:
                excluded_stale.append({
                    "platform": source,
                    "comparison_product_id": comparison_id,
                    "comparison_product_name": row.get("comparison_product_name", ""),
                    "source_path": row.get("comparison_source_path", ""),
                    "category_at_execution": execution_category,
                    "current_category": current_category,
                    "current_detail": current_row.get("finalDetailCode", ""),
                    "reason": "historical_result_category_differs_from_current_classification",
                })
                continue
            accepted.append(row)
        return accepted

    musinsa_current = current_engine_rows("musinsa", [musinsa, musinsa_extended])[:600]
    uniqlo_current = current_engine_rows("uniqlo", [uniqlo])
    uniqlo_seen = {
        (str(row.get("reference_product_id", "")), str(row.get("comparison_product_id", "")))
        for row in uniqlo_current
    }
    uniqlo_allowed = []
    for row in blocked:
        if row.get("targetSource") != "uniqlo" or row.get("pairComparisonLevel") == "blocked":
            continue
        pair_key = (str(row.get("referenceID", "")), str(row.get("targetID", "")))
        if pair_key in uniqlo_seen:
            continue
        uniqlo_seen.add(pair_key)
        uniqlo_allowed.append(row)

    selected_blocked: list[dict] = []
    uniqlo_blocked = [
        row for row in blocked
        if row.get("targetSource") == "uniqlo" and row.get("pairComparisonLevel") == "blocked"
    ]
    for reason, limit in (
        ("길이 구조 불일치", 68),
        ("성별·연령 보호 차단", 54),
        ("의류 구조 불일치", 250),
    ):
        selected_blocked.extend([
            row for row in uniqlo_blocked if row.get("unavailableReason") == reason
        ][:limit])

    if len(musinsa_current) != 600:
        raise SystemExit(f"Expected 600 current Musinsa positives, got {len(musinsa_current)}")
    if len(uniqlo_current) + len(uniqlo_allowed) != 228:
        raise SystemExit(
            f"Expected 228 current Uniqlo positives, got {len(uniqlo_current) + len(uniqlo_allowed)}"
        )
    if len(selected_blocked) != 372:
        raise SystemExit(f"Expected 372 Uniqlo blocks, got {len(selected_blocked)}")

    cases: list[dict] = []
    positive_index = 0
    for source, rows in (("musinsa", musinsa_current), ("uniqlo", uniqlo_current)):
        for row in rows:
            reference_on = positive_index % 2 == 0
            cases.append(positive_case(
                row, source, len(cases) + 1, current, reference_on
            ))
            positive_index += 1
    for row in uniqlo_allowed:
        reference_on = positive_index % 2 == 0
        cases.append(allowed_matcher_case(
            row, len(cases) + 1, current, reference_on
        ))
        positive_index += 1
    for blocked_index, row in enumerate(selected_blocked):
        cases.append(blocked_case(
            row, len(cases) + 1, current, blocked_index % 2 == 0
        ))

    if len(cases) != 1200:
        raise SystemExit(f"Expected 1200 cases, got {len(cases)}")

    summary = {
        "total": len(cases),
        "passed": sum(row["result"] == "PASS" for row in cases),
        "failed": sum(row["result"] == "FAIL" for row in cases),
        "platforms": dict(Counter(row["platform"] for row in cases)),
        "target_platforms": dict(Counter(row["target_platform"] for row in cases)),
        "reference_setting": dict(Counter(
            "ON" if row["closet_reference_on"] else "OFF" for row in cases
        )),
        "evidence_levels": dict(Counter(row["evidence_level"] for row in cases)),
        "flows": dict(Counter(row["flow"] for row in cases)),
        "block_reasons": dict(Counter(row["block_reason"] for row in cases if row["block_reason"])),
        "error_reasons": dict(Counter(error for row in cases for error in row["errors"])),
    }
    batches = []
    for offset in range(0, len(cases), 10):
        batch = cases[offset:offset + 10]
        batches.append({
            "batch": offset // 10 + 1,
            "range": f"{offset + 1}-{offset + len(batch)}",
            "passed": sum(row["result"] == "PASS" for row in batch),
            "failed": sum(row["result"] == "FAIL" for row in batch),
            "confirmed": sum(row["actual_pair_outcome"] == "confirmed" for row in batch),
            "insufficient_evidence": sum(
                row["actual_pair_outcome"] == "insufficient_evidence" for row in batch
            ),
            "blocked": sum(row["actual_pair_outcome"] == "blocked" for row in batch),
        })
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "cases.json").write_text(
        json.dumps(cases, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (args.output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (args.output / "batches.json").write_text(
        json.dumps(batches, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (args.output / "excluded-stale-evidence.json").write_text(
        json.dumps(excluded_stale, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
