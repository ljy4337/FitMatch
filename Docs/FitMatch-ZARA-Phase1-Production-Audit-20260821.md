# FitMatch ZARA Integration — Phase 1 Production Audit

기준일: 2026-08-21 (KST)  
문서 용도: 다른 채팅·작업자에게 그대로 전달할 수 있는 독립형 조사 보고서  
작업 범위: 코드, 운영 DB, ZARA KR 응답의 읽기 전용 조사  
변경 여부: 앱 코드 및 운영 Supabase 변경 없음

## 핵심 결론

FitMatch의 기존 무신사·유니클로 공통 파이프라인은 ZARA에도 대부분 재사용할 수 있다. ZARA 전용 비교 엔진이나 별도 내 옷장 흐름은 필요하지 않다.

그러나 현재 상태로는 production DB 구현에 바로 들어가면 안 된다. 운영 DB에는 ZARA source/category/measurement mapping이 없고, observation CHECK도 ZARA를 허용하지 않는다. 더 큰 문제는 ZARA 상품 URL에서 실측 API용 내부 `productId`를 안정적으로 얻는 production-safe 경로가 확인되지 않았다는 점이다. 또한 실측 API는 상품에 따라 완성 의류 실측인 `measureGuideInfo`가 아니라 신체 권장치인 `sizeGuideInfo`만 반환한다.

## 1. 현재 architecture

현재 실제 실행 흐름은 다음과 같다.

```text
상품 URL 입력
→ provider URL 판별
→ provider parser
→ ParsedProductInfo 공통 모델
→ Supabase 상품 resolve + raw observation shadow 제출
→ runtime product / variant / size / measurement
→ 내 옷장 등록 및 기준 옷 설정
→ 비교 후보 조회
→ 로컬 비교·추천 계산
→ comparison run/result/history 저장
```

주요 코드 경로:

- `FitMatch/FitMatch/Services/ProductURLParserService.swift`
  - `ParsedProductInfo`, `ParsedProductSize`, `ParsedMeasurement` 공통 구조를 정의한다.
  - `ProductURLSupport`가 Musinsa, Uniqlo, ZARA, COS URL을 판별한다.
  - provider별 parser를 같은 진입점 아래에서 호출한다.
- `FitMatch/FitMatch/Services/MusinsaParser.swift`
  - metadata → 공식 실측 → 검증 → fallback/OCR → partial error 흐름이다.
- `FitMatch/FitMatch/Services/MusinsaProductMetadataParser.swift`
  - 상품 metadata API에서 상품명, 카테고리, 성별, 이미지 등을 읽는다.
- `FitMatch/FitMatch/Services/MusinsaActualSizeAPIParser.swift`
  - 공식 실측을 읽고 source measurement mapping policy로 canonical measurement에 연결한다.
- `FitMatch/FitMatch/Services/UniqloParser.swift`
  - HTML에서 product ID와 color를 해석한 뒤 공식 size-chart API와 mapping policy를 사용한다.
- `FitMatch/FitMatch/Services/ZARAParser.swift`
  - URL의 `-p########.html`을 style 번호로 추출한다.
  - 상품 HTML의 `zara.analyticsData.productId`에서 실측 API용 내부 product ID를 찾는다.
  - `size-measure-guide`의 `measureGuideInfo`만 완성 의류 실측으로 사용한다.
  - `sizeGuideInfo`만 있으면 신체 권장치로 판단하여 자동 비교를 실패 종료한다.
  - Akamai/bot challenge HTML을 감지한다.
  - 현재 category 판정은 `section/family/subfamily/productName` 문자열 규칙이며 미일치 시 top/shortSleeve로 기본값을 둔다. 이 기본값은 production taxonomy 용도로 안전하지 않다.
- `FitMatch/FitMatch/Services/FitMatchSupabaseProductResolver.swift`
  - 공통 DB resolve 및 observation 제출 경계다.
  - ZARA source code를 payload로 만들 수 있다.
  - 현재 `external_variant_id`는 실제 ZARA `v1`/catentry ID가 아니라 color name 또는 `__default__`를 사용한다. ZARA variant 보존을 위해 수정이 필요하다.
