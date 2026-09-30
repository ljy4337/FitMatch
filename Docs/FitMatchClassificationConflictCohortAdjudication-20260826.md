# FitMatch Classification Authority — Conflict Cohort Adjudication

Date: 2026-08-26 KST

Repository: `ljy4337/FitMatch`

Branch: `connectDB`

Production Supabase: `hnkplvyegonlhumlejst`

Mode: **READ-ONLY / NO PRODUCTION CHANGE / NO ALGORITHM CHANGE**

## 1. Executive conclusion

입력 baseline과 대상 수는 모두 exact match다.

- Phase 1B-2 shadow SHA-256: `b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385`
- Review Evidence Audit SHA-256: `cbcfa931a01c152f6b8205cf26a3d2696af73ad5b3ec0f9585f52831eec81ddb`
- review baseline: 1,431
- A conflict: 718
- B DB-only conservative candidate: 105
- C invalid-mapping product: 171
- A/B/C unique union: **895**. 겹침을 숨긴 `994`는 사용하지 않았다.

핵심 결론은 다음과 같다.

1. Conflict 718은 지정 key를 독립 adjudication 경계에서 한 번 더 분리해 **279 cohort**로 압축됐다. Product verdict는 `BOTH_UNTRUSTED 394`, `PRODUCT_REQUIRED 165`, `NEEDS_PRODUCT_ADJUDICATION 147`, `VERIFIED_DECISION_WINS 12`다.
2. 독립 검증된 semantic winner는 12건이지만, 현재 active v4 vocabulary로 owner 추론 없이 완성 가능한 conflict product는 **1건**뿐이다. 따라서 conflict 718의 verified-safe immediate unblock은 1, 잔여는 717이다.
3. DB-only 105는 **safe 86 / owner vocabulary 확인 7 / semantic adjudication 12**로 분리됐다. Safe 86은 Musinsa verified `CATEGORY_DIRECT` target clone 84와 UNIQLO exact decision tuple completion 2다.
4. Musinsa 84의 공통 원인은 빈 category code가 아니라 **mapping `target=UNKNOWN` 대 product audience exact-match 실패**다. 6개 base mapping을 17개 observed-target row로 clone하면 기존 v4 contract 안에서 84건을 커버할 수 있다.
5. Invalid-mapping 171은 **64 mapping rows**다. Verified replacement는 0이다. 10 rows/25 products는 `PRODUCT_REQUIRED`, 30/75는 replacement 없는 revoke 유지, 24/71은 taxonomy/app-mapping vocabulary reconciliation이 필요하다.
6. Independently verified safe gain은 총 **86**뿐이다. 이를 별도 승인된 future candidate-data에 반영한다고 가정해도 Phase 1B-3 전 예상치는 `confirmed 177→263`, `review_required 1,431→1,345`다. 이번 작업에서 실제 승격·write·apply는 0이다.
7. Structured typed signal 212와 name-add 246은 safe gain에서 제외했다. Owner가 선택한 structured-first 정책에 따라 212는 다음 별도 read-only adjudication의 가치가 있지만, 이번에 authority를 추가하지 않았다.

## 2. Scope, overlap, and manual flags

### 2.1 Exact overlap partition

| Mutually exclusive cell | Products |
|---|---:|
| A only | 621 |
| B only | 91 |
| C only | 84 |
| A∩B only | 12 |
| A∩C only | 85 |
| B∩C only | 2 |
| A∩B∩C | 0 |
| **Unique union** | **895** |

Pairwise intersection은 A∩B 12, A∩C 85, B∩C 2다. Triple overlap은 0이다.

### 2.2 Candidate manual flag overlap

| Scope | Manual-flag products |
|---|---:|
| full review baseline | 1,009 |
| A/B/C union | 719 |
| conflict A | 599 |
| DB-only B | 37 |
| invalid mapping C | 171 |

Manual flag 1,009는 1,009개의 서로 독립적인 mapping defect를 뜻하지 않는다. A/B/C union의 719 manual flags 가운데 invalid products 171은 64 mapping rows로, conflict 599는 deterministic cohort로 압축된다.

## 3. Authority Conflict 718 → 279 cohorts

### 3.1 Cohort key

기본 key는 다음과 같다.

`source + mapping source_identity + decision_version + conflict-dimension signature + Phase1A.5 root-cause class`

