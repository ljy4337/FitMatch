# 1차 출시 — 기존 데이터 기반 핵심 로직 감사 (2026-09-30)

> 후속 수정: H01/H02/H03은 재현 후 수정 및 offline 회귀 통과. [2026-09-30 수정 보고서](HistoryRestoreRepair-20260930.md) 참조. 아래 내용은 수정 전 감사 이력이다.

## 기준과 범위

- connectDB / HEAD `db190a9c677da0181c4de2910c979a82ca59c1b8` + 시작 시 존재한 미커밋 작업. HEAD만의 결과가 아니다.
- AGENTS, Behavior Map, Measurement Policy, Handoff 현재 상태 및 FirstReleaseChecklist 기준.
- 새로운 쇼핑몰 응답 수집 없음. Supabase `hnkplvyegonlhumlejst` 읽기 전용: 이전 승인 테스트의 COMPLETED 3건과 배포 History 함수 정의 확인. 이번 감사 DB mutation 없음.
- 기존 고정 fixture와 이전 실제 저장 상품: MUSINSA 5328103, UNIQLO E484080, ZARA internalProductID 564222870 / 선택 catentryID 564228855.
- 앱 production 코드는 이번 감사에서 변경하지 않았다. 신규 감사 테스트와 자료는 로컬 미추적 파일이며 commit/push하지 않았다.

## 핵심 결론

**실제 저장 기록 3건 모두에서 서버 History → 비어 있는 로컬 캐시 복원 실패를 재현했다. 출시 전 수정 대상이다.**

이전에 같은 기기에서 비교/재실행에 성공했다는 사실과 모순되지 않는다. 기존 local History ID가 존재하면 hydrator는 해당 row의 재생성을 건너뛴다. 새 기기/로컬 캐시 없는 상태에서 비로소 복원 결함이 드러난다. 서버에 저장된 기록 자체가 삭제되었다는 뜻은 아니다.

## 확정 결함 H01 — 정상 CATEGORY_GROUP History를 지원하지 않는 기록으로 거절

- 관련 체크: P08, P09, FLOW-HISTORY / FLOW-SYNC.
- owner: `FitMatch/Services/VNextHistoryCacheHydrator.swift`, `HistoricalTargetProjection.init(row:)` (약 129–177행).
- 실제 3건 모두: schema=4, source=`CATEGORY_GROUP`, state=`CATEGORY_GROUP_CONFIRMED`, result=`COMPLETED`, deleted_at 없음, 현재 comparison_result_heads에 포함.
- deployed `comparison_history()`는 comparison row를 JSON으로 반환한다. authority_snapshot의 상태를 GLOBAL로 바꾸는 호환 처리가 없다. public wrapper → comparison_history_sync → comparison_history 관계도 확인했다.
- Swift projection은 USER_EXPLICIT, GLOBAL_CONFIRMED/GLOBAL만 허용하고 default에서 incompleteSnapshot을 던진다.
- 호출: ComparisonSync.synchronizeOnce → hydrateCompleted → adapter 재계산/완료값 검증 → HistoricalTargetProjection → incompleteSnapshot. coordinator는 이를 복원할 수 없는 기록으로 처리한다.
- 영향: 이전 비교 결과를 서버에서 새로 복원하지 못함. 이미 로컬에 있는 기록은 표시될 수 있음. 추천 계산 자체 오류로 확대하지 않음.
- 수정 방향: **현재 서버가 승인한 group-based snapshot 계약을 정확히 해석**하도록 projection owner 보완. 임의 GLOBAL 치환, 상세분류 추측, 검증 생략 금지. 원래 USER_EXPLICIT/GLOBAL 및 미지원 상태 fail-closed 회귀 유지.
- 필요 검증: 이번 3개 원본 fixture 그대로 empty-cache 복원, 재실행, 기존 local ID 경로, 기존 History 교체 및 등록 준비 경로.

## 같은 owner의 후속 점검 지점 — 실행 확정 결함과 구분

### H02: canonical 코드 projection 누락 (정적 근거, H01에 의해 후속 실행 차단)

`makeProductSize`는 서버 comparisonMeasurements의 code/value를 전달하지만, `measurements(from:)` / `measurementRecords(from:)` (605–668행)는 `MeasurementCode(rawValue:)`만 인정한다. 실제 세 상품의 chest_width, back_length, outseam 등은 로컬 enum의 chest_width_pit_to_pit 등과 다르다. 이미 존재하는 `FitMatchCanonicalMeasurementCode.projection`과 달리 이 경로는 해당 값을 버린다.

현재 실제 fixture 테스트는 H01에서 먼저 중단되므로 **빈 실측으로 복원된 화면까지 실행 확인했다고 보고하지 않는다.** 최종 결과 UI는 calculationSnapshot을 우선 사용하므로 최종 점수/화면 전체가 잘못된다고도 단정하지 않는다. H01 수정 시 등록 준비에서 canonical을 raw로 위장하지 않으면서 서버 code/value 및 identity를 보존하는지 함께 확인해야 한다.

### H03: 교체 중 실패의 원자성 (정적 위험, 이번 데이터에서 파손 재현 없음)

hydrateCompleted는 기존 동일상품 기록 삭제를 새 projection 검증 전에 수행한다(289–332행). 호출자의 hydration error catch에 rollback이 없다. 현재 3건은 빈 캐시에서 검증했으므로 기존 캐시 손실을 재현한 것은 아니다. 교체 시 실패해도 기존 기록을 유지하는 회귀검사가 필요하다. 실제 데이터 손상 건수로 세지 않는다.

