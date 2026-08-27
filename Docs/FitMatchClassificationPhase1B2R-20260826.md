# FitMatch Classification Authority — Candidate Revision + Full Shadow Revalidation

Date: 2026-08-26 KST

Repository: `ljy4337/FitMatch`

Branch: `connectDB`

Start/end HEAD: `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab` (commit 없음)

Production project: `hnkplvyegonlhumlejst`

Local PostgreSQL: Homebrew PostgreSQL server/client `17.11`

Result: **NO-GO — approved artifact application is exact, but shadow coverage is PARTIAL (256/1,352, not 263/1,345)**

## 1. GO / NO-GO

Production activation과 다음 phase는 **NO-GO**다.

승인된 데이터 delta 자체는 정확히 반영됐고 모든 fail-closed safety gate, 기존 177 regression, Gold 3/3, clean apply/reapply/idempotency는 통과했다. 그러나 Musinsa clone cohort의 실제 결과는 mapping selected 84/84, confirmed 77/84다. 남은 7개에는 기존 incomplete legacy product decision이 존재하며 Resolver v4가 새 verified category mapping과의 conflict를 fail-closed한다.

따라서 실제 안전 전환은 clone 77 + exact decision 2 = **79**다. 예상 86보다 7 적고, 전체 결과는 **confirmed 256 / review_required 1,352**다. 숫자를 맞추기 위한 decision revoke/completion, authority precedence 변경, Resolver 수정은 하지 않았다.

Local release row의 schema status는 `validated`지만 revision gate는 validation transaction 안에서 정확히 `approved_transition_shortfall` blocker 하나로 `eligible=false`다. 이는 local artifact가 구조적으로 검증됐다는 뜻이지 activation 승인이 아니다.

## 2. Changed files

| 파일 | 역할 |
|---|---|
| `supabase/migrations/117_classification_candidate_revision_safe_data.sql` | local candidate v2, approved mappings/dispositions, two-decision manifest, PARTIAL gate |
| `supabase/sql/117_classification_candidate_revision_safe_data_validation.sql` | full 1,608 shadow, transition/safety/gate, rollback validation |
| `supabase/sql/fixtures/117_classification_candidate_revision_manifest.jsonl` | exact approved delta와 unapproved vocabulary parity 84 records |
| `Docs/FitMatchClassificationPhase1B2RShadow-20260826.jsonl` | 1 product = 1 row, exact 1,608-row revision shadow |
| `Docs/FitMatchClassificationPhase1B2R-20260826.md` | 본 보고서 |
| `Docs/CodexSessionHandoff.md` | 본 작업 결과 append |

기존 116, migrations 113–116, Swift production, Resolver/Evaluator/Recorder, public/internal RPC call site는 수정하지 않았다.

## 3. Baseline checksum parity

작업 시작 전에 지정한 여섯 입력을 모두 byte checksum으로 확인했다. Drift는 0이다.

| 입력 | SHA-256 | 결과 |
|---|---|---|
| Phase 1B-2 shadow | `b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385` | exact |
| Review Evidence Audit | `cbcfa931a01c152f6b8205cf26a3d2696af73ad5b3ec0f9585f52831eec81ddb` | exact |
| Conflict cohorts | `1c7e332d7b3ec44f1157c1f919c4f7626ef096b582caa2c68b1ed596402e465b` | exact |
| DB-only 105 | `c786470b1123efa9d7651c5a8a913aed073509135f6a679dc63a69e4bbc3229c` | exact |
| Invalid mapping rows | `660471260f5d544c5a307f95c85113a0fd637b36541e0d4b36eb07224c90cc25` | exact |
| Remediation plan | `e6b26efe743520b3627bf97492dd93c68958eafddd3c66399b1fd823c71c132c` | exact |

기존 116 validation을 같은 SELECT-only snapshot fixture에서 다시 실행한 결과도 기존 shadow와 byte-identical 1,608행이었다. Product key/fingerprint revision parity는 1,608/1,608, mismatch 0이다.

## 4. Approved exact counts

| approved delta | rows | affected products | local result |
|---|---:|---:|---|
| Musinsa observed-target CATEGORY_DIRECT clone | 17 | 84 unique | selected 84, confirmed 77, conflict review 7 |
| UNIQLO exact decision completion | 2 | 2 | confirmed 2/2 |
| SHOULD_BE_PRODUCT_REQUIRED | 10 | 25 | review 25, category-only confirmed 0 |
| SHOULD_BE_REVOKED_NO_REPLACEMENT | 30 | 75 | review 75, mapping authority leak 0 |

Mapping row bucket은 baseline `34 / 989 / 369 / 2,100`에서 revision `51 / 999 / 359 / 2,100`으로 바뀌었다.

