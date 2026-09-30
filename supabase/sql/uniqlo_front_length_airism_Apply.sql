-- Authorized repair: owner-confirmed DEV hnkplvyegonlhumlejst, 2026-09-17.
-- Dictionary DML only. No user/Closet/history/raw changes, no metric/policy expansion.
-- Current iOS observation parser_code is size_chart.
BEGIN;
DO $repair$
DECLARE r record; category text; decision jsonb; affected integer;
BEGIN
  -- Existing semantic definitions must match; never invent or merge measuring methods.
  FOR r IN SELECT * FROM (VALUES
    ('uniqlo.front_length.front_neck_to_hem','front_length','front_neck_to_hem'),
    ('uniqlo.shoulder_width.shoulder_seam_to_seam','shoulder_width','shoulder_seam_to_seam'),
    ('uniqlo.sleeve_length.sleeve_shoulder_seam_to_cuff','sleeve_length','sleeve_shoulder_seam_to_cuff'),
    ('uniqlo.sleeve_length.sleeve_center_back_to_cuff','sleeve_center_back_length','sleeve_center_back_to_cuff')
  ) v(source_key,canonical,basis) LOOP
    IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurements s
      JOIN fitmatch_vnext.source_measurement_mappings m USING(source_measurement_code)
      JOIN fitmatch_vnext.fitmatch_measurements f ON f.measurement_code=m.fitmatch_measurement_code
      WHERE s.source_measurement_code=r.source_key AND s.source_code='uniqlo'
        AND s.measurement_basis_code=r.basis AND s.native_unit_code='cm'
        AND s.is_active AND s.is_comparable AND m.is_active AND m.is_verified
        AND m.fitmatch_measurement_code=r.canonical AND m.scale_factor=1 AND m.offset_value=0
        AND f.is_active AND f.canonical_basis_code=r.basis AND f.canonical_unit_code='cm')
    THEN RAISE EXCEPTION 'Semantic prerequisite mismatch: %',r.source_key; END IF;
  END LOOP;

  FOREACH category IN ARRAY ARRAY['dresses','underwear','homewear'] LOOP
    IF (SELECT count(*) FROM fitmatch_vnext.source_measurement_aliases
      WHERE source_code='uniqlo' AND parser_code='size_chart' AND raw_code='knit-body-length-front'
        AND fitmatch_category_code=category AND garment_type_code IS NULL
        AND is_active AND is_verified AND source_measurement_code IN
          ('uniqlo.back_length.back_neck_to_hem','uniqlo.front_length.front_neck_to_hem')) <> 1
    THEN RAISE EXCEPTION 'Front alias drift: %',category; END IF;
    UPDATE fitmatch_vnext.source_measurement_aliases
      SET source_measurement_code='uniqlo.front_length.front_neck_to_hem'
      WHERE source_code='uniqlo' AND parser_code='size_chart' AND raw_code='knit-body-length-front'
        AND fitmatch_category_code=category AND garment_type_code IS NULL
        AND is_active AND is_verified
        AND source_measurement_code='uniqlo.back_length.back_neck_to_hem';

    FOR r IN SELECT * FROM (VALUES
      ('shoulder-width','어깨너비(솔기에서 솔기까지)','uniqlo.shoulder_width.shoulder_seam_to_seam','shoulder_width'),
      ('sleeve-length','소매길이','uniqlo.sleeve_length.sleeve_shoulder_seam_to_cuff','sleeve_length'),
      ('sleeve-length-cb','등 중심부터 소매까지 길이','uniqlo.sleeve_length.sleeve_center_back_to_cuff','sleeve_center_back_length')
    ) v(raw,label,source_key,canonical) LOOP
      IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a
        WHERE a.source_code='uniqlo' AND a.parser_code='size_chart' AND a.raw_code=r.raw
          AND (a.fitmatch_category_code=category OR a.fitmatch_category_code IS NULL)
          AND a.is_active AND a.is_verified AND a.source_measurement_code<>r.source_key)
      THEN RAISE EXCEPTION 'Conflicting alias % / %',r.raw,category; END IF;
      INSERT INTO fitmatch_vnext.source_measurement_aliases
        (source_code,parser_code,raw_code,raw_label,normalized_label,fitmatch_category_code,
         garment_type_code,source_measurement_code,priority,is_verified,is_active)
      SELECT 'uniqlo','size_chart',r.raw,r.label,fitmatch_vnext.normalize_measurement_label(r.label),
        category,NULL,r.source_key,30,true,true
      WHERE NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a
        WHERE a.source_code='uniqlo' AND a.parser_code='size_chart' AND a.raw_code=r.raw
          AND a.fitmatch_category_code=category AND a.garment_type_code IS NULL
          AND a.source_measurement_code=r.source_key AND a.is_active AND a.is_verified);
      decision := fitmatch_vnext.resolve_measurement('uniqlo','size_chart',r.raw,r.label,NULL,category,65);
      IF decision->>'resolution_status' IS DISTINCT FROM 'RESOLVED'
        OR decision->>'fitmatch_measurement_code' IS DISTINCT FROM r.canonical
        OR (decision->>'canonical_value')::numeric IS DISTINCT FROM 65::numeric
      THEN RAISE EXCEPTION 'Alias postcondition: % / %',r.raw,category; END IF;
    END LOOP;
    decision := fitmatch_vnext.resolve_measurement('uniqlo','size_chart','knit-body-length-front','앞기장',NULL,category,65);
    IF decision->>'fitmatch_measurement_code' IS DISTINCT FROM 'front_length'
    THEN RAISE EXCEPTION 'Front length postcondition: %',category; END IF;
  END LOOP;

  -- Owner policy: MEN AIRism upper garments use A. Exact known category keys only.
  -- Seamless briefs (58510), all other underwear bottoms and WOMEN/KIDS remain unchanged.
  FOR r IN SELECT * FROM (VALUES
    ('uniqlo:57893:57969:58059:58499',ARRAY['MEN','스포츠 유틸리티 웨어','이너웨어','에어리즘']),
    ('uniqlo:57893:57970:58061:58505',ARRAY['MEN','이너웨어','에어리즘','에어리즘']),
    ('uniqlo:57893:57970:58061:58506',ARRAY['MEN','이너웨어','에어리즘','코튼']),
    ('uniqlo:57893:81620:82089:82144',ARRAY['MEN','에어리즘','이너웨어 상의','크루넥'])
  ) v(key,path) LOOP
    IF (SELECT count(*) FROM fitmatch_catalog.source_category_comparison_groups
      WHERE policy_version='retailer-comparison-groups-v3-seven-20260911'
        AND source_code='uniqlo' AND source_category_key=r.key) <> 1
    THEN RAISE EXCEPTION 'Category identity drift: %',r.key; END IF;
    UPDATE fitmatch_catalog.source_category_comparison_groups
      SET group_code='A',mapping_basis='Owner policy 2026-09-17: MEN AIRism upper garments -> A; exact retailer category, not product-name inference.'
      WHERE policy_version='retailer-comparison-groups-v3-seven-20260911'
        AND source_code='uniqlo' AND source_category_key=r.key AND category_path=r.path
        AND group_code IN ('F','A') AND disposition='COMPARABLE';
    GET DIAGNOSTICS affected=ROW_COUNT;
    IF affected<>1 THEN RAISE EXCEPTION 'Category contract drift: %',r.key; END IF;
  END LOOP;
END
$repair$;
COMMIT;
