# FitMatch Classification Authority Phase 1A.5 — Root Cause Adjudication & Phase 1B Go/No-Go

- 감사일: 2026-08-25 KST
- Repository/branch/HEAD: `ljy4337/FitMatch` / `connectDB` / `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab`
- Supabase: `hnkplvyegonlhumlejst`
- Source of Truth: `FitMatchClassificationGlobalBaseline-20260825.md`, 같은 이름의 JSONL, `CodexSessionHandoff.md`
- Tuple 표기: `category / detail / garment_type / comparison_family / length / body_length / status`
- Source 약어: M=musinsa, U=uniqlo, Z=zara.
- 실행 경계: production DB에는 `SELECT`만 실행했다. production DB write 0, migration apply 0, Swift production 수정 0, Phase 1B 시작 0이다.
- 행 단위 근거: `FitMatchClassificationPhase1A5Adjudication-20260825.jsonl` 5,700행, SHA256 `029ca5a036ad4884d7735672ad7a9b8ff23a91a0cd5fcd4613430a4a9a3ccecc`.

## 1. GO / NO-GO

**NO-GO**다.

요청된 전수 분해와 read-only 검증 자체는 완료했다. invalid 952, stale 1,472, conflict 573, risky mapping 1,358의 각 행은 정확히 하나의 primary bucket을 갖고, mixed 59/285도 별도로 판정했다. Current UNIQLO 880은 cached official fixture를 실제 production Swift 경로로 실행했고, live 71은 가능한 정적/DB 검증과 실행 불가 범위를 분리했다.

그러나 Phase 1B를 안전하게 시작하기 위한 변경 값은 아직 전부 확정되지 않았다.

- conflict 310 products는 product decision과 mapping 중 어느 쪽도 신뢰할 독립 근거가 없다.
- manual review가 필요한 production product가 1,037개 남는다.
- structurally invalid mapping 369개의 정확한 replacement tuple은 전부 owner/manual adjudicated 상태가 아니다.
- homewear의 사용자 표시 category와 canonical major를 같은 값으로 둘지 분리할지 owner 결정 1건이 남는다.

Gate 1–8, 11–12는 충족했다. Gate 9와 10이 미충족이므로 Phase 1B migration, seed, RPC 변경, publish를 실행하면 안 된다.

## 2. root cause summary

### 2.1 invalid confirmed 952 — mutually exclusive 전수 분해

Primary cause 우선순위는 `owner/manual로 실제 오류 확정(J) → category/detail 관계(A) → required length axis(F) → legacy taxonomy shape(H) → conflict를 tuple invalidity로 합친 경우(K)`다. 동일 행이 여러 raw reason을 가져도 아래 표에는 한 번만 들어간다.

