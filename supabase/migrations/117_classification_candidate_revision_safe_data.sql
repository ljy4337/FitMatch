begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';
select pg_advisory_xact_lock(
  hashtext('fitmatch:classification-candidate-revision-safe-data-2026-08-26-v2')
);

-- Candidate-only, additive safe-data revision. This migration does not
-- activate/retire a release, persist product decisions, write history, or
-- change resolver/evaluator/recorder/public RPC contracts.

create or replace function
fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
returns table (value jsonb)
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $function$
  select item.value
  from jsonb_array_elements(
    $manifest$[{"record_type":"meta","manifest_version":"fitmatch-classification-candidate-revision-safe-data-2026-08-26-v1","release_id":"f83ca2f0-88a4-4430-96fc-037d6f1efcc2","release_key":"fitmatch-classification-authority-candidate-2026-08-26-v2","parent_candidate_release_id":"9f9c8155-61d9-41ce-9dd1-bf695ecc2140","production_parent_release_id":"65d72393-4a40-4e99-b701-fdc1ff865774","baseline_checksums":{"phase1b2_shadow":"b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385","review_evidence_audit":"cbcfa931a01c152f6b8205cf26a3d2696af73ad5b3ec0f9585f52831eec81ddb","conflict_cohorts":"1c7e332d7b3ec44f1157c1f919c4f7626ef096b582caa2c68b1ed596402e465b","db_only_105":"c786470b1123efa9d7651c5a8a913aed073509135f6a679dc63a69e4bbc3229c","invalid_mapping_rows":"660471260f5d544c5a307f95c85113a0fd637b36541e0d4b36eb07224c90cc25","remediation_plan":"e6b26efe743520b3627bf97492dd93c68958eafddd3c66399b1fd823c71c132c"},"approved_counts":{"target_clone_rows":17,"target_clone_products":84,"exact_decisions":2,"product_required_rows":10,"product_required_products":25,"revoke_rows":30,"revoke_products":75},"unapproved_parity":{"vocabulary_translation_products":7,"invalid_vocabulary_rows":24,"invalid_vocabulary_products":71,"unresolved_conflict_products":717,"structured_typed_signal_products":212,"name_add_signal_products":246,"clean_name_only_products":47},"component_checksums":{"target_clones":"1ee945ca971751f01daeeaa85b062d05ca2e1bf7fb906dfa17e1dd1b437c01bc","product_decisions":"0a698ee9856fdf385c1f453e027de017fd9cff6bf5c39d0c0f493c51346e24b5","product_required":"b1100c7c2be380c06cabc17c8030c87435c9cc5ea148d01d41ead7ba07f5d305","revoke_no_replacement":"990c71904a8d1ce0dce6a8b0f01f79b81190b97dec1dfa5b038b7762c3e7a719","untouched_invalid_vocabulary":"9281ac77b9c584462ffcda21a1704fda8f65b7e03c1b11f53662562dbd9f36ee"},"input_checksums":{"remediation_plan":"e6b26efe743520b3627bf97492dd93c68958eafddd3c66399b1fd823c71c132c","invalid_mapping_rows":"660471260f5d544c5a307f95c85113a0fd637b36541e0d4b36eb07224c90cc25"},"generated_at":"2026-08-26T00:00:00+09:00","production_apply_performed":false},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-bac3a82cd1bd","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|M,W|상의 > 반소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|UNKNOWN|상의 > 반소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001001","target":"M,W","normalized_path":"상의 > 반소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6833448","musinsa:6839271"],"affected_product_count":2,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-33c7c50c9ba0","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|M|상의 > 반소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|UNKNOWN|상의 > 반소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001001","target":"M","normalized_path":"상의 > 반소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:4971043","musinsa:5922490","musinsa:6590793","musinsa:6677115","musinsa:6850912","musinsa:6852823","musinsa:6858118","musinsa:6888542","musinsa:6896783","musinsa:6927386","musinsa:6939618"],"affected_product_count":11,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-c495d744ebe1","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|MEN|상의 > 반소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|UNKNOWN|상의 > 반소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001001","target":"MEN","normalized_path":"상의 > 반소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:4059353","musinsa:4739114","musinsa:6453592","musinsa:6609390","musinsa:6656624","musinsa:6656633","musinsa:6673687","musinsa:6693866","musinsa:6704378","musinsa:6708096","musinsa:6708161","musinsa:6708755","musinsa:6723404","musinsa:6760735","musinsa:6789405","musinsa:6945858"],"affected_product_count":16,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-ca43500c6e19","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|W|상의 > 반소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|UNKNOWN|상의 > 반소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001001","target":"W","normalized_path":"상의 > 반소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:4341120","musinsa:6618666","musinsa:6697403","musinsa:6778715","musinsa:6778769","musinsa:6805433"],"affected_product_count":6,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-3e66f39c13c7","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|WOMEN|상의 > 반소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|UNKNOWN|상의 > 반소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001001","target":"WOMEN","normalized_path":"상의 > 반소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:3132891","musinsa:3182421","musinsa:6200629","musinsa:6408788","musinsa:6666875","musinsa:6687292","musinsa:6689505","musinsa:6693832","musinsa:6696689","musinsa:6706361","musinsa:6709666","musinsa:6709673","musinsa:6715231","musinsa:6722931","musinsa:6732631","musinsa:6737107","musinsa:6755261","musinsa:6761404","musinsa:6768741","musinsa:6774915","musinsa:6778749","musinsa:6797265","musinsa:6797266","musinsa:6797271"],"affected_product_count":24,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-77257942b772","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001010|M|상의 > 긴소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001010|UNKNOWN|상의 > 긴소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001010","target":"M","normalized_path":"상의 > 긴소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"long_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"long_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6686260"],"affected_product_count":1,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-4471218b3968","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001010|MEN|상의 > 긴소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001010|UNKNOWN|상의 > 긴소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001010","target":"MEN","normalized_path":"상의 > 긴소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"long_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"long_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6656593","musinsa:6656596","musinsa:6910253"],"affected_product_count":3,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-3db49ff98a2a","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001010|W|상의 > 긴소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001010|UNKNOWN|상의 > 긴소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001010","target":"W","normalized_path":"상의 > 긴소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"long_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"long_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6595807","musinsa:6595811","musinsa:6837150","musinsa:6914789"],"affected_product_count":4,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-03ecd9c36bab","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001010|WOMEN|상의 > 긴소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001010|UNKNOWN|상의 > 긴소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001010","target":"WOMEN","normalized_path":"상의 > 긴소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"long_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"long_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:5982920","musinsa:6689485"],"affected_product_count":2,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-ddc0d713f07e","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001011|MEN|상의 > 민소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001011|UNKNOWN|상의 > 민소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001011","target":"MEN","normalized_path":"상의 > 민소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"sleeveless","garment_type_code":"tank_top","family_code":"tank_top","length_code":"sleeveless","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6534177"],"affected_product_count":1,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-b071d3d5a212","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001011|W|상의 > 민소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001011|UNKNOWN|상의 > 민소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001011","target":"W","normalized_path":"상의 > 민소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"sleeveless","garment_type_code":"tank_top","family_code":"tank_top","length_code":"sleeveless","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6666754","musinsa:6716197","musinsa:6716203","musinsa:6716212","musinsa:6843694","musinsa:6876277","musinsa:6941093"],"affected_product_count":7,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-f7fc1378dc6f","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001011|WOMEN|상의 > 민소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001011|UNKNOWN|상의 > 민소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"001011","target":"WOMEN","normalized_path":"상의 > 민소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"sleeveless","garment_type_code":"tank_top","family_code":"tank_top","length_code":"sleeveless","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6515855"],"affected_product_count":1,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-4c49317e8e00","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016002|M,W|스포츠/레저 > 상의 > 긴소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016002|UNKNOWN|스포츠/레저 > 상의 > 긴소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"017016002","target":"M,W","normalized_path":"스포츠/레저 > 상의 > 긴소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"long_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"long_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6812676"],"affected_product_count":1,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-4f0257d0a7b5","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016003|M,W|스포츠/레저 > 상의 > 나시/민소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016003|UNKNOWN|스포츠/레저 > 상의 > 나시/민소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"017016003","target":"M,W","normalized_path":"스포츠/레저 > 상의 > 나시/민소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"sleeveless","garment_type_code":"tank_top","family_code":"tank_top","length_code":"sleeveless","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6842592"],"affected_product_count":1,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-04a5c89b69fb","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016003|M|스포츠/레저 > 상의 > 나시/민소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016003|UNKNOWN|스포츠/레저 > 상의 > 나시/민소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"017016003","target":"M","normalized_path":"스포츠/레저 > 상의 > 나시/민소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"sleeveless","garment_type_code":"tank_top","family_code":"tank_top","length_code":"sleeveless","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6781113"],"affected_product_count":1,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-9972f389e306","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016005|M|스포츠/레저 > 상의 > 반소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016005|UNKNOWN|스포츠/레저 > 상의 > 반소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"017016005","target":"M","normalized_path":"스포츠/레저 > 상의 > 반소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6853485","musinsa:6906711"],"affected_product_count":2,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_target_clone","change_id":"P0-MAPPING-TARGET-e095e3941590","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016005|W|스포츠/레저 > 상의 > 반소매 티셔츠","base_source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016005|UNKNOWN|스포츠/레저 > 상의 > 반소매 티셔츠","source":"musinsa","snapshot_id":"0a0fab7a-e6a6-45b9-ab5c-3426aba173e3","external_category_id":"017016005","target":"W","normalized_path":"스포츠/레저 > 상의 > 반소매 티셔츠","canonical_tuple":{"category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null},"authority_status":"verified","resolution_scope":"category_direct","product_required":false,"affected_products":["musinsa:6842612"],"affected_product_count":1,"evidence_basis":["candidate CATEGORY_DIRECT mapping independently validator-PASS","Resolver v4 target equality is exact","each affected product has exact leaf code or exact normalized path","tuple is target-independent"]},{"record_type":"approved_product_decision","change_id":"P2-DECISION-UNIQLO-E482522","source":"uniqlo","external_product_id":"E482522","product_name":"AIRism코튼크루넥T","source_category_path":"이너웨어 > 에어리즘 > 코튼","input_fingerprint":"5086248f3a902b527d44be74b044cfde","category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null,"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-authority-candidate-2026-08-26-v2","action":"COMPLETE_VERIFIED_EXACT_DECISION_TUPLE","reason":"INDEPENDENT_MANUAL_ADJUDICATION_AND_CURRENT_HISTORY_SEMANTIC_PARITY","evidence":{"independent_manual_adjudication":true,"current_history_semantic_tuple_verified":true,"active_taxonomy_inventory_verified":true,"product_name_semantic_authority_used":false,"phase1b2r_approved_safe_data_only":true,"body_length_code":null},"affected_products":["uniqlo:E482522"],"affected_product_count":1},{"record_type":"approved_product_decision","change_id":"P2-DECISION-UNIQLO-E485454","source":"uniqlo","external_product_id":"E485454","product_name":"바이컬러T","source_category_path":"Special Collaborations > UNIQLO and JW ANDERSON > Cut & Sewn","input_fingerprint":"83d40d9d3893b19c9a8c978a752a842c","category_code":"tops","detail_code":"short_sleeve","garment_type_code":"tshirt","family_code":"tshirt","length_code":"short_sleeve","body_length_code":null,"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-authority-candidate-2026-08-26-v2","action":"COMPLETE_VERIFIED_EXACT_DECISION_TUPLE","reason":"INDEPENDENT_MANUAL_ADJUDICATION_AND_CURRENT_HISTORY_SEMANTIC_PARITY","evidence":{"independent_manual_adjudication":true,"current_history_semantic_tuple_verified":true,"active_taxonomy_inventory_verified":true,"product_name_semantic_authority_used":false,"phase1b2r_approved_safe_data_only":true,"body_length_code":null},"affected_products":["uniqlo:E485454"],"affected_product_count":1},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-1392c43e9d37","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102253|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 후드","source":"uniqlo","external_category_id":"102253","target":"MEN","normalized_path":"티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 후드","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E471808"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":3},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-c35ce0796152","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128388|WOMEN|니트 & 가디건 > 가디건 > 그 외","source":"uniqlo","external_category_id":"128388","target":"WOMEN","normalized_path":"니트 & 가디건 > 가디건 > 그 외","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E484939","uniqlo:E485340","uniqlo:E485717","uniqlo:E487001","uniqlo:E491991"],"affected_product_count":5,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":5},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-d9df3083865b","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135282|WOMEN|니트 & 가디건 > 가디건 > 스무드 코튼","source":"uniqlo","external_category_id":"135282","target":"WOMEN","normalized_path":"니트 & 가디건 > 가디건 > 스무드 코튼","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E487005","uniqlo:E491115","uniqlo:E491602"],"affected_product_count":3,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":3},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-56e5b481992e","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58125|WOMEN|아우터 > 재킷 & 코트 > 캐주얼 재킷","source":"uniqlo","external_category_id":"58125","target":"WOMEN","normalized_path":"아우터 > 재킷 & 코트 > 캐주얼 재킷","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E487518","uniqlo:E487846","uniqlo:E489026"],"affected_product_count":3,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":3},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-ee2ae1d71ef9","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58611|KIDS|원피스 & 스커트 > 원피스 > 슬리브리스","source":"uniqlo","external_category_id":"58611","target":"KIDS","normalized_path":"원피스 & 스커트 > 원피스 > 슬리브리스","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E483340","uniqlo:E488976","uniqlo:E489063"],"affected_product_count":3,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":3},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-5b9e5e5ccf4f","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58691|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 쇼트팬츠","source":"uniqlo","external_category_id":"58691","target":"BABY","normalized_path":"신생아(0개월~2세) > 레깅스 & 팬츠 > 쇼트팬츠","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E481788"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":2},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-1ef375cd838f","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58716|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 쇼트팬츠","source":"uniqlo","external_category_id":"58716","target":"BABY","normalized_path":"영유아(6개월~5세) > 레깅스 & 팬츠 > 쇼트팬츠","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E481786","uniqlo:E481787","uniqlo:E481790","uniqlo:E485322"],"affected_product_count":4,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":4},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-4663e46a9d14","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95407|MEN|니트 & 가디건 > 니트 > 터틀넥","source":"uniqlo","external_category_id":"95407","target":"MEN","normalized_path":"니트 & 가디건 > 니트 > 터틀넥","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E450544"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":2},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-2bc3a5940712","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98312|WOMEN|이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드","source":"uniqlo","external_category_id":"98312","target":"WOMEN","normalized_path":"이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E469765","uniqlo:E471601","uniqlo:E480342"],"affected_product_count":3,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":4},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-26885c34eabc","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98314|WOMEN|이너웨어 > 히트텍 > 히트텍 울트라 웜","source":"uniqlo","external_category_id":"98314","target":"WOMEN","normalized_path":"이너웨어 > 히트텍 > 히트텍 울트라 웜","verdict":"SHOULD_BE_PRODUCT_REQUIRED","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"verified","resolution_scope":"product_required","product_required":true,"canonical_tuple":null},"affected_products":["uniqlo:E478965"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID",{"adjudication_bucket":"C_PRODUCT_REQUIRED","phase1b_action":"PRODUCT_LEVEL_RESOLUTION_REQUIRED","product_count":2},"no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-248a376edb7d","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002002|UNKNOWN|아우터 > 레더/라이더스 재킷","source":"musinsa","external_category_id":"002002","target":"UNKNOWN","normalized_path":"아우터 > 레더/라이더스 재킷","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["musinsa:3042005","musinsa:6565987"],"affected_product_count":2,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-5925b0a88581","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002014|UNKNOWN|아우터 > 사파리/헌팅 재킷","source":"musinsa","external_category_id":"002014","target":"UNKNOWN","normalized_path":"아우터 > 사파리/헌팅 재킷","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["musinsa:2737014"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-45b1b083f0e9","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002018|UNKNOWN|아우터 > 트레이닝 재킷","source":"musinsa","external_category_id":"002018","target":"UNKNOWN","normalized_path":"아우터 > 트레이닝 재킷","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["musinsa:4336062","musinsa:6048605","musinsa:6271693","musinsa:6686197","musinsa:6814919"],"affected_product_count":5,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-c02719b7cde9","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002022|UNKNOWN|아우터 > 후드 집업","source":"musinsa","external_category_id":"002022","target":"UNKNOWN","normalized_path":"아우터 > 후드 집업","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["musinsa:4513309","musinsa:5329359","musinsa:5329361","musinsa:5345115","musinsa:6426535","musinsa:6695701","musinsa:6721671","musinsa:6794273","musinsa:6806873","musinsa:6887357","musinsa:6896379","musinsa:6912863","musinsa:6933792"],"affected_product_count":13,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-025fb5ee626e","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100085|MEN|팬츠 > 와이드 팬츠 > UNIQLO : C","source":"uniqlo","external_category_id":"100085","target":"MEN","normalized_path":"팬츠 > 와이드 팬츠 > UNIQLO : C","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E484875"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-e6aace5d2550","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105468|WOMEN|스포츠 유틸리티 웨어 > 아우터 > 풀집 후디","source":"uniqlo","external_category_id":"105468","target":"WOMEN","normalized_path":"스포츠 유틸리티 웨어 > 아우터 > 풀집 후디","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E483281"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-c27650909742","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114926|MEN|팬츠 > 캐주얼 팬츠 > 울트라 스트레치","source":"uniqlo","external_category_id":"114926","target":"MEN","normalized_path":"팬츠 > 캐주얼 팬츠 > 울트라 스트레치","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E465206","uniqlo:E485495","uniqlo:E485744","uniqlo:E485745"],"affected_product_count":4,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-c3419dc78158","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|115519|WOMEN|UV Protection > 팬츠 & 레깅스 > 팬츠","source":"uniqlo","external_category_id":"115519","target":"WOMEN","normalized_path":"UV Protection > 팬츠 & 레깅스 > 팬츠","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E474481","uniqlo:E477869","uniqlo:E483001"],"affected_product_count":3,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-309f5ad101e9","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123533|MEN|이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드","source":"uniqlo","external_category_id":"123533","target":"MEN","normalized_path":"이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E481441","uniqlo:E481442"],"affected_product_count":2,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-5aebe494223a","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124364|WOMEN|원피스 & 스커트 > 원피스 > GU","source":"uniqlo","external_category_id":"124364","target":"WOMEN","normalized_path":"원피스 & 스커트 > 원피스 > GU","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E486699"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-59d3ba34cc8e","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124370|MEN|팬츠 > 와이드 팬츠 > GU","source":"uniqlo","external_category_id":"124370","target":"MEN","normalized_path":"팬츠 > 와이드 팬츠 > GU","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E486729"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-4b8c0aea3dae","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149935|WOMEN|팬츠 > 배럴 레그 팬츠 > 긴 기장","source":"uniqlo","external_category_id":"149935","target":"WOMEN","normalized_path":"팬츠 > 배럴 레그 팬츠 > 긴 기장","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E489417"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-d0fc190782f7","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58292|WOMEN|이너웨어 > 히트텍 > 크루넥","source":"uniqlo","external_category_id":"58292","target":"WOMEN","normalized_path":"이너웨어 > 히트텍 > 크루넥","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E469742"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-217021f5bc54","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58511|MEN|이너웨어 > 에어리즘 > 브리프 (레귤러)","source":"uniqlo","external_category_id":"58511","target":"MEN","normalized_path":"이너웨어 > 에어리즘 > 브리프 (레귤러)","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E454326","uniqlo:E480997"],"affected_product_count":2,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-9c95db7d83a6","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58512|MEN|이너웨어 > 에어리즘 > 브리프 (로라이즈)","source":"uniqlo","external_category_id":"58512","target":"MEN","normalized_path":"이너웨어 > 에어리즘 > 브리프 (로라이즈)","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E454328","uniqlo:E474321","uniqlo:E478814"],"affected_product_count":3,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-ff3f89bb0cff","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58581|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트파카","source":"uniqlo","external_category_id":"58581","target":"KIDS","normalized_path":"티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트파카","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E488939"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-d37b0ed6f701","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58603|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 스트레치 팬츠","source":"uniqlo","external_category_id":"58603","target":"KIDS","normalized_path":"청바지 & 팬츠 > 청바지 & 팬츠 > 스트레치 팬츠","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E479575"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-be57405193b8","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58608|KIDS|청바지 & 팬츠 > 반바지 > 스커트 팬츠","source":"uniqlo","external_category_id":"58608","target":"KIDS","normalized_path":"청바지 & 팬츠 > 반바지 > 스커트 팬츠","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E483329","uniqlo:E483394","uniqlo:E484064","uniqlo:E484924","uniqlo:E486220","uniqlo:E487273","uniqlo:E488738","uniqlo:E489065"],"affected_product_count":8,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-0fc691c42606","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58612|KIDS|원피스 & 스커트 > 원피스 > 반팔","source":"uniqlo","external_category_id":"58612","target":"KIDS","normalized_path":"원피스 & 스커트 > 원피스 > 반팔","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E488239"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-b2750de7a542","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58672|BABY|신생아(0개월~2세) > 바디수트 > 코튼","source":"uniqlo","external_category_id":"58672","target":"BABY","normalized_path":"신생아(0개월~2세) > 바디수트 > 코튼","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E466434"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-136f9530b986","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58673|BABY|신생아(0개월~2세) > 바디수트 > 코튼메쉬","source":"uniqlo","external_category_id":"58673","target":"BABY","normalized_path":"신생아(0개월~2세) > 바디수트 > 코튼메쉬","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E444812","uniqlo:E481761","uniqlo:E481764","uniqlo:E481769"],"affected_product_count":4,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-2e0e98b78bac","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58674|BABY|신생아(0개월~2세) > 바디수트 > 긴팔","source":"uniqlo","external_category_id":"58674","target":"BABY","normalized_path":"신생아(0개월~2세) > 바디수트 > 긴팔","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E486367","uniqlo:E486378","uniqlo:E486380","uniqlo:E488861","uniqlo:E489526","uniqlo:E489530"],"affected_product_count":6,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-83f7aeca0d4d","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58675|BABY|신생아(0개월~2세) > 바디수트 > 반팔","source":"uniqlo","external_category_id":"58675","target":"BABY","normalized_path":"신생아(0개월~2세) > 바디수트 > 반팔","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E481772","uniqlo:E487909"],"affected_product_count":2,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-cf273ab54928","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58719|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 롱팬츠","source":"uniqlo","external_category_id":"58719","target":"BABY","normalized_path":"영유아(6개월~5세) > 레깅스 & 팬츠 > 롱팬츠","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E487375"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-d81947a0081b","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62687|MEN|팬츠 > 캐주얼 팬츠 > 리넨","source":"uniqlo","external_category_id":"62687","target":"MEN","normalized_path":"팬츠 > 캐주얼 팬츠 > 리넨","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E482920"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-6e6f87ba0257","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62974|MEN|팬츠 > 캐주얼 팬츠 > 웜 팬츠","source":"uniqlo","external_category_id":"62974","target":"MEN","normalized_path":"팬츠 > 캐주얼 팬츠 > 웜 팬츠","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E487261","uniqlo:E487263"],"affected_product_count":2,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-e534b5b6a4c4","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63085|WOMEN|팬츠 > 캐주얼 팬츠 > 유니섹스","source":"uniqlo","external_category_id":"63085","target":"WOMEN","normalized_path":"팬츠 > 캐주얼 팬츠 > 유니섹스","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E488739"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-5e88d456a8d2","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94952|WOMEN|아우터 > 재킷 & 코트 > 재킷","source":"uniqlo","external_category_id":"94952","target":"WOMEN","normalized_path":"아우터 > 재킷 & 코트 > 재킷","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E488652","uniqlo:E489025"],"affected_product_count":2,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-91d89242b5ed","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96140|WOMEN|팬츠 > 와이드 팬츠 > 이지(허리 밴딩)","source":"uniqlo","external_category_id":"96140","target":"WOMEN","normalized_path":"팬츠 > 와이드 팬츠 > 이지(허리 밴딩)","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E473791","uniqlo:E486982"],"affected_product_count":2,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"approved_mapping_disposition","change_id":"P3-INVALID-MAPPING-6d0070235188","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98372|MEN|이너웨어 > 히트텍 > 히트텍 울트라 웜","source":"uniqlo","external_category_id":"98372","target":"MEN","normalized_path":"이너웨어 > 히트텍 > 히트텍 울트라 웜","verdict":"SHOULD_BE_REVOKED_NO_REPLACEMENT","current_bucket":"INVALID_MAPPING","current_authority_status":"revoked","proposed_state":{"authority_status":"revoked","resolution_scope":"invalid_mapping","decision_status":"review_required","mapping_status":"revoked","runtime_lookup_eligible":false,"eligibility":false,"replacement_tuple":null,"preserve_fail_closed":true},"affected_products":["uniqlo:E479525"],"affected_product_count":1,"replacement_tuple":null,"evidence_basis":["Phase1A5 G_INVALID","no verified mixed-bucket replacement","no complete verified replacement tuple"]},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002020|UNKNOWN|아우터 > 카디건","source":"musinsa","external_category_id":"002020","target":"UNKNOWN","normalized_path":"아우터 > 카디건","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["musinsa:3972476","musinsa:4651436","musinsa:5070728","musinsa:5104486","musinsa:5178636","musinsa:5283519","musinsa:5626716","musinsa:5695795","musinsa:5980112","musinsa:6127741","musinsa:6127744","musinsa:6174464","musinsa:6227070","musinsa:6273570","musinsa:6291325","musinsa:6314223","musinsa:6319969","musinsa:6326050","musinsa:6401860","musinsa:6401861","musinsa:6402661","musinsa:6458651","musinsa:6499914","musinsa:6593581","musinsa:6595041","musinsa:6596161","musinsa:6837147"],"affected_product_count":27,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018015|UNKNOWN|스포츠/레저 > 아우터 > 하프 패딩/하프 헤비 아우터","source":"musinsa","external_category_id":"017018015","target":"UNKNOWN","normalized_path":"스포츠/레저 > 아우터 > 하프 패딩/하프 헤비 아우터","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["musinsa:6929142","musinsa:6929984"],"affected_product_count":2,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100100|KIDS|이너웨어 > 히트텍 > 레깅스","source":"uniqlo","external_category_id":"100100","target":"KIDS","normalized_path":"이너웨어 > 히트텍 > 레깅스","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E478637"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116336|WOMEN|니트 & 가디건 > 니트 > 폴로 니트","source":"uniqlo","external_category_id":"116336","target":"WOMEN","normalized_path":"니트 & 가디건 > 니트 > 폴로 니트","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E484607","uniqlo:E485224"],"affected_product_count":2,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128382|WOMEN|니트 & 가디건 > 가디건 > 메리노","source":"uniqlo","external_category_id":"128382","target":"WOMEN","normalized_path":"니트 & 가디건 > 가디건 > 메리노","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E469411"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128384|WOMEN|니트 & 가디건 > 가디건 > 캐시미어","source":"uniqlo","external_category_id":"128384","target":"WOMEN","normalized_path":"니트 & 가디건 > 가디건 > 캐시미어","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E485329"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128427|MEN|니트 & 가디건 > 가디건 > 수플레 얀","source":"uniqlo","external_category_id":"128427","target":"MEN","normalized_path":"니트 & 가디건 > 가디건 > 수플레 얀","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E487942"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135281|WOMEN|니트 & 가디건 > 가디건 > UV Protection","source":"uniqlo","external_category_id":"135281","target":"WOMEN","normalized_path":"니트 & 가디건 > 가디건 > UV Protection","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E465484"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136609|WOMEN|니트 & 가디건 > 가디건 > 브이넥","source":"uniqlo","external_category_id":"136609","target":"WOMEN","normalized_path":"니트 & 가디건 > 가디건 > 브이넥","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E484938","uniqlo:E489398","uniqlo:E489399"],"affected_product_count":3,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141498|WOMEN|이너웨어 > 코튼 이너탑 > 캐미솔","source":"uniqlo","external_category_id":"141498","target":"WOMEN","normalized_path":"이너웨어 > 코튼 이너탑 > 캐미솔","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E485709","uniqlo:E485710","uniqlo:E485711","uniqlo:E487121","uniqlo:E489044"],"affected_product_count":5,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141499|WOMEN|이너웨어 > 코튼 이너탑 > 탱크탑","source":"uniqlo","external_category_id":"141499","target":"WOMEN","normalized_path":"이너웨어 > 코튼 이너탑 > 탱크탑","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E485610","uniqlo:E487118","uniqlo:E487119","uniqlo:E487120","uniqlo:E489483"],"affected_product_count":5,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58154|WOMEN|티셔츠 & UT > 스웨트셔츠 & 후드집업 > 스웨트셔츠","source":"uniqlo","external_category_id":"58154","target":"WOMEN","normalized_path":"티셔츠 & UT > 스웨트셔츠 & 후드집업 > 스웨트셔츠","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E487585"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58274|WOMEN|이너웨어 > 에어리즘 > 탱크탑","source":"uniqlo","external_category_id":"58274","target":"WOMEN","normalized_path":"이너웨어 > 에어리즘 > 탱크탑","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E457912"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58275|WOMEN|이너웨어 > 에어리즘 > 캐미솔","source":"uniqlo","external_category_id":"58275","target":"WOMEN","normalized_path":"이너웨어 > 에어리즘 > 캐미솔","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E482148"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58401|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 스웨트셔츠","source":"uniqlo","external_category_id":"58401","target":"MEN","normalized_path":"티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 스웨트셔츠","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E475800","uniqlo:E480346","uniqlo:E481040"],"affected_product_count":3,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58407|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > (X)그래픽 스웨트","source":"uniqlo","external_category_id":"58407","target":"MEN","normalized_path":"티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > (X)그래픽 스웨트","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E486295","uniqlo:E489074","uniqlo:E489075","uniqlo:E489076"],"affected_product_count":4,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58635|KIDS|이너웨어 > 에어리즘 > 탱크탑","source":"uniqlo","external_category_id":"58635","target":"KIDS","normalized_path":"이너웨어 > 에어리즘 > 탱크탑","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E481951"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58636|KIDS|이너웨어 > 에어리즘 > 캐미솔","source":"uniqlo","external_category_id":"58636","target":"KIDS","normalized_path":"이너웨어 > 에어리즘 > 캐미솔","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E481994"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95370|WOMEN|니트 & 가디건 > 니트 > 3D 니트","source":"uniqlo","external_category_id":"95370","target":"WOMEN","normalized_path":"니트 & 가디건 > 니트 > 3D 니트","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E485321"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95375|WOMEN|니트 & 가디건 > 니트 > 가디건","source":"uniqlo","external_category_id":"95375","target":"WOMEN","normalized_path":"니트 & 가디건 > 니트 > 가디건","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E476975"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95376|WOMEN|니트 & 가디건 > 니트 > 크루넥 니트","source":"uniqlo","external_category_id":"95376","target":"WOMEN","normalized_path":"니트 & 가디건 > 니트 > 크루넥 니트","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E465734","uniqlo:E485318"],"affected_product_count":2,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95378|WOMEN|니트 & 가디건 > 니트 > 터틀넥","source":"uniqlo","external_category_id":"95378","target":"WOMEN","normalized_path":"니트 & 가디건 > 니트 > 터틀넥","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E465735"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95379|WOMEN|니트 & 가디건 > 니트 > 유니섹스","source":"uniqlo","external_category_id":"95379","target":"WOMEN","normalized_path":"니트 & 가디건 > 니트 > 유니섹스","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E450540"],"affected_product_count":1,"approved_for_change":false},{"record_type":"unapproved_invalid_vocabulary_parity","source_identity":"uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95405|MEN|니트 & 가디건 > 니트 > 크루넥 니트","source":"uniqlo","external_category_id":"95405","target":"MEN","normalized_path":"니트 & 가디건 > 니트 > 크루넥 니트","verdict":"TAXONOMY_VOCABULARY_REPAIR","expected_authority_status":"revoked","expected_resolution_scope":"invalid_mapping","replacement_tuple":null,"affected_products":["uniqlo:E450535","uniqlo:E450543","uniqlo:E453754","uniqlo:E482321"],"affected_product_count":4,"approved_for_change":false}]$manifest$::jsonb
  ) item(value)
