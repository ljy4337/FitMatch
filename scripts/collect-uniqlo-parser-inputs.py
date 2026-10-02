#!/usr/bin/env python3
"""Collect live UNIQLO size-chart responses that FitMatch can parse directly."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_URL = "https://www.uniqlo.com/kr/ko/men/tops/t-shirts"
SIZE_CHART_ENDPOINT = "https://www.uniqlo.com/kr/api/commerce/v5/ko/products/size-charts"
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
            "Accept: application/json",
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


def run_applescript(script: str) -> str:
    try:
        completed = subprocess.run(
            ["osascript"],
            input=script.encode("utf-8"),
            check=False,
            capture_output=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(
            "Safari 제어가 15초 안에 응답하지 않았습니다. "
            "macOS 설정 > 개인정보 보호 및 보안 > 자동화에서 터미널의 Safari 제어를 허용해 주세요."
        ) from error
    if completed.returncode != 0:
        message = completed.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(message or "Safari AppleScript failed")
    return completed.stdout.decode("utf-8", errors="replace").strip()


def apple_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def open_safari_window(url: str) -> int:
    output = run_applescript(
        f"""
        tell application "Safari"
            activate
            make new document with properties {{URL:{apple_string(url)}}}
            return id of front window
        end tell
        """
    )
    return int(output)


def set_safari_url(window_id: int, url: str) -> None:
    run_applescript(
        f"""
        tell application "Safari"
            set URL of current tab of window id {window_id} to {apple_string(url)}
        end tell
        """
    )


def safari_javascript(window_id: int, javascript: str) -> str:
    return run_applescript(
        f"""
        tell application "Safari"
            return do JavaScript {apple_string(javascript)} in current tab of window id {window_id}
        end tell
        """
    )


def discover_product_urls(source_url: str, count: int, timeout: float) -> tuple[list[str], int]:
    source_window_id = open_safari_window(source_url)
    deadline = time.monotonic() + timeout
    last_urls: list[str] = []
    javascript = """
    JSON.stringify(Array.from(document.querySelectorAll('a[href*="/products/"]'))
      .map(function(anchor) { return anchor.href; })
      .filter(function(url, index, values) { return values.indexOf(url) === index; }))
    """.strip()

    while time.monotonic() < deadline:
        try:
            raw = safari_javascript(source_window_id, javascript)
            parsed = json.loads(raw) if raw else []
            last_urls = [value for value in parsed if isinstance(value, str)]
            if len(unique_products(last_urls)) >= count:
                break
            safari_javascript(
                source_window_id,
                "window.scrollBy(0, Math.max(window.innerHeight * 2, 1200)); 'ok';",
            )
        except (RuntimeError, json.JSONDecodeError) as error:
            if "JavaScript from Apple Events" in str(error):
                raise RuntimeError(
                    "Safari 설정 > 개발자용에서 'Apple 이벤트의 JavaScript 허용'을 켜 주세요."
                ) from error
        time.sleep(1.0)
    return last_urls, source_window_id


def product_request(url: str) -> Optional[dict[str, str]]:
    parsed = urllib.parse.urlparse(url)
    match = re.search(r"/products/(E\d{6})(?:-\d{3})?", parsed.path, re.IGNORECASE)
    if not match:
        return None
    product_id = match.group(1).upper()
    query = urllib.parse.parse_qs(parsed.query)
    raw_color = (query.get("colorDisplayCode") or [""])[0].strip()
    color_code = raw_color.zfill(3) if raw_color.isdigit() else ""
    preferred_id = f"{product_id}-{color_code}" if color_code else f"{product_id}-000"
    return {
        "product_id": product_id,
        "product_url": url,
        "color_code": color_code,
        "preferred_id": preferred_id,
        "generic_id": f"{product_id}-000",
    }


def unique_products(urls: list[str]) -> list[dict[str, str]]:
    products: list[dict[str, str]] = []
    seen: set[str] = set()
    for url in urls:
        request = product_request(url)
        if request is None or request["product_id"] in seen:
            continue
        seen.add(request["product_id"])
        products.append(request)
    return products


def size_chart_url(product_id_with_color: str) -> str:
    query = urllib.parse.urlencode(
        {
            "productIdsWithColorCode": product_id_with_color,
            "includeBodyMeasurements": "true",
            "simpleSizeChart": "true",
            "httpFailure": "true",
        }
    )
    return f"{SIZE_CHART_ENDPOINT}?{query}"


def response_counts(payload: dict[str, Any]) -> tuple[int, int]:
    results = payload.get("result")
    if not isinstance(results, list):
        return 0, 0
    sizes = 0
    measurements = 0
    for result in results:
        if not isinstance(result, dict):
            continue
        chart = result.get("sizeChart")
        if not isinstance(chart, list):
            continue
        sizes += len(chart)
        for size in chart:
            if isinstance(size, dict) and isinstance(size.get("sizeParts"), list):
                measurements += sum(isinstance(item, dict) for item in size["sizeParts"])
    return sizes, measurements


def fetch_variant(
    product_id_with_color: str,
    product_url: str,
    timeout: float,
    retries: int,
) -> dict[str, Any]:
    api_url = size_chart_url(product_id_with_color)
    last_error: Optional[Exception] = None
    for attempt in range(retries + 1):
        try:
            body, status, final_url = request_bytes(api_url, product_url, timeout)
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise ValueError("response root is not a JSON object")
            size_count, measurement_count = response_counts(payload)
            return {
                "requested_id": product_id_with_color,
                "api_url": final_url,
                "status": status,
                "body": body,
                "payload": payload,
                "size_count": size_count,
                "measurement_count": measurement_count,
            }
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
        description="Collect live UNIQLO size-chart JSON files for FitMatch parser input."
    )
    parser.add_argument("--source-url", default=DEFAULT_SOURCE_URL)
    parser.add_argument("--product-url", action="append", default=[])
    parser.add_argument("--count", type=int, default=10)
    parser.add_argument("--max-candidates", type=int, default=50)
    parser.add_argument("--delay-ms", type=int, default=500)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--no-api-window", action="store_true")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("Docs/QA/UniqloParserInputs"),
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
    source_window_id: Optional[int] = None

    try:
        if args.product_url:
            discovered_urls = args.product_url
        else:
            discovered_urls, source_window_id = discover_product_urls(
                args.source_url,
                args.count,
                args.timeout,
            )
    except (RuntimeError, OSError) as error:
        print(f"Safari 상품 링크 수집 실패: {error}", file=sys.stderr)
        return 2

    candidates = unique_products(discovered_urls)[: args.max_candidates]
    if not candidates:
        print("유니클로 상품 링크에서 상품 코드를 찾지 못했습니다.", file=sys.stderr)
        return 2

    api_window_id: Optional[int] = None
    if not args.no_api_window:
        try:
            api_window_id = open_safari_window(size_chart_url(candidates[0]["preferred_id"]))
        except RuntimeError as error:
            print(f"Safari API 창 열기 실패: {error}", file=sys.stderr)
            return 2

    successes: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    for candidate in candidates:
        if len(successes) >= args.count:
            break
        attempts: list[dict[str, Any]] = []
        requested_ids = [candidate["preferred_id"]]
        if candidate["generic_id"] not in requested_ids:
            requested_ids.append(candidate["generic_id"])
        try:
            for requested_id in requested_ids:
                result = fetch_variant(
                    requested_id,
                    candidate["product_url"],
                    timeout=args.timeout,
                    retries=args.retries,
                )
                attempts.append(result)
            selected = max(
                attempts,
                key=lambda item: (item["size_count"], item["measurement_count"]),
            )
            if selected["size_count"] == 0 or selected["measurement_count"] == 0:
                raise ValueError("size-chart 응답에 사용할 수 있는 실측표가 없음")
            if api_window_id is not None:
                set_safari_url(api_window_id, selected["api_url"])
            output_path = output_dir / f"{candidate['product_id']}.json"
            output_path.write_bytes(selected["body"])
            successes.append(
                {
                    **candidate,
                    "selected_request_id": selected["requested_id"],
                    "api_url": selected["api_url"],
                    "status": selected["status"],
                    "file": relative_or_absolute(output_path),
                    "bytes": len(selected["body"]),
                    "sha256": hashlib.sha256(selected["body"]).hexdigest(),
                    "size_count": selected["size_count"],
                    "measurement_count": selected["measurement_count"],
                    "attempted_variants": [
                        {
                            "requested_id": item["requested_id"],
                            "status": item["status"],
                            "size_count": item["size_count"],
                            "measurement_count": item["measurement_count"],
                        }
                        for item in attempts
                    ],
                }
            )
            print(f"[{len(successes)}/{args.count}] {candidate['product_id']} 저장 완료")
        except (OSError, RuntimeError, ValueError, json.JSONDecodeError, FetchError) as error:
            status = error.status if isinstance(error, FetchError) else 0
            failures.append(
                {
                    **candidate,
                    "status": status,
                    "reason": str(error),
                }
            )
        time.sleep(args.delay_ms / 1000)

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_url": args.source_url,
        "source_window_id": source_window_id,
        "api_window_id": api_window_id,
        "requested_count": args.count,
        "discovered_url_count": len(discovered_urls),
        "checked_candidate_count": len(successes) + len(failures),
        "successful_count": len(successes),
        "parser_contract": "UniqloSizeChartResponse raw JSON",
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
