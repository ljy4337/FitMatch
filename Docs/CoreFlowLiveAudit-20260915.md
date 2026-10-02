# FitMatch 핵심 계약 및 신규 API 감사 — 2026-09-15

## 수정 후 상태 — 2026-09-15 (원래 감사 기록은 아래에 보존)

- F01: 새 링크 등록은 정확한 서버 사이즈 UUID로 서버가 canonical 실측을 저장한다. 원문 표시/관측값 보존, 직접 입력·수정 계약 유지. 클라이언트의 중복 의미 변환은 등록 authority에서 제거했다.
- F03: mapped 후보 조회도 eligible_candidate_sizes를 호출해 실제 허가된 size ID만 반환하도록 DB 적용.
- F04: ZARA의 별도 최소 두 항목/허리+엉덩이 조건 삭제. 원문 실측은 서버로 전달하고 실제 비교 가능 여부는 서버가 판정한다.
- F05: UNIQLO details 요청에 URL의 priceGroupCode 전달. suffix -001/-002의 동일성은 여전히 미검증이며 임의 변경하지 않았다.
- DB 적용: `linked_creation_server_snapshot_and_verified_candidates`. 적용 파일 `supabase/sql/core_registration_candidate_contract_Apply.sql`; 권한/SECURITY DEFINER/빈 search_path 유지 확인. 비로그인 호출 거절 PASS.
- DB read-only snapshot 검증: mapped 상품 193 sizes 중 188 usable, 잘못된 코드/단위/값과 중복 코드/semantic conflict 0. ZARA 5 sizes는 canonical 실측 0으로 기존 차단 유지. 이는 인증 등록 성공 증거가 아니다.
- Swift 회귀검사 PASS: 110 passed / 0 failed / 3 gated live tests NOT RUN. 초기 테스트 작성 컴파일 오류 수정 후, 폐기된 ZARA parser gate를 기대하던 두 테스트를 현재 서버 authority 계약으로 갱신해 재통과.
- F02: 기존 총장 6행 evidence_payload={}이고 원천 재조회 두 건은 HTTP 403 Cloudflare 차단. 정확한 측정 기준을 확인하지 못해 호환 alias를 추정 생성하거나 원문을 삭제하지 않았다. 새 등록은 확인된 canonical subset만 서버가 사용하므로 이 raw-only 행을 임의 canonical로 보낼 필요가 없다.
- 실제 정상 세션 UI 검증은 별도 `FitMatchAuthenticatedRegistrationUITests`로 수행. 최종 결과는 최신 Handoff 참조. 모의 인증 테스트나 HTTP 성공을 앱 등록·비교 성공으로 계산하지 않는다.


## 범위와 한계
- 로컬 connectDB, 미커밋 변경 포함. Behavior Map FLOW-PRODUCT-LOAD / CLOSET-LINK / CANDIDATES / COMPARE-BEGIN / TAXONOMY-MEASURE를 따라 관련 Swift 소유자와 배포된 SQL을 읽기 전용으로 대조했다.
- 연결 DB hnkplvyegonlhumlejst: 조회 시점 products 36 / variants 66 / sizes 317 / raw measurements 1400 / active Closet items 3. 전체 상품 그룹과 전체 사이즈 canonical resolver를 조회했다. 매핑 17 / 미매핑 19. 미매핑 자체는 오류가 아니다.
- 미매핑은 A~G 컨텍스트를 읽기 전용으로 대입해 resolver 결과를 검사했다. 이는 사용자 선택 시 가능한 데이터 해석 검사이며, 전역 분류를 결정하거나 변경하지 않았다.
- 배포 함수 11개 오버로드(Closet snapshot/upsert, candidates, eligible, authorization, begin, complete), 추가 authorization_v1 2개와 public candidate wrappers를 조회했다. 전체 저장소/DB 모든 함수의 검증 완료를 의미하지 않는다.
- 실제 앱 parser 실행, 인증된 Closet insert/read-back, candidate/begin/complete 전체 왕복, UI 테스트 및 신규 빌드는 이번 감사에서 NOT RUN. 앱/DB 동작 수정 없음.

## 발견 사항

