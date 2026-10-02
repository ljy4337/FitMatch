# FitMatch 확정 수정 5건 Implementation Plan — Terra 실행 지시

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. 수행주체는 Terra다. 한 단계의 검증을 마친 뒤 다음 단계로 진행한다. 자동 commit/push는 하지 않는다.

**Goal:** 링크 옷 수정과 원본 identity, 수동 detail, History 삭제 동기화, 서버 승인 원본 직접 비교, Git DB 재현성을 완성한다.

**Architecture:** Retailer는 사실을 제공하고 DB가 저장·비교 승인·정책을 소유한다. Swift는 exact identity를 전송하고 승인된 snapshot만 표시/계산한다. 기존 구조와 사용자 선택을 유지한다.

**Tech Stack:** Swift/SwiftUI/SwiftData, Supabase/PostgreSQL, XCTest/Swift Testing.

**Spec:** 사용자 확정 수정 5건 및 `Docs/FitMatchMeasurementPolicy.md`. 과거 제안보다 현재 정책을 우선한다.

## Global Constraints

저장소 `/Users/jinyoung/Developer/FitMatchLocal/FitMatch`, branch `connectDB`. 감사 HEAD `8c6586d51b73f405b4d6e7b52c5b688b24c7f732`는 참고 기준이다. 시작 시 실제 HEAD와 diff를 확인하고 최신 수정을 보존한다. reset/restore/stash/pull/branch 전환 금지.

AGENTS.md, Handoff 최신 상태 전체, Behavior Map 관련 Flow, MeasurementPolicy를 먼저 읽는다. 기존 dirty/untracked 파일을 덮어쓰지 않는다. 기존 테스트/SQL을 검색해 재사용하고 중복 파일을 만들지 않는다.

연결 DB `hnkplvyegonlhumlejst`는 먼저 실제 환경을 확인한다. 기존 세션의 명시적인 개발 DB 적용 승인이 확인된 경우에만 해당 범위의 migration 적용이 가능하다. 불확실하면 배포 DB는 READ ONLY로 유지하고 migration 준비/로컬 검증과 실제 적용을 구분해 보고한다. Production 적용, 사용자 데이터 일괄 보정/삭제, RLS 우회 금지. 현재 요청만으로 Production 적용 승인이 생기지 않는다.

기존 적용 migration 파일을 고쳐 과거를 바꾸지 않는다. 새 forward migration으로 작성하며 Verify/Rollback 또는 동등한 안전한 복구 절차를 제공한다. raw/history가 추가된 뒤 rollback 시 데이터를 삭제해야 한다면 자동 rollback하지 말고 비파괴 forward recovery를 명시한다.

동일 A–G 그룹만 비교한다. UNMAPPED만 session group 선택을 허용한다. 자동 후보 선택 금지. 다른 쇼핑몰 raw direct 금지. canonical mapping/기존 weight 임의 변경 금지. 보호된 scroll modifier와 call site, parser 병렬화, 예상 카드→선택→최종 결과 UX 변경 금지.

## Review Focus

사이즈 변경 중 실패하면 parent/canonical/raw 일부만 변경되지 않아야 한다. 재시도는 동일 수정 ID와 동일 payload를 유지한다. 오래된 history fetch가 삭제한 기록을 부활시키면 안 된다. legacy raw/detail이 없을 때 다른 사이즈·유사 이름으로 보충하면 안 된다. 구버전 canonical History는 새 비교 mode 도입 후에도 당시 값으로 읽혀야 한다.

## 실행 순서

1. 아래 Task 1→2→3을 순차 수행한다. 각 작업은 실패 재현→최소 수정→targeted/adjacent 회귀까지 닫는다.
2. Task 4를 서버 snapshot→Swift 소비→표시 순서로 완료한다. 큰 작업이므로 로컬 엔진만 바꾸고 완료 처리하지 않는다.
3. 모든 단계의 SQL을 처음부터 migration으로 관리하고, Task 5에서 전체 Git 재현성을 최종 검증한다.

## Task 1 — 링크 옷 수정 + 원본 실측 원자적 갱신

### 수정 대상

`FitMatch/Services/FitMatchClosetSyncCoordinator.swift`

- prepareLinkedClosetSizeEdit
- saveLinkedClosetEdit
- linkedEditRequest
- reconcileAcceptedLinkedEdit 및 readback 검증

