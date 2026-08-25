# FitMatch DB Runtime Contract

- 기준일: 2026-08-18
- DB 기반 버전: `db-runtime-2026-08-18-v1`
- 신규 상품 분류 버전: `db-auto-classifier-2026-08-18-v2`
- 비교 후보 정책 버전: `db-comparison-2026-08-18-v2`
- 대상: 출시 후 DB 연동 브랜치의 iOS/서버 개발
- 원칙: 공용 사실, 사용자 선택, 비교 실행 이력을 분리한다.

## 0. 확정된 애플리케이션 경계

FitMatch를 iOS와 PostgreSQL 두 덩어리로 나누지 않는다. 최종 책임은 아래
세 경계로 고정한다.

```text
iOS
  └─ 화면, 사용자 입력, 로컬 캐시

Retailer Adapter / FitMatch Domain API
  ├─ 쇼핑몰 API·HTML·OCR 파싱
  ├─ 신뢰된 상품 재검증
  └─ 최종 서버 추천 계산(현재 Swift 엔진과 shadow parity 후 승격)

Supabase PostgreSQL
  ├─ 공용 상품·확정 분류·정규화 실측
  ├─ 사용자 옷장·분류 override
  ├─ 비교 호환 정책·실행 snapshot
  └─ 추천 결과·근거·버전 이력
```

현재 전환 단계에서는 검증된 Swift 추천 엔진을 즉시 폐기하지 않는다. DB가
상품 분류와 비교 호환 입력의 기준이 되고 Swift는 기존 사용자 결과를 유지한다.
서버 추천 엔진은 동일 corpus와 실사용 shadow에서 전 필드 parity가 입증된 뒤에만
최종 결과의 source of truth로 승격한다.

앱은 `FitMatchDatabaseDomainServicing` 경계만 사용한다. private catalog table,
backend 전용 함수, service/secret key를 직접 사용하지 않는다. 옷장·후보·비교
RPC도 상품 resolve와 동일한 인증 세션을 공유한다.

최종 서버 계산 전까지 클라이언트가 제출한 비교 결과는 사용자 개인 이력으로만
취급한다. 공용 정책 학습이나 전역 통계의 정답으로 자동 승격하지 않는다.

## 1. 책임 경계

```text
배치 / 검증된 Edge Function (service_role)
  └─ retailer 원문 검증
      └─ runtime_resolve_and_promote_product
          ├─ 기존 상품+카테고리 증거 일치 → 현재 분류 재사용
          ├─ 신규/변경 → Gold 기반 unanimous profile 자동 분류
          ├─ 명시적 제외 → not_comparable
          └─ 근거 충돌/부족 → review_required
      └─ fitmatch_catalog.products / variants / sizes / measurements
          └─ product_classification_history (공용 canonical 사실)

인증된 iOS 사용자
  ├─ 알려진 상품 조회
  ├─ 미검증 상품 → product_intake_requests (공용 사실 직접 수정 금지)
  ├─ closet_items (사용자 소유)
  ├─ closet_item_classification_overrides (사용자별 해석)
  └─ comparison_runs / results / measurement_results (사용자별 결과)
```

앱 payload는 공용 상품을 직접 upsert하지 않는다. 그렇지 않으면 임의의 인증 사용자가 기존 상품명·카테고리를 바꿔 전체 사용자 결과를 오염시킬 수 있다.

## 2. 핵심 테이블