이 key만 그대로 사용하면 276 cohorts다. 다만 그중 세 cohort가 독립 adjudicated exact-but-incomplete product와 unverified peer를 같이 포함했다. Verified winner가 unverified 다수결에 섞이지 않도록 `INDEPENDENT_EXPECTED_CONFIRMED_V4_INCOMPLETE` Phase1A.5 class를 우선 적용해 deterministic하게 분리했고, 최종은 **279 cohorts**다. 상품명은 key나 winner 결정에 사용하지 않았다.

### 3.2 Source and mapping distribution

| Source | Products | Cohorts |
|---|---:|---:|
| UNIQLO | 693 | 267 |
| ZARA | 25 | 12 |
| Musinsa | 0 | 0 |
| **Total** | **718** | **279** |

| Candidate mapping bucket | Conflict products |
|---|---:|
| PRODUCT_REQUIRED | 474 |
| OTHER_EXISTING | 159 |
| INVALID_MAPPING | 85 |
| **Total** | **718** |

Conflict가 연결되는 unique mapping identity는 268개다. Cohort 수가 더 큰 이유는 동일 mapping에서도 decision version, conflict dimension, Phase1A.5 class가 다른 경우를 합치지 않았기 때문이다.

### 3.3 Verdict distribution

| Verdict | Cohorts | Products | 의미 | Immediate safe unblock |
|---|---:|---:|---|---:|
| VERIFIED_DECISION_WINS | 11 | 12 | 독립 expected semantic decision이 legacy mapping보다 우선 | 1 |
| PRODUCT_REQUIRED | 67 | 165 | category authority는 product-level truth 없이는 확정 불가 | 0 |
| BOTH_UNTRUSTED | 137 | 394 | Phase1A.5 `G_BOTH_UNTRUSTED` 309 + `F_SOURCE_MAPPING_WRONG` 85 | 0 |
| NEEDS_PRODUCT_ADJUDICATION | 64 | 147 | 두 legacy authority 중 winner 근거 없음 | 0 |
| **Total** | **279** | **718** |  | **1** |

Source별로 UNIQLO는 `BOTH_UNTRUSTED 394 / PRODUCT_REQUIRED 140 / NEEDS_PRODUCT_ADJUDICATION 147 / VERIFIED_DECISION_WINS 12`다. ZARA 25는 모두 12개의 `PRODUCT_REQUIRED` cohort다.

### 3.4 Phase 1A.5 evidence classes

| Phase1A.5 class | Products | 처리 |
|---|---:|---|
| G_BOTH_UNTRUSTED | 309 | 어느 쪽도 승자로 사용하지 않음 |
| NOT_IN_PHASE1A5_CONFLICT_COHORT | 240 | candidate product-required면 그대로 fail-close, 나머지는 product adjudication |
| F_SOURCE_MAPPING_WRONG | 85 | mapping은 잘못됐지만 legacy decision을 자동 승격하지 않음 |
| D_PRODUCT_REQUIRED_MIXED_CATEGORY | 72 | verified product-required 유지 |
| INDEPENDENT_EXPECTED_CONFIRMED_V4_INCOMPLETE | 12 | semantic decision winner 인정, tuple completion 별도 gate |

다수결, current Swift result, current Production confirmed status는 truth로 사용하지 않았다.

### 3.5 Decision/release facts

718건 모두 stored product fingerprint와 현재 decision fingerprint가 일치한다. 즉 이 cohort의 주 원인은 fingerprint drift가 아니다.

| Decision version | Products | Decision release status |
|---|---:|---|
| `swift-production-2026-08-16-v3` | 690 | retired |
| `zara-production-sample-2026-08-21-v1` | 25 | active |
| `db-runtime-2026-08-18-v1` | 2 | retired |
| `db-runtime-family-correction-2026-08-18-v1` | 1 | retired |

Candidate mapping은 local-only release `9f9c8155-61d9-41ce-9dd1-bf695ecc2140`의 `validated` artifact이고, Production active parent는 `65d72393-4a40-4e99-b701-fdc1ff865774`다. Cohort JSONL에는 mapping tuple, decision tuple, current history tuple signature, stale reasons, tuple blockers, release/status가 모두 집계돼 있다.

### 3.6 Correction leverage

