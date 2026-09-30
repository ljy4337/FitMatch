begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch:measurement-basis-completion-v1'));

-- Canonical identities are measurement-method identities. Similar display
-- names must not collapse different bases (shoulder, back, raglan, centre-back).
insert into fitmatch_vnext.fitmatch_measurements (
    measurement_code, display_name, canonical_unit_code, canonical_basis_code,
    representation_code, body_region_code, description, is_active
) values
    ('back_width', '등너비', 'cm', 'back_armhole_to_armhole', 'FLAT_WIDTH', 'BACK',
     '뒤 암홀 사이를 직선으로 잰 너비', true),
    ('front_length_shoulder_to_hem', '앞기장', 'cm', 'front_shoulder_to_hem', 'LENGTH', 'LENGTH',
     '앞쪽 어깨 기준점부터 앞 밑단까지 잰 길이', true),
    ('upper_arm_width', '위팔단면', 'cm', 'upper_arm_edge_to_edge', 'FLAT_WIDTH', 'SLEEVE',
     '위팔의 좌우를 직선으로 잰 단면', true),
    ('sleeve_opening_width', '소매부리단면', 'cm', 'cuff_opening_edge_to_edge', 'FLAT_WIDTH', 'SLEEVE',
     '소매 끝단의 좌우를 직선으로 잰 너비', true),
    ('sleeve_center_back_length', '화장(등중심)', 'cm', 'sleeve_center_back_to_cuff', 'LENGTH', 'SLEEVE',
     '등 중심부터 소매 끝까지 잰 길이', true),
    ('sleeve_raglan_length', '화장(래글런)', 'cm', 'sleeve_raglan_neck_to_cuff', 'LENGTH', 'SLEEVE',
     '래글런 목점부터 소매 끝까지 잰 길이', true),
    ('collar_height', '칼라높이', 'cm', 'collar_base_to_point', 'HEIGHT', 'NECK',
     '칼라 밑점부터 칼라 끝까지 잰 높이', true),
    ('gathered_body_width', '주름포함 몸판너비', 'cm', 'body_width_including_gather_and_tack', 'FLAT_WIDTH', 'CHEST',
     '주름 또는 턱을 포함한 몸판 너비이며 일반 가슴단면과 구분함', true),
    ('armhole_measurement_unspecified', '암홀', 'cm', 'armhole_method_unspecified', 'OTHER', 'SHOULDER',
     '원본 그림으로 직선·곡선·둘레가 확정되지 않은 암홀 측정값', true),
    ('back_panel_length', '뒤판길이', 'cm', 'back_panel_reference_to_hem', 'LENGTH', 'LENGTH',
     '뒤판 전용 기준점부터 밑단까지 잰 길이', true),
    ('lining_back_length', '안감뒷기장', 'cm', 'lining_back_neck_to_hem', 'LENGTH', 'LENGTH',
     '원피스 안감의 뒤 목점부터 안감 밑단까지 잰 길이', true),
    ('lining_body_width', '안감몸판너비', 'cm', 'lining_body_edge_to_edge', 'FLAT_WIDTH', 'CHEST',
     '원피스 안감 몸판의 좌우를 직선으로 잰 너비', true),
    ('petticoat_length', '페티코트길이', 'cm', 'petticoat_waist_to_hem', 'LENGTH', 'LENGTH',
     '페티코트 허리선부터 밑단까지 잰 길이', true),
    ('petticoat_waist_circumference', '페티코트허리둘레', 'cm', 'petticoat_garment_waist_circumference', 'CIRCUMFERENCE', 'WAIST',
     '페티코트의 허리 부분을 한 바퀴 잰 둘레', true),
    ('source_total_length', '원본전체길이', 'cm', 'source_defined_total_length', 'LENGTH', 'LENGTH',
     '상품 그룹만으로 시작 기준점을 확정할 수 없는 원본 전체길이', true)
on conflict (measurement_code) do update set
    display_name = excluded.display_name,
    canonical_unit_code = excluded.canonical_unit_code,
    canonical_basis_code = excluded.canonical_basis_code,
    representation_code = excluded.representation_code,
    body_region_code = excluded.body_region_code,
    description = excluded.description,
    is_active = excluded.is_active,
    updated_at = now();

