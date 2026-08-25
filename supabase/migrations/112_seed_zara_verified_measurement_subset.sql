begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch:zara-measurement-subset-v1'));

insert into fitmatch_taxonomy.policy_versions (
  code,schema_version,taxonomy_version,manifest_checksum,status,validated_at
) values (
  'zara-measurement-2026-08-21-v1',
  '2.2',
  'fitmatch-runtime-2026-08-21',
  '27d0d67459c4a365e620967b2e8e37a1b7ea62540c141e08a638929b1b322e83',
  'validated',
  now()
)
on conflict (code) do update set
  schema_version=excluded.schema_version,
  taxonomy_version=excluded.taxonomy_version,
  manifest_checksum=excluded.manifest_checksum,
  status=excluded.status,
  validated_at=excluded.validated_at;

-- The ZARA KR product-size modal identifies measureGuideInfo as garment
-- measurements taken with the item laid flat. Activate only the subset whose
-- current FitMatch comparison basis is unambiguous and whose category policy
-- has enough verified fields to remain fail-closed.
insert into fitmatch_taxonomy.source_measurement_aliases (
  source_code,parser_code,raw_code,raw_label,normalized_raw_label,
  measurement_code,raw_representation,comparison_basis,
  conversion_multiplier,category_scopes,is_comparable,evidence,policy_version
) values
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-waist','zone-name-waist','zone-name-waist',
   'waist_width','waist_edge_to_edge','waist_edge_to_edge',
   1,array['bottoms'],true,
   'VERIFIED: ZARA KR measureGuideInfo; official modal says garment laid flat; waist row observed as direct cm width. No circumference conversion.',
   'zara-measurement-2026-08-21-v1'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-hips','zone-name-hips','zone-name-hips',
   'hip_width','hip_at_widest','hip_at_widest',
   1,array['bottoms','dresses'],true,
   'VERIFIED: ZARA KR measureGuideInfo; official modal says garment laid flat; hips row observed as direct cm width. No circumference conversion.',
   'zara-measurement-2026-08-21-v1'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-front-rise','zone-name-front-rise','zone-name-front-rise',
   'front_rise','front_crotch_to_waist','front_crotch_to_waist',
   1,array['bottoms'],true,
   'VERIFIED: ZARA KR measureGuideInfo official front-rise row; direct cm length. Back rise remains raw-only.',
   'zara-measurement-2026-08-21-v1'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-chest','zone-name-chest','zone-name-chest',
   'chest_width','chest_pit_to_pit','chest_pit_to_pit',
   1,array['dresses'],true,
   'VERIFIED SUBSET: ZARA KR laid-flat garment chest row; activated only for dresses where chest, waist and hip jointly satisfy comparison policy. Upper-garment chest remains raw-only until a second basis is verified.',
   'zara-measurement-2026-08-21-v1'),
  ('zara','zara_kr_size_measure_guide_v1',
   'zone-name-waist-full-body','zone-name-waist-full-body','zone-name-waist-full-body',
   'waist_width','waist_edge_to_edge','waist_edge_to_edge',
   1,array['dresses'],true,
   'VERIFIED: ZARA KR measureGuideInfo full-body waist row; official modal says garment laid flat; direct cm width.',
   'zara-measurement-2026-08-21-v1')
on conflict (source_code,raw_label,measurement_code,policy_version)
do update set
  parser_code=excluded.parser_code,
  raw_code=excluded.raw_code,
  normalized_raw_label=excluded.normalized_raw_label,
  raw_representation=excluded.raw_representation,
  comparison_basis=excluded.comparison_basis,
  conversion_multiplier=excluded.conversion_multiplier,
  category_scopes=excluded.category_scopes,
  is_comparable=excluded.is_comparable,
  evidence=excluded.evidence;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from fitmatch_taxonomy.source_measurement_aliases
  where source_code='zara'
    and policy_version='zara-measurement-2026-08-21-v1'
    and is_comparable;
  if v_count <> 5 then
    raise exception 'expected 5 verified ZARA aliases, found %',v_count;
  end if;
end $$;

commit;