| 역할 | 테이블 | 소유/접근 |
|---|---|---|
| 공용 상품 ID | `fitmatch_catalog.products` | backend only |
| 상품 관측 이력 | `fitmatch_catalog.source_product_snapshots` | backend only |
| 앱 상품 원본 관측 | `fitmatch_catalog.product_observations` | backend only, 동일 payload 중복 제거 |
| 관측 제출 사용자 | `fitmatch_catalog.product_observation_submissions` | backend only |
| 관측 당시 원본 실측 | `fitmatch_catalog.product_observation_measurements` | backend only, immutable |
| 공용 분류 이력 | `fitmatch_catalog.product_classification_history` | backend only |
| 색상/옵션 | `fitmatch_catalog.product_variants` | backend only |
| 판매 사이즈 | `fitmatch_catalog.product_sizes` | backend only |
| 원문+정규화 실측 | `fitmatch_catalog.product_measurements` | backend only |
| 데이터 품질 이슈 원장 | `fitmatch_catalog.data_quality_issues` | backend only, 대상+issue code 중복 제거 |
| 미검증 앱 요청 | `public.product_intake_requests` | 요청자 SELECT, backend 처리 |
| 사용자 옷 | `public.closet_items` | owner RLS |
| 사용자별 분류 변경 | `public.closet_item_classification_overrides` | owner RLS, RPC write |
| 비교 실행 | `public.comparison_runs` | owner RLS, RPC write |
| 사이즈별 결과 | `public.comparison_results` | owner RLS, RPC write |
| 실측별 근거 | `public.comparison_measurement_results` | owner RLS, RPC write |

`source_product_snapshots`는 원본 관측 로그이고 `products`는 현재 공용 ID다. 동일 역할이 아니다.

앱이 링크에서 새로 읽은 값은 곧바로 `products`를 수정하지 않는다. 먼저
`product_observations`에 원본 payload를 보존하고, Edge Function이 검증한 뒤에만
`products / variants / sizes / product_measurements`의 현재 운영값으로 승격한다.
동일 payload는 행을 복제하지 않고 관측 횟수만 올리며, payload가 달라지면 새 이력으로 남긴다.

## 3. 내 옷장 등록 흐름

```text
상품 payload 수신
  ↓ fitmatch_resolve_product
공용 상품 + fingerprint 일치?
  ├─ YES → product_id + 현재 canonical 분류 반환
  └─ NO  → intake_request_id 반환, 공용 상품은 수정하지 않음

신뢰된 backend가 retailer API 결과를 재검증
  ↓ runtime_resolve_and_promote_product
  ├─ 상품별 확정 Gold → 그대로 사용
  ├─ path+상품명 signature가 2개 이상 Gold에서 전부 동일 → 자동 확정
  ├─ path가 2개 이상 Gold에서 전부 동일 → 자동 확정
  ├─ 검증된 제외 상품/path → not_comparable
  └─ 그 외 → review_required (억지 분류 금지)

분류 confirmed?
  ├─ YES → fitmatch_register_closet_item
  └─ NO  → 사용자가 분류 선택 후 override와 함께 등록

저장 결과
  ├─ 공용 canonical snapshot은 closet_items에 보존
  └─ 사용자 변경은 별도 override row에 보존
```

동일 공용 상품이라도 사용자 A/B의 override는 서로 영향을 주지 않는다. 비교 시에는 해당 옷장 row의 override가 canonical보다 우선한다.

## 4. 상품 비교 흐름

```text
내 옷(reference closet item) + 대상 공용 상품
  ↓ fitmatch_find_reference_candidates
사용자별 override를 반영한 effective profile + target canonical profile
  ↓ major/gender/family/detail/length/body-length/실측 overlap
  ├─ direct + 실측 충족 → automatic
  ├─ extended + 실측 충족 → manual_selection
  ├─ 구조 호환, 실측 부족 → measurements_required
  └─ 착용 부위/구조 불일치 → no_compatible_garment

선택된 내 옷
  ↓ fitmatch_begin_comparison
불명확/규칙 없음?
  ├─ YES → blocked (fail closed)
  └─ NO  → pending run 생성

reference size + target size
  ↓ runtime_prepare_size_comparison (backend)
동일 comparison_basis 실측만 pair
  ↓ required / required-any / minimum count 검증
ready=true일 때만 현재 앱 비교 엔진으로 점수 계산
  ↓ fitmatch_complete_comparison
run/result/measurement evidence 저장
```

DB는 현재 앱의 추천 점수를 임의로 재작성하지 않는다. DB가 compatibility와 정규화된 입력을 제공하고, 출시된 앱 엔진이 계산한 결과를 저장한다. 점수 알고리즘의 서버 이전은 별도 parity 작업이다.

## 5. 공개 RPC

### `fitmatch_submit_product_observation(p_payload jsonb) -> jsonb`