insert into fitmatch_vnext.source_measurements (
    source_measurement_code, source_code, display_name, measurement_kind,
    native_unit_code, measurement_basis_code, representation_code,
    is_comparable, is_active, description
) values
    ('uniqlo.front_length.front_neck_to_hem','uniqlo','앞기장','GARMENT_ACTUAL','cm','front_neck_to_hem','LENGTH',true,true,'knit-body-length-front'),
    ('uniqlo.sleeve_length.sleeve_center_back_to_cuff','uniqlo','등 중심부터 소매까지 길이','GARMENT_ACTUAL','cm','sleeve_center_back_to_cuff','LENGTH',true,true,'sleeve-length-cb'),
    ('uniqlo.neck_circumference.garment_neck_circumference','uniqlo','목둘레','GARMENT_ACTUAL','cm','garment_neck_circumference','CIRCUMFERENCE',false,true,'neck-circumference; stored and displayed, excluded from score'),
    ('uniqlo.collar_height.collar_base_to_point','uniqlo','칼라높이','GARMENT_ACTUAL','cm','collar_base_to_point','HEIGHT',false,true,'collar-point; stored and displayed, excluded from score'),
    ('uniqlo.gathered_body_width.body_width_including_gather_and_tack','uniqlo','주름포함 몸판너비','GARMENT_ACTUAL','cm','body_width_including_gather_and_tack','FLAT_WIDTH',false,true,'Not equivalent to chest pit-to-pit'),
    ('uniqlo.outseam.waist_to_outer_hem','uniqlo','옆길이','GARMENT_ACTUAL','cm','waist_to_outer_hem','LENGTH',true,true,'side-length scoped to bottoms'),
    ('uniqlo.total_length.waist_to_skirt_hem','uniqlo','스커트길이','GARMENT_ACTUAL','cm','waist_to_skirt_hem','LENGTH',true,true,'side-length or skirt-length scoped to skirts'),
    ('uniqlo.total_length.source_defined_total_length','uniqlo','전체길이','GARMENT_ACTUAL','cm','source_defined_total_length','LENGTH',false,true,'total-length without a verified start point'),
    ('uniqlo.back_panel_length.back_panel_reference_to_hem','uniqlo','뒤판길이','GARMENT_ACTUAL','cm','back_panel_reference_to_hem','LENGTH',false,true,'body-length-back-back'),
    ('uniqlo.lining_back_length.lining_back_neck_to_hem','uniqlo','안감뒷기장','GARMENT_ACTUAL','cm','lining_back_neck_to_hem','LENGTH',false,true,'body-length-back-underdress'),
    ('uniqlo.lining_body_width.lining_body_edge_to_edge','uniqlo','안감몸판너비','GARMENT_ACTUAL','cm','lining_body_edge_to_edge','FLAT_WIDTH',false,true,'body-width-underdress'),
    ('uniqlo.petticoat_length.petticoat_waist_to_hem','uniqlo','페티코트길이','GARMENT_ACTUAL','cm','petticoat_waist_to_hem','LENGTH',false,true,'skirt-length-petticoat'),
    ('uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference','uniqlo','페티코트허리둘레','GARMENT_ACTUAL','cm','petticoat_garment_waist_circumference','CIRCUMFERENCE',false,true,'waist-product-size-petticoat'),
    ('musinsa.sleeve_opening_width.cuff_opening_edge_to_edge','musinsa','소매부리단면','GARMENT_ACTUAL','cm','cuff_opening_edge_to_edge','FLAT_WIDTH',false,true,'Distinct from sleeve length'),
    ('musinsa.armhole.armhole_method_unspecified','musinsa','암홀','GARMENT_ACTUAL','cm','armhole_method_unspecified','OTHER',false,true,'Stored but excluded from score until official diagram basis is verified'),
    ('musinsa.sleeve_length.sleeve_raglan_neck_to_cuff','musinsa','전체소매길이','GARMENT_ACTUAL','cm','sleeve_raglan_neck_to_cuff','LENGTH',true,true,'Raglan profile only'),
    ('zara.back_width.back_armhole_to_armhole','zara','등너비','GARMENT_ACTUAL','cm','back_armhole_to_armhole','FLAT_WIDTH',true,true,'zone-name-back-width; never shoulder width'),
    ('zara.front_length.front_shoulder_to_hem','zara','앞기장','GARMENT_ACTUAL','cm','front_shoulder_to_hem','LENGTH',true,true,'zone-name-front-length'),
    ('zara.upper_arm_width.upper_arm_edge_to_edge','zara','위팔단면','GARMENT_ACTUAL','cm','upper_arm_edge_to_edge','FLAT_WIDTH',true,true,'zone-name-arm-width'),
    ('zara.outseam.waist_to_outer_hem','zara','하의 앞길이','GARMENT_ACTUAL','cm','waist_to_outer_hem','LENGTH',true,true,'zone-name-front-length-lower scoped to bottoms'),
    ('zara.back_rise.back_crotch_to_waist','zara','뒷밑위','GARMENT_ACTUAL','cm','back_crotch_to_waist','LENGTH',true,true,'zone-name-back-rise')
