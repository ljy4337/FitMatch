# FitMatch Classification Authority — Migration 115 Final Correction

Date: 2026-08-26 KST

Repository: `ljy4337/FitMatch`

Branch / HEAD: `connectDB` / `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab`

Production Supabase: `hnkplvyegonlhumlejst`

## 1. 결론

- **Phase 1B-2 candidate-data 작업은 GO다.** Migration 115의 지정된 두 contract 결함만 수정했고, PostgreSQL 17 disposable local environment에서 `113 -> 114 -> corrected 115`, validation rollback, 115 reapply를 실제 실행해 모두 PASS했다.
- 이 GO는 candidate release/data 작성과 local-only 검증을 허용하는 결론이다. Production migration/apply, active release 전환, history backfill, public RPC 전환은 여전히 시작하지 않았다.
- Production DB에는 SELECT/introspection만 실행했다. Production write/apply/release/history change는 모두 0이다.
- Swift production change 0, Phase 1B-2 automatic start 0, v5/parallel resolver/evaluator 0이다.
- `BOTH_UNTRUSTED` 310, manual review 1,037, replacement tuple 미확정 mapping, live network comparison 71은 계속 fail-closed/activation blocker다.

## 2. 변경 파일

| 파일 | 최종 변경 |
|---|---|
| `supabase/migrations/115_authoritative_classification_foundation.sql` | raw payload classifier override 제거, comparison/rule/measurement version 분리 |
| `supabase/sql/115_authoritative_classification_foundation_validation.sql` | payload spoof 및 distinct policy-version runtime assertions |
| `supabase/sql/115_authoritative_classification_foundation_local_fixture.sql` | 서로 다른 synthetic policy vocabulary |
| `Docs/FitMatchClassificationPhase1B1Validation-20260825.md` | 본 최종 검증 보고서 |
| `Docs/FitMatchClassificationPhase1B1Foundation-20260825.md` | final correction/additive activation-gate contract |
| `Docs/CodexSessionHandoff.md` | 누적 handoff 갱신 |

Migration 113/114, Swift production, Parser, mapping/product-decision seed, active release, Gold production decision, classification history는 수정하지 않았다.

Final SQL SHA256:

- Migration 115: `1d09dcde02a2d1728322b2bcb5b1eb567f4918ecbd9936f386a817f5d0a1e799`
- Validation SQL: `06a54982540da4b6ffa8f3ea05ffe1e662072bb3e8cf40e90b06c3ace230d0e4`
- Local fixture: `2830bea1fe32018b04b55a53a647707ac6677a3e9a82f461e5b62bd114d66980`

## 3. Contract correction

### 3.1 Raw payload classifier override 제거

`runtime_resolve_product_classification_v4`는 더 이상 `p_payload->>'classifier_policy_version'`을 읽지 않는다.

Classifier profile version source는 오직 selected release의 다음 값이다.

```text
validation_report.runtime_policy_contract.classifier_policy_version
```

- `trusted_payload_override` code/evidence/source 개념을 제거했다.
- `release.policy_version` fallback은 계속 사용하지 않는다.
- Version이 없으면 name/path/exclusion profile authority를 사용하지 않고 `classifier_policy_version_missing`을 evidence/unresolved reason에 기록한다.
- Verified exact product decision과 verified direct mapping은 classifier profile version과 독립적으로 계속 평가할 수 있다.
- Raw payload의 audience/source-category evidence 사용은 유지하되 policy authority로 사용하지 않는다.

### 3.2 Comparison policy와 compatibility rule version 분리

Selected release runtime contract는 다음 네 typed field를 사용한다.

```json
{
  "classifier_policy_version": "...",
  "comparison_policy_version": "...",
  "compatibility_rule_version": "...",
  "measurement_policy_version": "..."
}
```

Evaluator lookup은 다음과 같이 분리했다.

| 저장소 | Release-pinned field |
|---|---|
| `public.comparison_policies.policy_version` | `comparison_policy_version` |
| `fitmatch_taxonomy.comparison_compatibility_rules.policy_version` | `compatibility_rule_version` |
| `public.app_category_measurement_policies.policy_version` | `measurement_policy_version` |

Missing field 또는 지정 version의 required row 부재는 각각 다음 reason으로 fail-closed한다.

- `runtime_policy_contract_missing`
- `comparison_policy_version_missing`
- `compatibility_rule_version_missing`
- `measurement_policy_version_missing`

Evaluator response는 `comparison_policy_version`, `compatibility_rule_version`, `measurement_policy_version`을 별도로 반환한다. 모호한 기존 shadow-only `compatibility_policy_version` key는 제거했다.

Typed compatibility semantics(`allowed`, `fallback_allowed`, `length_match_required`, exclusion list, minimum/required/required-any/weights, directional)는 변경 없이 유지했다. T-shirt/base-layer safety block 및 generic underwear/homewear/dress fail-close도 유지했다.

### 3.3 Production vocabulary 확인

