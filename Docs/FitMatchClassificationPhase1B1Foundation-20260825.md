# FitMatch Classification Authority Phase 1B-1 — DB Foundation & Shadow Contract

Date: 2026-08-25

Repository: `ljy4337/FitMatch`

Branch: `connectDB`

Supabase project: `hnkplvyegonlhumlejst`

> **2026-08-26 Migration 115 final-correction addendum:** Raw payload classifier-policy override를 제거하고 classifier version을 selected release-only로 고정했다. Evaluator는 `comparison_policy_version`, `compatibility_rule_version`, `measurement_policy_version`을 분리한다. PostgreSQL 17 disposable local DB에서 corrected `113 -> 114 -> 115`, 두 번의 validation `ROLLBACK`, current exact-file 115 reapply가 모두 PASS했다. 아래 최초 작성 당시의 “actual DB validation 미실행 / Phase 1B-2 NO-GO” 문구는 [FitMatchClassificationPhase1B1Validation-20260825.md](FitMatchClassificationPhase1B1Validation-20260825.md)의 최종 증거로 대체된다. 현재 결론은 **Phase 1B-2 candidate-data GO / production activation NO-GO**다.

## 1. 결론

- **Phase 1B-1 repository foundation 구현은 완료했다.** Migration 115와 local/staging 전용 validation SQL을 추가했고, 네 contract를 다음 Phase에서 그대로 production call site에 연결할 최종 후보로 정의했다.
- **Phase 1B-2 실행 gate는 현재 NO-GO다.** 안전한 local/staging PostgreSQL에서 `113 -> 114 -> 115` 실제 apply와 validation transaction을 실행하지 못했다. 이 검증이 PASS하면 candidate-release 작업은 진행할 수 있다.
- `BOTH_UNTRUSTED` 310 products, manual review 1,037 products, replacement tuple 미확정 mapping, live network comparison 71은 foundation blocker가 아니다. Phase 1B-2 candidate에서는 `review_required` / `product_required` / invalid fail-closed로만 연결하며, **production activation blocker로 유지**한다.
- Phase 1B-2와 production activation을 시작하지 않았다.
- Production DB write 0, migration apply 0, active release change 0, history append/supersede 0, Swift production change 0이다.
- 신규/삭제 table 0, `DROP` 0, `TRUNCATE` 0, production data update/delete 0이다.

이 결과는 FitMatch 분류 시스템 완성이 아니다. 완성은 자동 closet 등록과 자동 비교가 같은 server authority를 사용하고, server-confirmed와 explicit user override가 분리되며, unresolved가 fail-closed하고, tuple·measurement compatibility를 통과하기 전 추천하지 않는 production 전환까지 끝났을 때만 선언할 수 있다.

## 2. 시작/종료 상태

| 항목 | 시작 | 종료 |
|---|---|---|
| branch | `connectDB` | `connectDB` |
| HEAD | `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab` | `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab` |
| production active release | `65d72393-4a40-4e99-b701-fdc1ff865774` | 동일 |
| production migration ledger latest | `20260821090138` | 동일 |
| production DB mutation | 0 | 0 |

기존 Phase 1A/1A.5 보고서, JSONL, handoff의 사용자 변경은 reset/revert하지 않았다.

## 3. 변경 파일

| 파일 | 역할 |
|---|---|
| `supabase/migrations/115_authoritative_classification_foundation.sql` | additive columns, constraints, FK, 네 최종 후보 internal contract |
| `supabase/sql/115_authoritative_classification_foundation_validation.sql` | local/staging 전용 static/runtime/rollback fixture assertions |
| `Docs/FitMatchClassificationPhase1B1Foundation-20260825.md` | 본 Phase 증거와 activation map |
| `Docs/CodexSessionHandoff.md` | 누적 handoff 갱신 |

SQL checksum:

- Final corrected Migration 115 SHA256: `1d09dcde02a2d1728322b2bcb5b1eb567f4918ecbd9936f386a817f5d0a1e799`
- Final Validation SQL SHA256: `06a54982540da4b6ffa8f3ea05ffe1e662072bb3e8cf40e90b06c3ace230d0e4`
- Local fixture SHA256: `2830bea1fe32018b04b55a53a647707ac6677a3e9a82f461e5b62bd114d66980`

Swift production file과 protected `FitMatch/Components/TabBarScrollVisibilityModifier.swift`는 수정하지 않았다.