| bucket | count | source | 대표 current | 기대 tuple/판정 | root cause | Phase 1B 위치 |
| --- | ---: | --- | --- | --- | --- | --- |
| A. CATEGORY_DETAIL_MISMATCH | 167 | M 12 / U 151 / Z 4 | E474152 `tops/shirt/∅/shirt/short_sleeve/∅/confirmed` | `tops/shirt_blouse/shirt_blouse/shirt_blouse/short_sleeve/∅/confirmed` | current legacy detail이 active major의 child가 아님. raw 168 중 6800912는 J로 이동 | decision/profile/history canonicalization |
| B. CATEGORY_GARMENT_TYPE_MISMATCH | 0 | — | — | — | H에 흡수 | — |
| C. GARMENT_FAMILY_MISMATCH | 0 | — | — | — | H에 흡수 | — |
| D. CATEGORY_FAMILY_MISMATCH | 0 | — | — | — | H에 흡수 | — |
| E. MISSING_GARMENT_TYPE | 0 | — | — | — | 단순 NULL이 아니라 schema 전체가 garment를 저장하지 못하는 H로 분류 | — |
| F. MISSING_REQUIRED_LENGTH_AXIS | 109 | M 24 / U 85 | 3144417 `skirts/skirt/skirt/skirt/short_sleeve/∅/confirmed` | `skirts/skirt/skirt/skirt/∅/short/confirmed` | skirt/body, pants, sleeve axis를 legacy `length_code` 하나에 잘못 저장하거나 누락 | history schema/recorder/backfill |
| G. INVALID_OR_DEPRECATED_CANONICAL_CODE | 0 | — | — | — | current product tuple에서는 H로 흡수; mapping 행은 별도 369건 | — |
| H. LEGACY_TAXONOMY_SHAPE | 640 | M 202 / U 421 / Z 17 | E422992 `tops/short_sleeve/∅/tshirt/short_sleeve/∅/confirmed` | `tops/short_sleeve/tshirt/tshirt/short_sleeve/∅/confirmed` | history/decision에 garment column이 없고 legacy family vocabulary를 사용 | additive schema, v4 resolver, history append |
| I. VALID_PRODUCT_BUT_VALIDATOR_TOO_STRICT | 0 | — | — | — | 상품 자체가 맞다고 단정할 독립 근거가 없어 사용하지 않음 | — |
| J. ACTUAL_PRODUCT_MISCLASSIFICATION | 4 | M 1 / U 3 | Golden 3 + 6800912 | owner/manual expected로 교정 | 실제 상품 의미가 틀린 confirmed | verified decision + history |
| K. OTHER — CONFLICT_CONFLATED_WITH_TUPLE_VALIDITY | 32 | U 32 | E465196 `tops/polo_shirt/tshirt/tshirt/short_sleeve/∅/confirmed` | product semantics는 conflict adjudication 전까지 미확정 | canonical tuple 자체는 구조적으로 유효하지만 mapping conflict를 `tuple_valid=false`에 포함 | validator와 authority-conflict gate 분리 |
| **TOTAL** | **952** | **M 239 / U 692 / Z 21** |  |  |  |  |

구조적 tuple 오류는 K 32를 제외한 **920**이다. 이 920은 “실제 상품 오분류”가 아니라 schema/taxonomy/axis 위반이며, 그중 owner/manual로 실제 상품 의미까지 틀렸다고 확정된 것은 J의 4건뿐이다.

### 2.2 stale history 1,472 — mutually exclusive 전수 분해

| bucket | count | source | 현재 의미 변화 | metadata-only update | 재분류 | closet/reference 영향 | comparison history |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| A. OLD_MAPPING_RELEASE_ONLY | 201 | M 52 / U 149 | 없음 | 예 | 아니오 | linked item 0 | snapshot 보존 |
| B. OLD_DECISION_VERSION_ONLY | 35 | M 30 / U 5 | 없음 | 예 | 아니오 | linked item 0 | snapshot 보존 |
| C. PRODUCT_FINGERPRINT_CHANGED | 94 | M 82 / U 12 | 가능 | 아니오 | 새 fingerprint로 재해결 | linked item 0 | snapshot 보존 |
| D. CURRENT_MAPPING_CHANGED | 761 | U 743 / Z 18 | 가능 | 아니오 | successor mapping으로 재해결 | linked item 0 | snapshot 보존 |
| E. PRODUCT_DECISION_CHANGED | 0 | — | — | — | — | — | — |
| F. CANONICAL_POLICY_CHANGED | 0 | — | policy migration은 별도 change set | — | — | — | — |
| G. ACTUAL_CLASSIFICATION_CHANGED | 0 | — | stale reason만으로는 확정하지 않음 | — | — | — | — |
| H. HISTORY_METADATA_ONLY_STALE | 381 | M 128 / U 253 | 없음 | 예 | 아니오 | linked item 0 | snapshot 보존 |
| I. OTHER | 0 | — | — | — | — | — | — |
| **TOTAL** | **1,472** |  |  |  |  |  |  |

Stale 원인만 보면 metadata-only는 **617**(201+35+381), 재해결이 필요한 것은 **855**(94+761)다. 단, metadata-only 617도 별도의 canonical tuple migration 대상과 겹칠 수 있다. 그러므로 stale 617을 current tuple 그대로 무조건 복제하거나, stale 1,472를 전부 의미 변경으로 취급해서는 안 된다. 기존 comparison history는 향후 row가 생기더라도 historical snapshot으로 보존한다.

### 2.3 mapping / product decision conflict 573 — mutually exclusive 전수 분해

573건은 U 572 / Z 1이고 fingerprint match는 573/573이다. 최신 release나 더 구체적인 decision이라는 이유만으로 승자를 정하지 않았다.

