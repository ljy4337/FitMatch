# 미진행 검사 목록과 실행 범위

**최신:** [Continuation20Report.md](Continuation20Report.md). 사용자 위임에 따라 점수·반올림·동점 기준을 확정했습니다. 이전 정책 미확정/사용자 결정 대기는 해소됐습니다. 실제 DB는 전용계정 정상 인증과 이후 seed 검증이 남아 있습니다. 아이폰 관리자 로그인만으로 Mac 테스트가 연결되지는 않습니다.

**최신 범위 정정:** 원래 요청의 자동 테스트 준비+소규모 smoke만 남은 일로 센다. 최신 실행은 [Resume20Report.md](Resume20Report.md). P10 대량 full과 P11 아이폰 검사는 이번 미완료 준비 항목이 아니다. 아래 과거 실행 수는 경과이며 최신 smoke61 methods/85 executions로 갱신됐다.

기준: QA `086617f49cd19c8c3e2777e75efa820d7f886b5f`. 이전 `ResumeReport.md`의 37개 메서드/49회 통과는 아래 미실행 범위의 증거가 아니다. 이번 실행 결과는 `PendingReport.md`와 evidence/Pending20261002/에 보존한다. 대량 `full`은 요청에 따라 실행하지 않는다.

| ID | 남았던 검사 | 이번 준비/실행 범위 | 현재 상태 |
|---|---|---|---|
| P01 | 등록→새 조회→현행 async 수정→새 조회→삭제→새 조회 | 실제 Coordinator/삭제 action, 동일 identity를 유지하는 synthetic remote 연속 검사 | PASS (실제 DB 아님) |
| P02 | 현행 async 실측 수정→같은 상품 재비교 | 과거 동기 edit 대체; read-back 후 새 비교 입력과 이전 snapshot 보존 확인 | PASS (실제 DB 아님) |
| P03 | 다른 사이즈→다른 내 옷→다른 사이즈의 화면 상태 | 실제 CompareFlowSheet/Result를 마운트하고 같은 버튼 함수를 호출. 새 내 옷 전환 후 선택/캐시 초기화·정확한 실측·새 승인 batch 확인. 고정 synthetic remote | PASS (물리 터치·실제 인증 DB 아님) |
| P04 | 3×3 방향·A–G·누락 패턴 756개 명세와 실행기 연결 | 원래 case ID를 유지한 synthetic owner probe; 대표 3개만 smoke. 실제 retailer/그룹 승인 증거로 승격하지 않음 | PASS (대표 3 probe, 실제 DB 비교 아님) |
| P05 | 실제 Swift+인증 DB 저장·수정·삭제·독립 사용자 격리 | 개발 전용 2계정, 새 클라이언트 read-back, 실행 ledger 및 소유 범위 정리. 코드 빌드·발견 PASS, 실제 인증 미설정 | BLOCKED |
| P06 | 실제 인증 DB 비교·다른 사이즈·내 옷 변경·보유 등록·기록 삭제 | 검증된 상품 seed로 실제 runtime/authorization/begin/complete/replay를 잇는 실행 경로. 코드 빌드·발견 PASS, 실제 인증/seed 미설정 | BLOCKED |
| P07 | 실제 3×3/A–G/누락 패턴의 서버 판정 정답 | 756행 synthetic probe 연결 완료. 실제 retailer 원문/DB 승인 seed binding은 없다. 신선한 검증 seed/권한 결과 필요 | BLOCKED |
| P08 | 점수 공식·반올림·동점의 독립 정답 | 추가 수기 경계5개와 기존4개 계산 검사 PASS. 정책 자체의 독립 승인 근거는 여전히 UNRESOLVED | BLOCKED (정책 승인) |
| P09 | 오류 후 각 화면/캐시 상태 및 실제 Task.cancel | 신규7종 저장 실패 후 새 로컬조회·무관한 옷 보존·동일 요청 재시도 PASS. 기존 취소검사 유지. 전체 화면 수명/실제 DB 응답유실은 미검증 | BLOCKED (잔여 범위) |
| P10 | 90개 URL·전체 원문·전체 조합 본검사 | 자료/진입 명령만 준비. 이번 대량 실행 금지 | NOT RUN |
| P11 | 기기 UI·공유·Apple 로그인·제스처 | 자동 앱 코드 검사의 범위 밖; 실기기 검증 필요 | NOT RUN |
| P12 | 실행 결과 누락/중복을 전체 PASS로 오인하지 않는 검사 | case ID 정확한 일치, 상태 누락/실패 전파, 격리된 오류 주입 | PASS (runner/자료/세션39개, DB guard9개, Swift ledger16회) |

## 이전 표시 결함 판정 정정

무신사 0값 `-` 표시는 현재 승인 문서·Git 변경과 일치한다. 앞선 zero-hidden 기대값은 후속 사용자 철회 근거 없이 무신사 예외를 빠뜨린 테스트 해석이었다. 기존 실패 로그와 v1 binding은 보존하고 v2에 정정 이유를 명시했다. 제품/정책은 바꾸지 않았으며 현재 대표 3개 probe 모두 PASS다. 상세는 Resume40Report.md와 ExpectationAudit.md.

## 안전 범위

- 운영 DB 요청/변경, RLS 완화, 개인 Keychain 세션 사용, 앱 제품 결함 수정 없음.
- 계정/검증 seed가 없을 때 DB 검사 결과는 BLOCKED이며 건너뛰기를 PASS로 처리하지 않는다.
- synthetic 입력과 실제 수집 원문은 별도이며, 같은 테스트에 provider 이름만 붙여 실제 3사 검증이라고 집계하지 않는다.
- 새 검사에서 제품 결함이 나오면 기대값을 바꾸지 않고 실패를 보존한다.

최신 재개 결과: [Resume30Report.md](Resume30Report.md). 이전40% 중단은 사용자30%까지 재개 승인으로 대체됐다. 실제 인증 DB는 전용2계정과 검증 seed가 필요하며, 중단 후 superseded 비교 정리는 AuthenticatedGapAudit.md의 계약 공백이 남아 있다.

## 이번 요청에서 남은 것만

1. **내가 계속할 일, 인증 필요:** 전용 개발2계정으로 실제 CRUD·사용자 격리 대표 검사 및 read-back/cleanup 확인. 기존 계정의 정상 인증 연결 도구는 준비돼 있다.
2. **내가 계속할 일, 인증 필요:** 실제 retailer3×3 방향과 지원그룹·누락패턴의 exact seed/서버 승인 정답 연결 및 인증 A–H 대표 검증. 90URL과56원문은 확보했지만 정상20개 확정 또는 DB 승인 정답은 아니다. 756개는 기존 합성 확장목록이며 사용자에게 전부 실행을 요구하는 새 조건이 아니다.
3. **사용자 판단 필요:** 현재 점수공식·반올림·동점 처리의 독립 제품기준. 현재 구현으로 고정한 손계산 검사는 통과했지만 이를 스스로 제품정답으로 승인하지 않는다.
4. **내가 확인할 일, 인증 후:** 중단 DB 정리 경로. 새 비교 전 이전 기록 정리는 offline PASS; 이미 superseded되거나 begin/complete 응답을 잃은 ledger는 증거 부족 시 BLOCKED로 멈춘다. 임의삭제/권한우회 없음.

정상 인증 전용계정이 없어 1·2·4를 지금 실행하지 못했다. 사용자에게 DB나 손계산 검사를 넘기는 뜻이 아니다.