인증된 앱이 파서에서 얻은 상품·색상·사이즈·원본 실측을 제출하는 입구다. payload는
크기·배열 수·문자열 길이·양수 실측값을 검증한 뒤 private immutable 관측 이력에만
저장한다. 앱은 공용 상품 current row를 직접 수정할 수 없다.

실제 앱은 이 RPC를 직접 조합하지 않고 JWT 검증이 켜진 Edge Function
`product-observation`을 호출한다. Edge Function은 사용자 권한으로 원본을 접수하고,
service role로 `fitmatch_process_product_observation`을 호출해 분류 → 실측 정규화 →
current runtime 반영을 한 트랜잭션 경계에서 수행한다.

### `fitmatch_resolve_product(p_payload jsonb) -> jsonb`

필수 입력:

```json
{
  "source": "uniqlo",
  "external_product_id": "E492123",
  "product_name": "데님릴렉스셔츠재킷",
  "source_category_path": "상의 > 셔츠"
}
```

알려진 상품은 `catalog_state=current`, `product_id`, `classification`을 반환한다. 신규/변경 상품은 `catalog_state=new|changed`, `intake_request_id`, `status=review_required`를 반환한다.

### `fitmatch_get_product_runtime(p_payload jsonb) -> jsonb`

`resolve_product`와 같은 retailer 증거를 다시 받는다. `source + external_product_id +
product_name + source_category_path` fingerprint와, 제공된 경우 audience/category codes까지
DB current와 일치할 때만 상품·현재 분류·variant·`product_size_id`·raw/canonical 실측을
반환한다. UUID만으로 전체 catalog를 탐색하는 호출은 제공하지 않는다.

상태는 분류와 비교 준비도를 섞지 않고 다음처럼 반환한다.

```text
classification_required | not_comparable | sizes_required |
measurements_required | ready
```

`ready`만 자동 비교 입력으로 사용할 수 있다. 다른 상태는 로컬 엔진 결과로 조용히
대체하는 것이 아니라 해당 원인을 UI/domain layer가 명시적으로 처리해야 한다.

### `fitmatch_register_closet_item(...) -> uuid`

```text
p_product_id uuid
p_product_size_id uuid? 
p_is_reference boolean
p_override jsonb?
```

override를 보낼 때 `category_code`, `detail_code`, `family_code`는 필수다. 길이 축이 필요한 의류는 `length_code`도 보내야 비교 가능하다.

### `fitmatch_set_closet_classification_override(...) -> jsonb`

사용자 소유 옷에만 적용된다. 공용 상품 분류는 바꾸지 않는다.

### `fitmatch_clear_closet_classification_override(...) -> jsonb`

사용자 변경을 삭제하고 해당 옷장 row를 저장 당시 canonical snapshot으로 되돌린다.

### `fitmatch_begin_comparison(...) -> jsonb`

사용자 소유 reference item만 허용한다. 명시적 family/detail/length 규칙이 없으면 `blocked`다.

### `fitmatch_find_reference_candidates(p_target_product_id uuid) -> jsonb`

내 옷장의 effective 분류(사용자 override 우선)를 대상으로 자동/수동 후보를 나눈다. 구조만 맞고 공통 canonical 실측이 부족하면 자동 비교로 가장하지 않고 `measurements_required`를 반환한다. 상의↔하의처럼 착용 부위가 다르면 후보를 반환하지 않는다.

### `fitmatch_complete_comparison(...) -> jsonb`

사용자 소유 pending run만 완료한다. 각 `target_size_id`가 run의 대상 상품에 속하는지 검증한다. 핏 점수와 coverage/data quality/confidence를 별도 저장하고, 사용/제외 실측 수는 제출 배열에서 서버가 다시 계산한다. 새 지표가 없는 구버전 요청도 계속 허용한다.

## 6. Backend 전용 함수

- `fitmatch_process_product_observation(uuid)`
- `runtime_record_observation_issue(uuid,text,text,jsonb)`
- `runtime_resolve_observation_issue(uuid,text,jsonb)`
- `runtime_ingest_product_payload(jsonb)`
- `runtime_resolve_and_promote_product(jsonb)`
- `runtime_resolve_product_classification_v3(...)`
- `runtime_record_product_classification(uuid,jsonb)`
- `runtime_normalize_measurement_v2(...)`
- `runtime_evaluate_product_compatibility(...)`
- `runtime_prepare_size_comparison(...)`
- `validate_product_runtime()`

