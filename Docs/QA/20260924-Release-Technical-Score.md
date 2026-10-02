# 2026-09-24 최종 자동 회귀 검증 — 90/100

**실기기 E2E를 제외한 현재 기술 검증 점수: 90/100.**
아래 78점·66점 기록은 수정 전 이력으로 보존한다. 이 점수는 오류 발생 확률이나 App Store 합격 확률이 아니다.

## 점수

| 영역 | 점수 | 현재 근거 |
|---|---:|---|
| 상품·사이즈·원본 수집 | 15/20 | 파서 및 고정 응답 비교 검사 통과. 최신 공식 API 접근은 차단 |
| 옷장 저장·수정·삭제 | 25/25 | 관련 Swift 전체 검사 통과, SQL·배포 계약 확인 |
| 비교 승인·계산·결과 | 25/25 | 그룹 계약을 보완한 전체 비교 경로 및 회귀 검사 통과 |
| History 저장·동기화 | 10/10 | 관련 Swift·SQL 검사와 배포 계약 확인 |
| 인증·사용자 격리 검사 범위 | 10/10 | 관련 자동검사 통과. 전체 보안 감사 완료를 뜻하지 않음 |
| 배포 계약 재현·빌드 | 5/10 | 배포 SQL 내용 일치. 빈 DB 구성은 초기 테이블 누락으로 실패 |

## 수정한 내용

앱 실행 코드와 DB에는 이번 작업에서 변경을 가하지 않았다. 기존 테스트가 현재 정책과 실제 요청 구조를 검사하도록 수정했다.

- `FitMatchClosetSyncCoordinatorTests.swift`: 실제 로컬 변경을 만들어 서버 재조회 실패를 유발한다. 실패 상태 보존 검사는 유지하고, 변경 없는 옷의 불필요한 재조회·재전송 방지 검사를 추가했다.
- `FitMatchHeadlessUserJourneyTests.swift`: 상품 runtime, 옷장, 후보 응답 fixture에 필수 비교 그룹 정보를 보완했다.
- `FitMatchFinalReleaseProviderSnapshotTests.swift`: 세 쇼핑몰의 고정 응답을 현재 화면의 사용자 선택 비교 경로로 검증한다. 독립 조회는 병렬을 허용하고, 후보→eligible→begin→complete 순서는 검증한다.
- `FitMatchFinalReleaseHeadlessAcceptanceTests.swift`, `FitMatchFinalReleaseScenarioExecutionTests.swift`: 신규 등록의 브랜드·이름 생략 정책과 기존 옷 편집의 필수 입력 검사를 분리했다.
- `MyClosetSwipeDeletionInteractionTests.swift`: 삭제 버튼 부재를 검사하던 문자열 검사를 실제 삭제 action의 서버 권한 부재 시 로컬 보존 검사로 교체했다.

## 최종 실행

```bash
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchSameGroupRetry -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests -resultBundlePath /tmp/FitMatchClosureFinal.xcresult test
```

**PASS, exit 0: 907 tests = 865 PASS / 0 FAIL / 42 skipped.**
파라미터 확장 포함: 919 runs = 877 PASS / 0 FAIL / 42 skipped.
결과: `/tmp/FitMatchClosureFinal.xcresult`, 로그: `/tmp/fitmatch-closure-final.log`.

이전 실패 41건은 수정 후 전체 실행에서 재발하지 않았다. 중간 검사 실패는 step1 29건, step2 29건, step3 1건이었으며 마지막 1건은 독립 서버 조회에 순차 실행을 요구하던 검사였다. 미실행 42건은 live/corpus/QA 환경의 별도 opt-in 검사 등이므로 PASS에 포함하지 않는다. 실시간 쇼핑몰과 인증된 DB 전체 여정을 실행했다는 뜻은 아니다.

별도 Debug 앱 빌드: **PASS, exit 0**. 동일 project/scheme/destination에서 `-derivedDataPath /tmp/FitMatchClosureBuild -disableAutomaticPackageResolution -configuration Debug build` 실행. 로그 `/tmp/fitmatch-closure-build.log`. 실기기 설치·실행 검증은 아니다.

## 남은 10점과 해결 조건

