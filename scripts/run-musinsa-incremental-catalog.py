#!/usr/bin/env python3
"""Discover the current Musinsa apparel catalog and collect only unseen products."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import hashlib
import json
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from catalog_batch_common import SupabaseBatchClient, musinsa_payload, sync_payloads


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = ROOT / "Docs/Research/CategoryCorpus-bootstrap/product_manifest.json"
DEFAULT_STATE = ROOT / "Docs/TestEvidence/MusinsaCatalogIncremental/state.json"
DEFAULT_RUN_ROOT = ROOT / "Docs/TestEvidence/MusinsaCatalogIncremental/runs"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) FitMatchResearch/1.0"


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_csv(path: Path, fields: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def initialize_state(baselines: list[Path]) -> dict:
    created_at = now()
    products: dict[str, dict] = {}
    for baseline in baselines:
        if not baseline.is_file():
            continue
        for item in read_json(baseline).get("products", []):
            if item.get("source") != "musinsa":
                continue
            product_id = str(item.get("product_key") or item.get("product_id") or "")
            if not product_id:
                continue
            products.setdefault(product_id, {
                "status": "stored",
                "first_seen_at": created_at,
                "last_seen_at": created_at,
                "product_name": item.get("product_name", ""),
                "brand": item.get("brand", ""),
                "category_path": (item.get("exposure_paths") or [""])[0],
                "canonical_url": item.get("product_url") or f"https://www.musinsa.com/products/{product_id}",
            })
    return {
        "version": 1,
        "source": "musinsa",
        "initialized_at": created_at,
        "baselines": [str(path) for path in baselines],
        "products": products,
        "last_run": None,
    }


def observations(checkpoint: Path) -> dict[str, dict]:
    source = read_json(checkpoint)["sources"]["musinsa"]
    return {
        str(product_id): {
            "product_id": str(product_id),
            "exposure_urls": sorted(set(urls)),
        }
        for product_id, urls in source["discovered_products"].items()
    }


class Limiter:
    def __init__(self, delay_seconds: float):
        self.delay_seconds = delay_seconds
        self.lock = threading.Lock()
        self.next_request = 0.0

    def wait(self) -> None:
        with self.lock:
            current = time.monotonic()
            wait_seconds = max(0.0, self.next_request - current)
            self.next_request = max(current, self.next_request) + self.delay_seconds
        if wait_seconds:
            time.sleep(wait_seconds)


def fetch(url: str, referer: str, limiter: Limiter) -> tuple[bytes, int, str]:
    limiter.wait()
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json", "Referer": referer},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read(), response.status, response.geturl()


def collect_product(product_id: str, exposure_urls: list[str], output: Path, limiter: Limiter) -> dict:
    referer = exposure_urls[0] if exposure_urls else "https://www.musinsa.com"
    result = {"product_id": product_id, "exposure_urls": exposure_urls}
    endpoints = {
        "product": f"https://goods-detail.musinsa.com/api2/goods/{product_id}",
        "actual_size": f"https://goods-detail.musinsa.com/api2/goods/{product_id}/actual-size",
        "options": f"https://goods-detail.musinsa.com/api2/goods/{product_id}/options",
    }
    try:
        for kind, url in endpoints.items():
            body, status, final_url = fetch(url, referer, limiter)
            target = output / "raw" / "musinsa" / kind / f"{product_id}.json"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(body)
            result[kind] = {
                "status": status,
                "url": final_url,
                "path": str(target),
                "bytes": len(body),
                "sha256": hashlib.sha256(body).hexdigest(),
            }
        payload = read_json(Path(result["product"]["path"]))
        data = payload.get("data") or {}
        size_payload = read_json(Path(result["actual_size"]["path"]))
        size_data = size_payload.get("data") or {}
        result.update({
            "status": "stored",
            "product_name": data.get("goodsNm") or data.get("goodsNmEng") or "",
            "brand": data.get("brand") or data.get("brandName") or "",
            "category_path": data.get("baseCategoryFullPath") or "",
            "size_type": size_data.get("typeName") or "",
            "size_row_count": len(size_data.get("sizes") or []),
        })
    except Exception as error:
        result.update({"status": "pending_retry", "error": str(error)})
    return result


def run(command: list[str]) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-manifest", type=Path, action="append")
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--run-id", default=datetime.now().strftime("%Y%m%d-%H%M%S"))
    parser.add_argument("--checkpoint", type=Path, help="Use an existing discovery checkpoint without crawling.")
    parser.add_argument("--no-fetch-new", action="store_true")
    parser.add_argument(
        "--no-db-sync", action="store_true",
        help="Testing only: collect locally without trusted Supabase ingest/classification.",
    )
    parser.add_argument("--delay-ms", type=int, default=350)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--max-category-pages", type=int, default=500)
    args = parser.parse_args()

    baselines = [path.resolve() for path in (args.baseline_manifest or [DEFAULT_BASELINE])]
    state_path = args.state.resolve()
    ledger = read_json(state_path) if state_path.is_file() else initialize_state(baselines)
    run_dir = args.run_root.resolve() / args.run_id
    run_dir.mkdir(parents=True, exist_ok=False)

    if args.checkpoint:
        checkpoint = args.checkpoint.resolve()
    else:
        discovery_dir = run_dir / "discovery"
        run([
            sys.executable,
            str(ROOT / "scripts/category-corpus/corpus_collector.py"),
            "live", "--source", "musinsa", "--output", str(discovery_dir),
            "--discovery-only", "--max-category-pages", str(args.max_category_pages),
            "--delay-ms", str(args.delay_ms),
        ])
        checkpoint = discovery_dir / "checkpoint.json"

    current = observations(checkpoint)
    known_ids = set(ledger["products"])
    current_ids = set(current)
    new_ids = sorted(current_ids - known_ids, key=int)
    db_client = None
    db_needing_ingest: set[str] = set()
    if not args.no_db_sync and not args.no_fetch_new:
        db_client = SupabaseBatchClient()
        db_needing_ingest = db_client.products_needing_ingest("musinsa", sorted(current_ids, key=int))
    collection_target_ids = sorted(set(new_ids) | db_needing_ingest, key=int)
    missing_ids = sorted(
        (product_id for product_id in known_ids - current_ids if ledger["products"][product_id]["status"] == "stored"),
        key=int,
    )

    discovered_rows = [{
        "product_id": product_id,
        "is_new": product_id in new_ids,
        "exposure_urls": ";".join(current[product_id]["exposure_urls"]),
    } for product_id in sorted(current_ids, key=int)]
    write_csv(run_dir / "discovered_products.csv", ["product_id", "is_new", "exposure_urls"], discovered_rows)
    write_csv(run_dir / "new_product_ids.csv", ["product_id", "exposure_urls"], [row for row in discovered_rows if row["is_new"]])
    write_csv(
        run_dir / "missing_product_ids.csv",
        ["product_id", "last_seen_at", "product_name", "brand", "category_path", "canonical_url"],
        [{"product_id": product_id, **ledger["products"][product_id]} for product_id in missing_ids],
    )

    results: list[dict] = []
    if collection_target_ids and not args.no_fetch_new:
        limiter = Limiter(args.delay_ms / 1000)
        detail_dir = run_dir / "new_products"
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = [
                executor.submit(
                    collect_product, product_id, current[product_id]["exposure_urls"], detail_dir, limiter
                )
                for product_id in collection_target_ids
            ]
            for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
                results.append(future.result())
                if index % 25 == 0 or index == len(futures):
                    print(json.dumps({"collected": index, "total": len(futures)}, ensure_ascii=False), flush=True)
        results.sort(key=lambda item: int(item["product_id"]))
        write_json(run_dir / "new_product_inputs.json", results)

    stored = [item for item in results if item["status"] == "stored"]
    pending = [item for item in results if item["status"] != "stored"]
    db_succeeded_ids: set[str] = set()
    db_rows: list[dict] = []
    if stored:
        if db_client is not None:
            db_succeeded_ids, db_rows = sync_payloads(
                db_client,
                (musinsa_payload(item) for item in stored),
                run_dir / "db_ingest_results.json",
            )
        else:
            db_succeeded_ids = {str(item["product_id"]) for item in stored}
    db_pending_ids = sorted(set(collection_target_ids) - db_succeeded_ids, key=int) if db_client is not None else []
    write_csv(
        run_dir / "new_products.csv",
        ["product_id", "product_name", "brand", "category_path", "size_type", "size_row_count", "product_url"],
        [{**item, "product_url": f"https://www.musinsa.com/products/{item['product_id']}"} for item in stored],
    )
    write_csv(
        run_dir / "pending_retry.csv",
        ["product_id", "error", "exposure_urls"],
        [{**item, "exposure_urls": ";".join(item.get("exposure_urls", []))} for item in pending],
    )

    completed_at = now()
    for product_id in current_ids & known_ids:
        ledger["products"][product_id]["last_seen_at"] = completed_at
    for item in stored:
        product_id = item["product_id"]
        if db_client is not None and product_id not in db_succeeded_ids:
            continue
        ledger["products"][product_id] = {
            "status": "stored",
            "first_seen_at": completed_at,
            "last_seen_at": completed_at,
            "product_name": item["product_name"],
            "brand": item["brand"],
            "category_path": item["category_path"],
            "canonical_url": f"https://www.musinsa.com/products/{product_id}",
        }

    summary = {
        "run_id": args.run_id,
        "completed_at": completed_at,
        "checkpoint": str(checkpoint),
        "known_before": len(known_ids),
        "currently_discovered": len(current_ids),
        "new_discovered": len(new_ids),
        "db_needing_ingest": len(db_needing_ingest),
        "collection_targets": len(collection_target_ids),
        "new_detail_collected": len(stored),
        "new_pending_retry": [item["product_id"] for item in pending] if not args.no_fetch_new else new_ids,
        "missing_from_current_catalog": len(missing_ids),
        "state_product_count_after": len(ledger["products"]),
        "state_updated": not args.no_fetch_new,
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
    }
    write_json(run_dir / "summary.json", summary)
    if not args.no_fetch_new:
        ledger["last_run"] = summary
        write_json(state_path, ledger)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 3 if db_pending_ids else 0


if __name__ == "__main__":
    raise SystemExit(main())
