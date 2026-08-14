#!/usr/bin/env python3
"""Group the fresh 320-product corpus using FitMatch's production category rules."""

from __future__ import annotations

import csv
import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "Docs/Research/NewClothingCorpus-320-20260806"
INPUT = CORPUS / "clothing_product_manifest.json"
DETAIL_CSV = CORPUS / "fitmatch_category_grouped_products.csv"
SUMMARY_CSV = CORPUS / "fitmatch_category_summary.csv"
GROUPED_JSON = CORPUS / "fitmatch_category_grouped_products.json"
REPORT = CORPUS / "fitmatch_category_grouping_report.md"

CATEGORY_ORDER = {"상의": 0, "하의": 1, "아우터": 2, "원피스": 3, "속옷": 4, "홈웨어": 5, "신발": 6, "액세서리": 7, "기타": 8}


def detail(text: str, source: str) -> tuple[str, str]:
    value = text.lower()
    if "cut & sewn" in value or "cut and sewn" in value:
        return "반팔", "production-source-category-default"
    rules = [
        (("여성 속옷 하의", "팬티"), "팬티"),
        (("브라탑", "브라"), "브라"),
        (("트렁크",), "남성 트렁크"),
        (("브리프",), "남성 브리프"),
        (("홈웨어", "파자마", "라운지"), "라운지웨어"),
        (("스커트",), "스커트"),
        (("원피스",), "원피스"),
        (("풀집 후디", "풀집후디", "메쉬 후디", "메쉬후디", "full zip hoodie", "full-zip hoodie", "mesh hoodie"), "점퍼"),
        (("슬리브리스", "민소매", "나시", "sleeveless", "tank"), "민소매"),
        (("7부",), "7부"),
        (("반소매", "반팔", "short sleeve"), "반팔"),
        (("긴소매", "긴팔", "long sleeve"), "긴팔"),
        (("가디건", "카디건", "cardigan"), "가디건"),
        (("후드", "hoodie"), "후드"),
        (("스웨트", "맨투맨", "sweat"), "스웨트"),
        (("블라우스",), "블라우스"),
        (("셔츠", "shirt"), "셔츠"),
        (("니트", "스웨터", "knit", "sweater"), "니트"),
        (("슬랙스", "slacks"), "슬랙스"),
        (("반바지", "숏 팬츠", "숏팬츠", "쇼트 팬츠", "쇼트팬츠", "쇼츠", "shorts", "short pants"), "반바지"),
        (("데님", "청바지", "jeans", "denim"), "데님"),
        (("레깅스", "leggings"), "레깅스"),
        (("블레이저",), "블레이저"),
        (("블루종",), "블루종"),
        (("플리스", "후리스", "fleece"), "플리스"),
        (("바람막이", "윈드브레이커", "windbreaker"), "바람막이"),
        (("경량 패딩", "퍼프테크"), "경량패딩"),
        (("숏 패딩",), "숏패딩"),
        (("패딩", "파카", "parka"), "패딩"),
        (("코트", "coat"), "코트"),
        (("점퍼", "jumper"), "점퍼"),
        (("재킷", "자켓", "트랙탑", "track top", "tracktop", "jacket"), "재킷"),
        (("속옷", "언더웨어", "이너웨어", "underwear", "inner"), "속옷"),
        (("조거", "트레이닝 팬츠"), "트레이닝 팬츠"),
        (("팬츠", "바지", "pants"), "긴바지"),
        (("티셔츠",), "반팔" if "그래픽" in text else "기타"),
    ]
    for tokens, mapped in rules:
        if any(token.lower() in value for token in tokens):
            return mapped, "production-keyword"
    return "기타", "fallback"


