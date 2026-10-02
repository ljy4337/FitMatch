# UNIQLO 경로 / ZARA 스커트 최소 수정 — 적용 대기

## 우선순위와 범위
1. UNIQLO 두 exact category key(95381/95388)의 class 이름 변경 호환. 기존 경로·override·정책·ZARA legacy 분기를 유지. 새 한국어 전체 경로/성별 제외 경로 4개만 추가 허용. ID 우선 조회 구조 개편 아님.
2. ZARA current parser / skirts의 zone-name-waist, zone-name-hips alias 2개. 기존 source와 FLAT_WIDTH canonical, scale1/offset0 재사용. 근거: 엑셀08행10/11의 측정방법 및 현재 source/mapping. 실제 스커트 API는 앞선 검토에서403; 상품 수치/E2E 성공을 주장하지 않음.
3. F/G, 원피스 소매, 스커트 길이, 정책 확대는 제외.

## 적용 상태
Target hnkplvyegonlhumlejst: 최신 인수인계에서 Production으로 식별.
사용자가 직접 수정을 요청했으나 apply_migration 자동 승인 검토가 Production 명시승인 부족으로 거절. 실제 DB 함수/alias/migration은 변경되지 않음. 다른 수단으로 우회하지 않음.
SQL은 supabase/sql/uniqlo_path_zara_skirt_20260916_Apply.sql. 정확한 기존 함수 정의 및 사전 의미가 달라지면 중단하는 guard 포함. 최종 승인 후 atomic migration 적용 및 read-only Verify가 필요.

## 검증
PASS: 로컬 PostgreSQL17 격리DB fitmatch_narrow_checked에 현재 카테고리사전과 실제 product_comparison_group 함수, 실측사전/resolver 복제. 단순화된 테이블 fixture 사용; 운영 사용자 데이터 쓰기 없음.
PASS:1065개 group 함수 호출 전후검사. 기존 전체경로/성별제외경로 및 음성대조 유지; 의도한 새경로4개만 A로 변경.
PASS:13 raw ×7category=91 resolver 조합. skirts 허리/엉덩이2개만 변경;89개 동일. 상의·아우터·원피스와 F/G 불변.
PASS:같은 Apply 재실행, 중복 추가 없음.
로컬 fixture 초기 함수구분자 오류는 보정 후 재실행 성공. 실패한 로컬 초기 실행을 PASS로 집계하지 않음.
BLOCKED: Production 적용 및 적용후 조회(자동 승인 검토).
NOT RUN: 실제 Swift/build/UI, 정상사용자 등록→후보→begin→complete→History 전체여정.

## 산출물 / 재개
Apply, Verify SQL. 로컬 재현 입력 /tmp/fitmatch-narrow-repair-data.json, fixture /tmp/fitmatch-narrow-fixture.sql, assertions /tmp/fitmatch-narrow-assert.sql.
Swift 기존 미커밋 파서보정은 수정하지 않음. 원격 a68c849에만 있는 로컬 파서 gate 등은 이번 SQL만으로 제거되지 않으며 최신 앱 빌드 여부를 별도 확인해야 함.
commit/push 없음.
