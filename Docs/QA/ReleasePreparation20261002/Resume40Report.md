# 추가 준비·검증 결과 — 부분 준비 완료

기준: QA `086617f49cd19c8c3e2777e75efa820d7f886b5f`. FitMatch-QA/Debug-QA, 개발 hnkplvyegonlhumlejst. 기존 변경 보존. 제품/UI/DB/정책 수정·실제 DB write·commit/push/merge 없음. 자료는 로컬 미추적/미커밋이며 원격 반영 아님.

## 이번 실행

| 실행 | 결과 |
|---|---|
| `python3 scripts/release_qa.py smoke --output /tmp/FitMatchResume40Combined` | exit2/BLOCKED. 앱 컴파일 및 48메서드/61회 PASS, 0FAIL/0skip |
| 대표 실제 URL MUSINSA/UNIQLO/ZARA | 별도1테스트 안에서 각1URL PASS, 2/7/4사이즈. DB 저장 증거 아님 |
| 새 범위 집중 실행 `/tmp/FitMatchResume40Focused` | xcodebuild exit0, 10메서드/11회 PASS. 실제 Task.cancel 3메서드/4회, ledger helper6개, matrix smoke1메서드/3probe |
| `python3 -m unittest discover -s scripts/tests -p test_release_qa.py -v` | 최종23 PASS. 통합 smoke 당시20개였고 이후 보고 누락/오래된 binding 거부 테스트 추가 후23개 재실행 |
| 기존 DB guard Python suite | 통합 smoke에서9 PASS |
| `python3 scripts/release_qa.py cleanup --output /tmp/FitMatchResume40CleanupNoCredentials` | exit2/BLOCKED. 전용 인증/ledger 없음, 요청 미시작을 확인 |
| 실제 Swift 인증3selector | 빌드·발견 PASS / 인증 실행 NOT RUN |
| 대량90URL/756조합/실기기 | NOT RUN |

전체 BLOCKED는 전용2계정 인증 정보와 점수 공식·반올림·동점의 독립 승인 근거가 없기 때문이다. 실제 제품 테스트 실패와 검사 미실행을 혼동하지 않는다.

## 이전 결과 정정

**무신사 0값을 `-`로 표시하는 것은 현행 정책과 일치한다.** 이전 보고는 과거 모든 0행 숨김 요청을 후속 무신사 예외 결정에도 적용해 제품 버그로 성급하게 판정했다. MeasurementPolicy §3.1/3.5, commit5d78a42, Handoff 2026-10-01 대체 결정이 근거다. 이 판정을 철회한다.

기존 matrix-binding.json과 실패 로그는 보존했다. matrix-binding-v2.json에 정정 이유를 기록하고, 정확히 MUSINSA zero→비canonical `-` 1행, 다른 provider zero→표시 없음, raw0보존/점수 제외를 검사해3probe PASS. 제품/정책/원문 corpus/수치 oracle을 바꾸지 않았다.

## 보완한 검사·도구

- 실제 Task.cancel 검사 재사용: 수동 저장 read-back, 링크 authority 준비, ZARA page 대기/guide 취소. 실제 앱 owner를 호출하되 synthetic remote이며 모든 UI·네트워크 취소를 증명하지 않음.
- 중단된 Swift 인증 검사 정리: 원래 프로젝트/run/2계정/개별 client·server identity/marker 검증. 전체 read-only 소유권 점검 후 정확한 생성 데이터만 정리. 불명확한 pending 비교는 BLOCKED. 오프라인 guard6개 PASS, 실제 DB 정리 NOT RUN.
- 보고 도구 수정: cleanup 인터럽트·잘못된 receipt에도 최종 보고 보존, null/배열 receipt 차단. 대표 caseID가 같아도 다른 binding/corpus hash·mode는 FAIL. 각 수정은 격리 단위검사 RED→GREEN. 실제 통합 matrix receipt도 최종 hash 검증 재통과.

## 실제 DB 확인 경계

개발 프로젝트 ACTIVE_HEALTHY 확인. 제한된 catalog read-only 조회에서 UNIQLO E487688 및 ZARA549829596 행 존재 확인. 내부 classification_status만으로 최종 등록/비교 가능 여부를 판정하지 않았다. 최종 runtime 함수는 read-only transaction에서도 Authentication required로 차단됐다. 정상 사용자 세션 없이 auth.uid를 임의 주입하거나 우회하지 않았다. 따라서 이 두 행을 검증 완료 seed/정답으로 채택하지 않았다. 요청한 MUSINSA3개 goods ID는 해당 catalog 조회에 없었으며 다른 상품 존재/부재를 일반화하지 않는다. 실제 사용자권한 DB 저장·수정·삭제 0건.

## 남은 목록

1. 전용 개발 테스트 계정2개의 access/refresh 세션 및 검증된 exact 상품 seed. 실제 CRUD·격리·비교·보유등록·기록삭제 실행은 BLOCKED.
2. 점수 정책3항목의 독립 근거: `100−5×절대차`/최솟값 처리, 항목별+가중평균 반올림 시점, 최종 동점 시 UUID 순위. 현재코드 특성화 검사는 PASS지만 정책 승인으로 대신하지 않음. 상세 ExpectationAudit.md.
3. 실제3×3/A–G/누락패턴의 서버 승인 정답. 756synthetic binding은 실제권한 증거 아님.
4. 다른 사이즈·다른 내 옷의 private SwiftUI 선택 상태, 실기기 공유/Apple로그인/표시·제스처. 내부 ViewModel/승인 batch 검사와 구분.
5. 대량 full은 이번 작업에서 실행하지 않음. 표본30URL씩, real원문56+synthetic1 확보는 기존과 같으며 전체 수집/통과로 계산하지 않음.

## 명령

준비 재검증: `python3 scripts/release_qa.py smoke`

본검사(차단 해소 후): `python3 scripts/release_qa.py full`

Swift중단 데이터 정리: `python3 scripts/release_qa.py cleanup --ledger /absolute/path/original.ledger.json --output /tmp/fitmatch-cleanup-new`

현재 full은 미완료 항목이 남아 성공 종료할 수 없다. 원본 로그/JSON은 evidence/Resume40/, xcresult는 /tmp/FitMatchResume40Focused/ 및 /tmp/FitMatchResume40Combined/에 보존한다. 이번 결과는 출시 승인 아님.

## 마감 상태

주간 사용량55%사용/45%잔여로40%중단기준에는 도달하지 않았다. 이번 추가 범위의 대표 실행·보고를 마쳤으며, 남은 실제 DB/정책/UI 범위는 위에 명시했다. 해시·diff·보호 스크롤 확인 PASS. 보고 재집계exit2/BLOCKED.