| bucket | count | 근거와 판정 | Phase 1B action |
| --- | ---: | --- | --- |
| A. PRODUCT_DECISION_CORRECT | 105 | independent adjudicated fixture 103 + explicit manual correction 2. 현재 decision 의미가 manual expected와 일치 | canonical garment/axis를 붙인 verified successor decision |
| B. SOURCE_MAPPING_CORRECT | 1 | ZARA 547276687: official path가 cardigan 방향을 지지. 단 product detail은 미완성 | legacy decision supersede, product review; auto-confirm 금지 |
| C. BOTH_VALID_DIFFERENT_CONTEXT | 0 | 문맥 차이만으로 둘 다 valid라고 확정할 독립 근거 없음 | — |
| D. PRODUCT_REQUIRED_MIXED_CATEGORY | 72 | 27 mapping identities에서 실제 product별 tuple이 달라짐 | category direct 금지, product resolution |
| E. LEGACY_DECISION_WRONG | 0 | mapping까지 완전 신뢰되는 단독 사례 없음 | — |
| F. SOURCE_MAPPING_WRONG | 85 | 40 mapping identities가 current app-category 또는 garment/group 관계를 구조적으로 위반 | successor mapping fix/fail-close; decision 자동 승격 금지 |
| G. BOTH_UNTRUSTED | 310 | E482514는 owner가 둘 다 틀렸음을 확정; 나머지 309는 self-consistency뿐 | manual review 또는 verified product evidence 전까지 non-auto |
| H. OTHER | 0 | — | — |
| **TOTAL** | **573** |  |  |

### 2.4 category-only risky mapping 1,358 및 mixed 59

Phase 1A의 `invalid_semantic_tuple=238`은 garment/group/major 관계만 검사했다. 이번 SELECT 교차검증에서 non-null `detail_code`가 current `app_categories` major의 active child가 아닌 mapping이 173개였고, 두 집합의 overlap은 42개였다. 따라서 current DB contract에 대한 구조 오류 union은 **369 = 238 + 173 - 42**다.

| requested bucket | count | source | 판정 |
| --- | ---: | --- | --- |
| A. SAFE_DIRECT | 0 | — | 이 1,358 집합 밖에 34개 존재 |
| B. SAFE_WITH_EXISTING_EVIDENCE | 0 | — | 이 1,358 집합 안에는 없음 |
| C. PRODUCT_REQUIRED | 989 | M 208 / U 716 / Z 65 | category hint는 보존 가능하지만 confirmed tuple은 product evidence가 필요 |
| D. REVIEW_REQUIRED | 0 | — | mapping row를 product status와 혼동하지 않음 |
| E. EXCLUDED | 0 | — | 이 집합은 confirmed mapping만 포함 |
| F. UNSUPPORTED | 0 | — | 이 집합은 confirmed mapping만 포함 |
| G. INVALID | 369 | M 150 / U 219 | successor에서 fix 또는 non-direct/fail-close |
| **TOTAL** | **1,358** |  |  |

전체 active confirmed mapping 1,392의 Phase 1B resolution contract는 **category direct 34 / product required 989 / invalid 369**다.

59 mixed buckets / 285 products의 별도 교차판정은 다음과 같다.

- `SAFE_WITH_EXISTING_EVIDENCE`: 3 buckets / 21 products. explicit T-shirt path이며 single known family + missing decision만 있어 기존 34 direct 안에 유지한다.
- `PRODUCT_REQUIRED`: 46 buckets / 202 products. 실제 family/detail/length가 갈리거나 confirmed mapping 자체가 incomplete하다.
- `EXCLUDED`: 10 buckets / 62 products. mapping이 이미 rejected이므로 direct로 부활시키지 않는다.

### 2.5 Current UNIQLO 880 read-only 검증

`CurrentUniqloCatalogAuditTests`를 cached official catalog fixture와 production Swift 코드로 실제 실행했다. 1 test PASS, 135.907초, raw 5,193 size rows, parsed 5,181 rows, A-test 2,246/2,246 PASS였다.

