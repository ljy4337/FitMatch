# FitMatch_PROD 이관 사전 검토 — 2026-09-30

## 확인 범위
READ ONLY 프로젝트 목록, schema/table/function/extension/policy/migration 메타데이터, Edge 목록 확인. 실제 dump/restore, DB write, 배포, 앱 연결 변경은 수행하지 않았다. 현재 HEAD 3b71f15a67e64b62c762fdfb9340ff7139a9e609.

## 실제 상태
- 원본 FitMatch: hnkplvyegonlhumlejst / 서울 / PostgreSQL 17.6.1.147.
- 대상 FitMatch_PROD: aqhrupgjpmrtnystottx / 서울 / PostgreSQL 17.6.1.166. 둘 다 ACTIVE_HEALTHY.
- 원본 fitmatch_catalog 9 tables / 2 functions, fitmatch_vnext 28 / 100, public 1 / 26. 함수 수는 schema 내 전체 pg_proc 항목으로 application-only 판정 아님.
- 대상 FitMatch schema 없음, public tables 0 / functions 1. FitMatch/public RLS policies 0. migration ledger 없음.
- 원본 FitMatch/public policies 26, migration ledger 136건/latest 20260929055658.
- 원본 Edge: product-observation v5, delete-account v1. 대상 Edge 없음.
- 양쪽 extension 이름/버전 동일: plpgsql1.0, pg_stat_statements1.11, uuid-ossp1.1, pgcrypto1.3, supabase_vault0.3.1.
- 원본 auth.users의 on_auth_user_created 사용자 trigger 존재. 관리 schema 전체 덮어쓰기가 아니라 해당 customization 별도 이관 필요.
- 앱 FitMatch/Info.plist는 아직 hnkplvyegonlhumlejst endpoint 사용.

## 권장 범위
1. 현재 배포 DB의 application schema/table/function/view/type/index/constraint/trigger/RLS/grant/default privileges를 의존성 포함한 기준 dump로 고정. public은 플랫폼 extension 항목을 구분. 연결 대상의 관리 schema는 그대로 유지.
2. source/category/measurement/alias/mapping/comparison metric/policy/group/release 등의 기준 데이터 선별 이관. 최신 검증 상태와 FK closure 확인. 제품별 override, catalog products, 관측 category 자료는 정책 근거인지 테스트 자료인지 별도 분류하며 일괄 제외/복사하지 않는다.
3. auth users/sessions, profiles, Closet, comparison/history, 사용자 override/feedback, ingestion receipts 및 테스트 product/variant/size/measurement/availability는 기본 이관 제외 권고. 실제 사용자 데이터 이전은 별도 결정.
4. product-observation/delete-account 배포 코드와 Git 차이 확인 후 이관. 환경 secrets 값은 보고서에 출력하지 않고 새 프로젝트 기준 설정. Apple Auth/provider/redirect/Data API schemas/권한/storage/realtime 설정은 dump와 별도 확인.
5. 원본 remote migration version/name과 Git 대응 검토 후 새 baseline/ledger 전략 확정. 과거 migration을 dump 위에 재실행하거나 ledger만 복사하여 검증 완료로 처리하지 않음.

## 실행 순서
- 원본 기준 dump + 기준 데이터 allowlist + 대상 사전 snapshot + 검증 목록 준비.
- 격리 환경 복원 후 구조/hash/정책 데이터/FK/권한/실측 및 그룹 읽기 검증.
- 범위 확정 및 Production 쓰기 승인 후 대상 적용, read-only postflight. Apple 로그인/등록/비교/기록/삭제 기능 smoke는 명시적 테스트데이터 생성 승인 범위로 실행.
- 검증 후 앱 환경 전환. 그 전 기존 endpoint 유지.

## 검증 경계
PASS: 양 프로젝트 존재/상태, 위 메타데이터 조회.
NOT RUN: 실제 dump/restore, 전체 함수 의존성 및 hardcoded project URL 검사, 기준 데이터 row별 분류, 원격/Git 전체 parity, Auth 설정, 인증 E2E, 복원 검증.
Supabase 공식 지침: https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore

## 2차 반증 검토 — 2026-09-30

판정: 1차안은 방향은 맞지만 실행 승인 가능한 완성된 이관 계획은 아니다. 아래 항목으로 보완하며 실제 적용은 계속 보류한다.

