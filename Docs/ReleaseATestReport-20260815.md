# FitMatch 무신사·유니클로 출시 A테스트 보고서 (2026-08-15)

## 판정

현재 `main`은 **출시 보류**다. 정상 분류된 상품의 비교 후보 선택·차단 흐름은 대규모 시나리오에서 안정적이지만, 실제 상품명과 쇼핑몰 카테고리를 현재 production 분류기에 통과시킨 결과 사용자 비교 대상을 바꾸는 의미 오분류가 확인됐다.

이 검사는 무신사·유니클로 전체 판매 카탈로그를 의미하지 않는다. 현재 프로젝트가 보유한 공식 상품 corpus 5,026개(무신사 4,011 / 유니클로 1,015)를 전수 검사하고, 공식 endpoint 재조회와 기존 A테스트 비교 시나리오를 교차 감사한 결과다.

5,026개는 서로 다른 수집 묶음 2,560개 + 2,000개 + 신규 466개를 상품 ID 기준으로 합친 corpus다.

## 검사 범위와 방법

- 검사 기준: 로컬 `main` HEAD `9264814` (`origin/main`보다 1커밋 앞선 상태)
- 작업 트리에는 이번 감사 전부터 상세 화면 성능 진단 관련 미커밋 변경이 있었다. 분류기·비교 matcher·canonical bundle의 미커밋 변경은 없지만, 빌드 검증은 이 UI 작업까지 포함한 현재 작업 트리를 대상으로 했다.
- 현재 production `ParsedClosetClassification`으로 5,026개 전수 재분류
- 쇼핑몰 원본 카테고리, FitMatch 대분류·세부분류, comparison family, 길이 축 기록
- 구조상 애매하거나 `other`였던 325개를 실제 iPhone에서 production parser로 라이브 재검증
- 5,026개 공식 상품 endpoint를 저속 재조회하여 판매/사이즈 데이터 도달 여부 확인
- 기존 5,000건 A테스트와 신규 라이브 700건을 현재 발견된 의미 위험 상품과 교차 감사
- 내장 canonical bundle checksum과 runtime overlay 확인
- Release arm64 generic iPhone 빌드 확인
- Simulator는 사용하지 않았다. 기기 실행이 필요한 5,026개 분류 및 325개 라이브 parser 검증은 연결된 iPhone 14 Pro(iOS 26.6, arm64)에서 수행했고 두 XCTest 실행 모두 실패 0이었다.

## 전체 분류 결과

| 항목 | 결과 |
|---|---:|
| 입력 / 고유 상품 / 출력 | 5,026 / 5,026 / 5,026 |
| 구조적으로 유효한 자동 분류 | 4,701 |
| 사용자 확인 필요 | 325 |
| taxonomy contract invalid | 0 |
| placeholder `other` | 79 |
| 무신사 | 4,011 |
| 유니클로 | 1,015 |

FitMatch 대분류 분포는 아우터 1,612, 상의 1,434, 하의 1,043, 속옷 330, 레깅스 157, 기타 79, 원피스 44, 스커트 42, 홈웨어 39이며, 나머지 246개는 분류 확인이 필요하다.

| 쇼핑몰 | 아우터 | 상의 | 하의 | 속옷 | 레깅스 | 원피스 | 스커트 | 홈웨어 | other | 분류 NULL |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 무신사 | 1,531 | 1,075 | 904 | 189 | 133 | 28 | 18 | 0 | 79 | 54 |
| 유니클로 | 81 | 359 | 139 | 141 | 24 | 16 | 24 | 39 | 0 | 192 |

## 확인된 의미 결함

### P0: 출시 전에 수정해야 하는 비교 영향 결함

현재 bundle 정책과 matcher의 최종 product-level 교정까지 적용한 뒤에도 비교 결과에 직접 영향을 주는 상품은 고유 128개(전체 corpus의 2.55%, 무신사 113 / 유니클로 15)다. 의미 분류 결함·회귀 전체는 고유 233개(4.64%)다.
이 중 80개는 최신 `브라`/`brief` 회귀가 직접 만든 P0이고, 이를 제거해도 나머지 P0 48개는 별도로 남는다. 그 48개 중 42개도 현재 공식 실측이 즉시 제공된다.