## 4. Migration 114 상태와 prerequisite 판정

### 4.1 Repository

- `supabase/migrations/114_release_gate_and_quality_review_queue.sql`은 이미 존재한다.
- Migration 115는 다음 114 소유 object를 재정의하지 않는다.
  - release validation/gate columns
  - `releases_one_active_idx`
  - `runtime_release_gate_report`
  - `enforce_release_activation_gate`
  - `runtime_activate_validated_release`
  - data-quality triage columns
  - `data_quality_review_queue`
  - `runtime_triage_data_quality_issue`
- 115는 114 function/view와 trusted grant boundary를 시작 시 검사하고, 하나라도 없거나 `anon`/`authenticated`가 activation/triage function을 실행할 수 있으면 transaction을 중단한다.
- 114 view는 migration 113의 observability columns를 참조하므로, 안전한 검증 순서는 **113 -> 114 -> 115**다.

### 4.2 Production SELECT-only introspection

- Production ledger에는 local migration 113/114/115가 없다.
- Production의 080–112 계열은 repository numeric filename과 동일 version이 아니라 timestamp ledger name으로 적용돼 있다. Numeric 113–115는 latest timestamp보다 정렬상 과거이므로 일반 `db push`가 자동 pending 순서로 처리한다고 가정할 수 없다.
- `runtime_release_gate_report`, `runtime_activate_validated_release`, `runtime_triage_data_quality_issue`, `data_quality_review_queue`와 114 triage/release columns가 없다.
- `releases_one_active_idx`와 동등한 single-active invariant는 114 이전 schema에 이미 존재하지만, 이것만으로 114 적용 완료로 보지 않았다.
- 따라서 production에 115를 단독 적용할 수 없고, 이번 Phase에서는 113/114/115 모두 적용하지 않았다.

### 4.3 114 검증 범위

- PostgreSQL top-level parser로 114 SQL 전체 parse는 PASS했다.
- 개별 PL/pgSQL function 중 release report, activation, triage function parse는 PASS했다.
- `enforce_release_activation_gate`는 trigger `NEW`/`OLD` record를 다루는 `pglast` JSON serializer 한계로 PL/pgSQL 보조 parse 결과를 직렬화하지 못했다. SQL parse 실패나 DB compile 실패로 판정하지 않았고, 실제 PostgreSQL apply 검증 대상으로 남겼다.
- 114에 명백한 오류를 발견하지 않았고 114 파일을 수정하지 않았다.

## 5. Migration 115 schema

### 5.1 `fitmatch_catalog.product_classification_decisions`

Additive columns:

- `garment_type_code text null`
- `authority_status text not null default 'legacy'`

Constraints:

- authority lifecycle는 `legacy`, `verified`, `revoked`만 허용한다.
- `verified` row는 category/detail/garment/family가 모두 존재하고 `requires_user_confirmation=false`여야 한다.
- 기존 PK `(source, external_product_id)`는 유지한다.
- `public.garment_types(code)`는 production에서 38 rows / 38 distinct / duplicate 0이고 valid single-column UNIQUE가 확인되어 nullable FK를 추가했다. FK는 `ON UPDATE/DELETE RESTRICT`다.
- migration 자체에 existing 5,056 rows UPDATE가 없다. PostgreSQL default에 의해 전부 `legacy`로 읽히며 garment는 NULL로 보존된다.

### 5.2 `fitmatch_catalog.product_classification_history`

- `garment_type_code text null`만 추가한다.
- 기존 1,860 rows UPDATE 0, current supersede 0, append 0이다.
- 한 product당 current exactly-one invariant를 변경하지 않는다.

### 5.3 변경하지 않은 schema

- `fitmatch_catalog.products`
- `fitmatch_catalog.product_observations`
- `public.closet_items`
- comparison runs/history
- variants, sizes, measurements
- taxonomy/policy data rows
- `garment_types_major_category_code_check`와 `comparison_groups_major_category_code_check`; 현재 허용 major에 dresses/underwear/homewear가 없으며 이번 Phase에서는 변경하지 않음

## 6. 네 최종 후보 contract

### 6.1 `runtime_validate_classification_tuple_v1`

Signature:

```sql
fitmatch_catalog.runtime_validate_classification_tuple_v1(
  text, text, text, text, text, text
) returns jsonb
```

