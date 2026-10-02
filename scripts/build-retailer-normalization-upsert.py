#!/usr/bin/env python3
"""Build a paste-ready, idempotent SQL snapshot from normalized CSVs."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def read_rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def json_literal(rows: list[dict], delimiter: str) -> str:
    value = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    if delimiter in value:
        raise ValueError("SQL dollar delimiter occurs in input")
    return f"{delimiter}{value}{delimiter}::jsonb"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    categories = read_rows(args.input / "categories.csv")
    fields = read_rows(args.input / "category_measurements.csv")
    if len(categories) != 161 or len(fields) != 703:
        raise ValueError(f"Unexpected input counts: categories={len(categories)}, fields={len(fields)}")
    category_keys = {(r["source"], r["category_id"], r["category_path"]) for r in categories}
    field_keys = {(r["source"], r["category_id"], r["category_path"], r["raw_code"], r["raw_label"], r["unit"])
                  for r in fields}
    if len(category_keys) != len(categories) or len(field_keys) != len(fields):
        raise ValueError("Duplicate normalized keys")
    if any(key[:3] not in category_keys for key in field_keys):
        raise ValueError("Measurement without a category")

    category_payload = json_literal(categories, "$fitmatch_categories$")
    field_payload = json_literal(fields, "$fitmatch_fields$")
    sql = f"""-- Prepared only. Run in the intended Supabase project after reviewing the CSV evidence.
-- Private observation snapshot: NO comparison-group or canonical-measurement activation.
-- Rerunnable for the same snapshot_id; does not delete earlier snapshots.
begin;

create table if not exists fitmatch_catalog.retailer_observed_categories (
  snapshot_id text not null,
  source_code text not null check (source_code in ('musinsa', 'uniqlo', 'zara')),
  source_category_id text not null,
  source_category_path text not null,
  observed_products integer not null check (observed_products > 0),
  observed_measurement_fields integer not null check (observed_measurement_fields >= 0),
  category_evidence text not null,
  measurement_evidence text not null,
  updated_at timestamptz not null default now(),
  primary key (snapshot_id, source_code, source_category_id, source_category_path)
);

create table if not exists fitmatch_catalog.retailer_observed_category_measurements (
  snapshot_id text not null,
  source_code text not null,
  source_category_id text not null,
  source_category_path text not null,
  raw_code text not null,
  raw_label text not null,
  unit_code text not null,
  observed_products integer not null check (observed_products > 0),
  measurement_evidence text not null,
  updated_at timestamptz not null default now(),
  primary key (snapshot_id, source_code, source_category_id, source_category_path,
               raw_code, raw_label, unit_code),
  foreign key (snapshot_id, source_code, source_category_id, source_category_path)
    references fitmatch_catalog.retailer_observed_categories
      (snapshot_id, source_code, source_category_id, source_category_path)
);

alter table fitmatch_catalog.retailer_observed_categories enable row level security;
alter table fitmatch_catalog.retailer_observed_category_measurements enable row level security;
revoke all on fitmatch_catalog.retailer_observed_categories from public, anon, authenticated;
revoke all on fitmatch_catalog.retailer_observed_category_measurements from public, anon, authenticated;

insert into fitmatch_catalog.retailer_observed_categories
  (snapshot_id, source_code, source_category_id, source_category_path,
   observed_products, observed_measurement_fields, category_evidence, measurement_evidence)
select 'retained-20260917', source, category_id, category_path,
       observed_products::integer, measurement_fields::integer,
       category_source_capture, measurement_source_capture
from jsonb_to_recordset({category_payload}) as r(
  source text, category_id text, category_path text, observed_products text,
  measurement_fields text, category_source_capture text, measurement_source_capture text
)
on conflict (snapshot_id, source_code, source_category_id, source_category_path)
do update set observed_products = excluded.observed_products,
              observed_measurement_fields = excluded.observed_measurement_fields,
              category_evidence = excluded.category_evidence,
              measurement_evidence = excluded.measurement_evidence,
              updated_at = now();

insert into fitmatch_catalog.retailer_observed_category_measurements
  (snapshot_id, source_code, source_category_id, source_category_path,
   raw_code, raw_label, unit_code, observed_products, measurement_evidence)
select 'retained-20260917', source, category_id, category_path,
       raw_code, raw_label, unit, observed_products::integer, measurement_source_capture
from jsonb_to_recordset({field_payload}) as r(
  source text, category_id text, category_path text, raw_code text, raw_label text,
  unit text, observed_products text, measurement_source_capture text
)
on conflict (snapshot_id, source_code, source_category_id, source_category_path,
             raw_code, raw_label, unit_code)
do update set observed_products = excluded.observed_products,
              measurement_evidence = excluded.measurement_evidence,
              updated_at = now();

do $validate_snapshot$
begin
  if (select count(*) from fitmatch_catalog.retailer_observed_categories
      where snapshot_id = 'retained-20260917') <> 161
     or (select count(*) from fitmatch_catalog.retailer_observed_category_measurements
         where snapshot_id = 'retained-20260917') <> 703 then
    raise exception 'Retailer observation snapshot row count mismatch';
  end if;
end
$validate_snapshot$;
commit;

-- Read-only postflight (run separately):
select source_code, count(*) as categories,
       sum(observed_measurement_fields) as category_measurement_pairs
from fitmatch_catalog.retailer_observed_categories
where snapshot_id = 'retained-20260917'
group by source_code order by source_code;

-- Recovery, only if this snapshot must be removed (run separately):
-- begin;
-- delete from fitmatch_catalog.retailer_observed_category_measurements
-- where snapshot_id = 'retained-20260917';
-- delete from fitmatch_catalog.retailer_observed_categories
-- where snapshot_id = 'retained-20260917';
-- commit;
"""
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")
    print(f"PREPARED categories={len(categories)} fields={len(fields)} bytes={len(sql.encode('utf-8'))}")


if __name__ == "__main__":
    main()
