#!/usr/bin/env python3
"""Reproducible, public-only category corpus collector for FitMatch research.

Bootstrap mode only reads the restored 2026-07-23 survey. Live mode is explicit,
rate limited, resumable, and does not authenticate or attempt to bypass blocking.
"""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import html
import json
import math
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_SURVEY_DIR = REPO_ROOT / "Docs/Research/LiveProductSurvey-20260723"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "Docs/Research/CategoryCorpus-bootstrap"
DEFAULT_MEDIUM_DIR = REPO_ROOT / "Docs/Research/CategoryCorpus-live-medium"
CONFIG_PATH = SCRIPT_DIR / "known_categories.json"
MIN_DELAY_MS = 250
DEFAULT_RETRIES = 2
USER_AGENT = "FitMatchCategoryCorpusResearch/1.0 (+public category audit)"

PRODUCTS_HEADER = {
    "source": "쇼핑몰",
    "url": "상품 URL",
    "product_id": "상품 ID 또는 코드",
    "product_name": "상품명",
    "gender": "성별",
    "path": "쇼핑몰 원본 카테고리 전체 경로",
    "depth_names": [f"categoryDepth{i} 이름" for i in range(1, 5)],
    "depth_codes": [f"categoryDepth{i} ID" for i in range(1, 5)],
}

SOURCE_NAMES = {"무신사": "musinsa", "유니클로": "uniqlo"}
AUDIENCE_VALUES = {"MEN", "WOMEN", "KIDS", "BABY"}
AUDIENCE_ORDER = ("MEN", "WOMEN", "KIDS", "BABY")
UNIQLO_AUDIENCE_ROOTS = {
    "MEN": ["https://www.uniqlo.com/kr/ko/men"],
    "WOMEN": ["https://www.uniqlo.com/kr/ko/women"],
    "KIDS": ["https://www.uniqlo.com/kr/ko/kids"],
    "BABY": ["https://www.uniqlo.com/kr/ko/baby"],
}
CHECKPOINT_VERSION = 2
BABY_PROBE_CATEGORY_URL = "https://www.uniqlo.com/kr/ko/baby/newborn/bodysuits"
BABY_ROOT_URL = "https://www.uniqlo.com/kr/ko/baby"
BABY_ROOT_RAW_NAME = "8f9b7efaf10ecb94841d.html"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, fieldnames: list[str], rows: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def normalize_component(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "").strip())


def split_path(value: str) -> list[str]:
    return [
        normalize_component(part)
        for part in re.split(r"\s*(?:>|/)\s*", value or "")
        if normalize_component(part)
    ]


def normalized_path(value: str | list[str]) -> str:
    parts = split_path(value) if isinstance(value, str) else [
        normalize_component(part) for part in value if normalize_component(part)
    ]
    return " > ".join(parts)


def source_code(value: str) -> str:
    return SOURCE_NAMES.get(normalize_component(value), normalize_component(value).lower())


def uniqlo_identity(raw_id: str) -> tuple[str, str | None]:
    match = re.fullmatch(r"(E?\d+)(?:-(\d{3}))?", normalize_component(raw_id))
    if not match:
        return normalize_component(raw_id), None
    return match.group(1), match.group(2)


def product_identity(source: str, raw_id: str) -> tuple[str, str | None]:
    if source == "uniqlo":
        return uniqlo_identity(raw_id)
    return normalize_component(raw_id), None


def path_prefixes(parts: list[str]) -> Iterable[list[str]]:
    for index in range(1, len(parts) + 1):
        yield parts[:index]


def configured_flags(
    source: str,
    path: str,
    config: dict[str, Any],
    alternate_paths: Iterable[str] = (),
) -> dict[str, Any]:
    normalized = normalized_path(path)
    candidate_paths = [normalized] + [
        normalized_path(candidate) for candidate in alternate_paths if normalized_path(candidate)
    ]
    candidate_path_keys = {candidate.casefold() for candidate in candidate_paths}
    terminal_keys = {
        parts[-1].casefold()
        for candidate in candidate_paths
        if (parts := split_path(candidate))
    }
    existing = {
        normalized_path(item).casefold()
        for item in config["existing_source_category_paths"]
    }
    result: dict[str, Any] = {
        "is_existing_source_category": bool(candidate_path_keys & existing),
        "is_db_candidate": not bool(candidate_path_keys & existing),
        "unresolved_rule": "",
        "unresolved_reason": "",
    }
    for rule in config["unresolved_rules"]:
        if rule["source"] not in ("*", source):
            continue
        exact = {normalized_path(item).casefold() for item in rule.get("exact_paths", [])}
        terminals = {item.casefold() for item in rule.get("terminal_labels", [])}
        matches = bool(candidate_path_keys & exact)
        matches = matches or bool(terminal_keys & terminals)
        if matches:
            result["is_db_candidate"] = False
            result["unresolved_rule"] = rule["id"]
            result["unresolved_reason"] = rule["reason"]
            break
    return result


def classify_node_status(
    direct_product_count: int,
    child_count: int,
    is_navigation_observed: bool,
    is_unresolved: bool,
) -> str:
    if is_unresolved:
        return "unresolved"
    if direct_product_count and child_count:
        return "leaf_and_parent"
    if direct_product_count:
        return "direct_product_leaf"
    if child_count:
        return "intermediate"
    if is_navigation_observed:
        return "navigation_only"
    return "unresolved"


def validate_survey(survey_dir: Path) -> dict[str, Any]:
    expected_files = {
        "categories.csv",
        "category-mappings.csv",
        "category-measurements.csv",
        "duplicates.csv",
        "failures.csv",
        "field-aliases.csv",
        "parser-cases.csv",
        "products.csv",
        "report.md",
        "sources.md",
        "verification.md",
    }
    actual_files = {path.name for path in survey_dir.iterdir() if path.is_file()}
    products = read_csv(survey_dir / "products.csv")
    categories = read_csv(survey_dir / "categories.csv")
    by_source = defaultdict(int)
    unique_paths: dict[str, set[str]] = defaultdict(set)
    observed_product_keys: set[tuple[str, str]] = set()
    base_product_keys: set[tuple[str, str]] = set()
    for row in products:
        source = source_code(row[PRODUCTS_HEADER["source"]])
        product_key, _ = product_identity(source, row[PRODUCTS_HEADER["product_id"]])
        by_source[source] += 1
        observed_product_keys.add((source, normalize_component(row[PRODUCTS_HEADER["product_id"]])))
        base_product_keys.add((source, product_key))
    for row in categories:
        source = source_code(row["쇼핑몰"])
        unique_paths[source].add(normalized_path(row["원본 카테고리 전체 경로"]))

    checks = {
        "file_count_11": len(actual_files) == 11 and actual_files == expected_files,
        "unique_products_300": len(observed_product_keys) == 300,
        "musinsa_products_200": by_source["musinsa"] == 200,
        "uniqlo_products_100": by_source["uniqlo"] == 100,
        "musinsa_unique_paths_30": len(unique_paths["musinsa"]) == 30,
        "uniqlo_unique_paths_5": len(unique_paths["uniqlo"]) == 5,
    }
    return {
        "passed": all(checks.values()),
        "checks": checks,
        "actual": {
            "files": sorted(actual_files),
            "file_count": len(actual_files),
            "unique_products": len(observed_product_keys),
            "unique_base_products": len(base_product_keys),
            "products_by_source": dict(sorted(by_source.items())),
            "unique_category_paths_by_source": {
                key: len(value) for key, value in sorted(unique_paths.items())
            },
        },
    }


def bootstrap(survey_dir: Path, output_dir: Path) -> dict[str, Any]:
    validation = validate_survey(survey_dir)
    if not validation["passed"]:
        raise RuntimeError(f"Survey integrity check failed: {validation}")

    config = read_json(CONFIG_PATH)
    products = read_csv(survey_dir / "products.csv")
    category_rows = read_csv(survey_dir / "categories.csv")
    mapping_rows = read_csv(survey_dir / "category-mappings.csv")
    mapping_certainty: dict[tuple[str, str], set[str]] = defaultdict(set)
    for row in mapping_rows:
        key = (source_code(row["쇼핑몰"]), normalized_path(row["원본 카테고리 경로"]))
        mapping_certainty[key].add(row["확정 여부"])

    manifest_by_key: dict[tuple[str, str], dict[str, Any]] = {}
    direct_exposures: dict[tuple[str, str], set[str]] = defaultdict(set)
    exposure_rows: list[dict[str, Any]] = []
    path_rows: list[dict[str, Any]] = []

    for row in products:
        source = source_code(row[PRODUCTS_HEADER["source"]])
        raw_id = row[PRODUCTS_HEADER["product_id"]]
        identity, color_code = product_identity(source, raw_id)
        path = normalized_path(row[PRODUCTS_HEADER["path"]])
        names = [normalize_component(row[name]) for name in PRODUCTS_HEADER["depth_names"]]
        codes = [normalize_component(row[name]) for name in PRODUCTS_HEADER["depth_codes"]]
        names = [name for name in names if name]
        direct_exposures[(source, path)].add(identity)
        key = (source, identity)
        manifest = manifest_by_key.setdefault(
            key,
            {
                "source": source,
                "product_key": identity,
                "observed_ids": [],
                "color_codes": [],
                "product_name": row[PRODUCTS_HEADER["product_name"]],
                "product_url": row[PRODUCTS_HEADER["url"]],
                "audience": row[PRODUCTS_HEADER["gender"]],
                "exposure_paths": [],
                "evidence": "restored_survey_products.csv",
            },
        )
        if raw_id not in manifest["observed_ids"]:
            manifest["observed_ids"].append(raw_id)
        if color_code and color_code not in manifest["color_codes"]:
            manifest["color_codes"].append(color_code)
        if path and path not in manifest["exposure_paths"]:
            manifest["exposure_paths"].append(path)
        exposure_rows.append(
            {
                "source": source,
                "product_key": identity,
                "observed_id": raw_id,
                "color_code": color_code or "",
                "category_path": path,
                "category_url": "",
                "evidence_url": row["카테고리 출처"],
                "evidence_type": "restored_survey",
            }
        )
        path_rows.append(
            {
                "source": source,
                "product_key": identity,
                "observed_id": raw_id,
                "product_name": row[PRODUCTS_HEADER["product_name"]],
                "audience": row[PRODUCTS_HEADER["gender"]],
                "category_path": path,
                **{
                    f"depth{index}_name": names[index - 1] if len(names) >= index else ""
                    for index in range(1, 5)
                },
                **{
                    f"depth{index}_code": codes[index - 1] if len(codes) >= index else ""
                    for index in range(1, 5)
                },
                "evidence_url": row["카테고리 출처"],
                "evidence_source": "restored_survey",
                "breadcrumb_evidence_json": "",
                "unresolved_reason": "",
            }
        )

    nodes: dict[tuple[str, str], dict[str, Any]] = {}
    for row in category_rows:
        source = source_code(row["쇼핑몰"])
        full_parts = split_path(row["원본 카테고리 전체 경로"])
        depth_codes = [normalize_component(row[f"categoryDepth{i} ID"]) for i in range(1, 5)]
        for parts in path_prefixes(full_parts):
            path = normalized_path(parts)
            key = (source, path)
            node = nodes.setdefault(
                key,
                {
                    "source": source,
                    "path": path,
                    "name": parts[-1],
                    "depth": len(parts),
                    "parent_path": normalized_path(parts[:-1]),
                    "category_codes": [],
                    "audiences": [],
                    "direct_product_count": 0,
                    "child_count": 0,
                    "status": "",
                    "mapping_certainty": [],
                },
            )
            code = depth_codes[len(parts) - 1] if len(depth_codes) >= len(parts) else ""
            if code and code not in node["category_codes"]:
                node["category_codes"].append(code)
            audience = normalize_component(row["성별 또는 섹션"])
            if audience and audience not in node["audiences"]:
                node["audiences"].append(audience)

    node_keys = set(nodes)
    for key, node in nodes.items():
        source, path = key
        node["direct_product_count"] = len(direct_exposures.get(key, set()))
        node["child_count"] = sum(
            1 for child_source, child_path in node_keys
            if child_source == source and normalized_path(split_path(child_path)[:-1]) == path
        )
        certainty = mapping_certainty.get(key, set())
        node["mapping_certainty"] = sorted(certainty)
        flags = configured_flags(source, path, config)
        node.update(flags)
        is_unresolved = bool(flags["unresolved_rule"] or "검토 필요" in certainty)
        node["status"] = classify_node_status(
            node["direct_product_count"],
            node["child_count"],
            True,
            is_unresolved,
        )
        if is_unresolved:
            if not node["unresolved_reason"]:
                node["unresolved_reason"] = "복구된 조사 자료에서 매핑 검토 필요"
            node["is_db_candidate"] = False

    unresolved_rows = [
        {
            "source": node["source"],
            "category_path": node["path"],
            "status": node["status"],
            "rule": node["unresolved_rule"] or "survey_review_needed",
            "reason": node["unresolved_reason"],
            "direct_product_count": node["direct_product_count"],
        }
        for node in nodes.values()
        if node["status"] == "unresolved"
    ]

    output_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = output_dir / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    (raw_dir / "README.md").write_text(
        "# Raw responses\n\n"
        "Bootstrap mode performs no network requests. The restored survey contains "
        "derived CSV evidence, not original HTTP response bodies, so no response "
        "has been synthesized here. Live mode stores response bodies in this directory.\n",
        encoding="utf-8",
    )
    write_json(
        output_dir / "category_inventory.json",
        {
            "mode": "bootstrap",
            "generated_at": utc_now(),
            "nodes": sorted(nodes.values(), key=lambda item: (item["source"], item["path"])),
        },
    )
    write_json(
        output_dir / "product_manifest.json",
        {
            "mode": "bootstrap",
            "generated_at": utc_now(),
            "products": sorted(
                manifest_by_key.values(), key=lambda item: (item["source"], item["product_key"])
            ),
        },
    )
    path_fields = [
        "source", "product_key", "observed_id", "product_name", "audience", "category_path",
        "depth1_name", "depth1_code", "depth2_name", "depth2_code",
        "depth3_name", "depth3_code", "depth4_name", "depth4_code", "evidence_url",
        "evidence_source", "breadcrumb_evidence_json", "unresolved_reason",
    ]
    write_csv(output_dir / "product_category_paths.csv", path_fields, path_rows)
    exposure_fields = [
        "source", "product_key", "observed_id", "color_code", "category_path",
        "category_url", "evidence_url", "evidence_type",
    ]
    write_csv(output_dir / "category_exposures.csv", exposure_fields, exposure_rows)
    unresolved_fields = [
        "source", "category_path", "status", "rule", "reason", "direct_product_count",
    ]
    write_csv(output_dir / "unresolved_categories.csv", unresolved_fields, unresolved_rows)

    statuses = defaultdict(int)
    for node in nodes.values():
        statuses[node["status"]] += 1
    summary = (
        "# Category corpus bootstrap summary\n\n"
        f"- Generated: {utc_now()}\n"
        "- Network requests: 0\n"
        f"- Survey integrity: {'PASS' if validation['passed'] else 'FAIL'}\n"
        f"- Unique products: {validation['actual']['unique_products']}\n"
        f"- Unique base products after source-specific deduplication: "
        f"{validation['actual']['unique_base_products']}\n"
        f"- Musinsa products: {validation['actual']['products_by_source']['musinsa']}\n"
        f"- Uniqlo products: {validation['actual']['products_by_source']['uniqlo']}\n"
        f"- Musinsa unique observed paths: "
        f"{validation['actual']['unique_category_paths_by_source']['musinsa']}\n"
        f"- Uniqlo unique observed paths: "
        f"{validation['actual']['unique_category_paths_by_source']['uniqlo']}\n"
        f"- Inventory nodes including prefixes: {len(nodes)}\n"
        f"- Node statuses: {json.dumps(dict(sorted(statuses.items())), ensure_ascii=False)}\n"
        f"- Unresolved nodes: {len(unresolved_rows)}\n"
        "- Raw response bodies: 0 (not present in the restored survey)\n"
        "- Existing source-category paths are marked is_db_candidate=false.\n"
        "- This output is research evidence and is not a database seed.\n"
    )
    (output_dir / "collection_summary.md").write_text(summary, encoding="utf-8")
    write_json(output_dir / "bootstrap_validation.json", validation)
    return {
        "validation": validation,
        "output_dir": str(output_dir),
        "inventory_nodes": len(nodes),
        "manifest_products": len(manifest_by_key),
        "unresolved_nodes": len(unresolved_rows),
        "network_requests": 0,
    }


class LinkExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        href = dict(attrs).get("href")
        if href:
            self.links.append(html.unescape(href))


@dataclass
class FetchResult:
    url: str
    status: int
    content_type: str
    body: bytes


class CollectionStopped(RuntimeError):
    pass


class HTTPStatusError(RuntimeError):
    def __init__(self, status: int, url: str) -> None:
        super().__init__(f"HTTP {status}: {url}")
        self.status = status
        self.url = url


def retry_after_seconds(value: str | None) -> float:
    if not value:
        return 0
    try:
        return max(0, float(value))
    except ValueError:
        try:
            target = parsedate_to_datetime(value)
        except (TypeError, ValueError):
            return 0
        if target.tzinfo is None:
            target = target.replace(tzinfo=timezone.utc)
        return max(0, (target - datetime.now(timezone.utc)).total_seconds())


class RateLimitedFetcher:
    def __init__(
        self,
        delay_ms: int,
        retries: int,
        event_handler: Any | None = None,
    ) -> None:
        if delay_ms < MIN_DELAY_MS:
            raise ValueError(f"delay-ms must be at least {MIN_DELAY_MS}")
        if not 0 <= retries <= 5:
            raise ValueError("retries must be between 0 and 5")
        self.delay_seconds = delay_ms / 1000
        self.retries = retries
        self.last_request_at = 0.0
        self.request_count = 0
        self.consecutive_network_failures = 0
        self.event_handler = event_handler

    def record_event(self, event: dict[str, Any]) -> None:
        if self.event_handler:
            self.event_handler(event)

    def fetch(
        self,
        url: str,
        referer: str | None = None,
        context: dict[str, Any] | None = None,
    ) -> FetchResult:
        last_error: Exception | None = None
        for attempt in range(self.retries + 1):
            wait = self.delay_seconds - (time.monotonic() - self.last_request_at)
            if wait > 0:
                time.sleep(wait)
            headers = {"User-Agent": USER_AGENT, "Accept": "*/*"}
            if referer:
                headers["Referer"] = referer
            request = urllib.request.Request(url, headers=headers)
            started_at = utc_now()
            started = time.monotonic()
            event_context = dict(context or {})
            try:
                self.last_request_at = time.monotonic()
                self.request_count += 1
                with urllib.request.urlopen(request, timeout=20) as response:
                    result = FetchResult(
                        url=response.geturl(),
                        status=response.status,
                        content_type=response.headers.get("Content-Type", ""),
                        body=response.read(),
                    )
                self.consecutive_network_failures = 0
                self.record_event(
                    {
                        **event_context,
                        "url": url,
                        "final_url": result.url,
                        "attempt": attempt,
                        "started_at": started_at,
                        "duration_ms": round((time.monotonic() - started) * 1000, 3),
                        "status": result.status,
                        "outcome": "success",
                        "retry_after_seconds": 0,
                    }
                )
                return result
            except urllib.error.HTTPError as error:
                last_error = error
                self.consecutive_network_failures = 0
                retry_after = retry_after_seconds(error.headers.get("Retry-After"))
                self.record_event(
                    {
                        **event_context,
                        "url": url,
                        "final_url": error.geturl(),
                        "attempt": attempt,
                        "started_at": started_at,
                        "duration_ms": round((time.monotonic() - started) * 1000, 3),
                        "status": error.code,
                        "outcome": "http_error",
                        "retry_after_seconds": retry_after,
                    }
                )
                if error.code in {403, 429}:
                    if retry_after > 0:
                        time.sleep(retry_after)
                    raise CollectionStopped(
                        f"HTTP {error.code}; additional requests stopped"
                    ) from error
                if error.code >= 500 and attempt < self.retries:
                    time.sleep(self.delay_seconds * (attempt + 1))
                    continue
                raise HTTPStatusError(error.code, url) from error
            except (urllib.error.URLError, TimeoutError) as error:
                last_error = error
                self.consecutive_network_failures += 1
                self.record_event(
                    {
                        **event_context,
                        "url": url,
                        "final_url": "",
                        "attempt": attempt,
                        "started_at": started_at,
                        "duration_ms": round((time.monotonic() - started) * 1000, 3),
                        "status": None,
                        "outcome": "network_error",
                        "retry_after_seconds": 0,
                        "error_type": type(error).__name__,
                    }
                )
                if self.consecutive_network_failures >= 5:
                    raise CollectionStopped(
                        "Five consecutive network failures; additional requests stopped"
                    ) from error
                if attempt < self.retries:
                    time.sleep(self.delay_seconds * (attempt + 1))
        raise RuntimeError(f"Request failed after {self.retries + 1} attempts: {url}: {last_error}")


def canonical_url(base: str, href: str) -> str:
    absolute = urllib.parse.urljoin(base, href)
    parsed = urllib.parse.urlsplit(absolute)
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc.lower(), parsed.path, parsed.query, ""))


INVALID_UNIQLO_PATH_COMPONENTS = {"undefined", "null", "none"}


def validated_uniqlo_category_href(
    page_url: str,
    href: str,
) -> tuple[str | None, str]:
    raw_href = html.unescape(href).strip()
    if not raw_href:
        return None, "empty href"
    absolute = urllib.parse.urljoin(page_url, raw_href)
    parsed = urllib.parse.urlsplit(absolute)
    if parsed.scheme != "https":
        return None, "category URL scheme must be https"
    if parsed.netloc.lower() != "www.uniqlo.com":
        return None, "category URL host must be www.uniqlo.com"
    if parsed.fragment:
        return None, "category URL fragment is not allowed"
    decoded_path = urllib.parse.unquote(parsed.path)
    segments = [segment for segment in decoded_path.split("/") if segment]
    lowered = [segment.casefold() for segment in segments]
    if any(segment in INVALID_UNIQLO_PATH_COMPONENTS for segment in lowered):
        return None, "category URL contains an undefined/null path component"
    if len(lowered) < 3 or lowered[:2] != ["kr", "ko"]:
        return None, "category URL must start with the /kr/ko locale path"
    if lowered[2] not in {"men", "women", "kids", "baby"}:
        return None, "category URL does not contain a supported audience segment"
    locale_positions = [
        index
        for index in range(len(lowered) - 1)
        if lowered[index : index + 2] == ["kr", "ko"]
    ]
    if locale_positions != [0]:
        return None, "category URL contains a duplicated locale path"
    normalized_path = "/" + "/".join(segments)
    return (
        urllib.parse.urlunsplit(
            ("https", "www.uniqlo.com", normalized_path, parsed.query, "")
        ),
        "",
    )


def uniqlo_link_evidence(
    page_url: str,
    body: bytes,
) -> tuple[set[str], set[str], list[dict[str, str]]]:
    parser = LinkExtractor()
    parser.feed(body.decode("utf-8", errors="replace"))
    categories: set[str] = set()
    products: set[str] = set()
    rejected: list[dict[str, str]] = []
    for raw_order, href in enumerate(parser.links):
        generic_url = canonical_url(page_url, href)
        generic_parts = urllib.parse.urlsplit(generic_url)
        product_match = re.search(
            r"/products/(E?\d+(?:-\d{3})?)",
            generic_parts.path,
            re.IGNORECASE,
        )
        if product_match:
            products.add(product_match.group(1).upper())
            continue
        if not audience_from_uniqlo_url(generic_url):
            continue
        category_url, reason = validated_uniqlo_category_href(page_url, href)
        if category_url is not None:
            categories.add(category_url)
            continue
        rejected.append(
            {
                "page_url": page_url,
                "raw_href": href,
                "resolved_url": generic_url,
                "raw_order": str(raw_order),
                "evidence_source": "html_a_href",
                "reason": reason,
            }
        )
    return categories, products, rejected


def discover_links(source: str, page_url: str, body: bytes) -> tuple[set[str], set[str]]:
    parser = LinkExtractor()
    parser.feed(body.decode("utf-8", errors="replace"))
    categories: set[str] = set()
    products: set[str] = set()
    for href in parser.links:
        url = canonical_url(page_url, href)
        parsed = urllib.parse.urlsplit(url)
        if source == "musinsa":
            match = re.search(r"/products/(\d+)", parsed.path)
            if match:
                products.add(match.group(1))
            elif parsed.netloc.endswith("musinsa.com") and "/category/" in parsed.path:
                categories.add(url)
        elif source == "uniqlo":
            match = re.search(r"/products/(E?\d+(?:-\d{3})?)", parsed.path, re.IGNORECASE)
            if match:
                products.add(match.group(1).upper())
            elif parsed.netloc.endswith("uniqlo.com") and re.match(
                r"^/kr/ko/(?:men|women|kids|baby)(?:/|$)", parsed.path, re.IGNORECASE
            ):
                categories.add(url)
    return categories, products


def uniqlo_category_page_evidence(page_url: str, body: bytes) -> dict[str, Any]:
    """Extract only audience-grounded category/product evidence from saved PLP HTML."""
    audience = audience_from_uniqlo_url(page_url)
    categories, linked_products, rejected_urls = uniqlo_link_evidence(page_url, body)
    audience_categories = {
        url for url in categories if audience_from_uniqlo_url(url) == audience
    }
    result: dict[str, Any] = {
        "audience": audience,
        "category_urls": sorted(audience_categories),
        "product_ids": sorted(linked_products),
        "cms_product_observations": [],
        "taxonomy_nodes": [],
        "rejected_category_urls": rejected_urls,
        "evidence_source": "html_links",
    }
    state = hydration_state(body.decode("utf-8", errors="replace"))
    if state is None or audience not in AUDIENCE_VALUES:
        return result

    taxonomies = state.get("taxonomies", {})
    if isinstance(taxonomies, dict):
        for level_name in ("classes", "categories", "subcategories"):
            values = taxonomies.get(level_name, [])
            if not isinstance(values, list):
                continue
            for item in values:
                if not isinstance(item, dict):
                    continue
                parents = item.get("parents", [])
                if not isinstance(parents, list) or not any(
                    isinstance(parent, dict)
                    and normalize_component(str(parent.get("name") or "")).upper() == audience
                    and normalize_component(str(parent.get("key") or "")).lower()
                    == audience.lower()
                    for parent in parents
                ):
                    continue
                result["taxonomy_nodes"].append(
                    {
                        "level": level_name,
                        "id": item.get("id"),
                        "name": item.get("name", ""),
                        "key": item.get("key", ""),
                        "parents": parents,
                        "evidence_path": f"taxonomies.{level_name}",
                    }
                )

    cms = state.get("cms", {}).get("/home/v2", {})
    components = cms.get("components", {}) if isinstance(cms, dict) else {}
    bodies = components.get("body", []) if isinstance(components, dict) else []
    for body_index, body_item in enumerate(bodies if isinstance(bodies, list) else []):
        if not isinstance(body_item, dict):
            continue
        audience_sections = body_item.get(audience.lower(), [])
        for section_index, section in enumerate(
            audience_sections if isinstance(audience_sections, list) else []
        ):
            contents = section.get("content", []) if isinstance(section, dict) else []
            for content_index, content in enumerate(
                contents if isinstance(contents, list) else []
            ):
                product_ids = content.get("productIds") if isinstance(content, dict) else None
                if not isinstance(product_ids, dict):
                    continue
                for bucket in ("prioritized", "default", "deprioritized"):
                    raw_ids = product_ids.get(bucket, [])
                    for raw_id in raw_ids if isinstance(raw_ids, list) else []:
                        raw_value = normalize_component(str(raw_id)).upper()
                        match = re.fullmatch(r"(E?\d+-\d{3})(?:-\d{2})?", raw_value)
                        if not match:
                            continue
                        observed_id = match.group(1)
                        result["product_ids"].append(observed_id)
                        result["cms_product_observations"].append(
                            {
                                "raw_product_id": raw_value,
                                "observed_id": observed_id,
                                "audience": audience,
                                "bucket": bucket,
                                "evidence_path": (
                                    "cms./home/v2.components.body"
                                    f"[{body_index}].{audience.lower()}[{section_index}]"
                                    f".content[{content_index}].productIds.{bucket}"
                                ),
                            }
                        )
    result["product_ids"] = sorted(set(result["product_ids"]))
    if result["cms_product_observations"]:
        result["evidence_source"] = "html_links+uniqlo_hydration_cms"
    return result


def merge_uniqlo_category_discovery(
    audience_states: dict[str, dict[str, Any]],
    queue_audience: str,
    local_queue: deque[str],
    visited: set[str],
    category_urls: Iterable[str],
) -> None:
    for category_url in sorted(set(category_urls)):
        target_audience = audience_from_uniqlo_url(category_url)
        if target_audience not in AUDIENCE_VALUES:
            continue
        if target_audience == queue_audience:
            if category_url not in visited and category_url not in local_queue:
                local_queue.append(category_url)
            continue
        target_state = audience_states[target_audience]
        if (
            category_url not in target_state["visited_categories"]
            and category_url not in target_state["queue"]
        ):
            target_state["queue"].append(category_url)


def baby_probe_plan(medium_dir: Path) -> dict[str, Any]:
    root_raw = (
        medium_dir
        / "raw/uniqlo/category-pages"
        / BABY_ROOT_RAW_NAME
    )
    if not root_raw.is_file():
        raise RuntimeError(f"Saved BABY root raw is missing: {root_raw}")
    evidence = uniqlo_category_page_evidence(BABY_ROOT_URL, root_raw.read_bytes())
    observations = evidence["cms_product_observations"]
    if len(observations) != 4:
        raise RuntimeError(
            f"Expected exactly four saved BABY CMS observations, found {len(observations)}"
        )
    product_requests = [
        {
            **observation,
            "url": (
                "https://www.uniqlo.com/kr/ko/products/"
                f"{observation['observed_id']}"
            ),
        }
        for observation in observations
    ]
    return {
        "category_request": {
            "url": BABY_PROBE_CATEGORY_URL,
            "source": "saved_baby_html_href",
        },
        "product_requests": product_requests,
        "logical_request_limit": 5,
        "source_raw": str(root_raw),
        "source_raw_sha256": sha256_file(root_raw),
    }


