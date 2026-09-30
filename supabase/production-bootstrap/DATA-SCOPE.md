# 운영 DB 이관 데이터 확정 명세

기준: 2026-09-30 개발 DB READ ONLY 조회. 대상 FitMatch_PROD.
**이 문서는 이관 범위 명세다. 후속 SQL 추출·로컬 전체 복원 검증은 완료했다. 운영 적용은 아직 하지 않았다. 최신 상태는 README.md와 FINAL-REVIEW.md를 따른다.**

## 확정 범위

- 기준·정책 16테이블: 6,984행. 현재 version/status/verified와 제외 규칙 그대로 보존한다.
- 기존 catalog 분류 근거 3테이블: 69행. products27/history27/releases15.
- 유니클로 E486587 / E486610의 연결 근거 8테이블: 114행.
- 합계 27테이블 7,167행. 사용자자료9·조사자료2테이블은0행. 전체38테이블 구조는 유지한다.
- 운영은 개발 계정·세션·프로필·옷장·비교 기록·개인 분류 변경 없이 시작한다. 개발 DB에서는 삭제하지 않는다.
- 두 receipt의 actor_id_snapshot은 과거 작성자 출처로 그대로 보존한다. 로그인 가능한 계정·프로필을 옮기는 것이 아니며 운영사용자로 재연결하거나 NULL로 바꾸지 않는다. 원문 JSON 전체의 개인정보/비밀값 검사는 이번 범위검증과 별도로 추출 전 확인한다.

## 테이블별 이관 행 수

| 테이블 | 이관 행 수 |
|---|---:|
| `fitmatch_catalog.comparison_group_policies` | 2 |
| `fitmatch_catalog.comparison_groups` | 7 |
| `fitmatch_catalog.product_classification_history` | 27 |
| `fitmatch_catalog.product_comparison_group_overrides` | 2 |
| `fitmatch_catalog.products` | 27 |
| `fitmatch_catalog.releases` | 15 |
| `fitmatch_catalog.retailer_observed_categories` | 0 |
| `fitmatch_catalog.retailer_observed_category_measurements` | 0 |
| `fitmatch_catalog.source_category_comparison_groups` | 1023 |
| `fitmatch_vnext.classification_axis_value_authority` | 12 |
| `fitmatch_vnext.classification_signal_mappings` | 2250 |
| `fitmatch_vnext.closet_item_measurements` | 0 |
| `fitmatch_vnext.closet_item_source_measurement_snapshots` | 0 |
| `fitmatch_vnext.closet_item_source_measurements` | 0 |
| `fitmatch_vnext.closet_items` | 0 |
| `fitmatch_vnext.comparison_metrics` | 647 |
| `fitmatch_vnext.comparison_policies` | 44 |
| `fitmatch_vnext.comparison_result_heads` | 0 |
| `fitmatch_vnext.comparisons` | 0 |
| `fitmatch_vnext.fitmatch_categories` | 11 |
| `fitmatch_vnext.fitmatch_measurements` | 42 |
| `fitmatch_vnext.garment_types` | 60 |
| `fitmatch_vnext.product_classification_signals` | 8 |
| `fitmatch_vnext.product_ingestion_receipts` | 2 |
| `fitmatch_vnext.product_size_measurements` | 70 |
| `fitmatch_vnext.product_sizes` | 14 |
| `fitmatch_vnext.product_variants` | 2 |
| `fitmatch_vnext.products` | 2 |
| `fitmatch_vnext.size_availability_observations` | 14 |
| `fitmatch_vnext.source_classification_signals` | 2555 |
| `fitmatch_vnext.source_identifiers` | 2 |
| `fitmatch_vnext.source_measurement_aliases` | 227 |
| `fitmatch_vnext.source_measurement_mappings` | 48 |
| `fitmatch_vnext.source_measurements` | 51 |
| `fitmatch_vnext.sources` | 3 |
| `fitmatch_vnext.user_classification_feedback_evidence` | 0 |
| `fitmatch_vnext.user_product_classification_overrides` | 0 |
| `public.profiles` | 0 |

## 정확한 선정·검증

- data-selection.json에 각 테이블의 WHERE 조건, 예상 행 수, 내용 MD5를 기록했다. TRUE는 현재행 전부, FALSE는0행, 나머지는 정확한 상품/관측 UUID와 FK관계로 제한한다. ID와 원본값을 재작성하지 않는다.
- data-selection-counts.sql: 같은 조건의 행수/내용해시 대조. 변경되면 기존확정을 자동으로 덮지 않고 재확인한다. MD5는 변경탐지용이며 덤프파일 SHA256과 구분한다.
- data-selection-fk-check.sql: 선정행의 관련FK38개 모두 부모행 누락0, PASS. auth.users는 이관0행으로 계산했다.
- data-selection-path-parity.sql: 실제 배포SQL의 관측테이블 입력만 선정행으로 제한했다. 원본 전체와 선정행의 UNIQLO 분류경로2/2 동일·non-null, PASS. 복원DB/E2E 검증은 아니다.

## 범위 확정 당시 기록 — 아래 미완료 표시는 후속 README 상태로 대체

- 이전19테이블 참고후보는 최종seed가 아니다. 최종범위는 이 문서와 data-selection.json의27테이블 선택행이다.
- 기존 prepare-production-dump.py는 구조dump와19테이블 참고후보만 지원한다. 최종 선택행 export를 동일DB snapshot으로 연결하는 작업과 실제 추출은 아직 수행하지 않았다. pg_dump의 테이블 제외 옵션만으로 상품2개 row필터가 된다고 가정하지 않는다.
- 민감정보 확인·일관된 추출·격리 복원·운영적용 검증은 남아 있다. source receipt 원문은 유지하며 자의적 익명화/UUID변경으로 통과시키지 않는다.
- 개발/운영 DB write, 실제 계정이전, commit/push 없음.