### F01 / P1 — 표시용 파서 실측이 서버 canonical 저장 계약과 충돌할 수 있음 (코드 경로 확인)
- ShoppingProductViewModel.swift:1121 registrationPresentationMeasurementRecords는 양수 retailerRecords가 하나라도 있으면 runtimeRecords 대신 반환한다.
- FitMatchComparedProductClosetRegistration.swift:692는 그 selectedSize.measurementRecords를 전송한다.
- FitMatchSupabaseProductResolver.swift:2927 linkedCanonicalMeasurements는 로컬 코드로 canonical 이름을 변환하지만 선택한 서버 size의 canonical 집합과 일치하는지 대조하지 않는다. 알려지지 않은 코드는 제외한다.
- 배포 apply_linked_closet_snapshot_for_swift는 RETAILER_SNAPSHOT의 코드/값/cm가 선택한 size canonical과 정확히 맞아야 하고, 서버 canonical 항목의 누락도 거절한다.
- 따라서 원문 실측이 화면에 보여도 앱/서버 매핑 차이로 저장이 실패할 수 있다. 앞선 5328103 총장 누락과 같은 유형이다. 현재 새 인증 요청의 실패를 재현한 것은 아니다.
- 수정 방향: 표시할 retailer facts와 서버가 승인한 저장 measurements를 분리하여 정확한 size identity로 연결. 불일치가 있으면 저장 전에 명시적 계약 오류로 드러내고 원인을 고친다. 원문 삭제, 임의 단위 환산, USER_MANUAL 전환, 서버 검증 완화는 금지.

### F02 / P1 — 구형 MUSINSA 총장 미매핑 데이터가 남아 있음 (DB에서 확인)
- 3346165: parser_code=legacy_unmapped 총장 2행, C 컨텍스트에서 raw 10 / canonical 8 / unresolved 2.
- 4818151: 같은 총장 4행, C에서 raw 20 / canonical 16 / unresolved 4.
- 앞서 추가한 하의 총장 alias는 actual_size에만 존재. tops/outerwear에는 legacy_unmapped alias도 있지만 bottoms에는 없다.
- 이는 5328103 수리가 모든 기존 총장 행까지 해결한 것이 아님을 뜻한다. 실제 새로 불러오기/재비교/저장에 미치는 영향은 경로별 재현 필요.
- 수정 방향: 원문 및 method evidence로 기존 6행의 의미를 검증하고 공식 관측으로 재수집하거나 제한된 호환 매핑을 검토한다. legacy_unmapped라는 이유로 전부 같은 의미로 매핑하거나 데이터 삭제하지 않는다.

### F03 / P1 — 자동 매핑 후보와 사용자 그룹 선택 후보의 검증 기준 불일치 (배포 SQL 확인)
- find_reference_candidates(uuid,uuid)는 같은 그룹 또는 A/B 관계면 allowed=true로 반환하고 대상 variant의 모든 size ID를 eligible_product_size_ids에 넣는다. common_measurement_count=null이고 실제 eligible_candidate_sizes를 호출하지 않는다.
- 3인자 함수는 requested group이 있으면 각 Closet마다 eligible_candidate_sizes를 실행한다. null이면 위 2인자 함수에 위임한다.
- Swift도 requested group이 없으면 2인자 흐름을 사용한다.
- 결과: 후보로 제시된 옷/사이즈가 실제 비교 허가 단계에서는 거절될 수 있는 구조. 이 후보 오판정은 코드로 확인했으나 인증된 특정 조합의 UI 실패는 이번에 재현하지 않았다.
- mapped 경로는 A/B 교차 후보를 허용하고 session 경로는 같은 group만 허용하는 차이도 있다. 허용 정책은 임의 통일하지 말고 현재 활성 서버 정책과 제품 의도를 검증해야 한다.
- 수정 방향: 후보 목록과 실제 eligible/authorization 결과를 같은 서버 판정으로 맞춘다. 서버에서 승인한 후보를 사용자가 선택하는 정책 유지. Swift fallback 금지.

### F04 / P1 — ZARA 파서에 서버와 다른 실측 최소 조건이 남음 (코드로 확인)
- ZARAParser.swift:203 / ZARASizeGuideParser.hasComparisonReadySize(:1086)는 상의 2개+어깨/가슴, 아우터 2개+가슴, 하의 허리+엉덩이, 원피스 가슴/허리/엉덩이 중 2개를 요구한다.
- 조건 미달 시 실제 sizes를 보유한 채 measurementAvailability=unavailable, enterMeasurementsManually를 설정하고 partial error를 던진다.
- 상위 ShoppingProductViewModel은 partial에서도 서버 resolve를 호출한다. 따라서 모든 경우가 최종 차단된다고 단정하지 않는다. 다만 원문 사실/서버 정책과 별개의 unavailable 및 수동 입력 상태가 만들어지는 불일치가 있다.
- 수정 방향: 파서는 실제 존재하는 실측과 의미 검증 상태를 보존하고, 비교 허가는 서버 공통 항목 >=1 및 나머지 정책이 결정하도록 정렬한다. 단일 실측 신규 상품으로 UI 상태/저장/비교까지 검증 필요.