- Independently verified semantic winner: 12 products / 11 cohorts.
- 그중 unique active v4 tuple completion까지 검증된 conflict product: **UNIQLO E482522 1건**.
- 나머지 winner 11건은 active vocabulary 또는 taxonomy 의미 동일성을 owner가 확인해야 한다.
- `PRODUCT_REQUIRED` 165는 mapping disposition이 이미 안전하다. Legacy decision을 일괄 winner로 바꾸면 안 되며, confirmed gain은 0이다.
- `BOTH_UNTRUSTED` 394와 `NEEDS_PRODUCT_ADJUDICATION` 147에는 cohort-wide verified winner가 없다.
- 따라서 이번 evidence로 가능한 P1 cohort-wide verified correction은 **0 changes / 0 safe gain**이다.

가장 큰 cohort는 26 products지만, independently verified 범위가 없으므로 26을 safe gain으로 세지 않았다. 모든 cohort의 affected product list와 correction unit은 `FitMatchClassificationConflictCohorts-20260826.jsonl`에 있다.

## 4. DB-only conservative candidate 105

### 4.1 Final partition

| Subset/verdict | Products | Musinsa | UNIQLO | Safe gain now |
|---|---:|---:|---:|---:|
| Verified CATEGORY_DIRECT target-row completion | 84 | 84 | 0 | 84 |
| A `SAFE_TUPLE_COMPLETION_DB_ONLY` | 2 | 0 | 2 | 2 |
| B `VOCABULARY_TRANSLATION_NEEDS_OWNER_CONFIRM` | 7 | 2 | 5 | 0 |
| C `SEMANTIC_ADJUDICATION_REQUIRED` | 12 | 0 | 12 | 0 |
| **Total** | **105** | **86** | **19** | **86** |

105건 중 새 Resolver/algorithm contract가 필요한 product는 0이다. 다만 semantic 12 중 underwear 10은 현재 active garment/comparison vocabulary로 complete tuple을 만들 수 없어, owner가 confirmed를 원한다면 별도 taxonomy 결정이 필요하다.

### 4.2 CATEGORY_DIRECT 84: exact root cause

84건은 6개의 verified Musinsa base mapping에 연결된다.

| External category | Path | Products | Observed target variants | Required clone rows |
|---|---|---:|---:|---:|
| 001001 | 상의 > 반소매 티셔츠 | 59 | 5 | 5 |
| 001010 | 상의 > 긴소매 티셔츠 | 10 | 4 | 4 |
| 001011 | 상의 > 민소매 티셔츠 | 9 | 3 | 3 |
| 017016002 | 스포츠/레저 > 상의 > 긴소매 티셔츠 | 1 | 1 | 1 |
| 017016003 | 스포츠/레저 > 상의 > 나시/민소매 티셔츠 | 2 | 2 | 2 |
| 017016005 | 스포츠/레저 > 상의 > 반소매 티셔츠 | 3 | 2 | 2 |
| **Total** |  | **84** |  | **17** |

Production parent와 candidate clone의 base row는 모두 `target=UNKNOWN`이다. Resolver v4는 `mapping.target = upper(payload.audience)` exact equality를 요구하며 `UNKNOWN`을 wildcard로 처리하지 않는다. 84개 product audience는 `M`, `W`, `MEN`, `WOMEN`, `M,W` 중 하나이므로 mapping이 선택되지 않았다.

보조 defect는 다음과 같지만 단독 primary blocker는 아니다.

- `source_category_codes=[]`: 45. 이 45건은 모두 normalized path exact match다.
- normalized path mismatch: 2. 두 상품은 각각 exact leaf code `001001` 또는 `001010`을 보유한다.
- code present: 39, path exact: 82, exact code 또는 exact path: **84/84**.

따라서 verified base tuple을 observed literal target별로 clone하는 17개의 candidate-only mapping row가 최소 DB-data correction unit이다. Product audience를 대량 재작성하거나 `UNKNOWN` wildcard 의미를 Resolver에 새로 추가할 필요가 없다. 새 row는 candidate mapping count/checksum을 바꾸므로, 실제 적용은 별도 승인된 새 candidate-data artifact에서만 재검증해야 한다.

### 4.3 Phase 1A.5 exact-but-incomplete 21