- `FitMatch/FitMatch/ViewModels/ShoppingProductViewModel.swift`
  - parse 후 DB shadow resolve 및 best-effort observation을 시작한다.
- `FitMatch/FitMatch/Services/FitMatchClosetSyncCoordinator.swift`
  - runtime product/product_size를 SwiftData 내 옷장과 동기화한다. source code로 ZARA를 수용할 수 있다.
- `FitMatch/FitMatch/Services/FitMatchComparisonSyncCoordinator.swift`
  - target resolve → runtime 조회 → 기준 옷 후보 조회 → comparison begin → complete 순서로 실행한다.
- `FitMatch/FitMatch/Services/MeasurementComparisonEngine.swift`
  - 공통 비교 엔진이다. 결측·미검증·basis 불일치 값은 비교에서 제외한다.
  - provider platform 인식에는 현재 `uniqlo`, `musinsa`, `fitmatch/manual`만 있고 `zara`가 없다. 따라서 ZARA끼리 동일 raw field를 직접 비교하는 provider shortcut은 현재 작동하지 않는다.
- SwiftData: `Product.swift`, `UserFit.swift`, `RecommendationHistory.swift`
  - source metadata, source category, product/size snapshot, 추천 결과와 history를 이미 수용한다.

공통 abstraction은 재사용하고 ZARA 전용으로 필요한 것은 URL/product ID resolver, metadata parser, category adapter, measurement adapter뿐이다. source-specific 조건을 comparison engine에 직접 넣으면 안 된다.

## 2. ZARA API 검증 결과

확인한 후보 엔드포인트:

```text
GET https://www.zara.com/itxrest/4/catalog/store/11717/product/{productId}/size-measure-guide?locale=ko_KR
```

식별자 관계:

- URL의 `-p04166166.html` 같은 값은 style 번호다.
- 공유 URL query의 `v1=545490346`은 color/variant 계열의 `catentryId`로 확인됐다.
- 실측 API path에는 style 번호나 `v1`이 아니라 상품 HTML analytics의 내부 `productId`가 필요하다.

확인 표본:

| 상품 | URL style | `v1`/catentryId | 내부 productId | 현재 API 결과 |
|---|---:|---:|---:|---|
| 레귤러 핏 셔츠 | 04166166 | 545490346 | 545486853 | `sizeGuideInfo`만 존재 |
| 울 릴렉스핏 블레이저 | 05552381 | 551791628 | 551789966 | `sizeGuideInfo`만 존재 |
| 플리츠 스트레이트 핏 팬츠 | 06861017 | 555813567 | 555794883 | `sizeGuideInfo`만 존재 |
| 레귤러핏 니트 폴로셔츠 | 05987400 | 545479232 | 545475314 | `sizeGuideInfo`만 존재 |
| 하트 스탬핑 티셔츠 API 표본 | 해당 URL 미확보 | 미확인 | 498702922 | `measureGuideInfo` 존재 |

`498702922` 표본의 `measureGuideInfo`에는 사이즈별 가슴 48.5 cm, 앞길이 62.5 cm, 소매 15.0 cm, 등너비 42.5 cm, 암폭 18.0 cm와 같은 완성 의류형 값이 있었다.

네 개의 현재 상품 표본은 모두 `measureGuideInfo = null`이고 `sizeGuideInfo`만 있었다. 따라서 엔드포인트 응답 구조는 상품·카테고리에 따라 달라진다.

HTTP 안정성:

- 명시적 모바일/iPhone User-Agent를 사용한 실측 API 요청은 JSON 200이 확인됐다.
- 기본 요청은 403이 발생한 사례가 있다.
- 더 중요한 HTML 상품 페이지 요청은 모바일 User-Agent를 사용해도 Akamai interstitial(`bm-verify`, `triggerInterstitialChallenge`)이 반환됐다.
- 현재 parser는 이 challenge를 감지하고 실패하도록 되어 있다.
- 안정적인 공개 metadata JSON API 또는 공식 productId resolver는 확인하지 못했다.