- total mapping rows: 3,509 = baseline 3,492 + clone 17
- baseline identities retained: 3,492/3,492
- identity loss / unexpected identity difference: 0 / 0
- unapproved baseline row mismatch: 0
- clone semantic mismatch against verified base tuple: 0
- clone은 observed literal target만 추가했으며 `UNKNOWN` wildcard와 audience rewrite는 0
- product-required 10은 replacement tuple을 만들지 않음
- revoke 30은 `review_required/revoked/lookup=false/eligibility=false`, replacement tuple null

Two exact decisions are only `uniqlo:E482522` and `uniqlo:E485454`:

`tops / short_sleeve / tshirt / tshirt / short_sleeve / body_length=null`, `verified`, `requires_user_confirmation=false`.

상품명은 이 두 decision의 semantic authority로 사용하지 않았다.

Component checksums:

| component | SHA-256 |
|---|---|
| revision manifest | `997f8fca3726ef38b728e5bc0c2e2dcd4cb72e578a70d3a26d3d3fda6aee3f16` |
| target clones | `1ee945ca971751f01daeeaa85b062d05ca2e1bf7fb906dfa17e1dd1b437c01bc` |
| decision delta | `0a698ee9856fdf385c1f453e027de017fd9cff6bf5c39d0c0f493c51346e24b5` |
| product-required | `b1100c7c2be380c06cabc17c8030c87435c9cc5ea148d01d41ead7ba07f5d305` |
| revoke/no-replacement | `990c71904a8d1ce0dce6a8b0f01f79b81190b97dec1dfa5b038b7762c3e7a719` |
| untouched invalid vocabulary | `9281ac77b9c584462ffcda21a1704fda8f65b7e03c1b11f53662562dbd9f36ee` |
| candidate mapping DB serialization | `bb968aa7b7acb23a4d48693b4596aeff09a57dd7fe26b3d04b22658bf05c0dd0` |
| targeted decision manifest serialization | `3e776892efc15b73669024b684cde2ed8d999b0c343697e43ad139331ae6e5b5` |

## 5. Untouched / unapproved parity

| deferred cohort | baseline | revision observation | authority change |
|---|---:|---|---:|
| legacy vocabulary translation | 7 products | review 7 | 0 |
| invalid vocabulary repair | 24 rows / 71 products | review 71, parity mismatch 0 | 0 |
| conflict cohort | 718 products | approved E482522 confirmed 1, unresolved 717 | winner selection 0 for remaining 717 |
| structured typed signal | 212 products | confirmed 33 / review 179 | typed-field authority 0 |
| name-add signal | 246 products | review 246 | name authority/profile 0 |
| clean name-only | 47 products | review 47 | name authority/profile 0 |

Structured typed 212의 membership은 Musinsa `size_type` 165 + UNIQLO `product_type_kr` 47 그대로다. 이 중 Musinsa 33은 approved category clone으로 confirmed됐으며 typed field를 사용한 결과가 아니다. 다음 read-only semantic validation에서 unresolved scope만 보면 179이고, original evidence cohort를 보면 212다.

Baseline manual flag 1,009 중 revision shadow는 confirmed 22 / review 987이다. Confirmed 22도 approved category/exact authority의 결과이며 manual issue를 삭제하거나 adjudicated truth를 생성하지 않았다.

## 6. Full shadow distribution

| status | baseline | revision | delta |
|---|---:|---:|---:|
| confirmed | 177 | 256 | +79 |
| review_required | 1,431 | 1,352 | -79 |
| not_comparable | 0 | 0 | 0 |
| unclassified | 0 | 0 | 0 |
| total | 1,608 | 1,608 | 0 |

Revision method는 canonical product decision 115, category mapping 141, unknown/review 1,352다. Confirmed authority는 verified 256/256이다. Product-level related mapping bucket은 CATEGORY_DIRECT 148, PRODUCT_REQUIRED 832, INVALID_MAPPING 158, OTHER_EXISTING 382, NO_MATCH 88이다.

Shadow artifact:

- rows / unique: 1,608 / 1,608
- SHA-256: `bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916`
- clean pass 1 / reapply pass 2 / checked-in artifact: byte-identical

## 7. Source distribution

| source | products | baseline confirmed/review | revision confirmed/review | confirmed delta |
|---|---:|---:|---:|---:|
| Musinsa | 394 | 3 / 391 | 80 / 314 | +77 |
| UNIQLO | 1,184 | 174 / 1,010 | 176 / 1,008 | +2 |
| ZARA | 30 | 0 / 30 | 0 / 30 | 0 |
| total | 1,608 | 177 / 1,431 | 256 / 1,352 | +79 |

## 8. Baseline → revision transition matrix

| baseline → revision | count |
|---|---:|
| confirmed → confirmed | 177 |
| review_required → confirmed | 79 |
| review_required → review_required | 1,352 |

기존 confirmed 177의 status regression, tuple change, method change, authority change, comparison allowed/reason change는 모두 0이다.

