-- Target: hnkplvyegonlhumlejst, explicitly identified by the owner as development use.
-- Add only the missing TOPS alias for an already verified ZARA chest-width definition.
-- No user rows, raw measurements, scoring policy, groups or authorization functions change.
DO $repair$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM fitmatch_vnext.source_measurements s
    JOIN fitmatch_vnext.source_measurement_mappings m USING (source_measurement_code)
    WHERE s.source_measurement_code='zara.chest_width.chest_pit_to_pit'
      AND s.measurement_basis_code='chest_pit_to_pit' AND s.is_active AND s.is_comparable
      AND m.fitmatch_measurement_code='chest_width' AND m.is_verified AND m.is_active
      AND m.scale_factor=1 AND m.offset_value=0
  ) THEN RAISE EXCEPTION 'Verified chest-width mapping prerequisite missing'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM fitmatch_vnext.source_measurement_aliases
    WHERE source_code='zara' AND parser_code='zara_kr_size_measure_guide_v1'
      AND raw_code='zone-name-chest' AND fitmatch_category_code='dresses'
      AND source_measurement_code='zara.chest_width.chest_pit_to_pit'
      AND is_active AND is_verified
  ) THEN RAISE EXCEPTION 'Existing reviewed ZARA alias missing'; END IF;
  IF EXISTS (
    SELECT 1 FROM fitmatch_vnext.source_measurement_aliases
    WHERE source_code='zara' AND parser_code='zara_kr_size_measure_guide_v1'
      AND raw_code='zone-name-chest' AND fitmatch_category_code='tops'
      AND (source_measurement_code IS DISTINCT FROM 'zara.chest_width.chest_pit_to_pit'
           OR NOT is_verified OR NOT is_active OR garment_type_code IS NOT NULL)
  ) THEN RAISE EXCEPTION 'Conflicting TOPS alias; review required'; END IF;
  INSERT INTO fitmatch_vnext.source_measurement_aliases
    (source_code,parser_code,raw_code,raw_label,normalized_label,fitmatch_category_code,
     garment_type_code,source_measurement_code,priority,is_verified,is_active)
  SELECT 'zara','zara_kr_size_measure_guide_v1','zone-name-chest','zone-name-chest',
    'zone-name-chest','tops',NULL,'zara.chest_width.chest_pit_to_pit',10,true,true
  WHERE NOT EXISTS (
    SELECT 1 FROM fitmatch_vnext.source_measurement_aliases
    WHERE source_code='zara' AND parser_code='zara_kr_size_measure_guide_v1'
      AND raw_code='zone-name-chest' AND fitmatch_category_code='tops'
  );
END
$repair$;
