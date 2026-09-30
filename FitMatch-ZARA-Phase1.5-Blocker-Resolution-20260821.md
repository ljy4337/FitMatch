# FitMatch ZARA Phase 1.5 — Blocker Resolution & Fail-Closed Audit

기준 시각: 2026-08-21 KST  
기준 branch: `connectDB`  
기준 commit: `43add48bf083dd0e01036038ee34254e8579025f`  
기준 문서: `Docs/FitMatch-ZARA-Phase1-Production-Audit-20260821.md`

## A. Executive decision

```text
IDENTITY_RESOLVER: PARTIAL
STYLE_V1_PRODUCT_ID_SEPARATION: PASS
VARIANT_IDENTITY_PRESERVATION: PASS
GARMENT_MEASUREMENT_COVERAGE: PARTIAL
MEASUREMENT_BASIS_VERIFICATION: PARTIAL
CATEGORY_FAIL_CLOSED: PASS
API_USAGE_AUTHORIZATION: NOT_VERIFIED
READY_FOR_STAGING_DB_PHASE: NO
READY_FOR_PRODUCTION_RELEASE: NO
```

다음 DB Phase로 진행하면 안 된다. 다만 기존 결론 중 실측 API 식별자는 2026-08-21 WKWebView 재검증으로 정정됐다. 실측 API는 analytics 내부 `productId`가 아니라 URL `v1`과 일치하는 `catentryId`를 사용한다. 사용자에게 보이는 ephemeral WKWebView에서 비필수 쿠키 거부를 명시적으로 선택한 뒤 티셔츠·셔츠·팬츠 3개 모두 metadata identity와 `measureGuideInfo`를 재현했다. 표준 `URLSession` 상품 HTML 요청은 여전히 Akamai interstitial을 받을 수 있다.

과거 `internal productId`로 호출해 `body_only`로 기록한 D/E 표와 `ZARAAudit/cache/*.json` 결과는 잘못된 API 식별자에 대한 역사적 증거다. ZARA garment coverage 근거로 사용하면 안 된다. 현재 권위 표본은 `ZARAAudit/zara_webview_poc_samples.jsonl`이다.

이번 결론은 technical staging gate에 대한 것이다. 표본에서 응답을 받은 사실은 장기 안정성이나 production 사용 허가를 뜻하지 않는다.

### 2026-08-21 사용자 승인 후 DB 테스트 경계 적용

Phase 1.5 조사 종료 뒤 사용자가 category 등록·mapping·observation 수용 경계를 실제 DB에 적용하도록 별도로 승인했다. 따라서 위 gate 표의 `READY_FOR_STAGING_DB_PHASE=NO`는 원래 완료 기준 전체, 특히 measurement basis와 physical-device 조건을 뜻하며, 아래의 bounded DB 작업을 수행하지 않았다는 뜻은 아니다.

- ZARA source 활성화 및 observation allowlist 적용
- analytics section/family/subfamily 36건 등록·mapping
- 사용자 제공 검증 패키지의 공식 숫자형 category tree 213건 등록·mapping
- public/client mapping 총 249건: confirmed 56, review_required 51, rejected 142
- active runtime release ZARA 56건 추가, 전체 expected/actual 3,483 일치
- unknown/mixed/canonical 미지원 category는 runtime confirmed row에서 제외
- measurement mapping은 0건 유지

실제 runtime source resolver는 analytics 셔츠와 공식 숫자형 셔츠를 각각 confirmed로 찾고, 원피스 review 표본과 unknown code는 `found=false`로 종료했다. 다만 현재 공통 product classifier는 positive source mapping만으로 상품을 자동 confirmed하지 않아 신규 ZARA 상품 분류는 `review_required`다. measurement basis가 미확인이므로 이 동작을 억지로 승격하지 않았다.

## B. 변경된 파일

작업 시작 시 working tree에는 다수의 기존 미커밋 변경과 untracked 파일이 있었다. reset, checkout, stash를 하지 않았고 관련 없는 변경을 수정하지 않았다. `ZARAParser.swift`와 Supabase resolver 자체도 시작 시 untracked 상태였으며, 아래는 그 파일 안에서 이번 Phase가 추가·수정한 범위다.

