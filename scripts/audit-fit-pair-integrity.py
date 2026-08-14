#!/usr/bin/env python3
"""Independently audit exported FitMatch pair arithmetic and release invariants."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806"
DEFAULT_INPUTS = [
    ("musinsa", RESEARCH / "musinsa_actual_measurement_pair_results_914.json"),
    ("uniqlo", RESEARCH / "uniqlo_actual_measurement_pair_results.json"),
]
DEFAULT_OUTPUT = (
    ROOT / "Docs/Research/FitPairHumanReview-20260806/automated_integrity_report.json"
)


def close(lhs: float, rhs: float, tolerance: float = 1e-8) -> bool:
    return math.isfinite(lhs) and math.isfinite(rhs) and abs(lhs - rhs) <= tolerance


def swift_round_nonnegative(value: float) -> int:
    """Mirror Swift Double.rounded() for nonnegative fit scores (.5 away from zero)."""
    return math.floor(value + 0.5)


def expected_reliability(status: str, count: int) -> str:
    if status != "confirmed":
        return "근거 부족"
    if count >= 4:
        return "높은 신뢰도"
    if count == 3:
        return "충분한 비교"
    return "최소 기준 충족"


def expected_explicit_family(category: str, product_name: str) -> str | None:
    """Return only high-confidence family signals stated in the product name."""
    value = product_name.lower()
    if category == "tops":
        hoodie_tokens = [
            "후디", "후드 티", "후드티", "hoodie", "풀집파카", "풀집 파카",
            "스웨트파카", "스웨트 파카", "full-zip parka", "full zip parka",
        ]
        if any(token in value for token in hoodie_tokens):
            return "hoodie"
        if any(token in value for token in [
            "스웨트셔츠", "스웨트 셔츠", "스웨트", "맨투맨", "sweatshirt",
        ]):
            return "sweatshirt"
        if any(token in value for token in ["니트", "스웨터", "knit", "sweater"]):
            return "knit_cardigan"
    elif category == "bottoms":
        if any(token in value for token in ["레깅스", "타이즈", "타이츠", "leggings"]):
            return "leggings"
        if any(token in value for token in ["데님", "청바지", "denim", "jeans"]):
            return "denim"
    elif category == "outerwear":
        if any(token in value for token in ["가디건", "카디건", "cardigan"]):
            return "knit_cardigan"
        if any(token in value for token in [
            "레더 재킷", "레더 자켓", "가죽 재킷", "가죽 자켓", "라이더스",
            "leather jacket", "riders jacket",
        ]):
            return "leather_jacket"
    return None


def audit(provider: str, path: Path) -> tuple[list[dict], list[dict]]:
    rows = json.loads(path.read_text(encoding="utf-8"))
    issues: list[dict] = []
    seen_pairs: set[str] = set()

    def issue(index: int, code: str, detail: str = "") -> None:
        row = rows[index]
        issues.append({
            "provider": provider,
            "row": index,
            "code": code,
            "detail": detail,
            "reference_product_id": str(row.get("reference_product_id", "")),
            "comparison_product_id": str(row.get("comparison_product_id", "")),
        })

    for index, row in enumerate(rows):
        reference_id = str(row.get("reference_product_id", ""))
        comparison_id = str(row.get("comparison_product_id", ""))
        if not reference_id or not comparison_id or reference_id == comparison_id:
            issue(index, "invalid_pair_identity")
        pair_key = "|".join(sorted([reference_id, comparison_id]))
        if pair_key in seen_pairs:
            issue(index, "duplicate_unordered_pair", pair_key)
        seen_pairs.add(pair_key)

        if row.get("reference_category_code") != row.get("comparison_category_code"):
            issue(index, "major_category_mismatch")
        if row.get("reference_detail_code") != row.get("comparison_detail_code"):
            issue(index, "detail_category_mismatch")

        reference_family = str(row.get("reference_garment_family", ""))
        comparison_family = str(row.get("comparison_garment_family", ""))
        if (not reference_family or reference_family == "unknown"
                or not comparison_family or comparison_family == "unknown"):
            issue(index, "garment_family_missing")
        if (reference_family != comparison_family
                and {reference_family, comparison_family} != {"denim", "pants"}):
            issue(
                index,
                "garment_family_mismatch",
                f"reference={reference_family},comparison={comparison_family}",
            )
        for side, family in [
            ("reference", reference_family),
            ("comparison", comparison_family),
        ]:
            expected_family = expected_explicit_family(
                str(row.get(f"{side}_category_code", "")),
                str(row.get(f"{side}_product_name", "")),
            )
            if expected_family is not None and family != expected_family:
                issue(
                    index,
                    "explicit_product_family_mismatch",
                    f"side={side},expected={expected_family},actual={family}",
                )

        reference_construction = str(row.get("reference_construction_type", ""))
        comparison_construction = str(row.get("comparison_construction_type", ""))
        if not reference_construction or not comparison_construction:
            issue(index, "construction_type_missing")
        if (reference_construction != "unknown"
                and comparison_construction != "unknown"
                and reference_construction != comparison_construction):
            issue(
                index,
                "construction_type_mismatch",
                f"reference={reference_construction},comparison={comparison_construction}",
            )

        reference_gender = str(row.get("reference_gender_code", ""))
        comparison_gender = str(row.get("comparison_gender_code", ""))
        if not reference_gender or not comparison_gender:
            issue(index, "missing_gender_code")
        child_gender_codes = {"boys", "girls", "kids_unisex"}
        adult_gender_codes = {"male", "female"}
        adult_cross_gender_families = {
            "knit_cardigan", "tshirt", "shirt", "sweatshirt", "hoodie",
            "pants", "denim", "leggings", "skirt", "outerwear",
            "leather_jacket", "shoes",
        }
        genders_are_compatible = (
            "unknown" in {reference_gender, comparison_gender}
            or (
                reference_gender in child_gender_codes
                and comparison_gender in child_gender_codes
            )
            or (
                "unisex" in {reference_gender, comparison_gender}
                and not ({reference_gender, comparison_gender} & child_gender_codes)
            )
            or (
                reference_gender in adult_gender_codes
                and comparison_gender in adult_gender_codes
                and (
                    reference_gender == comparison_gender
                    or comparison_family in adult_cross_gender_families
                )
            )
        )
        if not genders_are_compatible:
            issue(
                index,
                "gender_incompatible",
                f"reference={reference_gender},comparison={comparison_gender}",
            )

        if row.get("category_code") in {"tops", "bottoms", "outerwear", "dresses"}:
            reference_length = str(row.get("reference_length_type", ""))
            comparison_length = str(row.get("comparison_length_type", ""))
            if not reference_length or reference_length == "unknown":
                issue(index, "reference_length_missing")
            if not comparison_length or comparison_length == "unknown":
                issue(index, "comparison_length_missing")
            if reference_length != comparison_length:
                issue(
                    index,
                    "comparison_length_mismatch",
                    f"reference={reference_length},comparison={comparison_length}",
                )
        if row.get("category_code") == "outerwear":
            reference_body_length = str(row.get("reference_body_length_type", ""))
            comparison_body_length = str(row.get("comparison_body_length_type", ""))
            if not reference_body_length or reference_body_length == "unknown":
                issue(index, "reference_outer_body_length_missing")
            if not comparison_body_length or comparison_body_length == "unknown":
                issue(index, "comparison_outer_body_length_missing")
            if reference_body_length != comparison_body_length:
                issue(
                    index,
                    "outer_body_length_mismatch",
                    f"reference={reference_body_length},comparison={comparison_body_length}",
                )

        items = row.get("compared_items")
        if not isinstance(items, list):
            issue(index, "compared_items_not_array")
            items = []
        if row.get("compared_item_count") != len(items):
            issue(index, "compared_item_count_mismatch")

        weighted_scores: list[float] = []
        weights: list[float] = []
        seen_kinds: set[str] = set()
        for item_index, item in enumerate(items):
            prefix = f"item={item_index}"
            try:
                reference = float(item["reference_value_cm"])
                comparison = float(item["comparison_value_cm"])
                signed = float(item["signed_difference_cm"])
                absolute = float(item["absolute_difference_cm"])
                item_score = int(item["item_score"])
                weight = float(item["weight"])
            except (KeyError, TypeError, ValueError):
                issue(index, "invalid_compared_item", prefix)
                continue

            if reference <= 0 or comparison <= 0:
                issue(index, "nonpositive_measurement", prefix)
            if not close(signed, comparison - reference):
                issue(index, "signed_difference_mismatch", prefix)
            if not close(absolute, abs(signed)):
                issue(index, "absolute_difference_mismatch", prefix)
            if not 0 <= item_score <= 100:
                issue(index, "item_score_out_of_range", prefix)
            if not math.isfinite(weight) or weight <= 0:
                issue(index, "invalid_weight", prefix)
            code = str(item.get("measurement_code", ""))
            if not code or "unknown" in code.lower():
                issue(index, "unknown_measurement_code", f"{prefix},code={code}")
            kind = str(item.get("kind", ""))
            if not kind or kind in seen_kinds:
                issue(index, "duplicate_or_missing_kind", f"{prefix},kind={kind}")
            seen_kinds.add(kind)
            weighted_scores.append(item_score * weight)
            weights.append(weight)

        required_kinds = row.get("required_kinds")
        required_all_kinds = row.get("required_all_kinds")
        minimum_comparable_count = row.get("minimum_comparable_count")
        minimum_required_kind_count = row.get("minimum_required_kind_count")
        contract_values_are_valid = (
            isinstance(required_kinds, list)
            and isinstance(required_all_kinds, list)
            and isinstance(minimum_comparable_count, int)
            and minimum_comparable_count >= 0
            and isinstance(minimum_required_kind_count, int)
            and minimum_required_kind_count >= 0
        )
        if not contract_values_are_valid:
            issue(index, "comparison_contract_missing_or_invalid")
        else:
            required_kinds_set = {str(kind) for kind in required_kinds}
            required_all_kinds_set = {str(kind) for kind in required_all_kinds}
            eligible = (
                len(items) >= minimum_comparable_count
                and len(seen_kinds & required_kinds_set) >= minimum_required_kind_count
                and required_all_kinds_set.issubset(seen_kinds)
            )
            expected_status = "confirmed" if eligible else "insufficient_evidence"
            if row.get("status") != expected_status:
                issue(
                    index,
                    "comparison_status_contract_mismatch",
                    f"expected={expected_status}",
                )

        if weights:
            recomputed = swift_round_nonnegative(sum(weighted_scores) / sum(weights))
            if row.get("score") != recomputed:
                issue(index, "aggregate_score_mismatch", f"expected={recomputed}")
        score = row.get("score")
        if not isinstance(score, int) or not 0 <= score <= 100:
            issue(index, "score_out_of_range")
        coverage = row.get("coverage")
        if not isinstance(coverage, (int, float)) or not 0 <= coverage <= 1:
            issue(index, "coverage_out_of_range")
        expected = expected_reliability(str(row.get("status", "")), len(items))
        if row.get("reliability") != expected:
            issue(index, "reliability_mismatch", f"expected={expected}")

        if provider == "musinsa":
            if not str(row.get("reference_url", "")).startswith("https://www.musinsa.com/products/"):
                issue(index, "invalid_reference_url")
            if not str(row.get("comparison_url", "")).startswith("https://www.musinsa.com/products/"):
                issue(index, "invalid_comparison_url")
        elif provider == "uniqlo":
            prefix = "https://www.uniqlo.com/kr/ko/products/"
            if not str(row.get("reference_url", "")).startswith(prefix):
                issue(index, "invalid_reference_url")
            if not str(row.get("comparison_url", "")).startswith(prefix):
                issue(index, "invalid_comparison_url")

    return rows, issues


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    all_rows: list[dict] = []
    issues: list[dict] = []
    provider_counts: dict[str, int] = {}
    for provider, path in DEFAULT_INPUTS:
        rows, provider_issues = audit(provider, path)
        provider_counts[provider] = len(rows)
        all_rows.extend(rows)
        issues.extend(provider_issues)

    report = {
        "meta": {
            "created_at": date.today().isoformat(),
            "audit_version": "fit-pair-integrity-v1",
            "pair_count": len(all_rows),
            "provider_counts": provider_counts,
        },
        "result": "passed" if not issues else "failed",
        "issue_count": len(issues),
        "issue_counts": dict(sorted(Counter(item["code"] for item in issues).items())),
        "checked_invariants": [
            "unique_unordered_product_pair",
            "same_major_and_detail_category",
            "compatible_garment_family",
            "explicit_product_name_family_signal",
            "compatible_construction_type",
            "matching_gender_policy",
            "comparison_status_minimum_evidence_contract",
            "positive_measurements",
            "signed_and_absolute_difference_arithmetic",
            "weighted_aggregate_score",
            "score_and_coverage_range",
            "reliability_label_contract",
            "known_measurement_codes_and_unique_kinds",
            "provider_official_url_shape",
        ],
        "issues": issues,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if issues:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
