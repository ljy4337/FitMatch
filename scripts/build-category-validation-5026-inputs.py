#!/usr/bin/env python3
"""Build the deterministic 5,026-product input resource for the Swift audit."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    ROOT / "Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/swift_production_classification_results_cumulative_2560.json",
    ROOT / "Docs/Research/NewClothingCorpus-2000-20260810/classification_inputs.json",
    ROOT / "Docs/Research/NewClothingCorpus-Fresh-20260810/classification_results.json",
)
OUTPUT = ROOT / "FitMatchTests/CategoryValidation5026Inputs.json"


def canonical_product_id(source: str, product_id: object) -> str:
    value = str(product_id).strip()
    if source == "uniqlo":
        value = re.sub(r"^E", "", value, flags=re.IGNORECASE)
        value = re.sub(r"-\d{3}(?:-\d{2})?$", "", value)
        return f"E{value}"
    return value


def main() -> None:
    records: list[dict[str, object]] = []
    identities: set[tuple[str, str]] = set()

    for source_path in SOURCES:
        source_rows = json.loads(source_path.read_text(encoding="utf-8"))
        for row in source_rows:
            source = str(row.get("source", "")).lower().strip()
            product_id = canonical_product_id(source, row.get("product_id", ""))
            identity = (source, product_id)
            if identity in identities:
                raise SystemExit(f"duplicate product identity: {source}:{product_id}")
            identities.add(identity)

            product_url = row.get("product_url")
            if not product_url:
                if source == "musinsa":
                    product_url = f"https://www.musinsa.com/products/{product_id}"
                elif source == "uniqlo":
                    product_url = f"https://store-kr.uniqlo.com/kr/ko/products/{product_id}-000/00"

            records.append(
                {
                    "source": source,
                    "product_id": product_id,
                    "product_name": str(row.get("product_name", "")),
                    "source_path": str(
                        row.get("source_path", row.get("original_category_path", ""))
                    ),
                    "product_url": product_url,
                    "origin_input": str(source_path.relative_to(ROOT)),
                    "previous_category_code": row.get("category_code"),
                    "previous_detail_code": row.get("detail_code"),
                    "external_category_id": str(
                        row.get(
                            "discovery_category_code",
                            row.get("external_category_id", ""),
                        )
                    ),
                }
            )

    if len(records) != 5_026 or len(identities) != 5_026:
        raise SystemExit(
            f"expected 5,026 unique inputs, got rows={len(records)} unique={len(identities)}"
        )

    OUTPUT.write_text(
        json.dumps(records, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(records)} unique inputs to {OUTPUT}")


if __name__ == "__main__":
    main()