1. **최신 쇼핑몰 응답 계약 (+5)**: 무신사 actual-size와 ZARA guide는 HTTP403, 유니클로는 HTTP2 오류 및 HTTP1 timeout. 접속 가능한 환경에서 공식 응답을 확보하고 실제 파서의 identity·사이즈·원본 실측·payload를 확인해야 한다. 현재 BLOCKED.
2. **DB 전체 재생성 (+5)**: 빈 PostgreSQL17에서 첫 migration이 `public.sources` 누락으로 exit3. 검증된 schema-only 초기 baseline과 필수 seed를 확보해 전체 replay와 배포 함수·권한·제약조건 대조가 필요하다. 테이블을 추측해서 만들어 통과 처리하지 않았다.

배포한 3개 migration은 원격 기록과 로컬 SQL의 MD5가 정확히 일치한다. 그러나 이것만으로 전체 DB 재현성을 보장할 수 없다. 원격 migration 129개 목록 및 해시는 `20260924-RemoteMigrationInventory.json`, 대응 관계는 `20260924-FiveRepairsMigrationManifest.md`에 기록했다.

실기기 화면·터치·재실행·두 기기 실제 여정은 사용자 E2E로 별도 관리하며 이번 점수에서 감점하지 않았다. commit/push는 수행하지 않았다.

---

# 2026-09-24 DB 적용 후 점수 갱신

**현재 기술 검증 점수: 78/100 (77.5 반올림), E2E 제외.**

아래 66점 보고서는 배포 전 기록이며 보존한다. 이번에는 배포한 세 계약의 범위만 재검수했다.

- Closet: 12.5/25 → 18.75/25. DB 거절·응답 누락은 보완됐지만 sync 테스트 두 건은 여전히 실패하므로 전체 검증 완료 아님.
- History: 5/10 → 10/10. 관련 Swift suite, 격리 SQL, 실제 배포 계약/권한 확인. 두 기기 E2E 성공을 의미하지 않음.
- 나머지 영역 점수 동일. 합계77.5. 전체 suite 재실행이나 미해결41실패 원인 분석은 이번 범위 아님.

이번 실행: 관련89 tests 중87 PASS/2 FAIL, exit65. 결과 `/tmp/FitMatchDBContractReaudit.xcresult`. 실패명과 명령은 Handoff 최신 항목 참조.
SQL linked/detail 및 History harness 각각 PASS exit0. 배포10함수 hash 동일, 앱 DTO 필드와 public RPC 경로 재대조.
현재 실제 DB raw snapshot은0건으로 실물 데이터 정합성 증거 없음. 인증 mutation/read-back와 실기기 E2E는 NOT RUN이며 점수 감점 대상에서 제외.

---

# FitMatch 출시 핵심 기능 기술 검증 — E2E 제외

## 결과

- 기준 HEAD: `3243e980bc0a304693d461e2e4279fc6f970c350`, connectDB.
- 검증 대상: 현재 checkout(기존 untracked SQL 포함) + 실제 연결 Supabase `hnkplvyegonlhumlejst`.
- 기술 검증 점수: **66/100** (가중 합계 66.25를 반올림).
- 이 점수는 사용자 성공률/버그 발생률/애플 심사 합격확률이 아니다. 제한된 검증 범위의 가중 평가다.
- 실기기 E2E는 점수 분모 및 감점에서 제외했다. v2 production 활성화는 별도 보류하기로 했으므로 감점하지 않았다.
- 판정: 로컬 수정은 진전됐으나 연결 DB와 계약이 맞지 않아 배포 가능한 핵심 기능 상태로 판정하지 않는다.

## 점수 기준

확인된 핵심 기능의 미해결 계약 결함은 해당 영역 최대 50%, 관련 자동 통합검증 또는 실제 API 확인이 막힌 영역은 최대 75%로 평가했다. 실행한 해당 범위의 검사가 통과하고 확인된 결함이 없으면 해당 범위 점수를 부여했다. 이는 E2E 정상 보장이 아니다. 원격 write/E2E를 하지 않았다는 이유 자체로 감점하지 않았다.