$function$;

create or replace function
fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
returns table (
  source text,
  external_product_id text,
  product_name text,
  source_category_path text,
  input_fingerprint text,
  category_code text,
  detail_code text,
  garment_type_code text,
  family_code text,
  length_code text,
  body_length_code text,
  authority_status text,
  requires_user_confirmation boolean,
  decision_version text,
  action text,
  reason text,
  evidence jsonb
)
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $function$
  select *
  from fitmatch_catalog.runtime_classification_candidate_decision_manifest_v1()
  union all
  select
    row.value->>'source',
    row.value->>'external_product_id',
    row.value->>'product_name',
    row.value->>'source_category_path',
    row.value->>'input_fingerprint',
    row.value->>'category_code',
    row.value->>'detail_code',
    row.value->>'garment_type_code',
    row.value->>'family_code',
    row.value->>'length_code',
    nullif(row.value->>'body_length_code', ''),
    row.value->>'authority_status',
    (row.value->>'requires_user_confirmation')::boolean,
    row.value->>'decision_version',
    row.value->>'action',
    row.value->>'reason',
    row.value->'evidence'
  from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
    row
  where row.value->>'record_type' = 'approved_product_decision'
$function$;

create or replace function
fitmatch_catalog.runtime_classification_candidate_revision_mapping_manifest_v2()
returns table (
  source_identity text,
  source text,
  external_category_id text,
  target text,
  normalized_path text,
  bucket text,
  authority_status text,
  resolution_scope text,
  product_required boolean,
  reason_codes jsonb,
  phase1a5_action text
)
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $function$
  with dispositions as (
    select row.value as row
    from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
      row
    where row.value->>'record_type' = 'approved_mapping_disposition'
  )
  select
    base.source_identity,
    base.source,
    base.external_category_id,
    base.target,
    base.normalized_path,
    case
      when disposition.row->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED'
        then 'PRODUCT_REQUIRED'
      else base.bucket
    end,
    case
      when disposition.row->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED'
        then 'verified'
      else base.authority_status
    end,
    case
      when disposition.row->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED'
        then 'product_required'
      else base.resolution_scope
    end,
    case
      when disposition.row->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED'
        then true
      else base.product_required
    end,
    case
      when disposition.row->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED'
        then coalesce(base.reason_codes, '[]'::jsonb)
          || jsonb_build_array('product_level_resolution_required')
      else base.reason_codes
    end,
    case
      when disposition.row->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED'
        then 'PRODUCT_LEVEL_RESOLUTION_REQUIRED'
      else base.phase1a5_action
    end
  from fitmatch_catalog.runtime_classification_candidate_mapping_manifest_v1()
    base
  left join dispositions disposition
    on disposition.row->>'source_identity' = base.source_identity
  union all
  select
    row.value->>'source_identity',
    row.value->>'source',
    row.value->>'external_category_id',
    row.value->>'target',
    row.value->>'normalized_path',
    'CATEGORY_DIRECT',
    'verified',
    'category_direct',
    false,
    '[]'::jsonb,
    'CLONE_VERIFIED_CATEGORY_DIRECT_OBSERVED_TARGET'
  from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
    row
  where row.value->>'record_type' = 'approved_target_clone'