- `app_categories` major/detail parent 관계, active garment/major, active comparison group/major, garment-to-family를 각각 검사한다.
- sleeve/pants/body required axes를 garment metadata에서 읽는다.
- NULL, `unknown`/axis-specific unknown, `not_applicable`, valid axis code를 서로 다르게 판정한다.
- structural blockers만 반환하며 mapping/decision authority conflict를 포함하지 않는다. 따라서 Phase 1A.5 K bucket처럼 tuple이 구조적으로 valid인 conflict row는 `valid=true`가 가능하다.
- 반환 contract는 `valid`, `blockers`, `normalized`, `required_axes`, `contract_version=classification-tuple-v1`다.
- `STABLE`, `SECURITY INVOKER`, empty `search_path`, side effect 0이다.

### 6.2 `runtime_resolve_product_classification_v4`

Signature:

```sql
fitmatch_catalog.runtime_resolve_product_classification_v4(
  text, text, text, text, jsonb, uuid
) returns jsonb
```

Classifier profile version은 raw `p_payload`가 아니라 selected release의
`validation_report.runtime_policy_contract.classifier_policy_version`에서만
읽는다. Version이 없으면 verified exact decision/direct mapping은 계속
평가할 수 있지만 name/path/exclusion profile authority는 사용하지 않는다.

Authority order:

1. fingerprint가 일치하고 tuple-valid인 `verified` exact product decision
2. candidate/active release의 verified `category_direct` mapping 중 confirmed/direct/eligible/tuple-valid/conflict-free row
3. policy version이 일치하고 evidence로 independently verified된 auto-eligible name/path profile
4. fingerprint가 일치하고 tuple-valid/conflict-free인 `legacy` exact decision; `legacy_authority=true`
5. independently verified exclusion; `not_comparable`
6. 나머지; `review_required`

Fail-closed details:

- current legacy mapping은 `raw_record.authorityContract`가 없으므로 v4에서 자동으로 trusted direct가 되지 않는다.
- Phase 1B-2 mapping data는 `authorityStatus=verified`와 `resolutionScope=category_direct|product_required`를 명시해야 한다.
- ambiguous mapping, product-required mapping, invalid tuple, unverified authority, unresolved conflict는 confirmed로 승격하지 않는다.
- invalid verified decision은 낮은 authority로 조용히 fall through하지 않는다.
- revoked decision은 무시하되 evidence에 unresolved reason을 남긴다.
- verified exact decision이 lower-priority mapping과 다를 때 verified decision은 우선하되 conflict를 `authority_conflicts`에 숨기지 않는다.
- unknown을 임의의 tops/tshirt/other tuple로 보정하지 않는다.
- 요청된 additive response field 전부를 반환한다.
- `STABLE`, `SECURITY INVOKER`, empty `search_path`, side effect 0이다.

### 6.3 `runtime_record_product_classification_v2`

Signature:

```sql
fitmatch_catalog.runtime_record_product_classification_v2(uuid, jsonb)
returns uuid
```

- `garment_type_code`와 body axis를 포함해 history를 append한다.
- product row lock 후 기존 current를 supersede하고 새 current를 insert한다.
- historical DELETE가 없고, 종료 시 current exactly-one을 재검사한다.
- confirmed resolution은 tuple validator PASS와 `requires_user_confirmation=false`를 강제한다.
- 기존 recorder signature/definition을 변경하지 않는다.
- migration/production에서 호출하지 않는다. Validation fixture는 transaction rollback 내부 호출만 정의했다.

### 6.4 `runtime_evaluate_comparison_profiles_v4`

Signature:

```sql
fitmatch_catalog.runtime_evaluate_comparison_profiles_v4(
  text, text, text, text, text, text,
  text, text, text, text, text, text,
  text, text, boolean, uuid
) returns jsonb
```