앱에서 service key를 사용하거나 위 함수를 직접 호출하면 안 된다.

## 7. 실측 payload 계약

```json
{
  "measurement_identity": "body-width",
  "parser_code": "size_chart",
  "raw_code": "body-width",
  "raw_label": "몸폭",
  "raw_value": 50,
  "raw_unit": "cm",
  "category_scope": "tops"
}
```

반드시 raw 값과 정규화 값을 함께 보존한다. `category_scope`가 필요한 alias에 scope가 없으면 비교 불가로 반환한다. 지원 단위는 `cm`, `mm`, `in|inch`다.

교차 쇼핑몰 조인은 retailer 명칭이나 measurement code가 아니라 동일한 `comparison_basis`로 수행한다. 예: 유니클로 허리둘레 80cm는 0.5 변환 후 `waist_edge_to_edge=40cm`가 된다.

## 8. 상태와 fail-safe

| 상태/사유 | 처리 |
|---|---|
| `confirmed` | canonical 사용 가능 |
| `review_required` | 사용자/운영 검토 전 자동 비교 금지 |
| `unclassified` | 분류 입력 필요 |
| `not_comparable` | 비교 금지 |
| `no_unanimous_verified_profile` | 기존 카테고리여도 검증된 결론이 하나가 아니면 검토 |
| `detail_mismatch` | 명시적 상세 호환 규칙 없으면 차단 |
| `length_classification_missing` | 길이축 필수 상품 차단 |
| `compatibility_rule_missing` | 차단 |
| `measurement_alias_not_found` | 해당 실측 제외/수집 검토 |
| `insufficient_common_measurements` | 점수 계산 금지 |

False-compatible 방지가 coverage보다 우선이다.

## 9. 앱 관측 저장 흐름

```text
쇼핑몰 링크 입력
  ↓ iOS retailer parser
상품/카테고리/색상/사이즈/원본 실측 추출
  ↓ Edge Function product-observation (사용자 JWT 필수)
immutable product_observations + raw measurement rows 저장
  ↓ backend-only process RPC
canonical 상품 분류 → measurement alias 정규화
  ↓
products / variants / sizes / product_measurements 최신 운영값 반영
  ↓
기존 DB runtime 조회와 로컬 비교 shadow는 계속 진행
```

현재 iOS 관측 payload가 보존하는 범위는 파서가 추출한 모든 상품 필드와
`measurementRecords`다. 쇼핑몰 HTTP 응답 원문 전체 body는 파서 모델이 전달하지 않으므로
아직 포함되지 않는다. 전체 HTTP 원문 저장은 개인정보·용량·쇼핑몰 약관을 검토한 뒤
별도 object storage 정책으로 결정하며, 현재 비교 정확도에 필요한 원본 실측 보존과는 구분한다.

## 10. 적용 및 검증 결과

- 공용 상품: 1,577
- 상품 관측 스냅샷: 3,842 / 연결 3,842
- current 분류 이력: 1,577 / 공용 상품 1,577
- current 상태: confirmed 1,076 / not_comparable 169 / review_required 332
- variant: 2,576
- 판매 사이즈: 6,545
- 정규화 실측: 27,492
- 분류 Gold: 5,026 / 5,026 (100%)
- category-family 모순: 0
- current 중복 분류: 0
- 공개 SECURITY DEFINER의 anon EXECUTE: 0
- 동시 동일 상품 upsert: 동일 UUID 반환
- 유니클로↔무신사 실측 왕복: 3개 공통 실측, `ready=true`
- 신상품 가정 Gold 재생: 자동 2,536 / 정답 2,536 / 오답 0
- 자동 제외 path: 40
- 후보 RPC 통합: 반팔 티↔긴팔 셔츠 `manual_selection`, 상의↔하의 후보 0

배치 연동으로 `product_sizes`와 `product_measurements` 운영 적재가 시작됐다. 다만 모든 상품/사이즈의 실측 완전성을 뜻하지는 않는다. 상품별 누락은 후보 RPC가 `measurements_required` 또는 후보 없음으로 fail-closed 처리해야 한다.

