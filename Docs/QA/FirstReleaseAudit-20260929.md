# 1차 출시 순차 검수 — 2026-09-29

## 최신 검증 갱신 — 2단계 완료 (2026-09-29)

- 전체 FitMatchTests **PASS: 881개 통과/0실패/42미실행**, xcodebuild exit0. Debug 앱·테스트 build/실행 PASS. 과거 전체실패 결과는 이 실행으로 대체하며 이력은 보존한다.
- 구형 테스트 계약/runner 오류 정비, MUSINSA raw0 보존. 비교용 양수 gate 유지. 격리 로컬 PostgreSQL raw snapshot 회귀 PASS. 연결DB 변경 없음.
- 실기기·실시간쇼핑몰 API·인증서버 mutation E2E·Release archive **NOT RUN**. 출시 전체 승인이나 아래 실기기 체크 완료를 의미하지 않는다. 3단계 제출설정은 미진행.
- 명령·근거·수정파일: [2단계 검증 보고서](Phase2RepairVerification-20260929.md).


기준: connectDB / db190a9c677da0181c4de2910c979a82ca59c1b8 + 시작 시 기존 dirty 변경. 앱/SQL 수정 없이 정책→배포 계약→자동검사 순서로 확인. 결과는 이 범위에 한정하며 출시 승인이나 실기기 E2E를 대신하지 않는다.

## 1. 정책과 active 구현

| 항목 | 판정 | 직접 확인한 근거 |
|---|---|---|
| 최종 점수 권한 | 정적 확인 PASS | VNextComparisonEngineAdapter.analyze:78부터 begin validator, allowed/정확한 candidate ID 집합 검증 후 comparisonMeasurements만 scoreCache에 전달. cache는 전체 evidence와 minimum이 같을 때 산술만 재사용 |
| preview와 최종 산술 | 정적 확인 PASS | RecommendationService:125–177과 adapter가 VNextAuthorizedScoreCache를 공유. 같은 값·가중치·minimum에는 같은 엔진, preview는 begin 권한이 아님 |
| 전체 원본 직접 비교 | 출시 범위 결정 필요 | adapter:112 CANONICAL policy count, validator:232 이후 v2 scoreIncluded=true 차단. 배포 evidence는 canonical + 제한된 SOURCE_NATIVE_OVERRIDE fallback. 모든 raw 직접 비교 활성화가 아님. 정책 4.3의 v2 보류와 일치하므로 이를 새 점수 버그로 단정하지 않음 |
| 원본 0값 보존 | 확인된 정책 불일치 | MusinsaParser:102 → MusinsaActualSizeAPIParser.makeParsedSize:220이 value>0만 measurementRecords에 보존. Resolver:3431은 이 records를 observation rows로 변환하며 finite zero를 허용하지만 앞 단계에서 제외된 값을 복원하지 않음. 원문 evidence body 보존과 개별 raw 행 표시/저장은 별개. 실측 정책3.5 미충족; 잘못된 양수 점수를 입증한 것은 아님 |
| 링크 사이즈 변경 | 소스/배포 계약 확인 PASS | public update wrapper가 source_observation_id 또는 use_server_measurements 입력을 update_closet_item으로 라우팅. 구형 creation-only helper의 예외는 이 경로 결함의 근거가 아님. exact receipt/variant/size 확인 후 같은 함수에서 canonical parent와 raw snapshot 갱신. Swift SyncCoordinator:918 read-back도 observation/tuple/count 확인 |
| 수동 상세 보존 | 소스/배포 계약 확인 PASS | list_closet_items가 closet_detail_code_snapshot 별도 반환, DTO optional 필드, matchesManualEditReadback:2295가 explicit snapshot 확인. 기존 상세 데이터를 현재 그룹-only UI와 혼동하지 않음 |
| 기록 삭제/최신 결과 | 소스/배포 계약 확인 PASS | comparison_history는 result_heads+deleted_at, comparison_history_sync는 owner-scoped tombstone. Swift sync와 hydrator가 삭제 및 같은 target의 이전 projection 정리. 두 기기 E2E는 별도 |

## 2. 연결 DB 직접 확인 — READ ONLY