- v3의 첫 12 profile arguments를 유지하고 reference/target garment type과 selected release ID를 추가했다. NULL release ID는 active release를 읽는다.
- Release runtime contract는 classifier/comparison-policy/compatibility-rule/measurement 네 version을 별도 field로 고정한다.
- `comparison_policies`, `comparison_compatibility_rules`, `app_category_measurement_policies`는 각각 자기 version field와 exact match하는 row만 사용한다. 단일 compatibility version으로 두 저장소를 합치거나 여러 measurement version을 혼합하지 않는다.
- Missing contract/row는 `runtime_policy_contract_missing`, `comparison_policy_version_missing`, `compatibility_rule_version_missing`, `measurement_policy_version_missing`으로 구분해 fail-closed한다.
- 양쪽 tuple, garment/group, comparison policy, major-category measurement policy, required group/minimum dimensions를 검증한다.
- `base_layer_top`과 `tshirt` 자동 비교를 명시적으로 차단하고 base-layer를 generic underwear로 병합하지 않는다.
- cross-family는 현재 compatibility-rule contract가 있을 때만 허용한다.
- required length/body mismatch는 automatic=false이고, explicit extended 요청에서만 관련 measurements를 제외한다.
- Dresses는 canonical contract/measurement policy가 준비되지 않으면 false다.
- Underwear는 명확한 subtype 없이는 false이고 generic underwear는 false다.
- Homewear Option A를 고정한다: display/canonical major `homewear`, future `homewear_top`/`homewear_bottom`/`homewear_set`; 이번 Phase에 row를 seed하지 않아 false다. tops/bottoms 강제 이동이나 generic homewear auto 비교는 없다.
- measurement policy가 불완전하면 추천 이전 단계에서 false다.

### 6.5 Security와 public exposure

- 네 function 모두 `PUBLIC`, `anon`, `authenticated` execute를 revoke하고 `service_role`만 grant한다.
- public preview RPC는 만들지 않았다. SQL validation은 internal function을 직접 호출하도록 작성했다.
- 기존 public RPC는 하나도 v4로 전환하지 않았다.

## 7. Validation SQL contract

`supabase/sql/115_authoritative_classification_foundation_validation.sql`은 **LOCAL/STAGING ONLY**이며 전체를 transaction으로 감싸 마지막에 `ROLLBACK`한다.

Assertions:

- additive columns, checks, FK 존재
- decisions 5,056 전부 legacy / garment NULL
- history 1,860 / current 1,608 / garment NULL
- products 1,608 / measurements 28,418 불변
- old v2/v3/recorder/public RPC definition hash와 internal/public role grant matrix 불변
- existing DB validator v3 PASS
- 114 gate/view/grant 존재와 current mapping-only release gate rejection
- 네 새 function의 service-role-only boundary
- valid tshirt, valid base-layer, category/detail mismatch, garment/category mismatch, garment/family mismatch, required sleeve states, skirt body axis, K-style structural-valid case
- verified decision, revoked decision, clear direct mapping, product-required, invalid mapping, legacy, both-untrusted, verified profile/exclusion, raw payload policy spoof rejection resolver cases
- recorder v2 append/supersede, invalid-confirmed rejection, exactly-one invariant
- distinct comparison/rule/measurement version pinning, typed compatibility semantics, tshirt/base-layer, underwear, homewear, dresses evaluator cases
- fixture가 baseline-shaped counts를 벗어나지 않음
- 모든 synthetic write rollback

Baseline count가 정당한 별도 작업으로 변한 경우 숫자를 현재 결과에 자동 맞추지 않는다. 새 snapshot을 확인하고 drift 원인을 adjudicate한 뒤 validation expectation 변경 여부를 별도로 승인한다.

## 8. 검증 결과

### 8.1 실제 실행 PASS

| 검증 | 결과 |
|---|---|
| Migration 113 top-level SQL parse | PASS |
| Migration 114 top-level SQL parse | PASS |
| Migration 115 top-level SQL + PL/pgSQL parse | PASS |
| Validation SQL top-level SQL + PL/pgSQL parse | PASS |
| Migration 115 idempotency guard static check | PASS: 3 additive columns guarded, named constraints guarded, 4 functions `create or replace`, grants/comments repeat-safe |
| `git diff --check` + untracked artifact whitespace checks | PASS |
| Swift production diff | 0 |
| protected TabBar file/modifier call-site diff | 0 |
| Production `fitmatch_qa.validate_product_runtime()` | PASS |
| Production `fitmatch_qa.validate_product_runtime_v2()` | PASS |
| Production `fitmatch_qa.validate_product_runtime_v3()` | PASS |
| Production 5,026 parity | 5,026 / 5,026, mismatch 0 |
| Local `CategoryValidation5026AuditTests` | 1/1 PASS, input/unique/output 5,026, invalid 0 |
| Local `CategoryLive300ShadowAuditTests` | 1/1 PASS, 300 unique |

Xcode result bundles:

- 5,026: `/tmp/FitMatchPhase1B1-5026-20260825.xcresult`
- Live300: `/tmp/FitMatchPhase1B1Live300-20260825.xcresult`

