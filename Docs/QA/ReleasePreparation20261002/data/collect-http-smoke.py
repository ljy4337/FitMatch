#!/usr/bin/env python3
"""Three explicit official measurement GETs; no discovery, retries, auth, DB or Swift execution."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import time
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
ALLOWED_HOSTS = {'goods-detail.musinsa.com', 'www.uniqlo.com', 'www.zara.com'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def shape(provider, body):
    try:
        obj = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return {'json_object': False, 'garment_table_present': False, 'reason': 'non_json_response'}
    if not isinstance(obj, dict):
        return {'json_object': False, 'garment_table_present': False, 'reason': 'root_not_object'}
    if provider == 'musinsa':
        data = obj.get('data') or {}
        sizes = data.get('sizes', []) if isinstance(data, dict) else []
        rows = sum(len(s.get('items', [])) for s in sizes if isinstance(s, dict))
    elif provider == 'uniqlo':
        results = obj.get('result') or []
        sizes = [s for p in results if isinstance(p, dict) for s in p.get('sizeChart', [])]
        rows = sum(len(s.get('sizeParts', [])) for s in sizes if isinstance(s, dict))
    else:
        guide = obj.get('measureGuideInfo') or {}
        sizes = guide.get('sizes', []) if isinstance(guide, dict) else []
        rows = sum(len(s.get('measures', [])) for s in sizes if isinstance(s, dict))
    return {'json_object': True, 'garment_table_present': bool(sizes and rows), 'size_rows': len(sizes), 'measurement_columns_across_sizes': rows, 'note': 'Structural receipt check only; numeric/semantic validity and Swift parsing not asserted.'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collect', action='store_true', help='Perform exactly three read-only GET requests; default is dry run.')
    parser.add_argument('--run-id', help='New directory name (letters, digits, hyphen only); never overwrites.')
    args = parser.parse_args()
    plan_path = HERE / 'http-smoke-plan.json'
    plan = json.loads(plan_path.read_text())
    requests = plan['requests']
    if len(requests) != 3 or {r['provider'] for r in requests} != {'musinsa', 'uniqlo', 'zara'}:
        raise SystemExit('Refusing a plan other than exactly one request per provider.')
    for request in requests:
        parsed = urlparse(request['request_url'])
        if parsed.scheme != 'https' or parsed.hostname not in ALLOWED_HOSTS or parsed.username or parsed.password:
            raise SystemExit('Refusing an unsupported request destination.')
    if not args.collect:
        print(json.dumps({'status': 'DRY_RUN', 'requests': len(requests), 'network_requests': 0, 'plan_sha256': digest(plan_path)}))
        return 0
    run_id = args.run_id or datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    if not run_id or any(not (c.isalnum() or c == '-') for c in run_id):
        raise SystemExit('Invalid run ID.')
    output = HERE / 'http-smoke' / run_id
    output.mkdir(parents=True, exist_ok=False)
    results = []
    for request in requests:
        started = datetime.now(timezone.utc).isoformat()
        stamp = time.monotonic()
        body_path = output / (request['provider'] + '.body')
        command = ['curl', '--silent', '--show-error', '--max-time', '20', '--connect-timeout', '8', '--proto', '=https', '--max-filesize', '5242880', '--user-agent', 'Mozilla/5.0 FitMatchReleasePreparation/1.0', '--header', 'Accept: application/json', '--referer', request['source_product_url'], '--output', str(body_path), '--write-out', '%{http_code}\n%{content_type}\n%{url_effective}', request['request_url']]
        # Redirects are deliberately recorded as responses. No challenge bypass or hidden follow-up.
        result = subprocess.run(command, capture_output=True, text=True, timeout=25)
        metadata = result.stdout.split('\n', 2)
        body = body_path.read_bytes() if body_path.exists() else b''
        record = dict(request, started_at=started, finished_at=datetime.now(timezone.utc).isoformat(), elapsed_seconds=round(time.monotonic()-stamp, 3), curl_exit=result.returncode, http_status=int(metadata[0]) if metadata and metadata[0].isdigit() else 0, content_type=metadata[1] if len(metadata)>1 else None, final_url=metadata[2] if len(metadata)>2 else None, error=result.stderr.strip() or None, response_path=str(body_path.relative_to(HERE)) if body_path.exists() else None, response_sha256=hashlib.sha256(body).hexdigest() if body_path.exists() else None, response_bytes=len(body), shape=shape(request['provider'], body), swift_parser_status='NOT RUN', page_identity_verification='NOT RUN', db_write=False)
        record['receipt_status'] = 'PASS' if result.returncode==0 and 200 <= record['http_status'] < 300 and record['shape']['garment_table_present'] else ('BLOCKED' if result.returncode else 'FAIL')
        results.append(record)
        print(json.dumps({k:record[k] for k in ['provider','curl_exit','http_status','receipt_status','response_bytes']},ensure_ascii=False), flush=True)
    summary = {'schema_version':'fitmatch-read-only-http-smoke-v1','plan_sha256':digest(plan_path),'network_requests':3,'scope':'Official measurement endpoint receipts only, not Swift parser or authenticated journey. No retries, DB calls or app execution.','results':results}
    (output / 'results.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    return 0 if all(r['receipt_status']=='PASS' for r in results) else 2

if __name__ == '__main__':
    raise SystemExit(main())
