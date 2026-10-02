# ZARA 사전 보강 영향 / 실제 링크 디버깅

## 결론

확인 범위에서 신규 회귀는 발견하지 못했다. 하지만 신규 실제 API 응답→앱 등록→비교 성공은 검증하지 못했으므로 무조건 오류가 없다는 보장은 불가하다. 이번 작업은 Supabase 읽기 전용 및 로컬 격리 검사만 수행했으며 앱/DB 동작을 수정하지 않았다.

## 엑셀에서 선정한 실제 링크

| 시트05 행 | 상품 | 점검 목적 | 실제 요청 결과 |
|---|---|---|---|
|196|[릴렉스핏 배색 티셔츠](https://www.zara.com/kr/ko/릴렉스핏-배색-티셔츠-p00722370.html)|신규 소매 + 기존 가슴 유지|페이지/상세ajax/실측 API 모두403|
|400|[콘트라스트 스티치 스트라이프 원피스](https://www.zara.com/kr/ko/콘트라스트-스티치-스트라이프-원피스-p01608613.html)|신규 밑단, KID audience와 dresses category 구분|페이지/상세ajax/실측 API 모두403|
|201|[스트라이프 와이드 팬츠](https://www.zara.com/kr/ko/스트라이프-와이드-팬츠-p04387223.html)|기존 하의 매핑이 변하지 않는 음성 대조|페이지/상세ajax/실측 API 모두403|

총9개 HTTP 요청을 실제 수행했다. HTTP403 응답을 정상 상품 JSON으로 취급하지 않았다. curl 전송종료코드0은 상품 불러오기 성공이 아니다. 공식 차단을 우회하지 않았다. 아우터는 엑셀에 이름/페이지가 충분히 식별된 별도 표본을 이번에 확보하지 못해 실제 링크 성공 테스트는 미실행이다.

## 보강 전후 회귀 검사

연결 DB에서 현재 실측1917행(50상품)을 읽어, 기존 실제 사전 snapshot과 deployed resolver로 구성한 로컬 PostgreSQL17 fixture에서 보강 전후를 비교했다. 7개 category 문맥을 의도적으로 교차해13419조합을 검사했다. 이는13419개의 실사용/API/E2E 성공 건수가 아니다.

- PASS:13407조합 완전 동일. UNIQLO9639/MUSINSA2310조합 전부 동일.
- PASS:의도한 ZARA12조합만 UNMAPPED→RESOLVED. 저장된 실제 소매4행×tops/outerwear와 가슴4행×outerwear. 다른 raw/category 영향0.
- PASS:동일 size/category/canonical에 서로 다른 값이 새로 합쳐지는 충돌0.
- PASS:현재 연결 DB resolver9개 검사 전부 성공(허용4 + 잘못된category/parser/raw5).
- PASS:로컬에서 소매 source basis를 의도적으로 raglan으로 오염시킨 거래는 보강 SQL이 Conflicting source로 중단. 거래 rollback 후 shoulder-seam basis 그대로 확인. 실제 DB 오염/변경 아님.
- 원피스 밑단은 현재 저장된 실제 관측값이 없어 above actual-row 회귀에는 포함되지 않았다. synthetic17cm resolver 검사만 PASS, 새 실상품 응답 검증은 BLOCKED.
- 실제 저장 소매의 ZARA549678665는 현재 REVIEW_REQUIRED. tops/outerwear 교차 검사는 사용자 group 선택을 대신한 인증/권한 테스트가 아니며 미매핑 상품을 자동 확정하지 않았다.

## 오류가 생길 수 있는 지점

| 지점 | 확인/판정 |
|---|---|
|Swift가 새 canonical을 몰라 결과 처리 실패|이번 재사용3코드 sleeve_length/hem_width/chest_width는 MeasurementComparisonEngine.swift:336 이후 기존 adapter 지원. source 확인; 앱 전체 실행은 NOT RUN|
|기존 alias를 덮거나 다른 문맥으로 번짐|추가만 수행;13419조합 비교에서 지정문맥 외 변화0|
|둘레와 단면/소매 시작점 혼합|scale1/offset0 및 distinct canonical 유지. 중심등/래글런 소매를 sleeve_length로 변환하지 않음|
|같은 실측코드의 중복/서로 다른 값|저장된 실제 데이터 전후 새충돌0; 미래상품의 모순 원문까지 보장하지 않음|
|0·음수·단위없는값·body size가 들어옴|ZARAParser.swift:1009–1018은 measureGuideInfo만 소비하고 positive cm를 요구. 소스 검사; 이번 새 API 응답은403이라 parser 통과 미검증|
|옷장 저장 payload와 새 서버 snapshot 불일치|최신 FitMatchSupabaseProductResolver.swift:2576은 linked request에 useServerMeasurements=true 사용. 이전 설치본까지 같다는 보장은 불가|
|추천점수 변화|양쪽 옷에 새로 인정된 동일 실측이 있으면 기존 policy가 그 항목을 사용해 결과가 바뀔 수 있음. 정책 row 불변이 점수 불변을 뜻하지 않음|
|이미 열어둔 응답/과거 비교결과|기존 완료결과는 snapshot. 새로 불러와 재비교해야 최신 해석 확인 가능. 열린 화면 전환/재시도 E2E는 NOT RUN|
|새 live API 실패|선정3상품 모두 HTTP403. 이 요청들은 DB 매핑까지 도달하지 않았으므로 이번 매핑 때문이라는 근거 없음|

## 미검증

새 공식 API 정상응답, 아우터 실제 링크 성공, 인증된 옷장저장→begin→complete, 실기기 UI/구버전 앱. 시뮬레이터·DB 변경·commit/push 없음. 최종 diff/protected-scroll 검사는 별도 완료 기록 참조.

## 증거

/Users/jinyoung/.codex/visualizations/2026/09/15/01a0a364-09f9-7b50-b02d-393c729d457f/zara-mapping-regression-20260916

`live-fetch.json`과9개 body 파일, actual-raw.json, before/after-matrix.json, matrix-summary.json, live-resolver-postflight.json, conflict-guard.log 보존. API403 body는 성공 데이터가 아니다.
