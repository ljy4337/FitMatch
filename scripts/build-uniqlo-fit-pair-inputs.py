#!/usr/bin/env python3
"""Bundle stored UNIQLO size-chart responses with product classification inputs."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def gender_codes(corpus: Path, product_id: str) -> list[str]:
    product_files = sorted((corpus / "raw" / "uniqlo" / "products").glob(f"{product_id}-*.html"))
    if not product_files:
        return []
    html = product_files[0].read_text(encoding="utf-8", errors="ignore")
    for field in ("genderCategory", "genderName"):
        match = re.search(rf'"{field}"\s*:\s*"([^\"]+)"', html)
        if match:
            value = match.group(1).strip().upper()
            if value in {"MEN", "WOMEN", "UNISEX", "KIDS", "BABY"}:
                return [value]
    return []


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--classifications", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    corpus = args.corpus if args.corpus.is_absolute() else ROOT / args.corpus
    classifications_path = (
        args.classifications if args.classifications.is_absolute()
        else ROOT / args.classifications
    )
    output = args.output if args.output.is_absolute() else ROOT / args.output
    classifications = json.loads(classifications_path.read_text(encoding="utf-8"))

    rows = []
    for product in classifications:
        product_id = str(product["product_id"])
        response_path = corpus / "raw" / "uniqlo" / "size_charts" / f"{product_id}.json"
        rows.append({
            "product_id": product_id,
            "product_name": product["product_name"],
            "source_path": product["source_path"],
            "gender_codes": gender_codes(corpus, product_id),
            "response": json.loads(response_path.read_text(encoding="utf-8")),
        })

    output.write_text(
        json.dumps(rows, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(json.dumps({"products": len(rows), "output": str(output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
