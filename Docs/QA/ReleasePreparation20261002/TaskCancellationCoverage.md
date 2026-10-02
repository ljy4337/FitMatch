# P09 실제 Task 취소 — 기존 검사 재사용

기준: QA `086617f49cd19c8c3e2777e75efa820d7f886b5f`. 제품 Swift/UI/정책/DB 변경 없이 기존 테스트를 조사했다. 동등한 실제 `Task.cancel()` 검사가 이미 있어 `FitMatchReleaseTaskCancellationTests.swift`를 중복 생성하지 않는다.

P09는 실제 취소 검사가 전혀 없는 상태가 아니다. 기존 `smoke-selectors.json`의 `fault-cancel`은 아래 수동 등록 재조회 검사를 이미 선택한다. `URLError.cancelled` 주입 검사와 이 실제 Task 취소 증거를 구분해야 한다. 아래 세 메서드를 소규모 후속 실행 대상으로 재사용한다. 후속 실제 실행은 **PASS: 3개 메서드/4회 실행/0 skip**이다. `/tmp/FitMatchResume40Focused`와 최종 통합 `/tmp/FitMatchResume40Combined`에서 확인했다.

## 실행 선택자와 판정 범위

```text
FitMatchTests/FitMatchClosetSyncCoordinatorTests/manualRegistrationCancellationDuringReadbackDoesNotPublish()
FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests/linkDraftPrecedesServerCompletionAndCancellationCannotPublishAuthority(cancel:)
FitMatchTests/ZARAParserConcurrencyTests/cancellationWhilePageIsPendingCancelsSpeculativeGuideBeforePageCompletes()
```

| 검사 | 실제 제품 owner | 취소 경계와 관찰값 | 제한 |
|---|---|---|---|
| 수동 등록 재조회 | `FitMatchClosetSyncCoordinator.registerManualServerFirst` | synthetic upsert 후 list read-back 도착을 확인하고 `task.cancel()`. 게이트를 열면 remote는 ready를 반환하지만 제품 owner의 `Task.checkCancellation()`이 local projection 전에 중단한다. `CancellationError`, 취소 전후 SwiftData `UserFit` 0개를 확인한다. | 실제 서버 취소·rollback·UI dismiss 증거는 아니다. 서버에 이미 저장된 결과의 재시도 동작은 별도 검사다. |
| 링크 등록 authority 준비 | `FitMatchLinkClosetRegistrationAction.load` → `ShoppingProductViewModel` → `FitMatchServerAuthorityCoordinator` | observation 도착까지 대기. retailer draft의 preparing 상태·빈 authority identity·등록 불가를 확인한다. 취소한 경우 `.cancelled`이며 `.loaded`가 되면 실패한다. 취소하지 않는 대조 실행은 exact selected-size identity를 확인한다. | 1개 메서드의 `cancel=false/true` 2회 실행. synthetic remote도 취소 플래그를 확인하므로 비협조적 늦은 성공 응답 전체를 증명하지 않는다. 실제 SwiftUI sheet 상태는 범위 밖이다. |
| ZARA 페이지 대기 | `ZARAParser.parse` | page와 speculative guide 시작 이벤트 확인 후 `task.cancel()`. guide에 실제 취소 전달을 확인하고, 취소를 무시한 page 게이트를 정상 응답으로 연다. `CancellationError` 및 전후 details 요청 0회를 확인한다. | synthetic provider loader이며 live retailer/실제 URLSession 취소 증거는 아니다. 임의 시간 경과를 정상 완료 근거로 쓰지 않는다. |

## 동기화와 빌드 주의

- 수동 등록은 기존 `JourneyAsyncGate`의 기록된 arrival을 기다린다. 해당 helper는 10ms 간격으로 최대 5초 확인하며 미도착 시 `Issue.record` 후 게이트를 연다. 고정 sleep 뒤 무조건 진행하는 테스트가 아니다. helper 파일은 `FitMatchHeadlessUserJourneyTests.swift`다.
- 링크 준비는 `ComparedProductSubmissionGate`의 continuation arrival/open 신호로 진행한다. 해당 private helper와 fixture가 같은 `FitMatchFinalReleaseHeadlessAcceptanceTests.swift`에 있다.
- ZARA의 `RetailerParserConcurrencyTestWait`는 actor가 기록한 시작/취소 상태를 `Task.yield()`로 확인하고 2초 watchdog으로 누락 이벤트를 실패 처리한다. 공유 helper는 `UniqloParserConcurrencyTests.swift`에 있어 개별 파일만 따로 컴파일할 수 없다.
- XCTest/Swift Testing 선택자에서 `()` 및 `(cancel:)`를 보존한다. 빌드 성공만으로 실행 성공을 기록하지 않고 발견 목록·xcresult에서 세 메서드와 매개변수 실행을 확인한다. 예상은 **3개 메서드 / 4회 실행**, skip 0이다.
- 통합 담당이 `FitMatch-QA` / `Debug-QA`로 순차 실행했다. 동일 DerivedData 병렬 빌드 없음.

## 남은 범위

P09 전체를 PASS로 닫지 않는다. 취소 시점별 모든 저장·수정·삭제·비교 캐시, 화면 이탈/계정 변경, private SwiftUI 선택 상태와 실제 네트워크/인증 DB 효과는 별도 증거가 필요하다. 이 세 검사로 제품 결함이 발견되면 원래 기대값을 유지하고 FAIL을 기록하며 제품 코드를 수정하지 않는다.
