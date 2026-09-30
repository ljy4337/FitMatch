-- Run only on isolated snapshot fixture database, from repository root.
-- Setup includes current deployed function definitions and dictionary/raw snapshots.
CREATE TEMP TABLE before_alias_results AS
SELECT id,fitmatch_vnext.resolve_measurement(source_code,parser_code,raw_code,raw_label,
  garment_type_code,fitmatch_category_code,65) result
FROM fitmatch_vnext.source_measurement_aliases;
CREATE TEMP TABLE before_categories AS SELECT * FROM fitmatch_catalog.source_category_comparison_groups;
DO $$ BEGIN
 IF (SELECT count(*) FROM raw_fixture WHERE fitmatch_vnext.resolve_measurement(
  'uniqlo',parser_code,raw_code,raw_label,NULL,'underwear',raw_value)->>'resolution_status'='RESOLVED')<>64
 THEN RAISE EXCEPTION 'Expected baseline 64 of 128 raw rows resolved'; END IF;
 IF EXISTS (SELECT 1 FROM unnest(ARRAY['dresses','underwear','homewear']) c
  WHERE fitmatch_vnext.resolve_measurement('uniqlo','size_chart','knit-body-length-front','앞기장',NULL,c,65)
    ->>'fitmatch_measurement_code'<>'back_length')
 THEN RAISE EXCEPTION 'Front bug baseline missing'; END IF;
END $$;
\i supabase/sql/uniqlo_front_length_airism_Apply.sql
DO $$ DECLARE c text; r record; actual jsonb; BEGIN
 FOREACH c IN ARRAY ARRAY['tops','outerwear','dresses','underwear','homewear'] LOOP
  FOR r IN SELECT * FROM (VALUES
    ('knit-body-length-front','front_length'),('body-length-back','back_length'),
    ('body-width','chest_width'),('shoulder-width','shoulder_width'),
    ('sleeve-length','sleeve_length'),('sleeve-length-cb','sleeve_center_back_length')
  ) v(raw,canonical) LOOP
   actual := fitmatch_vnext.resolve_measurement('uniqlo','size_chart',r.raw,r.raw,NULL,c,65);
   IF actual->>'resolution_status' IS DISTINCT FROM 'RESOLVED'
     OR actual->>'fitmatch_measurement_code' IS DISTINCT FROM r.canonical
     OR (actual->>'canonical_value')::numeric IS DISTINCT FROM 65::numeric
   THEN RAISE EXCEPTION 'Wrong semantic/value: % % %',c,r.raw,actual; END IF;
  END LOOP;
 END LOOP;
 IF EXISTS (SELECT 1 FROM raw_fixture WHERE fitmatch_vnext.resolve_measurement(
   'uniqlo',parser_code,raw_code,raw_label,NULL,'underwear',raw_value)->>'resolution_status'<>'RESOLVED')
 THEN RAISE EXCEPTION 'Raw AIRism unresolved'; END IF;
 IF EXISTS (SELECT 1 FROM raw_fixture GROUP BY size_id HAVING count(*)<>4
   OR count(DISTINCT fitmatch_vnext.resolve_measurement('uniqlo',parser_code,raw_code,raw_label,NULL,'underwear',raw_value)->>'fitmatch_measurement_code')<>4)
 THEN RAISE EXCEPTION 'Expected four distinct measurements per size'; END IF;
 IF EXISTS (SELECT 1 FROM fitmatch_vnext.products
   WHERE fitmatch_vnext.product_comparison_group(id)->>'group_code' IS DISTINCT FROM 'A')
 THEN RAISE EXCEPTION 'AIRism group not A'; END IF;
 IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a
   JOIN before_alias_results b USING(id)
   WHERE NOT (a.source_code='uniqlo' AND a.parser_code='size_chart'
     AND a.raw_code='knit-body-length-front' AND a.fitmatch_category_code IN ('dresses','underwear','homewear'))
   AND fitmatch_vnext.resolve_measurement(a.source_code,a.parser_code,a.raw_code,a.raw_label,
      a.garment_type_code,a.fitmatch_category_code,65) IS DISTINCT FROM b.result)
 THEN RAISE EXCEPTION 'Unrelated alias behavior changed'; END IF;
 IF EXISTS (SELECT 1 FROM before_categories b
  JOIN fitmatch_catalog.source_category_comparison_groups a USING(policy_version,source_code,source_category_key)
  WHERE b.source_category_key NOT IN ('uniqlo:57893:57969:58059:58499','uniqlo:57893:57970:58061:58505',
    'uniqlo:57893:57970:58061:58506','uniqlo:57893:81620:82089:82144') AND to_jsonb(a)<>to_jsonb(b))
 THEN RAISE EXCEPTION 'Unrelated category changed'; END IF;
 IF fitmatch_vnext.resolve_measurement('uniqlo','size_chart','unknown-new-code','새 항목',NULL,'underwear',65)->>'resolution_status'<>'UNMAPPED'
 THEN RAISE EXCEPTION 'Unknown metric fabricated'; END IF;
 IF (SELECT count(*) FROM fitmatch_vnext.source_measurement_aliases)<>236
 THEN RAISE EXCEPTION 'Unexpected alias count'; END IF;
END $$;
-- Idempotency: a second application must not add rows or alter results.
\i supabase/sql/uniqlo_front_length_airism_Apply.sql
DO $$ BEGIN
 IF (SELECT count(*) FROM fitmatch_vnext.source_measurement_aliases)<>236
 THEN RAISE EXCEPTION 'Not idempotent'; END IF;
END $$;
SELECT 'PASS: 30 semantic cases; AIRism 32 sizes/128 values; 224 unrelated alias inputs; 526 unchanged categories; idempotency' result;
