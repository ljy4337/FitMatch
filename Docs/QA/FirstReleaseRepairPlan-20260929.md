# FitMatch 1차 출시 결함 수정 계획

> 실행자는 superpowers:executing-plans를 사용해 아래 3단계를 순서대로 수행한다. 이번 문서는 계획 확정이며 구현/DB 적용 승인이 아니다. commit/push는 별도 요청이 없으면 하지 않는다.

**Goal:** 과거 기록 복원 결함을 제거하고, 실제 결함을 숨기지 않는 최신 회귀검사 및 제출 준비 기준을 확보한다.
**Architecture:** 기존 서버 승인·불변 snapshot·Swift 재생 검증 유지. 현재 신규 점수/신뢰도 정책은 변경하지 않고 과거 완료 결과의 호환성을 분리한다.
**Tech Stack:** Swift/SwiftData/XCTest·Swift Testing/PostgreSQL.
**Spec:** FitMatchMeasurementPolicy.md, FirstReleaseAudit-20260929.md, FirstReleaseChecklist-20260929.md.
**기준:** connectDB db190a9+기존 dirty. 구현 시작 시 HEAD/변경 재확인.

## 범위와 금지

핵심 그룹 정책·후보 선택·신규 점수·canonical mapping·동일 상품 기록1개 정책·성능 병렬화·보호 스크롤 변경 금지. 기존 dirty hunk 보존. 과거 comparison row 일괄 변경/삭제 금지. Production은 READ ONLY; 필요한 migration이 확인되면 준비와 적용을 분리한다. 원본 직접 비교 전체 활성화 및 새 운영 DB 구축은 이 수정 묶음에 넣지 않는다.

## 1단계 — History 복원 호환성 (최우선, 출시 전 필수)

### 확정 수정 파일

| 파일 | 수정 위치/책임 |
|---|---|
| FitMatch/Services/VNextComparisonEngineAdapter.swift | engineVersion, analyze, reliability: 신규 결과와 완료 replay의 계산 버전 분리 |
| FitMatch/Services/FitMatchVNextContractValidator.swift | completedReplayEngineVersion 단일 상수 의존, validateCompletedReplay: 허용 버전 목록 및 row/evidence 버전 일치 검증 |
| FitMatch/Services/VNextHistoryCacheHydrator.swift | hydrateCompleted, completionMatches: 완료 snapshot 전용 replay 계약 호출, 저장된 신뢰도 보존 |
| FitMatch/Services/VNextCompletedReplayPolicy.swift (신규) | 검증된 과거 신뢰도 공식과 현재 공식을 좁은 내부 정책으로 관리. 저장값/근거로 유효성 검증하며 임의 추정 금지 |
| FitMatchTests/FitMatchVNextContractTests.swift | 신규/구버전 계약, 위조 reliability·metric·score·version 거절 |
| FitMatchTests/FitMatchComparisonSyncCoordinatorTests.swift | 기존 실패 fixture를 그대로 유지하여 old 완료 복원·tombstone·계정 전환 RED→GREEN |
| FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests.swift | 과거 불변 projection·재실행 회귀 |
| FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests.swift | 최신 기록1개·History→Closet 회귀 |

### 수정 로직

- [x] 현행 실패를 먼저 재현하고 과거 Git 계산 함수와 저장된 v1 결과를 읽기 전용 대조한다. 같은 v1 안에 여러 공식이 섞였으므로 모든18건을 한 공식으로 설명했다고 가정하지 않는다.
- [x] 신규 결과는 `fitmatch-ios-vnext-snapshot-v2`로 구분한다. 이는 **신뢰도 계약 버전**이며 RETAILER_EXACT 활성화가 아니다. 신규 신뢰도는 현재 count 공식 그대로다. 적용 전 배포 complete의 버전 허용 계약과 모든 replay consumer를 확인한다. 서버가 거부하면 이 변경을 단독 배포하지 않고 계약 보완을 별도 보고한다.
- [x] 기존 v1 완료 결과는 이미 출시된 코드에서 확인한 공식만 명시적 호환 집합으로 검증한다. 신규 count 공식으로 저장된 v1도 포함한다. 추천 사이즈·점수·가중치·차이·coverage·정렬·identity 검증은 유지한다. 신뢰도만 임의 범위1~5로 통과시키거나 저장값을 현재 공식으로 덮어쓰지 않는다.
- [x] 과거 공식이 증명되지 않는 row는 계속 명시적 복원 실패로 남기고 추가 근거 대상으로 보고한다. 날짜/쇼핑몰/값이 비슷하다는 이유로 버전을 추측하지 않는다.
- [x] Hydrator가 검증된 저장 신뢰도를 표시/보존하게 한다. 신규 계산 owner와 완료 replay owner를 분리하되 DTO 필드는 기존 engine_version을 재사용한다. 별도 스키마 추가는 기본 범위가 아니다.
- [x] old/current-v1/new-v2, 1/2/3/4항목과 coverage 경계, unknown version, 변조 evidence를 각각 검증한다. 기존 old fixture의 reliability2를1로 고쳐 통과시키지 않는다.

