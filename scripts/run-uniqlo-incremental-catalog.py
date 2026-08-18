#!/usr/bin/env python3
"""Discover the current UNIQLO KR catalog and collect only unseen products."""

from __future__ import annotations

import argparse
import csv
import fcntl
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from catalog_batch_common import SupabaseBatchClient, sync_payloads, uniqlo_payload


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = ROOT / "Docs/TestEvidence/CurrentUniqloCatalog-20260815/CurrentUniqloCatalogURLs.csv"
DEFAULT_UNAVAILABLE = ROOT / "Docs/TestEvidence/CurrentUniqloCatalog-20260815/CurrentUniqloCatalogUnavailableURLs.csv"
DEFAULT_STATE = ROOT / "Docs/TestEvidence/UniqloCatalogIncremental/state.json"
DEFAULT_RUN_ROOT = ROOT / "Docs/TestEvidence/UniqloCatalogIncremental/runs"
AUDIENCES = ("MEN", "WOMEN", "KIDS", "BABY")


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def core_id(value: str) -> str:
    return value.split("-")[0].upper()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, fields: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def initialize_state(baseline: Path, unavailable: Path) -> dict:
    created_at = now()
    products: dict[str, dict] = {}
    for row in read_csv(baseline):
        product_id = core_id(row["product_id"])
        entry = products.setdefault(product_id, {
            "status": "stored",
            "first_seen_at": created_at,
            "last_seen_at": created_at,
            "observed_ids": [],
            "product_name": row.get("product_name", ""),
            "canonical_url": row.get("canonical_product_url", ""),
        })
        observed = row.get("observed_id", "")
        if observed and observed not in entry["observed_ids"]:
            entry["observed_ids"].append(observed)
    for row in read_csv(unavailable):
        product_id = core_id(row["product_id"])
        products.setdefault(product_id, {
            "status": "known_unavailable",
            "first_seen_at": created_at,
            "last_seen_at": None,
            "observed_ids": [row["product_id"]],
            "product_name": "",
            "canonical_url": row.get("product_url", ""),
        })
    return {
        "version": 1,
        "source": "uniqlo_kr",
        "initialized_at": created_at,
        "baseline": str(baseline),
        "products": products,
        "last_run": None,
    }


def observations(checkpoint: Path) -> dict[str, dict]:
    state = read_json(checkpoint)
    result: dict[str, dict] = {}
    audience_states = state["sources"]["uniqlo"]["audiences"]
    for audience in AUDIENCES:
        for observed_id, exposure_urls in audience_states[audience]["discovered_products"].items():
            product_id = core_id(observed_id)
            entry = result.setdefault(product_id, {
                "product_id": product_id,
                "observed_ids": set(),
                "audiences": set(),
                "exposure_urls": set(),
            })
            entry["observed_ids"].add(observed_id)
            entry["audiences"].add(audience)
            entry["exposure_urls"].update(exposure_urls)
    return result