API 사용정책/계약:

- 저장소와 공개 페이지에서 FitMatch에 부여된 ZARA 공식 파트너 API 계약 증거는 확인하지 못했다.
- 기술적으로 200 응답을 얻는 것과 production 사용 허가는 별개다.
- 무신사·유니클로도 저장소 외부 계약이 있다면 그 문서를 별도로 확인해야 하며, 코드가 있다는 사실만으로 사용 허가를 의미하지 않는다.

## 3. ZARA category 확보 가능 여부

부분적으로 가능하지만, production에서 지속적으로 신규 상품을 분류할 수 있는 안정적 수집 경로는 아직 확정되지 않았다.

확인된 후보 데이터:

- 상품 analytics의 `section` (`MAN`, `WOMAN`)
- 상품 analytics의 `family`/`subfamily`
- ZARA KR GNB의 카테고리명과 landing ID (`l####`)
- 상품 URL/페이지의 이름, 컬러, SKU형 코드

권장 taxonomy identity는 merchandising landing ID가 아니라 상품 수준의 `section + family`다. `신상품`, `세일`, `모두 보기`, 캠페인 페이지는 상품 종류가 섞이므로 source category leaf로 확정하면 안 된다.

로컬 초안 `fitmatch_supabase_seed_zara_categories.sql`에는 남성 11개, 여성 15개 의미 기반 노드가 준비되어 있다. 그러나 이는 2026-08-21 표본 snapshot이며 운영 DB에는 적용되지 않았다. 전체 taxonomy의 완전성도 증명하지 못했다.

주의할 구조:

- 같은 이름이 성별별로 별도 identity를 가질 수 있다.
- `WOMAN:탑 | 바디수트`, `WOMAN:스웨트셔츠 | 조거 팬츠`처럼 하나의 family가 여러 FitMatch detail을 포함한다.
- GNB category와 상품 analytics family가 일대일이라는 보장이 없다.
- category 이름과 landing ID는 시즌 및 merchandising 개편으로 변경될 수 있다.
- 액세서리·향수·홈 등 의류 외 category는 자동 비교 대상에서 제외해야 한다.

## 4. ZARA measurement 신뢰성

판정:

- `measureGuideInfo`: 실제 표본상 완성 의류 실측으로 사용할 수 있다. 다만 필드 의미가 명확한 항목만 canonical mapping한다.
- `sizeGuideInfo`: 신체 권장 치수다. 상품 실측으로 변환하거나 comparison engine에 넣으면 안 된다.
- 둘 중 어느 구조인지 확인되지 않은 값은 raw로 보존하되 비교에서는 제외한다.

호환성:

| ZARA raw field | 의미 | 단위 | FitMatch canonical | 비교 가능성 |
|---|---|---|---|---|
| `zone-name-chest` | 가슴 단면 또는 API 정의상 가슴값 | cm | `chest_width` | basis 확인 시 가능 |
| `zone-name-front-length` | 앞길이 | cm | `front_length` | 가능 |
| `zone-name-back-length` | 뒤길이 | cm | `back_length` | 가능 |
| `zone-name-sleeve-length` | 소매길이 | cm | `sleeve_length` | 가능 |
| `zone-name-shoulder-width` | 어깨너비 | cm | `shoulder_width` | 가능 |
| `zone-name-waist` | 허리 | cm | `waist_width` 또는 circumference | basis 확인 필요 |
| `zone-name-hip` | 엉덩이 | cm | `hip_width` 또는 circumference | basis 확인 필요 |
| `zone-name-thigh` | 허벅지 | cm | `thigh_width` | basis 확인 시 가능 |
| `zone-name-front-rise` / `back-rise` | 앞/뒤 밑위 | cm | 대응 rise key | 가능 |
| `zone-name-hem` / `leg-opening` | 밑단 | cm | `hem_width` | 가능 |
| `zone-name-inside-leg` / `inseam` | 인심 | cm | `inseam` | 가능 |
| `zone-name-outside-leg` / `outseam` | 아웃심 | cm | `outseam` | 가능 |
| `back-width` | 등너비 | cm | 확정 없음 | unknown 보존 |
| `arm-width` | 암폭 | cm | 확정 없음 | unknown 보존 |

