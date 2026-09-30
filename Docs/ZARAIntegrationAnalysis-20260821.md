# ZARA KR 공식 실측 API · 카테고리 연동 메모

기준일: 2026-08-21

> 정정: 이 문서의 과거 `analytics.productId` API 식별자 결론은 폐기됐다. 2026-08-21 사용자 가시 WKWebView 재검증에서 실측 API는 URL `v1 == analytics.catentryId`를 사용하며, 내부 `productId`는 별도 identity로 확인됐다. 티셔츠·셔츠·팬츠 3개가 `catentryId` 호출에서 `measureGuideInfo`를 반환했다. 일반 URLSession 상품 HTML은 여전히 challenge 가능성이 있고 공식 사용 허가는 확인되지 않아 production gate는 닫혀 있다.

## 확인된 실측 계약

- 엔드포인트: `GET https://www.zara.com/itxrest/4/catalog/store/11717/product/{catentryId}/size-measure-guide?locale=ko_KR`
- `Accept: application/json`, `Accept-Language: ko-KR,ko;q=0.9`, 명시적 iPhone `User-Agent` 요청에서 예시 `498702922`가 HTTP 200 및 JSON으로 확인됐다. 기본 요청은 403이었다.
- `measureGuideInfo.sizes[].measures[]`만 의류 실측으로 사용한다. `sizeGuideInfo`만 있는 응답은 신체 권장치이므로 FitMatch 비교 실측으로 변환하지 않고 partial/자동 비교 불가로 처리한다.
- `zone-name-chest`, `front/back-length`, `sleeve-length`, `shoulder-width`, 허리·힙·허벅지·밑위·밑단·인심/아웃심처럼 정의가 명확한 항목만 매핑한다. `back-width`, `arm-width` 등은 unknown record로 보존하며 어깨 등 다른 값으로 추정하지 않는다.

## URL 파싱 상태

- URL query `v1`과 공식 상품 HTML의 `zara.analyticsData.catentryId`가 일치해야 하며 이 값을 실측 API에 사용한다. `analytics.productId`, `productRef`, URL style 번호는 각각 별도로 보존한다.
- 브라우저의 공식 상품 페이지에서는 실제 metadata를 확인했지만, 앱과 같은 직접 URLSession 요청은 Akamai interstitial HTML을 반환하는 경우가 있었다. 따라서 현재 구현은 bot challenge를 감지하면 실패하며, 실측 API만으로 URL의 내부 productId를 역산하지 않는다.
- 출시 전에는 ZARA가 허용하는 공식 productId resolver/파트너 계약을 확보하거나, 실제 iPhone 네트워크에서 URL 페이지 응답과 실측 API를 함께 재검증해야 한다. 이 확인 전에는 ZARA URL 붙여넣기의 성공을 보장하면 안 된다.

## 카테고리

- 두 category namespace를 섞지 않고 함께 보존한다.
  - 상품 HTML analytics: `MAN:셔츠:B. Camisería` 같은 section/family/subfamily 36건. 현재 iOS parser가 DB 요청에 전달하는 값이다.
  - 공식 메뉴/SSR hydration: `2431994` 같은 ZARA 숫자형 category ID 213건. 사용자 제공 `zara_fitmatch_collection_20260813.zip`의 해시·재생성 검증을 통과한 snapshot이다.
- 공식 tree는 WOMAN 55, MAN 57뿐 아니라 KIDS/HOME/PERFUME/TRAVEL/UNKNOWN도 원본 section과 parent 관계를 보존한다. 비의류 142건은 `rejected`, 혼합·집계·canonical 미지원 45건은 `review_required`로 저장했다.
- FitMatch garment type까지 안전하게 확정한 매핑은 analytics 30건, 공식 숫자형 26건이다. 원피스·점프수트·란제리처럼 현재 `garment_types`에 canonical type이 없는 항목과 혼합 category는 자동 확정하지 않았다.

## DB 적용 순서

1. 완료: `seed_zara_verified_categories`로 analytics category 36건을 등록했다.
2. 완료: `add_zara_observation_source`로 authenticated observation RPC와 service-role batch RPC의 allowlist에 `zara`를 추가했다. 임의 source는 계속 거절한다.
3. 완료: `enable_zara_testing_categories`로 source를 활성화하고 analytics category의 public mapping 36건(confirmed 30, review 6)을 등록했다.
4. 완료: `seed_zara_official_category_tree`로 공식 숫자형 category 213건과 public mapping 213건(confirmed 26, review 45, rejected 142)을 등록했다.
5. 완료: `publish_zara_client_category_mappings`로 앱 read table에 ZARA 249건(confirmed 56, review 51, rejected 142)을 게시했다.
6. 완료: active runtime release를 기존 provider row를 그대로 복제한 새 release로 원자 전환했다. 현재 전체 3,483건은 Musinsa 1,922, Uniqlo 1,505, ZARA 56이며 expected/actual이 일치한다.

DB category·observation 경계는 테스트 가능한 상태다. 다만 `runtime_resolve_product_classification_v2`는 source mapping을 positive confirmed product classification으로 직접 승격하지 않으므로 신규 ZARA product는 현재 `review_required`다. 또한 ZARA measurement basis가 검증되지 않아 measurement mapping과 자동 비교는 계속 비활성이다. 이는 DB 누락이 아니라 의도된 fail-closed gate다.