on conflict (source_measurement_code) do update set
    display_name = excluded.display_name,
    measurement_kind = excluded.measurement_kind,
    native_unit_code = excluded.native_unit_code,
    measurement_basis_code = excluded.measurement_basis_code,
    representation_code = excluded.representation_code,
    is_comparable = excluded.is_comparable,
    is_active = excluded.is_active,
    description = excluded.description,
    updated_at = now();

-- Correct prior lossy mappings. Circumference remains circumference; distinct
-- sleeve methods remain distinct canonical identities.
insert into fitmatch_vnext.source_measurement_mappings (
    source_measurement_code, fitmatch_measurement_code, scale_factor,
    offset_value, is_verified, is_active
) values
    ('uniqlo.waist_circumference.garment_waist_circumference','waist_circumference',1,0,true,true),
    ('uniqlo.hip_circumference.garment_hip_circumference','hip_circumference',1,0,true,true),
    ('uniqlo.front_length.front_neck_to_hem','front_length',1,0,true,true),
    ('uniqlo.sleeve_length.sleeve_center_back_to_cuff','sleeve_center_back_length',1,0,true,true),
    ('uniqlo.neck_circumference.garment_neck_circumference','neck_circumference',1,0,true,true),
    ('uniqlo.collar_height.collar_base_to_point','collar_height',1,0,true,true),
    ('uniqlo.gathered_body_width.body_width_including_gather_and_tack','gathered_body_width',1,0,true,true),
    ('uniqlo.outseam.waist_to_outer_hem','outseam',1,0,true,true),
    ('uniqlo.total_length.waist_to_skirt_hem','total_length',1,0,true,true),
    ('uniqlo.total_length.source_defined_total_length','source_total_length',1,0,true,true),
    ('uniqlo.back_panel_length.back_panel_reference_to_hem','back_panel_length',1,0,true,true),
    ('uniqlo.lining_back_length.lining_back_neck_to_hem','lining_back_length',1,0,true,true),
    ('uniqlo.lining_body_width.lining_body_edge_to_edge','lining_body_width',1,0,true,true),
    ('uniqlo.petticoat_length.petticoat_waist_to_hem','petticoat_length',1,0,true,true),
    ('uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference','petticoat_waist_circumference',1,0,true,true),
    ('musinsa.sleeve_opening_width.cuff_opening_edge_to_edge','sleeve_opening_width',1,0,true,true),
    ('musinsa.armhole.armhole_method_unspecified','armhole_measurement_unspecified',1,0,true,true),
    ('musinsa.sleeve_length.sleeve_raglan_neck_to_cuff','sleeve_raglan_length',1,0,true,true),
    ('zara.back_width.back_armhole_to_armhole','back_width',1,0,true,true),
    ('zara.front_length.front_shoulder_to_hem','front_length_shoulder_to_hem',1,0,true,true),
    ('zara.upper_arm_width.upper_arm_edge_to_edge','upper_arm_width',1,0,true,true),
    ('zara.outseam.waist_to_outer_hem','outseam',1,0,true,true),
    ('zara.back_rise.back_crotch_to_waist','back_rise',1,0,true,true)
