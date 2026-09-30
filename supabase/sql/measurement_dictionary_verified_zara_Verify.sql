-- Read-only postflight. Expected 4 new-context RESOLVED decisions and 5 UNMAPPED.
WITH cases(raw,category,parser,expected) AS (VALUES
 ('zone-name-sleeve-length','tops','zara_kr_size_measure_guide_v1','sleeve_length'),
 ('zone-name-sleeve-length','outerwear','zara_kr_size_measure_guide_v1','sleeve_length'),
 ('zone-name-hem-width','dresses','zara_kr_size_measure_guide_v1','hem_width'),
 ('zone-name-chest','outerwear','zara_kr_size_measure_guide_v1','chest_width'),
 ('zone-name-sleeve-length','bottoms','zara_kr_size_measure_guide_v1',NULL),
 ('zone-name-sleeve-length','tops','unknown_parser',NULL),
 ('zone-name-hem-width','tops','zara_kr_size_measure_guide_v1',NULL),
 ('zone-name-hem-width','kids','zara_kr_size_measure_guide_v1',NULL),
 ('zone-name-new-unknown','tops','zara_kr_size_measure_guide_v1',NULL)
), decisions AS (
 SELECT *,fitmatch_vnext.resolve_measurement('zara',parser,raw,raw,NULL,category,17) d FROM cases
)
SELECT raw,category,parser,expected,d,
 CASE WHEN expected IS NULL THEN d->>'resolution_status'='UNMAPPED'
 ELSE d->>'resolution_status'='RESOLVED' AND d->>'fitmatch_measurement_code'=expected
 AND (d->>'canonical_value')::numeric=17 AND d->>'canonical_unit_code'='cm' END AS passed
FROM decisions;
