# 개발 DB 불필요 객체 검토 — 2026-09-30

## 결론
개발 DB를 먼저 지우고 덤프하는 것보다 원본을 보존하고 복제/복원본에서 삭제 후보를 검증한 뒤 운영용 구조·seed를 확정한다. 이번 감사는 삭제 승인 또는 DROP 안전성의 실행 증명이 아니다.

## 범위·방법
- 대상 hnkplvyegonlhumlejst, 현재 checkout HEAD 3b71f15a67e64b62c762fdfb9340ff7139a9e609. READ ONLY 메타데이터/정의/COUNT 조회. 사용자 row 본문 미수집.
- public/fitmatch_catalog/fitmatch_vnext: 테이블38, 함수128(오버로드 각각), procedure0, view1, sequence1, index116. 비시스템 schema11개 목록 분류. 앱 관련 trigger44개(auth trigger 포함), storage 기본trigger7개는 플랫폼 소유로 유지.
- 모든128 함수 정의 수집→schema-qualified 호출 보수적 그래프→public entrypoints와 trigger root에서 도달성 확인. overload는 이름 단위로 합쳐 보수적으로 유지하므로 126개에 참조가 있다는 것이 매 사용자요청마다 실행된다는 뜻은 아님.
- 두 무호출 후보는 전체 non-system 함수본문 이름 검색, pg_depend 역참조, Swift/Edge/지원script 검색과 ACL 추가 대조. pg_depend는 문자열본문 SQL의 전체 의존성을 보장하지 않으며 동적 호출/외부운영도구/구버전클라이언트까지 부재 증명하지 못함.
- track_functions=none / pg_stat_user_functions=0. 실행횟수0으로 미사용 판정하지 않음.
- supabase/sql/cleanup_retired_paths_Verify.sql READ ONLY 실제 5/5 PASS. 격리 DROP/복원/인증 E2E NOT RUN.

## 1. 삭제 후보 — 최우선 2개
| 객체 | 근거 | 권고 |
|---|---|---|
| fitmatch_vnext.product_readiness_with_context_v1(uuid,jsonb) | 현 product_readiness_with_context는 product_measurement_readiness로 직접 연결. 배포 함수본문/pg_depend/Swift/Edge에서 caller 미발견. service_role EXECUTE만 허용 | 구형 함수 삭제 후보. 과거 SQL와 verifier 참조가 있으므로 복원본에서 DROP RESTRICT 및 현 contract 회귀 후 승인 |
| fitmatch_vnext.update_closet_item_with_group_for_swift(uuid,jsonb) | 현 public update wrapper가 내부 update/apply snapshot/group 로직 직접 수행; 해당 helper 호출 없음. authenticated/service_role EXECUTE 잔존 | 중복 구형 helper 삭제 후보. closet_group_mutation_permissions_Apply.sql은 이 이름을 다시 사용하므로 과거 실행문서도 대응 필요 |

두 함수가 없어진다고 앱이 빨라진다는 성능 증거는 없음. 정리 목적은 혼동·유지보수 범위 축소. 원본DB에서 DROP CASCADE 금지.

## 2. 조사 테이블 — 운영 제외 후보, 개발 삭제 비권장
- fitmatch_catalog.retailer_observed_categories:161행.
- fitmatch_catalog.retailer_observed_category_measurements:703행.
- Swift/Edge/배포함수 caller 없음. 둘 사이 FK만 확인. scripts/build-retailer-normalization-upsert.py가 의도적으로 생성/저장/검증하는 category/measurement 조사 자료. 운영 필수 계산 테이블과 다르지만 사용자가 요구한 유지보수 근거로 유용하다. 개발에 보존하거나 별도 archive하고 운영 dump에서는 제외 검토.
- 두 테이블 합계 pg_total_relation_size=475136 bytes. 전체 앱 relation 약50.5MB 중 작은 일부로, 제거의 성능 이득을 주장하지 않음.

## 3. 추가 폐기 검토 후보 — 지금은 유지
- set/unset_closet_reference 내부2 + public wrapper2: 현 Swift에는 protocol/구현만 검색되고 production 호출 미발견. 공개 RPC 계약이 남아 있으므로 구버전 사용과 지원도구 확인/폐기 승인 없이는 삭제 확정 금지. reference라는 이름의 다른 candidate/authorization 함수는 현재 핵심 기능이다.
- 상세분류 recovery와 user override: 최신 group authority가 개인 detailed override를 primary gate로 쓰지 않아도 ViewModel recovery 경로와 공개 RPC가 남아 있다. user_product_classification_overrides4행/feedback6행도 이들 함수가 사용. 단순 구형 명칭으로 삭제 금지.