- 앱 Info.plist:41은 `hnkplvyegonlhumlejst`(FitMatch, ACTIVE_HEALTHY, PG17.6.1.147)를 가리킨다. 최신 문서가 Production으로 부르므로 안전상 Production 취급. 쓰기/사용자 RPC mutation 없음.
- 별도 `aqhrupgjpmrtnystottx`(FitMatch_PROD, ACTIVE_HEALTHY)도 존재한다. 이 DB에서는 확인한 comparison_evidence_20260908, comparison_history_sync, comparison_history, apply_linked_closet_snapshot_for_swift, public selected candidate 함수가 0개였다. 전체 schema가 비었다는 뜻은 아니지만 현재 앱의 대체 endpoint로 준비됐다고 볼 수 없다. 전환 전 복원/계약검증 필수. 현재 기존 DB 앱이 고장났다는 뜻도 아니다.
- 기존 DB migration ledger에서 linked size/detail/tombstone(9/24), selected candidate(9/24), preview(9/28), latest result(9/28), native fallback(9/29) 적용 이력 확인. 파일 존재만으로 applied 판정하지 않음.
- 공개 RPC 8개(get/upsert/update/delete Closet, selected candidate, history sync, begin, complete): authenticated EXECUTE=true / anon=false.
- 사용자 관련 6개 table RLS=true / anon SELECT=false. 직접 조회 가능한 closet_items/comparisons는 auth.uid=user_id, measurements는 소유 Closet EXISTS 정책. 이는 확인한 테이블/함수 범위의 정적 권한 확인이며 보안 전수 감사 또는 두 계정 공격 테스트 PASS가 아님.
- 배포 함수 원본 증거: `/tmp/fitmatch-release-checklist-db-definitions.json`. 사용자 row나 credential은 기록하지 않았다.

## 3. 제출 준비에서 확인한 별도 항목

- Info.plist의 FitMatchPrivacyPolicyURL, FitMatchSupportURL 공란: 실제 공개 URL 준비/출시 설정 확인 필요.
- scripts/audit-app-store-archive.sh:75–76에 과거 1.0/build4 고정값. 현재 앱/확장 pbxproj는 1.1/build8. 스크립트의 버전 실패를 앱 결함으로 해석하면 안 되며 제출 전 입력화/현행화 대상이다. 이번에는 수정하지 않음.
- 출시 endpoint 선택, 전체 raw direct 범위, 실제 연락처/공개 정책, 최신 빌드 실기기 확인은 AI가 임의 결정하지 않음.

## 4. 실행 검증

현재 실행 결과는 아래 최종 기록으로 확정한다. 이전 Handoff의 PASS 숫자는 재사용하지 않는다.

명령:
```
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchBuild8Debug -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests -resultBundlePath /tmp/FitMatchReleaseChecklist20260929.xcresult test
```
로그: `/tmp/fitmatch-release-checklist-20260929.log`.
샌드박스 simctl 연결 실패는 권한 범위 밖 재확인으로 해결했고 실제 사용 가능한 iPhone17Pro/iOS26.3 장치를 확인했다. main-actor isolation 등 compiler warning이 존재하며 warning을 오류나 PASS로 바꿔 보고하지 않는다.

## 5. 미검증 경계

실제 retailer 신규 API, 인증 mutation→read-back→begin→complete, Apple 로그인/탈퇴, 두 기기 동기화, 실제 공유 시트/스와이프/체감속도는 NOT RUN. 새 운영 DB full restore와 심사 제출도 NOT RUN. 코드·DB 변경 및 commit/push 없음.

## 6. 자동검사 최종 결과와 출시 판단

### 전체 검사 — FAIL

- xcodebuild exit 65. xcresult summary 기준 **918 tests: 834 PASS / 42 FAIL / 42 skipped**.
- parameterized runs를 포함한 device 집계는 **931 runs: 845 PASS / 44 FAIL / 42 skipped**. 서로 다른 집계 기준을 혼합하지 않는다.
- 앱/테스트 컴파일 및 테스트 실행까지 완료. 별도 Release build/archive는 NOT RUN. compiler warning 존재.
- 실패 suite: FitMatchTests18, BodyShapeRemoval1, ComparisonSync11, FinalReleaseHeadless5, FinalReleaseScenario5, ClosetPreview1, ReferenceClosetSetupXCTests1.
- 과거 자동 기준옷 선택/우선정렬, 최소2항목, 이전 어깨가중치1.2를 기대하는 실패는 최신 정책과 충돌하는 테스트 계약 문제의 직접 증거다. 전체 42개를 모두 구형 테스트라고 확정하지 않는다.

### 확인된 실제 결함 — 과거 결과 신뢰도 replay 불일치 (HIGH, 출시 전 수정)

