#!/usr/bin/env python3
"""Replay one new corpus and reject products already used by prior corpora."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
def load_category_logic():
    path = ROOT / "scripts/group-new-clothing-by-fitmatch-category.py"
    spec = importlib.util.spec_from_file_location("fitmatch_category_logic", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--corpus",
        type=Path,
        default=ROOT / "Docs/Research/NewClothingCorpus-320-20260806",
    )
    parser.add_argument(
        "--baseline",
        action="append",
        type=Path,
        default=[],
        help="Prior corpus directory. May be repeated; any product overlap fails.",
    )
    parser.add_argument(
        "--expected-count",
        type=int,
        default=None,
        help="Require the new corpus to contain exactly this many products.",
    )
    args = parser.parse_args()
    corpus = args.corpus if args.corpus.is_absolute() else ROOT / args.corpus
    manifest = corpus / "clothing_product_manifest.json"
    output = corpus / "fitmatch_320_direct_logic_results.csv"
    report = corpus / "fitmatch_320_direct_logic_report.md"
    production_inputs = corpus / "production_classification_inputs.json"
    logic = load_category_logic()
    products = json.loads(manifest.read_text(encoding="utf-8"))["products"]
    if args.expected_count is not None and len(products) != args.expected_count:
        raise SystemExit(f"expected {args.expected_count} products, got {len(products)}")

    def identity(product):
        return product["source"].lower(), str(product["product_key"]).lower()

    new_ids = [identity(product) for product in products]
    duplicate_inside = sorted(key for key, count in Counter(new_ids).items() if count > 1)
    if duplicate_inside:
        raise SystemExit(f"duplicate products inside new corpus: {duplicate_inside[:20]}")

    baseline_ids = set()
    baseline_counts = {}
    for baseline_arg in args.baseline:
        baseline = baseline_arg if baseline_arg.is_absolute() else ROOT / baseline_arg
        baseline_products = json.loads(
            (baseline / "clothing_product_manifest.json").read_text(encoding="utf-8")
        )["products"]
        baseline_counts[baseline.name] = len(baseline_products)
        baseline_ids.update(identity(product) for product in baseline_products)
    overlap = sorted(set(new_ids) & baseline_ids)
    if overlap:
        raise SystemExit(f"new corpus overlaps baseline by {len(overlap)} products: {overlap[:20]}")

    rows = []
    for product in products:
        source = product["source"]
        product_id = product["product_key"]
        evidence = product["raw_evidence"][0]
        raw_path = Path(evidence["path"])
        if not raw_path.is_absolute():
            raw_path = ROOT / raw_path
        manifest_path = " | ".join(product.get("exposure_paths") or [])
        product_name, brand, source_path = logic.raw_metadata(raw_path, source, manifest_path)
        parser_category, category_basis = logic.parser_category(source_path, source)
        managed_category = logic.managed_category(parser_category)
        detail_text = f"{source_path} {product_name}"
        detail_category, detail_basis = logic.detail(detail_text, source)

        # Production ParsedClosetClassification preserves a valid taxonomy
        # fallback for broad provider families instead of rejecting them.
        if detail_category == "기타" and managed_category == "상의":
            detail_category = "기타 상의"
            detail_basis = "production-other_tops"
        elif detail_category == "기타" and managed_category == "하의":
            detail_category = "기타 하의"
            detail_basis = "production-other_bottoms"

        # ParsedClosetClassification resolves special garment types atomically;
        # do not keep a provider-major category that contradicts the detail.
        detail_owner = {
            "반바지": "하의", "긴바지": "하의", "데님": "하의", "스커트": "하의",
            "레깅스": "하의", "트레이닝 팬츠": "하의",
            "브라": "속옷", "남성 브리프": "속옷", "남성 트렁크": "속옷", "속옷": "속옷",
            "원피스": "원피스",
            "라운지웨어": "홈웨어",
            "코트": "아우터", "재킷": "아우터", "점퍼": "아우터", "바람막이": "아우터",
            "패딩": "아우터", "경량패딩": "아우터",
        }.get(detail_category)
        if detail_owner is not None:
            managed_category = detail_owner

        top_level_classified = managed_category != "기타"
        detail_classified = detail_category != "기타"
        # The authoritative compatibility check is the DB/app taxonomy evaluator.
        # This offline pass verifies that both routing keys exist; it must not
        # maintain a second, drifting allow-list of category/detail pairs.
        same_category_reference_selectable = top_level_classified and detail_classified

        declares_size_support = "unknown"
        if source == "musinsa":
            raw = json.loads(raw_path.read_text(encoding="utf-8"))
            value = (raw.get("data") or {}).get("isUseSize")
            declares_size_support = "yes" if value is True else "no" if value is False else "unknown"

        rows.append({
            "판매처": source,
            "상품ID": product_id,
            "브랜드": brand,
            "상품명": product_name,
            "원본카테고리경로": source_path,
            "FitMatch관리카테고리": managed_category,
            "FitMatch세부카테고리": detail_category,
            "상위카테고리분류성공": "yes" if top_level_classified else "no",
            "세부카테고리분류성공": "yes" if detail_classified else "no",
            "동일분류_내옷선택가능": "yes" if same_category_reference_selectable else "no",
            "판매처사이즈사용표시": declares_size_support,
            "실측수치비교검증": "not_tested_no_saved_size_response",
            "판정근거": f"{category_basis}/{detail_basis}",
            "원본파일": str(raw_path),
        })

    rows.sort(key=lambda row: (row["판매처"], row["상품ID"]))
    with output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    category_ok = sum(row["상위카테고리분류성공"] == "yes" for row in rows)
    detail_ok = sum(row["세부카테고리분류성공"] == "yes" for row in rows)
    route_ok = sum(row["동일분류_내옷선택가능"] == "yes" for row in rows)
    categories = Counter(row["FitMatch관리카테고리"] for row in rows)
    unresolved = [row for row in rows if row["동일분류_내옷선택가능"] == "no"]
    musinsa_size_yes = sum(row["판매처"] == "musinsa" and row["판매처사이즈사용표시"] == "yes" for row in rows)

    lines = [
        "# FitMatch 신규 의류 320개 직접 로직 검증",
        "",
        "## 결론",
        "",
        f"- 신규 상품 수: {len(rows)}개 (내부 중복 0개, 과거 코퍼스 중복 0개)",
        f"- 상위 카테고리 분류 성공: {category_ok}/{len(rows)} ({category_ok / len(rows):.1%})",
        f"- 세부 카테고리 확정: {detail_ok}/{len(rows)} ({detail_ok / len(rows):.1%})",
        f"- 동일 분류의 내 옷 선택 라우팅 가능: {route_ok}/{len(rows)} ({route_ok / len(rows):.1%})",
        "- 실측 수치 기반 핏 비교: 이번 코퍼스에 사이즈 API 원본 응답이 없어 판정하지 않음",
        f"- 무신사 상품 상세에서 사이즈 사용 표시가 확인된 상품: {musinsa_size_yes}/{sum(row['판매처'] == 'musinsa' for row in rows)}",
        "",
        "## 상위 카테고리",
        "",
        "| 카테고리 | 상품 수 |",
        "|---|---:|",
    ]
    order = ["상의", "하의", "아우터", "원피스", "속옷", "기타"]
    for category in order:
        if categories[category]:
            lines.append(f"| {category} | {categories[category]} |")
    lines += [
        "",
        "## 비교 라우팅 불가 상품",
        "",
        "상위 카테고리는 정해졌지만 세부 카테고리가 `기타`여서 동일 세부 카테고리 기준 자동 선택을 확정할 수 없는 상품입니다.",
        "",
        "| 판매처 | 상품ID | 상위 분류 | 원본 경로 | 상품명 |",
        "|---|---|---|---|---|",
    ]
    for row in unresolved:
        lines.append(f"| {row['판매처']} | {row['상품ID']} | {row['FitMatch관리카테고리']} | {row['원본카테고리경로'] or '없음'} | {row['상품명'] or '확인 불가'} |")
    lines += [
        "",
        "## 판정 범위",
        "",
        "이 검증은 저장된 판매처 원본 응답에 FitMatch의 카테고리 정규화 및 동일 `serviceGroup + detailCategory` 비교 후보 조건을 직접 적용한 결과입니다. 실제 사이즈 추천 점수까지 검증하려면 상품별 사이즈 API 응답과 같은 분류의 내 옷 실측값이 추가로 필요합니다.",
    ]
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    production_inputs.write_text(json.dumps([
        {
            "source": row["판매처"],
            "product_id": row["상품ID"],
            "product_name": row["상품명"],
            "source_path": row["원본카테고리경로"],
        }
        for row in rows
    ], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "total": len(rows),
        "category_classified": category_ok,
        "detail_classified": detail_ok,
        "comparison_route_possible": route_ok,
        "comparison_route_blocked": len(unresolved),
        "duplicate_inside_new_corpus": len(duplicate_inside),
        "overlap_with_baseline": len(overlap),
        "baseline_corpora": baseline_counts,
        "categories": categories,
        "musinsa_size_declared": musinsa_size_yes,
    }, ensure_ascii=False, default=dict))


if __name__ == "__main__":
    main()