| 영역 | 배점 | 점수 | 근거 |
|---|---:|---:|---|
| 상품·사이즈·원본 수집 | 20 | 15 | 파서/원본 evidence 자동검사 PASS. 공식 live API 접근 차단으로 현재 응답 검증 공백 |
| 옷장 저장·수정·삭제 | 25 | 12.5 | 로컬 SQL/Swift 개선 검증 PASS지만 연결 DB linked update가 생성 전용 flag를 거절하고 explicit detail 응답 미지원 |
| 비교 승인·계산·결과 | 25 | 18.75 | authority/permit/measurement suites PASS. 기존 full-chain fixture 실패로 자동 통합검증 공백 |
| History 저장·동기화 | 10 | 5 | 로컬 tombstone tests PASS. 연결 DB에 새 sync RPC 없음, 삭제 전파 미완료 |
| 인증 세션·사용자 격리의 검사 범위 | 10 | 10 | AuthSessionStore suite 및 로컬 SQL owner 제한 회귀 PASS. 전체 보안 감사/실기기 로그인 점수 아님 |
| 배포 계약 재현·빌드 | 10 | 5 | build PASS. 새 migration은 untracked/미적용이며 Git-only 전체 replay 미검증 |

## 이번에 실제 실행한 검증

### Swift

```bash
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchSameGroupRetry -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests test
```

결과 **FAIL, exit 65**. 906 tests = 823 PASS / 41 FAIL / 42 skipped. 파라미터 확장 918 runs = 835 PASS / 41 FAIL / 42 skipped.

xcresult: `/tmp/FitMatchSameGroupRetry/Logs/Test/Test-FitMatch-2026.09.24_10-33-34-+0900.xcresult`.
JSON summary/tree: `/tmp/fitmatch-release-score-summary.json`, `/tmp/fitmatch-release-score-tree.json`.
로그: `/tmp/fitmatch-release-score-full.log`.

PASS suite: UniqloParserConcurrencyTests, MusinsaParserConcurrencyTests, ZARAParserConcurrencyTests, FitMatchRetailerAPIEvidenceTests, FitMatchServerAuthorityIntegrationTests, FitMatchComparisonPermitSequencingTests, FitMatchClosetTransportContractTests, FitMatchClosetDeletionTransactionTests, FitMatchComparisonSyncCoordinatorTests, FitMatchVNextContractTests, MeasurementPolicyConsolidationTests, ManualClosetUXRegressionTests, FitMatchAuthSessionStoreTests 등.

실패 분포: HeadlessUserJourney 26, FinalReleaseScenarioExecution 9, FinalReleaseProviderSnapshot 2, ClosetSync 2, MyClosetSwipeDeletionInteraction 1, FinalReleaseHeadlessAcceptance 1.

현재 HeadlessUserJourneyTests:3883 후보 fixture에 필수 group이 없다. 현재 coordinator:1390은 이를 정상적으로 fail-closed한다. 신규 수동 등록 브랜드 필수 기대도 현행 정책과 다르다. 이 대표 원인은 확인했지만 41개 전부를 동일 원인/무해한 legacy로 처리하지 않았다. 41개가 실제 사용자 버그 41건이라는 뜻도 아니다.

별도 Debug build: 동일 project/scheme/destination/derivedDataPath에 `-configuration Debug build`, **PASS exit 0**. 로그 `/tmp/fitmatch-release-score-build.log`.

### 일회용 로컬 PostgreSQL 17

각각 새 cluster를 생성하고 로컬 socket만 사용한 뒤 종료했다. 연결 Supabase/사용자 데이터에는 쓰지 않았다.

- linked_closet_snapshot_round_trip_LocalRegression: **PASS exit 0**.
- comparison_history_tombstone_sync_LocalRegression: **PASS exit 0**.
- retailer_exact_evidence_v2_preflight_LocalRegression: **PASS exit 0**.

로그: `/tmp/fitmatch-score-pg-60pfp29t/0/run.log`, `/tmp/fitmatch-score-pg-60pfp29t/1/run.log`, `/tmp/fitmatch-score-pg-60pfp29t/2/run.log`.

이 harness는 최소 owner/table fixture를 제공한다. 빈 DB에 전체 실제 migration을 replay한 증거가 아니다. 전체 replay **NOT RUN**; 기존 bootstrap/reproducibility 공백 유지.

### 현재 연결 DB — READ ONLY

프로젝트: FitMatch / hnkplvyegonlhumlejst / ap-northeast-2 / PostgreSQL17. 환경 이름만으로 Production 여부를 재분류하지 않았으며 이번 작업은 모두 읽기 전용이다.