| Verdict | Products | Evidence conclusion |
|---|---:|---|
| A SAFE_TUPLE_COMPLETION_DB_ONLY | 2 | expected `tops/short_sleeve/tshirt/short_sleeve`; active `tshirt` garment/family가 유일 |
| B VOCABULARY_TRANSLATION_NEEDS_OWNER_CONFIRM | 7 | legacy `shirt` 2, `knit_top/knit_cardigan` 5; active vocabulary translation을 자동 승인하지 않음 |
| C SEMANTIC_ADJUDICATION_REQUIRED | 12 | underwear 10, outerwear/cardigan 1, windbreaker missing valid sleeve axis 1 |

Safe 2는 `uniqlo:E482522`, `uniqlo:E485454`다. E482522만 conflict A와 겹친다.

B의 7건은 다음과 같다.

- `musinsa:4989733`, `musinsa:6843879`: legacy `shirt`와 active `shirt_blouse` 의미 동일성 owner 확인 필요.
- `uniqlo:E450535`, `E475053`, `E481004`, `E482328`, `E485318`: legacy `knit_top/knit_cardigan`을 active `knit_sweater` 또는 `cardigan` 중 어느 것으로 번역할지 확인 필요.

C의 12건은 underwear 10건과 `uniqlo:E488014`, `uniqlo:E491320`이다. Expected 값을 현재 taxonomy에 맞춰 자동 수정하지 않았다.

## 5. Invalid mapping 171 → 64 mapping rows

### 5.1 Distribution and verdict

| Source | Unique rows | Products |
|---|---:|---:|
| Musinsa | 6 | 50 |
| UNIQLO | 58 | 121 |
| **Total** | **64** | **171** |

| Mapping-row verdict | Rows | Products | Confirmed safe gain |
|---|---:|---:|---:|
| REPLACEMENT_MAPPING_VERIFIED | 0 | 0 | 0 |
| SHOULD_BE_PRODUCT_REQUIRED | 10 | 25 | 0 |
| SHOULD_BE_REVOKED_NO_REPLACEMENT | 30 | 75 | 0 |
| TAXONOMY_VOCABULARY_REPAIR | 24 | 71 | 0 |
| NEEDS_MANUAL_MAPPING_ADJUDICATION | 0 | 0 | 0 |
| **Total** | **64** | **171** | **0** |

`SHOULD_BE_PRODUCT_REQUIRED`는 Phase1A.5 `mixed_mapping_bucket=C_PRODUCT_REQUIRED`가 있는 경우만 부여했다. `SHOULD_BE_REVOKED_NO_REPLACEMENT`는 semantic relation이 invalid이고 verified successor tuple이 없는 row다. Semantic relation은 valid하지만 canonical semantic fields와 legacy `appMapping` category/detail vocabulary가 불일치한 24 rows는 `TAXONOMY_VOCABULARY_REPAIR`로 분리했다. 이 24 rows도 replacement 값은 owner 확인 전 null이다.

Production parent의 64 rows는 모두 `decision_status=confirmed`, `runtime_lookup_eligible=true`, `eligibility=true`이며 mapping status는 direct 46 / transform-required 18이다. Candidate authority metadata가 revoked라 v4는 이미 fail-close하지만, revoke-only 30의 concrete proposal은 future candidate에서 physical status도 `review_required/revoked/ineligible`로 일치시키는 것이다. 이번에 실제 row는 바꾸지 않았다.

Invalid row와 exact-but-incomplete가 겹치는 product는 2건이지만 둘 다 complete verified v4 replacement가 아니다. 따라서 verified replacement row는 0이고 Top1/Top5/Top10/all verified-safe invalid correction coverage는 모두 0이다.

### 5.2 Top 20 invalid rows by affected products

