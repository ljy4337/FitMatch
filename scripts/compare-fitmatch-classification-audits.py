#!/usr/bin/env python3
"""Compare two local FitMatch classification fixture audit CSV files."""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path


TUPLE_FIELDS = (
    "garment_type_code",
    "sleeve_length_code",
    "lower_length_code",
    "body_length_code",
    "audience_code",
    "product_structure_code",
    "comparison_measurement_contract",
)


def read_rows(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {row["fixture_index"]: row for row in csv.DictReader(handle)}


def tuple_value(row: dict[str, str]) -> dict[str, str]:
    return {field: row.get(field, "") for field in TUPLE_FIELDS}


def product_summary(row: dict[str, str]) -> dict[str, object]:
    return {
        "fixture_index": int(row["fixture_index"]),
        "source": row.get("source_code"),
        "source_product_key": row.get("source_product_key"),
        "product_name": row.get("product_name"),
        "status": row.get("classification_status"),
        "tuple": tuple_value(row),
        "reason_codes": json.loads(row.get("reason_codes") or "[]"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    before = read_rows(args.before)
    after = read_rows(args.after)
    missing_after = sorted(set(before) - set(after), key=int)
    added_after = sorted(set(after) - set(before), key=int)

    transitions: Counter[str] = Counter()
    review_to_confirmed: list[dict[str, object]] = []
    review_to_not_applicable: list[dict[str, object]] = []
    confirmed_tuple_changes: list[dict[str, object]] = []
    confirmed_regressions: list[dict[str, object]] = []
    not_applicable_to_confirmed: list[dict[str, object]] = []
    errors: list[dict[str, object]] = []

    for fixture_index in sorted(set(before) & set(after), key=int):
        old = before[fixture_index]
        new = after[fixture_index]
        old_status = old.get("classification_status") or "ERROR"
        new_status = new.get("classification_status") or "ERROR"
        transitions[f"{old_status} -> {new_status}"] += 1

        change = {
            "before": product_summary(old),
            "after": product_summary(new),
        }
        if old.get("error_message") or new.get("error_message"):
            errors.append(change)
        if old_status == "REVIEW_REQUIRED" and new_status == "CONFIRMED":
            review_to_confirmed.append(change)
        if old_status == "REVIEW_REQUIRED" and new_status == "NOT_APPLICABLE":
            review_to_not_applicable.append(change)
        if old_status == "CONFIRMED" and new_status != "CONFIRMED":
            confirmed_regressions.append(change)
        if old_status == "CONFIRMED" and new_status == "CONFIRMED" and tuple_value(old) != tuple_value(new):
            confirmed_tuple_changes.append(change)
        if old_status == "NOT_APPLICABLE" and new_status == "CONFIRMED":
            not_applicable_to_confirmed.append(change)

    report = {
        "before_rows": len(before),
        "after_rows": len(after),
        "missing_after": missing_after,
        "added_after": added_after,
        "transitions": dict(sorted(transitions.items())),
        "review_to_confirmed": review_to_confirmed,
        "review_to_not_applicable": review_to_not_applicable,
        "confirmed_tuple_changes": confirmed_tuple_changes,
        "confirmed_regressions": confirmed_regressions,
        "not_applicable_to_confirmed": not_applicable_to_confirmed,
        "errors": errors,
        "safety_gate_passed": not any(
            (
                missing_after,
                added_after,
                confirmed_tuple_changes,
                confirmed_regressions,
                not_applicable_to_confirmed,
                errors,
            )
        ),
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0 if report["safety_gate_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
