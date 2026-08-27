# FitMatch Classification Authority — Phase 1B-2 Candidate Release

Date: 2026-08-26 KST

Repository: `ljy4337/FitMatch`

Branch: `connectDB`

Start/end HEAD: `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab` (commit 없음)

Production project: `hnkplvyegonlhumlejst`

Local PostgreSQL: Homebrew PostgreSQL server/client `17.11`

Result: **GO for Phase 1B-2 artifacts / NO-GO for Production activation**

## 1. GO / NO-GO

Phase 1B-2의 candidate-data build와 local shadow validation은 **GO**다.

- candidate mapping 3,492와 34/989/369/2,100 bucket이 exact하다.
- targeted decision manifest 114는 113 verified + 1 revoked이며 Gold 3은 exact다.
- runtime policy contract 네 version과 checksum이 release에 고정됐다.
- extended gate negative/positive probe, trigger, FK, grant가 통과했다.
- resolver v4 shadow는 1,608/1,608이며 confirmed invalid tuple과 unsafe authority leak가 0이다.
- PostgreSQL 17 clean apply, validation ROLLBACK, 116 reapply, 재validation이 통과했다.

Production activation은 **NO-GO**다. 이 Phase에서는 production apply, public/internal call-site switch, 114 decision write, release activation, history append를 실행하지 않았다. Activation 전에는 Section 16의 atomic cutover와 validated rollback successor/preimage artifact가 필요하다.

## 2. Changed files

| 파일 | 역할 |
|---|---|
| `supabase/migrations/116_classification_candidate_release.sql` | candidate release/mapping/review rows, exact decision manifests, four-policy/checksum gate 확장 |
| `supabase/sql/116_classification_candidate_release_validation.sql` | 1,608 shadow, gate/trigger/FK/grant, decision/recorder/activation transaction rollback validation |
| `supabase/sql/116_classification_candidate_release_local_fixture.sql` | Production SELECT-only non-user snapshot을 disposable DB에 적재 |
| `supabase/sql/fixtures/116_classification_candidate_manifest.jsonl` | mapping authority 3,492, decision 114, review 1,037의 machine-authoritative input |
| `Docs/FitMatchClassificationPhase1B2Shadow-20260826.jsonl` | 1 product = 1 row인 1,608 shadow 결과 |
| `Docs/FitMatchClassificationPhase1B2Candidate-20260826.md` | 본 보고서 |
| `Docs/CodexSessionHandoff.md` | 누적 handoff 갱신 |

신규 persistent table, DROP, TRUNCATE, history DELETE, Swift production 변경은 0이다. Migration 113/114/115와 기존 v2/v3/public RPC를 수정하지 않았다.

## 3. Production snapshot identity

Source snapshot 관측 시각은 `2026-08-25T23:00:34.588255Z`다. Phase 종료 postflight는 `2026-08-25T23:47:09.068714Z`에 다시 SELECT-only로 수행했다.

| 항목 | 값 |
|---|---:|
| active release ID | `65d72393-4a40-4e99-b701-fdc1ff865774` |
| active release key | `fitmatch-active-with-zara-official-tree-2026-08-13-v1__zara-sample30-2026-08-21` |
| active mappings | 3,492 |
| products | 1,608 |
| product decisions | 5,056 |
| history / current | 1,860 / 1,608 |
| candidate release in Production | 0 |
| classification review issues in Production | 0 |
| latest Production migration | `20260821090138 seed_zara_verified_measurement_subset` |

Production snapshot checksums:

- products: `07f8a54d8f331b025e1a94f0c213d69b6af6ded511a55f79b525a4aa0f1bdbf0`
- active mappings: `28a7700805e95d9e643b0cb860770fde8e12acd86057cace879082ff82a307f2`
- decisions: `bb245f2a505c720cdac568dc0c7c0ee7cc921520f377df1bb386022cabd33376`

