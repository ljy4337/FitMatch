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

## BF1012-01 / BF1012-06 후속 — 개발 DB 적용 완료

브랜치: bugfix1012 · 작업일: 2026-10-12 (Asia/Seoul)

### 승인과 계획

- 사용자 “개발디비에 먼저 적용해. 승인한다”를 BF1012-01 준비 SQL의 개발 `hnkplvyegonlhumlejst` 적용 승인으로 확인했다. QA scheme과 실제 project metadata(FitMatch/ACTIVE_HEALTHY/서울/PG17.6)를 대조했다. 운영 적용·main 승격·배포 승인으로 확대하지 않는다.
- 계획: 현재 DB 정의/대상 확인 → 기존 준비 Apply 그대로 migration 적용 → 별도 Verify/권한/API 사후 검사 → 이력 기록. 신규 계약 범위를 추가하지 않는다.

### 실제 실행 / 대상 파일

- **APPLIED** `supabase/sql/bugfix1012_user_size_recovery_Apply.sql` 원문 1회. 원격 migration `20261012045134`, 이름 `bugfix1012_user_size_recovery`. 함수/테이블/제약조건/권한 및 기존 비교 연결을 하나의 준비된 계약으로 적용했다.
- **EXECUTED READ ONLY** `supabase/sql/bugfix1012_user_size_recovery_Verify.sql`의 4개 SELECT를 각각 독립 실행해 모든 결과를 보존했다. owner policy/ACL parity와 실제 익명 HTTPS API 검사를 추가했다.
- **NOT RUN** `supabase/sql/bugfix1012_user_size_recovery_Rollback.sql`: 준비만, 실제 실행 없음. 수락된 복구 데이터가 있으면 rollback을 거절해 사용자 identity를 보존하는 계약 유지.
- 실제 수정 파일: 이 이력, `Docs/CodexSessionHandoff.md`, `FitMatch Behavior Map.md`, 새 적용 증거 `Docs/ChangeHistory/bugfix1012-development-db-applied.json`. 앱/테스트/기존 SQL 원문 변경 없음. JSON은 실행 SQL SHA256·원격 migration·사전/사후 metadata·API 결과·기존 advisory를 보존한다.
- 기존 문제: 준비된 복구 RPC/저장소가 개발 DB에 없어서 실제 서버 복구 검증이 막혀 있었다. 현재는 계약 배포 완료이며 아래 과거 개발 미적용/승인 대기 상태를 대체한다. 실제 로그인 앱 동작 완료를 뜻하지 않는다.

### 이번 실행 검증

| 항목 | 상태 | 근거 / 경계 |
| --- | --- | --- |
| 개발 대상·신규 계약 미적용·기존 함수12 일치 | PASS | 실제 get_project 및 읽기 전용 system catalog. 모든 LF-normalized hash 일치 확인 후 적용 |
| 준비 SQL 격리 회귀 재실행 | PASS | `/private/tmp/bf1012/sql-dev-apply-preflight.log`, exit0. PGlite 실제 SQL/fixture; live 인증 E2E 아님 |
| 원격 Apply / migration 영수증 | PASS | apply_migration success=true 및 ledger `20261012045134` 재조회 |
| 사용자 소유 RLS·직접 INSERT/UPDATE/DELETE 거절·anon 접근 거절 | PASS | owner_id=auth.uid() SELECT 정책2, authenticated SELECT만, backup 접근 거절 |
| public 저장/조회 RPC와 private helper 권한 | PASS | public SECURITY INVOKER2, authenticated 실행 허용/anon 거절, 빈 search_path. private 비교 helper 직접 실행 거절 |
| 공식 FK·사용자 recovery FK·정확한 비교 identity | PASS | 기존 product_sizes FK 보존, 별도 recovery FK와 상호배타 check/owner snapshot trigger 확인 |
| 적용된 함수12 정의·기존 canonical ACL/security 유지 | PASS | backup applied hash와 현재 pg_get_functiondef 전부 일치, canonical old/new ACL·invoker 동일 |
| 실제 HTTPS 익명 RPC 접근 | PASS | 정확한 앱 인자 get(p_request_id)/save(p_request) 각각 HTTP401·42501. 인증 저장 성공 증거는 아님 |
| 신규 security advisor | PASS | 사전/사후 동일 findings18(기존 INFO14+WARN3+WARN1), 추가0. 기존 경고 해결을 주장하지 않음 |
| 실제 로그인 복구·재조회·비교 완료·History / live 자동 비교 | NOT RUN | 정상 QA 사용자 세션 필요. auth impersonation/RLS bypass/사용자 테스트 데이터 생성 없음 |
| 적용 후 앱 build/test 재실행 / 실기기 | NOT RUN | 이번 앱 소스 변경 없음. 이전 198/11 결과를 이번 실행으로 표현하지 않음 |
| 운영 DB 적용 / Rollback / main 승격·배포 | NOT RUN | 이번 실행 대상 제외, 실제 적용0 |