## 10. iOS 연동 순서

1. 기존 로컬 엔진 출시는 유지한다. (완료)
2. `connectDB` 브랜치에서 DB DTO/RPC client를 추가한다. (완료)
3. `resolve_product`를 shadow 호출하고 로컬 결과와 비교한다. (구현 완료, 운영 인증 설정 대기)
4. 알려진 상품의 canonical 분류·size ID·정규화 실측을 scoped runtime RPC로 읽는다. (계약/RPC 완료, 화면 연결 대기)
5. batch/Edge Function을 통해 variant/size/measurement를 적재한다.
6. `runtime_prepare_size_comparison` 입력과 로컬 엔진 입력 parity를 검증한다.
7. 5,026 Gold + 실제 상품 표본 + false-compatible 0 기준을 통과한 뒤 DB 경로를 기본값으로 전환한다.

## 11. 반박 및 남은 리스크

- “DB가 100% 완성됐으니 앱만 붙이면 즉시 모든 비교가 된다”는 표현은 부정확하다. 운영 사이즈/실측 row가 아직 없으므로 수집 결과 적재가 필요하다.
- comparison detail 확장 규칙은 현재 빈 상태다. 동일 상세는 direct, 다른 상세는 안전하게 blocked다. 앱의 선택형 확장 비교를 서버로 옮길 때 검증된 rule만 추가해야 한다.
- 5,026 분류 Gold의 4건은 category/detail과 family가 모순되어 DB Gold 자체를 교정했다. 로컬 JSON fixture도 새 브랜치에서 같은 네 건을 맞춰야 한다.
- Supabase의 `SECURITY DEFINER` 경고는 의도적이다. 모든 공개 RPC는 `auth.uid()` 확인, 빈 search path, 객체 소유권 확인, anon revoke를 적용했다.
- 현재 프로젝트의 anonymous sign-in은 비활성화 상태다. 앱에 정식 로그인 세션이 아직 없으므로 실제 shadow 호출은 인증 실패 후 로컬 fallback으로 끝난다. Dashboard에서 anonymous sign-in을 활성화하거나 정식 Auth를 연결하기 전까지 DB 호출 성공을 운영 완료로 간주하면 안 된다.

## 11-1. iOS shadow 연동 현황

- `FitMatchSupabaseDomainClient`가 publishable key와 하나의 authenticated session으로 상품 resolve/runtime, 옷장 등록, 후보 조회, 비교 시작/완료 RPC를 호출한다. 기존 이름은 typealias로 호환한다.
- `ShoppingProductViewModel`은 API 파싱 성공/부분 성공 뒤 DB를 비동기로 조회하되 로컬 분류 결과를 변경하지 않는다.
- current+confirmed 완전 일치만 `matched`, 신규/변경/비확정은 `reviewRequired`, 현재 확정값 불일치는 `mismatch`, 인증·네트워크 오류는 `unavailable`이다.
- `E482202`의 속옷 major/T셔츠 family 모순은 migration 097과 로컬 resolver 양쪽에서 `underwear` family로 교정했다.
- 운영 검증: `passed=true`, Gold 5,026/5,026, category-family 모순 0.
- migration `add_scoped_product_runtime_read_contract`는 retailer evidence가 일치할 때만 private catalog의 필요한 runtime projection을 반환한다. 운영 인증 컨텍스트에서 `E492538`이 `ready`, variant 2, size 12, measurement 72를 반환했고 변조된 이름/경로는 `product_evidence_mismatch`로 차단됐다.

## 12. 운영 명령

검증:

```sql
select fitmatch_qa.validate_product_runtime_v3();
```

비상 중단은 데이터 삭제가 아니라 RPC 진입을 막는 [087_product_runtime_safe_rollback.sql](../supabase/sql/087_product_runtime_safe_rollback.sql)을 사용한다.

## 13. 로컬 retailer 배치 계약