| metric | result |
| --- | ---: |
| fixture total / unique | 880 / 880 |
| local result coverage / unique | 880 / 880 |
| production DB manifest coverage | 880 / 880 |
| local operational proxy confirmed/review/notComparable/unclassified | 439 / 0 / 300 / 141 |
| DB current confirmed/review/notComparable/unclassified | 670 / 100 / 110 / 0 |
| local `classification.isValid` invalid | 0 |
| DB strict invalid tuple | 811 |
| local/DB exact / mismatch | 482 / 398 |
| mismatch dimensions | category 122 / detail 153 / family 174 / length 350 |
| mapping/decision conflict | 431 |
| Golden present / collision | 3 / 3 |
| mixed mapping product | 102 |
| missing DB measurement policy | 196 |

Local status는 test attachment에 DB status가 없어서 `category 없음→unclassified`, `confirmation 필요→review`, `canonicalEligibility=false→notComparable`, 나머지→confirmed로 만든 operational proxy다. `review=0`을 semantic review가 없다는 뜻으로 해석하면 안 된다.

Expected provenance도 분리했다. 880 fixture는 official catalog path/size payload의 cached source fact이고, local result는 현재 Swift가 생성한 결과다. 독립 semantic Gold가 아니다. 실제로 E482514/E454311/E456567은 모두 local에서도 underwear로 남았지만 self-consistency A-test는 PASS했다. 따라서 2,246 PASS는 비교 흐름의 결정성과 boundary를 증명할 뿐 분류 정확도 100%를 증명하지 않는다.

Missing DB measurement policy 196은 dresses 15, homewear 36, leggings 24, skirts 23, underwear 98이다. Production `app_category_measurement_policies`는 tops/bottoms/outerwear에만 존재한다.

### 2.6 live comparison 71

새 대량 외부 호출은 하지 않았다. Fixture/current DB/cached evidence만 사용했다.

| metric | result |
| --- | ---: |
| fixture | 71 = M 40 + U 31; coverage gaps 6 |
| production DB coverage | 33 |
| DB status | confirmed 32 / review 1 |
| DB invalid tuple | 31 |
| historical expected detail과 DB 비교 | 18 match / 15 mismatch / 38 DB 없음 |
| mapping/decision conflict | 17 |
| mixed bucket | 1 |
| runtime ready / strict policy ready | 21 / 18 |
| silent propagation risk | 3 |
| live parse/measurement/recommendation | **SKIP 71** |

Historical expected detail은 과거 live 결과이지 owner Gold가 아니다. 15 mismatch를 곧바로 DB 오류라고 판정하지 않았다. Production linked closet item은 0이고 comparison history도 0이므로 user-specific candidate allow/block의 동적 DB/local 비교도 SKIP이다.

현재 runtime은 허용하지만 strict policy는 막아야 하는 3건은 E488204, E488364, E488738이다. 모두 skirt 계열이며, 이 상태가 recommendation까지 전파되지 않도록 Phase 1B evaluator가 fail-closed해야 한다. Live network 실행을 하지 않은 71건을 PASS로 기록하지 않는다.

### 2.7 기존 31 products / 64 assertions

- 207 expected는 모두 independent manual adjudication이다. 자동 생성 expected 0, outdated assertion 0, taxonomy 자체 모순으로 판정한 assertion 0, expectation correction 대상 0이다.
- Current DB overlap은 137, manual expected exact는 132, DB mismatch는 5다.
- 31 products / 64 assertions(category 1, detail 31, family 31, length 1)는 local Swift logic이 manual expected/DB와 달라진 회귀다. 전부 iOS Phase 2 대상이고 expected를 수정하지 않는다.
- Phase 1B DB 대상 5: `musinsa:6800912`, `uniqlo:E450536`, `uniqlo:E465193`, `uniqlo:E486066`, `uniqlo:E486103`.
- Current catalog에 없는 historical fixture는 70개다. 그중 3개가 local 31-failure에 포함되고, 나머지 67개는 현 production DB change 대상이 아니다.

## 3. 실제 오분류 수

Independent owner/manual evidence로 현재 production product 의미가 틀리거나 빠졌다고 확정한 것은 **8 products**다.

- Wrong confirmed 4: E482514, E454311, E456567, musinsa 6800912.
- Review false-negative 4: E450536, E465193, E486066, E486103.