현재 앱 비교 핵심 조건:

- top/shirt/knit: 비교 가능한 항목 최소 2개, shoulder/chest 중 최소 1개 필요
- outer: 최소 2개, chest 필수
- bottom/pants: 최소 2개, waist/hip/thigh 중 최소 2개 필요
- dress: 최소 2개, chest/waist/hip 중 최소 1개 필요
- shoes: foot length 1개 필요

DB runtime은 confirmed classification과 comparable measurement 최소 1개가 있어야 comparison-ready 후보가 된다. 실제 comparison begin은 기본적으로 공통 measurement overlap 2개 이상을 요구한다.

결론적으로 ZARA 상품을 수집할 수 있어도 body-only 상품은 자동 비교 불가이며, `measureGuideInfo`가 있는 상품도 핵심 치수 조건을 충족하지 않으면 추천 대상이 될 수 없다.

## 5. DB 현재 상태

연결된 운영 프로젝트: `hnkplvyegonlhumlejst`  
조사 방식: actual schema 및 row count 읽기 전용 조회. migration 파일을 운영 상태로 간주하지 않음.

운영 적용 migration은 `20260820144326`까지다. 저장소에는 운영에 미적용된 다음 파일이 있다.

- `supabase/migrations/106_add_cos_observation_source.sql`
- `supabase/migrations/20260820223726_add_zara_observation_source.sql`

운영 데이터 현황:

| 대상 | 실제 상태 |
|---|---|
| `public.sources` | `musinsa`, `uniqlo`만 존재. `zara`, `cos` 없음 |
| `public.source_categories` | musinsa 314, uniqlo 1,717, zara 0 |
| `public.source_category_mappings` | musinsa 314, uniqlo 1,717, zara 0 |
| `public.source_measurement_mappings` | musinsa 12, uniqlo 9, zara 0 |
| `public.category_measurement_items` | 전체 0 rows |
| `fitmatch_catalog.products` | musinsa 394, uniqlo 1,184 |
| `fitmatch_catalog.current_source_products` | musinsa 384, uniqlo 1,156 |
| `fitmatch_catalog.product_observations` | musinsa 1, uniqlo 1 |
| observation source CHECK | `uniqlo`, `musinsa`, `cos`만 허용. `zara` 차단 |
| canonical measurement items | 25개 존재 |
| active app categories | 11개 |
| active detail categories | 75개 |
| active source-to-FitMatch mappings | 3,427개 |

활성 release:

- ID: `7aba7f62-4f56-402d-9adb-8acb37f2c609`
- key: `observed-official-2026-08-03__taxonomy-corrected-2026-08-14`

핵심 table/constraint:

