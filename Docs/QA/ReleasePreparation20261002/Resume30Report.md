# 잔여30%까지 재개 — 부분 준비 완료

QA HEAD `086617f49cd19c8c3e2777e75efa820d7f886b5f`, FitMatch-QA / Debug-QA / 개발 `hnkplvyegonlhumlejst`. 운영 DB 요청·변경, 실제 Auth/DB mutation, 제품 결함 수정, 비교 정책 변경, commit/push/merge/deploy 없음. 기존 dirty/untracked 변경을 유지했다. 이번에는 실제 화면 상태 검사를 위해 두 View에 nil-default DEBUG 관찰·transport 주입을 추가했고 기존 버튼의 inline 동작을 동일 private 함수로 추출했다. 외형·문구·제스처·navigation 동작은 변경하지 않았다.

## 결과

| 검사 | 실제 실행 결과 | 증거 범위 |
|---|---|---|
| 단일 smoke | 전체 **BLOCKED**, exit2; 집계70 PASS /3 BLOCKED | 필수 미완료를 성공 종료하지 않음 |
| 앱 빌드·발견·실행 | **PASS**, 56메서드 / 매개변수 포함75회, 0 FAIL/0 skip | 실제 앱 Swift owner, synthetic remote와 mounted view |
| 실제 쇼핑몰 수집 | **PASS**, 별도1test에서 무신사·유니클로·자라 각1URL, 사이즈2/7/4 | 실제 ProductURLParserService, 서버 저장은 아님 |
| Python 실행기·세션 | **PASS**, 35개 | 통제된 오류/위험 대상/증거 누락 검출 포함 |
| 오프라인 DB 안전장치 | **PASS**, 9개 | 운영 차단·자격/대상 검증, 실제 RLS 증거 아님 |
| 개발 DB 함수 정의 읽기 | **PASS** | 현재 history/current-head/tombstone 계약만 확인 |
| 인증 DB CRUD·A–H·사용자 격리 | **BLOCKED** | 전용2계정 정상 세션 및 검증 seed 미확보 |
| 점수 정책의 독립 승인 근거 | **BLOCKED** | score-formula, rounding, tie-break UNRESOLVED |
| 대량 full·실기기·TestFlight | **NOT RUN** | 이번 준비 범위 밖 |

## 이번에 닫은 준비 공백

1. **화면 선택 연속 동작:** 실제 CompareFlowSheet와 Result를 UIHostingController로 마운트. 같은 버튼 함수로 첫 내 옷 → 다른 사이즈 → 다른 내 옷 → 다른 사이즈를 실행한다. Result subtree가 실제 사라지고 새로 나타나는지, 이전 selected ID/cache/실측이 섞이지 않는지 확인했다. 물리 터치·화면 배치·접근성 검사가 아니며 가짜 reset state로 대체하지 않았다.
2. **독립 손계산 경계5개:** 항목별 .5 반올림, 최종 .5 반올림, 0/100점, 동점의 가중차이→UUID 순서, 잘못된 음수 absolute evidence 거절. 앱 함수를 호출해 정답을 생성하지 않았다. 현재 공식의 특성화이며 제품 정책 승인으로 승격하지 않는다. `oracle-boundaries-v1.json` 참조.
3. **저장 실패 후 상태7종:** 실제 등록 action → 실제 SDK → 가로챈 HTTP. offline/403/429/500/timeout/malformed/cancelled 오류 뒤 신규 로컬 저장과 projection이 없고 기존 옷이 보존된다. 두 번 재시도의 wire JSON과 exact IDs가 같다. 서버 commit/응답유실·실제 Task.cancel은 별도 범위다.
4. **중단 복구 안전 검사:** superseded 완료 기록이 active 목록과 tombstone에 모두 없을 때 정리 검증이 BLOCKED로 닫힘을 추가해 ledger7개 PASS. 정상 실행의 마지막 정리 성공이나 실제 중단 복구 성공으로 해석하지 않는다.

## 발견과 수정