on conflict (source_measurement_code) do update set
    fitmatch_measurement_code = excluded.fitmatch_measurement_code,
    scale_factor = excluded.scale_factor,
    offset_value = excluded.offset_value,
    is_verified = excluded.is_verified,
    is_active = excluded.is_active,
    updated_at = now();

create temporary table measurement_alias_seed (
    source_code text, parser_code text, raw_code text, raw_label text,
    normalized_label text, fitmatch_category_code text,
    source_measurement_code text, priority smallint
) on commit drop;

insert into measurement_alias_seed values
    ('uniqlo','size_chart','knit-body-length-front','앞기장','앞기장','tops','uniqlo.front_length.front_neck_to_hem',30),
    ('uniqlo','size_chart','knit-body-length-front','앞기장','앞기장','outerwear','uniqlo.front_length.front_neck_to_hem',30),
    ('uniqlo','size_chart','sleeve-length-cb','등 중심부터 소매까지 길이','등 중심부터 소매까지 길이','tops','uniqlo.sleeve_length.sleeve_center_back_to_cuff',30),
    ('uniqlo','size_chart','sleeve-length-cb','등 중심부터 소매까지 길이','등 중심부터 소매까지 길이','outerwear','uniqlo.sleeve_length.sleeve_center_back_to_cuff',30),
    ('uniqlo','size_chart','neck-circumference','목둘레','목둘레','tops','uniqlo.neck_circumference.garment_neck_circumference',30),
    ('uniqlo','size_chart','neck-circumference','목둘레','목둘레','outerwear','uniqlo.neck_circumference.garment_neck_circumference',30),
    ('uniqlo','size_chart','collar-point','깃 높이','깃 높이','tops','uniqlo.collar_height.collar_base_to_point',30),
    ('uniqlo','size_chart','body-width-gather-and-tack','몸 너비(주름 및 박음질 포함)','몸 너비(주름 및 박음질 포함)','tops','uniqlo.gathered_body_width.body_width_including_gather_and_tack',30),
    ('uniqlo','size_chart','side-length','옆길이','옆길이','bottoms','uniqlo.outseam.waist_to_outer_hem',30),
    ('uniqlo','size_chart','side-length','옆길이','옆길이','skirts','uniqlo.total_length.waist_to_skirt_hem',30),
    ('uniqlo','size_chart','total-length','전체 길이','전체 길이',null,'uniqlo.total_length.source_defined_total_length',20),
    ('uniqlo','size_chart','body-length-back-back','전체 길이 (후면)','전체 길이 (후면)',null,'uniqlo.back_panel_length.back_panel_reference_to_hem',20),
    ('uniqlo','size_chart','body-length-back-underdress','전체 길이 [언더드레스]','전체 길이 [언더드레스]','dresses','uniqlo.lining_back_length.lining_back_neck_to_hem',30),
    ('uniqlo','size_chart','body-width-underdress','가슴너비 [언더드레스]','가슴너비 [언더드레스]','dresses','uniqlo.lining_body_width.lining_body_edge_to_edge',30),
    ('uniqlo','size_chart','skirt-length-petticoat','스커트 길이 [페티코트]','스커트 길이 [페티코트]','skirts','uniqlo.petticoat_length.petticoat_waist_to_hem',30),
    ('uniqlo','size_chart','waist-product-size-petticoat','허리 둘레 [페티코트]','허리 둘레 [페티코트]','skirts','uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference',30),
    ('musinsa','actual_size',null,'소매부리단면','소매부리단면','tops','musinsa.sleeve_opening_width.cuff_opening_edge_to_edge',30),
    ('musinsa','actual_size',null,'소매부리단면','소매부리단면','outerwear','musinsa.sleeve_opening_width.cuff_opening_edge_to_edge',30),
    ('musinsa','actual_size',null,'암홀','암홀','tops','musinsa.armhole.armhole_method_unspecified',30),
    ('musinsa','actual_size',null,'암홀','암홀','outerwear','musinsa.armhole.armhole_method_unspecified',30),
    ('musinsa','actual_size',null,'전체소매길이','전체소매길이','tops','musinsa.sleeve_length.sleeve_raglan_neck_to_cuff',30),
    ('musinsa','actual_size',null,'전체소매길이','전체소매길이','outerwear','musinsa.sleeve_length.sleeve_raglan_neck_to_cuff',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-back-width','zone-name-back-width','zone-name-back-width','tops','zara.back_width.back_armhole_to_armhole',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-back-width','zone-name-back-width','zone-name-back-width','outerwear','zara.back_width.back_armhole_to_armhole',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-front-length','zone-name-front-length','zone-name-front-length','tops','zara.front_length.front_shoulder_to_hem',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-front-length','zone-name-front-length','zone-name-front-length','outerwear','zara.front_length.front_shoulder_to_hem',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-front-length-full-body','zone-name-front-length-full-body','zone-name-front-length-full-body','dresses','zara.front_length.front_shoulder_to_hem',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-arm-width','zone-name-arm-width','zone-name-arm-width','tops','zara.upper_arm_width.upper_arm_edge_to_edge',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-arm-width','zone-name-arm-width','zone-name-arm-width','outerwear','zara.upper_arm_width.upper_arm_edge_to_edge',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-front-length-lower','zone-name-front-length-lower','zone-name-front-length-lower','bottoms','zara.outseam.waist_to_outer_hem',30),
    ('zara','zara_kr_size_measure_guide_v1','zone-name-back-rise','zone-name-back-rise','zone-name-back-rise','bottoms','zara.back_rise.back_crotch_to_waist',30);