$function$;

revoke all on function
  fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
  from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
  from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_classification_candidate_revision_mapping_manifest_v2()
  from public, anon, authenticated;
grant execute on function
  fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
  to service_role;
grant execute on function
  fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
  to service_role;
grant execute on function
  fitmatch_catalog.runtime_classification_candidate_revision_mapping_manifest_v2()
  to service_role;

do $$
declare
  v_active_release_id uuid;
begin
  select id into v_active_release_id
  from fitmatch_catalog.releases
  where status = 'active';
  if v_active_release_id is distinct from
      '65d72393-4a40-4e99-b701-fdc1ff865774'::uuid then
    raise exception 'phase1b2r_active_parent_drift:%', v_active_release_id;
  end if;
  if not exists (
      select 1
      from fitmatch_catalog.releases
      where id = '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'::uuid
        and release_key =
          'fitmatch-classification-authority-candidate-2026-08-26-v1'
        and status = 'validated'
        and expected_mapping_count = 3492
        and expected_qa_count = 1608
    )
    or (select count(*)
        from fitmatch_catalog.source_category_mappings
        where release_id =
          '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'::uuid) <> 3492
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
          manifest(value)
        where value->>'record_type' = 'approved_target_clone') <> 17
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
          manifest(value)
        where value->>'record_type' = 'approved_product_decision') <> 2
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
          manifest(value)
        where value->>'record_type' = 'approved_mapping_disposition'
          and value->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED') <> 10
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
          manifest(value)
        where value->>'record_type' = 'approved_mapping_disposition'
          and value->>'verdict' =
            'SHOULD_BE_REVOKED_NO_REPLACEMENT') <> 30
    or (select count(*)
        from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
          manifest(value)
        where value->>'record_type' =
          'unapproved_invalid_vocabulary_parity') <> 24 then
    raise exception 'phase1b2r_precondition_or_manifest_count_mismatch';
  end if;
