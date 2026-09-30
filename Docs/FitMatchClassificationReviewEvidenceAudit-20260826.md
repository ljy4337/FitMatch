# FitMatch Classification Authority — Review-Required Evidence Audit

- Audit date: `2026-08-26`
- Repository / branch: `ljy4337/FitMatch` / `connectDB`
- Production project: `hnkplvyegonlhumlejst`
- Scope: Phase 1B-2 `review_required` 1,431 products, one output row per product
- Mode: read-only evidence audit; Production write/apply/activation 0, algorithm/Swift change 0
- Input shadow SHA-256: `b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385` — expected value와 일치
- Output JSONL SHA-256: `cbcfa931a01c152f6b8205cf26a3d2696af73ad5b3ec0f9585f52831eec81ddb`

## 1. Executive conclusion

1,431건이 남은 가장 큰 이유는 이름을 읽지 않아서가 아니다. `AUTHORITY_CONFLICT`가 718건(50.2%), incomplete legacy decision이 112건, invalid mapping이 86건이며, mapping/path/product authority가 없거나 불완전한 나머지 cohort가 뒤를 잇는다.

엄격한 NO_NAME 기준에서 지금 바로 canonical v4 tuple을 확정할 수 있는 상품은 **0건**이다. review row 중 related `CATEGORY_DIRECT` mapping은 84건이지만 Resolver 입력에서 실제 선택·검증된 mapping은 0건이므로 safe coverage로 올리지 않았다. Phase 1A.5 독립 검증 중 expected status가 confirmed인 21건도 garment type을 포함한 complete v4 tuple이 아니어서 `ALREADY_EXACT_AUTHORITY_BUT_BLOCKED_FOR_OTHER_REASON`으로 분리했다.

저장된 typed evidence는 존재한다. Musinsa `size_type` 유효값 165건, UNIQLO `product_type_kr` 유효값 47건, ZARA family/subfamily/official category 30건이다. 다만 ZARA 30건은 모두 path/codes에 동일 taxonomy가 이미 반영되어 추가 discriminator가 아니며, Musinsa/UNIQLO의 212건만 현재 v4가 소비하지 않는 additive typed signal이다. 이 212건도 verified canonical mapping이 없으므로 confirmed로 계산하지 않았다.

상품명은 246건에서 structured evidence signature에 없던 token을 추가했다. 그러나 verified-complete name profile은 0이므로 S4 confirmed 0, S5 confirmed credit 0이다. 즉 현재 authority contract 아래에서는 이름을 보더라도 1,431건 모두 여전히 unconfirmed다. 이 중 clean `NAME_ADDS_INFORMATION_ONLY` verdict는 47건이고, candidate manual-review flag는 1,009건이다.

숫자는 다음 세 정책을 명확히 구분한다.

| 정책 | 즉시 safe confirmed | 관측 가능한 후보 coverage | 현재 blocker |
|---|---:|---:|---|
| A. 상품명 완전 금지 | 0 | structured-unverified primary 143 | verified/applicable structured authority 부족 |
| B. verified 보조 name evidence | 0 | clean name-only 47, gross name-adds 246 | verified-complete name profile 0 |
| C. structured API evidence 확대 후 name 최후 보조 | 0 | additive raw typed signal 212 | source-specific mapping 검증과 backend contract 필요 |

본 감사만으로 어느 정책도 활성화하지 않는다. owner 결정을 기다린다.

## 2. 1,431 root-cause distribution

Primary bucket precedence는 `AUTHORITY_CONFLICT → INVALID_MAPPING → revoked decision → LEGACY_DECISION_INCOMPLETE → unused typed field → name-only signal → PRODUCT_REQUIRED → NO_MAPPING → path insufficiency → manual/other`다. 따라서 한 상품은 정확히 한 primary bucket만 가진다.

