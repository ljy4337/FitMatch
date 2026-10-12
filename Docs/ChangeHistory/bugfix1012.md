# bugfix1012 변경 이력

- 작업일: 2026-10-12 (Asia/Seoul)
- 브랜치: `bugfix1012`
- 분기 기준: fetch 후 `2d01ea4cc0dd245f9406a9f3e80e2f50711d485d`. 기존 local/remote bugfix1012와 최신 origin/main이 동일한 것을 확인했다. 기존 브랜치를 재생성하거나 reset하지 않았다. 작업 시작 시 clean.
- QA: `1580aa358486c6dc2a24fbd51d3c550059667545`, main 대비 QR 관련 2 commits(`5606119`, `1580aa3`), 9 files. QA/main merge·commit·push·배포 없음.
- 기존 Handoff의 과거 승인·적용 기록은 이번 신규 recovery SQL의 승인이 아니다.

## BF1012-01 — 사이즈표 복구와 서버 비교

브랜치: bugfix1012 · 작업일: 2026-10-12

### 계획 / 조사

기존 완료 action은 로컬 선택 ID만 설정했다. 현재 코드에서 재확인했고, 실제 기존 action을 호출한 최소 의존성 probe에서 서버 저장 없이 완료되는 것을 FAIL로 재현했다. frozenProductObservation 재전송 방식은 사용하지 않는다. 기존 수동 Closet 저장 계약은 exact Closet identity를 대상으로 하며, 쇼핑 상품의 사용자 전용 복구 identity·승인·snapshot 연결을 제공하지 않아 별도 최소 계약이 필요했다.

### 실제 변경 / 대상 파일

- `FitMatch/Services/FitMatchUserSizeRecovery.swift`: owner/request/product/variant/official-or-user-size/observation/source/raw rows와 exact receipt DTO.
- `FitMatch/Services/SizeTableRecoveryFeature.swift`, `FitMatch/Views/SizeTableRecoveryView.swift`: 비교 완료는 비동기 저장·검증 성공 후만 실행. 실패 시 입력/화면 유지. 저장 중 중복·입력 변경 방지, 닫기 취소. 사진 전송 시작 전 context/user를 캡처하고 전후·취소를 검증하며 화면 종료/새 사진 선택 시 작업 취소. 기존 Closet 로컬 선택은 별도 action으로 유지.
- `FitMatch/ViewModels/ShoppingProductViewModel.swift`: 불변 retailer observation 보존, 같은 요청 UUID로 재시도, 편집 canonical과 OCR 원문 분리, 새 runtime 적용, 이전 permit/candidate/recommendation 무효화. 다른 상품·계정·취소 후 응답 거절. 명확한 입력 거절만 수정한 새 요청을 허용한다. 임의 서버 semantic conflict를 지우지 않는다.
- `FitMatch/Views/CompareFlowSheet.swift`: sizesRequired/measurementsRequired 모두 복구 경로, 이전 foreground permit/후보/선택 폐기 후 기존 사용자 선택→begin→complete 재사용.
- `FitMatch/Services/FitMatchServerAuthorityCoordinator.swift`, `FitMatch/Services/FitMatchSupabaseProductResolver.swift`, `FitMatch/Services/FitMatchVNextDTOs.swift`: save→독립 get→fresh runtime→정확한 사용자/상품/variant/size/요청/실측/출처 검증. 공식 추가 실측과 원본 raw rows는 보존하며 사용자값을 공식 출처로 표기하지 않는다.
- `FitMatchTests/FitMatchUserSizeRecoveryContractTests.swift`, `FitMatchTests/FitMatchUserSizeRecoveryTests.swift`: 실제 DTO/coordinator/VM 및 injected comparison 여정 회귀. 지연 사진 전송의 context/account/cancel 거절과 정상 전송 허용을 실제 production action으로 검증. 기존 `FitMatchFinalReleaseProviderSnapshotTests.swift`의 로컬 선택 테스트는 Closet용으로 이름/설명 분리.
- `supabase/sql/bugfix1012_user_size_recovery_{Apply,Verify,Rollback}.sql`, `supabase/sql/tests/bugfix1012_user_size_recovery{.mjs,_baseline.sql,_tables.sql}`: 준비한 서버 계약과 격리 회귀.