Production에서 실행한 SQL은 SELECT/CTE SELECT/introspection뿐이다. `apply_migration`, DDL, INSERT, UPDATE, DELETE, RPC mutation, temp object는 0이다.

## 4. Candidate release identity

| 항목 | 값 |
|---|---|
| release ID | `9f9c8155-61d9-41ce-9dd1-bf695ecc2140` |
| release key | `fitmatch-classification-authority-candidate-2026-08-26-v1` |
| parent | `65d72393-4a40-4e99-b701-fdc1ff865774` |
| local status | `validated` |
| bundle checksum | `543c16fbf9a4d2cf53d4465b556b29dbf498c65a18aff490418e8ffb3748572f` |
| expected mappings / QA | 3,492 / 1,608 |
| validation contract | `fitmatch-release-gate-v2` |
| candidate manifest file SHA-256 | `f542025c3cd84a4b785903e746b276f4f07ad1b9152d2c4c0301e4983d6d66ea` |
| shadow SHA-256 | `b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385` |

Candidate는 local DB에서만 insert됐다. Migration 116은 decision 114를 permanent upsert하지 않고 exact manifest function으로 보존한다. 이는 `(source, external_product_id)` PK가 release-scoped가 아니어서 v3가 살아 있는 동안 미리 쓰면 production behavior가 바뀌기 때문이다.

## 5. Mapping 3,492 bucket counts

| bucket | mapping rows | candidate authority |
|---|---:|---|
| CATEGORY_DIRECT | 34 | verified / category_direct / productRequired=false |
| PRODUCT_REQUIRED | 989 | verified / product_required / productRequired=true |
| INVALID_MAPPING | 369 | revoked / invalid_mapping / non-authoritative |
| OTHER_EXISTING | 2,100 | legacy / existing_non_authoritative; 기존 non-confirmed 의미 보존 |
| total | 3,492 | overlap 0, identity loss 0 |

- parent row의 source identity, source/target/path, semantic tuple, lookup flags를 exact clone했다.
- authority metadata만 `raw_record.authorityContract`와 `phase1b2Adjudication`에 additive로 기록했다.
- CATEGORY_DIRECT 34는 tuple validator PASS 34/34다.
- PRODUCT_REQUIRED와 INVALID_MAPPING이 category mapping만으로 confirmed된 shadow row는 각각 0이다.
- mapping manifest checksum: `14498c1015e2f537ddd25aced2661968ac2508a2445309a82a1603150a8d2327`
- candidate mapping DB checksum: `0fcffcc3be8a8605ce1a1ac87bb1b351a200b499ff10b1bc706ea3152cb9b633`

## 6. Decision 114 counts and Gold 3

| action | count |
|---|---:|
| verified/corrected | 113 |
| ZARA revoke-to-review | 1 |
| total | 114 |

Verified tuple validator 결과는 113/113 PASS다. Revoked row는 `zara:547276687`이며 자동 authority가 아니다.

Gold:

| product | candidate tuple | result |
|---|---|---|
| UNIQLO E482514 | `tops/short_sleeve/tshirt/tshirt/short_sleeve` | exact confirmed verified |
| UNIQLO E454311 | `tops/base_layer_top/base_layer_top/base_layer_top/short_sleeve` | exact confirmed verified |
| UNIQLO E456567 | `tops/base_layer_top/base_layer_top/base_layer_top/short_sleeve` | exact confirmed verified |

Gold exact 3/3, collision 0이다. Decision manifest checksum은 `16000e9ddb51eda923d242fadb97422ee868af503496eb440f3bca7e0206b820`, DB serialization checksum은 `ec82846268cb5e8c6b0c3ce90ff1902648080456d05f336414631b4a742818ab`다.