| Primary root cause | Total | Musinsa | UNIQLO | ZARA | 비율 |
|---|---:|---:|---:|---:|---:|
| `NO_MAPPING` | 53 | 52 | 1 | 0 | 3.7% |
| `PRODUCT_REQUIRED_NO_PRODUCT_AUTHORITY` | 99 | 18 | 81 | 0 | 6.9% |
| `INVALID_MAPPING` | 86 | 50 | 36 | 0 | 6.0% |
| `LEGACY_DECISION_INCOMPLETE` | 112 | 92 | 16 | 4 | 7.8% |
| `AUTHORITY_CONFLICT` | 718 | 0 | 693 | 25 | 50.2% |
| `STRUCTURED_EVIDENCE_AVAILABLE_NOT_CONSUMED` | 160 | 114 | 46 | 0 | 11.2% |
| `PATH_EVIDENCE_UNVERIFIED_OR_INCOMPLETE` | 153 | 33 | 120 | 0 | 10.7% |
| `NAME_ONLY_DISCRIMINATOR_CANDIDATE` | 49 | 32 | 17 | 0 | 3.4% |
| `TRUE_MANUAL_ADJUDICATION_REQUIRED` | 0 | 0 | 0 | 0 | 0.0% |
| `OTHER` | 1 | 0 | 0 | 1 | 0.1% |
| **합계** | **1,431** | **391** | **1,010** | **30** | **100.0%** |

`TRUE_MANUAL_ADJUDICATION_REQUIRED` primary가 0인 것은 manual product가 없다는 뜻이 아니다. 1,009 manual flags가 모두 conflict, invalid mapping, incomplete decision 등 더 구체적인 primary cause에 먼저 배치됐기 때문이다. `OTHER` 1건은 ZARA exact decision `revoked`다.

Mapping bucket product distribution도 입력과 일치한다.

| Mapping bucket | Total | Musinsa | UNIQLO | ZARA |
|---|---:|---:|---:|---:|
| `CATEGORY_DIRECT` | 84 | 84 | 0 | 0 |
| `PRODUCT_REQUIRED` | 708 | 135 | 547 | 26 |
| `INVALID_MAPPING` | 171 | 50 | 121 | 0 |
| `OTHER_EXISTING` | 380 | 45 | 335 | 0 |
| `NO_MATCH` | 88 | 77 | 7 | 4 |
| **합계** | **1,431** | **391** | **1,010** | **30** |

Top 20 blocker는 stale release pointer 자체를 제외하고 product별 reason 존재 여부를 한 번씩 센 값이다.

| Rank | Blocker | Products |
|---:|---|---:|
| 1 | `comparison_family_inactive_or_missing` | 1,217 |
| 2 | `garment_type_not_stored_or_unambiguously_inferable` | 1,210 |
| 3 | `garment_type_code_missing` | 1,012 |
| 4 | `category_only_missing_product_axis_or_detail` | 855 |
| 5 | `exact_product_decision_tuple_invalid` | 845 |
| 6 | `authority_conflict_unresolved` | 718 |
| 7 | `product_decision_source_mapping_conflict` | 718 |
| 8 | `detail_not_active_under_category` | 627 |
| 9 | `product_decision_conflict` | 607 |
| 10 | `active_mapping_vs_current_history:comparison_family` | 599 |
| 11 | `C_PRODUCT_REQUIRED` | 573 |
| 12 | `source_mapping_product_required` | 573 |
| 13 | `active_mapping_vs_current_history:detail` | 549 |
| 14 | `family_code_not_found_or_inactive` | 545 |
| 15 | `detail_code_missing` | 534 |
| 16 | `confirmed_tuple_null` | 497 |
| 17 | `category_inactive_or_missing` | 496 |
| 18 | `family_code_missing` | 495 |
| 19 | `category_code_missing` | 494 |
| 20 | `required_sleeve_axis_missing` | 490 |

## 3. Source별 evidence availability

Production `products` schema와 실제 1,431 raw payload를 읽어 존재한 key만 집계했다. `stored`는 key/value 존재, `informative`는 빈 문자열·`unknown`을 제외한 값이다.

