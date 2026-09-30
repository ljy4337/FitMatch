-- Run ONLY in an empty disposable local PostgreSQL database.
-- Uses the captured deployed authorization body with synthetic dependency fixtures.
\set ON_ERROR_STOP on
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
 'windbreaker','zip_hoodie') THEN 'UPPER_BODY'
 WHEN p_policy IN ('homewear_bottom','leggings','skirt','standard_pants') THEN 'LOWER_BODY'
 WHEN p_policy='dress' THEN 'FULL_BODY'
 WHEN p_policy IN ('men_briefs','men_trunks','men_undershirt','women_bra',
 'women_camisole','women_panty','women_slip') THEN 'OTHER'
 ELSE 'UNKNOWN' END;
$function$
;
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
create function public.probe() returns jsonb language sql as $$ select fitmatch_vnext.authorize_comparison_with_context_v1('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000005',true,fitmatch_vnext.effective_target_classification('00000000-0000-0000-0000-000000000003')) $$;
do $$ begin if public.probe()->>'reason_code' <> 'INCOMPATIBLE_BODY_REGION' then raise exception 'Baseline reproduction failed'; end if; end $$;
\ir ../cross_group_outerwear_domain_Apply.sql
do $$ begin
 if public.probe()->>'allowed' <> 'true' then raise exception 'A/B manual rejected'; end if;
 if fitmatch_vnext.authorize_comparison_with_context_v1('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000005',false,fitmatch_vnext.effective_target_classification('00000000-0000-0000-0000-000000000003'))->>'allowed' <> 'false' then raise exception 'Automatic cross comparison accepted'; end if;
 if fitmatch_vnext.authorize_comparison_with_context_v1('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000005',true,'{}')->>'allowed' <> 'false' then raise exception 'Forged context accepted'; end if;
end $$;
begin;
update fitmatch_vnext.closet_items set user_id='00000000-0000-0000-0000-000000000009';
do $$ begin if public.probe()->>'allowed' <> 'false' then raise exception 'Other owner accepted'; end if; end $$;
rollback;
begin;
create or replace function fitmatch_vnext.comparison_evidence_20260908(uuid,text,jsonb) returns jsonb language sql as $$ select '[]'::jsonb $$;
do $$ begin if public.probe()->>'reason_code' <> 'NO_COMMON_MEASUREMENTS' then raise exception 'Empty measurements accepted'; end if; end $$;
rollback;
select 'PASS: manual A/B, explicit selection, stale context, ownership, no common metric' result;
