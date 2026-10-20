# BF1012-08 / BF1012-09 — 사이즈 판단 변경 통합

브랜치: `bugfix1012` · 작업일: 2026-10-20 (Asia/Seoul)

## BF1012-08 — 기존 알고리즘 변경과 bugfix 통합

### 계획과 범위

- 사용자 승인: `89e6014`를 기존 bugfix에 통합하고 현재 로컬을 bugfix로 설정한 뒤 QA 통합을 진행한다. main 승격·배포는 포함하지 않는다.
- fetch 후 main/origin/main=`2d01ea4`, bugfix/origin/bugfix=`0a58019`, QA/origin/QA=`a1f09df` 확인.
- 기존 `bugfix1012`를 재생성하지 않고 사용한다. 기존 크기 복구·공유 취소·검색·옷장 동기화·버튼 레이아웃 변경을 보존한다.
- `89e6014`의 조건부 점수 표시를 그대로 통합한다. 유사도 완전 제거는 이번 통합에서 구현하지 않았다.

### 실제 변경

- 기존 40파일 알고리즘 변경을 정상 merge로 통합했다. `Docs/CodexSessionHandoff.md` 충돌은 공통 원본 위에 양쪽 이력을 모두 유지해 해결했다.
- 병합 전 Handoff의 미커밋 81행은 `scratch/branch-integration-20261020/`에 원문·prefix·patch로 백업한다. 통합 커밋에 섞지 않고 커밋 이후 현재 작업 폴더에 복원한다.
- `supabase/sql/tests/bugfix1012_user_size_recovery.mjs`: 선택 인자 `--with-size-decision-v3`를 추가한다. 기존 복구 흐름에 v3 SQL을 연결하고, 위조 점수·순위를 거절한 뒤 exact 복구 identity로 완료·멱등 재시도·History·소유권 격리를 검증한다. 기본 실행의 기존 서버 계약 검사는 유지한다.

### 검증 결과

- PASS: 현재 개발 `complete_comparison` 정의를 읽기 전용으로 확보해 로컬 PGlite에서 v3 SQL 31시나리오 실행. 이후 미적용 오류 재현을 추가한 최종 실행은 32개 PASS.
- PASS: 기존 baseline에 v3 SQL 31시나리오 실행. 최종 32개 PASS. 이후 미적용 오류 재현을 추가한 최종 실행은 32개 PASS.
- PASS: 기존 사용자 복구 SQL 회귀, 그리고 v3와 복구 SQL을 함께 사용한 회귀 실행. 격리 DB와 synthetic auth/catalog/hash 의존성을 사용했다. 원격 정상 로그인/RLS/API E2E를 증명하지 않는다.
- 앱·QA 최종 소스 검증 결과와 커밋은 동명 JSON 증거 및 인수인계에 기록한다. 과거 테스트 결과를 현재 통합의 PASS로 재사용하지 않는다.

## BF1012-09 — 개발 DB 적용 필요 여부

### 직접 조회한 대상과 상태

- 개발 프로젝트: `FitMatch` / `hnkplvyegonlhumlejst`, ACTIVE_HEALTHY. 운영 프로젝트는 조회·변경하지 않았다.
- `fitmatch_vnext.complete_comparison(uuid,jsonb)`에는 사용자 복구 identity 처리가 존재한다.
- `validate_size_decision_v3(jsonb,jsonb)`는 없고 completion과의 연결도 없다. 기존 삽입 anchor는 존재한다.
- 복구 저장/재조회 public RPC 2개는 존재한다. 이번 변경을 위해 복구 계약을 다시 적용하지 않는다.
- `front_length_shoulder_to_hem` canonical 정의가 현재 개발 DB에 없다. 기존 tshirt/unclassified_outerwear의 back_length metric은 활성화되어 있다.

### 준비 SQL과 적용 구분

| SQL | 필요 여부 / 현재 상태 |
|---|---|
| `supabase/migrations/20261012230000_size_decision_v3.sql` | v3 점수·순위 검증에 필요. 개발의 기존 복구 처리를 보존하는 삽입 방식이며 현 함수 정의로 격리 검증 PASS. **개발/운영 실제 미적용**. |
| `supabase/sql/20261012_size_decision_v3_Verify.sql` | 승인 후 실제 적용 직후 실행할 읽기 전용 사후 검증. 실제 적용 후 검증은 NOT RUN. |
| `supabase/sql/20261012_size_decision_v3_Rollback.sql` | 준비된 되돌리기. 실제 DB에서 NOT RUN. |
| `supabase/sql/20261020_size_decision_v3_Development_Preflight.sql` | 이번에 준비한 개발 읽기 전용 사전 점검. 원격에서 동일 조건을 직접 조회했다. |
| `supabase/sql/20261012_front_length_Activate.sql` | 별도 보류. 개발 canonical 정의가 없으므로 현재 preflight에서 중단된다. 승인된 사전 정의/매핑과 최소 앱 버전 확인 없이 적용하지 않는다. |

### 남은 항목

- 개발 v3 SQL 적용 승인 및 실제 적용 후 사후 검증.
- 정상 사용자 인증으로 비교 생성→완료→재조회/History 재열기, 다른 계정 격리 검증.
- v3 기록을 이해하지 못하는 구버전 앱 혼재에 대한 배포 정책. 앞기장 활성화는 별도 판단.
- main 승격·운영 DB·배포·실기기 E2E는 이번 통합의 완료 범위가 아니다.

원문 로그/xcresult: `/private/tmp/FitMatchIntegration20261020/`. 최신 개발 함수 원문은 `scratch/branch-integration-20261020/development_complete_observed.sql`이며 서버 변경이 아닌 읽기 전용 관측이다.

### 앱 통합 회귀 실행

PASS: FitMatch-QA / Debug-QA, iPhone17 시뮬레이터. xcresult totalTestCount121 / passedTests121 / 실패0 / skip0, xcodebuild exit0. 첫 시도는 기기 준비 대기로 중단(BLOCKED), 기기 데이터 삭제 없는 재시작 후 재실행했다. 실제 정상 로그인 DB 비교·실기기 E2E는 NOT RUN.

### 개발 SQL 적용 필요성의 재현

PASS: 이번에 읽은 개발 complete_comparison 정의를 로컬에 복제하고, M에는 가슴+기장/L에는 가슴만 있는 승인 snapshot으로 v3 공통 가슴 결과를 제출하면 미적용 함수는 `Coverage does not match begin-snapshot metric coverage`로 거절하고 PENDING을 유지한다. 같은 함수에 v3 삽입부를 적용하면 정상 완료한다. 실제 개발 서버 사용자 RPC 호출이 아닌 격리 재현이며, 최종 현재 개발 정의/기존 baseline 검사 각각32개 PASS.

### QA 최종 조합 검증

PASS: QA merge `de458b3` 소스를 FitMatch-QA / Debug-QA에서 새 빌드·검사. totalTestCount129 / passedTests129 / 실패0 / skip0 / xcodebuild exit0. 기존 알고리즘·복구·버튼·옷장·History121개와 QR8개 포함. bugfix→QA 앱 코드 patch-id는 기존 QR 통합 차이와 동일(`74b2aaf2bffc4d2339d9555745443bb7dc45cccd`). 문서 충돌2개는 양쪽 기록을 보존했다. 최종 후속 변경은 SQL 테스트·검증 문서뿐이며 앱 소스는 검증한 조합과 동일하다.

NOT RUN: 전체 Release Gate / 실제 로그인 개발DB 저장·비교·History / 실기기. 개발 v3 SQL 적용은 승인 대기이며 앞기장 정의/최소 앱 버전 문제는 보류 상태다.
