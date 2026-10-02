# 실측 사전 보강 — 2026-09-16

대상: 사용자 개발 DB `hnkplvyegonlhumlejst`. 사용자 요청으로 실제 적용 완료.

| 쇼핑몰 | 원본 항목 | 적용 문맥 | 연결 canonical | 추가 계층 |
|---|---|---|---|---|
| ZARA | zone-name-sleeve-length | tops / outerwear | sleeve_length | source 1 + mapping 1 + alias 2 |
| ZARA | zone-name-hem-width | dresses | hem_width | source 1 + mapping 1 + alias 1 |
| ZARA | zone-name-chest | outerwear | chest_width | alias 1; 기존 source/mapping 재사용 |

합계: 항목 3개, 문맥 연결 4개, DB 신규 8행. 기존 행 변경 0.

## 근거

- 원본 마스터 `08_자라_상세` 행7: 어깨 소매 심라인→소매 하단, 337 cm셀. `05_조사상품_목록` 행196: 대표 티셔츠.
- 같은 시트 행17: 하단 좌우 직선 폭, 12 cm셀. `05` 행400: 콘트라스트 스티치 스트라이프 원피스, style01608613 / commercial545465654. KID를 별도 의류 category로 해석하지 않음.
- 현재 ZARAParser.swift의 verifiedMapping은 소매 어깨 기준과 아우터 가슴단면을 지원. 현재 DB에도 미매핑 소매 cm 양수값 4행 존재.
- 위 원본 마스터 방법 증거와 현재 구현을 사용했다. 새 공식 JS 요청 성공을 주장하지 않음.

## 검증

- PASS: PostgreSQL17 격리 fixture(실제 사전 데이터/실제 resolver, 단순화 테이블) 적용 및 재실행.
- PASS: 로컬/실제 DB 각각 9개 resolver 검사. 올바른 4개 문맥은 RESOLVED; 잘못된 category·parser·unknown raw 5건은 UNMAPPED 유지.
- PASS: 사전 전체 전후 비교. source49→51, alias221→225, mapping46→48. 기존 source49/alias221/mapping46행 완전 동일. canonical42·metric647·policy44행 모두 동일.
- PASS: git diff --check 및 protected-scroll 확인.
- NOT RUN: 앱 로그인 상태 등록→비교 / 실기기 실행. 사용자 데이터 변경, schema/function 변경, migration ledger 변경, commit/push 없음.

## 남은 항목

- UNIQLO front-rise: 대표 E469682는 공식 JP 자료에서 보정 속옷으로 확인됨. 앞선 bottoms 제안은 적용하지 않음. KR 실제 측정 시작점/category 확인 후 결정.
- 무신사 상의 허리·다른 문맥 총장/밑단: 공식 방법 확인 전 일괄 연결하지 않음.
- inner·lining·petticoat·끈 포함 길이·단위없는 항목을 본체 실측으로 합치지 않음.
- 등 중심/래글런 소매 등 comparison metric 확대는 이번 사전 보강과 별도. 정책/점수 계산 변경 없음.

DB 변경은 신규 요청의 서버 해석에 적용된다. 기존 완료 비교 결과를 다시 쓰지 않았으며, 앱에서 새로 불러와 재비교해야 최신 해석을 확인할 수 있다.
