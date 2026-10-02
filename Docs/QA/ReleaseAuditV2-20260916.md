# FitMatch Release Audit v2 — 2026-09-16

## 1. Executive Summary

수정 전 **56.25/100 → 수정 후 56.25/100**

Verification coverage: **새 계약 회귀 7/7 PASS; 전체 출시 검증 confidence LOW**. 전체 앱 검사 7개를 통과했다는 뜻이 아니다.

Release blockers: **옷장 삭제의 서버 완료 전 성공 처리, 서버 후보 판정의 폐기된 reference 권위, 인증된 전체 흐름 미검증**. 이번 조사에서 confirmed P0는 없었다. 이는 P0 부재를 보증하지 않는다.

- 후보 응답의 정확한 상품/옵션 ID 및 중복 Closet ID 검증을 기존 validator에 추가했다. 두 RPC overload에 동일하게 적용했다.
- 일반 iOS 빌드 전후 PASS. 시뮬레이터 실행 없이 실제 DTO/validator 원문으로 로컬 Swift Testing 7개 PASS.
- Product/variant를 바꿔 끼우거나 후보를 deduplicate하는 fallback은 없다. 잘못된 응답을 명시적으로 거절한다.
- Production DB는 metadata/function definition SELECT만 수행했다. RPC 실행·저장·migration·배포는 없었다.
- 운영 함수/옷장 persistence의 남은 P1 cap 때문에 전체 점수는 올리지 않았다.

## 2. Baseline

- Branch: `connectDB`.
- Initial HEAD: `ae69b30ed37386f6361882d36bafbd972235ebd4`.
- 원격 `git ls-remote`: `a68c8496628eb0bc1223b34708fb88e8fe945de1`; local ahead 1. fetch/pull/checkout 없음.
- 수정 전 tracked dirty 43개, staged 0개. untracked 파일 7,405개(기존 빌드 산출물 등 포함). 원문 목록·diff·hash: `/tmp/fitmatch-release-audit-v2/{baseline.json,baseline.diff,untracked.txt}`.
- application/test targets: FitMatch, FitMatchShareExtension, FitMatchTests, FitMatchUITests.
- `Package.swift`는 실제 인증/쓰기 가능한 E2E runner를 포함한다. 실행하지 않았다. 기존 fixture shell runner도 simulator/DB replay 경로가 있어 무조건 실행하지 않았다.
- 초기 sandbox 빌드는 SwiftPM 캐시 접근 `Operation not permitted`로 BLOCKED. 승인된 캐시 접근으로 generic iOS unsigned build 재실행 PASS. 코드 baseline failure로 분류하지 않는다.
- Supabase `get_project`: FitMatch / `hnkplvyegonlhumlejst` / ap-northeast-2 / ACTIVE_HEALTHY / PostgreSQL 17.6. `FitMatch/Info.plist:41`의 동일 endpoint와 일치. 환경은 최신 handoff 및 사용자 프로토콜에 따라 Production.
- 기존 미커밋 코드는 이번 수정 성과로 계산하지 않았다.

## 3. Confirmed Issues / Evidence Ledger

### RA-01 [P1] 후보 응답 identity/중복 검증 누락 — Fixed, targeted Verified

- Actual: mapped 후보 RPC는 UUID decoding 뒤 요청 ID 대조 없이 반환했다. requested-group overload는 ID를 확인했지만 양쪽 모두 후보 ID 중복을 확인하지 않았다.
- Expected: 응답은 요청한 exact product/variant에 속해야 하고 같은 Closet item이 중복되거나 selectable/blocked 양쪽에 있을 수 없다.
- Root cause: transport → candidate projection boundary의 envelope validation 누락.
- Evidence: 수정 전 원문 `/tmp/fitmatch-release-audit-v2/FitMatchSupabaseProductResolver.swift`, 현재 `FitMatchSupabaseProductResolver.swift:2166` 이후 두 overload. `FitMatchServerAuthorityCoordinator.referenceSelectionPlan`은 vNext 목록을 map하며, `CompareFlowSheet.swift:2401` 부근은 `Dictionary(uniqueKeysWithValues:)`로 투영한다.
- Impact: 잘못된 서버 응답이 왔을 때 다른 상품 후보를 표시하거나 중복 키로 종료될 수 있었다. 실제 Production이 이런 응답을 보냈다는 증거 또는 사용자 crash 재현은 확보하지 않았다. **확정한 것은 방어 계약 누락과 그 정적 경로**다.
- Change: 공통 validator 호출. wrong product, wrong variant, candidate duplicate, blocked duplicate, 양쪽 중복 거절.
- Verification: 실제 DTO/validator + 새 테스트 7 PASS, iOS integration build PASS. 네트워크 transport mock/E2E는 NOT RUN.