| # | Source | External category / target | Normalized path | Products | Conflict overlap | Verdict |
|---:|---|---|---|---:|---:|---|
| 1 | Musinsa | 002020 / UNKNOWN | 아우터 > 카디건 | 27 | 0 | TAXONOMY_VOCABULARY_REPAIR |
| 2 | Musinsa | 002022 / UNKNOWN | 아우터 > 후드 집업 | 13 | 0 | SHOULD_BE_REVOKED_NO_REPLACEMENT |
| 3 | UNIQLO | 58608 / KIDS | 청바지 & 팬츠 > 반바지 > 스커트 팬츠 | 8 | 8 | SHOULD_BE_REVOKED_NO_REPLACEMENT |
| 4 | UNIQLO | 58674 / BABY | 신생아(0개월~2세) > 바디수트 > 긴팔 | 6 | 0 | SHOULD_BE_REVOKED_NO_REPLACEMENT |
| 5 | Musinsa | 002018 / UNKNOWN | 아우터 > 트레이닝 재킷 | 5 | 0 | SHOULD_BE_REVOKED_NO_REPLACEMENT |
| 6 | UNIQLO | 128388 / WOMEN | 니트 & 가디건 > 가디건 > 그 외 | 5 | 5 | SHOULD_BE_PRODUCT_REQUIRED |
| 7 | UNIQLO | 141498 / WOMEN | 이너웨어 > 코튼 이너탑 > 캐미솔 | 5 | 5 | TAXONOMY_VOCABULARY_REPAIR |
| 8 | UNIQLO | 141499 / WOMEN | 이너웨어 > 코튼 이너탑 > 탱크탑 | 5 | 5 | TAXONOMY_VOCABULARY_REPAIR |
| 9 | UNIQLO | 114926 / MEN | 팬츠 > 캐주얼 팬츠 > 울트라 스트레치 | 4 | 4 | SHOULD_BE_REVOKED_NO_REPLACEMENT |
| 10 | UNIQLO | 58407 / MEN | 스웨트셔츠 & 후드집업 > (X)그래픽 스웨트 | 4 | 4 | TAXONOMY_VOCABULARY_REPAIR |
| 11 | UNIQLO | 58673 / BABY | 신생아(0개월~2세) > 바디수트 > 코튼메쉬 | 4 | 0 | SHOULD_BE_REVOKED_NO_REPLACEMENT |
| 12 | UNIQLO | 58716 / BABY | 레깅스 & 팬츠 > 쇼트팬츠 | 4 | 3 | SHOULD_BE_PRODUCT_REQUIRED |
| 13 | UNIQLO | 95405 / MEN | 니트 & 가디건 > 니트 > 크루넥 니트 | 4 | 3 | TAXONOMY_VOCABULARY_REPAIR |
| 14 | UNIQLO | 115519 / WOMEN | UV Protection > 팬츠 & 레깅스 > 팬츠 | 3 | 3 | SHOULD_BE_REVOKED_NO_REPLACEMENT |
| 15 | UNIQLO | 135282 / WOMEN | 가디건 > 스무드 코튼 | 3 | 3 | SHOULD_BE_PRODUCT_REQUIRED |
| 16 | UNIQLO | 136609 / WOMEN | 가디건 > 브이넥 | 3 | 3 | TAXONOMY_VOCABULARY_REPAIR |
| 17 | UNIQLO | 58125 / WOMEN | 아우터 > 재킷 & 코트 > 캐주얼 재킷 | 3 | 0 | SHOULD_BE_PRODUCT_REQUIRED |
| 18 | UNIQLO | 58401 / MEN | 스웨트셔츠 & 후드집업 > 스웨트셔츠 | 3 | 3 | TAXONOMY_VOCABULARY_REPAIR |
| 19 | UNIQLO | 58512 / MEN | 이너웨어 > 에어리즘 > 브리프 (로라이즈) | 3 | 3 | SHOULD_BE_REVOKED_NO_REPLACEMENT |
| 20 | UNIQLO | 58611 / KIDS | 원피스 & 스커트 > 원피스 > 슬리브리스 | 3 | 0 | SHOULD_BE_PRODUCT_REQUIRED |

## 6. Minimal remediation proposal manifest

이 manifest는 SQL이 아니며 실제 write가 없다. Concrete candidate-data logical row unit만 담았고, conflict cohort의 zero-truth manual queue는 cohort JSONL에 유지해 중복 DB change proposal로 만들지 않았다.

| Priority | Proposed rows | Breakdown | Verified-safe gain |
|---|---:|---|---:|
| P0 | 17 | verified CATEGORY_DIRECT observed-target clones | 84 |
| P1 | 0 | verified cohort-wide mapping/decision correction 없음 | 0 |
| P2 | 33 | exact tuple 2 safe + vocabulary-confirm 7 + invalid vocabulary 24 | 2 |
| P3 | 40 | invalid row product-required 10 + revoke-preserve 30 | 0 |
| P4 | 12 | exact product semantic adjudication | 0 |
| **Total** | **102** |  | **86** |

P3는 confirmed gain이 아니라 fail-closed disposition이다. `SHOULD_BE_REVOKED_NO_REPLACEMENT` 30은 candidate authority metadata의 revoked 상태에 더해 physical `decision_status`, `mapping_status`, lookup/eligibility flags를 inactivate하는 proposal이며 review reduction은 0이다.

