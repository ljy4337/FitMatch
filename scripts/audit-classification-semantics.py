#!/usr/bin/env python3
"""Audit high-confidence semantic signals in exported production classifications."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806"
DEFAULT_INPUT = RESEARCH / "swift_production_classification_results_cumulative_2560.json"
DEFAULT_OUTPUT = (
    ROOT / "Docs/Research/FitPairHumanReview-20260806"
    / "classification_semantic_audit_report.json"
)


def contains_any(value: str, tokens: list[str]) -> bool:
    normalized = value.lower()
    return any(token in normalized for token in tokens)


def expected_top_detail(product_name: str) -> str | None:
    if contains_any(product_name, ["민소매", "나시", "슬리브리스", "sleeveless", "tank"]):
        return "sleeveless"
    has_short = contains_any(product_name, [
        "반팔", "반소매", "숏슬리브", "하프 슬리브", "short sleeve", "half sleeve",
        "cap sleeve", "s/s tee", "s/s t-shirt", "s/s tshirt",
    ])
    has_long = contains_any(product_name, [
        "긴팔", "긴소매", "롱슬리브", "long sleeve",
        "l/s tee", "l/s t-shirt", "l/s tshirt",
    ])
    if has_short != has_long:
        return "short_sleeve" if has_short else "long_sleeve"
    if contains_any(product_name, ["7부", "three quarter", "3/4"]):
        return "three_quarter_sleeve"
    return None


def expected_bottom_detail(category: str, product_name: str) -> str | None:
    if category == "leggings":
        if contains_any(product_name, ["6부", "7부", "8부", "카프리", "capri", "three quarter", "3/4"]):
            return "three_quarter_leggings"
        if contains_any(product_name, ["9부", "ankle"]):
            return "nine_tenths_leggings"
        if contains_any(product_name, [
            "숏", "쇼트", "short", "쇼츠", "바이커", "3부", "3.5부", "4부",
            "4.5부", "5부", "하프 타이즈", "하프타이즈", "하프 타이츠", "하프타이츠",
        ]):
            return "short_leggings"
        if contains_any(product_name, ["롱", "long", "10부"]):
            return "long_leggings"
        return None
    if category != "bottoms":
        return None
    if contains_any(product_name, [
        "숏 팬츠", "숏팬츠", "쇼트 팬츠", "쇼트팬츠", "반바지", "쇼츠",
        "버뮤다", "큐롯", "culotte", "shorts", "short pants",
    ]):
        return "shorts"
    if contains_any(product_name, [
        "크롭 팬츠", "크롭팬츠", "cropped pants", "카프리 팬츠", "카프리팬츠",
        "capri pants",
    ]):
        return "cropped_pants"
    if contains_any(product_name, [
        "6부 팬츠", "7부 팬츠", "8부 팬츠", "three quarter pants", "3/4 pants",
    ]):
        return "three_quarter_pants"
    if contains_any(product_name, ["9부 팬츠", "9부팬츠", "ankle pants", "nine tenths pants"]):
        return "nine_tenths_pants"
    if contains_any(product_name, ["긴바지", "롱 팬츠", "long pants"]):
        return "long_pants"
    return None


def expected_category_and_detail(row: dict) -> tuple[str, str] | None:
    name = str(row.get("product_name", ""))
    source_path = str(row.get("source_path", ""))
    if contains_any(name, ["가디건", "카디건", "cardigan"]):
        if not contains_any(source_path, ["홈웨어", "파자마", "homewear", "pajama", "pyjama"]):
            return "outerwear", "cardigan"
    if contains_any(name, ["레깅스", "leggings"]):
        if not contains_any(source_path, ["이너웨어", "히트텍", "innerwear", "heattech"]):
            return "leggings", str(row.get("detail_code", ""))
    if "원피스" in name:
        if not contains_any(source_path, [
            "점프 슈트", "점프수트", "오버올", "jumpsuit", "overall", "수영", "swim",
        ]):
            return "dresses", "one_piece"
    return None


def audit(rows: list[dict], expected_count: int) -> list[dict]:
    issues: list[dict] = []
    seen: set[tuple[str, str]] = set()

    def issue(index: int, code: str, detail: str = "") -> None:
        row = rows[index] if index < len(rows) else {}
        issues.append({
            "row": index,
            "code": code,
            "detail": detail,
            "source": str(row.get("source", "")),
            "product_id": str(row.get("product_id", "")),
            "product_name": str(row.get("product_name", "")),
        })

    if len(rows) != expected_count:
        issue(0, "unexpected_corpus_count", f"expected={expected_count},actual={len(rows)}")

    for index, row in enumerate(rows):
        identity = (str(row.get("source", "")), str(row.get("product_id", "")))
        if not all(identity):
            issue(index, "missing_product_identity")
        elif identity in seen:
            issue(index, "duplicate_product_identity", "|".join(identity))
        seen.add(identity)

        if row.get("is_valid") is not True:
            issue(index, "invalid_classification")
        category = str(row.get("category_code", ""))
        detail = str(row.get("detail_code", ""))
        if not category or not detail:
            issue(index, "missing_category_or_detail")

        if category == "tops":
            expected_detail = expected_top_detail(str(row.get("product_name", "")))
            if expected_detail is not None and detail != expected_detail:
                issue(
                    index,
                    "explicit_top_length_mismatch",
                    f"expected={expected_detail},actual={detail}",
                )

        expected_bottom = expected_bottom_detail(category, str(row.get("product_name", "")))
        if expected_bottom is not None and detail != expected_bottom:
            issue(
                index,
                "explicit_bottom_length_mismatch",
                f"expected={expected_bottom},actual={detail}",
            )

        expected_category = expected_category_and_detail(row)
        if expected_category is not None:
            expected_major, expected_detail = expected_category
            if category != expected_major or detail != expected_detail:
                issue(
                    index,
                    "explicit_category_mismatch",
                    f"expected={expected_major}/{expected_detail},actual={category}/{detail}",
                )

    return issues


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--expected-count", type=int, default=2560)
    args = parser.parse_args()

    rows = json.loads(args.input.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        raise SystemExit("classification input must be a JSON array")
    issues = audit(rows, args.expected_count)
    report = {
        "meta": {
            "audit_version": "classification-semantic-v1",
            "created_at": date.today().isoformat(),
            "classification_count": len(rows),
            "provider_counts": dict(sorted(Counter(
                str(row.get("source", "")) for row in rows
            ).items())),
        },
        "result": "passed" if not issues else "failed",
        "issue_count": len(issues),
        "issue_counts": dict(sorted(Counter(item["code"] for item in issues).items())),
        "checked_invariants": [
            "expected_corpus_count",
            "unique_provider_product_identity",
            "valid_nonempty_classification",
            "explicit_product_category_signal",
            "explicit_top_length_signal",
            "explicit_bottom_length_signal",
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