Canonical expected는 Gold 3건을 사용자 지정 그대로 사용한다. 6800912는 `tops/shirt_blouse/shirt_blouse/shirt_blouse/short_sleeve/∅/confirmed`; E465193/E486103은 `tops/long_sleeve/tshirt/tshirt/long_sleeve/∅/confirmed`; E450536/E486066은 current official fixture의 sleeve evidence까지 사용해 `tops/knit_top/knit_sweater/knit_sweater/long_sleeve/∅/confirmed` 후보로 검증해야 한다. 마지막 두 건의 Phase 1B seed는 cached size/name evidence checksum을 함께 고정해야 한다.

이 8은 lower-bound verified count다. G/BOTH_UNTRUSTED 310과 manual review 1,037을 맞다고 간주하지 않았으므로, 실제 semantic error가 8개뿐이라는 뜻은 아니다.

## 4. 구조적 tuple 오류 수

Product current confirmed의 구조적 tuple 오류는 **920**이다. Mapping row의 구조적 오류 369는 별도 집합이며 이 수에 합산하지 않는다.

`invalid confirmed 952 = structural 920 + conflict-conflated 32`다. Structural 920 안에는 실제 의미까지 틀린 confirmed 4가 포함된다.

## 5. metadata-only stale 수

**617**이다. OLD_MAPPING_RELEASE_ONLY 201 + OLD_DECISION_VERSION_ONLY 35 + HISTORY_METADATA_ONLY_STALE 381이다.

이 수는 “stale 원인만 metadata”라는 뜻이다. 해당 product가 별도 canonical migration으로 tuple 변경될 가능성은 남아 있다. 기존 current history를 in-place rewrite하거나 historical comparison snapshot을 삭제하지 않는다.

## 6. 실제 mapping 오류 수

Current DB contract에 대해 구조적으로 확정된 mapping 오류는 **369 mapping rows**다.

- Phase 1A garment/group/major invalid 238.
- 추가 발견한 non-null detail/major mismatch 173.
- overlap 42.
- conflict product 관점에서 SOURCE_MAPPING_WRONG은 85 products / 40 unique mapping identities이며 369의 부분집합이다.

369를 모두 같은 replacement tuple로 바꾸지 않는다. Correct canonical 값이 owner/manual evidence로 확정된 행만 fix하고, 나머지는 successor release에서 non-direct/fail-close한다.

## 7. product-required mapping 수

**989 active confirmed mappings**다. 이들은 mapping evidence를 삭제하거나 rejected로 일괄 변경하지 않는다. Category hint는 유지하되 v4 resolver가 name/product fingerprint/verified decision 없이 confirmed tuple을 만들 수 없도록 한다.

Category-level direct로 남길 것은 34개다. Mixed 교차검증에서 3개/21 products는 explicit T-shirt path라 이 34 안에 유지했고, 46 mixed buckets/202 products는 product resolution으로 보냈다.

## 8. manual review 필요 product 수

**1,037 production products**다.

Phase 1A preview의 1,147에서 이번에 독립/manual 근거가 확보된 conflict 105와 DB mismatch 5, 합계 110을 제외했다. 이 1,037을 일괄 `review_required`로 쓰지 않는다. Phase 1B gate/queue에 행 단위 reason을 적재하고 verified evidence가 있는 product만 decision/history를 변경한다.

## 9. owner decision 필요 항목

Owner 질문은 **homewear canonical/display 관계 1건**만 남긴다. Dresses, underwear, base-layer는 current DB와 코드 의미로 fail-closed 정책을 확정했다.

| scope | 사용자 표시 | canonical major | garment/group | length axes | measurement | auto compare | migration |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base-layer top | tops / base_layer_top | tops | base_layer_top / base_layer_top | sleeve required | upper_core, min 2 | 기존 DB상 eligible; strict evidence 필요 | Gold E454311/E456567 및 product-level cases |
| dresses | dresses / one_piece | dresses | dress / dress 신규 | body required, sleeve product별 | chest/waist/hip/total_length | Phase 1B에서는 false | current 48 histories, closet 0 |
| underwear | underwear / subtype | underwear | bottom/bra/top subtype별 분리 | generic sleeve 불필요; subtype body optional | bottom waist/hip; bra chest/under_bust; top chest/length | Phase 1B에서는 false | current 142 중 Gold 3은 tops로 이동 |
| homewear | homewear / loungewear | **owner 결정** | top/bottom/set 분리 | product 구조별 | top/bottom policy mirror | false | current 47 histories, closet 0 |

