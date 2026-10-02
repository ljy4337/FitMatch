# 2단계 수정·검증 — 2026-09-29

기준 connectDB/db190a9 + 1단계 및 기존 사용자 dirty 변경 보존. 범위: 구형 검사계약 정렬, 검사 중단 원인 해결, MUSINSA raw0 보존. DB/Edge 계약·배포·비교정책 변경 없음.

## 실패 분류와 수정 근거

| 최초 실패 묶음 | 개수 | 판정/처리 |
|---|---:|---|
| ComparisonSync | 11 | 1단계 과거 신뢰도 replay 결함 수정 및73개 회귀로 확인 |
| FinalReleaseScenario | 5 | 1단계 replay 수정으로 해소; 현재 최신head 정책 검사 유지 |
| FitMatchTests | 18 | 자동대표선택·우선정렬·최소2개 요구의 구형 기대. 현재 사용자선택·공통1개 허용으로 정렬. zero-common 부정검사는 shoulder unknown fixture로 유지하고 positive1 검사와 분리 |
| BodyShapeRemoval | 1 | 상의 정책 가슴2/어깨1.5/총장1/소매1, 합5.5 명시. 기존체형설정 비영향 검사 유지 |
| ClosetPreview | 1 | 승인 canonical1개면 preview 계산. raw 미정의 항목은 점수 제외;0/7 원본값과3 retailer 조합을 hydration까지 검사 |
| Headless | 5 | legacy대표 정렬/저장/원격reference호출 기대3개 정렬. 같은target의 이전기록3개 동시표시 기대2개는 최신head 순차교체와 재실행 보존 검사로 교체. 상품ID를 서로 다르게 바꾸지 않음 |
| ReferenceClosetSetupXCTests | 1 | sync XCTest가 SwiftTesting 테스트함수를 직접호출. 아래 crash 근거. async XCTest에서 production owner 호출/assertions로 대체; 원래 SwiftTesting8개 독립검사는 유지 |

## 크래시 직접 근거

- 2026-09-29 21:29/21:33 SIGABRT: malloc_report → swift_task_deinitOnExecutorMainActorBackDeploy → VNextAuthorizedScoreCache.__deallocating_deinit → singleExactRepresentative... → synchronous XCTest wrapper. 단독재현 기존기록과 일치. 앱 실기기 crash 증거라고 주장하지 않음.
- 22:25/22:26 SIGILL: Array._checkSubscript → Headless v4PersonalHistoryHydration... line1800. 최신1개 정책으로 반환된 배열에 테스트가 histories[1] 접근. #expect는 실행을 중단하지 않음. 현재단계에서 동일상품 순차head교체를 검사하고 require로 수량을 확인한 뒤 접근.
- 테스트 삭제/skip 추가/상품identity 우회 없음. 본체 코드의 actor/cache 동작은 변경하지 않음.

## 무신사 수정

- RED: 새 actualSizePreservesZeroRawRowsWithoutMakingThemComparable에서 records1 vs expected3 확인. 수신capture → 실제 actual-size parser → sourceDisplayRows → makeRecord → observation 전송 검사.
- makeParsedSize만 변경: finite0 raw행 보존, 양수만 scalar projection. 기존양수 의미변환/병렬요청/서버권한 변경 없음. unknown 양수도 raw로 유지. zero-only parsed evidence는 hasUsableMeasurements=false, raw record isComparable=false.
- 기존 observation finite0 보존/DB raw snapshot 저장/canonical positive gate 재사용. DB mutation·새migration 없음.

## 실행 증거