- `public.sources`: PK `id`, UNIQUE `code`, lowercase CHECK, RLS enabled, public read
- `public.source_categories`: source/parent/audience/external ID/path, app category/detail, metadata. source·audience·external ID/path unique index, RLS enabled
- `public.source_category_mappings`: source category PK/FK, garment type, default length codes, resolution/mapping status CHECK, evidence/policy version, RLS enabled
- `public.measurement_items`: canonical key UNIQUE 성격, unit/value type/aliases, RLS enabled
- `public.category_measurement_items`: source category와 measurement item 연결, `(source_category_id, measurement_item_id, original_label)` UNIQUE, RLS enabled
- `public.source_measurement_mappings`: source/parser/raw code·label/basis별 UNIQUE, canonical item FK, conversion/category scopes/comparable/evidence, RLS enabled
- `fitmatch_catalog.products`: `(source, external_product_id)` UNIQUE, raw payload와 fingerprint 보존
- `fitmatch_catalog.product_variants`: `(product_id, external_variant_id)` UNIQUE
- `fitmatch_catalog.product_sizes`: `(variant_id, size_identity)` UNIQUE
- `fitmatch_catalog.product_measurements`: `(product_size_id, measurement_identity)` UNIQUE. comparable row는 code/value/kind/comparison basis 필요
- `public.closet_items`: runtime product/variant/size, canonical category, measurements, snapshot, fit preference를 보존하며 소유자 RLS 적용
- `public.comparison_runs/results/measurement_results/history`: 비교 실행, 사이즈별 점수, 근거, snapshot/history를 저장하며 소유자 RLS 적용

운영 함수:

- `fitmatch_resolve_product`: 현재 상품/분류가 없으면 intake request를 만들고 review-required candidate를 반환한다.
- `fitmatch_get_product_runtime`: `classification_required`, `not_comparable`, `sizes_required`, `measurements_required`, `ready`를 판정한다.
- `fitmatch_register_closet_item`: authenticated user와 현재 상품/분류를 요구하고 comparable measurements를 closet에 복사한다.
- `fitmatch_list_closet_items`, `fitmatch_set_closet_reference`: 내 옷장과 기준 옷을 제공한다.
- `fitmatch_find_reference_candidates`: category/measurement overlap을 근거로 기준 옷 후보를 찾는다.
- `fitmatch_begin_comparison`: 기본 공통치수 2개 미만이면 차단한다.
- `fitmatch_complete_comparison`: results, per-measurement evidence, comparison history를 저장한다.

## 6. DB 추가 작업

아직 실행하면 안 되며, blocker 해소 후 필요한 변경 범위는 다음과 같다.

1. `public.sources`에 `code='zara'`, KR base URL, 활성 상태를 idempotent하게 등록한다.
2. `fitmatch_catalog.product_observations.source` CHECK에 `zara`를 추가한다.
3. 검증된 source taxonomy snapshot을 `public.source_categories`에 적재한다. raw ID/path/parent/audience/metadata를 보존한다.
4. 각 leaf를 기존 canonical category에 연결하는 `source_category_mappings`를 적재한다. ambiguous/excluded도 상태와 evidence를 저장한다.
5. `measureGuideInfo` raw fields에 대한 `source_measurement_mappings`를 적재한다. body guide는 comparable false로 분리하거나 observation raw payload에만 보존한다.
6. ingestion 후 runtime projection이 product → variant → size → comparable measurement를 올바르게 생성하는지 shadow 표본으로 검증한다.

새 canonical category를 만들 필요는 현재 확인되지 않았다.

## 7. category mapping 전략

기준 identity:

```text
source = zara
audience = MEN/WOMEN
external_category_id = section + ':' + semantic family
raw = section/family/subfamily/GNB path/landing ID 전체 보존
```

분류 원칙:

- EXACT: 하나의 ZARA semantic family가 기존 FitMatch detail 하나와 명확히 일치
- RULE_BASED: family만으로 부족하지만 공식 subfamily/상품 type을 사용하면 결정 가능
- AMBIGUOUS: 하나의 source family에 서로 다른 garment type이 섞임
- EXCLUDED: 의류가 아니거나 자동 실측 비교 대상이 아님

현재 초안 판정 예:

- EXACT: 티셔츠, 셔츠, 팬츠, 데님팬츠, 쇼츠/버뮤다, 블레이저, 니트, 스웨트셔츠, 원피스, 스커트
- RULE_BASED: 자켓/점퍼, 오버셔츠, 가디건/스웨터. canonical detail 또는 comparison family를 subfamily로 보완할 수 있는지 검증 필요
- AMBIGUOUS: 여성 `탑 | 바디수트`, `스웨트셔츠 | 조거 팬츠`
- EXCLUDED: 신상품/세일/모두 보기/캠페인 landing, 액세서리·향수·홈 등 비의류