별도 SQL formatter/linter binary는 설치되어 있지 않아 SKIP했고, PostgreSQL grammar/PL/pgSQL static parse로 대체했다.

Live300 distribution:

- confirmed 243
- review_required 29
- unclassified 28
- silent conflict confirmation 0
- strict comparison conflict leak 0
- independent Gold label 0

5,026와 Live300은 현재 classifier의 regression/self-consistency 증거다. Phase 1A.5의 structural/semantic adjudication을 뒤집거나 “오분류 0”을 증명하지 않는다.

### 8.2 PostgreSQL 17 actual apply/runtime validation PASS

- Existing Homebrew PostgreSQL `17.11` formula binary로 `/tmp/FitMatchPostgres17-20260826-072435`, port `55432` disposable cluster를 구성했다. `brew services start`와 port 5432는 사용하지 않았다.
- Production-shaped synthetic fixture 후 migration 113 `0.04s`, 114 `0.03s`, corrected 115 `0.04s`로 실제 COMMIT됐다.
- Validation transaction은 `0.10s`와 `0.09s`에 두 번 PASS하고 각각 명시적 `ROLLBACK`으로 끝났다.
- Current exact-file 115 reapply는 `0.04s` PASS했다. Duplicate column/constraint/function/trigger는 0이다.
- 114 trigger/gate/view/grant와 115 function/CHECK/FK/recorder/evaluator runtime assertions가 실제 PostgreSQL catalog에서 PASS했다.
- Post-rollback synthetic counts와 old v2/v3/public RPC combined definition hash가 불변이었다.
- Cluster와 temporary formula support symlink는 검증 종료 후 삭제했다. 상세 증거는 final validation report를 따른다.

## 9. Production behavior 불변 증거

Production SELECT-only 시작/종료 counts:

| object | 시작 | 종료 |
|---|---:|---:|
| product decisions | 5,056 | 5,056 |
| classification history | 1,860 | 1,860 |
| current classification | 1,608 | 1,608 |
| products | 1,608 | 1,608 |
| product measurements | 28,418 | 28,418 |
| closet items | 6 (active 1) | 6 (active 1) |
| comparison runs | 0 | 0 |

추가 확인:

- active release ID 불변
- production new columns/functions와 114 gate/queue는 종료 시에도 없음
- 기존 internal v2/v3/recorder/evaluator와 public resolve/runtime/candidate/begin RPC definition hash 불변
- public RPC argument와 output을 수정하지 않음
- source mapping 3,492, decisions 114, Gold 3, history, review queue에 write 0
- Swift production diff 0

## 10. Activation map — 동일 contract의 production 승격 경로

다음 Phase에서 v5나 parallel resolver를 만들 계획은 없다. 실제 PostgreSQL apply에서만 발견되는 contract-breaking 기술 문제가 없다면 이번 네 object를 그대로 연결한다.

### 10.1 기존 DB function/RPC 전환

| 현재 call site | 현재 authority | 전환 내용 |
|---|---|---|
| `fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)` | resolver v3 + old recorder | resolver v4 + recorder v2 호출; garment/body/authority evidence 전달 |
| `public.fitmatch_process_product_observation(uuid)` | 위 promote function 간접 호출 | argument 유지; promote 전환을 통해 v4 사용 |
| `public.fitmatch_resolve_product(jsonb)` | current history 또는 legacy resolver candidate | arguments/기존 JSON key 유지; v4와 additive fields 연결 |
| `public.fitmatch_get_product_runtime(jsonb)` | current history projection | garment/authority/release/tuple/policy additive projection |
| `fitmatch_catalog.runtime_evaluate_product_compatibility(uuid,uuid,boolean)` | evaluator v3 | 양쪽 garment type을 읽어 evaluator v4 호출 |
| `public.fitmatch_find_reference_candidates(uuid)` | evaluator v3 | candidate tuple/measurement gate를 evaluator v4로 전환 |
| `public.fitmatch_begin_comparison(uuid,uuid,boolean,uuid)` | evaluator v3 | recommendation 이전 final server gate를 evaluator v4로 전환 |

`fitmatch_process_product_observation`, batch ingest, existing observation pipeline의 public contract는 새 resolver를 별도로 복제하지 않고 `runtime_resolve_and_promote_product` 한 곳을 통해 같은 v4 algorithm을 사용한다.

### 10.2 Phase 1B-2 data와 object 연결

