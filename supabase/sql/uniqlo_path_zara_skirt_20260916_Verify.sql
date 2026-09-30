-- READ ONLY postflight after authorized application; no app E2E claim.
BEGIN READ ONLY;
SELECT position('Exact compatibility for two verified UNIQLO breadcrumb renames' IN
 pg_get_functiondef('fitmatch_vnext.product_comparison_group(uuid)'::regprocedure))>0 AS compatibility_patch_present;
SELECT category,raw,fitmatch_vnext.resolve_measurement('zara','zara_kr_size_measure_guide_v1',raw,raw,NULL,category,17) result
FROM (VALUES ('skirts','zone-name-waist'),('skirts','zone-name-hips'),
 ('skirts','zone-name-front-length-lower'),('underwear','zone-name-waist'),
 ('homewear','zone-name-hips'),('tops','zone-name-sleeve-length'),
 ('outerwear','zone-name-sleeve-length'),('outerwear','zone-name-chest'),
 ('dresses','zone-name-hem-width'),('bottoms','zone-name-waist'),
 ('bottoms','zone-name-hips'),('dresses','zone-name-hips')) v(category,raw);
COMMIT;