상품명 문자열은 최후의 review hint로만 사용하고, taxonomy key로 사용하지 않는다. 미분류 상품을 top/shortSleeve로 기본 확정하는 현재 ZARA parser fallback은 제거 또는 review-required 처리해야 한다.

## 8. 앱 코드 변경 범위

상태별 gap:

| 영역 | 판정 | 필요한 일 |
|---|---|---|
| A. DB 변경 | 신규 구현 필요 | source, CHECK, taxonomy/mapping/measurement seed |
| B. ZARA source/category data | 신규 구현 필요 | 검증된 snapshot과 증거 적재 |
| C. category mapping | 수정/신규 필요 | heuristic fallback 제거, DB mapping 우선 |
| D. measurement mapping | 신규 구현 필요 | canonical mapping 정책과 raw 보존 |
| E. API/Parser/Provider | 수정 필요 | 안정적인 productId resolver, HTTP 실패 정책, variant 추출 |
| F. domain model | 대부분 지원됨 | 실제 external variant/catentry ID 전달 보강 |
| G. closet registration | 이미 지원됨 | ZARA runtime data가 생성된 후 통합 검증 |
| H. comparison pipeline | 대부분 지원됨 | ZARA provider recognition 및 정책 parity 검증 |
| I. persistence/history | 이미 지원됨 | ZARA snapshot round-trip 검증 |
| J. UI | 확인/소폭 수정 | body-only/미지원/재시도 불가 메시지 구분 |
| K. tests | 신규 필요 | live fixture, parser, DB contract, end-to-end |

핵심 코드 변경:

- ZARA URL → style/v1/internal productId를 서로 다른 필드로 보존한다.
- real `v1`/catentry ID를 `external_variant_id`로 전달한다.
- HTML resolver가 challenge를 받을 경우 재시도만 반복하지 말고 명시적 unsupported/blocked 상태로 종료한다.
- ZARA category는 DB mapping을 사용하고 source parser heuristic은 raw hint로 제한한다.
- ZARA measurement mapping은 공통 policy abstraction으로 이동한다.
- `MeasurementComparisonEngine.platform(for:)`에 ZARA를 넣을지는 raw basis의 동등성이 검증된 후 결정한다.

## 9. 기존 abstraction 재사용 가능 범위

재사용 가능:

- URL provider dispatch
- `ParsedProductInfo`/size/measurement 공통 모델
- Supabase resolve/observation ingest
- runtime projection
- SwiftData product/closet/history 모델
- closet sync와 기준 옷 선택
- comparison candidate/begin/complete RPC
- canonical comparison engine, 추천 점수, 신뢰도, history 저장
- partial/unsupported error 표현의 기본 구조

ZARA source-specific 구현:

- style/v1/productId resolver
- ZARA metadata decoding
- section/family/subfamily raw taxonomy adapter
- `measureGuideInfo`와 `sizeGuideInfo` 구분
- ZARA raw measurement decoding
- Akamai/403 대응과 계약상 허용된 호출 방식

## 10. 위험 요소

1. HTML resolver가 Akamai challenge에 막히면 URL만으로 내부 productId를 얻을 수 없다.
2. 실측 API가 200이어도 상품 대부분이 body guide만 제공할 수 있다.
3. User-Agent 모방으로 일시 성공해도 API 사용 권한과 장기 안정성을 보장하지 않는다.
4. `v1`, style, productId를 혼동하면 같은 상품의 color variant와 product size가 잘못 합쳐진다.
5. mixed category를 임의 확정하면 잘못된 핵심치수 정책과 추천 결과가 적용된다.
6. 허리·힙·가슴 값의 width/circumference basis를 잘못 해석하면 값이 2배 차이 날 수 있다.
7. 로컬 seed/migration 존재를 운영 적용 상태로 오인할 위험이 있다.
8. 기존 parser의 top/shortSleeve 기본값은 오분류를 조용히 확정한다.
9. 캐시·재시도·속도 제한은 403 우회 수단이 아니다. 목적은 정상 허용된 호출에서 장애 확산, 중복 호출, ZARA 서버 부하를 줄이는 것이다.

