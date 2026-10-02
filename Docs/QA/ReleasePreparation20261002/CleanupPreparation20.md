# 중단 정리 사전 준비 — 2026-10-02

## 범위

QA `086617f` 기준 테스트 하네스만 대상으로 한다. 앱 기능·UI·점수정책·DB/RPC 계약은 변경하지 않는다. 실제 인증·DB 쓰기·대량 full 검사는 실행하지 않는다.

## 확인한 원인과 경계

기존 [AuthenticatedGapAudit.md](AuthenticatedGapAudit.md)의 공백을 현재 소스와 보존된 개발 DB 정의 증거로 재확인했다. `comparison_result_heads`는 사용자와 **상품**을 기준으로 최신 완료 비교 하나를 가리킨다. 같은 상품의 이전 완료 비교는 active History에서 빠지지만, `deleted_at`이 없으므로 tombstone에도 없다. 이전 ledger를 복원할 때 현재 소유권을 재검증할 수 없어 BLOCKED가 맞다. 이번에 개발 DB 정의를 새로 조회한 것은 아니다.

테스트 하네스에 다음 비교의 begin 전에 실행하는 사전 처리를 추가했다. 이전 run 소유 비교의 정확한 History tuple과 reference Closet의 marker·client/server/product/variant를 list와 exact read로 검증하고, 정확한 comparison client ID만 숨긴 뒤 fresh sync의 tombstone을 확인한다. 같은 상품의 모든 이전 항목을 검증한 뒤 hide를 시작하며 다른 variant도 같은 상품 head 범위에 포함한다. 검증·hide 응답·postflight·ledger 저장 중 실패하면 다음 비교로 진행하지 않는다. 이미 숨겨진 상태는 독립 tombstone으로만 인정한다. 기존 restore cleanup의 소유권 규칙은 변경하지 않았다.

기존 B의 Closet 편집 후 과거 History 불변 확인은 사전 처리보다 먼저 수행한다. G의 과거 결과 replay는 이미 받은 immutable DTO를 그대로 사용한다. 과거 완료행을 active API에서 다시 읽을 수 있다고 주장하지 않는다. E는 현재 비교와 다른 상품 비교의 보존 검사를 계속 수행한다. H/E의 검증 seed는 기존 기대대로 target과 reference 상품이 달라야 한다.

`ReleaseAuthComparisonRetirement`는 실제 인증 하네스가 호출하는 같은 action이다. 오프라인 검사는 외부 read/hide/write 경계만 주입하여 정확한 대상만 숨김·무관한 기록 보존, History/참조/exact-read 증거 누락 시 hide 없음, 잘못된 receipt·tombstone 누락·hide 응답 유실 시 다음 비교 차단, 기존 tombstone으로 journal 복구, 같은 상품의 다른 variant 증거 누락 시 부분 hide 차단을 검사한다. 가짜 SDK 응답으로 실제 DB 성공을 선언하지 않는다.

## 검증 기록

- **RED 확인:** root의 `/tmp/FitMatchPrep20CleanupRed.xcresult`, exit65. 기존7 실행 PASS, 신규7 실행 FAIL(신규2 메서드). no-op 사전처리에서 정확한 hide 누락과 실패 후 다음 비교 허용을 탐지했다. 이 결과를 받은 뒤 구현했다.
- **PASS:** 수정한3 Swift 파일 syntax parse, `git diff --check`, 보호스크롤 검사. 타입 검사·실행 증거로 확대하지 않는다.
- **GREEN PASS:** root의 구현 후 ledger + 관련 History focused Xcode 실행 exit0, `/tmp/FitMatchPrep20Focused.xcresult`. 보존 증거: `evidence/Resume20/focused-summary.json`, `evidence/Resume20/focused.log`. 상세 실행 수는 해당 요약을 따른다. 이 문서의 agent는 Xcode를 중복 실행하지 않았다.

## 남은 제한

- 이미 superseded 상태로 남은 기존 ledger는 계속 BLOCKED다. 소유권 guard를 완화하지 않는다.
- begin/complete 응답 유실, pending 비교, 참조 삭제 후 증거 부족 등 모든 중단 지점을 해결한 것은 아니다.
- 실제 두 전용 계정 인증·정확한 seed·실제 중단 복구는 미실행이다. 오프라인 검사는 실제 DB 복구 성공 증거가 아니다.