-- Repair already-ingested observations as well as future parser output.
insert into measurement_alias_seed
select source_code, 'legacy_unmapped', raw_code, raw_label, normalized_label,
       fitmatch_category_code, source_measurement_code, priority
from measurement_alias_seed
where source_code in ('uniqlo','musinsa','zara');

insert into measurement_alias_seed
select source_code, 'official_size_chart', raw_code, raw_label, normalized_label,
       fitmatch_category_code, source_measurement_code, priority
from measurement_alias_seed
where source_code = 'uniqlo' and parser_code = 'size_chart';

insert into measurement_alias_seed
select source_code, 'ingestion_unmapped', raw_code, raw_label, normalized_label,
       fitmatch_category_code, source_measurement_code, priority
from measurement_alias_seed
where source_code = 'uniqlo' and parser_code = 'size_chart';

update fitmatch_vnext.source_measurement_aliases a
set is_active = false, updated_at = now()
from measurement_alias_seed s
where a.is_active
  and a.source_code = s.source_code
  and a.parser_code = s.parser_code
  and (
      (s.raw_code is not null and a.raw_code = s.raw_code)
      or
      (s.raw_code is null and a.raw_code is null
       and a.normalized_label = s.normalized_label)
  )
  and a.fitmatch_category_code is not distinct from s.fitmatch_category_code;

insert into fitmatch_vnext.source_measurement_aliases (
    source_code, parser_code, raw_code, raw_label, normalized_label,
    fitmatch_category_code, garment_type_code, source_measurement_code,
    priority, is_verified, is_active
)
select source_code, parser_code, raw_code, raw_label, normalized_label,
       fitmatch_category_code, null, source_measurement_code,
       priority, true, true
from measurement_alias_seed;

-- Fail the migration if any previously dangerous equivalence survives.
do $$
begin
    if exists (
        select 1
        from fitmatch_vnext.source_measurement_mappings
        where source_measurement_code in (
            'uniqlo.waist_circumference.garment_waist_circumference',
            'uniqlo.hip_circumference.garment_hip_circumference'
        )
          and (fitmatch_measurement_code in ('waist_width','hip_width') or scale_factor <> 1)
          and is_active
    ) then raise exception 'circumference_to_width_mapping_survived'; end if;

    if exists (
        select 1 from fitmatch_vnext.source_measurement_aliases
        where source_code = 'zara' and raw_code = 'zone-name-back-width'
          and source_measurement_code like '%.shoulder_width.%' and is_active
    ) then raise exception 'zara_back_width_still_maps_to_shoulder'; end if;

    if exists (
        select 1 from fitmatch_vnext.source_measurement_aliases
        where source_code = 'musinsa' and normalized_label = '소매부리단면'
          and source_measurement_code like '%.sleeve_length.%' and is_active
    ) then raise exception 'musinsa_cuff_still_maps_to_sleeve_length'; end if;
end $$;

commit;
