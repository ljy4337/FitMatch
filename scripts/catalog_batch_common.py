#!/usr/bin/env python3
"""Shared trusted Supabase sync and payload adapters for retailer batches."""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Iterable


BATCH_INGEST_VERSION = "catalog-batch-2026-08-18-v1"
DEFAULT_SUPABASE_URL = "https://hnkplvyegonlhumlejst.supabase.co"
NUMBER = re.compile(r"^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$")


class BatchDatabaseError(RuntimeError):
    pass


class SupabaseBatchClient:
    def __init__(self, url: str | None = None, secret_key: str | None = None):
        self.url = (url or os.environ.get("FITMATCH_SUPABASE_URL") or DEFAULT_SUPABASE_URL).rstrip("/")
        self.secret_key = secret_key or os.environ.get("FITMATCH_SUPABASE_SECRET_KEY") or os.environ.get(
            "FITMATCH_SUPABASE_SERVICE_ROLE_KEY"
        )
        if not self.secret_key:
            raise BatchDatabaseError(
                "FITMATCH_SUPABASE_SECRET_KEY가 없습니다. 바탕화면 배치를 실행해 Keychain에 한 번 저장하세요."
            )

    def rpc(self, function: str, arguments: dict[str, Any]) -> Any:
        body = json.dumps(arguments, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        headers = {
            "apikey": self.secret_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        # Modern sb_secret keys are opaque and belong only in apikey. Legacy
        # service_role JWTs still require the Authorization header.
        if not self.secret_key.startswith("sb_secret_"):
            headers["Authorization"] = f"Bearer {self.secret_key}"
        request = urllib.request.Request(
            f"{self.url}/rest/v1/rpc/{function}", data=body, headers=headers, method="POST"
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise BatchDatabaseError(f"Supabase RPC {function} 실패(HTTP {error.code}): {detail}") from error
        except urllib.error.URLError as error:
            raise BatchDatabaseError(f"Supabase RPC {function} 연결 실패: {error}") from error
        return json.loads(payload) if payload else None

    def products_needing_ingest(self, source: str, product_ids: Iterable[str]) -> set[str]:
        ordered = list(dict.fromkeys(str(value) for value in product_ids if str(value)))
        result: set[str] = set()
        for offset in range(0, len(ordered), 5000):
            chunk = ordered[offset:offset + 5000]
            rows = self.rpc("fitmatch_batch_products_needing_ingest", {
                "p_source": source,
                "p_external_ids": chunk,
                "p_batch_version": BATCH_INGEST_VERSION,
            })
            result.update(row["external_product_id"] for row in (rows or []))
        return result

    def ingest_product(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.rpc("fitmatch_batch_ingest_product", {"p_payload": payload})


def numeric(value: Any) -> float | None:
    text = str(value).strip()
    return float(text) if NUMBER.fullmatch(text) else None


def uniqlo_payload(item: dict[str, Any]) -> dict[str, Any]:
    variants: list[dict[str, Any]] = []
    image_url = ""
    for result in (item.get("size_chart_payload") or {}).get("result") or []:
        image_url = image_url or str(result.get("imageUrl") or "")
        sizes = []
        for order, size in enumerate(result.get("sizeChart") or []):
            measurements = []
            for part in size.get("sizeParts") or []:
                cm = next((m for m in (part.get("measurements") or []) if m.get("unit") == "cm"), None)
                value = numeric(cm.get("value")) if cm else None
                if value is None or value <= 0:
                    continue
                measurements.append({
                    "measurement_identity": str(part.get("code") or part.get("name") or ""),
                    "raw_code": str(part.get("code") or ""),
                    "raw_label": str(part.get("name") or ""),
                    "raw_value": value,
                    "raw_unit": "cm",
                    "evidence": {"collector": "uniqlo_official_size_chart"},
                })
            label = str(size.get("name") or size.get("displayCode") or size.get("sizeCode") or "").strip()
            if label:
                sizes.append({
                    "size_identity": str(size.get("sizeCode") or size.get("displayCode") or label),
                    "external_size_id": str(size.get("sizeCode") or ""),
                    "size_label": label,
                    "normalized_size_label": str(size.get("displayCode") or label),
                    "display_order": order,
                    "measurements": measurements,
                    "raw_payload": {"display_code": size.get("displayCode")},
                })
        variants.append({
            "external_variant_id": str(result.get("productId") or "__default__"),
            "variant_name": str(result.get("productId") or "기본 옵션"),
            "color_code": str(result.get("colorCode") or ""),
            "sizes": sizes,
        })
    return {
        "source": "uniqlo",
        "external_product_id": str(item["product_id"]),
        "product_name": str(item["product_name"]),
        "canonical_url": str(item.get("canonical_url") or ""),
        "audience": str(item.get("audience") or ""),
        "source_category_path": str(item.get("source_path") or ""),
        "source_category_codes": [str(value) for value in item.get("source_depth_codes") or [] if value],
        "image_url": image_url,
        "raw_payload": {
            "batch_ingest_version": BATCH_INGEST_VERSION,
            "observed_ids": item.get("observed_ids") or [],
            "product_type": item.get("product_type"),
        },
        "variants": variants or [{"external_variant_id": "__default__", "sizes": []}],
    }


def _read_result_payload(result: dict[str, Any], kind: str) -> dict[str, Any]:
    reference = result.get(kind) or {}
    path = Path(str(reference.get("path") or ""))
    if not path.is_file():
        return {}
    return (json.loads(path.read_text(encoding="utf-8")).get("data") or {})


def musinsa_payload(result: dict[str, Any]) -> dict[str, Any]:
    detail = _read_result_payload(result, "product")
    actual_size = _read_result_payload(result, "actual_size")
    category = detail.get("category") or {}
    names = []
    codes = []
    for depth in range(1, 5):
        name = category.get(f"categoryDepth{depth}Name") or category.get(f"categoryDepth{depth}Title")
        code = category.get(f"categoryDepth{depth}Code")
        if name:
            names.append(str(name))
        if code:
            codes.append(str(code))
    source_path = " > ".join(names) or str(detail.get("baseCategoryFullPath") or result.get("category_path") or "")
    sizes = []
    for order, size in enumerate(actual_size.get("sizes") or []):
        label = str(size.get("name") or "").strip()
        if not label:
            continue
        measurements = []
        for measurement in size.get("items") or []:
            value = numeric(measurement.get("value"))
            name = str(measurement.get("name") or "").strip()
            if not name or value is None or value <= 0:
                continue
            measurements.append({
                "measurement_identity": name.lower(),
                "raw_label": name,
                "raw_value": value,
                "raw_unit": "cm",
                "evidence": {"collector": "musinsa_official_actual_size"},
            })
        sizes.append({
            "size_identity": label.lower(),
            "size_label": label,
            "normalized_size_label": label,
            "display_order": int(size.get("sequence") or order),
            "measurements": measurements,
        })
    images = detail.get("goodsImages") or []
    image_url = str(detail.get("thumbnailImageUrl") or (images[0].get("imageUrl") if images else "") or "")
    if image_url.startswith("//"):
        image_url = "https:" + image_url
    elif image_url.startswith("/"):
        image_url = "https://image.msscdn.net" + image_url
    audience = ",".join(str(value) for value in (detail.get("genders") or detail.get("sex") or []))
    return {
        "source": "musinsa",
        "external_product_id": str(result["product_id"]),
        "product_name": str(detail.get("goodsNm") or detail.get("goodsNmEng") or result.get("product_name") or ""),
        "canonical_url": f"https://www.musinsa.com/products/{result['product_id']}",
        "audience": audience,
        "source_category_path": source_path,
        "source_category_codes": codes,
        "image_url": image_url,
        "raw_payload": {
            "batch_ingest_version": BATCH_INGEST_VERSION,
            "brand": detail.get("brand") or result.get("brand"),
            "size_type": actual_size.get("typeName") or result.get("size_type"),
        },
        "sizes": sizes,
    }


def sync_payloads(
    client: SupabaseBatchClient,
    payloads: Iterable[dict[str, Any]],
    result_path: Path,
) -> tuple[set[str], list[dict[str, Any]]]:
    rows: list[dict[str, Any]] = []
    succeeded: set[str] = set()
    for payload in payloads:
        product_id = str(payload["external_product_id"])
        try:
            response = client.ingest_product(payload)
            classification = response.get("classification") or {}
            row = {
                "external_product_id": product_id,
                "status": "succeeded",
                "classification_status": classification.get("classification_status"),
                "category_code": classification.get("category_code"),
                "detail_code": classification.get("detail_code"),
                "comparison_family": classification.get("family_code"),
                "sizes_processed": response.get("sizes_processed", 0),
                "measurements_processed": response.get("measurements_processed", 0),
                "comparison_ready": response.get("comparison_ready", False),
            }
            succeeded.add(product_id)
        except Exception as error:
            row = {"external_product_id": product_id, "status": "failed", "error": str(error)}
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    result_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return succeeded, rows