| 파일 | 변경 이유 | 영향 범위 |
|---|---|---|
| `FitMatch/Services/ZARAParser.swift` | typed identity 분리, challenge/identity 불일치 명시 실패, category fallback 제거, 미검증 실측 raw-only 처리 | ZARA parser만 변경 |
| `FitMatch/Services/ZARAWebViewMetadataAudit.swift` | 사용자 가시 WKWebView metadata capture와 cookie 선택 후 재검증 PoC | DEBUG launch argument에서만 활성, production 비활성 |
| `FitMatch/Models/ProductMetadata.swift` | product identity와 다른 provider variant identity 보존용 `externalVariantID` 추가 | optional 기본값으로 backward-compatible |
| `FitMatch/Services/FitMatchSupabaseProductResolver.swift` | ZARA observation에서 실제 v1/catentry를 variant ID로 사용하고 세 ID를 raw payload에 분리 | `source == zara` 분기만 변경; DB 호출/쓰기 확대 없음 |
| `FitMatchTests/ZARAParserPhase1_5Tests.swift` | identity, challenge, body/garment guide, malformed, unknown/mixed/excluded category 검증 | 신규 targeted tests |
| `FitMatchTests/FitMatchTests.swift` | 기존 ZARA expectation을 미검증 basis fail-closed 정책으로 정정 | 기존 두 ZARA fixture test만 변경 |
| `FitMatchTests/FitMatchSupabaseProductResolverTests.swift` | style/v1/internal ID observation 분리 검증 | ZARA 신규 test 1개 |
| `ZARAAudit/zara_phase1_5_audit.mjs` | 순차·cache·제한 재시도 audit 자동화 | audit 전용, 앱 runtime과 무관 |
| `ZARAAudit/zara_phase1_5_identity_samples.jsonl` | 실제 브라우저/기존 증거로 확인한 identity 입력 | 원본 identity manifest |
| `ZARAAudit/zara_phase1_5_samples.csv` | size API 결과와 hash를 구조화 | 생성 manifest |
| `ZARAAudit/zara_webview_poc_samples.jsonl` | 올바른 `catentryId`로 재검증한 WKWebView 표본 3개 | 현재 권위 identity/guide PoC manifest |
| `ZARAAudit/cache/*.json` | 18개 unique 내부 ID의 실제 공개 응답 보존 | cookie/token/개인정보 없음 |
| `ZARAAudit/fixtures/*` | challenge, malformed, unknown, mixed 대표 fixture | challenge는 token 제거, 나머지 synthetic 여부 명시 |
| `FitMatch-ZARA-Phase1.5-Blocker-Resolution-20260821.md` | 본 조사 보고서 | 문서 |

Phase 1.5 조사 시점에는 운영 migration, seed, Supabase row를 변경하지 않았다. 이후 사용자의 별도 승인으로 `107_seed_zara_verified_categories.sql`, `20260820223726_add_zara_observation_source.sql`, `108_enable_zara_testing_categories.sql`, `109_seed_zara_official_category_tree.sql`, `110_publish_zara_client_category_mappings.sql`을 적용했다. `MeasurementComparisonEngine.swift`와 추천 점수 공식은 변경하지 않았다.

## C. Identity resolver 조사

### 후보별 결과

| 후보 | 요청/입력 | 출력 | 인증·cookie | 결과 |
|---|---|---|---|---|
| 상품 URL | URL 문자열 자체 | style=`-p########`, query v1 | 없음 | 실측 API ID인 v1 확보 가능; metadata는 별도 resolver 필요 |
| redirect URL | 상품 URL redirect follow | 최종 style/v1 | 없음 | 내부 productId 없음. style 변경 redirect는 코드에서 거부 |
| JSON-LD | 상품 HTML의 `ProductGroup` | `productGroupID`=style, variant offer URL의 v1 | 상품 HTML 접근 필요 | 내부 productId 없음 |
| embedded analytics | 상품 HTML의 `zara.analyticsData` | `productId`, `productRef`, `catentryId`, section/family/subfamily | 사용자 가시 WKWebView에서 확인; 계정/비공개 credential 없음 | 티셔츠·셔츠·팬츠 3개 재현. 실제 iPhone/장기 안정성 미검증으로 PARTIAL |
| category `window.zara.viewPayload` | 공개 category page HTML | commercial component/color ID | 익명 브라우저 | ID는 catentry/variant 계열. 내부 productId와 다르므로 대체 불가 |
| size API | `GET /itxrest/4/catalog/store/11717/product/{catentryId}/size-measure-guide?locale=ko_KR` | guide JSON | 표본에서는 cookie/auth 불필요 | URL v1과 HTML catentry 일치 검증 후 호출; 3/3 garment measure |