**완료:** History 단독 11실패의 복원 원인 해결; 과거 기록·최신head·삭제동기화·계정격리 회귀 PASS; 현재 신규 결과의 추천/점수/count 신뢰도 불변. 실제 사용자 row 쓰기 없이 확인 가능한 범위를 먼저 닫는다.

## 2단계 — 회귀검사 정비 및 raw0 보존 (서로 다른 원인, 별도 검증)

### A. 구형 테스트/abort runner

수정 대상:
`FitMatchTests/FitMatchTests.swift`, `BodyShapeRemovalTests.swift`, `ClosetPreviewMeasurementRegressionTests.swift`, `FitMatchFinalReleaseHeadlessAcceptanceTests.swift`, `CategoryLiveComparisonAuditTests.swift`.
History 관련 테스트는 1단계에서 우선 검증하며 그 실패를 테스트 정비로 숨기지 않는다.

- [x] 감사보고서 실패42개를 항목별로 현 정책·production caller와 대조한다. 이미 확정된 자동기준옷·최소2개·어깨1.2 기대만 우선 정렬한다. 나머지는 개별 판정 후 수정한다.
- [x] 자동선택 기대는 “서버 승인 후보 유지 + 자동선택 nil + 사용자 선택 전 begin/complete 없음”으로 대체. 1개 허용/0개 거절과 어깨1.5 등 현재 정책 경계를 검증한다. assertion 삭제·무조건성공·skip 추가 금지.
- [x] CategoryLiveComparisonAuditTests의 `ReferenceClosetSetupXCTests.testComparisonClassificationBoundaryPolicy` abort stack을 확인한다. XCTest에서 다른 Swift Testing 테스트 메서드를 직접 부르는 묶음 실행을 중단하고, 필요한 검증은 같은 production owner를 XCTest assertion으로 직접 검사한다. 단순 테스트 삭제 금지. 정확한 abort 원인은 stack 확보 전 확정하지 않는다.
- [x] 좁은 suite PASS 후 전체 FitMatchTests 재실행. 실행수 감소는 삭제/중복정비 근거를 모두 설명한다.

### B. MUSINSA raw0 보존

| 파일 | 변경 |
|---|---|
| FitMatch/Services/MusinsaActualSizeAPIParser.swift | makeParsedSize의 raw record 생성과 양수 canonical scalar projection 분리 |
| FitMatchTests/MusinsaParserConcurrencyTests.swift | 실제 parser seam에 양수+0+unknown 혼합 fixture 회귀 |
| FitMatchTests/MusinsaSizePipelineFixtures.swift | 필요할 때 위 fixture 지원; 기존 fixture 불변 |
| FitMatchTests/FitMatchSupabaseProductResolverTests.swift | raw0 observation 보존·canonical 비포함 계약 검증 |
| FitMatch/Services/MeasurementResolver.swift | 기존 raw 표시가0을 유지하므로 우선 변경 없음. 사용자에게 상태/사유가 없는 것이 재현될 때만 source display에 보완 |

- [x] 양수+0 fixture로 “원본행 보존 / 양수 canonical만 사용” 실패를 먼저 확보.
- [x] 유한0은 raw value/text/code/label/unit 그대로 ParsedMeasurement에 보존하고 valuesByName 등 비교용 scalar에는 넣지 않는다. finite/positive comparison gate 유지. NaN/문자값을0으로 꾸미지 않는다.
- [x] unknown 양수 항목도 유지. 수신→sourceDisplayRows→observation→격리 DB raw 저장→hydration 개수/값 확인. 현재 downstream이 이미0을 보존하면 수정하지 않는다.
- [x] 0만 있는 상품이 READY/비교 가능으로 승격되지 않는지 검증. 원문 body만 보관하고 완료라고 하지 않는다.

**완료:** 정상 양수 결과/점수/병렬 요청 불변,0은 원본 참고 상태로만 보존, 비교 제외. 음수·비숫자 전체 모델 재설계는 별도 정책범위로 남기며 이번 수정으로 모든 비정상값 보존 완료라고 보고하지 않는다.

**실행 결과:** 2026-09-29 전체881PASS/0FAIL/42미실행, Debug build/test PASS. raw 경로는 실제 Swift parser/observation/hydration 검사와 별도 격리SQL fixture로 검증했으며 인증 서버 E2E는 NOT RUN. 상세 [2단계 검증](Phase2RepairVerification-20260929.md).

## 3단계 — 제출 도구/출시 설정 및 최종 게이트

