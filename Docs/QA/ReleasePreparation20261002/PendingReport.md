> 후속 정정: 무신사 0 표시 제품 BUG 판정은 철회했다. 현행 정책에 맞춘 v2 테스트와 추가 안전장치의 최신 결과는 [Resume40Report.md](Resume40Report.md). 아래는 이전 실행 당시 기록이며 실패 증거를 보존한다.

# 미진행 검사 보완 결과 — 부분 준비 완료

기준: QA `086617f49cd19c8c3e2777e75efa820d7f886b5f`, FitMatch-QA/Debug-QA, 개발 `hnkplvyegonlhumlejst`. 운영 DB·제품 Swift/UI·정책 변경, 실제 DB 쓰기, commit/push/merge 없음. 신규 자료는 로컬 미추적 상태이며 원격 반영 아님.

## 실행 결과

| 명령/범위 | 결과 |
|---|---|
| `python3 scripts/release_qa.py smoke --output /tmp/FitMatchPendingSmokeChecked` | exit 2, 보고서 FAIL. 앱 컴파일 성공, 39 메서드 PASS / 1 FAIL / 0 skip. 매개변수 확장 51 PASS / 1 FAIL |
| 등록→새 조회→현행 async 수정→새 조회→삭제→새 조회 | PASS. 실제 Coordinator/action/SwiftData + synthetic remote |
| 현행 async 실측 수정→같은 상품 새 비교 | PASS. 새 실측 사용, 기존 결과 보존 |
| MUSINSA / UNIQLO / ZARA 각 1 URL | PASS. 실제 ProductURLParserService, 각각 2/7/4 사이즈. 별도 1 테스트 |
| 실행기 단위 검사 / DB 안전장치 | 18 PASS / 9 PASS. 잘못된 결과·누락·중복·운영 override를 차단 |
| 인증 Swift 검사 2개 | 빌드 및 발견 PASS, 실제 실행 BLOCKED: 전용 2계정과 검증된 상품 seed 없음 |
| full 90 URL / 756 조합 / 실기기 | NOT RUN. 대량 본검사 요청 범위 아님 |

## 발견 내용

1. **무신사 0값 행 표시 요구 불일치 — FAIL.** 현재 `MeasurementResolver.shouldShowSourceValue`는 MUSINSA 0을 남기고 `-`로 표시한다. 최신 사용자 요청의 유효값만 표시와 다르며 정책 문서도 구형 문구가 남았다. 고정 synthetic 입력으로 실제 owner에서 재현했다. 실제 쇼핑몰 모든 화면 E2E 결함으로 확대하지 않는다. 원본 저장 보존과 화면 필터는 별개다. 이번에는 제품/정책을 수정하지 않았다.
2. **신규 테스트 기대 단계 오류.** exact size 불일치가 adapter 이전 DTO decode에서 `conflictingProof("authorized_candidate_product_size_ids")`로 정상 거부됐는데 테스트가 나중 오류만 예상했다. 해당 정확한 타입/필드를 검증하도록 테스트만 보정했다. 무신사 0 기대값을 완화하지 않았다. 후속 좁은 재실행은 아래 기록한다.
3. **실행기 검증 강화.** 누락/중복 case ID, 과거 run ID, 정리 실패, 하위 검사 미통과를 상위 PASS로 인정하지 않는다. 격리 단위 검사 RED→GREEN 로그 보존.
4. 초기 신규 테스트 컴파일 오류 3차례는 생성자 인수와 throwing macro 사용 문제였다. 테스트만 수정 후 위 combined smoke에서 컴파일·실행됨. 이전 실패 로그 보존.

## 남은 작업

- P03: 실제 SwiftUI의 다른 사이즈·다른 내 옷 버튼 선택 상태. 실제 ViewModel/승인 batch 검사는 PASS지만 private 화면 state와 같다고 주장하지 않음.
- P05/P06: 전용 개발 2계정의 진짜 사용자 세션과 검증 seed를 설정한 뒤 실제 사용자권한 DB 실행. RLS 해제·관리자 mutation으로 대체하지 않음. Swift interrupted ledger 독립 재정리 도구도 미완료.
- P07: 실제 원문과 DB 승인에 연결된 3×3 방향/A–G/누락 패턴 정답. 756개 synthetic 실행 binding은 그 증거가 아님.
- P08: 점수 공식·반올림·동점의 최신 독립 정책 근거 미확정. 현재 구현 특성화 숫자 검사와 제품 정답 승인을 구분.
- P09/P11: 모든 UI 수명·실제 Task.cancel·공유·로그인·제스처·실기기 화면 확인.
- P10: 대량 full은 아직 실행하지 않음. URL 30개씩/실제 원문 56개/합성 1개 확보는 통과 건수 아님.

## 재실행

소규모: `python3 scripts/release_qa.py smoke`

본 검사(차단 요소 해소 후 사용자 실행): `python3 scripts/release_qa.py full`

`full`은 preflight부터 실행하고 필수 FAIL/BLOCKED/NOT RUN/정책 UNRESOLVED가 남으면 성공 종료하지 않는다. 지금은 full 전체 PASS를 보장하지 않는다. 설정 변수명은 environment.example 및 AuthenticatedCoverage.md 참조. 비밀값은 문서·로그·저장소에 넣지 않는다.

## 증거

`evidence/Pending20261002/`에 로그/결과를 보존한다. 원본 xcresult는 `/tmp/FitMatchPendingSmokeChecked/app.xcresult`. 이전 실행 보고서를 덮어쓰지 않았다.

## 좁은 재검사 및 사용량 기준 중단

`FitMatchReleaseMatrixTests/smokeRepresentativeCorpusCases()`만 QA 스킴에서 `xcodebuild ... test` 재실행(exit65). musinsa-to-musinsa-A-raw_zero=FAIL, musinsa-to-uniqlo-A-complete_shared_canonical=PASS, zara-to-musinsa-G-exact_identity_mismatch=PASS. 정확한 명령은 evidence/Pending20261002/commands.txt 참조. 전체 combined smoke를 수정 후 다시 실행한 것은 아니다.

주간 한도 50% 사용/50% 잔여에 도달하여 사용자 지시에 따라 추가 테스트를 멈추고 계속 여부를 요청했다. 실제 DB 검사와 위 BLOCKED 항목은 완료되지 않았다. 종료된 결과 보존·인수인계·보호 diff 확인만 마무리했다.