표준 상품 GET은 `Accept: text/html...`, `Accept-Language: ko-KR`, `User-Agent: FitMatch/1.0 (iPhone; iOS 18.0)`, redirect follow로 수행했다. HTTP 200이었지만 3,288-byte Akamai interstitial이었고 `bm-verify`와 `triggerInterstitialChallenge`가 존재했다. 원본 SHA-256은 `dc3952e136b24524c0c68d0a6a4c7bf6ea808e0a046e55231cc40a771ae3c486`이다. per-response 값은 저장하지 않고 sanitized fixture만 남겼다.

구현한 parser identity는 다음 불일치에 fail-closed한다.

- requested/resolved style 불일치
- analytics `productRef` style 불일치
- URL v1과 analytics `catentryId` 불일치
- internal `productId` 누락
- challenge marker
- malformed style/v1

삭제·unavailable·sale 상품의 충분한 표본, 실제 iPhone, 장기 재현성은 확보하지 못했다. 따라서 `IDENTITY_RESOLVER = PARTIAL`이다. 일반 앱 흐름은 feature gate로 닫혀 있으며 DEBUG PoC만 사용할 수 있다.

### 공개 사용 허가

저장소 검색에서 ZARA 계약, 제휴, API 사용 승인 문서는 발견되지 않았다. 사용자 제공 자료에도 허가 문서는 없었다. ZARA 공개 도움말/약관에서는 FitMatch가 이 endpoint를 production 수집에 사용할 수 있다는 developer/API grant를 확인하지 못했다. 법률적 허용 여부는 해석하지 않고 `API_USAGE_AUTHORIZATION = NOT_VERIFIED`로 둔다.

## D. Identity matrix

> 아래 D/E 표는 최초 조사 당시 내부 `productId`로 size API를 호출한 역사적 결과다. 호출 식별자가 잘못됐으므로 현재 guide coverage 판정에 사용하지 않는다. 정정 표본은 `ZARAAudit/zara_webview_poc_samples.jsonl`을 사용한다.

아래 값은 URL을 만들어낸 것이 아니라 사용자 제공 URL, 기존 조사 자료, 실제 ZARA catalog/product 화면에서 확인한 상품만 사용했다. size 결과는 2026-08-21 audit cache 기준이다.

| 표본 | style | v1/catentry | internal productId | section / family | resolver source | size API |
|---|---:|---:|---:|---|---|---|
| 남성 레귤러 핏 셔츠 | 04166166 | 545490346 | 545486853 | MAN / 셔츠 | embedded analytics | body_only, 200 |
| 남성 울 블레이저 | 05552381 | 551791628 | 551789966 | MAN / 브레이저 | embedded analytics | body_only, 200 |
| 남성 플리츠 팬츠 | 06861017 | 555813567 | 555794883 | MAN / 바지 | embedded analytics | body_only, 200 |
| 남성 니트 폴로 | 05987400 | 545479232 | 545475314 | MAN / 스웨터 | embedded analytics | body_only, 200 |
| 남성 스포츠 재킷 | 06987339 | 549815778 | 549813606 | MAN / 스포츠 재킷 | embedded analytics | body_only, 200 |
| 남성 데님 | 04470350 | 547367126 | 547363203 | MAN / 바지 | embedded analytics | body_only, 200 |
| 남성 버뮤다 | 04090032 | 555080429 | 555068728 | MAN / 버뮤다반바지 | embedded analytics | body_only, 200 |
| 남성 스웨트셔츠 | 04087303 | 549569317 | 549551955 | MAN / 스웨트 셔츠 | embedded analytics | body_only, 200 |
| 여성 티셔츠 navy | 04174325 | 547793140 | 545408873 | WOMAN / 티셔츠 | embedded analytics | body_only, 200 |
| 같은 티셔츠 brown | 04174325 | 555526397 | 545408873 | WOMAN / 티셔츠 | embedded analytics | body_only, cache reuse |
| 같은 티셔츠 cream | 04174325 | 555529728 | 545408873 | WOMAN / 티셔츠 | embedded analytics | body_only, cache reuse |
| 여성 원피스 | 01058506 | 585384053 | 550330066 | WOMAN / 드레스 | embedded analytics | body_only, 200 |
| 여성 셔츠 | 08741239 | 584074972 | 545478073 | WOMAN / 셔츠 | embedded analytics | body_only, 200 |
| 여성 가디건 | 02893103 | 545474606 | 545471348 | WOMAN / 가디건 | embedded analytics | body_only, 200 |
| 여성 스포츠 재킷 | 04391892 | 547008825 | 547002700 | WOMAN / 스포츠 재킷 | embedded analytics | body_only, 200 |
| 여성 데님 | 01934230 | 585050955 | 545395654 | WOMAN / 바지 | embedded analytics | body_only, 200 |
| 여성 쇼츠 | 04391520 | 585264213 | 547261621 | WOMAN / 버뮤다반바지 | embedded analytics | body_only, 200 |
| 여성 블레이저 | 02753522 | 585277985 | 545479171 | WOMAN / 브레이저 | embedded analytics | body_only, 200 |
| 여성 스커트 | 08338537 | 547002060 | 546995917 | WOMAN / 치마 | embedded analytics | body_only, 200 |
| 기존 API garment control | 미확보 | 미확인 | 498702922 | 미확인 | Phase 1 API evidence | garment_measure, 200 |