| Evidence | Total | Musinsa 391 | UNIQLO 1,010 | ZARA 30 | 해석 |
|---|---:|---:|---:|---:|---|
| `audience` | 1,431 | 391 | 1,010 | 30 | 전수 저장 |
| `source_category_path` | 1,431 | 391 | 1,010 | 30 | 전수 저장 |
| non-empty `source_category_codes` | 1,238 | 198 | 1,010 | 30 | Musinsa 193건은 path만 존재 |
| raw `size_type` stored / informative | 197 / 165 | 197 / 165 | 0 | 0 | Musinsa parser typed garment/table signal |
| raw `product_type` stored / informative | 1,010 / 0 | 0 | 1,010 / 0 | 0 | UNIQLO 값 전부 `unknown` |
| raw `product_type_kr` stored / informative | 986 / 47 | 0 | 986 / 47 | 0 | 939건은 빈 문자열; 유효값은 주로 accessory type |
| raw `gender_category` / `gender_name` | 986 | 0 | 986 | 0 | `audience`와 같은 차원, subtype 추가 정보 아님 |
| raw `family_id/name` | 30 | 0 | 0 | 30 | ZARA retailer taxonomy |
| raw `subfamily_id/name` | 30 | 0 | 0 | 30 | ZARA retailer taxonomy |
| raw `official_category_id` | 30 | 0 | 0 | 30 | ZARA official taxonomy |
| raw `mapping_status` | 30 | 0 | 0 | 30 | parser status; canonical authority 아님 |
| raw `section` | 0 | 0 | 0 | 0 | stored absent; API capability는 `NOT_VERIFIED` |
| meaningful typed evidence | 242 | 165 | 47 | 30 | ZARA 30은 path/codes와 중복 |
| additive raw-only discriminator | 212 | 165 | 47 | 0 | 현재 v4가 직접 소비하지 않음 |

Authority/profile inventory는 다음과 같다.

| Evidence | Total | Musinsa | UNIQLO | ZARA |
|---|---:|---:|---:|---:|
| current legacy decision present | 1,063 | 238 | 795 | 30 |
| legacy decision fingerprint match | 846 | 107 | 709 | 30 |
| legacy decision fingerprint mismatch | 217 | 131 | 86 | 0 |
| Phase 1A.5 independent product evidence | 27 | 8 | 19 | 0 |
| Phase 1A.5 expected confirmed, v4 tuple incomplete | 21 | 2 | 19 | 0 |
| current name-profile match | 554 | 173 | 381 | 0 |
| current path-profile match | 459 | 64 | 395 | 0 |
| current exclusion-profile match | 187 | 3 | 184 | 0 |
| verified-complete product decision | 0 | 0 | 0 | 0 |
| verified-complete name/path profile | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| authority conflict | 718 | 0 | 693 | 25 |
| current history stale | 1,297 | 290 | 989 | 18 |

Production 전체 profile inventory도 name 839, path 420, exclusion 273이며 각각 verified authority row는 0이다. Auto-eligible row는 name 335, path 161, exclusion 40이지만, auto-eligible을 independently verified authority로 대체 해석하지 않았다.

Raw payload에는 batch/checksum/price/brand/import metadata도 있었지만 typed classification evidence가 아니어서 coverage에 포함하지 않았다. Live retailer API를 호출하지 않았으므로 모든 미저장 필드는 `stored absent`; retailer API의 실제 제공 가능성은 별도 `API capability NOT_VERIFIED`다.

## 4. NO_NAME 결과

NO_NAME verdict는 다음 precedence로 정확히 하나만 부여했다: safe → Phase 1A.5 exact-but-incomplete → candidate manual issue → structured-unverified → name-only → structured-missing.

