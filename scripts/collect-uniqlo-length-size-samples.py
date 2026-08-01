#!/usr/bin/env python3
"""Collect official UNIQLO size charts for explicitly labeled length categories."""

from __future__ import annotations

import argparse
import csv
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path


TOKENS = ("반팔", "긴팔", "쇼트 팬츠", "반바지")
ENDPOINT = "https://www.uniqlo.com/kr/api/commerce/v5/ko/products/size-charts"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    rows = list(csv.DictReader(args.corpus.open(encoding="utf-8-sig", newline="")))
    selected = [
        row for row in rows
        if row.get("final_path", "").startswith("팬츠 >")
        or any(
            token in row.get("final_path", "").split(">")[-1]
            for token in TOKENS
        )
    ]
    products = []
    for start in range(0, len(selected), 10):
        batch = selected[start:start + 10]
        codes = ",".join(row["product_id"] for row in batch)
        query = urllib.parse.urlencode({
            "productIdsWithColorCode": codes,
            "includeBodyMeasurements": "true",
            "simpleSizeChart": "true",
            "httpFailure": "true",
        })
        request = urllib.request.Request(
            f"{ENDPOINT}?{query}",
            headers={
                "Accept": "application/json",
                "Referer": "https://www.uniqlo.com/kr/ko/",
                "User-Agent": "Mozilla/5.0",
            },
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
        by_id = {item.get("productId"): item for item in payload.get("result", [])}
        for row in batch:
            products.append({
                "product_id": row["product_id"],
                "gender": row["audience"],
                "category_path": row["final_path"],
                "size_chart": by_id.get(row["product_id"], {}).get("sizeChart", []),
            })
        time.sleep(0.25)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps({
            "source": ENDPOINT,
            "products": products,
        }, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "selected": len(selected),
        "with_size_chart": sum(bool(item["size_chart"]) for item in products),
        "output": str(args.output),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