동일 style 04174325의 세 v1에서 internal productId와 size API cache는 같았다. 이는 이 표본의 product-level guide 공유를 보여줄 뿐, 모든 style/color가 같다는 일반 규칙은 아니다. 세 ID 간 산술 변환은 사용하지 않았다. 확인된 identity collision은 없었다.

## E. Category별 guide 조사

요청은 동시성 1, cache 우선, timeout 15초, 403/challenge 무재시도, transient 5xx만 최대 1회 재시도로 수행했다. 결과는 20 manifest rows, 18 unique size requests다.

| section / structured family | manifest rows | 독립 상품 | garment | body-only | both | blocked/unavailable | raw garment code |
|---|---:|---:|---:|---:|---:|---:|---|
| MAN / 셔츠 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| MAN / 브레이저 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| MAN / 바지(일반+데님) | 2 | 2 | 0 | 2 | 0 | 0 | - |
| MAN / 스웨터 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| MAN / 스포츠 재킷 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| MAN / 버뮤다반바지 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| MAN / 스웨트 셔츠 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| WOMAN / 티셔츠 | 3 | 1 style, 3 colors | 0 | 3 | 0 | 0 | - |
| WOMAN / 드레스 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| WOMAN / 셔츠 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| WOMAN / 가디건 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| WOMAN / 스포츠 재킷 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| WOMAN / 바지 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| WOMAN / 버뮤다반바지 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| WOMAN / 브레이저 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| WOMAN / 치마 | 1 | 1 | 0 | 1 | 0 | 0 | - |
| API-only control / category 미확인 | 1 | 1 | 1 | 0 | 0 | 0 | chest, front-length, sleeve-length, back-width, arm-width |

총계는 `body_only=19`, `garment_measure=1`, `both=0`, `empty=0`, `blocked=0`, `unavailable=0`, `parse_error=0`이다. 실제 URL 상품 기준으로는 17/17이 body-only다. family당 독립 상품 3개 목표를 충족하지 못했다. 이유는 공개 category payload가 내부 productId를 제공하지 않아 각 상품 detail의 challenge-sensitive analytics를 개별 확인해야 했고, 불필요한 crawling/challenge 반복 금지 정책을 지켰기 때문이다. 따라서 이는 제한 표본이며 coverage 판정은 `INSUFFICIENT`다.

실제 `both`와 `empty` 응답은 확보하지 못했으므로 fixture를 만들어내지 않았다. `malformed`만 parser 방어 테스트용 synthetic fixture임을 파일명과 내용에 명시했다.

## F. Measurement basis

실제 garment control 응답 SHA-256: `1b18d6e486ce5442a170bdd5fb53caea63300b2475929fc97afbf459a7246ea7`. `cm`과 `in`이 함께 있고 parser는 raw `cm` 값만 보존한다.