최초 focused 명령은 exit65: 14메서드 중13PASS/1FAIL, 매개변수 포함31PASS/1FAIL이었다. 앱은 begin/complete/저장/결과 onAppear를 완료했지만 새 테스트가 History용 immutable reference ID를 원래 Closet ID로 오인했다. 기존 `referencesClosetItem(clientItemID:)`와 실제 화면의 projected size ID를 쓰도록 **테스트만** 보정했다. 기대한 exact server size, 원본 내 옷 identity, 실측값 검증은 유지했다. 최초 실패 증거를 보존했고 재검사 mounted1+ledger7=8PASS(exit0), 최종 smoke75회PASS다. 제품 버그 수정 건수로 세지 않는다.

확인한 추가 준비 제한: 같은 상품의 이전 완료 비교는 최신 head만 반환하는 history에서 빠지지만 삭제 tombstone도 없다. 중단 뒤 ledger를 복원하는 정리 도구는 이전 행의 소유권을 현 read API로 확인하지 못해 BLOCKED다. 실제 DEV 정의 읽기로 소스와 대조했다. 삭제로 추측하거나 소유권 guard/RLS를 약화하지 않았다. `AuthenticatedGapAudit.md` 참조. 이번에 실제 사용자 데이터 오류를 재현한 것은 아니다.

## 실제 명령과 원본

```bash
python3 -m unittest discover -s scripts/tests -p 'test_release_qa*.py' -v
python3 scripts/test_release_qa_db.py -v
python3 scripts/release_qa.py preflight --output /tmp/FitMatchResume30Preflight
FITMATCH_QA_SIMULATOR_ID=03BAF093-552E-4E53-ABFB-7DE0653BE676 python3 scripts/release_qa.py smoke --output /tmp/FitMatchResume30Smoke
```

앞의 Python 둘은 exit0, preflight/smoke는 필수 차단을 반영해 exit2다. 정확한 Xcode 명령은 `evidence/Resume30/commands.txt`와 smoke/app.log, live-parser.log, discovery.log에 보존한다. xcresult 원본은 `/tmp/FitMatchResume30Focused.xcresult`, `/tmp/FitMatchResume30MountedLedger.xcresult`, `/tmp/FitMatchResume30Smoke/`에 있다. 요약·test tree·로그·원문 관측·실패 증거는 프로젝트 `evidence/Resume30/`에 복사했다. 통과 수를 여러 실행끼리 더하지 않는다.

## 준비 자료 / 미완료

- 기존 URL manifest 쇼핑몰별30개/총90개와 원문56개+합성1개를 유지했다. 이번 새 대량 수집·756조합 본검사는 하지 않았다. 대표3 synthetic probe PASS를3×3 실제 DB 승인 증거로 확대하지 않는다.
- 전용 개발2계정의 정상 인증과 정확한 product/variant/size/observation seed가 필요하다. 실제 DB로 확인한 것은 함수 정의이며 CRUD/격리는 mock 결과다.
- 실제3×3/A–G/누락 패턴 서버 정답 binding, 중단 복구 계약, 독립 점수정책 승인, 전체 실패 후 UI 수명 경계는 남아 있다.
- 실행 후 app/extension 공유, Apple 로그인, 표시/터치/제스처 및 체감 속도는 기기 검증 필요.
- 테스트·데이터·실행기 대부분 로컬 미추적 파일이다. `git status` 설정이 untracked=no라 기본 요약에 숨겨진다. `git status --short -uall`로 확인해야 한다. 원격 Git 반영은 **NOT RUN**.

본검사 진입 명령은 `python3 scripts/release_qa.py full`. 필수 BLOCKED가 해결되기 전에는 이 명령도 전체 PASS를 반환하지 않는다. 지금 대량 실행하라는 권고가 아니다. 준비 상태는 **부분 준비 완료**다.

## 사용량 및 마감

최종 확인69% 사용/31% 잔여. 사용자 기준30%에 도달하기 전에 이번 소규모 검증과 보고를 마쳤다. 실행 중인 테스트 없음. 다음 실제 인증 DB 실행은 위의 전용 계정·정확한 seed·안전한 중단 복구 준비가 필요하다. diff 및 보호 스크롤 검사 PASS.
