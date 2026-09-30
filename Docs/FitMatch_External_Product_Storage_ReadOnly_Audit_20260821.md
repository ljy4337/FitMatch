# FitMatch 외부 쇼핑몰 상품 데이터 저장 구조 READ-ONLY 감사

감사 기준: 2026-08-21 운영 Supabase `FitMatch` 프로젝트와 현재 iOS production 코드  
수행 범위: DB·production 코드·migration 변경 없이 읽기 전용 조사

## A. 현재 실제 데이터 흐름

무신사·유니클로:

상품 URL 입력  
→ `ProductURLParserService`  
→ 쇼핑몰 전용 parser/API  
→ `ParsedProductInfo`, size, measurement 생성·정규화  
→ 로컬 `ComparisonEngine`  
→ SwiftData `Product`, `ProductSize`, `UserFit`, `RecommendationHistory`  
→ Supabase 옷장·비교 동기화

현재 다음 서버 저장 경로도 활성화되어 있다.

상품 URL 분석 성공 또는 부분 성공  
→ `submitProductObservation`  
→ `product-observation` Edge Function  
→ `fitmatch_catalog.product_observations` 저장  
→ `fitmatch_process_product_observation`  
→ `fitmatch_catalog.products/product_variants/product_sizes/product_measurements` 영구 승격

또한 `fitmatch_resolve_product`는 catalog에 없는 상품을 조회할 때 `public.product_intake_requests`에 입력 payload를 저장한다. 따라서 현재 “DB shadow 조회”는 완전한 read-only 조회가 아니다.

ZARA:

- parser 코드는 존재한다.
- Release build에서는 `ZARAIntegrationAvailability.isEnabled=false`다.
- 일반 production 사용자 URL 입력 경로에서는 실행되지 않는다.
- 운영 DB의 ZARA 30상품은 사용자 URL 관측이 아니라 관리자 A-test preload다.
- DEBUG gate가 열린 경우에만 URL → HTML analytics identity → size guide API → normalize 경로를 사용한다.

## B. 현재 Supabase 관련 테이블

### FitMatch master data

- `public.sources`
- `public.brands`
- `public.app_categories`
- `public.source_categories`
- `public.source_category_mappings`
- `public.client_source_category_mappings`
- `public.measurement_items`
- `public.category_measurement_items`
- `public.source_measurement_mappings`
- `public.garment_types`
- comparison policy 관련 테이블
- `fitmatch_taxonomy.*`

### 사용자 데이터

- `public.profiles`
- `public.user_settings`
- `public.closet_items`
- `public.closet_item_classification_overrides`
- `public.comparison_runs`
- `public.comparison_results`
- `public.comparison_measurement_results`
- `public.comparison_history`

### 외부 쇼핑몰 상품 데이터

- `fitmatch_catalog.products`
- `fitmatch_catalog.product_variants`
- `fitmatch_catalog.product_sizes`
- `fitmatch_catalog.product_measurements`
- `fitmatch_catalog.source_product_snapshots`
- `fitmatch_catalog.product_observations`
- `fitmatch_catalog.product_observation_measurements`
- `fitmatch_catalog.product_observation_submissions`
- product classification history/decision 관련 테이블
- `public.product_intake_requests`

### 캐시·임시·QA 데이터

- `fitmatch_staging.*`
- `fitmatch_qa.*`
- collection/import/sampling/parity run 관련 테이블
- `private` 스키마의 과거 mapping 백업 테이블

### 실제 주요 행 수

| source | products | variants | sizes | measurements | snapshots | observations |
|---|---:|---:|---:|---:|---:|---:|
| Musinsa | 394 | 394 | 572 | 2,229 | 767 | 1 |
| Uniqlo | 1,184 | 2,184 | 5,987 | 25,319 | 3,075 | 1 |
| ZARA | 30 | 75 | 188 | 870 | 0 | 0 |
| 합계 | 1,608 | 2,653 | 6,747 | 28,418 | 3,842 | 2 |

기타 실제 행 수:

- `sources`: 3
- `source_categories`: 2,293
- `measurement_items`: 25
- `brands`: 0
- `category_measurement_items`: 0
- `profiles`: 2
- `closet_items`: 5
- `comparison_history`: 0
- `comparison_runs`: 0
- `comparison_results`: 0
- `product_intake_requests`: 3
- Storage bucket/object: 모두 0

주요 FK:

- `closet_items.product_id` → `fitmatch_catalog.products.id`, `ON DELETE RESTRICT`
- `closet_items.product_size_id` → `fitmatch_catalog.product_sizes.id`, `ON DELETE SET NULL`
- `comparison_runs.target_product_id` → `fitmatch_catalog.products.id`, `ON DELETE RESTRICT`
- `comparison_results.target_size_id` → `fitmatch_catalog.product_sizes.id`, `ON DELETE SET NULL`

따라서 기존 catalog 상품을 즉시 삭제하면 옷장·비교 FK와 runtime 조회가 깨질 수 있다.

