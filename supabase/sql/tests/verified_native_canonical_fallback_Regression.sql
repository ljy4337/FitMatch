\set ON_ERROR_STOP on
create schema auth;
create schema fitmatch_vnext;
create function auth.uid() returns uuid language sql stable
as $$ select '00000000-0000-0000-0000-000000000001'::uuid $$;

create table fitmatch_vnext.products (id uuid primary key, source_code text not null);
create table fitmatch_vnext.product_variants (id uuid primary key, product_id uuid not null);
create table fitmatch_vnext.product_sizes (id uuid primary key, variant_id uuid not null);
create table fitmatch_vnext.closet_items (
    id uuid primary key, user_id uuid not null, product_id uuid not null,
    deleted_at timestamptz
);
create table fitmatch_vnext.closet_item_measurements (
    closet_item_id uuid, fitmatch_measurement_code text, source_measurement_code text,
    source_measurement_code_snapshot text, value numeric, unit_code text
);
create table fitmatch_vnext.fitmatch_measurements (
    measurement_code text primary key, canonical_unit_code text,
    canonical_basis_code text, representation_code text, body_region_code text,
    is_active boolean
);
create table fitmatch_vnext.comparison_metrics (
    comparison_policy_code text, metric_mode text, fitmatch_measurement_code text,
    source_measurement_code text, weight numeric, requirement_mode text,
    priority integer, is_active boolean
);
create table fitmatch_vnext.source_measurements (
    source_measurement_code text primary key, source_code text,
    measurement_basis_code text, representation_code text,
    is_active boolean, is_comparable boolean
);
create table fitmatch_vnext.source_measurement_mappings (
    source_measurement_code text, fitmatch_measurement_code text,
    is_active boolean, is_verified boolean,
    scale_factor numeric, offset_value numeric
);

insert into fitmatch_vnext.products values
('00000000-0000-0000-0000-000000000101','uniqlo'),
('00000000-0000-0000-0000-000000000102','uniqlo'),
('00000000-0000-0000-0000-000000000103','zara');
insert into fitmatch_vnext.product_variants values
('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000102'),
('00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000103');
insert into fitmatch_vnext.product_sizes values
('00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000201'),
('00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000000202');
insert into fitmatch_vnext.closet_items values
('00000000-0000-0000-0000-000000000401','00000000-0000-0000-0000-000000000001',
 '00000000-0000-0000-0000-000000000101',null);
insert into fitmatch_vnext.fitmatch_measurements values
('back_length','cm','back_neck_to_hem','LENGTH','LENGTH',true),
('chest_width','cm','chest_pit_to_pit','FLAT_WIDTH','CHEST',true),
('sleeve_length','cm','sleeve_shoulder_seam_to_cuff','LENGTH','SLEEVE',true),
('sleeve_center_back_length','cm','sleeve_center_back_to_cuff','LENGTH','SLEEVE',true);
insert into fitmatch_vnext.comparison_metrics values
('jacket','CANONICAL','back_length',null,0.8,'OPTIONAL',0,true),
('jacket','CANONICAL','chest_width',null,1.5,'OPTIONAL',0,true),
('jacket','CANONICAL','sleeve_length',null,1,'OPTIONAL',0,true),
('jacket','SOURCE_NATIVE_OVERRIDE',null,
 'uniqlo.sleeve_length.sleeve_center_back_to_cuff',1,'OPTIONAL',0,true);
insert into fitmatch_vnext.source_measurements values
('uniqlo.sleeve_length.sleeve_center_back_to_cuff','uniqlo',
 'sleeve_center_back_to_cuff','LENGTH',true,true);
insert into fitmatch_vnext.source_measurement_mappings values
('uniqlo.sleeve_length.sleeve_center_back_to_cuff',
 'sleeve_center_back_length',true,true,1,0);
insert into fitmatch_vnext.closet_item_measurements values
('00000000-0000-0000-0000-000000000401','back_length',null,null,76,'cm'),
('00000000-0000-0000-0000-000000000401','chest_width',null,null,70,'cm'),
('00000000-0000-0000-0000-000000000401','sleeve_center_back_length',null,
 'uniqlo.sleeve_length.sleeve_center_back_to_cuff',91,'cm');

