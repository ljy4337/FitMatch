# FitMatch 데이터 지원 명세 및 보완 관리 기준

기준일: 2026-09-17 / branch: connectDB / HEAD: ae69b30ed37386f6361882d36bafbd972235ebd4 + 현재 미커밋 코드
DB: hnkplvyegonlhumlejst / 읽기 전용 사전 추출

## 1. 이 파일의 목적

“어떤 데이터를 받으면 어디까지 처리할 수 있고, 막히면 무엇을 보완해야 하는가?”를 관리한다.
**쇼핑몰별 지원 데이터 목록은 유지보수에 유용하다. 다만 입력 필드 이름뿐 아니라 값·단위·문맥·식별정보의 조합까지 관리해야 한다.**
예: ‘총장’이라는 이름이 같아도 상의의 등길이와 바지의 허리부터 밑단까지 길이는 다르다.

이 문서는 세 부분으로 구성된다.
- 본문: 일반 사용자가 읽을 수 있는 처리 조건과 조치 기준.
- 별도 목록: 현재 DB에 실제 등록된 카테고리와 실측 연결 규칙.
- 보완대장: 처리되지 않는 입력과 조치·검증 상태.

**전 세계 모든 상품을 지원한다는 명세가 아니다.** DB 등록 규칙을 현재 상태로 확정한 것이며, 새 상품·최신 API 전체를 성공 검증한 것은 아니다. 사전에 없는 raw 항목의 전체 목록은 새 관측 없이는 알 수 없다.

## 2. ‘지원’을 나누는 기준

| 단계 | 의미 | 확인 근거 | 다음 단계 성공 보장? |
|---|---|---|---|
| 원문 수신 | URL에서 공식 응답을 얻음 | HTTP + 실제 응답 형식 | 아니오 |
| 원문 해석 | 상품/옵션/사이즈/실측을 분리 | 실제 parser 결과 | 아니오 |
| source 등록 | 원본 실측의 의미를 사전에 정의 | source_measurements | 아니오 |
| alias 등록 | parser/raw code/label/분류와 source 연결 | source_measurement_aliases | 아니오 |
| canonical 연결 | FitMatch 공통 실측으로 변환 | mappings + canonical 정의 + resolver 실행 | 아니오 |
| 비교 정책 등록 | 정책에서 쓸 수 있는 실측 | comparison_metrics/policies | 아니오 |
| 실제 저장·비교 | 인증·소유권·선택·공통실측 등 모두 충족 | 실제 등록/read-back/begin/complete/결과 | 해당 사례에만 해당 |

관리 상태: `지원 확인` / `조건부 처리` / `사용자 보완` / `원문 보존만` / `정책상 제외` / `구현 결함` / `외부 장애` / `미검증`.
검사 결과는 별도로 `PASS / FAIL / BLOCKED / NOT RUN`을 기록한다. 미등록과 오류를 같은 상태로 기록하지 않는다.

## 3. 쇼핑몰별 입력 계약

| 데이터 | 무신사 | 유니클로 | 자라 |
|---|---|---|---|
| 링크 | products/{id}, musinsa.onelink.me 공유링크 | E######-suffix/price-group와 선택 query | -p스타일번호.html 및 v1 선택정보 |
| 상품 식별 | 실제 goods/product ID | core E번호와 suffix 증거를 구분 | 상세 product.id=internalProductID |
| 선택 옵션 | 실제 variant가 있으면 보존 | colorDisplayCode, pldDisplayCode | 선택 colors[].productId=catentryID |
| 사이즈 | 원문 label과 정확한 size identity | sizeDisplayCode와 표시 label 구분 | 선택 catentry의 size identity/label |
| 카테고리 | 공식 category path/code | 공식 breadcrumb/code/컬렉션 등 | 공식 section/familyId/subfamilyId |
| 제품 실측 | actual-size, 근거 있는 표/이미지 보완 경로 | 공식 size-chart | measureGuideInfo |
| 별도 취급 | 상품명으로 그룹 추정 금지 | 신체 권장치수, 재고 UNKNOWN | sizeGuideInfo는 제품 실측 대체 금지 |
| 특수 조건 | 단축링크의 실제 상품번호 확인 필요 | 색상표 부족 시 공식 generic000 비교; suffix 동일성 임의 가정 금지 | product와 catentry가 달라도 정상; 스타일번호를 parent로 대체 금지 |

구현 근거: FitMatch/Services/MusinsaURLResolver.swift, MusinsaParser.swift, MusinsaProductMetadataParser.swift, UniqloParser.swift, ZARAParser.swift, ProductURLParserService.swift. 상세 흐름은 루트 FitMatch Behavior Map.md.
ZARA 기능 활성 설정과 지원 지역/응답 계약도 실제 진입 경로에서 확인한다. COS는 현재 활성 지원 parser 대상이 아니다.

## 4. 실제 DB 관리 규모

아래는 **등록행 수**다. 고유 원문 항목 수나 성공 상품 수가 아니다. 동일 항목에 분류별 alias가 여러 개일 수 있다.

| 쇼핑몰 | source 정의 | alias 규칙 | 현재 조회 정책 카테고리행 |
|---|---:|---:|---:|
| 무신사 | 17 | 54 | 40 |
| 유니클로 | 23 | 142 | 342 |
| 자라 | 11 | 31 | 148 |
| 합계 | 51 | 227 | 530 |

추가 전체 사전 snapshot: source→canonical mapping48, canonical42, policy44, metric647행. 비활성·미검증 규칙도 포함한 전체 추출 수다.