Base-layer top은 DB에 이미 `tops/base_layer_top/base_layer_top`, sleeve required, `upper_core`, min 2, auto-comparable row가 있다. 반면 Swift `CanonicalComparisonProfile.appGarmentFamily`는 `base_layer_top`을 `underwear`로 축약한다. 이는 Phase 2 iOS defect이며 bra/panty 계열과 같은 comparison family로 합치면 안 된다.

Underwear는 bra, lower underwear, lingerie top을 서로 다른 non-auto group으로 둔다. `women_camisole`/undershirt가 기능성 base layer인지 lingerie인지 애매하면 product-level 판정한다. Generic underwear 하나로 자동 비교하지 않는다.

Homewear owner 선택지는 다음 3개다.

1. **A — 권장:** display/canonical major를 homewear로 유지하고 non-auto `homewear_top`, `homewear_bottom`, `homewear_set` group을 추가한다. 47 histories를 재판정하지만 자동 비교 변화는 0이다.
2. B: single piece를 canonical tops/bottoms로 보내고 homewear는 display metadata로 분리한다. 의미는 가장 깔끔하지만 additive display/canonical 분리와 iOS Phase 2가 필요하다.
3. C: homewear를 전부 review/notComparable로 유지한다. 새 group은 없지만 현재 confirmed 47이 confirmed eligibility를 잃는다.

## 10. Phase 1B 정확한 변경 object

아래는 baseline 11–15절을 유지하면서 이번 판정으로 범위를 좁힌 목록이다. NO-GO가 해소되기 전에는 적용하지 않는다.

