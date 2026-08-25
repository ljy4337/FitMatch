begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch:zara-measurement-subset-v2'));

-- Local migration candidate only. The official ZARA KR measurement help shown
-- on 2026-08-24 verifies three upper/outer bases:
--   chest: edge-to-edge at armhole height
--   back width: shoulder sleeve seam to opposite shoulder sleeve seam
--   sleeve length: shoulder sleeve seam to cuff
-- Front length starts at a shoulder seam rather than FitMatch's HPS endpoint,
-- and arm width has no typed canonical code, so both remain raw-only.
insert into fitmatch_taxonomy.policy_versions (
  code,schema_version,taxonomy_version,manifest_checksum,status,validated_at
) values (
  'zara-measurement-2026-08-24-v2',
  '2.2',
  'fitmatch-runtime-2026-08-24',
  '0251519fe5b9a0173f0a6689d00213fdf6c7d7877a173e2cb702b3025eff286d',
  'validated',
  now()
)
on conflict (code) do nothing;

insert into fitmatch_taxonomy.source_measurement_aliases (
  source_code,parser_code,raw_code,raw_label,normalized_raw_label,
  measurement_code,raw_representation,comparison_basis,
  conversion_multiplier,category_scopes,is_comparable,evidence,policy_version
) values
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-waist','zone-name-waist','zone-name-waist',
   'waist_width','waist_edge_to_edge','waist_edge_to_edge',
   1,array['bottoms'],true,
   'VERIFIED: ZARA KR measureGuideInfo; official modal says garment laid flat; waist is a direct cm width.',
   'zara-measurement-2026-08-24-v2'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-hips','zone-name-hips','zone-name-hips',
   'hip_width','hip_at_widest','hip_at_widest',
   1,array['bottoms','dresses'],true,
   'VERIFIED: ZARA KR measureGuideInfo; official modal says garment laid flat; hips is a direct cm width.',
   'zara-measurement-2026-08-24-v2'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-front-rise','zone-name-front-rise','zone-name-front-rise',
   'front_rise','front_crotch_to_waist','front_crotch_to_waist',
   1,array['bottoms'],true,
   'VERIFIED: ZARA KR measureGuideInfo official front-rise row; direct cm length. Back rise remains raw-only.',
   'zara-measurement-2026-08-24-v2'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-chest','zone-name-chest','zone-name-chest',
   'chest_width','chest_pit_to_pit','chest_pit_to_pit',
   1,array['tops','outerwear','dresses'],true,
   'VERIFIED: ZARA KR official help measures chest edge-to-edge at armhole height; direct cm width.',
   'zara-measurement-2026-08-24-v2'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-waist-full-body','zone-name-waist-full-body','zone-name-waist-full-body',
   'waist_width','waist_edge_to_edge','waist_edge_to_edge',
   1,array['dresses'],true,
   'VERIFIED: ZARA KR measureGuideInfo full-body waist row; direct cm width.',
   'zara-measurement-2026-08-24-v2'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-back-width','zone-name-back-width','zone-name-back-width',
   'shoulder_width','shoulder_seam_to_seam','shoulder_seam_to_seam',
   1,array['tops','outerwear'],true,
   'VERIFIED: ZARA KR official help measures between the two shoulder sleeve seams; direct cm width.',
   'zara-measurement-2026-08-24-v2'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-sleeve-length','zone-name-sleeve-length','zone-name-sleeve-length',
   'sleeve_length','sleeve_shoulder_seam_to_cuff','sleeve_shoulder_seam_to_cuff',
   1,array['tops','outerwear'],true,
   'VERIFIED: ZARA KR official help measures from shoulder sleeve seam to cuff; direct cm length.',
   'zara-measurement-2026-08-24-v2')
on conflict (source_code,raw_label,measurement_code,policy_version)
do nothing;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from fitmatch_taxonomy.source_measurement_aliases
  where source_code='zara'
    and policy_version='zara-measurement-2026-08-24-v2'
    and is_comparable;
  if v_count <> 7 then
    raise exception 'expected 7 verified ZARA aliases, found %',v_count;
  end if;
end $$;

commit;