### 서버 경계 / 준비 SQL과 적용 SQL

**추가 계약**: 사용자 소유 불변 `user_size_recoveries` + active pointer, save/get RPC. 같은 owner/request의 다른 payload는 거절하고, 응답 유실 재시도는 동일 receipt/size를 반환한다. 오래된 요청 재시도가 새 active pointer를 되돌리지 않는다. 공식 size가 없으면 서버 발급 `USER_RECOVERY` identity를 쓴다.

**재사용 계약**: 기존 canonical context, 후보, authorization, begin, complete, History. 비교 snapshot에는 사용자의 recovery provenance를 보존한다. 기존 official recommended FK는 유지하고 recovery 전용 FK/완료 검증을 추가한다. 공용 상품/실측/매핑, 다른 사용자값, 점수/그룹 정책을 수정하지 않는다.

- 준비 대상: 개발 DB `hnkplvyegonlhumlejst` (FitMatch, 기존 FitMatch-QA 빌드 대상). 읽기 전용 project/catalog/function 확인만 수행.
- 실제 적용 SQL: **없음**. 개발 신규 적용 **BLOCKED — 승인 필요**.
- 운영 DB `aqhrupgjpmrtnystottx`: 변경 없음, 적용 대상 아님.
- Apply: 알려진 현재 함수 hash/constraint guard, transactional patch와 기존 정의 backup. 정의가 바뀌었으면 중단.
- Verify: RLS/ACL/FK/함수 hash를 읽기 전용 검증. 사용자 raw payload 조회 없음.
- Rollback: 원래 정의/권한 복원 준비. 수락된 recovery가 이미 있으면 데이터 손실을 피하려고 중단하며, 별도 보존 계획이 필요하다.
- 기존 classification/semantic conflict 안전 gate는 유지한다. 미해결 서버 semantic conflict는 복구 입력만으로 강제 해제하지 않는다.

### 검증

최종 실행 결과는 BF1012-06 표와 evidence에 기록한다. 로컬 선택 probe·fixture SQL·injected remote는 실제 인증 서버 E2E 증거가 아니다.

## BF1012-02 — 공유 닫기 취소

브랜치: bugfix1012 · 작업일: 2026-10-12

- 변경 전: 닫기가 확장만 종료하여 저장 링크가 남고 늦은 추출이 다시 저장될 수 있었다.
- 실제 파일: `FitMatchShareExtension/ShareViewController.swift`, `Shared/FitMatchSharedURLHandoff.swift`, `scripts/test-share-cancellation.sh`, `scripts/tests/share-cancellation/ShareCancellationTests.swift`.
- 변경: 저장 시 정확한 generation 반환, URL+generation 일치 시만 취소 삭제, 취소 이후 추출/앱 열기 callback 무시. 기존 비교/옷장 목적지 유지.
- 검증: 수정 전 실제 controller harness 6 tests 중 2 실패. 수정 후 실제 production controller/store 기반 UIKit harness **11 XCTest, 0 fail, 0 skip PASS**. 앱 활성화 slot 소비·중간 취소·새 공유 보존·두 목적지 검증.
- 한계: test visibility/App Group adapter를 사용한 simulator harness. 실제 Share Sheet/앱 전환 실기기 **NOT RUN**.

## BF1012-03 — 상품명·브랜드 검색

브랜치: bugfix1012 · 작업일: 2026-10-12

- 변경 전: 관심상품 구분명·분류·쇼핑몰·사이즈도 매칭되고 brand 미상의 표시 fallback이 검색에 포함됐다.
- 실제 파일: `FitMatch/Services/FitMatchHistoryPresentation.swift`, `FitMatch/Views/GlobalSearchView.swift`, `FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests.swift`.
- 변경: 옷장/비교기록 모두 실제 상품명·브랜드 부분 일치만 사용. trim/case-insensitive 유지. 안내 문구 “상품명 또는 브랜드명을 입력해 주세요”. 빈 입력 preview 8 및 기존 결과 개수 동작·관심상품 기능 유지.
- 검증: 실제 presentation 코드 standalone RED 9 failures→GREEN PASS. 전체 Xcode 결과는 BF1012-06. 기존 identity 검색 회귀의 size query는 새 승인 검색 범위에 맞춰 product query로 변경한다.
- 실제 화면 문구·키보드 상호작용 **NOT RUN**.

