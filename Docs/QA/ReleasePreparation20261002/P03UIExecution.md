# P03 화면 선택 상태 — 읽기 전용 부분 검사

준비: `FitMatchUITests/FitMatchReleaseAlternativeSelectionUITests.swift`.
전체 P03 상태: **BLOCKED**. 아래는 기존 History의 대체 사이즈 선택·표시만 검사하는 일부 경로다. 다른 Closet 선택 후 상태 초기화는 검증하지 않는다.

이번 작업: 앱 실행·네트워크·DB write 없음. Swift 문법 parse PASS. 최종 Xcode 빌드·발견 PASS (SessionPreparationReport.md), 실제 실행 NOT RUN. 전용 개발 계정의 정상 로그인과 기존 검증 History가 없어 이 부분 검사 실행도 BLOCKED다.

## 실제 검사 범위와 한계

- 정상 로그인된 QA 앱의 기록 탭에서 **정확한 상품명 하나**에 해당하는 기존 History를 연다. 동일 이름이 둘 이상이거나 화면에 없으면 실패한다.
- 다른 사이즈 시트가 미선택 상태로 시작하는지 확인한다. 기존 접근성 label/selected trait으로 승인된 추천 외 사이즈를 선택·적용하고 `비교 사이즈` 표시를 확인한다.
- `비교할 내 옷 변경` 버튼의 존재와 활성 상태만 확인하며 **누르지 않는다**. 기존 History replay와 임시 대체 사이즈 표시는 새로운 begin/complete를 만들지 않는다.
- 상품명은 UI 조회 근거이며 server UUID/현재 로그인 UUID의 read-back 증거는 아니다. 전용 계정과 정확한 History/상품/Closet/승인 대체 사이즈 identity는 별도 읽기 검증으로 먼저 확인해야 한다.

History에서 변경 버튼을 누르면 `CompareFlowSheet(initialHistoricalProduct:)` → `loadProductInfoFromHistoricalProduct` → `resolveServerAuthority` → `resolveFreshRetailerProductAuthority`로 이어져 **후보를 고르기 전에도 observation ingestion/promotion을 할 수 있다**. 그러므로 해당 버튼 누르기부터는 읽기 전용 검사에 포함하지 않는다.

## 실행 준비

QA 앱 `com.ljy4337.fitmatch.qa`, 개발 프로젝트 `hnkplvyegonlhumlejst`, 정상 로그인된 전용 계정을 사용한다. 계정 token/fake-auth flag는 주입하지 않는다. 기록 목록에서 유일하게 확인한 정확한 상품명과 그 결과의 승인된 추천 외 사이즈를 준비한다. 자동 정리나 새 비교를 만드는 동작은 없다.

아래 값은 검증한 fixture로 채운다. `FITMATCH_QA_SIMULATOR_ID`는 `simctl`에서 확인한 실제 UDID다. Xcode의 `TEST_RUNNER_` 전달 접두사를 사용한다. 새 결과 경로를 선택한다.

```bash
export TEST_RUNNER_FITMATCH_P03_READ_ONLY=1
export TEST_RUNNER_FITMATCH_P03_DEDICATED_ACCOUNT=1
export TEST_RUNNER_FITMATCH_P03_PROJECT_REF=hnkplvyegonlhumlejst
export TEST_RUNNER_FITMATCH_P03_HISTORY_PRODUCT_NAME='<검증된 기존 History의 정확한 상품명>'
export TEST_RUNNER_FITMATCH_P03_ALTERNATIVE_SIZE='<이 결과의 승인된 추천 외 사이즈>'
xcodebuild test -project FitMatch.xcodeproj -scheme FitMatch-QA -configuration Debug-QA \
  -destination "platform=iOS Simulator,id=${FITMATCH_QA_SIMULATOR_ID:?확인한 simulator UDID 필요}" \
  -only-testing:FitMatchUITests/FitMatchReleaseAlternativeSelectionUITests/testExistingHistoryAlternativeSelection \
  -resultBundlePath /tmp/FitMatchP03UIReadOnly.xcresult
```

설정 누락은 앱 실행 전 `FitMatchP03Blocked` 오류로 실패한다. skip/PASS가 아니다. 결과에서 정확히 1개 실행·0실패·0skip을 확인해도 **부분 경로 PASS**로만 집계한다. 운영/기본 FitMatch scheme은 사용하지 않는다.

## 전체 P03 실행 전 필요한 것

다른 내 옷→다른 사이즈 전환 검사는 정확한 실행 계정 identity, 승인된 두 후보·상품/size ID, 원래 run ledger, 실제 생성 ID 추적, 소유 범위 cleanup/read-back을 갖춘 개발 DB 쓰기 경로에 연결해야 한다. 이번 테스트에는 fresh 상품 URL 비교, 다른 Closet 버튼 클릭, 두 번째 후보 선택을 넣지 않았다.

`RecommendationResultView.selectedAlternativeSizeID`는 private `@State`이며 `resetTemporarySizeComparison()`은 현재 호출되지 않는다. 실제 초기화는 `CompareFlowSheet`의 `.result` 분기 제거·재생성에 따른다. 따라서 호출되지 않는 reset 함수를 노출하거나 미장착 View 상태를 바꾸는 검사는 전체 P03 증거가 아니다. 제품 hook과 선택 로직은 수정하지 않았다.