Production SELECT-only 결과는 결함 원인과 일치했다.

| 저장소 | Current version |
|---|---|
| classifier name/path/exclusion profiles | `db-auto-classifier-2026-08-18-v2` |
| `public.comparison_policies` | `v1` |
| compatibility rules current set | `db-comparison-2026-08-18-v2` |
| measurement policies | `2026.07.1` |

하나의 compatibility 문자열로 두 policy 저장소를 조회할 수 없다는 점을 production write 없이 재확인했다.

## 4. Distinct-version local fixture

Fixture는 production mismatch를 숨기지 않도록 의도적으로 서로 다른 값을 사용한다.

- classifier: `classifier-v1`
- comparison policies: `comparison-policy-v1`
- compatibility rules: `compatibility-rule-v1`
- wrong rule fixture: `compatibility-rule-wrong`
- measurement: `measure-v1`
- simultaneous wrong measurement fixture: `measure-v2`

Active synthetic release의 validation transaction contract에는 네 field를 모두 넣었다. Fixture는 synthetic taxonomy/catalog data만 포함하며 production raw product, `auth.users` row, closet item, user measurement, comparison history를 복사하지 않았다.

## 5. Disposable PostgreSQL 17 environment

| 항목 | 결과 |
|---|---|
| Homebrew formula | existing `postgresql@17 17.11` 사용, 추가 설치 0 |
| server/client | `postgres`, `psql`, `initdb`, `pg_ctl` 모두 `17.11 (Homebrew)` |
| binary root | `/usr/local/opt/postgresql@17/bin` |
| cluster root | `/tmp/FitMatchPostgres17-20260826-072435` |
| data directory | `/tmp/FitMatchPostgres17-20260826-072435/data` |
| socket | `/tmp/FitMatchPostgres17-20260826-072435/socket` |
| port | `55432`; port 5432 미사용 |
| database | `fitmatch_validation` |
| service | `brew services start` 실행 0 |
| cloud branch | 생성 0 |

Formula-specific server가 요구한 `/usr/local/share/postgresql@17`과 `/usr/local/lib/postgresql@17` support path는 formula keg를 가리키는 temporary symlink로만 제공했고 검증 종료 후 제거했다. 기존 libpq 18 link/configuration은 변경하지 않았다.

## 6. Exact apply order and results

모든 server/client 명령은 `/usr/local/opt/postgresql@17/bin`만 사용했다.

```text
1. initdb /tmp/FitMatchPostgres17-20260826-072435/data
2. pg_ctl start, Unix socket only, port 55432
3. createdb fitmatch_validation
4. psql -f 115_authoritative_classification_foundation_local_fixture.sql
5. psql -f 113_p3_data_quality_observability.sql
6. psql -f 114_release_gate_and_quality_review_queue.sql
7. psql -f 115_authoritative_classification_foundation.sql
8. psql -f 115_authoritative_classification_foundation_validation.sql
9. psql -f 115_authoritative_classification_foundation.sql
10. psql -f 115_authoritative_classification_foundation_validation.sql
11. post-rollback count/object/hash query
12. pg_ctl stop and disposable root deletion
```

| 단계 | 결과 | wall time |
|---|---|---:|
| fixture | PASS | `0.11s` |
| 113 apply | PASS / COMMIT | `0.04s` |
| 114 apply | PASS / COMMIT | `0.03s` |
| corrected 115 initial apply | PASS / COMMIT | `0.04s` |
| validation run 1 | PASS / explicit ROLLBACK | `0.10s` |
| current exact-file 115 reapply | PASS / COMMIT | `0.04s` |
| validation run 2 | PASS / explicit ROLLBACK | `0.09s` |

Local-only ledger는 `113`, `114`, `115` 순서다. Production timestamp ledger repair/update는 0이다.

## 7. Validation results

### 7.1 Payload spoof and classifier pin

- Active release `classifier-v1` + exact `classifier-v1` profile: confirmed PASS.
- Selected release `classifier-v2` + only `classifier-v1` profile: review PASS.
- Missing classifier contract: profile unused, `classifier_policy_version_missing` PASS.
- Selected release `classifier-v2` + raw payload spoof `classifier-v1`: result remained `review_required`, returned version remained `classifier-v2`, source remained `release_runtime_policy_contract`. Spoof-confirmed 0.
- Verified direct mapping/legacy conflict and verified profile/legacy conflict both remained review-required.

### 7.2 Distinct comparison/rule/measurement versions

- `comparison-policy-v1` + `compatibility-rule-v1` + `measure-v1`: policy-ready same-group and allowed cross-group PASS.
- Missing/wrong comparison policy version: `comparison_policy_version_missing`.
- Missing/wrong compatibility rule version: `compatibility_rule_version_missing`.
- Missing measurement version: `measurement_policy_version_missing`.
- Wrong rule row `compatibility-rule-wrong` was not consumed; returned rule version/weights were exactly the selected good version.
- Simultaneously active `measure-v2` row was not mixed. Dimensions/weights/version list contained only `measure-v1`.