- 바탕화면 실행 진입점은 `유니클로_신규상품_배치.command`, `무신사_신규상품_배치.command` 두 개다. 결과는 각각 `유니클로_배치결과`, `무신사_배치결과`에 쌓인다.
- 배치는 관측 ID를 최대 5,000개씩 `fitmatch_batch_products_needing_ingest`에 보내 DB 미적재/이전 계약 상품을 확인한다.
- 상세·공식 사이즈표를 수집한 뒤 `fitmatch_batch_ingest_product`를 상품별로 호출한다. 이 RPC 한 트랜잭션에서 상품/variant/size/measurement upsert와 current canonical classification 기록을 완료한다.
- 최종 상태는 `confirmed`, `not_comparable`, `review_required`, `unclassified` 중 하나다. `review_required`를 임의 category로 강제하지 않는다.
- DB 미완료 상품이 하나라도 있으면 배치는 종료 코드 3을 반환하고 로컬 원장에 완료 상품으로 승격하지 않는다. 결과 폴더의 `db_ingest_results.json`과 `summary.json`에서 재시도 대상을 확인한다.
- secret/service-role key는 소스나 결과 파일에 저장하지 않고 macOS Keychain에서 읽는다. `anon`/`authenticated`에는 두 batch RPC 실행권이 없다.
- 첫 DB 연동 실행은 기존 DB 상품에 batch version marker가 없으므로 현재 관측 범위의 상세·실측을 backfill한다. 이후에는 신규/미완료 상품만 다시 수집한다.

## 14. 인증 사용자 옷장 CRUD 계약

옷장 데이터의 장기 원본은 Supabase이고 SwiftData는 로컬 캐시와 오프라인 outbox 역할을 맡는다. 로그인 완료 후 `FitMatchClosetSyncCoordinator`가 서버와 동기화하며 기존 화면은 SwiftData를 계속 읽으므로 UI와 오프라인 사용성을 유지한다.

- `client_item_id`: 앱에서 만든 안정적인 UUID다. 네트워크 재시도 시 같은 항목이 중복 생성되지 않도록 `(user_id, client_item_id)`를 유일하게 유지한다.
- `fitmatch_upsert_closet_item`: 수동 등록과 공용 catalog 상품 등록을 하나의 진입점으로 처리한다. catalog 상품은 DB canonical 분류를 우선하고, 수동 상품은 안전하게 해석할 수 있는 category/family만 확정한다. 불명확하면 `review_required`로 저장해 자동 비교를 막는다.
- `fitmatch_list_closet_items`: 로그인 사용자 본인의 활성 옷장만 반환한다. canonical snapshot, 사용자 override, 원본 실측 record와 동기화 revision을 함께 반환한다.
- `fitmatch_set_closet_reference`: 동일 사용자·성별·대분류·상세분류 범위에서 대표 옷을 하나만 유지한다.
- `fitmatch_delete_closet_item`: 실제 row 삭제 대신 `deleted_at`을 기록하는 soft delete다.
- authenticated 사용자의 `closet_items` 직접 INSERT/UPDATE/DELETE 권한은 제거했다. 앱은 위 RPC만 호출하며 모든 함수는 `auth.uid()`와 소유권을 다시 검증한다.
- `measurement_records`에는 숫자만 남기지 않고 raw label/value, 단위, 입력 출처, mapping version, evidence를 보존한다. 서버 재분류나 감사 시 입력 근거를 재현할 수 있다.
- migration `099_authenticated_closet_crud_contract.sql`이 운영 프로젝트에 `authenticated_closet_crud_contract_v1`으로 적용됐다.
- migration `100_closet_sync_hydration_contract.sql`이 운영 프로젝트에 `closet_sync_hydration_contract_v1`으로 적용됐다. 재설치 복원에 필요한 retailer 상품 ID, audience, 원본 category code를 사용자 소유 옷장 행을 통해서만 반환한다.
- 앱의 `UserFit.id`를 그대로 `client_item_id`로 사용한다. 로컬 신규/수정은 멱등 upsert되고, 삭제는 사용자별 tombstone으로 보관한 뒤 soft-delete RPC 성공 시 제거한다.
- 같은 사용자의 재로그인은 로컬 캐시를 유지한다. 다른 계정으로 전환되면 이전 계정의 `UserFit`과 비교 기록을 먼저 제거한 뒤 새 계정의 서버 옷장을 복원해 계정 간 데이터 혼합을 막는다. 공용 상품 캐시는 사용자 데이터가 아니므로 유지한다.
- 충돌은 client/server `updated_at`을 비교해 서버가 더 최신이면 내려받고, 그 외에는 로컬 변경을 올린다. 부분 실패는 `pendingRetry`로 남기며 다음 동기화에서 재시도한다.