| 활성 P0 원인 | 상품 수 |
|---|---:|
| `브라` 부분 문자열 오인식 | 77 |
| 명시적 가디건 구조 손실 | 10 |
| 스코츠 major/family 불일치 | 8 |
| 상의 브라탑 major/family 불일치 | 6 |
| 상·하의 복합 세트 단일 자동 분류 | 6 |
| 서로 다른 상체 구조 복합 세트 단일 자동 분류 | 5 |
| 블라우스가 T-shirt family로 잔존 | 4 |
| `brief` 포함 러닝 하의 속옷 오인식 | 3 |
| 히트텍 레깅스가 상체 base-layer family로 라우팅 | 3 |
| 하이픈 소매 길이 미해석 | 2 |
| 다중 길이 pack·옵션 의존·레이어드 길이·코치재킷 경로 우선 오류 | 각 1 |

1. `브라` 부분 문자열 오인식
   - 87개 무신사 상품이 `브라운`, `브라이트`, `CHAMBRAY`, `무브라이트` 등의 문자열 때문에 `속옷 / 여성 브라`로 바뀐다.
   - 예: `원턱 와이드 슬랙스[딥브라운]`, `플리츠 스커트 브라운`, 레더 재킷·코트 다수.
   - 원인: 안전한 단어 경계 검사 함수가 이미 있지만 `explicitUnderwearDetail`에서 별도로 `contains("브라")`를 먼저 적용한다.
   - 잘못된 대분류는 comparison profile의 `majorCategory`가 되어 정상 하의·아우터 기준 옷과의 비교를 차단하거나, bundle lookup이 없으면 속옷끼리 잘못 비교할 수 있다.
   - canonical bundle은 comparison family를 고쳐도 `Product.category` 자체는 바꾸지 않으므로 이 대분류 오류를 사후 복구하지 못한다.
   - 이 회귀는 로컬 최신 커밋 `9264814`에서 AIRism 구조 분류를 보완하며 `explicitUnderwearDetail`을 source category 판정보다 앞에 추가한 변경에서 유입됐다. `origin/main`에는 아직 이 커밋이 없다.
   - 기존 회귀 테스트 `brownBottomNamesDoNotBecomeBras()`가 바로 `카펜터 버뮤다 밴딩 팬츠 브라운`, `원턱 8부 썬스턴 버뮤다 카고팬츠 브라운`을 하의로 요구하지만, 현재 실제 production 5,026개 출력에서는 두 상품 모두 `underwear/women_bra`다. 즉 현재 HEAD는 이미 저장된 기대 계약과도 모순된다.

2. 겉옷 쇼츠·레깅스의 `브리프 라인드` 오인식
   - 3개 러닝 쇼츠/타이츠가 남성 브리프로 분류된다.
   - 상품 ID: 5774853, 4915410, 6111762.
   - 이 결함도 같은 `9264814`의 `explicitUnderwearDetail` 추가에서 유입됐다.

`브라` 87개 + `브리프` 3개, 총 90개는 corpus의 이전 분류에서는 모두 속옷이 아니었고 현재 HEAD에서만 속옷으로 바뀐 명확한 회귀다.
이 90개 중 84개는 현재 공식 실측까지 즉시 내려오므로 사용자가 바로 등록·비교를 시도할 수 있는 상태다.

3. 가디건 대분류 손실
   - 명칭이 명확한 가디건 10개가 `상의 / 니트`로 분류된다.
   - FitMatch taxonomy에서 가디건은 아우터이므로 정상 가디건 기준 옷과 major category가 달라 비교되지 않는다.

4. 다중 의류 세트 자동 분류
   - 상의+하의 세트 7개와 코트+베스트·탑+가디건 세트 5개가 단일 의류로 자동 분류된다.
   - `[SET]`처럼 문자열 앞에 붙은 표기를 현재 `" set"`, `"set "` 검사로 놓치며, 연결 문자 없는 `탑 가디건 세트`도 놓친다.
   - 최소 11개는 canonical eligibility가 명시적으로 차단되지 않아 단일 의류로 비교될 수 있다.

