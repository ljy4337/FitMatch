# 1차 출시 테스트 준비 결과 — 2026-10-02

> 최신 재개 결과: [ResumeReport.md](ResumeReport.md). 아래는 최초 준비 실행의 보존 기록입니다. 저장공간 차단과 연속2/3 미실행 상태는 최신 보고서의 해당 범위로 대체됩니다.

**부분 준비 완료: 실행 가능한 대표 smoke는 검증했으나 전용 DB 계정·일부 정책·연속 시나리오 연결이 남아 있다. 출시 승인이 아니다.**

## 기준과 환경

- QA / `086617f49cd19c8c3e2777e75efa820d7f886b5f`. 시작 시 tracked diff0, 기존 untracked 조사/테스트자료 다수 보존. 브랜치 전환/commit/push/merge 없음.
- Xcode26.3(17C529), Swift6.2.4, x86_64 macOS15.7.7. iPhone17Pro Simulator iOS26.3.1, UDID `03BAF093-552E-4E53-ABFB-7DE0653BE676`.
- 실제 scheme `FitMatch-QA`, configuration `Debug-QA`, app `com.ljy4337.fitmatch.qa`. 개발 `hnkplvyegonlhumlejst`; 운영 접근/변경 없음.
- 외부 API GET/실제 Swift full parser 가능. DB 구조 읽기 가능. 사용자 권한 DB writes는 전용2계정 인증정보가 없어0건.
- 시작 여유공간 약1.4GiB; 재사용 DerivedData로 테스트 성공. 마지막 preflight 시 여유337MiB로 700MiB 보호 기준 미달 → **새 빌드 BLOCKED**. 기존 캐시/사용자 파일 임의 삭제 없음.

## 실제 실행

| 명령 | 결과 | 증거 |
|---|---|---|
| `xcodebuild … -scheme FitMatch-QA -configuration Debug-QA -only-testing:FitMatchTests/FitMatchReleaseConfigurationTests … test` | PASS, exit0,2 tests | `/tmp/FitMatchPreparationEnvironment-20261002.xcresult` |
| `python3 scripts/release_qa.py smoke --output /tmp/FitMatchPrepSmokeFinal` | 전체 BLOCKED, exit2. 앱32PASS/0FAIL/0skip. Live parser 테스트1PASS 안에서3URL 모두 성공 | [실행 결과](evidence/FitMatchPrepSmokeFinal/results.json), [앱 로그/정확한 명령](evidence/FitMatchPrepSmokeFinal/app.log), [실제 test tree](evidence/FitMatchPrepSmokeFinal/app-tests.json) |
| 같은 smoke의 runner unit tests | PASS11개. 고의FAIL/결과누락/빈실행/잘못된대상/빈checksum 실패 검증 포함 | [로그](evidence/FitMatchPrepSmokeFinal/runner-tests.log) |
| 같은 smoke의 DB guard tests | PASS9개. 실제 DB 검사가 아님 | [로그](evidence/FitMatchPrepSmokeFinal/db-runner-tests.log) |
| `python3 scripts/release_qa.py preflight --output /tmp/FitMatchPrepFinalPreflight` | BLOCKED, exit2. 최종 source+plan/data lock PASS, 정책/DB/디스크 BLOCKED | [결과](evidence/FitMatchPrepFinalPreflight/results.json) |
| `python3 scripts/release_qa.py report --output /tmp/FitMatchPrepSmokeFinal` | BLOCKED, exit2 유지 | 필수누락을 전체 성공으로 바꾸지 않음 |
| `python3 …/data/collect-http-smoke.py --collect --run-id network-20261002` | PASS,3 GET/HTTP200; 별도 HTTP수집 증거 | [원문·수집 보고](DataInventory.md) |
| `git diff --check` / protected scroll | PASS | 이번 변경은 production/UI/DB 스키마 수정 없음 |
| 대량 `full`, 실기기 E2E, TestFlight | NOT RUN | 이번 범위 밖 |

전체 exit2는 실패를 숨긴 정상종료가 아니다. DB 검사 미실행·정책 미확정 때문에 의도적으로 성공 종료하지 않는다. 32개는 기능 대표 자동 검사 수이며 8개 기능 전체 E2E 통과 수가 아니다. 90URLs/756명세/과거 검사 결과를 이번 통과 수에 합산하지 않는다.

## 기능별 상태

