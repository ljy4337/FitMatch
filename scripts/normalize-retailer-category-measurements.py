#!/usr/bin/env python3
"""Deduplicate observed retailer categories and garment measurement fields.

Reads retained official response captures only. It does not fetch, classify,
infer FitMatch comparison groups, or write to Supabase.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def numeric(value) -> bool:
    try:
        return float(value) > 0
    except (TypeError, ValueError):
        return False


def musinsa_observations():
    for product_path in sorted((ROOT / "Docs/TestEvidence/MusinsaCatalogIncremental/runs").glob(
        "*/new_products/raw/musinsa/product/*.json"
    )):
        size_path = product_path.parents[1] / "actual_size" / product_path.name
        if not size_path.is_file():
            continue
        details = read_json(product_path).get("data") or {}
        size_data = read_json(size_path).get("data") or {}
        path = details.get("baseCategoryFullPath")
        if not path:
            continue
        fields = set()
        for size in size_data.get("sizes") or []:
            for item in size.get("items") or []:
                label = str(item.get("name") or "").strip()
                if label and numeric(item.get("value")):
                    fields.add(("", label, "unknown"))
        yield ("musinsa", str(path).strip(), "", product_path.stem, fields,
               str(product_path.relative_to(ROOT)), str(size_path.relative_to(ROOT)))


def uniqlo_observations():
    runs = ROOT / "Docs/TestEvidence/UniqloCatalogIncremental/runs"
    for manifest_path in sorted(runs.glob("*/new_products/clothing_product_manifest.json")):
        raw_dir = manifest_path.parent / "raw/uniqlo/size_charts"
        for product in read_json(manifest_path).get("products") or []:
            product_id = str(product.get("product_key") or "")
            size_path = raw_dir / f"{product_id}.json"
            if not size_path.is_file():
                continue
            fields = set()
            for chart in read_json(size_path).get("result") or []:
                for size in chart.get("sizeChart") or []:
                    for part in size.get("sizeParts") or []:
                        code = str(part.get("code") or "").strip()
                        label = str(part.get("name") or "").strip()
                        if not code or not label:
                            continue
                        if any(measurement.get("unit") == "cm" and numeric(measurement.get("value"))
                               for measurement in part.get("measurements") or []):
                            fields.add((code, label, "cm"))
            for path in sorted(set(product.get("exposure_paths") or [])):
                if path:
                    yield ("uniqlo", str(path).strip(), "", product_id, fields,
                           str(manifest_path.relative_to(ROOT)), str(size_path.relative_to(ROOT)))


def zara_observations():
    manifest = ROOT / "ZARAAudit/zara_production_sample_30_manifest.jsonl"
    for line in manifest.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        if row.get("response_type") != "garment_measure" or row.get("http_status") != 200:
            continue
        relative = row.get("fixture_path")
        if not relative:
            continue
        capture_path = ROOT / "ZARAAudit" / relative
        if not capture_path.is_file():
            continue
        capture = read_json(capture_path)
        guide = (capture.get("response") or {}).get("measureGuideInfo") or {}
        fields = set()
        for size in guide.get("sizes") or []:
            for measure in size.get("measures") or []:
                code = str(measure.get("tableTitleZone") or "").strip()
                if not code:
                    continue
                if any(dimension.get("unitId") == "cm" and numeric(dimension.get("value"))
                       for dimension in measure.get("dimensions") or []):
                    fields.add((code, code, "cm"))
        category = " > ".join(filter(None, [row.get("official_category_path"),
                                             row.get("family_name"), row.get("subfamily_name")]))
        category_id = str(row.get("official_category_id") or "")
        if category and category_id:
            yield ("zara", category, category_id, str(row.get("product_id") or ""), fields,
                   str(manifest.relative_to(ROOT)), str(capture_path.relative_to(ROOT)))


def write_csv(path: Path, names: list[str], rows: list[dict]):
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=names)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    categories = defaultdict(lambda: {"products": set(), "category_captures": set(), "measurement_captures": set()})
    measurements = defaultdict(lambda: {"products": set(), "captures": set()})
    for source, path, category_id, product_id, fields, category_capture, measurement_capture in (
        *musinsa_observations(), *uniqlo_observations(), *zara_observations()
    ):
        category_key = (source, category_id, path)
        categories[category_key]["products"].add(product_id)
        categories[category_key]["category_captures"].add(category_capture)
        categories[category_key]["measurement_captures"].add(measurement_capture)
        for code, label, unit in fields:
            entry = measurements[(*category_key, code, label, unit)]
            entry["products"].add(product_id)
            entry["captures"].add(measurement_capture)

    category_rows = [
        {"source": source, "category_id": category_id, "category_path": path,
         "observed_products": len(evidence["products"]),
         "measurement_fields": sum(key[:3] == (source, category_id, path) for key in measurements),
         "category_source_capture": sorted(evidence["category_captures"])[0],
         "measurement_source_capture": sorted(evidence["measurement_captures"])[0]}
        for (source, category_id, path), evidence in sorted(categories.items())
    ]
    measurement_rows = [
        {"source": source, "category_id": category_id, "category_path": path,
         "raw_code": code, "raw_label": label, "unit": unit,
         "observed_products": len(evidence["products"]),
         "measurement_source_capture": sorted(evidence["captures"])[0]}
        for (source, category_id, path, code, label, unit), evidence in sorted(measurements.items())
    ]
    write_csv(output / "categories.csv",
              ["source", "category_id", "category_path", "observed_products", "measurement_fields",
               "category_source_capture", "measurement_source_capture"],
              category_rows)
    write_csv(output / "category_measurements.csv",
              ["source", "category_id", "category_path", "raw_code", "raw_label", "unit",
               "observed_products", "measurement_source_capture"],
              measurement_rows)
    summary = {"categories": len(category_rows), "category_measurements": len(measurement_rows),
               "by_source": {source: {"categories": sum(row["source"] == source for row in category_rows),
                                      "category_measurements": sum(row["source"] == source for row in measurement_rows)}
                             for source in ("musinsa", "uniqlo", "zara")},
               "provenance": "retained official response captures; not refreshed live"}
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