### F05 / P2 — UNIQLO URL price group과 details API 요청 불일치 (코드로 확인, 실제 실패 영향 미확인)
- UniqloParser.swift:150은 URL priceGroupCode를 추출해 반환하지만 :285 fetchProductDetailsResponse는 details 경로를 price-groups/00으로 고정한다.
- -001/-002 suffix도 core product ID와 color hint 기반으로 처리되어, 의미 있는 상품 변형인지 별도 검증이 필요하다. suffix가 반드시 다른 상품이라고 단정하지 않는다.
- 새로 검사한 E485575는 /00이므로 이 결함의 실사용 실패 증거는 아니다.
- 수정 방향: 동일 URL identity/price-group context를 details·size·stock 요청 전체에 전달하고 실제 provider evidence로 suffix 의미를 검증한다.

## 새 상품 실 API 검사
선정 전 FitMatchTests/FitMatchUITests/Docs QA의 ID 검색과 연결 DB를 확인했다. 검사 기록을 찾지 못한 상품이지, 접근할 수 없는 모든 과거 실행까지 '한 번도 검사 안 함'을 보증하지 않는다.

| 상품 URL | 실제 호출 결과 | 판정 |
|---|---|---|
| https://www.musinsa.com/products/6158959 | details 200, goodsNo 일치. actual-size 200, type 20 셔츠, M/L/XL/XXL 각 양수 실측 4개. 0 값의 추가 칸도 존재 | PASS: HTTP/JSON/실측 존재. Swift parser 및 저장은 NOT RUN |
| https://www.musinsa.com/products/6322076 | details 200, goodsNo 일치. actual-size 200 SUCCESS이지만 data=null | 원천 actual-size 없음. 상세 이미지 복구 가능성은 미검증; 상품 전체에 실측이 없다고 단정하지 않음 |
| https://www.uniqlo.com/kr/ko/products/E485575-000/00 | details/size-chart 200. E485575-000, S/M/L/XL 각 6개 의류 실측 항목. 공식 breadcrumb는 여성 파자마/홈웨어 > 라운지 팬츠 | PASS: HTTP/JSON/실측 존재. 그룹 추론/DB 등록 안 함 |
| https://www.zara.com/kr/ko/rll-p-shrt-p04496307.html | 로컬 GET 200이나 2241-byte bm-verify 접근 확인 HTML. 상품 internal ID/selected catentry 미확보 | BLOCKED: 이 실행 환경에서 상세/실측 API 체인 미진입. web 검색의 상품 설명은 API 통과 증거로 사용하지 않음 |

- 총 7회 GET: 6개 API JSON 응답 + ZARA 페이지 1개. 무신사 null 응답도 실패 목록에서 제외하지 않았다.
- 원본 응답은 /tmp/fitmatch-new-api-audit/, 호출 방법 /tmp/fitmatch-new-api-audit.py. 요약 manifest는 본 보고서 옆 JSON.
- API 응답 정상과 실제 앱 등록/비교 성공은 구분한다. 공유 앱에서 직접 생성한 링크 테스트는 NOT RUN.

## 권장 수정 순서 (미실행)
1. F01 저장 계약 분리와 실제 사용자 저장 오류 재현, F02 과거 관측 호환성 검증.
2. F03 후보/허가 통일 및 F04 ZARA 상태 계약 정렬. 각각 기존 실패 + 신규 상품으로 실제 등록/비교 재검사.
3. F05 옵션 context 정렬과 세 provider의 빈 응답/접근 제한 recovery, 정상 세션 UI 자동화 보완.

## 검증 상태
- PASS: 전체 36상품/317size resolver 및 그룹 조회, 배포 계약 대조, 신규 HTTP 요청/응답 기록.
- FAIL(감사 발견): F01~F04 계약/데이터 불일치. F05 조건부 위험.
- BLOCKED: 신규 ZARA 상세/실측 체인, 기존 시뮬레이터 조작 경로.
- NOT RUN: 신규 상품 Swift parser, authenticated save/compare end-to-end, UI/build, 전체 DB 함수 검증.
- 앱/DB 수정·배포·커밋·푸시 없음. 기존 미커밋 변경 보존.