## C. 외부 상품 데이터 중 현재 영구 저장되는 필드

| 필드 | Supabase 영구 저장 | SwiftData 저장 | 비고 |
|---|---|---|---|
| source product ID | 예 | 예 | catalog, observation, closet/history snapshot |
| URL | 예 | 예 | canonical URL 또는 product URL |
| 상품명 | 예 | 예 | catalog 및 사용자 snapshot |
| 이미지 | URL만 저장 | URL 저장 | 이미지 binary/Storage 복제 없음 |
| 가격 | JSON payload 등에 저장 | Product/history snapshot | catalog 전용 price 컬럼은 없음 |
| 설명 | 확인되지 않음 | 모델 필드 없음 | 현재 observation payload에도 없음 |
| category | 예 | 예 | source category와 canonical classification |
| size 목록 | 예 | 예 | catalog 전체 size 및 로컬 상품 snapshot |
| measurements | 예 | 예 | raw, normalized, comparable 값과 evidence |
| 색상·variant | 예 | 예 | variant/color identity |
| 기타 원본 데이터 | 예 | 일부 | raw payload, raw label/code, parser metadata |

현재 observation payload에는 source, external product ID, 상품명, canonical URL, audience, source category path/codes, image URL, variant와 색상, 모든 size, 모든 measurement, raw measurement label/code/value, parser metadata, 가격 일부가 포함된다.

Edge Function은 이 payload를 관측 테이블에 저장한 뒤 중앙 catalog로 승격한다.

## D. 문제 없는 부분

- canonical taxonomy 구조는 목적에 맞다.
- source category와 FitMatch category mapping은 유지해야 한다.
- measurement definition과 comparison policy 구조는 유지해야 한다.
- 쇼핑몰 이미지를 Supabase Storage에 복제하지 않는다.
- HTML 전체나 상품 설명 전체를 SwiftData Product에 보존하지 않는다.
- 사용자 옷장에는 선택한 상품·사이즈·실측 snapshot을 유지한다.
- 비교 기록에는 당시 상품명·URL·이미지·가격·분류·비교 결과 snapshot을 유지한다.
- 이 snapshot은 오프라인 표시와 과거 비교 재조회에 필요하다.
- `closet_items.product_id`가 nullable이므로 catalog 미등록 상품도 사용자 snapshot만으로 저장할 수 있다.
- ZARA Release gate가 닫혀 있어 미검증 URL 흐름이 일반 사용자에게 노출되지 않는다.

## E. 변경이 필요한 부분

1. URL 분석마다 `submitProductObservation`을 자동 실행하는 iOS 동작
2. 사용자 관측 상품을 중앙 catalog로 즉시 영구 승격하는 Edge Function
3. catalog miss를 `product_intake_requests`에 영구 기록하는 `fitmatch_resolve_product`
4. 비교 서버 동기화가 catalog의 `target_product_id/target_size_id`를 필수로 요구하는 구조
5. observation/intake 데이터의 TTL 또는 명시적 삭제 정책 부재

현재 구조에는 외부 쇼핑몰 상품을 FitMatch 중앙 상품 카탈로그로 영구 축적하는 구조가 실제로 존재한다.

## F. 변경하지 말아야 할 부분

- canonical taxonomy
- source category 및 FitMatch mapping
- measurement definitions
- comparison rules/weights
- 사용자 closet data
- 사용자 comparison history
- SwiftData `Product`
- SwiftData `ProductSize`
- SwiftData `UserFit`
- SwiftData `RecommendationHistory`
- 옷장에 저장된 상품명·URL·이미지·선택 사이즈·실측 snapshot
- 비교 결과의 측정값·차이·coverage·confidence snapshot
- 기존 catalog 데이터의 즉시 삭제
- 기존 FK의 사전 전환 없는 제거

SwiftData와 사용자 snapshot을 축소하면 앱 재시작, 오프라인 동작, 옷장 재조회, 비교 기록 재조회 및 동기화가 깨질 수 있다.

## G. 최소 변경안

1. iOS에서 URL 분석 직후 실행되는 `submitProductObservation` 자동 호출을 제거한다.
2. 기존 catalog에 대한 `fitmatch_resolve_product` shadow 조회는 유지한다.
3. `fitmatch_resolve_product`를 실제 read-only 함수로 바꾼다.
4. catalog miss에서는 `product_intake_requests`를 생성하지 않고 `not_found` 또는 `review_required`만 반환한다.
5. product observation 제출 권한을 관리자·명시적 QA ingest로 제한한다.
6. 일반 authenticated 앱은 중앙 catalog를 증식시키지 못하게 한다.
7. catalog에 없는 상품의 비교 기록은 catalog FK 없이 사용자 소유 snapshot으로 저장할 fallback RPC를 추가한다.
8. 옷장 동기화는 현재의 `product_id=NULL` fallback을 유지한다.
9. 기존 catalog 1,608상품과 observation 2건은 당장 삭제하지 않는다.
10. 기존 데이터 cleanup은 FK 사용 현황과 회귀 검증 후 별도 단계로 수행한다.