Phase 1A.5가 E450536/E486066에 제시한 `knit_top` detail은 “candidate로 검증”할 값이었다. 실제 115 validator는 둘 다 `detail_code_not_found_or_inactive`로 차단했다. 현재 active taxonomy의 `knit_sweater` detail은 동일 garment/family/long-sleeve tuple로 PASS하므로 verified decision은 `tops/knit_sweater/knit_sweater/knit_sweater/long_sleeve`로 고정했다. Manual expected를 현재 결과에 맞춰 수정하지 않았고, 이 taxonomy-vocabulary 차이는 Section 13에 literal mismatch로 그대로 남겼다.

## 7. Review 1,037 / BOTH_UNTRUSTED 310 handling

- review manifest 1,037은 `data_quality_issues`의 기존 dedupe contract에 exact 1,037개 issue로 적재됐다.
- confirmed product decision은 이 1,037개에 추가하지 않았다.
- review manifest checksum: `7f292498a3ddb77c9dfcaee0e8b3a341cdd330efd4b1fb90877c6d2f8712189b`
- review DB checksum: `7aa0e654c9731e33603ba37a43b3c8381a8a2c5406970a21c02788dc4b076a0d`
- Shadow에서 1,037 중 1,009는 review_required, 28은 independently verified CATEGORY_DIRECT mapping으로 confirmed됐다. Phase 1A.5 지시대로 1,037 전체를 일괄 review_required로 덮어쓰지 않았으며 28도 review issue는 유지한다.

BOTH_UNTRUSTED original cohort 310은 다음처럼 처리했다.

- 309 unresolved: review_required 309, confirmed 0.
- E482514 1건: original conflict cohort에 속하지만 이후 owner Gold가 두 legacy 후보를 supersede한 exact verified decision이므로 confirmed다.
- “untrusted mapping/legacy/profile 경로를 통한 unsafe confirm”은 original 310 전체에서 0이다.

## 8. Runtime policy contract and checksums

Candidate `validation_report.runtime_policy_contract`:

```json
{
  "classifier_policy_version": "db-auto-classifier-2026-08-18-v2",
  "comparison_policy_version": "v1",
  "compatibility_rule_version": "db-comparison-2026-08-18-v2",
  "measurement_policy_version": "2026.07.1"
}
```

Migration 116 stable-serialization checksums:

| policy set | rows | checksum |
|---|---:|---|
| classifier name/path/exclusion | 1,532 | `0b76032f9a227caf01345fb81904da20ee6d5f095ec22ddf67299795bf73d9c5` |
| comparison policies | 30 | `894f11830cfcd7f4b484700b0e57a05f440b4bf88380067eec40a5abd8a840fa` |
| compatibility rules | 2 | `37e9f0058e06508cf1f2eeb5dd5fae228066de41fd92e2781e1be507e696a96e` |
| measurement policies | 25 | `dfea5b0f3ea935ff73dd05bec8a5fd793eb0d23e7a03f84fac5f563b4c6d3abe` |

`runtime_policy_contract_validated=true`를 요구한다. Version vocabulary를 합치거나 최신값을 임의 선택하지 않는다.

## 9. Extended release gate results

`runtime_release_gate_report(uuid)`는 114의 blocker를 모두 유지하고 다음을 추가했다.

- 네 runtime version non-empty 및 exact row 존재
- 네 deterministic checksum match
- `runtime_policy_contract_validated=true`
- mapping identity/count/bucket/checksum parity
- exact decision 114 content가 activation transaction에 실제 존재
- review issue 1,037 parity
- shadow/Gold/fail-closed QA evidence

검증 결과:

- decision write 전 gate: expected blocker `targeted_decision_count_or_content_mismatch`, activation denied.
- 네 field 각각 제거: 해당 `*_version_missing` blocker 확인.
- 존재하지 않는 classifier version: required-row blocker 확인.
- checksum spoof: `classifier_policy_checksum_mismatch` 확인.
- validation flag false: `runtime_policy_contract_not_validated` 확인.
- 114 trigger direct activation negative probe: denied.
- rollback transaction 안에서 exact decision 114 upsert 후 artifact report/gate: eligible=true.
- `runtime_activate_validated_release` positive probe: candidate만 active 1개.
- final ROLLBACK 후 parent active, candidate validated, exact candidate decisions 0, history 0으로 복귀.

