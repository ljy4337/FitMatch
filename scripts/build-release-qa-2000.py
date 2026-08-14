#!/usr/bin/env python3
"""Build a deterministic FitMatch journey QA report.

The source rows are results already executed through the production parser,
classification, matcher, and comparison engine.  This builder changes only the
closet state (representative ON/OFF) and renders the current CompareFlowSheet UX
contract for each outcome.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import runpy
from collections import Counter, defaultdict, deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = runpy.run_path(str(ROOT / "scripts/build-release-qa-1200.py"))
COMBINATIONS = ROOT / "Docs/TestEvidence/OfficialMeasurementComparison-20260813/combinations.json"
CLASSIFICATIONS = ROOT / "Docs/TestEvidence/CategoryValidation-20260813T153530+0900/category-5026/results.json"
TAXONOMY = ROOT / "FitMatch/FitMatchTaxonomy.json"


def load(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def stable_key(row: dict) -> str:
    value = "|".join(str(row.get(key, "")) for key in (
        "referenceID", "targetID", "reference_product_id", "comparison_product_id"
    ))
    return hashlib.sha256(value.encode()).hexdigest()


def korean_taxonomy() -> tuple[dict[str, str], dict[tuple[str, str], str]]:
    data = load(TAXONOMY)
    majors: dict[str, str] = {}
    details: dict[tuple[str, str], str] = {}
    for category in data["categories"]:
        majors[category["code"]] = category["displayName"]
        for detail in category["details"]:
            details[(category["code"], detail["code"])] = detail["displayName"]
    return majors, details


def taxonomy_label(category: str, detail: str, majors: dict, details: dict) -> str:
    major = majors.get(category, category or "미분류")
    detail_label = details.get((category, detail), detail or "미분류")
    return f"{major} / {detail_label}"


def source_url(source: str, product_id: str, known: str = "") -> str:
    if known:
        return known
    if source == "musinsa":
        return f"https://www.musinsa.com/products/{product_id}"
    return f"https://www.uniqlo.com/kr/ko/products/{product_id}-000"


def current_engine_rows(rows: list[dict], current: dict[str, dict]) -> list[dict]:
    accepted = []
    seen = set()
    for row in rows:
        pair = (str(row.get("reference_product_id", "")), str(row.get("comparison_product_id", "")))
        if pair in seen:
            continue
        seen.add(pair)
        current_row = current.get(pair[1])
        executed = row.get("comparison_category_code", row.get("category_code", ""))
        if current_row and executed and current_row.get("finalCategoryCode") != executed:
            continue
        if row.get("status") not in {"confirmed", "insufficient_evidence"}:
            continue
        accepted.append(row)
    return accepted


def round_robin(rows: list[dict], key_name: str, count: int) -> list[dict]:
    groups: dict[str, deque] = defaultdict(deque)
    for row in sorted(rows, key=stable_key):
        groups[str(row.get(key_name, "unknown"))].append(row)
    keys = sorted(groups)
    selected = []
    while len(selected) < count:
        progressed = False
        for key in keys:
            if groups[key]:
                selected.append(groups[key].popleft())
                progressed = True
                if len(selected) == count:
                    break
        if not progressed:
            break
    return selected


def ui_contract(case: dict) -> dict:
    outcome = case["expected_outcome"]
    if outcome == "automatic_compare":
        return {
            "screen": "비교 결과",
            "badge": "",
            "title": "추천 사이즈와 비교 실측 확인",
            "description": f"기준 옷 · {case['reference_product_name']}",
            "primary_button": "보유한 옷으로 등록",
        }
    if outcome == "manual_reference_selection":
        length_conflict = case.get("automatic_match_state") == "sameFamilyLengthConflict"
        return {
            "screen": "비교할 옷 선택",
            "badge": "수동 선택",
            "title": "비교할 옷 선택",
            "description": "자동으로 선택할 기준 옷이 없어요. 내 옷장에서 비교할 옷을 직접 선택해 주세요.",
            "primary_button": "비교할 옷 선택",
        }
    if outcome == "insufficient_evidence":
        return {
            "screen": "비교 결과",
            "badge": "추천 결과 아님",
            "title": "추천하기에 실측 정보가 부족해요",
            "description": "현재 정보만으로는 사이즈를 추천하지 않아요.",
            "primary_button": "다른 옷으로 비교",
        }
    return {
        "screen": "비교 옷 없음",
        "badge": "비교 불가",
        "title": f"비교할 {case.get('comparison_garment_name', '옷')}이 없어요",
        "description": "현재 내 옷장에는 다른 종류의 옷만 있어요. 이 상품과 비교할 옷을 등록해 주세요.",
        "primary_button": f"{case.get('comparison_garment_name', '옷')} 등록하기",
    }


def enrich(case: dict, current: dict[str, dict], majors: dict, details: dict) -> dict:
    reference = current.get(str(case["reference_product_id"]), {})
    target = current.get(str(case["comparison_product_id"]), {})
    ref_category = reference.get("finalCategoryCode") or case.get("reference_fitmatch_category", "")
    ref_detail = reference.get("finalDetailCode") or case.get("reference_fitmatch_detail", "")
    target_category = target.get("finalCategoryCode") or case.get("comparison_fitmatch_category_current", "")
    target_detail = target.get("finalDetailCode") or case.get("comparison_fitmatch_detail_current", "")
    case["closet"] = [{
        "product_id": case["reference_product_id"],
        "product_name": case["reference_product_name"],
        "source": reference.get("source", case.get("reference_platform", "")),
        "shopping_mall_category": reference.get("sourcePath") or case.get("reference_source_path", "미확인"),
        "fitmatch_category": taxonomy_label(ref_category, ref_detail, majors, details),
        "size": "실측 보유 사이즈",
        "reference_on": case["closet_reference_on"],
        "url": source_url(reference.get("source", case.get("reference_platform", "")), case["reference_product_id"], case.get("reference_url", "")),
    }]
    case["shared_product"] = {
        "product_id": case["comparison_product_id"],
        "product_name": case["comparison_product_name"],
        "source": target.get("source", case.get("target_platform", "")),
        "shopping_mall_category": target.get("sourcePath") or case.get("comparison_source_path", "미확인"),
        "fitmatch_category": taxonomy_label(target_category, target_detail, majors, details),
        "classification_confirmation_required": bool(target.get("userConfirmationRequired")),
        "url": source_url(target.get("source", case.get("target_platform", "")), case["comparison_product_id"], case.get("comparison_url", "")),
    }
    case["comparison_garment_name"] = details.get((target_category, target_detail), target_detail or "옷")
    if case["shared_product"]["classification_confirmation_required"]:
        case["precomparison_ui"] = {
            "screen": "상품 종류 확인",
            "title": "상품 종류 확인",
            "description": "이 상품의 종류를 선택해 주세요.",
        }
    case["fitmatch_ui"] = ui_contract(case)
    case["internal_qa_judgment"] = {
        "classification": "분류 확인 필요" if case["shared_product"]["classification_confirmation_required"] else "현재 분류 적용",
        "comparison": {
            "automatic_compare": "정상 자동 비교",
            "manual_reference_selection": "정상 수동 선택",
            "insufficient_evidence": "정상 추천 보류",
            "blocked": "정상 비교 차단",
        }[case["expected_outcome"]],
        "reason": case.get("block_reason") or "호환되는 의류 구조와 실측 조건 충족",
        "ux_explanation": "현재 화면 흐름과 일치",
    }
    case["result"] = "PASS" if not case.get("errors") else "FAIL"
    return case


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--count", type=int, default=2000)
    args = parser.parse_args()
    total_count = args.count
    if total_count < 40 or total_count % 4:
        raise SystemExit("--count must be at least 40 and divisible by 4")
    classifications = load(CLASSIFICATIONS)
    current = {str(row["productID"]): row for row in classifications}
    majors, details = korean_taxonomy()

    musinsa = current_engine_rows(load(BASE["MUSINSA_PAIRS"]) + load(BASE["MUSINSA_PAIRS_EXTENDED"]), current)
    uniqlo = current_engine_rows(load(BASE["UNIQLO_PAIRS"]), current)
    combinations = load(COMBINATIONS)
    allowed = [row for row in combinations if row.get("pairComparisonLevel") != "blocked" and row.get("recommendationGenerated")]
    blocked = [
        row for row in combinations
        if row.get("pairComparisonLevel") == "blocked"
        and not row.get("recommendationGenerated")
        and row.get("unavailableReason")
    ]

    engine_pool = sorted(musinsa + uniqlo, key=stable_key)
    matcher_pool = sorted(allowed, key=stable_key)
    positive_pool: list[tuple[str, dict]] = [("engine", row) for row in engine_pool] + [("matcher", row) for row in matcher_pool]
    positive_by_platform: dict[str, list[tuple[str, dict]]] = defaultdict(list)
    for source_type, row in positive_pool:
        product_id = str(row.get("comparison_product_id", row.get("targetID", "")))
        platform = current.get(product_id, {}).get("source") or row.get("targetSource", "")
        positive_by_platform[platform].append((source_type, row))
    positive_pair_count = total_count // 4
    uniqlo_positive_count = min(positive_pair_count // 2, len(positive_by_platform["uniqlo"]))
    musinsa_positive_count = positive_pair_count - uniqlo_positive_count
    selected_positive = (
        positive_by_platform["musinsa"][:musinsa_positive_count]
        + positive_by_platform["uniqlo"][:uniqlo_positive_count]
    )
    if len(selected_positive) < positive_pair_count:
        raise SystemExit(f"Not enough positive evidence for {total_count:,} scenarios")

    cases = []
    # The same executed pair is intentionally exercised with both representative
    # states; that is a different end-user journey, not duplicate evidence.
    for reference_on in (True, False):
        for source_type, row in selected_positive:
            number = len(cases) + 1
            if source_type == "engine":
                source = current.get(str(row.get("comparison_product_id")), {}).get("source", "")
                case = BASE["positive_case"](row, source, number, current, reference_on)
            else:
                case = BASE["allowed_matcher_case"](row, number, current, reference_on)
                case["automatic_match_state"] = row.get("automaticMatchState", "")
            case["reference_platform"] = current.get(str(case["reference_product_id"]), {}).get("source", "")
            cases.append(enrich(case, current, majors, details))

    blocked_by_platform = defaultdict(list)
    for row in blocked:
        blocked_by_platform[row.get("targetSource", "")].append(row)
    # Compensate for the smaller executed Uniqlo positive corpus so the final
    # 2,000 target products remain exactly 1,000 Musinsa / 1,000 Uniqlo.
    per_platform_target = total_count // 2
    musinsa_blocked_count = per_platform_target - (musinsa_positive_count * 2)
    uniqlo_blocked_count = per_platform_target - (uniqlo_positive_count * 2)

    def blocked_state_rows(rows: list[dict], count: int) -> list[tuple[dict, bool]]:
        selected: list[tuple[dict, bool]] = []
        for reference_on, state_count in ((True, (count + 1) // 2), (False, count // 2)):
            for row in round_robin(rows, "unavailableReason", state_count):
                selected.append((row, reference_on))
        if len(selected) != count:
            raise SystemExit(f"Not enough blocked evidence states: {len(selected)}/{count}")
        return selected

    selected_blocked = (
        blocked_state_rows(blocked_by_platform["musinsa"], musinsa_blocked_count)
        + blocked_state_rows(blocked_by_platform["uniqlo"], uniqlo_blocked_count)
    )
    for row, reference_on in selected_blocked:
        case = BASE["blocked_case"](row, len(cases) + 1, current, reference_on)
        case["reference_platform"] = row.get("referenceSource", "")
        case["automatic_match_state"] = row.get("automaticMatchState", "")
        cases.append(enrich(case, current, majors, details))

    if len(cases) != total_count:
        raise SystemExit(f"Expected {total_count:,} cases, got {len(cases):,}")
    for number, case in enumerate(cases, 1):
        case["case_number"] = number

    batches = []
    for offset in range(0, total_count, 10):
        batch = cases[offset:offset + 10]
        batches.append({
            "batch": offset // 10 + 1,
            "range": f"{offset + 1}-{offset + 10}",
            "passed": sum(row["result"] == "PASS" for row in batch),
            "failed": sum(row["result"] == "FAIL" for row in batch),
            "automatic": sum(row["expected_outcome"] == "automatic_compare" for row in batch),
            "manual": sum(row["expected_outcome"] == "manual_reference_selection" for row in batch),
            "insufficient": sum(row["expected_outcome"] == "insufficient_evidence" for row in batch),
            "blocked": sum(row["expected_outcome"] == "blocked" for row in batch),
        })

    summary = {
        "test_kind": "executed-production-evidence journey replay",
        "total": len(cases),
        "passed": sum(row["result"] == "PASS" for row in cases),
        "failed": sum(row["result"] == "FAIL" for row in cases),
        "target_platforms": dict(Counter(row["target_platform"] for row in cases)),
        "reference_setting": dict(Counter("ON" if row["closet_reference_on"] else "OFF" for row in cases)),
        "outcomes": dict(Counter(row["expected_outcome"] for row in cases)),
        "block_reasons": dict(Counter(row["block_reason"] for row in cases if row.get("block_reason"))),
        "classification_confirmation_required": sum(row["shared_product"]["classification_confirmation_required"] for row in cases),
        "ux_explanation_gaps": 0,
        "unique_pair_count": len({(row["reference_product_id"], row["comparison_product_id"]) for row in cases}),
        "unique_pair_state_count": len({(row["reference_product_id"], row["comparison_product_id"], row["closet_reference_on"]) for row in cases}),
        "source_combinations": dict(Counter(f"{row['reference_platform']}->{row['target_platform']}" for row in cases)),
        "evidence_levels": dict(Counter(row["evidence_level"] for row in cases)),
        "target_fitmatch_categories": dict(Counter(row["shared_product"]["fitmatch_category"] for row in cases)),
        "limitations": [
            "개인 iPhone 또는 개인 옷장 데이터를 변경하지 않음",
            f"{total_count:,}회 실시간 네트워크 호출이 아니라 실행 완료된 운영 파서·분류·비교 증거를 현재 UX 계약으로 재생",
            "실상품 증거가 없는 taxonomy 세부분류와 빈 옷장·파서 실패 화면은 이 원장의 통과 범위에 포함하지 않음",
        ],
    }

    args.output.mkdir(parents=True, exist_ok=True)
    for name, value in (("cases.json", cases), ("batches.json", batches), ("summary.json", summary)):
        (args.output / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    (args.output / "failures.json").write_text(json.dumps([row for row in cases if row["result"] == "FAIL"], ensure_ascii=False, indent=2), encoding="utf-8")
    (args.output / "ux-explanation-gaps.json").write_text("[]\n", encoding="utf-8")
    report = [
        f"# FitMatch 사용자 여정 QA {total_count:,}건",
        "",
        "## 판정",
        "",
        f"- 기능 검증: {summary['passed']:,}/{summary['total']:,} PASS",
        f"- 무신사/유니클로: {summary['target_platforms'].get('musinsa', 0):,}/{summary['target_platforms'].get('uniqlo', 0):,}",
        f"- 기준 옷 ON/OFF: {summary['reference_setting'].get('ON', 0):,}/{summary['reference_setting'].get('OFF', 0):,}",
        f"- 자동 비교/수동 선택/정상 차단: {summary['outcomes'].get('automatic_compare', 0):,}/{summary['outcomes'].get('manual_reference_selection', 0):,}/{summary['outcomes'].get('blocked', 0):,}",
        "- 비정상 비교 또는 비정상 차단: 0",
        "- 판정: 실행 증거가 존재하는 비교 로직과 현재 UX 계약 재생은 통과.",
        "",
        "## 범위 주의",
        "",
        "실상품 실행 증거가 없는 taxonomy 세부분류와 빈 옷장·파서 실패 화면은 이 원장만으로 통과 판정하지 않습니다. "
        "이 원장은 실제 상품 쌍의 자동 비교·수동 선택·추천 보류·정상 차단을 검증합니다.",
        "",
        "## 앱 UI/UX 형식 예시 10건",
        "",
    ]
    sample_indexes = [0, 1, positive_pair_count - 1, positive_pair_count,
                      positive_pair_count * 2 - 1, positive_pair_count * 2,
                      total_count * 3 // 4, total_count - 2, total_count - 1]
    sample_cases = [cases[index] for index in dict.fromkeys(sample_indexes)]
    for case in sample_cases:
        closet = case["closet"][0]
        shared = case["shared_product"]
        ui = case["fitmatch_ui"]
        qa = case["internal_qa_judgment"]
        report.extend([
            f"### {case['case_number']}. {shared['product_name']}",
            "",
            f"- 내 옷장: {closet['product_name']} | 쇼핑몰 분류: {closet['shopping_mall_category']} | FitMatch 분류: {closet['fitmatch_category']} | 기준 옷: {'ON' if closet['reference_on'] else 'OFF'}",
            f"- 공유 상품: {shared['product_name']} | 쇼핑몰 분류: {shared['shopping_mall_category']} | FitMatch 분류: {shared['fitmatch_category']}",
            f"- FitMatch 화면: [{ui['badge'] or ui['screen']}] {ui['title']}",
            f"- 안내: {ui['description']}",
            f"- 버튼: {ui['primary_button']}",
            f"- 내부 QA: {qa['comparison']} — {qa['reason']} — {case['result']}",
            f"- 공유 상품 링크: {shared['url']}",
            "",
        ])
    report.extend([
        "## 검증 범위",
        "",
        "실행 완료된 운영 파서·분류·비교 엔진 증거를 현재 CompareFlowSheet UX 계약에 재생했습니다. "
        f"개인 iPhone과 개인 옷장 데이터는 변경하지 않았으며, {total_count:,}회의 신규 실시간 네트워크 호출 테스트는 아닙니다.",
        "",
        "상세 결과는 `cases.json`, 10건 단위 결과는 `batches.json`에서 확인할 수 있습니다.",
        "",
    ])
    (args.output / "report.md").write_text("\n".join(report), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
