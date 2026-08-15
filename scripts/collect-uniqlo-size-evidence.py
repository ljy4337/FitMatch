#!/usr/bin/env python3
"""Download official UNIQLO size-chart evidence for a stored manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENDPOINT = "https://www.uniqlo.com/kr/api/commerce/v5/ko/products/size-charts"


def fetch_batch(product_ids: list[str]) -> dict:
    query = urllib.parse.urlencode({
        "productIdsWithColorCode": ",".join(product_ids),
        "includeBodyMeasurements": "true",
        "simpleSizeChart": "true",
        "httpFailure": "true",
    })
    request = urllib.request.Request(
        f"{ENDPOINT}?{query}",
        headers={
            "Accept": "application/json",
            "Referer": "https://www.uniqlo.com/kr/ko/",
            "User-Agent": "Mozilla/5.0 FitMatchResearch/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument("--delay-ms", type=int, default=250)
    args = parser.parse_args()

    corpus = args.corpus if args.corpus.is_absolute() else ROOT / args.corpus
    manifest = json.loads((corpus / "clothing_product_manifest.json").read_text(encoding="utf-8"))
    output_dir = corpus / "raw" / "uniqlo" / "size_charts"
    output_dir.mkdir(parents=True, exist_ok=True)

    requests: list[tuple[str, str]] = []
    for product in manifest["products"]:
        product_key = str(product["product_key"])
        observed_ids = product.get("observed_ids") or []
        requested_id = str(observed_ids[0]) if observed_ids else f"{product_key}-000"
        requests.append((product_key, requested_id))

    details = []
    for start in range(0, len(requests), args.batch_size):
        batch = requests[start:start + args.batch_size]
        payload = fetch_batch([requested_id for _, requested_id in batch])
        by_id = {str(item.get("productId")): item for item in payload.get("result", [])}
        for product_key, requested_id in batch:
            item = by_id.get(requested_id)
            wrapped = {"result": [item] if item else []}
            encoded = json.dumps(wrapped, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            output_path = output_dir / f"{product_key}.json"
            output_path.write_bytes(encoded)
            size_chart = (item or {}).get("sizeChart") or []
            try:
                recorded_path = str(output_path.relative_to(ROOT))
            except ValueError:
                recorded_path = str(output_path)
            details.append({
                "product_id": product_key,
                "requested_id": requested_id,
                "result_found": item is not None,
                "size_count": len(size_chart),
                "measurement_count": sum(
                    len(size.get("sizeParts") or []) for size in size_chart
                ),
                "path": recorded_path,
                "bytes": len(encoded),
                "sha256": hashlib.sha256(encoded).hexdigest(),
            })
        time.sleep(args.delay_ms / 1000)

    summary = {
        "source": ENDPOINT,
        "products": len(details),
        "result_found": sum(item["result_found"] for item in details),
        "with_size_chart": sum(item["size_count"] > 0 for item in details),
        "size_rows": sum(item["size_count"] for item in details),
        "measurement_parts": sum(item["measurement_count"] for item in details),
        "products_detail": details,
    }
    summary_path = corpus / "uniqlo_size_evidence.json"
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({key: value for key, value in summary.items() if key != "products_detail"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
