with probes(source_code, parser_code, raw_code, raw_label, category_code, expected_code) as (
    values
      ('uniqlo','size_chart','sleeve-length-cb','등 중심부터 소매까지 길이','tops','sleeve_center_back_length'),
      ('uniqlo','size_chart','knit-body-length-front','앞기장','tops','front_length'),
      ('musinsa','actual_size',null::text,'소매부리단면','tops','sleeve_opening_width'),
      ('musinsa','actual_size',null::text,'암홀','tops','armhole_measurement_unspecified'),
      ('zara','zara_kr_size_measure_guide_v1','zone-name-back-width','zone-name-back-width','tops','back_width'),
      ('zara','zara_kr_size_measure_guide_v1','zone-name-front-length','zone-name-front-length','tops','front_length_shoulder_to_hem'),
      ('zara','zara_kr_size_measure_guide_v1','zone-name-arm-width','zone-name-arm-width','tops','upper_arm_width'),
      ('zara','zara_kr_size_measure_guide_v1','zone-name-back-rise','zone-name-back-rise','bottoms','back_rise')
), resolved as (
    select p.*,
           fitmatch_vnext.resolve_measurement(
               p.source_code, p.parser_code, p.raw_code, p.raw_label,
               null, p.category_code, 10
           ) result
    from probes p
)
select source_code, raw_code, raw_label, category_code, expected_code,
       result->>'resolution_status' as resolution_status,
       result->>'fitmatch_measurement_code' as actual_code,
       (result->>'fitmatch_measurement_code' = expected_code) as passed
from resolved
order by source_code, raw_code nulls last, raw_label;

select source_measurement_code, fitmatch_measurement_code, scale_factor,
       fitmatch_measurement_code in ('waist_circumference','hip_circumference')
         and scale_factor = 1 as passed
from fitmatch_vnext.source_measurement_mappings
where source_measurement_code in (
    'uniqlo.waist_circumference.garment_waist_circumference',
    'uniqlo.hip_circumference.garment_hip_circumference'
)
order by source_measurement_code;
