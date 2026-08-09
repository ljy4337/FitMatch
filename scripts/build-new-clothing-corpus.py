#!/usr/bin/env python3
import csv
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "Docs/Research/NewClothingCorpus-320-20260806"
SURVEY = ROOT / "Docs/Research/LiveProductSurvey-20260723/products.csv"
NON_CLOTHING = re.compile(r"액세서리|가방|모자|벨트|우산|양말|삭스|신발|슈즈|주얼리|시계|뷰티")


def normalized_key(source: str, product_key: str) -> tuple[str, str]:
    return source, product_key.split("-")[0]


def previous_keys() -> set[tuple[str, str]]:
    keys = set()
    with SURVEY.open(encoding="utf-8-sig", newline="") as file:
        for row in csv.DictReader(file):
            source = "musinsa" if row["쇼핑몰"] == "무신사" else "uniqlo"
            keys.add(normalized_key(source, row["상품 ID 또는 코드"]))
    return keys


def main() -> None:
    manifest = json.loads((CORPUS / "product_manifest.json").read_text(encoding="utf-8"))["products"]
    selected = []
    excluded = []
    for product in manifest:
        paths = product.get("exposure_paths", [])
        if NON_CLOTHING.search(" | ".join(paths)):
            excluded.append({
                "source": product["source"],
                "product_key": product["product_key"],
                "exposure_paths": paths,
                "reason": "non_clothing_path",
            })
            continue
        selected.append({
            "source": product["source"],
            "product_key": product["product_key"],
            "observed_ids": product.get("observed_ids", []),
            "exposure_paths": paths,
            "raw_evidence": product.get("raw_evidence", []),
            "selection": "fresh_live_collection_clothing_path",
        })

    for path in sorted((CORPUS / "raw/supplement").glob("musinsa-*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        data = payload.get("data") or {}
        product_key = str(data.get("goodsNo") or path.stem.removeprefix("musinsa-"))
        category_path = data.get("baseCategoryFullPath") or ""
        if NON_CLOTHING.search(category_path):
            excluded.append({
                "source": "musinsa",
                "product_key": product_key,
                "exposure_paths": [category_path],
                "reason": "non_clothing_path",
            })
            continue
        selected.append({
            "source": "musinsa",
            "product_key": product_key,
            "observed_ids": [product_key],
            "product_name": data.get("goodsNm"),
            "brand": data.get("brand"),
            "gender": data.get("genders", []),
            "exposure_paths": [category_path],
            "raw_evidence": [{
                "path": str(path.relative_to(ROOT)),
                "url": f"https://goods-detail.musinsa.com/api2/goods/{product_key}",
                "status": 200,
                "bytes": path.stat().st_size,
            }],
            "selection": "fresh_live_collection_clothing_supplement",
        })

    unique = {}
    for product in selected:
        unique[(product["source"], product["product_key"])] = product
    selected = sorted(unique.values(), key=lambda item: (item["source"], item["product_key"]))
    if len(selected) != 320:
        raise SystemExit(f"expected 320 selected clothing products, got {len(selected)}")

    old = previous_keys()
    for product in selected:
        product["seen_in_20260723_survey"] = normalized_key(product["source"], product["product_key"]) in old

    generated_at = datetime.now(timezone.utc).isoformat()
    output = {
        "generated_at": generated_at,
        "definition": "Fresh HTTP responses collected on 2026-08-06; non-clothing paths excluded.",
        "product_count": len(selected),
        "products": selected,
        "excluded_non_clothing": excluded,
    }
    (CORPUS / "clothing_product_manifest.json").write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    with (CORPUS / "clothing_products.csv").open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=[
            "source", "product_key", "observed_ids", "exposure_paths", "selection",
            "seen_in_20260723_survey", "raw_evidence_count",
        ])
        writer.writeheader()
        for product in selected:
            writer.writerow({
                "source": product["source"],
                "product_key": product["product_key"],
                "observed_ids": "|".join(product.get("observed_ids", [])),
                "exposure_paths": "|".join(product.get("exposure_paths", [])),
                "selection": product["selection"],
                "seen_in_20260723_survey": product["seen_in_20260723_survey"],
                "raw_evidence_count": len(product.get("raw_evidence", [])),
            })

    source_counts = Counter(product["source"] for product in selected)
    repeated = sum(product["seen_in_20260723_survey"] for product in selected)
    report = f"""# 신규 의류 320개 수집 결과

- 생성 시각: {generated_at}
- 신규 HTTP 수집 의류 원본: **{len(selected)}개**
- 무신사: {source_counts['musinsa']}개
- 유니클로: {source_counts['uniqlo']}개
- 비의류 제외: {len(excluded)}개
- 2026-07-23 조사 상품과 ID 중복: {repeated}개
- 이전 조사에 없던 상품 ID: {len(selected) - repeated}개

## 정의

이 결과의 `신규`는 기존 CSV를 복사한 것이 아니라 2026-08-06에 공개 HTTP 응답을 다시 수집했다는 의미다. 현재 판매 상품 특성상 이전 조사와 동일한 상품 ID가 포함될 수 있으며 위에 별도 집계했다.

액세서리, 가방, 모자, 벨트, 우산, 양말, 신발, 주얼리, 시계, 뷰티 경로는 제외했다. 보충 표본은 무신사 의류 카테고리에서 발견됐지만 최초 제한 때문에 상세를 받지 않았던 상품을 사용했다.

## 산출물

- `clothing_product_manifest.json`: 상품별 원본 증거 경로와 선별 근거
- `clothing_products.csv`: 검토·집계용 평면 목록
- `raw/`: 원본 HTTP 응답
- `checkpoint.json`: 요청·재개 체크포인트
- `request_metrics.json`: 요청 성공·실패·응답시간
"""
    (CORPUS / "new_clothing_collection_summary.md").write_text(report, encoding="utf-8")
    print(json.dumps({
        "selected_clothing": len(selected),
        "sources": source_counts,
        "excluded_non_clothing": len(excluded),
        "seen_in_previous_survey": repeated,
        "new_product_ids": len(selected) - repeated,
    }, ensure_ascii=False, indent=2, default=dict))


if __name__ == "__main__":
    main()