end $$;

insert into fitmatch_catalog.releases (
  id,
  release_key,
  taxonomy_version,
  policy_version,
  status,
  bundle_checksum,
  app_taxonomy_checksum,
  expected_mapping_count,
  expected_qa_count,
  metadata,
  validated_at,
  validation_contract_version,
  validation_report
)
select
  'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid,
  'fitmatch-classification-authority-candidate-2026-08-26-v2',
  parent.taxonomy_version,
  parent.policy_version,
  'validated',
  '997f8fca3726ef38b728e5bc0c2e2dcd4cb72e578a70d3a26d3d3fda6aee3f16',
  parent.app_taxonomy_checksum,
  3509,
  1608,
  jsonb_build_object(
    'phase', 'Phase 1B-2R',
    'candidate_only', true,
    'local_validation_only', true,
    'parent_candidate_release_id', parent.id,
    'production_parent_release_id',
      '65d72393-4a40-4e99-b701-fdc1ff865774',
    'production_activation_performed', false,
    'approved_safe_data_only', true,
    'decision_write_requires_controlled_activation', true
  ),
  now(),
  'fitmatch-release-gate-v2',
  jsonb_build_object(
    'runtime_policy_contract',
      parent.validation_report->'runtime_policy_contract',
    'classifier_policy_checksum',
      parent.validation_report->>'classifier_policy_checksum',
    'comparison_policy_checksum',
      parent.validation_report->>'comparison_policy_checksum',
    'compatibility_rule_checksum',
      parent.validation_report->>'compatibility_rule_checksum',
    'measurement_policy_checksum',
      parent.validation_report->>'measurement_policy_checksum',
    'runtime_policy_contract_validated', true,
    'baseline_checksums', jsonb_build_object(
      'phase1b2_shadow',
        'b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385',
      'review_evidence_audit',
        'cbcfa931a01c152f6b8205cf26a3d2696af73ad5b3ec0f9585f52831eec81ddb',
      'conflict_cohorts',
        '1c7e332d7b3ec44f1157c1f919c4f7626ef096b582caa2c68b1ed596402e465b',
      'db_only_105',
        'c786470b1123efa9d7651c5a8a913aed073509135f6a679dc63a69e4bbc3229c',
      'invalid_mapping_rows',
        '660471260f5d544c5a307f95c85113a0fd637b36541e0d4b36eb07224c90cc25',
      'remediation_plan',
        'e6b26efe743520b3627bf97492dd93c68958eafddd3c66399b1fd823c71c132c'
    ),
    'revision_manifest_checksum',
      '997f8fca3726ef38b728e5bc0c2e2dcd4cb72e578a70d3a26d3d3fda6aee3f16',
    'target_clone_count', 17,
    'target_clone_product_count', 84,
    'target_clone_checksum',
      '1ee945ca971751f01daeeaa85b062d05ca2e1bf7fb906dfa17e1dd1b437c01bc',
    'targeted_decision_count', 116,
    'approved_decision_delta_count', 2,
    'approved_decision_delta_checksum',
      '0a698ee9856fdf385c1f453e027de017fd9cff6bf5c39d0c0f493c51346e24b5',
    'product_required_count', 10,
    'product_required_product_count', 25,
    'product_required_checksum',
      'b1100c7c2be380c06cabc17c8030c87435c9cc5ea148d01d41ead7ba07f5d305',
    'revoke_count', 30,
    'revoke_product_count', 75,
    'revoke_checksum',
      '990c71904a8d1ce0dce6a8b0f01f79b81190b97dec1dfa5b038b7762c3e7a719',
    'unresolved_vocabulary_row_count', 24,
    'unresolved_vocabulary_product_count', 71,
    'unresolved_vocabulary_checksum',
      '9281ac77b9c584462ffcda21a1704fda8f65b7e03c1b11f53662562dbd9f36ee'
  ) || jsonb_build_object(
    'source_mapping_count', 3509,
    'manual_review_product_count', 1037,
    'shadow_product_count', 1608,
    'shadow_output_checksum',
      'bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916',
    'baseline_confirmed_count', 177,
    'confirmed_count', 256,
    'review_required_count', 1352,
    'required_approved_review_to_confirmed_count', 86,
    'approved_review_to_confirmed_count', 79,
    'target_clone_mapping_selected_count', 84,
    'target_clone_confirmed_count', 77,
    'target_clone_legacy_decision_conflict_count', 7,
    'target_clone_legacy_decision_conflict_products', jsonb_build_array(
      'musinsa:5982920',
      'musinsa:6515855',
      'musinsa:6534177',
      'musinsa:6781113',
      'musinsa:6797265',
      'musinsa:6797266',
      'musinsa:6797271'
    ),
    'owner_acceptance_target_met', false,
    'acceptance_result', 'PARTIAL_NO_GO',
    'unexpected_transition_count', 0,
    'gold_exact_count', 3,
    'gold_collision_count', 0,
    'confirmed_tuple_invalid_count', 0,
    'unsafe_product_required_confirm_count', 0,
    'unsafe_revoked_mapping_confirm_count', 0,
    'both_untrusted_unsafe_confirm_count', 0,
    'arbitrary_unknown_fallback_count', 0,
    'generic_underwear_auto_leak_count', 0,
    'tshirt_base_layer_auto_leak_count', 0,
    'qa_full_validation_included', true,
    'core_regression_passed', true,
    'current_behavior_parity_passed', true,
    'production_identity_verified', true,
    'label_sample_sufficiency_passed', true,
    'unsafe_auto_accept_count', 0,
    'classification_conflict_leak_count', 0,
    'measurement_alias_conflict_count', 0,
    'production_write_count', 0
  )