| NO_NAME verdict | Total | Musinsa | UNIQLO | ZARA |
|---|---:|---:|---:|---:|
| `SAFE_NO_NAME_RESOLVABLE` | 0 | 0 | 0 | 0 |
| `STRUCTURED_EVIDENCE_PRESENT_BUT_UNVERIFIED` | 143 | 97 | 45 | 1 |
| `STRUCTURED_EVIDENCE_MISSING` | 219 | 26 | 193 | 0 |
| `NAME_ADDS_INFORMATION_ONLY` | 47 | 2 | 45 | 0 |
| `MANUAL_ADJUDICATION_REQUIRED` | 1,001 | 264 | 708 | 29 |
| `ALREADY_EXACT_AUTHORITY_BUT_BLOCKED_FOR_OTHER_REASON` | 21 | 2 | 19 | 0 |
| **합계** | **1,431** | **391** | **1,010** | **30** |

핵심 질문의 계량값은 다음과 같다. 아래 gross diagnostic은 서로 겹칠 수 있으며, 위 verdict 표만 상호배타 partition이다.

| 핵심 숫자 | Total | Musinsa | UNIQLO | ZARA | 정의 |
|---|---:|---:|---:|---:|---|
| A. 상품명 금지 + 현재 verified authority로 즉시 confirmed | 0 | 0 | 0 | 0 | complete·unique authority만 인정 |
| B. structured evidence가 있어 보이나 authority가 없어 막힌 primary cohort | 143 | 97 | 45 | 1 | manual/exact-blocked precedence 이후 |
| C. stored discriminator shortage gross | 1,139 | 176 | 963 | 0 | meaningful typed field와 related verified direct가 모두 없음 |
| D. 상품명에만 추가 discriminator 관측 gross | 246 | 86 | 152 | 8 | structured signature 대비 name-only token 존재 |
| E. S4/S5까지도 현재 confirmed credit가 없어 남는 수 | 1,431 | 391 | 1,010 | 30 | S5는 통계 신호일 뿐 authority 아님 |
| candidate manual-adjudication flag | 1,009 | 265 | 715 | 29 | manifest의 product-level manual issue |

21 exact-but-blocked 중 8건은 candidate manual flag와도 겹친다. Verdict partition에서는 더 구체적인 exact-but-blocked가 우선하므로 manual verdict는 1,001이고, JSONL의 `manual_adjudication_required` boolean은 manifest를 보존해 1,009다.

## 5. structured evidence만으로 가능한 범위

| Scenario | Confirmed | Review | 추가 계량 |
|---|---:|---:|---|
| S0 `VERIFIED_PRODUCT_ONLY` | 0 | 1,431 | Phase 1A.5 expected confirmed 21은 complete v4 tuple 부족으로 blocked |
| S1 `STRUCTURED_CATEGORY_ONLY` | 0 | 1,431 | related verified direct 84, Resolver-applicable complete 0 |
| S2 `STRUCTURED_PRODUCT_FIELDS` | 0 | 1,431 | additive typed discriminator 212; ZARA duplicate taxonomy 30 |
| S3 `VERIFIED_PATH_PROFILE` | 0 | 1,431 | current match 459, verified-complete 0 |
| S4 `CURRENT_VERIFIED_NAME_PROFILE` | 0 | 1,431 | current match 554, verified-complete 0 |
| S5 `HYPOTHETICAL_NAME_SIGNAL` | 0 credit | 1,431 | name adds 246, no observed addition 1,185 |

S1의 related `CATEGORY_DIRECT` 84건은 모두 Musinsa다. 이 mapping은 candidate manifest에서 verified/category-direct이나 해당 product Resolver run에서는 `mapping_tuple_validation`이 생성되지 않았고 선택된 authority가 아니었다. 빈 `source_category_codes`, target/path lookup coverage 등의 DB data gap을 해소하기 전에는 safe로 세지 않았다.

S2의 `UNIQUE_STRUCTURED_DISCRIMINATOR_PRESENT`는 Musinsa 165 + UNIQLO 47 = 212다. `STRUCTURED_BUT_UNADJUDICATED_DUPLICATES_CATEGORY`는 ZARA 30이다. 어느 것도 canonical tuple으로 임의 변환하지 않았다.

