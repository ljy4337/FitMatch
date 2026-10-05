# FitMatch Release Gate

확정일: 2026-10-03. 이 문서는 개발·QA·승격의 장기 기준이다. 이번 기록은 새 자동 실행기 구축이나 현재 앱의 Release PASS를 의미하지 않는다. 실행 결과와 임시 차단은 `CodexSessionHandoff.md`에 기록한다.

## 브랜치와 승격

- `main`: 배포 기준. 일반 기능 개발을 직접 하지 않는다.
- `QA`: 작업 브랜치를 통합하고 배포 전 검증한다. 기능 개발 장소로 사용하지 않는다.
- 작업 브랜치: 최신 main에서 생성해 개발·수정·자체 검증한다. connectDB는 신규 개발 기준에서 은퇴했다.
- 흐름: main -> 작업 브랜치 -> 자체 검증 -> QA 통합 -> 필수 Gate PASS -> 검증된 변경을 main에 승격.
- main이 앞서면 다음 개발 전에 QA를 정상 병합으로 동기화한다. QA 고유 변경은 보존한다. 작업이 없는 정상 상태에서는 main == QA를 목표로 한다.
- 승격 대상 커밋과 변경 범위를 고정하고 실제 main에 들어갈 최종 조합을 검증한다. 선택 승격도 가능하지만 QA에서 검증한 조합과 달라지거나 병합 충돌을 해결하면 영향받는 검사를 다시 실행한다.
- 개발 중 dirty tree 검증은 변경 범위를 기록해 허용한다. 최종 승격 근거는 커밋된 clean tree에서 확보한다. 검증 후 관련 코드가 바뀌면 그 결과를 재사용하지 않는다.
- 기존 사용자 변경을 덮어쓰지 않는다. QA에서 발견한 제품 버그도 작업 브랜치에서 수정하고 다시 통합한다. force push와 history rewrite는 금지한다.

## 핵심 검증 범위

검사 전에 A-E별 정상 경로와 현재 중요한 실패·identity·권한·저장 회귀를 고정한다. 모든 오류 x 모든 화면 x 모든 쇼핑몰 조합을 자동으로 출시 조건에 추가하지 않는다. 기대값은 승인 정책에 근거하며 잘못된 구현에 맞춰 바꾸지 않는다.

| ID | 필수 사용자 기능 | 확인할 결과 | 코드 탐색 진입점 |
|---|---|---|---|
| A | 링크/직접 내 옷 등록·조회·수정·삭제 | 정보/사이즈/원본 실측, 서버 저장 후 새 조회, 수정 후 새 조회, 삭제 후 활성 조회에서 제거, 실패 시 성공 UI 금지, 재실행 일관성 | Behavior Map FLOW-CLOSET-LINK / MANUAL / MANAGE |
| B | 상품 비교 | 현재 API 파싱 -> 서버 그룹 -> 후보 -> 사용자 선택 -> authorization -> begin -> 계산 -> complete -> 결과. 동일 그룹/authority/exact identity 유지, 목록·상세 계산 근거, 추천 사이즈/매칭률/신뢰도/차이/저장 확인 | FLOW-PRODUCT-LOAD / COMPARE / CANDIDATES / COMPARE-BEGIN |
| C | 다른 사이즈 비교 | 현재 승인 session evidence의 정확한 대상/사이즈만 재사용, 선택 사이즈의 결과 표시, 같은 계산 정책, 재실행 History의 승인 evidence 복원 | FLOW-RESULT 및 RecommendationResultView |
| D | 비교할 내 옷 변경 | 후보 표시 후 사용자 선택, exact Closet ID, fresh authorization/begin/complete, 이전 결과·authority 잘못 재사용 금지 | FLOW-COMPARE / RESULT |
| E | 비교 상품을 보유한 옷으로 등록 | exact product/variant/size, 원본 실측 보존, duplicate/unknown 처리, authoritative 저장 후 성공, 새 조회·재실행 존재 확인 | FLOW-RESULT / CLOSET-LINK |

자동 내 옷 선택에 의한 상세 결과 생성은 금지한다. 비교 그룹·점수·가중치·신뢰도·추천 사이즈·retailer parser·UI를 Gate 정비 명목으로 변경하지 않는다. 실제 버그는 재현 -> 원인 확인 -> 회귀 테스트 -> 최소 수정 -> 재검증으로 처리한다. UI 변경은 사용자 명시 요청 규칙을 따른다.

## 증거 계층