- adapter engineVersion:58은 계속 `fitmatch-ios-vnext-snapshot-v1`.
- `dca8294` 이전 reliability는 1항목→2, 2항목→3, 3항목+coverage 조건→4 등. 현재 adapter:267은 `min(5,max(1,evidenceCount))`.
- Hydrator:310–317은 현재 adapter로 과거 snapshot을 재계산하고 :411에서 stored reliability와 현재 reliability 완전 일치를 요구한다. 따라서 과거 정상 완료 결과 1항목/reliability2는 현재 계산1과 충돌해 completionMismatch로 복원을 거절한다.
- 전체 실행에서 `schema4HydratedFrozenReferenceResolvesItsOriginalClosetIdentity` 등 실제 hydrator 사용 테스트가 이 예외로 실패. fixture는 1항목/점수95/reliability2의 v1 완료 결과(ComparisonSyncCoordinatorTests:824–838, :855 이후).
- DB READ ONLY 집계에서도 v1 완료34건 중 현재 count 공식과 충돌18건, 그중 삭제되지 않은 최신 표시 head1건을 확인했다. 나머지16건은 count 공식과 일치한다. 18건 모두 동일한 과거 공식을 사용했다거나 실기기에서 모두 실패했다고 주장하지 않는다. 적어도 현재 표시 대상 1건(1항목/reliability2)이 동일 충돌을 갖는다.
- 집계 시 UUID 문자열은 lower로 정규화했다. 최초 대소문자 미정규화 조회의 34건 불일치 결과는 잘못된 조사 집계로 폐기했다. 최종 근거는 정규화된 18건/visible1건이다.
- 사용자 영향: 기존 로컬 기록은 남을 수 있지만 신규 설치/다른 기기/캐시 재구성에서 과거 기록 복원이 거절될 수 있다. DB 삭제/새 점수 산술 오류의 증거는 아니다.
- 수정 방향: 신규 계산 의미를 버전 구분하고 과거 완료 결과의 불변 계약에 맞는 replay를 유지. 같은 v1 이름의 서로 다른 공식이 이미 존재하므로 날짜/숫자만으로 추정하지 말고 snapshot/evidence를 검증하는 명시적 호환 계약 설계가 필요하다. 과거 값을 DB에서 일괄 재계산하거나 reliability 검사를 무조건 제거하지 않는다. old/new 완료 결과·새 설치·tombstone·latest-head 회귀로 검증한다.

### 테스트 실행기 종료 — 별도 추적 필요

- `ReferenceClosetSetupXCTests/testComparisonClassificationBoundaryPolicy`가 전체/좁은 재실행 모두 signal abrt로 종료.
- 이 XCTest는 CategoryLiveComparisonAuditTests:1096에서 폐기된 자동선택 Swift Testing 테스트들을 직접 호출한다. 앱 사용자 화면 caller가 아니다. 현재 근거로 앱 크래시라고 주장하지 않는다. activity에는 abrt만 있어 정확한 abort 원인은 추가 crash stack 확인 필요.
- 좁은 재실행 `/tmp/FitMatchReleaseChecklistFocused20260929.xcresult`: exit65, 1 FAIL. 동시 지정한 Swift test는 발견/실행되지 않았으므로 이 실행으로 History 재현을 주장하지 않는다. History suite 단독 재실행은 별도 기록한다.

### 우선순위 결론

1. 실제 과거 History replay 호환성을 먼저 수정·검증해야 한다. 사용자 E2E로만 넘기지 않는다.
2. 현재 정책과 충돌하는 테스트 및 abort runner를 정리하되 실제 실패를 기대값 변경으로 숨기지 않는다.
3. raw0 정책 불일치는 별도 최소 보완/명시적 정책 결정 대상. 정상 양수 비교의 치명적 오류라고 과장하지 않는다.
4. 기존 연결 DB의 확인한 핵심 계약은 존재하지만 새 FitMatch_PROD 전환은 아직 준비됐다고 볼 수 없다.
5. 공개 URL·개인정보 답변·실기기/인증 E2E를 완료한 뒤 출시 판단. 지금 전체 회귀 FAIL 상태를 출시 검증 완료로 처리하지 않는다.

### 실패 목록(테스트 단위)