## 6. current backend가 사용하지 않는 structured fields

여기서 `Resolver v4 consumes`는 repository의 candidate v4 contract를 뜻한다. Production에는 v4 function과 decision `authority_status`/`garment_type_code` column이 아직 없다.

| Field/evidence | STORED? | VERIFIED? | Resolver v4 consumes? | 새 concept 없이 사용 가능? | Backend contract change? | DB data only? | Source-specific? |
|---|---|---|---|---|---|---|---|
| `source` + `external_product_id` | 1,431 | snapshot key parity yes | yes | yes | no | no | no |
| verified exact decision | legacy 1,063; complete verified 0 | no | yes | yes | no | yes, after adjudication | no |
| `source_category_codes` | 1,238 | mapping별 상이 | yes | yes | no | yes | partly |
| `source_category_path` | 1,431 | path authority 0 | yes | yes | no | yes | no |
| `audience` | 1,431 | identity only | yes, target lookup | yes | no | yes | no |
| raw `size_type` | 197 / useful 165 | no | no | yes: existing garment/sleeve concepts | **yes** | no, field를 직접 쓰려면 | Musinsa |
| raw `product_type` | 1,010 / useful 0 | no | no | 현재 값으로는 no | upstream data 필요 | no | UNIQLO |
| raw `product_type_kr` | 986 / useful 47 | no | no | yes: retailer type/exclusion 후보 | **yes** | path exclusion으로 재표현할 때만 | UNIQLO |
| raw `gender_category/name` | 986 | no | no | audience와 중복 | 불필요 | audience mapping data로 가능 | UNIQLO |
| raw ZARA family/subfamily/official ID | 30 | parser lock은 authority 아님 | raw 직접은 no | yes | 직접 사용 시 yes | **현재 path/codes mapping으로 가능** | ZARA |
| raw `mapping_status` | 30 | canonical authority 아님 | no | 검증 정책 필요 | yes | no | ZARA |
| `classification_path_profiles` | matching 459 | verified-complete 0 | yes | yes | no | yes | no |
| `classification_name_profiles` | matching 554 | verified-complete 0 | yes | yes | no | yes | no |
| exclusion profiles | matching 187 | verified 0 | yes | yes | no | yes | no |
| `section` | 0 | no | no | capability unknown | unknown | no | API capability `NOT_VERIFIED` |

## 7. 상품명이 실제로 추가 정보를 주는 범위

S5는 Production의 deterministic name-signature 함수와 동일한 tokenizer를 사용했다. 상품명 signature에서 path, codes, audience, 실제 typed raw fields를 합친 structured signature를 빼고 남은 token만 `name_adds_information=true`로 셌다. Canonical label 추론은 0건이다.

- name signature non-empty: 944
- structured evidence에 없는 name-only token 보유: 246
- source: Musinsa 86 / UNIQLO 152 / ZARA 8
- clean `NAME_ADDS_INFORMATION_ONLY` verdict: 47 — Musinsa 2 / UNIQLO 45 / ZARA 0
- S5 confirmed credit: 0

Dimension은 한 상품에 여러 개일 수 있어 합계가 246을 넘는다.

| Name-only dimension | Products |
|---|---:|
| sleeve/arm coverage | 60 |
| lower garment subtype | 53 |
| outerwear subtype | 52 |
| upper garment subtype | 43 |
| material or garment detail | 26 |
| underwear subtype | 14 |
| product structure/set | 11 |
| usage family/loungewear | 5 |

상위 token은 `shorts` 48, `jacket` 27, `denim` 26, `short_sleeve` 26, `long_sleeve` 24, `knit` 17, `windbreaker` 17, `hoodie` 13, `set` 11, `sleeveless` 10이다. 이는 future verified-profile/human-review 후보의 관측치일 뿐 정답 label이 아니다.

## 8. 상품명까지 써도 해결되지 않는 범위

