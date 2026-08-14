#!/usr/bin/env python3
"""Interactively record independent human judgments for FitMatch pair candidates."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = (
    ROOT
    / "Docs/Research/FitPairHumanReview-20260806"
    / "fit_pair_human_review_candidates_200.json"
)

QUESTIONS = [
    ("category_compatibility", "두 상품의 의류 카테고리가 비교 가능한가?"),
    ("measurement_semantics_correct", "비교한 실측 항목의 의미가 서로 같은가?"),
    ("signed_differences_correct", "비교 상품-내 옷 차이의 방향과 수치가 맞는가?"),
    ("reliability_label_appropriate", "표시된 신뢰도 등급이 근거량에 적절한가?"),
    ("overall_result_acceptable", "사용자에게 이 결과를 보여줘도 되는가?"),
]


def load_payload(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload.get("pairs"), list):
        raise ValueError(f"검수 후보 배열이 없습니다: {path}")
    return payload


def is_reviewed(pair: dict) -> bool:
    return pair.get("review", {}).get("overall_result_acceptable") is not None


def save_payload(path: Path, payload: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def summary(payload: dict) -> str:
    pairs = payload["pairs"]
    reviewed = [pair for pair in pairs if is_reviewed(pair)]
    failures = Counter()
    for pair in reviewed:
        review = pair["review"]
        for key, _ in QUESTIONS:
            if review.get(key) is False:
                failures[key] += 1
    lines = [
        f"전체 {len(pairs)}쌍 / 완료 {len(reviewed)}쌍 / 남음 {len(pairs) - len(reviewed)}쌍",
        f"출시 불가 판정 {sum(pair['review']['overall_result_acceptable'] is False for pair in reviewed)}쌍",
    ]
    if failures:
        lines.append("실패 항목: " + ", ".join(f"{key} {count}건" for key, count in sorted(failures.items())))
    return "\n".join(lines)


def format_pair(pair: dict, index: int, total: int) -> str:
    measurements = []
    for item in pair.get("compared_items", []):
        measurements.append(
            "  - {title}: 내 옷 {reference:g}cm / 비교 {comparison:g}cm / 차이 {difference:+g}cm".format(
                title=item.get("display_title", item.get("kind", "실측")),
                reference=float(item.get("reference_value_cm", 0)),
                comparison=float(item.get("comparison_value_cm", 0)),
                difference=float(item.get("signed_difference_cm", 0)),
            )
        )
    return "\n".join(
        [
            "",
            "=" * 72,
            f"[{index}/{total}] {pair.get('pair_id', '-')}",
            f"내 옷: {pair.get('reference_product_name', '-')} / {pair.get('reference_size_name', '-')}",
            f"       {pair.get('reference_url', '-')}",
            f"비교:  {pair.get('comparison_product_name', '-')} / {pair.get('comparison_size_name', '-')}",
            f"       {pair.get('comparison_url', '-')}",
            (
                f"분류: {pair.get('category_code', '-')} / {pair.get('detail_code', '-')} | "
                f"점수 {pair.get('score', '-')} | {pair.get('reliability', '-')} | "
                f"상태 {pair.get('status', '-')}"
            ),
            "실측:",
            *(measurements or ["  - 비교 가능한 실측 없음"]),
            "위험 신호: " + (", ".join(pair.get("risk_flags", [])) or "없음"),
        ]
    )


def prompt_choice(prompt: str, choices: set[str]) -> str:
    while True:
        answer = input(prompt).strip().lower()
        if answer in choices:
            return answer
        print("입력값이 올바르지 않습니다: " + "/".join(sorted(choices)))


def review_pair(pair: dict, reviewer: str) -> str:
    quick = prompt_choice("다섯 판정이 모두 통과인가? [y/n, s=건너뜀, q=종료]: ", {"y", "n", "s", "q"})
    if quick in {"s", "q"}:
        return quick

    answers: dict[str, bool] = {}
    if quick == "y":
        answers = {key: True for key, _ in QUESTIONS}
    else:
        for key, question in QUESTIONS:
            answer = prompt_choice(f"{question} [y/n]: ", {"y", "n"})
            answers[key] = answer == "y"

    notes = input("메모(없으면 Enter): ").strip() or None
    pair.setdefault("review", {}).update(answers)
    pair["review"].update(
        {
            "reviewer": reviewer,
            "reviewed_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "notes": notes,
        }
    )
    return "saved"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--reviewer", help="검수자 이름")
    parser.add_argument("--summary", action="store_true", help="진행률만 표시")
    parser.add_argument("--limit", type=int, default=0, help="이번 실행에서 저장할 최대 건수(0=제한 없음)")
    args = parser.parse_args()

    payload = load_payload(args.input)
    if args.summary:
        print(summary(payload))
        return
    if not args.reviewer or not args.reviewer.strip():
        parser.error("검수 실행에는 --reviewer가 필요합니다.")

    pending = [pair for pair in payload["pairs"] if not is_reviewed(pair)]
    if not pending:
        print("모든 후보 검수가 완료되었습니다.")
        print(summary(payload))
        return

    saved = 0
    for offset, pair in enumerate(pending, start=1):
        print(format_pair(pair, len(payload["pairs"]) - len(pending) + offset, len(payload["pairs"])))
        action = review_pair(pair, args.reviewer.strip())
        if action == "q":
            break
        if action == "s":
            continue
        save_payload(args.input, payload)
        saved += 1
        print("저장했습니다.")
        if args.limit > 0 and saved >= args.limit:
            break

    print("\n" + summary(payload))


if __name__ == "__main__":
    main()