| raw field | 관찰 의미 | unit | width/circumference 또는 시작점 | 근거 상태 | canonical mapping |
|---|---|---|---|---|---|
| `zone-name-chest` | 가슴 | cm/in | width인지 circumference인지 공식 확인 없음 | PROBABLE | 불가; raw-only |
| `zone-name-front-length` | 앞길이 | cm/in | 시작점/종료점 공식 확인 없음 | PROBABLE | 불가; raw-only |
| `zone-name-sleeve-length` | 소매길이 | cm/in | 어깨 seam/center-back 등 시작점 미확인 | PROBABLE | 불가; raw-only |
| `zone-name-back-width` | 등너비 | cm/in | canonical 대응 정의 미확인 | UNKNOWN | 불가; raw-only |
| `zone-name-arm-width` | 암폭 | cm/in | canonical 대응 정의 미확인 | UNKNOWN | 불가; raw-only |

`measureGuideInfo`는 garment measurement 후보, `sizeGuideInfo`는 body recommendation으로 코드와 fixture에서 분리했다. 그러나 raw label 자체를 basis 검증 근거로 쓰지 않았다. 모든 garment record는 `measurementCode=.unknown`, `semanticStatus=.unknownDefinition`, `evidenceLevel=.unknown`으로 저장되고 `candidate_canonical=...;basis_status=PROBABLE`만 raw info에 남는다. 따라서 match score, reliability, comparison engine 입력에는 들어가지 않는다.

`sizeGuideInfo`는 size 생성, 2분할, 여유분 추정, 다른 브랜드 보정, confidence 계산에 전혀 사용하지 않는다.

## G. Category fail-closed 수정

기존 root cause는 `section/family/subfamily/productName` 문자열 규칙이 실패하면 최종적으로 `.top/.shortSleeve`를 반환한 것이었다. 이 때문에 미분류, mixed family, 액세서리까지 반팔 상의로 조용히 확정될 수 있었다.

최소 수정은 다음과 같다.

1. 공식 `section → family → subfamily`만 classification 입력으로 사용한다.
2. product name은 category 결정에서 제외하고 표시 metadata/review hint로만 보존한다.
3. unknown, mixed(`탑 | 바디수트`, `스웨트셔츠 | 조거 팬츠`), non-apparel는 `.other/.other`로 만든다.
4. parser는 해당 상태를 성공으로 반환하지 않고 `ProductURLParserPartialError`로 종료한다.
5. category가 구조적으로 확정되어도 verified comparable measurement가 없으면 역시 partial/unavailable로 종료한다.

현재 공통 모델에는 별도 `reviewRequired` enum이 없다. 대규모 공통 model 변경 대신 기존 `.other/.other + ProductURLParserPartialError`를 사용했다. 이 경로는 잘못된 비교 진입을 막고 metadata는 보존한다.

## H. Regression risk

- `ProductMetadata.externalVariantID`는 optional 기본값이라 기존 initializer/call site에 값이 없으면 이전 동작을 유지한다.
- observation variant ID 변경은 `resolution.source == "zara"`이고 값이 있을 때만 적용된다. Musinsa/Uniqlo는 기존 color 또는 `__default__` 규칙을 그대로 사용한다.
- parser dispatch와 공통 `ParsedProductInfo` 필수 category field는 바꾸지 않았다.
- comparison engine, score, reliability, category eligibility, closet, history를 수정하지 않았다.
- 남은 위험은 `.other` partial metadata가 observation shadow 경계까지 전달될 수 있다는 점이다. 운영 DB는 현재 ZARA CHECK로 write를 차단하고 있으며, 다음 DB Phase에서도 unresolved category를 confirmed/runtime-comparable로 승격하지 않아야 한다.

## I. 테스트

환경: Xcode, iPhone 17 Pro Simulator, iOS 26.3.1.

| 순서 | 명령/범위 | 결과 |
|---|---|---|
| 1 | ZARA Phase 1.5 suite | 15 passed, 0 failed |
| 2 | URL dispatch + 기존 ZARA 2 + provider 선택 회귀 | 5 passed, 0 failed |
| 3 | Supabase resolver suite | 9 passed, 0 failed |
| 4 | iPhone 17 Pro Simulator visible WKWebView | 티셔츠·셔츠·팬츠 3/3 identity + garment API 성공 |
| 5 | `FitMatchTests` 전체 unit target | 미실행 |

첫 targeted build에서는 신규 test suite의 `@MainActor` 누락으로 compile fail이 발생했고 수정했다. 두 번째 build에서는 기존 ZARA test의 복합 `#expect`가 compiler type-check timeout을 일으켜 assertion을 단순 분리했다. 이후 위 targeted/affected 결과는 모두 통과했다. 실행하지 않은 physical iPhone, App Store production build, staging E2E는 통과로 표현하지 않는다.