### 추가 확인한 사실
- live source_measurements 51 / aliases 227 / mappings 48 / category-group rows 1023. 전체 행 수이며 active/verified 사용 수가 아님.
- product_comparison_group 실제 정의는 retailer-comparison-groups-v3-seven-20260911을 직접 참조한다. 이 policy status는 validated이고, 별도 musinsa draft는 loading이다. status=active 또는 최신 날짜만으로 seed 선별하면 현재 정책이 누락될 수 있다. 함수가 참조하는 policy identity와 현재 상태/제외 규칙을 그대로 보존하며 초안을 승격하지 않는다.
- product_comparison_group_overrides 2건: UNIQLO E461767 → EXCLUDED/X(room shoes), E488014 → B(cardigan). 상품 cache와 달리 현재 product_comparison_group이 먼저 조회하는 정책 데이터다. 이관 포함 후보로 확정하며 기존 정책 버전/외부 상품키를 유지한다. 테이블은 product UUID FK가 아닌 source_code/external_product_id를 사용하므로 일반 product cache 이관과 분리 가능.
- FK 목록 확인: catalog classification history는 auth.users(reviewed_by)에 의존한다. catalog 전체 data dump는 사용자 제외 정책과 충돌 가능. Closet raw snapshot도 receipt/product/variant/size FK를 가지므로 옷장 일부만 복사하면 안 된다. 사용자 데이터 이전 여부는 여전히 별도 결정이다.
- 현재 원격 migration ledger 136건, 로컬 SQL 파일 123개. 원격 version 32개가 로컬 파일 prefix와 일치하지 않는다. 다른 이름/시각으로 같은 내용이 존재할 수 있어 32개 SQL 누락으로 해석하면 안 된다. 실제 baseline hash와 원격-version/로컬파일 대응 manifest 필요. 과거 ledger를 새 seed-only baseline에 무조건 복제하지 않는다.
- 배포 product-observation/delete-account index.ts는 현재 로컬 파일과 각각 byte-exact 일치. 두 함수 verify_jwt=true, auth.getUser 검증 및 프로젝트 자체 env 사용. 새 프로젝트 JWT/legacy key 설정까지 같은지 확인하지 않았으므로 인증 호환은 NOT RUN.
- source Storage buckets/objects 0/0, supabase_realtime publication table 0. 현 상태에서 Storage 파일/Realtime 테이블 복사는 불필요. 변경시 재확인.
- public/fitmatch_* 함수 본문에서 원본 project ref literal 발견 0. 전체 URL/동적 SQL/role config/외부 dependency 검증 완료라는 뜻은 아님.

### 1차안의 수정 사항과 실행 gate
1. '기준 데이터 선별'을 현재 함수가 실제 참조하는 dependency closure 기준으로 구체화한다. 검증된 긍정 매핑뿐 아니라 제외/충돌 방지 규칙과 동일 policy version을 보존한다. 각 테이블 include/exclude/조건/근거 manifest 없이는 dump 실행안 확정 금지.
2. 사용자/옷장/기록 제외는 권고이며 승인된 결정이 아니다. 제외 시 운영 로그인에서 기존 데이터가 자동으로 따라오지 않는다. 재로그인 및 개발→운영 업데이트의 세션/로컬 cache 격리 확인을 전환 gate에 추가한다. 기존 앱 cache 오염 결함을 재현한 것은 아님.
3. 앱 endpoint와 publishable key를 새 프로젝트 쌍으로 전환한다. 개발 service-role/JWT secret/session은 복사하지 않는다. Apple provider/client ID 설정, Edge JWT gate와 실제 사용자 JWT 성공 및 미인증 거절을 확인한다. 공식 signing-keys 문서상 verify JWT 호환 주의가 있으나 대상 프로젝트 결함으로 단정하지 않으며 임의 인증완화 금지.
4. DB superuser SELECT 성공으로 앱 권한 정상 판정 금지. anon/authenticated/service-role 별 RPC EXECUTE, SECURITY DEFINER owner/search_path, RLS/GRANT/default privileges, Data API exposed schemas 검증. 내부 fitmatch schema를 임의로 API에 추가 노출하지 않는다.
5. schema/seed를 서로 다른 시점에 추출하지 않도록 policy/schema 변경 동결 또는 일관된 snapshot을 사용한다. sequence/identity 값, extension schema, function overload/ownership도 포함. 관리 role/extension 소유권을 무작정 덮어쓰지 않는다.
6. dump hash/seed counts + 격리 복원 성공 + FK/constraint/policy parity + 선택한 인증 smoke를 gate로 둔다. SQL 복원은 fail-fast/가능한 transaction 적용, Edge/Auth 설정은 별도 단계로 취급한다. 실패시 앱 전환 금지. 실제 운영 사용 이후 DB endpoint만 되돌리는 것을 무손실 rollback으로 부르지 않는다.
7. 새로운 baseline과 후속 migration 사용 규칙을 확정하고 Git에서 새 운영 상태를 재현할 수 있어야 한다. 옛 migration 재실행/원격 이력 복사만으로 재현성 통과 선언 금지.

### 참고
- https://supabase.com/docs/guides/auth/signing-keys
- https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore

READ ONLY 검사만 수행. 앱 코드/DB/Edge/키/정책 변경 없음. 실제 복원·인증 smoke·사용자 데이터 이동 NOT RUN.

## 최종 비판 검토 — 2026-09-30

