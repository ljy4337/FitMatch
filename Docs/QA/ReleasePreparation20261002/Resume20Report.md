# 잔여20%까지 승인 후 — 준비 검증 결과

**부분 준비 완료: 앱 코드·실행기·자료의 대표 검사는 통과했으나, 실제 DB 인증·서버 승인 정답 연결·제품 정답 기준이 남아 있다.**

이번 범위는 원래 요청의 **자동 테스트 준비와 소규모 smoke**다. 대량 full, 실기기 검수, 출시 승인·배포는 하지 않았다. QA HEAD `086617f49cd19c8c3e2777e75efa820d7f886b5f` / `FitMatch-QA` / `Debug-QA` / 개발 `hnkplvyegonlhumlejst`. 운영 `aqhrupgjpmrtnystottx` 요청·변경 없음. 기존 dirty/untracked 보존, 이번 추가분은 테스트·자료·문서뿐이며 production Swift/UI/DB 계약·정책 변경, commit/push/merge 없음.

## 실제 결과

| 구분 | 결과 | 의미 |
|---|---|---|
| 단일 준비 smoke | **BLOCKED**, exit2; 보고항목71 PASS/3 BLOCKED | DB·정답 기준 누락을 성공으로 숨기지 않음 |
| QA 앱/테스트 빌드·발견·실행 | **PASS**,61메서드/매개변수 포함85회,0 FAIL/0 skip | 실제 Swift owner, 가로챈 HTTP/합성 remote, SwiftData 및 mounted 선택 상태 |
| 대표 실제 링크 수집 | **PASS**, 별도1테스트에서 M/U/Z 각1URL, 사이즈2/7/4 | ProductURLParserService 실제 수집; DB 저장은 아님 |
| 실행기·세션·자료 검사 | **PASS**,39개 | 고의 오류·결과 누락·위험 환경·원문 변조 탐지 포함 |
| 오프라인 DB 안전장치 | **PASS**,9개 | 인증/운영 대상 차단; 실제 사용자 격리 성공 증거는 아님 |
| 개발DB 읽기 | **PASS** | 프로젝트 정상 상태·공개 상품 구조·정확 receipt identity 연결 가능 수만 확인 |
| 인증 DB CRUD·A–H·정리·두 사용자 격리 | **BLOCKED** | 전용2계정 정상 세션과 검증 seed 미설정; 실제 DB 쓰기0 |
| 대량 full·실기기·Release archive | **NOT RUN** | 이번 준비 범위 밖 |

별도 focused17회와 최종 smoke85회는 겹치므로 합산하지 않는다. 앱전체 XCTest PASS나 출시점수로 확대하지 않는다.

## 이번에 보완한 것

1. **기록 숫자 복원 정답 검사:** 앱 엔진으로 정답을 만들지 않은 literal History 입력(기준50, 상품52, 차이+2, 점수90, 실측1개, coverage1)을 실제 hydrator로 저장하고 새 파일 기반 ModelContainer로 읽었다. 활성 옷 실측을61로 바꿔도 과거 기록50과 envelope가 유지된다. 계산정책 자체를 새로 승인한 것은 아니다.
2. **테스트 중단 정리:** 같은 상품의 다음 비교 전에 이전 run 소유 기록을 독립 조회로 확인하고 숨긴 뒤 새 tombstone을 확인한다. 잘못된 소유권·receipt·미확인 삭제는 다음 비교를 막는다. no-op에서 신규7실행 FAIL → 구현 후 전체focused17PASS를 확인했다. 실제 사용자 데이터나 제품DB계약 수정이 아니다. 이미 superseded된 과거 ledger/pending/응답유실의 모든 복구를 해결한 것은 아니다.
3. **자료 사실 확인:** 원문 해시/출처, 서로 다른 구조, 0값·단위누락·유니클로 등중심 소매·자라 신체표만 있는 경우 등27개 exact raw pointer를 검사했다. 원본을 canonical 또는 그룹 승인으로 승격하지 않았다.
4. **원래 범위 연결:** A–H와 연속동작1–10, 필요한 오류 경계를 실제 함수/선택자/상태/건수/새 조회/무관한 데이터/정답근거에 연결했다. [PreparationCoverage20.md](PreparationCoverage20.md), [requirement-coverage-v1.json](requirement-coverage-v1.json). 모든 오류×모든 화면 조합을 새 필수 작업으로 늘리지 않는다.

## 확보 자료와 정확한 한계

| 쇼핑몰 | URL | 실제 원문 fixture | 원문 실측표가 있는 fixture |
|---|---:|---:|---:|
| 무신사 |30|5|5|
| 유니클로 |30|25|23|
| 자라 |30|26|23|
| 합계 |90|56|51|

별도 malformed 합성fixture1개. 각 쇼핑몰20개는 **정상 후보**,10개는 경계 표본이며20개 모두의 정상 동작을 검증했다는 뜻이 아니다. 데이터69개 동결해시, 출처147건 검증. 실제 원문→서버 승인 비교 정답의3×3 연결은 아직 BLOCKED. 기존756개 합성 조합은 확장 명세이며 준비 완료를 위해 모두 지금 실행하라는 새 조건이 아니다.

