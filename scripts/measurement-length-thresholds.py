#!/usr/bin/env python3
"""Derive conservative garment-length thresholds from the checked-in live survey."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


SHORT_SLEEVE = ("반소매", "반팔", "short sleeve")
LONG_SLEEVE = ("긴소매", "긴팔", "long sleeve")
SHORT_BOTTOM = ("쇼트 팬츠", "쇼트팬츠", "반바지", "쇼츠", "shorts", "버뮤다")
LONG_BOTTOM = (
    "긴바지", "데님 팬츠", "코튼 팬츠", "슈트 팬츠", "슬랙스",
    "트레이닝/조거", "트레이닝 팬츠", "조거 팬츠", "long pants",
)


def percentile(values: list[float], probability: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def label_for(text: str, garment: str) -> str | None:
    lowered = text.lower()
    if garment == "sleeve":
        short_position = max((lowered.rfind(token) for token in SHORT_SLEEVE), default=-1)
        long_position = max((lowered.rfind(token) for token in LONG_SLEEVE), default=-1)
        if short_position >= 0 or long_position >= 0:
            return "short" if short_position > long_position else "long"
    else:
        short_position = max((lowered.rfind(token) for token in SHORT_BOTTOM), default=-1)
        long_position = max((lowered.rfind(token) for token in LONG_BOTTOM), default=-1)
        if short_position >= 0 or long_position >= 0:
            return "short" if short_position > long_position else "long"
    return None


def normalized_gender(value: str) -> str:
    upper = value.upper()
    if "아동" in value or "키즈" in value or "KIDS" in upper or "BABY" in upper:
        return "kids"
    if ("여성" in value and "남성" not in value) or upper == "WOMEN":
        return "women"
    if ("남성" in value and "여성" not in value) or upper == "MEN":
        return "men"
    return "unisex"


def measurement_for(row: dict[str, str], item: dict, garment: str) -> tuple[str, float] | None:
    name = str(item.get("name", "")).lower().replace(" ", "")
    code = str(item.get("code", "")).lower()
    try:
        value = float(str(item.get("value", "")).replace(",", "."))
    except ValueError:
        return None
    if not math.isfinite(value) or value <= 0:
        return None

    if garment == "sleeve":
        if "sleeve-length-cb" in code or "등중심부터소매" in name or name == "화장":
            return "center_back", value
        if "sleeve-length" in code or "소매" in name:
            method = "musinsa_reported" if row["쇼핑몰"] == "무신사" else "set_in"
            return method, value
        return None

    if row["쇼핑몰"] == "유니클로":
        if code == "inseam" or "다리길이" in name or name == "인심":
            return "inseam", value
    elif name in {"총장", "총기장", "총길이", "기장"}:
        return "outseam", value
    return None


def derive(input_path: Path, uniqlo_samples_path: Path | None = None) -> dict:
    samples: dict[tuple[str, str, str, str, str], list[float]] = defaultdict(list)
    product_counts: dict[str, int] = defaultdict(int)
    with input_path.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            text = " ".join([
                row["상품명"],
                row["쇼핑몰 원본 카테고리 전체 경로"],
                row["조사자 상세분류 후보"],
            ])
            garment = "sleeve" if row["조사자 앱 대분류 후보"] in {"상의", "아우터"} else "bottom"
            label = label_for(text, garment)
            if label is None:
                continue
            try:
                size_rows = json.loads(row["원본 실측 행 JSON"] or "[]")
            except json.JSONDecodeError:
                continue
            by_method: dict[str, list[float]] = defaultdict(list)
            for size_row in size_rows:
                for item in size_row.get("items", []):
                    found = measurement_for(row, item, garment)
                    if found:
                        method, value = found
                        by_method[method].append(value)
            for method, values in by_method.items():
                product_median = statistics.median(values)
                key = (
                    row["쇼핑몰"],
                    garment,
                    normalized_gender(row["성별"]),
                    method,
                    label,
                )
                samples[key].append(product_median)
                product_counts[row["쇼핑몰"]] += 1

    if uniqlo_samples_path:
        payload = json.loads(uniqlo_samples_path.read_text(encoding="utf-8"))
        for product in payload.get("products", []):
            path = product.get("category_path", "")
            garment = "bottom" if "팬츠" in path else "sleeve"
            label_source = path if garment == "bottom" else path.split(">")[-1]
            label = label_for(label_source, garment)
            if garment == "bottom" and label is None and path.startswith("팬츠 >"):
                label = "long"
            if label is None:
                continue
            by_method: dict[str, list[float]] = defaultdict(list)
            for size in product.get("size_chart", []):
                for part in size.get("sizeParts", []):
                    code = str(part.get("code", "")).lower()
                    if garment == "sleeve":
                        if code == "sleeve-length-cb":
                            method = "center_back"
                        elif code == "sleeve-length":
                            method = "set_in"
                        else:
                            continue
                    elif code == "inseam":
                        method = "inseam"
                    else:
                        continue
                    centimeter = next(
                        (value for value in part.get("measurements", [])
                         if value.get("unit") == "cm"),
                        None,
                    )
                    if not centimeter:
                        continue
                    try:
                        value = float(centimeter["value"])
                    except (TypeError, ValueError):
                        continue
                    if math.isfinite(value) and value > 0:
                        by_method[method].append(value)
            for method, values in by_method.items():
                key = (
                    "유니클로",
                    garment,
                    normalized_gender(product.get("gender", "")),
                    method,
                    label,
                )
                samples[key].append(statistics.median(values))
                product_counts["유니클로"] += 1

    groups: list[dict] = []
    bases = sorted({key[:4] for key in samples})
    for platform, garment, gender, method in bases:
        short = samples.get((platform, garment, gender, method, "short"), [])
        long = samples.get((platform, garment, gender, method, "long"), [])
        if not short or not long:
            continue
        short_p95 = percentile(short, 0.95)
        long_p05 = percentile(long, 0.05)
        midpoint = (statistics.median(short) + statistics.median(long)) / 2
        separation_boundary = (short_p95 + long_p05) / 2
        boundary = separation_boundary if short_p95 < long_p05 else midpoint
        groups.append({
            "platform": platform,
            "garment": garment,
            "gender": gender,
            "method": method,
            "short": {
                "count": len(short),
                "min": round(min(short), 2),
                "median": round(statistics.median(short), 2),
                "p95": round(short_p95, 2),
                "max": round(max(short), 2),
            },
            "long": {
                "count": len(long),
                "min": round(min(long), 2),
                "p05": round(long_p05, 2),
                "median": round(statistics.median(long), 2),
                "max": round(max(long), 2),
            },
            "boundary_cm": round(boundary, 2),
            "separated": short_p95 < long_p05,
        })
    return {
        "source": str(input_path),
        "additional_source": str(uniqlo_samples_path) if uniqlo_samples_path else None,
        "survey_product_count": 300,
        "platform_product_samples": dict(sorted(product_counts.items())),
        "groups": groups,
    }


def markdown(result: dict) -> str:
    lines = [
        "# 플랫폼 상품 실측 기반 길이 분류 통계",
        "",
        f"- 원본 조사 상품: {result['survey_product_count']}개",
        f"- 분석 원본: `{result['source']}`",
        "- 단위: cm",
        "- 상품 하나가 사이즈 수만큼 과대표집되지 않도록 상품별 사이즈 중앙값을 표본 1개로 사용",
        "",
        "| 플랫폼 | 의류 | 성별 | 측정 방식 | 짧은 표본 | 짧은 중앙값 | 긴 표본 | 긴 중앙값 | 판정 경계 | 분리 여부 |",
        "|---|---|---|---|---:|---:|---:|---:|---:|---|",
    ]
    for group in result["groups"]:
        lines.append(
            f"| {group['platform']} | {group['garment']} | {group['gender']} | "
            f"{group['method']} | {group['short']['count']} | {group['short']['median']} | "
            f"{group['long']['count']} | {group['long']['median']} | "
            f"{group['boundary_cm']} | {'명확' if group['separated'] else '겹침'} |"
        )
    lines.extend([
        "",
        "## 적용 원칙",
        "",
        "1. 플랫폼 원본 카테고리나 상품명에 길이가 명시되면 그 값을 우선한다.",
        "2. 명시가 없을 때만 플랫폼·성별·측정 방식에 맞는 경계를 사용한다.",
        "3. 해당 세부 그룹의 양쪽 표본이 부족하면 플랫폼 통합 또는 FitMatch 보수 기준을 사용한다.",
        "4. 민소매는 소매값 부재만으로 확정하지 않고 명시적 분류를 요구한다.",
        "5. 키즈·베이비는 별도 표본 기준을 사용하며 성인 절대 길이 기준을 재사용하지 않는다.",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--markdown-output", type=Path, required=True)
    parser.add_argument("--uniqlo-samples", type=Path)
    args = parser.parse_args()
    result = derive(args.input, args.uniqlo_samples)
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.markdown_output.write_text(markdown(result), encoding="utf-8")


if __name__ == "__main__":
    main()