## J. 미확인 사항

- challenge 없이 iOS app process가 상품 analytics를 안정적으로 받는 공식 resolver
- 삭제·품절·sale 상품의 resolver 상태 구분 및 장기 재현성
- 04174325 외 2개 이상의 동일-style 다색상 사례
- category family당 3~5개 독립 상품의 guide coverage
- 실제 `both`, `empty`, size API 403/challenge/unavailable 응답
- raw field별 공식 diagram/definition에 근거한 width/circumference 및 측정 시작점
- ZARA 전체 source taxonomy와 시즌 변경 안정성
- FitMatch의 ZARA API 사용 허가 또는 파트너 계약
- 실제 iPhone 네트워크, App Store production build, staging end-to-end

## K. 다음 단계

1. ZARA가 허용하는 공식 product metadata/resolver 또는 계약 근거를 확보하고, 삭제·품절·sale 포함 실제 iPhone 표본으로 동일 identity를 재검증한다.
2. resolver가 확보된 뒤 family당 3~5개 독립 상품으로 guide audit을 확장하고, 공식 diagram/문서로 raw measurement basis를 `VERIFIED`까지 올린다.
3. 위 두 조건이 충족된 경우에만 staging에서 ZARA source/CHECK/category/measurement mapping migration과 rollback을 적용·검증한다.

현재 결론: **다음 DB Phase 진행 불가**. 운영 DB migration, seed, 전체 ZARA integration, comparison engine 변경으로 넘어가지 않는다.

## L. 후속 사용자 승인 DB 반영 — 2026-08-21

Phase 1.5 종료 뒤 사용자가 ZARA DB 테스트 준비를 명시적으로 승인했고, 이후 제공한 `zara_fitmatch_collection_20260813.zip`도 validator와 deterministic rebuild를 통과했다. 이에 category·observation DB 경계를 테스트 가능한 범위까지 확장했다. 이는 위 조사 시점의 gate 판정을 소급 변경하거나 production 출시를 승인하는 작업이 아니다.

- 운영 Supabase migration ledger:
  - `20260821032148 seed_zara_verified_categories`
  - `20260821042246 add_zara_observation_source`
  - `20260821042251 enable_zara_testing_categories`
  - `20260821042258 seed_zara_official_category_tree`
  - `20260821042806 publish_zara_client_category_mappings`
- `public.sources.zara.is_active=true`
- source category: analytics namespace 36건 + 공식 숫자 ID namespace 213건 = 총 249건
- public/client mapping 각각: confirmed 56, review_required 51, rejected 142
- active runtime release: `fitmatch-active-with-zara-official-tree-2026-08-13-v1`
- runtime mapping: 전체 3,483건 중 ZARA 56건; expected/actual 일치
- observation CHECK와 authenticated submit/service-role batch RPC에 `zara` 허용
- 부모 누락 0, client/public mapping parity 오류 0, runtime resolver의 confirmed/review/unknown fail-closed probe 통과
- 미적용: ZARA measurement mapping, positive source mapping의 자동 product-confirmed 승격, production release gate

추가 targeted XCTest는 iPhone 17 Pro Simulator(iOS 26.3.1)에서 24/24 통과했다. category 등록과 앱 read/observation 경계는 테스트할 수 있지만, 공식 measurement basis가 확인되지 않아 추천 사이즈·매칭률 입력은 계속 차단한다. API authorization, 실제 iPhone, staging E2E도 아직 확인되지 않았으므로 `READY_FOR_PRODUCTION_RELEASE=NO`다.

## M. 운영 30상품 A-test 적재 — 2026-08-21

사용자가 실제 ZARA 상품 20~30건의 운영 DB 적재를 명시적으로 승인한 뒤, 제공된 수집 패키지에서 서로 다른 상품 30건을 선정했다. 29건은 근거가 명확한 category decision으로 확정했고, `자수 프린트 스커트 팬츠` 1건은 세부 유형을 임의 확정하지 않고 `review_required`로 보존했다.

공개 size guide는 동시성 1, cache 우선, transient 5xx 1회 재시도 정책으로 다시 수집했다. 결과는 실제 색상 variant 45건, size 188건, raw measurement 870건이다. 45개 variant 중 42개는 `measureGuideInfo`, 3개는 `sizeGuideInfo`만 제공했다. body-only 3건은 size/garment measurement로 변환하지 않았다. garment raw field도 공식 측정 기준이 검증되지 않아 870건 전부 `measurement_alias_not_found`, `is_comparable=false`로 저장했다.

