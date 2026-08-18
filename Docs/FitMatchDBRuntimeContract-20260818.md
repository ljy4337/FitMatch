# FitMatch DB Runtime Contract

- 기준일: 2026-08-18
- DB 기반 버전: `db-runtime-2026-08-18-v1`
- 신규 상품 분류 버전: `db-auto-classifier-2026-08-18-v2`
- 비교 후보 정책 버전: `db-comparison-2026-08-18-v2`
- 대상: 출시 후 DB 연동 브랜치의 iOS/서버 개발
- 원칙: 공용 사실, 사용자 선택, 비교 실행 이력을 분리한다.

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
| 공용 분류 이력 | `fitmatch_catalog.product_classification_history` | backend only |
| 색상/옵션 | `fitmatch_catalog.product_variants` | backend only |
| 판매 사이즈 | `fitmatch_catalog.product_sizes` | backend only |
| 원문+정규화 실측 | `fitmatch_catalog.product_measurements` | backend only |
| 미검증 앱 요청 | `public.product_intake_requests` | 요청자 SELECT, backend 처리 |
| 사용자 옷 | `public.closet_items` | owner RLS |
| 사용자별 분류 변경 | `public.closet_item_classification_overrides` | owner RLS, RPC write |
| 비교 실행 | `public.comparison_runs` | owner RLS, RPC write |
| 사이즈별 결과 | `public.comparison_results` | owner RLS, RPC write |
| 실측별 근거 | `public.comparison_measurement_results` | owner RLS, RPC write |

`source_product_snapshots`는 원본 관측 로그이고 `products`는 현재 공용 ID다. 동일 역할이 아니다.

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

사용자 소유 pending run만 완료한다. 각 `target_size_id`가 run의 대상 상품에 속하는지 검증한다.

## 6. Backend 전용 함수

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

## 9. 적용 및 검증 결과

- 공용 상품: 1,542
- 상품 관측 스냅샷: 3,842 / 연결 3,842
- current 분류 이력: 1,542 / 공용 상품 1,542
- current 상태: confirmed 1,114 / not_comparable 184 / review_required 244
- 기본 variant: 1,542
- 분류 Gold: 5,026 / 5,026 (100%)
- category-family 모순: 0
- current 중복 분류: 0
- 공개 SECURITY DEFINER의 anon EXECUTE: 0
- 동시 동일 상품 upsert: 동일 UUID 반환
- 유니클로↔무신사 실측 왕복: 3개 공통 실측, `ready=true`
- 신상품 가정 Gold 재생: 자동 2,536 / 정답 2,536 / 오답 0
- 자동 제외 path: 40
- 후보 RPC 통합: 반팔 티↔긴팔 셔츠 `manual_selection`, 상의↔하의 후보 0

현재 `product_sizes`와 `product_measurements`의 운영 row는 0이다. 기존 수집 스냅샷에는 실제 사이즈표 원문이 없기 때문이다. 구조/정규화/후보 프로시저는 검증됐지만, 연동 브랜치에서 검증된 retailer fetch 결과를 backend 경로로 적재해야 실제 비교가 DB 입력을 사용한다. 실측 없는 상품은 후보 RPC가 `measurements_required` 또는 후보 없음으로 fail-closed 처리한다.

## 10. iOS 연동 순서

1. 기존 로컬 엔진 출시는 유지한다.
2. 새 브랜치에서 DB DTO/RPC client를 추가한다.
3. `resolve_product`를 shadow 호출하고 로컬 결과와 비교한다.
4. 알려진 상품의 canonical 분류를 읽되 추천 점수는 기존 엔진으로 계산한다.
5. batch/Edge Function을 통해 variant/size/measurement를 적재한다.
6. `runtime_prepare_size_comparison` 입력과 로컬 엔진 입력 parity를 검증한다.
7. 5,026 Gold + 실제 상품 표본 + false-compatible 0 기준을 통과한 뒤 DB 경로를 기본값으로 전환한다.

## 11. 반박 및 남은 리스크

- “DB가 100% 완성됐으니 앱만 붙이면 즉시 모든 비교가 된다”는 표현은 부정확하다. 운영 사이즈/실측 row가 아직 없으므로 수집 결과 적재가 필요하다.
- comparison detail 확장 규칙은 현재 빈 상태다. 동일 상세는 direct, 다른 상세는 안전하게 blocked다. 앱의 선택형 확장 비교를 서버로 옮길 때 검증된 rule만 추가해야 한다.
- 5,026 분류 Gold의 4건은 category/detail과 family가 모순되어 DB Gold 자체를 교정했다. 로컬 JSON fixture도 새 브랜치에서 같은 네 건을 맞춰야 한다.
- Supabase의 `SECURITY DEFINER` 경고는 의도적이다. 모든 공개 RPC는 `auth.uid()` 확인, 빈 search path, 객체 소유권 확인, anon revoke를 적용했다.

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