def run(command: list[str]) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--baseline-unavailable", type=Path, default=DEFAULT_UNAVAILABLE)
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--run-id", default=datetime.now().strftime("%Y%m%d-%H%M%S"))
    parser.add_argument("--checkpoint", type=Path, help="Use an existing discovery checkpoint without network crawling.")
    parser.add_argument("--no-fetch-new", action="store_true", help="Report deltas without downloading new details.")
    parser.add_argument(
        "--no-db-sync", action="store_true",
        help="Testing only: collect locally without trusted Supabase ingest/classification.",
    )
    parser.add_argument("--delay-ms", type=int, default=350)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument(
        "--category-retries",
        type=int,
        choices=range(0, 6),
        default=5,
        help="Retries for transient network errors and mismatched category responses.",
    )
    args = parser.parse_args()

    state_path = args.state.resolve()
    state_path.parent.mkdir(parents=True, exist_ok=True)
    lock_stream = state_path.with_name(state_path.name + ".lock").open("w")
    try:
        fcntl.flock(lock_stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit("같은 유니클로 증분 배치가 이미 실행 중입니다.")
    ledger = read_json(state_path) if state_path.is_file() else initialize_state(
        args.baseline.resolve(), args.baseline_unavailable.resolve()
    )
    run_dir = args.run_root.resolve() / args.run_id
    run_dir.mkdir(parents=True, exist_ok=False)

    if args.checkpoint:
        checkpoint = args.checkpoint.resolve()
    else:
        crawl_dir = run_dir / "discovery"
        run([
            sys.executable,
            str(ROOT / "scripts/category-corpus/corpus_collector.py"),
            "live", "--source", "uniqlo", "--output", str(crawl_dir),
            "--discovery-only", "--max-category-pages", "500",
            "--uniqlo-limit", "5000", "--uniqlo-men-limit", "5000",
            "--uniqlo-women-limit", "5000", "--uniqlo-kids-limit", "5000",
            "--uniqlo-baby-limit", "5000", "--delay-ms", str(args.delay_ms),
            "--retries", str(args.category_retries),
        ])
        checkpoint = crawl_dir / "checkpoint.json"

    current = observations(checkpoint)
    discovery_summary_path = checkpoint.parent / "discovery_summary.json"
    discovery_summary = read_json(discovery_summary_path) if discovery_summary_path.is_file() else {}
    discovery_complete = discovery_summary.get("discovery_complete", True)
    known_ids = set(ledger["products"])
    stored_ids = {
        product_id for product_id, item in ledger["products"].items()
        if item["status"] == "stored"
    }
    current_ids = set(current)
    newly_seen_ids = sorted(current_ids - stored_ids)
    not_seen_ids = sorted(stored_ids - current_ids) if discovery_complete else []
    db_client = None
    db_needing_ingest: set[str] = set()
    if not args.no_db_sync and not args.no_fetch_new:
        db_client = SupabaseBatchClient()
        db_needing_ingest = db_client.products_needing_ingest("uniqlo", sorted(current_ids))
    collection_target_ids = sorted(set(newly_seen_ids) | db_needing_ingest)

    discovery_rows = []
    for product_id in sorted(current):
        item = current[product_id]
        discovery_rows.append({
            "product_id": product_id,
            "is_newly_seen": product_id in newly_seen_ids,
            "observed_ids": ";".join(sorted(item["observed_ids"])),
            "audiences": ";".join(sorted(item["audiences"])),
            "exposure_urls": ";".join(sorted(item["exposure_urls"])),
        })
    write_csv(
        run_dir / "discovered_products.csv",
        ["product_id", "is_newly_seen", "observed_ids", "audiences", "exposure_urls"],
        discovery_rows,
    )
    write_csv(
        run_dir / "new_product_ids.csv",
        ["product_id", "observed_ids", "audiences", "exposure_urls"],
        [row for row in discovery_rows if row["is_newly_seen"]],
    )
    write_csv(
        run_dir / "missing_product_ids.csv",
        ["product_id", "last_seen_at", "product_name", "canonical_url"],
        [{"product_id": product_id, **ledger["products"][product_id]} for product_id in not_seen_ids],
    )

    collected_ids: set[str] = set()
    collection_dir = run_dir / "new_products"
    db_succeeded_ids: set[str] = set()
    db_rows: list[dict] = []
    if collection_target_ids and not args.no_fetch_new:
        baseline_manifest = run_dir / "known_product_manifest.json"
        write_json(baseline_manifest, {
            "products": [
                {"source": "uniqlo", "product_key": product_id}
                for product_id in sorted(current_ids - set(collection_target_ids))
            ]
        })
        run([
            sys.executable, str(ROOT / "scripts/collect-new-uniqlo-retest.py"),
            "--checkpoint", str(checkpoint), "--old-manifest", str(baseline_manifest),
            "--include-all-catalog-items", "--select-all-complete",
            "--attempt-limit", str(len(collection_target_ids)), "--workers", str(args.workers),
            "--delay-ms", str(args.delay_ms), "--output", str(collection_dir),
        ])
        manifest = read_json(collection_dir / "clothing_product_manifest.json")
        html_collected_ids = {item["product_key"] for item in manifest["products"]}
        if html_collected_ids:
            shutil.copy2(checkpoint, collection_dir / "checkpoint.json")
            run([
                sys.executable, str(ROOT / "scripts/collect-uniqlo-size-evidence.py"),
                "--corpus", str(collection_dir), "--delay-ms", str(args.delay_ms),
            ])
            run([
                sys.executable, str(ROOT / "scripts/build-current-uniqlo-a-test-inputs.py"),
                "--corpus", str(collection_dir),
                "--output-json", str(run_dir / "new_product_inputs.json"),
                "--output-urls", str(run_dir / "new_products.csv"),
            ])
            size_evidence = read_json(collection_dir / "uniqlo_size_evidence.json")
            size_complete_ids = {
                item["product_id"]
                for item in size_evidence["products_detail"]
                if item["result_found"]
            }
            collected_ids = html_collected_ids & size_complete_ids

        input_path = run_dir / "new_product_inputs.json"
        if input_path.is_file():
            raw_inputs = read_json(input_path)
            selected_inputs = [
                item for item in raw_inputs
                if str(item.get("product_id") or "") in set(collection_target_ids)
            ]
            if db_client is not None:
                db_succeeded_ids, db_rows = sync_payloads(
                    db_client,
                    (uniqlo_payload(item) for item in selected_inputs),
                    run_dir / "db_ingest_results.json",
                )
            else:
                db_succeeded_ids = {str(item["product_id"]) for item in selected_inputs}

    if db_client is not None:
        collected_ids &= db_succeeded_ids
    db_pending_ids = sorted(set(collection_target_ids) - db_succeeded_ids) if db_client is not None else []

    completed_at = now()
    for product_id in current_ids & known_ids:
        ledger["products"][product_id]["last_seen_at"] = completed_at
    product_rows = {
        row["product_id"]: row
        for row in read_csv(run_dir / "new_products.csv")
    }
    for product_id in collected_ids:
        item = current[product_id]
        ledger["products"][product_id] = {
            "status": "stored",
            "first_seen_at": completed_at,
            "last_seen_at": completed_at,
            "observed_ids": sorted(item["observed_ids"]),
            "product_name": product_rows.get(product_id, {}).get("product_name", ""),
            "canonical_url": f"https://www.uniqlo.com/kr/ko/products/{sorted(item['observed_ids'])[0]}",
        }

    summary = {
        "run_id": args.run_id,
        "completed_at": completed_at,
        "checkpoint": str(checkpoint),
        "known_before": len(known_ids),
        "currently_discovered": len(current_ids),
        "discovery_complete": discovery_complete,
        "category_response_mismatches": discovery_summary.get("category_response_mismatches", 0),
        "category_response_failures": discovery_summary.get("category_response_failures", 0),
        "newly_seen": len(newly_seen_ids),
        "db_needing_ingest": len(db_needing_ingest),
        "collection_targets": len(collection_target_ids),
        "newly_seen_detail_and_size_collected": len(collected_ids),
        "newly_seen_pending_retry": sorted(set(newly_seen_ids) - collected_ids),
        "db_ingest_succeeded": len(db_succeeded_ids) if db_client is not None else None,
        "db_ingest_failed": sum(row.get("status") == "failed" for row in db_rows),
        "db_ingest_pending_product_ids": db_pending_ids,
        "db_classification_statuses": {
            status: sum(
                row.get("status") == "succeeded" and row.get("classification_status") == status
                for row in db_rows
            )
            for status in ("confirmed", "not_comparable", "review_required", "unclassified")
        },
        "not_seen_this_run": len(not_seen_ids) if discovery_complete else None,
        "state_product_count_after": len(ledger["products"]),
        "state_updated": not args.no_fetch_new,
    }
    write_json(run_dir / "summary.json", summary)
    if not args.no_fetch_new:
        ledger["last_run"] = summary
        write_json(state_path, ledger)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if not discovery_complete:
        print(
            "유니클로 카테고리 응답이 요청 경로와 일치하지 않아 "
            "이번 실행은 불완전합니다. 기존 상품의 판매 종료 여부는 판정하지 않았습니다.",
            file=sys.stderr,
        )
        lock_stream.close()
        return 2
    if db_pending_ids:
        lock_stream.close()
        return 3
    lock_stream.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