## 4. 중요한 반대 근거 — 상품/receipt 일괄삭제 금지
- 현재 active auto-promoted UNIQLO classification mapping 1건 존재. classification_decision→uniqlo_auto_promoted_mapping_is_current→uniqlo_complete_observed_category_path는 product_classification_signals/products/product_ingestion_receipts의 완전한 breadcrumb 관측을 읽는다.
- 따라서 앞선 운영안의 product/receipt를 기본적으로 모두 제외한다는 권고는 무조건 적용할 수 없다. 순수 사용자 테스트자료와 정책 근거를 구분해야 한다. 실제 비교가 반드시 실패한다는 뜻은 아니며 새 API 관측으로 재생성될 수 있지만, 삭제 전후 동일 분류 계약은 아직 미검증이다.
- catalog current_product_classifications view→catalog products/history/release도 recovery에서 참조한다. catalog 제품27/분류history27을 쓸모없는 캐시라고 판단하지 않음.
- 필요한 근거만 추출할 경우 receipt metadata에 사용자/세션 provenance 포함 여부도 검토한다. 임의 삭제/익명화로 fingerprint를 바꾸지 않는다.

## 5. Schema 판정
| schema | 판정 |
|---|---|
| fitmatch_vnext | 핵심 저장/비교/실측/권한. schema 삭제 금지 |
| fitmatch_catalog | 그룹 정책·분류 근거·관리조사 혼재. 전체 삭제 금지 |
| public | RPC24개(오버로드 포함)와 auth/update trigger 함수2개, profiles. 유지 |
| auth / storage / realtime / extensions / vault / graphql / graphql_public | Supabase 관리 영역. 미사용 기능이라고 schema 직접삭제 금지. 플랫폼 지원 설정 변경은 별도 범위 |
| supabase_migrations | 개발DB 이력 유지. 운영 새baseline의 이력은 별도 전략 |

## 6. 전체 테이블 판정
테이블 구조 유지와 기존 데이터의 운영 복사 여부는 별개다. 사용자 데이터 비이관이 테이블 DROP을 뜻하지 않는다.

