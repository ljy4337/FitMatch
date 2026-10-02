# 계정 연결·남은 화면 검사 준비 — 부분 준비 완료

QA HEAD `086617f49cd19c8c3e2777e75efa820d7f886b5f`, FitMatch-QA / Debug-QA / 개발 hnkplvyegonlhumlejst. 기존 dirty/untracked 보존. 앱 제품 코드/UI/정책/DB 계약 변경, 실제 로그인·DB mutation, commit/push/merge 없음.

## 이번 추가 결과

| 대상 | 결과와 한계 |
|---|---|
| 세션 연결 도구 | 전용 개발 2계정의 정상 로그인만 허용. 기본 실행은 안내만 출력. 운영/관리자 키/동일 사용자/잘못된 저장 경로 거부. 실제 로그인 NOT RUN |
| Python 도구 검사 | 최종 runner23 + session12 = 35 PASS, exit0. 합성 HTTP 응답/오프라인 검사 |
| 신규 UI 검사 | 실제 Xcode build-for-testing exit0, 실행 대상 발견 exit0. 실제 앱 동작 실행 BLOCKED |
| preflight | 처음 sandbox에서 CoreSimulator 접근 BLOCKED. 호스트 권한 재조회는 simulator PASS. 최종 전체 exit2/BLOCKED: 정책3항목·전용 인증 없음 |
| 기존 앱 smoke | 앞선 Resume40Report의 48메서드/61회 PASS, 3사 각1URL PASS. 이번에 재실행한 것으로 집계하지 않음 |
| 대량 full / 실기기 | NOT RUN |

세션 도구의 최초 통합 재검사에서 34개 중3FAIL을 보존했다. macOS Python3.9에서 Darwin 임시 폴더 상수 이름이 없어 정상 경로를 거부했다. OS 상수 조회와 해당 회귀 검사를 추가했고, OS 환경까지 지우던 fixture를 수정했다. 최종35개 PASS. 제품 결함이 아닌 새 테스트 도구 결함이었다.

## 실제 명령

```bash
python3 scripts/release_qa_session.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_release_qa*.py' -v
python3 scripts/release_qa.py preflight --output /tmp/FitMatchContinuationPreflightHost
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch-QA -configuration Debug-QA -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchEnvironmentBuild -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests/FitMatchReleasePreparationTests -only-testing:FitMatchUITests/FitMatchReleaseAlternativeSelectionUITests -resultBundlePath /tmp/FitMatchContinuationBuild.xcresult build-for-testing
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch-QA -configuration Debug-QA -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchEnvironmentBuild -disableAutomaticPackageResolution -only-testing:FitMatchUITests/FitMatchReleaseAlternativeSelectionUITests -enumerate-tests -test-enumeration-style flat -test-enumeration-format json -test-enumeration-output-path /tmp/FitMatchContinuationDiscovery.json test-without-building
```

발견된 신규 selector: `FitMatchUITests/FitMatchReleaseAlternativeSelectionUITests/testExistingHistoryAlternativeSelection()` (enabled). 컴파일·발견은 실행 통과가 아니다. 기본 세션 안내 exit0은 로그인 성공이 아니다. 사용법은 SessionSetup.md.

## P03 범위 결정

private SwiftUI 상태를 흉내 낸 별도 모델이나 실제 호출되지 않는 reset 함수를 테스트해 전체 전환 PASS로 보고하지 않았다. 제품 코드 hook은 추가하지 않았다.

준비한 UI 부분 검사는 기존 검증 History 열기 → 승인된 추천 외 사이즈 선택·적용 → 내 옷 변경 버튼 존재 확인까지다. **변경 버튼을 누르지 않는다.** History의 해당 버튼은 새 flow의 observation ingestion/promotion으로 이어질 수 있어 읽기 전용이 아니다. 새 비교 생성·두 번째 후보 선택은 run ledger/정확한 계정 및 생성 ID/cleanup 연결 전에는 실행하지 않는다. 따라서 전체 P03과 부분 UI 실제 실행 모두 BLOCKED다. 앱 자체 배경 동기화까지 전면 읽기 전용으로 만든 테스트는 아니다.

## 남은 작업

1. 전용 개발 테스트 계정2개의 정상 세션과 검증된 exact 상품 seed 확보 → 실제 앱 Swift의 CRUD/비교/격리/read-back/정리 실행.
2. 점수 공식·항목별/최종 반올림·동점 기준에 대한 독립 정책 결정. 현재 방식 유지 여부를 사용자에게 질문했고 답변은 아직 없음. 정책 임의 변경 없음.
3. 실제 3×3 방향/A–G/누락 패턴의 DB 승인 정답 binding. synthetic756개 계획을 이 증거로 대체하지 않음.
4. 다른 사이즈→다른 내 옷→다른 사이즈 전체 화면 상태와 각 실패 후 UI 상태. 준비된 부분 UI 검사는 전용 로그인/기존 History 필요.
5. 본검사90URL/756조합은 이번 요청에서 실행하지 않음. 이후 명령 `python3 scripts/release_qa.py full`; 필수 BLOCKED가 남으면 성공 종료하지 않는다.

## 사용량 중단

최종 조회 주간60%사용/40%잔여 도달. 약속에 따라 추가 테스트 중단, 실행 중인 프로세스 없음. 사용자에게 재개 여부 질문. 이후에는 결과 보존만 수행했다. 이 보고서는 테스트 준비 또는 출시 전체 완료 선언이 아니다.