단위 검증에서는 서버에만 존재하는 유니클로 옷장 행이 동일한 `client_item_id`, retailer 상품 ID, category code, size/measurement와 함께 SwiftData로 복원됐다. 남은 한계는 실제 Apple 로그인 세션을 이용한 upsert→재조회→삭제→재설치/재로그인 통합 검증과, 비교 실행·결과 저장 RPC를 현재 추천 화면 흐름에 연결하는 작업이다.

## 15. 비교 이력 동기화 계약

기존 추천 결과의 사용자 체감과 신뢰도를 바꾸지 않기 위해 현재 단계에서는 로컬 비교 엔진이 점수와 추천 size를 결정한다. Supabase는 동일 입력의 canonical 검증, 비교 허용 여부, durable run/result/evidence 저장을 담당한다.

```text
RecommendationHistory 생성
  → 옷장 동기화 완료 확인
  → retailer 증거로 대상 상품 resolve
  → scoped runtime에서 DB product/size UUID 확정
  → fitmatch_find_reference_candidates
  → fitmatch_begin_comparison(client_history_id)
  → 로컬 점수·사용/제외 실측을 fitmatch_complete_comparison에 저장
```

- `client_history_id`는 로컬 `RecommendationHistory.id`이며 사용자 범위에서 유일하다. 동일 ID 재호출은 기존 run을 반환하고 다른 reference/target 조합으로 재사용하면 오류가 난다.
- 수동 옷장은 catalog size가 없어도 저장된 정규화 실측으로 overlap을 계산한다. 분류 우선순위는 사용자 override, catalog canonical snapshot, 수동 `app_category/app_detail_category` 순이다.
- candidate가 direct이면 `allow_extended=false`, direct는 아니지만 manual-ready이면 `allow_extended=true`로 시작한다. 구조·실측이 부족하면 DB가 `blocked`를 기록하고 앱은 해당 로컬 결과를 서버의 완료 결과로 가장하지 않는다.
- 추천 size는 DB runtime 안에서 color와 정규화 size label로 정확히 하나가 확인될 때만 저장한다. 0개 또는 중복이면 `pendingRetry`로 두어 잘못된 size FK를 만들지 않는다.
- `comparison_results`에는 추천 핏 점수, rank, comparable 여부와 별도로 `coverage_ratio`, `data_quality_score`, `confidence_score`, 사용/제외 실측 수, 계산 버전을 저장한다. 핏이 비슷하다는 의미와 근거가 충분하다는 의미를 하나의 숫자로 섞지 않는다.
- `comparison_measurement_results`에는 canonical measurement code, 양쪽 값, 차이, weight, 포함/제외 사유와 evidence를 저장한다. RPC는 이 배열의 `included` 값으로 결과 행의 사용/제외 개수를 재계산한다.
- 앱의 처리 완료 원장은 사용자별 `UserDefaults`에 저장한다. DB unique index가 최종 멱등성을 보장하며 앱 원장은 불필요한 재호출을 줄이는 캐시다.

적용 migration은 `101_comparison_sync_contract.sql`, `102_manual_closet_comparison_fallback.sql`, `105_comparison_quality_and_data_issue_contract.sql`이다. 자동 테스트는 성공 저장, 동일 history 중복 방지, DB 차단 시 결과 미저장과 새 품질 지표 JSON 전송까지 검증한다.

현재 한계는 두 가지다. 첫째, DB 비교 결과를 재설치 후 로컬 `RecommendationHistory`로 다시 내려받는 read/hydration 계약은 없다. 둘째, 공용 catalog UUID가 없는 수동 URL/지원 외 쇼핑몰 비교는 로컬 기록만 유지한다. 실제 Apple 로그인 세션의 end-to-end 검증 전에는 운영 완료로 판정하지 않는다.