def matched_hydration_product(
    body: bytes,
    observed_id: str,
    selected_entity_key: str,
) -> dict[str, Any]:
    state = hydration_state(body.decode("utf-8", errors="replace"))
    entities = state.get("entity", {}).get("pdpEntity", {}) if state else {}
    entity = entities.get(selected_entity_key, {}) if isinstance(entities, dict) else {}
    product = entity.get("product", {}) if isinstance(entity, dict) else {}
    return {
        "selected_entity_key": selected_entity_key,
        "requested_observed_id": observed_id,
        "hydration_product_id": normalize_component(str(product.get("productId") or "")).upper(),
    }


def parse_cms_product_id(raw_product_id: str) -> tuple[str, str]:
    match = re.fullmatch(r"(E?\d+-\d{3})-(\d{2})", normalize_component(raw_product_id).upper())
    if not match:
        raise ValueError(f"Unsupported CMS product ID structure: {raw_product_id}")
    return match.group(1), match.group(2)


def validate_probe_result_url(
    expected: str,
    actual: str,
    raw_product_id: str | None = None,
) -> dict[str, Any]:
    expected_parts = urllib.parse.urlsplit(expected)
    actual_parts = urllib.parse.urlsplit(actual)
    if expected_parts.query or expected_parts.fragment or actual_parts.query or actual_parts.fragment:
        raise CollectionStopped("Query or fragment is not allowed in BABY probe URLs")
    if expected_parts.scheme != "https" or actual_parts.scheme != "https":
        raise CollectionStopped("BABY probe URL scheme must remain https")
    if (
        expected_parts.netloc.lower() != "www.uniqlo.com"
        or actual_parts.netloc.lower() != "www.uniqlo.com"
    ):
        raise CollectionStopped("BABY probe URL host must remain www.uniqlo.com")

    if raw_product_id is None:
        if actual_parts.path.rstrip("/") != expected_parts.path.rstrip("/"):
            raise CollectionStopped(
                f"Unexpected final URL during BABY probe: expected {expected}, got {actual}"
            )
        return {"allowed": True, "base_product_id": "", "variant_suffix": ""}

    try:
        base_product_id, variant_suffix = parse_cms_product_id(raw_product_id)
    except ValueError as error:
        raise CollectionStopped(str(error)) from error
    expected_path = f"/kr/ko/products/{base_product_id}"
    allowed_final_path = f"{expected_path}/{variant_suffix}"
    if expected_parts.path.rstrip("/") != expected_path:
        raise CollectionStopped(
            f"Requested product path does not match CMS base product ID {base_product_id}"
        )
    if actual_parts.path.rstrip("/") != allowed_final_path:
        raise CollectionStopped(
            "Final product path does not match CMS base product ID and variant suffix: "
            f"expected {allowed_final_path}, got {actual_parts.path}"
        )
    return {
        "allowed": True,
        "base_product_id": base_product_id,
        "variant_suffix": variant_suffix,
        "allowed_final_path": allowed_final_path,
    }


VARIANT_SELECTION_RULE = "canonical_redirect_matches_raw_variant"


def validate_canonical_product_url(
    expected: str,
    actual: str,
    base_product_id: str,
) -> dict[str, Any]:
    expected_parts = urllib.parse.urlsplit(expected)
    actual_parts = urllib.parse.urlsplit(actual)
    if expected_parts.query or expected_parts.fragment or actual_parts.query or actual_parts.fragment:
        raise CollectionStopped("Query or fragment is not allowed in BABY collection URLs")
    if expected_parts.scheme != "https" or actual_parts.scheme != "https":
        raise CollectionStopped("BABY collection URL scheme must remain https")
    if (
        expected_parts.netloc.lower() != "www.uniqlo.com"
        or actual_parts.netloc.lower() != "www.uniqlo.com"
    ):
        raise CollectionStopped("BABY collection URL host must remain www.uniqlo.com")
    normalized_base = normalize_component(base_product_id).upper()
    if not re.fullmatch(r"E?\d+-\d{3}", normalized_base):
        raise CollectionStopped(f"Unsupported base product ID structure: {base_product_id}")
    expected_path = f"/kr/ko/products/{normalized_base}"
    if expected_parts.path.rstrip("/") != expected_path:
        raise CollectionStopped(
            f"Requested product path does not match base product ID {normalized_base}"
        )
    match = re.fullmatch(
        rf"{re.escape(expected_path)}/(\d{{2}})",
        actual_parts.path.rstrip("/"),
    )
    if not match:
        raise CollectionStopped(
            "Final product path does not match the requested locale and base product ID: "
            f"{actual_parts.path}"
        )
    return {
        "allowed": True,
        "base_product_id": normalized_base,
        "canonical_suffix": match.group(1),
        "allowed_final_path": actual_parts.path.rstrip("/"),
    }


def select_canonical_raw_variant(
    base_product_id: str,
    canonical_suffix: str,
    observations: list[dict[str, Any]],
) -> dict[str, Any]:
    normalized_base = normalize_component(base_product_id).upper()
    preserved: list[dict[str, Any]] = []
    for observation in observations:
        raw_id = normalize_component(str(observation.get("raw_product_id") or "")).upper()
        try:
            observed_base, observed_suffix = parse_cms_product_id(raw_id)
        except ValueError:
            continue
        if observed_base != normalized_base:
            continue
        preserved.append(
            {
                "raw_product_id": raw_id,
                "base_product_id": observed_base,
                "suffix": observed_suffix,
                "raw_order": observation.get("raw_order"),
                "evidence_path": observation.get("evidence_path", ""),
                "search_key": observation.get("search_key", ""),
            }
        )
    preserved.sort(
        key=lambda item: (
            item["raw_order"] if isinstance(item["raw_order"], int) else sys.maxsize
        )
    )
    first = preserved[0] if preserved else None
    matches = [item for item in preserved if item["suffix"] == canonical_suffix]
    selected = matches[0] if matches else None
    unresolved_reason = ""
    if not preserved:
        unresolved_reason = (
            f"No valid raw variant observations exist for base product {normalized_base}"
        )
    elif selected is None:
        unresolved_reason = (
            f"Canonical suffix {canonical_suffix} was not observed in raw evidence "
            f"for base product {normalized_base}"
        )
    selected_is_first = bool(selected and first and selected == first)
    return {
        "selection_rule": VARIANT_SELECTION_RULE,
        "selection_evidence_source": "uniqlo_hydration_search_product_ids",
        "raw_variant_observations": preserved,
        "first_observation_id": first["raw_product_id"] if first else "",
        "first_observation_suffix": first["suffix"] if first else "",
        "first_observation_raw_order": first["raw_order"] if first else None,
        "canonical_suffix": canonical_suffix,
        "selected_observation_id": selected["raw_product_id"] if selected else "",
        "selected_observation_raw_order": selected["raw_order"] if selected else None,
        "selected_first_observation": selected_is_first,
        "selection_reason": (
            VARIANT_SELECTION_RULE if selected else ""
        ),
        "first_observation_replacement_reason": (
            ""
            if not selected or selected_is_first
            else "canonical suffix matched a later explicitly observed raw variant"
        ),
        "unselected_observations": [
            item for item in preserved if selected is None or item is not selected
        ],
        "unresolved": selected is None,
        "unresolved_reason": unresolved_reason,
    }


def atomic_write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(value, encoding="utf-8")
    os.replace(temporary, path)


def atomic_write_json(path: Path, value: Any) -> None:
    atomic_write_text(
        path,
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    )