## 9. Approved 86 transition proof

Approved product union은 정확히 86이며 overlap은 0이다.

| proof | count |
|---|---:|
| clone mapping exact selected | 84/84 |
| clone category confirmed | 77/84 |
| clone fail-closed conflict | 7/84 |
| exact decision confirmed | 2/2 |
| approved review → confirmed | 79/86 |
| approved review → review | 7/86 |

Blocked seven:

1. `musinsa:5982920`
2. `musinsa:6515855`
3. `musinsa:6534177`
4. `musinsa:6781113`
5. `musinsa:6797265`
6. `musinsa:6797266`
7. `musinsa:6797271`

모두 clone mapping tuple validation은 PASS다. Resolver v4가 기존 `swift-production-2026-08-16-v3` legacy decision의 null/incomplete tuple 또는 `tshirt` family와 clone의 complete `tshirt`/`tank_top` tuple 차이를 발견해 다음 reason으로 review한다.

- `exact_product_decision_tuple_invalid`
- `authority_conflict_unresolved`
- conflict code `product_decision_source_mapping_conflict`

이 7개 decision을 revoke, supersede, complete하거나 Resolver precedence를 바꾸는 것은 이번 승인 범위 밖이므로 수행하지 않았다.

## 10. Unexpected transition count

Approved union 86 밖의 status transition은 **0**이다. Approved fail-closed dispositions도 의도대로 status gain을 만들지 않았다.

- PRODUCT_REQUIRED 25: review → review 25, category mapping confirmed 0
- revoke 75: review → review 75, category mapping confirmed 0
- invalid vocabulary 71: review → review 71

## 11. Gold 3/3

| product | tuple | result |
|---|---|---|
| `uniqlo:E482514` | `tops/short_sleeve/tshirt/tshirt/short_sleeve` | confirmed verified exact |
| `uniqlo:E454311` | `tops/base_layer_top/base_layer_top/base_layer_top/short_sleeve` | confirmed verified exact |
| `uniqlo:E456567` | `tops/base_layer_top/base_layer_top/base_layer_top/short_sleeve` | confirmed verified exact |

Gold exact 3/3, collision 0이다.

## 12. Fail-closed acceptance counts

| acceptance | count |
|---|---:|
| confirmed invalid tuple | 0 |
| PRODUCT_REQUIRED mapping-alone confirmed | 0 |
| approved revoked mapping authority leak | 0 |
| BOTH_UNTRUSTED unsafe confirmed | 0 |
| arbitrary unknown fallback | 0 |
| generic underwear automatic leak | 0 |
| tshirt ↔ base_layer_top automatic leak | 0 |
| name/path product-classifier confirmed | 0 |
| unresolved original conflict | 717 |
| legacy vocabulary owner-review retained | 7 |
| invalid vocabulary review retained | 71 |

Physical mapping bucket이 PRODUCT_REQUIRED/INVALID_MAPPING이어도 independently verified exact product decision으로 confirmed된 기존 row는 있다. 위 leak count는 category mapping alone을 엄격히 구분하며 모두 0이다.

## 13. Comparison eligibility regression

| comparison preview | baseline | revision | delta |
|---|---:|---:|---:|
| allowed | 165 | 244 | +79 |
| confirmed but non-auto group | 8 | 8 | 0 |
| confirmed but measurement policy missing | 4 | 4 | 0 |
| classification not confirmed | 1,431 | 1,352 | -79 |

기존 confirmed 177의 `allowed/reason` regression은 0이다. 새 approved confirmed 79는 self-preview allowed 79/79다. Comparison policy, score, weight, ranking은 변경하지 않았다.

Runtime policy contract는 v1 candidate에서 그대로 상속하고 exact checksum을 검증했다.

| policy | version | checksum |
|---|---|---|
| classifier | `db-auto-classifier-2026-08-18-v2` | `0b76032f9a227caf01345fb81904da20ee6d5f095ec22ddf67299795bf73d9c5` |
| comparison | `v1` | `894f11830cfcd7f4b484700b0e57a05f440b4bf88380067eec40a5abd8a840fa` |
| compatibility | `db-comparison-2026-08-18-v2` | `37e9f0058e06508cf1f2eeb5dd5fae228066de41fd92e2781e1be507e696a96e` |
| measurement | `2026.07.1` | `dfea5b0f3ea935ff73dd05bec8a5fd793eb0d23e7a03f84fac5f563b4c6d3abe` |

`runtime_policy_contract_validated=true`다. Resolver v4, Evaluator v4, Recorder v2 function body/checksum과 call site는 수정하지 않았다.

## 14. Local apply / reapply / idempotency

Fresh database에서 다음 순서를 exact 실행했다.

