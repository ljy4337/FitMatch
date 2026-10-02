#!/usr/bin/env python3
"""Collect live Musinsa actual-size responses that FitMatch can parse directly."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_URL = "https://www.musinsa.com/category/001005/goods?gf=A"
PRODUCT_URL_TEMPLATE = "https://www.musinsa.com/products/{product_id}"
ACTUAL_SIZE_URL_TEMPLATE = (
    "https://goods-detail.musinsa.com/api2/goods/{product_id}/actual-size"
)
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/140.0.0.0 Safari/537.36 FitMatchResearch/1.0"
)
STATUS_MARKER = b"\n__FITMATCH_HTTP_STATUS__:"
URL_MARKER = b"\n__FITMATCH_FINAL_URL__:"


class FetchError(Exception):
    def __init__(self, message: str, status: int = 0):
        super().__init__(message)
        self.status = status


def request_bytes(url: str, referer: str, timeout: float) -> tuple[bytes, int, str]:
    completed = subprocess.run(
        [
            "curl",
            "-L",
            "--silent",
            "--show-error",
            "--max-time",
            str(timeout),
            "--user-agent",
            USER_AGENT,
            "--referer",
            referer,
            "--header",
            "Accept: application/json,text/html;q=0.9,*/*;q=0.8",
            "--write-out",
            "\n__FITMATCH_HTTP_STATUS__:%{http_code}\n__FITMATCH_FINAL_URL__:%{url_effective}",
            url,
        ],
        check=False,
        capture_output=True,
    )
    if completed.returncode != 0:
        message = completed.stderr.decode("utf-8", errors="replace").strip()
        raise FetchError(message or f"curl exited with {completed.returncode}")
    try:
        body, trailer = completed.stdout.rsplit(STATUS_MARKER, 1)
        status_bytes, final_url_bytes = trailer.split(URL_MARKER, 1)
        status = int(status_bytes.decode("ascii"))
        final_url = final_url_bytes.decode("utf-8", errors="replace")
    except (ValueError, UnicodeDecodeError) as error:
        raise FetchError(f"curl response metadata parse failed: {error}") from error
    if not 200 <= status < 300:
        raise FetchError(f"HTTP {status}", status=status)
    return body, status, final_url


def discover_product_ids(source_url: str, timeout: float) -> list[str]:
    body, _, _ = request_bytes(source_url, "https://www.musinsa.com/", timeout)
    text = body.decode("utf-8", errors="replace")
    found = re.findall(r'"goodsNo"\s*:\s*"?(\d+)"?', text)
    found.extend(re.findall(r"/products/(\d+)", text))

    unique: list[str] = []
    seen: set[str] = set()
    for product_id in found:
        if product_id not in seen:
            seen.add(product_id)
            unique.append(product_id)
    return unique


def count_measurements(payload: dict[str, Any]) -> tuple[int, int]:
    data = payload.get("data")
    if not isinstance(data, dict):
        return 0, 0
    sizes = data.get("sizes")
    if not isinstance(sizes, list):
        return 0, 0
    measurement_count = 0
    for size in sizes:
        if not isinstance(size, dict):
            continue
        items = size.get("items")
        if isinstance(items, list):
            measurement_count += sum(isinstance(item, dict) for item in items)
    return len(sizes), measurement_count


def fetch_actual_size(
    product_id: str,
    timeout: float,
    retries: int,
) -> tuple[bytes, dict[str, Any], int, str]:
    api_url = ACTUAL_SIZE_URL_TEMPLATE.format(product_id=product_id)
    product_url = PRODUCT_URL_TEMPLATE.format(product_id=product_id)
    last_error: Optional[Exception] = None

    for attempt in range(retries + 1):
        try:
            body, status, final_url = request_bytes(api_url, product_url, timeout)
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise ValueError("response root is not a JSON object")
            return body, payload, status, final_url
        except (OSError, ValueError, json.JSONDecodeError, FetchError) as error:
            last_error = error
            if attempt < retries:
                time.sleep(0.75 * (attempt + 1))

    assert last_error is not None
    raise last_error


def relative_or_absolute(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect live Musinsa actual-size JSON files for FitMatch parser input."
    )
    parser.add_argument("--source-url", default=DEFAULT_SOURCE_URL)
    parser.add_argument("--count", type=int, default=10)
    parser.add_argument("--max-candidates", type=int, default=50)
    parser.add_argument("--delay-ms", type=int, default=500)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("Docs/QA/MusinsaParserInputs"),
    )
    args = parser.parse_args()

    if args.count <= 0:
        parser.error("--count must be greater than zero")
    if args.max_candidates < args.count:
        parser.error("--max-candidates must be at least --count")
    if args.delay_ms < 0 or args.retries < 0 or args.timeout <= 0:
        parser.error("delay and retries must be non-negative; timeout must be positive")

    output_dir = args.output_dir if args.output_dir.is_absolute() else ROOT / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        product_ids = discover_product_ids(args.source_url, args.timeout)
    except (OSError, FetchError) as error:
        print(f"상품 목록 요청 실패: {error}", file=sys.stderr)
        return 2

    candidates = product_ids[: args.max_candidates]
    if not candidates:
        print("공식 페이지에서 상품 코드를 찾지 못했습니다.", file=sys.stderr)
        return 2

    successes: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []

    for product_id in candidates:
        if len(successes) >= args.count:
            break
        api_url = ACTUAL_SIZE_URL_TEMPLATE.format(product_id=product_id)
        product_url = PRODUCT_URL_TEMPLATE.format(product_id=product_id)
        try:
            body, payload, status, final_url = fetch_actual_size(
                product_id,
                timeout=args.timeout,
                retries=args.retries,
            )
            size_count, measurement_count = count_measurements(payload)
            if size_count == 0 or measurement_count == 0:
                failures.append(
                    {
                        "product_id": product_id,
                        "product_url": product_url,
                        "api_url": api_url,
                        "status": status,
                        "reason": "actual-size 응답에 사용할 수 있는 실측표가 없음",
                    }
                )
            else:
                output_path = output_dir / f"{product_id}.json"
                output_path.write_bytes(body)
                data = payload.get("data") or {}
                successes.append(
                    {
                        "product_id": product_id,
                        "product_url": product_url,
                        "api_url": final_url,
                        "status": status,
                        "file": relative_or_absolute(output_path),
                        "bytes": len(body),
                        "sha256": hashlib.sha256(body).hexdigest(),
                        "type_name": data.get("typeName"),
                        "type_number": data.get("typeNumber"),
                        "size_count": size_count,
                        "measurement_count": measurement_count,
                    }
                )
                print(f"[{len(successes)}/{args.count}] {product_id} 저장 완료")
        except (OSError, ValueError, json.JSONDecodeError, FetchError) as error:
            status = error.status if isinstance(error, FetchError) else 0
            failures.append(
                {
                    "product_id": product_id,
                    "product_url": product_url,
                    "api_url": api_url,
                    "status": status,
                    "reason": str(error),
                }
            )
        time.sleep(args.delay_ms / 1000)

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_url": args.source_url,
        "requested_count": args.count,
        "discovered_product_count": len(product_ids),
        "checked_candidate_count": len(successes) + len(failures),
        "successful_count": len(successes),
        "parser_contract": "MusinsaActualSizeResponse raw JSON",
        "products": successes,
        "failures": failures,
    }
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"manifest: {relative_or_absolute(manifest_path)}")
    if len(successes) != args.count:
        print(
            f"요청한 {args.count}개 중 {len(successes)}개만 수집했습니다.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
