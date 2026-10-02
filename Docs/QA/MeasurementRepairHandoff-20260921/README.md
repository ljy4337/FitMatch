# 사용자 DB 실행 순서 / Terra 전달
대상 프로젝트: **FitMatch — hnkplvyegonlhumlejst**.
이 폴더의 SQL은 작성·로컬검증 완료 상태다. 연결 Supabase에는 적용하지 않았다.

## SQL Editor에서 실행
해당 프로젝트를 선택하고 아래 파일 내용을 순서대로 전부 붙여넣어 실행한다.
1. 00-Preflight.sql: 현재 함수/정확한 alias 상태 검사. PASS면 다음 진행.
2. 01-Apply.sql: transaction 하나로 alias10개 및 함수3개 변경. 실패하면 전체 rollback. 성공은 COMMIT 완료 기준.
3. 02-Verify.sql: 설치된 정의/alias 검사 + AIRism 각 size 결과 + exact/alias resolver 대조.
   기대: AIRism 각 사이즈 canonical 실측4개, 앞기장→front_length, 등중심 소매→sleeve_center_back_length.
   정책 점수 항목4개가 된다는 뜻이 아님.
4. 문제 시에만 03-Rollback.sql: 이후 다른 변경이 없을 때 이전 함수/alias 동작 복원.
   예전 오류도 되살아난다. updated_at은 trigger가 현재 시각으로 갱신하며 과거 시각으로 되돌리지 않는다.

Preflight/Apply/Verify에서 오류가 나면 조건을 삭제해 강제로 진행하지 말고 오류 메시지를 전달한다.
수동 SQL Editor 실행은 migration ledger를 기록하지 않는다. 나중에 배포 절차에서 기존
supabase/migrations/20260921090000_measurement_semantic_context_separation.sql과 이 적용 결과를 대조해야 한다.
이전 uniqlo_front_length_airism_Apply.sql을 추가로 중복 실행하지 않는다.

## 실제 변경 범위
- UNIQLO 잘못된 alias10개: 앞기장3, 주름포함너비5, 페티코트2.
- resolve_measurement: 검증된 원본 표준화와 is_comparable 점수 자격의 혼동 보완.
- canonical_measurements_for_size_with_context: 제품 원래 문맥에서 해석된 의미를 우선 보존.
  native UNMAPPED인 경우 기존 검증된 group context recovery는 유지한다.
  따라서 모든 상황에서 그룹 문맥을 완전히 제거하는 대규모 재설계가 아니다.
- product_measurement_readiness: canonical 개수와 정책 사용 개수 분리.
- 카테고리/비교 weight/원본 raw/옷장/History 데이터 변경 없음.
- 적용 전 함수 fingerprint와 alias 세부값이 예상 상태와 다르면 중단.
- 새 연결 원칙을 임의로 만들지 않고 기존 준비 migration을 재사용한다.

## 이번 SQL에서 보류한 항목
- ZARA 미등록7개 category: exact ID 누락은 확정, 그룹 지정은 공식 분류/상품 구조 확인 후 별도.
- MUSINSA 아우터 밑단: 실제 미해석 확인, 공식 측정방법 확인 후 alias 추가.
- MUSINSA 상의 허리/복부: canonical 의미/기준 검증 필요. 하의 허리로 합치지 않음.
- UNIQLO 벨트/슬릿: raw-only 보존 우선, 새 canonical/weight를 만들지 않음.
- 경로 없는17상품: 사전 추가보다 원문 재수집/보존 경로 확인.
이번 파일이 앞선 감사의 모든 보완대상을 해결하는 것은 아니다.

## 검증 내역
PASS:
- 실제 배포 함수/alias 읽기 전용 snapshot 확보.
- PostgreSQL17 격리 fixture에서 실제 준비 migration 회귀:
  alias, exact/alias, A/F 의미 불변, group-only recovery, readiness 개수 구분.
- 전달용 Preflight→Apply→핵심 Verify→재Apply→핵심 Verify→Rollback→Preflight 실행.
- diff/protected scroll 검사.
NOT RUN:
- 연결 DB 적용 및 적용 후 AIRism 실제32사이즈 read-back.
- 전달용 Verify의 실상품 조회 부분(격리 fixture에는 실제 상품/전체 의존성 없음).
- 전체69상품/211행 full replay, 권한/RLS·실제 앱 등록→비교 E2E.
로컬 fixture 회귀 PASS는 연결 DB나 앱 전체 성공을 뜻하지 않는다.
첫 로컬 준비는 libpq initdb 경로 및 sandbox 공유메모리 오류가 있었고 PostgreSQL17 실행파일/허용된 로컬 실행으로 해결했다.

## Terra
Terra-Prompt.md의 전체 내용을 전달한다.
앱 파일이 이미 다른 작업에서 수정 중이므로 현재 diff를 먼저 읽고 완료된 변경을 중복 구현하지 않게 했다.
DB 저장 contract 추가가 필요하면 Terra가 migration을 작성·로컬 검증하고 사용자가 별도 적용한다.
이번 SQL만으로 신규 raw snapshot 저장 계약을 추가한 것은 아니다.