| Phase 1B-2 data | 연결 contract |
|---|---|
| 3,492-row successor mapping release | v4가 `authorityContract.authorityStatus`와 `resolutionScope`를 읽음 |
| category-direct 34 | verified direct로 명시한 row만 mapping authority path 진입 |
| product-required 989 | `product_required`로 명시하여 category-only confirmation 차단 |
| structurally invalid 369 | invalid tuple/review로 fail-close; replacement 미확정 row 자동 보정 금지 |
| targeted decision plan 114 | `garment_type_code`와 `authority_status=verified|revoked`를 채워 exact-product path 연결 |
| Gold E482514/E454311/E456567 | 114 plan의 owner-verified tuple로 v4 validator/resolver 연결 |
| BOTH_UNTRUSTED 310 | 승자 선택 없이 conflict evidence + review_required |
| manual review 1,037 | 114 review queue contract에 적재하되 resolver confirmed authority로 사용하지 않음 |
| future verified name/path profiles | policy version + verified evidence + full tuple가 있을 때만 v4 path 진입 |
| Homewear Option A taxonomy/policy | future subtype/group/policy rows가 모두 존재하기 전 evaluator v4 false |
| activation 후 reclassification | recorder v2 append/supersede; 기존 history delete 0 |

Successor release는 active 3,492를 clone하되 active release를 in-place 수정하지 않는다. Candidate data validation과 release gate를 통과하기 전 active 전환은 없다.

### 10.3 Phase 2 정확한 Swift call site

| 파일/call site | additive 전환 |
|---|---|
| `FitMatch/Services/FitMatchSupabaseProductResolver.swift:22` `FitMatchDatabaseClassification` | `garmentTypeCode`, `authorityStatus`, `mappingReleaseID`, `tupleValidation`, `classifierPolicyVersion` optional decode |
| 같은 파일 `:739` `FitMatchLocalClassificationSnapshot.matches` | garment와 authority 의미를 포함하고 local snapshot을 server authority로 오인하지 않음 |
| 같은 파일 `:922` `resolve` | additive `fitmatch_resolve_product` response 소비 |
| 같은 파일 `:1014`, `:1026`, `:1040` | runtime/candidate/begin response의 server tuple/measurement gate 소비 |
| `FitMatch/Services/FitMatchClosetSyncCoordinator.swift:204` `makeUpsertRequest` | server-confirmed와 explicit user override 분리 유지, garment 전달 |
| 같은 파일 `:360` `classificationDiffers` | garment axis를 diff에 포함 |
| `FitMatch/Services/FitMatchComparisonSyncCoordinator.swift:133` | resolve -> runtime -> candidates -> begin 전 구간에서 같은 server authority 요구 |
| `FitMatch/ViewModels/ShoppingProductViewModel.swift:254` | DB resolution을 authoritative result로 소비 |
| 같은 파일 `:544`, `:591`, `:616`, `:643` | local classifier/profile을 server confirmation과 분리 |
| `FitMatch/Services/CanonicalComparisonProfileResolver.swift:24` | UI/offline projection으로 한정; server-confirmed authority 생성 금지 |
| `FitMatch/Services/ComparisonProfileMatcher.swift:227`, `:811`, `:890` | server evaluator result 이후 offline/manual 보조로 한정 |
| `FitMatch/Services/RecommendationService.swift:49`, `:201`, `:295` | server measurement compatibility가 허용하기 전 recommendation 금지 |
| `FitMatch/Views/CompareFlowSheet.swift:1092`, `:1207`, `:1605`, `:1655` | local matcher 결과를 automatic server allow로 승격하지 않음 |

기존 Parser, measurement parsing/storage, manual input, closet sync, comparison sync API arguments는 제거하지 않고 additive response를 소비한다.

### 10.4 최종 전환 후 authority가 아닌 legacy path

- resolver v2/v3와 old recorder는 runtime write authority가 아니다.
- evaluator v3는 automatic comparison/recommendation authority가 아니다.
- Swift `ParsedClosetClassification`, `CanonicalComparisonProfileResolver`, `ComparisonProfileMatcher`는 offline/UI/manual assistance가 될 수 있지만 server-confirmed를 생성하지 않는다.
- source-specific Parser는 source facts를 수집하지만 canonical authority를 소유하지 않는다.
- explicit user override는 server-confirmed와 별도 authority로 유지하며 legacy로 폐기하지 않는다.
- 이전 object는 Phase 1B-1에서 drop하지 않는다. 전환·관찰 후 별도 deprecation 승인 전까지 compatibility fallback으로만 보존한다.

