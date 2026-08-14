#!/usr/bin/env python3
"""Bundle stored Musinsa actual-size responses with Swift classifications."""
import argparse, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, required=True)
    ap.add_argument("--classifications", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    corpus = args.corpus if args.corpus.is_absolute() else ROOT / args.corpus
    classifications_path = args.classifications if args.classifications.is_absolute() else ROOT / args.classifications
    output = args.output if args.output.is_absolute() else ROOT / args.output
    classifications = {
        (row["source"], str(row["product_id"])): row
        for row in json.loads(classifications_path.read_text(encoding="utf-8"))
    }
    manifest = json.loads((corpus / "clothing_product_manifest.json").read_text(encoding="utf-8"))
    rows = []
    for product in manifest["products"]:
        product_id = str(product["product_key"])
        classification = classifications[("musinsa", product_id)]
        response_path = corpus / "raw" / "musinsa" / "actual_size" / f"{product_id}.json"
        product_path = corpus / "raw" / "musinsa" / "products" / f"{product_id}.json"
        product_payload = json.loads(product_path.read_text(encoding="utf-8"))
        product_data = product_payload.get("data") or {}
        gender_codes = product_data.get("genders") or product_data.get("sex") or []
        rows.append({
            "product_id": product_id,
            "product_name": product["product_name"],
            "category_code": classification["category_code"],
            "detail_code": classification["detail_code"],
            "source_path": classification["source_path"],
            "gender_codes": [str(value) for value in gender_codes],
            "response": json.loads(response_path.read_text(encoding="utf-8")),
        })
    output.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(json.dumps({"products": len(rows), "output": str(output)}))

if __name__ == "__main__":
    main()