`FitMatch/Services/FitMatchSupabaseProductResolver.swift`

- closetUpdatePayload / VNextClosetMutationPayload
- sourceObservationID 전송, list 응답 매핑

`FitMatch/Services/FitMatchVNextDTOs.swift`

- Closet 원본 snapshot identity/records 응답 계약

DB: 실제 public update wrapper부터 `apply_linked_closet_snapshot_for_swift`와 raw snapshot 저장/list owner까지 추적한다. `closet_items`, `closet_item_measurements`, `closet_item_source_measurement_snapshots`, `closet_item_source_measurements`를 함께 다룬다. 기존 `20260921110000_closet_raw_measurement_snapshots.sql`은 참고하고 새 migration을 작성한다.

### 반드시 바꿀 로직

현재 앱은 linked update에 use_server_measurements=true를 보내지만 배포 helper는 creation-only로 거절한다. **flag만 제거하지 마라.** update에서도 exact 서버 size snapshot을 사용할 수 있도록 계약을 완성한다.

저장 요청은 기존 수정 저널/idempotency 방식을 재사용한다. 새 observation이 필요하면 정확한 선택 product/variant/size에 속한 observation을 준비한다. 서버가 직접 고를 경우에도 선택 기준을 검증하고 확정 ID를 응답에 남긴다. label 또는 latest-any-size로 대체 금지.

```text
BEGIN
  소유권 + 현재 revision/기대 identity + 요청 identity 검증
  exact 선택 size의 canonical 및 raw observation 검증
  closet parent product/variant/size 갱신
  canonical snapshot 갱신
  해당 Closet의 raw snapshot/rows를 동일 size로 갱신
  accepted revision/identity 반환
COMMIT
→ authoritative list/readback
→ 동일 identity/raw 내용 확인
→ local projection
→ 성공 표시
```

기존 raw snapshot 재사용 규칙은 동일 요청 retry와 새로운 size edit를 구분해야 한다. metadata-only 수정은 원본을 불필요하게 새로 수집/교체하지 않는다. 과거 비교 History snapshot은 수정하지 않는다. raw가 없는 legacy row에 임의 값을 만들지 않는다.

### 검증/완료 조건

- [ ] 기존 테스트 `FitMatchClosetSyncCoordinatorTests.swift`, `FitMatchClosetTransportContractTests.swift`와 SQL raw regression을 확장한다.
- [ ] 실제 production payload가 기존 DB helper에서 거절됨을 로컬 DB에서 재현한다.
- [ ] M→L 후 parent/canonical/raw의 product·variant·size ID 및 값이 전부 L과 일치한다.
- [ ] 중간 실패 시 전부 M 유지. 동일 요청 retry 중복 없음. M→M 메모 수정 정상.
- [ ] 다른 사용자/다른 variant/다른 size observation은 거절된다.
- [ ] 재조회 후 화면 sourceDisplayRows의 개수·내용이 저장 raw와 일치한다. fake remote PASS만으로 SQL 성공이라 보고하지 않는다.

## Task 2 — 수동 옷 exact detail 보존

### 수정 대상

`FitMatch/Services/FitMatchSupabaseProductResolver.swift`: mutation DTO, closetPayload, mapClosetItem, closetDetailCode.

`FitMatch/Services/FitMatchVNextDTOs.swift`: VNextClosetItemDTO.

`FitMatch/Services/FitMatchClosetSyncCoordinator.swift`: matchesManualEditReadback, projectAuthoritativeRegistration, apply.

DB 확인 대상: `set_closet_detail_snapshot_for_swift`, `list_closet_items_snapshot_base`, `closet_detail_code_snapshot`. 배포 DB는 이미 이 기능을 제공하므로 실제 부족할 때만 migration을 추가한다.

### 반드시 바꿀 로직

사용자가 명시한 UI detail을 `closet_detail_code`로 보내고, 서버가 반환한 exact detail을 DTO→record→UserFit까지 보존한다. canonical family가 shirt_blouse라는 이유로 exact blouse를 shirt로 바꾸지 않는다.

```text
명시적 유효 detail 있음 → 저장된 exact detail 복원
legacy detail 없음 → 기존 호환 복원 경로, 원래 사용자 선택을 안다고 주장 금지
명시적이지만 유효하지 않은 detail → 조용한 기본값 대체 금지
```