### 10.5 Phase 1B-1에서 production 사용처가 없는 object

- resolver v4, recorder v2, evaluator v4는 **의도적으로 production caller 0**이다. 이번 Phase의 production behavior-change 금지 조건 때문이다.
- tuple validator는 새 resolver/recorder/evaluator 세 곳에서 이미 내부 사용한다.
- 나머지 세 object도 위 activation consumer가 정확히 정해져 있으므로 임시 실험물이나 목적 없는 dead code가 아니다.
- public preview RPC는 만들지 않아 사용처 없는 public surface도 없다.

## 11. Migration risk

1. **Apply-order/ledger risk:** production은 113/114가 없으므로 115 단독 apply는 의도적으로 실패한다. Repository numeric versions와 production timestamp ledger가 다르므로 preview에서 113 -> 114 -> 115의 controlled apply/ledger reconciliation을 검증해야 하며 production migration repair를 추측으로 실행하면 안 된다.
2. **Fixture parity risk:** production catalog에서 필요한 contract를 SELECT-only로 확인해 synthetic schema를 만들었지만 production user/raw data 전체를 복제하지 않았다. Local PASS는 compile/contract 증거이지 candidate distribution 또는 production data-lock 증거가 아니다.
3. **Compile risk resolved locally:** PostgreSQL 17에서 113/114/115 function/trigger/FK/check actual compile과 runtime validation을 통과했다. Production apply는 여전히 별도 승인 전 금지다.
4. **Constraint scan/lock risk:** production 5,056 decision rows에 CHECK/FK를 추가하는 실제 lock duration은 미측정이다. Migration의 10s lock timeout과 180s statement timeout을 유지하고 controlled deployment window에서 확인해야 한다.
5. **Authority metadata risk:** current mappings는 새 `authorityContract`가 없어 자동 direct로 승격되지 않는다. Candidate data가 이를 누락하면 대량 review_required가 정상적인 fail-closed 결과다.
6. **Taxonomy gap risk:** dresses/underwear/homewear garment/group/policy rows가 현재 없거나 불완전하므로 evaluator는 false다. 두 major-category CHECK도 현재 이 세 major를 허용하지 않으므로 constraint policy를 별도 승인하기 전 row seed가 불가능하다. 임의 fallback을 추가하지 않는다.
7. **Count drift risk:** validation은 Phase 1A.5 baseline counts를 고정한다. 정당한 concurrent data change가 있으면 원인 확인 없이 expected를 변경하지 않는다.
8. **Future wrapper security risk:** public/authenticated wrapper는 `SECURITY DEFINER`, fixed search path, ownership과 grants를 별도 review해야 한다. Internal functions를 anon/authenticated에 직접 grant하지 않는다.
9. **FK child-index review:** nullable decision `garment_type_code` FK의 supporting index는 PostgreSQL best practice지만 이번 exact scope가 columns/functions/required constraints로 제한되어 추가하지 않았다. Existing 5,056 rows는 모두 NULL이고 referenced garment update/delete는 RESTRICT다. Candidate 규모·advisor/EXPLAIN을 staging에서 확인한 뒤 별도 additive index 승인 여부를 결정한다.

## 12. Rollback

### 12.1 현재

Production에 적용하지 않았으므로 DB rollback 작업은 없다. Repository 변경만 존재한다.

### 12.2 Future pre-activation apply

- 113/114/115 또는 validation이 transaction 중 실패하면 전체 transaction rollback을 확인한다.
- 115가 적용됐지만 activation하지 않은 상태의 가장 안전한 operational rollback은 public call site를 연결하지 않고 additive object를 dormant로 두는 것이다. Data/table delete가 필요 없다.
- 새 column이 모두 미사용/NULL임을 증명하고 별도 owner 승인을 받기 전에는 column/function drop migration을 만들지 않는다.

### 12.3 Future post-activation rollback

- public/internal callers를 v3/old recorder/evaluator v3 compatibility path로 되돌린다.
- candidate release를 inactive/revoked/superseded 처리하고 release gate를 거쳐 직전 validated release로 전환한다.
- recorder v2가 만든 history는 historical snapshot으로 보존한다. DELETE하지 않고 필요 시 새 current row를 append/supersede한다.
- closet/reference와 comparison history를 삭제하지 않는다.

## 13. Phase 1B-2 exact prerequisites

