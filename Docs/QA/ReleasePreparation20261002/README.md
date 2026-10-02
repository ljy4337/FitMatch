# FitMatch 1차 출시 자동 테스트 준비

**최근 재개:** [Resume15Report.md](Resume15Report.md). 개발 두 계정의 데이터 초기화 승인은 받았지만 자동 승인 검토가 관리자 SQL 변경을 차단하여 적용하지 못했습니다. 정상 인증도 미연결입니다. Apple 계정 자체는 테스트에서 제외할 이유가 없으며 비밀번호 로그인 도우미의 한계와 구분합니다. 아래 보고서는 각 시점의 실행 이력입니다.

**최신:** [Continuation20Report.md](Continuation20Report.md). 사용자 위임에 따라 점수·반올림·동점 기준을 확정했습니다. 이전 정책 미확정/사용자 결정 대기는 해소됐습니다. 실제 DB는 전용계정 정상 인증과 이후 seed 검증이 남아 있습니다. 아이폰 관리자 로그인만으로 Mac 테스트가 연결되지는 않습니다.

**현재 기준:** [Resume20Report.md](Resume20Report.md). 원래 요청의 준비+대표 smoke만 수행한다. 아이폰 수동 검사·대량 full·출시 승인은 이번 잔여 준비 목록에 넣지 않는다. 실제 DB 인증/정답 연결 및 독립 정책 근거는 미완료로 유지한다. 아래 이전 기록은 경과이며 최신 판정은 위 보고서를 따른다.

이 문서는 **준비 smoke**의 진입점이다. 전체 검사/출시 승인은 별도다. 현재 환경은 QA branch / FitMatch-QA / Debug-QA / 개발 `hnkplvyegonlhumlejst`. 기본 FitMatch 스킴은 운영이므로 이 테스트에 사용하지 않는다.

## 실행

저장소 루트에서, Xcode 및 Simulator 권한이 있는 터미널로 실행한다. Python3 표준 라이브러리만 사용한다.

```bash
python3 scripts/release_qa.py preflight
python3 scripts/release_qa.py smoke
python3 scripts/release_qa.py full
python3 scripts/release_qa.py report --output /tmp/FitMatchReleaseQA/<run-directory>
```

- **preflight**: QA branch/scheme/URL override, Swift/Xcode/Python, hash locks, URL 수, 정책 미확정, 공간, 실제 사용 가능한 시뮬레이터, 두 개발 테스트 계정 자격 확인. DB 쓰기 없음.
- **smoke**: preflight → 실행기 자체 검사 → 실제 Swift owner 대표 검사 → 실행 대상 발견 확인 → 실제 쇼핑몰별1URL ProductURLParserService → 설정된 경우 개발DB 계약 검사 → JSON/Markdown 보고. 정책/DB가 BLOCKED여도 독립 local 검사는 실행한다.
- **full**: preflight부터 자동 시작. 고정 broad suite+smoke union, manifest90 실제 URL, 준비된 DB 계약 smoke를 실행한다. 인증 Swift A–H와 synthetic 756 probe가 연결됐지만 실제 전용 인증/seed, 3×3 서버 정답, 일부 UI 연속 상태는 BLOCKED로 집계하므로 **현재는 full이 출시 PASS를 반환할 수 없다**. 부분 준비를 완성된 full로 오해하지 않는다. 이번 작업에서 full은 실행하지 않았다.
- **report**: 기존 run 결과를 다시 집계. 필수 ID 누락/FAIL/BLOCKED/NOT RUN/정책미확정은 0으로 종료하지 않는다. 과거 실행 결과를 새 실행으로 표시하지 않는다.

기본 출력은 `/tmp/FitMatchReleaseQA/qa-<UTC>-<UUID 일부>/`. 다른 위치는 `--output /원하는/새디렉터리`. 이미 파일이 있는 출력 디렉터리는 실행 전 거부한다. 중단된 실행의 결과를 새 증거로 재사용하지 않는다. xcresult 원본, 위생 처리한 로그, 실제 test tree/count, live parser 관측, DB ledger(있는 경우), `results.json`, `report.md`가 남는다. 장기 보존하려면 run 디렉터리를 별도 보관한다.

선택 설정:

```bash
export FITMATCH_QA_SIMULATOR_ID=<simctl로 확인한 실제 UDID>
export FITMATCH_QA_DERIVED_DATA=/tmp/FitMatchEnvironmentBuild
```