| class/object | 현재 역할/문제 | 변경 내용 | 변경하지 않을 내용 | migration/backfill | rollback/validation | iOS 영향 |
| --- | --- | --- | --- | --- | --- | --- |
| A SCHEMA — `fitmatch_catalog.product_classification_decisions` | exact decision; garment/authority 없음 | additive `garment_type_code`, `authority_status`, verified completeness CHECK; FK는 code 검증 후 | 기존 key/legacy rows 삭제 안 함 | 5,056 rows `legacy` 보존; targeted plan 114 | additive column 유지, bad new decision revoke; verified tuple 100% validator | additive DTO는 Phase 2 소비 |
| A SCHEMA — `fitmatch_catalog.product_classification_history` | append/supersede current; garment 없음 | additive `garment_type_code` | delete/in-place mass rewrite 안 함 | expected new current 1,601–1,608 | rollback tuple을 새 current로 append; current=1 | runtime DTO additive |
| A SCHEMA — `fitmatch_catalog.releases` | release pointer; production gate 114 없음 | migration 114의 validation columns, one-active index | active row in-place mapping edit 안 함 | successor candidate | gate report/checksum/count/QA | 없음 |
| A SCHEMA — `fitmatch_catalog.data_quality_issues`, `data_quality_review_queue` | issue ledger 0; triage/view 없음 | migration 114 triage columns/index/security-invoker view | 새 queue table 만들지 않음 | 1,037 product review reasons는 dedupe issue로 계획 | status/reason required; rollback은 columns/view 보존 후 traffic stop | 없음 |
| B FUNCTION — `runtime_resolve_product_classification_v4` | v3 authority 혼합 | verified product → clear direct mapping → verified profile → legacy exact → exclusion → review | v3 signature 삭제 안 함 | 없음 | 5,026 + Gold + conflict leakage 0 | Phase 2 shadow parity |
| B FUNCTION — `runtime_resolve_and_promote_product`, `runtime_record_product_classification_v2` | fingerprint만 재사용; garment 기록 불가 | fingerprint/release/version/garment stale 비교, append/supersede; old recorder wrapper | old function drop 안 함 | 1,472 stale + non-stale invalid confirmed | current=1, history delete 0 | additive response |
| B FUNCTION — `runtime_release_gate_report`, `enforce_release_activation_gate`, `runtime_activate_validated_release`, `runtime_triage_data_quality_issue` | production에 없음 | local 114와 ledger reconcile 후 그대로 검증 | gate bypass/grant 확대 안 함 | release validation metadata | migration 114 verification, security baseline | 없음 |
| B RPC — `public.fitmatch_resolve_product`, `public.fitmatch_get_product_runtime` | garment/authority 없음 | 기존 key 유지, garment/authority/release/version/evidence additive | arguments/기존 JSON key 변경 안 함 | 없음 | DTO 14 regression + backward client | Phase 2 DTO 소비 |
| B RPC — `public.fitmatch_upsert_closet_item`, `public.fitmatch_list_closet_items` | family를 garment로 오인 가능 | valid garment code→UUID lookup, invalid confirmed fail-close, manual override 유지 | 별도 garment string column/사용자 값 변경 안 함 | linked closet 0 | manual closet 6 regression | sync coordinator Phase 2 |
| B FUNCTION/RPC — `runtime_evaluate_comparison_profiles_v4`, `fitmatch_find_reference_candidates`, `fitmatch_begin_comparison` | v3가 legacy family를 hard-code하고 public policy table을 직접 권위로 쓰지 않음 | canonical garment/group/axis/measurement policy 기반 evaluator; 외부 signature 유지 | generic family 자동 허용 안 함 | history readiness 재계산 | runtime>strict leak 0; live silent-risk 3 block | matcher parity Phase 2 |
| C MAPPING DATA — `fitmatch_catalog.releases`, `source_category_mappings` | active 3,492 | exact clone; direct 34 유지, product-required 989 표시, invalid 369 fix/fail-close; 82144 포함 | current active release/identity 삭제 안 함 | candidate 3,492 | checksum/count/risk manifest | resolver만 영향 |
| C PROFILE DATA — `classification_name_profiles`, `classification_path_profiles`, `classification_exclusion_profiles` | legacy family vocabulary | new policy version; ambiguous auto-ineligible | old version 삭제 안 함 | versioned regeneration | 5,026 unexpected failure 0 | Phase 2 parity |
| C TAXONOMY/POLICY DATA — `public.garment_types`, `comparison_groups`, `comparison_policies`, `app_category_measurement_policies`, subtype overrides | dresses/underwear/homewear rows·정책 없음 | dress/underwear fail-closed rows; homewear는 owner A/B/C 후 확정 | base_layer를 underwear family로 이동 안 함 | current scope 237, Gold 3 tops 이동 | auto=false, policy/measurement validator | local embedded policy와 Phase 2 parity |
| D PRODUCT DECISION — `product_classification_decisions` | legacy authority | 105 verified conflict winners + actual 8 = 113 successor decisions; ZARA 1은 supersede-to-review | 5,056 일괄 revoke 안 함 | exact 114-row plan이 JSONL에 있음 | fingerprint exact, revoked resolver use 0 | expected 수정 없음 |
| E HISTORY BACKFILL — `product_classification_history` | stale/legacy current | 617 metadata cause, 855 re-resolve, non-stale confirmed garment migration; append only | historical delete 0 | 1,601–1,608 예상 | total current 1,608 exact | DTO additive |
| F RELEASE/PUBLISH — candidate release/profile versions | QA count 0인 active release | full QA evidence가 있는 validated successor만 activate | 자동 publish/old active mutation 안 함 | mapping 3,492 | migration 114 gate 전 항목 PASS | 없음 |
| G NO CHANGE | products/observations/snapshots/sizes/measurements/manual closet/comparison history | 없음 | 원본과 historical snapshot 보존 | 0 | count non-decrease | 없음 |
| H DEFER TO IOS PHASE | `CanonicalComparisonProfile`, matcher, recommendation, measurement engine | DB/local vocabulary drift, 31/64 local fail | Phase 2에서만 수정 | 이번 Phase Swift 수정 0 | 31/64 expected 보존 | 별도 Phase |

Backfill 순서, rollback 원칙, acceptance criteria는 baseline 13–15절을 그대로 유지한다. 이번 Phase의 추가 acceptance는 mapping `detail_code` parent 관계 검증, 369 invalid direct 사용 0, 989 product-required category auto-confirm 0, mixed 59 판정 보존, UNIQLO Gold collision 0, live silent-risk 3 block이다.

## 11. Phase 1B에서 절대 건드리지 않을 object