Phase 1B-2 명령을 실행하기 전에 다음을 모두 만족해야 한다.

1. pre-080 production baseline schema가 포함된 disposable clone/staging Supabase 확보
2. clone 위에 pending chain 113 -> 114 -> 115를 실제 apply
3. numeric repository file와 timestamp migration ledger 차이를 preview에서 reconcile하고, 일반 `db push`/repair가 아니라 재현 가능한 적용 명령과 ledger 결과를 기록
4. 114 release gate/view/trigger/grant runtime validation PASS
5. 115 네 function 실제 compile 및 validation SQL 전체 PASS/ROLLBACK
6. validation 전후 baseline-shaped counts와 old v2/v3/public RPC hashes 불변 확인
7. successor mapping 3,492 manifest 준비: direct 34, product-required 989, invalid 369, 나머지 rejected/excluded를 mutually exclusive하게 표시
8. targeted decision 114 manifest에 garment/authority/fingerprint/evidence를 전수 명시; Gold 3 tuple 고정
9. BOTH_UNTRUSTED 310과 manual review 1,037을 confirmed로 자동 확정하지 않는 fixture
10. Dresses/underwear/homewear row를 seed하려면 두 existing major-category CHECK의 확장 정책과 non-destructive migration을 먼저 별도 승인; 승인 전에는 row seed 없이 fail-close
11. Homewear Option A contract 유지; subtype/group/policy seed가 없다면 auto=false fixture 유지하고, future group을 seed해도 Phase 1B에서는 `is_auto_comparable=false`
12. candidate release `runtime_policy_contract`에 classifier/comparison-policy/compatibility-rule/measurement 네 field를 모두 명시
13. production activation 전 114 gate 또는 후속 gate가 각 selected version의 required row/checksum과 `runtime_policy_contract_validated=true` 또는 동등 evidence를 검증; 미충족 시 activation NO-GO
14. candidate release gate input/QA evidence 준비; active release mutation 금지
15. activation 전 live comparison 71과 unresolved replacement tuple을 별도 blocker로 유지
16. Phase 1B-2 완료 후에도 public RPC/iOS production call site 전환은 별도 activation/Phase 2 승인 전까지 금지

위 1–6은 최종 local validation에서 PASS했다. Unresolved product를 fail-closed 상태로 보존하는 **candidate-release data 작업은 GO**다. 7–15가 해소되거나 명시적으로 release gate에서 차단되기 전 production activation은 NO-GO다.

## 14. 예상 영향

### 14.1 이번 Phase 실제 영향

- production product 0
- production closet 0
- production history 0
- active release 0
- public/iOS behavior 0

### 14.2 Future Phase 1B-2 candidate scope

- successor mapping rows: 3,492
- targeted product decisions: 114
- fail-closed product-required mappings: 989
- structurally invalid mapping review/fix scope: 369
- manual review products: 1,037
- BOTH_UNTRUSTED conflict: 310
- production active release/history/closet impact: candidate-only 단계에서는 0

### 14.3 Future activation scope

- re-resolve product: 1,608
- expected append/supersede history: 1,601–1,608
- existing history 1,860은 보존
- linked closet migration: Phase 1A.5 baseline 0
- comparison history migration: 0

## 15. 미검증 항목

- local/staging fresh migration apply
- migration 114 trigger의 real PostgreSQL compile/runtime
- migration 115 네 function의 real PostgreSQL compile/runtime
- validation SQL assertions와 recorder rollback fixture 실제 실행
- migration 115 reapply/idempotency-safe catalog behavior
- candidate release data가 들어간 resolver v4 shadow distribution
- live network comparison 71
- dresses/underwear/homewear future taxonomy/measurement rows
- Phase 2 additive Swift decoding과 end-to-end user override/measurement gate

## 16. 최종 gate와 다음 명령

**Phase 1B-2 candidate-data: GO.** PostgreSQL 17 disposable local DB에서 corrected 113/114/115 apply, runtime validation rollback, 115 reapply를 통과해 foundation 검증 blocker가 해소됐다. Phase 1A.5의 unresolved data는 candidate에서 fail-closed로 다룬다. Production activation은 별도 gate 확장·data evidence·ledger reconciliation 전까지 NO-GO다.

다음 명령은 사용자가 별도로 승인하는 Phase 1B-2 candidate release/data migration 작성과 동일 local-only validation이어야 한다. Production `db push`, `apply_migration`, active-release activation, history backfill은 계속 금지한다.
