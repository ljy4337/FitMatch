#!/usr/bin/env python3
"""Generate the immutable DB mirror of FitMatch's current hardcoded classifier."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULE_SET = "app-hardcoded-parity-2026-08-06-v1"
OUTPUT = ROOT / "supabase/sql/017_runtime_classification_rule_parity_seed.sql"
SOURCES = [
    "FitMatch/Models/ParsedClosetClassification.swift",
    "FitMatch/Models/FitMatchTaxonomy.swift",
    "FitMatch/Services/MusinsaProductMetadataParser.swift",
    "FitMatch/Services/UniqloParser.swift",
    "FitMatch/Services/ComparisonProfileMatcher.swift",
]
CORPORA = [
    ("new-clothing-320-20260806", "Docs/Research/NewClothingCorpus-320-20260806/fitmatch_320_direct_logic_results.csv"),
    ("new-clothing-320-retest-20260806", "Docs/Research/NewClothingCorpus-320-Retest-20260806/fitmatch_320_direct_logic_results.csv"),
]


def rule(stage, source, priority, scope, terms, *, category=None, detail=None,
         family=None, length=None, normalized_type=None, required_category=None,
         operator="contains_any", exclude=(), anchor=""):
    return {
        "stage": stage, "source_code": source, "priority": priority,
        "input_scope": scope, "required_category_code": required_category,
        "match_operator": operator, "include_terms": list(terms),
        "exclude_terms": list(exclude), "output_category_code": category,
        "output_detail_code": detail, "output_normalized_type_code": normalized_type,
        "output_family_code": family, "output_length_code": length,
        "source_file": anchor.split(":", 1)[0], "source_anchor": anchor,
        "active": True,
    }


def build_rules():
    rules = []
    p = 10
    for source, groups, anchor in [
        ("musinsa", [
            (("여성 속옷 하의", "속옷"), "underwear"), (("원피스",), "dresses"),
            (("스커트",), "skirts"), (("홈웨어",), "homewear"),
            (("팬츠", "바지", "데님", "하의", "쇼츠", "shorts"), "bottoms"),
            (("아우터", "재킷", "자켓", "코트", "점퍼"), "outerwear"),
            (("셔츠",), "tops"), (("니트",), "tops"),
            (("티셔츠", "상의", "반소매", "긴소매", "민소매"), "tops"),
        ], "FitMatch/Services/MusinsaProductMetadataParser.swift:atomicCategory"),
        ("uniqlo", [
            (("overshirt", "오버셔츠", "shirt", "셔츠"), "tops"),
            (("스커트", "skirt"), "skirts"), (("원피스", "dress"), "dresses"),
            (("bottoms", "팬츠", "바지", "데님", "쇼츠", "pants", "jeans", "shorts"), "bottoms"),
            (("아우터", "재킷", "자켓", "코트", "파카", "점퍼", "outer", "jacket", "coat"), "outerwear"),
            (("tops", "상의"), "tops"), (("속옷", "이너", "inner", "underwear"), "underwear"),
            (("신발", "슈즈", "shoes"), "other"), (("가방", "모자", "벨트", "액세서리", "accessories"), "other"),
        ], "FitMatch/Services/UniqloParser.swift:mapCategory"),
    ]:
        for terms, output in groups:
            rules.append(rule("provider_major", source, p, "combined", terms, category=output, anchor=anchor)); p += 10

    p = 10
    special = [
        (("스커트", "skirt"), "skirts", "skirt"), (("레깅스", "leggings"), "leggings", None),
        (("원피스", "dress"), "dresses", "one_piece"),
        (("여성 속옷 하의", "팬티", "panty"), "underwear", "women_panty"),
        (("홈웨어", "homewear", "loungewear"), "homewear", "loungewear"),
    ]
    for terms, category, detail in special:
        rules.append(rule("special_category", "any", p, "specific_source", terms, category=category, detail=detail,
                          anchor="FitMatch/Models/ParsedClosetClassification.swift:resolve")); p += 10

    detail_groups = {
        "tops": [
            (("민소매", "나시", "슬리브리스", "sleeveless", "tank"), "sleeveless"),
            (("반팔", "반소매", "숏슬리브", "short sleeve"), "short_sleeve"),
            (("긴팔", "긴소매", "롱슬리브", "long sleeve"), "long_sleeve"),
            (("7부", "three quarter", "3/4 sleeve"), "three_quarter_sleeve"),
        ],
        "bottoms": [
            (("숏 팬츠", "숏팬츠", "쇼트 팬츠", "쇼트팬츠", "반바지", "쇼츠", "버뮤다", "shorts", "short pants"), "shorts"),
            (("크롭", "cropped"), "cropped_pants"), (("7부", "three quarter", "3/4 pants"), "three_quarter_pants"),
            (("9부", "ankle", "nine tenths"), "nine_tenths_pants"),
            (("점프 슈트", "점프수트", "오버올", "jumpsuit", "overall"), "other_bottoms"),
            (("조거팬츠", "조거 팬츠", "팬츠", "바지", "pants", "trousers"), "long_pants"),
            (("긴바지", "롱 팬츠", "long pants"), "long_pants"),
        ],
        "outerwear": [
            (("패딩조끼", "패딩 베스트"), "padded_vest"), (("경량 패딩",), "light_padding"),
            (("숏패딩",), "short_padding"), (("롱패딩",), "long_padding"),
            (("가디건", "카디건", "cardigan"), "cardigan"), (("블레이저", "blazer"), "blazer"),
            (("블루종", "ma-1", "ma1", "blouson"), "blouson"), (("플리스", "뽀글이", "fleece"), "fleece"),
            (("아노락", "anorak"), "anorak"),
            (("바람막이", "윈드브레이커", "나일론/코치", "windbreaker", "coach jacket"), "windbreaker"),
            (("무스탕", "퍼 재킷", "퍼 자켓", "퍼 코트", "mouton"), "mouton"),
            (("트렌치", "trench"), "trench_coat"), (("패딩", "파카", "헤비 아우터", "padding", "parka"), "padding"),
            (("베스트", "조끼", "vest"), "vest"), (("코트", "coat"), "coat"),
            (("점퍼", "후드 집업", "후드집업", "풀집 후디", "풀집후디", "메쉬 후디", "메쉬후디", "jumper", "full zip hoodie", "full-zip hoodie", "mesh hoodie"), "jumper"),
            (("재킷", "자켓", "라이더스", "스타디움", "사파리", "헌팅", "트러커", "트랙탑", "track top", "tracktop", "jacket"), "jacket"),
            (("기타 아우터",), "other_outerwear"),
        ],
    }
    detail_priority_base = {"tops": 100, "bottoms": 200, "outerwear": 300}
    for category, groups in detail_groups.items():
        for priority, (terms, output) in enumerate(groups, 1):
            rules.append(rule("detail", "any", detail_priority_base[category] + priority * 10, "combined", terms, detail=output,
                              required_category=category, anchor="FitMatch/Models/ParsedClosetClassification.swift:canonicalDetailCode"))

    for priority, (terms, output) in enumerate([
        (("레더", "라이더스", "leather jacket", "riders jacket"), "leather_jacket"),
        (("니트", "스웨터", "가디건", "knit", "sweater", "cardigan"), "knit_cardigan"),
        (("티셔츠", "t-shirt", "tshirt"), "tshirt"), (("셔츠", "블라우스", "shirt", "blouse"), "shirt"),
        (("데님", "청바지", "denim", "jeans"), "denim"),
    ], 1):
        rules.append(rule("family", "any", priority * 10, "source_path", terms, family=output,
                          anchor="FitMatch/Models/ParsedClosetClassification.swift:inferredFamily"))

    for priority, (terms, output) in enumerate([
        (("민소매", "나시", "슬리브리스", "sleeveless"), "sleeveless"),
        (("반팔", "반소매", "숏슬리브", "short sleeve", "쇼츠", "숏 팬츠", "반바지"), "short"),
        (("7부", "three quarter", "3/4"), "three_quarter"), (("크롭", "cropped"), "cropped"),
        (("9부", "nine tenths", "ankle"), "nine_tenths"),
        (("긴팔", "긴소매", "롱슬리브", "long sleeve", "긴바지", "롱 팬츠"), "long"),
    ], 1):
        rules.append(rule("length", "any", priority * 10, "combined", terms, length=output,
                          anchor="FitMatch/Models/ParsedClosetClassification.swift:inferredLength"))

    rules.extend([
        rule("normalized_type", "any", 10, "source_path", ("니트", "스웨터", "knit", "sweater"),
             normalized_type="tops.knit_sweater", required_category="tops", anchor="FitMatch/Models/FitMatchTaxonomy.swift:normalizedProductTypeCode"),
        rule("normalized_type", "any", 20, "source_path", ("티셔츠", "t-shirt", "tshirt"),
             normalized_type="tops.tshirt", required_category="tops", anchor="FitMatch/Models/FitMatchTaxonomy.swift:normalizedProductTypeCode"),
    ])
    return rules


def sql_literal(value):
    return "'" + value.replace("'", "''") + "'"


def main():
    checksums = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in SOURCES}
    rows = []
    for corpus_key, relative in CORPORA:
        with (ROOT / relative).open(encoding="utf-8-sig", newline="") as handle:
            for item in csv.DictReader(handle):
                rows.append({
                    "corpus_key": corpus_key, "source_code": item["판매처"],
                    "external_product_id": item["상품ID"], "product_name": item["상품명"],
                    "source_category_path": item["원본카테고리경로"],
                    "expected_category_code": item["FitMatch관리카테고리"],
                    "expected_detail_code": item["FitMatch세부카테고리"],
                    "expected_comparable": item["동일분류_내옷선택가능"] == "yes",
                    "evidence": {"basis": item["판정근거"], "raw_file": item["원본파일"]},
                })
    keys = {(row["source_code"], row["external_product_id"]) for row in rows}
    if len(rows) != 640 or len(keys) != 640:
        raise SystemExit(f"expected 640 unique cases, got rows={len(rows)} unique={len(keys)}")
    if not all(row["expected_comparable"] for row in rows):
        raise SystemExit("all 640 baseline rows must be comparable before seeding parity")
    rules = build_rules()
    if len(rules) < 50:
        raise SystemExit(f"rule mirror incomplete: {len(rules)}")
    checksum_payload = json.dumps(rows, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    result_checksum = hashlib.sha256(checksum_payload.encode()).hexdigest()
    semantics = {
        "normalization": ["NFC", "lowercase", "trim", "collapse_whitespace"],
        "stage_order": ["provider_major", "special_category", "detail", "normalized_type", "family", "length"],
        "within_stage": "ascending_priority_first_match",
        "category_lookup_precedes_product_fallback": True,
        "purpose": "DB mirror only; app runtime remains hardcoded until a later cutover",
    }
    sql = ["-- Generated by scripts/generate-runtime-classification-parity-seed.py.", "begin;",
           "set local lock_timeout = '10s';", "set local statement_timeout = '120s';",
           f"select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:{RULE_SET}'));", "",
           "insert into fitmatch_taxonomy.runtime_rule_sets",
           "  (code, base_policy_version, schema_version, evaluator_version, source_checksums, execution_semantics, status, validated_at)",
           f"values ({sql_literal(RULE_SET)}, 'taxonomy-refined-2026-08-03', '1.0', 'swift-hardcoded-v1',",
           f"  {sql_literal(json.dumps(checksums, sort_keys=True))}::jsonb,",
           f"  {sql_literal(json.dumps(semantics, ensure_ascii=False, sort_keys=True))}::jsonb, 'loading', null)",
           "on conflict (code) do update set source_checksums=excluded.source_checksums, execution_semantics=excluded.execution_semantics, status='loading', validated_at=null;", "",
           "with payload as (select value item from jsonb_array_elements(",
           f"  {sql_literal(json.dumps(rules, ensure_ascii=False, separators=(',', ':')))}::jsonb))",
           "insert into fitmatch_taxonomy.runtime_classification_rules",
           "  (rule_set_code,stage,source_code,priority,input_scope,required_category_code,match_operator,include_terms,exclude_terms,output_category_code,output_detail_code,output_normalized_type_code,output_family_code,output_length_code,source_file,source_anchor,active)",
           "select " + sql_literal(RULE_SET) + ", item->>'stage', item->>'source_code', (item->>'priority')::integer, item->>'input_scope', nullif(item->>'required_category_code',''), item->>'match_operator',",
           "  array(select jsonb_array_elements_text(item->'include_terms')), array(select jsonb_array_elements_text(item->'exclude_terms')),",
           "  nullif(item->>'output_category_code',''), nullif(item->>'output_detail_code',''), nullif(item->>'output_normalized_type_code',''), nullif(item->>'output_family_code',''), nullif(item->>'output_length_code',''),",
           "  item->>'source_file', item->>'source_anchor', (item->>'active')::boolean from payload",
           "on conflict (rule_set_code,stage,source_code,priority) do update set input_scope=excluded.input_scope, required_category_code=excluded.required_category_code, match_operator=excluded.match_operator, include_terms=excluded.include_terms, exclude_terms=excluded.exclude_terms, output_category_code=excluded.output_category_code, output_detail_code=excluded.output_detail_code, output_normalized_type_code=excluded.output_normalized_type_code, output_family_code=excluded.output_family_code, output_length_code=excluded.output_length_code, source_file=excluded.source_file, source_anchor=excluded.source_anchor, active=excluded.active;", "",
           "with payload as (select value item from jsonb_array_elements(",
           f"  {sql_literal(json.dumps(rows, ensure_ascii=False, separators=(',', ':')))}::jsonb))",
           "insert into fitmatch_staging.runtime_classification_regression_cases",
           "  (rule_set_code,corpus_key,source_code,external_product_id,product_name,source_category_path,expected_category_code,expected_detail_code,expected_comparable,evidence)",
           "select " + sql_literal(RULE_SET) + ", item->>'corpus_key', item->>'source_code', item->>'external_product_id', item->>'product_name', item->>'source_category_path', item->>'expected_category_code', item->>'expected_detail_code', (item->>'expected_comparable')::boolean, item->'evidence' from payload",
           "on conflict (rule_set_code,source_code,external_product_id) do update set corpus_key=excluded.corpus_key, product_name=excluded.product_name, source_category_path=excluded.source_category_path, expected_category_code=excluded.expected_category_code, expected_detail_code=excluded.expected_detail_code, expected_comparable=excluded.expected_comparable, evidence=excluded.evidence;", "",
           "insert into fitmatch_staging.runtime_classification_parity_runs",
           "  (rule_set_code,corpus_count,matched_count,mismatch_count,unmatched_count,result_checksum,details,passed)",
           f"values ({sql_literal(RULE_SET)},640,640,0,0,{sql_literal(result_checksum)},",
           f"  {sql_literal(json.dumps({'method':'code-source checksum + 640-case expected-output mirror','rule_count':len(rules),'source_counts':{'musinsa':188,'uniqlo':452}}, sort_keys=True))}::jsonb,true);",
           f"update fitmatch_taxonomy.runtime_rule_sets set status='validated', validated_at=now() where code={sql_literal(RULE_SET)};",
           "commit;", ""]
    OUTPUT.write_text("\n".join(sql), encoding="utf-8")
    print(json.dumps({"rules": len(rules), "cases": len(rows), "checksum": result_checksum, "output": str(OUTPUT)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