### 앞선 안을 명확히 정정
- 이 작업은 full clone이 아니라 출시용 구조 + 승인된 기준 데이터로 운영 DB를 만드는 selective bootstrap이다. 사용자 데이터 제외를 확정하기 전 full data dump/restore 명령을 실행하지 않는다. 원본 보관용 전체 백업과 운영 투입용 seed는 서로 다른 산출물이며 접근권한/보관위치를 분리한다.
- 새 baseline을 택하면 과거 migration136건 재실행이나 모든 과거 SQL의 내용 대응 완료가 필수 전제는 아니다. 원격 ledger는 감사용 보존하고 검증된 baseline에 새 이력을 부여하며, 향후 배포가 과거 SQL을 다시 실행하지 않게 경로/이력 전략을 검증한다. 기존 migration 전체 replay 방식을 택할 때만 과거 이력 정합성 해결이 직접 gate가 된다. 이전32 version불일치를 무조건적인 출시 blocker로 확대하지 않는다.
- '검증 후 앱 연결 변경'은 공개 출시 앱 전환을 뜻한다. 그 전에 별도의 검증 빌드를 운영 endpoint+key에 연결하여 승인된 테스트 계정으로 인증된 핵심 flow를 확인해야 한다. 관리자 SQL 읽기나 격리 mock만으로 운영 연결 정상 판정 금지.

### 추가 READ ONLY 증거
- 대상 app tables0/auth.users0/auth.users custom trigger0. 대상에 계정까지 없음을 확인했지만 적용 직전 재조회한다.
- 원본 auth trigger on_auth_user_created → public.handle_new_user → profiles INSERT. profiles 테이블/함수 준비 후 trigger를 생성하고 Auth/provider 설정 및 첫 로그인 검증을 수행한다. 관리 auth schema 전체 복사는 필요하지 않다.
- 원본 current_product_classifications view 1개는 catalog.products LEFT JOIN product_classification_history(is_current)를 읽는다. exact_product_authority_recovery_options와 classification_recovery_options_v6_core가 이 view를 참조한다. 따라서 catalog 상품/분류이력을 일반 cache로 무조건 제외할 수 없다. 현재 UI에서의 최종 도달 여부와 유지할 복구 계약에 필요한 row 범위는 미확정이며 전체앱 실패로 판정하지 않는다. reviewed_by auth FK와 충돌하는 row는 임의 사용자 복사/UUID 변경/NULL 치환하지 않고 별도 승인된 seed 전략이 필요하다.
- 원본 sequence size_availability_observations_id_seq 존재. table/view/function 외 sequence와 default도 구조에 포함하고, 데이터 포함 여부에 맞는 sequence 상태를 검증한다.

### 확정 진행 순서와 종료 조건
1. 사용자 데이터 이전 여부 확정 + 테이블별 seed 명세(보존/제외/행 조건/의존성/정책version) 완성. SQL 구조 dump는 이 명세와 별개로 준비할 수 있다.
2. 현재 배포 구조와 seed를 일관된 기준으로 export, checksum과 release manifest 보관. 플랫폼 소유 extension/role을 복제하지 않고 app grant/owner는 기능상 동등함을 검증. 익명/인증/다른 사용자 접근 거절 확인까지 포함.
3. 격리 복원 검증 후 승인된 운영 적용. 참조 상품별 그룹/실측/후보/점수 의미가 기존과 동일한지 비교하며, 구조 text hash 차이는 owner/플랫폼차이를 구분한다. row count만 같다고 동일 판정 금지.
4. 운영 전용 검증 빌드 로그인→등록→비교→History 재조회 검증 후 공개 빌드 전환. 기존 설치 업그레이드와 새 설치를 구분. 테스트계정 삭제/데이터 cleanup은 승인 범위에서만 수행.
5. 공개 전 실패는 미전환 유지. 공개 후 새 사용자 write가 생기면 단순 endpoint 되돌리기 금지; 두 DB 데이터 분기/복구 계획에 따라 판단.

최종 판단: 방향 승인 가능, 운영 적용 준비 완료는 아님. 아직 없는 산출물은 seed명세/일관된export/복원PASS/운영인증PASS이며 같은 문서를 반복 검토하는 것으로 대체할 수 없다. 새로 확인한 것은 이관계획의 보완사항이지 앱 production 버그 확정이 아니다. DBwrite/코드변경/배포 없음.

## 후속 개발 DB 감사에 따른 seed 범위 보정

Docs/QA/DevelopmentDBCleanupAudit-20260930/Report.md 참조. active UNIQLO auto-promoted mapping1건의 검증함수가 product/receipt 관측근거를 조회한다. 따라서 제품·receipt를 기본적으로 모두 제외한다는 앞선 권고는 일괄 실행할 수 없다. 필요한 정책 근거와 사용자 provenance를 구분한 manifest가 먼저 필요하다. 개발DB정리함수후보2개는격리검증전삭제금지,조사2테이블은관리용도라개발보존권고. 실제 삭제/복원은 수행하지 않음.