### BF1012-03 후속 기능 재검증 — 2026-10-12

- 브랜치: bugfix1012. 대상 파일: `FitMatch/Views/GlobalSearchView.swift`.
- 실제 QA `92cacd6` 시뮬레이터 검색 입력칸의 runtime snapshot에서 요청 문구와 달리 끝 마침표가 있는 것을 확인했다. 정확한 문자열 검증 **FAIL** (`상품명 또는 브랜드명을 입력해 주세요.`).
- 변경: 입력칸 안내의 마침표 한 글자만 제거. 검색 조건·레이아웃·정책 변경 없음.
- 계획: 기존 승인에 따라 QA에 통합하고 동일 화면의 정확한 문자열·입력/초기화 및 기능 회귀를 재검증한다. 이 시점 후속 수정 소스의 검증은 **NOT RUN**이며 최종 실행 결과는 BF1012-06 후속 기능 재검증에 기록한다.

## BF1012-04 — 옷장 동기화 실패와 수정값 보존

브랜치: bugfix1012 · 작업일: 2026-10-12

- 변경 전: 기술적/일반 오류 안내, 재시도 시작 시 오류 조기 해제, 실패한 update 뒤 stale list hydration이 로컬 이름·메모를 덮음.
- 실제 파일: `FitMatch/Components/FitMatchCard.swift`, `FitMatch/Services/FitMatchClosetSyncCoordinator.swift`, `FitMatch/Services/FitMatchLinkedSizeEditIntent.swift`, `FitMatch/Views/MyClosetView.swift`, `FitMatch/Views/AddClosetItemView.swift`, `FitMatch/Views/ClosetItemDetailView.swift`, `FitMatchTests/FitMatchClosetSyncCoordinatorTests.swift`.
- 변경: 명시적 list/save/unknown 실패 종류로 승인 문구 표시. 작은 inline banner와 current-user 재시도, 요청 중 중복 방지, 실제 성공 때 해제. 입력/계약 거절은 편집 가능한 안전한 이유를 같이 표시한다. 반복 오류 popup 대신 기존 공통 카드/버튼 사용.
- 재현된 실패 mutation ID만 최종 projection에서 제외해 미저장 수정값을 보존. 광범위 rollback 제거는 하지 않았다.
- 수정 전 실제 Xcode suite **52 tests, 3 issues FAIL**: 이름·메모 덮임 2 assertions, retry 중 실패 지워짐 1. 목록조회 실패 rollback 손실 검사는 원래도 PASS이므로 해당 경로 수정 없음.
- 최종 실행 결과는 BF1012-06. 실기기 banner/레이아웃 **NOT RUN**. 보호 scroll 파일/modifier 변경 없음.

## BF1012-05 — 재현 확인 / 보류

브랜치: bugfix1012 · 작업일: 2026-10-12

### 백그라운드 실패와 수정값

- 관련: `FitMatchClosetSyncCoordinator.synchronizeOnce` update 실패→최종 remote list projection.
- 조건: 서버에 있는 항목을 로컬에서 이름·메모 편집, update가 거절되지만 목록 조회는 기존 서버값을 반환.
- 실행: 수정 전 이름·메모 손실 재현 **PASS (결함 확인)**. 필요한 최소 보존 수정은 BF1012-04에만 포함.
- 목록 조회 예외 후 rollback 자체에 의한 독립 손실은 이번 회귀에서 **미재현**. 정상 저장 여부와 입력 유지 assertion을 구분했다.

### 같은 개수 기록 교체