### RA-02 [P1] 활성 서버 후보 판정에 legacy reference 권위 — Confirmed / Blocked

- Actual: 현재 internal 2-arg `fitmatch_vnext.find_reference_candidates`는 `ci.is_reference desc`로 정렬하고 같은 그룹의 reference를 `AUTOMATIC`, 나머지를 `MANUAL_EXTENDED`로 판정한다. 이어 `eligible_candidate_sizes(..., decision_value <> 'AUTOMATIC')`에 서로 다른 manual-explicit 값을 전달한다.
- public 2-arg wrapper도 `is_current_reference`를 정렬 우선순위에 사용한다. 반환 policy 이름은 `same_group_reference_then_same_group_then_all`이다.
- Expected: v2.0 §10.1에 따라 legacy flag는 신규 후보 정렬·결정의 권위가 될 수 없다. 같은 그룹 우선은 유지 가능하다.
- Caller: `ShoppingProductViewModel` → `FitMatchServerAuthorityCoordinator.referenceSelectionPlan` → `FitMatchSupabaseDomainClient.findReferenceCandidates` → public 2-arg RPC → internal 2-arg 함수. requested-group 3-arg는 별도 경로다.
- Evidence: 이번 READ ONLY `pg_get_functiondef` 원문 `/tmp/fitmatch-release-audit-v2/deployed-functions.json`; DTO는 legacy bool을 facts로 보존하며 UI plan은 서버 순서를 보존한다.
- Impact: legacy flag가 후보 순서와 authorization 입력에 영향을 준다. UI가 후보를 자동 선택한다는 뜻은 아니다. 현재 UI는 `automaticallySelectedCandidate: nil`이다.
- Minimal next repair: 두 2-arg 함수의 reference 기반 정렬/decision을 제거하고 explicit selection으로 통일, 그룹 우선과 기존 ownership/identity/measurement 검증 유지. flag true/false를 바꿔도 후보 순서·eligibility가 동일한 regression 필요.
- Not changed: 운영 함수 수정이 필요하며 이번 프로토콜에서 Production migration/write 금지. Swift에서 서버 정책을 덮어쓰지 않았다.

### RA-03 [P1] 옷장 삭제의 성공 시점이 서버 persistence보다 빠름 — Confirmed / Deferred

- Actual: `FitMatchClosetDeletionAction.swift:77-82`는 로컬 rows 삭제/save → `closetSync?.enqueueDeletion` → `.deleted`. 원격 삭제는 이후 `FitMatchClosetSyncCoordinator.flushPendingDeletes:1145`에서 별도 실행한다.
- Active callers: MyClosetView의 swipe 삭제, ClosetItemDetailView의 삭제 후 dismiss.
- Expected: 최신 §4/11 persistence 원칙상 원격 성공 전 완료 표시 금지.
- Impact: 네트워크/권한/서버 실패 시 앱에서 사라진 옷이 서버 후보에는 남을 수 있다. 실제 사용자 데이터 손실이 발생했다는 증거는 없다.
- Root cause: local-first 삭제 + 후행 큐를 authoritative deletion과 동일한 결과로 표현.
- 최소 설계: exact server ID 확인 → 원격 삭제 receipt 검증 → 로컬 삭제. 계정 변경·재시도·이미 삭제된 항목·History hide 부분 성공·local-only 항목을 별도로 다뤄야 한다.
- Deferred: 한 줄 순서 이동으로 안전하게 끝낼 수 없고, existing dirty sync/action code와 history hide의 여러 persistence 단계가 연결된다. 해당 transaction/계정 전환에 대한 실행 가능한 통합 검증을 확보하지 못했으므로 Auto-Fix Gate를 통과시키지 않았다. 준비된 서버 환경을 허용받거나 격리 DB/인증 fixture로 해당 흐름을 검증한 뒤 처리할 것.

### 이전 감사에서 이어지는 별도 항목

- UNIQLO 두 renamed category path 및 ZARA skirts waist/hip 연결: `Docs/QA/UniqloPathZaraSkirtRepair-20260916.md`와 prepared SQL 참조. **이번에 새로 수정/적용/재검증했다고 계산하지 않는다.** 현재 function definition의 경로 기반 조회는 확인했다.
- ZARA F/G 및 원피스 소매: actual garment evidence 부족. 일괄 매핑하지 않으며 confirmed defect로 계산하지 않는다.

### Needs Evidence / Inactive