def baby_probe(args: argparse.Namespace) -> dict[str, Any]:
    output_dir = args.output.resolve()
    if output_dir.exists() and any(output_dir.iterdir()):
        raise RuntimeError(f"BABY probe output must be new and empty: {output_dir}")
    plan = baby_probe_plan(args.medium_dir.resolve())
    allowed_urls = {
        plan["category_request"]["url"],
        *(item["url"] for item in plan["product_requests"]),
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = output_dir / "raw"
    request_events: list[dict[str, Any]] = []
    logical_requests: list[str] = []
    product_manifest: list[dict[str, Any]] = [
        {
            **planned,
            "base_product_id": parse_cms_product_id(planned["raw_product_id"])[0],
            "variant_suffix": parse_cms_product_id(planned["raw_product_id"])[1],
            "requested": False,
            "request_url": planned["url"],
            "final_url": "",
            "url_allowed": None,
            "url_rejection_reason": "",
            "http_status": None,
            "raw_evidence": None,
            "hydration_validation_executed": False,
            "product_id_matches": None,
            "hydration_audience": "",
            "category_status": "not_requested",
            "category_path": "",
            "json_ld_status": "not_checked",
            "hydration_status": "not_checked",
            "evidence_source": "",
            "breadcrumb_items": [],
            "unresolved_reason": "",
            "validation_status": "not_requested",
            "skipped_reason": "",
        }
        for planned in plan["product_requests"]
    ]
    unresolved: list[dict[str, Any]] = []
    category_record: dict[str, Any] = {
        "url": plan["category_request"]["url"],
        "requested": False,
        "final_url": "",
        "http_status": None,
        "raw_evidence": None,
        "audience": "",
        "category_urls": [],
        "product_ids": [],
        "cms_product_observations": [],
        "taxonomy_nodes": [],
        "validation_status": "not_requested",
    }
    stop_reason = ""

    def record_request(event: dict[str, Any]) -> None:
        if event["url"] not in allowed_urls:
            raise CollectionStopped(f"Unexpected BABY probe request URL: {event['url']}")
        request_events.append(event)
        atomic_write_json(
            output_dir / "request_metrics.json",
            summarize_request_events(request_events),
        )

    fetcher = RateLimitedFetcher(args.delay_ms, args.retries, event_handler=record_request)

    category_url = plan["category_request"]["url"]
    try:
        logical_requests.append(category_url)
        category_record["requested"] = True
        category_result = fetcher.fetch(
            category_url,
            context={
                "source": "uniqlo",
                "kind": "baby_probe_category",
                "queue_audience": "BABY",
            },
        )
        category_record["http_status"] = category_result.status
        category_record["final_url"] = category_result.url
        category_record["raw_evidence"] = save_raw(
            raw_path(
                raw_dir,
                "uniqlo",
                "category-pages",
                "baby-newborn-bodysuits",
                category_result.content_type,
            ),
            category_result,
        )
        validate_probe_result_url(category_url, category_result.url)
        category_evidence = uniqlo_category_page_evidence(
            category_url, category_result.body
        )
        category_record.update(
            {
                "audience": category_evidence["audience"],
                "category_urls": category_evidence["category_urls"],
                "product_ids": category_evidence["product_ids"],
                "cms_product_observations": category_evidence["cms_product_observations"],
                "taxonomy_nodes": category_evidence["taxonomy_nodes"],
            }
        )
        if category_evidence["audience"] != "BABY":
            raise CollectionStopped(
                "Requested category page did not resolve to BABY audience"
            )
        if not category_evidence["product_ids"]:
            raise CollectionStopped(
                "No product link or audience-scoped hydration product ID found"
            )
        category_record["validation_status"] = "resolved_baby"

        for index, item in enumerate(product_manifest):
            product_url = item["url"]
            logical_requests.append(product_url)
            item["requested"] = True
            result = fetcher.fetch(
                product_url,
                referer=category_url,
                context={
                    "source": "uniqlo",
                    "kind": "baby_probe_product",
                    "queue_audience": "BABY",
                    "observed_id": item["observed_id"],
                },
            )
            item["http_status"] = result.status
            item["final_url"] = result.url
            item["raw_evidence"] = save_raw(
                raw_path(
                    raw_dir,
                    "uniqlo",
                    "products",
                    item["observed_id"],
                    result.content_type,
                ),
                result,
            )
            try:
                canonical = validate_probe_result_url(
                    product_url,
                    result.url,
                    item["raw_product_id"],
                )
                item.update(canonical)
                item["url_allowed"] = True
            except CollectionStopped as error:
                item["url_allowed"] = False
                item["url_rejection_reason"] = str(error)
                raise

            category = uniqlo_category_evidence(result.body, item["observed_id"])
            json_ld = jsonld_category_evidence(
                result.body.decode("utf-8", errors="replace")
            )
            item["hydration_validation_executed"] = True
            item["json_ld_status"] = json_ld["status"]
            item["hydration_status"] = (
                "resolved"
                if category["evidence_source"] in {"uniqlo_hydration", "json_ld"}
                and category["status"] == "resolved"
                else category["status"]
            )
            identity = matched_hydration_product(
                result.body,
                item["observed_id"],
                category.get("selected_entity_key", ""),
            )
            item.update(identity)
            item["product_id_matches"] = (
                identity["hydration_product_id"] == item["observed_id"]
            )
            item["hydration_audience"] = category["audience"]
            item["category_status"] = category["status"]
            item["category_path"] = category["path"]
            item["evidence_source"] = category["evidence_source"]
            item["breadcrumb_items"] = category.get("breadcrumb_items", [])
            item["unresolved_reason"] = category.get("unresolved_reason", "")
            is_resolved_baby = (
                item["product_id_matches"]
                and category["status"] == "resolved"
                and category["audience"] == "BABY"
                and bool(category["path"])
            )
            item["validation_status"] = (
                "resolved_baby" if is_resolved_baby else "unresolved"
            )
            if not is_resolved_baby:
                raise CollectionStopped(
                    category.get("unresolved_reason")
                    or "Product hydration did not resolve to matching BABY evidence"
                )
    except Exception as error:
        stop_reason = str(error)
        unresolved.append(
            {
                "kind": "probe_stop",
                "reason": stop_reason,
                "logical_request_count": len(logical_requests),
            }
        )
        for item in product_manifest:
            if item["requested"] and item["validation_status"] == "not_requested":
                item["validation_status"] = "unresolved"
                item["unresolved_reason"] = stop_reason
            elif not item["requested"]:
                item["skipped_reason"] = f"Skipped after prior probe stop: {stop_reason}"
    finally:
        metrics = summarize_request_events(request_events)
        resolved = sum(
            item["validation_status"] == "resolved_baby"
            for item in product_manifest
        )
        requested_products = sum(item["requested"] for item in product_manifest)
        empty_paths = sum(
            item["requested"] and not item["category_path"]
            for item in product_manifest
        )
        success = (
            category_record["validation_status"] == "resolved_baby"
            and requested_products == 4
            and resolved == 4
            and not unresolved
            and metrics["http_403"] == 0
            and metrics["http_429"] == 0
            and len(logical_requests) <= 5
        )
        payload = {
            "mode": "baby-probe",
            "generated_at": utc_now(),
            "plan": plan,
            "logical_requests": logical_requests,
            "stop_reason": stop_reason,
            "category": category_record,
            "products": product_manifest,
            "success": success,
        }
        atomic_write_json(output_dir / "request_metrics.json", metrics)
        atomic_write_json(output_dir / "probe_manifest.json", payload)
        atomic_write_json(output_dir / "unresolved.json", unresolved)
        atomic_write_text(
            output_dir / "baby_probe_summary.md",
            "# Uniqlo BABY limited live probe\n\n"
            f"- Generated: {utc_now()}\n"
            f"- Logical requests: {len(logical_requests)}\n"
            f"- Attempts: {metrics['attempts']}\n"
            f"- Category product evidence count: {len(category_record['product_ids'])}\n"
            f"- Requested products: {requested_products}/4\n"
            f"- Resolved BABY products: {resolved}/4\n"
            f"- Empty requested product paths: {empty_paths}\n"
            f"- Unresolved: {len(unresolved)}\n"
            f"- Stop reason: {stop_reason or 'none'}\n"
            f"- Success: {success}\n",
        )
    return {
        "success": success,
        "logical_requests": len(logical_requests),
        "attempts": metrics["attempts"],
        "category_product_evidence_count": len(category_record["product_ids"]),
        "resolved_baby_products": resolved,
        "empty_paths": empty_paths,
        "unresolved": len(unresolved),
        "stop_reason": stop_reason,
        "request_metrics": metrics,
        "output": str(output_dir),
    }


def uniqlo_search_product_observations(
    page_url: str,
    body: bytes,
) -> list[dict[str, Any]]:
    audience = audience_from_uniqlo_url(page_url)
    if audience not in AUDIENCE_VALUES:
        return []
    state = hydration_state(body.decode("utf-8", errors="replace"))
    search_root = state.get("search", {}) if state else {}
    if not isinstance(search_root, dict):
        return []
    parsed = urllib.parse.urlsplit(page_url)
    expected_prefix = "/v2" + parsed.path.removeprefix("/kr/ko")
    observations: list[dict[str, Any]] = []
    raw_order = 0
    for search_key, container in search_root.items():
        if not str(search_key).startswith(expected_prefix):
            continue
        search = container.get("search", {}) if isinstance(container, dict) else {}
        raw_ids = search.get("productIds", []) if isinstance(search, dict) else []
        if not isinstance(raw_ids, list):
            continue
        for index, raw_id in enumerate(raw_ids):
            raw_value = normalize_component(str(raw_id)).upper()
            try:
                base_product_id, variant_suffix = parse_cms_product_id(raw_value)
            except ValueError:
                continue
            core_product_id, color_code = product_identity("uniqlo", base_product_id)
            observations.append(
                {
                    "raw_product_id": raw_value,
                    "base_product_id": base_product_id,
                    "core_product_id": core_product_id,
                    "color_code": color_code or "",
                    "variant_suffix": variant_suffix,
                    "audience": audience,
                    "discovered_category_url": page_url,
                    "search_key": str(search_key),
                    "evidence_path": (
                        f"search.{search_key}.search.productIds[{index}]"
                    ),
                    "raw_order": raw_order,
                }
            )
            raw_order += 1
    return observations


def baby_collection_plan_from_raw(page_url: str, body: bytes, limit: int = 10) -> dict[str, Any]:
    observations = uniqlo_search_product_observations(page_url, body)
    grouped: dict[str, list[dict[str, Any]]] = {}
    ordered_core_ids: list[str] = []
    for observation in observations:
        core = observation["core_product_id"]
        if core not in grouped:
            grouped[core] = []
            ordered_core_ids.append(core)
        grouped[core].append(observation)
    selected = [
        {
            **grouped[core][0],
            "duplicate_observations": grouped[core],
            "raw_variant_observations": [
                observation
                for observation in grouped[core]
                if observation["base_product_id"]
                == grouped[core][0]["base_product_id"]
            ],
            "request_url": (
                "https://www.uniqlo.com/kr/ko/products/"
                f"{grouped[core][0]['base_product_id']}"
            ),
            "discovery_order": index,
        }
        for index, core in enumerate(ordered_core_ids[:limit], start=1)
    ]
    return {
        "category_url": page_url,
        "raw_observation_count": len(observations),
        "unique_core_product_count": len(grouped),
        "selected": selected,
        "remaining_core_product_ids": ordered_core_ids[limit:],
        "maximum_logical_requests": 1 + len(selected),
    }


def baby_collect_10(args: argparse.Namespace) -> dict[str, Any]:
    output_dir = args.output.resolve()
    source_raw = (
        args.evidence_dir.resolve()
        / "raw/uniqlo/category-pages/baby-newborn-bodysuits.html"
    )
    if not source_raw.is_file():
        raise RuntimeError(f"Verified BABY category evidence is missing: {source_raw}")
    offline_plan = baby_collection_plan_from_raw(
        BABY_PROBE_CATEGORY_URL,
        source_raw.read_bytes(),
        args.baby_limit,
    )
    if offline_plan["maximum_logical_requests"] > args.max_logical_requests:
        raise RuntimeError(
            "Planned BABY logical requests exceed safety cap: "
            f"{offline_plan['maximum_logical_requests']} > {args.max_logical_requests}"
        )
    if len(offline_plan["selected"]) < args.baby_limit:
        raise RuntimeError(
            f"Only {len(offline_plan['selected'])} unique BABY candidates are grounded"
        )
    dry_run_result = {
        "mode": "baby-collect-10-dry-run",
        "network_requests": 0,
        "category_requests": 1,
        "product_requests": len(offline_plan["selected"]),
        "maximum_logical_requests": offline_plan["maximum_logical_requests"],
        "maximum_attempts_with_retries": (
            offline_plan["maximum_logical_requests"] * (args.retries + 1)
        ),
        "accepted_baby_limit": args.baby_limit,
        "selected_raw_product_ids": [
            item["raw_product_id"] for item in offline_plan["selected"]
        ],
        "output": str(output_dir),
    }
    if args.dry_run:
        print(json.dumps(dry_run_result, ensure_ascii=False, indent=2))
        return dry_run_result
    if output_dir.exists() and any(output_dir.iterdir()):
        raise RuntimeError(f"BABY collection output must be new and empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = output_dir / "raw"
    request_events: list[dict[str, Any]] = []
    logical_requests: list[str] = []
    accepted_products: list[dict[str, Any]] = []
    product_records: list[dict[str, Any]] = []
    unresolved: list[dict[str, Any]] = []
    stop_reason = ""
    remaining_candidate_core_ids: list[str] = []
    category_record: dict[str, Any] = {
        "url": BABY_PROBE_CATEGORY_URL,
        "requested": False,
        "final_url": "",
        "http_status": None,
        "raw_evidence": None,
        "audience": "",
        "category_urls": [],
        "product_ids": [],
        "search_observations": [],
        "validation_status": "not_requested",
    }
    settings = {
        "source": "uniqlo",
        "audience": "BABY",
        "baby_limit": args.baby_limit,
        "max_logical_requests": args.max_logical_requests,
        "delay_ms": args.delay_ms,
        "retries": args.retries,
        "start_url": BABY_PROBE_CATEGORY_URL,
    }

    def snapshot() -> None:
        metrics = summarize_request_events(request_events)
        checkpoint = {
            "version": 1,
            "updated_at": utc_now(),
            "settings": settings,
            "logical_requests": logical_requests,
            "accepted_core_product_ids": [
                item["core_product_id"] for item in accepted_products
            ],
            "accepted_count": len(accepted_products),
            "processed_base_product_ids": [
                item["base_product_id"] for item in product_records if item["requested"]
            ],
            "remaining_queue": [
                item["raw_product_id"]
                for item in product_records
                if not item["requested"]
            ] + remaining_candidate_core_ids,
            "stopped": bool(stop_reason) or len(accepted_products) >= args.baby_limit,
            "stop_reason": stop_reason,
            "resume_supported": False,
            "resume_reason": (
                "This bounded evidence run is terminal; use a new output path "
                "for any separately approved follow-up."
            ),
        }
        manifest = {
            "mode": "baby-collect-10",
            "generated_at": utc_now(),
            "settings": settings,
            "category": category_record,
            "products": product_records,
            "accepted_products": accepted_products,
            "logical_requests": logical_requests,
            "stop_reason": stop_reason,
        }
        atomic_write_json(output_dir / "checkpoint.json", checkpoint)
        atomic_write_json(output_dir / "request_metrics.json", metrics)
        atomic_write_json(output_dir / "collection_manifest.json", manifest)
        atomic_write_json(output_dir / "unresolved.json", unresolved)
        atomic_write_json(
            output_dir / "category_evidence.json",
            category_record,
        )
        success = len(accepted_products) == args.baby_limit and not unresolved
        atomic_write_text(
            output_dir / "baby_collection_summary.md",
            "# Uniqlo BABY 10 limited collection\n\n"
            f"- Generated: {utc_now()}\n"
            f"- Logical requests: {len(logical_requests)}\n"
            f"- Attempts: {metrics['attempts']}\n"
            f"- Raw product observations: {len(category_record['search_observations'])}\n"
            f"- Unique requested candidates: {len(product_records)}\n"
            f"- Accepted unique BABY products: {len(accepted_products)}/{args.baby_limit}\n"
            f"- Unresolved: {len(unresolved)}\n"
            f"- Remaining queue: {sum(not item['requested'] for item in product_records)}\n"
            f"- Stop reason: {stop_reason or 'accepted limit reached'}\n"
            f"- Success: {success}\n",
        )

    def record_request(event: dict[str, Any]) -> None:
        request_events.append(event)
        snapshot()

    fetcher = RateLimitedFetcher(args.delay_ms, args.retries, event_handler=record_request)
    try:
        logical_requests.append(BABY_PROBE_CATEGORY_URL)
        category_record["requested"] = True
        result = fetcher.fetch(
            BABY_PROBE_CATEGORY_URL,
            context={
                "source": "uniqlo",
                "kind": "baby_collection_category",
                "queue_audience": "BABY",
            },
        )
        category_record["http_status"] = result.status
        category_record["final_url"] = result.url
        category_record["raw_evidence"] = save_raw(
            raw_path(
                raw_dir,
                "uniqlo",
                "category-pages",
                "baby-newborn-bodysuits",
                result.content_type,
            ),
            result,
        )
        validate_probe_result_url(BABY_PROBE_CATEGORY_URL, result.url)
        page_evidence = uniqlo_category_page_evidence(
            BABY_PROBE_CATEGORY_URL, result.body
        )
        live_plan = baby_collection_plan_from_raw(
            BABY_PROBE_CATEGORY_URL, result.body, args.baby_limit
        )
        remaining_candidate_core_ids = live_plan["remaining_core_product_ids"]
        category_record.update(
            {
                "audience": page_evidence["audience"],
                "category_urls": page_evidence["category_urls"],
                "product_ids": page_evidence["product_ids"],
                "search_observations": uniqlo_search_product_observations(
                    BABY_PROBE_CATEGORY_URL, result.body
                ),
                "validation_status": "resolved_baby",
            }
        )
        if page_evidence["audience"] != "BABY":
            raise CollectionStopped("Start category did not resolve to BABY")
        if len(live_plan["selected"]) < args.baby_limit:
            raise CollectionStopped(
                f"Live category exposed only {len(live_plan['selected'])} unique candidates"
            )
        product_records = [
            {
                **candidate,
                "requested": False,
                "final_url": "",
                "url_allowed": None,
                "http_status": None,
                "raw_evidence": None,
                "hydration_product_id": "",
                "product_id_matches": None,
                "hydration_audience": "",
                "breadcrumb_items": [],
                "category_path": "",
                "json_ld_status": "not_checked",
                "evidence_source": "",
                "is_db_candidate": None,
                "db_candidate_reason": "",
                "validation_status": "not_requested",
                "unresolved_reason": "",
                "variant_selection": None,
            }
            for candidate in live_plan["selected"]
        ]
        snapshot()

        for item in product_records:
            if len(accepted_products) >= args.baby_limit:
                break
            if len(logical_requests) >= args.max_logical_requests:
                raise CollectionStopped("Maximum logical request cap reached")
            request_url = item["request_url"]
            if audience_from_uniqlo_url(BABY_PROBE_CATEGORY_URL) != "BABY":
                raise CollectionStopped("Non-BABY discovery URL selected")
            logical_requests.append(request_url)
            item["requested"] = True
            response = fetcher.fetch(
                request_url,
                referer=BABY_PROBE_CATEGORY_URL,
                context={
                    "source": "uniqlo",
                    "kind": "baby_collection_product",
                    "queue_audience": "BABY",
                    "observed_id": item["base_product_id"],
                },
            )
            item["http_status"] = response.status
            item["final_url"] = response.url
            item["raw_evidence"] = save_raw(
                raw_path(
                    raw_dir,
                    "uniqlo",
                    "products",
                    item["base_product_id"],
                    response.content_type,
                ),
                response,
            )
            try:
                canonical = validate_canonical_product_url(
                    request_url, response.url, item["base_product_id"]
                )
                selection = select_canonical_raw_variant(
                    item["base_product_id"],
                    canonical["canonical_suffix"],
                    item["duplicate_observations"],
                )
                item["variant_selection"] = selection
                if selection["unresolved"]:
                    raise CollectionStopped(selection["unresolved_reason"])
                item["url_allowed"] = True
            except CollectionStopped as error:
                item["url_allowed"] = False
                item["validation_status"] = "unresolved"
                item["unresolved_reason"] = str(error)
                unresolved.append(
                    {
                        "raw_product_id": item["raw_product_id"],
                        "base_product_id": item["base_product_id"],
                        "reason": str(error),
                    }
                )
                raise
            category = uniqlo_category_evidence(
                response.body, item["base_product_id"]
            )
            identity = matched_hydration_product(
                response.body,
                item["base_product_id"],
                category.get("selected_entity_key", ""),
            )
            item["hydration_product_id"] = identity["hydration_product_id"]
            item["product_id_matches"] = (
                identity["hydration_product_id"] == item["base_product_id"]
            )
            item["hydration_audience"] = category["audience"]
            item["breadcrumb_items"] = category.get("breadcrumb_items", [])
            item["category_path"] = category["path"]
            item["json_ld_status"] = jsonld_category_evidence(
                response.body.decode("utf-8", errors="replace")
            )["status"]
            item["evidence_source"] = category["evidence_source"]
            flags = configured_flags("uniqlo", category["path"], read_json(CONFIG_PATH))
            item["is_db_candidate"] = flags["is_db_candidate"]
            item["db_candidate_reason"] = (
                flags["unresolved_reason"]
                or (
                    "existing source category"
                    if flags["is_existing_source_category"]
                    else "new reviewed corpus candidate"
                )
            )
            valid = (
                item["product_id_matches"]
                and category["status"] == "resolved"
                and category["audience"] == "BABY"
                and bool(category["path"])
                and bool(category["evidence_source"])
                and item["raw_evidence"] is not None
            )
            if not valid:
                item["validation_status"] = "unresolved"
                item["unresolved_reason"] = (
                    category.get("unresolved_reason")
                    or "Product failed BABY acceptance conditions"
                )
                unresolved.append(
                    {
                        "raw_product_id": item["raw_product_id"],
                        "base_product_id": item["base_product_id"],
                        "reason": item["unresolved_reason"],
                    }
                )
                raise CollectionStopped(item["unresolved_reason"])
            if any(
                accepted["core_product_id"] == item["core_product_id"]
                for accepted in accepted_products
            ):
                item["validation_status"] = "duplicate"
                item["unresolved_reason"] = "Duplicate core product ID"
                unresolved.append(
                    {
                        "raw_product_id": item["raw_product_id"],
                        "base_product_id": item["base_product_id"],
                        "reason": "Duplicate core product ID",
                    }
                )
                continue
            item["validation_status"] = "accepted_baby"
            accepted_products.append(item)
            snapshot()
        if len(accepted_products) == args.baby_limit:
            stop_reason = "Accepted BABY product limit reached"
    except Exception as error:
        stop_reason = str(error)
        if not unresolved:
            unresolved.append({"kind": "collection_stop", "reason": stop_reason})
    finally:
        snapshot()

    metrics = summarize_request_events(request_events)
    success = (
        len(accepted_products) == args.baby_limit
        and not unresolved
        and metrics["http_403"] == 0
        and metrics["http_429"] == 0
        and len(logical_requests) <= args.max_logical_requests
    )
    return {
        "success": success,
        "logical_requests": len(logical_requests),
        "attempts": metrics["attempts"],
        "accepted_baby_products": len(accepted_products),
        "unresolved": len(unresolved),
        "stop_reason": stop_reason,
        "request_metrics": metrics,
        "output": str(output_dir),
    }


def recursive_find_category(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        keys = {key.casefold() for key in value}
        if any(key.startswith("categorydepth") for key in keys):
            return value
        for child in value.values():
            found = recursive_find_category(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = recursive_find_category(child)
            if found:
                return found
    return None


def musinsa_category_evidence(body: bytes) -> dict[str, Any]:
    payload = json.loads(body)
    category = recursive_find_category(payload) or {}
    names: list[str] = []
    codes: list[str] = []
    for index in range(1, 5):
        title = category.get(f"categoryDepth{index}Title")
        name = title or category.get(f"categoryDepth{index}Name")
        code = category.get(f"categoryDepth{index}Code")
        if normalize_component(str(name or "")):
            names.append(normalize_component(str(name)))
            codes.append(normalize_component(str(code or "")))
    return {"audience": "", "depth_names": names, "depth_codes": codes, "path": normalized_path(names)}


def flatten_jsonld(value: Any) -> Iterable[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        graph = value.get("@graph")
        if isinstance(graph, list):
            for child in graph:
                yield from flatten_jsonld(child)
    elif isinstance(value, list):
        for child in value:
            yield from flatten_jsonld(child)


def empty_uniqlo_evidence(source: str, reason: str = "") -> dict[str, Any]:
    return {
        "status": "unresolved",
        "audience": "",
        "depth_names": [],
        "depth_codes": [],
        "path": "",
        "evidence_source": source,
        "breadcrumb_items": [],
        "selected_entity_key": "",
        "entity_match_basis": "",
        "unresolved_reason": reason,
    }


def jsonld_category_evidence(text: str) -> dict[str, Any]:
    scripts = re.findall(
        r"<script[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>",
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    raw_items: list[dict[str, Any]] = []
    product_names: set[str] = set()
    objects: list[dict[str, Any]] = []
    for script in scripts:
        try:
            objects.extend(flatten_jsonld(json.loads(html.unescape(script))))
        except json.JSONDecodeError:
            continue
    for item in objects:
        kind = item.get("@type")
        kinds = {kind} if isinstance(kind, str) else set(kind or [])
        if "Product" in kinds or "ProductGroup" in kinds:
            if item.get("name"):
                product_names.add(normalize_component(str(item["name"])).casefold())
        if "BreadcrumbList" in kinds:
            for raw_order, element in enumerate(item.get("itemListElement", [])):
                name = element.get("name")
                nested_item = element.get("item") if isinstance(element.get("item"), dict) else {}
                if not name:
                    name = nested_item.get("name")
                if name:
                    raw_items.append(
                        {
                            "role": "json_ld_item",
                            "id": normalize_component(str(nested_item.get("@id") or nested_item.get("id") or "")),
                            "name": normalize_component(str(name)),
                            "locale": "",
                            "level": element.get("position"),
                            "raw_order": raw_order,
                        }
                    )
    filtered_items = [
        item for item in raw_items
        if item["name"].casefold() not in {"홈", "home", "유니클로", "uniqlo"}
        and item["name"].casefold() not in product_names
    ]
    audience = ""
    if filtered_items and filtered_items[0]["name"].upper() in AUDIENCE_VALUES:
        audience = filtered_items.pop(0)["name"].upper()
    for index, item in enumerate(filtered_items):
        item["role"] = f"category_{index + 1}"
    names = [item["name"] for item in filtered_items[:4]]
    if not names:
        return empty_uniqlo_evidence("json_ld", "유효한 JSON-LD BreadcrumbList 경로 없음")
    return {
        "status": "resolved",
        "audience": audience,
        "depth_names": names,
        "depth_codes": [item["id"] for item in filtered_items[:4]],
        "path": normalized_path(names),
        "evidence_source": "json_ld",
        "breadcrumb_items": filtered_items[:4],
        "selected_entity_key": "",
        "entity_match_basis": "json_ld_breadcrumb",
        "unresolved_reason": "",
    }


def hydration_state(text: str) -> dict[str, Any] | None:
    match = re.search(
        r"window\.__PRELOADED_STATE__\s*=\s*(\{.*?\})\s*;?\s*</script>",
        text.replace("\x00", ""),
        flags=re.DOTALL,
    )
    if not match:
        return None
    try:
        value = json.loads(match.group(1))
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def hydration_category_evidence(text: str, target_product_code: str) -> dict[str, Any]:
    state = hydration_state(text)
    if state is None:
        return empty_uniqlo_evidence("uniqlo_hydration", "hydration JSON을 찾거나 해석할 수 없음")
    entities = state.get("entity", {}).get("pdpEntity", {})
    if not isinstance(entities, dict):
        return empty_uniqlo_evidence("uniqlo_hydration", "entity.pdpEntity가 객체가 아님")

    target = normalize_component(target_product_code).upper()
    matches: list[tuple[str, dict[str, Any], str]] = []
    for entity_key, raw_entity in entities.items():
        entity = raw_entity if isinstance(raw_entity, dict) else {}
        product = entity.get("product") if isinstance(entity.get("product"), dict) else {}
        product_id = normalize_component(str(product.get("productId") or "")).upper()
        normalized_key = normalize_component(str(entity_key)).upper()
        if product_id == target:
            matches.append((str(entity_key), product, "product.productId_exact"))
        elif normalized_key == target or normalized_key.startswith(target + "-"):
            matches.append((str(entity_key), product, "pdpEntity_key_prefix"))

    unique_matches: dict[str, tuple[dict[str, Any], str]] = {}
    for key, product, basis in matches:
        existing = unique_matches.get(key)
        if existing is None or basis == "product.productId_exact":
            unique_matches[key] = (product, basis)
    if len(unique_matches) != 1:
        available_keys = ", ".join(sorted(str(key) for key in entities)) or "없음"
        return empty_uniqlo_evidence(
            "uniqlo_hydration",
            f"대상 상품 코드 {target}와 일치하는 pdpEntity가 "
            f"{len(unique_matches)}개임; available_keys={available_keys}",
        )

    entity_key, (product, match_basis) = next(iter(unique_matches.items()))
    breadcrumbs = product.get("breadcrumbs")
    if not isinstance(breadcrumbs, dict):
        return empty_uniqlo_evidence(
            "uniqlo_hydration",
            f"선택한 pdpEntity {entity_key}에 product.breadcrumbs가 없음",
        )

    recognized_roles = {"gender", "class", "category", "subcategory"}
    breadcrumb_items: list[dict[str, Any]] = []
    for raw_order, (role, raw_item) in enumerate(breadcrumbs.items()):
        if role not in recognized_roles or not isinstance(raw_item, dict):
            continue
        breadcrumb_items.append(
            {
                "role": role,
                "id": normalize_component(str(raw_item.get("id") or "")),
                "name": normalize_component(str(raw_item.get("name") or "")),
                "locale": normalize_component(str(raw_item.get("locale") or "")),
                "level": raw_item.get("level"),
                "raw_order": raw_order,
            }
        )

    gender_item = next((item for item in breadcrumb_items if item["role"] == "gender"), None)
    audience = ""
    if gender_item:
        audience = (gender_item["locale"] or gender_item["name"]).upper()
    category_items = [
        item for item in breadcrumb_items
        if item["role"] in {"class", "category", "subcategory"}
    ]
    category_items.sort(
        key=lambda item: (
            item["level"] if isinstance(item["level"], int) else sys.maxsize,
            item["raw_order"],
        )
    )
    if not category_items or any(not (item["locale"] or item["name"]) for item in category_items):
        return empty_uniqlo_evidence(
            "uniqlo_hydration",
            f"선택한 pdpEntity {entity_key}의 class/category/subcategory가 불완전함",
        )
    names = [item["locale"] or item["name"] for item in category_items]
    return {
        "status": "resolved",
        "audience": audience,
        "depth_names": names,
        "depth_codes": [item["id"] for item in category_items],
        "path": normalized_path(names),
        "evidence_source": "uniqlo_hydration",
        "breadcrumb_items": breadcrumb_items,
        "selected_entity_key": entity_key,
        "entity_match_basis": match_basis,
        "unresolved_reason": "",
    }


def uniqlo_category_evidence(body: bytes, target_product_code: str) -> dict[str, Any]:
    text = body.decode("utf-8", errors="replace")
    json_ld = jsonld_category_evidence(text)
    hydration = hydration_category_evidence(text, target_product_code)
    json_ld_valid = json_ld["status"] == "resolved" and bool(json_ld["path"])
    hydration_valid = hydration["status"] == "resolved" and bool(hydration["path"])

    if json_ld_valid and hydration_valid:
        paths_match = normalized_path(json_ld["path"]).casefold() == normalized_path(
            hydration["path"]
        ).casefold()
        audiences_match = (
            not json_ld["audience"]
            or not hydration["audience"]
            or json_ld["audience"].casefold() == hydration["audience"].casefold()
        )
        if not paths_match or not audiences_match:
            result = empty_uniqlo_evidence(
                "conflict",
                "JSON-LD와 hydration breadcrumb의 경로 또는 audience가 충돌함",
            )
            result["evidence_candidates"] = {
                "json_ld": json_ld,
                "uniqlo_hydration": hydration,
            }
            return result
        result = dict(json_ld)
        result["evidence_source"] = "json_ld"
        result["evidence_candidates"] = {
            "json_ld": json_ld,
            "uniqlo_hydration": hydration,
        }
        return result
    if json_ld_valid:
        result = dict(json_ld)
        result["evidence_candidates"] = {"json_ld": json_ld}
        return result
    if hydration_valid:
        result = dict(hydration)
        result["evidence_candidates"] = {"uniqlo_hydration": hydration}
        return result

    result = empty_uniqlo_evidence(
        "none",
        "JSON-LD와 hydration 모두 유효한 카테고리 경로를 제공하지 않음; "
        f"json_ld={json_ld['unresolved_reason']}; "
        f"hydration={hydration['unresolved_reason']}",
    )
    result["evidence_candidates"] = {
        "json_ld": json_ld,
        "uniqlo_hydration": hydration,
    }
    return result


def raw_path(raw_dir: Path, source: str, kind: str, identity: str, content_type: str) -> Path:
    extension = ".json" if "json" in content_type.lower() else ".html"
    safe_identity = re.sub(r"[^A-Za-z0-9_.-]", "_", identity)
    return raw_dir / source / kind / f"{safe_identity}{extension}"


def save_raw(path: Path, result: FetchResult) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(result.body)
    return {
        "path": str(path),
        "url": result.url,
        "status": result.status,
        "content_type": result.content_type,
        "sha256": hashlib.sha256(result.body).hexdigest(),
        "bytes": len(result.body),
        "collected_at": utc_now(),
    }


def audience_from_uniqlo_url(url: str) -> str:
    match = re.search(r"/kr/ko/(men|women|kids|baby)(?:/|$)", url, re.IGNORECASE)
    return match.group(1).upper() if match else ""


def initial_uniqlo_audience_states(config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    seeds: dict[str, list[str]] = {
        audience: list(urls) for audience, urls in UNIQLO_AUDIENCE_ROOTS.items()
    }
    for url in config["live_seeds"]["uniqlo"]:
        audience = audience_from_uniqlo_url(url)
        if audience and url not in seeds[audience]:
            seeds[audience].append(url)
    return {
        audience: {
            "queue": urls,
            "visited_categories": [],
            "discovered_products": {},
            "confirmed_products": [],
        }
        for audience, urls in seeds.items()
    }


def initial_live_state(config: dict[str, Any]) -> dict[str, Any]:
    return {
        "version": CHECKPOINT_VERSION,
        "started_at": utc_now(),
        "sources": {
            "musinsa": {
                "queue": config["live_seeds"]["musinsa"],
                "visited_categories": [],
                "discovered_products": {},
                "processed_products": [],
            },
            "uniqlo": {
                "audiences": initial_uniqlo_audience_states(config),
                "processed_products": [],
                "product_audiences": {},
                "audience_mismatches": [],
                "unknown_audience_products": [],
                "over_quota_observations": [],
            },
        },
        "raw_records": [],
        "request_events": [],
    }


def audience_has_capacity(
    source_state: dict[str, Any],
    audience: str,
    audience_limits: dict[str, int],
) -> bool:
    return (
        audience in AUDIENCE_VALUES
        and len(source_state["audiences"][audience]["confirmed_products"])
        < audience_limits[audience]
    )


def record_uniqlo_audience_result(
    source_state: dict[str, Any],
    observed_id: str,
    queue_audience: str,
    category: dict[str, Any],
    audience_limits: dict[str, int],
) -> tuple[str, bool]:
    actual_audience = category.get("audience", "")
    if category.get("status") != "resolved" or actual_audience not in AUDIENCE_VALUES:
        source_state["unknown_audience_products"].append(
            {
                "observed_id": observed_id,
                "queue_audience": queue_audience,
                "reason": category.get("unresolved_reason")
                or "hydration audience를 확인할 수 없음",
            }
        )
        return actual_audience, False

    source_state["product_audiences"][observed_id] = actual_audience
    confirmed = source_state["audiences"][actual_audience]["confirmed_products"]
    accepted = len(confirmed) < audience_limits[actual_audience]
    if accepted and observed_id not in confirmed:
        confirmed.append(observed_id)
    elif not accepted:
        source_state["over_quota_observations"].append(
            {
                "observed_id": observed_id,
                "actual_audience": actual_audience,
                "limit": audience_limits[actual_audience],
            }
        )
    if actual_audience != queue_audience:
        source_state["audience_mismatches"].append(
            {
                "observed_id": observed_id,
                "queue_audience": queue_audience,
                "actual_audience": actual_audience,
                "evidence_source": category.get("evidence_source", ""),
                "category_path": category.get("path", ""),
            }
        )
    return actual_audience, accepted


def update_product_manifest(
    manifest_by_key: dict[tuple[str, str], dict[str, Any]],
    source: str,
    observed_id: str,
    evidence: dict[str, Any],
    category_observation: dict[str, Any] | None = None,
) -> dict[str, Any]:
    product_key, color_code = product_identity(source, observed_id)
    manifest = manifest_by_key.setdefault(
        (source, product_key),
        {
            "source": source,
            "product_key": product_key,
            "observed_ids": [],
            "color_codes": [],
            "exposure_paths": [],
            "raw_evidence": [],
            "category_observations": [],
        },
    )
    if observed_id not in manifest["observed_ids"]:
        manifest["observed_ids"].append(observed_id)
    if color_code and color_code not in manifest["color_codes"]:
        manifest["color_codes"].append(color_code)
    if evidence not in manifest["raw_evidence"]:
        manifest["raw_evidence"].append(evidence)
    if category_observation is not None:
        path = category_observation.get("path", "")
        if path and path not in manifest["exposure_paths"]:
            manifest["exposure_paths"].append(path)
        if category_observation not in manifest["category_observations"]:
            manifest["category_observations"].append(category_observation)
    return manifest


def migrate_v1_checkpoint(state: dict[str, Any]) -> dict[str, Any]:
    migrated = copy.deepcopy(state)
    if migrated.get("version") not in (None, 1):
        raise RuntimeError(
            f"Unsupported checkpoint version: {migrated.get('version')}; "
            "the checkpoint was not overwritten"
        )
    sources = migrated.get("sources")
    if not isinstance(sources, dict):
        raise RuntimeError("Invalid v1 checkpoint: sources is missing")
    old = sources.get("uniqlo")
    if old is not None and not isinstance(old, dict):
        raise RuntimeError("Invalid v1 checkpoint: sources.uniqlo is not an object")

    config = read_json(CONFIG_PATH)
    audience_states = initial_uniqlo_audience_states(config)
    if old:
        for url in old.get("queue", []):
            audience = audience_from_uniqlo_url(url)
            if not audience:
                raise RuntimeError(
                    f"Cannot migrate v1 Uniqlo queue URL without audience: {url}; "
                    "the checkpoint was not overwritten"
                )
            if url not in audience_states[audience]["queue"]:
                audience_states[audience]["queue"].append(url)
        for url in old.get("visited_categories", []):
            audience = audience_from_uniqlo_url(url)
            if not audience:
                raise RuntimeError(
                    f"Cannot migrate v1 Uniqlo visited URL without audience: {url}; "
                    "the checkpoint was not overwritten"
                )
            audience_states[audience]["visited_categories"].append(url)
            audience_states[audience]["queue"] = [
                item for item in audience_states[audience]["queue"] if item != url
            ]
        for observed_id, urls in old.get("discovered_products", {}).items():
            for url in urls:
                audience = audience_from_uniqlo_url(url)
                if not audience:
                    raise RuntimeError(
                        f"Cannot migrate v1 Uniqlo exposure URL without audience: {url}; "
                        "the checkpoint was not overwritten"
                    )
                values = audience_states[audience]["discovered_products"].setdefault(
                    observed_id, []
                )
                if url not in values:
                    values.append(url)

    processed = list((old or {}).get("processed_products", []))
    product_audiences: dict[str, str] = {}
    unknown: list[dict[str, str]] = []
    raw_records = migrated.get("raw_records", [])
    for record in raw_records:
        path = Path(str(record.get("path") or ""))
        if "uniqlo" not in path.parts or path.parent.name != "products":
            continue
        observed_id = path.stem.upper()
        if observed_id not in processed or not path.is_file():
            continue
        evidence = uniqlo_category_evidence(path.read_bytes(), observed_id)
        if evidence["status"] == "resolved" and evidence["audience"] in AUDIENCE_VALUES:
            product_audiences[observed_id] = evidence["audience"]
            audience_states[evidence["audience"]]["confirmed_products"].append(observed_id)
        else:
            unknown.append(
                {
                    "observed_id": observed_id,
                    "reason": evidence["unresolved_reason"],
                }
            )

    migrated["version"] = CHECKPOINT_VERSION
    migrated["legacy_v1"] = copy.deepcopy(old or {})
    migrated["sources"]["uniqlo"] = {
        "audiences": audience_states,
        "processed_products": processed,
        "product_audiences": product_audiences,
        "audience_mismatches": [],
        "unknown_audience_products": unknown,
        "over_quota_observations": [],
    }
    migrated.setdefault("request_events", [])
    return migrated


def load_live_state(checkpoint_path: Path, resume: bool, config: dict[str, Any]) -> dict[str, Any]:
    if not resume:
        return initial_live_state(config)
    if not checkpoint_path.is_file():
        raise RuntimeError(f"--resume requires checkpoint.json: {checkpoint_path}")
    state = read_json(checkpoint_path)
    version = state.get("version")
    if version == CHECKPOINT_VERSION:
        required = state.get("sources", {}).get("uniqlo", {}).get("audiences")
        if not isinstance(required, dict) or not set(AUDIENCE_ORDER).issubset(required):
            raise RuntimeError(
                "Invalid v2 checkpoint audience state; the checkpoint was not overwritten"
            )
        sanitize_uniqlo_checkpoint_category_queues(state)
        return state
    return migrate_v1_checkpoint(state)


def sanitize_uniqlo_checkpoint_category_queues(state: dict[str, Any]) -> None:
    source_state = state.get("sources", {}).get("uniqlo")
    if not isinstance(source_state, dict):
        return
    rejected = source_state.setdefault("rejected_category_urls", [])
    known_rejections = {
        (
            item.get("page_url", ""),
            item.get("raw_href", ""),
            item.get("resolved_url", ""),
            item.get("reason", ""),
        )
        for item in rejected
    }
    raw_category_records = [
        record
        for record in state.get("raw_records", [])
        if "uniqlo" in Path(str(record.get("path") or "")).parts
        and Path(str(record.get("path") or "")).parent.name == "category-pages"
        and Path(str(record.get("path") or "")).is_file()
    ]
    for record in state.get("raw_records", []):
        path = Path(str(record.get("path") or ""))
        if (
            "uniqlo" not in path.parts
            or path.parent.name != "category-pages"
            or not path.is_file()
        ):
            continue
        page_url = str(record.get("url") or "")
        evidence = uniqlo_category_page_evidence(page_url, path.read_bytes())
        for item in evidence.get("rejected_category_urls", []):
            enriched = {
                **item,
                "raw_path": str(path),
                "raw_sha256": record.get("sha256", ""),
                "request_skipped": True,
            }
            key = (
                enriched.get("page_url", ""),
                enriched.get("raw_href", ""),
                enriched.get("resolved_url", ""),
                enriched.get("reason", ""),
            )
            if key not in known_rejections:
                rejected.append(enriched)
                known_rejections.add(key)

    failed_category_urls: dict[str, int] = {}
    for event in state.get("request_events", []):
        if (
            event.get("source") == "uniqlo"
            and event.get("kind") == "category_page"
            and event.get("status") == 404
        ):
            failed_category_urls[str(event.get("url") or "")] = 404
    for failed_url, status in failed_category_urls.items():
        provenance: dict[str, Any] = {}
        for record in raw_category_records:
            path = Path(record["path"])
            parser = LinkExtractor()
            parser.feed(path.read_text(encoding="utf-8", errors="replace"))
            match = next(
                (
                    (raw_order, href)
                    for raw_order, href in enumerate(parser.links)
                    if canonical_url(str(record.get("url") or ""), href) == failed_url
                ),
                None,
            )
            if match:
                provenance = {
                    "page_url": str(record.get("url") or ""),
                    "raw_href": match[1],
                    "raw_order": str(match[0]),
                    "raw_path": str(path),
                    "raw_sha256": record.get("sha256", ""),
                }
                break
        item = {
            **provenance,
            "resolved_url": failed_url,
            "evidence_source": "http_404_category_response",
            "reason": f"public category request returned HTTP {status}",
            "request_skipped": True,
        }
        key = (
            item.get("page_url", ""),
            item.get("raw_href", ""),
            item["resolved_url"],
            item["reason"],
        )
        if key not in known_rejections:
            rejected.append(item)
            known_rejections.add(key)

    for audience in AUDIENCE_ORDER:
        audience_state = source_state["audiences"][audience]
        sanitized: list[str] = []
        for queued_url in audience_state.get("queue", []):
            if queued_url in failed_category_urls:
                continue
            normalized, reason = validated_uniqlo_category_href(queued_url, queued_url)
            if normalized is not None and audience_from_uniqlo_url(normalized) == audience:
                if normalized not in sanitized:
                    sanitized.append(normalized)
                continue
            matching = next(
                (
                    item
                    for item in rejected
                    if item.get("resolved_url") == queued_url
                ),
                None,
            )
            item = {
                "page_url": (matching or {}).get("page_url", ""),
                "raw_href": (matching or {}).get("raw_href", ""),
                "resolved_url": queued_url,
                "raw_order": (matching or {}).get("raw_order", ""),
                "evidence_source": (
                    (matching or {}).get("evidence_source")
                    or "checkpoint_queue_validation"
                ),
                "reason": reason or "category URL audience does not match its queue",
                "raw_path": (matching or {}).get("raw_path", ""),
                "raw_sha256": (matching or {}).get("raw_sha256", ""),
                "request_skipped": True,
            }
            key = (
                item["page_url"],
                item["raw_href"],
                item["resolved_url"],
                item["reason"],
            )
            if key not in known_rejections:
                rejected.append(item)
                known_rejections.add(key)
        audience_state["queue"] = sanitized


def percentile(values: list[float], probability: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def duration_summary(events: list[dict[str, Any]]) -> dict[str, Any]:
    values = [
        float(event["duration_ms"])
        for event in events
        if isinstance(event.get("duration_ms"), (int, float))
    ]
    if not values:
        return {"count": 0, "min_ms": None, "median_ms": None, "p95_ms": None, "max_ms": None}
    return {
        "count": len(values),
        "min_ms": round(min(values), 3),
        "median_ms": round(statistics.median(values), 3),
        "p95_ms": round(percentile(values, 0.95) or 0, 3),
        "max_ms": round(max(values), 3),
    }


def summarize_request_events(events: list[dict[str, Any]]) -> dict[str, Any]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for event in events:
        grouped[f"{event.get('source', 'unknown')}/{event.get('kind', 'unknown')}"].append(event)
    status_counts = defaultdict(int)
    for event in events:
        status_counts[str(event.get("status") if event.get("status") is not None else "network")] += 1
    segments: list[dict[str, Any]] = []
    segment_size = max(1, math.ceil(len(events) / 4)) if events else 1
    for start in range(0, len(events), segment_size):
        segment = events[start:start + segment_size]
        failures = sum(event.get("outcome") != "success" for event in segment)
        segments.append(
            {
                "attempt_range": [start + 1, start + len(segment)],
                "attempts": len(segment),
                "failures": failures,
                "failure_rate": failures / len(segment) if segment else 0,
                "duration": duration_summary(segment),
            }
        )
    return {
        "attempts": len(events),
        "successes": sum(event.get("outcome") == "success" for event in events),
        "failures": sum(event.get("outcome") != "success" for event in events),
        "retries": sum(int(event.get("attempt", 0)) > 0 for event in events),
        "http_403": sum(event.get("status") == 403 for event in events),
        "http_429": sum(event.get("status") == 429 for event in events),
        "status_counts": dict(sorted(status_counts.items())),
        "duration": duration_summary(events),
        "by_source_kind": {
            key: {
                "attempts": len(group),
                "successes": sum(event.get("outcome") == "success" for event in group),
                "failures": sum(event.get("outcome") != "success" for event in group),
                "duration": duration_summary(group),
            }
            for key, group in sorted(grouped.items())
        },
        "progress_segments": segments,
    }


def live_collect(args: argparse.Namespace) -> dict[str, Any]:
    config = read_json(CONFIG_PATH)
    output_dir = args.output.resolve()
    checkpoint_path = output_dir / "checkpoint.json"
    source_names = ["musinsa", "uniqlo"] if args.source == "all" else [args.source]
    audience_limits = {
        audience: (
            getattr(args, f"uniqlo_{audience.lower()}_limit")
            if getattr(args, f"uniqlo_{audience.lower()}_limit") is not None
            else args.uniqlo_limit
        )
        for audience in AUDIENCE_ORDER
    }
    if args.dry_run:
        product_limit = (
            (args.musinsa_limit if "musinsa" in source_names else 0)
            + (args.uniqlo_limit if "uniqlo" in source_names else 0)
        )
        category_limit = args.max_category_pages * len(source_names)
        result = {
            "mode": "live-dry-run",
            "network_requests": 0,
            "sources": source_names,
            "seed_category_pages": {
                "musinsa": len(config["live_seeds"]["musinsa"]) if "musinsa" in source_names else 0,
                "uniqlo_by_audience": {
                    audience: len(state["queue"])
                    for audience, state in initial_uniqlo_audience_states(config).items()
                } if "uniqlo" in source_names else {},
            },
            "maximum_category_page_requests": category_limit,
            "maximum_product_detail_requests": product_limit,
            "maximum_total_requests": category_limit + product_limit,
            "maximum_attempts_with_retries": (
                category_limit + product_limit
            ) * (args.retries + 1),
            "musinsa_product_limit": args.musinsa_limit,
            "uniqlo_total_product_request_limit": args.uniqlo_limit,
            "uniqlo_confirmed_audience_limits": audience_limits,
            "limit_rule": (
                "Uniqlo detail requests stop at --uniqlo-limit. Hydration-confirmed "
                "audience observations are accepted until that audience limit; the "
                "first reached limit applies."
            ),
            "delay_ms": args.delay_ms,
            "retries": args.retries,
            "checkpoint": str(checkpoint_path),
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return result

    output_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = output_dir / "raw"
    state = load_live_state(checkpoint_path, args.resume, config)
    write_json(checkpoint_path, state)

    def record_request(event: dict[str, Any]) -> None:
        state.setdefault("request_events", []).append(event)
        write_json(checkpoint_path, state)

    fetcher = RateLimitedFetcher(args.delay_ms, args.retries, event_handler=record_request)
    all_paths: list[dict[str, Any]] = list(state.get("path_rows", []))
    all_exposures: list[dict[str, Any]] = list(state.get("exposure_rows", []))
    manifest_by_key: dict[tuple[str, str], dict[str, Any]] = {
        (item["source"], item["product_key"]): item
        for item in state.get("manifests", [])
    }

    if "musinsa" in source_names:
        source = "musinsa"
        source_state = state["sources"][source]
        queue = deque(source_state["queue"])
        visited = set(source_state["visited_categories"])
        product_exposures: dict[str, set[str]] = {
            key: set(value) for key, value in source_state["discovered_products"].items()
        }
        while queue and len(visited) < args.max_category_pages:
            page_url = queue.popleft()
            if page_url in visited:
                continue
            result = fetcher.fetch(
                page_url,
                context={"source": source, "kind": "category_page", "queue_audience": ""},
            )
            evidence = save_raw(
                raw_path(raw_dir, source, "category-pages", hashlib.sha256(page_url.encode()).hexdigest()[:20], result.content_type),
                result,
            )
            state["raw_records"].append(evidence)
            visited.add(page_url)
            categories, products = discover_links(source, page_url, result.body)
            for category in sorted(categories):
                if category not in visited and category not in queue:
                    queue.append(category)
            for product in products:
                product_exposures.setdefault(product, set()).add(page_url)
            source_state["queue"] = list(queue)
            source_state["visited_categories"] = sorted(visited)
            source_state["discovered_products"] = {
                key: sorted(value) for key, value in sorted(product_exposures.items())
            }
            write_json(checkpoint_path, state)

        processed = set(source_state["processed_products"])
        for observed_id in sorted(product_exposures):
            if len(processed) >= args.musinsa_limit or observed_id in processed:
                continue
            detail_url = f"https://goods-detail.musinsa.com/api2/goods/{observed_id}"
            result = fetcher.fetch(
                detail_url,
                referer=next(iter(product_exposures[observed_id]), None),
                context={
                    "source": source,
                    "kind": "product",
                    "queue_audience": "",
                    "observed_id": observed_id,
                },
            )
            evidence_path = raw_path(raw_dir, source, "products", observed_id, result.content_type)
            evidence = save_raw(evidence_path, result)
            state["raw_records"].append(evidence)
            category = musinsa_category_evidence(result.body)
            product_key, color_code = product_identity(source, observed_id)
            manifest_key = (source, product_key)
            manifest = manifest_by_key.setdefault(
                manifest_key,
                {
                    "source": source,
                    "product_key": product_key,
                    "observed_ids": [],
                    "color_codes": [],
                    "exposure_paths": [],
                    "raw_evidence": [],
                },
            )
            if observed_id not in manifest["observed_ids"]:
                manifest["observed_ids"].append(observed_id)
            if color_code and color_code not in manifest["color_codes"]:
                manifest["color_codes"].append(color_code)
            if category["path"] and category["path"] not in manifest["exposure_paths"]:
                manifest["exposure_paths"].append(category["path"])
            manifest["raw_evidence"].append(evidence)
            path_row = {
                    "source": source,
                    "product_key": product_key,
                    "observed_id": observed_id,
                    "queue_audience": "",
                    "product_name": "",
                    "audience": category["audience"],
                    "accepted_for_audience_quota": True,
                    "category_path": category["path"],
                    **{
                        f"depth{index}_name": (
                            category["depth_names"][index - 1]
                            if len(category["depth_names"]) >= index else ""
                        )
                        for index in range(1, 5)
                    },
                    **{
                        f"depth{index}_code": (
                            category["depth_codes"][index - 1]
                            if len(category["depth_codes"]) >= index else ""
                        )
                        for index in range(1, 5)
                    },
                    "evidence_url": result.url,
                    "evidence_source": category.get("evidence_source", "musinsa_detail_api"),
                    "breadcrumb_evidence_json": json.dumps(
                        category.get("breadcrumb_items", []),
                        ensure_ascii=False,
                        separators=(",", ":"),
                    ),
                    "unresolved_reason": category.get("unresolved_reason", ""),
                }
            if path_row not in all_paths:
                all_paths.append(path_row)
            for exposure_url in sorted(product_exposures[observed_id]):
                exposure_row = {
                        "source": source,
                        "product_key": product_key,
                        "observed_id": observed_id,
                        "color_code": color_code or "",
                        "category_path": category["path"],
                        "category_url": exposure_url,
                        "queue_audience": "",
                        "actual_audience": "",
                        "accepted_for_audience_quota": True,
                        "evidence_url": result.url,
                        "evidence_type": "live_public_response",
                    }
                if exposure_row not in all_exposures:
                    all_exposures.append(exposure_row)
            processed.add(observed_id)
            source_state["processed_products"] = sorted(processed)
            state["manifests"] = list(manifest_by_key.values())
            state["path_rows"] = all_paths
            state["exposure_rows"] = all_exposures
            write_json(checkpoint_path, state)

    if "uniqlo" in source_names:
        source = "uniqlo"
        source_state = state["sources"][source]
        audience_states = source_state["audiences"]
        total_visited = sum(
            len(audience_states[audience]["visited_categories"])
            for audience in AUDIENCE_ORDER
        )
        while total_visited < args.max_category_pages:
            progressed = False
            for queue_audience in AUDIENCE_ORDER:
                if total_visited >= args.max_category_pages:
                    break
                audience_state = audience_states[queue_audience]
                if not audience_has_capacity(source_state, queue_audience, audience_limits):
                    continue
                queue = deque(audience_state["queue"])
                visited = set(audience_state["visited_categories"])
                while queue and queue[0] in visited:
                    queue.popleft()
                if not queue:
                    audience_state["queue"] = []
                    continue
                page_url = queue.popleft()
                normalized_page_url, invalid_reason = validated_uniqlo_category_href(
                    page_url, page_url
                )
                if (
                    normalized_page_url is None
                    or audience_from_uniqlo_url(normalized_page_url) != queue_audience
                ):
                    source_state.setdefault("rejected_category_urls", []).append(
                        {
                            "page_url": "",
                            "raw_href": "",
                            "resolved_url": page_url,
                            "raw_order": "",
                            "evidence_source": "checkpoint_queue_validation",
                            "reason": invalid_reason
                            or "category URL audience does not match its queue",
                            "request_skipped": True,
                        }
                    )
                    audience_state["queue"] = list(queue)
                    write_json(checkpoint_path, state)
                    progressed = True
                    continue
                page_url = normalized_page_url
                try:
                    result = fetcher.fetch(
                        page_url,
                        context={
                            "source": source,
                            "kind": "category_page",
                            "queue_audience": queue_audience,
                        },
                    )
                except HTTPStatusError as error:
                    if error.status != 404:
                        raise
                    source_state.setdefault("rejected_category_urls", []).append(
                        {
                            "page_url": "",
                            "raw_href": "",
                            "resolved_url": page_url,
                            "raw_order": "",
                            "evidence_source": "http_404_category_response",
                            "reason": "public category request returned HTTP 404",
                            "request_skipped": False,
                        }
                    )
                    audience_state["queue"] = list(queue)
                    write_json(checkpoint_path, state)
                    progressed = True
                    continue
                evidence = save_raw(
                    raw_path(
                        raw_dir,
                        source,
                        "category-pages",
                        hashlib.sha256(page_url.encode()).hexdigest()[:20],
                        result.content_type,
                    ),
                    result,
                )
                state["raw_records"].append(evidence)
                visited.add(page_url)
                page_evidence = uniqlo_category_page_evidence(page_url, result.body)
                for rejected_url in page_evidence.get("rejected_category_urls", []):
                    record = {
                        **rejected_url,
                        "raw_path": evidence["path"],
                        "raw_sha256": evidence["sha256"],
                        "request_skipped": True,
                    }
                    values = source_state.setdefault("rejected_category_urls", [])
                    if record not in values:
                        values.append(record)
                categories = set(page_evidence["category_urls"])
                products = set(page_evidence["product_ids"])
                merge_uniqlo_category_discovery(
                    audience_states,
                    queue_audience,
                    queue,
                    visited,
                    categories,
                )
                source_state.setdefault("category_discovery_evidence", []).append(
                    {
                        "page_url": page_url,
                        "queue_audience": queue_audience,
                        **page_evidence,
                    }
                )
                for product in products:
                    urls = audience_state["discovered_products"].setdefault(product, [])
                    if page_url not in urls:
                        urls.append(page_url)
                audience_state["queue"] = list(queue)
                audience_state["visited_categories"] = sorted(visited)
                total_visited += 1
                progressed = True
                write_json(checkpoint_path, state)
            if not progressed:
                break

        processed = set(source_state["processed_products"])
        while len(processed) < args.uniqlo_limit:
            progressed = False
            for queue_audience in AUDIENCE_ORDER:
                if len(processed) >= args.uniqlo_limit:
                    break
                audience_state = audience_states[queue_audience]
                if len(audience_state["confirmed_products"]) >= audience_limits[queue_audience]:
                    continue
                candidate = next(
                    (
                        observed_id
                        for observed_id in sorted(audience_state["discovered_products"])
                        if observed_id not in processed
                    ),
                    None,
                )
                if candidate is None:
                    continue
                observed_id = candidate
                exposure_pairs: list[tuple[str, str]] = []
                for exposure_audience in AUDIENCE_ORDER:
                    urls = audience_states[exposure_audience]["discovered_products"].get(
                        observed_id, []
                    )
                    exposure_pairs.extend((exposure_audience, url) for url in urls)
                detail_url = f"https://www.uniqlo.com/kr/ko/products/{observed_id}"
                result = fetcher.fetch(
                    detail_url,
                    referer=exposure_pairs[0][1] if exposure_pairs else None,
                    context={
                        "source": source,
                        "kind": "product",
                        "queue_audience": queue_audience,
                        "observed_id": observed_id,
                    },
                )
                evidence_path = raw_path(
                    raw_dir, source, "products", observed_id, result.content_type
                )
                evidence = save_raw(evidence_path, result)
                state["raw_records"].append(evidence)
                category = uniqlo_category_evidence(result.body, observed_id)
                actual_audience, accepted = record_uniqlo_audience_result(
                    source_state,
                    observed_id,
                    queue_audience,
                    category,
                    audience_limits,
                )

                product_key, color_code = product_identity(source, observed_id)
                update_product_manifest(
                    manifest_by_key,
                    source,
                    observed_id,
                    evidence,
                    {
                        "observed_id": observed_id,
                        "queue_audience": queue_audience,
                        "actual_audience": actual_audience,
                        "accepted_for_audience_quota": accepted,
                        "status": category["status"],
                        "path": category["path"],
                        "evidence_source": category["evidence_source"],
                        "breadcrumb_items": category.get("breadcrumb_items", []),
                        "unresolved_reason": category["unresolved_reason"],
                    },
                )
                path_row = {
                    "source": source,
                    "product_key": product_key,
                    "observed_id": observed_id,
                    "queue_audience": queue_audience,
                    "product_name": "",
                    "audience": actual_audience,
                    "accepted_for_audience_quota": accepted,
                    "category_path": category["path"],
                    **{
                        f"depth{index}_name": (
                            category["depth_names"][index - 1]
                            if len(category["depth_names"]) >= index else ""
                        )
                        for index in range(1, 5)
                    },
                    **{
                        f"depth{index}_code": (
                            category["depth_codes"][index - 1]
                            if len(category["depth_codes"]) >= index else ""
                        )
                        for index in range(1, 5)
                    },
                    "evidence_url": result.url,
                    "evidence_source": category["evidence_source"],
                    "breadcrumb_evidence_json": json.dumps(
                        category.get("breadcrumb_items", []),
                        ensure_ascii=False,
                        separators=(",", ":"),
                    ),
                    "unresolved_reason": category["unresolved_reason"],
                }
                if path_row not in all_paths:
                    all_paths.append(path_row)
                for exposure_audience, exposure_url in sorted(set(exposure_pairs)):
                    exposure_row = {
                        "source": source,
                        "product_key": product_key,
                        "observed_id": observed_id,
                        "color_code": color_code or "",
                        "category_path": category["path"],
                        "category_url": exposure_url,
                        "queue_audience": exposure_audience,
                        "actual_audience": actual_audience,
                        "accepted_for_audience_quota": accepted,
                        "evidence_url": result.url,
                        "evidence_type": "live_public_response",
                    }
                    if exposure_row not in all_exposures:
                        all_exposures.append(exposure_row)
                processed.add(observed_id)
                source_state["processed_products"] = sorted(processed)
                state["manifests"] = list(manifest_by_key.values())
                state["path_rows"] = all_paths
                state["exposure_rows"] = all_exposures
                write_json(checkpoint_path, state)
                progressed = True
            if not progressed:
                break

    # Live output intentionally uses the same stable schemas as bootstrap.
    write_json(
        output_dir / "product_manifest.json",
        {
            "mode": "live",
            "generated_at": utc_now(),
            "products": sorted(
                manifest_by_key.values(), key=lambda item: (item["source"], item["product_key"])
            ),
        },
    )
    path_fields = [
        "source", "product_key", "observed_id", "queue_audience", "product_name",
        "audience", "accepted_for_audience_quota", "category_path",
        "depth1_name", "depth1_code", "depth2_name", "depth2_code",
        "depth3_name", "depth3_code", "depth4_name", "depth4_code", "evidence_url",
        "evidence_source", "breadcrumb_evidence_json", "unresolved_reason",
    ]
    write_csv(output_dir / "product_category_paths.csv", path_fields, all_paths)
    exposure_fields = [
        "source", "product_key", "observed_id", "color_code", "category_path",
        "category_url", "queue_audience", "actual_audience",
        "accepted_for_audience_quota", "evidence_url", "evidence_type",
    ]
    write_csv(output_dir / "category_exposures.csv", exposure_fields, all_exposures)
    # Inventory is derived from collected product paths. Navigation-only nodes remain
    # in checkpoint/raw evidence until a later reviewed extractor can name them safely.
    inventory = derive_live_inventory(all_paths, config)
    write_json(
        output_dir / "category_inventory.json",
        {"mode": "live", "generated_at": utc_now(), "nodes": inventory},
    )
    unresolved = [node for node in inventory if node["status"] == "unresolved"]
    if "uniqlo" in source_names:
        unresolved.extend(
            {
                "source": "uniqlo",
                "path": "",
                "status": "unresolved",
                "unresolved_rule": "audience_unknown",
                "unresolved_reason": item["reason"],
                "direct_product_count": 1,
                "observed_id": item["observed_id"],
            }
            for item in state["sources"]["uniqlo"]["unknown_audience_products"]
        )
        unresolved.extend(
            {
                "source": "uniqlo",
                "path": "",
                "status": "unresolved",
                "unresolved_rule": "invalid_category_url",
                "unresolved_reason": (
                    f"{item.get('reason', '')}; raw_href={item.get('raw_href', '')}; "
                    f"resolved_url={item.get('resolved_url', '')}; "
                    f"raw_path={item.get('raw_path', '')}"
                ),
                "direct_product_count": 0,
                "observed_id": "",
            }
            for item in state["sources"]["uniqlo"].get(
                "rejected_category_urls", []
            )
        )
    write_csv(
        output_dir / "unresolved_categories.csv",
        [
            "source", "observed_id", "category_path", "status",
            "rule", "reason", "direct_product_count",
        ],
        [
            {
                "source": node["source"],
                "observed_id": node.get("observed_id", ""),
                "category_path": node["path"],
                "status": node["status"],
                "rule": node["unresolved_rule"],
                "reason": node["unresolved_reason"],
                "direct_product_count": node["direct_product_count"],
            }
            for node in unresolved
        ],
    )
    request_metrics = summarize_request_events(state.get("request_events", []))
    write_json(output_dir / "request_metrics.json", request_metrics)
    uniqlo_counts = {}
    if "uniqlo" in source_names:
        uniqlo_counts = {
            audience: len(
                state["sources"]["uniqlo"]["audiences"][audience]["confirmed_products"]
            )
            for audience in AUDIENCE_ORDER
        }
    (output_dir / "collection_summary.md").write_text(
        "# Category corpus live summary\n\n"
        f"- Generated: {utc_now()}\n"
        f"- Network requests in this run: {fetcher.request_count}\n"
        f"- Request metrics: {json.dumps(request_metrics, ensure_ascii=False)}\n"
        f"- Unique base products in output: {len(manifest_by_key)}\n"
        f"- Uniqlo hydration-confirmed accepted products: "
        f"{json.dumps(uniqlo_counts, ensure_ascii=False)}\n"
        f"- Inventory nodes: {len(inventory)}\n"
        f"- Unresolved nodes: {len(unresolved)}\n"
        f"- Checkpoint: {checkpoint_path}\n",
        encoding="utf-8",
    )
    return {
        "network_requests": fetcher.request_count,
        "request_metrics": request_metrics,
        "products": len(manifest_by_key),
        "uniqlo_confirmed_audience_counts": uniqlo_counts,
        "inventory_nodes": len(inventory),
        "checkpoint": str(checkpoint_path),
    }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def offline_reprocess(output_dir: Path) -> dict[str, Any]:
    """Rebuild parsing outputs from saved raw files without making a request."""
    output_dir = output_dir.resolve()
    checkpoint_path = output_dir / "checkpoint.json"
    if not checkpoint_path.is_file():
        raise RuntimeError(f"checkpoint.json not found: {checkpoint_path}")
    checkpoint_hash_before = sha256_file(checkpoint_path)
    state = read_json(checkpoint_path)
    config = read_json(CONFIG_PATH)

    raw_records = state.get("raw_records", [])
    raw_hash_failures: list[dict[str, str]] = []
    for record in raw_records:
        path = Path(record["path"])
        if not path.is_absolute():
            path = (REPO_ROOT / path).resolve()
        actual_hash = sha256_file(path) if path.is_file() else ""
        if actual_hash != record.get("sha256"):
            raw_hash_failures.append(
                {
                    "path": str(path),
                    "expected": str(record.get("sha256") or ""),
                    "actual": actual_hash,
                }
            )
    if raw_hash_failures:
        raise RuntimeError(f"Raw evidence integrity failure: {raw_hash_failures}")

    parsed_uniqlo: dict[str, dict[str, Any]] = {}
    raw_record_by_observed: dict[str, dict[str, Any]] = {}
    for record in raw_records:
        raw_file = Path(record["path"])
        if not raw_file.is_absolute():
            raw_file = (REPO_ROOT / raw_file).resolve()
        parts = raw_file.parts
        if "uniqlo" not in parts or raw_file.parent.name != "products":
            continue
        observed_id = raw_file.stem.upper()
        parsed_uniqlo[observed_id] = uniqlo_category_evidence(
            raw_file.read_bytes(),
            observed_id,
        )
        raw_record_by_observed[observed_id] = record

    original_paths = copy.deepcopy(state.get("path_rows", []))
    rebuilt_paths: list[dict[str, Any]] = [
        {
            **row,
            "observed_id": row.get("observed_id", ""),
            "evidence_source": row.get("evidence_source", "musinsa_detail_api"),
            "breadcrumb_evidence_json": row.get("breadcrumb_evidence_json", ""),
            "unresolved_reason": row.get("unresolved_reason", ""),
        }
        for row in original_paths
        if row.get("source") != "uniqlo"
    ]
    per_product_results: list[dict[str, Any]] = []
    for observed_id, category in sorted(parsed_uniqlo.items()):
        product_key, _ = product_identity("uniqlo", observed_id)
        record = raw_record_by_observed[observed_id]
        breadcrumb_items = category.get("breadcrumb_items", [])
        rebuilt_paths.append(
            {
                "source": "uniqlo",
                "product_key": product_key,
                "observed_id": observed_id,
                "product_name": "",
                "audience": category["audience"],
                "category_path": category["path"],
                **{
                    f"depth{index}_name": (
                        category["depth_names"][index - 1]
                        if len(category["depth_names"]) >= index else ""
                    )
                    for index in range(1, 5)
                },
                **{
                    f"depth{index}_code": (
                        category["depth_codes"][index - 1]
                        if len(category["depth_codes"]) >= index else ""
                    )
                    for index in range(1, 5)
                },
                "evidence_url": record["url"],
                "evidence_source": category["evidence_source"],
                "breadcrumb_evidence_json": json.dumps(
                    breadcrumb_items,
                    ensure_ascii=False,
                    separators=(",", ":"),
                ),
                "unresolved_reason": category["unresolved_reason"],
            }
        )
        per_product_results.append(
            {
                "observed_id": observed_id,
                "product_key": product_key,
                "status": category["status"],
                "path": category["path"],
                "audience": category["audience"],
                "evidence_source": category["evidence_source"],
                "selected_entity_key": category.get("selected_entity_key", ""),
                "entity_match_basis": category.get("entity_match_basis", ""),
                "breadcrumb_items": breadcrumb_items,
                "unresolved_reason": category["unresolved_reason"],
                "evidence_candidates": category.get("evidence_candidates", {}),
            }
        )

    manifests = copy.deepcopy(state.get("manifests", []))
    for manifest in manifests:
        if manifest.get("source") != "uniqlo":
            continue
        observations = []
        paths = list(manifest.get("exposure_paths", []))
        for observed_id in manifest.get("observed_ids", []):
            category = parsed_uniqlo.get(str(observed_id).upper())
            if not category:
                continue
            observations.append(
                {
                    "observed_id": observed_id,
                    "status": category["status"],
                    "path": category["path"],
                    "audience": category["audience"],
                    "evidence_source": category["evidence_source"],
                    "selected_entity_key": category.get("selected_entity_key", ""),
                    "entity_match_basis": category.get("entity_match_basis", ""),
                    "breadcrumb_items": category.get("breadcrumb_items", []),
                    "unresolved_reason": category["unresolved_reason"],
                }
            )
            if category["path"] and category["path"] not in paths:
                paths.append(category["path"])
        manifest["exposure_paths"] = paths
        manifest["category_observations"] = observations

    exposures = copy.deepcopy(state.get("exposure_rows", []))
    for exposure in exposures:
        if exposure.get("source") != "uniqlo":
            continue
        category = parsed_uniqlo.get(str(exposure.get("observed_id", "")).upper())
        if category:
            exposure["category_path"] = category["path"]
            exposure["category_evidence_source"] = category["evidence_source"]

    inventory = derive_live_inventory(rebuilt_paths, config)
    parse_unresolved = [
        result for result in per_product_results if result["status"] != "resolved"
    ]
    unresolved_rows = [
        {
            "source": node["source"],
            "observed_id": "",
            "category_path": node["path"],
            "status": node["status"],
            "rule": node["unresolved_rule"] or "configured_unresolved",
            "reason": node["unresolved_reason"],
            "direct_product_count": node["direct_product_count"],
        }
        for node in inventory
        if node["status"] == "unresolved"
    ]
    unresolved_rows.extend(
        {
            "source": "uniqlo",
            "observed_id": result["observed_id"],
            "category_path": "",
            "status": "unresolved",
            "rule": "category_evidence_unresolved",
            "reason": result["unresolved_reason"],
            "direct_product_count": 1,
        }
        for result in parse_unresolved
    )

    path_fields = [
        "source", "product_key", "observed_id", "product_name", "audience", "category_path",
        "depth1_name", "depth1_code", "depth2_name", "depth2_code",
        "depth3_name", "depth3_code", "depth4_name", "depth4_code", "evidence_url",
        "evidence_source", "breadcrumb_evidence_json", "unresolved_reason",
    ]
    exposure_fields = [
        "source", "product_key", "observed_id", "color_code", "category_path",
        "category_url", "evidence_url", "evidence_type", "category_evidence_source",
    ]
    write_json(
        output_dir / "product_manifest.json",
        {
            "mode": "live-offline-reprocessed",
            "generated_at": utc_now(),
            "products": sorted(manifests, key=lambda item: (item["source"], item["product_key"])),
        },
    )
    write_csv(output_dir / "product_category_paths.csv", path_fields, rebuilt_paths)
    write_csv(output_dir / "category_exposures.csv", exposure_fields, exposures)
    write_json(
        output_dir / "category_inventory.json",
        {
            "mode": "live-offline-reprocessed",
            "generated_at": utc_now(),
            "nodes": inventory,
        },
    )
    write_csv(
        output_dir / "unresolved_categories.csv",
        [
            "source", "observed_id", "category_path", "status",
            "rule", "reason", "direct_product_count",
        ],
        unresolved_rows,
    )

    resolved = [result for result in per_product_results if result["status"] == "resolved"]
    empty_paths = [result for result in per_product_results if not result["path"]]
    unique_paths = sorted({result["path"] for result in resolved if result["path"]})
    audiences = defaultdict(int)
    evidence_sources = defaultdict(int)
    for result in per_product_results:
        audiences[result["audience"] or "unknown"] += 1
        evidence_sources[result["evidence_source"]] += 1
    summary_payload = {
        "mode": "offline-reprocess",
        "generated_at": utc_now(),
        "network_requests": 0,
        "checkpoint_sha256": checkpoint_hash_before,
        "checkpoint_preserved": checkpoint_hash_before == sha256_file(checkpoint_path),
        "raw_files_verified": len(raw_records),
        "raw_hash_failures": raw_hash_failures,
        "uniqlo_raw_products": len(per_product_results),
        "resolved_paths": len(resolved),
        "empty_paths": len(empty_paths),
        "unresolved_products": len(parse_unresolved),
        "unique_paths": unique_paths,
        "audience_counts": dict(sorted(audiences.items())),
        "evidence_source_counts": dict(sorted(evidence_sources.items())),
        "inventory_status_counts": dict(
            sorted(
                (status, sum(1 for node in inventory if node["status"] == status))
                for status in {
                    "direct_product_leaf",
                    "intermediate",
                    "leaf_and_parent",
                    "navigation_only",
                    "unresolved",
                }
            )
        ),
        "per_product": per_product_results,
    }
    write_json(output_dir / "offline_reprocess_summary.json", summary_payload)
    (output_dir / "collection_summary.md").write_text(
        "# Category corpus offline reprocess summary\n\n"
        f"- Generated: {utc_now()}\n"
        "- Network requests: 0\n"
        f"- Saved raw files verified: {len(raw_records)}\n"
        f"- Checkpoint preserved: {summary_payload['checkpoint_preserved']}\n"
        f"- Uniqlo raw products: {len(per_product_results)}\n"
        f"- Resolved paths: {len(resolved)}\n"
        f"- Empty paths: {len(empty_paths)}\n"
        f"- Unresolved products: {len(parse_unresolved)}\n"
        f"- Unique Uniqlo paths: {len(unique_paths)}\n"
        f"- Audience counts: {json.dumps(dict(sorted(audiences.items())), ensure_ascii=False)}\n"
        f"- Evidence sources: "
        f"{json.dumps(dict(sorted(evidence_sources.items())), ensure_ascii=False)}\n"
        "- Existing product identities, raw evidence, category exposure URLs, and "
        "checkpoint state were preserved.\n",
        encoding="utf-8",
    )
    if not summary_payload["checkpoint_preserved"]:
        raise RuntimeError("offline reprocess unexpectedly changed checkpoint.json")
    return summary_payload


def derive_live_inventory(path_rows: list[dict[str, Any]], config: dict[str, Any]) -> list[dict[str, Any]]:
    direct: dict[tuple[str, str], set[str]] = defaultdict(set)
    keys: set[tuple[str, str]] = set()
    alternate_paths: dict[tuple[str, str], set[str]] = defaultdict(set)
    for row in path_rows:
        source = row["source"]
        full_path = normalized_path(row["category_path"])
        if not full_path:
            continue
        direct[(source, full_path)].add(row["product_key"])
        raw_breadcrumb = row.get("breadcrumb_evidence_json", "")
        if raw_breadcrumb:
            try:
                breadcrumb_items = json.loads(raw_breadcrumb)
            except json.JSONDecodeError:
                breadcrumb_items = []
            name_path = normalized_path(
                [
                    item.get("name", "")
                    for item in breadcrumb_items
                    if item.get("role") in {"class", "category", "subcategory"}
                ]
            )
            if name_path:
                alternate_paths[(source, full_path)].add(name_path)
        for prefix in path_prefixes(split_path(full_path)):
            keys.add((source, normalized_path(prefix)))
    nodes: list[dict[str, Any]] = []
    for source, path in sorted(keys):
        children = sum(
            1 for child_source, child_path in keys
            if child_source == source and normalized_path(split_path(child_path)[:-1]) == path
        )
        direct_count = len(direct.get((source, path), set()))
        flags = configured_flags(source, path, config, alternate_paths.get((source, path), set()))
        status = classify_node_status(
            direct_count,
            children,
            False,
            bool(flags["unresolved_rule"]),
        )
        nodes.append(
            {
                "source": source,
                "path": path,
                "name": split_path(path)[-1],
                "depth": len(split_path(path)),
                "parent_path": normalized_path(split_path(path)[:-1]),
                "direct_product_count": direct_count,
                "child_count": children,
                "status": status,
                **flags,
            }
        )
    return nodes


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    bootstrap_parser = subparsers.add_parser(
        "bootstrap", help="Validate and normalize the restored 300-product survey without network access"
    )
    bootstrap_parser.add_argument("--survey-dir", type=Path, default=DEFAULT_SURVEY_DIR)
    bootstrap_parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_DIR)

    live_parser = subparsers.add_parser(
        "live", help="Explicitly collect public live category evidence; never used by bootstrap"
    )
    live_parser.add_argument("--source", choices=["musinsa", "uniqlo", "all"], default="all")
    live_parser.add_argument("--output", type=Path, required=True)
    live_parser.add_argument("--dry-run", action="store_true")
    live_parser.add_argument("--resume", action="store_true")
    live_parser.add_argument("--delay-ms", type=int, default=MIN_DELAY_MS)
    live_parser.add_argument("--retries", type=int, default=DEFAULT_RETRIES)
    live_parser.add_argument("--max-category-pages", type=int, default=250)
    live_parser.add_argument("--musinsa-limit", type=int, default=1000)
    live_parser.add_argument("--uniqlo-limit", type=int, default=200)
    live_parser.add_argument("--uniqlo-men-limit", type=int)
    live_parser.add_argument("--uniqlo-women-limit", type=int)
    live_parser.add_argument("--uniqlo-kids-limit", type=int)
    live_parser.add_argument("--uniqlo-baby-limit", type=int)

    offline_parser = subparsers.add_parser(
        "offline-reprocess",
        help="Rebuild parsing outputs from an existing checkpoint and raw files without network access",
    )
    offline_parser.add_argument("--output", type=Path, required=True)

    probe_parser = subparsers.add_parser(
        "baby-probe",
        help="Run the fixed one-category/four-product BABY live probe (maximum five requests)",
    )
    probe_parser.add_argument("--output", type=Path, required=True)
    probe_parser.add_argument("--medium-dir", type=Path, default=DEFAULT_MEDIUM_DIR)
    probe_parser.add_argument("--delay-ms", type=int, default=MIN_DELAY_MS)
    probe_parser.add_argument("--retries", type=int, default=DEFAULT_RETRIES)

    baby_collect_parser = subparsers.add_parser(
        "baby-collect-10",
        help="Collect at most ten hydration-confirmed unique BABY products",
    )
    baby_collect_parser.add_argument("--output", type=Path, required=True)
    baby_collect_parser.add_argument(
        "--evidence-dir",
        type=Path,
        default=REPO_ROOT / "Docs/Research/CategoryCorpus-live-baby-probe-v2",
    )
    baby_collect_parser.add_argument("--baby-limit", type=int, default=10)
    baby_collect_parser.add_argument("--max-logical-requests", type=int, default=25)
    baby_collect_parser.add_argument("--delay-ms", type=int, default=MIN_DELAY_MS)
    baby_collect_parser.add_argument("--retries", type=int, default=DEFAULT_RETRIES)
    baby_collect_parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.command == "bootstrap":
            result = bootstrap(args.survey_dir.resolve(), args.output.resolve())
        elif args.command == "offline-reprocess":
            result = offline_reprocess(args.output.resolve())
        elif args.command == "baby-probe":
            result = baby_probe(args)
        elif args.command == "baby-collect-10":
            result = baby_collect_10(args)
        else:
            result = live_collect(args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except Exception as error:
        print(f"category-corpus: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
