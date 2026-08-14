#!/usr/bin/env python3
"""Generate idempotent DB expectation updates from Swift production results."""
import argparse, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULE_SET = "app-hardcoded-parity-2026-08-06-v1"

def literal(value):
    return "'" + value.replace("'", "''") + "'"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--chunk-index", type=int, required=True)
    parser.add_argument("--chunk-count", type=int, required=True)
    parser.add_argument("--expected-count", type=int, default=1280)
    args = parser.parse_args()
    path = args.results if args.results.is_absolute() else ROOT / args.results
    rows = json.loads(path.read_text(encoding="utf-8"))
    unique_count = len({(x["source"], x["product_id"]) for x in rows})
    if len(rows) != args.expected_count or unique_count != args.expected_count:
        raise SystemExit(
            f"Swift result must contain {args.expected_count:,} unique products "
            f"(rows={len(rows):,}, unique={unique_count:,})"
        )
    selected = rows[args.chunk_index::args.chunk_count]
    payload = literal(json.dumps(selected, ensure_ascii=False, separators=(",", ":")))
    sql = f"""begin;
set local statement_timeout='120s';
with payload as (select value item from jsonb_array_elements({payload}::jsonb))
update fitmatch_staging.runtime_classification_regression_cases c
set expected_category_code=item->>'category_code',
    expected_detail_code=item->>'detail_code',
    expected_comparable=(item->>'category_code') <> 'other'
      and (item->>'detail_code') <> 'other',
    evidence=c.evidence || jsonb_build_object('swift_production_path',true)
from payload
where c.rule_set_code={literal(RULE_SET)}
  and c.source_code=item->>'source'
  and c.external_product_id=item->>'product_id';
commit;
"""
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.write_text(sql, encoding="utf-8")
    print(json.dumps({"rows": len(selected), "output": str(output)}))

if __name__ == "__main__": main()
