#!/usr/bin/env python3
"""Collect the publicly discoverable Musinsa apparel catalog into compact SQLite/CSV files."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import fcntl
import gzip
import html
import json
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TAXONOMY = ROOT / "Docs/Research/CanonicalTaxonomyBundle-20260803/FitMatchSourceCategoryMappings.json"
DEFAULT_OUTPUT = Path.home() / "Desktop/무신사_전체의류_데이터"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) FitMatchCatalog/1.0"
NEXT_DATA_PATTERN = re.compile(r'<script[^>]+id="__NEXT_DATA__"[^>]*>(.*?)</script>', re.DOTALL)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


class RateLimiter:
    def __init__(self, delay_seconds: float):
        self.delay_seconds = delay_seconds
        self.lock = threading.Lock()
        self.next_request = 0.0

    def wait(self) -> None:
        with self.lock:
            current = time.monotonic()
            wait_seconds = max(0.0, self.next_request - current)
            self.next_request = max(current, self.next_request) + self.delay_seconds
        if wait_seconds:
            time.sleep(wait_seconds)


class FetchError(RuntimeError):
    def __init__(self, message: str, status: int = 0):
        super().__init__(message)
        self.status = status


def fetch(url: str, referer: str, limiter: RateLimiter, retries: int) -> tuple[bytes, int, str]:
    last_error: Exception | None = None
    for attempt in range(retries + 1):
        limiter.wait()
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "application/json,text/html;q=0.9,*/*;q=0.8",
                "Referer": referer,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read(), response.status, response.geturl()
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code not in (403, 408, 429, 500, 502, 503, 504) or attempt == retries:
                raise FetchError(f"HTTP {error.code}: {url}", error.code) from error
            retry_after = error.headers.get("Retry-After")
            time.sleep(float(retry_after) if retry_after and retry_after.isdigit() else min(30, 2 ** attempt))
        except (TimeoutError, urllib.error.URLError) as error:
            last_error = error
            if attempt == retries:
                raise FetchError(f"network error: {url}: {error}") from error
            time.sleep(min(30, 2 ** attempt))
    raise FetchError(str(last_error or "unknown fetch error"))


def find_product_page(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        if isinstance(value.get("list"), list) and isinstance(value.get("pagination"), dict):
            if any(isinstance(item, dict) and "goodsNo" in item for item in value["list"]):
                return value
        for child in value.values():
            found = find_product_page(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_product_page(child)
            if found:
                return found
    return None


def parse_category_response(body: bytes, content_type: str = "") -> tuple[list[dict], dict]:
    text = body.decode("utf-8", errors="replace")
    if "json" in content_type or text.lstrip().startswith("{"):
        payload = json.loads(text)
        page = find_product_page(payload)
    else:
        match = NEXT_DATA_PATTERN.search(text)
        page = find_product_page(json.loads(html.unescape(match.group(1)))) if match else None
    if page is None:
        raise ValueError("Musinsa product list and pagination were not found")
    return page["list"], page["pagination"]


def apparel_category_codes(taxonomy_path: Path) -> list[str]:
    records = json.loads(taxonomy_path.read_text(encoding="utf-8"))["records"]
    accepted = {
        str(record.get("apiCategoryCode") or "")
        for record in records
        if record.get("source") == "musinsa"
        and record.get("decisionStatus") in {"confirmed", "review_required"}
        and str(record.get("apiCategoryCode") or "").isdigit()
    }
    # Crawl only terminal known apparel categories. Parent category products are
    # represented by their descendants, avoiding the largest duplicate scans.
    return sorted(code for code in accepted if not any(other.startswith(code) and len(other) > len(code) for other in accepted))


def connect(database: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute("PRAGMA synchronous=NORMAL")
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS categories (
            category_code TEXT PRIMARY KEY,
            next_url TEXT NOT NULL,
            next_page INTEGER NOT NULL DEFAULT 1,
            total_pages INTEGER,
            completed INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS pages (
            category_code TEXT NOT NULL,
            page_number INTEGER NOT NULL,
            product_count INTEGER NOT NULL,
            fetched_at TEXT NOT NULL,
            PRIMARY KEY (category_code, page_number)
        );
        CREATE TABLE IF NOT EXISTS products (
            product_id TEXT PRIMARY KEY,
            product_name TEXT NOT NULL DEFAULT '',
            brand_code TEXT NOT NULL DEFAULT '',
            brand_name TEXT NOT NULL DEFAULT '',
            gender TEXT NOT NULL DEFAULT '',
            mall_category TEXT NOT NULL DEFAULT '',
            canonical_url TEXT NOT NULL,
            size_type TEXT NOT NULL DEFAULT '',
            detail_done INTEGER NOT NULL DEFAULT 0,
            size_done INTEGER NOT NULL DEFAULT 0,
            options_done INTEGER NOT NULL DEFAULT 0,
            unavailable INTEGER NOT NULL DEFAULT 0,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            first_seen_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS exposures (
            product_id TEXT NOT NULL,
            category_code TEXT NOT NULL,
            PRIMARY KEY (product_id, category_code)
        );
        CREATE TABLE IF NOT EXISTS sizes (
            product_id TEXT NOT NULL,
            size_name TEXT NOT NULL,
            size_sequence INTEGER NOT NULL,
            measurement_name TEXT NOT NULL,
            measurement_value REAL,
            measurement_sequence INTEGER NOT NULL,
            PRIMARY KEY (product_id, size_name, measurement_name)
        );
        CREATE TABLE IF NOT EXISTS options (
            product_id TEXT NOT NULL,
            option_name TEXT NOT NULL,
            option_value TEXT NOT NULL,
            option_sequence INTEGER NOT NULL,
            value_sequence INTEGER NOT NULL,
            PRIMARY KEY (product_id, option_name, option_value)
        );
        CREATE TABLE IF NOT EXISTS failures (
            phase TEXT NOT NULL,
            item_key TEXT NOT NULL,
            status INTEGER NOT NULL DEFAULT 0,
            error TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            PRIMARY KEY (phase, item_key)
        );
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
    )
    return connection


def initialize_categories(connection: sqlite3.Connection, codes: list[str], refresh: bool) -> None:
    timestamp = utc_now()
    for code in codes:
        url = f"https://www.musinsa.com/category/{code}/goods?gf=A"
        connection.execute(
            "INSERT OR IGNORE INTO categories(category_code,next_url,updated_at) VALUES(?,?,?)",
            (code, url, timestamp),
        )
    if refresh:
        connection.execute(
            "UPDATE categories SET next_url='https://www.musinsa.com/category/' || category_code || '/goods?gf=A', next_page=1, total_pages=NULL, completed=0, last_error=NULL, updated_at=?",
            (timestamp,),
        )
        connection.execute("DELETE FROM pages")
    else:
        # A failed category is deferred for the rest of that run, then retried
        # when the next run starts. This prevents one bad response from
        # blocking every category that follows it.
        connection.execute("UPDATE categories SET last_error=NULL WHERE completed=0")
    connection.commit()


def record_discovery_page(connection: sqlite3.Connection, category_code: str, page_number: int, products: list[dict], pagination: dict) -> None:
    timestamp = utc_now()
    for item in products:
        product_id = str(item.get("goodsNo") or "")
        if not product_id.isdigit():
            continue
        connection.execute(
            """
            INSERT INTO products(product_id,product_name,brand_code,brand_name,gender,canonical_url,first_seen_at,last_seen_at,updated_at)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(product_id) DO UPDATE SET
              product_name=CASE WHEN products.detail_done=0 THEN excluded.product_name ELSE products.product_name END,
              brand_code=CASE WHEN products.detail_done=0 THEN excluded.brand_code ELSE products.brand_code END,
              brand_name=CASE WHEN products.detail_done=0 THEN excluded.brand_name ELSE products.brand_name END,
              gender=CASE WHEN products.detail_done=0 THEN excluded.gender ELSE products.gender END,
              last_seen_at=excluded.last_seen_at,
              updated_at=excluded.updated_at
            """,
            (
                product_id,
                item.get("goodsName") or "",
                item.get("brand") or "",
                item.get("brandName") or "",
                item.get("displayGenderText") or "",
                item.get("goodsLinkUrl") or f"https://www.musinsa.com/products/{product_id}",
                timestamp,
                timestamp,
                timestamp,
            ),
        )
        connection.execute("INSERT OR IGNORE INTO exposures(product_id,category_code) VALUES(?,?)", (product_id, category_code))
    next_url = pagination.get("nextPageUrl") or ""
    completed = not bool(pagination.get("hasNext")) or not next_url
    connection.execute(
        "INSERT OR REPLACE INTO pages(category_code,page_number,product_count,fetched_at) VALUES(?,?,?,?)",
        (category_code, page_number, len(products), timestamp),
    )
    connection.execute(
        "UPDATE categories SET next_url=?,next_page=?,total_pages=?,completed=?,last_error=NULL,updated_at=? WHERE category_code=?",
        (next_url, page_number + 1, pagination.get("totalPages"), int(completed), timestamp, category_code),
    )
    connection.execute("DELETE FROM failures WHERE phase='discovery' AND item_key=?", (f"{category_code}:{page_number}",))
    connection.commit()


def discover(connection: sqlite3.Connection, limiter: RateLimiter, retries: int, max_pages: int) -> int:
    pages_fetched = 0
    while not max_pages or pages_fetched < max_pages:
        category = connection.execute(
            "SELECT * FROM categories WHERE completed=0 AND last_error IS NULL ORDER BY category_code LIMIT 1"
        ).fetchone()
        if category is None:
            break
        code, page_number, url = category["category_code"], category["next_page"], category["next_url"]
        referer = f"https://www.musinsa.com/category/{code}/goods?gf=A"
        try:
            body, _, final_url = fetch(url, referer, limiter, retries)
            content_type = "application/json" if final_url.startswith("https://api.musinsa.com/") else "text/html"
            products, pagination = parse_category_response(body, content_type)
            record_discovery_page(connection, code, page_number, products, pagination)
            pages_fetched += 1
            total_products = connection.execute("SELECT COUNT(*) FROM products").fetchone()[0]
            total_pages = pagination.get("totalPages") or "?"
            print(f"[탐색] 카테고리={code} 페이지={page_number}/{total_pages} 발견상품={total_products:,}", flush=True)
        except Exception as error:
            status = error.status if isinstance(error, FetchError) else 0
            timestamp = utc_now()
            connection.execute("UPDATE categories SET last_error=?,updated_at=? WHERE category_code=?", (str(error), timestamp, code))
            connection.execute("INSERT OR REPLACE INTO failures VALUES(?,?,?,?,?)", ("discovery", f"{code}:{page_number}", status, str(error), timestamp))
            connection.commit()
            print(f"[탐색 실패] 카테고리={code} 페이지={page_number} 오류={error}", flush=True)
            continue
    return pages_fetched


def product_work(row: sqlite3.Row, limiter: RateLimiter, retries: int) -> dict:
    product_id = row["product_id"]
    referer = row["canonical_url"]
    result: dict[str, Any] = {"product_id": product_id, "responses": {}, "errors": {}}
    endpoints = []
    if not row["detail_done"]:
        endpoints.append(("detail", f"https://goods-detail.musinsa.com/api2/goods/{product_id}"))
    if not row["size_done"]:
        endpoints.append(("size", f"https://goods-detail.musinsa.com/api2/goods/{product_id}/actual-size"))
    if not row["options_done"]:
        endpoints.append(("options", f"https://goods-detail.musinsa.com/api2/goods/{product_id}/options"))
    for kind, url in endpoints:
        try:
            body, _, _ = fetch(url, referer, limiter, retries)
            result["responses"][kind] = json.loads(body).get("data") or {}
        except FetchError as error:
            if error.status == 404 and kind in {"size", "options"}:
                result["responses"][kind] = {}
            else:
                result["errors"][kind] = {"status": error.status, "message": str(error)}
                if error.status == 404 and kind == "detail":
                    result["unavailable"] = True
                    break
    return result


def store_product_result(connection: sqlite3.Connection, result: dict) -> None:
    product_id = result["product_id"]
    timestamp = utc_now()
    responses = result["responses"]
    detail = responses.get("detail")
    size = responses.get("size")
    options = responses.get("options")
    if detail is not None:
        brand_info = detail.get("brandInfo") or {}
        connection.execute(
            """
            UPDATE products SET product_name=?,brand_code=?,brand_name=?,gender=?,mall_category=?,canonical_url=?,detail_done=1,updated_at=? WHERE product_id=?
            """,
            (
                detail.get("goodsNm") or detail.get("goodsNmEng") or "",
                detail.get("brand") or "",
                brand_info.get("brandName") if isinstance(brand_info, dict) else "",
                compact_json(detail.get("genders") or detail.get("sex") or detail.get("sexCode") or []),
                detail.get("baseCategoryFullPath") or "",
                f"https://www.musinsa.com/products/{product_id}",
                timestamp,
                product_id,
            ),
        )
    if size is not None:
        connection.execute("DELETE FROM sizes WHERE product_id=?", (product_id,))
        for size_row in size.get("sizes") or []:
            for measurement in size_row.get("items") or []:
                connection.execute(
                    "INSERT OR REPLACE INTO sizes VALUES(?,?,?,?,?,?)",
                    (
                        product_id,
                        str(size_row.get("name") or ""),
                        int(size_row.get("sequence") or 0),
                        str(measurement.get("name") or ""),
                        measurement.get("value"),
                        int(measurement.get("sequence") or 0),
                    ),
                )
        connection.execute("UPDATE products SET size_type=?,size_done=1,updated_at=? WHERE product_id=?", (size.get("typeName") or "", timestamp, product_id))
    if options is not None:
        connection.execute("DELETE FROM options WHERE product_id=?", (product_id,))
        option_groups = (options.get("basic") or []) + (options.get("extra") or [])
        for option in option_groups:
            for value in option.get("optionValues") or []:
                connection.execute(
                    "INSERT OR REPLACE INTO options VALUES(?,?,?,?,?)",
                    (
                        product_id,
                        str(option.get("name") or ""),
                        str(value.get("name") or value.get("code") or ""),
                        int(option.get("sequence") or 0),
                        int(value.get("sequence") or 0),
                    ),
                )
        connection.execute("UPDATE products SET options_done=1,updated_at=? WHERE product_id=?", (timestamp, product_id))
    errors = result.get("errors") or {}
    error_text = "; ".join(f"{kind}: {value['message']}" for kind, value in sorted(errors.items())) or None
    connection.execute(
        "UPDATE products SET attempts=attempts+1,last_error=?,unavailable=?,updated_at=? WHERE product_id=?",
        (error_text, int(result.get("unavailable", False)), timestamp, product_id),
    )
    for kind, error in errors.items():
        connection.execute("INSERT OR REPLACE INTO failures VALUES(?,?,?,?,?)", (kind, product_id, error["status"], error["message"], timestamp))
    for kind in responses:
        connection.execute("DELETE FROM failures WHERE phase=? AND item_key=?", (kind, product_id))
    connection.commit()


def collect_products(
    connection: sqlite3.Connection,
    limiter: RateLimiter,
    retries: int,
    workers: int,
    max_products: int,
    product_ids: list[str],
    batch_size: int,
) -> int:
    if not product_ids and max_products <= 0:
        raise ValueError("상세 수집은 --product-id 또는 --max-products로 대상을 제한해야 합니다.")

    completed = 0
    requested = list(dict.fromkeys(product_ids))
    while True:
        remaining = max_products - completed if max_products else len(requested)
        if remaining <= 0:
            break
        fetch_limit = min(batch_size, remaining)
        if requested:
            current_ids = requested[:fetch_limit]
            requested = requested[fetch_limit:]
            placeholders = ",".join("?" for _ in current_ids)
            rows = connection.execute(
                f"SELECT * FROM products WHERE product_id IN ({placeholders}) AND unavailable=0 "
                "AND (detail_done=0 OR size_done=0 OR options_done=0) ORDER BY CAST(product_id AS INTEGER)",
                current_ids,
            ).fetchall()
        else:
            rows = connection.execute(
                "SELECT * FROM products WHERE unavailable=0 "
                "AND (detail_done=0 OR size_done=0 OR options_done=0) "
                "ORDER BY CAST(product_id AS INTEGER) LIMIT ?",
                (fetch_limit,),
            ).fetchall()
        if not rows:
            if requested:
                continue
            break
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [executor.submit(product_work, row, limiter, retries) for row in rows]
            for future in concurrent.futures.as_completed(futures):
                store_product_result(connection, future.result())
                completed += 1
                if completed % 25 == 0:
                    print(f"[상세] 이번실행={completed:,}", flush=True)
        print(f"[상세] 이번실행={completed:,} 최근배치={len(rows):,}", flush=True)
    return completed


@contextmanager
def gzip_csv(path: Path, fields: list[str]) -> Iterator[csv.writer]:
    with gzip.open(path, "wt", encoding="utf-8-sig", newline="", compresslevel=9) as stream:
        writer = csv.writer(stream)
        writer.writerow(fields)
        yield writer


def export_files(connection: sqlite3.Connection, output: Path) -> dict:
    with gzip_csv(output / "musinsa_products.csv.gz", [
        "product_id", "product_name", "brand_code", "brand_name", "gender", "mall_category",
        "canonical_url", "size_type", "unavailable", "first_seen_at", "last_seen_at", "updated_at",
    ]) as writer:
        for row in connection.execute(
            "SELECT product_id,product_name,brand_code,brand_name,gender,mall_category,canonical_url,size_type,unavailable,first_seen_at,last_seen_at,updated_at FROM products ORDER BY CAST(product_id AS INTEGER)"
        ):
            writer.writerow(row)
    with gzip_csv(output / "musinsa_sizes.csv.gz", [
        "product_id", "size_name", "size_sequence", "measurement_name", "measurement_value", "measurement_sequence",
    ]) as writer:
        for row in connection.execute("SELECT * FROM sizes ORDER BY CAST(product_id AS INTEGER),size_sequence,measurement_sequence"):
            writer.writerow(row)
    with gzip_csv(output / "musinsa_options.csv.gz", [
        "product_id", "option_name", "option_value", "option_sequence", "value_sequence",
    ]) as writer:
        for row in connection.execute("SELECT * FROM options ORDER BY CAST(product_id AS INTEGER),option_sequence,value_sequence"):
            writer.writerow(row)
    with (output / "musinsa_failures.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["phase", "item_key", "status", "error", "occurred_at"])
        writer.writerows(connection.execute("SELECT * FROM failures ORDER BY phase,item_key"))
    summary = summary_data(connection)
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary


def summary_data(connection: sqlite3.Connection) -> dict:
    scalar = lambda query: connection.execute(query).fetchone()[0]
    summary = {
        "generated_at": utc_now(),
        "category_total": scalar("SELECT COUNT(*) FROM categories"),
        "category_completed": scalar("SELECT COUNT(*) FROM categories WHERE completed=1"),
        "category_pages_collected": scalar("SELECT COUNT(*) FROM pages"),
        "products_discovered": scalar("SELECT COUNT(*) FROM products"),
        "products_detail_complete": scalar("SELECT COUNT(*) FROM products WHERE detail_done=1"),
        "products_size_complete": scalar("SELECT COUNT(*) FROM products WHERE size_done=1"),
        "products_with_measurements": scalar("SELECT COUNT(DISTINCT product_id) FROM sizes"),
        "measurement_rows": scalar("SELECT COUNT(*) FROM sizes"),
        "products_options_complete": scalar("SELECT COUNT(*) FROM products WHERE options_done=1"),
        "products_unavailable": scalar("SELECT COUNT(*) FROM products WHERE unavailable=1"),
        "products_pending": scalar("SELECT COUNT(*) FROM products WHERE unavailable=0 AND (detail_done=0 OR size_done=0 OR options_done=0)"),
        "failures": scalar("SELECT COUNT(*) FROM failures"),
    }
    summary["index_complete"] = (
        summary["category_completed"] == summary["category_total"]
        and scalar("SELECT COUNT(*) FROM failures WHERE phase='discovery'") == 0
    )
    summary["detail_collection_complete"] = summary["products_pending"] == 0
    summary["collection_complete"] = summary["index_complete"]
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--taxonomy", type=Path, default=DEFAULT_TAXONOMY)
    parser.add_argument("--phase", choices=("discover", "collect", "export"), default="discover")
    parser.add_argument("--refresh-discovery", action="store_true")
    parser.add_argument("--max-categories", type=int, default=0, help="Testing only: restrict initialized categories.")
    parser.add_argument("--max-pages", type=int, default=0, help="0 means unlimited.")
    parser.add_argument("--max-products", type=int, default=0, help="Maximum products to detail; required unless --product-id is used.")
    parser.add_argument("--product-id", action="append", default=[], help="Fetch detail for one product ID; repeatable.")
    parser.add_argument("--batch-size", type=int, default=500, help="Maximum detail jobs held in memory at once.")
    parser.add_argument("--delay-ms", type=int, default=350)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--retries", type=int, default=2)
    args = parser.parse_args()

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    lock_path = output / ".batch.lock"
    with lock_path.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("같은 무신사 전체 배치가 이미 실행 중입니다.")
        connection = connect(output / "state.sqlite3")
        try:
            codes = apparel_category_codes(args.taxonomy.resolve())
            if args.max_categories:
                codes = codes[:args.max_categories]
            initialize_categories(connection, codes, args.refresh_discovery)
            limiter = RateLimiter(args.delay_ms / 1000)
            if args.phase == "discover":
                discover(connection, limiter, args.retries, args.max_pages)
            if args.phase == "collect":
                collect_products(
                    connection, limiter, args.retries, args.workers,
                    args.max_products, args.product_id, args.batch_size,
                )
            summary = export_files(connection, output)
            print(json.dumps(summary, ensure_ascii=False, indent=2), flush=True)
        finally:
            connection.close()
    return 0 if summary["collection_complete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