from fitmatch_catalog.releases parent
where parent.id = '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'::uuid
on conflict (release_key) do nothing;

do $$
begin
  if not exists (
    select 1
    from fitmatch_catalog.releases
    where id = 'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid
      and release_key =
        'fitmatch-classification-authority-candidate-2026-08-26-v2'
      and status = 'validated'
      and expected_mapping_count = 3509
      and expected_qa_count = 1608
      and validation_contract_version = 'fitmatch-release-gate-v2'
  ) then
    raise exception 'phase1b2r_release_identity_or_precondition_mismatch';
  end if;
end $$;

-- Retain every v1 candidate mapping identity and field exactly before the
-- approved per-row dispositions and observed-target additions below.
insert into fitmatch_catalog.source_category_mappings (
  release_id,
  source_identity,
  source,
  snapshot_id,
  external_category_id,
  target,
  normalized_path,
  decision_status,
  mapping_status,
  runtime_lookup_eligible,
  eligibility,
  semantic_category_code,
  semantic_garment_type,
  comparison_family,
  source_external_key,
  source_external_target_key,
  source_path_key,
  source_target_path_key,
  raw_record,
  created_at
)
select
  'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid,
  parent.source_identity,
  parent.source,
  parent.snapshot_id,
  parent.external_category_id,
  parent.target,
  parent.normalized_path,
  parent.decision_status,
  parent.mapping_status,
  parent.runtime_lookup_eligible,
  parent.eligibility,
  parent.semantic_category_code,
  parent.semantic_garment_type,
  parent.comparison_family,
  parent.source_external_key,
  parent.source_external_target_key,
  parent.source_path_key,
  parent.source_target_path_key,
  parent.raw_record,
  parent.created_at
