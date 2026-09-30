\set ON_ERROR_STOP on
CREATE SCHEMA auth;
CREATE SCHEMA fitmatch_vnext;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.user_id',true),'')::uuid $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
\ir 20260924_performance_tables_fixture.sql
CREATE SEQUENCE public.base_calls MINVALUE 0 START 0;
CREATE SEQUENCE public.context_calls MINVALUE 0 START 0;
CREATE SEQUENCE public.readiness_calls MINVALUE 0 START 0;
CREATE FUNCTION fitmatch_vnext.effective_target_classification(uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT jsonb_build_object('effective_source', classification_status) FROM fitmatch_vnext.products WHERE id=$1 $$;
CREATE FUNCTION fitmatch_vnext.canonical_measurements_for_size(uuid) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN PERFORM nextval('public.base_calls'); RETURN jsonb_build_object('size',$1,'basis','base'); END $$;
CREATE FUNCTION fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN PERFORM nextval('public.context_calls'); RETURN jsonb_build_object('size',$1,'basis','context','classification',$2); END $$;
CREATE FUNCTION fitmatch_vnext.product_measurement_readiness(uuid,jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN PERFORM nextval('public.readiness_calls'); RETURN jsonb_build_object('product',$1,'context',$2,'ready',true); END $$;
CREATE FUNCTION fitmatch_vnext.product_comparison_unit_decision(uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"eligible":true}'::jsonb $$;
CREATE FUNCTION fitmatch_vnext.closet_comparison_group(uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('id',$1,'group_code','A') $$;
\ir 20260924_performance_before_fixture.sql
SELECT set_config('app.user_id','10000000-0000-0000-0000-000000000001',false);
INSERT INTO fitmatch_vnext.garment_types(garment_type_code,category_code,comparison_policy_code,is_active) VALUES ('shirt','tops','tops_v1',true);
INSERT INTO fitmatch_vnext.products(id,source_code,source_product_key,garment_type_code,classification_status,source_extra)
VALUES ('20000000-0000-0000-0000-000000000001','uniqlo','fixture','shirt','GLOBAL_CONFIRMED','{"source_category_path":"official path"}');
INSERT INTO fitmatch_vnext.product_variants(id,product_id,source_variant_key,sort_order) VALUES ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','color07',1);
INSERT INTO fitmatch_vnext.product_sizes(id,variant_id,source_size_key,size_label,sort_order)
VALUES ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','M','M',1),('40000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001','L','L',2);
INSERT INTO fitmatch_vnext.closet_items(id,user_id,client_item_id,product_id,product_variant_id,product_size_id,garment_type_code,closet_detail_code_snapshot,created_at)
SELECT ('50000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 CASE WHEN i=3 THEN '10000000-0000-0000-0000-000000000002'::uuid ELSE auth.uid() END,
 ('60000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 '20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','shirt','blouse','2026-09-24Z'::timestamptz FROM generate_series(1,3) i;
INSERT INTO fitmatch_vnext.closet_item_source_measurements(closet_item_id,raw_measurement_key,source_code,parser_code,raw_code,raw_label,raw_value,raw_value_text,raw_unit_code,evidence_payload)
VALUES ('50000000-0000-0000-0000-000000000001','unknown','uniqlo','fixture','future-field','future-field',44,'44.0','cm','{"unknown":"preserve"}');
INSERT INTO fitmatch_vnext.closet_item_source_measurement_snapshots(closet_item_id,source_observation_id,product_id,product_variant_id,product_size_id,source_measurement_count)
VALUES ('50000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',1);
INSERT INTO fitmatch_vnext.closet_item_measurements(closet_item_id,fitmatch_measurement_code,source_measurement_code_snapshot,value,unit_code)
VALUES ('50000000-0000-0000-0000-000000000001','chest_width','source.chest',50,'cm');
CREATE TABLE expected AS SELECT public.fitmatch_vnext_list_closet_items() items,
 fitmatch_vnext.get_product_runtime('uniqlo','fixture') base,
 fitmatch_vnext.get_product_runtime_for_swift('uniqlo','fixture') runtime;
UPDATE fitmatch_vnext.products SET classification_status='USER_OVERRIDE';
ALTER TABLE expected ADD COLUMN overridden jsonb;
UPDATE expected SET overridden=fitmatch_vnext.get_product_runtime_for_swift('uniqlo','fixture');
UPDATE fitmatch_vnext.products SET classification_status='GLOBAL_CONFIRMED';
\ir ../../migrations/20260924120000_closet_single_item_readback.sql
\ir ../../migrations/20260924121000_runtime_skip_discarded_projections.sql
DO $$ BEGIN
 IF (SELECT items FROM expected) IS DISTINCT FROM public.fitmatch_vnext_list_closet_items() THEN RAISE EXCEPTION 'full list changed'; END IF;
 IF public.fitmatch_vnext_get_closet_item('50000000-0000-0000-0000-000000000001') IS DISTINCT FROM (SELECT jsonb_agg(v) FROM expected,jsonb_array_elements(items) v WHERE v->>'id'='50000000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'single raw/detail/canonical receipt changed'; END IF;
 IF public.fitmatch_vnext_get_closet_item('50000000-0000-0000-0000-000000000003') <> '[]'::jsonb THEN RAISE EXCEPTION 'cross user leak'; END IF;
 IF public.fitmatch_vnext_get_closet_item('99999999-0000-0000-0000-000000000000') <> '[]'::jsonb THEN RAISE EXCEPTION 'missing ID fallback'; END IF;
 IF (SELECT base FROM expected) IS DISTINCT FROM fitmatch_vnext.get_product_runtime('uniqlo','fixture') THEN RAISE EXCEPTION 'base runtime changed'; END IF;
 PERFORM setval('base_calls',0,false); PERFORM setval('context_calls',0,false); PERFORM setval('readiness_calls',0,false);
 IF (SELECT runtime FROM expected) IS DISTINCT FROM fitmatch_vnext.get_product_runtime_for_swift('uniqlo','fixture') THEN RAISE EXCEPTION 'final runtime changed'; END IF;
 IF (SELECT is_called FROM base_calls) THEN RAISE EXCEPTION 'discarded base resolution still called'; END IF;
 IF (SELECT last_value FROM context_calls) <> 1 THEN RAISE EXCEPTION 'expected two context size resolutions'; END IF;
 IF (SELECT last_value FROM readiness_calls) <> 0 OR NOT (SELECT is_called FROM readiness_calls) THEN RAISE EXCEPTION 'expected exactly one readiness'; END IF;
 IF fitmatch_vnext.get_product_runtime_for_swift('uniqlo','missing') <> '{"found":false}'::jsonb THEN RAISE EXCEPTION 'missing product contract'; END IF;
END $$;
UPDATE fitmatch_vnext.products SET classification_status='USER_OVERRIDE';
DO $$ BEGIN
 IF (SELECT overridden FROM expected) IS DISTINCT FROM fitmatch_vnext.get_product_runtime_for_swift('uniqlo','fixture') THEN RAISE EXCEPTION 'override context changed'; END IF;
END $$;
UPDATE fitmatch_vnext.closet_items SET deleted_at=now() WHERE id='50000000-0000-0000-0000-000000000002';
DO $$ BEGIN
 IF public.fitmatch_vnext_get_closet_item('50000000-0000-0000-0000-000000000002') <> '[]'::jsonb THEN RAISE EXCEPTION 'deleted receipt returned'; END IF;
 IF has_function_privilege('anon','public.fitmatch_vnext_get_closet_item(uuid)','EXECUTE') THEN RAISE EXCEPTION 'anon grant'; END IF;
END $$;
SET ROLE authenticated;
SELECT public.fitmatch_vnext_get_closet_item('50000000-0000-0000-0000-000000000001');
RESET ROLE;
SELECT set_config('app.user_id','',false);
DO $$ BEGIN
 BEGIN PERFORM public.fitmatch_vnext_get_closet_item('50000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'missing auth accepted'; EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'Authentication required' THEN RAISE; END IF; END;
END $$;
\ir ../20260924121000_runtime_skip_discarded_projections_Rollback.sql
\ir ../20260924120000_closet_single_item_readback_Rollback.sql
SELECT 'PERFORMANCE CONTRACT REGRESSION PASS' result;