개발DB read-only에서 상품 수 M24/U38/Z22를 확인했다. PROCESSED observation의 exact variant/size join과2개이상 사이즈 조건에 맞는 **receipt/variant 쌍**은 M47/U146/Z27이었다. 이는 테스트 seed 후보가 있다는 증거일 뿐, 현재 사용자 runtime·동일그룹 허용·실측 의미·비교 정답 검증이 아니다. 임의 latest observation이나 다른 size를 선택하지 않았다.

## 이번 요청에서 실제로 남은 일 — 담당

| 남은 준비 | 담당 | 막힌 이유 |
|---|---|---|
| 개발DB 등록→새 조회→수정→새 조회→삭제, 두 계정 격리 대표 실행 | 아스트라 | 전용2계정 정상 인증 없음 |
| 실제3×3방향·지원그룹·누락패턴의 exact seed/정답 연결, 인증 A–H 대표 실행 | 아스트라 | 인증 후 runtime/authorization으로 정확한 데이터 확인 필요 |
| 실제 중단 정리와 응답유실 재시도 확인 | 아스트라 | 정상 인증 필요; 증거 부족한 과거ledger는 안전하게BLOCKED 유지 |
| 테스트 계정 이메일 확인/정상 로그인 지원 | 사용자 도움이 필요할 수 있음 | 개인세션 추출·인증우회 없이 전용세션 확보 |
| 점수공식·반올림·동점의 제품기준 확정 | 사용자 결정, 근거정리는 아스트라 | 현재 구현 특성화 외 독립 승인 근거 미확정 |

현재 관측된 규칙은 항목점수 `clamp(round(100−5×절대차이),0…100)` → 가중평균 반올림, 동점은 가중실측차이 → 정확 UUID 순이다. 이를 손계산한 검사는 PASS지만 현재 구현이라는 이유만으로 제품정답으로 승인하지 않는다. 정책을 임의 변경하지 않았다.

**아이폰 공유/터치/실제 로그인 화면, 대량90URL/full, 출시 승인은 위 잔여 준비 항목에 포함하지 않는다.** 나중의 사용자 확인은 [UserChecklist.md](UserChecklist.md)2번에 분리했다. DB 확인이나 점수 손계산을 사용자에게 넘기는 뜻이 아니다.

## 재현 명령

이번 실제 실행:

```bash
FITMATCH_QA_SIMULATOR_ID=03BAF093-552E-4E53-ABFB-7DE0653BE676 FITMATCH_QA_DERIVED_DATA=/tmp/FitMatchEnvironmentBuild python3 scripts/release_qa.py smoke --output /tmp/FitMatchPrep20Smoke
python3 scripts/release_qa.py report --output /tmp/FitMatchPrep20Smoke
```

smoke와 report 모두 exit2. report는 같은 결과를 재집계하며 새 테스트 실행이 아니다. runner가 실행한 정확한 Xcode 명령은 `evidence/Resume20/smoke/app.log`, `live-parser.log`, `discovery.log`에 있다. 의도된RED xcresult `/tmp/FitMatchPrep20CleanupRed.xcresult`, GREEN `/tmp/FitMatchPrep20Focused.xcresult`; 각각exit65/0. focused12메서드/17실행. 원본xcresult는 /tmp, 로그/요약/tree/전후선택자/해시는 `evidence/Resume20/`에 보존했다.

필요 설정 후 **향후 본검사 한 줄 명령**:

```bash
python3 scripts/release_qa.py full
```

이번에는 실행하지 않았다. 전용인증·검증seed·정답기준이 없으면 전체PASS를 반환하지 않는다. 환경설정은 environment.example/SessionSetup.md/AuthenticatedCoverage.md, 자기run 데이터정리는 README의cleanup 명령을 따른다. live 수집동시성1, harness retry0, smoke timeout300초/프로세스420초 유지.

## 파일과 Git

신규 HistoryOracleTests, 기존 인증Support/LedgerSafety/Tests, Python data-inventory검사, 원문 사실audit JSON·요구사항coverage JSON/문서, 최신 보고·담당표·증거를 보완했다. 전체 신규test/fixture/도구/문서 목록은 [ChangedFiles.txt](ChangedFiles.txt). 신규자료 대부분 로컬untracked이며 원격반영 아님. `git status --short -uall`로 확인한다.

## 최종 판단

- 테스트 도구: 위 대표 경로는 실행되어 작동을 확인했다. 새 검사는 제품 결함 수정 건수로 세지 않는다.
- 제품 상태: 이번85회 범위에서 추가 실패는 없었다. 실제 인증DB·모든상품·실기기 정상 보장은 아니다.
- 준비 전체: **부분 준비 완료**. 외부 인증/서버 정답 연결/독립 정책기준이 구체적으로 남아 있다.
- 사용량: 마감 직전 주간24%잔여. 사용자20%경계에 도달하기 전에 독립 실행 가능한 이번 보완과 보고를 마쳤다.

최종 정적 검증 **PASS**: plan7파일·data69파일·이번검사소스8파일 해시, coverage19항목 JSON, 신규미추적소스 공백, `git diff --check`, 보호스크롤 무변경. 임시 수동해시확인 명령의 상대경로 기준 오류를 바로잡고 재실행했으며 데이터/기대값 변경은 없었다.