5. 스코츠와 브라탑의 major/family 교차 오염
   - 유니클로 스코츠 8개는 화면 분류가 스커트지만 runtime family가 pants라 스커트·팬츠 어느 쪽과도 정상 직접 비교되지 않는다.
   - 무신사 상의 경로의 브라탑/브라 인 나시 6개는 화면 대분류가 속옷, runtime family는 T-shirt라 정상 상의와 비교되지 않는다.
   - 유니클로 브라탑 3개는 같은 불일치가 있으나 현재 bundle에서 ineligible로 차단된다.

6. 명시적 블라우스 일부의 잘못된 비교 family
   - 명시적 블라우스 22개 중 4개는 bundle 적용 후에도 T-shirt family로 남아 일반 티셔츠 비교 후보가 된다.

7. 명확한 길이·옵션 구조 처리 누락
   - `Short-Sleeve`, `Long-Sleeve` 하이픈 표기를 읽지 못하는 상품 3개 확인.
   - `민소매/반팔 2종`, `나시 레이어드 반팔티`, `[나시 선택] 반팔 셔츠` 3개가 사용자 확인 없이 한 길이 구조로 확정된다.

8. 유니클로 merchandising 경로가 명확한 재킷 구조를 덮어씀
   - `E491320 KIDS PEANUTS코치재킷`은 현재 공식 metadata가 `tops / ut graphic tees`로 내려오지만, 상품명과 사이즈표(총장·어깨·가슴·등 중심 소매)가 명확한 코치재킷이다.
   - 현재 FitMatch는 `상의 / 반팔`, T-shirt family로 처리하여 키즈 티셔츠와 잘못 비교할 수 있다.

9. 유니클로 히트텍 하체 상품에 상체 comparison family 적용
   - `E480966`, `E485369`, `E487201`은 상품명이 명확한 레깅스이고 공식 사이즈도 각각 7개, 6개, 7개 제공된다.
   - 화면 분류는 `속옷`인데 canonical 경로 매핑이 `base_layer_top`, runtime family가 `tshirt`라 하체 레깅스가 상체 베이스레이어 정책을 사용한다.
   - 원인은 `히트텍 울트라 웜`, `히트텍 엑스트라 웜`, `히트텍 캐시미어 블렌드`처럼 상·하의가 함께 들어오는 경로를 상품 구조 확인 없이 상체 family로 확정하는 매핑이다.

### 실제 A테스트에서 나타나는 사용자 결과

| 내 옷장 | 가져온 상품 | 현재 FitMatch 판단 | QA 판정 |
|---|---|---|---|
| 잘 맞는 슬랙스 | `원턱 와이드 슬랙스[딥브라운]` | 가져온 상품을 여성 브라로 보아 슬랙스 후보를 차단 | 비정상 비교 불가 |
| 잘 맞는 코트 | `발마칸 코트 - 브라운` | 가져온 상품을 여성 브라로 보아 코트 후보를 차단 | 비정상 비교 불가 |
| 가디건 기준 옷 | 니트 경로의 명시적 가디건 | 가져온 상품은 상의, 기준 옷은 아우터가 되어 차단 | 비정상 비교 불가 |
| 반팔 티셔츠 기준 옷 | `[SET] T-shirt + Shorts` | 세트 확인 없이 티셔츠 한 벌로 자동 비교 가능 | 비정상 비교 가능 |
| 스커트 기준 옷 | 유니클로 미니스코츠 | 화면은 스커트지만 runtime은 pants라 스커트 후보 차단 | 비정상 비교 불가 |
| 상의 나시 기준 옷 | 상의 경로의 BRA-IN 나시 | 가져온 상품은 속옷, 기준 옷은 상의가 되어 차단 | 비정상 비교 불가 |
| 히트텍 레깅스 기준 옷 | 히트텍 울트라웜/엑스트라웜 레깅스 | 하체 상품에 T-shirt family가 적용되어 정상 레깅스 후보를 찾지 못함 | 비정상 비교 불가 |
| 긴팔/반팔 상의 | 구조와 길이가 명확한 정상 상품 | 자동 비교에서는 길이 차단, 사용자가 고르면 소매 제외 부분 비교 | 정상 동작 |
| 긴바지/반바지 | 구조와 길이가 명확한 정상 상품 | 자동 비교에서는 길이 차단, 사용자가 고르면 허리·엉덩이·허벅지 중심 참고 비교 | 정상 동작 |

