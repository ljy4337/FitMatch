#!/usr/bin/env python3
"""Offline, read-only splitter for retailer JSON catalog snapshots.

The classifier deliberately uses structured API category evidence before any
human-readable product title.  It never opens a URL and never writes below an
input directory; only the requested manifest/report output directories are
created or replaced.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


DECISIONS = ("clothing", "non_clothing", "review_needed")
IGNORED_CONTEXT = {
    "men", "women", "kids", "kid", "baby", "newborn", "toddler", "gender",
    "airism", "linen", "uv protection", "sport", "sports", "sport utility wear",
}
CLOTHING_CODES = {
    "tops", "bottoms", "outerwear", "dresses", "underwear", "innerwear",
}
CLOTHING_LEAF_CODES = {
    "t shirts", "shirt", "shirts", "polo shirts", "short sleeve", "half sleeve", "long sleeve",
    "sleeveless", "pants", "skirts", "leggings", "shorts", "jogger", "jogger pants",
    "jeans", "jackets", "jacket", "coats", "parka", "blouson", "vest", "sweaters",
    "sweater", "knitwear", "cardigan", "loungewear", "pajamas", "bodysuits", "coveralls",
}
CLOTHING_LEAF_FRAGMENTS = (
    "티셔츠", "스웨트셔츠", "팬츠", "바지", "스커트", "원피스", "아우터", "자켓", "재킷",
    "파카", "블루종", "베스트", "셔츠", "폴로", "니트", "가디건", "레깅스", "타이즈",
    "바디수트", "커버올", "파자마", "홈웨어", "의류", "polo shirt", "t shirt", "jacket",
    "pants", "shorts", "leggings", "sweat",
)
PROPOSED_CLOTHING_CONTEXT_CODES = {
    *CLOTHING_CODES, "shirts and blouses", "bras and bra tops", "inner tops", "one pieces",
    "loungewear and pajamas", "lounge and underwear collection",
}
PROPOSED_CLOTHING_LABEL_FRAGMENTS = (
    *CLOTHING_LEAF_FRAGMENTS, "shirts", "blouses", "polo", "t-shirts", "longsleeves", "sleeveles",
    "one pieces", "bra tops", "underwear", "loungewear", "pajamas", "bikini", "hiphugger",
)
NON_CLOTHING_CODES = {
    # Keep the original broad policy values and the explicit accessory values
    # in one declaration so neither rule set can silently drift.
    "accessories", "bags", "beauty", "electronics", "food", "home", "lifestyle",
    "shoes", "umbrella", "non_clothing", "goods", "socks", "sock", "hat", "caps",
    "cap", "beanie", "scarves", "belt", "belts", "bag", "sunglasses", "shoe", "footwear",
}
NON_CLOTHING_LABEL_FRAGMENTS = (
    "액세서리", "양말", "삭스", "우산", "모자", "벨트", "가방", "선글라스", "신발", "잡화",
    "accessories", "socks", "umbrella", "hat", "cap", "beanie", "scarf", "belt", "bag", "sunglasses", "shoes",
)


def norm(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip().lower())


def as_list(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    return [value] if value is not None else []


def walk_dicts(value: Any) -> Iterable[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_dicts(child)


def candidate_objects(item: dict[str, Any]) -> Iterable[dict[str, Any]]:
    """Visit catalog metadata containers, never measurement/image payloads."""
    yield item
    responses = item.get("responses")
    details = responses.get("details") if isinstance(responses, dict) else None
    body = details.get("body") if isinstance(details, dict) else None
    result = body.get("result") if isinstance(body, dict) else None
    for value in (responses, details, body, result):
        if isinstance(value, dict):
            yield value
    for key in ("category_observations", "category", "breadcrumbs"):
        value = item.get(key)
        if isinstance(value, dict):
            yield value
        elif isinstance(value, list):
            yield from (x for x in value if isinstance(x, dict))
def breadcrumb_nodes(item: dict[str, Any]) -> list[list[dict[str, Any]]]:
    """Collect API breadcrumb/category paths without using product titles."""
    paths: list[list[dict[str, Any]]] = []
    # Normalized catalog snapshots may retain the same API evidence as parallel
    # code/name arrays instead of materializing breadcrumb objects.
    for obj in candidate_objects(item):
        codes = obj.get("source_depth_codes")
        names = obj.get("source_depth_names")
        if isinstance(codes, list) and isinstance(names, list) and (codes or names):
            paths.append([
                {"id": codes[index] if index < len(codes) else "", "code": codes[index] if index < len(codes) else "",
                 "name": names[index] if index < len(names) else "", "role": f"depth{index + 1}"}
                for index in range(max(len(codes), len(names)))
            ])
        elif isinstance(obj.get("source_path"), str) and obj["source_path"].strip():
            names = [part.strip() for part in obj["source_path"].split(">")] if ">" in obj["source_path"] else []
            if names:
                paths.append([{"name": name, "role": f"depth{index + 1}"} for index, name in enumerate(names)])
    for obj in candidate_objects(item):
        for key in ("breadcrumb_items", "breadcrumbs", "breadcrumb", "categoryBreadcrumb"):
            value = obj.get(key)
            if isinstance(value, dict) and value:
                ordered = sorted(value.values(), key=lambda node: int(node.get("level", 999)) if isinstance(node, dict) else 999)
                if all(isinstance(x, dict) for x in ordered):
                    paths.append(ordered)
            if isinstance(value, list) and value and all(isinstance(x, dict) for x in value):
                paths.append(value)
        category = obj.get("category")
        if isinstance(category, dict):
            nodes = []
            for depth in range(1, 10):
                code = category.get(f"categoryDepth{depth}Code")
                title = category.get(f"categoryDepth{depth}Title") or category.get(f"categoryDepth{depth}Name")
                if code or title:
                    nodes.append({"id": code, "code": code, "name": title, "role": f"depth{depth}"})
            if nodes:
                paths.append(nodes)
    # Keep one copy of each ordered API path.
    unique: list[list[dict[str, Any]]] = []
    seen: set[str] = set()
    for path in paths:
        key = json.dumps(path, ensure_ascii=False, sort_keys=True)
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique


def category_code(node: dict[str, Any]) -> str:
    for key in ("code", "id", "categoryCode", "category_code", "categoryId", "category_id"):
        if node.get(key) not in (None, ""):
            return str(node[key])
    return ""


def category_label(node: dict[str, Any]) -> str:
    for key in ("name", "title", "categoryName", "categoryTitle", "locale"):
        if node.get(key) not in (None, ""):
            return str(node[key])
    return ""


def product_id(item: dict[str, Any], source_path: Path) -> str:
    for obj in candidate_objects(item):
        for key in ("product_key", "productId", "product_id", "goodsNo", "goods_no", "id"):
            value = obj.get(key)
            if value not in (None, "") and not isinstance(value, (dict, list)):
                return str(value)
        ids = obj.get("observed_ids")
        if isinstance(ids, list) and ids:
            return str(ids[0])
    return source_path.stem


def source_name(item: dict[str, Any], source_path: Path) -> str:
    for obj in candidate_objects(item):
        value = obj.get("source") or obj.get("retailer") or obj.get("mall")
        if isinstance(value, str) and value.strip():
            return value.strip()
    return source_path.parts[-2] if len(source_path.parts) > 1 else "unknown"


def product_name(item: dict[str, Any]) -> str | None:
    for obj in candidate_objects(item):
        for key in ("product_name", "productName", "name", "goodsNm"):
            value = obj.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return None


def review_proposal(nodes: list[dict[str, Any]]) -> tuple[str, str]:
    """Suggest a next review action without changing the stored decision."""
    candidates = [n for n in nodes if norm(n.get("role")) not in {"gender", "age"}]
    if not candidates:
        return "review_needed", "missing_api_category_evidence"
    for node in reversed(candidates):
        code, label = norm(node.get("code")), norm(node.get("label"))
        if code in PROPOSED_CLOTHING_CONTEXT_CODES or label in PROPOSED_CLOTHING_CONTEXT_CODES:
            return "clothing", "proposed_specific_clothing_category"
        if code in CLOTHING_LEAF_CODES or label in CLOTHING_LEAF_CODES or any(fragment in label for fragment in PROPOSED_CLOTHING_LABEL_FRAGMENTS):
            return "clothing", "proposed_clear_clothing_leaf_category"
    return "review_needed", "manual_review_unresolved_category_leaf"


def classify(item: dict[str, Any]) -> tuple[str, str, list[dict[str, Any]], str, dict[str, str] | None]:
    paths = breadcrumb_nodes(item)
    if not paths:
        return "review_needed", "missing_api_breadcrumb_or_category_code", [], "", None

    signatures = []
    for path in paths:
        nodes = [
            {"code": category_code(node), "label": category_label(node), "role": node.get("role", "")}
            for node in path
            if category_code(node) or category_label(node)
        ]
        if nodes:
            signatures.append(nodes)
    if not signatures:
        return "review_needed", "empty_api_breadcrumb_or_category_code", [], "", None

    # Multiple disagreeing API observations are never silently resolved.
    signature_keys = {tuple((norm(n["code"]), norm(n["label"])) for n in path) for path in signatures}
    if len(signature_keys) > 1:
        return "review_needed", "conflicting_api_category_observations", signatures[0], "", None

    nodes = signatures[0]
    candidates = [n for n in nodes if norm(n.get("role")) not in {"gender", "age"}]
    labels = [(norm(n["code"]), norm(n["label"])) for n in candidates]
    if any(code in NON_CLOTHING_CODES or any(fragment in label for fragment in NON_CLOTHING_LABEL_FRAGMENTS)
           for code, label in labels
    ):
        return "non_clothing", "api_category_identifies_non_clothing", nodes, nodes[-1]["code"], None
    for node in reversed(candidates):
        code, label = norm(node["code"]), norm(node["label"])
        if code in CLOTHING_CODES or label in CLOTHING_CODES:
            return "clothing", "specific_clothing_category", nodes, nodes[-1]["code"], {
                "matched_rule": "specific_clothing_category", "matched_category_code": node["code"], "matched_category_label": node["label"]
            }
        if code in CLOTHING_LEAF_CODES or label in CLOTHING_LEAF_CODES or any(fragment in label for fragment in CLOTHING_LEAF_FRAGMENTS):
            return "clothing", "clear_clothing_leaf_category", nodes, nodes[-1]["code"], {
                "matched_rule": "clear_clothing_leaf_category", "matched_category_code": node["code"], "matched_category_label": node["label"]
            }
    return "review_needed", "api_category_present_but_not_in_known_policy", nodes, nodes[-1]["code"], None


def extract_records(value: Any, path: Path) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [x for x in value if isinstance(x, dict)]
    if not isinstance(value, dict):
        return []
    for key in ("products", "items", "goods", "records", "results"):
        if isinstance(value.get(key), list):
            return [x for x in value[key] if isinstance(x, dict)]
    return [value]


def input_files(inputs: list[Path], default: Path) -> list[Path]:
    roots = inputs or [default]
    files: list[Path] = []
    for root in roots:
        if root.is_file() and root.suffix.lower() == ".json":
            files.append(root)
        elif root.is_dir():
            files.extend(sorted(root.rglob("*.json")))
    return sorted(set(files))


def load_json_file(file: Path) -> tuple[Path, bytes, Any]:
    raw = file.read_bytes()
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON: {file}: {exc}")
    return file, raw, parsed


def main() -> int:
    ap = argparse.ArgumentParser(description="Split retailer JSON into offline FitMatch manifests.")
    ap.add_argument("--input", action="append", type=Path, help="JSON file or directory; repeatable")
    ap.add_argument("--manifest-dir", type=Path, default=Path("data/manifests"))
    ap.add_argument("--report-dir", type=Path, default=Path("data/reports"))
    ap.add_argument("--run-name", default="catalog")
    args = ap.parse_args()

    files = input_files(args.input, Path("data/raw"))
    if not files:
        ap.error("no JSON inputs found; pass --input FILE or populate data/raw")
    args.manifest_dir.mkdir(parents=True, exist_ok=True)
    args.report_dir.mkdir(parents=True, exist_ok=True)

    rows: dict[str, list[dict[str, Any]]] = defaultdict(list)
    category_report: dict[str, dict[str, Any]] = {}
    input_sha256: dict[str, str] = {}
    broad_context_only_clothing_ids: list[str] = []
    # The collector directory is on a slow external/local filesystem. Threads
    # only overlap reads; every input remains an individual source file and is
    # still hashed and parsed independently.
    with ThreadPoolExecutor(max_workers=4) as executor:
        loaded_files = list(executor.map(load_json_file, files))
    for file, raw, parsed in loaded_files:
        input_sha256[str(file)] = hashlib.sha256(raw).hexdigest()
        for item in extract_records(parsed, file):
            decision, reason, nodes, leaf_code, match = classify(item)
            pid = product_id(item, file)
            source = source_name(item, file)
            name = product_name(item)
            path = " > ".join(n["label"] for n in nodes if n["label"])
            if decision == "clothing" and match is None:
                broad_context_only_clothing_ids.append(pid)
            row = {
                "product_id": pid,
                "product_name": name,
                "source": source,
                "decision": decision,
                "reason": reason,
                "category_code": leaf_code or None,
                "category_path": path or None,
                "api_categories": nodes,
                "input_file": str(file),
                "matched_rule": match["matched_rule"] if match else None,
                "matched_category_code": match["matched_category_code"] if match else None,
                "matched_category_label": match["matched_category_label"] if match else None,
                "proposed_decision": review_proposal(nodes)[0] if decision == "review_needed" else None,
                "proposed_rule": review_proposal(nodes)[1] if decision == "review_needed" else None,
            }
            rows[decision].append(row)
            key = f"{source}:{leaf_code or path or 'unknown'}"
            entry = category_report.setdefault(key, {
                "source": source, "category_code": leaf_code or None, "category_path": path or None,
                "counts": {decision_name: 0 for decision_name in DECISIONS}, "representative_product_ids": [],
            })
            entry["counts"][decision] += 1
            if len(entry["representative_product_ids"]) < 3:
                entry["representative_product_ids"].append(pid)

    for decision in DECISIONS:
        rows[decision].sort(key=lambda row: (row["source"], row["product_id"], row["input_file"]))
        out = args.manifest_dir / f"{args.run_name}.{decision}.jsonl"
        out.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows[decision]), encoding="utf-8")

    if broad_context_only_clothing_ids:
        raise SystemExit("classification policy violation: broad context alone classified as clothing: " + ",".join(broad_context_only_clothing_ids))
    review_rows = rows["review_needed"]
    review_groups: dict[str, dict[str, Any]] = {}
    for row in review_rows:
        group_key = row["category_path"] or "__missing_category_path__"
        group = review_groups.setdefault(group_key, {
            "category_path": row["category_path"],
            "count": 0,
            "proposed_decision": row["proposed_decision"],
            "proposed_rule": row["proposed_rule"],
            "representative_product": {
                "product_id": row["product_id"], "product_name": row["product_name"]
            },
            "product_ids": [],
        })
        group["count"] += 1
        group["product_ids"].append(row["product_id"])
    sock_rows = [
        row for decision_rows in rows.values() for row in decision_rows
        if any(token in norm(row.get("category_path")) for token in ("sock", "양말", "삭스"))
    ]
    report = {
        "run_name": args.run_name,
        "offline": True,
        "input_files": input_sha256,
        "input_file_count": len(files),
        "record_counts": {decision: len(rows[decision]) for decision in DECISIONS},
        "broad_context_only_clothing_count": len(broad_context_only_clothing_ids),
        "broad_context_only_clothing_ids": broad_context_only_clothing_ids,
        "review_needed_products": [
            {"product_id": row["product_id"], "category_code": row["category_code"],
             "category_path": row["category_path"], "reason": row["reason"]}
            for row in review_rows
        ],
        "sock_socks_count": len(sock_rows),
        "sock_socks_decision_counts": {
            decision: sum(row["decision"] == decision for row in sock_rows) for decision in DECISIONS
        },
        "review_category_path_group_count": sum(key != "__missing_category_path__" for key in review_groups),
        "review_missing_category_group_count": int("__missing_category_path__" in review_groups),
        "category_counts": sorted(category_report.values(), key=lambda x: (x["source"], x["category_path"] or "")),
    }
    (args.report_dir / f"{args.run_name}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.report_dir / f"{args.run_name}-review-groups.json").write_text(
        json.dumps({"group_count": len(review_groups), "groups": sorted(review_groups.values(), key=lambda x: x["category_path"] or "")}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"run_name": args.run_name, "record_counts": report["record_counts"], "category_count": len(report["category_counts"])}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