신규 간소화 화면에 detail 입력을 다시 추가하지 않는다. canonical 분류와 비교그룹은 바꾸지 않는다. readback은 전송한 exact detail까지 검증한다.

### 검증/완료 조건

- [ ] 기존 DTO/transport/sync 테스트에 blouse→save→list→hydrate→blouse 사례를 추가한다.
- [ ] shirt와 blouse가 같은 family여도 구분 유지. 기존 편집과 새 cache hydration 모두 검사.
- [ ] legacy detail 없음, 명시적 unknown detail, 서버가 다른 detail을 돌려주는 경우를 각각 검사한다.
- [ ] 기존 family/category/group 및 새 수동 등록 UX 회귀 없음.

## Task 3 — 다른 기기 History 삭제 전파

### 수정 대상

`FitMatch/Services/FitMatchComparisonSyncCoordinator.swift`: fetch/sync, hideVNextComparisonHistories, processedHistoryIDs, 현재 사용자/요청 generation 처리.

`FitMatch/Services/VNextHistoryCacheHydrator.swift`: hydrateCompleted 및 visibility 적용 경계.

`FitMatch/Services/FitMatchSupabaseProductResolver.swift`, `FitMatch/Services/FitMatchVNextDTOs.swift`: visibility 응답 계약.

DB: `comparison_history`, `hide_comparison_history`, 실제 public RPC wrappers. 기존 `20260906090000_vnext_hide_comparison_history.sql` 참고, 새 migration 추가.

### 반드시 바꿀 로직

**서버 목록에 없다는 이유로 local History를 삭제하지 마라.** 소유권으로 제한된 명시적 삭제 목록(tombstone)을 제공하는 read-only 계약을 추가하거나 기존 응답에 backward-compatible하게 포함한다. 항목은 exact server/client comparison ID와 삭제 시점을 식별할 수 있어야 한다.

```text
서버의 명시적 tombstone 수신
→ 해당 사용자의 exact local history만 숨김/삭제
→ hydrate 시 동일 ID의 오래된 completed row는 제외
→ local persistence 성공
→ 그 이후에 visibility cursor/processed 상태 확정
```

processedHistoryIDs에 들어 있어도 tombstone 적용을 생략하지 않는다. fetch 시작 후 hide가 완료된 경우 늦은 fetch로 기록을 재생성하지 않도록 사용자별 generation/삭제 상태를 기존 구조에 연결한다. local save 실패 시 tombstone 처리를 소비한 것으로 표시하지 않는다. 계정 전환 시 다른 사용자의 tombstone을 적용하지 않는다. 공유 Product/Closet row를 삭제하지 않는다.

### 검증/완료 조건

- [ ] 실제 coordinator/hydrator를 두 개의 분리된 in-memory store로 검증한다. 테스트가 없으면 `FitMatchTests/FitMatchHistoryVisibilitySyncTests.swift`를 추가한다.
- [ ] A hide→B sync, B 재시작 상당의 fresh coordinator+기존 cache, 이미 processed된 기록을 검사한다.
- [ ] hide 이전 fetch가 늦게 도착해도 부활하지 않는다.
- [ ] partial/실패 response 때문에 다른 정상 기록이 삭제되지 않는다.
- [ ] local save 실패→retry, 중복 tombstone, 사용자 전환을 검사한다.
- [ ] 공개 RPC의 인증/소유권 및 구버전 History 읽기 계약 유지.

## Task 4 — 서버 승인 원본 직접 비교를 최종 결과까지 연결

### 수정 대상

DB: `comparison_evidence_20260908`, canonical/context resolvers의 실제 caller, `eligible_candidate_sizes` overloads, `authorize_comparison_with_context` 계열, `begin_comparison`, `complete_comparison`, 정책 snapshot 및 History 반환 계약.

`FitMatch/Services/FitMatchVNextDTOs.swift`: versioned comparison evidence/mode DTO.

`FitMatch/Services/FitMatchVNextContractValidator.swift`: mode별 identity/evidence 검증.

`FitMatch/Services/VNextComparisonEngineAdapter.swift`: canonical-only filter와 coverage 계산.

`FitMatch/Services/MeasurementComparisonEngine.swift`: compareAuthorizedEvidence의 승인된 mode 소비.

`FitMatch/Services/FitMatchServerAuthorityCoordinator.swift`: candidate/eligible/permit에서 새 계약 소비.