### P1: 비교 또는 화면 신뢰도를 떨어뜨리는 분류 결함

1. 일반 셔츠 83개가 `셔츠`가 아니라 반팔·긴팔 세부분류로 저장된다.
2. 블라우스 22개가 `블라우스`가 아니라 소매 길이/T-shirt 축으로 저장된다.
3. 명확한 니티드 폴로셔츠 4개가 니트, 폴로셔츠 1개가 `브라운` 오인식과 겹쳐 속옷으로 저장된다.
4. 원인은 `canonicalDetailCode(tops)`가 명시적 셔츠·블라우스 구조보다 상품명 소매 길이를 먼저 반환하는 순서다.
5. canonical bundle이 대부분 comparison family를 `shirt`로 복구하여 티셔츠와의 자동 비교는 차단하지만, 화면 분류와 정확한 기준 옷 자동 선택은 달라질 수 있다.
6. 후보 설명 생성 한 곳이 family-aware 표시 함수가 아닌 공통 `displayName`을 사용하여, 긴바지 후보에 `같은 긴팔` 같은 문구가 다시 나타날 수 있다.
7. 무신사 상품 `4534935`의 공식 `goodsNm`에는 관리자 URL 문자열이 상품명 뒤에 붙어 있다. 앱 parser는 현재 `goodsNm`을 그대로 사용하므로 상품명 카드에도 손상된 문자열이 노출될 수 있다. 같은 응답의 `goodsNmEng`는 정상 상품명이므로 URL/관리자 패턴 검출 후 정상 필드로 fallback하는 방어가 필요하다.

### 안전하게 차단된 사례

- 325개 라이브 재검증: 파싱 성공 325, 실제 확인 필요 49, 위험한 `other` 자동 확정 0, 파서 실패 0.
- 최신 무신사 경로에서 `하의 / 기타 하의`로 구조 분류된 점프수트·오버올 55개는 내장 canonical record가 정확히 `rejected`, `eligibility=false`, app mapping 없음이어서 자동 비교 후보에서는 제외된다. parser의 구조 분류만 보면 자동 확정처럼 보이지만 최종 비교 정책까지 포함하면 안전 차단이다.
- 사이즈 0인 무신사 6개는 등록/비교를 진행하지 않아 잘못된 추천을 만들지 않았다.
- 룸슈즈와 일부 잘못된 sweatpants 분류는 bundle `eligibility=false`가 적용되어 비교가 차단된다.
- 확정 defect/risk set, 사용자 확인 대상, bundle ineligible 대상을 제외한 뒤 현재 공식 endpoint의 `아우터`, `바지`, `원피스/스커트`, `상의` 등 강한 쇼핑몰 root와 FitMatch 대분류가 정면 충돌하는 잔여 자동 분류는 무신사 0, 유니클로 0건이었다.
- 유니클로 상품명에 `AIRism`이 포함된 97개를 별도 전수 확인했다. 속옷 경로 54개만 속옷으로 분류됐고 나머지는 티셔츠·폴로·팬츠·원피스·레깅스·아우터 등 공식 경로에 따라 분리됐다. `AIRism` 문자열 하나만으로 전부 속옷 처리되는 회귀는 재현되지 않았다.
- 명시적 폴로셔츠 140개(무신사 122 / 유니클로 18)를 별도 확인했다. canonical resolver가 중간 저장값을 `shirt`로 만들지만 실제 비교 직전 `storedGarmentType`이 폴로의 inferred T-shirt family로 교정한다. Product와 UserFit 모두 같은 보호를 사용하며 폴로↔동일 길이 티셔츠 허용, 폴로↔우븐 셔츠 자동 차단 회귀 테스트도 존재한다. 내장 transform과 생성 스크립트의 `polo_shirt: shirt` 표기는 혼동을 일으키므로 정리 권장이지만 현재 실행 P0는 아니다.
- 사용자가 제보했던 `E482522 AIRism코튼크루넥T`는 현재 `tops/short_sleeve`, T-shirt family로 분류되고 공식 사이즈 8개가 확인됐다.
- 기존 성별 제보 상품 `E450540 메리노V넥가디건`의 현재 공식 metadata는 `genderName=unisex`, `genderCategory=UNISEX`, `topCategories=[men,women]`이며, 현재 5,026개 분류 출력은 `outerwear/cardigan`이다. parser source에도 이 조합을 `UNISEX`로 요구하는 회귀 테스트가 남아 있다.
- 기존 비교 제보 조합 `E487957 스마트와이드스트레이트팬츠`와 `E492538 스트레이트진(셀비지)`은 현재 각각 `bottoms/long_pants`의 pants/denim family이고 공식 사이즈 7개/12개가 확인됐다. matcher는 pants↔denim을 같은 하의 대분류의 직접 호환 조합으로 허용한다.