Service role만 manifest/policy/artifact/gate function을 실행할 수 있고 anon/authenticated execute는 false다. Release trigger enabled, garment FK 1, verified-completeness CHECK가 존재한다.

## 10. 1,608 shadow distribution

| status | total | Musinsa | UNIQLO | ZARA |
|---|---:|---:|---:|---:|
| confirmed | 177 | 3 | 174 | 0 |
| review_required | 1,431 | 391 | 1,010 | 30 |
| not_comparable | 0 | 0 | 0 | 0 |
| unclassified | 0 | 0 | 0 | 0 |
| total | 1,608 | 394 | 1,184 | 30 |

Method: verified product decision 113, verified category mapping 64, unknown/review 1,431. Authority: verified 177, unresolved/null 1,431. Existing production profile rows에는 verified authority/complete garment evidence가 0이므로 product-classifier confirmed는 0이다.

Product별 related mapping bucket은 CATEGORY_DIRECT 148, PRODUCT_REQUIRED 801, INVALID_MAPPING 189, OTHER_EXISTING 382, NO_MATCH 88이다. 이 수는 mapping row bucket 34/989/369/2,100과 다른 product distribution이다.

Comparison self-preview는 allowed 165, non-auto group 8, required measurement policy missing 4, classification-not-confirmed 1,431이다. Generic underwear leak 0, tshirt↔base_layer_top automatic leak 0이다.

## 11. Current to candidate transition matrix

| current → candidate | count |
|---|---:|
| confirmed → confirmed | 172 |
| confirmed → review_required | 934 |
| not_comparable → review_required | 169 |
| review_required → confirmed | 5 |
| review_required → review_required | 328 |

934개의 confirmed→review 전환은 숫자를 맞추기 위한 downgrade가 아니라 verified complete authority가 없는 legacy tuple을 v4가 fail-closed한 결과다. History는 이 Phase에서 쓰지 않았다.

## 12. Invalid, conflict, and fail-closed counts

| acceptance | result |
|---|---:|
| input/output/unique | 1,608 / 1,608 / 1,608 |
| confirmed tuple invalid | 0 |
| product-required mapping alone confirmed | 0 |
| invalid mapping alone confirmed | 0 |
| BOTH_UNTRUSTED unsafe confirmed | 0 |
| Gold exact / collision | 3 / 0 |
| arbitrary unknown→tops/tshirt/other fallback | 0 |
| generic underwear auto leak | 0 |
| tshirt/base-layer auto leak | 0 |

Resolver가 새로 기록한 authority-conflict evidence row는 830이다. Phase 1A.5 original conflict cohort 573의 결과는 A_PRODUCT_DECISION_CORRECT 105 confirmed, G_BOTH_UNTRUSTED owner Gold 1 confirmed, 나머지 467 review_required다.

Current stale 1,472와 fingerprint mismatch 94는 manifest에 보존됐다. 많이 발생한 blocker는 legacy decision garment missing 845, legacy family inactive/missing 531, category mapping required sleeve not-applicable 406, mapping detail missing 374이다. Stale라는 이유로 current history를 재작성하지 않았다.

## 13. Independent adjudicated regression

Independent expected 207은 수정/자동 생성하지 않았다.

| scope | total | current overlap | exact | literal mismatch | review_required | SKIP/missing |
|---|---:|---:|---:|---:|---:|---:|
| full independent corpus | 207 | 137 | 16 | 121 | 27 | 70 |
| 기존 31-product/64-assertion failure corpus | 31 | 28 | 0 | 28 | 1 | 3 |
| Phase 1B DB target | 5 | 5 | 2 | 3 | 0 | 0 |