실제 API 첫 검사 스크립트가 save 인자를 p_payload로 잘못 보내 PGRST202를 받은 것은 검사 오류였다. 앱/SQL 소유자의 p_request를 확인해 검사만 수정하고 get/save 모두 재실행했다. 해당 최초 결과를 계약 배포 실패나 PASS 증거로 사용하지 않는다.

기존 보안 참고: [authenticated SECURITY DEFINER 경고](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [유출 비밀번호 보호](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). 이번 승인 범위에서 기존 Auth 설정을 변경하지 않았다.

### 남음

- 개발 DB 적용에 필요한 추가 승인/사용자 SQL 실행은 없다. 정상 로그인한 FitMatch-QA 앱에서 복구 입력→서버 재조회→옷 선택→비교 완료·History 및 기존 자동 비교를 검증해야 한다.
- 운영 적용은 이번 승인에 포함되지 않으며 NOT APPLIED. 별도 승인과 현시점 사전 검사 필요.
- 실기기 공유/사진/오류화면, History count-only cache 문제와 기존 명시 보류 항목은 그대로 남는다. 추가 독립 수정 없음.

## BF1012-06 후속 — 개발 DB 적용 후 재검증

브랜치: bugfix1012 (기록) / QA (실행) · 작업일: 2026-10-12 (Asia/Seoul)

### 계획 / 조사 범위

- 현재 QA 소스와 실제 개발 연결을 확인하고, 일반 앱 로그인 상태·원격 계약·실제 API·영향 회귀를 새 실행한다. 실제 인증이 없으면 그 경계를 기록하고 필요한 지원을 요청한다.
- 기존 문제: BF1012-01 개발 계약은 적용됐지만 정상 인증 앱의 저장·비교 성공 증거가 없다. 이번에는 앱/SQL를 수정하지 않고 실행 결과와 지원 조건만 기록한다.
- 대상 파일: 이 이력, `Docs/CodexSessionHandoff.md`, 새 `Docs/ChangeHistory/bugfix1012-development-db-retest.json`. 테스트한 QA source는 `fa01c7d771aed079fe9cc3048d9a802a990cdbb9`, 시작 clean. main/운영/DB schema/Auth 설정 변경 없음.

### 실제 실행과 판정

| 항목 | 상태 | 실제 근거 / 경계 |
| --- | --- | --- |
| BF1012-06 QA build·install·일반 launch | PASS | FitMatch-QA/Debug-QA, bundle com.ljy4337.fitmatch.qa, 실제 plist URL hnkplvyegonlhumlejst. fake auth/launch override0. iPhone 17에서 Apple 로그인 화면 확인 |
| BF1012-01/02/03/04/05 영향 회귀·QR | PASS | 새198 methods(190 Swift Testing+8 QR XCTest), 0fail/0skip. DevelopmentDBRetest.xcresult와 별도 summary 확인. scripted remote/SwiftData/fixtures이며 정상 인증 DB 실행이 아님 |
| BF1012-01 실제 개발 계약 재조회 | PASS | 기존 migration20261012045134 확인, Verify의 4 SELECT 별도 실행. RLS2·RPC/helper6·비교 제약4·적용 함수12 hash 일치. 관리자 catalog 검사와 정상 사용자 저장 검사는 별도 |
| BF1012-01 실제 HTTPS 익명 저장·조회 거절 | PASS | get(p_request_id)/save(p_request) 모두401/code42501. 수락된 사용자 복구 쓰기0, recovery/active 사후0건 |
| BF1012-01 격리 SQL 회귀 | PASS | sql-dev-retest.log의 실제 save/read/eligibility/begin/complete/History·retry·owner/원본 불변·rollback 검사 새 실행. PGlite catalog/classification fixture, 원격 인증 성공 증거가 아님 |
| BF1012-01 정상 로그인 저장→독립 재조회→fresh runtime→사용자 옷 선택→비교·History | BLOCKED | 일반 QA 앱이 Continue with Apple 화면. 전용 정상 사용자 세션 없음. Auth preflight exit2/request0, 개인 앱 token 추출·사칭·RLS 우회 없음 |
| BF1012-01 원격 retry/응답유실 멱등성·다른 사용자/공용 원본 영향·live 자동 비교 | BLOCKED | 정상 A/B 전용 세션 미제공. fixture PASS를 이 항목 PASS로 사용하지 않음 |
| BF1012-04 정상 인증 retry 성공·저장 실패 화면 | BLOCKED | 정상 QA 앱 로그인 필요. 현재 로컬 owner 회귀 통과와 별도 |
| BF1012-02 실제 공유 확장 Close/앱 활성화·실기기 | NOT RUN | 이번 실행하지 않음. 과거 controller harness11을 이번 실행으로 보고하지 않음 |
| BF1012-05 같은 개수 History 실제 stale 화면 | NOT RUN | 이번 독립 수정/화면 실행0, 명시 보류 유지 |
| 추가 SQL 적용·운영/main 승격·배포 | NOT RUN | 이번 SQL Apply0. 기존 승인 migration 유지. Verify만 읽기 전용 재실행 |

- 실행 중 도구 profile의 `(default)` 표시명을 복원 이름으로 사용한 검사는 거절되어 shutdown regression simulator snapshot도 실패했다. 명시적 bf1012-dev-ui profile을 기존 booted iPhone 17로 설정하고 snapshot 재실행 성공. 앱/서버 결함으로 분류하지 않는다.
- 공개 Auth settings에서 Apple provider 활성·anonymous 비활성을 확인했다. QA client ID 허용이나 Apple 로그인 성공은 이 결과로 확인할 수 없다. 실제 오류가 없는 상태에서 provider 설정을 임의 변경하지 않는다.

### 필요한 사용자 지원 / 남은 승인

- **추가 개발 DB 적용 승인이나 사용자 SQL 실행은 필요 없다.** 우선 현재 iPhone 17 Simulator의 FitMatch-QA에 테스트 계정으로 직접 로그인하고 완료를 알려주면 정상 앱 복구/비교 검증을 이어갈 수 있다. 비밀번호·2FA·token은 채팅에 보내지 않는다. 사용자에게 이 지원을 비동기 요청했다.
- 원격 타 계정 격리 자동 검증에는 별도의 두 번째 정상 전용 QA 사용자 세션이 필요하다. 필요 시 기존 `Docs/QA/ReleasePreparation20261002/SessionSetup.md`의 로컬 비밀 입력 절차를 사용한다. 로그인 세션 연결 없이 계정을 생성하거나 Auth/RLS를 변경하지 않는다.
- 운영 적용·main 승격·배포는 별도 승인/Release Gate 대상이다. 다른 기기 Closet 삭제 전달, History 삭제 후 복사 정리, 같은 개수 History cache 독립 수정은 이번에도 보류한다.


## BF1012-07 — 긴 상품명과 버튼 레이아웃 (UI 후속)

- 브랜치: `bugfix1012`; 작업일: `2026-10-12` (Asia/Seoul).
- 사용자 승인 범위: 첨부 IMG_2589.PNG의 “비교할 내 옷 변경” 버튼 깨짐 및 앱 내부 버튼의 긴 텍스트 대응. UI만 변경, 기능 변경 금지.
- 변경 전 문제: 선택한 내 옷의 긴 상품명/브랜드/옵션과 버튼이 가로폭을 경쟁해 버튼 문구가 줄바꿈되고 높이38 밖으로 나옴.
- 계획: 짧은 인라인 액션의 폭 확보, 옆 상품 텍스트 말줄임, 공통/개별 액션 문구 한 줄·축소·말줄임. 설명을 포함한 카드 전체나 시스템 alert/menu에 한 줄 제한을 걸지 않음.
- 실제 변경: `FitMatch/Components/FitMatchCard.swift` 공통 액션 텍스트/인라인 레이아웃 modifier 및 Primary/Secondary/EmptyState 버튼. `RecommendationResultView.swift`는 같은 데이터·같은 액션으로 표시하는 `ResultClosetReferenceCard`를 분리해 실제 카드의 레이아웃을 검사할 수 있게 함. 브랜드/상품명/옵션 말줄임, 변경 버튼 우선 폭 확보, 나머지 비교 액션 문구 보정.
- 대상 파일: Components/{FitMatchCard,ContentFilterBar,ProductSizeSelectionGrid}.swift; ContentView.swift; Views/{AddClosetItemView,AddComparedProductToClosetSheet,ClosetItemDetailView,CompareFlowSheet,FitMatchOnboardingView,HomeView,LinkClosetRegistrationView,MyClosetView,MyPageView,RecommendationResultView,ReleaseInformationView,SettingsView,SizeTableRecoveryView}.swift; FitMatchTests/FitMatchButtonLayoutTests.swift; Docs/CodexSessionHandoff.md.
- 실제 변경 경계: 버튼 action/조건/상태/선택 identity/저장/RPC/비교/점수/문구 원문 변경0, SQL 준비·적용0, DB 변경0. 기존 줄수 제한·축소가 있는 사이즈 선택은 기준0.72 유지. 카드 설명과 FAQ 본문은 여러 줄 유지. 아이콘 버튼과 시스템 alert/menu의 기존 고유 레이아웃은 유지.
- **PASS** 최종 앱 build-for-testing / FitMatch-QA·Debug-QA, iPhone 17 Regression Simulator iOS26.3.1. `ButtonLayoutFinal.xcresult`: 신규 UI 검사3 + 기존 실제 mounted 비교 선택 회귀1 =4 PASS/0FAIL/0SKIP. 긴 상품명·브랜드·옵션을 각각10회 반복한 입력과 짧은 입력에서 320/375/430pt 모두 변경 버튼 폭 동일·높이38pt·가로 경계 안 유지. 액션 문구는 80/156/280pt에서 한 줄 높이·가로폭 검사. 기존 선택 회귀는 scripted remote 기반이며 live 서버 검증 아님.
- 최초 `ButtonLayout.xcresult`는 2PASS/1FAIL: UIHostingController의 접근성 요소 탐색이 nil인 테스트 측정 실패. DEBUG 전용 선택적 geometry observer로 실제 카드의 버튼 좌표를 측정하도록 바꿔 위 최종 실행 PASS. 앱 기능이나 서버 오류로 분류하지 않는다. DEBUG observer는 Release에 포함되지 않음.
- 캡처 검증: drawHierarchy 이미지가 검게 나와 시각 확인 근거에서 제외. ImageRenderer로 같은 실제 UI 컴포넌트를 렌더링해 재실행: `ButtonLayoutRender.xcresult` UI3 PASS/0FAIL/0SKIP, xcodebuild exit0. 실제 결과 카드의 320/375/430pt 긴 이름 이미지 직접 확인 PASS(버튼 한 줄, 상품 텍스트 말줄임). `/private/tmp/bf1012/button-layout/BF1012-button-{320,375,430}-long.png`. 합성 입력/표시용 카드이며 실제 서버·전체 화면·실기기 증거 아님. 공통 버튼 이미지의 Secondary 렌더는 배경/글자 식별이 불명확해 시각 PASS 근거로 쓰지 않음; 공통 액션의 한 줄·폭 자동 검사는 PASS.
- **PASS** `git diff --check`, 보호 스크롤 diff0 및 검사, 최종 UI diff에서 기존 action/상태/조건/서버 코드 보존 확인. 재현/검증 증거와 소스 hash: `Docs/ChangeHistory/bugfix1012-button-layout-verification.json`.
- **NOT RUN** 실기기 UI 확인, 앱 전체 화면의 직접 조작, 이번 UI 변경의 QA merge/push/배포. 정상 인증 DB E2E의 기존 미검증 상태는 이번 UI 검사로 대체하지 않는다. 추가 DB 승인·SQL 적용 필요 없음.


### BF1012-07 후속 — QA 반영 및 별도 알고리즘 후보 재검증

- 브랜치 `bugfix1012`, 작업일 `2026-10-12`(Asia/Seoul). 사용자 버튼 UI QA 반영 및 89e6014 전환·검증 승인에 따라 실행.
- 실제 UI 변경 파일은 BF1012-07 목록과 동일. UI commit `0a58019` → QA merge `e9ddb2a`, 원격 QA/bugfix1012 push 완료. QR 두 commit과 기존 수정 모두 ancestry 확인. source 충돌0, main/DB/운영 변경0.
- **PASS** 병합한 QA 소스로 새 build/test12(버튼3+mounted 선택1+QR8), 실패/skip0; diff-check/보호 스크롤 확인. 과거 검사 수치를 이번 결과로 사용하지 않음. 해당 UI·QR 검사는 고정 입력/생성 QR 및 scripted remote이며 인증/실기기 PASS 아님.
- 기본 폴더 HEAD를 정확히 `89e6014`로 전환(detached/clean). feature 브랜치는 기존 별도 worktree/동일 HEAD/clean 보존. QA와 후보 알고리즘을 합치지 않음.
- **PASS** 후보 fresh48 focused 앱 검사, 개발/운영 completion 정의 fixture 각각31 PGlite SQL 시나리오. 실패가 없어 후보 폐기0. 알고리즘 소스 수정0. 대상/근거/미검증 경계는 최신 Handoff 및 `bugfix1012-qa-ui-and-size-decision-recheck.json`에 기록.
- **NOT RUN** 실제 v3 DB 적용/정상 인증 비교·기록, 구버전 앱 혼용 E2E, 실기기, 후보+QA 통합, 운영/main/배포. v3 적용은 별도 승인 필요. 이전 BF1012-07의 QA 미반영 기록은 당시 상태이며 이번 후속으로 대체.

## BF1012-08 / BF1012-09 — 사이즈 판단 변경 통합 및 개발 DB 조사

브랜치: bugfix1012 · 작업일: 2026-10-20 (Asia/Seoul)

- 대상: 기존 `89e6014`의 알고리즘·결과 표시·v3 SQL 40파일, 복구 결합 SQL 회귀, 개발 읽기 전용 preflight, 통합 이력.
- 변경 전: bugfix 수정과 알고리즘 변경이 서로 다른 브랜치에 존재했고 현재 로컬은 detached였다. 개발에는 v3 검증 함수가 없었다.
- 변경: 기존 bugfix에 정상 병합하고 문서 양쪽 이력 및 기존 미커밋 조사기록을 보존한다. QR이 있는 QA 최종 조합도 별도로 검증한다. main/실제 DB/배포는 변경하지 않는다.
- 검증: 현 개발 함수로 격리 v3 SQL31개, 기존 baseline31개, 복구 단독 및 v3 결합 SQL 회귀 PASS. 앱·QA 검증의 실제 결과는 아래 상세 기록을 따른다. 정상 사용자 원격 인증 비교/실기기 E2E는 NOT RUN.
- 개발 DB v3 SQL 적용 승인은 이번 요청에 포함되지 않았으며 실제 적용0. 앞기장 활성화는 사전 정의/매핑 및 최소 앱 버전 조건으로 보류한다.
- 상세/결과: [bugfix1012-size-decision-integration-20261020.md](bugfix1012-size-decision-integration-20261020.md).