## 공식 endpoint 현재 상태

- 5,026개 모두 공식 상품 endpoint에 도달했다. rate limit 0, unavailable 0이다.
- 공식 실측 즉시 확인: 4,569개(90.91%)
  - 무신사 3,561 / 4,011
  - 유니클로 1,008 / 1,015
- 상품 정보는 확인되지만 직접 실측 응답이 비어 있음: 457개
  - 무신사 450개는 HTML·이미지 OCR fallback 또는 수동 입력 경로를 별도로 거친다. 이 수치를 곧바로 앱 parser 실패로 해석하면 안 된다.
  - 유니클로 7개는 브라 5, 영유아 레깅스 1, 진 1이다.
- 실제 iPhone에서 재파싱한 애매 상품 325개 중 직접 실측 응답이 비었던 상품은 7개였고, production parser가 3개를 다른 경로로 복구했다. 남은 4개는 등록 불가로 안전하게 중단됐다. 직접 실측이 있던 2개도 세트/오버올 구조 때문에 등록하지 않아 잘못된 단일 의류 추천을 만들지 않았다.
- P0 비교 영향 결함 128개 중 116개는 현재 공식 실측까지 즉시 내려온다. 나머지 12개도 상품 endpoint는 살아 있다. 따라서 P0는 오래된 fixture만의 문제가 아니라 현재 사용자에게 노출 가능한 결함이다.
- 무신사 저장 경로와 현재 공식 경로가 문자열상 다른 항목은 2,475개지만, 2,466개는 과거 corpus의 `Clothing`/`Sportswear` 영문 root와 현재 한글 root의 표기 차이다. 한글 경로에서 의미 있게 이동한 상품은 7개였고 모두 동일한 대분류 안의 세부분류 이동이었다. 2개는 현재 경로가 빈 응답이었다.

## 기존 A테스트 재해석

- 기존 5,000건은 당시 모두 PASS였으나 현재 확인된 의미 위험 상품이 포함된 520건(10.4%)은 출시 근거에서 제외해야 한다.
- 이 중 70건(자동 35 / 수동 35)은 최신 `9264814`의 `브라`·`브리프` 회귀만으로 기존 PASS 근거가 무효가 됐다.
- 위험 상품을 제거한 4,480건은 전부 PASS다.
  - 자동 비교 1,158
  - 수동 기준 옷 선택 1,158
  - 정상 차단 2,158
  - 실측 근거 부족 6
- 신규 라이브 700건도 원래 700/700 PASS였으나 의미 위험 상품 86건을 제외한 유효 614건이 PASS다.
  - 실제 고유 상품 323개(무신사 228 / 유니클로 95), 무신사→무신사·무신사→유니클로·유니클로→무신사·유니클로→유니클로 각 175건
  - 자동 비교 83
  - 수동 선택 133
  - 정상 차단 398
- 신규 700건 runner는 production parser가 아니라 저장된 분류를 사용하는 근사 정책 검사이므로 단독 출시 근거로 사용하지 않는다.

## 빌드 및 bundle