운영 반영 후 상태는 다음과 같다.

| 항목 | 결과 |
|---|---:|
| ZARA product | 30 |
| 실제 source variant | 45 |
| runtime 필수 `__default__` placeholder | 30 |
| size | 188 |
| raw measurement | 870 |
| comparable measurement | 0 |
| confirmed product classification | 29 |
| review-required product classification | 1 |
| ZARA product observation | 0 |

적재는 인증 사용자를 가장하지 않고 기존 service-role 전용 `fitmatch_batch_ingest_product` 경계로 수행했다. 따라서 이 30건은 canonical product table의 관리자 A-test 표본이며, 사용자 observation history는 생성하지 않았다. `__default__` variant 30건도 runtime upsert 계약상 생성되는 빈 placeholder이므로 실제 색상 variant로 계산하지 않는다.

새로 관찰된 structured leaf category 13건을 `supabase/migrations/111_extend_zara_production_sample_categories.sql`로 추가했다. 이 중 9건은 confirmed, dress 및 mixed/ambiguous pants 4건은 review-required다. 운영 migration ledger에는 `20260821080945 extend_zara_production_sample_categories`로 적용됐다. 적용 후 ZARA source category는 262건이고 public/client mapping은 각각 confirmed 65, review-required 55, rejected 142로 일치한다. active runtime ZARA mapping은 confirmed 65건이다.

상품별 decision은 실제 앱 parser가 생성하는 `ZARA > 남성/여성 > family > subfamily` 경로와 `SECTION:FAMILY:SUBFAMILY` code를 사용했다. 앱 경로의 source resolver 및 product resolver probe는 confirmed 상품을 올바른 FitMatch category로 반환했고, 실측이 비교 불가이므로 `comparison_ready=false`를 반환했다.

코드에서는 ZARA structured category를 상품명 heuristic으로 다시 덮어쓰지 않게 했고, `지퍼 재킷`이 `퍼 재킷` substring에 걸려 mouton으로 오분류되는 문제를 단어 경계 규칙으로 수정했다. ZARA targeted suite는 17/17, 영향 공통 회귀 suite는 32/32 통과했다.

현재 A-test 결론은 다음과 같다.

```text
PRODUCTION_SAMPLE_CATALOG_INGEST: PASS
PRODUCT_CATEGORY_RESOLUTION: 29 CONFIRMED / 1 REVIEW_REQUIRED
RAW_MEASUREMENT_PRESERVATION: PASS
CROSS_BRAND_COMPARISON_READY: NO
READY_FOR_PRODUCTION_RELEASE: NO
```

즉 상품·variant·size·raw measurement와 category 분류를 운영에서 조회하는 테스트는 가능하다. 그러나 ZARA raw measurement의 공식 basis와 canonical alias가 검증될 때까지 ZARA↔무신사·유니클로 자동 추천·매칭률 계산은 의도적으로 차단된다. API 사용 권한, 실제 iPhone live resolver, App Store build, staging E2E도 여전히 별도 release blocker다.

구조화 산출물:

- `ZARAAudit/zara_production_sample_30_manifest.jsonl`: 색상 variant 단위 45행
- `ZARAAudit/zara_production_sample_30_payloads.jsonl`: 상품 단위 canonical ingest payload 30행
- `ZARAAudit/zara_production_sample_30_decisions.jsonl`: 상품별 classification decision 30행
- `ZARAAudit/prepare_production_sample_30.mjs`: 재현 가능한 선정·수집·payload 생성기

## N. 검증된 measurement subset 적용 — 2026-08-21

사용자 승인 후 ZARA KR의 공식 상품 사이즈 UI와 운영 30상품 응답을 다시 대조해, 의미와 단면 기준을 함께 확인할 수 있는 최소 subset만 활성화했다. 공식 UI는 의류를 평평하게 편 상태에서 측정한다고 안내하며 값과 FitMatch canonical 값이 모두 cm 단면이므로 변환 multiplier는 전부 `1.0`이다. 둘레로 확대하거나 2로 나누지 않는다.