## 11. 미확인 사항

- ZARA가 FitMatch production 사용을 허가하는 공식 API/파트너 계약
- challenge 없이 URL → internal productId를 제공하는 공식 resolver
- 전체 KR semantic source taxonomy와 계절 변경 안정성
- `measureGuideInfo` 제공 비율을 대표하는 충분한 카테고리별 표본
- 각 raw measurement의 공식 width/circumference/측정 기준 문서
- 여성 mixed family를 안정적으로 나누는 공식 subfamily code
- color별 productId/measurement 차이와 `v1`의 장기 identity 안정성
- 앱스토어 production 네트워크와 실제 iPhone에서의 응답 안정성

## 12. 구현 순서

1. ZARA 사용정책/계약과 허용된 호출 방식을 확정한다.
2. production-safe URL → productId resolver를 확보하고 style/v1/productId 관계를 fixture로 고정한다.
3. 남성·여성 주요 의류 category별로 다수 상품을 표본 조사하여 taxonomy와 garment-measure 제공률을 확정한다.
4. category mapping과 measurement basis를 review하고 EXACT/RULE_BASED/AMBIGUOUS/EXCLUDED 데이터를 확정한다.
5. migration과 seed를 staging에서 적용한다.
6. ZARA parser/provider를 공통 abstraction에 맞춰 수정한다.
7. observation → runtime product/variant/size/measurement projection을 shadow 검증한다.
8. closet → reference → comparison → recommendation → history 전체 경로를 staging에서 검증한다.
9. body-only, challenge, 403, unknown measurement, mixed category 실패 경로를 검증한다.
10. 기존 Musinsa/Uniqlo regression을 통과한 뒤 제한적 rollout한다.

## 13. 수정 예상 파일

- `FitMatch/FitMatch/Services/ZARAParser.swift`
- `FitMatch/FitMatch/Services/ProductURLParserService.swift`
- `FitMatch/FitMatch/Services/FitMatchSupabaseProductResolver.swift`
- `FitMatch/FitMatch/Services/MeasurementComparisonEngine.swift`
- ZARA measurement mapping policy 관련 신규 또는 기존 공통 service 파일
- body-only/unsupported UI를 표시하는 관련 ViewModel/View
- `FitMatch/FitMatchTests/FitMatchTests.swift`
- `FitMatch/FitMatchTests/FitMatchP0ProductionPathTests.swift`
- Supabase resolver/closet/comparison coordinator test 파일
- `FitMatch/supabase/migrations/...`
- 검증 완료 후 `FitMatch/fitmatch_supabase_seed_zara_categories.sql`

## 14. 필요한 migration

최소 migration 단위:

1. ZARA source 등록
2. product observation source CHECK 확장
3. 검증된 ZARA source taxonomy seed
4. source category mapping seed
5. source measurement mapping seed

요구 조건:

- 모두 idempotent 또는 명확한 UNIQUE 충돌 정책을 가져야 한다.
- raw source ID/path/metadata/evidence/policy version을 보존한다.
- AMBIGUOUS/EXCLUDED를 삭제하지 말고 상태로 남긴다.
- exposed `public` table의 RLS를 유지한다.
- 적용 전후 row count, FK/UNIQUE/CHECK, RPC runtime 결과를 검증한다.
- 현재 로컬 `20260820223726_add_zara_observation_source.sql`과 category seed는 초안으로 review한 후 적용한다.

## 15. 필요한 테스트

Parser/API:

- 공유 URL에서 style과 `v1` 분리
- HTML analytics에서 internal productId 추출
- challenge/interstitial 탐지
- `measureGuideInfo` 수용
- `sizeGuideInfo` 단독 응답 fail-closed
- 두 guide 동시 존재 시 garment 값만 사용
- unknown measurement raw 보존
- unit과 decimal parsing
- color/variant별 size 관계

