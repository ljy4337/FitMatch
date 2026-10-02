# 1차 출시 자동 검사 명세

목표는 현재 정책과 고정 자료의 정확성 검사다. 준비 smoke는 출시 승인이나 모든 기능 정상 판정이 아니다. 원칙의 근거는 사용자 이번 요청 A–H/연속1–10, `AGENTS.md`, `Docs/FitMatchMeasurementPolicy.md`다. 실제 함수·RPC·진입점과 실행 선택자는 CoreCoverage.md / smoke-selectors.json에 연결한다.

## 기대 동작 (코드의 현재 출력이 정답은 아님)

| ID | 사전 상태 / 입력 | 기대 상태·출력 / 새 조회 | 예상 DB 효과 및 보존 대상 | 근거 / 증거 경계 |
|---|---|---|---|---|
| A | 선택된 상품/색상/사이즈 exact UUID, 등록 가능 서버 receipt | 같은 identity·원본·canonical read-back 뒤 success. 응답 불명확 시 같은 요청 유지 | 신규 Closet 1, 동일 요청 재시도 추가 0. 다른 Closet/History 유지 | 정책3, 사용자A. Swift synthetic transport; 실제 DB는 별도 |
| B | 기존 Closet1, 새 exact size+source observation 또는 사용자 편집 | 요청 대상만 변경. 같은 선택 identity raw/canonical 동시 일치. 실패 시 success 금지 | 기존 row1 update; 신규 Closet0. 무관 row 유지. 과거 History snapshot 재계산 금지 | 정책3/5, 사용자B. 현재 smoke는 linked readback+manual stale receipt |
| C | Closet A/B, A 관련 History | 확인/서버 응답 후 A만 active 목록에서 제거 | A soft delete1. B0. 관련 기록 가시성 처리는 현 계약 테스트로 특성화; 물리 snapshot 보존 | 사용자C, 정책5. 기록 자동 숨김의 제품 기준은 아래 미확정 참조 |
| D | 같은 그룹, 명시적으로 선택한 Closet, 서버 승인 candidate sizes/metrics | 승인 evidence만 계산. 같은 evidence면 preview/detail/completion 수치 일치 | begin/complete 각 comparison identity, 재시도 동일 identity. 다른 기록 snapshot 유지 | 정책4/5. 독립 손계산 oracle.json, 공식 자체 승인 미확정 |
| E | History A/B, Closet C | A만 사용자 목록에서 사라짐; 새 객체 조회에서도 tombstone 유지 | History A hide1, B0, Closet C0. hard delete 요구하지 않음 | 사용자E. mock second session과 실제 DB 구분 |
| F | 승인된 사이즈 M/L, 현재 M | L 선택 시 L UUID와 실측으로만 임시 결과; M 결과 혼합 금지 | 현재 앱은 임시 선택에 새 complete 호출 안 함. 이 동작 정책 확정은 아래 참조 | 사용자F, 현재 결과 호출 경로. smoke는 exact batch 복원 |
| G | 상품1, Closet A/B, 현재 A | B 명시 선택 → 새 서버 authorization/begin/complete. A snapshot 불변 | 새 comparison 요청. 기존 History 가시성/새 선택 size 유지 규칙은 명세 공백 별도 | 사용자G, 정책4.3/5 |
| H | 결과의 추천 M, 사용자가 등록할 L 확정 | 등록 L UUID/색상/실측. 추천 M으로 바꾸지 않음 | 신규 Closet1, 원래 comparison snapshot 불변. 이후 승인 후보 가능 여부 서버 확인 | 정책3.1, 사용자H. payload/save 부분 검사, 전체 새옷 재비교 미연결 |

`DB 효과` 열은 정답 요구이지 mock 실행이 실제 row를 바꿨다는 주장이 아니다. 서버 History 현재 visible head 정책상 이전 기록을 숨기더라도 immutable snapshot 변경과 구분한다.

## 정답 데이터

- `oracle.json`: 수기 산술과 단위/basis/가중치/허용오차. 최종 정수는 정확 일치, 부동소수는 절대 오차 0.000001. 실제 비교 엔진으로 기대값을 생성하지 않는다.
- `FitMatchReleasePreparationTests`: 실제 adapter/preview/completion DTO 계산. fixture는 합성 schema3 replay이며 현재 인증된 schema4 begin을 대신하지 않는다.
- `FitMatchReleaseRawFixtureTests`: U8size32facts/M4size24facts/Z4size20facts와 첫 사이즈의 literal raw 값. Zara 측정 JSON은 실제 원문, PDP shell은 명시적 합성. rawCode/rawLabel을 semantics 추정에 사용하지 않는다.
- 원문/index/URL: data/ 및 DataInventory.md. 수집일/ID가 원자료에 없으면 새로 만들어 채우지 않는다. 정상 후보와 검증된 정상은 구분한다.

## 미확정 정책과 검사 한계

점수 공식·반올림·동점 처리의 독립 제품 명세를 찾지 못했다. 현 구현의 결정적 재현은 가능하지만 그것만으로 제품 정답을 승인하지 않는다. `policy-expectations.json`에서 UNRESOLVED로 전체 성공을 차단한다.

또한 중복 **같은 요청의 재시도**와 사용자가 의도적으로 같은 상품·사이즈를 다시 등록하는 것은 다르다. 후자의 허용/거절 기준, 다른 내 옷을 선택할 때 이전 임시 사이즈 유지 여부, 임시 사이즈 선택 기록 여부, 옷 삭제 시 관련 기록 자동 숨김 여부는 현 계약과 사용자 명세를 구분해 최종 확인이 필요하다. 해당 정책에 의존하지 않는 exact identity/기존 snapshot 불변 검사는 계속 실행한다.

완성된 테스트 함수와 종단 체인 전체는 동일하지 않다. 연속2/3의 실제 Swift owner 연결을 추가 검증했다. 대체 사이즈 부분은 승인 batch 조회까지이며 SwiftUI 선택 상태를 검증하지 않는다. 3×3 실제 auth DB 비교, 모든 A–G fixture에 승인된 identity 바인딩은 준비 미완료이며 full 결과를 PASS로 만들지 않는다.

## 오류 주입·정리

32개 smoke 선택자에는 stale response, timeout, synthetic commit 후 응답 유실, 중복 submit, 삭제 실패/재시도, 취소, malformed delta, 비교 근거 없음이 포함된다. 실제 테스트가 어느 경계를 대체하는지는 CoreCoverage 표와 XCTest 이름을 따른다. 별도 `FitMatchReleaseTransportFaultTests`가 offline/403/429/500/timeout/malformed/cancelled를 6개 실제 mutation RPC 경계에 주입한다. 이는 실제 서버 장애가 아니라 가로챈 HTTP 응답/오류이며, 삭제 외 모든 화면/캐시 후속 상태까지 검증하지 않는다.

Runner 자체에는 통제된 FAIL/누락 상태/빈 test run/잘못된 DB 주소/빈 hash lock 테스트가 있다. 임시 디렉터리만 사용하며 앱·DB에 잘못된 값을 주입하지 않는다. 통제된 실패가 전체 종료를 nonzero로 만드는지 실제 unittest로 확인한다.

정답표/정책 파일은 이번 재개에서 바꾸지 않았다. 새 선택자와 테스트 입력 보정 이유는 PreparationChanges.md에 기록한다.