- 관련: `FitMatch/Views/RecommendationHistoryView.swift`의 `histories.count` 관찰/cache, `FitMatch/Services/VNextHistoryCacheHydrator.swift`, `FitMatchTests/FitMatchComparisonSyncCoordinatorTests.swift`.
- 계획: 실제 hydrator와 count-only 관찰 조건을 사용하는 진단 회귀로 확인, History production 수정 금지.
- 최초 fixture는 A→B 교체가 아니라 1→2 추가였으므로 그 실패는 재현 증거로 사용하지 않는다. 최종 진단 실행/조건은 BF1012-06에 기록.
- 최종 supported schema 4 immutable fixture는 같은 서버 target identity로 A를 B로 교체하고, 실제 hydrator 저장 후 count 1 유지/identity 변경/count-only 관찰 누락을 확인했다. **PASS (캐시 무효화 누락 조건 재현)**. schema 3 legacy fixture는 target identity가 없어 A+B 두 건을 유지했다. 실제 화면이 오래된 목록을 표시하는 직접 UI 재현은 **NOT RUN**, production History 수정 없음.

### 명시 보류

- 다른 기기의 옷장 삭제 전달: 수정 없음, **NOT RUN**.
- 기록 삭제 후 관련 복사 데이터 정리: 수정 없음, **NOT RUN**.

## BF1012-06 — 최종 검증·인계

브랜치: bugfix1012 · 작업일: 2026-10-12

### 후속 승인 — QA 통합

2026-10-12 사용자가 “QA에 머지하도록해”로 QA 통합을 승인했다. 아래 앞선 merge/commit/push 없음 기록은 최초 구현 완료 시점의 이력이다. 기존 bugfix1012 변경을 추적 가능한 메시지로 커밋한 뒤, clean 기존 QA checkout에 정상 병합하고 QR를 포함한 조합을 다시 검증한다. 신규 DB 적용/main 변경/배포는 이 승인에 포함되지 않는다. 최종 병합 SHA와 검증은 후속 기록으로 남긴다.

### 변경 파일 / 통합 영향

- BF1012-01~04의 실제 소스/테스트/SQL 파일은 위 번호별 목록 참조. BF1012-05는 진단 테스트만 추가했고 독립 History 수정은 하지 않았다.
- BF1012-06 문서: 이 파일, `Docs/CodexSessionHandoff.md`, 관련 owner 경로를 갱신한 `FitMatch Behavior Map.md` / `FitMatch Swift Feature Map.md`, 최종 실행 요약 `bugfix1012-verification.json`.
- QA QR의 소스 변경을 `git diff origin/main origin/QA -- FitMatch FitMatchShareExtension Shared`로 추출해 현재 tree에서 `git apply --check` **PASS**. 실제 적용/merge 없음. 겹치는 CompareFlowSheet/MyClosetView의 QR 진입 hunk와 복구/banner hunk는 직접 충돌하지 않는다. QR를 포함한 최종 조합 build/기기 흐름은 **NOT RUN**.
- commit/push 없음. 커밋 시 `[bugfix1012][실제 작업일][BF1012-번호]` 형식으로 해당 이력을 추적한다.

### 검증 상태와 근거