- FitMatchTests/automaticFlowKeepsProfileCompatibleItemForInsufficientEvidenceScreen()
- FitMatchTests/bottomComparisonRequiresTwoCoreWidthMeasurements()
- FitMatchTests/bottomWidthAndLengthAloneDoNotConfirmRecommendation()
- BodyShapeRemovalTests/categoryBaseWeightsRemainUnchanged()
- FitMatchComparisonSyncCoordinatorTests/closetDeletionActionKeepsClosetAndHistoryWhenDurableHideFailsThenRetries()
- FitMatchComparisonSyncCoordinatorTests/closetDeletionHidesAssociatedCompletedServerHistoryWithoutDeletingRemoteEvidence()
- FitMatchFinalReleaseHeadlessAcceptanceTests/closetPresentationUsesOnlyActiveOwnedRowsAndPreservesFilterSortIdentity()
- FitMatchFinalReleaseHeadlessAcceptanceTests/comparedProductClosetSaveUsesTheProductionBoundaryAndRejectsDuplicateSubmit()
- FitMatchTests/compatibleOtherBrandOutranksSameBrandWithDifferentMeasurementMethod()
- FitMatchTests/compatibleRepresentativeOutranksHigherSimilarity()
- FitMatchTests/compatibleRepresentativeOutranksRicherMeasurementEvidence()
- FitMatchTests/compatibleRepresentativeOutranksSameBrandCandidate()
- FitMatchComparisonSyncCoordinatorTests/completedServerHistoryHideSurvivesSyncAndModeledSecondSession()
- FitMatchComparisonSyncCoordinatorTests/deletedReferenceHydratesAsHistoryOnlyForEveryAuthoritySource()
- FitMatchComparisonSyncCoordinatorTests/explicitServerTombstoneRemovesOnlyTheMatchingStaleLocalHistory()
- FitMatchFinalReleaseScenarioExecutionTests/hi001FreshGlobalHistoryHydrationPreservesExactCompletedSnapshot()
- FitMatchFinalReleaseScenarioExecutionTests/hi014HistoryToClosetKeepsGlobalAndPersonalAuthorityBoundariesSeparate()
- FitMatchFinalReleaseScenarioExecutionTests/historyDeletionHydrationAndCurrentAuthorityCoverHIAndResultFlows()
- FitMatchComparisonSyncCoordinatorTests/historyUnavailableReceiptKeepsLocalHistoryAndClosetWithoutLoginMessage()
- FitMatchTests/insufficientRecommendationReturnsUnsavedReferenceEvidence()
- FitMatchTests/insufficientResultReferenceChangeKeepsPersistedHistory()
- FitMatchFinalReleaseScenarioExecutionTests/latestHistoricalRowReplacesPriorVisibleProjection()
- FitMatchComparisonSyncCoordinatorTests/locallyPersistedHideBlocksAnAlreadyInFlightStaleHistoryResponse()
- FitMatchTests/measurementComparisonExcludesDifferentSleeveDefinitions()
- FitMatchTests/multipleCompatibleRepresentativesSelectDeterministically()
- FitMatchTests/outerComparisonRequiresChestAndOneAdditionalMeasurement()
- FitMatchTests/outerShoulderAndSleeveWithoutChestAreInsufficient()
- FitMatchComparisonSyncCoordinatorTests/overlappingAccountSwitchCannotHydrateOutgoingHistoryIntoNewAccount()
- FitMatchComparisonSyncCoordinatorTests/overlappingSameAccountHistorySyncUsesNewestFollowUpSnapshot()
- FitMatchComparisonSyncCoordinatorTests/pendingServerSnapshotRecoversThenHydratesExactlyOnce()
- FitMatchTests/poloUsesTshirtFamilyAndAutomaticallyMatchesSameLengthTshirt()
- ClosetPreviewMeasurementRegressionTests/rawSnapshotsDoNotReplaceComparisonEvidence(source:)
- FitMatchTests/recommendationIsBlockedWhenCompatibleEvidenceIsInsufficient()
- FitMatchFinalReleaseHeadlessAcceptanceTests/referenceRejectionKeepsServerCreatedClosetItemAndLocalReferenceFalse()
- FitMatchTests/representativeOutranksSimilarityWhenEvidenceIsEqual()
- FitMatchTests/resultReferenceSelectionKeepsPickerForInsufficientEvidence()
- FitMatchComparisonSyncCoordinatorTests/schema4HydratedFrozenReferenceResolvesItsOriginalClosetIdentity()
- FitMatchTests/singleExactRepresentativeForUserResolvedCategoryIsAutomaticallySelected()
- ReferenceClosetSetupXCTests/testComparisonClassificationBoundaryPolicy()
- FitMatchFinalReleaseScenarioExecutionTests/v4HistoryHydrationKeepsLatestResultPerProduct()
- FitMatchFinalReleaseHeadlessAcceptanceTests/v4PersonalHistoryHydrationKeepsEachImmutableAuthorityProjection()
- FitMatchFinalReleaseHeadlessAcceptanceTests/v4PersonalHistoryProjectionSurvivesFreshContainerWithoutTupleSharing()

