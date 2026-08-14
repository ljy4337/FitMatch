#!/usr/bin/env python3
"""Build one-run official product/comparison evidence from an xcodebuild log."""

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path


PRODUCT_PREFIX = "OFFICIAL_PRODUCT_RECORD "
COMPARISON_PREFIX = "OFFICIAL_COMPARISON_RECORD "


def read_records(log_path: Path, prefix: str) -> list[dict]:
    records: list[dict] = []
    text = log_path.read_bytes().replace(b"\x00", b"").decode("utf-8", errors="replace")
    for line in text.splitlines():
        if line.startswith(prefix):
            records.append(json.loads(line[len(prefix) :]))
    return records


def without_audit(record: dict) -> dict:
    return {key: value for key, value in record.items() if key != "audit"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--xcresult-summary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    product_records = read_records(args.log, PRODUCT_PREFIX)
    combinations = read_records(args.log, COMPARISON_PREFIX)
    xcresult = json.loads(args.xcresult_summary.read_text(encoding="utf-8"))

    products_by_identity: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for record in product_records:
        products_by_identity[(record["source"], record["productID"])].append(record)

    inconsistencies: list[dict] = []
    products: list[dict] = []
    for identity, variants in sorted(products_by_identity.items()):
        signatures = {
            json.dumps(without_audit(record), ensure_ascii=False, sort_keys=True)
            for record in variants
        }
        if len(signatures) != 1:
            inconsistencies.append(
                {"source": identity[0], "product_id": identity[1], "records": variants}
            )
        product = without_audit(variants[0])
        product["audits"] = sorted(record["audit"] for record in variants)
        products.append(product)

    audits = Counter(record["audit"] for record in product_records)
    comparison_audits = Counter(record["audit"] for record in combinations)
    loaded = [record for record in products if record["parsingSucceeded"]]
    failures = [record for record in products if not record["parsingSucceeded"]]
    confirmation_required = [
        record for record in products if record.get("userConfirmationRequired")
    ]
    direct = sum(bool(record["directComparisonAvailable"]) for record in combinations)
    base_extended = sum(
        bool(record["baseExtendedComparisonAvailable"]) for record in combinations
    )
    manual_extended = sum(
        bool(record["manualExtendedComparisonAvailable"]) for record in combinations
    )
    blocked = len(combinations) - direct - base_extended - manual_extended
    recommendation_failures = sum(
        not record["recommendationGenerated"]
        for record in combinations
        if record["directComparisonAvailable"]
        or record["baseExtendedComparisonAvailable"]
        or record["manualExtendedComparisonAvailable"]
    )
    recovery_failures = sum(
        not record["recoveryPathAvailable"] for record in combinations
    )
    sweatshirts = {
        record["productID"]: {
            "final_category_code": record.get("finalCategoryCode"),
            "final_detail_code": record.get("finalDetailCode"),
            "parsed_detail": record.get("parsedDetail"),
        }
        for record in products
        if record["productID"] in {"2080488", "2738737"}
    }
    sweatshirt_gate_passed = len(sweatshirts) == 2 and all(
        value["final_category_code"] == "tops"
        and value["final_detail_code"] == "sweatshirt"
        for value in sweatshirts.values()
    )

    summary = {
        "run_id": args.run_id,
        "source_log": str(args.log),
        "source_log_sha256": sha256(args.log),
        "xcresult": xcresult,
        "actual_test_count": xcresult.get("totalTestCount"),
        "actual_passed_tests": xcresult.get("passedTests"),
        "actual_failed_tests": xcresult.get("failedTests"),
        "actual_skipped_tests": xcresult.get("skippedTests"),
        "raw_product_record_count": len(product_records),
        "unique_product_count": len(products),
        "product_records_per_audit": dict(sorted(audits.items())),
        "loaded_product_count": len(loaded),
        "parse_failure_count": len(failures),
        "parse_failure_product_ids": [record["productID"] for record in failures],
        "user_confirmation_required_count": len(confirmation_required),
        "cross_audit_product_inconsistency_count": len(inconsistencies),
        "combination_count": len(combinations),
        "combination_records_per_audit": dict(sorted(comparison_audits.items())),
        "direct_comparison_count": direct,
        "base_extended_comparison_count": base_extended,
        "manual_extended_comparison_count": manual_extended,
        "blocked_comparison_count": blocked,
        "automatic_candidate_pair_count": sum(
            bool(record["automaticCandidateAvailable"]) for record in combinations
        ),
        "automatically_selected_reference_pair_count": sum(
            bool(record["automaticallySelectedReference"]) for record in combinations
        ),
        "reference_selection_required_pair_count": sum(
            bool(record["referenceSelectionRequired"]) for record in combinations
        ),
        "recommendation_failure_count": recommendation_failures,
        "recovery_path_failure_count": recovery_failures,
        "unavailable_reason_counts": dict(
            sorted(
                Counter(
                    record.get("unavailableReason") or "comparison_available"
                    for record in combinations
                ).items()
            )
        ),
        "sweatshirt_regression_products": sweatshirts,
        "sweatshirt_regression_gate_passed": sweatshirt_gate_passed,
    }

    gates = {
        "two_tests_actually_executed": xcresult.get("totalTestCount") == 2,
        "all_tests_passed": xcresult.get("result") == "Passed"
        and xcresult.get("passedTests") == 2
        and xcresult.get("failedTests") == 0
        and xcresult.get("skippedTests") == 0,
        "all_71_manifest_products_recorded_twice": len(product_records) == 142
        and audits == {"MUSINSA_REFERENCE": 71, "UNIQLO_REFERENCE": 71},
        "all_71_unique_product_identities_recorded": len(products) == 71,
        "cross_audit_product_results_are_identical": not inconsistencies,
        "expected_70_loaded_and_one_parse_failure": len(loaded) == 70
        and len(failures) == 1
        and failures[0]["productID"] == "E488923",
        "all_3707_combinations_recorded": len(combinations) == 3_707,
        "all_allowed_comparisons_generated_recommendations": recommendation_failures == 0,
        "all_blocked_comparisons_have_recovery_paths": recovery_failures == 0,
        "two_sweatshirts_resolve_to_tops_sweatshirt": sweatshirt_gate_passed,
    }
    summary["gates"] = gates
    summary["all_gates_passed"] = all(gates.values())

    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "products.json").write_text(
        json.dumps(products, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (args.output / "combinations.json").write_text(
        json.dumps(combinations, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (args.output / "product-inconsistencies.json").write_text(
        json.dumps(inconsistencies, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (args.output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    report = [
        "# Official 71-product current-production validation",
        "",
        f"- Run ID: `{args.run_id}`",
        f"- Actual XCTest execution: {xcresult.get('totalTestCount')} total, "
        f"{xcresult.get('passedTests')} passed, {xcresult.get('failedTests')} failed, "
        f"{xcresult.get('skippedTests')} skipped",
        f"- Manifest products: {len(products)} unique; {len(loaded)} loaded; "
        f"{len(failures)} parse failure",
        f"- Comparison pairs: {len(combinations):,}",
        f"- Direct: {direct:,}; base extended: {base_extended:,}; "
        f"manual extended: {manual_extended:,}; blocked: {blocked:,}",
        f"- Recommendation failures after an allowed comparison: {recommendation_failures}",
        f"- Missing recovery paths: {recovery_failures}",
        f"- Cross-audit product inconsistencies: {len(inconsistencies)}",
        f"- Sweatshirt regression gate: {'PASS' if sweatshirt_gate_passed else 'FAIL'}",
        f"- All evidence gates: {'PASS' if summary['all_gates_passed'] else 'FAIL'}",
        "",
        "`E488923` remains the single parse failure because the current production "
        "parser cannot load its baby-size table format; it is not counted as a loaded product.",
    ]
    (args.output / "report.md").write_text("\n".join(report) + "\n", encoding="utf-8")

    print(json.dumps({"all_gates_passed": summary["all_gates_passed"], **gates}, indent=2))
    if not summary["all_gates_passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
