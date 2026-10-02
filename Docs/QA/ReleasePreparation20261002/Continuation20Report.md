# 테스트 준비 재개 및 계산 기준 확정

**부분 준비 완료 — 점수 기준은 확정했고 실제 DB 인증·승인seed 연결은 남아 있다.**

## 실제 진행

- QA HEAD086617f/FitMatch-QA/Debug-QA/개발hnkpl. 운영 요청·변경, DB write, Auth계정 생성, 앱 기능/UI/산술코드 수정, commit/push/merge 없음.
- 개발 DB 정상 상태와6상품의 exact product/variant/size/sourceObservation 연결을 READ ONLY로 확인했다. 후보81개 수집기록/620size행/2488원본실측을 고정 추출했고 검증코드2개(고의오류4조건 포함)PASS. 이는 사용자권한 비교승인이나 방금 수집한 API원문이 아니다. [DevelopmentSeedPreparation.md](DevelopmentSeedPreparation.md).
- 사용자가 계산 알고리즘 결정을 위임했다. 에이전트는 1차 출시의 결과 안정성·기존 기록 보존을 위해 현재검증된5점/cm 가중점수, 두 단계 반올림, 점수→가중절대차→정확UUID동점 순서를 선택했다. `Docs/FitMatchMeasurementPolicy.md §4.4`가 이제 독립 제품 기준이다. 코드가 이미 이 기준과 일치하여 계산코드/숫자정답 변경은 없다. “새 알고리즘을 구현했다”거나 “실제착용 최적성이 입증됐다”는 뜻이 아니다.
- 정책3항목은RESOLVED. 이전미확정JSON/hash는evidence에보존했고기존oracle숫자/고정자료는불변이다. `score-policy-binding-v1.json`이 과거 특성화자료와 현행정책을 연결한다. [ScorePolicyDecision.md](ScorePolicyDecision.md).

## 이번 실행

| 검사 | 상태 |
|---|---|
| 실제Swift 점수·반올림·동점·기록복원 집중검사 | PASS10/10,0skip,exit0 |
| Python 실행기·세션·원문·신규seed검사 | PASS41/41,exit0 |
| preflight의도구/환경/해시/정책 | PASS |
| preflight전체 | BLOCKED,exit2:전용계정인증없음 |
| 실제인증DBCRUD/A–H/사용자격리 | BLOCKED |
| 새로운전체앱빌드·대량full·실기기 | NOT RUN |

이전85회 앱smoke·세쇼핑몰각1URL PASS는 이전 실행 증거이며이번10회와합산하지않는다. 이번 Swift는기존동일산술앱바이너리를 test-without-building으로 실행했다.

실제명령:

```bash
python3 -m unittest discover -s scripts/tests -p 'test_release_qa*.py' -v
python3 scripts/release_qa.py preflight --output /tmp/FitMatchPolicyDecision20Preflight
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch-QA -configuration Debug-QA -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchEnvironmentBuild -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests/FitMatchReleasePreparationTests -only-testing:FitMatchTests/FitMatchReleaseHistoryOracleTests -resultBundlePath /tmp/FitMatchPolicyDecision20.xcresult test-without-building
```

원본xcresult는/tmp,로그·summary/test tree·preflight는evidence/Continuation20/. 고의오류는메모리복사본만사용하여원본수정0. 신규자료와테스트는로컬untracked이며원격미반영.

## 남은 단계

1. 전용개발테스트계정2개의정상세션연결. 아이폰Supabase관리사이트로그인은이Mac의테스트앱세션이아니다. 현재 연결브라우저에는로그인된관리탭이없고전용인증변수도없다. [아이폰 준비 안내](PhoneAuthPreparation.md).
2. 인증후현재runtime/authority에서정확한observation과선택·대체size를검증해3×3방향·지원그룹·누락패턴정답자료완성.
3. 실제DB등록·수정·삭제·격리·비교/기록·정리의대표실행. 이미superseded된ledger와begin/complete응답유실복구는별도검증필요;근거없이삭제하지않는다.

위단계는에이전트담당이며사용자에게DB/수치검사를넘기지않는다. 대량full·아이폰UI검수·출시승인은원래준비범위밖이다. 향후본검사명령 `python3 scripts/release_qa.py full`은필수차단이남으면성공종료하지않는다.

마감직전주간21%잔여.20%중단기준전에현재독립가능작업과증거정리를마쳤다.