설정이 없으면 실제 `simctl` 목록 중 실행 중인 iPhone, 없으면 사용 가능한 iPhone을 고른다. 시뮬레이터 화면 반복 조작을 수행하는 UI suite는 이 실행기에 포함하지 않는다. 앱 모듈·SwiftData/UIKit 등을 실행하기 위해 Simulator test host는 필요하다. Swift 로직을 Python으로 재구현하지 않는다.

## 네트워크와 DB 안전

- 운영 및 위장 host, shell/TEST_RUNNER/SIMCTL_CHILD의 운영 URL override를 차단한다. DB harness는 추가로 두 dedicated user, authenticated role/issuer/UUID/expiry를 검증한다.
- DB 설정은 `environment.example`의 변수명과 DBPreparation.md 참조. 토큰을 이 문서·저장소·채팅에 기록하지 않는다. 기존 앱/개인 Keychain 세션을 훔쳐 테스트하지 않는다.
- 개발 DB 전용 두 테스트 계정의 active Closet가 비어 있어야 DB smoke가 시작된다. run UUID ledger를 요청 전에 저장한다. 생성1개와 그 행만 수정/재조회/삭제하며 사용자B격리도 검사한다.
- 로그는 credential/email redaction 후 저장한다. 샘플 상품 URL/실측은 QA 자료이며 개인 계정 payload와 구분한다.
- DB 응답이 불명확하거나 cleanup이 차단되면 새 데이터를 계속 만들지 말고 ledger를 사용한다:

```bash
python3 scripts/release_qa_db.py cleanup --ledger /tmp/<run>/db-smoke.json.ledger.json --output /tmp/<run>/cleanup.json
```

정리는 앱의 soft-delete RPC다. active run row0을 확인하지만 물리 tombstone/감사 기록을 hard delete하지 않는다. 기존 데이터 전체 삭제나 RLS 해제는 하지 않는다.

- 실제 parser는 URL을 순차로1개씩 실행하며 테스트기 차원 자동 재시도0. 앱 안의 기존 parallel HTTP/fallback은 유지한다. smoke 전체 live test 최대300초/프로세스420초, full7200초/프로세스7500초. 원래 앱 OCR/WebView timeout/후보 수는 변경하지 않는다.
- 별도3요청 HTTP collector는 DataInventory.md 참고. 그 HTTP200을 Swift parser/DB 성공으로 집계하지 않는다.

## 판정과 범위

| 증거 | 의미 | 증명하지 않는 것 |
|---|---|---|
| Swift synthetic-remote tests | 실제 action/coordinator/ViewModel/adapter의 상태·선택·계산·cache | 현재 DB deployment/RLS/실기기 |
| Archived raw replay | 실제 source JSON을 실제 parser에 투입 | 현재 live identity, 모든 수집 시나리오 |
| Live parser | 지금 대표 URL을 실제 전체 파서로 수집 | 상품 observation/Closet DB mutation |
| Authenticated RPC harness | 전용 계정 권한으로 개발 DB 계약·변경·재조회 | Swift 전체 버튼/화면 E2E |
| Runner unit tests | 누락/의도된 오류/위험 대상을 올바르게 차단 | 제품 기능 정상 |

PASS/FAIL/BLOCKED/NOT RUN을 각 결과에 유지한다. UNRESOLVED 정책은 BLOCKED. 실제 시험하지 않은756 조합 명세, 과거184성공,90 URL 확보를 실행 통과 수에 더하지 않는다. 기능별 상세 제한은 CoreCoverage.md에 명시한다.

## 고정 자료와 변경 관리

- data/SHA256SUMS: 원문/manifest/HTTP 관측 고정. 실행 중 raw fixture나 실패 표본을 바꾸지 않는다.
- plan-SHA256SUMS: 선택자·정책 정답표·oracle 고정. 검증에서 누락/변경을 발견하면 FAIL.
- 새 표본·정책 승인·기대값 변경은 새 version 디렉터리/manifest와 변경 이유를 남기고 재검토한다. 실패를 통과시키려고 원본/기대값/체크섬을 조용히 갱신하지 않는다.
- `smoke-selectors.json`: A–H+오류 경계+원문 replay 정확한 test ID. `full-selectors.json`: 추가 suite. `oracle.json`: 독립 손계산. `TestSpecification.md`: 정답 근거/변경되지 않아야 하는 데이터.

## 아직 준비 완료가 아닌 부분