- [카테고리 사전 목록](카테고리목록.md): 정확한 키·경로·A~G/제외·정책.
- [원본 실측 등록 목록](원본실측등록목록.md): alias가 없는 source도 포함.
- [실측 연결 목록](실측연결목록.md): raw code/label·parser·category/garment·단위·기준·변환·정책 등록 수.
- [원본 DB snapshot](db-snapshot-20260917.json): 활성/검증 상태, canonical 정의, metric 가중치와 정책 포함.

정적 연결 있음은 ‘조건이 맞는 사전 연결이 존재한다’는 뜻이다. 실제 resolver 우선순위/중복/정책 선택 결과는 실행 검증해야 한다. product override는 이 카테고리 목록과 별도이며, 실제 분류에 영향을 줄 수 있다.

## 5. 어떤 입력에서 막히는가

| 입력 상태 | 기대 처리 | 무엇을 보완할지 |
|---|---|---|
| 공식 API403/timeout | 실패 원인 구분, 입력 보존·재시도 | 외부 접근/통신 조사. 매핑 추가로 해결 못 함 |
| 상품/선택 색상 ID 누락·충돌 | 잘못된 상품 저장/비교 차단 | URL resolver/parser/DTO identity 수정 |
| 사이즈는 있으나 제품 실측 없음 | 사이즈 표시와 처리 가능 여부 분리 | 근거 있는 제품 실측 확보/명시적 보완 경로 |
| raw 실측 있음, source 없음 | 지원하지 못한 의미를 원문으로 보존할 수 있는지 확인 | 원문 근거로 source 정의 후보 |
| source 있음, 맞는 alias 없음 | canonical 연결 불가 가능 | 정확한 parser/raw/category에 alias 추가 검토 |
| alias 있음, canonical mapping 없음 | raw 존재와 비교 가능을 구분 | 기존 canonical 연결 또는 의미가 다르면 신규 정의 검토 |
| canonical 있음, 현재 정책에서 미사용 | 화면 표시 가능성과 점수 사용을 구분 | 정책 판단. 자동 metric 추가 금지 |
| 분류 미등록 | 사용자 그룹 선택 | 선택 경로 유지; 실제 빈도 높은 정확한 카테고리만 추가 검토 |
| 공통 승인 실측0개 | 비교 불가 이유 안내 | 의미가 맞는 공통 실측 보완 |
| 공통 승인 실측1개 이상 | 나머지 승인 조건 검증 후 제한된 근거로 비교 고려 | 신뢰도·누락항목 설명. 무조건 성공 아님 |
| cm 아닌 단위/0/결측/NaN | 유효 실측으로 계산하지 않음 | 원문 확인/검증된 단위변환. 임의0값 대체 금지 |
| 안감·속옷 부속·벨트·세트 혼합 | 본체 실측과 분리 | 구성품 identity/의미 근거 필요 |
| 원문4→parser4→DB4→화면2 | 단계간 손실 조사 | 앱 전송/필터/표시 수정 후보; DB 사전 추가 아님 |
| API 신규 정보와 저장 cache 불일치 | 관측시각/identity 확인 | stale 상태/동기화 경로 조사 |

## 6. 사용자 보고 상품으로 확인한 경계

[10상품 실제 검사 보고서](../QA/ReportedProductRegression-20260917.md)

- 자라8상품: 새 garment API 응답→현재 parser에서8개 사례 모두 사이즈 보존 PASS. 전체 등록/비교 성공 아님.
- 유니클로 E484080: color007 표 비어 있음, generic000 8사이즈 존재. Swift의 실제 fallback 실행은 별도 미검증.
- 무신사 ct27zw6f: 상품5328103 확인, 현재 환경 API403. DB에는 C/4size. live 수신 실패와 저장 사전 상태 구분.
- 자라 하이넥/폴로/청바지 3개: UNMAPPED. 사용자 그룹 선택 대상이지 자동 결함 아님.

## 7. 지속 관리 방법

1. 새 문제가 들어오면 URL/선택 옵션/관측시각/앱 빌드와 **실제 실패 단계**를 보완대장에 남긴다. 계정·토큰은 남기지 않는다.
2. 원문→parser→source→alias→canonical→정책→저장/비교를 순서대로 대조한다. 이름만 보고 연결하지 않는다.
3. 필요한 계층만 수정하고 원래 실패사례·인접 사례를 검사한다. DB 적용 여부와 앱 빌드 반영 여부를 따로 기록한다.

갱신 시점: parser/DTO/DB 사전/비교정책 변경 시, 새로운 raw code·측정기준·카테고리 관측 시.
사전 snapshot은 자동 갱신되지 않는다. 새 읽기 전용 export를 확보한 뒤 `python3 scripts/build-data-support-register.py`로 목록을 재생성한다. 이 스크립트는 현재 snapshot 렌더링만 하며 DB 접속/변경하지 않는다.
현재 정책 버전이 바뀌면 category 추출 조건도 실제 조회함수 기준으로 수정한다. 과거 수치와 새 수치를 비교할 때 동일 정책·활성조건을 사용한다.

## 8. 유지해야 할 원칙

‘미등록 데이터 제로’가 목표가 아니다. **확실히 지원하는 범위와, 안전하게 보완/거절하는 범위를 모두 명확히 하는 것**이 목표다.
새 canonical 등록, 비교 정책 참여, 실제 추천 품질은 서로 다른 결정이다. 사전 등록을 곧바로 출시 검증 완료로 표시하지 않는다.