from fitmatch_catalog.source_category_mappings parent
where parent.release_id =
  '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'::uuid
on conflict (release_id, source_identity) do nothing;

-- Approved 10-row fail-closed product-level disposition. The existing
-- semantic tuple is not treated as a replacement mapping.
update fitmatch_catalog.source_category_mappings mapping
set raw_record = mapping.raw_record || jsonb_build_object(
  'authorityContract', jsonb_build_object(
    'authorityStatus', 'verified',
    'resolutionScope', 'product_required',
    'productRequired', true,
    'contractVersion', 'classification-authority-v1'
  ),
  'phase1b2Adjudication',
    coalesce(mapping.raw_record->'phase1b2Adjudication', '{}'::jsonb)
    || jsonb_build_object(
      'bucket', 'PRODUCT_REQUIRED',
      'phase1a5Action', 'PRODUCT_LEVEL_RESOLUTION_REQUIRED',
      'reasonCodes', (
        select coalesce(jsonb_agg(reason_code order by first_ordinal),
          '[]'::jsonb)
        from (
          select reason_code, min(ordinality) first_ordinal
          from jsonb_array_elements_text(
            coalesce(mapping.raw_record#>
              '{phase1b2Adjudication,reasonCodes}', '[]'::jsonb)
            || jsonb_build_array('product_level_resolution_required')
          ) with ordinality reason(reason_code, ordinality)
          group by reason_code
        ) deduplicated
      ),
      'manifestChecksum',
        'b1100c7c2be380c06cabc17c8030c87435c9cc5ea148d01d41ead7ba07f5d305'
    ),
  'phase1b2rRevision', jsonb_build_object(
    'disposition', 'SHOULD_BE_PRODUCT_REQUIRED',
    'replacementTuple', null,
    'approvedSafeDataOnly', true
  )
)
from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
  manifest
where mapping.release_id =
    'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid
  and manifest.value->>'record_type' = 'approved_mapping_disposition'
  and manifest.value->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED'
  and mapping.source_identity = manifest.value->>'source_identity';

-- Approved 30-row physical fail-closed alignment. No replacement tuple is
-- created and the semantic columns remain byte-for-byte inherited.
update fitmatch_catalog.source_category_mappings mapping
set decision_status = 'review_required',
    mapping_status = 'revoked',
    runtime_lookup_eligible = false,
    eligibility = false,
    raw_record = mapping.raw_record || jsonb_build_object(
      'decisionStatus', 'review_required',
      'runtimeLookupEligible', false,
      'eligibility', false,
      'appMapping', coalesce(mapping.raw_record->'appMapping', '{}'::jsonb)
        || jsonb_build_object('mappingStatus', 'revoked'),
      'phase1b2rRevision', jsonb_build_object(
        'disposition', 'SHOULD_BE_REVOKED_NO_REPLACEMENT',
        'replacementTuple', null,
        'lookupEligible', false,
        'approvedSafeDataOnly', true,
        'manifestChecksum',
          '990c71904a8d1ce0dce6a8b0f01f79b81190b97dec1dfa5b038b7762c3e7a719'
      )
    )
from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
  manifest
where mapping.release_id =
    'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid
  and manifest.value->>'record_type' = 'approved_mapping_disposition'
  and manifest.value->>'verdict' =
    'SHOULD_BE_REVOKED_NO_REPLACEMENT'
  and mapping.source_identity = manifest.value->>'source_identity';

-- Approved 17 observed-target clones only. UNKNOWN remains an ordinary
-- literal target and is never converted into a wildcard.
insert into fitmatch_catalog.source_category_mappings (
  release_id,
  source_identity,
  source,
  snapshot_id,
  external_category_id,
  target,
  normalized_path,
  decision_status,
  mapping_status,
  runtime_lookup_eligible,
  eligibility,
  semantic_category_code,
  semantic_garment_type,
  comparison_family,
  source_external_key,
  source_external_target_key,
  source_path_key,
  source_target_path_key,
  raw_record,
  created_at
)
select
  'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid,
  manifest.value->>'source_identity',
  base.source,
  base.snapshot_id,
  base.external_category_id,
  manifest.value->>'target',
  base.normalized_path,
  base.decision_status,
  base.mapping_status,
  base.runtime_lookup_eligible,
  base.eligibility,
  base.semantic_category_code,
  base.semantic_garment_type,
  base.comparison_family,
  base.source_external_key,
  base.source || '|' || base.external_category_id || '|'
    || (manifest.value->>'target'),
  base.source_path_key,
  base.source || '|' || (manifest.value->>'target') || '|'
    || base.normalized_path,
  base.raw_record || jsonb_build_object(
    'target', manifest.value->>'target',
    'sourceIdentity', manifest.value->>'source_identity',
    'lookupKeys', coalesce(base.raw_record->'lookupKeys', '{}'::jsonb)
      || jsonb_build_object(
        'sourceExternalTarget',
          base.source || '|' || base.external_category_id || '|'
            || (manifest.value->>'target'),
        'sourceTargetPath',
          base.source || '|' || (manifest.value->>'target') || '|'
            || base.normalized_path
      ),
    'phase1b2Adjudication',
      coalesce(base.raw_record->'phase1b2Adjudication', '{}'::jsonb)
      || jsonb_build_object(
        'bucket', 'CATEGORY_DIRECT',
        'phase1a5Action',
          'CLONE_VERIFIED_CATEGORY_DIRECT_OBSERVED_TARGET',
        'manifestChecksum',
          '1ee945ca971751f01daeeaa85b062d05ca2e1bf7fb906dfa17e1dd1b437c01bc'
      ),
    'phase1b2rRevision', jsonb_build_object(
      'changeID', manifest.value->>'change_id',
      'baseSourceIdentity', manifest.value->>'base_source_identity',
      'approvedSafeDataOnly', true
    )
  ),
  base.created_at
from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
  manifest
join fitmatch_catalog.source_category_mappings base
  on base.release_id =
    'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid
 and base.source_identity = manifest.value->>'base_source_identity'
where manifest.value->>'record_type' = 'approved_target_clone'
on conflict (release_id, source_identity) do nothing;