| 테이블 | 실제 행 | 구조 판정 / 데이터 주의 |
|---|---:|---|
| `fitmatch_catalog.comparison_group_policies` | 2 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_catalog.comparison_groups` | 7 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_catalog.product_classification_history` | 27 | 유지·추가범위확인 / recovery view·FK·분류 근거 |
| `fitmatch_catalog.product_comparison_group_overrides` | 2 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_catalog.products` | 27 | 유지·추가범위확인 / recovery view·FK·분류 근거 |
| `fitmatch_catalog.releases` | 15 | 유지·추가범위확인 / recovery view·FK·분류 근거 |
| `fitmatch_catalog.retailer_observed_categories` | 161 | 개발 보존 권고 / 운영 제외 후보(관리script 사용) |
| `fitmatch_catalog.retailer_observed_category_measurements` | 703 | 개발 보존 권고 / 운영 제외 후보(관리script 사용) |
| `fitmatch_catalog.source_category_comparison_groups` | 1023 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.classification_axis_value_authority` | 12 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.classification_signal_mappings` | 2250 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.closet_item_measurements` | 268 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.closet_item_source_measurement_snapshots` | 11 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.closet_item_source_measurements` | 52 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.closet_items` | 65 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.comparison_metrics` | 647 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.comparison_policies` | 44 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.comparison_result_heads` | 18 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.comparisons` | 37 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.fitmatch_categories` | 11 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.fitmatch_measurements` | 42 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.garment_types` | 60 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.product_classification_signals` | 241 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.product_ingestion_receipts` | 251 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.product_size_measurements` | 2576 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.product_sizes` | 561 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.product_variants` | 113 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.products` | 83 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.size_availability_observations` | 1430 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.source_classification_signals` | 2555 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.source_identifiers` | 573 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.source_measurement_aliases` | 227 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.source_measurement_mappings` | 48 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.source_measurements` | 51 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.sources` | 3 | 유지 / 정책·사전·의존 근거 seed 보존; active만 선별 금지 |
| `fitmatch_vnext.user_classification_feedback_evidence` | 6 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `fitmatch_vnext.user_product_classification_overrides` | 4 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |
| `public.profiles` | 2 | 유지 / 실행데이터; 운영 복사 여부 별도 결정 |

## 7. 전체 함수 판정
현재 호출 경로 유지는 잠재 caller 또는 trigger 계약이 있다는 뜻이며, 모든 분기의 실사용 여부가 검증되었다는 뜻은 아니다.

| 함수(정확한 signature) | 판정 | 들어오는 참조 예 |
|---|---|---|
| `fitmatch_catalog.runtime_infer_body_length_code(p_category_code text, p_product_name text, p_source_category_path text)` | 유지 / 현재 참조 또는 계약 | fitmatch_catalog.sync_product_body_length |
| `fitmatch_catalog.sync_product_body_length()` | 유지 / 현재 참조 또는 계약 | product_classification_sync_body_length |
| `fitmatch_vnext.advance_comparison_result_head()` | 유지 / 현재 참조 또는 계약 | comparisons_advance_result_head |
| `fitmatch_vnext.apply_closet_comparison_group(p_closet_item_id uuid, p_requested_group_code text, p_explicit boolean)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.update_closet_item_with_group_for_swift; fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base; public.fitmatch_vnext_update_closet_item |
| `fitmatch_vnext.apply_linked_closet_snapshot_for_swift(p_request jsonb, p_existing_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.update_closet_item_with_group_for_swift; fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base; public.fitmatch_vnext_update_closet_item |
| `fitmatch_vnext.authorize_comparison_with_context(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.eligible_candidate_sizes |
| `fitmatch_vnext.authorize_comparison_with_context(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.eligible_candidate_sizes |
| `fitmatch_vnext.authorize_comparison_with_context_v1(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context |
| `fitmatch_vnext.authorize_comparison_with_context_v1(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_product_size_id uuid, p_manual_explicit boolean, p_effective_classification jsonb, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context |
| `fitmatch_vnext.begin_comparison(p_request jsonb)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_begin_comparison |
| `fitmatch_vnext.begin_comparison_legacy_20260914(p_request jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.begin_comparison |
| `fitmatch_vnext.canonical_measurements_for_session_group(p_product_size_id uuid, p_effective_classification jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context_v1; fitmatch_vnext.eligible_candidate_sizes |
| `fitmatch_vnext.canonical_measurements_for_size(p_product_size_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.canonical_measurements_for_size_with_context; fitmatch_vnext.get_product_runtime_base |
| `fitmatch_vnext.canonical_measurements_for_size_with_context(p_product_size_id uuid, p_effective_classification jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.apply_linked_closet_snapshot_for_swift; fitmatch_vnext.authorize_comparison_with_context_v1; fitmatch_vnext.canonical_measurements_for_session_group |
| `fitmatch_vnext.classification_decision(p_source_code text, p_source_product_key text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.classification_recovery_options; fitmatch_vnext.classification_recovery_options_v6_core; fitmatch_vnext.classification_recovery_options_v7_pre_explicit_core |
| `fitmatch_vnext.classification_recovery_options(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.set_user_product_classification; public.fitmatch_vnext_get_classification_recovery_options |
| `fitmatch_vnext.classification_recovery_options_v6_core(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.classification_recovery_options_v7_pre_explicit_core |
| `fitmatch_vnext.classification_recovery_options_v7_pre_explicit_core(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.classification_recovery_options |
| `fitmatch_vnext.classification_tuple_validation(p_garment_type_code text, p_product_structure_code text, p_audience_code text, p_sleeve_length_code text, p_lower_length_code text, p_body_length_code text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.apply_linked_closet_snapshot_for_swift; fitmatch_vnext.classification_decision; fitmatch_vnext.classification_recovery_options |
| `fitmatch_vnext.clear_closet_classification_override(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_clear_closet_classification_override |
| `fitmatch_vnext.clear_user_product_classification(p_product_id uuid, p_mutation_id uuid, p_expected_revision integer)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_clear_user_product_classification |
| `fitmatch_vnext.closet_comparison_group(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context_v1; fitmatch_vnext.find_reference_candidates_filtered; public.fitmatch_vnext_eligible_candidate_sizes |
| `fitmatch_vnext.comparison_domain_20260908(p_policy text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context_v1 |
| `fitmatch_vnext.comparison_evidence_20260908(p_reference_closet_item_id uuid, p_policy text, p_canonical jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context_v1; fitmatch_vnext.eligible_candidate_sizes |
| `fitmatch_vnext.comparison_group_tuple(p_product_id uuid, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.comparison_target_context; fitmatch_vnext.effective_target_classification; fitmatch_vnext.update_closet_item_with_group_for_swift |
| `fitmatch_vnext.comparison_history()` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.comparison_history_sync; public.fitmatch_vnext_comparison_history |
| `fitmatch_vnext.comparison_history_sync()` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_comparison_history_sync |
| `fitmatch_vnext.comparison_target_context(p_target_product_id uuid, p_target_variant_id uuid, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context_v1; fitmatch_vnext.begin_comparison; fitmatch_vnext.eligible_candidate_sizes |
| `fitmatch_vnext.complete_comparison(p_comparison_id uuid, p_result jsonb)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_complete_comparison |
| `fitmatch_vnext.effective_product_readiness(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.get_product_runtime_for_swift |
| `fitmatch_vnext.effective_target_classification(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context_v1; fitmatch_vnext.begin_comparison_legacy_20260914; fitmatch_vnext.clear_user_product_classification |
| `fitmatch_vnext.eligible_candidate_sizes(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_variant_id uuid, p_manual_explicit boolean)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.begin_comparison; fitmatch_vnext.begin_comparison_legacy_20260914; fitmatch_vnext.eligible_candidate_sizes |
| `fitmatch_vnext.eligible_candidate_sizes(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_variant_id uuid, p_manual_explicit boolean, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.begin_comparison; fitmatch_vnext.begin_comparison_legacy_20260914; fitmatch_vnext.eligible_candidate_sizes |
| `fitmatch_vnext.enforce_uniqlo_generic_category_leaf_inactive()` | 유지 / 현재 참조 또는 계약 | source_classification_signals_uniqlo_generic_leaf_inactive |
| `fitmatch_vnext.exact_product_authority_recovery_options(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.classification_recovery_options_v6_core |
| `fitmatch_vnext.find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_find_reference_candidates |
| `fitmatch_vnext.find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_find_reference_candidates |
| `fitmatch_vnext.find_reference_candidates_filtered(p_target_product_id uuid, p_target_variant_id uuid, p_reference_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.find_reference_candidates; fitmatch_vnext.find_reference_candidates_filtered; public.fitmatch_vnext_find_selected_reference_candidate |
| `fitmatch_vnext.find_reference_candidates_filtered(p_target_product_id uuid, p_target_variant_id uuid, p_requested_group_code text, p_reference_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.find_reference_candidates; fitmatch_vnext.find_reference_candidates_filtered; public.fitmatch_vnext_find_selected_reference_candidate |
| `fitmatch_vnext.get_product_runtime(p_source_code text, p_source_product_key text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.ingest_product_observation_v2 |
| `fitmatch_vnext.get_product_runtime_base(p_source_code text, p_source_product_key text, p_include_derived boolean)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.get_product_runtime; fitmatch_vnext.get_product_runtime_for_swift |
| `fitmatch_vnext.get_product_runtime_for_swift(p_source_code text, p_source_product_key text)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_get_product_runtime |
| `fitmatch_vnext.hide_comparison_history(p_client_comparison_ids uuid[])` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_hide_comparison_history |
| `fitmatch_vnext.ingest_product_observation(p_payload jsonb, p_actor_id uuid)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_ingest_product_observation |
| `fitmatch_vnext.ingest_product_observation_v2(p_payload jsonb, p_actor_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.ingest_product_observation |
| `fitmatch_vnext.list_closet_items()` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.list_closet_items; public.fitmatch_vnext_get_closet_item; public.fitmatch_vnext_list_closet_items |
| `fitmatch_vnext.list_closet_items(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.list_closet_items; public.fitmatch_vnext_get_closet_item; public.fitmatch_vnext_list_closet_items |
| `fitmatch_vnext.list_closet_items_detail_snapshot_base()` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.list_closet_items; fitmatch_vnext.list_closet_items_detail_snapshot_base |
| `fitmatch_vnext.list_closet_items_detail_snapshot_base(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.list_closet_items; fitmatch_vnext.list_closet_items_detail_snapshot_base |
| `fitmatch_vnext.list_closet_items_snapshot_base()` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.list_closet_items_snapshot_base; fitmatch_vnext.list_closet_items_snapshot_receipt_base |
| `fitmatch_vnext.list_closet_items_snapshot_base(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.list_closet_items_snapshot_base; fitmatch_vnext.list_closet_items_snapshot_receipt_base |
| `fitmatch_vnext.list_closet_items_snapshot_receipt_base()` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.list_closet_items_detail_snapshot_base; fitmatch_vnext.list_closet_items_snapshot_receipt_base |
| `fitmatch_vnext.list_closet_items_snapshot_receipt_base(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.list_closet_items_detail_snapshot_base; fitmatch_vnext.list_closet_items_snapshot_receipt_base |
| `fitmatch_vnext.normalize_measurement_label(p_label text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.resolve_measurement |
| `fitmatch_vnext.product_comparison_group(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.apply_closet_comparison_group; fitmatch_vnext.comparison_group_tuple; fitmatch_vnext.comparison_target_context |
| `fitmatch_vnext.product_comparison_unit_decision(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.authorize_comparison_with_context; fitmatch_vnext.authorize_comparison_with_context_v1; fitmatch_vnext.classification_decision |
| `fitmatch_vnext.product_measurement_readiness(p_product_id uuid, p_effective_classification jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.product_readiness; fitmatch_vnext.product_readiness_with_context |
| `fitmatch_vnext.product_readiness(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.effective_product_readiness; fitmatch_vnext.get_product_runtime_base; fitmatch_vnext.ingest_product_observation_v2 |
| `fitmatch_vnext.product_readiness_with_context(p_product_id uuid, p_effective_classification jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.effective_product_readiness |
| `fitmatch_vnext.product_readiness_with_context_v1(p_product_id uuid, p_effective_classification jsonb)` | 삭제 후보 / 검증 전 유지 | caller 미발견 |
| `fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping(p_target_signal_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.ingest_product_observation_v2 |
| `fitmatch_vnext.protect_completed_comparison()` | 유지 / 현재 참조 또는 계약 | comparisons_protect_completed |
| `fitmatch_vnext.protect_fitmatch_measurement_semantics()` | 유지 / 현재 참조 또는 계약 | fitmatch_measurements_protect_semantics |
| `fitmatch_vnext.protect_product_ingestion_receipt()` | 유지 / 현재 참조 또는 계약 | product_ingestion_receipts_protect_evidence |
| `fitmatch_vnext.protect_source_measurement_semantics()` | 유지 / 현재 참조 또는 계약 | source_measurements_protect_semantics |
| `fitmatch_vnext.protect_user_classification_feedback_evidence()` | 유지 / 현재 참조 또는 계약 | user_classification_feedback_append_only |
| `fitmatch_vnext.record_size_availability(p_product_size_id uuid, p_availability_status text, p_evidence_kind text, p_evidence_payload jsonb, p_observed_at timestamp with time zone, p_valid_until timestamp with time zone)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.ingest_product_observation_v2 |
| `fitmatch_vnext.resolve_measurement(p_source_code text, p_parser_code text, p_raw_measurement_code text, p_raw_label text, p_garment_type_code text, p_fitmatch_category_code text, p_raw_value numeric)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.canonical_measurements_for_size; fitmatch_vnext.canonical_measurements_for_size_with_context; fitmatch_vnext.update_closet_item |
| `fitmatch_vnext.resolve_product_classification(p_source_code text, p_source_product_key text, p_apply boolean)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.ingest_product_observation_v2 |
| `fitmatch_vnext.revalidate_uniqlo_auto_promoted_mappings(p_external_key text)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.ingest_product_observation_v2 |
| `fitmatch_vnext.set_closet_classification_override(p_closet_item_id uuid, p_override jsonb)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_set_closet_classification_override |
| `fitmatch_vnext.set_closet_detail_snapshot_for_swift(p_closet_item_id uuid, p_request jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.update_closet_item_with_group_for_swift; fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base; public.fitmatch_vnext_update_closet_item |
| `fitmatch_vnext.set_closet_reference(p_closet_item_id uuid)` | 폐기 검토 보류 / 공개호환 확인 필요 | public.fitmatch_vnext_set_closet_reference |
| `fitmatch_vnext.set_updated_at()` | 유지 / 현재 참조 또는 계약 | sources_set_updated_at; fitmatch_categories_set_updated_at |
| `fitmatch_vnext.set_user_product_classification(p_product_id uuid, p_selected_candidate_fingerprint text, p_expected_candidate_set_hash text, p_expected_product_input_fingerprint text, p_expected_product_evidence_fingerprint text, p_mutation_id uuid, p_expected_revision integer)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_set_user_product_classification |
| `fitmatch_vnext.soft_delete_closet_item(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_delete_closet_item |
| `fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current(p_mapping_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.classification_decision; fitmatch_vnext.revalidate_uniqlo_auto_promoted_mappings |
| `fitmatch_vnext.uniqlo_category_parent_chain_matches_observed_path(p_signal_id uuid, p_path text[])` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current; fitmatch_vnext.uniqlo_category_parent_chain_safe |
| `fitmatch_vnext.uniqlo_category_parent_chain_safe(p_signal_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.ingest_product_observation_v2; fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping |
| `fitmatch_vnext.uniqlo_complete_observed_category_path(p_signal_id uuid)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping; fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current; fitmatch_vnext.uniqlo_category_parent_chain_safe |
| `fitmatch_vnext.unset_closet_reference(p_closet_item_id uuid)` | 폐기 검토 보류 / 공개호환 확인 필요 | public.fitmatch_vnext_unset_closet_reference |
| `fitmatch_vnext.update_closet_item(p_closet_item_id uuid, p_request jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.update_closet_item_with_group_for_swift; public.fitmatch_vnext_update_closet_item |
| `fitmatch_vnext.update_closet_item_snapshot_base(p_closet_item_id uuid, p_request jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.update_closet_item |
| `fitmatch_vnext.update_closet_item_with_group_for_swift(p_closet_item_id uuid, p_request jsonb)` | 삭제 후보 / 검증 전 유지 | caller 미발견 |
| `fitmatch_vnext.upsert_closet_item(p_request jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.upsert_closet_item_for_swift |
| `fitmatch_vnext.upsert_closet_item_for_swift(p_request jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base |
| `fitmatch_vnext.upsert_closet_item_with_group_for_swift(p_request jsonb)` | 유지 / 현재 참조 또는 계약 | public.fitmatch_vnext_upsert_closet_item |
| `fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base(p_request jsonb)` | 유지 / 현재 참조 또는 계약 | fitmatch_vnext.upsert_closet_item_with_group_for_swift |
| `fitmatch_vnext.validate_classification_mapping()` | 유지 / 현재 참조 또는 계약 | classification_signal_mappings_validate_contract |
| `fitmatch_vnext.validate_closet_measurement_mode()` | 유지 / 현재 참조 또는 계약 | closet_item_measurements_validate_mode |
| `fitmatch_vnext.validate_closet_measurement_source_snapshot()` | 유지 / 현재 참조 또는 계약 | closet_item_measurements_validate_source_snapshot |
| `fitmatch_vnext.validate_closet_product_hierarchy()` | 유지 / 현재 참조 또는 계약 | closet_items_validate_product_hierarchy |
| `fitmatch_vnext.validate_comparison_completion_payload()` | 유지 / 현재 참조 또는 계약 | comparisons_validate_completion_payload |
| `fitmatch_vnext.validate_comparison_ownership_and_target()` | 유지 / 현재 참조 또는 계약 | comparisons_validate_ownership_and_target |
| `fitmatch_vnext.validate_garment_axis_values()` | 유지 / 현재 참조 또는 계약 | products_validate_garment_axes; closet_items_validate_garment_axes |
| `fitmatch_vnext.validate_ingestion_receipt_facts()` | 유지 / 현재 참조 또는 계약 | product_ingestion_receipts_validate_facts |
| `fitmatch_vnext.validate_product_signal_source()` | 유지 / 현재 참조 또는 계약 | product_classification_signals_validate_source |
| `fitmatch_vnext.validate_size_availability_observation()` | 유지 / 현재 참조 또는 계약 | size_availability_observations_validate |
| `fitmatch_vnext.validate_source_identifier_owner()` | 유지 / 현재 참조 또는 계약 | source_identifiers_validate_owner |
| `fitmatch_vnext.validate_source_measurement_alias_source()` | 유지 / 현재 참조 또는 계약 | source_measurement_aliases_validate_source |
| `fitmatch_vnext.validate_source_signal_parent()` | 유지 / 현재 참조 또는 계약 | source_classification_signals_validate_parent |
| `fitmatch_vnext.validate_user_product_classification_override()` | 유지 / 현재 참조 또는 계약 | user_product_classification_override_validate |
| `public.fitmatch_vnext_begin_comparison(p_request jsonb)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_clear_closet_classification_override(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_clear_user_product_classification(p_product_id uuid, p_mutation_id uuid, p_expected_revision integer)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_comparison_history()` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_comparison_history_sync()` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_complete_comparison(p_comparison_id uuid, p_result jsonb)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_delete_closet_item(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_eligible_candidate_sizes(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_variant_id uuid, p_manual_explicit boolean)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_eligible_candidate_sizes(p_reference_closet_item_id uuid, p_target_product_id uuid, p_target_variant_id uuid, p_manual_explicit boolean, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_find_reference_candidates(p_target_product_id uuid, p_target_variant_id uuid, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_find_selected_reference_candidate(p_target_product_id uuid, p_target_variant_id uuid, p_reference_closet_item_id uuid, p_requested_group_code text)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_get_classification_recovery_options(p_product_id uuid)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_get_closet_item(p_closet_item_id uuid)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_get_product_runtime(p_source_code text, p_source_product_key text)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_hide_comparison_history(p_client_comparison_ids uuid[])` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_ingest_product_observation(p_payload jsonb, p_actor_id uuid)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_list_closet_items()` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_set_closet_classification_override(p_closet_item_id uuid, p_override jsonb)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_set_closet_reference(p_closet_item_id uuid)` | 폐기 검토 보류 / 공개호환 확인 필요 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_set_user_product_classification(p_product_id uuid, p_selected_candidate_fingerprint text, p_expected_candidate_set_hash text, p_expected_product_input_fingerprint text, p_expected_product_evidence_fingerprint text, p_mutation_id uuid, p_expected_revision integer)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_unset_closet_reference(p_closet_item_id uuid)` | 폐기 검토 보류 / 공개호환 확인 필요 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_update_closet_item(p_closet_item_id uuid, p_request jsonb)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.fitmatch_vnext_upsert_closet_item(p_request jsonb)` | 유지 / 현재 참조 또는 계약 | public RPC/trigger 진입점 |
| `public.handle_new_user()` | 유지 / 현재 참조 또는 계약 | on_auth_user_created |
| `public.set_updated_at()` | 유지 / 현재 참조 또는 계약 | profiles_set_updated_at |

## 8. 삭제하면 안 되는 대표 연결
- public.begin→begin_comparison→begin_comparison_legacy_20260914. legacy지만 현재 연결.
- public.list/get_closet→list_closet_items→detail_snapshot_base→snapshot_receipt_base→snapshot_base. 원본/상세/단일조회 계층.
- public.upsert→upsert_closet_item_with_group_for_swift→snapshot_base→apply_linked_closet_snapshot_for_swift 등. raw/canonical/identity 저장 계층.
- public.recovery→classification_recovery_options→v7_pre_explicit_core→v6_core→exact_product_authority_recovery_options. 과거명칭만으로 제거 불가.

## 9. 다음 실행안
1. 원본을 지우지 않은 기준 dump 확보 → 격리 복원.
2. 함수2개만 제거한 복원본으로 무삭제기준과 등록/수정/비교/History 계약 대조. 조사2테이블은 운영 산출물에서만 제외 검토.
3. 통과 후 승인된 정리 migration과 복원 절차 준비. 기준데이터/사용자자료 범위를 확정하여 운영 이관.
이번에는 삭제SQL 작성/적용/앱수정/운영DBwrite/commit/push 없음. 함수128개와 테이블38개 metadata/정의 기반 목록검토는 수행했지만 전체 실행행동 테스트는 NOT RUN.

## 10. 덤프 대상 목록 재검토 — 같은 날 후속 READ ONLY

앞선 목록은 객체 분류안이며 아직 실행 가능한 행 단위 seed/export 명세가 아니다. 실제 source/target catalog를 다시 조회했다. 증거: `DumpScopeRecheck.json`. 앱 소스/DB는 변경하지 않았다.

### 수량과 범위

| 대상 | 원본 현재 수량 | 운영 이관안 |
|---|---:|---|
| 테이블 | 38 | 핵심·호환 구조36 + 조사 전용2 제외 후보. 제외는 아직 실행 검증 전 |
| 함수 | 128 | 우선128 유지. 무호출 후보2개 정리는 출시 이관의 필수 조건이 아님 |
| 프로시저 | 0 | 없음 |
| 뷰 | 1 | current_product_classifications 유지 |
| 시퀀스 | 1 | size_availability_observations.id의 identity sequence. 데이터 선택 범위에 맞춰 복원 |
| 인덱스 | 116 | 조사2테이블을 제외할 경우114. 116은 원본 전체 수량이며36테이블의 수량이 아님 |
| 앱 트리거 | 44 | auth.users의 on_auth_user_created 포함. 조사2테이블에는 별도 trigger 없음 |
| RLS 정책 | 26 | 유지. 정책뿐 아니라 RLS enable/force 상태·schema USAGE·객체 ACL·함수 owner/security/search_path도 보존/대조 |

독립 enum/domain/range/composite type, 앱 schema event trigger, 별도 rewrite rule은 이번 source 조회에서0. 테이블의 자동 row type 등은 테이블 정의에 따른다. 조사2테이블은 서로간 FK1개와 각각 index1개만 확인되며 RLS policy/사용자 trigger0. 이 사실만으로 복원 회귀 통과를 주장하지 않는다.

### 이전 설명의 정정·구체화

1. **운영DB는 앱 테이블이 없지만 완전한 빈DB는 아니다.** `public.rls_auto_enable()` + event trigger `ensure_rls`가 이미 있다. public에 새 테이블을 만들면 RLS를 켜는 함수다. source의 public.profiles도 이미 RLS=true여서 그 테이블의 설정과 충돌하는 근거는 없다. 대상 기본 객체를 삭제하거나 전체 함수 수를128로 강제하지 않는다. 이 기본함수를 유지하고 앱128개를 복원하면 해당3스키마 함수 수는129가 될 수 있다. 앱객체별 대조가 필요하다.
2. **권한 복원은 플랫폼 기본설정을 통째로 덮어쓰는 것과 다르다.** 실제 schema/default ACL을 확인했다. source의 앱객체 권한을 보존하되 target 플랫폼 권한·기본 객체를 별도로 취급한다. public 전체 DROP/재생성이나 모든GRANT 제거는 계획에 포함하지 않는다.
3. **분류 이력 때문에 개발계정 이관이 필수라는 근거는 없다.** catalog.product_classification_history 27건의 reviewed_by는 모두NULL. FK가 있다는 사실과 현재 사용자참조가 있다는 사실을 구분한다. 한편 product_ingestion_receipts에는 actor_id_snapshot 컬럼이 실제 존재하므로 필요한 정책근거 receipt를 선택할 때 provenance 검토는 여전히 필요하다. 실제값을 수집하거나 바꾸지 않았다.
4. **데이터3분류는 유지하되 전량복사 승인으로 해석하지 않는다.** 기준·정책16테이블 / 상품·관측 근거11테이블 / 사용자데이터9테이블 / 조사2테이블 합계38. 정책status/version/검증조건을 그대로 보존하며, 필요한 상품·receipt 근거와 그 종속row를 구체적으로 선정해야 한다. 사용자9테이블은 구조 유지·기존행 비이관 권고이며 사용자 결정 전 확정하지 않는다.
5. **auth trigger와 Edge는 빠뜨리기 쉽다.** 앱3스키마만 선택하는 산출물에는 auth.users에 붙은 앱trigger를 별도 포함해야 한다. Edge2개와 Apple/Auth/API/키 설정은 SQL구조 목록과 별도 배포·검증 항목이다. 과거migration 이력과 새baseline의 관계도 문서화하여 재적용을 막는다.

### 판정과 종료 경계

- 구조 목록 재확인 PASS. source38/128 및 target 기본객체 확인, 제외안의 index114 정정.
- 앱128함수의 재실행 전체 검증/격리복원/운영권한·로그인·등록·비교 smoke NOT RUN. 앱테스트는 문서·목록검토와 무관하여 이번에 실행하지 않음.
- 새 결함을 확인한 것이 아니라 이관 명세의 정확도를 보완한 것. 남은 핵심은 행 단위 seed 명세와 복원 검증이다. 개발DB 정리는 먼저 할 필요 없으며 두 미사용 후보 함수 삭제를 출시 이관 선행조건으로 삼지 않는다.
- dump/restore/DDL/DML/migration/deploy/endpoint 변경/commit/push 없음. 이 문서와 JSON은 로컬 미추적 산출물이며 Git 원격 반영이 아니다.