| 번호 / 항목 | 상태 | 실행 근거 / 경계 |
| --- | --- | --- |
| BF1012-01 DTO/비동기 저장·독립 readback·fresh runtime·정확한 identity/provenance | PASS | 신규 16 tests, 아래 Xcode 8 suites에 포함. scripted remote, 실제 DTO/coordinator/VM 실행 |
| BF1012-01 sizesRequired/measurementsRequired→복구→사용자 선택→begin/complete | PASS | ViewModel 2 상태 + injected 기존 비교 action. 로컬 선택만 통과한 결과가 아님 |
| BF1012-01 실패 입력 유지/complete 없음, 동일 요청 retry, 다른 계정·상품/late 응답 거절 | PASS | 요청·이벤트·선택·readiness 검증, lost-response와 definite-rejection 구분 |
| BF1012-01 proposed SQL save/read/실제 후보·begin·complete·History | PASS | PGlite PostgreSQL/WASM. 실제 개발 함수 정의 fixture, classification/catalog/hash dependency fixture 사용 |
| BF1012-01 owner RLS/멱등성/공용 원본 불변/기존 automatic parity | PASS | authenticated role 분리, official FK·ACL/invoker 보존, no-recovery runtime JSON/automatic eligible 동일 |
| BF1012-01 원격 SQL 적용 / 정상 인증 앱 E2E | BLOCKED | 신규 개발 적용 승인 미확보. 실제 적용 SQL 0. 승인 후 정상 QA 세션으로 확인 필요 |
| BF1012-02 Close/추출 중 취소/새 공유 보호/Compare·Closet 목적지 | PASS | 실제 controller/shared store UIKit harness 11 tests, 0 fail/0 skip |
| BF1012-03 product/brand·trim/case·부분 일치, 제거 조건/관심상품/빈 preview/결과 제한 | PASS | standalone presentation + Xcode Scenario/Provider 회귀 |
| BF1012-04 실패 update 입력 보존 / typed 실패 / 중복·계정 retry / 실제 성공 해제 | PASS | Closet suite 53 tests. 기준 코드 52 tests/3 issues FAIL에서 수정 후 통과 |
| BF1012-05 같은 개수 교체 진단 | PASS | supported schema4 실제 hydrator 1→1, identity A→B, count-only observer 조건 누락 확인. 독립 수정 없음 |
| BF1012-06 최종 앱/확장 빌드·선택 회귀 | PASS | 최종 190 methods/8 suites, 0 fail/0 skip. FitMatch-QA iOS Simulator 26.3.1. `reviewed.log` / `Reviewed.xcresult`, 요약 JSON 참조 |
| BF1012-06 diff/보호 scroll / QA source patch 검사 | PASS | `git diff --check`, 요구된 보호 검사, 적용 없는 `git apply --check` |
| 실제 Share Sheet·앱 활성화·OCR 카메라/화면·Closet banner 실기기 | NOT RUN | simulator XCTest/controller callback을 실기기 성공으로 확대하지 않음 |
| 운영 적용·QA/main merge·배포 | NOT RUN | 요청 범위 제외, 실제 수행 0 |

독립 코드 검토에서 늦은 사진 전송의 컨텍스트 문제를 발견해 BF1012-01 안에서 수정했다. 수정 재검토에서 추가 Critical/Important 없음. URL image overload는 현재 production caller가 없어 별도 기능 확장은 하지 않았다.

### 남은 작업

1. **승인 필요**: 개발 `hnkplvyegonlhumlejst` 신규 recovery Apply. 이전 개발 DB 수정 승인을 이번 계약에 재사용하지 않는다.
2. 승인된 개발 적용 + Verify + 정상 QA 로그인으로 실제 저장·재조회·복구 비교·History 및 owner isolation 확인.
3. 기존 서버 semantic conflict가 남는 상품은 안전 gate 유지로 비교 차단될 수 있다. 출처/정책을 우회해 성공 처리하지 않는다.
4. 실기기 공유·복구·오류 화면 검증, 별도 QA 통합과 최종 source combination/ReleaseGate, 이후 별도 main 승격·배포 승인.
5. 다른 기기 Closet 삭제/History 복사 정리와 BF1012-05 History cache 무효화 수정은 별도 범위.

### 재실행 명령

```bash
# 실제 controller + shared store, simulator XCTest harness
bash scripts/test-share-cancellation.sh

# 임시 dependency 설치 후 실제 proposed SQL을 격리 PostgreSQL/WASM에서 실행
npm install --prefix /private/tmp/bf1012/sql --ignore-scripts --no-audit --no-fund @electric-sql/pglite@0.3.14
node supabase/sql/tests/bugfix1012_user_size_recovery.mjs /private/tmp/bf1012/sql/node_modules/@electric-sql/pglite/dist/index.js

# Xcode: 실제 존재하는 FitMatch-QA, simulator; whole-suite selectors 사용
xcodebuild test -project FitMatch.xcodeproj -scheme FitMatch-QA \
  -destination 'platform=iOS Simulator,id=2D3180C9-2B32-4B9B-A8CB-0D40CB0FCB5E' \
  -derivedDataPath /private/tmp/bf1012/DerivedData \
  -only-testing:FitMatchTests/FitMatchUserSizeRecoveryContractTests \
  -only-testing:FitMatchTests/FitMatchUserSizeRecoveryTests \
  -only-testing:FitMatchTests/FitMatchClosetSyncCoordinatorTests \
  -only-testing:FitMatchTests/FitMatchComparisonSyncCoordinatorTests \
  -only-testing:FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests \
  -only-testing:FitMatchTests/FitMatchFinalReleaseProviderSnapshotTests \
  -only-testing:FitMatchTests/FitMatchServerAuthorityIntegrationTests \
  -only-testing:FitMatchTests/FitMatchShareClosetEntryTests
```