Category/measurement:

- MEN/WOMEN 동일 이름 identity 분리
- EXACT/RULE_BASED/AMBIGUOUS/EXCLUDED 처리
- mixed family가 자동 확정되지 않음
- width/circumference basis 불일치 제외
- category별 핵심치수/최소 overlap 충족 및 미충족

DB contract:

- ZARA observation insert 허용
- product/variant/size idempotency
- `v1`/catentry ID variant 분리
- raw payload 보존
- confirmed/review-required/not-comparable runtime state
- RLS own-row 접근 보장

Production path:

- ZARA URL → parse → observation → runtime
- 내 옷장 등록 → 기준 옷 선택
- 사이즈별 추천, match score, reliability
- comparison results와 history snapshot 저장
- body-only 상품의 자동 비교 차단
- 403/challenge의 명확한 사용자 오류
- Musinsa/Uniqlo 전체 regression

현재 ZARA test는 synthetic parser 단위 테스트 두 개가 중심이며 live production-path 안정성을 증명하지 않는다.

## 최종 판정

**READY FOR DB IMPLEMENTATION: NO**

Blocker:

1. ZARA production API 사용정책/계약이 확인되지 않았다.
2. 상품 URL에서 내부 `productId`를 안정적으로 얻는 허용된 production resolver가 없다.
3. 운영 DB에 `zara` source가 없고 observation CHECK가 ZARA를 차단한다.
4. 운영 DB에 ZARA source category/category mapping/measurement mapping이 없다.
5. 카테고리별 `measureGuideInfo` 제공률과 measurement basis가 충분히 검증되지 않았다.
6. 실제 ZARA `v1`/catentry variant ID가 현재 observation/runtime 경로에 보존되지 않는다.
7. 전체 KR taxonomy를 신규 상품까지 안정적으로 분류할 수 있는 획득 경로가 확정되지 않았다.

## 다음 작업자에게 전달할 지시문

아래 문장을 이 문서와 함께 다른 채팅에 붙여넣으면 된다.

```text
첨부한 FitMatch ZARA Phase 1 Production Audit를 기준으로 작업하라.
문서에 적힌 사실과 blocker를 실제 코드·운영 DB·현재 API 응답으로 다시 확인하기 전에는 production DB를 변경하지 말라.
기존 Musinsa/Uniqlo 공통 abstraction을 재사용하고 ZARA 전용 비교 파이프라인을 만들지 말라.
measureGuideInfo만 완성 의류 실측 후보로 사용하고 sizeGuideInfo는 신체 권장치이므로 비교 입력에서 제외하라.
style 번호, URL v1/catentryId, 내부 productId를 서로 다른 identity로 보존하라.
category는 EXACT/RULE_BASED/AMBIGUOUS/EXCLUDED를 명시하고 불명확한 값을 임의 확정하지 말라.
모든 raw source data, measurement basis, mapping evidence를 보존하라.
먼저 blocker 해소 증거와 staging 적용 계획을 보고한 뒤 구현 승인을 받아라.
```

## 검증에 사용한 공개 URL

- ZARA size API garment-measure 표본: https://www.zara.com/itxrest/4/catalog/store/11717/product/498702922/size-measure-guide?locale=ko_KR
- 셔츠 size API: https://www.zara.com/itxrest/4/catalog/store/11717/product/545486853/size-measure-guide?locale=ko_KR
- 블레이저 size API: https://www.zara.com/itxrest/4/catalog/store/11717/product/551789966/size-measure-guide?locale=ko_KR
- 팬츠 size API: https://www.zara.com/itxrest/4/catalog/store/11717/product/555794883/size-measure-guide?locale=ko_KR
- 니트 size API: https://www.zara.com/itxrest/4/catalog/store/11717/product/545475314/size-measure-guide?locale=ko_KR
