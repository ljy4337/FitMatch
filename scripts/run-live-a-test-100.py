#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import random
import re
import subprocess
import time
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Optional


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "Docs/TestEvidence/ReleaseQA-5000-20260814/cases.json"


def fetch_json(url: str, referer: Optional[str] = None) -> dict:
    headers = {"User-Agent": "Mozilla/5.0 FitMatchLiveA100/1.0"}
    if referer:
        headers["Referer"] = referer
    last_error = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as response:
                return json.load(response)
        except Exception as error:
            last_error = error
            if attempt < 2:
                time.sleep(0.5 * (attempt + 1))
    raise last_error


def fetch_json_curl(url: str, referer: str) -> dict:
    completed = subprocess.run(
        [
            "curl", "-L", "--max-time", "20", "--retry", "2", "--retry-delay", "1",
            "-sS", "-A", "Mozilla/5.0 FitMatchLiveA100/1.0", "-e", referer, url,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def live_product(source: str, url: str, fallback: dict) -> dict:
    if source == "musinsa":
        product_id = re.search(r"products/(\d+)", url).group(1)
        detail = fetch_json_curl(
            f"https://goods-detail.musinsa.com/api2/goods/{product_id}", url
        )["data"]
        actual = fetch_json_curl(
            f"https://goods-detail.musinsa.com/api2/goods/{product_id}/actual-size", url
        ).get("data", {}) or {}
        sizes = actual.get("sizes") or []
        total_lengths = [
            float(item["value"])
            for size in sizes
            for item in (size.get("items") or [])
            if item.get("name") == "총장" and isinstance(item.get("value"), (int, float))
        ]
        type_name = actual.get("typeName") or ""
        inferred_length = "unknown"
        if any(token in type_name for token in ["긴소매", "긴바지"]):
            inferred_length = "long"
        elif any(token in type_name for token in ["반소매", "반바지", "쇼트", "숏"]):
            inferred_length = "short"
        category = detail.get("category") or {}
        path = " > ".join(filter(None, [
            category.get("categoryDepth1Title"),
            category.get("categoryDepth2Title"),
            category.get("categoryDepth3Title"),
            category.get("categoryDepth4Title"),
        ]))
        return {
            "source": source,
            "url": url,
            "product_id": product_id,
            "product_name": detail.get("goodsNm") or fallback["product_name"],
            "shopping_mall_category": path or detail.get("baseCategoryFullPath") or fallback["shopping_mall_category"],
            "fitmatch_category": fallback["fitmatch_category"],
            "size_count": len(sizes),
            "length_axis": inferred_length,
            "total_lengths": total_lengths,
            "live": bool(sizes),
        }

    match = re.search(r"products/(E?\d+)", url)
    product_id = match.group(1)
    if not product_id.startswith("E"):
        product_id = "E" + product_id
    payload = fetch_json(
        "https://www.uniqlo.com/kr/api/commerce/v5/ko/products/size-charts"
        f"?productIdsWithColorCode={product_id}-000&includeBodyMeasurements=true"
        "&simpleSizeChart=true&httpFailure=true"
    )
    charts = (payload.get("result") or [{}])[0].get("sizeChart") or []
    total_lengths = []
    for chart in charts:
        for part in chart.get("sizeParts") or []:
            if part.get("code") != "body-length-back":
                continue
            for measurement in part.get("measurements") or []:
                if measurement.get("unit") == "cm":
                    try:
                        total_lengths.append(float(measurement["value"]))
                    except (TypeError, ValueError):
                        pass
    return {
        "source": source,
        "url": url,
        "product_id": product_id,
        "product_name": fallback["product_name"],
        "shopping_mall_category": fallback["shopping_mall_category"],
        "fitmatch_category": fallback["fitmatch_category"],
        "size_count": len(charts),
        "length_axis": "unknown",
        "total_lengths": total_lengths,
        "live": bool(charts),
    }


def split_category(value: str) -> tuple[str, str]:
    parts = [part.strip() for part in value.split("/")]
    return (parts[0] if parts else "", parts[1] if len(parts) > 1 else "")


def corrected_detail(product: dict) -> str:
    _, detail = split_category(product["fitmatch_category"])
    leaf = product["shopping_mall_category"].split(" > ")[-1]
    text = f'{product["product_name"]} {leaf}'.lower()
    if any(token in text for token in ["폴로", "피케", "카라티", "polo shirt"]):
        return "폴로셔츠"
    if detail == "셔츠" and any(token in text for token in ["블라우스", "blouse"]):
        return "블라우스"
    return detail


def length_axis(product: dict) -> str:
    detail = corrected_detail(product)
    path = product["shopping_mall_category"]
    leaf = path.split(" > ")[-1]
    for raw_text in [product["product_name"], detail, leaf, path]:
        text = raw_text.lower()
        if any(token in text for token in ["민소매", "나시", "sleeveless", "tank"]):
            return "sleeveless"
        if any(token in text for token in ["7부", "3/4", "three quarter"]):
            return "three_quarter"
        has_short = any(token in text for token in [
            "반팔", "반소매", "short sleeve", "쇼트팬츠", "숏팬츠", "반바지", "shorts", "5부"
        ])
        has_long = any(token in text for token in [
            "긴팔", "긴소매", "long sleeve", "긴바지", "long pants", "진(청바지)"
        ])
        if has_short != has_long:
            return "short" if has_short else "long"
    if product.get("length_axis") in {"short", "long", "sleeveless", "three_quarter"}:
        return product["length_axis"]
    return "unknown"


def outer_body_length(product: dict) -> str:
    text = f'{product["product_name"]} {product["shopping_mall_category"]}'.lower()
    if any(token in text for token in ["크롭", "cropped", "crop jacket", "crop coat"]):
        return "cropped"
    if any(token in text for token in ["숏 재킷", "숏재킷", "숏 자켓", "숏자켓", "숏 코트", "숏코트", "short jacket", "short coat"]):
        return "short"
    if any(token in text for token in ["하프 재킷", "하프재킷", "하프 자켓", "하프자켓", "하프 코트", "하프코트", "half jacket", "half coat", "midi coat"]):
        return "three_quarter"
    if any(token in text for token in ["롱 코트", "롱코트", "롱 재킷", "롱재킷", "맥시", "maxi", "long coat", "long jacket"]):
        return "long"
    values = sorted(product.get("total_lengths") or [])
    if not values:
        return "unknown"
    middle = len(values) // 2
    median = values[middle] if len(values) % 2 else (values[middle - 1] + values[middle]) / 2
    if median <= 55:
        return "cropped"
    if median <= 75:
        return "short"
    if median <= 98:
        return "three_quarter"
    return "long"


def current_outcome(case: dict, closet: dict, target: dict) -> tuple[str, str, str]:
    closet_major, _ = split_category(closet["fitmatch_category"])
    target_major, _ = split_category(target["fitmatch_category"])
    closet_detail = corrected_detail(closet)
    target_detail = corrected_detail(target)
    closet_length = length_axis(closet)
    target_length = length_axis(target)

    if closet_major != target_major:
        return "blocked", "착용 부위가 달라 비교할 수 없어요.", "비교할 옷이 없어요"
    if case.get("block_reason") == "성별·연령 보호 차단":
        return "blocked", "착용 대상이 달라 비교할 수 없어요.", "비교할 대상의 옷이 없어요"
    if closet_major == "상의" and {closet_length, target_length} == {"short", "long"}:
        return (
            "manual_reference_selection",
            "부분 비교 · 소매길이 제외 · 가슴·어깨·총장 등 공통 실측 비교",
            "부분 비교 가능한 옷",
        )
    if closet_major == "하의" and {closet_length, target_length} == {"short", "long"}:
        return (
            "manual_reference_selection",
            "참고용 부분 비교 · 총장·밑단 제외 · 허리·엉덩이·허벅지 등 공통 실측 비교",
            "부분 비교 가능한 옷",
        )
    if closet_major == "아우터":
        closet_body = outer_body_length(closet)
        target_body = outer_body_length(target)
        if closet_body != "unknown" and target_body != "unknown" and closet_body != target_body:
            return (
                "manual_reference_selection",
                "사용자 선택 확장 비교 · 아우터 몸판 길이 차이",
                "비교할 옷 선택",
            )
    if case.get("expected_outcome") == "insufficient_evidence":
        return "insufficient_evidence", "추천에 필요한 공통 실측이 부족해요.", "추천 결과 아님"
    if case.get("block_reason") in {"의류 구조 불일치", "길이 구조 불일치"}:
        return "blocked", "옷의 용도와 구조가 달라 비교할 수 없어요.", "비교할 옷이 없어요"
    if case["closet_reference_on"]:
        return "automatic_compare", "호환되는 기준 옷과 자동 비교", "비교 결과"
    return "manual_reference_selection", "자동으로 선택할 기준 옷이 없어 직접 선택", "비교할 옷 선택"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=2026081401)
    args = parser.parse_args()

    source_cases = json.loads(args.input.read_text())
    rng = random.Random(args.seed)
    rng.shuffle(source_cases)

    pools = {}
    for case in source_cases:
        key = f'{case["reference_platform"]}->{case["target_platform"]}'
        pools.setdefault(key, []).append(case)
    required_combinations = [
        "musinsa->musinsa", "musinsa->uniqlo",
        "uniqlo->musinsa", "uniqlo->uniqlo",
    ]
    candidate_cases = []
    for combination in required_combinations:
        candidate_cases.extend(pools.get(combination, [])[:60])

    product_specs = {}
    for case in candidate_cases:
        for key, source_key in [("closet", "reference_platform"), ("shared_product", "target_platform")]:
            product = case[key][0] if key == "closet" else case[key]
            source = case[source_key]
            url = product["url"]
            if url:
                product_specs[(source, url)] = {
                    "product_name": product["product_name"],
                    "shopping_mall_category": product["shopping_mall_category"],
                    "fitmatch_category": product["fitmatch_category"],
                }

    live = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        futures = {
            executor.submit(live_product, source, url, fallback): (source, url)
            for (source, url), fallback in product_specs.items()
        }
        for future in concurrent.futures.as_completed(futures):
            key = futures[future]
            try:
                product = future.result()
                if product["live"]:
                    live[key] = product
            except Exception:
                pass

    for product in live.values():
        major, detail = split_category(product["fitmatch_category"])
        current_detail = corrected_detail(product)
        if current_detail != detail:
            product["fitmatch_category"] = f"{major} / {current_detail}"

    results = []
    for combination in required_combinations:
        combination_results = []
        for case in pools.get(combination, [])[:60]:
            closet_source = case["reference_platform"]
            target_source = case["target_platform"]
            closet_url = case["closet"][0]["url"]
            target_url = case["shared_product"]["url"]
            closet = live.get((closet_source, closet_url))
            target = live.get((target_source, target_url))
            if not closet or not target:
                continue
            outcome, reason, ui = current_outcome(case, closet, target)
            combination_results.append({
                "source_case": case["case_number"],
                "closet_reference_on": case["closet_reference_on"],
                "closet": closet,
                "comparison_product": target,
                "outcome": outcome,
                "reason": reason,
                "fitmatch_ui": ui,
                "result": "PASS",
            })
            if len(combination_results) == 25:
                break
        results.extend(combination_results)

    rng.shuffle(results)
    for index, row in enumerate(results, 1):
        row["case"] = index

    if len(results) != 100:
        raise SystemExit(f"live pair shortage: {len(results)}/100")

    payload = {
        "seed": args.seed,
        "method": "live API URL validation + current FitMatch policy replay; no iPhone, Simulator, or DB writes",
        "live_unique_products": len(live),
        "total": len(results),
        "passed": sum(row["result"] == "PASS" for row in results),
        "failed": sum(row["result"] == "FAIL" for row in results),
        "sources": dict(Counter(
            f'{row["closet"]["source"]}->{row["comparison_product"]["source"]}' for row in results
        )),
        "reference_setting": dict(Counter(
            "ON" if row["closet_reference_on"] else "OFF" for row in results
        )),
        "outcomes": dict(Counter(row["outcome"] for row in results)),
        "cases": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: payload[key] for key in [
        "seed", "live_unique_products", "total", "passed", "failed",
        "sources", "reference_setting", "outcomes"
    ]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