History suite 단독 재현: `-only-testing:FitMatchTests/FitMatchComparisonSyncCoordinatorTests test-without-building`, 동일 project/scheme/destination/derivedData, resultBundle `/tmp/FitMatchReleaseHistoryOnly20260929.xcresult`. **FAIL exit65: 18 tests / 7 PASS / 11 FAIL / 0 skipped**. 전체 실행과 같은 completionMismatch 및 그 후속 복원 누락이 재현되어 다른 XCTest abort나 병렬 fixture만으로 설명할 수 없다. 로그 `/tmp/fitmatch-release-history-only.log`.

최종: 정책/DB 읽기 전용 점검 완료, 자동 회귀 FAIL, diff/protected-scroll PASS. 앱·SQL·테스트 수정 없음. 최종 Release archive/심사 준비의 완료 판정은 실제 History 결함과 회귀 실패 정리 뒤 진행한다.

## 7. 1단계 수정 후 검증 — 2026-09-29

- 기준 connectDB/db190a9 + 기존 dirty 보존. VNextCompletedReplayPolicy 신규, VNextComparisonEngineAdapter 신규 완료 engine v2, FitMatchVNextContractValidator v1/v2 계약, VNextHistoryCacheHydrator 버전별 reliability 검증. 과거 v1의 두 실제 공식만 허용하고 저장 reliability 유지. score/ranking/coverage/metric/identity 검증 불변. v2는 현재 count 공식만 허용하며 RETAILER_EXACT 활성화가 아님.
- 배포 public complete wrapper와 내부 complete 정의 READ ONLY 확인: 버전 whitelist 없음(nonempty/128자 이하). 실제 v1 완료34건 count/coverage/reliability는 구/현재 공식으로 모두 설명됨. DB write/migration/사용자row 변경 없음. 이는 34건 전체 hydration/E2E 통과 증명이 아님.
- RED: 직전 단독 History18건 중11FAIL. GREEN: 최종 3개 suite(Contract, ComparisonSync, FinalReleaseScenario) **73/73 PASS, skip0, xcodebuild exit0**. 신규 old/current-v1/new-v2 저장신뢰도 보존, 버전/identity/score/coverage/rank/weight/difference 변조거절, count/coverage 경계 회귀 포함. 기존 fixture reliability2 유지. 앱/테스트 Debug build 및 실행 PASS.
- 첫 확대4 suite는117건112PASS/5FAIL. Headless의 기존 reference 정책1, Closet 테스트 crash2, 같은상품 복수기록 기대2가 남음. 기존 동일상품 fixture를 다른상품으로 바꾸는 편집은 자동 승인 검토에서 테스트 약화 위험으로 거절되어 적용하지 않음. 기존 Headless/Scenario 파일 수정 없음. 전체 suite PASS라고 주장하지 않으며 해당 계약 정비/크래시 원인분석은2단계로 유지.
- 결과: /tmp/FitMatchPhase1Final20260929.xcresult, /tmp/fitmatch-phase1-final.log, /tmp/fitmatch-phase1-final-summary.json. 확대 실패: /tmp/FitMatchPhase1Repair20260929.xcresult. 상세 실행명령은 FirstReleaseAudit-20260929.md 추가절.
- 독립 정적리뷰: 새 결함 지적 없음(실행 검증과 별도). diff/protected scroll PASS. 신규 policy/QA문서 로컬 미추적, commit/push 없음. 실기기 로그인·재실행·두기기 E2E 및 Release/archive NOT RUN. 이전 앱은 새v2 기록을 지원하지 않으므로 새 앱 설치 전후를 혼동하지 말 것.


최종 실행명령(실제 exit0):
```bash
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchBuild8Debug -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests/FitMatchVNextContractTests -only-testing:FitMatchTests/FitMatchComparisonSyncCoordinatorTests -only-testing:FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests -resultBundlePath /tmp/FitMatchPhase1Final20260929.xcresult test
```
확대 검사명령은 위3 suite에 `-only-testing:FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests`를 추가하고 resultBundlePath를 `/tmp/FitMatchPhase1Repair20260929.xcresult`로 사용. exit65. 두 실행을 혼합해 전체 PASS로 계산하지 않음.

## 3단계 실행 결과 — 2026-09-29

도구6case PASS, unsigned Release archive PASS. 제출 gate FAIL: 공개URL2개·서명2개 미충족. 공개정책 초안 정렬 완료, 실제 운영정보·서명·실기기 미완료. DB/핵심앱 코드 변경 없음. [명령과 상세 근거](Phase3ReleasePreparation-20260929.md). 이전3단계 미진행/Release NOT RUN 기록은 이 결과로 갱신하며 과거기록은 유지한다.