31-product failure corpus는 Phase 1A.5에서 전부 iOS Phase 2 대상으로 확정됐으므로 28 literal mismatch를 DB candidate에 맞춰 expected correction하지 않았다. Current catalog에 없는 3개는 SKIP이다.

DB target literal mismatch 3은 `6800912`의 legacy `blouse/shirt` 대 canonical `shirt_blouse`, E450536/E486066의 inactive `knit_top`/legacy `knit_cardigan` 대 validator-valid `knit_sweater` vocabulary다. 5개 모두 confirmed verified이며 semantic correction plan은 반영됐지만, independent expected와의 literal equality를 PASS로 가장하지 않는다.

## 14. Local apply, reapply, and rollback

Environment:

- cluster: `/tmp/FitMatchPostgres17-20260826-01`
- port: `55432` (5432 미사용)
- server/client: PostgreSQL `17.11 (Homebrew)`
- `brew services start`: 0
- additional install: 0

Exact clean command order:

```bash
PGBIN="$(brew --prefix postgresql@17)/bin"
"$PGBIN/initdb" -D /tmp/FitMatchPostgres17-20260826-01/data \
  --no-locale --encoding=UTF8 --auth-local=trust --auth-host=trust
"$PGBIN/pg_ctl" -D /tmp/FitMatchPostgres17-20260826-01/data \
  -l /tmp/FitMatchPostgres17-20260826-01/postgres.log \
  -o "-p 55432 -h 127.0.0.1" start
"$PGBIN/createdb" -h 127.0.0.1 -p 55432 fitmatch_phase1b2
"$PGBIN/psql" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 \
  -d fitmatch_phase1b2 \
  -f supabase/sql/116_classification_candidate_release_local_fixture.sql \
  -f supabase/migrations/113_p3_data_quality_observability.sql \
  -f supabase/migrations/114_release_gate_and_quality_review_queue.sql \
  -f supabase/migrations/115_authoritative_classification_foundation.sql \
  -f supabase/migrations/116_classification_candidate_release.sql
"$PGBIN/psql" -X -qAt -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 \
  -d fitmatch_phase1b2 \
  -f supabase/sql/116_classification_candidate_release_validation.sql
"$PGBIN/psql" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 \
  -d fitmatch_phase1b2 \
  -f supabase/migrations/116_classification_candidate_release.sql
"$PGBIN/psql" -X -qAt -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 \
  -d fitmatch_phase1b2 \
  -f supabase/sql/116_classification_candidate_release_validation.sql
```

Results:

- fixture→113→114→115→116 clean apply: PASS, total 4.06s.
- 116 first apply: candidate release 1, mappings 3,492, review issues 1,037.
- validation: PASS; 1,608 JSONL, final ROLLBACK.
- 116 reapply: PASS 0.33s; release/mapping/issue inserts 0/0/0.
- validation after reapply: PASS; first output와 byte-identical, checksum 동일.
- post-rollback: products 1,608, decisions 5,056, history 0, parent active, candidate validated, candidate decision exact matches 0.
- lock timeout/statement timeout 발생 0; apply 중 contention/lock wait 관측 0.
- final server stop PASS; `/tmp/FitMatchPostgres17-20260826-01`과 임시 Homebrew share/lib support symlink 삭제 확인.

Local fixture history 0은 Production history를 복사하지 않았기 때문이다. Production history 1,860/current 1,608은 SELECT-only parity로 별도 확인했다.

## 15. Production unchanged evidence

Phase 종료 Production SELECT-only postflight:

- products 1,608, decisions 5,056, history 1,860/current 1,608.
- active release ID와 active mapping 3,492 불변.
- candidate release count 0.
- 114 gate, resolver v4, candidate manifest function 모두 Production에 없음.
- migration ledger latest가 `20260821090138`로 불변.
- production write/apply/activation/history change 0.
- Swift production diff 0.