1. `116_classification_candidate_release_local_fixture.sql`
2. migration 113
3. migration 114
4. migration 115
5. migration 116
6. migration 117 first apply
7. validation + exact-decision transaction + JSONL output + `ROLLBACK`
8. migration 117 reapply
9. validation + JSONL output + `ROLLBACK`

First apply / reapply parity:

| item | first | reapply |
|---|---:|---:|
| local releases | 7 | 7 |
| local v2 release | 1 | 1 |
| local active release | 1 | 1 |
| v2 mappings | 3,509 | 3,509 |
| persistent decisions | 5,056 | 5,056 |
| history | 0 | 0 |
| mapping checksum | `bb968a…c0dd0` | `bb968a…c0dd0` |
| shadow rows | 1,608 | 1,608 |
| shadow checksum | `bb5809…2916` | `bb5809…2916` |

재적용 검증 중 PRODUCT_REQUIRED `reasonCodes`가 반복 append될 수 있는 idempotency 결함을 발견했고, 승인 reason을 order-preserving dedup하는 데이터 표현으로 수정했다. Fresh first apply와 reapply checksum은 이후 exact 동일하다.

Decision 116+2는 validation transaction 안에서만 upsert했고 매 pass 마지막에 rollback됐다. Release activation, history write, active release switch는 0이다.

## 15. Production unchanged evidence

Production preflight `2026-08-26T04:58:02.985718Z`, final postflight `2026-08-26T05:41:28.451116Z`에 SELECT/introspection only로 확인했다.

| Production item | preflight | postflight |
|---|---:|---:|
| products | 1,608 | 1,608 |
| decisions | 5,056 | 5,056 |
| history / current | 1,860 / 1,608 | 1,860 / 1,608 |
| releases | 5 | 5 |
| active release count | 1 | 1 |
| active release ID | `65d72393-4a40-4e99-b701-fdc1ff865774` | same |
| active mappings | 3,492 | 3,492 |
| candidate v1 release/mappings | 0 / 0 | 0 / 0 |
| candidate v2 release/mappings | 0 / 0 | 0 / 0 |
| classification review issues | 0 | 0 |
| resolver v4 present | false | false |
| migration 117 present | false | false |
| latest migration | `20260821090138 seed_zara_verified_measurement_subset` | same |

Production에서 실행한 SQL은 SELECT/introspection뿐이다. Production write/DDL, migration apply, release create/activate/retire, decision/mapping/profile/history write는 모두 0이다. Retailer live API/network 호출도 0이다.

Swift production diff, Resolver/Evaluator/Recorder diff, Phase 1B-3 start, structured typed authority, name profile, taxonomy change는 모두 0이다.

## 16. Remaining blockers

현재 review_required 1,352를 baseline audit primary cause로 추적하면 다음과 같다.

| primary root cause | remaining review |
|---|---:|
| AUTHORITY_CONFLICT | 717 |
| STRUCTURED_EVIDENCE_AVAILABLE_NOT_CONSUMED | 131 |
| PATH_EVIDENCE_UNVERIFIED_OR_INCOMPLETE | 121 |
| PRODUCT_REQUIRED_NO_PRODUCT_AUTHORITY | 99 |
| LEGACY_DECISION_INCOMPLETE | 95 |
| INVALID_MAPPING | 86 |
| NO_MAPPING | 53 |
| NAME_ONLY_DISCRIMINATOR_CANDIDATE | 49 |
| OTHER — revoked exact decision | 1 |
| total | 1,352 |

이번 candidate의 직접 blocker는 approved clone products 중 새로 드러난 7 legacy decision conflicts다. 이를 해소하려면 정확히 다음 중 하나에 대한 새 owner 승인이 필요하다.

1. 해당 7 legacy decisions의 exact disposition 또는 independently adjudicated tuple completion
2. category mapping과 incomplete legacy decision 사이 authority precedence contract 변경
3. 목표를 실제 verified-safe 결과 256/1,352로 재승인

1은 DB data 변경, 2는 backend contract/Resolver 변경이며 둘 다 이번 승인에 포함되지 않았다. 근거 없이 winner를 선택하지 않았다.

## 17. Next-step recommendation

현재 결과로 Phase 1B-3, Production activation/apply, Swift/Resolver/Evaluator 수정, history backfill을 시작하지 않는다.

Owner는 먼저 위 7건의 disposition을 별도로 승인하거나, 256/1,352를 candidate revision의 허용 baseline으로 명시적으로 재승인해야 한다. 그 전에는 release gate를 닫아 둔다.

`Structured Typed Evidence 212 — Read-Only Semantic Validation`은 여전히 가치가 있다. 다만 이번 작업이 GO 조건을 충족하지 못했으므로 자동 시작하지 않는다. Owner가 이 NO-GO를 해소하고 별도 승인한 뒤에만 original 212 cohort와 현재 unresolved 179 subset을 함께 보고 시작한다.
