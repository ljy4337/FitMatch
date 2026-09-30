-- Target: hnkplvyegonlhumlejst (owner-designated development database).
-- Authorized 2026-09-16: verified measurement dictionary reinforcement.
-- Evidence: master 08 rows 7/17; 05 rows 196/400; existing Swift ZARA mapping.
-- Additive data-only repair: 2 source rows, 2 mappings, 4 exact-context aliases.
-- No canonical definitions, policies, raw product/Closet/history data or auth changes.
DO $repair$
DECLARE r record; decision jsonb;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('sleeve_length','sleeve_shoulder_seam_to_cuff','LENGTH'),
    ('hem_width','hem_edge_to_edge','FLAT_WIDTH'),
    ('chest_width','chest_pit_to_pit','FLAT_WIDTH')
  ) v(code,basis,representation) LOOP
    IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.fitmatch_measurements f
      WHERE f.measurement_code=r.code AND f.canonical_basis_code=r.basis
      AND f.representation_code=r.representation AND f.canonical_unit_code='cm' AND f.is_active)
    THEN RAISE EXCEPTION 'Canonical prerequisite mismatch: %',r.code; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurements s
    JOIN fitmatch_vnext.source_measurement_mappings m USING(source_measurement_code)
    WHERE s.source_measurement_code='zara.chest_width.chest_pit_to_pit'
      AND s.source_code='zara' AND s.measurement_basis_code='chest_pit_to_pit'
      AND s.native_unit_code='cm' AND s.representation_code='FLAT_WIDTH'
      AND s.is_active AND s.is_comparable AND m.is_verified AND m.is_active
      AND m.fitmatch_measurement_code='chest_width' AND m.scale_factor=1 AND m.offset_value=0)
  THEN RAISE EXCEPTION 'Existing ZARA chest mapping mismatch'; END IF;

  FOR r IN SELECT * FROM (VALUES
    ('zara.sleeve_length.sleeve_shoulder_seam_to_cuff','소매길이','sleeve_shoulder_seam_to_cuff','LENGTH','sleeve_length',
     'Master 20260916 08 row7 / 05 row196: shoulder sleeve seam to cuff; cm garment guide. Existing Swift verified zone semantics; no center-back/raglan equivalence.'),
    ('zara.hem_width.hem_edge_to_edge','밑단단면','hem_edge_to_edge','FLAT_WIDTH','hem_width',
     'Master 20260916 08 row17 / 05 row400: garment bottom edge-to-edge, dress style01608613 commercial545465654. Alias limited to dresses; age is not category.')
  ) v(source_key,label,basis,representation,canonical,evidence) LOOP
    IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurements s WHERE s.source_measurement_code=r.source_key
      AND (s.source_code IS DISTINCT FROM 'zara' OR s.measurement_kind IS DISTINCT FROM 'GARMENT_ACTUAL'
        OR s.native_unit_code IS DISTINCT FROM 'cm' OR s.measurement_basis_code IS DISTINCT FROM r.basis
        OR s.representation_code IS DISTINCT FROM r.representation OR NOT s.is_active OR NOT s.is_comparable))
    THEN RAISE EXCEPTION 'Conflicting source: %',r.source_key; END IF;
    INSERT INTO fitmatch_vnext.source_measurements
      (source_measurement_code,source_code,display_name,measurement_kind,native_unit_code,
       measurement_basis_code,representation_code,is_comparable,is_active,description)
    SELECT r.source_key,'zara',r.label,'GARMENT_ACTUAL','cm',r.basis,r.representation,true,true,r.evidence
    WHERE NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurements WHERE source_measurement_code=r.source_key);
    IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_mappings m WHERE m.source_measurement_code=r.source_key
      AND (m.fitmatch_measurement_code IS DISTINCT FROM r.canonical OR m.scale_factor IS DISTINCT FROM 1::numeric
        OR m.offset_value IS DISTINCT FROM 0::numeric OR NOT m.is_active OR NOT m.is_verified))
    THEN RAISE EXCEPTION 'Conflicting mapping: %',r.source_key; END IF;
    INSERT INTO fitmatch_vnext.source_measurement_mappings
      (source_measurement_code,fitmatch_measurement_code,scale_factor,offset_value,is_verified,is_active)
    SELECT r.source_key,r.canonical,1,0,true,true
    WHERE NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_mappings WHERE source_measurement_code=r.source_key);
  END LOOP;

  FOR r IN SELECT * FROM (VALUES
    ('zone-name-sleeve-length','tops','zara.sleeve_length.sleeve_shoulder_seam_to_cuff','sleeve_length'),
    ('zone-name-sleeve-length','outerwear','zara.sleeve_length.sleeve_shoulder_seam_to_cuff','sleeve_length'),
    ('zone-name-hem-width','dresses','zara.hem_width.hem_edge_to_edge','hem_width'),
    ('zone-name-chest','outerwear','zara.chest_width.chest_pit_to_pit','chest_width')
  ) v(raw,category,source_key,canonical) LOOP
    IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a
      WHERE a.source_code='zara' AND a.parser_code='zara_kr_size_measure_guide_v1' AND a.raw_code=r.raw
      AND (a.fitmatch_category_code IS NULL OR a.fitmatch_category_code=r.category)
      AND (a.source_measurement_code IS DISTINCT FROM r.source_key OR NOT a.is_active OR NOT a.is_verified
        OR a.garment_type_code IS NOT NULL))
    THEN RAISE EXCEPTION 'Conflicting alias % / %',r.raw,r.category; END IF;
    INSERT INTO fitmatch_vnext.source_measurement_aliases
      (source_code,parser_code,raw_code,raw_label,normalized_label,fitmatch_category_code,
       garment_type_code,source_measurement_code,priority,is_verified,is_active)
    SELECT 'zara','zara_kr_size_measure_guide_v1',r.raw,r.raw,r.raw,r.category,NULL,r.source_key,30,true,true
    WHERE NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a
      WHERE a.source_code='zara' AND a.parser_code='zara_kr_size_measure_guide_v1'
      AND a.raw_code=r.raw AND a.fitmatch_category_code=r.category AND a.garment_type_code IS NULL);
    decision := fitmatch_vnext.resolve_measurement('zara','zara_kr_size_measure_guide_v1',r.raw,r.raw,NULL,r.category,17);
    IF decision->>'resolution_status' IS DISTINCT FROM 'RESOLVED'
      OR decision->>'fitmatch_measurement_code' IS DISTINCT FROM r.canonical
      OR (decision->>'canonical_value')::numeric IS DISTINCT FROM 17::numeric
    THEN RAISE EXCEPTION 'Resolver postcondition failed: % / %',r.raw,r.category; END IF;
  END LOOP;
END
$repair$;