`FitMatch/Services/RecommendationService.swift`, `FitMatch/Services/FitMatchSupabaseProductResolver.swift`: begin/complete 전달·검증.

`FitMatch/Views/RecommendationResultView.swift`, `FitMatch/Views/CompareFlowSheet.swift`: 실제 승인 mode 설명. 화면 구조나 예상 카드 UX는 유지.

### 반드시 바꿀 로직

최종 정책은 아래와 같다. 예전의 다른 쇼핑몰 raw-exact 제안을 적용하지 않는다.

```text
동일 A–G 그룹 검증
→ 같은 쇼핑몰 + 검증된 같은 schema/측정 의미인가?
    YES: 동일 원본 항목을 RETAILER_EXACT evidence로 승인
    NO: 검증된 공통 canonical 항목만 기존 정책으로 승인
→ 어느 경로도 검증되지 않은 항목은 제외
→ 승인 evidence를 begin에 고정
→ Swift가 해당 evidence만 계산
→ complete가 snapshot과 결과를 대조
→ History가 당시 snapshot을 보존
```

같은 rawLabel/rawCode/parser 문자열이라는 사실만으로 의미 동일성을 만들어내지 않는다. DB가 source/schema version, 원본 항목 identity, basis, representation, unit, 구성품, exact selected size를 확인해야 한다. 충돌하는 여러 원본을 first로 선택하지 않는다.

raw records는 보관 snapshot에서 읽고 canonical을 역변환해서 원본이라고 부르지 않는다. raw snapshot이 없거나 동일성을 입증하지 못하면 기존 검증된 canonical 경로만 사용한다. canonical도 없으면 해당 항목 제외. legacy snapshot을 임의 retailer raw로 승격하지 않는다.

서버 evidence에는 최소 mode, 원본/공통 항목 ID, 양쪽 값·단위·basis, source/schema provenance, score 포함 여부, policy metric/weight/version을 추적한다. raw-only 참고 항목에는 임의 weight를 만들지 않는다. 기존 metric의 weight를 쓰려면 해당 metric의 정의·단위·scale/tolerance와 raw 값이 호환된다는 서버 정책 근거가 있어야 한다. 단면/둘레 값에 기존 threshold를 그대로 적용하지 않는다.

raw 직접 비교를 표시만 추가하고 기존 canonical-only gate 때문에 eligible에서 막히게 두지 않는다. candidate→eligible→authorize→begin→complete의 동일 승인 규칙을 끝까지 맞춘다. 유효한 점수 항목이 없으면 추천/100점을 만들지 말고 근거부족 경로를 사용한다. 1개라는 이유만으로 과거의 2개 최소 규칙을 부활시키지 않는다.

begin mode/정책 version을 추가해 구버전 CANONICAL snapshot을 계속 읽는다. 새 코드로 과거 History를 재계산하지 않는다. 로컬 preview 엔진을 서버 authority로 승격하지 않는다.

### 검증/완료 조건

- [ ] 고정 응답으로 같은 retailer+같은 구조, 같은 retailer+다른 구조, 다른 retailer를 각각 확인한다.
- [ ] UNIQLO body-width, ZARA chest, MUSINSA 원본의 verified 동일 구조 사례를 각각 검사한다.
- [ ] 소매 vs 화장, 앞기장 vs 뒷기장, 앞밑위 vs 뒷밑위, 본체 vs 안감 직접 혼합 금지.
- [ ] unknown raw 표시·저장 유지, 미승인 비교 제외, raw-only 임의 점수 없음.
- [ ] 서버 begin→실제 Swift adapter→complete evidence→History까지 mode/값/identity 일치.
- [ ] 같은 canonical 고정 입력의 기존 점수 회귀 없음. raw mode의 허용된 값·scale 차이는 명시적으로 검증.
- [ ] 다른 그룹 차단, 선택 후보/variant/size 보존, 위조 mode/evidence/weight 차단.
- [ ] 기존 `MeasurementPolicyConsolidationTests`, `FitMatchServerAuthorityIntegrationTests`, `FitMatchVNextContractTests`, permit/engine tests를 확장하고 실제 SQL 회귀도 실행한다.

## Task 5 — Git으로 DB 재현 가능하게 정리

### 정리 대상

`supabase/migrations/`, `supabase/sql/` 및 관련 SQL regression/fixture.

우선 확인할 현재 untracked 파일:

- `supabase/migrations/20260923110000_same_comparison_group_only.sql`
- `supabase/sql/20260923_same_comparison_group_only_Verify.sql`
- `supabase/sql/20260923_same_comparison_group_only_Rollback.sql`
- `supabase/sql/tests/same_comparison_group_only_Regression.sql`
- `supabase/sql/tests/same_comparison_group_only_RollbackRegression.sql`

### 반드시 할 일

같은 그룹 SQL 하나만 추가하면 끝난다고 가정하지 않는다. tracked migration, 로컬 untracked SQL, 배포 migration history, 현재 함수 정의를 대응시킨다. obsolete draft/QA data dump/secret을 배포 migration에 섞지 않는다.

원격 migration timestamp와 로컬 filename이 다르면 내용을 비교해 대응관계를 기록한다. 동일 이름이란 이유로 동일 적용이라고 판단하지 않는다. helper/wrapper rename과 동적 preimage patch는 올바른 순서와 예상 definition에서만 실행돼야 한다.

정확한 파일 집합을 별도 일회용 디렉터리에 복사하여 ‘Git에 포함할 후보 파일만’으로 빈 로컬 DB를 만든다. 사용자의 checkout을 reset/clean하거나 개발 DB를 초기화하지 않는다. 필요한 bootstrap schema/extension/role이 빠졌다면 재현 실패로 기록하고 누락 원인을 해결한다.

비교 대상은 함수 signature/body, 테이블/컬럼, constraint, trigger, RLS, grants, source·canonical·group policy의 필요한 seed다. 사용자 Closet/History/인증 데이터는 복제하지 않는다. 사용자 데이터가 없는 DB에서 적용 가능한 정책 seed만 포함한다.

### 검증/완료 조건

- [ ] 빈 로컬 DB migration replay PASS.
- [ ] 기존 계약 상태 DB→이번 migration upgrade PASS.
- [ ] deployed baseline과 새 변경의 의도된 차이를 목록화하고 그 외 차이 설명.
- [ ] same-group-only, linked M→L raw/canonical, detail round-trip, History tombstone, raw/canonical comparison mode SQL 회귀 PASS.
- [ ] env가 없어 replay를 못하면 BLOCKED. 파일이 있다는 이유로 재현 성공이라 보고하지 않는다.
- [ ] commit/push하지 않는다. Git 포함 대상 manifest를 제출한다. untracked 파일은 명시적으로 ‘Git 미반영’이라고 보고한다.

## 공통 검증과 완료 보고

현재 전체 suite 기준은 899 tests / 41 FAIL / 42 skipped였다. 이를 무조건 baseline harmless로 처리하지 않는다. 수정 관련 실패부터 실제 production 계약과 fixture를 대조한다. 누락 group fixture나 오래된 brand-required 기대만 정당한 근거로 수정하고 assertion을 약화하지 않는다.

각 단계는 실패 재현→수정→targeted 테스트→인접 회귀 순서로 진행한다. 같은 suite는 추가 변경이 없는 한 불필요하게 반복하지 않는다. 마지막에 실제 scheme/destination을 확인해 Debug build와 전체 FitMatchTests를 실행한다. 실제 명령·exit code·test 수를 기록한다.

Behavior Map은 바뀐 호출/계약만 갱신한다. Handoff에는 실제 HEAD·dirty·migration 준비/적용 상태·테스트 결과·남은 gap을 추가한다. MeasurementPolicy는 구현에 맞추려고 약화하지 않는다.

최종 응답은 Changed files / Summary / Verification / Remaining issues로 작성한다. 각 5건마다 구현, 로컬 DB 검증, 연결 DB 적용, 실기기 E2E, Git 추적/commit/push를 별도로 표시한다. PASS / FAIL / NOT RUN / BLOCKED만 사용한다. ‘로컬 구현됨’을 ‘배포 및 실기기 정상’으로 보고하지 않는다.

최종 보호 검사:

```bash
git diff --check
git diff -- FitMatch/Components/TabBarScrollVisibilityModifier.swift
if git diff | grep -qE 'hidesBottomTabBarOnScroll|tracksTabBarVisibilityOnScroll|hidesTopChromeOnScroll'; then
  echo 'PROTECTED_SCROLL_DIFF_FOUND'
  exit 1
else
  echo 'PROTECTED_SCROLL_OK'
fi
```