1. public.fitmatch_vnext_update_closet_item → update_closet_item_with_group_for_swift → apply_linked_closet_snapshot_for_swift 경로 유지.
2. linked helper에는 `Server size snapshot is only supported for linked creation` 거절 조건이 남아 있음. 현재 Swift closetUpdatePayload:2704는 linked update에 use_server_measurements=true를 보냄.
3. list_closet_items는 source_measurements만 추가한다. 별도 source_measurement_snapshot 및 closet_detail_code_snapshot 응답 추가 migration은 미반영. base는 coalesce(snapshot,garment_type_code)의 closet_detail_code만 반환한다.
4. public.fitmatch_vnext_comparison_history_sync 및 private comparison_history_sync 함수 없음. Swift resolver:2428은 PGRST202에서 기존 active-list로 호환 조회하며 tombstones=[] 반환. 조회는 유지되지만 다른 기기 삭제 전파는 구현 완료 상태가 아님.
5. 새 20260924100000/101000/102000/103000 migration 파일은 git ls-files에 없고 untracked 목록에 있음. 준비/로컬검증/원격적용/Git반영을 구분해야 함.

### 실제 쇼핑몰 접근

- UNIQLO E484080-000 details: HTTP/2 transport error, HTTP/1.1 재시도도 timeout. **BLOCKED**.
- MUSINSA 7035474 actual-size: HTTP403. **BLOCKED**.
- ZARA 사용자가 제공한 v1=564228855 size-measure-guide: HTTP403. **BLOCKED**.

실제 응답을 확보하지 못했으므로 상품 원본 내용·실측 수를 현재 live PASS로 보고하지 않았다. 실패가 앱 결함인지 쇼핑몰이 비앱 접근을 제한한 것인지 이 호출만으로 판정하지 않는다. 같은 차단 경로를 30개 반복하지 않았다. **예정한 실제 상품 30개 검증은 이번에 완료하지 못했다.** 고정 실제응답 fixture 테스트와 live 확인을 구분한다.

## 출시 전에 남은 핵심 작업

1. 검증된 Task1/2/3 migration을 승인된 대상에 적용한 뒤 Swift와 DB 계약 재확인. 이번에 적용하지 않음.
2. 실제 owner 경로를 통과하지 못하는 자동 통합 fixture/테스트를 현재 정책에 맞게 복구하고 회귀검증. assertion 완화 금지.
3. 새 운영 DB 계획에 맞춰 Git 포함 파일과 bootstrap/seed를 정리하고 full replay 확인.
4. 접근 가능한 환경에서 실제 상품 응답 재확인. v2 shadow 활성화는 출시 필수 수정과 분리.

## 사용자 E2E — 점수 제외

새 앱 빌드와 DB migration 적용 상태가 맞춰진 뒤 실행한다. 이미 확인된 미적용 DB로 같은 실패를 반복 확인할 필요는 없다.

| 순서 | 조작 | 기대 결과 |
|---|---|---|
| 1 | 각 쇼핑몰 정상 상품 하나를 공유→불러오기 | 선택 상품/색상/사이즈가 맞고 완료 후 카드·다음 표시 |
| 2 | 실제 소유 사이즈로 등록→앱 종료·재실행 | 같은 사이즈와 원본 실측 유지 |
| 3 | 링크 옷 M→L 수정→재실행 | L 표시와 L의 실측이 함께 유지 |
| 4 | 기존 수동 옷의 세부 종류 편집→재실행 | 선택한 세부 종류 유지 |
| 5 | 같은 그룹 내 옷 선택→비교→기록 열기 | 선택 옷·추천 사이즈·결과가 맞고 기록 재열기 시 동일 |
| 6 | 같은 그룹 내 옷이 없는 상품 비교 | 이유 안내 후 종료, 무한 로딩/잘못된 대체 선택 없음 |
| 7 | 기록 삭제→다른 기기 동기화(가능할 때) | 삭제 전파, 다른 기록 유지 |
| 8 | 로그아웃·다른 계정 로그인 | 이전 계정 옷/기록 노출 없음 |

실기기 동작을 이 보고서의 점수에 가산/감점하지 않았다. 앱스토어 심사 메타데이터/개인정보 표기 감사도 이번 점수 범위가 아니다.

## 작업 안전성

앱 코드/테스트/연결 DB 수정 없음. 로컬 임시 PostgreSQL에만 합성 검증 데이터 생성. 보고서와 Handoff만 기록. commit/push 없음. 보호 스크롤 검사 PASS.