- `fitmatch_catalog.products`, `product_observations`, `source_product_snapshots` row와 fingerprint/source fact.
- variants, sizes, normalized/raw measurements, source measurement evidence.
- 기존 classification history DELETE, comparison history DELETE, table DROP/TRUNCATE.
- `public.closet_items` manual override, user measurements, soft-delete 상태.
- existing RPC argument signatures와 기존 JSON keys.
- active release `65d72393-4a40-4e99-b701-fdc1ff865774`의 in-place mapping mutation.
- legacy decision 5,056의 일괄 revoke/폐기.
- fixture expected의 자동 변경.
- RLS/GRANT/SECURITY DEFINER/search_path baseline의 의도하지 않은 변경.
- Swift production code. Base-layer transform과 31/64는 iOS Phase 2다.

삭제가 필요한 table/object/역사 row는 발견하지 않았다. DROP 0, TRUNCATE 0, historical DELETE 0을 유지한다. 잘못된 새 decision/release는 delete 대신 revoked/retired/superseded/inactive를 사용한다.

## 12. Phase 1B 예상 영향 product / closet / history 수

| object | expected impact |
| --- | ---: |
| `products` 원본 row | **0 변경**; 1,608 전수 재계산만 수행 |
| semantic correction independently verified | minimum 8 products |
| product decisions | 5,056 legacy 보존; targeted plan 114(verified/corrected 113 + ZARA supersede-to-review 1) |
| source mappings | successor clone 3,492; direct 34 / product-required 989 / invalid 369; non-confirmed 2,100 보존 |
| policy-scope current products | 237 = dresses 48 + underwear 142 + homewear 47; Gold 3은 tops로 이동 |
| closet | total 6 / active 1 / linked product **0**; automatic migration 0, manual override 변경 0 |
| classification history | existing 1,860 보존; expected append/supersede **1,601–1,608**, post-migration total 3,461–3,468, current는 항상 1,608 |
| comparison history/runs | current 0; migration 변경 0, future snapshot contract 보존 |

History 범위가 range인 이유는 non-stale non-confirmed 7건이 successor metadata 변화 없이 재사용 가능한지 owner policy/re-resolve 결과에 달렸기 때문이다. 이 범위를 단일 숫자로 가장해 Phase 1B를 시작하지 않는다.

Rollback은 candidate pre-activation retire, prior release 기반 gated rollback release, bad decision revoke, history supersede+rollback append, old function wrapper/old JSON key 유지로 수행한다. Schema column/function은 즉시 drop하지 않는다.

## 13. 미검증 항목

- Live comparison 71의 새 network parse, official measurement fetch, 실제 recommendation은 전부 SKIP이다. 이유는 사용자 지시의 no-new-bulk-external-call과 live-only dependency다.
- Production linked closet item이 0이므로 DB candidate allow/block와 실제 authenticated user recommendation end-to-end는 동적으로 검증하지 못했다.
- UNIQLO 880의 2,246 PASS는 current Swift self-consistency다. 독립 semantic expected가 없고 Gold 3 collision이 있으므로 정확도 PASS가 아니다.
- Conflict BOTH_UNTRUSTED 310의 올바른 product tuple.
- Manual review 1,037의 owner/independent product truth.
- Structurally invalid mapping 369 중 owner/manual replacement가 없는 행의 새 tuple.
- Homewear owner 선택 A/B/C.
- Current production에는 release gate 114와 review queue view가 없고 active release QA count가 0이므로 gated publish를 실제로 검증하지 못했다.
- COS production DB end-to-end와 current comparison history migration은 여전히 검증되지 않았다.

## 14. 다음 명령

다음 단계는 Phase 1B가 아니라 산출물 무결성 확인과 owner/homewear 선택 수집이다. 안전한 다음 명령은 다음 두 개다.

```bash
jq -s 'group_by(.record_type) | map({type: .[0].record_type, count: length})' Docs/FitMatchClassificationPhase1A5Adjudication-20260825.jsonl
git diff --check
```

Owner가 homewear A/B/C를 결정하고, 310 conflict/369 invalid mapping의 필요한 adjudication artifact가 확보된 뒤에만 이 보고서의 Gate 9–10을 다시 계산한다. **Phase 1B는 자동 시작하지 않는다.**
