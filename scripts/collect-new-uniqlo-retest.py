#!/usr/bin/env python3
"""Collect fresh Uniqlo product pages that do not overlap an earlier corpus."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path


NON_CLOTHING = re.compile(
    r"accessor|sock|shoe|bag|hat|cap|belt|umbrella|glove|scarf|sunglass|bodysuit|"
    r"액세서리|양말|신발|가방|모자|캡|벨트|우산|장갑|스카프|선글라스|바디수트",
    re.IGNORECASE,
)
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 FitMatchResearch/1.0"


def load_corpus_collector():
    path = Path(__file__).parent / "category-corpus" / "corpus_collector.py"
    spec = importlib.util.spec_from_file_location("fitmatch_corpus_collector", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


CORPUS_COLLECTOR = load_corpus_collector()


def core_id(value: str) -> str:
    return value.split("-")[0]


def load_candidates(
    checkpoint: Path,
    old_manifests: list[Path],
    include_all_catalog_items: bool,
) -> list[tuple[str, list[str]]]:
    state = json.loads(checkpoint.read_text(encoding="utf-8"))
    old_ids = set()
    for old_manifest in old_manifests:
        old = json.loads(old_manifest.read_text(encoding="utf-8"))["products"]
        old_ids.update(core_id(item["product_key"]) for item in old if item["source"] == "uniqlo")

    exposures: dict[str, set[str]] = {}
    for audience in state["sources"]["uniqlo"]["audiences"].values():
        for observed_id, urls in audience["discovered_products"].items():
            exposures.setdefault(observed_id, set()).update(urls)

    candidates_by_core: dict[str, tuple[str, list[str]]] = {}
    for observed_id, urls in sorted(exposures.items()):
        product_core = core_id(observed_id)
        if product_core in old_ids:
            continue
        eligible_urls = sorted(urls) if include_all_catalog_items else sorted(
            url for url in urls if not NON_CLOTHING.search(url)
        )
        if eligible_urls and product_core not in candidates_by_core:
            candidates_by_core[product_core] = (observed_id, eligible_urls)
    return [candidates_by_core[key] for key in sorted(candidates_by_core)]


class LaunchLimiter:
    def __init__(self, interval: float) -> None:
        self.interval = interval
        self.lock = threading.Lock()
        self.next_start = 0.0

    def wait(self) -> None:
        with self.lock:
            now = time.monotonic()
            delay = max(0.0, self.next_start - now)
            self.next_start = max(now, self.next_start) + self.interval
        if delay:
            time.sleep(delay)


def fetch(
    candidate: tuple[str, list[str]],
    raw_dir: Path,
    limiter: LaunchLimiter,
    include_all_catalog_items: bool,
) -> dict:
    observed_id, exposure_urls = candidate
    url = f"https://www.uniqlo.com/kr/ko/products/{observed_id}"
    candidate_urls = [url, f"{url}/01", f"{url}/00"]
    existing_path = raw_dir / f"{observed_id}.html"
    if existing_path.exists():
        body = existing_path.read_bytes()
        text = body.decode("utf-8", errors="replace")
        category = CORPUS_COLLECTOR.uniqlo_category_evidence(body, observed_id)
        complete = (
            observed_id.split("-")[0] in text
            and len(body) > 10_000
            and category["status"] == "resolved"
            and bool(category["path"])
            and (include_all_catalog_items or not NON_CLOTHING.search(category["path"]))
        )
        return {
            "observed_id": observed_id,
            "exposure_paths": exposure_urls,
            "url": url,
            "status": 200,
            "bytes": len(body),
            "sha256": hashlib.sha256(body).hexdigest(),
            "path": str(existing_path),
            "complete": complete,
            "category_path": category["path"],
            "category_evidence_source": category["evidence_source"],
            "error": "" if complete else category["unresolved_reason"] or "product_identity_or_body_missing",
        }
    error = ""
    for attempt, request_url in enumerate(candidate_urls):
        limiter.wait()
        request = urllib.request.Request(
            request_url,
            headers={"User-Agent": USER_AGENT, "Referer": exposure_urls[0]},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read()
                final_url = response.geturl()
                status = response.status
            path = raw_dir / f"{observed_id}.html"
            path.write_bytes(body)
            text = body.decode("utf-8", errors="replace")
            category = CORPUS_COLLECTOR.uniqlo_category_evidence(body, observed_id)
            complete = (
                observed_id.split("-")[0] in text
                and len(body) > 10_000
                and category["status"] == "resolved"
                and bool(category["path"])
                and (include_all_catalog_items or not NON_CLOTHING.search(category["path"]))
            )
            return {
                "observed_id": observed_id,
                "exposure_paths": exposure_urls,
                "url": final_url,
                "status": status,
                "bytes": len(body),
                "sha256": hashlib.sha256(body).hexdigest(),
                "path": str(path),
                "complete": complete,
                "category_path": category["path"],
                "category_evidence_source": category["evidence_source"],
                "error": "" if complete else category["unresolved_reason"] or "product_identity_or_body_missing",
            }
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            error = str(exc)
            time.sleep(0.5 * (attempt + 1))
    return {
        "observed_id": observed_id,
        "exposure_paths": exposure_urls,
        "url": url,
        "status": 0,
        "bytes": 0,
        "sha256": "",
        "path": "",
        "complete": False,
        "error": error or "request_failed",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--old-manifest", action="append", type=Path, default=[])
    parser.add_argument(
        "--include-all-catalog-items",
        action="store_true",
        help="Include accessories and other non-clothing listings for exclusion-policy QA.",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target", type=int, default=320)
    parser.add_argument(
        "--select-all-complete",
        action="store_true",
        help="Keep every complete response and report failures without enforcing --target.",
    )
    parser.add_argument("--attempt-limit", type=int, default=500)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--delay-ms", type=int, default=250)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    raw_dir = args.output / "raw" / "uniqlo" / "products"
    raw_dir.mkdir(parents=True, exist_ok=True)
    candidates = load_candidates(
        args.checkpoint,
        args.old_manifest,
        args.include_all_catalog_items,
    )[: args.attempt_limit]
    if not args.select_all_complete and len(candidates) < args.target:
        raise SystemExit(f"only {len(candidates)} non-overlapping clothing candidates")

    limiter = LaunchLimiter(args.delay_ms / 1000)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [
            executor.submit(
                fetch,
                candidate,
                raw_dir,
                limiter,
                args.include_all_catalog_items,
            )
            for candidate in candidates
        ]
        for index, future in enumerate(concurrent.futures.as_completed(futures), start=1):
            results.append(future.result())
            if index % 25 == 0:
                print(json.dumps({"completed": index, "complete": sum(r["complete"] for r in results)}))

    complete = sorted((result for result in results if result["complete"]), key=lambda item: item["observed_id"])
    if not args.select_all_complete and len(complete) < args.target:
        raise SystemExit(f"only {len(complete)} complete responses from {len(candidates)} attempts")
    selected = complete if args.select_all_complete else complete[: args.target]
    products = []
    for result in selected:
        products.append({
            "source": "uniqlo",
            "product_key": core_id(result["observed_id"]),
            "observed_ids": [result["observed_id"]],
            "exposure_paths": [result["category_path"]],
            "raw_evidence": [{
                "path": result["path"],
                "url": result["url"],
                "status": result["status"],
                "bytes": result["bytes"],
                "sha256": result["sha256"],
            }],
            "selection": "fresh_live_non_overlapping_retest",
        })
    manifest = {
        "definition": "Fresh Uniqlo responses; product IDs excluded against every supplied baseline manifest.",
        "baseline_manifests": [str(path) for path in args.old_manifest],
        "product_count": len(products),
        "products": products,
        "attempted": len(results),
        "complete_responses": len(complete),
        "failures": [result for result in results if not result["complete"]],
    }
    (args.output / "clothing_product_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"selected": len(products), "attempted": len(results), "complete": len(complete)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
