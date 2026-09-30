-- LOCAL ONLY: empty disposable database named fitmatch_all_groups_regression.
-- Captured production candidate/eligible/authorization bodies; dependency fixtures
-- supply synthetic auth, classification and canonical evidence. Not an app E2E test.
\set ON_ERROR_STOP on
do $$ begin
 if current_database() <> 'fitmatch_all_groups_regression' then
  raise exception 'Only run in the named disposable local fixture database';
 end if;
end $$;
create schema auth;
create schema fitmatch_vnext;
create function auth.uid() returns uuid language sql as $$ select '00000000-0000-0000-0000-000000000001'::uuid $$;
create table fitmatch_vnext.closet_items(id uuid, user_id uuid, deleted_at timestamptz, garment_type_code text, audience_code text,is_reference boolean);
create table fitmatch_vnext.products(id uuid);
create table fitmatch_vnext.garment_types(garment_type_code text,comparison_policy_code text,is_active boolean);
create table fitmatch_vnext.comparison_policies(policy_code text,is_active boolean,audience_policy_code text,min_common_measurements integer,required_any_min integer,policy_version text,policy_checksum text);
create table fitmatch_vnext.product_variants(id uuid,product_id uuid);
create table fitmatch_vnext.product_sizes(id uuid,variant_id uuid);
create function fitmatch_vnext.effective_target_classification(uuid) returns jsonb language sql as $$ select '{"classification_status":"CONFIRMED","garment_type_code":"top","audience_code":"MEN","effective_source":"GLOBAL_CONFIRMED"}'::jsonb $$;
create function fitmatch_vnext.product_comparison_unit_decision(uuid) returns jsonb language sql as $$ select '{"eligible":true}'::jsonb $$;
create function fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb) returns jsonb language sql as $$ select '{"semantic_conflict_count":0}'::jsonb $$;
create function fitmatch_vnext.comparison_evidence_20260908(uuid,text,jsonb) returns jsonb language sql as $$ select '[{"measurement_code":"chest_width","requirement_mode":"REQUIRED_ANY"}]'::jsonb $$;
insert into fitmatch_vnext.closet_items values ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',null,'outer','MEN',false);
insert into fitmatch_vnext.products values ('00000000-0000-0000-0000-000000000003');
insert into fitmatch_vnext.product_variants values ('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000003');
insert into fitmatch_vnext.product_sizes values ('00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000004');
insert into fitmatch_vnext.garment_types values ('outer','unclassified_outerwear',true),('top','tshirt',true);
insert into fitmatch_vnext.comparison_policies values ('tshirt',true,'ADULT_ANY',1,0,'test','test');
CREATE OR REPLACE FUNCTION fitmatch_vnext.comparison_domain_20260908(p_policy text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
SELECT CASE
 WHEN p_policy IN ('anorak','base_layer_top','blazer','blouson','bodysuit_top',
 'cardigan','coat','fleece_jacket','homewear_top','hoodie','jacket','knit_sweater',
 'knit_vest','ma1','mouton','outer_vest','polo_shirt','puffer_jacket','puffer_vest',
 'shirt_blouse','sleeveless_tshirt','sports_top','sweatshirt','tank_top','tshirt',
 'windbreaker','zip_hoodie','unclassified_outerwear') THEN 'UPPER_BODY'
 WHEN p_policy IN ('homewear_bottom','leggings','skirt','standard_pants') THEN 'LOWER_BODY'
 WHEN p_policy='dress' THEN 'FULL_BODY'
 WHEN p_policy IN ('men_briefs','men_trunks','men_undershirt','women_bra',
 'women_camisole','women_panty','women_slip') THEN 'OTHER'
 ELSE 'UNKNOWN' END;
$function$
;
create schema extensions;
create extension pgcrypto with schema extensions;
alter table fitmatch_vnext.closet_items add column comparison_group_code text, add column item_name text, add column size_label text, add column product_id uuid, add column product_variant_id uuid, add column product_size_id uuid, add column updated_at timestamptz default now();
alter table fitmatch_vnext.products add column comparison_group_code text, add column garment_type_code text;
alter table fitmatch_vnext.product_variants add column sort_order integer default 0;
alter table fitmatch_vnext.product_sizes add column size_label text default 'M', add column sort_order integer default 0;
create table fitmatch_vnext.size_availability_observations(id uuid,product_size_id uuid,availability_status text,observed_at timestamptz,valid_until timestamptz,evidence_fingerprint text);
create table fitmatch_vnext.closet_item_measurements(closet_item_id uuid,measurement_code text);
update fitmatch_vnext.closet_items set comparison_group_code='B',item_name='Synthetic jacket';
insert into fitmatch_vnext.closet_items (id,user_id,garment_type_code,audience_code,is_reference,comparison_group_code,item_name) values
 ('00000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000001','top','MEN',false,'A','Synthetic top'),
 ('00000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000001','bottom','MEN',false,'C','Synthetic pants');
insert into fitmatch_vnext.closet_item_measurements values ('00000000-0000-0000-0000-000000000002','chest_width'),('00000000-0000-0000-0000-000000000006','chest_width'),('00000000-0000-0000-0000-000000000007','waist_width');
update fitmatch_vnext.products set comparison_group_code='F',garment_type_code='inner';
insert into fitmatch_vnext.garment_types values ('inner','generic_underwear',true),('bottom','standard_pants',true);
insert into fitmatch_vnext.comparison_policies values ('generic_underwear',true,'ADULT_ANY',1,0,'test','test'),('unclassified_outerwear',true,'ADULT_ANY',1,0,'test','test'),('standard_pants',true,'ADULT_ANY',1,0,'test','test');
create or replace function fitmatch_vnext.effective_target_classification(uuid) returns jsonb language sql as $$ select jsonb_build_object('classification_status','CONFIRMED','garment_type_code',garment_type_code,'audience_code','MEN','effective_source','GLOBAL_CONFIRMED','comparison_group_code',comparison_group_code) from fitmatch_vnext.products where id=$1 $$;
create function fitmatch_vnext.product_comparison_group(uuid) returns jsonb language sql as $$ select jsonb_build_object('group_code',comparison_group_code) from fitmatch_vnext.products where id=$1 $$;
create function fitmatch_vnext.closet_comparison_group(uuid) returns jsonb language sql as $$ select jsonb_build_object('group_code',comparison_group_code) from fitmatch_vnext.closet_items where id=$1 $$;
create function fitmatch_vnext.comparison_target_context(uuid,uuid,text) returns jsonb language sql as $$ select jsonb_build_object('effective_classification',fitmatch_vnext.effective_target_classification($1) || jsonb_build_object('comparison_group_code',$3,'effective_source','SESSION_USER_SELECTED','effective_authority_fingerprint','synthetic-session'),'target_comparison_group',jsonb_build_object('group_code',$3,'source','SESSION_USER_SELECTED')) $$;
create function fitmatch_vnext.canonical_measurements_for_session_group(uuid,jsonb) returns jsonb language sql as $$ select fitmatch_vnext.canonical_measurements_for_size_with_context($1,$2) $$;
create or replace function fitmatch_vnext.comparison_evidence_20260908(uuid,text,jsonb) returns jsonb language sql as $$ select coalesce(jsonb_agg(jsonb_build_object('measurement_code',measurement_code,'requirement_mode','REQUIRED_ANY')),'[]'::jsonb) from fitmatch_vnext.closet_item_measurements where closet_item_id=$1 and measurement_code='chest_width' $$;
CREATE OR REPLACE FUNCTION fitmatch_vnext.authorize_comparison_with_context_v1(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 caller_id uuid := auth.uid();
 ref fitmatch_vnext.closet_items%rowtype;
 target fitmatch_vnext.products%rowtype;
 ref_gt fitmatch_vnext.garment_types%rowtype;
 target_gt fitmatch_vnext.garment_types%rowtype;
 policy fitmatch_vnext.comparison_policies%rowtype;
 effective_value jsonb;
 unit_value jsonb;
 canonical_value jsonb;
 evidence_value jsonb;
 ref_domain text;
 target_domain text;
 audience_ok boolean;
 common_count integer := 0;
 required_count integer := 0;
 reason_code_value text := 'INVALID_AUTHORITY';
 reason_value text := 'Invalid comparison authority';
 decision_value text := 'BLOCKED';
 result_value jsonb;
BEGIN
 IF caller_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 <<evaluate_pair>>
 BEGIN
  SELECT * INTO ref FROM fitmatch_vnext.closet_items ci
  WHERE ci.id=p_reference_closet_item_id AND ci.user_id=caller_id AND ci.deleted_at IS NULL;
  IF NOT FOUND THEN
   reason_value := 'Reference is missing or not owned'; EXIT evaluate_pair;
  END IF;
  SELECT * INTO target FROM fitmatch_vnext.products p WHERE p.id=p_target_product_id;
  IF NOT FOUND THEN reason_value := 'Target product not found'; EXIT evaluate_pair; END IF;
  -- Reject forged context even when this internal entry point is called directly.
  effective_value := fitmatch_vnext.effective_target_classification(target.id);
  IF p_effective_classification IS DISTINCT FROM effective_value THEN
   reason_value := 'Stale or invalid effective classification context'; EXIT evaluate_pair;
  END IF;
  IF effective_value->>'classification_status' IS DISTINCT FROM 'CONFIRMED' THEN
   reason_code_value := 'CLASSIFICATION_REQUIRED';
   reason_value := 'Target effective classification is not CONFIRMED'; EXIT evaluate_pair;
  END IF;
  unit_value := fitmatch_vnext.product_comparison_unit_decision(target.id);
  IF NOT coalesce((unit_value->>'eligible')::boolean,false) THEN
   reason_code_value := 'STRUCTURALLY_NOT_COMPARABLE';
   reason_value := unit_value->>'reason'; EXIT evaluate_pair;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.product_sizes ps
   JOIN fitmatch_vnext.product_variants pv ON pv.id=ps.variant_id
   WHERE ps.id=p_target_product_size_id AND pv.product_id=target.id) THEN
   reason_code_value := 'NO_ELIGIBLE_TARGET_SIZE';
   reason_value := 'Target size hierarchy mismatch'; EXIT evaluate_pair;
  END IF;
  SELECT * INTO ref_gt FROM fitmatch_vnext.garment_types
  WHERE garment_type_code=ref.garment_type_code AND is_active;
  SELECT * INTO target_gt FROM fitmatch_vnext.garment_types
  WHERE garment_type_code=effective_value->>'garment_type_code' AND is_active;
  IF ref_gt.garment_type_code IS NULL OR target_gt.garment_type_code IS NULL THEN
   reason_value := 'Unsupported garment'; EXIT evaluate_pair;
  END IF;
  SELECT * INTO policy FROM fitmatch_vnext.comparison_policies
  WHERE policy_code=target_gt.comparison_policy_code AND is_active;
  IF NOT FOUND THEN reason_value := 'Comparison policy unavailable'; EXIT evaluate_pair; END IF;
  ref_domain := fitmatch_vnext.comparison_domain_20260908(ref_gt.comparison_policy_code);
  target_domain := fitmatch_vnext.comparison_domain_20260908(target_gt.comparison_policy_code);
  IF ref_gt.comparison_policy_code IS DISTINCT FROM target_gt.comparison_policy_code
     AND NOT (ref_domain=target_domain AND ref_domain IN ('UPPER_BODY','LOWER_BODY')) THEN
   reason_code_value := 'INCOMPATIBLE_BODY_REGION';
   reason_value := 'Comparison domains are incompatible'; EXIT evaluate_pair;
  END IF;
  -- Existing audience policy remains in force; no new audience policy is invented.
  audience_ok := CASE policy.audience_policy_code
   WHEN 'IGNORE' THEN true
   WHEN 'ADULT_ANY' THEN ref.audience_code IN ('MEN','WOMEN','UNISEX')
     AND effective_value->>'audience_code' IN ('MEN','WOMEN','UNISEX')
   WHEN 'SAME_ONLY' THEN ref.audience_code=effective_value->>'audience_code'
   ELSE ref.audience_code=effective_value->>'audience_code'
     OR ref.audience_code='UNISEX' OR effective_value->>'audience_code'='UNISEX' END;
  IF NOT coalesce(audience_ok,false) THEN
   reason_code_value := 'INCOMPATIBLE_AUDIENCE';
   reason_value := 'Audience is incompatible'; EXIT evaluate_pair;
  END IF;
  canonical_value := fitmatch_vnext.canonical_measurements_for_size_with_context(
    p_target_product_size_id,effective_value);
  IF coalesce((canonical_value->>'semantic_conflict_count')::integer,0)>0 THEN
   reason_value := 'Canonical measurement semantic conflict'; EXIT evaluate_pair;
  END IF;
  evidence_value := fitmatch_vnext.comparison_evidence_20260908(ref.id,policy.policy_code,canonical_value);
  common_count := jsonb_array_length(evidence_value);
  SELECT count(*) INTO required_count FROM jsonb_array_elements(evidence_value) e
   WHERE e->>'requirement_mode'='REQUIRED_ANY';
  IF common_count<1 THEN
   decision_value := 'MEASUREMENTS_REQUIRED'; reason_code_value := 'NO_COMMON_MEASUREMENTS';
   reason_value := 'No usable common canonical policy measurement'; EXIT evaluate_pair;
  END IF;
  -- Automatic mode requires a designated reference in the existing policy family.
  -- Axis differences are scored, not excluded or blocked, in BOTH modes.
  IF NOT coalesce(p_manual_explicit,false) AND
    (NOT coalesce(ref.is_reference,false) OR ref_gt.comparison_policy_code<>target_gt.comparison_policy_code) THEN
   reason_code_value := 'NO_AUTOMATIC_REFERENCE';
   reason_value := 'Explicit user selection is required'; EXIT evaluate_pair;
  END IF;
  IF coalesce(p_manual_explicit,false) THEN
   decision_value := 'MANUAL_EXTENDED'; reason_code_value := 'USER_SELECTED_REFERENCE';
   reason_value := 'User-selected comparison with at least one common canonical measurement';
  ELSE
   decision_value := 'AUTOMATIC'; reason_code_value := 'AUTOMATIC_MATCH';
   reason_value := 'Designated reference with at least one common canonical measurement';
  END IF;
 END evaluate_pair;
 result_value := jsonb_build_object(
  'decision',decision_value,'allowed',decision_value IN ('AUTOMATIC','MANUAL_EXTENDED'),
  'mode',CASE WHEN decision_value IN ('AUTOMATIC','MANUAL_EXTENDED') THEN decision_value ELSE 'NONE' END,
  'reason_code',reason_code_value,'reason',reason_value,
  'reference_measurement_domain',ref_domain,'target_measurement_domain',target_domain,
  'excluded_measurement_codes','[]'::jsonb,'excluded_measurement_reasons','[]'::jsonb,
  'required_measurement_codes','[]'::jsonb,'minimum_common',1,
  'common_measurement_count',common_count,'required_any_count',required_count,
  'required_any_min',0,'policy_minimum_common',policy.min_common_measurements,
  'policy_required_any_min',policy.required_any_min,
  'used_measurement_codes',coalesce((SELECT jsonb_agg(e->'measurement_code' ORDER BY e->>'measurement_code')
    FROM jsonb_array_elements(coalesce(evidence_value,'[]'::jsonb)) e),'[]'::jsonb),
  'policy_code',policy.policy_code,'policy_version',policy.policy_version,'policy_checksum',policy.policy_checksum,
  'authorization_version','fitmatch-vnext-authorization-20260908-user-policy-v1');
 IF effective_value->>'effective_source'='USER_EXPLICIT' THEN
  result_value := result_value || jsonb_build_object('classification_source','USER_EXPLICIT',
   'effective_authority_fingerprint',effective_value->>'effective_authority_fingerprint',
   'override_revision',effective_value->'override_revision');
 END IF;
 RETURN result_value;
END;
$function$

;
CREATE OR REPLACE FUNCTION fitmatch_vnext.authorize_comparison_with_context_v1(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb, p_requested_group_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_id uuid := auth.uid();
  ref fitmatch_vnext.closet_items%rowtype;
  target fitmatch_vnext.products%rowtype;
  ref_gt fitmatch_vnext.garment_types%rowtype;
  target_gt fitmatch_vnext.garment_types%rowtype;
  policy fitmatch_vnext.comparison_policies%rowtype;
  context_value jsonb;
  effective_value jsonb;
  canonical_value jsonb;
  evidence_value jsonb;
  unit_value jsonb;
  target_variant_id uuid;
  ref_domain text;
  target_domain text;
  audience_ok boolean;
  common_count integer := 0;
  reason_code_value text := 'INVALID_AUTHORITY';
  reason_value text := 'Invalid comparison authority';
  decision_value text := 'BLOCKED';
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  <<evaluate_pair>>
  begin
    select * into ref from fitmatch_vnext.closet_items ci
    where ci.id = p_reference_closet_item_id
      and ci.user_id = caller_id and ci.deleted_at is null;
    if not found then
      reason_value := 'Reference is missing or not owned'; exit evaluate_pair;
    end if;
    select * into target from fitmatch_vnext.products p
    where p.id = p_target_product_id;
    if not found then reason_value := 'Target product not found'; exit evaluate_pair; end if;

    select pv.id into target_variant_id
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where ps.id = p_target_product_size_id and pv.product_id = target.id;
    if not found then
      reason_code_value := 'NO_ELIGIBLE_TARGET_SIZE';
      reason_value := 'Target size hierarchy mismatch'; exit evaluate_pair;
    end if;
    context_value := fitmatch_vnext.comparison_target_context(
      target.id, target_variant_id, p_requested_group_code
    );
    effective_value := context_value->'effective_classification';
    if p_effective_classification is distinct from effective_value then
      reason_value := 'Stale or invalid effective classification context';
      exit evaluate_pair;
    end if;
    if effective_value->>'classification_status' is distinct from 'CONFIRMED' then
      reason_code_value := 'CLASSIFICATION_REQUIRED';
      reason_value := 'Target effective classification is not CONFIRMED';
      exit evaluate_pair;
    end if;
    unit_value := fitmatch_vnext.product_comparison_unit_decision(target.id);
    if not coalesce((unit_value->>'eligible')::boolean, false) then
      reason_code_value := 'STRUCTURALLY_NOT_COMPARABLE';
      reason_value := unit_value->>'reason'; exit evaluate_pair;
    end if;
    select * into ref_gt from fitmatch_vnext.garment_types
    where garment_type_code = ref.garment_type_code and is_active;
    select * into target_gt from fitmatch_vnext.garment_types
    where garment_type_code = effective_value->>'garment_type_code' and is_active;
    if ref_gt.garment_type_code is null or target_gt.garment_type_code is null then
      reason_value := 'Unsupported garment'; exit evaluate_pair;
    end if;
    if fitmatch_vnext.closet_comparison_group(ref.id)->>'group_code'
       is distinct from effective_value->>'comparison_group_code' then
      reason_code_value := 'INCOMPATIBLE_BODY_REGION';
      reason_value := 'Reference comparison group does not match requested group';
      exit evaluate_pair;
    end if;
    select * into policy from fitmatch_vnext.comparison_policies
    where policy_code = target_gt.comparison_policy_code and is_active;
    if not found then reason_value := 'Comparison policy unavailable'; exit evaluate_pair; end if;

    ref_domain := fitmatch_vnext.comparison_domain_20260908(
      ref_gt.comparison_policy_code
    );
    target_domain := fitmatch_vnext.comparison_domain_20260908(
      target_gt.comparison_policy_code
    );
    if ref_gt.comparison_policy_code is distinct from target_gt.comparison_policy_code
       and not (ref_domain = target_domain and ref_domain in ('UPPER_BODY','LOWER_BODY')) then
      reason_code_value := 'INCOMPATIBLE_BODY_REGION';
      reason_value := 'Comparison domains are incompatible'; exit evaluate_pair;
    end if;
    audience_ok := case policy.audience_policy_code
      when 'IGNORE' then true
      when 'ADULT_ANY' then ref.audience_code in ('MEN','WOMEN','UNISEX')
        and effective_value->>'audience_code' in ('MEN','WOMEN','UNISEX')
      when 'SAME_ONLY' then ref.audience_code = effective_value->>'audience_code'
      else ref.audience_code = effective_value->>'audience_code'
        or ref.audience_code = 'UNISEX'
        or effective_value->>'audience_code' = 'UNISEX' end;
    if not coalesce(audience_ok, false) then
      reason_code_value := 'INCOMPATIBLE_AUDIENCE';
      reason_value := 'Audience is incompatible'; exit evaluate_pair;
    end if;

    canonical_value := fitmatch_vnext.canonical_measurements_for_session_group(
      p_target_product_size_id, effective_value
    );
    if coalesce((canonical_value->>'semantic_conflict_count')::integer, 0) > 0 then
      reason_value := 'Canonical measurement semantic conflict'; exit evaluate_pair;
    end if;
    evidence_value := fitmatch_vnext.comparison_evidence_20260908(
      ref.id, policy.policy_code, canonical_value
    );
    common_count := jsonb_array_length(evidence_value);
    if common_count < 1 then
      decision_value := 'MEASUREMENTS_REQUIRED';
      reason_code_value := 'NO_COMMON_MEASUREMENTS';
      reason_value := 'No usable common canonical policy measurement';
      exit evaluate_pair;
    end if;
    if not coalesce(p_manual_explicit, false) then
      reason_code_value := 'NO_AUTOMATIC_REFERENCE';
      reason_value := 'Explicit user selection is required'; exit evaluate_pair;
    end if;
    decision_value := 'MANUAL_EXTENDED';
    reason_code_value := 'USER_SELECTED_REFERENCE';
    reason_value := 'User-selected comparison with server-validated session group';
  end evaluate_pair;

  return jsonb_build_object(
    'decision', decision_value,
    'allowed', decision_value = 'MANUAL_EXTENDED',
    'mode', case when decision_value = 'MANUAL_EXTENDED'
      then decision_value else 'NONE' end,
    'reason_code', reason_code_value,
    'reason', reason_value,
    'reference_measurement_domain', ref_domain,
    'target_measurement_domain', target_domain,
    'excluded_measurement_codes', '[]'::jsonb,
    'excluded_measurement_reasons', '[]'::jsonb,
    'required_measurement_codes', '[]'::jsonb,
    'minimum_common', 1,
    'common_measurement_count', common_count,
    'policy_code', policy.policy_code,
    'policy_version', policy.policy_version,
    'policy_checksum', policy.policy_checksum,
    'classification_source', effective_value->>'effective_source',
    'effective_authority_fingerprint',
      effective_value->>'effective_authority_fingerprint',
    'override_revision', effective_value->'override_revision',
    'target_comparison_group', context_value->'target_comparison_group',
    'authorization_version', 'fitmatch-vnext-session-group-authorization-v1'
  );
end
$function$

;
CREATE OR REPLACE FUNCTION fitmatch_vnext.find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  eligible_value jsonb;
  eligible_size_ids_value jsonb;
  eligible_common_count integer;
  checked_variant record;
  eligibility_reason text;
  caller_id uuid := auth.uid();
  target_row fitmatch_vnext.products%rowtype;
  target_group jsonb;
  target_group_code text;
  closet_row fitmatch_vnext.closet_items%rowtype;
  closet_group jsonb;
  closet_group_code text;
  same_group_count integer;
  decision_value text;
  allowed_value boolean;
  reason_code_value text;
  reason_value text;
  item_value jsonb;
  candidates_value jsonb := '[]'::jsonb;
  blocked_value jsonb := '[]'::jsonb;
  all_items_value jsonb := '[]'::jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select * into target_row from fitmatch_vnext.products p
  where p.id=p_target_product_id;
  if not found then raise exception 'Target product not found'; end if;

  if p_target_variant_id is not null and not exists (
    select 1 from fitmatch_vnext.product_variants pv
    where pv.id=p_target_variant_id and pv.product_id=target_row.id
  ) then
    raise exception 'Target variant hierarchy mismatch';
  end if;

  target_group := fitmatch_vnext.product_comparison_group(target_row.id);
  target_group_code := target_group->>'group_code';

  select count(*) into same_group_count
  from fitmatch_vnext.closet_items ci
  where ci.user_id=caller_id and ci.deleted_at is null
    and ci.comparison_group_code=target_group_code;

  for closet_row in
    select * from fitmatch_vnext.closet_items ci
    where ci.user_id=caller_id and ci.deleted_at is null
    order by ci.is_reference desc,ci.updated_at desc,ci.id
  loop
    closet_group := fitmatch_vnext.closet_comparison_group(closet_row.id);
    closet_group_code := closet_group->>'group_code';

    if target_group_code is null then
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'COMPARISON_GROUP_REQUIRED';
      reason_value := '상품의 비교 그룹을 먼저 선택해 주세요.';
    elsif closet_group_code=target_group_code and closet_row.is_reference then
      decision_value := 'AUTOMATIC';
      allowed_value := true;
      reason_code_value := 'AUTOMATIC_MATCH';
      reason_value := '같은 그룹의 기준 옷입니다.';
    elsif closet_group_code=target_group_code then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '같은 그룹에서 직접 선택할 수 있습니다.';
    elsif (target_group_code='A' and closet_group_code='B')
       or (target_group_code='B' and closet_group_code='A') then
      decision_value := 'MANUAL_EXTENDED';
      allowed_value := true;
      reason_code_value := 'USER_SELECTED_REFERENCE';
      reason_value := '상의와 아우터를 직접 선택해 비교할 수 있습니다.';
    else
      decision_value := 'BLOCKED';
      allowed_value := false;
      reason_code_value := 'INCOMPATIBLE_BODY_REGION';
      reason_value := '측정하는 신체 부위가 달라 비교할 수 없습니다.';
    end if;

    eligible_size_ids_value := '[]'::jsonb;
    eligible_common_count := 0;
    eligibility_reason := null;
    if allowed_value then
      for checked_variant in
        select pv.id from fitmatch_vnext.product_variants pv
        where pv.product_id=target_row.id
          and (p_target_variant_id is null or pv.id=p_target_variant_id)
        order by pv.sort_order,pv.id
      loop
        eligible_value := fitmatch_vnext.eligible_candidate_sizes(
          closet_row.id,target_row.id,checked_variant.id,decision_value<>'AUTOMATIC'
        );
        if coalesce((eligible_value->>'allowed')::boolean,false) then
          eligible_size_ids_value := eligible_size_ids_value ||
            coalesce(eligible_value->'authorized_candidate_product_size_ids','[]'::jsonb);
          eligible_common_count := greatest(eligible_common_count,
            jsonb_array_length(coalesce(
              eligible_value->'candidates'->0->'comparison_measurements','[]'::jsonb)));
        else
          eligibility_reason := coalesce(eligibility_reason,eligible_value->>'reason_code');
        end if;
      end loop;
      if jsonb_array_length(eligible_size_ids_value)=0 then
        allowed_value := false;
        decision_value := 'BLOCKED';
        reason_code_value := coalesce(eligibility_reason,'NO_ELIGIBLE_TARGET_SIZE');
        reason_value := '공통 실측 등 비교 조건을 충족하는 사이즈가 없습니다.';
      end if;
    end if;

    item_value := jsonb_build_object(
      'closet_item_id',closet_row.id,
      'item_name',closet_row.item_name,
      'size_label',closet_row.size_label,
      'product_id',closet_row.product_id,
      'variant_id',closet_row.product_variant_id,
      'product_size_id',closet_row.product_size_id,
      'is_current_reference',closet_row.is_reference,
      'decision',decision_value,
      'allowed',allowed_value,
      'mode',case when decision_value='AUTOMATIC' then 'AUTOMATIC'
                  when decision_value='MANUAL_EXTENDED' then 'MANUAL_EXTENDED'
                  else 'NONE' end,
      'manual_explicit_required',decision_value='MANUAL_EXTENDED',
      'reason_code',reason_code_value,
      'reason',reason_value,
      'common_measurement_count',eligible_common_count,
      'excluded_measurement_codes','[]'::jsonb,
      'required_measurement_codes','[]'::jsonb,
      'eligible_product_size_ids',case when allowed_value
        then eligible_size_ids_value else '[]'::jsonb end,
      'comparison_group',closet_group,
      'same_comparison_group',closet_group_code=target_group_code
    );

    all_items_value := all_items_value || jsonb_build_array(item_value);
    if allowed_value then
      candidates_value := candidates_value || jsonb_build_array(item_value);
    else
      blocked_value := blocked_value || jsonb_build_array(item_value);
    end if;
  end loop;

  return jsonb_build_object(
    'target_product_id',target_row.id,
    'target_variant_id',p_target_variant_id,
    'effective_classification',fitmatch_vnext.effective_target_classification(target_row.id),
    'comparison_group',target_group,
    'candidates',candidates_value,
    'blocked',blocked_value,
    'fallback_closet_items',case when same_group_count=0
      then all_items_value else '[]'::jsonb end,
    'candidate_count',jsonb_array_length(candidates_value),
    'blocked_count',jsonb_array_length(blocked_value),
    'same_group_count',same_group_count,
    'status',case when jsonb_array_length(candidates_value)>0
      then 'READY' else 'NO_REFERENCE_CANDIDATE' end,
    'selection_policy','CATEGORY_GROUP_ONLY',
    'measurements_used_for_candidate_selection',true,
    'reference_candidate_version','fitmatch-vnext-group-candidates-v1'
  );
end
$function$

;
CREATE OR REPLACE FUNCTION fitmatch_vnext.find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid, p_requested_group_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_id uuid := auth.uid();
  context_value jsonb;
  target_group_code text;
  closet_row fitmatch_vnext.closet_items%rowtype;
  closet_group jsonb;
  eligible_value jsonb;
  item_value jsonb;
  candidates_value jsonb := '[]'::jsonb;
  blocked_value jsonb := '[]'::jsonb;
begin
  if p_requested_group_code is null then
    return fitmatch_vnext.find_reference_candidates(
      p_target_product_id, p_target_variant_id
    );
  end if;
  if caller_id is null then raise exception 'Authentication required'; end if;
  context_value := fitmatch_vnext.comparison_target_context(
    p_target_product_id, p_target_variant_id, p_requested_group_code
  );
  target_group_code := context_value->'target_comparison_group'->>'group_code';
  if target_group_code is null then
    raise exception 'Requested comparison group was not validated';
  end if;

  for closet_row in
    select * from fitmatch_vnext.closet_items ci
    where ci.user_id = caller_id and ci.deleted_at is null
    order by ci.updated_at desc, ci.id
  loop
    closet_group := fitmatch_vnext.closet_comparison_group(closet_row.id);
    if closet_group->>'group_code' is distinct from target_group_code then
      item_value := jsonb_build_object(
        'closet_item_id', closet_row.id,
        'item_name', closet_row.item_name,
        'size_label', closet_row.size_label,
        'product_id', closet_row.product_id,
        'variant_id', closet_row.product_variant_id,
        'product_size_id', closet_row.product_size_id,
        'is_current_reference', closet_row.is_reference,
        'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
        'manual_explicit_required', true,
        'reason_code', 'INCOMPATIBLE_BODY_REGION',
        'reason', 'Reference comparison group does not match requested group',
        'common_measurement_count', 0,
        'eligible_product_size_ids', '[]'::jsonb,
        'comparison_group', closet_group,
        'same_comparison_group', false
      );
      blocked_value := blocked_value || jsonb_build_array(item_value);
      continue;
    end if;

    eligible_value := fitmatch_vnext.eligible_candidate_sizes(
      closet_row.id, p_target_product_id, p_target_variant_id,
      true, p_requested_group_code
    );
    item_value := jsonb_build_object(
      'closet_item_id', closet_row.id,
      'item_name', closet_row.item_name,
      'size_label', closet_row.size_label,
      'product_id', closet_row.product_id,
      'variant_id', closet_row.product_variant_id,
      'product_size_id', closet_row.product_size_id,
      'is_current_reference', closet_row.is_reference,
      'decision', eligible_value->>'decision',
      'allowed', coalesce((eligible_value->>'allowed')::boolean, false),
      'mode', eligible_value->>'mode',
      'manual_explicit_required', true,
      'reason_code', eligible_value->>'reason_code',
      'reason', eligible_value->>'reason',
      'common_measurement_count', case
        when jsonb_array_length(coalesce(eligible_value->'candidates','[]'::jsonb)) > 0
        then jsonb_array_length(coalesce(
          eligible_value->'candidates'->0->'comparison_measurements','[]'::jsonb
        )) else 0 end,
      'eligible_product_size_ids', coalesce(
        eligible_value->'authorized_candidate_product_size_ids','[]'::jsonb
      ),
      'comparison_group', closet_group,
      'same_comparison_group', true
    );
    if coalesce((eligible_value->>'allowed')::boolean, false) then
      candidates_value := candidates_value || jsonb_build_array(item_value);
    else
      blocked_value := blocked_value || jsonb_build_array(item_value);
    end if;
  end loop;

  return jsonb_build_object(
    'target_product_id', p_target_product_id,
    'target_variant_id', p_target_variant_id,
    'effective_classification', context_value->'effective_classification',
    'comparison_group', context_value->'target_comparison_group',
    'target_comparison_group', context_value->'target_comparison_group',
    'candidates', candidates_value,
    'blocked', blocked_value,
    'candidate_count', jsonb_array_length(candidates_value),
    'blocked_count', jsonb_array_length(blocked_value),
    'status', case when jsonb_array_length(candidates_value) > 0
      then 'READY' else 'NO_REFERENCE_CANDIDATE' end,
    'selection_policy', 'SESSION_REQUESTED_GROUP_ONLY',
    'measurements_used_for_candidate_selection', true,
    'reference_candidate_version',
      'fitmatch-vnext-session-group-candidates-v1'
  );
end
$function$
;
CREATE OR REPLACE FUNCTION fitmatch_vnext.authorize_comparison_with_context(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    unit_value jsonb;
begin
    unit_value := fitmatch_vnext.product_comparison_unit_decision(
        p_target_product_id
    );
    if not coalesce((unit_value ->> 'eligible')::boolean, false) then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'STRUCTURALLY_NOT_COMPARABLE',
            'excluded_measurement_codes', '[]'::jsonb,
            'excluded_measurement_reasons', '[]'::jsonb,
            'reason', unit_value ->> 'reason',
            'comparison_unit', unit_value
        );
    end if;
    return fitmatch_vnext.authorize_comparison_with_context_v1(
        p_reference_closet_item_id, p_target_product_id,
        p_target_product_size_id, p_manual_explicit, p_effective_classification
    );
end
$function$

;
CREATE OR REPLACE FUNCTION fitmatch_vnext.authorize_comparison_with_context(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb, p_requested_group_code text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select fitmatch_vnext.authorize_comparison_with_context_v1(
    p_reference_closet_item_id, p_target_product_id,
    p_target_product_size_id, p_manual_explicit,
    p_effective_classification, p_requested_group_code
  )
$function$

;
CREATE OR REPLACE FUNCTION fitmatch_vnext.eligible_candidate_sizes(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_variant_id uuid, p_manual_explicit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
    reference_row fitmatch_vnext.closet_items%rowtype;
    target_row fitmatch_vnext.products%rowtype;
    effective_value jsonb;
    size_row record;
    canonical_value jsonb;
    authorization_value jsonb;
    comparison_measurements_value jsonb;
    candidates_value jsonb := '[]'::jsonb;
    fingerprint_candidates_value jsonb := '[]'::jsonb;
    candidate_value jsonb;
    total_size_count_value integer := 0;
    available_count_value integer := 0;
    sold_out_count_value integer := 0;
    unknown_count_value integer := 0;
    expired_available_count_value integer := 0;
    semantic_conflict_count_value integer := 0;
    authorization_rejected_count_value integer := 0;
    authority_fingerprint_value text;
    authority_version_value text;
    rejected_reason_code_value text;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;

    select * into reference_row
    from fitmatch_vnext.closet_items ci
    where ci.id = p_reference_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null;

    if not found then
        raise exception 'Reference is missing or not owned';
    end if;

    select * into target_row
    from fitmatch_vnext.products p
    where p.id = p_target_product_id;

    if not found then
        raise exception 'Target product not found';
    end if;

    effective_value := fitmatch_vnext.effective_target_classification(
        target_row.id
    );

    if effective_value ->> 'classification_status' <> 'CONFIRMED' then
        return jsonb_build_object(
            'allowed', false,
            'decision', 'BLOCKED',
            'reason', 'Target effective classification is not CONFIRMED',
            'effective_classification', effective_value,
            'authorized_candidate_product_size_ids', '[]'::jsonb,
            'candidates', '[]'::jsonb,
            'candidate_authority_version', 'fitmatch-vnext-candidates-20260908-effective-v1'
        );
    end if;

    if not exists (
        select 1
        from fitmatch_vnext.product_variants pv
        where pv.id = p_target_variant_id
          and pv.product_id = p_target_product_id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    for size_row in
        select
            ps.id as product_size_id,
            ps.size_label,
            ps.sort_order,
            availability.availability_status,
            availability.observed_at as availability_observed_at,
            availability.valid_until as availability_valid_until,
            availability.evidence_fingerprint as availability_evidence_fingerprint
        from fitmatch_vnext.product_sizes ps
        left join lateral (
            select
                o.availability_status,
                o.observed_at,
                o.valid_until,
                o.evidence_fingerprint
            from fitmatch_vnext.size_availability_observations o
            where o.product_size_id = ps.id
            order by o.observed_at desc, o.id desc
            limit 1
        ) availability on true
        where ps.variant_id = p_target_variant_id
        order by ps.sort_order, ps.id
    loop
        total_size_count_value := total_size_count_value + 1;

        -- Inventory is diagnostic/presentation data only.
        -- IMPORTANT: no inventory state below is allowed to `continue` the loop.
        case size_row.availability_status
            when 'AVAILABLE' then
                available_count_value := available_count_value + 1;
            when 'SOLD_OUT' then
                sold_out_count_value := sold_out_count_value + 1;
            else
                unknown_count_value := unknown_count_value + 1;
        end case;

        if size_row.availability_status = 'AVAILABLE'
           and (
               size_row.availability_valid_until is null
               or size_row.availability_valid_until < now()
           ) then
            expired_available_count_value := expired_available_count_value + 1;
        end if;

        canonical_value :=
            fitmatch_vnext.canonical_measurements_for_size_with_context(
                size_row.product_size_id,
                effective_value
            );

        if coalesce(
            (canonical_value ->> 'semantic_conflict_count')::integer,
            0
        ) > 0 then
            semantic_conflict_count_value :=
                semantic_conflict_count_value + 1;
            continue;
        end if;

        authorization_value :=
            fitmatch_vnext.authorize_comparison_with_context(
                reference_row.id,
                target_row.id,
                size_row.product_size_id,
                p_manual_explicit,
                effective_value
            );

        if not coalesce(
            (authorization_value ->> 'allowed')::boolean,
            false
        ) then
            rejected_reason_code_value := coalesce(rejected_reason_code_value, authorization_value->>'reason_code');
            authorization_rejected_count_value :=
                authorization_rejected_count_value + 1;
            continue;
        end if;

        comparison_measurements_value :=
            fitmatch_vnext.comparison_evidence_20260908(
                reference_row.id, authorization_value ->> 'policy_code', canonical_value
            );
        if jsonb_array_length(comparison_measurements_value) < 1 then
            authorization_rejected_count_value := authorization_rejected_count_value + 1;
            continue;
        end if;

        candidate_value := jsonb_build_object(
            'product_size_id', size_row.product_size_id,
            'size_label', size_row.size_label,
            'availability', jsonb_build_object(
                'status', size_row.availability_status,
                'observed_at', size_row.availability_observed_at,
                'valid_until', size_row.availability_valid_until,
                'evidence_fingerprint',
                    size_row.availability_evidence_fingerprint
            ),
            'canonical_measurements', canonical_value,
            'comparison_measurements', comparison_measurements_value,
            'authorization', authorization_value
        );

        candidates_value :=
            candidates_value || jsonb_build_array(candidate_value);

        -- Candidate authority intentionally excludes inventory metadata.
        -- A SOLD_OUT <-> AVAILABLE change must not invalidate fit authority.
        fingerprint_candidates_value :=
            fingerprint_candidates_value || jsonb_build_array(
                jsonb_build_object(
                    'product_size_id', size_row.product_size_id,
                    'size_label', size_row.size_label,
                    'canonical_measurements', canonical_value,
                    'comparison_measurements', comparison_measurements_value,
                    'authorization', authorization_value
                )
            );
    end loop;

    if effective_value ->> 'effective_source' = 'GLOBAL_CONFIRMED' then
        authority_version_value := 'fitmatch-vnext-candidates-20260908-global-v1';
        authority_fingerprint_value := encode(
            extensions.digest(
                concat_ws(
                    '|',
                    reference_row.id::text,
                    target_row.id::text,
                    p_target_variant_id::text,
                    p_manual_explicit::text,
                    fingerprint_candidates_value::text,
                    authority_version_value
                ),
                'sha256'
            ),
            'hex'
        );
    else
        authority_version_value := 'fitmatch-vnext-candidates-20260908-effective-v1';
        authority_fingerprint_value := encode(
            extensions.digest(
                concat_ws(
                    '|',
                    reference_row.id::text,
                    target_row.id::text,
                    p_target_variant_id::text,
                    p_manual_explicit::text,
                    effective_value ->> 'effective_authority_fingerprint',
                    effective_value ->> 'override_revision',
                    fingerprint_candidates_value::text,
                    authority_version_value
                ),
                'sha256'
            ),
            'hex'
        );
    end if;

    return jsonb_build_object(
        'allowed', jsonb_array_length(candidates_value) > 0,
        'decision', case
            when jsonb_array_length(candidates_value) > 0 then
                coalesce(
                    candidates_value -> 0 -> 'authorization' ->> 'decision',
                    'BLOCKED'
                )
            else 'BLOCKED'
        end,
        'reason_code', case when jsonb_array_length(candidates_value)>0
            then candidates_value->0->'authorization'->>'reason_code'
            else coalesce(rejected_reason_code_value,'NO_ELIGIBLE_TARGET_SIZE') end,
        'mode', case
            when jsonb_array_length(candidates_value) > 0 then
                coalesce(
                    candidates_value -> 0 -> 'authorization' ->> 'mode',
                    'NONE'
                )
            else 'NONE'
        end,
        'reason', case
            when jsonb_array_length(candidates_value) > 0
                then 'Database-generated eligible candidate set'
            when total_size_count_value = 0
                then 'Target variant has no sizes'
            when semantic_conflict_count_value > 0
                then 'Canonical measurement semantic conflict'
            else 'No size satisfies comparison authorization and measurement minimums'
        end,
        'reference_closet_item_id', reference_row.id,
        'target_product_id', target_row.id,
        'target_variant_id', p_target_variant_id,
        'manual_explicit', p_manual_explicit,
        'classification_source', effective_value ->> 'effective_source',
        'effective_authority_fingerprint',
            effective_value ->> 'effective_authority_fingerprint',
        'override_revision', effective_value -> 'override_revision',
        'authorized_candidate_product_size_ids', coalesce((
            select jsonb_agg(candidate -> 'product_size_id')
            from jsonb_array_elements(candidates_value) candidate
        ), '[]'::jsonb),
        'candidates', candidates_value,
        'diagnostics', jsonb_build_object(
            'total_size_count', total_size_count_value,
            'latest_available_count', available_count_value,
            'latest_sold_out_count', sold_out_count_value,
            'latest_unknown_or_missing_count', unknown_count_value,
            'expired_or_unbounded_available_count',
                expired_available_count_value,
            'semantic_conflict_count', semantic_conflict_count_value,
            'authorization_rejected_count',
                authorization_rejected_count_value,
            'inventory_ignored_for_eligibility', true
        ),
        'candidate_authority_fingerprint', authority_fingerprint_value,
        'candidate_authority_version', authority_version_value
    );
end
$function$

;
CREATE OR REPLACE FUNCTION fitmatch_vnext.eligible_candidate_sizes(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_variant_id uuid, p_manual_explicit boolean, p_requested_group_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_id uuid := auth.uid();
  reference_row fitmatch_vnext.closet_items%rowtype;
  context_value jsonb;
  effective_value jsonb;
  size_row record;
  canonical_value jsonb;
  authorization_value jsonb;
  comparison_measurements_value jsonb;
  candidates_value jsonb := '[]'::jsonb;
  fingerprint_candidates_value jsonb := '[]'::jsonb;
  candidate_value jsonb;
  semantic_conflict_count_value integer := 0;
  rejected_reason_code_value text;
  authority_version_value constant text :=
    'fitmatch-vnext-session-group-candidates-v1';
  authority_fingerprint_value text;
begin
  if p_requested_group_code is null then
    return fitmatch_vnext.eligible_candidate_sizes(
      p_reference_closet_item_id, p_target_product_id,
      p_target_variant_id, p_manual_explicit
    );
  end if;
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into reference_row from fitmatch_vnext.closet_items ci
  where ci.id = p_reference_closet_item_id
    and ci.user_id = caller_id and ci.deleted_at is null;
  if not found then raise exception 'Reference is missing or not owned'; end if;

  context_value := fitmatch_vnext.comparison_target_context(
    p_target_product_id, p_target_variant_id, p_requested_group_code
  );
  effective_value := context_value->'effective_classification';
  if effective_value->>'classification_status' is distinct from 'CONFIRMED' then
    return jsonb_build_object(
      'allowed', false, 'decision', 'BLOCKED',
      'reason_code', 'CLASSIFICATION_REQUIRED',
      'reason', 'Target comparison context is not confirmed',
      'authorized_candidate_product_size_ids', '[]'::jsonb,
      'candidates', '[]'::jsonb,
      'target_comparison_group', context_value->'target_comparison_group'
    );
  end if;

  for size_row in
    select ps.id as product_size_id, ps.size_label, ps.sort_order,
      availability.availability_status,
      availability.observed_at as availability_observed_at,
      availability.valid_until as availability_valid_until,
      availability.evidence_fingerprint as availability_evidence_fingerprint
    from fitmatch_vnext.product_sizes ps
    left join lateral (
      select o.availability_status, o.observed_at, o.valid_until,
        o.evidence_fingerprint
      from fitmatch_vnext.size_availability_observations o
      where o.product_size_id = ps.id
      order by o.observed_at desc, o.id desc limit 1
    ) availability on true
    where ps.variant_id = p_target_variant_id
    order by ps.sort_order, ps.id
  loop
    canonical_value := fitmatch_vnext.canonical_measurements_for_session_group(
      size_row.product_size_id, effective_value
    );
    if coalesce((canonical_value->>'semantic_conflict_count')::integer, 0) > 0 then
      semantic_conflict_count_value := semantic_conflict_count_value + 1;
      continue;
    end if;
    authorization_value := fitmatch_vnext.authorize_comparison_with_context(
      reference_row.id, p_target_product_id, size_row.product_size_id,
      p_manual_explicit, effective_value, p_requested_group_code
    );
    if not coalesce((authorization_value->>'allowed')::boolean, false) then
      rejected_reason_code_value := coalesce(
        rejected_reason_code_value, authorization_value->>'reason_code'
      );
      continue;
    end if;
    comparison_measurements_value := fitmatch_vnext.comparison_evidence_20260908(
      reference_row.id, authorization_value->>'policy_code', canonical_value
    );
    if jsonb_array_length(comparison_measurements_value) < 1 then continue; end if;
    candidate_value := jsonb_build_object(
      'product_size_id', size_row.product_size_id,
      'size_label', size_row.size_label,
      'availability', jsonb_build_object(
        'status', size_row.availability_status,
        'observed_at', size_row.availability_observed_at,
        'valid_until', size_row.availability_valid_until,
        'evidence_fingerprint', size_row.availability_evidence_fingerprint
      ),
      'canonical_measurements', canonical_value,
      'comparison_measurements', comparison_measurements_value,
      'authorization', authorization_value
    );
    candidates_value := candidates_value || jsonb_build_array(candidate_value);
    fingerprint_candidates_value := fingerprint_candidates_value
      || jsonb_build_array(candidate_value - 'availability');
  end loop;

  authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
    reference_row.id::text, p_target_product_id::text,
    p_target_variant_id::text, p_manual_explicit::text,
    effective_value->>'effective_authority_fingerprint',
    fingerprint_candidates_value::text, authority_version_value
  ), 'sha256'), 'hex');

  return jsonb_build_object(
    'allowed', jsonb_array_length(candidates_value) > 0,
    'decision', case when jsonb_array_length(candidates_value) > 0
      then 'MANUAL_EXTENDED' else 'BLOCKED' end,
    'reason_code', case when jsonb_array_length(candidates_value) > 0
      then 'USER_SELECTED_REFERENCE'
      else coalesce(rejected_reason_code_value, 'NO_ELIGIBLE_TARGET_SIZE') end,
    'mode', case when jsonb_array_length(candidates_value) > 0
      then 'MANUAL_EXTENDED' else 'NONE' end,
    'reason', case when jsonb_array_length(candidates_value) > 0
      then 'Database-generated eligible candidate set'
      when semantic_conflict_count_value > 0
      then 'Canonical measurement semantic conflict'
      else 'No size satisfies comparison authorization and measurement minimums' end,
    'reference_closet_item_id', reference_row.id,
    'target_product_id', p_target_product_id,
    'target_variant_id', p_target_variant_id,
    'manual_explicit', p_manual_explicit,
    'classification_source', effective_value->>'effective_source',
    'effective_authority_fingerprint',
      effective_value->>'effective_authority_fingerprint',
    'override_revision', effective_value->'override_revision',
    'authorized_candidate_product_size_ids', coalesce((
      select jsonb_agg(candidate->'product_size_id')
      from jsonb_array_elements(candidates_value) candidate
    ), '[]'::jsonb),
    'candidates', candidates_value,
    'target_comparison_group', context_value->'target_comparison_group',
    'candidate_authority_fingerprint', authority_fingerprint_value,
    'candidate_authority_version', authority_version_value,
    'diagnostics', jsonb_build_object(
      'semantic_conflict_count', semantic_conflict_count_value,
      'inventory_ignored_for_eligibility', true
    )
  );
end
$function$

;
do $$ declare r jsonb; begin
 r:=fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004');
 if r->>'candidate_count' <> '0' then raise exception 'Old F cross-group rejection not reproduced'; end if;
end $$;
\ir ../explicit_cross_group_comparison_Apply.sql
-- Run in a disposable fixture database only. The caller is synthetic.
do $$
declare r jsonb; a jsonb; ctx jsonb;
begin
 r:=fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004');
 if r->>'candidate_count'<>'2' or r->>'same_group_count'<>'0' then raise exception 'F without same-group: %',r; end if;
 if exists(select 1 from jsonb_array_elements(r->'candidates') c where c->>'decision'<>'MANUAL_EXTENDED' or c->>'same_comparison_group'<>'false' or jsonb_array_length(c->'eligible_product_size_ids')<>1) then raise exception 'Wrong cross-group candidate contract'; end if;
 r:=fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004','F');
 if r->>'candidate_count'<>'2' then raise exception 'Session F cross-group: %',r; end if;
 if exists(select 1 from jsonb_array_elements(r->'candidates') c where c->>'same_comparison_group'<>'false') then raise exception 'Cross-group mislabeled same'; end if;
 ctx:=fitmatch_vnext.comparison_target_context('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004','F')->'effective_classification';
 a:=fitmatch_vnext.authorize_comparison_with_context_v1('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000005',false,ctx,'F');
 if a->>'allowed'<>'false' then raise exception 'Implicit session cross accepted'; end if;
 a:=fitmatch_vnext.authorize_comparison_with_context_v1('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000005',true,'{}','F');
 if a->>'allowed'<>'false' then raise exception 'Forged session accepted'; end if;
end $$;
begin;
update fitmatch_vnext.products set comparison_group_code='A',garment_type_code='top';
do $$ declare r jsonb; begin
 r:=fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004');
 if r->>'candidate_count'<>'2' or r->>'same_group_count'<>'1' then raise exception 'A with A+B Closet: %',r; end if;
end $$;
rollback;
begin;
update fitmatch_vnext.closet_items set user_id='00000000-0000-0000-0000-000000000009';
do $$ declare r jsonb; begin
 r:=fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004');
 if r->>'candidate_count'<>'0' then raise exception 'Foreign Closet leaked'; end if;
end $$;
rollback;
begin;
create or replace function fitmatch_vnext.product_comparison_unit_decision(uuid) returns jsonb language sql as $$ select '{"eligible":false,"reason":"Synthetic set"}'::jsonb $$;
do $$ declare r jsonb; begin
 r:=fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004');
 if r->>'candidate_count'<>'0' then raise exception 'Structurally excluded target accepted'; end if;
end $$;
rollback;
select 'PASS: mapped A/B, F without same group, session F, zero common metrics, explicit selection, forged context, ownership, structure' result;