1. 전용 개발 테스트 계정2개의 유효한 user credential이 없어 실제 DB 변경 검증 BLOCKED.
2. 점수 공식/반올림/동점 및 일부 선택·중복·기록 정책의 독립 승인 명세 미확정. 현재 구현 특성화와 정책 승인을 구분한다.
3. 연속2/3의 실제 Swift owner 체인은 추가·실행했다. 추가 mounted 검사로 다른 사이즈→다른 내 옷→다른 사이즈의 실제 SwiftUI 상태를 synthetic 응답으로 확인했다. 실제 인증 DB 전환과 물리 터치는 별도다. 실제 auth3×3/A–G/누락패턴 연결은 미완성이다.
4. 403/429/500을 포함한 7종 오류를 실제 SDK/앱 RPC 6개 경계에 주입하는 검사를 추가했다. 삭제는 로컬 commit 차단까지 검증하며, 나머지 mutation의 모든 UI/캐시 후속 상태 조합은 미검증이다.
5. 화면 버튼 연결/공유 확장/Apple 로그인/실기기 표시·제스처/네트워크 전환은 별도 사용자 E2E. 이 작업은 테스트 준비이며 해당 UI/제품 정책을 수정하지 않았다.

## 저장공간 확보 후 재검증

최신 결과: [ResumeReport.md](ResumeReport.md). 테스트 추가와 실행기 RED/GREEN 내역: [PreparationChanges.md](PreparationChanges.md). 개발 인증 준비: [AuthReadiness.md](AuthReadiness.md). 이전 결과는 evidence/에 보존한다.

## 미진행 검사 보완 최신 상태

[PendingTests.md](PendingTests.md), [PendingReport.md](PendingReport.md)를 먼저 확인한다. 실제 Swift 인증 경로 설정·검사 범위는 [AuthenticatedCoverage.md](AuthenticatedCoverage.md) 참조. 새 인증 검사는 build/discovery만 PASS이며 실행은 BLOCKED다. Swift ledger 독립 정리는 아래 cleanup 모드로 준비했다. 실제 인증 실행은 BLOCKED이며 위 Python cleanup은 Python ledger에만 적용한다.

## 잔여 40% 기준 재개 결과

최신: [Resume40Report.md](Resume40Report.md). 이전 무신사 0 표시 BUG 판정은 테스트 기대값 오류로 정정했다. 제품/정책 무변경. 실제 Task.cancel 재사용과 Swift ledger 안전장치를 포함한 48 methods/61 executions PASS. 실제 DB·독립 정책 근거는 여전히 BLOCKED.

중단된 **Swift** 인증 검사 ledger 정리(전용 2계정의 새 유효 세션 필요):

```bash
python3 scripts/release_qa.py cleanup --ledger /absolute/path/original-auth-swift.json.ledger.json --output /tmp/fitmatch-cleanup-new
```

cleanup은 본검사와 별도 결과이며 출시 PASS가 아니다. 원래 run UUID/계정/정확한 소유 증거를 확인한 행만 soft-delete/hide한다. 정책 미확정 상태에서도 이미 만든 자기 데이터 정리는 가능하다. 증거 부족·pending 비교·인증 실패·인터럽트는 BLOCKED/FAIL 보고서를 남긴다. 이 명령은 실제 DB로 실행 검증하지 않았고, 인증 없이 차단되는 경로와 오프라인 안전 helper만 실행했다.

## 최신 추가 준비 및 중단 상태

[SessionPreparationReport.md](SessionPreparationReport.md): 세션 연결 도구·새 UI 부분 검사 추가. 도구35개 PASS, UI build/discovery PASS·실행 BLOCKED. [SessionSetup.md](SessionSetup.md)는 기존 전용2계정을 정상 로그인하는 안전한 로컬 사용법이며 새 계정 생성/인증 우회가 아니다. [P03UIExecution.md](P03UIExecution.md)는 전체 선택 변경 중 일부만 준비했다. 이전40% 중단 기록이며 이후30%까지 재개 승인됐다.

## 최신: 잔여30%까지 재개

[Resume30Report.md](Resume30Report.md): mounted 선택 상태, 수기 계산경계5개, 저장 실패7종 후 로컬 상태, ledger guard7개. [AuthenticatedGapAudit.md](AuthenticatedGapAudit.md)의 중단 복구 계약 공백은 실제 인증 검사 전에 해결할 준비 항목이다. 물리 UI·실제 인증 DB·정책 승인·대량 full과 구분한다.

## 사용자가 직접 확인할 일

[UserChecklist.md](UserChecklist.md): 로그인 도움과 아이폰 핵심 동작만 한 장으로 정리했다. DB 검사·정답 데이터·계산 검증은 에이전트 담당이다. 체크박스는 아직 실행 완료 표시가 아니다.