def parser_category(text: str, source: str) -> tuple[str, str]:
    value = text.lower()
    if source == "musinsa":
        depths = [part.strip() for part in text.split(">") if part.strip()]
        umbrella = {"원피스/스커트", "경량 패딩/패딩 베스트"}
        probes = [part for part in reversed(depths) if part not in umbrella] + [text]
        for probe in probes:
            if "여성 속옷 하의" in probe or "속옷" in probe: return "속옷", "production-path"
            if "원피스" in probe: return "원피스", "production-path"
            if "스커트" in probe: return "하의", "production-path"
            if "홈웨어" in probe: return "기타", "production-path"
            if any(x in probe for x in ("팬츠", "바지", "데님", "하의", "쇼츠")): return "하의", "production-path"
            if any(x in probe for x in ("아우터", "재킷", "자켓", "코트", "점퍼", "패딩")): return "아우터", "production-path"
            if "셔츠" in probe: return "셔츠", "production-path"
            if "니트" in probe: return "니트", "production-path"
            if any(x in probe for x in ("티셔츠", "상의", "반소매", "긴소매", "민소매")): return "상의", "production-path"
        return "기타", "fallback"

    if any(x in value for x in ("homewear", "loungewear")) or any(x in text for x in ("홈웨어", "라운지", "파자마")): return "홈웨어", "production-path"
    if "오버셔츠" in text or "shirt" in value or "셔츠" in text: return "상의", "production-path"
    if "스커트" in text or "skirt" in value: return "하의", "production-path"
    if "원피스" in text or ("women" in value and "dress" in value): return "원피스", "production-path"
    if any(x in value for x in ("bottoms", "pants", "jeans", "shorts")) or any(x in text for x in ("팬츠", "바지", "데님", "쇼츠", "레깅스")): return "하의", "production-path"
    if any(x in value for x in ("outer", "jacket", "coat")) or any(x in text for x in ("아우터", "재킷", "자켓", "코트", "파카", "점퍼")): return "아우터", "production-path"
    if "tops" in value or "상의" in text: return "상의", "production-path"
    if any(x in value for x in ("inner", "underwear")) or any(x in text for x in ("속옷", "이너")): return "속옷", "production-path"
    return "상의", "production-default"


def managed_category(parser: str) -> str:
    return {"셔츠": "상의", "니트": "상의", "팬츠": "하의"}.get(parser, parser)


def raw_metadata(raw_path: Path, source: str, fallback_path: str) -> tuple[str, str, str]:
    if source != "musinsa":
        supplement_path = raw_path.parents[3] / "supplemental_product_metadata.json"
        if supplement_path.exists():
            supplement = json.loads(supplement_path.read_text(encoding="utf-8"))
            product_core = raw_path.stem.split("-")[0]
            if product_core in supplement:
                item = supplement[product_core]
                return item["product_name"], item.get("brand", "유니클로"), item["source_path"]
        text = raw_path.read_text(encoding="utf-8", errors="replace").replace("\x00", "")
        match = re.search(
            r"window\.__PRELOADED_STATE__\s*=\s*(\{.*?\})\s*;?\s*</script>",
            text,
            flags=re.DOTALL,
        )
        if match:
            try:
                state = json.loads(match.group(1))
                entities = state.get("entity", {}).get("pdpEntity", {})
                product_core = raw_path.stem.split("-")[0]
                for entity in entities.values():
                    product = entity.get("product", {}) if isinstance(entity, dict) else {}
                    if str(product.get("productId", "")).startswith(product_core):
                        return str(product.get("name") or ""), "유니클로", fallback_path
            except json.JSONDecodeError:
                pass
        return "", "유니클로", fallback_path
    raw = json.loads(raw_path.read_text(encoding="utf-8"))
    data = raw.get("data") or {}
    category = data.get("category") or {}
    depths = []
    for depth in range(1, 5):
        value = category.get(f"categoryDepth{depth}Title") or category.get(f"categoryDepth{depth}Name")
        if value and value not in depths:
            depths.append(value)
    return data.get("goodsNm") or "", (data.get("brandInfo") or {}).get("brandName") or "", " > ".join(depths) or fallback_path