create or replace function
fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(
  p_release_id uuid
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_mapping_count integer;
  v_category_direct_count integer;
  v_product_required_count integer;
  v_invalid_mapping_count integer;
  v_other_existing_count integer;
  v_mapping_identity_difference_count integer;
  v_baseline_identity_loss_count integer;
  v_unapproved_base_mismatch_count integer;
  v_clone_count integer;
  v_clone_semantic_mismatch_count integer;
  v_product_required_count_actual integer;
  v_revoke_count_actual integer;
  v_vocabulary_parity_count integer;
  v_vocabulary_mismatch_count integer;
  v_decision_match_count integer;
  v_decision_mismatch_count integer;
  v_review_issue_count integer;
  v_mapping_checksum text;
  v_decision_checksum text;
  v_blockers jsonb := '[]'::jsonb;
begin
  select * into v_release
  from fitmatch_catalog.releases
  where id = p_release_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'release_not_found';
  end if;

  select
    count(*),
    count(*) filter (where
      mapping.raw_record#>>'{phase1b2Adjudication,bucket}' =
        'CATEGORY_DIRECT'),
    count(*) filter (where
      mapping.raw_record#>>'{phase1b2Adjudication,bucket}' =
        'PRODUCT_REQUIRED'),
    count(*) filter (where
      mapping.raw_record#>>'{phase1b2Adjudication,bucket}' =
        'INVALID_MAPPING'),
    count(*) filter (where
      mapping.raw_record#>>'{phase1b2Adjudication,bucket}' =
        'OTHER_EXISTING'),
    encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'source_identity', mapping.source_identity,
      'source', mapping.source,
      'snapshot_id', mapping.snapshot_id,
      'external_category_id', mapping.external_category_id,
      'target', mapping.target,
      'normalized_path', mapping.normalized_path,
      'decision_status', mapping.decision_status,
      'mapping_status', mapping.mapping_status,
      'runtime_lookup_eligible', mapping.runtime_lookup_eligible,
      'eligibility', mapping.eligibility,
      'semantic_category_code', mapping.semantic_category_code,
      'semantic_garment_type', mapping.semantic_garment_type,
      'comparison_family', mapping.comparison_family,
      'source_external_key', mapping.source_external_key,
      'source_external_target_key', mapping.source_external_target_key,
      'source_path_key', mapping.source_path_key,
      'source_target_path_key', mapping.source_target_path_key,
      'raw_record', mapping.raw_record
    )::text, E'\n' order by mapping.source_identity), ''), 'sha256'),
      'hex')
  into v_mapping_count, v_category_direct_count,
    v_product_required_count, v_invalid_mapping_count,
    v_other_existing_count, v_mapping_checksum
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id = p_release_id;

  with difference as (
    (select mapping.source_identity
     from fitmatch_catalog.source_category_mappings mapping
     where mapping.release_id = p_release_id
     except
     select manifest.source_identity
     from fitmatch_catalog.runtime_classification_candidate_revision_mapping_manifest_v2()
       manifest)
    union all
    (select manifest.source_identity
     from fitmatch_catalog.runtime_classification_candidate_revision_mapping_manifest_v2()
       manifest
     except
     select mapping.source_identity
     from fitmatch_catalog.source_category_mappings mapping
     where mapping.release_id = p_release_id)
  )
  select count(*) into v_mapping_identity_difference_count from difference;

  select count(*) into v_baseline_identity_loss_count
  from fitmatch_catalog.source_category_mappings baseline
  left join fitmatch_catalog.source_category_mappings revision
    on revision.release_id = p_release_id
   and revision.source_identity = baseline.source_identity
  where baseline.release_id =
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'::uuid
    and revision.source_identity is null;

  select count(*) into v_unapproved_base_mismatch_count
  from fitmatch_catalog.source_category_mappings baseline
  join fitmatch_catalog.source_category_mappings revision
    on revision.release_id = p_release_id
   and revision.source_identity = baseline.source_identity
  where baseline.release_id =
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'::uuid
    and not exists (
      select 1
      from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
        disposition
      where disposition.value->>'record_type' =
          'approved_mapping_disposition'
        and disposition.value->>'source_identity' = baseline.source_identity
    )
    and (to_jsonb(revision) - 'release_id') is distinct from
      (to_jsonb(baseline) - 'release_id');

  select count(*), count(*) filter (where
      clone.source <> base.source
      or clone.snapshot_id <> base.snapshot_id
      or clone.external_category_id is distinct from
        base.external_category_id
      or clone.normalized_path <> base.normalized_path
      or clone.decision_status <> base.decision_status
      or clone.mapping_status is distinct from base.mapping_status
      or clone.runtime_lookup_eligible <> base.runtime_lookup_eligible
      or clone.eligibility <> base.eligibility
      or clone.semantic_category_code is distinct from
        base.semantic_category_code
      or clone.semantic_garment_type is distinct from
        base.semantic_garment_type
      or clone.comparison_family is distinct from base.comparison_family
      or clone.source_external_key is distinct from base.source_external_key
      or clone.source_path_key is distinct from base.source_path_key
      or clone.target <> manifest.value->>'target'
      or clone.raw_record#>>'{authorityContract,authorityStatus}' <>
        'verified'
      or clone.raw_record#>>'{authorityContract,resolutionScope}' <>
        'category_direct'
      or coalesce((clone.raw_record#>>
          '{authorityContract,productRequired}')::boolean, true)
    )
  into v_clone_count, v_clone_semantic_mismatch_count
  from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
    manifest
  join fitmatch_catalog.source_category_mappings clone
    on clone.release_id = p_release_id
   and clone.source_identity = manifest.value->>'source_identity'
  join fitmatch_catalog.source_category_mappings base
    on base.release_id = p_release_id
   and base.source_identity = manifest.value->>'base_source_identity'
  where manifest.value->>'record_type' = 'approved_target_clone';

  select count(*) into v_product_required_count_actual
  from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
    manifest
  join fitmatch_catalog.source_category_mappings mapping
    on mapping.release_id = p_release_id
   and mapping.source_identity = manifest.value->>'source_identity'
  where manifest.value->>'record_type' = 'approved_mapping_disposition'
    and manifest.value->>'verdict' = 'SHOULD_BE_PRODUCT_REQUIRED'
    and mapping.raw_record#>>'{authorityContract,authorityStatus}' =
      'verified'
    and mapping.raw_record#>>'{authorityContract,resolutionScope}' =
      'product_required'
    and coalesce((mapping.raw_record#>>
      '{authorityContract,productRequired}')::boolean, false);

  select count(*) into v_revoke_count_actual
  from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
    manifest
  join fitmatch_catalog.source_category_mappings mapping
    on mapping.release_id = p_release_id
   and mapping.source_identity = manifest.value->>'source_identity'
  where manifest.value->>'record_type' = 'approved_mapping_disposition'
    and manifest.value->>'verdict' =
      'SHOULD_BE_REVOKED_NO_REPLACEMENT'
    and mapping.decision_status = 'review_required'
    and mapping.mapping_status = 'revoked'
    and not mapping.runtime_lookup_eligible
    and not mapping.eligibility
    and mapping.raw_record#>>'{authorityContract,authorityStatus}' =
      'revoked'
    and mapping.raw_record#>>'{authorityContract,resolutionScope}' =
      'invalid_mapping'
    and mapping.raw_record#>'{phase1b2rRevision,replacementTuple}' =
      'null'::jsonb;

  select count(*), count(*) filter (where
      (to_jsonb(revision) - 'release_id') is distinct from
        (to_jsonb(baseline) - 'release_id'))
  into v_vocabulary_parity_count, v_vocabulary_mismatch_count
  from fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
    manifest
  join fitmatch_catalog.source_category_mappings baseline
    on baseline.release_id =
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140'::uuid
   and baseline.source_identity = manifest.value->>'source_identity'
  join fitmatch_catalog.source_category_mappings revision
    on revision.release_id = p_release_id
   and revision.source_identity = manifest.value->>'source_identity'
  where manifest.value->>'record_type' =
    'unapproved_invalid_vocabulary_parity';

  with manifest as (
    select *
    from fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
  ), comparison as (
    select manifest.*,
      decision.source is not null
      and decision.product_name = manifest.product_name
      and decision.source_category_path = manifest.source_category_path
      and decision.input_fingerprint = manifest.input_fingerprint
      and decision.category_code is not distinct from manifest.category_code
      and decision.detail_code is not distinct from manifest.detail_code
      and decision.garment_type_code is not distinct from
        manifest.garment_type_code
      and decision.comparison_family is not distinct from manifest.family_code
      and decision.length_type is not distinct from manifest.length_code
      and decision.authority_status = manifest.authority_status
      and decision.requires_user_confirmation =
        manifest.requires_user_confirmation
      and decision.decision_version = manifest.decision_version
      and nullif(decision.evidence->>'body_length_code', '')
        is not distinct from manifest.body_length_code as exact_match
    from manifest
    left join fitmatch_catalog.product_classification_decisions decision
      using (source, external_product_id)
  )
  select count(*) filter (where exact_match),
    count(*) filter (where not exact_match),
    encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'source', source,
      'external_product_id', external_product_id,
      'product_name', product_name,
      'source_category_path', source_category_path,
      'input_fingerprint', input_fingerprint,
      'category_code', category_code,
      'detail_code', detail_code,
      'garment_type_code', garment_type_code,
      'family_code', family_code,
      'length_code', length_code,
      'body_length_code', body_length_code,
      'authority_status', authority_status,
      'requires_user_confirmation', requires_user_confirmation,
      'decision_version', decision_version,
      'action', action,
      'reason', reason,
      'evidence', evidence
    )::text, E'\n' order by source, external_product_id), ''), 'sha256'),
      'hex')
  into v_decision_match_count, v_decision_mismatch_count,
    v_decision_checksum
  from comparison;

  select count(*) into v_review_issue_count
  from fitmatch_catalog.data_quality_issues
  where issue_code = 'CLASSIFICATION_AUTHORITY_REVIEW_REQUIRED'
    and evidence->>'candidate_release_id' =
      '9f9c8155-61d9-41ce-9dd1-bf695ecc2140';

  if v_mapping_count <> 3509 then
    v_blockers := v_blockers || jsonb_build_array('mapping_count_mismatch');
  end if;
  if (v_category_direct_count, v_product_required_count,
      v_invalid_mapping_count, v_other_existing_count)
      is distinct from (51, 999, 359, 2100) then
    v_blockers := v_blockers
      || jsonb_build_array('mapping_bucket_count_mismatch');
  end if;
  if v_mapping_identity_difference_count <> 0
    or v_baseline_identity_loss_count <> 0 then
    v_blockers := v_blockers
      || jsonb_build_array('mapping_identity_parity_mismatch');
  end if;
  if v_unapproved_base_mismatch_count <> 0 then
    v_blockers := v_blockers
      || jsonb_build_array('unapproved_base_mapping_changed');
  end if;
  if v_clone_count <> 17 or v_clone_semantic_mismatch_count <> 0 then
    v_blockers := v_blockers
      || jsonb_build_array('target_clone_content_mismatch');
  end if;
  if v_product_required_count_actual <> 10 then
    v_blockers := v_blockers
      || jsonb_build_array('product_required_disposition_mismatch');
  end if;
  if v_revoke_count_actual <> 30 then
    v_blockers := v_blockers
      || jsonb_build_array('revoke_disposition_mismatch');
  end if;
  if v_vocabulary_parity_count <> 24
    or v_vocabulary_mismatch_count <> 0 then
    v_blockers := v_blockers
      || jsonb_build_array('unapproved_vocabulary_parity_mismatch');
  end if;
  if v_decision_match_count <> 116 or v_decision_mismatch_count <> 0 then
    v_blockers := v_blockers
      || jsonb_build_array('targeted_decision_count_or_content_mismatch');
  end if;
  if v_review_issue_count <> 1037 then
    v_blockers := v_blockers
      || jsonb_build_array('baseline_review_issue_count_mismatch');
  end if;
  if nullif(v_release.validation_report->>'candidate_mapping_db_checksum', '')
      is distinct from v_mapping_checksum then
    v_blockers := v_blockers
      || jsonb_build_array('candidate_mapping_checksum_mismatch');
  end if;
  if nullif(v_release.validation_report->>'targeted_decision_db_checksum', '')
      is distinct from v_decision_checksum then
    v_blockers := v_blockers
      || jsonb_build_array('targeted_decision_checksum_mismatch');
  end if;

  return jsonb_build_object(
    'eligible', jsonb_array_length(v_blockers) = 0,
    'blockers', v_blockers,
    'mapping_count', v_mapping_count,
    'mapping_buckets', jsonb_build_object(
      'CATEGORY_DIRECT', v_category_direct_count,
      'PRODUCT_REQUIRED', v_product_required_count,
      'INVALID_MAPPING', v_invalid_mapping_count,
      'OTHER_EXISTING', v_other_existing_count
    ),
    'mapping_identity_difference_count',
      v_mapping_identity_difference_count,
    'baseline_identity_loss_count', v_baseline_identity_loss_count,
    'unapproved_base_mismatch_count', v_unapproved_base_mismatch_count,
    'target_clone_count', v_clone_count,
    'target_clone_semantic_mismatch_count',
      v_clone_semantic_mismatch_count,
    'product_required_count', v_product_required_count_actual,
    'revoke_count', v_revoke_count_actual,
    'unresolved_vocabulary_parity_count', v_vocabulary_parity_count,
    'unresolved_vocabulary_mismatch_count', v_vocabulary_mismatch_count,
    'targeted_decision_match_count', v_decision_match_count,
    'targeted_decision_mismatch_count', v_decision_mismatch_count,
    'baseline_review_issue_count', v_review_issue_count,
    'candidate_mapping_db_checksum', v_mapping_checksum,
    'targeted_decision_db_checksum', v_decision_checksum
  );