목표 흐름:

사용자 URL 입력  
→ 쇼핑몰 on-demand 조회  
→ normalize  
→ 로컬 ComparisonEngine  
→ SwiftData snapshot  
→ 옷장·비교 기능에 필요한 사용자 snapshot과 결과만 Supabase 저장

## H. 필요한 SQL migration 목록

이번 단계에서는 실행하지 않는다.

### 1. `make_product_resolution_read_only`

- `fitmatch_resolve_product`의 `product_intake_requests` INSERT 제거
- catalog miss에서 상태만 반환

### 2. `restrict_product_observation_submission`

- `fitmatch_submit_product_observation(jsonb)`의 `authenticated` 실행권 회수
- `service_role` 또는 별도 관리자 ingest 경계만 유지

### 3. `add_uncatalogued_comparison_snapshot_sync`

- `comparison_history`에 `client_history_id` 추가
- `(user_id, client_history_id)` unique constraint 추가
- catalog product/size FK 없이 사용자 product/result snapshot을 upsert하는 소유권 제한 RPC 추가

### 4. 선택적 `define_observation_retention`

- 관리 목적 observation을 계속 사용할 경우 TTL/status 기반 정리 정책 추가
- 사용자 제출 원본 데이터의 무기한 보존 방지

### 5. 기존 catalog cleanup

현재 필요한 migration 목록에 포함하지 않는다.

기존 catalog 삭제는 `closet_items` FK, `comparison_runs/results` FK, runtime size 조회, 기존 사용자 동기화, rollback 및 데이터 복구 방법을 먼저 확인한 뒤 별도 결정해야 한다.

Edge Function은 SQL migration과 별도로 일반 사용자 요청에서 `runtime_resolve_and_promote_product` 호출을 제거해야 한다.

## I. iOS 영향 파일 목록

최소 변경 예상 파일:

- `FitMatch/ViewModels/ShoppingProductViewModel.swift`
  - 자동 product observation 제출 제거
- `FitMatch/Services/FitMatchSupabaseProductResolver.swift`
  - read-only resolve 계약 반영
  - catalog 미등록 comparison history fallback RPC 추가
- `FitMatch/Services/FitMatchComparisonSyncCoordinator.swift`
  - catalog miss 시 snapshot-only 동기화
- `FitMatchTests/FitMatchSupabaseProductResolverTests.swift`
- `FitMatchTests/FitMatchComparisonSyncCoordinatorTests.swift`

변경하지 않을 파일/영역:

- `Product.swift`
- `ProductSize.swift`
- `UserFit.swift`
- `RecommendationHistory.swift`
- canonical taxonomy
- category mapping
- measurement definitions
- comparison engine
- comparison weights

## J. 데이터 손실/회귀 위험

1. 기존 catalog를 삭제하면 `closet_items`와 `comparison_runs`의 `RESTRICT` FK가 깨질 수 있다.
2. catalog product/size ID를 사용하는 runtime 조회와 비교 후보 조회가 실패할 수 있다.
3. observation만 중단하고 comparison fallback을 추가하지 않으면 신규 상품 비교는 로컬에서 성공해도 서버 동기화가 계속 재시도 상태가 된다.
4. SwiftData 상품 snapshot을 제거하면 오프라인 옷장·기록 표시가 손실된다.
5. RecommendationHistory snapshot을 제거하면 당시 가격·이미지·상품명·URL·비교 근거를 다시 표시할 수 없다.
6. catalog 가격 일부가 raw JSON 안에 있으므로 cleanup 시 예상보다 넓은 데이터가 삭제될 수 있다.
7. 현재 서버 `comparison_history`는 0건이며 iOS 동기화는 로컬 기록 업로드 중심이다. 원격 비교 기록 복원이 완성됐다고 가정하면 안 된다.
8. ZARA 30상품은 관리자 A-test 데이터이므로 일반 사용자 observation과 구분해야 한다.
9. 기존 catalog cleanup은 즉시 실행하지 말고 FK·사용자 데이터·rollback 검증 후 별도 단계로 진행해야 한다.

## 최종 결론

현재 FitMatch에는 외부 쇼핑몰 상품을 중앙 상품 카탈로그처럼 영구 축적하는 구조가 실제로 존재한다.

특히 iOS URL 분석 직후 상품·variant·전체 size·실측·일부 원본 데이터를 observation으로 제출하고, 운영 Edge Function이 이를 `products/product_variants/product_sizes/product_measurements`로 승격한다.

최소 변경 방향은 다음과 같다.

- 기존 catalog는 즉시 삭제하지 않는다.
- 일반 앱의 observation/intake 자동 쓰기를 중단한다.
- catalog 조회는 read-only로 유지한다.
- 신규 catalog 미등록 상품은 on-demand로 비교한다.
- 옷장과 비교 기록에는 사용자 기능에 필요한 snapshot과 결과만 저장한다.
- SwiftData와 사용자 snapshot은 오프라인·재조회·동기화를 위해 유지한다.