| 항목 | 대상 | 확정 방향 |
|---|---|---|
| archive 검사 구버전 고정 | scripts/audit-app-store-archive.sh | `<archive> <expected-version> <expected-build>`를 필수 입력으로 받아 앱/확장 모두 검증. 누락은 usage 실패. 실제 archive 값을 기대값으로 자동 대입하는 자기검증 금지. 1.1/8 하드코딩 교체 금지 |
| 도구 회귀 | scripts/tests/test-audit-app-store-archive.sh (신규) | 인수 누락/버전 일치·불일치/앱확장 차이 검사. 합성plist 검사는 실제 서명검증 PASS와 구분 |
| 공개 정책/지원 | FitMatch/Info.plist, Docs/AppStorePrivacyPolicyDraft-20260806.md, Docs/AppStoreReadiness-20260806.md, Docs/ReleaseNote.md | 실제 운영자/연락처/보관정책/HTTPS URL 제공 후 반영. 수집없음·기준옷 등 구형 내용 정렬. 가짜 URL/임의 연락처 금지 |
| 앱 내 안내 | FitMatch/Views/ReleaseInformationView.swift | 실제 문구·링크가 확정 정책과 다를 때만 수정. 동작 UI 전면 개편 제외 |
| 새 운영 DB | aqhrupgjpmrtnystottx | 현 상태로 전환 금지. 환경 선택 후 별도 복원계획. 이번 코드수정의 자동 포함 대상 아님 |
| 전체 원본 직접비교 | 정책/별도 개발 계획 | 현재 활성 범위 명시. 이번 History 호환 버전 변경으로 raw exact 활성화 금지 |

- [ ] 1·2단계 종료 후 전체 회귀와 Debug/Release 빌드 검증. 제출용 archive는 실제 제출 버전으로 검사.
- [ ] 체크리스트/지도(호출 경로 변경분만)/인수인계/감사보고서에 사실대로 기록.
- [ ] 실기기 담당 목록을 최신 빌드 기준으로 전달. 공유·로그인·History 새설치 복원·두기기 삭제·정확한 사이즈 수정·결과를 사용자가 확인한다.

## 최종 완료 조건

새 History 복원 결함 없음, 검증된 과거값 불변, 현재 정책 회귀 PASS, unexplained FAIL0(환경BLOCKED 별도), raw0 점수 유입0, 기존 dirty/보호스크롤 보존. 실기기·Production mutation·새DB복원·심사제출 미실행을 완료로 보고하지 않는다. 순수 검토만 한 이번 턴에서는 위 항목을 체크하지 않는다.

## 2026-09-29 1단계 실행 기록

- 사용자 “1단계를 모조리 해결하라” 승인으로 Phase1만 실행. 기준 HEAD db190a9, 기존 dirty 보존. 신규 엔진 v2는 신뢰도 count 공식 버전 구분이며 raw exact 활성화가 아니다.
- 배포 public complete wrapper 및 fitmatch_vnext.complete_comparison을 읽기 전용 확인: engine_version nonempty/길이128 이하, 별도 whitelist 없음. mutation 미실행.
- 저장 v1 34건의 count/coverage/reliability 집계는 Git dca8294 이전 공식 또는 현재 count 공식으로 모두 설명됨. 18건의 현재 공식 불일치에 대해 임의 허용 대신 명시적 과거 공식 호환 적용.
- VNextCompletedReplayPolicy 추가, adapter 신규버전 구분, validator 두 버전 허용/동일성 유지, hydrator 신뢰도만 버전별 검증. score/coverage/ranking/metric/identity 검증 유지.
- 기존 History 단독 RED:18건 중11FAIL. 첫 수정 후 확대4 suite:117건112PASS/5FAIL; History 기존11실패 해소. 남은 Headless5실패는 삭제/완화하지 않았으며 전체 suite PASS라고 보고하지 않음.
- 자동 승인 검토가 Headless 동일상품 fixture를 서로 다른상품으로 바꾸는 변경을 테스트 약화 위험으로 거절. 명령 미실행/파일 미변경. 안전한 대안으로 해당 테스트는 보존하고 이미 존재하는 최신head 정책 suite와 전용 replay/변조회귀를 실행.
- 기존 Headless 계약 정비는 2단계로 유지. 빌드·실행 및 실제 계정 E2E/배포 여부는 별도로 기록한다.

**1단계 최종:** 관련3 suite73/73 PASS(exit0,skip0). 기존 Headless2개 복수기록 기대와3개 기타실패는 테스트를 변경하지 않고2단계에 남김. Phase1 production 수정/전용 회귀 완료, 전체앱 E2E 및 Release/배포 NOT RUN.

## 3단계 실행 결과 — 2026-09-29

도구6case PASS, unsigned Release archive PASS. 제출 gate FAIL: 공개URL2개·서명2개 미충족. 공개정책 초안 정렬 완료, 실제 운영정보·서명·실기기 미완료. DB/핵심앱 코드 변경 없음. [명령과 상세 근거](Phase3ReleasePreparation-20260929.md). 이전3단계 미진행/Release NOT RUN 기록은 이 결과로 갱신하며 과거기록은 유지한다.
