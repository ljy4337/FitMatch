-- Target: hnkplvyegonlhumlejst (owner-authorized development database).
-- Repair missing MUSINSA actual_size bottoms total-length mapping; preserve raw/user data.
DO $repair$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.fitmatch_measurements WHERE measurement_code='outseam' AND canonical_basis_code='waist_to_outer_hem' AND is_active)
 THEN RAISE EXCEPTION 'Active outseam prerequisite missing'; END IF;
 IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurements WHERE source_measurement_code='musinsa.outseam.waist_to_outer_hem'
 AND (source_code <> 'musinsa' OR measurement_basis_code <> 'waist_to_outer_hem' OR native_unit_code <> 'cm' OR representation_code <> 'LENGTH' OR measurement_kind <> 'GARMENT_ACTUAL' OR NOT is_active OR NOT is_comparable))
 THEN RAISE EXCEPTION 'Conflicting source definition'; END IF;
 INSERT INTO fitmatch_vnext.source_measurements
 (source_measurement_code,source_code,display_name,measurement_kind,native_unit_code,measurement_basis_code,representation_code,is_comparable,is_active,description)
 VALUES ('musinsa.outseam.waist_to_outer_hem','musinsa','총장','GARMENT_ACTUAL','cm','waist_to_outer_hem','LENGTH',true,true,'Official actual_size bottoms total length; 5328103 type 6 and existing MeasurementCode bottom-type contract.')
 ON CONFLICT (source_measurement_code) DO NOTHING;
 IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_mappings WHERE source_measurement_code='musinsa.outseam.waist_to_outer_hem'
 AND (fitmatch_measurement_code <> 'outseam' OR scale_factor <> 1 OR offset_value <> 0 OR NOT is_active OR NOT is_verified))
 THEN RAISE EXCEPTION 'Conflicting canonical mapping'; END IF;
 INSERT INTO fitmatch_vnext.source_measurement_mappings
 (source_measurement_code,fitmatch_measurement_code,scale_factor,offset_value,is_verified,is_active)
 SELECT 'musinsa.outseam.waist_to_outer_hem','outseam',1,0,true,true
 WHERE NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_mappings WHERE source_measurement_code='musinsa.outseam.waist_to_outer_hem');
 IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases
 WHERE source_code='musinsa' AND parser_code='actual_size' AND normalized_label='총장' AND fitmatch_category_code='bottoms'
 AND (source_measurement_code <> 'musinsa.outseam.waist_to_outer_hem' OR NOT is_active OR NOT is_verified OR garment_type_code IS NOT NULL OR raw_code IS NOT NULL))
 THEN RAISE EXCEPTION 'Conflicting bottoms total-length alias'; END IF;
 INSERT INTO fitmatch_vnext.source_measurement_aliases
 (source_code,parser_code,raw_code,raw_label,normalized_label,fitmatch_category_code,garment_type_code,source_measurement_code,priority,is_verified,is_active)
 SELECT 'musinsa','actual_size',NULL,'총장','총장','bottoms',NULL,'musinsa.outseam.waist_to_outer_hem',10,true,true
 WHERE NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases WHERE source_code='musinsa' AND parser_code='actual_size' AND normalized_label='총장' AND fitmatch_category_code='bottoms');
END
$repair$;