\ir ../../migrations/20260929132500_verified_native_canonical_fallback.sql

do $$
declare
    target jsonb := jsonb_build_object(
        'product_size_id','00000000-0000-0000-0000-000000000301',
        'semantic_conflict_count',0,
        'measurements',jsonb_build_array(
            jsonb_build_object('fitmatch_measurement_code','back_length',
                'value',69,'unit_code','cm','basis_code','back_neck_to_hem'),
            jsonb_build_object('fitmatch_measurement_code','chest_width',
                'value',72,'unit_code','cm','basis_code','chest_pit_to_pit'),
            jsonb_build_object('fitmatch_measurement_code','sleeve_center_back_length',
                'source_measurement_code','uniqlo.sleeve_length.sleeve_center_back_to_cuff',
                'value',92,'unit_code','cm','basis_code','sleeve_center_back_to_cuff')
        )
    );
    evidence jsonb;
begin
    evidence := fitmatch_vnext.comparison_evidence_20260908(
        '00000000-0000-0000-0000-000000000401','jacket',target);
    if jsonb_array_length(evidence)<>3 or not exists (
        select 1 from jsonb_array_elements(evidence) e
        where e->>'measurement_code'='sleeve_center_back_length'
          and (e->>'reference_value')::numeric=91
          and (e->>'target_value')::numeric=92
    ) then raise exception 'same retailer verified sleeve was not scored: %',evidence; end if;

    evidence := fitmatch_vnext.comparison_evidence_20260908(
        '00000000-0000-0000-0000-000000000401','jacket',
        jsonb_set(target,'{product_size_id}',
            '"00000000-0000-0000-0000-000000000302"'::jsonb));
    if jsonb_array_length(evidence)<>2 then
        raise exception 'cross retailer source override was scored: %',evidence;
    end if;

    evidence := fitmatch_vnext.comparison_evidence_20260908(
        '00000000-0000-0000-0000-000000000401','jacket',
        jsonb_set(target,'{measurements,2,basis_code}',
            '"sleeve_shoulder_seam_to_cuff"'::jsonb));
    if jsonb_array_length(evidence)<>2 then
        raise exception 'conflicting basis was scored: %',evidence;
    end if;

    update fitmatch_vnext.closet_item_measurements
       set source_measurement_code_snapshot='other-source'
     where fitmatch_measurement_code='sleeve_center_back_length';
    evidence := fitmatch_vnext.comparison_evidence_20260908(
        '00000000-0000-0000-0000-000000000401','jacket',target);
    if jsonb_array_length(evidence)<>2 then
        raise exception 'mismatched reference source was scored: %',evidence;
    end if;
end
$$;

\ir ../verified_native_canonical_fallback_Rollback.sql
do $$
declare
    evidence jsonb;
begin
    evidence := fitmatch_vnext.comparison_evidence_20260908(
        '00000000-0000-0000-0000-000000000401','jacket',
        '{"product_size_id":"00000000-0000-0000-0000-000000000301",
          "semantic_conflict_count":0,"measurements":[
            {"fitmatch_measurement_code":"back_length","value":69,
             "unit_code":"cm","basis_code":"back_neck_to_hem"},
            {"fitmatch_measurement_code":"chest_width","value":72,
             "unit_code":"cm","basis_code":"chest_pit_to_pit"},
            {"fitmatch_measurement_code":"sleeve_center_back_length",
             "source_measurement_code":"uniqlo.sleeve_length.sleeve_center_back_to_cuff",
             "value":92,"unit_code":"cm","basis_code":"sleeve_center_back_to_cuff"}
          ]}'::jsonb
    );
    if jsonb_array_length(evidence)<>2 then
        raise exception 'rollback did not restore canonical-only evidence: %',evidence;
    end if;
end
$$;

select 'PASS verified native canonical fallback regression' result;