| category scope | ZARA raw field | FitMatch canonical | basis | 변환 | 상태 |
|---|---|---|---|---:|---|
| bottoms | `zone-name-waist` | `waist_width` | `waist_edge_to_edge` | ×1 | comparable |
| bottoms | `zone-name-hips` | `hip_width` | `hip_at_widest` | ×1 | comparable |
| bottoms | `zone-name-front-rise` | `front_rise` | `front_crotch_to_waist` | ×1 | comparable |
| dresses | `zone-name-chest` | `chest_width` | `chest_pit_to_pit` | ×1 | comparable |
| dresses | `zone-name-waist-full-body` | `waist_width` | `waist_edge_to_edge` | ×1 | comparable |
| dresses | `zone-name-hips` | `hip_width` | `hip_at_widest` | ×1 | comparable |

`front-length`, `sleeve-length`, `arm-width`, `back-width`, `front-length-lower`, `back-rise`, `front-length-full-body`는 정확한 시작·종료점 또는 canonical 대응이 확인되지 않아 raw-only를 유지했다. `back-width`를 shoulder로 바꾸지 않았고 `sizeGuideInfo` body guidance도 비교에 사용하지 않았다. 상의는 안전한 두 번째 핵심 치수가 부족하므로 이번 활성화 대상이 아니다.

앱 parser와 A-test payload의 `raw_code`는 위치 문자 `A~E` 대신 stable `tableTitleZone`을 사용하고, 원래 `zoneId`는 `raw_zone_id` evidence에 보존한다. category별 최소 조건도 parser에서 다시 확인해 팬츠는 waist+hip, 원피스는 chest/waist/hip 중 2개가 있어야 성공한다. 미충족 상품은 잘못된 추천으로 진입하지 않는다.

운영 Supabase에는 `seed_zara_verified_measurement_subset` migration(version `20260821090138`)을 적용하고 30상품을 동일 service-role ingest 경계로 재정규화했다. 결과는 raw measurement 870건, comparable 177건, raw-only 693건이며 `raw_zone_id`와 전체 `source_dimensions`는 870건 모두 보존됐다. unstable `A~E` raw code는 0건이다. product classification은 confirmed 29건, review-required 1건 그대로다.

DB runtime compatibility probe 결과는 다음과 같다.

| 비교 | 결과 | 근거/차단 사유 |
|---|---|---|
| ZARA 팬츠 ↔ ZARA 팬츠 | PASS | waist, hip, front rise 공통 |
| ZARA 팬츠 ↔ UNIQLO 팬츠 | PASS | waist, hip, front rise 공통; 정책 최소 충족 |
| ZARA 팬츠 ↔ Musinsa 팬츠 | BLOCKED | waist만 핵심 공통; Musinsa thigh와 ZARA hip은 다른 치수이므로 `required_any_measurements_missing` |
| ZARA 원피스 ↔ ZARA 원피스 | BLOCKED | canonical 폭은 있으나 표본의 공식 length classification이 없어 `length_classification_missing` |
| review-required ZARA ↔ UNIQLO | BLOCKED | `classification_not_confirmed` |
| 기존 UNIQLO 팬츠 ↔ Musinsa 팬츠 | PASS | 기존 provider 회귀 경로 유지 |

Musinsa 교차 비교를 억지로 통과시키기 위해 hip을 thigh로 바꾸거나 비교 정책·점수를 느슨하게 하지 않았다. 원피스 길이도 상품명만 보고 확정하지 않았다. 따라서 검증 subset DB 반영은 완료됐지만 전체 ZARA 교차 브랜드 지원과 production release gate는 계속 닫혀 있다. `API_USAGE_AUTHORIZATION=NOT_VERIFIED`, `READY_FOR_PRODUCTION_RELEASE=NO`다.

검증 결과는 ZARA targeted 20/20, closet hydration 2/2 통과다. `FitMatchTests` 전체 struct는 260 passed, 9 assertion-failed, 장시간 corpus 1건 canceled로 종료됐다. 실패는 기존 COS/category taxonomy 기대값과 현재 구현의 불일치이며 ZARA 테스트 실패는 없었다. `storedMusinsaCorpusBuildsActualMeasurementFitPairs`가 10분 이상 출력 없이 실행돼 결과 번들 보존 후 interrupt했으며, 전체 suite를 통과했다고 표현하지 않는다. 결과 bundle은 `/tmp/FitMatchZARACommonFinalDerivedData/Logs/Test/Test-FitMatch-2026.08.21_18-16-04-+0900.xcresult`다.