| 계층 | 증거 | 판정 경계 |
|---|---|---|
| Level 1 Pure/Unit | 엔진/점수/가중치/신뢰도/DTO/identity/fixture/직렬화 | 현재 서버나 실제 화면 성공을 증명하지 않는다. Xcode test host를 사용해도 테스트의 의존성으로 분류한다. |
| Level 2 Integration | contract, authority, CRUD, begin/complete, History/cache, 저장·read-back | synthetic contract와 authenticated development DB를 구분한다. 실제 DB PASS에는 정상 사용자 RPC, 새 조회, 소유권 격리, 테스트 생성 데이터 정리 증거가 필요하다. 관리자 SELECT는 사용자 기능 PASS가 아니다. |
| Level 3 Simulator E2E | 실제 앱 화면의 A-E 버튼·선택·화면 연결 | 가능한 환경에서 현재 retailer API와 개발 DB 사용. fixture 화면 검증은 실제 인증 DB E2E와 별도다. 서비스 테스트만으로 버튼 연결을 PASS 처리하지 않는다. |
| Level 4 USER CHECK / NOT AUTOMATED | 실제 iPhone UX 체감·디자인·스크롤·애니메이션, Apple 계정/2FA/최종 제출 | 사용자 담당. Codex가 PASS를 만들거나 자동 기술 Gate의 blocker로 추가하지 않는다. |

필수인 것은 핵심 동작의 검증 결과다. 각 검사의 자동화 가능 여부와 대체 증거 범위를 미리 기록한다. 실행되지 않은 필수 검사를 실행 중에 선택 검사로 내려 전체 PASS를 만들지 않는다. 화면 연결을 검증하지 못했다면 해당 범위는 미검증으로 표시한다.

## 판정

- PASS: 해당 소스·환경·시나리오에서 실제 실행하고 기대 결과를 확인했다.
- FAIL: 실행 결과가 승인된 기대값과 다르다.
- BLOCKED: 인증·도구·공간·필수 입력 등 확인된 차단 때문에 유효한 검증을 완료하지 못했다.
- NOT RUN: 실행하지 않았다. 실행/발견 0건, 누락, 건너뛰기는 성공이 아니다.
- 전체 우선순위: FAIL -> BLOCKED -> NOT RUN -> PASS. 필수 자동 검사가 모두 PASS일 때만 전체 RELEASE GATE = PASS다. USER CHECK/NOT AUTOMATED는 이 집계에서 제외한다.
- 과거 수백 건 PASS를 현재 HEAD 결과로 재사용하지 않는다. source commit/dirty 범위, scheme/configuration, DB 환경, 명령, 실제 실행 수, 증거 경로를 남긴다.

## 실행 경로와 자동화 기준

QA 검증은 `FitMatch-QA`의 Debug-QA/Release-QA 및 개발 `hnkplvyegonlhumlejst`를 명시한다. 운영 scheme/URL override를 테스트에 사용하지 않는다. 인증은 정상 전용 사용자 세션을 사용하고 원래 데이터는 보존한다. DB/파괴 작업은 AGENTS의 기존 승인 규칙을 따른다.

기존 진입점: `python3 scripts/release_qa.py preflight`, `smoke`, `full`, `report --output <run-dir>`. 범위·인증 조건은 `Docs/QA/ReleasePreparation20261002/README.md`와 실제 실행 코드를 함께 확인한다. 기존 준비 smoke/full을 이 문서의 전체 Release Gate PASS로 자동 승격하지 않는다.

공식 로컬 실행: `python3 -B scripts/fitmatch_release_gate.py --output /private/tmp/FitMatchReleaseGate/<새 실행 폴더>`.
QA clean HEAD에서 branch/dirty/protected diff, 기존 실행기 회귀, archive 감사 회귀, 실제 QA build/unit/regression 및 쇼핑몰별 live parser, 정상 인증 개발 DB/Swift, 기존 온보딩/현재 화면 fixture 검사를 묶는다. 결과는 `release-gate.json`/`release-gate.md`와 원문 로그/xcresult로 남는다. 운영 쓰기·업로드·main 승격은 하지 않는다.
정상 인증/검증된 seed가 없으면 Integration은 BLOCKED다. 기존 live UI 도구는 전체 A-E 여정을 증명하지 않으므로 이 화면 여정은 아직 BLOCKED로 명시한다. fixture/UI owner PASS를 실사용 E2E PASS로 확대하지 않으며, 미구현·미실행 필수 항목이 남은 상태에서 실행기가 출시 PASS를 반환하지 않는다.

로컬 Mac Gate를 우선 사용할 수 있다. CI는 확인된 Xcode 환경에서 빠른 build/unit/regression부터 선택하고, 비용이 큰 live API/인증 DB/화면 검사는 필요에 따라 명시 실행한다. 필수 status check는 실제 실행 가능한 check만 등록한다. GitHub 보호 설정은 권한 확인 후 정상 PR/승격 경로를 유지하며 force push·branch deletion을 금지한다. 설정 불가는 `BLOCKED: GitHub repository administration permission required`로 기록하고 문서/로컬 검증은 계속한다.

## 현재 API와 문서 관리

현재 지원 API를 기준으로 개발한다. 미래 변경만을 이유로 추가 추상화·추론 fallback을 만들지 않는다. 현재 관측되는 timeout/403/미매핑/빈 실측 및 필수 응답 검증과 fail-closed는 유지한다.

AGENTS는 안정적인 규칙, 이 문서는 검증·승격 기준, MeasurementPolicy는 실측 제품 정책, 두 Map은 코드 탐색, Handoff는 실제 최신 상태를 소유한다. 과거 감사/테스트 문서는 날짜가 있는 증거이며 현행 정책을 덮어쓰지 않는다.
