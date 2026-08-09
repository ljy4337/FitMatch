#!/usr/bin/env python3
"""Build a deterministic, risk-weighted human review set from actual FitMatch pairs."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RESEARCH = ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806"
DEFAULT_OUTPUT = ROOT / "Docs/Research/FitPairHumanReview-20260806"


def load_json(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def stable_key(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def count_by(rows: list[dict], field: str) -> dict[str, int]:
    return dict(sorted(Counter(str(row.get(field, "unknown")) for row in rows).items()))


def review_template() -> dict:
    return {
        "category_compatibility": None,
        "measurement_semantics_correct": None,
        "signed_differences_correct": None,
        "reliability_label_appropriate": None,
        "overall_result_acceptable": None,
        "reviewer": None,
        "reviewed_at": None,
        "notes": None,
    }


def app_service_group(category_code: str) -> str:
    """Mirror ClothingCategory.fromTaxonomyCode(...).serviceGroup.taxonomyCode."""
    if category_code == "tops":
        return "tops"
    if category_code in {"bottoms", "leggings", "skirts"}:
        return "bottoms"
    if category_code == "outerwear":
        return "outerwear"
    if category_code == "dresses":
        return "dresses"
    if category_code == "underwear":
        return "underwear"
    if category_code == "shoes":
        return "shoes"
    if category_code == "accessories":
        return "accessories"
    return "other"


def enrich_pair(pair: dict, provider: str, classifications: dict[tuple[str, str], dict]) -> dict:
    comparison_id = str(pair["comparison_product_id"])
    reference_id = str(pair["reference_product_id"])
    comparison = classifications.get((provider, comparison_id), {})
    reference = classifications.get((provider, reference_id), {})
    comparison_detail = comparison.get("detail_code", pair.get("detail_code", "unknown"))
    reference_detail = reference.get("detail_code", "unknown")
    comparison_semantic_category = comparison.get(
        "category_code", pair.get("comparison_category_code", pair.get("category_code", "unknown"))
    )
    reference_semantic_category = reference.get(
        "category_code", pair.get("reference_category_code", "unknown")
    )
    comparison_category = pair.get(
        "comparison_category_code", app_service_group(comparison_semantic_category)
    )
    reference_category = pair.get(
        "reference_category_code", app_service_group(reference_semantic_category)
    )
    pair_id = f"{provider}:{reference_id}:{comparison_id}"

    risk_flags: list[str] = []
    if pair.get("status") != "confirmed":
        risk_flags.append("insufficient_evidence")
    if comparison_category != reference_category:
        risk_flags.append("major_category_mismatch")
    if comparison_detail != reference_detail:
        risk_flags.append("detail_category_mismatch")
    if pair.get("reliability") == "높은 신뢰도" and comparison_detail != reference_detail:
        risk_flags.append("high_reliability_cross_detail")
    if float(pair.get("coverage", 0)) < 0.75:
        risk_flags.append("low_coverage")
    if int(pair.get("score", 0)) <= 20:
        risk_flags.append("very_low_score")
    if int(pair.get("score", 0)) >= 90:
        risk_flags.append("very_high_score")
    if any(abs(float(item.get("signed_difference_cm", 0))) >= 20 for item in pair.get("compared_items", [])):
        risk_flags.append("large_measurement_difference")

    result = dict(pair)
    result.update({
        "pair_id": pair_id,
        "provider": provider,
        "comparison_semantic_category_code": comparison_semantic_category,
        "comparison_category_code": comparison_category,
        "comparison_detail_code": comparison_detail,
        "reference_semantic_category_code": reference_semantic_category,
        "reference_category_code": reference_category,
        "reference_detail_code": reference_detail,
        "category_match": comparison_category == reference_category,
        "detail_match": comparison_detail == reference_detail,
        "risk_flags": risk_flags,
        "risk_score": len(risk_flags),
        "review": review_template(),
    })
    return result


def select_stratified(rows: list[dict], target: int) -> list[dict]:
    if target >= len(rows):
        return sorted(rows, key=lambda row: row["pair_id"])

    selected: list[dict] = []
    selected_ids: set[str] = set()

    def add(row: dict) -> None:
        if row["pair_id"] not in selected_ids and len(selected) < target:
            selected.append(row)
            selected_ids.add(row["pair_id"])

    for row in sorted(rows, key=lambda item: (-item["risk_score"], stable_key(item["pair_id"]))):
        if row["status"] != "confirmed":
            add(row)

    groups: dict[tuple[str, ...], list[dict]] = defaultdict(list)
    for row in rows:
        key = (
            row["category_code"],
            row["comparison_detail_code"],
            row["reliability"],
            row["status"],
            str(row["detail_match"]),
        )
        groups[key].append(row)
    for values in groups.values():
        values.sort(key=lambda item: (-item["risk_score"], stable_key(item["pair_id"])))

    ordered_keys = sorted(groups, key=lambda key: stable_key("|".join(key)))
    index = 0
    while len(selected) < target:
        added = False
        for key in ordered_keys:
            values = groups[key]
            if index < len(values):
                before = len(selected)
                add(values[index])
                added = added or len(selected) > before
                if len(selected) == target:
                    break
        if not added and all(index + 1 >= len(values) for values in groups.values()):
            break
        index += 1

    if len(selected) < target:
        for row in sorted(rows, key=lambda item: (-item["risk_score"], stable_key(item["pair_id"]))):
            add(row)

    return sorted(selected, key=lambda row: (row["provider"], row["category_code"], row["pair_id"]))


def markdown_summary(all_rows: list[dict], candidates: list[dict]) -> str:
    category_mismatch_count = sum(not row["category_match"] for row in all_rows)
    mismatch_count = sum(not row["detail_match"] for row in all_rows)
    high_cross_detail = sum(
        row["reliability"] == "높은 신뢰도" and not row["detail_match"] for row in all_rows
    )
    lines = [
        "# 실제 핏 쌍 사람 검수 후보셋",
        "",
        f"생성일: {date.today().isoformat()}",
        "",
        "이 파일은 정답이 확정된 골드셋이 아니라 사람이 독립 판정할 후보셋이다. 앱 엔진 출력은 참고 열로만 사용하며, `review`의 다섯 판정값을 먼저 기록한 뒤 집계한다.",
        "",
        "## 전체 실제 쌍",
        "",
        f"- 전체: {len(all_rows):,}쌍",
        f"- 공급사: {count_by(all_rows, 'provider')}",
        f"- 카테고리: {count_by(all_rows, 'category_code')}",
        f"- 신뢰도: {count_by(all_rows, 'reliability')}",
        f"- 앱 대분류가 다른 쌍: {category_mismatch_count:,}쌍",
        f"- 세부 카테고리가 다른 호환 쌍: {mismatch_count:,}쌍",
        f"- 높은 신뢰도이면서 세부 카테고리가 다른 쌍: {high_cross_detail:,}쌍",
        "",
        "## 검수 후보",
        "",
        f"- 후보: {len(candidates):,}쌍",
        f"- 공급사: {count_by(candidates, 'provider')}",
        f"- 카테고리: {count_by(candidates, 'category_code')}",
        f"- 신뢰도: {count_by(candidates, 'reliability')}",
        "- 무신사 150쌍, 유니클로 50쌍을 공급사·대분류·세부분류·신뢰도·확정 상태·세부 일치 여부로 층화했다.",
        "- 근거 부족, 세부 불일치, 낮은 커버리지, 극단 점수, 20cm 이상 차이를 우선 포함했다.",
        "",
        "## 검수 방법",
        "",
        "```bash",
        "python3 scripts/review-fit-pair-candidates.py --summary",
        "python3 scripts/review-fit-pair-candidates.py --reviewer \"검수자 이름\"",
        "```",
        "",
        "- 한 번에 일부만 검수하려면 `--limit 20`을 붙인다.",
        "- 각 판정은 즉시 후보 JSON에 저장되므로 중간에 종료해도 이어서 진행할 수 있다.",
        "- 후보셋을 다시 생성해도 완료된 동일 `pair_id`의 판정은 보존된다.",
        "- 다섯 항목이 모두 맞으면 `y` 한 번으로 통과 처리하고, 하나라도 의심되면 `n`을 눌러 항목별로 판정한다.",
        "",
        "## 출시 판정 규칙",
        "",
        "1. `category_compatibility`, `measurement_semantics_correct`, `signed_differences_correct`는 오류 0건이어야 한다.",
        "2. `높은 신뢰도` 표본의 `reliability_label_appropriate` 오류는 0건이어야 한다.",
        f"3. 오류가 하나라도 나오면 해당 규칙·동일 계층 전체를 수정한 뒤 {len(all_rows):,}쌍 전체 회귀와 신규 독립 표본 재검수를 수행한다.",
        "4. 사람 판정이 모두 채워지기 전에는 이 후보셋을 정확도 수치나 골드셋으로 부르지 않는다.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--research-dir", type=Path, default=DEFAULT_RESEARCH)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--musinsa-target", type=int, default=150)
    parser.add_argument("--uniqlo-target", type=int, default=50)
    args = parser.parse_args()

    classifications = {
        (str(row["source"]), str(row["product_id"])): row
        for row in load_json(args.research_dir / "swift_production_classification_results_cumulative_2560.json")
    }
    musinsa = [
        enrich_pair(row, "musinsa", classifications)
        for row in load_json(args.research_dir / "musinsa_actual_measurement_pair_results_914.json")
    ]
    uniqlo = [
        enrich_pair(row, "uniqlo", classifications)
        for row in load_json(args.research_dir / "uniqlo_actual_measurement_pair_results.json")
    ]
    all_rows = musinsa + uniqlo
    candidates = select_stratified(musinsa, args.musinsa_target) + select_stratified(
        uniqlo, args.uniqlo_target
    )
    candidates.sort(key=lambda row: (row["provider"], row["category_code"], row["pair_id"]))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    candidate_path = args.output_dir / "fit_pair_human_review_candidates_200.json"
    existing_reviews: dict[str, dict] = {}
    if candidate_path.exists():
        existing_payload = load_json(candidate_path)
        existing_reviews = {
            str(row["pair_id"]): row["review"]
            for row in existing_payload.get("pairs", [])
            if row.get("pair_id")
            and row.get("review", {}).get("overall_result_acceptable") is not None
        }
    for row in candidates:
        if row["pair_id"] in existing_reviews:
            row["review"] = existing_reviews[row["pair_id"]]

    all_payload = {
        "meta": {
            "created_at": date.today().isoformat(),
            "status": "unlabeled_actual_pair_corpus",
            "pair_count": len(all_rows),
            "provider_counts": count_by(all_rows, "provider"),
        },
        "pairs": all_rows,
    }
    candidate_payload = {
        "meta": {
            "created_at": date.today().isoformat(),
            "status": "human_review_required_not_gold",
            "pair_count": len(candidates),
            "provider_counts": count_by(candidates, "provider"),
            "allowed_review_values": [True, False],
        },
        "pairs": candidates,
    }
    (args.output_dir / "actual_fit_pairs_enriched.json").write_text(
        json.dumps(all_payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    candidate_path.write_text(
        json.dumps(candidate_payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (args.output_dir / "README.md").write_text(
        markdown_summary(all_rows, candidates), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