## 16. Exact future Production deployment sequencing

Production에서는 다음을 별도 승인 후 수행한다.

1. **Schema/candidate-data additive deploy:** 113→114→115→116을 적용한다. Candidate는 `validated`, active pointer는 parent 유지, decision 114는 아직 쓰지 않는다. 기존 v2/v3/public RPC behavior는 그대로다.
2. **Additive client readiness:** Phase 2 Swift optional decoding을 먼저 배포할 수 있다. 기존 JSON key와 argument는 유지되므로 old client도 계속 동작한다.
3. **Single atomic DB cutover transaction:**
   - advisory activation lock과 release/114 decision rows를 `FOR UPDATE`로 고정한다.
   - exact 114 decision manifest를 upsert한다.
   - `runtime_resolve_and_promote_product`를 resolver v4 + recorder v2로 연결한다.
   - `public.fitmatch_resolve_product`와 `public.fitmatch_get_product_runtime`에 additive fields를 연결한다.
   - `runtime_evaluate_product_compatibility`, `fitmatch_find_reference_candidates`, `fitmatch_begin_comparison`을 evaluator v4로 연결한다.
   - gate report가 exact decision/policy/checksum/shadow evidence를 재검증한 뒤 candidate를 activate한다.
   - transaction commit 한 번으로 decision, call-site, active pointer를 동시에 공개한다.
4. **Post-commit observation:** old arguments/keys, Parser, measurement, closet/manual input flow가 유지되고 unresolved가 review_required인지 확인한다. History reclassification/backfill은 이 cutover와 분리하고 별도 승인한다.

중간 상태에서 candidate decision이 legacy v3에 노출되는 window는 0이어야 한다.

Post-commit rollback도 사전 검증된 한 transaction이어야 한다. Activation 전에 exact 114-row Production preimage와 checksum을 별도 rollback artifact로 만들고, parent mapping 기반의 `fitmatch-release-gate-v2` rollback successor를 미리 validation한다. 장애 시 call site를 v3/old recorder/evaluator로 되돌리고 decision preimage를 복원한 뒤 rollback successor를 activate한다. Candidate history를 DELETE하지 않고 이후 row로 supersede한다. 기존 active parent를 gate 없이 직접 되살리거나 candidate decision을 남긴 채 v3로 돌아가는 것은 금지한다.

## 17. Remaining blockers

- Production 113/114/115/116 apply와 atomic activation dry-run은 미실행이다.
- 114 decision exact preimage rollback artifact와 gated rollback successor가 아직 없다.
- manual review 1,037의 independent product truth는 미확정이다.
- BOTH_UNTRUSTED 309의 승자는 미확정이다. E482514만 owner Gold로 해소됐다.
- invalid mapping 369의 replacement tuple은 대부분 미확정이며 candidate에서 fail-closed다.
- live network comparison 71과 authenticated closet/recommendation E2E는 미실행이다.
- 기존 31-product/64-assertion Swift regression은 Phase 2 대상이다; expected correction 0.
- current classifier profiles는 verified complete authority evidence가 0이므로 candidate automatic profile coverage가 0이다.
- Dresses/underwear/homewear는 policy-ready 전까지 fail-closed다.

이 항목들은 Phase 1B-2 artifact GO를 막지 않지만 Production activation을 막는다.

## 18. Next exact phase

다음 단계는 **`Phase 1B-3 — Controlled Activation Transaction + Rollback Successor Dry Run (Local/Staging Only, Production Apply 0)`**다.

그 Phase에서 exact 114-row preimage/rollback artifact, v4/v2/evaluator call-site switch migration, rollback successor, atomic cutover/rollback을 같은 PostgreSQL 17 disposable 환경에서 검증한다. Production apply, active release activation, history backfill, Phase 2 Swift 수정은 자동 시작하지 않는다.
