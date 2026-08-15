#!/usr/bin/env python3
"""Render the current Uniqlo catalog audit attachments as reviewable evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_csv(path: Path, rows: list[dict], fields: list[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_category_catalog(path: Path, rows: list[dict]) -> None:
    category_names = {
        "tops": "상의", "bottoms": "하의", "outerwear": "아우터",
        "underwear": "속옷", "homewear": "홈웨어", "leggings": "레깅스",
        "skirts": "스커트", "dresses": "원피스",
    }
    detail_names = {
        "short_sleeve": "반팔", "long_sleeve": "긴팔", "sleeveless": "민소매",
        "three_quarter_sleeve": "7부소매", "polo_shirt": "폴로셔츠",
        "shirt": "셔츠", "blouse": "블라우스", "knit_top": "니트",
        "cardigan": "가디건", "jacket": "재킷", "coat": "코트",
        "fleece": "플리스", "padding": "패딩", "long_pants": "긴바지",
        "shorts": "반바지", "denim": "데님", "long_leggings": "롱 레깅스",
        "short_leggings": "숏 레깅스", "skirt": "스커트", "one_piece": "원피스",
        "underwear": "속옷",
    }
    lines = [
        "# 유니클로 현재 판매 상품별 FitMatch 카테고리",
        "",
        f"- 기준일: 2026-08-15",
        f"- 활성 상품: {len(rows)}개",
        "- `자동 비교 제외/확인 필요`는 분류 실패를 숨긴 값이 아니라 현재 비교 정책 밖 상품이다.",
        "",
        "| # | 상품 | 유니클로 카테고리 | FitMatch 카테고리 | 상태 |",
        "|---:|---|---|---|---|",
    ]
    for index, row in enumerate(rows, 1):
        category_code = row.get("fitMatchCategoryCode") or ""
        detail_code = row.get("fitMatchDetailCode") or ""
        if category_code:
            fitmatch = category_names.get(category_code, category_code)
            if detail_code:
                fitmatch += " / " + detail_names.get(detail_code, detail_code)
        else:
            fitmatch = "자동 비교 제외/확인 필요"
        if row.get("userConfirmationRequired") or not category_code:
            status = "자동 비교 제외/분류 확인"
        elif not row.get("sizeCount"):
            status = "비교 가능한 실측 없음"
        elif row.get("canonicalEligibility"):
            status = "비교 정책 대상"
        else:
            status = "기준 옷 조건에 따라 비교"
        product = f"[{row['productName']}]({row['productURL']}) (`{row['productID']}`)"
        mall = row["shoppingMallCategory"].replace("|", "\\|")
        lines.append(f"| {index} | {product} | {mall} | {fitmatch} | {status} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def review_reason(row: dict) -> str:
    path = row.get("shoppingMallCategory", "")
    name = row.get("productName", "")
    if "바디수트" in path or "커버올" in path or "살로페트" in name:
        return "독립 body/coverall 비교 축이 없어 사용자 분류 확인 필요"
    if "양말" in path or "삭스" in name:
        return "양말은 현재 FitMatch 치수 비교 대상이 아님"
    if any(token in path for token in ("액세서리", "신발", "우산", "벨트", "선글라스", "모자", "장갑", "목도리")):
        return "비의류 액세서리로 자동 비교 제외"
    if row.get("providerDetailCategory") == "브라" or "브라" in name:
        return "브라 전용 실측 비교 정책이 없어 자동 비교 제외"
    if "수납파우치" in name:
        return "아우터 카테고리에 노출된 수납용 부속품으로 자동 비교 제외"
    if row.get("rawSizeRowCount", 0) and not row.get("sizeCount", 0):
        return "사이즈 표기는 있으나 현재 지원 실측 항목이 없어 자동 비교 제외"
    return "현재 canonical 비교 정책 밖이므로 사용자 확인 또는 비교 제외"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--classifications", type=Path, required=True)
    parser.add_argument("--scenarios", type=Path, required=True)
    parser.add_argument("--unavailable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    classifications = read_json(args.classifications)
    scenarios = read_json(args.scenarios)
    args.output.mkdir(parents=True, exist_ok=True)

    class_fields = list(classifications[0].keys())
    scenario_fields = list(scenarios[0].keys())
    class_csv = args.output / "CurrentUniqloClassificationResults.csv"
    scenario_csv = args.output / "CurrentUniqloATestResults.csv"
    review_csv = args.output / "CurrentUniqloSemanticReview.csv"
    write_csv(class_csv, classifications, class_fields)
    write_csv(scenario_csv, scenarios, scenario_fields)
    write_category_catalog(
        args.output.parent.parent / "CurrentUniqloProductCategoryCatalog-20260815.md",
        classifications,
    )

    review_rows = []
    for row in classifications:
        if row.get("userConfirmationRequired") or not row.get("fitMatchCategoryCode"):
            review_rows.append({**row, "reviewReason": review_reason(row)})
    write_csv(review_csv, review_rows, class_fields + ["reviewReason"])

    failed = [row for row in scenarios if not row.get("passed")]
    unavailable_rows = []
    with args.unavailable.open(encoding="utf-8-sig", newline="") as stream:
        unavailable_rows = list(csv.DictReader(stream))

    summary = {
        "catalogProductCount": len(classifications),
        "rawSizeRowCount": sum(row.get("rawSizeRowCount", 0) for row in classifications),
        "parsedUniqueSizeRowCount": sum(row.get("parsedSizeRowCount", 0) for row in classifications),
        "productsWithUsableSizes": sum(bool(row.get("sizeCount")) for row in classifications),
        "canonicalEligibleProducts": sum(bool(row.get("canonicalEligibility")) for row in classifications),
        "userConfirmationOrExcludedProducts": len(review_rows),
        "scenarioCount": len(scenarios),
        "scenarioPassCount": len(scenarios) - len(failed),
        "scenarioFailureCount": len(failed),
        "scenarioCounts": dict(sorted(Counter(row["scenario"] for row in scenarios).items())),
        "outcomeCounts": dict(sorted(Counter(row["actualOutcome"] for row in scenarios).items())),
        "fitMatchCategoryCounts": dict(sorted(Counter(row.get("fitMatchCategoryCode") or "unclassified" for row in classifications).items())),
        "unavailableOfficialLinkCount": len(unavailable_rows),
        "unavailableOfficialLinks": unavailable_rows,
        "evidenceSha256": {
            class_csv.name: sha256(class_csv),
            scenario_csv.name: sha256(scenario_csv),
            review_csv.name: sha256(review_csv),
        },
    }
    (args.output / "CurrentUniqloATestSummary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