### 6.1 Top 20 by independently verified safe-unblock leverage

| # | Change unit | Priority | Affected | Safe gain |
|---:|---|---|---:|---:|
| 1 | 001001 target WOMEN clone | P0 | 24 | 24 |
| 2 | 001001 target MEN clone | P0 | 16 | 16 |
| 3 | 001001 target M clone | P0 | 11 | 11 |
| 4 | 001011 target W clone | P0 | 7 | 7 |
| 5 | 001001 target W clone | P0 | 6 | 6 |
| 6 | 001010 target W clone | P0 | 4 | 4 |
| 7 | 001010 target MEN clone | P0 | 3 | 3 |
| 8 | 001010 target WOMEN clone | P0 | 2 | 2 |
| 9 | 017016005 target M clone | P0 | 2 | 2 |
| 10 | 001001 target M,W clone | P0 | 2 | 2 |
| 11 | 017016003 target M clone | P0 | 1 | 1 |
| 12 | 017016002 target M,W clone | P0 | 1 | 1 |
| 13 | 017016003 target M,W clone | P0 | 1 | 1 |
| 14 | 001010 target M clone | P0 | 1 | 1 |
| 15 | 001011 target MEN clone | P0 | 1 | 1 |
| 16 | 017016005 target W clone | P0 | 1 | 1 |
| 17 | 001011 target WOMEN clone | P0 | 1 | 1 |
| 18 | `uniqlo:E482522` complete v4 decision | P2 | 1 | 1 |
| 19 | `uniqlo:E485454` complete v4 decision | P2 | 1 | 1 |
| 20 | invalid 002020 vocabulary adjudication | P2 | 27 | 0 |

Positive-gain proposal은 19 rows뿐이다. 이후 모든 proposal의 independently verified confirmed gain은 0이다.

### 6.2 Cumulative potential

| Scope | Safe gain | Projected confirmed | Projected review_required |
|---|---:|---:|---:|
| Baseline | 0 | 177 | 1,431 |
| P0 | 84 | 261 | 1,347 |
| P0+P1 | 84 | 261 | 1,347 |
| P0+P1+P2 verified-safe subset | 86 | 263 | 1,345 |
| All independently verified-safe | **86** | **263** | **1,345** |

Safe changes ranked by row leverage는 Top1 24, Top5 cumulative 64, Top10 cumulative 77, all 19 positive rows cumulative 86이다.

Source별 safe gain은 Musinsa 84, UNIQLO 2, ZARA 0이다.

## 7. DB data only, backend contract, and owner truth

### 7.1 Backend contract change 없이 가능한 범위

Candidate v4 contract를 기준으로 새 algorithm/backend contract 없이 해결 가능한 verified-safe 범위는 **86**이다.

- 84: `source_category_mappings` candidate rows only.
- 2: `product_classification_decisions` complete v4 tuple only.
- 추가 7: owner가 legacy→active vocabulary 의미 동일성을 확인한 뒤에는 DB decision data만으로 가능할 수 있으나, 현재 safe gain에는 포함하지 않았다.
- 12: semantic truth가 없고 그중 underwear 10은 taxonomy decision까지 필요하므로 현재 DB-only safe가 아니다.

현재 Production에는 resolver v4와 decision `authority_status`/`garment_type_code` columns가 아직 없다. 따라서 “backend contract change 0”은 이미 설계된 candidate v4 contract에 새 concept를 추가할 필요가 없다는 뜻이며, 지금 Production row에 즉시 쓸 수 있다는 뜻이 아니다. Migration/apply/activation은 별도 승인 전 금지다.

### 7.2 Owner/manual truth가 필요한 범위

Conflict 안에서는 safe 1을 제외한 **717**이 review로 남는다.

- independently verified winner지만 tuple/vocabulary owner 확인 필요: 11
- verified product-required이며 product-level truth 필요: 165
- both untrusted: 394
- explicit product adjudication: 147

Invalid mapping은 mapping-level fail-closed disposition이 정해진 40 rows도 affected products를 confirmed로 만들지는 않는다. Replacement value가 owner 확인을 필요로 하는 vocabulary rows는 24/71 products다.

## 8. Structured API evidence and name evidence excluded

다음 값은 관측만 보존하고 safe gain에 포함하지 않았다.

