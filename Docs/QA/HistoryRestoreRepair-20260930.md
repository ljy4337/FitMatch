# 기존 데이터 History 복원 수정 — 2026-09-30

## 범위

connectDB/db190a9 + 기존 dirty. 새 쇼핑몰 API 수집·DB 변경 없음. 앞선 감사의 기존 완료기록 MUSINSA5328103 / UNIQLOE484080 / ZARA564222870 고정 자료를 사용했다. 앱의 점수·추천·분류 정책을 바꾸지 않는다.

## 수정 및 재현

1. `VNextHistoryCacheHydrator.HistoricalTargetProjection`: CATEGORY_GROUP + CATEGORY_GROUP_CONFIRMED를 정확한 조합으로 허용. 다른 상태를 GLOBAL로 치환하지 않는다. 앞선 감사3/3 incompleteSnapshot 실패 근거를 그대로 사용.
2. 같은 owner의 canonical projection: CATEGORY_GROUP 수정 후 실측6/4/2개가 전부0개로 소실되는 실패를 실제 실행했다(`/tmp/FitMatchHistoryRepairStep1.xcresult`, exit65). 서버 canonical code/value를 그대로 record에 보존하고 기존 canonical projection만 표시용으로 사용한다. 공통값의 methodSource는 fitmatch_vnext_snapshot, 원본과 구분. weight/계산/단위환산 추가 없음.
3. 교체 전 검증: 기존 실제기록을 먼저 복원한 뒤 source는 유지하고 state만 REVIEW_REQUIRED로 바꾼 합성 실패입력으로 기존 History 삭제를 재현했다(`/tmp/FitMatchHistoryRepairStep2.xcresult`, 6runsPASS/1FAIL, exit65). 실제 retailer 신규응답 또는 서버파손 사건으로 보고하지 않는다. 새 replacement 전체의 score/authority/reference를 검증한 뒤 기존 cache를 교체한다. 분석 결과를 재사용해 점수 재계산을 중복하지 않는다. 다른 미저장 작업까지 rollback하지 않는다.

## 검사

`FrozenReleaseHistoryAuditTests`:
- 기존3상품 추천ID/score 재생.
- empty-cache hydration 및 canonical code/value/count 유지.
- 로컬 disk store 저장 후 새 container 재개방으로 History/실측 유지.
- 거절된 replacement에서 기존 History와 context 변경 없음.

중간 전체 offline suite: `/tmp/FitMatchHistoryRepairFinal.xcresult`, exit0, **876tests PASS/0FAIL/10skip; device runs899PASS**. 이것은 이후 원본/공통 경계 검증 추가 전 결과다.

## 경계

- 실제 두 기기 네트워크 E2E, 물리iPhone, Release archive는 이번에 실행하지 않는다.
- 기존 compiler actor-isolation warning은 유지.
- commit/push 없음, 새 테스트/fixture는 로컬파일.
- 디스크 저장 오류 자체의 rollback을 이번 테스트로 증명하지 않는다. 확인된 snapshot 검증 실패가 기존 기록을 지우지 않는 범위를 보장한다.

## 원본 재전송 안전 경계

추가 검사에서 restored Product가 fitMatchStoredRetailerFactsForRecompare를 통해 variant=__default__ 및 canonical records를 가진 retailer envelope로 만들어지는 것을 재현했다. `/tmp/FitMatchHistoryRawBoundaryRed.xcresult` exit65, 해당3상품 parameter runs 실패. 이 payload를 실제 DB로 보내지는 않았다.

`FitMatchProductAuthorityPayloadBuilder.fitMatchParsedRetailerFacts`에서 hydrator가 부여한 fitmatch_vnext_history source marker의 Product를 원본 관측으로 재사용하지 않도록 거절한다. API에서 실제 불러온 Product에는 적용하지 않는다. DB에 없는 색상/원문을 추측해 복구하지 않는다.

**기능 한계:** 원본이 없는 서버복원 History에서 바로 옷장등록/원본 기반 재비교는 상품 링크 재입력이 필요하다. 기존 링크가 있으면 History 재비교 action은 URL경로를 우선한다. 서버의 exact 원본/variant를 복원하여 이 추가동작까지 자동 지원하는 구현은 이번 최소 복원 수정에 포함하지 않았다. 성공했다고 보고하지 않는다.

## 최종 검증

- 최종 전체 offline: **PASS**, exit0, `/tmp/FitMatchHistoryRepairVerified.xcresult` / 동일명.log.
- **876 PASS / 0 FAIL / 10 NOT RUN(skip)**. 동적 인자 기준899runs PASS. live/API/auth-write suite 명시 제외는 PASS에 포함하지 않는다.
- 신규4 test functions/10 parameter runs: **PASS**. 원본 고정3건 재생·복원·exact code/value 보존·disk reopen 및 합성거절1건 기존기록보존, 원문오인재전송 차단 포함.
- Debug app/test build **PASS**. Release build·실기기·두기기E2E **NOT RUN**.
- git diff --check / 보호스크롤 **PASS**. Branch/HEAD 동일. 기존 dirty보존, commit/push/DB write/migration 없음.

