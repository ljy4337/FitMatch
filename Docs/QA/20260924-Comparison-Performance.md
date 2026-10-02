# 상품 비교 성능 개선 — 2026-09-24

## 2026-09-24 개발 DB 적용 완료 — 이전 승인 차단 해소

- 사용자가 exact 개발 프로젝트 migration 적용 요청에 “승인한다”로 명시 승인하여 `hnkplvyegonlhumlejst`에 `selected_comparison_candidate`를 apply_migration으로 적용했다. 성공 응답 및 migration ledger 확인: remote version `20260924045025`; 로컬 파일 `supabase/migrations/20260924130000_selected_comparison_candidate.sql`과 대응한다. 과거 승인 차단 기록은 이 상태로 대체되며 이력은 보존한다.
- READ ONLY postflight PASS: 신규 endpoint 존재, authenticated 실행 허용, anon 차단, mapped/session private helper 직접 실행 차단(5/5 true). eligible_candidate_sizes 2개, authorize_comparison_with_context 2개, begin_comparison, complete_comparison 총 6개 정의 hash 모두 적용 전과 동일.
- 이번 승인 후 앱 코드 추가 변경/테스트 재실행 없음. 직전 동일 변경의 전체 Swift 결과는 870 PASS / 0 FAIL / 42 skipped, 격리 SQL parity/role/rollback PASS. 배포 후 실제 인증 사용자 비교 E2E 및 실기기 속도 측정은 NOT RUN.
- 사용자 상품·옷장·비교 row 변경 없음. 함수/권한 및 migration ledger만 변경. 앱 성능 경로를 사용하려면 최신 로컬 소스로 빌드 필요. commit/push 없음.


## 범위

기준 HEAD `3243e980bc0a304693d461e2e4279fc6f970c350` + 기존 로컬 작업을 보존했다. 그룹/실측/점수/자동선택 정책 변경 없음. 다른 사이즈 비교는 기존 승인 batch를 사용하는 로컬 표시 그대로다.

## 변경

1. **선택한 옷만 후보 판정**: `FitMatchServerAuthorityCoordinator.authorizeReferenceCandidate`의 후보 조회를 선택된 exact Closet ID로 제한한다. `FitMatchSupabaseDomainClient.findSelectedReferenceCandidate`는 신규 RPC envelope의 product/variant/unique candidate identity 및 selected ID를 검증한다. 기존 current Closet receipt 및 reference/target authority 확인, local snapshot 대조, eligible, begin, complete는 유지한다.
   - SQL: 두 기존 `find_reference_candidates` 본문을 private `find_reference_candidates_filtered` overload로 공유. 전체 목록 wrapper는 NULL 필터, 새 public RPC는 exact ID 필터. 필터는 user ownership/active 조건과 함께 적용되며 auth.uid/variant/context/그룹/eligible 판정은 기존 그대로다. 원본 함수의 사용자 선택 규칙과 JSON은 변경하지 않는다.
   - **제한**: 최종 stale/fingerprint 보장을 위해 별도 eligible → begin 경계는 통합하지 않았다. 전체 Closet receipt 읽기도 유지한다. 모든 중복 계산을 없앴다는 의미가 아니다.
2. **현재 결과의 다른 옷 비교**: `CompareFlowSheet`가 기존 비교목록 callback을 두 버튼에 함께 전달한다. 이번 세션의 상품/후보 표시를 재사용하고 선택을 해제한다. History 결과의 새 CompareFlow fallback은 그대로다. 새로운 옷 선택 때에는 새 서버 허가/begin/complete를 실행한다.
   - 목록은 기존 비교목록 버튼과 동일한 세션 snapshot이다. 원격 옷장 변경을 실시간 push로 반영하는 기능은 추가하지 않았다. 최종 선택 검증은 현재 서버 상태를 다시 확인한다.
3. **첫 후보 조회의 runtime 왕복 생략**: `ShoppingProductViewModel`은 fresh observation authority를 첫 후보 계획에 한 번만 전달한다. authority 변경 시 소비 상태를 초기화하고 재시도는 runtime을 다시 조회한다. Coordinator는 source/product/runtime 계약을 다시 검사하고 후보 자체는 서버에서 현재 정책으로 조회한다. 새 영구/전역 캐시는 없다.

## 검증 범위

- SQL fixture는 배포 candidate 함수 원본으로 시작하고 eligibility/group 보조함수는 통제된 stub이다. 실제 DB 전체 비교 E2E가 아니다.
- selected/full 후보와 차단 JSON 동일, 비선택 row eligibility 호출 없음, mapped/session 그룹, 타사용자/삭제/null/미인증, rollback 후 기존 JSON 복원을 확인한다.
- Swift authority tests는 production coordinator를 실행한다. 버튼 검사는 source wiring 검사이며 실기기 UI 검증이 아니다.
- 실기기 before/after 시간과 인증된 상품 비교 E2E는 NOT RUN. 초/퍼센트 개선을 주장하지 않는다.

## 명령

`xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchSameGroupRetry -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests ... test`

SQL: PostgreSQL17 임시 DB, `psql -X -v ON_ERROR_STOP=1 -v apply=true -f supabase/sql/tests/20260924_comparison_candidates_Regression.sql`.

## 파일

