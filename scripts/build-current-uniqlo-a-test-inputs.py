#!/usr/bin/env python3
"""Build compact, reproducible inputs from a current Uniqlo catalog capture."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import re
import sys
from pathlib import Path


def load_collector(repo_root: Path):
    path = repo_root / "scripts/category-corpus/corpus_collector.py"
    spec = importlib.util.spec_from_file_location("fitmatch_current_uniqlo_collector", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def matching_product(state: dict, core_id: str) -> dict:
    entities = state.get("entity", {}).get("pdpEntity", {})
    matches = []
    for key, entity in entities.items():
        product = entity.get("product", {}) if isinstance(entity, dict) else {}
        product_id = str(product.get("productId") or "")
        if key.startswith(f"{core_id}-") or product_id.startswith(f"{core_id}-"):
            matches.append(product)
    if len(matches) != 1:
        raise ValueError(f"{core_id}: expected one hydration product, found {len(matches)}")
    return matches[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--output-urls", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    collector = load_collector(repo_root)
    corpus = args.corpus.resolve()
    manifest = json.loads((corpus / "clothing_product_manifest.json").read_text(encoding="utf-8"))
    checkpoint = json.loads((corpus / "checkpoint.json").read_text(encoding="utf-8"))
    size_summary = json.loads((corpus / "uniqlo_size_evidence.json").read_text(encoding="utf-8"))
    size_by_core = {item["product_id"]: item for item in size_summary["products_detail"]}

    observations: dict[str, set[str]] = {}
    for audience in checkpoint["sources"]["uniqlo"]["audiences"].values():
        for observed_id, category_urls in audience["discovered_products"].items():
            core_id = observed_id.split("-")[0]
            observations.setdefault(core_id, set()).add(observed_id)

    records = []
    url_rows = []
    for item in manifest["products"]:
        core_id = item["product_key"]
        observed_id = item["observed_ids"][0]
        raw_path = Path(item["raw_evidence"][0]["path"])
        raw = raw_path.read_bytes()
        category = collector.uniqlo_category_evidence(raw, observed_id)
        state = collector.hydration_state(raw.decode("utf-8", errors="replace"))
        product = matching_product(state, core_id)
        size_path = Path(size_by_core[core_id]["path"])
        size_payload = json.loads(size_path.read_text(encoding="utf-8"))
        observed_ids = sorted(observations.get(core_id, {observed_id}))
        canonical_url = item["raw_evidence"][0]["url"]
        depth_names = category["depth_names"]
        depth_codes = category["depth_codes"]
        records.append({
            "product_id": core_id,
            "product_name": str(product.get("name") or "").strip(),
            "canonical_url": canonical_url,
            "observed_ids": observed_ids,
            "source_path": category["path"],
            "source_depth_names": depth_names,
            "source_depth_codes": depth_codes,
            "audience": category["audience"],
            "gender_name": product.get("genderName"),
            "gender_category": product.get("genderCategory"),
            "product_type": product.get("productType"),
            "product_type_kr": product.get("productTypeKr"),
            "size_chart_payload": size_payload,
            "size_count_official": size_by_core[core_id]["size_count"],
        })
        for variant in observed_ids:
            color = re.search(r"-(\d{3})$", variant)
            url_rows.append({
                "product_id": core_id,
                "observed_id": variant,
                "color_code": color.group(1) if color else "",
                "canonical_product_url": canonical_url,
                "observed_product_url": f"https://www.uniqlo.com/kr/ko/products/{variant}",
                "product_name": str(product.get("name") or "").strip(),
                "audience": category["audience"],
                "source_path": category["path"],
            })

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_urls.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(
        json.dumps(records, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    with args.output_urls.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(url_rows[0]))
        writer.writeheader()
        writer.writerows(url_rows)
    print(json.dumps({
        "products": len(records),
        "observed_urls": len(url_rows),
        "with_size_chart": sum(row["size_count_official"] > 0 for row in records),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