현재 verified-complete name profile이 0이므로 S4가 새로 확정하는 상품은 0이다. S5는 authority가 아니므로 246 name-add signal에도 confirmed credit를 주지 않았다. 결과적으로 현재 근거만으로 1,431건 전부 unconfirmed다.

그중 product-level manual queue로 유지해야 하는 manifest flag는 1,009건이다. 더 구체적으로 authority conflict 718, invalid mapping product distribution 171, exact legacy tuple invalid 845가 크게 겹친다. 이름이 추가 정보를 주는 246건 중에도 conflict/manual evidence가 섞여 있으므로 name token만으로 승자를 고를 수 없다.

## 9. source별 권장 개선 방향

### Musinsa

`source_category_codes` coverage가 198/391에 불과하지만 path는 391/391이다. 우선 84 related verified category-direct row의 code/target/path applicability를 DB data로 완성할 수 있는지 검증해야 한다. 그 다음 `size_type` 유효 165건을 existing garment/sleeve taxonomy에 연결할 source-specific authority table을 adjudicate할 가치가 있다. Name-add 86건은 이 structured work 뒤의 보조 후보로 유지한다.

### UNIQLO

Codes/path는 1,010/1,010이지만 authority conflict가 693건이다. 가장 큰 blocker는 API field 부족보다 legacy decision과 source mapping의 충돌이다. `product_type`은 1,010건 모두 `unknown`이라 coverage 개선에 쓸 수 없고, `product_type_kr` 유효 47건만 accessory/exclusion 후보가 된다. 먼저 693 conflicts와 121 invalid-mapping products를 adjudicate하고, clean name-only 45건은 verified profile 정책 여부를 owner가 결정해야 한다.

### ZARA

Family/subfamily/official ID가 30/30에 있지만 모두 path/codes에도 들어 있어 새 backend field 없이 mapping data로 표현 가능하다. 현재 blocker는 25 authority conflicts, 26 `PRODUCT_REQUIRED`, revoked exact decision 1이다. Raw taxonomy contract 추가보다 decision/mapping authority 정리가 먼저다.

## 10. DB data 변경만으로 해결 가능한 수

보수적으로 **105건**을 `db_data_only_change_possible=true`로 표시했다.

- related verified `CATEGORY_DIRECT`가 있으나 product Resolver에서 적용되지 않은 84건 — 전부 Musinsa
- Phase 1A.5 independently verified expected-confirmed evidence가 있으나 complete v4 tuple이 아닌 21건 — Musinsa 2 / UNIQLO 19

Source union은 Musinsa 86 / UNIQLO 19 / ZARA 0이다. 이 숫자는 “지금 confirmed 가능”이 아니라 현재 v4 data model 안에서 mapping target/code 또는 complete decision tuple을 보강할 수 있는 보수적 후보 수다. 본 감사에서는 어떤 row도 수정하지 않았다.

## 11. backend contract 수정이 필요한 수

현재 raw-only typed signal을 직접 authority path로 소비하려면 **212건**이 backend contract change 대상이다.

- Musinsa `size_type` informative: 165
- UNIQLO `product_type_kr` informative: 47
- ZARA: 0 — 동일 taxonomy가 이미 path/codes에 있음

이는 “contract를 바꾸면 212건 confirmed”라는 뜻이 아니다. Field-to-canonical mapping의 독립 검증, conflict policy, tuple completeness가 먼저 필요하다. Exact product decision으로 개별 adjudication하는 대안도 있으므로 212는 필수 수정량이 아니라 typed-field route를 선택할 때의 coverage다.

## 12. manual adjudication이 필요한 수

Candidate manifest의 product-level manual issue는 **1,009건**이다.

| Source | Manual flag |
|---|---:|
| Musinsa | 265 |
| UNIQLO | 715 |
| ZARA | 29 |
| **Total** | **1,009** |