| 기능 | 대표 Swift 검사 | 실제 코드 사용 / 남은 한계 |
|---|---|---|
| A 저장·중복 | PASS | server-first submission/authoritative projection; remote scripted. 인증 DB NOT RUN |
| B 수정 | PASS | linked exact readback/manual stale receipt rejection; 전체 편집→비교 연속 연결 미완성 |
| C 삭제 | PASS | 실제 deletion action/transaction, 다른 대상 보존; remote scripted |
| D 비교 정답 | PASS(구현 특성화) | 실제 adapter+preview+completion payload. 손계산91/82/부분94. 공식 자체 제품 승인 UNRESOLVED |
| E 기록 삭제 | PASS | visibility action/sync, synthetic tombstone/new session |
| F 다른 사이즈 | PASS(복원 범위) | exact 승인2size batch 복원. 실제 화면 선택 전체 체인 미검증 |
| G 내 옷 변경 | PASS | fresh authorized recompare; 이전 snapshot 불변. F→G→F 전체 체인 미연결 |
| H 보유 등록 | PASS(부분 경로) | 정확 identity payload/등록 retry/save 경로. 등록옷으로 재비교 종단 체인 미연결 |
| 늦은 응답/취소/없는 데이터/응답유실 | PASS | 실제 ViewModel/action+제어된 transport. synthetic commit→timeout→동일 request재시도 포함 |

상세 호출 함수/RPC 및 사전조건·DB 기대 변화·영향없는 데이터·정답 근거: [CoreCoverage](CoreCoverage.md), [TestSpecification](TestSpecification.md), [oracle](oracle.json).

## 쇼핑몰 데이터

| 쇼핑몰 | URL 정상후보/경계 | 실제 원문 fixture | 이번 live 실제 파서 |
|---|---:|---:|---|
| MUSINSA |20/10|5|PASS1URL,2size/14raw|
| UNIQLO |20/10|25|PASS1URL,7size/28raw|
| ZARA |20/10|26|PASS1URL,4size/20raw|

원문56+별도 합성invalid1. 알려진 고유상품ID86개, malformed 입력1개, 나머지 URL variant차이는 명시. 모든30개가 현재 정상이라고 판정하지 않았다. 이번 raw replay는 U8size32/M4size24/Z4size20. Zara replay의 page shell은 합성, measurement body는 실수집이다. Live parser는 실제 전체상품 경로이지만 DB ingestion은 하지 않았다.

## 발견 결함과 테스트 도구 보정

**이번 대표 범위에서 확정된 제품 결함 없음.** 미검증 경로에 결함이 없다는 뜻은 아니다.

1. 새 oracle 테스트의 nested `#require`가 컴파일 실패 → 지역변수로 나눔. smoke1 build BLOCKED, 테스트 미실행. 생산 코드 문제 아님.
2. Swift Testing의 개별 선택자에 `()`가 없어 Xcode exit0/실행0 → 선택자 생성 수정. 실행0은 처음부터 BLOCKED. 발견JSON 내부error/선택자 존재도 검사하도록 보강. 초기 보고의 discovery PASS는 파일/exit만 검사한 도구 한계였고 최종보고에서는 사용하지 않는다.
3. Zara 합성 page에 parser가 요구하는 ProductGroup 상품명이 없어 raw replay1 FAIL → 정상 synthetic JSON-LD를 추가. 실제 원문/기대값/production 검사는 완화하지 않음. smoke3 31PASS/1FAIL → 최종32PASS.
4. 독립 리뷰에서 누락 결과·빈checksum·forwarded ProductionURL·full에서 smoke누락·URL결과 일부누락·DBFAIL분류 문제를 확인하고 실행기를 보강. 재현한 runner 테스트는 RED 후 GREEN. 제품 코드는 변경하지 않음.
5. 마지막 hash lock 포함 preflight와 runner11/DBguard9 검사를 다시 실행. 앱/파서 코드 및 테스트 입력은 최종 smoke 이후 변경하지 않았다.

## 미완료 및 필요한 것

- dedicated QA 계정2개와 유효한 일반 사용자 token/UUID/public key → [DB 준비](DBPreparation.md). 채팅에 비밀값 전달 불필요. 실제 DB 생성/수정/삭제0건. DB helper 자체는 사용자 권한 RPC이지만 Swift호출 증명은 별도다.
- 점수 공식/반올림/동점, 의도적 중복등록/임시사이즈·기록 처리 등 정책 공백은 임의결정 안 함. [정책 상태](policy-expectations.json), [명세](TestSpecification.md).
- 연속2/3, current async 편집→재비교, 실제 DB3×3 및 A–G/missing-pattern 바인딩, 403/429/500 전체경계 주입 미연결. 선언된756조합은 실행 가능한 완성된756테스트가 아님.
- 디스크 여유 확보 전 새 빌드 중단. 물리기기 Apple로그인/공유 확장/버튼·시트·스크롤 UI는 사용자E2E.

본 검사 명령은 **`python3 scripts/release_qa.py full`**. 다만 현재 준비 공백을 그대로 BLOCKED/nonzero로 보고하므로 출시 판단용 전체 PASS를 얻는 단계는 아직 아니다. 준비물 재확인은 **`python3 scripts/release_qa.py smoke`**.

모든 작업은 로컬 변경이다. 원격 Git/배포/DB migration 반영 없음. 신규 테스트·fixtures·스크립트는 아직 untracked이므로 향후 승인된 commit 때 포함해야 한다.