- Release arm64 generic iPhone: `BUILD SUCCEEDED`.
- Debug arm64 generic iPhone `build-for-testing`: 앱, Share Extension, unit test, UI test 타깃까지 `TEST BUILD SUCCEEDED`. Simulator와 실기기 데이터는 사용하지 않은 컴파일 검증이다.
- App과 Share Extension은 `MARKETING_VERSION=1.0`, `CURRENT_PROJECT_VERSION=4`, iOS 17 minimum, 동일 App Group `group.com.ljy4337.fitmatch`로 정렬돼 있다. 두 Info.plist·두 PrivacyInfo.xcprivacy·두 entitlement plist lint도 모두 통과했다.
- 추가 실제 iPhone P0 회귀 실행은 build/sign까지 완료됐지만 기기가 잠겨 test host launch 전에 중단했다. 이 실행은 통과 실적으로 계산하지 않았다.
- 내장 source mappings, comparison policies 및 bundle checksum은 검증 통과.
- 내장 정책 교차참조도 family 44 / garment policy 15 / compatibility 19 / measurement 22 / source alias 21에서 존재하지 않는 family·measurement 참조 0건이었다. sourceExternal/sourceTargetPath 중복 결과 충돌도 0건이다.
- 내장 measurement policy에는 Docs 원본보다 `foot_length`가 하나 더 있어 두 manifest hash가 다르다. 현재 내장 bundle은 자체 일관성이 있지만 향후 DB/원격 bundle 적용 전에 동기화해야 한다.

## 산출물

전체 machine-readable evidence 위치: `../FitMatchArchive/Docs/TestEvidence/ReleaseATest-20260815/`

- `FitMatchA5026-category-mappings-20260815.csv`: 상품 5,026개의 쇼핑몰 경로와 FitMatch 분류 전수 내역
- `FitMatchA5026-mall-to-fitmatch-mapping-20260815.csv`: 쇼핑몰 카테고리 경로 → FitMatch 분류 607개 조합
- `FitMatchA5026-category-summary-20260815.csv`: source/FitMatch 분류별 98개 집계
- `FitMatchA5026-confirmed-semantic-blockers-v7.json`: 1차 의미 결함 상품 230개와 원인 코드
- `FitMatchA5026-active-p0-comparison-defects.json`: 1차 bundle 감사에서 비교에 직접 영향을 주는 고유 상품 125개
- `FitMatchA5026-supplemental-p0-v8.json`: 추가 family 방향 감사에서 확인한 유니클로 히트텍 레깅스 P0 3개
- `FitMatchA5026-confirmed-family-routing-risks.json`: major/family 교차 위험 21개
- `FitMatchA5026-runtime-bundle-overlay.json`: 상품별 canonical bundle 적용 결과
- `FitMatchA5026-live-endpoint-probe-retried.json`: 공식 endpoint 전수 재조회 결과

## 출시 전 필수 조치

1. `브라`/`brief` 단어 경계와 provider major 우선순위를 수정한다.
2. 셔츠·블라우스·가디건 구조를 소매 길이보다 먼저 확정한다.
3. 다중 의류 세트와 옵션 의존 상품을 사용자 확인 또는 unsupported로 보낸다.
4. 스코츠와 상의 브라탑의 major/family 정책을 하나로 맞춘다.
5. 히트텍 혼합 경로는 상품명·측정 축으로 상체/하체를 분기하고, 위 233개 의미 fixture를 회귀 테스트로 고정한 뒤 5,026개 semantic oracle를 다시 통과시킨다.
6. 무신사 상품명에 URL·관리자 경로가 섞이면 `goodsNmEng` 또는 정제된 이름으로 fallback하도록 한다.
7. 수정 후 위험 상품이 제거된 상태에서 A테스트 비교 시나리오를 재생하고 실제 iPhone 핵심 사용자 여정 6건을 마지막으로 확인한다.
8. 기존 성능 진단 작업 트리를 별도로 검토·커밋하여 심사에 올릴 정확한 source revision을 고정한다. 이미 App Store Connect에 build 4를 올렸다면 수정본은 다음 build 번호로 만들어야 한다.