NO_NAME verdict partition에서는 Phase 1A.5 exact-but-incomplete 21을 먼저 분리해 `MANUAL_ADJUDICATION_REQUIRED`가 1,001이다. 그 21 중 8은 manual flag도 보존되어 있다. 따라서 operational queue는 1,009, 상호배타 verdict bucket은 1,001로 읽어야 한다.

## 13. owner에게 필요한 의사결정

1. Musinsa verified direct mapping의 UNKNOWN/target/path applicability를 DB data 보완 대상으로 승인할지.
2. Musinsa `size_type` 165건과 UNIQLO `product_type_kr` 47건을 source-specific structured authority로 승격하는 contract를 설계할지.
3. UNIQLO 693 + ZARA 25 authority conflicts에서 decision/mapping 중 무엇을 source cohort별로 신뢰할지.
4. Invalid-mapping product 171의 replacement tuple adjudication을 별도 작업으로 승인할지.
5. Clean name-only 47건과 gross signal 246건에 대해 verified-complete name profile 보조 정책을 허용할지.
6. Phase 1A.5 exact evidence 21건의 missing garment/active family/length tuple을 DB-only completion 대상으로 인정할지.

정책 선택 비교:

| 선택 | Immediate confirmed | Source별 candidate signal | 필요한 결정 |
|---|---:|---|---|
| A. 상품명 완전 금지 | 0 | safe 0 / 0 / 0 | structured authority와 manual queue만 처리 |
| B. verified name 보조 | 0 | clean 2 / 45 / 0; gross 86 / 152 / 8 | name profile authority·complete tuple 검증 |
| C. structured API 확대, name 최후 | 0 | additive raw 165 / 47 / 0 | typed-field contract와 verified mappings |

## 14. Production unchanged evidence

Production full-parity SELECT는 `2026-08-26T01:22:24.475019Z`에, final count/pointer postflight는 `2026-08-26T01:37:23.496830Z` (`2026-08-26 10:37:23 KST`)에 SELECT/introspection only로 수행했다.

| Check | Result |
|---|---|
| Phase 1B-2 product key/fingerprint parity | expected 1,608, matched 1,608, missing 0, mismatch 0 |
| Products | 1,608 — Musinsa 394 / UNIQLO 1,184 / ZARA 30 |
| Decisions | 5,056 |
| History / current | 1,860 / 1,608 |
| Active release | `65d72393-4a40-4e99-b701-fdc1ff865774` |
| Active mappings | 3,492 |
| Candidate release in Production | 0 |
| Candidate classification review issues in Production | 0 |
| Latest migration | `20260821090138 seed_zara_verified_measurement_subset` |
| Resolver v4 function in Production | 0 |
| Decision `authority_status` / `garment_type_code` columns | 0 / 0 |
| Production SQL mutation | 0 |
| Migration apply / release activation / history write | 0 / 0 / 0 |

Input shadow checksum은 요구된 baseline과 exact match다. Source subset도 Musinsa 391 / UNIQLO 1,010 / ZARA 30으로 drift가 없다. Live retailer network/API 호출은 0이다.

## 15. 다음 단계 제안

본 감사는 여기서 중지한다. Phase 1B-3, Production activation, migration apply, Swift/Resolver/Evaluator 변경, profile/decision 생성, review→confirmed 승격을 시작하지 않는다.

Owner가 A/B/C 중 정책과 위 6개 adjudication 결정을 선택한 뒤 별도 승인된 작업에서만 다음 evidence package를 설계해야 한다. 특히 option C를 선택해도 212 typed-signal rows를 자동 확정하지 말고, source-specific field semantics와 canonical mapping의 independent verification부터 수행해야 한다.

검증 결과:

- input review rows: 1,431
- output JSONL rows: 1,431
- unique `source+external_product_id`: 1,431
- primary root cause: exactly 1/product, overlap 0
- NO_NAME verdict: exactly 1/product
- Production write/apply/change: 0
- migration change: 0
- Swift production diff: 0
- Phase 1B-3 start: 0