1. 2단계 초기 focused 실행: `/tmp/FitMatchPhase2Red20260929.xcresult`, exit65, 372 tests=354PASS/4FAIL/14skip. 실패: raw0신규검사, bottom requiredKinds 기대, BodyShape 옛가중치, preview optional nil 기대. 최초확인한18개 정책불일치와 History/XCTest 종료문제는 이 실행에서 재발하지 않음. 테스트출력의 단일 crash를 다른 테스트의 앱crash로 확대하지 않음.
2. 독립 `/tmp` PostgreSQL17 fixture: 기존 `supabase/sql/tests/closet_raw_measurement_snapshots_LocalRegression.sql` + 해당 Apply/Rollback, exit0 `LOCAL_REGRESSION_PASS`. 로그 `/tmp/fitmatch-phase2-raw-db.log`. 로컬fixture는 기존ingestion owner 일부를 모델링하므로 실제Supabase 전체E2E가 아님. 생성cluster 서버 종료 완료. 연결Supabase 접근/쓰기 없음.
3. 전체1차 `/tmp/FitMatchPhase2Full20260929.xcresult`: exit65,923tests=879PASS/2FAIL/42skip. 추가실패는 musinsaActualSizeAcceptsLetterSizesWithProductDescriptors(0-only사이즈 raw에추가), storedMusinsaCorpusExportsActualSizeAttritionDiagnostics(보존raw와positive usable구분 필요). raw size3/valid2를 각각 검증하고, no-positive 판정은 rawPositiveMeasurementCount==0으로 분리. corpus1037/공식size없음113/positive없음10/eligible914 기준 자체는 유지.
4. 최종 전체 `/tmp/FitMatchPhase2Final20260929.xcresult`: PASS, exit0. test 단위923=881PASS/0FAIL/42skip; parameter별 device 실행939=897PASS/0FAIL/42skip. Debug 앱·테스트 컴파일 및 실행 PASS. 42개 미실행 검사는 PASS에서 제외. 기존 actor-isolation warning은 남아 있으며 warning-free 빌드라고 주장하지 않음. 요약 `/tmp/fitmatch-phase2-final-summary.json`, 로그 `/tmp/fitmatch-phase2-final.log`.

## 미검증 경계

실시간 retailer API, 인증된 실제 서버mutation/E2E, 실기기 공유/화면/체감성능, Release archive는 이 단계의 자동검사와 구분. 3단계 제출설정 수정은 미진행.

## 실행 명령

```bash
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchBuild8Debug -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests -resultBundlePath /tmp/FitMatchPhase2Final20260929.xcresult test
```
최종 로그 `/tmp/fitmatch-phase2-final.log`; 최초full은 resultBundle/log의 Final→Full로 구분. RED focused는 FitMatchTests/BodyShapeRemovalTests/ClosetPreviewMeasurementRegressionTests/FinalReleaseHeadlessAcceptanceTests/ReferenceClosetSetupXCTests/MusinsaParserConcurrencyTests 6개 suite를 각각 only-testing으로 지정.

## 변경 파일

- production: `FitMatch/Services/MusinsaActualSizeAPIParser.swift` (makeParsedSize).
- tests: `FitMatchTests/FitMatchTests.swift`, `BodyShapeRemovalTests.swift`, `CategoryLiveComparisonAuditTests.swift`, `ClosetPreviewMeasurementRegressionTests.swift`, `FitMatchFinalReleaseHeadlessAcceptanceTests.swift`, `MusinsaParserConcurrencyTests.swift`.
- 문서: 본 보고서, FirstReleaseRepairPlan/Checklist/Audit, Handoff, Behavior Map의 raw0 보존 설명.
- 본체 RecommendationService/MeasurementComparisonEngine/MeasurementComparisonPolicySnapshot 및 DB파일 변경 없음. 시작시 다른 dirty 변경은 보존.

## 최종 상태

- 독립 정적리뷰: 차단 결함 지적 없음. 실행검사와 별도.
- connectDB/db190a9 유지, 기존 dirty 보존. 신규 보고서 등 로컬 미추적 파일은 원격 반영되지 않음. commit/push 없음.
- 연결 DB write/migration/사용자 데이터 변경 없음. 격리 로컬 SQL 회귀만 수행.