### 최종 명령 (live suite 제외)

```bash
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchBuild8Debug -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests -skip-testing:FitMatchTests/LiveReleaseRetailerProofTests -skip-testing:FitMatchTests/LiveProductGroupURLAuditTests -skip-testing:FitMatchTests/LiveUniqloValidationTests -skip-testing:FitMatchTests/LiveManualProductClassificationTests -skip-testing:FitMatchTests/LiveMusinsaValidationTests -skip-testing:FitMatchTests/LiveProductCorpusValidationTests -skip-testing:FitMatchTests/LiveThreeProductComparisonTests -skip-testing:FitMatchTests/FitMatchReleaseLiveProductAuditTests -skip-testing:FitMatchTests/LiveReleaseQA1200Tests -skip-testing:FitMatchTests/MixedTopLiveRegressionTests -skip-testing:FitMatchTests/CategoryLiveComparisonAuditTests -skip-testing:FitMatchTests/ReferenceClosetSetupXCTests -skip-testing:FitMatchTests/ZARAParserPhase1_5Tests/liveDefaultLoaderResolvesOfficialProductIdentityAndGarmentGuide -skip-testing:FitMatchTests/ZARAParserPhase1_5Tests/liveURLVariantDirectlyResolvesOfficialGarmentGuideWithoutProductPage -skip-testing:FitMatchTests/ZARAParserPhase1_5Tests/liveUserSharedZARAURLReachesProductionParser -skip-testing:FitMatchTests/CategoryValidation5026AuditTests/testLiveProductionParserRevalidatesOfflineAmbiguousAndOtherProducts -resultBundlePath /tmp/FitMatchHistoryRepairVerified.xcresult test > /tmp/FitMatchHistoryRepairVerified.log 2>&1
```

## 이번 변경 파일

- FitMatch/Services/VNextHistoryCacheHydrator.swift: 그룹상태·canonical 보존·교체전 검증. 기존 v1/v2 호환성 dirty는 보존.
- FitMatch/Services/FitMatchProductAuthorityPayloadBuilder.swift: restored History의 canonical projection을 retailer fact로 재사용 금지.
- FitMatchTests/FrozenReleaseHistoryAuditTests.swift: 실제3상품·disk reopen·실패보존·원문경계 회귀.
- FitMatchTests/Fixtures/ReleaseAuditPreviouslyCompleted20260930.json: 앞선 감사에서 read-only로 확보한 고정자료 그대로 사용.
- Behavior Map / Handoff / FirstReleaseChecklist / 본 보고서 및 감사보고서에 최신 결과 연결.

## 추가 수정 — 사용자 선택 그룹 History

- 기존 DB 완료기록 c4c1b9c1-29e8-4942-bdae-f8263f4fa1f2를 읽기전용으로 확보. visible/current head/schema4/v1. 신규상품 수집/DBwrite 없음.
- 신규 fixture ReleaseAuditSessionHistory20260930.json. 서버는 source 대신 effective_source=SESSION_USER_SELECTED, state=SESSION_GROUP_CONFIRMED를 기록. 기존 Swift는 필수source가 없어서 거절했다.
- 최초 개별 test 필터 실행은0tests라 증거에서 제외. 실제 클래스 실행 `/tmp/FitMatchSessionHistoryRed2.xcresult`에서5testsPASS/1FAIL, incompleteSnapshot으로 재현.
- source 대체 필드 소비는 SESSION_GROUP_CONFIRMED 문맥에만 한정. exact 그룹코드/요청그룹/저장그룹/source/fingerprint 일치 검증. local provenance=.serverSessionComparison이며 GLOBAL/USER_EXPLICIT로 치환하지 않는다.
- 실제 기록 복원/기존score/size 보존 테스트 + 상태/source/group/fingerprint 불일치4개 거절회귀 추가. 원본재전송 차단 유지.
- production 변경은 VNextHistoryCacheHydrator의 HistoricalTargetProjection만. 기존dirty/이전수정 보존. 최종실행결과는 아래에 추가.

### 사용자 선택 그룹 최종 결과

PASS: `/tmp/FitMatchSessionHistoryGreen.xcresult`, xcodebuild exit0, 878tests/904runs PASS / 0FAIL / 10skip. Debug app/test build PASS. 신규 session 실제기록복원 및 변조4case 포함. live 제외 목록은 위 전체 offline 명령과 동일하며 resultBundlePath만 변경했다. Release/물리기기 재설치 E2E NOT RUN. 코드 diff/보호스크롤 PASS. 새fixture는 로컬 미추적이며 commit/push 없음.