def main() -> None:
    payload = json.loads(INPUT.read_text(encoding="utf-8"))
    products = payload["products"]
    if len(products) != 320:
        raise SystemExit(f"expected 320 products, got {len(products)}")

    rows = []
    for product in products:
        path = " | ".join(product.get("exposure_paths") or [])
        evidence = product["raw_evidence"][0]
        raw_path = Path(evidence["path"])
        if not raw_path.is_absolute():
            raw_path = ROOT / raw_path
        product_name, brand_name, effective_path = raw_metadata(raw_path, product["source"], path)
        parsed, category_basis = parser_category(effective_path, product["source"])
        detail_text = f"{effective_path} {product_name}"
        detail_name, detail_basis = detail(detail_text, product["source"])
        collected_at = evidence.get("collected_at") or datetime.fromtimestamp(raw_path.stat().st_mtime, timezone.utc).isoformat()
        sha256 = evidence.get("sha256") or hashlib.sha256(raw_path.read_bytes()).hexdigest()
        rows.append({
            "핏매치_관리카테고리": managed_category(parsed),
            "핏매치_세부카테고리": detail_name,
            "핏매치_파서카테고리": parsed,
            "판매처": product["source"],
            "상품ID": product["product_key"],
            "상품명": product_name,
            "브랜드": brand_name,
            "판매처_카테고리경로": path,
            "원본응답_카테고리경로": effective_path,
            "분류근거": f"{category_basis}/{detail_basis}",
            "수집시각_UTC": collected_at,
            "원본응답URL": evidence["url"],
            "원본파일": str(raw_path),
            "SHA256": sha256,
        })

    rows.sort(key=lambda row: (CATEGORY_ORDER.get(row["핏매치_관리카테고리"], 99), row["핏매치_세부카테고리"], row["판매처"], row["상품ID"]))
    with DETAIL_CSV.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    counts = Counter((row["핏매치_관리카테고리"], row["핏매치_세부카테고리"], row["판매처"]) for row in rows)
    summary_rows = [
        {"핏매치_관리카테고리": category, "핏매치_세부카테고리": detail_name, "판매처": source, "상품수": count}
        for (category, detail_name, source), count in counts.items()
    ]
    summary_rows.sort(key=lambda row: (CATEGORY_ORDER.get(row["핏매치_관리카테고리"], 99), row["핏매치_세부카테고리"], row["판매처"]))
    with SUMMARY_CSV.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(summary_rows[0]))
        writer.writeheader()
        writer.writerows(summary_rows)

    grouped = {}
    for row in rows:
        grouped.setdefault(row["핏매치_관리카테고리"], {}).setdefault(row["핏매치_세부카테고리"], []).append(row)
    GROUPED_JSON.write_text(json.dumps({"product_count": len(rows), "categories": grouped}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    category_counts = Counter(row["핏매치_관리카테고리"] for row in rows)
    source_counts = Counter(row["판매처"] for row in rows)
    fallback_count = sum("fallback" in row["분류근거"] for row in rows)
    lines = [
        "# 신규 의류 320개 FitMatch 카테고리 분류 결과",
        "",
        "- 기준: 앱의 MusinsaProductMetadataParser/UniqloParser 분류 순서 및 ClothingCategory.serviceGroup",
        f"- 전체 상품: {len(rows)}개 (무신사 {source_counts['musinsa']}개, 유니클로 {source_counts['uniqlo']}개)",
        f"- 키워드 미확정 세부 분류 포함: {fallback_count}개 (`기타`로 보존)",
        "",
        "## 관리 카테고리별 상품 수",
        "",
        "| 관리 카테고리 | 상품 수 |",
        "|---|---:|",
    ]
    for category in sorted(category_counts, key=lambda item: CATEGORY_ORDER.get(item, 99)):
        lines.append(f"| {category} | {category_counts[category]} |")
    lines += [
        "",
        "## 산출물",
        "",
        "- `fitmatch_category_grouped_products.csv`: 320개 전체 상세 목록",
        "- `fitmatch_category_summary.csv`: 카테고리/세부 카테고리/판매처별 집계",
        "- `fitmatch_category_grouped_products.json`: 카테고리 계층형 데이터",
        "",
        "주의: 이 파일은 수집 당시 판매처 카테고리 경로를 앱의 현재 규칙에 대입한 사전 분류 결과이며, 실제 상품 상세 파싱에서 상품명 등 추가 메타데이터로 보정될 수 있습니다.",
    ]
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"products": len(rows), "categories": category_counts, "sources": source_counts, "fallback": fallback_count}, ensure_ascii=False, default=dict))


if __name__ == "__main__":
    main()