- RecommendationService의 local `referenceSelectionPlan` 및 representative ranking은 선언 외 새 비교 caller를 찾지 못했다. 현재 Compare는 coordinator plan을 소비한다. inactive/historical 신호를 별도 defect로 확정하지 않았다.
- legacy candidate validator의 `minimumCommonMeasurements ?? 2`는 실제 production vNext response 경로가 아니다. 활성 adapter는 server minimum 또는 1을 사용한다. 이름 검색만으로 2개 제한 오류라고 하지 않았다.
- 수동 수정 action도 로컬 persistence 경로가 보인다. 수동 등록/수정 전체 parent callback·sync receipt 검증은 미완료이므로 별도 신규 confirmed 항목으로 확대하지 않았다.

## 4. Breadth-first Inventory / Changes

| Subsystem | 확인한 활성 owner / boundary | 이번 검증 범위 |
|---|---|---|
| App/Auth | ContentView → FitMatchAuthSessionStore → Supabase Auth | session/cache ownership gate 소스 확인, 실제 로그인 NOT RUN |
| Share | SharedURLStore → SharedURLHandoffStore → ContentView | pending/expiry/recovery 경로, physical share NOT RUN |
| Providers | ProductURLParserService → UniqloParser / MusinsaParser / ZARAParser | map·parser transport owners 및 category/identity 계약 확인; 최신 live 3회 차단 |
| Product/group | ShoppingProductViewModel → authority coordinator → resolver/Edge/runtime | 활성 caller 확인, 최신 DB function definitions READ ONLY |
| Raw/canonical | source/alias/mapping → context canonical → comparison | 앞선 dictionary 감사와 분리; 새 dictionary write 없음 |
| Closet link/manual | registration views → form/submission action → sync/RPC | URL server-first 경계, manual callback 및 delete 경계 inventory |
| Candidate | coordinator → 2/3-arg RPC → exact DTO → UI projection | RA-01 수정, RA-02 confirmed |
| Comparison/result | completeVNextRecommendation → adapter → completeAuthorizedComparison | server complete 뒤 history/result 생성과 stale request guard 확인 |
| History | ComparisonSyncCoordinator → history/complete RPC → cache | pending replay도 쓰기 경로이므로 실행하지 않음 |
| DB/security | metadata, definitions, RLS policies | 주요 6 table RLS on; closet/comparisons SELECT ownership predicate 확인. 권한 전체 검증 아님 |

실제 앱 수정은 **RA-01 root cause 1개**다. 후보 eligibility, 그룹, 순서, score, size 선택, DB schema, user data는 변경하지 않았다.

## 5. Before / After

| 입력 | Before | After |
|---|---|---|
| 다른 product/variant 응답 | mapped transport에서 decode 후 소비 | contract error로 거절 |
| 같은 Closet ID 두 번 | UI identity dictionary 충돌 가능 | UI 도달 전 거절 |
| candidate와 blocked에 같은 ID | 양쪽에서 상충 상태 노출 가능 | 전체 응답 거절 |
| 정상/빈 후보 목록 | server response 소비 | 기존 순서·legacy fact 그대로 유지 |

## 6. Verification

| Area | Level | Result | Evidence / limitation |
|---|---|---|---|
| baseline generic iOS build | Build | PASS | build-authorized.log; 최초 sandbox 실패 후 재실행 |
| candidate contract | Unit | PASS | 7 tests; production DTO/validator 원문, Swift Testing macOS |
| 정상/빈 목록·order·legacy facts | Adjacent regression | PASS | 위 7개 중 정상 2개; bad envelope 5개 |
| 재사용 스크립트 | Unit harness | PASS | scripts/test-candidate-envelope.sh 실행, 같은 7개 재실행. 총14개 독립시나리오로 세지 않음 |
| final generic iOS build | Build | PASS | build-after.log; code signing disabled |
| iOS-hosted test suite | Regression | NOT RUN | simulator 금지 유지; macOS contract subset과 구분 |
| production function/RLS metadata | Static/live DB | PASS | READ ONLY SELECT; 실제 RPC 실행 아님 |
| MUSINSA detail 4096130 | Live | BLOCKED | HTTP403 |
| UNIQLO E488182 detail | Live | BLOCKED | 25초 timeout, HTTP000 |
| ZARA guide 551168852 | Live | BLOCKED | HTTP403 |
| 로그인→등록/read-back→비교→History | Integration/E2E | NOT RUN | Production write 금지; 격리 환경 전체 replay 미실행 |
| protected scroll / whitespace | Static | PASS | 최종 git diff 검사 |

로그 root: `/tmp/fitmatch-release-audit-v2/`. 해당 폴더의 정상 응답/오류 로그를 저장했으며 credential 출력 없음.