## 체크리스트별 검토

| 범위 | 이번 확인 | 판정/한계 |
|---|---|---|
| C01–C04 링크 등록·원본 보존·서버 저장 | 기존 provider/payload/등록 회귀, 앞선 duplicate unknown 수정 포함 | 자동검사 PASS; 새 retailer/live 등록 수행 안 함 |
| C05–C06 링크 사이즈 수정·수동 detail | exact identity/context/observation 및 read-back 후 projection 코드, 관련 회귀 | 이번 범위 추가 결함 미확인 |
| C07 삭제 | 서버삭제 후 local 저장/rollback/tombstone 순서, 관련 회귀 | 이번 범위 추가 결함 미확인 |
| P01–P04 후보·사용자선택·실측 | 같은 그룹, min1, 서버 승인, manualCandidates/no automatic selection | 관련 회귀 PASS; 자동 calculateRecommendation의 활성 UI caller 확인 안 됨 |
| P05–P07 최종 결과·다른옷/사이즈 | 승인 batch 소비, request/user guard, 저장 후 결과, 기존 fixture | 관련 회귀 PASS; 실제 기존 3건 점수·추천 ID 재생 별도 확인 |
| P08–P09 기록 복원·기록에서 등록 | 기존 저장 3건을 새 in-memory SwiftData로 복원 | **FAIL: H01**; downstream 등록까지 정상이라고 판정 불가 |
| P10 삭제 동기화 | deployed tombstone envelope 및 Swift exact-ID reconciliation | 부재만으로 삭제하지 않음; 두 기기 E2E NOT RUN |
| U02/U04 계정·취소 | stale response/request ownership guard 및 회귀 | 이번 범위 추가 결함 미확인 |

## 검증 기록

1. 기존 offline 회귀: `/tmp/FitMatchFrozenReleaseAudit20260930.xcresult`, exit 0.
   **872 PASS / 0 FAIL / 10 skipped**, 동적 인자 device runs 889 PASS. FitMatchTests 대상, 실시간/인증 write suite는 명시 제외. 제외·skip을 PASS에 포함하지 않았다. Debug app/test 컴파일 및 실행 포함.
2. 신규 실제 기록 감사의 최초 harness 컴파일은 타입/속성 오류로 실패했다. 테스트 코드만 바로잡았다. 앱 컴파일 결함으로 분류하지 않는다.
3. `/tmp/FitMatchFrozenActualReplay20260930b.xcresult`, exit 65: 2개 parameterized test / 6 runs 모두 incompleteSnapshot. 원인을 분리하기 위해 점수재생과 hydration을 별도 테스트로 정리하고 재실행했다.
4. 최종 분리 실행 결과는 아래 최종 결과 절에 기재한다.

고정 자료: `FitMatchTests/Fixtures/ReleaseAuditPreviouslyCompleted20260930.json`. user_id/요청해시 등 불필요 필드는 제외. DB 저장 row를 사용하므로 실제 API 신규 응답이나 인증 RPC E2E 재실행을 의미하지 않는다. 배포 함수의 그대로 반환하는 snapshot 계약과 대조했다.

최종 focused 명령:

```bash
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch \
 -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' \
 -derivedDataPath /tmp/FitMatchBuild8Debug -disableAutomaticPackageResolution \
 -parallel-testing-enabled NO \
 -only-testing:FitMatchTests/FrozenReleaseHistoryAuditTests \
 -resultBundlePath /tmp/FitMatchFrozenActualReplay20260930c.xcresult test
```

## 출시 판단

핵심 자동검사가 많이 통과했어도 **현 상태에서 기존 데이터 전체 정상 판정은 불가**. 범위를 확대하기보다 H01 복원 계약을 먼저 고치고 같은 원본 3건을 다시 실행한다. H02/H03은 같은 owner 수정 시 함께 검증할 지점이다. 이번에 원본 데이터/점수/DB 정책을 변경할 이유는 발견하지 않았다.

실기기 공유·제스처·다른 기기 실제 동작 및 새 retailer 응답은 이번 감사 범위 밖이다. 새 데이터 대응 요구를 출시 차단 이유에 추가하지 않았다.

## 최종 결과

- 최종 focused test: **FAIL**, exit65. 2 tests 중1PASS/1FAIL, 6개 동적 실행은 **3PASS/3FAIL**.
- 기존 세 상품 추천 ID·점수 재생: **PASS 3/3**. History 빈 캐시 복원: **FAIL 3/3**, 모두 incompleteSnapshot.
- H02의 실측 수량 assertion은 H01 예외로 도달하지 못함. 해당 assertion 실행 성공/실패로 보고하지 않음.
- Debug app/test build: **PASS**(최종 test 실행까지 컴파일 완료). Release build/실기기 E2E: **NOT RUN**.
- git diff --check: **PASS**. 보호 스크롤 파일 및 call-site diff: **PASS**, PROTECTED_SCROLL_OK.
- 최종 branch/HEAD: connectDB / db190a9c677da0181c4de2910c979a82ca59c1b8. 기존 dirty 보존, commit/push 없음.
- 이번 수정파일: 이 보고서, Handoff, FirstReleaseChecklist; 신규 FrozenReleaseHistoryAuditTests.swift 및 기존 데이터 JSON fixture. 기존 production diff는 이번 감사 변경이 아니다.