| Excluded signal | Products |
|---|---:|
| structured typed signal | 212 |
| Musinsa `size_type` | 165 |
| UNIQLO `product_type_kr` | 47 |
| name-add signal | 246 |
| clean name-only | 47 |

Owner가 structured-first 정책 C를 선택했으므로 212를 다음에 볼 가치는 있다. 그러나 이번 audit에서 field authority, Resolver consumption, mapping, name profile을 추가하지 않았고 Phase 1B-3도 시작하지 않았다.

## 9. Owner decisions required

다음 decision만 요청한다. 어느 것도 이번 산출물에서 자동 적용되지 않았다.

1. **P0 17 target clones / 84 products**를 다음 candidate-data baseline에 포함할지 승인.
2. **UNIQLO E482522, E485454**의 complete v4 product-decision proposal 2건을 승인.
3. Legacy vocabulary translation 7건을 owner가 semantic-equivalent로 확인할지, product adjudication으로 내릴지 결정.
4. Invalid rows 중 A5-verified mixed 10 rows를 `PRODUCT_REQUIRED`로 전환하고 30 rows는 revoke/no-replacement로 유지할지 승인.
5. Invalid vocabulary 24 rows의 coherent replacement tuple을 mapping-row 단위로 adjudicate.
6. Conflict 잔여 717의 product truth queue 우선순위를 정함. Cohort size를 safe truth로 보지 말 것.
7. 이후 별도 read-only 단계에서 structured typed evidence 212를 검증할지 결정.

## 10. Production unchanged evidence

Production full product parity와 postflight를 SELECT/introspection only로 실행했다. Final postflight 관측 시각은 `2026-08-26T04:30:33.040547Z` (`2026-08-26 13:30:33 KST`)다.

| Check | Result |
|---|---|
| Phase 1B-2 product key/fingerprint parity | expected 1,608, matched 1,608, missing 0, mismatch 0 |
| Product source counts | Musinsa 394 / UNIQLO 1,184 / ZARA 30 |
| Products / decisions | 1,608 / 5,056 |
| History / current | 1,860 / 1,608 |
| Active release | `65d72393-4a40-4e99-b701-fdc1ff865774`, exactly 1 |
| Active mappings | 3,492 |
| Candidate release in Production | 0 |
| Candidate classification authority issues | 0; all quality issues 0 |
| Resolver v4 in Production | absent |
| Decision `authority_status` / `garment_type_code` columns | absent / absent |
| Latest migration | `20260821090138 seed_zara_verified_measurement_subset` |
| Production SQL mutation / DDL | 0 / 0 |
| Migration/release/decision/mapping/profile/history write | 0 |
| Live retailer API/network | 0 |

## 11. Safety validation and stop condition

| Artifact | Rows | SHA-256 |
|---|---:|---|
| `FitMatchClassificationConflictCohorts-20260826.jsonl` | 279 | `1c7e332d7b3ec44f1157c1f919c4f7626ef096b582caa2c68b1ed596402e465b` |
| `FitMatchClassificationDBOnly105-20260826.jsonl` | 105 | `c786470b1123efa9d7651c5a8a913aed073509135f6a679dc63a69e4bbc3229c` |
| `FitMatchClassificationInvalidMappingRows-20260826.jsonl` | 64 | `660471260f5d544c5a307f95c85113a0fd637b36541e0d4b36eb07224c90cc25` |
| `FitMatchClassificationRemediationPlan-20260826.jsonl` | 102 | `e6b26efe743520b3627bf97492dd93c68958eafddd3c66399b1fd823c71c132c` |

- Conflict input: 718 exact.
- DB-only input/output: 105 exact, unique product 105.
- Invalid-mapping product distribution: 171 exact.
- Invalid mapping rows: 64, affected sum 171.
- Conflict cohorts: 279, product-count sum 718, one verdict per cohort.
- Overlap partition sum: 895 unique union, hidden overlap 0.
- Safe gain: independently verified evidence only, 86 unique products.
- Production write/DDL, migration create/apply, release change: 0.
- Decision/mapping/profile/history write: 0.
- Swift/Resolver/Evaluator production modification: 0.
- Name profile/algorithm/structured authority change: 0.
- Phase 1B-3 / Production activation: 0.

본 audit는 여기서 중지한다. 위 proposal은 owner 승인과 별도 candidate-data 작업 전에는 실행하지 않는다.
