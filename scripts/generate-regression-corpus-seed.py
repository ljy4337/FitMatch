#!/usr/bin/env python3
"""Generate an idempotent SQL seed for one validated product corpus."""
import argparse, csv, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULE_SET = "app-hardcoded-parity-2026-08-06-v1"

def literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--corpus-key", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-count", type=int, required=True)
    parser.add_argument("--chunk-index", type=int, default=0)
    parser.add_argument("--chunk-count", type=int, default=1)
    args = parser.parse_args()
    corpus = args.corpus if args.corpus.is_absolute() else ROOT / args.corpus
    rows = []
    with (corpus / "fitmatch_320_direct_logic_results.csv").open(encoding="utf-8-sig", newline="") as handle:
        for item in csv.DictReader(handle):
            rows.append({
                "corpus_key": args.corpus_key, "source_code": item["판매처"],
                "external_product_id": item["상품ID"], "product_name": item["상품명"],
                "source_category_path": item["원본카테고리경로"],
                "expected_category_code": item["FitMatch관리카테고리"],
                "expected_detail_code": item["FitMatch세부카테고리"],
                "expected_comparable": item["동일분류_내옷선택가능"] == "yes",
                "evidence": {"basis": item["판정근거"], "raw_file": item["원본파일"]},
            })
    keys = {(r["source_code"], r["external_product_id"]) for r in rows}
    if len(rows) != args.expected_count or len(keys) != args.expected_count:
        raise SystemExit(f"expected {args.expected_count} unique rows, got {len(rows)}/{len(keys)}")
    if not 0 <= args.chunk_index < args.chunk_count:
        raise SystemExit("chunk-index must be within chunk-count")
    rows = rows[args.chunk_index::args.chunk_count]
    payload = literal(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
    sql = f"""begin;
set local lock_timeout='10s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:{args.corpus_key}'));
with payload as (select value item from jsonb_array_elements({payload}::jsonb))
insert into fitmatch_staging.runtime_classification_regression_cases
 (rule_set_code,corpus_key,source_code,external_product_id,product_name,source_category_path,
  expected_category_code,expected_detail_code,expected_comparable,evidence)
select {literal(RULE_SET)},item->>'corpus_key',item->>'source_code',item->>'external_product_id',
 item->>'product_name',item->>'source_category_path',item->>'expected_category_code',
 item->>'expected_detail_code',(item->>'expected_comparable')::boolean,item->'evidence'
from payload
on conflict (rule_set_code,source_code,external_product_id) do update set
 corpus_key=excluded.corpus_key,product_name=excluded.product_name,
 source_category_path=excluded.source_category_path,expected_category_code=excluded.expected_category_code,
 expected_detail_code=excluded.expected_detail_code,expected_comparable=excluded.expected_comparable,
 evidence=excluded.evidence;
commit;
"""
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.write_text(sql, encoding="utf-8")
    print(json.dumps({"cases": len(rows), "chunk": args.chunk_index, "output": str(output)}, ensure_ascii=False))

if __name__ == "__main__": main()