- `FitMatch/Services/FitMatchServerAuthorityCoordinator.swift`
- `FitMatch/Services/FitMatchSupabaseProductResolver.swift` (기존 getClosetItem 변경과 구분)
- `FitMatch/ViewModels/ShoppingProductViewModel.swift`
- `FitMatch/Views/CompareFlowSheet.swift`
- `FitMatchTests/FitMatchServerAuthorityIntegrationTests.swift`
- `FitMatchTests/FitMatchComparisonPermitSequencingTests.swift`
- `FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests.swift` (기존 변경 보존, handoff 실패/재시도/취소 검증 추가)
- `supabase/migrations/20260924130000_selected_comparison_candidate.sql`
- `supabase/sql/20260924130000_selected_comparison_candidate_Rollback.sql`
- `supabase/sql/20260924_selected_comparison_candidate_Verify.sql`
- `supabase/sql/tests/20260924_comparison_candidates_Baseline.sql`
- `supabase/sql/tests/20260924_comparison_candidates_Regression.sql`
- 이 보고서/계획서, Behavior Map, Handoff.

## 실행 결과 / 배포

최종 검증 및 배포 결과는 아래에 추가한다. 이 줄 자체는 완료 증거가 아니다.

- 단계1 Swift: RED 41 PASS/1 FAIL(selectedCandidateIDs), GREEN 42/42 PASS exit0. `/tmp/FitMatchComparisonStep1.xcresult`.
- 단계2 wiring: RED 4 PASS/1 FAIL, GREEN 5/5 PASS exit0. `/tmp/FitMatchComparisonStep2Green.xcresult`.
- 단계3 coordinator: RED 42 PASS/2 FAIL(runtime 재조회 및 다른 상품 handoff), GREEN 44/44 PASS exit0. `/tmp/FitMatchComparisonStep3Green.xcresult`.
- SQL: RED selected candidate/full-list 불일치; 최종 GREEN exit0 `/tmp/fitmatch-deploy-comparison-roles-0uyrr5nj/run.log`. 실제 authenticated/anon 역할 실행, invalid variant/group, 없는 row, rollback 추가 PASS. eligibility/context 자체는 fixture 통제값이므로 live 정책 E2E로 확대 해석하지 않음.
- 독립 코드 리뷰: scoped Important/Critical 지적 없음. UI는 source wiring만 확인했고 실기기 미확인. ViewModel one-use 추가 회귀를 전체 suite에 포함.
- 환경: 최초 sandbox PostgreSQL shared memory/Xcode cache 접근 BLOCKED 후 승인된 로컬 실행으로 재검증. Supabase CLI 미설치로 repository timestamp 규칙에 맞춰 migration 파일 작성. 신규 Supabase SDK/CLI 기능 도입 없음.

### 중간 전체 검사 실패 분석

`/tmp/FitMatchComparisonPerformanceFinal.xcresult`: exit65, 866 PASS / 4 FAIL / 42 skipped (총912).

- `actualProductionSwiftFullChainRequiresBeginBeforeCompletion`, `comparisonProviderSequenceAndNegativeGatesCoverCP001ThroughCP039`, `everyValidFiniteJourneyScenarioExecutes`: 옛 helper가 첫 후보 이전 별도 resolve를 요구했다. 새 flow는 observation/runtime → 첫 후보이며, 선택 후 resolve/runtime/Closet → 후보 → eligible → begin → complete는 유지된다. helper를 첫 후보의 runtime/Closet과 마지막 선택 후보의 fresh resolve/runtime/Closet 순서 양쪽을 확인하도록 수정했다. 최종 허가/저장 assertion은 유지했다.
- `cp034LaterGlobalNotApplicableBlocksOnlyTheFutureComparison`: 순차 runtime fixture의 사용하지 않는 세 번째 personal 응답이 다음 상품 load에 남아 있었다. load/선택 재검증의 두 personal 응답 다음에 blocked 응답을 두도록 정렬. NOT_APPLICABLE 차단 및 이전 History 불변 assertions 유지.
- 실제 ViewModel one-use 실패/재시도/취소 신규 테스트는 이 실행에서 PASS.

추가 관련 파일: `FitMatchTests/FitMatchHeadlessUserJourneyTests.swift`, `FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests.swift`의 위 helper/해당 fixture만 수정. 기존 사용자 변경 보존.

### 최종 코드 검증

- `/tmp/FitMatchComparisonPerformanceVerified.xcresult`: exit0, **870 PASS / 0 FAIL / 42 skipped**, 총912. 앱/테스트 compile 포함. 로그 `/tmp/fitmatch-comparison-performance-verified.log`, summary `/tmp/compare-verified-summary.json`.
- git diff --check / protected scroll PASS. 기존 관련없는 dirty/untracked 작업 보존. commit/push 없음.
- 실기기 E2E/실제 전후 latency NOT RUN.

### DB 적용 차단 — 아직 배포하지 않음

- `apply_migration(selected_comparison_candidate)`는 자동 승인 검토에서 두 차례 거절됐다. 사유: 과거 DB/Edge migration 금지/read-only 지시와 충돌, 개발 환경 및 write 승인 불충분이라는 판단. 두 번째 요청에는 사용자의 기존 개발 DB 허용과 이번 개선 승인, 격리/회귀 검증 근거를 명시했으나 거절됐다. 우회 경로 사용 없음.
- 첫 거절 후 SELECT에서 새 RPC absent 확인. 최신 원격 상태는 최종 postflight로 확인할 것.
- 사용자에게 현재 개발 프로젝트의 정확한 migration 적용 재승인을 요청했다. 승인 전 원격 migration 적용은 BLOCKED.
- **새 앱의 단건 조회 호출은 migration 적용이 선행되어야 한다.** 코드 테스트 PASS는 배포 완료나 live 비교 성공이 아니다. 기존 설치 앱과 기존 원격 함수를 이번 작업에서 변경하지 않았다.