### 개발 적용 승인 후 절차

1. 대상 개발 project ID/상태를 재확인하고 Apply hash guard가 현시점 정의와 일치하는지 확인한다. 운영 적용 금지.
2. 명시 승인 후 Apply를 실행하고 Verify 결과의 RLS/권한/기존 official FK/새 recovery FK/함수 hash를 확인한다.
3. 정상 QA 사용자 세션으로 sizesRequired·measurementsRequired, USER_OCR·USER_MANUAL, 응답 유실 재시도, 다른 계정·공용 원본 영향, 사용자 선택 비교·History를 검증한다. DB 관리자의 격리 SQL 테스트를 인증 앱 성공으로 표현하지 않는다.
4. 별도 승인된 QA 통합 이후 QR+복구/옷장 source combination 검증. 필수 ReleaseGate 통과 전 main 승격/배포 금지.

### BF1012-06 후속 실행 완료 — 2026-10-12 QA 병합 검증

- 브랜치: bugfix1012 → QA. 구현 커밋 `a676ab88197827daf952dfa662296136383eac4f`, QA 소스 병합 `32d34804d68b4a88b2c882a23fab9da27194b1f5` (기존 QA `1580aa3`). 기존 QR source 보존, 앱 소스 자동 병합. Handoff/Behavior Map 두 문서 충돌은 양쪽 전체 이력을 보존해 해결했다.
- **PASS** 실제 병합 소스 FitMatch-QA simulator build/test: 총198개(기존 회귀190 + QR XCTest8), 0fail/0skip, exit0. `bugfix1012-qa-verification.json`, `/private/tmp/bf1012/qa-merged.log`, `/private/tmp/bf1012/QAMerged.xcresult`. 보호 scroll/diff 검사 PASS. 아래 결과가 최초 완료 보고의 QA integration NOT RUN 상태를 대체한다.
- 최종 검증 후 문서 이력만 추가한다. 원격 QA 반영 대상이며 최종 local/remote SHA는 push 후 직접 확인한다. main 변경·DB 적용·배포 없음. 신규 개발 SQL 승인은 여전히 별도이며 인증 앱/실기기/전체 ReleaseGate는 미검증이다.

## BF1012-06 후속 기능 재검증 — 2026-10-12

브랜치: bugfix1012 → QA · 작업일: 2026-10-12 (Asia/Seoul)

- 요청에 따라 이전 결과를 재사용하지 않고 QA `92cacd6`에서 회귀198·공유11·격리 SQL을 새로 실행했다. 실제 검색 화면에서 BF1012-03 안내의 끝 마침표 불일치 **FAIL** 확인 → bugfix1012 `1fa0f62`에서 한 글자 수정 → QA 소스 `aac49221aa5b678ca17c1f8a16430c9115e1ecf5`에 정상 병합했다. 최종 QA 조합도 다시 빌드/검증했다.
- 대상 파일: `FitMatch/Views/GlobalSearchView.swift` (문구만), 이 이력, `Docs/CodexSessionHandoff.md`, 새 실행 보고 `Docs/ChangeHistory/bugfix1012-functional-retest.json` 및 같은 이름 폴더의 화면 증거3개. 테스트/SQL/비교 정책 변경 없음. 보고 JSON에 실제 source hash와 runtime snapshot을 보존했다.
- 이 후속 기록은 BF1012-03의 과거 화면 문구·키보드 NOT RUN 중 아래 실행한 범위만 대체한다. 원격 DB 적용 승인과 실기기 미검증 상태는 유지한다.