빌드 경고: final build에는 3개 Swift warning(기존 nonisolated actor 접근 2개, 기존 never-mutated 변수 1개) 및 AppIntents metadata warning이 있다. 새 validator/호출부 warning은 없다. baseline incremental build에서 동일 파일이 재컴파일되지 않았으므로 경고 수 전후 차이를 새 회귀/해결로 계산하지 않았다.

## 7. Verification Gaps

- 새로운 실제 provider JSON을 확보하지 못해 이번 HTTP probe를 Parser PASS로 표현할 수 없다.
- current iPhone 바이너리/설치 상태·iOS17 runtime·실제 화면·Share Sheet·performance profiling 미검증.
- 로그인 session/RLS 다중 사용자 테스트와 persistent Closet/History 검증 미실행. metadata RLS 확인은 security PASS 보증이 아니다.
- candidate transport의 네트워크 응답 주입 테스트는 미실행; 두 production caller 연결은 소스 확인 + iOS compile, validation 자체는 native unit으로 검증했다.

## 8. Remaining Issues

1. RA-02: Production 함수에 남은 reference 결정 권위. 정책과 충돌하지만 운영 변경 금지로 미적용.
2. RA-03: 삭제 receipt 이전 local 성공. 다단계 persistence 및 계정 전환 regression 환경을 먼저 확보해야 함.
3. 이전 UNIQLO path / ZARA skirt prepared repair: 운영 적용 없음, 실제 skirt raw/value 최종 비교 증거도 없음. 이전 보고서의 증거 수준 유지.

## 9. Modified Files (this audit only)

- `FitMatch/Services/FitMatchVNextContractValidator.swift`: candidate envelope validator.
- `FitMatch/Services/FitMatchSupabaseProductResolver.swift`: 두 candidate RPC 응답에 validator 적용.
- `FitMatchTests/FitMatchCandidateEnvelopeTests.swift`: 새 독립 contract 7개.
- `scripts/test-candidate-envelope.sh`: simulator/DB 없는 재실행 방법.
- `FitMatch Behavior Map.md`: 검증 경계 및 latest no-write 정책 반영.
- `Docs/CodexSessionHandoff.md`: 실제 수정/결과/미검증/새 정책 기록.
- 이 보고서.

## 10. Production Safety

**이번 v2 실행 동안** Production DB write 없음 / migration apply 없음 / user data 변경 없음 / deploy 없음 / mutating RPC 호출 없음. 이전 대화의 승인된 적용과 이번 작업을 혼동하지 않는다.

## 11. Final Git State

- `connectDB`, HEAD `ae69b30ed37386f6361882d36bafbd972235ebd4` 그대로.
- staged 0개, 최종 untracked 7,408개(기존 7,405개 + 새 test/script/report 3개). staging/commit/push 없음. 기존 tracked dirty 43개를 보존했다. 이번 변경은 그중 resolver/validator/handoff 및 기존 untracked map에만 추가했고 새 test/script/report를 만들었다.
- 기존 untracked/build 산출물 삭제·정리 없음. 최종 baseline hash 비교로 나머지 기존 tracked dirty 파일 불변 확인.

## 12. Final Score

이 점수는 사용자 지정 cap을 적용한 **보수적 release gate 지표**이며 버그 확률 또는 완성률이 아니다. 소스 수정 전 `/tmp/fitmatch-release-audit-v2/score-before.json`에 고정했다.

| 영역 | 전 → 후 | cap 근거 |
|---|---:|---|
| 기능 | 10/20 → 10/20 | RA-03 및 서버 후보 RA-02 unresolved P1 |
| 데이터/contract | 10/20 → 10/20 | RA-01 targeted fix 뒤에도 RA-02/03 unresolved |
| 안정성 | 10/20 → 10/20 | 서버 실패 시 삭제 성공 표현 RA-03 unresolved |
| 흐름 | 7.5/15 → 7.5/15 | RA-02/03 사용자 결과와 표시 시점 불일치 |
| 테스트 | 7.5/10 → 7.5/10 | authenticated core flow material gap |
| 성능 | 3.75/5 → 3.75/5 | 실제 core flow latency 측정 미검증 |
| 보안/데이터 안전 | 3.75/5 → 3.75/5 | auth/RLS runtime isolation 검증 gap |
| 유지보수/관측 | 3.75/5 → 3.75/5 | 실제 core failure 진단 전달까지 미검증 |
| 합계 | **56.25 → 56.25 / 100** | 격리된 계약 fix를 전체 출시 개선으로 과장하지 않음 |

최종 판단: **출시 승인 보류**. 로컬 안전 수정 1건은 검증됐지만 전체 등록·비교 정상 여부는 확인되지 않았다.