end $$;

create or replace function
fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(
  p_release_id uuid
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_policy jsonb;
  v_artifact jsonb;
  v_blockers jsonb := '[]'::jsonb;
begin
  select * into v_release
  from fitmatch_catalog.releases
  where id = p_release_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'release_not_found';
  end if;

  if v_release.release_key <>
      'fitmatch-classification-authority-candidate-2026-08-26-v2'
    or v_release.status <> 'validated'
    or v_release.expected_mapping_count <> 3509
    or v_release.expected_qa_count <> 1608
    or v_release.validation_contract_version <>
      'fitmatch-release-gate-v2' then
    v_blockers := v_blockers
      || jsonb_build_array('revision_release_contract_mismatch');
  end if;

  v_policy := fitmatch_catalog.runtime_policy_contract_report_v1(
    p_release_id
  );
  v_artifact :=
    fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(
      p_release_id
    );
  v_blockers := v_blockers
    || coalesce(v_policy->'blockers', '[]'::jsonb)
    || coalesce(v_artifact->'blockers', '[]'::jsonb);

  if not (v_release.validation_report @> jsonb_build_object(
    'source_mapping_count', 3509,
    'target_clone_count', 17,
    'target_clone_product_count', 84,
    'approved_decision_delta_count', 2,
    'targeted_decision_count', 116,
    'product_required_count', 10,
    'product_required_product_count', 25,
    'revoke_count', 30,
    'revoke_product_count', 75,
    'unresolved_vocabulary_row_count', 24,
    'unresolved_vocabulary_product_count', 71,
    'shadow_product_count', 1608,
    'baseline_confirmed_count', 177,
    'confirmed_count', 256,
    'review_required_count', 1352,
    'required_approved_review_to_confirmed_count', 86,
    'approved_review_to_confirmed_count', 79,
    'target_clone_mapping_selected_count', 84,
    'target_clone_confirmed_count', 77,
    'target_clone_legacy_decision_conflict_count', 7,
    'owner_acceptance_target_met', false,
    'acceptance_result', 'PARTIAL_NO_GO',
    'unexpected_transition_count', 0,
    'gold_exact_count', 3,
    'gold_collision_count', 0,
    'confirmed_tuple_invalid_count', 0,
    'unsafe_product_required_confirm_count', 0,
    'unsafe_revoked_mapping_confirm_count', 0,
    'both_untrusted_unsafe_confirm_count', 0,
    'arbitrary_unknown_fallback_count', 0,
    'generic_underwear_auto_leak_count', 0,
    'tshirt_base_layer_auto_leak_count', 0,
    'runtime_policy_contract_validated', true,
    'production_write_count', 0
  )) then
    v_blockers := v_blockers
      || jsonb_build_array('revision_validation_report_incomplete');
  end if;
  if nullif(v_release.validation_report->>'shadow_output_checksum', '')
      in ('__PHASE1B2R_SHADOW_CHECKSUM__', '') then
    v_blockers := v_blockers
      || jsonb_build_array('revision_shadow_checksum_pending');
  end if;
  if (v_release.validation_report->>
        'approved_review_to_confirmed_count')::integer <>
      (v_release.validation_report->>
        'required_approved_review_to_confirmed_count')::integer
    or not coalesce((v_release.validation_report->>
        'owner_acceptance_target_met')::boolean, false) then
    v_blockers := v_blockers
      || jsonb_build_array('approved_transition_shortfall');
  end if;

  return jsonb_build_object(
    'contract_version', 'fitmatch-release-gate-v2+phase1b2r-safe-data-v1',
    'release_id', v_release.id,
    'release_key', v_release.release_key,
    'eligible', jsonb_array_length(v_blockers) = 0,
    'blockers', v_blockers,
    'runtime_policy_contract', v_policy,
    'candidate_revision_artifacts', v_artifact
  );
end $$;

revoke all on function
  fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(uuid)
  from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(uuid)
  from public, anon, authenticated;
grant execute on function
  fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(uuid)
  to service_role;
grant execute on function
  fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(uuid)
  to service_role;

-- Store deterministic DB serializations after all candidate-only mapping rows
-- exist. Product decisions remain a manifest until validation/cutover.
update fitmatch_catalog.releases release
set validation_report = release.validation_report || jsonb_build_object(
  'candidate_mapping_db_checksum', artifact.report->>
    'candidate_mapping_db_checksum',
  'targeted_decision_db_checksum', artifact.report->>
    'targeted_decision_db_checksum',
  'shadow_output_checksum',
    'bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916',
  'confirmed_count', 256,
  'review_required_count', 1352,
  'required_approved_review_to_confirmed_count', 86,
  'approved_review_to_confirmed_count', 79,
  'target_clone_mapping_selected_count', 84,
  'target_clone_confirmed_count', 77,
  'target_clone_legacy_decision_conflict_count', 7,
  'target_clone_legacy_decision_conflict_products', jsonb_build_array(
    'musinsa:5982920',
    'musinsa:6515855',
    'musinsa:6534177',
    'musinsa:6781113',
    'musinsa:6797265',
    'musinsa:6797266',
    'musinsa:6797271'
  ),
  'owner_acceptance_target_met', false,
  'acceptance_result', 'PARTIAL_NO_GO'
)
from (
  select
    fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid
    ) report
) artifact
where release.id = 'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid;

do $$
declare
  v_report jsonb;
begin
  v_report :=
    fitmatch_catalog.runtime_classification_candidate_revision_artifact_report_v1(
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid
    );
  if (v_report->>'mapping_count')::integer <> 3509
    or v_report->'mapping_buckets' is distinct from
      '{"CATEGORY_DIRECT":51,"PRODUCT_REQUIRED":999,"INVALID_MAPPING":359,"OTHER_EXISTING":2100}'::jsonb
    or (v_report->>'mapping_identity_difference_count')::integer <> 0
    or (v_report->>'baseline_identity_loss_count')::integer <> 0
    or (v_report->>'unapproved_base_mismatch_count')::integer <> 0
    or (v_report->>'target_clone_count')::integer <> 17
    or (v_report->>'target_clone_semantic_mismatch_count')::integer <> 0
    or (v_report->>'product_required_count')::integer <> 10
    or (v_report->>'revoke_count')::integer <> 30
    or (v_report->>'unresolved_vocabulary_parity_count')::integer <> 24
    or (v_report->>'unresolved_vocabulary_mismatch_count')::integer <> 0
    or (v_report->>'targeted_decision_mismatch_count')::integer <> 116
    or not (v_report->'blockers'
      ? 'targeted_decision_count_or_content_mismatch') then
    raise exception 'phase1b2r_candidate_mapping_acceptance_failed:%',
      v_report;
  end if;
end $$;

comment on function
  fitmatch_catalog.runtime_classification_candidate_revision_manifest_v1()
is 'Exact 84-row Phase 1B-2R safe-data and unapproved-parity manifest.';
comment on function
  fitmatch_catalog.runtime_classification_candidate_revision_gate_report_v1(uuid)
is 'Local candidate-only Phase 1B-2R gate; does not activate or replace the 114 release activation boundary.';

commit;