| 항목 | 상태 | 이번 실행 근거 / 경계 |
| --- | --- | --- |
| BF1012-01 복구 저장→독립 재조회→fresh runtime→사용자 옷 선택→비교 완료 | PASS | 실제 DTO/coordinator/ViewModel 16개 포함. scripted remote. sizesRequired/measurementsRequired, 실패 입력 보존, 응답 유실 동일 요청 재시도, 늦은 상품/계정 응답 거절 포함 |
| BF1012-01 실제 SQL 저장·재조회·후보·begin·complete·History / 멱등성·RLS·원본 불변 | PASS | PGlite에서 신규 실행 exit0. 실제 함수 SQL과 catalog/classification dependency fixture. 원격 DB 또는 정상 인증 앱 E2E 증거 아님 |
| BF1012-02 저장 후 Close·추출 중 취소·새 공유 보호·Compare/Closet 목적지 | PASS | 실제 controller/shared store simulator harness11, 0fail/0skip. visibility/AppGroup test adapter 사용 |
| BF1012-03 상품명/브랜드/부분 일치·trim/case·관심상품 구분어 및 제거 조건 제외·빈 preview | PASS | Scenario36 및 Provider12 안의 실제 presentation 회귀. populated 화면 검색 E2E는 NOT RUN |
| BF1012-03 정확한 입력칸 문구·ABC 입력·Clear→빈 preview | PASS | 최종 QA 설치/실행 후 runtime snapshot과 screenshot. 마침표 수정 전 FAIL→수정 후 동일 정확 문자열 PASS. 빈 데이터 UI 모드 |
| BF1012-03 한글 입력 도구 | BLOCKED | runtime UI 자동 입력은 US/ASCII만 지원하여 한글 입력을 실행하지 못했다. 한글 검색 조건은 위 기능 테스트로 검증 |
| BF1012-04 typed 실패·입력 보존·현재 사용자/중복 retry·실제 성공 후 해제 | PASS | Closet53 tests 새 실행. 실패한 update 뒤 stale projection이 로컬 이름·메모를 덮지 않음 |
| BF1012-04 실제 조회 실패 안내/다시 시도/재실패 안내 유지 | PASS | 시뮬레이터 UI 테스트 모드(유효 Supabase 인증 없음)에서 목록 조회 실패와 버튼 탭 확인. 기술 오류/반복 팝업 관측 없음 |
| BF1012-04 정상 인증 retry 성공·저장 실패 banner 화면 | NOT RUN | 정상 인증/해당 상태의 직접 화면 실행 안 함. coordinator 테스트 성공을 화면 성공으로 확대하지 않음 |
| BF1012-05 같은 개수 교체 조건 / 실패 저장 입력 보존 | PASS | ComparisonSync25 및 Closet53 새 실행. History count-only 무효화 누락 조건은 계속 재현됨. 독립 History 수정 없음 |
| BF1012-06 최종 QA 빌드·회귀·QR | PASS | 최종 총198개(190 Swift Testing+QR XCTest8), 0fail/0skip, xcodebuild exit0. `/private/tmp/bf1012/FunctionalRetestFinal.xcresult` |
| BF1012-02 시스템 공유 시트→QA 확장 Close→앱 활성화 | BLOCKED | Safari 시스템 공유 시트까지 screenshot 확인. runtime snapshot이 확장 선택 항목을 노출하지 않아 확장 진입/Close/활성화 실행 안 함 |
| 실제 인증 복구 E2E / 개발 신규 SQL 적용 | BLOCKED | 개발 hnkplvyegonlhumlejst 적용 승인 대기, 실제 SQL 적용0. 운영 변경0 |
| 실기기 Share·카메라·복구·오류화면 / 실제 stale History 화면 / 전체 ReleaseGate | NOT RUN | 이번 시뮬레이터·fixture 결과로 대신하지 않음 |

- 보류 유지: 다른 기기 Closet 삭제 전달, History 삭제 후 복사 데이터 정리. 같은 개수 History 화면 cache 수정도 별도 범위이다.
- 최종 검증 이후 추가 변경은 실행 보고/이력/화면 증거뿐이다. main 승격·DB 적용·배포 없음. bugfix1012 및 QA의 원격 반영은 push 후 SHA를 직접 확인한다.