### 7.3 Existing typed semantics and foundation runtime

- Compatibility allowed/denied, fallback denial, required-length automatic denial, fallback exclusion list, non-required length mismatch, required/required-any/minimum/weights, directional reverse denial PASS.
- T-shirt/base-layer explicit block, generic underwear, unseeded Homewear Option A, dress fail-close PASS.
- 113 functions/RLS/grants actual compile/runtime PASS.
- 114 release gate report, activation trigger deny/allow, review view, triage function and grant matrix actual runtime PASS.
- 115 tuple validator, resolver v4, recorder v2, evaluator v4 actual PostgreSQL compile/runtime PASS.
- Decision CHECK 2 + nullable garment FK 1 present/validated. Unknown child insert and referenced parent delete RESTRICT probes PASS inside rollback.
- Recorder v2 append/supersede/current-exactly-one/invalid-confirmed rejection PASS inside rollback.

### 7.4 Grants, rollback, idempotency

- Four 115 functions: service_role EXECUTE `4/4`; anon/authenticated EXECUTE `0/8`.
- Evaluator 16-argument overload exactly 1; obsolete 15-argument v4 overload 0.
- Validation ended in explicit `ROLLBACK` twice.
- Post-rollback fixture counts remained releases/mappings/decisions/history/products/measurements/issues/name-profiles = `1/1/1/1/1/0/0/0`.
- Active synthetic release `validation_report` returned to `{}` after each rollback.
- Old internal v2/v3 and four public RPC combined definition hash was identical before/after: `dc9e989eb233b066d6c7a973b57e9010`.
- Reapply postflight: decision columns 2, history garment column 1, decision constraints 3, foundation functions 4, evaluator overload 1, release trigger 1. Duplicate object 0.

## 8. Lock/performance

- Waiting locks after apply/reapply: 0.
- 113/114/115 apply and 115 reapply were each `0.04s` or less in the one-row synthetic fixture.
- Validation was `0.10s` and `0.09s`.
- The fixture is compile/contract evidence, not a production lock-duration prediction for 5,056 decisions. Production deployment still requires the existing 10s lock timeout/180s statement timeout and a controlled deployment window.
- Nullable decision garment FK child index was not added. Existing synthetic EXPLAIN/RESTRICT behavior did not establish a need; this remains an evidence-based future advisor/EXPLAIN decision.

## 9. Production unchanged evidence

Final production SELECT-only postflight at `2026-08-26 07:29 KST`:

| 항목 | 값 |
|---|---:|
| products | 1,608 |
| product decisions | 5,056 |
| history / current | 1,860 / 1,608 |
| product measurements | 28,418 |
| active release | 1 |
| latest migration ledger | `20260821090138 seed_zara_verified_measurement_subset` |
| 114 release columns | 0 |
| 115 decision/history columns | 0 / 0 |
| 114 gate function | absent |
| tuple validator/resolver v4/recorder v2/evaluator v4 | all absent |
| existing eight legacy function combined hash | `0551eee819d6ae2db5ccd40c0f66a275` |

Production SQL calls in this task were SELECT statements only. `apply_migration`, `db push`, RPC write, DDL, DML, temporary schema/table creation were not called. Production behavior/data change 0이다.

## 10. Production activation gate follow-up contract

Migration 114는 이번 최소 수정에서 변경하지 않았다. Production activation 전에 release gate를 다음 contract로 확장해야 한다.

1. Candidate `runtime_policy_contract`에 네 field가 모두 non-empty인지 검사한다.
2. 각 selected version의 required rows와 expected checksum/evidence를 검사한다.
3. `runtime_policy_contract_validated=true` 또는 동등한 명시적 gate evidence를 release validation report에 기록한다.
4. 위 evidence가 없거나 어떤 version row/checksum도 불일치하면 activation은 NO-GO다.

이 확장은 Phase 1B-2 candidate validation 또는 별도 production-activation migration에서 구현해야 한다. Candidate data를 작성할 수 있다는 현재 GO가 activation gate를 우회하지 않는다.

## 11. Remaining blockers and next boundary

Phase 1B-2 candidate-data 작업은 GO지만 다음은 production activation blocker다.

- Four-field runtime policy contract release-gate enforcement/checksum evidence 미구현
- Production numeric migration 113/114/115와 timestamp ledger의 controlled reconciliation 미검증
- `BOTH_UNTRUSTED` 310, manual review 1,037, invalid replacement tuple 미확정
- Live network comparison 71 미실행
- Candidate successor mappings/decisions/QA evidence 미작성
- Public RPC/iOS activation과 additive Swift decoding 미실행

다음 작업은 사용자가 별도로 명령할 때만 **Phase 1B-2 candidate release/data migration 작성 및 동일 local-only validation**이다. Production apply/activation, history backfill, Swift Phase 2는 자동 시작하지 않는다.
