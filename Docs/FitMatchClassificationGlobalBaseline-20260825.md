# FitMatch Classification Global Baseline — 2026-08-25

> Phase 1A read-only audit. 이 문서는 현재 production DB와 `connectDB` 코드의 상태를 계량한 기준선이며, migration/seed/RPC/Swift production 수정은 수행하지 않았다. 재판정 preview는 진단용 후보이지 expected 자동 갱신이나 production 승인 결과가 아니다.

## 핵심 결론

- production `products` 1608건과 current history 1608건을 100% 포함했다. 모든 product는 current row가 정확히 1건이다.
- current confirmed 1106건 중 strict canonical tuple이 유효한 것은 154건(13.9%), invalid confirmed는 952건(86.1%)이다.
- current history 1472건(91.5%)이 현재 fingerprint/active release/decision/tuple 기준 중 하나 이상에서 stale하다.
- active source mapping 3492건은 100% 집계했다. mapping row 자체의 exact duplicate/mixed-target identity는 0이지만, observed product-decision tuple이 섞인 category bucket은 59개(285 products), category-only confirmed 위험 mapping은 1358건, product decision과 실제 충돌하는 mapping row는 182건이다.
- product decisions 5056건에는 authority column이 없으며 모두 implicit legacy다. active release decision은 30건, 독립 evidence가 있는 decision은 237건, strict auto-eligible은 8건이다.
- 보수적 preview는 confirmed 192, review_required 1120, not_comparable 296건이다. 이는 legacy 수천 건을 즉시 차단하라는 결론이 아니라 Phase 1B에서 authority를 분리해야 한다는 계량 결과다.
- 세 owner Golden case는 current DB가 모두 `underwear/underwear/underwear/unknown/confirmed`로 잘못되어 있고, preview는 요청된 canonical tuple과 실제 product fingerprint를 사용한다.
- production release-gate migration 114의 핵심 object인 `data_quality_review_queue`가 없고 latest migration ledger는 `20260821090138`이다. active release의 expected/actual mapping count는 3492/3492로 일치하지만, QA count는 0이고 gate 통과를 증명할 production object는 없다.

## 1. 실행 기준 HEAD/project/release

| 항목 | 확인값 | 판정 |
| --- | --- | --- |
| Git branch | connectDB | 일치 |
| Git HEAD | c251b2a824b9a99e2f99b809f2cb23cb1721c9ab | 감사 기준 HEAD와 exact match |
| 기준 대비 rev-list | 0 ahead / 0 behind | 차이 없음 |
| Supabase project ref | hnkplvyegonlhumlejst | Info.plist·scripts·실제 연결 identity 일치 |
| PostgreSQL | 17.6 / database=postgres / user=postgres | production SELECT session |
| active taxonomy release | fitmatch-active-with-zara-official-tree-2026-08-13-v1__zara-sample30-2026-08-21 | 65d72393-4a40-4e99-b701-fdc1ff865774 |
| active release policy | taxonomy-corrected-2026-08-14+zara-test-2026-08-21-v1+zara-official-tree-2026-08-13-v1+zara-sample30-2026-08-21-v1 | validated_at=2026-08-21T08:09:45.81608+00:00 |
| active mapping count | 3492 | expected=3492 |
| active release QA | expected_qa_count=0 | qa_full_validation_included=false |
| latest production migration | 20260821090138 | local numeric 113/114 contract는 production에 없음 |
| latest repository numeric migration | 114_release_gate_and_quality_review_queue.sql | production queue/view/function 부재 |
| latest repository timestamp migration | 20260824100350_extend_zara_verified_upper_measurements.sql | production ledger보다 최신; 미적용 |
| DB write | 0 | 본 감사에서 SELECT/metadata 조회만 수행 |
| Swift production change | 0 | 문서 2개만 생성 |

Production schema preflight:

| Object/column | 존재 | 의미 |
| --- | --- | --- |
| fitmatch_catalog.data_quality_issues | true | 0 rows |
| fitmatch_catalog.data_quality_review_queue | false | release gate 114 미적용 |
| product_classification_decisions.garment_type_code | false | 부재 |
| product_classification_decisions.authority_status | false | 부재 |
| product_classification_history.garment_type_code | false | 부재 |

## 2. 현재 authority map

현재 실제 precedence와 소비 경로는 다음과 같다.

| 층 | 현재 authority/동작 | 감사 판정 |
| --- | --- | --- |
| Product decision | exact source+external ID와 fingerprint가 맞으면 최우선. authority_status/garment_type 없음 | legacy decision과 verified decision을 구별할 수 없음 |
| Name/path profiles | v2/v3에서 auto_eligible profile 사용 | profile 결과도 legacy family vocabulary를 포함 |
| Source mapping | runtime_resolve_source_mapping에서 active release를 사용하나 v2 positive confirmed precedence는 제한적이며 exclusion 중심 | release mapping과 product decision이 별도 authority로 충돌 가능 |
| Exclusion | v2/v3 exclusion profile, v3 snapshot/path exclusion 추가 | not_comparable authority는 존재하나 verified 상태 없음 |
| Current history | promote가 same fingerprint current row를 즉시 재사용 | decision_version/mapping release/garment 변화 stale 감지 없음 |
| Public resolve | public.fitmatch_resolve_product → promote/v2 | 기존 JSON contract; garment/authority 없음 |
| Public runtime | public.fitmatch_get_product_runtime | current history + 최소 1 comparable measurement로 runtime ready |
| Closet | manual override 유지; linked product면 DB classification snapshot 사용 | iOS sync가 familyCode를 garmentTypeRawValue로 저장 |
| Compare | DB current history로 candidates/begin comparison; iOS도 독립 local profile을 비교 | DB/local authority가 병렬로 존재 |
| iOS shopping | local classifier가 화면/eligibility authority, DB resolve는 shadow | 동일 입력도 local/DB divergence 가능 |

Runtime signature·security baseline:

| Function | Arguments | Security | search_path | EXECUTE anon/auth/service | definition md5 |
| --- | --- | --- | --- | --- | --- |
| fitmatch_catalog.resolve_product_classification | p_source text, p_external_product_id text, p_product_name text, p_source_category_path text | invoker | search_path=pg_catalog, fitmatch_catalog, fitmatch_taxonomy | false/false/true | 49f621270dd99222301fe4dea211ca3f |
| fitmatch_catalog.runtime_record_product_classification | p_product_id uuid, p_decision jsonb | invoker | search_path=pg_catalog, fitmatch_catalog | false/false/true | 92481272b088bb9aaea03054ba41d5de |
| fitmatch_catalog.runtime_resolve_and_promote_product | p_payload jsonb | invoker | search_path=pg_catalog, fitmatch_catalog | false/false/true | 22fed74ba5597768ee8aba0f689fc2ec |
| fitmatch_catalog.runtime_resolve_product_classification_v2 | p_source text, p_external_product_id text, p_product_name text, p_source_category_path text, p_payload jsonb | invoker | search_path=pg_catalog, fitmatch_catalog | false/false/true | 891e87ca889f6d23779ce6af0b2022ed |
| fitmatch_catalog.runtime_resolve_product_classification_v3 | p_source text, p_external_product_id text, p_product_name text, p_source_category_path text, p_payload jsonb | invoker | search_path=pg_catalog, fitmatch_catalog | false/false/true | bc941b6894d01b19f02bfb674fd4efe1 |
| fitmatch_catalog.runtime_resolve_source_mapping | p_payload jsonb | invoker | search_path=pg_catalog, fitmatch_catalog | false/false/true | ddac552550c270328f90517ccdd39996 |
| public.fitmatch_begin_comparison | p_reference_item_id uuid, p_target_product_id uuid, p_allow_extended boolean, p_client_history_id uuid | definer | search_path="" | false/true/true | 9c0ae9707baef6a07643725d897a71f2 |
| public.fitmatch_find_reference_candidates | p_target_product_id uuid | definer | search_path="" | false/true/true | 91a8b2e8e3008336eec644fdd84c6fd3 |
| public.fitmatch_get_product_runtime | p_payload jsonb | definer | search_path="" | false/true/true | 330bc6fe54924f352d6056f03beda89b |
| public.fitmatch_resolve_product | p_payload jsonb | definer | search_path="" | false/true/true | 0c8787e8251d825afb8c0feeb6214282 |
| public.fitmatch_upsert_closet_item | p_client_item_id uuid, p_item jsonb, p_product_id uuid, p_product_size_id uuid, p_override jsonb | definer | search_path="" | false/true/false | ab41e8932a5cd1db5ffaff58a7219f56 |
| public.fitmatch_list_closet_items | (no arguments) | definer | search_path="" | false/true/false | 667f0770b44db067c99adafc52678834 |

Authority data distributions:

| Object | Source | Policy/release | Metrics |
| --- | --- | --- | --- |
| closet_items | uniqlo | manual_override | total=6; active=1; confirmed=6; with_product=0; with_garment_type=6 |
| exclusion_profiles | musinsa | db-auto-classifier-2026-08-18-v2 | total=54; auto_eligible=3; ambiguous_rows=0; reviewed_samples=0 |
| exclusion_profiles | uniqlo | db-auto-classifier-2026-08-18-v2 | total=219; auto_eligible=37; ambiguous_rows=0; reviewed_samples=0 |
| name_profiles | musinsa | db-auto-classifier-2026-08-18-v2 | total=571; auto_eligible=207; ambiguous_rows=60; reviewed_samples=102 |
| name_profiles | uniqlo | db-auto-classifier-2026-08-18-v2 | total=268; auto_eligible=128; ambiguous_rows=8; reviewed_samples=8 |
| path_profiles | musinsa | db-auto-classifier-2026-08-18-v2 | total=129; auto_eligible=33; ambiguous_rows=79; reviewed_samples=154 |
| path_profiles | uniqlo | db-auto-classifier-2026-08-18-v2 | total=291; auto_eligible=128; ambiguous_rows=36; reviewed_samples=175 |
| snapshots | musinsa | retired | total=767; confirmed=0; not_comparable=0; linked_products=767; review_required=0 |
| snapshots | uniqlo | retired | total=3075; confirmed=0; not_comparable=0; linked_products=3075; review_required=0 |

RLS/SELECT baseline:

| Object | RLS | Policies | SELECT anon/auth/service |
| --- | --- | --- | --- |
| fitmatch_catalog.classification_exclusion_profiles | true | 0 | false/false/true |
| fitmatch_catalog.classification_name_profiles | true | 0 | false/false/true |
| fitmatch_catalog.classification_path_profiles | true | 0 | false/false/true |
| fitmatch_catalog.data_quality_issues | true | 0 | false/false/true |
| fitmatch_catalog.product_classification_decisions | true | 0 | false/false/true |
| fitmatch_catalog.product_classification_history | true | 0 | false/false/true |
| fitmatch_catalog.products | true | 0 | false/false/true |
| fitmatch_catalog.source_category_mappings | true | 0 | false/false/true |
| fitmatch_catalog.source_product_snapshots | true | 0 | false/false/true |
| public.app_categories | true | 1 | true/true/false |
| public.app_category_measurement_policies | true | 1 | true/true/false |
| public.closet_items | true | 4 | true/true/true |
| public.comparison_groups | true | 1 | true/true/false |
| public.comparison_policies | true | 1 | true/true/false |
| public.garment_types | true | 1 | true/true/false |
| public.measurement_items | true | 1 | true/true/true |
| public.source_measurement_mappings | true | 1 | false/false/false |

## 3. 전체 metrics

### A. Products/current classification

| source | products | current | confirmed | review_required | not_comparable | unclassified | invalid confirmed | stale current | mapping/decision conflict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| musinsa | 394 | 394 | 311 | 82 | 1 | 0 | 239 | 292 | 0 |
| uniqlo | 1184 | 1184 | 766 | 250 | 168 | 0 | 692 | 1162 | 572 |
| zara | 30 | 30 | 29 | 1 | 0 | 0 | 21 | 18 | 1 |
| TOTAL | 1608 | 1608 | 1106 | 333 | 169 | 0 | 952 | 1472 | 573 |

Current status:

| 값 | 건수 |
| --- | --- |
| confirmed | 1106 |
| review_required | 333 |
| not_comparable | 169 |

Current method:

| 값 | 건수 |
| --- | --- |
| canonical_product_decision | 1105 |
| category_mapping | 169 |
| product_classifier | 168 |
| unknown | 162 |
| manual_review | 4 |

Current decision version:

| 값 | 건수 |
| --- | --- |
| swift-production-2026-08-16-v3 | 1074 |
| db-auto-classifier-2026-08-18-v2 | 499 |
| zara-production-sample-2026-08-21-v1 | 30 |
| db-runtime-2026-08-18-v1 | 4 |
| db-runtime-family-correction-2026-08-18-v1 | 1 |

History rows는 total 1860, current 1608, superseded 252다. product별 current row count는 모두 정확히 1이며 missing current는 0건이다.

### B. Source mappings

| source | active total | confirmed | review_required | rejected | unsupported | invalid semantic | category-only risk | decision conflict rows |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| musinsa | 1922 | 368 | 369 | 1145 | 40 | 1671 | 358 | 0 |
| uniqlo | 1505 | 959 | 239 | 307 | 0 | 665 | 935 | 181 |
| zara | 65 | 65 | 0 | 0 | 0 | 0 | 65 | 1 |
| TOTAL | 3492 | 1392 | 608 | 1452 | 40 | 2336 | 1358 | 182 |

- exact source identity duplicate groups/rows: 0/0
- mapping row target만 비교한 same-source-category mixed target groups/rows: 0/0
- 같은 active mapping identity에 연결된 observed product decision tuple mixed bucket: 59 groups / 285 products
  - non-null family가 실제로 2개 이상: 14 groups / 56 products
  - 한 family와 missing decision이 혼재: 27 groups / 145 products
  - family는 같고 detail/length만 혼재: 18 groups / 84 products
- conflicting target identity groups: 0
- confirmed 1392건 중 raw `category_only_auto_complete=true`는 45건이다. 이 중 product conflict 11건을 제외한 non-risky mapping은 34건이고, 하나 이상의 category-only/conflict 위험이 있는 confirmed mapping은 1358건이다.

### C. Product decisions

| source | total | active release | retired release | fingerprint match | mismatch | product absent | valid tuple | independent evidence | history conflict | strict auto |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| musinsa | 4011 | 0 | 4011 | 108 | 132 | 3771 | 500 | 77 | 50 | 0 |
| uniqlo | 1015 | 0 | 1015 | 877 | 90 | 48 | 163 | 130 | 78 | 0 |
| zara | 30 | 30 | 0 | 30 | 0 | 0 | 8 | 30 | 0 | 8 |
| TOTAL | 5056 | 30 | 5026 | 1015 | 222 | 3819 | 671 | 237 | 128 | 8 |

| metric | count |
| --- | --- |
| implicit legacy authority | 5056 |
| independent evidence 없음 | 4819 |
| legacy exact backward-compat 후보 | 128 |
| 반드시 검토할 후보 | 5048 |
| strict auto-eligible 후보 | 8 |

Evidence trust:

| 값 | 건수 |
| --- | --- |
| adjudicated_fixture | 207 |
| correction_marker | 5 |
| official_structured_source | 30 |
| self_consistency_fixture_only | 4814 |

### D. Canonical/measurement/comparison readiness

| Canonical object | rows |
| --- | --- |
| public.app_categories | 99 |
| public.garment_types | 38 |
| public.comparison_groups | 30 |
| public.comparison_policies | 30 |
| public.app_category_measurement_policies | 25 |
| public.measurement_items | 25 |
| public.source_measurement_mappings | 21 |

| 값 | 건수 |
| --- | --- |
| 전체 products | 1608 |
| runtime_comparison_ready=true | 622 |
| strict_policy_ready=true | 504 |
| confirmed products | 1106 |
| confirmed + runtime ready | 622 |
| confirmed + strict policy ready | 504 |
| confirmed이나 strict policy 미충족 | 602 |
| runtime ready이나 strict policy 미충족 | 118 |

동일 current family/category/source 조합에서 서로 다른 actual measurement basis가 공존하는 집계 충돌은 0건이었다. 다만 이는 family 자체가 strict canonical인지와 별개다. `fitmatch_get_product_runtime`의 현재 ready 조건은 “comparable measurement 1개 이상”이라 policy minimum/required group을 적용한 strict ready보다 118건 넓다.

### E. 그 밖의 row

| Object | rows | 상태 |
| --- | --- | --- |
| fitmatch_catalog.source_product_snapshots | 3842 | 전부 retired release: musinsa 767, uniqlo 3,075 |
| fitmatch_catalog.product_observations | 2 | 2; 삭제/변경 없음 |
| fitmatch_catalog.data_quality_issues | 0 | 0 |
| fitmatch_catalog.data_quality_review_queue | object 없음 | production migration 114 미적용 |
| public.closet_items | 6 | active=1, soft-deleted=5 |
| comparison_runs | 0 | 0 |
| comparison_history | 0 | 0 |

### F. Production DB validation functions

| validator | passed | products/current | snapshots | 5,026 parity | profile cases/mismatch | security leaks |
| --- | --- | --- | --- | --- | --- | --- |
| fitmatch_qa.validate_product_runtime | true | 1,608/1,608 | 3,842 | 5,026/5,026 (100%) | — | 0 |
| fitmatch_qa.validate_product_runtime_v2 | true | 1,608/1,608 | 3,842 | 5,026/5,026 (100%) | 2,536/0 | 0 |
| fitmatch_qa.validate_product_runtime_v3 | true | 1,608/1,608 | 3,842 | 5,026/5,026 (100%) | 2,536/0 | 0 |

세 validator의 duplicate current는 0, invalid comparable measurement는 0이다. 이 PASS는 현재 DB decision과 동일 계보의 5,026 QA corpus를 비교한 self-consistency 결과이므로, 위의 strict semantic tuple 오류 952건을 반증하지 않는다.

## 4. source별 coverage

| source | products | active mappings | decisions | snapshots | current confirmed | invalid confirmed | stale | preview confirmed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| musinsa | 394 | 1922 | 4011 | 767 | 311 | 239 | 292 | 149 |
| uniqlo | 1184 | 1505 | 1015 | 3075 | 766 | 692 | 1162 | 42 |
| zara | 30 | 65 | 30 | 0 | 29 | 21 | 18 | 1 |

- Production catalog source는 MUSINSA/UNIQLO/ZARA 세 종류뿐이다.
- COS는 iOS production parser와 sync source normalization이 존재하지만 production `products`/mapping/decision row는 0이다. COS fixture subset은 섹션 9에서 app-only sentinel로 분리한다.
- 5,026 fixture는 MUSINSA/UNIQLO legacy decision corpus와 100% overlap한다. ZARA는 active release의 공식 structured subset 30 decision 중 current products 29건이 확인된다.
- source별 affected closet item과 comparison history는 manifest 전 행에서 0이다. 현재 closet 6건 모두 product_id가 없고 comparison history 자체가 0건이기 때문이다.

## 5. invalid confirmed 목록

Strict tuple 판정은 active app category/detail, active garment type, garment major, active comparison group, family/garment compatibility, group major, required length axis, non-null/non-generic confirmed 조건을 모두 적용했다. history에 garment_type이 없으므로 category+family로 단 하나의 active garment가 명백히 추론되는 경우만 임시 inference했다.

Invalid reason 분포(한 product에 복수 reason 가능):

| 값 | 건수 |
| --- | --- |
| comparison_family_inactive_or_missing | 811 |
| garment_type_not_stored_or_unambiguously_inferable | 811 |
| source_mapping_product_decision_conflict | 419 |
| detail_not_active_under_category | 168 |
| required_sleeve_axis_invalid_or_missing | 45 |
| required_body_axis_invalid_or_missing | 38 |
| required_pants_axis_invalid_or_missing | 26 |

<details>
<summary>invalid confirmed 전수 952건</summary>

**musinsa (239)**

`musinsa:1558197`, `musinsa:1803235`, `musinsa:1803462`, `musinsa:1884480`, `musinsa:2124438`, `musinsa:2303284`, `musinsa:2398609`, `musinsa:2444810`, `musinsa:2447802`, `musinsa:2578996`, `musinsa:2609006`, `musinsa:2737014`, `musinsa:2796118`, `musinsa:3042005`, `musinsa:3138552`, `musinsa:3144417`, `musinsa:3154695`, `musinsa:3189629`

`musinsa:3201942`, `musinsa:3225860`, `musinsa:3274287`, `musinsa:3306719`, `musinsa:3346165`, `musinsa:3442344`, `musinsa:3503598`, `musinsa:3690284`, `musinsa:3774997`, `musinsa:3790852`, `musinsa:3791988`, `musinsa:3822928`, `musinsa:3837942`, `musinsa:3943088`, `musinsa:3972476`, `musinsa:4071959`, `musinsa:4108579`, `musinsa:4154987`

`musinsa:4163350`, `musinsa:4190655`, `musinsa:4336062`, `musinsa:4513309`, `musinsa:4619961`, `musinsa:4622191`, `musinsa:4636893`, `musinsa:4651436`, `musinsa:4652853`, `musinsa:4663938`, `musinsa:4664068`, `musinsa:4687212`, `musinsa:4696797`, `musinsa:4702364`, `musinsa:4719540`, `musinsa:4720624`, `musinsa:4747236`, `musinsa:4763740`

`musinsa:4795032`, `musinsa:4818151`, `musinsa:4821229`, `musinsa:4827195`, `musinsa:4933453`, `musinsa:4989733`, `musinsa:4993190`, `musinsa:5038460`, `musinsa:5070728`, `musinsa:5074988`, `musinsa:5097306`, `musinsa:5104486`, `musinsa:5134734`, `musinsa:5139106`, `musinsa:5152458`, `musinsa:5178636`, `musinsa:5199474`, `musinsa:5279560`

`musinsa:5310167`, `musinsa:5310275`, `musinsa:5322326`, `musinsa:5329361`, `musinsa:5345115`, `musinsa:5354512`, `musinsa:5358816`, `musinsa:5413150`, `musinsa:5442400`, `musinsa:5489923`, `musinsa:5504965`, `musinsa:5626716`, `musinsa:5661620`, `musinsa:5661624`, `musinsa:5661658`, `musinsa:5695795`, `musinsa:5698175`, `musinsa:5698179`

`musinsa:5795897`, `musinsa:5795942`, `musinsa:5828291`, `musinsa:5886363`, `musinsa:5894308`, `musinsa:5897661`, `musinsa:5930121`, `musinsa:5936309`, `musinsa:5946738`, `musinsa:5973119`, `musinsa:5980112`, `musinsa:5983366`, `musinsa:5987009`, `musinsa:5990761`, `musinsa:5991125`, `musinsa:5992470`, `musinsa:6005543`, `musinsa:6021332`

`musinsa:6026203`, `musinsa:6041618`, `musinsa:6048605`, `musinsa:6055644`, `musinsa:6077337`, `musinsa:6102673`, `musinsa:6111537`, `musinsa:6127741`, `musinsa:6127744`, `musinsa:6145321`, `musinsa:6146614`, `musinsa:6152463`, `musinsa:6174464`, `musinsa:6219777`, `musinsa:6227070`, `musinsa:6271693`, `musinsa:6273570`, `musinsa:6284785`

`musinsa:6291325`, `musinsa:6305662`, `musinsa:6305730`, `musinsa:6314223`, `musinsa:6319969`, `musinsa:6326050`, `musinsa:6364512`, `musinsa:6365348`, `musinsa:6373202`, `musinsa:6385445`, `musinsa:6385539`, `musinsa:6390295`, `musinsa:6401860`, `musinsa:6401861`, `musinsa:6402661`, `musinsa:6403675`, `musinsa:6411854`, `musinsa:6426535`

`musinsa:6430808`, `musinsa:6433137`, `musinsa:6450036`, `musinsa:6454409`, `musinsa:6458570`, `musinsa:6458651`, `musinsa:6461382`, `musinsa:6469952`, `musinsa:6472215`, `musinsa:6479372`, `musinsa:6480709`, `musinsa:6488982`, `musinsa:6496880`, `musinsa:6499914`, `musinsa:6504560`, `musinsa:6515986`, `musinsa:6518709`, `musinsa:6532779`

`musinsa:6534481`, `musinsa:6565987`, `musinsa:6590780`, `musinsa:6595041`, `musinsa:6596161`, `musinsa:6610865`, `musinsa:6622473`, `musinsa:6633891`, `musinsa:6633896`, `musinsa:6639238`, `musinsa:6656659`, `musinsa:6679899`, `musinsa:6686050`, `musinsa:6686197`, `musinsa:6686255`, `musinsa:6693986`, `musinsa:6697003`, `musinsa:6697020`

`musinsa:6702426`, `musinsa:6716192`, `musinsa:6719352`, `musinsa:6723562`, `musinsa:6724257`, `musinsa:6733025`, `musinsa:6746766`, `musinsa:6764812`, `musinsa:6769967`, `musinsa:6777736`, `musinsa:6777737`, `musinsa:6786592`, `musinsa:6786600`, `musinsa:6786762`, `musinsa:6794273`, `musinsa:6797005`, `musinsa:6800912`, `musinsa:6806873`

`musinsa:6809274`, `musinsa:6809660`, `musinsa:6812499`, `musinsa:6814919`, `musinsa:6829636`, `musinsa:6829724`, `musinsa:6829741`, `musinsa:6830458`, `musinsa:6833248`, `musinsa:6837145`, `musinsa:6837147`, `musinsa:6837218`, `musinsa:6842888`, `musinsa:6843879`, `musinsa:6843889`, `musinsa:6844030`, `musinsa:6844107`, `musinsa:6859762`

`musinsa:6859805`, `musinsa:6874981`, `musinsa:6878575`, `musinsa:6880047`, `musinsa:6883772`, `musinsa:6883774`, `musinsa:6883776`, `musinsa:6884177`, `musinsa:6885251`, `musinsa:6896595`, `musinsa:6897082`, `musinsa:6901447`, `musinsa:6903639`, `musinsa:6907832`, `musinsa:6928699`, `musinsa:6932766`, `musinsa:6938901`, `musinsa:6938903`

`musinsa:6941805`, `musinsa:6968252`, `musinsa:7046980`, `musinsa:750908`, `musinsa:865862`

**uniqlo (692)**

`uniqlo:E439340`, `uniqlo:E439661`, `uniqlo:E444557`, `uniqlo:E444715`, `uniqlo:E447780`, `uniqlo:E448034`, `uniqlo:E448039`, `uniqlo:E448040`, `uniqlo:E448041`, `uniqlo:E448042`, `uniqlo:E448043`, `uniqlo:E448044`, `uniqlo:E448045`, `uniqlo:E449753`, `uniqlo:E450195`, `uniqlo:E450259`, `uniqlo:E450260`, `uniqlo:E450535`

`uniqlo:E450540`, `uniqlo:E450543`, `uniqlo:E452298`, `uniqlo:E453754`, `uniqlo:E454063`, `uniqlo:E454311`, `uniqlo:E454312`, `uniqlo:E454326`, `uniqlo:E454327`, `uniqlo:E454328`, `uniqlo:E455476`, `uniqlo:E455957`, `uniqlo:E456567`, `uniqlo:E457517`, `uniqlo:E457912`, `uniqlo:E457913`, `uniqlo:E458325`, `uniqlo:E458462`

`uniqlo:E458788`, `uniqlo:E460776`, `uniqlo:E460974`, `uniqlo:E461001`, `uniqlo:E461003`, `uniqlo:E461013`, `uniqlo:E461420`, `uniqlo:E461767`, `uniqlo:E463820`, `uniqlo:E464311`, `uniqlo:E464334`, `uniqlo:E464536`, `uniqlo:E464637`, `uniqlo:E465163`, `uniqlo:E465185`, `uniqlo:E465196`, `uniqlo:E465203`, `uniqlo:E465206`

`uniqlo:E465491`, `uniqlo:E465707`, `uniqlo:E465734`, `uniqlo:E466489`, `uniqlo:E466509`, `uniqlo:E467574`, `uniqlo:E468671`, `uniqlo:E469292`, `uniqlo:E469409`, `uniqlo:E469410`, `uniqlo:E469411`, `uniqlo:E469617`, `uniqlo:E469740`, `uniqlo:E469742`, `uniqlo:E469765`, `uniqlo:E469836`, `uniqlo:E469863`, `uniqlo:E469871`

`uniqlo:E469956`, `uniqlo:E470061`, `uniqlo:E470118`, `uniqlo:E470143`, `uniqlo:E470182`, `uniqlo:E470187`, `uniqlo:E470362`, `uniqlo:E470374`, `uniqlo:E470542`, `uniqlo:E470549`, `uniqlo:E471601`, `uniqlo:E471717`, `uniqlo:E471809`, `uniqlo:E473559`, `uniqlo:E473696`, `uniqlo:E473715`, `uniqlo:E473944`, `uniqlo:E473945`

`uniqlo:E473979`, `uniqlo:E474152`, `uniqlo:E474175`, `uniqlo:E474321`, `uniqlo:E474481`, `uniqlo:E474592`, `uniqlo:E474816`, `uniqlo:E474832`, `uniqlo:E475053`, `uniqlo:E475367`, `uniqlo:E475386`, `uniqlo:E475598`, `uniqlo:E475647`, `uniqlo:E475649`, `uniqlo:E475800`, `uniqlo:E475941`, `uniqlo:E475943`, `uniqlo:E475945`

`uniqlo:E476209`, `uniqlo:E476225`, `uniqlo:E476320`, `uniqlo:E476528`, `uniqlo:E476975`, `uniqlo:E476997`, `uniqlo:E477704`, `uniqlo:E477869`, `uniqlo:E478018`, `uniqlo:E478023`, `uniqlo:E478025`, `uniqlo:E478123`, `uniqlo:E478456`, `uniqlo:E478623`, `uniqlo:E478628`, `uniqlo:E478634`, `uniqlo:E478637`, `uniqlo:E478656`

`uniqlo:E478657`, `uniqlo:E478670`, `uniqlo:E478702`, `uniqlo:E478814`, `uniqlo:E478965`, `uniqlo:E479000`, `uniqlo:E479071`, `uniqlo:E479073`, `uniqlo:E479134`, `uniqlo:E479202`, `uniqlo:E479450`, `uniqlo:E479467`, `uniqlo:E479497`, `uniqlo:E479502`, `uniqlo:E479525`, `uniqlo:E479538`, `uniqlo:E479575`, `uniqlo:E479620`

`uniqlo:E479724`, `uniqlo:E479751`, `uniqlo:E479755`, `uniqlo:E479816`, `uniqlo:E479885`, `uniqlo:E480342`, `uniqlo:E480346`, `uniqlo:E480764`, `uniqlo:E480785`, `uniqlo:E480861`, `uniqlo:E480911`, `uniqlo:E480966`, `uniqlo:E480997`, `uniqlo:E481004`, `uniqlo:E481030`, `uniqlo:E481036`, `uniqlo:E481040`, `uniqlo:E481224`

`uniqlo:E481249`, `uniqlo:E481388`, `uniqlo:E481441`, `uniqlo:E481442`, `uniqlo:E481582`, `uniqlo:E481583`, `uniqlo:E481599`, `uniqlo:E481731`, `uniqlo:E481779`, `uniqlo:E481780`, `uniqlo:E481782`, `uniqlo:E481786`, `uniqlo:E481787`, `uniqlo:E481788`, `uniqlo:E481790`, `uniqlo:E481791`, `uniqlo:E481800`, `uniqlo:E481801`

`uniqlo:E481808`, `uniqlo:E481809`, `uniqlo:E481881`, `uniqlo:E481951`, `uniqlo:E481963`, `uniqlo:E481965`, `uniqlo:E481994`, `uniqlo:E482006`, `uniqlo:E482008`, `uniqlo:E482009`, `uniqlo:E482015`, `uniqlo:E482148`, `uniqlo:E482154`, `uniqlo:E482172`, `uniqlo:E482181`, `uniqlo:E482184`, `uniqlo:E482189`, `uniqlo:E482194`

`uniqlo:E482198`, `uniqlo:E482201`, `uniqlo:E482202`, `uniqlo:E482204`, `uniqlo:E482243`, `uniqlo:E482259`, `uniqlo:E482260`, `uniqlo:E482279`, `uniqlo:E482280`, `uniqlo:E482281`, `uniqlo:E482286`, `uniqlo:E482299`, `uniqlo:E482303`, `uniqlo:E482304`, `uniqlo:E482305`, `uniqlo:E482306`, `uniqlo:E482321`, `uniqlo:E482328`

`uniqlo:E482329`, `uniqlo:E482415`, `uniqlo:E482419`, `uniqlo:E482424`, `uniqlo:E482434`, `uniqlo:E482452`, `uniqlo:E482460`, `uniqlo:E482461`, `uniqlo:E482479`, `uniqlo:E482480`, `uniqlo:E482481`, `uniqlo:E482483`, `uniqlo:E482497`, `uniqlo:E482498`, `uniqlo:E482502`, `uniqlo:E482514`, `uniqlo:E482538`, `uniqlo:E482556`

`uniqlo:E482557`, `uniqlo:E482558`, `uniqlo:E482563`, `uniqlo:E482565`, `uniqlo:E482567`, `uniqlo:E482569`, `uniqlo:E482581`, `uniqlo:E482598`, `uniqlo:E482600`, `uniqlo:E482646`, `uniqlo:E482652`, `uniqlo:E482658`, `uniqlo:E482659`, `uniqlo:E482697`, `uniqlo:E482701`, `uniqlo:E482703`, `uniqlo:E482758`, `uniqlo:E482825`

`uniqlo:E482856`, `uniqlo:E482868`, `uniqlo:E482880`, `uniqlo:E482920`, `uniqlo:E482937`, `uniqlo:E482942`, `uniqlo:E482944`, `uniqlo:E482965`, `uniqlo:E482982`, `uniqlo:E482983`, `uniqlo:E483001`, `uniqlo:E483128`, `uniqlo:E483129`, `uniqlo:E483184`, `uniqlo:E483281`, `uniqlo:E483285`, `uniqlo:E483327`, `uniqlo:E483329`

`uniqlo:E483394`, `uniqlo:E483395`, `uniqlo:E483406`, `uniqlo:E483411`, `uniqlo:E483412`, `uniqlo:E483443`, `uniqlo:E483502`, `uniqlo:E483512`, `uniqlo:E483546`, `uniqlo:E483556`, `uniqlo:E483564`, `uniqlo:E483807`, `uniqlo:E483869`, `uniqlo:E483872`, `uniqlo:E483875`, `uniqlo:E483880`, `uniqlo:E483881`, `uniqlo:E483890`

`uniqlo:E483903`, `uniqlo:E483912`, `uniqlo:E483913`, `uniqlo:E483924`, `uniqlo:E483970`, `uniqlo:E483972`, `uniqlo:E483975`, `uniqlo:E483986`, `uniqlo:E483999`, `uniqlo:E484026`, `uniqlo:E484064`, `uniqlo:E484066`, `uniqlo:E484075`, `uniqlo:E484209`, `uniqlo:E484240`, `uniqlo:E484244`, `uniqlo:E484245`, `uniqlo:E484249`

`uniqlo:E484256`, `uniqlo:E484289`, `uniqlo:E484398`, `uniqlo:E484425`, `uniqlo:E484508`, `uniqlo:E484598`, `uniqlo:E484605`, `uniqlo:E484607`, `uniqlo:E484610`, `uniqlo:E484664`, `uniqlo:E484705`, `uniqlo:E484717`, `uniqlo:E484784`, `uniqlo:E484792`, `uniqlo:E484807`, `uniqlo:E484830`, `uniqlo:E484849`, `uniqlo:E484854`

`uniqlo:E484860`, `uniqlo:E484876`, `uniqlo:E484904`, `uniqlo:E484905`, `uniqlo:E484920`, `uniqlo:E484924`, `uniqlo:E484928`, `uniqlo:E484938`, `uniqlo:E484939`, `uniqlo:E484940`, `uniqlo:E484992`, `uniqlo:E484993`, `uniqlo:E484996`, `uniqlo:E484997`, `uniqlo:E485143`, `uniqlo:E485162`, `uniqlo:E485224`, `uniqlo:E485265`

`uniqlo:E485306`, `uniqlo:E485307`, `uniqlo:E485310`, `uniqlo:E485318`, `uniqlo:E485321`, `uniqlo:E485322`, `uniqlo:E485340`, `uniqlo:E485359`, `uniqlo:E485369`, `uniqlo:E485393`, `uniqlo:E485435`, `uniqlo:E485495`, `uniqlo:E485541`, `uniqlo:E485558`, `uniqlo:E485564`, `uniqlo:E485565`, `uniqlo:E485566`, `uniqlo:E485567`

`uniqlo:E485568`, `uniqlo:E485584`, `uniqlo:E485593`, `uniqlo:E485610`, `uniqlo:E485612`, `uniqlo:E485653`, `uniqlo:E485679`, `uniqlo:E485709`, `uniqlo:E485710`, `uniqlo:E485711`, `uniqlo:E485717`, `uniqlo:E485735`, `uniqlo:E485737`, `uniqlo:E485739`, `uniqlo:E485744`, `uniqlo:E485745`, `uniqlo:E485778`, `uniqlo:E485782`

`uniqlo:E485808`, `uniqlo:E486071`, `uniqlo:E486074`, `uniqlo:E486080`, `uniqlo:E486095`, `uniqlo:E486107`, `uniqlo:E486117`, `uniqlo:E486119`, `uniqlo:E486120`, `uniqlo:E486121`, `uniqlo:E486167`, `uniqlo:E486171`, `uniqlo:E486220`, `uniqlo:E486295`, `uniqlo:E486317`, `uniqlo:E486320`, `uniqlo:E486411`, `uniqlo:E486416`

`uniqlo:E486417`, `uniqlo:E486425`, `uniqlo:E486426`, `uniqlo:E486427`, `uniqlo:E486428`, `uniqlo:E486443`, `uniqlo:E486448`, `uniqlo:E486449`, `uniqlo:E486450`, `uniqlo:E486451`, `uniqlo:E486468`, `uniqlo:E486471`, `uniqlo:E486499`, `uniqlo:E486501`, `uniqlo:E486503`, `uniqlo:E486507`, `uniqlo:E486511`, `uniqlo:E486562`

`uniqlo:E486565`, `uniqlo:E486566`, `uniqlo:E486568`, `uniqlo:E486578`, `uniqlo:E486585`, `uniqlo:E486586`, `uniqlo:E486587`, `uniqlo:E486588`, `uniqlo:E486590`, `uniqlo:E486591`, `uniqlo:E486594`, `uniqlo:E486595`, `uniqlo:E486596`, `uniqlo:E486597`, `uniqlo:E486598`, `uniqlo:E486600`, `uniqlo:E486602`, `uniqlo:E486604`

`uniqlo:E486612`, `uniqlo:E486614`, `uniqlo:E486615`, `uniqlo:E486630`, `uniqlo:E486637`, `uniqlo:E486638`, `uniqlo:E486660`, `uniqlo:E486683`, `uniqlo:E486684`, `uniqlo:E486691`, `uniqlo:E486695`, `uniqlo:E486696`, `uniqlo:E486697`, `uniqlo:E486699`, `uniqlo:E486701`, `uniqlo:E486703`, `uniqlo:E486706`, `uniqlo:E486718`

`uniqlo:E486722`, `uniqlo:E486723`, `uniqlo:E486724`, `uniqlo:E486725`, `uniqlo:E486726`, `uniqlo:E486729`, `uniqlo:E486734`, `uniqlo:E486736`, `uniqlo:E486738`, `uniqlo:E486743`, `uniqlo:E486746`, `uniqlo:E486747`, `uniqlo:E486819`, `uniqlo:E486834`, `uniqlo:E486875`, `uniqlo:E486877`, `uniqlo:E487001`, `uniqlo:E487005`

`uniqlo:E487016`, `uniqlo:E487024`, `uniqlo:E487026`, `uniqlo:E487028`, `uniqlo:E487030`, `uniqlo:E487032`, `uniqlo:E487034`, `uniqlo:E487036`, `uniqlo:E487038`, `uniqlo:E487040`, `uniqlo:E487042`, `uniqlo:E487044`, `uniqlo:E487046`, `uniqlo:E487048`, `uniqlo:E487050`, `uniqlo:E487052`, `uniqlo:E487054`, `uniqlo:E487058`

`uniqlo:E487060`, `uniqlo:E487064`, `uniqlo:E487066`, `uniqlo:E487070`, `uniqlo:E487072`, `uniqlo:E487074`, `uniqlo:E487118`, `uniqlo:E487119`, `uniqlo:E487120`, `uniqlo:E487121`, `uniqlo:E487124`, `uniqlo:E487125`, `uniqlo:E487127`, `uniqlo:E487128`, `uniqlo:E487201`, `uniqlo:E487206`, `uniqlo:E487209`, `uniqlo:E487216`

`uniqlo:E487220`, `uniqlo:E487261`, `uniqlo:E487263`, `uniqlo:E487272`, `uniqlo:E487273`, `uniqlo:E487278`, `uniqlo:E487286`, `uniqlo:E487303`, `uniqlo:E487337`, `uniqlo:E487338`, `uniqlo:E487339`, `uniqlo:E487340`, `uniqlo:E487345`, `uniqlo:E487348`, `uniqlo:E487394`, `uniqlo:E487396`, `uniqlo:E487404`, `uniqlo:E487408`

`uniqlo:E487420`, `uniqlo:E487516`, `uniqlo:E487517`, `uniqlo:E487518`, `uniqlo:E487526`, `uniqlo:E487528`, `uniqlo:E487589`, `uniqlo:E487630`, `uniqlo:E487650`, `uniqlo:E487688`, `uniqlo:E487689`, `uniqlo:E487742`, `uniqlo:E487751`, `uniqlo:E487832`, `uniqlo:E487846`, `uniqlo:E487891`, `uniqlo:E487899`, `uniqlo:E487939`

`uniqlo:E487942`, `uniqlo:E487957`, `uniqlo:E487959`, `uniqlo:E487978`, `uniqlo:E487989`, `uniqlo:E487995`, `uniqlo:E487996`, `uniqlo:E488005`, `uniqlo:E488006`, `uniqlo:E488007`, `uniqlo:E488008`, `uniqlo:E488010`, `uniqlo:E488014`, `uniqlo:E488035`, `uniqlo:E488037`, `uniqlo:E488038`, `uniqlo:E488041`, `uniqlo:E488089`

`uniqlo:E488145`, `uniqlo:E488157`, `uniqlo:E488163`, `uniqlo:E488167`, `uniqlo:E488168`, `uniqlo:E488171`, `uniqlo:E488172`, `uniqlo:E488173`, `uniqlo:E488174`, `uniqlo:E488200`, `uniqlo:E488203`, `uniqlo:E488204`, `uniqlo:E488206`, `uniqlo:E488209`, `uniqlo:E488210`, `uniqlo:E488216`, `uniqlo:E488280`, `uniqlo:E488333`

`uniqlo:E488357`, `uniqlo:E488358`, `uniqlo:E488364`, `uniqlo:E488371`, `uniqlo:E488397`, `uniqlo:E488426`, `uniqlo:E488448`, `uniqlo:E488520`, `uniqlo:E488522`, `uniqlo:E488559`, `uniqlo:E488560`, `uniqlo:E488580`, `uniqlo:E488630`, `uniqlo:E488642`, `uniqlo:E488643`, `uniqlo:E488650`, `uniqlo:E488651`, `uniqlo:E488668`

`uniqlo:E488684`, `uniqlo:E488694`, `uniqlo:E488700`, `uniqlo:E488722`, `uniqlo:E488726`, `uniqlo:E488738`, `uniqlo:E488743`, `uniqlo:E488785`, `uniqlo:E488787`, `uniqlo:E488789`, `uniqlo:E488790`, `uniqlo:E488793`, `uniqlo:E488794`, `uniqlo:E488795`, `uniqlo:E488796`, `uniqlo:E488797`, `uniqlo:E488798`, `uniqlo:E488814`

`uniqlo:E488816`, `uniqlo:E488828`, `uniqlo:E488829`, `uniqlo:E488860`, `uniqlo:E488866`, `uniqlo:E488922`, `uniqlo:E488923`, `uniqlo:E488925`, `uniqlo:E488934`, `uniqlo:E488939`, `uniqlo:E488997`, `uniqlo:E489026`, `uniqlo:E489044`, `uniqlo:E489045`, `uniqlo:E489049`, `uniqlo:E489055`, `uniqlo:E489058`, `uniqlo:E489065`

`uniqlo:E489074`, `uniqlo:E489075`, `uniqlo:E489076`, `uniqlo:E489085`, `uniqlo:E489110`, `uniqlo:E489125`, `uniqlo:E489136`, `uniqlo:E489138`, `uniqlo:E489180`, `uniqlo:E489216`, `uniqlo:E489217`, `uniqlo:E489227`, `uniqlo:E489229`, `uniqlo:E489230`, `uniqlo:E489367`, `uniqlo:E489392`, `uniqlo:E489393`, `uniqlo:E489394`

`uniqlo:E489398`, `uniqlo:E489399`, `uniqlo:E489406`, `uniqlo:E489407`, `uniqlo:E489408`, `uniqlo:E489409`, `uniqlo:E489415`, `uniqlo:E489427`, `uniqlo:E489483`, `uniqlo:E489508`, `uniqlo:E489509`, `uniqlo:E489540`, `uniqlo:E489541`, `uniqlo:E489563`, `uniqlo:E489565`, `uniqlo:E489682`, `uniqlo:E490285`, `uniqlo:E490697`

`uniqlo:E491000`, `uniqlo:E491001`, `uniqlo:E491002`, `uniqlo:E491086`, `uniqlo:E491096`, `uniqlo:E491104`, `uniqlo:E491115`, `uniqlo:E491116`, `uniqlo:E491119`, `uniqlo:E491209`, `uniqlo:E491210`, `uniqlo:E491284`, `uniqlo:E491285`, `uniqlo:E491294`, `uniqlo:E491297`, `uniqlo:E491320`, `uniqlo:E491380`, `uniqlo:E491602`

`uniqlo:E491779`, `uniqlo:E491988`, `uniqlo:E491991`, `uniqlo:E492040`, `uniqlo:E492081`, `uniqlo:E492123`, `uniqlo:E492365`, `uniqlo:E492538`

**zara (21)**

`zara:545406831`, `zara:545427337`, `zara:545428239`, `zara:545439169`, `zara:545483281`, `zara:547003473`, `zara:547276687`, `zara:548577264`, `zara:552163213`, `zara:554006103`, `zara:554764120`, `zara:555161842`, `zara:555162424`, `zara:556139700`, `zara:558215502`, `zara:560347128`, `zara:561264931`, `zara:561568002`

`zara:561583709`, `zara:561610369`, `zara:562814885`

</details>

Stale reason 분포(한 product에 복수 reason 가능):

| 값 | 건수 |
| --- | --- |
| mapping_release_not_active | 1380 |
| decision_release_not_active | 1207 |
| active_source_mapping_differs_from_current_history | 773 |
| product_fingerprint_mismatch | 94 |

<details>
<summary>stale current history 전수 1472건</summary>

**musinsa (292)**

`musinsa:1558197`, `musinsa:1803235`, `musinsa:1803462`, `musinsa:1884480`, `musinsa:2124438`, `musinsa:2303284`, `musinsa:2398609`, `musinsa:2444810`, `musinsa:2518490`, `musinsa:2578996`, `musinsa:2609006`, `musinsa:2737014`, `musinsa:2796118`, `musinsa:3042005`, `musinsa:3132891`, `musinsa:3134729`, `musinsa:3138552`, `musinsa:3154695`

`musinsa:3182421`, `musinsa:3189629`, `musinsa:3201942`, `musinsa:3274287`, `musinsa:3306719`, `musinsa:3346165`, `musinsa:3690284`, `musinsa:3776694`, `musinsa:3790852`, `musinsa:3791988`, `musinsa:3837942`, `musinsa:3943088`, `musinsa:4062254`, `musinsa:4093932`, `musinsa:4108579`, `musinsa:4109246`, `musinsa:4154987`, `musinsa:4163350`

`musinsa:4190655`, `musinsa:4336062`, `musinsa:4513309`, `musinsa:4619961`, `musinsa:4622191`, `musinsa:4636893`, `musinsa:4651400`, `musinsa:4651436`, `musinsa:4652853`, `musinsa:4663938`, `musinsa:4664068`, `musinsa:4687212`, `musinsa:4696797`, `musinsa:4702364`, `musinsa:4719540`, `musinsa:4719977`, `musinsa:4739114`, `musinsa:4747236`

`musinsa:4763740`, `musinsa:4795032`, `musinsa:4800605`, `musinsa:4818151`, `musinsa:4821229`, `musinsa:4827195`, `musinsa:4933453`, `musinsa:4989733`, `musinsa:4993190`, `musinsa:5074988`, `musinsa:5097306`, `musinsa:5104486`, `musinsa:5134734`, `musinsa:5139106`, `musinsa:5152458`, `musinsa:5178636`, `musinsa:5199474`, `musinsa:5279560`

`musinsa:5283519`, `musinsa:5310167`, `musinsa:5329359`, `musinsa:5329361`, `musinsa:5343592`, `musinsa:5345115`, `musinsa:5354512`, `musinsa:5358816`, `musinsa:5413150`, `musinsa:5479465`, `musinsa:5489923`, `musinsa:5626716`, `musinsa:5673055`, `musinsa:5698175`, `musinsa:5698181`, `musinsa:5698186`, `musinsa:5795897`, `musinsa:5828291`

`musinsa:5886363`, `musinsa:5894308`, `musinsa:5897661`, `musinsa:5946738`, `musinsa:5973119`, `musinsa:5980112`, `musinsa:5982920`, `musinsa:5983366`, `musinsa:5987009`, `musinsa:5990761`, `musinsa:5991125`, `musinsa:5992470`, `musinsa:6005543`, `musinsa:6008535`, `musinsa:6021332`, `musinsa:6026203`, `musinsa:6041618`, `musinsa:6048605`

`musinsa:6055644`, `musinsa:6077337`, `musinsa:6102673`, `musinsa:6111537`, `musinsa:6127741`, `musinsa:6127744`, `musinsa:6140472`, `musinsa:6145321`, `musinsa:6146614`, `musinsa:6152463`, `musinsa:6200629`, `musinsa:6219777`, `musinsa:6227070`, `musinsa:6253269`, `musinsa:6273570`, `musinsa:6284785`, `musinsa:6291325`, `musinsa:6305662`

`musinsa:6305730`, `musinsa:6314223`, `musinsa:6319969`, `musinsa:6326050`, `musinsa:6341391`, `musinsa:6364512`, `musinsa:6373202`, `musinsa:6385445`, `musinsa:6385539`, `musinsa:6390295`, `musinsa:6401861`, `musinsa:6402661`, `musinsa:6408788`, `musinsa:6411854`, `musinsa:6418260`, `musinsa:6426535`, `musinsa:6430808`, `musinsa:6453592`

`musinsa:6454409`, `musinsa:6458570`, `musinsa:6458651`, `musinsa:6461382`, `musinsa:6469952`, `musinsa:6472215`, `musinsa:6480709`, `musinsa:6488982`, `musinsa:6499914`, `musinsa:6501146`, `musinsa:6501149`, `musinsa:6515855`, `musinsa:6515986`, `musinsa:6518709`, `musinsa:6532779`, `musinsa:6534177`, `musinsa:6565987`, `musinsa:6590780`

`musinsa:6590793`, `musinsa:6593581`, `musinsa:6609200`, `musinsa:6609390`, `musinsa:6610865`, `musinsa:6632593`, `musinsa:6632608`, `musinsa:6639238`, `musinsa:6656624`, `musinsa:6670811`, `musinsa:6677393`, `musinsa:6679899`, `musinsa:6686050`, `musinsa:6686197`, `musinsa:6686255`, `musinsa:6686260`, `musinsa:6689485`, `musinsa:6693832`

`musinsa:6693866`, `musinsa:6693986`, `musinsa:6694431`, `musinsa:6695701`, `musinsa:6696985`, `musinsa:6697020`, `musinsa:6702426`, `musinsa:6702453`, `musinsa:6706361`, `musinsa:6708161`, `musinsa:6715231`, `musinsa:6716192`, `musinsa:6716203`, `musinsa:6716212`, `musinsa:6719352`, `musinsa:6721671`, `musinsa:6721706`, `musinsa:6729526`

`musinsa:6729879`, `musinsa:6732631`, `musinsa:6733025`, `musinsa:6737107`, `musinsa:6745094`, `musinsa:6746766`, `musinsa:6754165`, `musinsa:6755261`, `musinsa:6755330`, `musinsa:6768741`, `musinsa:6774915`, `musinsa:6778715`, `musinsa:6778749`, `musinsa:6778769`, `musinsa:6781113`, `musinsa:6786576`, `musinsa:6786592`, `musinsa:6786600`

`musinsa:6786762`, `musinsa:6789405`, `musinsa:6794273`, `musinsa:6797265`, `musinsa:6797266`, `musinsa:6797271`, `musinsa:6800367`, `musinsa:6800912`, `musinsa:6800975`, `musinsa:6805433`, `musinsa:6806873`, `musinsa:6809660`, `musinsa:6812676`, `musinsa:6814919`, `musinsa:6829636`, `musinsa:6829724`, `musinsa:6829741`, `musinsa:6830458`

`musinsa:6833448`, `musinsa:6833866`, `musinsa:6837218`, `musinsa:6837242`, `musinsa:6839271`, `musinsa:6842612`, `musinsa:6842888`, `musinsa:6843694`, `musinsa:6843879`, `musinsa:6843889`, `musinsa:6844030`, `musinsa:6844040`, `musinsa:6849281`, `musinsa:6850912`, `musinsa:6852823`, `musinsa:6858118`, `musinsa:6859762`, `musinsa:6859805`

`musinsa:6876277`, `musinsa:6878575`, `musinsa:6883772`, `musinsa:6883774`, `musinsa:6883776`, `musinsa:6884177`, `musinsa:6885251`, `musinsa:6887357`, `musinsa:6896379`, `musinsa:6896595`, `musinsa:6896783`, `musinsa:6897082`, `musinsa:6903639`, `musinsa:6907230`, `musinsa:6907832`, `musinsa:6907891`, `musinsa:6908583`, `musinsa:6908818`

`musinsa:6908820`, `musinsa:6908905`, `musinsa:6910253`, `musinsa:6912863`, `musinsa:6914789`, `musinsa:6927386`, `musinsa:6929142`, `musinsa:6929984`, `musinsa:6932766`, `musinsa:6933792`, `musinsa:6948430`, `musinsa:6957088`, `musinsa:6960215`, `musinsa:6961628`, `musinsa:6961646`, `musinsa:6980872`, `musinsa:6987932`, `musinsa:6996910`

`musinsa:6998028`, `musinsa:7008856`, `musinsa:750908`, `musinsa:865862`

**uniqlo (1162)**

`uniqlo:E422992`, `uniqlo:E424873`, `uniqlo:E433776`, `uniqlo:E439340`, `uniqlo:E439661`, `uniqlo:E441897`, `uniqlo:E444557`, `uniqlo:E444715`, `uniqlo:E444812`, `uniqlo:E447780`, `uniqlo:E448034`, `uniqlo:E448039`, `uniqlo:E448040`, `uniqlo:E448041`, `uniqlo:E448042`, `uniqlo:E448043`, `uniqlo:E448044`, `uniqlo:E448045`

`uniqlo:E449753`, `uniqlo:E450179`, `uniqlo:E450195`, `uniqlo:E450259`, `uniqlo:E450260`, `uniqlo:E450535`, `uniqlo:E450536`, `uniqlo:E450540`, `uniqlo:E450543`, `uniqlo:E450544`, `uniqlo:E452029`, `uniqlo:E452298`, `uniqlo:E453754`, `uniqlo:E454063`, `uniqlo:E454311`, `uniqlo:E454312`, `uniqlo:E454326`, `uniqlo:E454327`

`uniqlo:E454328`, `uniqlo:E455365`, `uniqlo:E455476`, `uniqlo:E455942`, `uniqlo:E455957`, `uniqlo:E456567`, `uniqlo:E457111`, `uniqlo:E457120`, `uniqlo:E457121`, `uniqlo:E457267`, `uniqlo:E457288`, `uniqlo:E457517`, `uniqlo:E457857`, `uniqlo:E457912`, `uniqlo:E457913`, `uniqlo:E458325`, `uniqlo:E458462`, `uniqlo:E458788`

`uniqlo:E459561`, `uniqlo:E459564`, `uniqlo:E459565`, `uniqlo:E459567`, `uniqlo:E460431`, `uniqlo:E460490`, `uniqlo:E460776`, `uniqlo:E460974`, `uniqlo:E461001`, `uniqlo:E461003`, `uniqlo:E461013`, `uniqlo:E461025`, `uniqlo:E461420`, `uniqlo:E461767`, `uniqlo:E462191`, `uniqlo:E462216`, `uniqlo:E462220`, `uniqlo:E462233`

`uniqlo:E463729`, `uniqlo:E463730`, `uniqlo:E463820`, `uniqlo:E464284`, `uniqlo:E464311`, `uniqlo:E464334`, `uniqlo:E464384`, `uniqlo:E464386`, `uniqlo:E464390`, `uniqlo:E464392`, `uniqlo:E464536`, `uniqlo:E464637`, `uniqlo:E465163`, `uniqlo:E465185`, `uniqlo:E465187`, `uniqlo:E465189`, `uniqlo:E465193`, `uniqlo:E465196`

`uniqlo:E465203`, `uniqlo:E465206`, `uniqlo:E465484`, `uniqlo:E465491`, `uniqlo:E465707`, `uniqlo:E465734`, `uniqlo:E465735`, `uniqlo:E465751`, `uniqlo:E465755`, `uniqlo:E465760`, `uniqlo:E466168`, `uniqlo:E466434`, `uniqlo:E466489`, `uniqlo:E466509`, `uniqlo:E467322`, `uniqlo:E467421`, `uniqlo:E467574`, `uniqlo:E468495`

`uniqlo:E468496`, `uniqlo:E468671`, `uniqlo:E469292`, `uniqlo:E469409`, `uniqlo:E469410`, `uniqlo:E469411`, `uniqlo:E469617`, `uniqlo:E469700`, `uniqlo:E469740`, `uniqlo:E469742`, `uniqlo:E469765`, `uniqlo:E469836`, `uniqlo:E469863`, `uniqlo:E469871`, `uniqlo:E469956`, `uniqlo:E469996`, `uniqlo:E470008`, `uniqlo:E470061`

`uniqlo:E470118`, `uniqlo:E470143`, `uniqlo:E470182`, `uniqlo:E470187`, `uniqlo:E470362`, `uniqlo:E470374`, `uniqlo:E470542`, `uniqlo:E470549`, `uniqlo:E470836`, `uniqlo:E470960`, `uniqlo:E471157`, `uniqlo:E471601`, `uniqlo:E471717`, `uniqlo:E471808`, `uniqlo:E471809`, `uniqlo:E471947`, `uniqlo:E471951`, `uniqlo:E471958`

`uniqlo:E471968`, `uniqlo:E471972`, `uniqlo:E472516`, `uniqlo:E472517`, `uniqlo:E472519`, `uniqlo:E472520`, `uniqlo:E473486`, `uniqlo:E473559`, `uniqlo:E473696`, `uniqlo:E473715`, `uniqlo:E473791`, `uniqlo:E473944`, `uniqlo:E473945`, `uniqlo:E473953`, `uniqlo:E473968`, `uniqlo:E473970`, `uniqlo:E473979`, `uniqlo:E474152`

`uniqlo:E474175`, `uniqlo:E474321`, `uniqlo:E474462`, `uniqlo:E474481`, `uniqlo:E474592`, `uniqlo:E474816`, `uniqlo:E474832`, `uniqlo:E475053`, `uniqlo:E475344`, `uniqlo:E475367`, `uniqlo:E475376`, `uniqlo:E475386`, `uniqlo:E475598`, `uniqlo:E475647`, `uniqlo:E475648`, `uniqlo:E475649`, `uniqlo:E475762`, `uniqlo:E475763`

`uniqlo:E475800`, `uniqlo:E475941`, `uniqlo:E475943`, `uniqlo:E475945`, `uniqlo:E476209`, `uniqlo:E476225`, `uniqlo:E476320`, `uniqlo:E476353`, `uniqlo:E476354`, `uniqlo:E476355`, `uniqlo:E476528`, `uniqlo:E476975`, `uniqlo:E476997`, `uniqlo:E477074`, `uniqlo:E477345`, `uniqlo:E477704`, `uniqlo:E477869`, `uniqlo:E478018`

`uniqlo:E478023`, `uniqlo:E478025`, `uniqlo:E478123`, `uniqlo:E478168`, `uniqlo:E478306`, `uniqlo:E478444`, `uniqlo:E478456`, `uniqlo:E478623`, `uniqlo:E478628`, `uniqlo:E478634`, `uniqlo:E478637`, `uniqlo:E478656`, `uniqlo:E478657`, `uniqlo:E478670`, `uniqlo:E478702`, `uniqlo:E478814`, `uniqlo:E478965`, `uniqlo:E479000`

`uniqlo:E479071`, `uniqlo:E479073`, `uniqlo:E479134`, `uniqlo:E479182`, `uniqlo:E479183`, `uniqlo:E479184`, `uniqlo:E479202`, `uniqlo:E479450`, `uniqlo:E479467`, `uniqlo:E479487`, `uniqlo:E479488`, `uniqlo:E479525`, `uniqlo:E479538`, `uniqlo:E479546`, `uniqlo:E479575`, `uniqlo:E479620`, `uniqlo:E479724`, `uniqlo:E479751`

`uniqlo:E479755`, `uniqlo:E479816`, `uniqlo:E479885`, `uniqlo:E480054`, `uniqlo:E480342`, `uniqlo:E480345`, `uniqlo:E480346`, `uniqlo:E480716`, `uniqlo:E480717`, `uniqlo:E480721`, `uniqlo:E480726`, `uniqlo:E480727`, `uniqlo:E480729`, `uniqlo:E480732`, `uniqlo:E480764`, `uniqlo:E480785`, `uniqlo:E480814`, `uniqlo:E480815`

`uniqlo:E480850`, `uniqlo:E480851`, `uniqlo:E480861`, `uniqlo:E480911`, `uniqlo:E480966`, `uniqlo:E480997`, `uniqlo:E481004`, `uniqlo:E481030`, `uniqlo:E481036`, `uniqlo:E481040`, `uniqlo:E481091`, `uniqlo:E481224`, `uniqlo:E481249`, `uniqlo:E481388`, `uniqlo:E481441`, `uniqlo:E481442`, `uniqlo:E481582`, `uniqlo:E481583`

`uniqlo:E481599`, `uniqlo:E481610`, `uniqlo:E481623`, `uniqlo:E481626`, `uniqlo:E481636`, `uniqlo:E481637`, `uniqlo:E481638`, `uniqlo:E481639`, `uniqlo:E481640`, `uniqlo:E481646`, `uniqlo:E481648`, `uniqlo:E481649`, `uniqlo:E481731`, `uniqlo:E481761`, `uniqlo:E481764`, `uniqlo:E481769`, `uniqlo:E481772`, `uniqlo:E481779`

`uniqlo:E481780`, `uniqlo:E481782`, `uniqlo:E481786`, `uniqlo:E481787`, `uniqlo:E481788`, `uniqlo:E481790`, `uniqlo:E481791`, `uniqlo:E481792`, `uniqlo:E481794`, `uniqlo:E481796`, `uniqlo:E481797`, `uniqlo:E481800`, `uniqlo:E481801`, `uniqlo:E481808`, `uniqlo:E481809`, `uniqlo:E481881`, `uniqlo:E481898`, `uniqlo:E481930`

`uniqlo:E481931`, `uniqlo:E481951`, `uniqlo:E481963`, `uniqlo:E481965`, `uniqlo:E481972`, `uniqlo:E481973`, `uniqlo:E481978`, `uniqlo:E481994`, `uniqlo:E482006`, `uniqlo:E482008`, `uniqlo:E482009`, `uniqlo:E482015`, `uniqlo:E482148`, `uniqlo:E482154`, `uniqlo:E482172`, `uniqlo:E482181`, `uniqlo:E482184`, `uniqlo:E482189`

`uniqlo:E482194`, `uniqlo:E482198`, `uniqlo:E482201`, `uniqlo:E482202`, `uniqlo:E482204`, `uniqlo:E482243`, `uniqlo:E482259`, `uniqlo:E482260`, `uniqlo:E482268`, `uniqlo:E482279`, `uniqlo:E482280`, `uniqlo:E482281`, `uniqlo:E482286`, `uniqlo:E482299`, `uniqlo:E482303`, `uniqlo:E482304`, `uniqlo:E482305`, `uniqlo:E482306`

`uniqlo:E482321`, `uniqlo:E482328`, `uniqlo:E482329`, `uniqlo:E482415`, `uniqlo:E482419`, `uniqlo:E482424`, `uniqlo:E482434`, `uniqlo:E482452`, `uniqlo:E482460`, `uniqlo:E482461`, `uniqlo:E482479`, `uniqlo:E482480`, `uniqlo:E482481`, `uniqlo:E482483`, `uniqlo:E482497`, `uniqlo:E482498`, `uniqlo:E482502`, `uniqlo:E482514`

`uniqlo:E482522`, `uniqlo:E482538`, `uniqlo:E482556`, `uniqlo:E482557`, `uniqlo:E482558`, `uniqlo:E482563`, `uniqlo:E482565`, `uniqlo:E482567`, `uniqlo:E482569`, `uniqlo:E482581`, `uniqlo:E482591`, `uniqlo:E482593`, `uniqlo:E482606`, `uniqlo:E482638`, `uniqlo:E482646`, `uniqlo:E482652`, `uniqlo:E482658`, `uniqlo:E482659`

`uniqlo:E482697`, `uniqlo:E482701`, `uniqlo:E482703`, `uniqlo:E482722`, `uniqlo:E482727`, `uniqlo:E482729`, `uniqlo:E482730`, `uniqlo:E482732`, `uniqlo:E482751`, `uniqlo:E482752`, `uniqlo:E482756`, `uniqlo:E482758`, `uniqlo:E482766`, `uniqlo:E482769`, `uniqlo:E482770`, `uniqlo:E482804`, `uniqlo:E482815`, `uniqlo:E482825`

`uniqlo:E482856`, `uniqlo:E482868`, `uniqlo:E482880`, `uniqlo:E482883`, `uniqlo:E482886`, `uniqlo:E482920`, `uniqlo:E482937`, `uniqlo:E482942`, `uniqlo:E482944`, `uniqlo:E482965`, `uniqlo:E482982`, `uniqlo:E482983`, `uniqlo:E483001`, `uniqlo:E483021`, `uniqlo:E483022`, `uniqlo:E483126`, `uniqlo:E483127`, `uniqlo:E483128`

`uniqlo:E483129`, `uniqlo:E483184`, `uniqlo:E483255`, `uniqlo:E483258`, `uniqlo:E483261`, `uniqlo:E483265`, `uniqlo:E483268`, `uniqlo:E483281`, `uniqlo:E483285`, `uniqlo:E483327`, `uniqlo:E483329`, `uniqlo:E483340`, `uniqlo:E483349`, `uniqlo:E483350`, `uniqlo:E483373`, `uniqlo:E483374`, `uniqlo:E483377`, `uniqlo:E483382`

`uniqlo:E483394`, `uniqlo:E483395`, `uniqlo:E483406`, `uniqlo:E483411`, `uniqlo:E483412`, `uniqlo:E483414`, `uniqlo:E483415`, `uniqlo:E483416`, `uniqlo:E483417`, `uniqlo:E483418`, `uniqlo:E483419`, `uniqlo:E483420`, `uniqlo:E483426`, `uniqlo:E483430`, `uniqlo:E483443`, `uniqlo:E483461`, `uniqlo:E483479`, `uniqlo:E483502`

`uniqlo:E483512`, `uniqlo:E483535`, `uniqlo:E483536`, `uniqlo:E483546`, `uniqlo:E483556`, `uniqlo:E483564`, `uniqlo:E483660`, `uniqlo:E483662`, `uniqlo:E483665`, `uniqlo:E483670`, `uniqlo:E483671`, `uniqlo:E483673`, `uniqlo:E483674`, `uniqlo:E483675`, `uniqlo:E483676`, `uniqlo:E483677`, `uniqlo:E483678`, `uniqlo:E483680`

`uniqlo:E483681`, `uniqlo:E483682`, `uniqlo:E483683`, `uniqlo:E483686`, `uniqlo:E483707`, `uniqlo:E483708`, `uniqlo:E483732`, `uniqlo:E483807`, `uniqlo:E483869`, `uniqlo:E483872`, `uniqlo:E483875`, `uniqlo:E483880`, `uniqlo:E483881`, `uniqlo:E483890`, `uniqlo:E483896`, `uniqlo:E483903`, `uniqlo:E483912`, `uniqlo:E483913`

`uniqlo:E483924`, `uniqlo:E483970`, `uniqlo:E483972`, `uniqlo:E483975`, `uniqlo:E483986`, `uniqlo:E483999`, `uniqlo:E484064`, `uniqlo:E484066`, `uniqlo:E484075`, `uniqlo:E484080`, `uniqlo:E484121`, `uniqlo:E484209`, `uniqlo:E484212`, `uniqlo:E484214`, `uniqlo:E484217`, `uniqlo:E484218`, `uniqlo:E484219`, `uniqlo:E484220`

`uniqlo:E484226`, `uniqlo:E484228`, `uniqlo:E484240`, `uniqlo:E484244`, `uniqlo:E484245`, `uniqlo:E484249`, `uniqlo:E484256`, `uniqlo:E484260`, `uniqlo:E484287`, `uniqlo:E484289`, `uniqlo:E484330`, `uniqlo:E484398`, `uniqlo:E484418`, `uniqlo:E484421`, `uniqlo:E484425`, `uniqlo:E484457`, `uniqlo:E484472`, `uniqlo:E484473`

`uniqlo:E484474`, `uniqlo:E484475`, `uniqlo:E484476`, `uniqlo:E484477`, `uniqlo:E484478`, `uniqlo:E484479`, `uniqlo:E484480`, `uniqlo:E484481`, `uniqlo:E484482`, `uniqlo:E484498`, `uniqlo:E484500`, `uniqlo:E484501`, `uniqlo:E484502`, `uniqlo:E484508`, `uniqlo:E484598`, `uniqlo:E484607`, `uniqlo:E484610`, `uniqlo:E484664`

`uniqlo:E484705`, `uniqlo:E484717`, `uniqlo:E484719`, `uniqlo:E484758`, `uniqlo:E484759`, `uniqlo:E484765`, `uniqlo:E484766`, `uniqlo:E484776`, `uniqlo:E484777`, `uniqlo:E484783`, `uniqlo:E484784`, `uniqlo:E484792`, `uniqlo:E484807`, `uniqlo:E484830`, `uniqlo:E484848`, `uniqlo:E484849`, `uniqlo:E484854`, `uniqlo:E484860`

`uniqlo:E484875`, `uniqlo:E484876`, `uniqlo:E484904`, `uniqlo:E484905`, `uniqlo:E484920`, `uniqlo:E484924`, `uniqlo:E484928`, `uniqlo:E484932`, `uniqlo:E484934`, `uniqlo:E484935`, `uniqlo:E484937`, `uniqlo:E484938`, `uniqlo:E484939`, `uniqlo:E484940`, `uniqlo:E484992`, `uniqlo:E484993`, `uniqlo:E484996`, `uniqlo:E484997`

`uniqlo:E485005`, `uniqlo:E485035`, `uniqlo:E485036`, `uniqlo:E485037`, `uniqlo:E485053`, `uniqlo:E485054`, `uniqlo:E485058`, `uniqlo:E485059`, `uniqlo:E485062`, `uniqlo:E485064`, `uniqlo:E485067`, `uniqlo:E485069`, `uniqlo:E485071`, `uniqlo:E485143`, `uniqlo:E485162`, `uniqlo:E485207`, `uniqlo:E485208`, `uniqlo:E485224`

`uniqlo:E485251`, `uniqlo:E485265`, `uniqlo:E485306`, `uniqlo:E485307`, `uniqlo:E485308`, `uniqlo:E485310`, `uniqlo:E485312`, `uniqlo:E485318`, `uniqlo:E485321`, `uniqlo:E485322`, `uniqlo:E485329`, `uniqlo:E485340`, `uniqlo:E485347`, `uniqlo:E485359`, `uniqlo:E485369`, `uniqlo:E485389`, `uniqlo:E485393`, `uniqlo:E485394`

`uniqlo:E485396`, `uniqlo:E485397`, `uniqlo:E485398`, `uniqlo:E485400`, `uniqlo:E485403`, `uniqlo:E485408`, `uniqlo:E485411`, `uniqlo:E485416`, `uniqlo:E485435`, `uniqlo:E485454`, `uniqlo:E485480`, `uniqlo:E485481`, `uniqlo:E485482`, `uniqlo:E485495`, `uniqlo:E485530`, `uniqlo:E485558`, `uniqlo:E485564`, `uniqlo:E485565`

`uniqlo:E485566`, `uniqlo:E485567`, `uniqlo:E485568`, `uniqlo:E485584`, `uniqlo:E485593`, `uniqlo:E485610`, `uniqlo:E485612`, `uniqlo:E485616`, `uniqlo:E485642`, `uniqlo:E485647`, `uniqlo:E485653`, `uniqlo:E485679`, `uniqlo:E485709`, `uniqlo:E485710`, `uniqlo:E485711`, `uniqlo:E485717`, `uniqlo:E485735`, `uniqlo:E485737`

`uniqlo:E485739`, `uniqlo:E485744`, `uniqlo:E485745`, `uniqlo:E485778`, `uniqlo:E485782`, `uniqlo:E485791`, `uniqlo:E485803`, `uniqlo:E485808`, `uniqlo:E486042`, `uniqlo:E486066`, `uniqlo:E486071`, `uniqlo:E486074`, `uniqlo:E486080`, `uniqlo:E486095`, `uniqlo:E486103`, `uniqlo:E486107`, `uniqlo:E486117`, `uniqlo:E486119`

`uniqlo:E486120`, `uniqlo:E486121`, `uniqlo:E486129`, `uniqlo:E486159`, `uniqlo:E486167`, `uniqlo:E486171`, `uniqlo:E486176`, `uniqlo:E486184`, `uniqlo:E486186`, `uniqlo:E486191`, `uniqlo:E486194`, `uniqlo:E486196`, `uniqlo:E486199`, `uniqlo:E486220`, `uniqlo:E486295`, `uniqlo:E486317`, `uniqlo:E486320`, `uniqlo:E486335`

`uniqlo:E486336`, `uniqlo:E486367`, `uniqlo:E486378`, `uniqlo:E486380`, `uniqlo:E486411`, `uniqlo:E486412`, `uniqlo:E486416`, `uniqlo:E486417`, `uniqlo:E486423`, `uniqlo:E486424`, `uniqlo:E486425`, `uniqlo:E486426`, `uniqlo:E486427`, `uniqlo:E486428`, `uniqlo:E486443`, `uniqlo:E486444`, `uniqlo:E486468`, `uniqlo:E486471`

`uniqlo:E486499`, `uniqlo:E486501`, `uniqlo:E486503`, `uniqlo:E486507`, `uniqlo:E486511`, `uniqlo:E486562`, `uniqlo:E486565`, `uniqlo:E486566`, `uniqlo:E486568`, `uniqlo:E486578`, `uniqlo:E486585`, `uniqlo:E486586`, `uniqlo:E486587`, `uniqlo:E486588`, `uniqlo:E486590`, `uniqlo:E486591`, `uniqlo:E486594`, `uniqlo:E486595`

`uniqlo:E486596`, `uniqlo:E486597`, `uniqlo:E486598`, `uniqlo:E486600`, `uniqlo:E486602`, `uniqlo:E486604`, `uniqlo:E486612`, `uniqlo:E486614`, `uniqlo:E486615`, `uniqlo:E486622`, `uniqlo:E486630`, `uniqlo:E486637`, `uniqlo:E486638`, `uniqlo:E486651`, `uniqlo:E486658`, `uniqlo:E486660`, `uniqlo:E486675`, `uniqlo:E486682`

`uniqlo:E486683`, `uniqlo:E486684`, `uniqlo:E486691`, `uniqlo:E486695`, `uniqlo:E486696`, `uniqlo:E486697`, `uniqlo:E486699`, `uniqlo:E486701`, `uniqlo:E486703`, `uniqlo:E486704`, `uniqlo:E486706`, `uniqlo:E486718`, `uniqlo:E486722`, `uniqlo:E486723`, `uniqlo:E486724`, `uniqlo:E486725`, `uniqlo:E486726`, `uniqlo:E486729`

`uniqlo:E486734`, `uniqlo:E486736`, `uniqlo:E486738`, `uniqlo:E486739`, `uniqlo:E486743`, `uniqlo:E486746`, `uniqlo:E486747`, `uniqlo:E486755`, `uniqlo:E486819`, `uniqlo:E486834`, `uniqlo:E486866`, `uniqlo:E486868`, `uniqlo:E486871`, `uniqlo:E486875`, `uniqlo:E486897`, `uniqlo:E486910`, `uniqlo:E486916`, `uniqlo:E486982`

`uniqlo:E486984`, `uniqlo:E486992`, `uniqlo:E486994`, `uniqlo:E487001`, `uniqlo:E487005`, `uniqlo:E487016`, `uniqlo:E487024`, `uniqlo:E487026`, `uniqlo:E487028`, `uniqlo:E487030`, `uniqlo:E487032`, `uniqlo:E487034`, `uniqlo:E487036`, `uniqlo:E487038`, `uniqlo:E487040`, `uniqlo:E487042`, `uniqlo:E487044`, `uniqlo:E487046`

`uniqlo:E487048`, `uniqlo:E487050`, `uniqlo:E487052`, `uniqlo:E487054`, `uniqlo:E487058`, `uniqlo:E487060`, `uniqlo:E487064`, `uniqlo:E487066`, `uniqlo:E487070`, `uniqlo:E487072`, `uniqlo:E487074`, `uniqlo:E487093`, `uniqlo:E487096`, `uniqlo:E487118`, `uniqlo:E487119`, `uniqlo:E487120`, `uniqlo:E487121`, `uniqlo:E487124`

`uniqlo:E487125`, `uniqlo:E487127`, `uniqlo:E487128`, `uniqlo:E487133`, `uniqlo:E487136`, `uniqlo:E487141`, `uniqlo:E487144`, `uniqlo:E487149`, `uniqlo:E487152`, `uniqlo:E487153`, `uniqlo:E487201`, `uniqlo:E487206`, `uniqlo:E487209`, `uniqlo:E487216`, `uniqlo:E487220`, `uniqlo:E487261`, `uniqlo:E487263`, `uniqlo:E487272`

`uniqlo:E487273`, `uniqlo:E487277`, `uniqlo:E487278`, `uniqlo:E487286`, `uniqlo:E487303`, `uniqlo:E487337`, `uniqlo:E487338`, `uniqlo:E487339`, `uniqlo:E487340`, `uniqlo:E487345`, `uniqlo:E487348`, `uniqlo:E487375`, `uniqlo:E487394`, `uniqlo:E487395`, `uniqlo:E487396`, `uniqlo:E487404`, `uniqlo:E487408`, `uniqlo:E487420`

`uniqlo:E487462`, `uniqlo:E487465`, `uniqlo:E487466`, `uniqlo:E487516`, `uniqlo:E487517`, `uniqlo:E487518`, `uniqlo:E487526`, `uniqlo:E487528`, `uniqlo:E487538`, `uniqlo:E487579`, `uniqlo:E487585`, `uniqlo:E487589`, `uniqlo:E487630`, `uniqlo:E487688`, `uniqlo:E487689`, `uniqlo:E487742`, `uniqlo:E487751`, `uniqlo:E487806`

`uniqlo:E487819`, `uniqlo:E487832`, `uniqlo:E487846`, `uniqlo:E487891`, `uniqlo:E487898`, `uniqlo:E487899`, `uniqlo:E487908`, `uniqlo:E487909`, `uniqlo:E487939`, `uniqlo:E487942`, `uniqlo:E487950`, `uniqlo:E487957`, `uniqlo:E487959`, `uniqlo:E487962`, `uniqlo:E487978`, `uniqlo:E487989`, `uniqlo:E487995`, `uniqlo:E487996`

`uniqlo:E488005`, `uniqlo:E488006`, `uniqlo:E488007`, `uniqlo:E488008`, `uniqlo:E488010`, `uniqlo:E488014`, `uniqlo:E488035`, `uniqlo:E488037`, `uniqlo:E488038`, `uniqlo:E488041`, `uniqlo:E488044`, `uniqlo:E488045`, `uniqlo:E488046`, `uniqlo:E488047`, `uniqlo:E488071`, `uniqlo:E488072`, `uniqlo:E488087`, `uniqlo:E488088`

`uniqlo:E488089`, `uniqlo:E488091`, `uniqlo:E488093`, `uniqlo:E488094`, `uniqlo:E488096`, `uniqlo:E488105`, `uniqlo:E488106`, `uniqlo:E488145`, `uniqlo:E488157`, `uniqlo:E488163`, `uniqlo:E488167`, `uniqlo:E488168`, `uniqlo:E488171`, `uniqlo:E488172`, `uniqlo:E488173`, `uniqlo:E488174`, `uniqlo:E488193`, `uniqlo:E488200`

`uniqlo:E488202`, `uniqlo:E488203`, `uniqlo:E488204`, `uniqlo:E488206`, `uniqlo:E488209`, `uniqlo:E488210`, `uniqlo:E488216`, `uniqlo:E488239`, `uniqlo:E488246`, `uniqlo:E488247`, `uniqlo:E488248`, `uniqlo:E488269`, `uniqlo:E488270`, `uniqlo:E488280`, `uniqlo:E488298`, `uniqlo:E488304`, `uniqlo:E488305`, `uniqlo:E488306`

`uniqlo:E488307`, `uniqlo:E488309`, `uniqlo:E488333`, `uniqlo:E488357`, `uniqlo:E488358`, `uniqlo:E488359`, `uniqlo:E488364`, `uniqlo:E488371`, `uniqlo:E488397`, `uniqlo:E488426`, `uniqlo:E488448`, `uniqlo:E488520`, `uniqlo:E488522`, `uniqlo:E488559`, `uniqlo:E488560`, `uniqlo:E488572`, `uniqlo:E488580`, `uniqlo:E488630`

`uniqlo:E488642`, `uniqlo:E488643`, `uniqlo:E488648`, `uniqlo:E488649`, `uniqlo:E488650`, `uniqlo:E488651`, `uniqlo:E488652`, `uniqlo:E488668`, `uniqlo:E488684`, `uniqlo:E488694`, `uniqlo:E488700`, `uniqlo:E488722`, `uniqlo:E488726`, `uniqlo:E488729`, `uniqlo:E488738`, `uniqlo:E488739`, `uniqlo:E488743`, `uniqlo:E488762`

`uniqlo:E488777`, `uniqlo:E488785`, `uniqlo:E488787`, `uniqlo:E488789`, `uniqlo:E488790`, `uniqlo:E488793`, `uniqlo:E488794`, `uniqlo:E488795`, `uniqlo:E488796`, `uniqlo:E488797`, `uniqlo:E488798`, `uniqlo:E488814`, `uniqlo:E488816`, `uniqlo:E488826`, `uniqlo:E488827`, `uniqlo:E488828`, `uniqlo:E488829`, `uniqlo:E488858`

`uniqlo:E488859`, `uniqlo:E488860`, `uniqlo:E488861`, `uniqlo:E488866`, `uniqlo:E488884`, `uniqlo:E488901`, `uniqlo:E488902`, `uniqlo:E488903`, `uniqlo:E488922`, `uniqlo:E488923`, `uniqlo:E488925`, `uniqlo:E488926`, `uniqlo:E488927`, `uniqlo:E488928`, `uniqlo:E488929`, `uniqlo:E488934`, `uniqlo:E488936`, `uniqlo:E488939`

`uniqlo:E488947`, `uniqlo:E488957`, `uniqlo:E488958`, `uniqlo:E488960`, `uniqlo:E488961`, `uniqlo:E488962`, `uniqlo:E488976`, `uniqlo:E488977`, `uniqlo:E488997`, `uniqlo:E489012`, `uniqlo:E489013`, `uniqlo:E489021`, `uniqlo:E489025`, `uniqlo:E489026`, `uniqlo:E489044`, `uniqlo:E489045`, `uniqlo:E489049`, `uniqlo:E489058`

`uniqlo:E489063`, `uniqlo:E489065`, `uniqlo:E489070`, `uniqlo:E489071`, `uniqlo:E489072`, `uniqlo:E489074`, `uniqlo:E489075`, `uniqlo:E489076`, `uniqlo:E489085`, `uniqlo:E489110`, `uniqlo:E489125`, `uniqlo:E489136`, `uniqlo:E489138`, `uniqlo:E489152`, `uniqlo:E489153`, `uniqlo:E489154`, `uniqlo:E489155`, `uniqlo:E489156`

`uniqlo:E489157`, `uniqlo:E489158`, `uniqlo:E489159`, `uniqlo:E489160`, `uniqlo:E489168`, `uniqlo:E489169`, `uniqlo:E489170`, `uniqlo:E489171`, `uniqlo:E489176`, `uniqlo:E489180`, `uniqlo:E489191`, `uniqlo:E489216`, `uniqlo:E489217`, `uniqlo:E489227`, `uniqlo:E489229`, `uniqlo:E489230`, `uniqlo:E489247`, `uniqlo:E489257`

`uniqlo:E489258`, `uniqlo:E489259`, `uniqlo:E489367`, `uniqlo:E489372`, `uniqlo:E489386`, `uniqlo:E489387`, `uniqlo:E489389`, `uniqlo:E489392`, `uniqlo:E489393`, `uniqlo:E489394`, `uniqlo:E489395`, `uniqlo:E489398`, `uniqlo:E489399`, `uniqlo:E489406`, `uniqlo:E489407`, `uniqlo:E489408`, `uniqlo:E489409`, `uniqlo:E489412`

`uniqlo:E489413`, `uniqlo:E489414`, `uniqlo:E489415`, `uniqlo:E489417`, `uniqlo:E489427`, `uniqlo:E489483`, `uniqlo:E489508`, `uniqlo:E489509`, `uniqlo:E489526`, `uniqlo:E489530`, `uniqlo:E489551`, `uniqlo:E489552`, `uniqlo:E489563`, `uniqlo:E489565`, `uniqlo:E489682`, `uniqlo:E489908`, `uniqlo:E489909`, `uniqlo:E489910`

`uniqlo:E489911`, `uniqlo:E489912`, `uniqlo:E489913`, `uniqlo:E489914`, `uniqlo:E489915`, `uniqlo:E489916`, `uniqlo:E490277`, `uniqlo:E490278`, `uniqlo:E490279`, `uniqlo:E490285`, `uniqlo:E490470`, `uniqlo:E490697`, `uniqlo:E491000`, `uniqlo:E491001`, `uniqlo:E491002`, `uniqlo:E491086`, `uniqlo:E491096`, `uniqlo:E491104`

`uniqlo:E491115`, `uniqlo:E491116`, `uniqlo:E491119`, `uniqlo:E491142`, `uniqlo:E491143`, `uniqlo:E491181`, `uniqlo:E491209`, `uniqlo:E491210`, `uniqlo:E491211`, `uniqlo:E491212`, `uniqlo:E491213`, `uniqlo:E491231`, `uniqlo:E491232`, `uniqlo:E491233`, `uniqlo:E491279`, `uniqlo:E491280`, `uniqlo:E491281`, `uniqlo:E491282`

`uniqlo:E491283`, `uniqlo:E491284`, `uniqlo:E491285`, `uniqlo:E491287`, `uniqlo:E491288`, `uniqlo:E491289`, `uniqlo:E491294`, `uniqlo:E491297`, `uniqlo:E491320`, `uniqlo:E491380`, `uniqlo:E491602`, `uniqlo:E491779`, `uniqlo:E491888`, `uniqlo:E491889`, `uniqlo:E491988`, `uniqlo:E491991`, `uniqlo:E492040`, `uniqlo:E492081`

`uniqlo:E492123`, `uniqlo:E492199`, `uniqlo:E492200`, `uniqlo:E492318`, `uniqlo:E492365`, `uniqlo:E492538`, `uniqlo:E492881`, `uniqlo:E493044`, `uniqlo:E493045`, `uniqlo:E493046`

**zara (18)**

`zara:545406831`, `zara:545427337`, `zara:545428239`, `zara:545439169`, `zara:545483281`, `zara:547003473`, `zara:547276687`, `zara:548577264`, `zara:552163213`, `zara:554006103`, `zara:554764120`, `zara:555161842`, `zara:555162424`, `zara:556139700`, `zara:560347128`, `zara:561264931`, `zara:561568002`, `zara:562814885`

</details>

Machine-readable 전수 근거는 [FitMatchClassificationGlobalBaseline-20260825.jsonl](./FitMatchClassificationGlobalBaseline-20260825.jsonl)의 `current.tuple_valid`, `current.invalid_reasons`, `current.stale_history`, `current.stale_reasons`다.

## 6. mapping conflict 목록

Mapping 위험 reason 분포:

| 값 | 건수 |
| --- | --- |
| category_only_missing_product_axis_or_detail | 1347 |
| invalid_semantic_tuple | 238 |
| product_decision_conflict | 182 |
| product_level_resolution_required | 1 |

Mapping/product conflict dimension 분포:

| 값 | 건수 |
| --- | --- |
| detail | 148 |
| garment_type | 103 |
| comparison_family | 85 |
| length | 84 |
| category | 63 |
| body_length | 7 |

+<details>
<summary>동일 active mapping identity의 observed product-decision mixed bucket 전수 59개</summary>

- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001001|UNKNOWN|상의 > 반소매 티셔츠` — products=2; non_null_families=tshirt; missing=true; tuples=tops/short_sleeve/tshirt/short_sleeve || ∅/∅/∅/∅; ids=6418260,6562698
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100097|KIDS|이너웨어 > 히트텍 > 긴팔` — products=3; non_null_families=tshirt,underwear; missing=false; tuples=tops/long_sleeve/tshirt/long_sleeve || underwear/underwear/underwear/unknown; ids=E470362,E478628,E478634
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100098|KIDS|이너웨어 > 히트텍 > 히트텍 엑스트라 웜` — products=2; non_null_families=tshirt,leggings; missing=false; tuples=tops/long_sleeve/tshirt/long_sleeve || leggings/long_leggings/leggings/long_sleeve; ids=E485359,E485369
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102253|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 후드` — products=3; non_null_families=outerwear; missing=true; tuples=∅/∅/∅/∅ || outerwear/jumper/outerwear/unknown; ids=E471808,E485735,E486119
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102687|MEN|니트 & 가디건 > 니트 > GU` — products=2; non_null_families=tshirt,knit_cardigan; missing=false; tuples=tops/polo_shirt/tshirt/short_sleeve || tops/knit_top/knit_cardigan/short_sleeve; ids=E486746,E486747
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105253|KIDS|아우터 > 재킷 & 파카 > 후리스` — products=2; non_null_families=outerwear; missing=true; tuples=∅/∅/∅/∅ || outerwear/fleece/outerwear/unknown; ids=E478168,E486660
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105313|BABY|영유아(6개월~5세) > 아우터 > 후리스` — products=2; non_null_families=outerwear; missing=true; tuples=outerwear/fleece/outerwear/unknown || ∅/∅/∅/∅; ids=E486443,E486444
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112643|MEN|스포츠 유틸리티 웨어 > 팬츠 > 울트라 스트레치 팬츠` — products=2; non_null_families=pants; missing=false; tuples=bottoms/long_pants/pants/long_sleeve || bottoms/shorts/pants/short_sleeve; ids=E465491,E475386
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116871|WOMEN|리넨 > 팬츠 > 팬츠` — products=2; non_null_families=pants; missing=false; tuples=bottoms/shorts/pants/short_sleeve || bottoms/long_pants/pants/long_sleeve; ids=E473696,E483903
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|118977|MEN|이너웨어 > 언더웨어 > 코튼 브리프` — products=10; non_null_families=underwear; missing=true; tuples=underwear/men_briefs/underwear/unknown || ∅/∅/∅/∅; ids=E464311,E476320,E479497,E479502,E482598,E482600,E486875,E486877,E487650,E489055
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123531|MEN|팬츠 > 진(청바지) > 스트레이트` — products=7; non_null_families=denim; missing=true; tuples=∅/∅/∅/∅ || bottoms/long_pants/denim/long_sleeve; ids=E479816,E485737,E487206,E487742,E488684,E492365,E492538
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124368|WOMEN|이너웨어 > 언더웨어 > 소프트 모달` — products=4; non_null_families=underwear; missing=true; tuples=underwear/underwear/underwear/unknown || ∅/∅/∅/∅; ids=E482697,E482701,E482703,E485541
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124445|MEN|GU > 상의 > 티셔츠` — products=2; non_null_families=tshirt; missing=true; tuples=∅/∅/∅/∅ || tops/long_sleeve/tshirt/long_sleeve; ids=E486739,E486743
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124450|MEN|GU > 팬츠 > 팬츠` — products=4; non_null_families=pants; missing=false; tuples=bottoms/long_pants/pants/long_sleeve || bottoms/shorts/pants/short_sleeve; ids=E478702,E486723,E486724,E486726
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128388|WOMEN|니트 & 가디건 > 가디건 > 그 외` — products=5; non_null_families=knit_cardigan; missing=false; tuples=outerwear/cardigan/knit_cardigan/unknown || outerwear/cardigan/knit_cardigan/short_sleeve; ids=E484939,E485340,E485717,E487001,E491991
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|134044|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon` — products=4; non_null_families=tshirt; missing=true; tuples=tops/short_sleeve/tshirt/short_sleeve || ∅/∅/∅/∅; ids=E483670,E483671,E483673,E483674
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135282|WOMEN|니트 & 가디건 > 가디건 > 스무드 코튼` — products=3; non_null_families=knit_cardigan; missing=false; tuples=outerwear/cardigan/knit_cardigan/unknown || outerwear/cardigan/knit_cardigan/long_sleeve; ids=E487005,E491115,E491602
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136135|KIDS|티셔츠 & UT > 그래픽티셔츠 > mofusand` — products=6; non_null_families=tshirt; missing=true; tuples=∅/∅/∅/∅ || tops/short_sleeve/tshirt/short_sleeve; ids=E483373,E483374,E488827,E489257,E489258,E489259
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|140590|KIDS|티셔츠 & UT > 그래픽티셔츠 > Monchhichi` — products=6; non_null_families=tshirt; missing=true; tuples=∅/∅/∅/∅ || tops/short_sleeve/tshirt/short_sleeve; ids=E488936,E489412,E489413,E489414,E491282,E491283
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144584|KIDS|티셔츠 & UT > 그래픽티셔츠 > MARIO KART WORLD` — products=8; non_null_families=hoodie,tshirt; missing=false; tuples=tops/hoodie/hoodie/unknown || tops/short_sleeve/tshirt/short_sleeve; ids=E488193,E488309,E491231,E491232,E491233,E491287,E491288,E491289
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146107|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Jason Polan` — products=7; non_null_families=sweatshirt; missing=true; tuples=∅/∅/∅/∅ || tops/sweatshirt/sweatshirt/unknown; ids=E484260,E489152,E489153,E489154,E491000,E491001,E491002
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146992|KIDS|티셔츠 & UT > 그래픽티셔츠 > CHIIKAWA` — products=7; non_null_families=tshirt,sweatshirt; missing=true; tuples=tops/short_sleeve/tshirt/short_sleeve || tops/sweatshirt/sweatshirt/unknown || ∅/∅/∅/∅; ids=E485530,E487272,E491279,E491280,E491281,E491284,E491285
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146993|WOMEN|티셔츠 & UT > 그래픽티셔츠 > CHIIKAWA` — products=7; non_null_families=sweatshirt; missing=true; tuples=∅/∅/∅/∅ || tops/sweatshirt/sweatshirt/unknown; ids=E483261,E488041,E491209,E491210,E491211,E491212,E491213
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58125|WOMEN|아우터 > 재킷 & 코트 > 캐주얼 재킷` — products=3; non_null_families=outerwear; missing=false; tuples=outerwear/padding/outerwear/unknown || outerwear/blouson/outerwear/unknown; ids=E487518,E487846,E489026
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58130|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 퍼프테크` — products=5; non_null_families=outerwear; missing=true; tuples=outerwear/padding/outerwear/unknown || ∅/∅/∅/∅; ids=E469863,E469871,E479751,E487404,E492040
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58142|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 긴팔` — products=7; non_null_families=tshirt,knit_cardigan; missing=false; tuples=tops/long_sleeve/tshirt/long_sleeve || tops/knit_top/knit_cardigan/unknown; ids=E465751,E470143,E483536,E487579,E487908,E488298,E489372
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58144|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 반팔` — products=14; non_null_families=tshirt; missing=true; tuples=tops/short_sleeve/tshirt/short_sleeve || ∅/∅/∅/∅; ids=E424873,E465755,E465760,E480054,E483268,E483461,E483463,E483535,E484418,E484421,E484457,E487277,E487819,E488087
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58193|WOMEN|팬츠 > 와이드 팬츠 > 유틸리티(커브ㆍ카고)` — products=4; non_null_families=pants; missing=true; tuples=bottoms/long_pants/pants/long_sleeve || ∅/∅/∅/∅; ids=E475344,E477345,E488202,E489191
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58243|WOMEN|원피스 & 스커트 > 원피스 > 슬리브리스 원피스` — products=7; non_null_families=dress; missing=true; tuples=dresses/one_piece/dress/sleeveless || ∅/∅/∅/∅; ids=E482982,E482983,E483564,E484026,E487278,E487286,E488216
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58245|WOMEN|원피스 & 스커트 > 스커트 > 롱 (맥시)` — products=2; non_null_families=skirt; missing=false; tuples=skirts/skirt/skirt/unknown || skirts/skirt/skirt/long_sleeve; ids=E487995,E488934
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58247|WOMEN|원피스 & 스커트 > 스커트 > 플레어` — products=3; non_null_families=skirt; missing=false; tuples=skirts/skirt/skirt/long_sleeve || skirts/skirt/skirt/unknown; ids=E482286,E484705,E488089
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58306|WOMEN|이너웨어 > 브라탑 > 코튼` — products=6; non_null_families=underwear; missing=false; tuples=underwear/women_bra/underwear/unknown || underwear/women_camisole/underwear/unknown; ids=E482194,E482198,E482201,E482329,E484830,E485558
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58334|WOMEN|파자마 & 홈웨어 > 파자마 > 그 외` — products=2; non_null_families=underwear,knit_cardigan; missing=false; tuples=homewear/loungewear/underwear/unknown || outerwear/cardigan/knit_cardigan/unknown; ids=E461767,E488014
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58335|WOMEN|파자마 & 홈웨어 > 라운지 팬츠 > 이지 팬츠` — products=5; non_null_families=underwear,pants; missing=true; tuples=∅/∅/∅/∅ || homewear/loungewear/underwear/unknown || bottoms/long_pants/pants/long_sleeve; ids=E484605,E486317,E487589,E488167,E488168
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58389|MEN|아우터 > 경량 패딩 (PUFFTECH) > 그 외` — products=2; non_null_families=outerwear; missing=true; tuples=outerwear/padding/outerwear/unknown || ∅/∅/∅/∅; ids=E489110,E491988
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58390|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 에어리즘 코튼` — products=5; non_null_families=tshirt; missing=false; tuples=tops/sleeveless/tshirt/sleeveless || tops/short_sleeve/tshirt/short_sleeve || tops/long_sleeve/tshirt/long_sleeve; ids=E457517,E465185,E465193,E484508,E486103
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58460|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 스웨트` — products=5; non_null_families=pants; missing=false; tuples=bottoms/long_pants/pants/long_sleeve || bottoms/shorts/pants/short_sleeve; ids=E471809,E473715,E482758,E486120,E486121
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58531|MEN|이너웨어 > 언더웨어 > 코튼 트렁크` — products=10; non_null_families=underwear; missing=true; tuples=underwear/men_trunks/underwear/unknown || ∅/∅/∅/∅; ids=E439661,E479487,E479488,E482591,E482593,E486866,E486868,E486871,E488929,E489021
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58584|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 긴팔` — products=5; non_null_families=tshirt; missing=true; tuples=tops/long_sleeve/tshirt/long_sleeve || ∅/∅/∅/∅; ids=E486651,E486658,E486992,E486994,E488762
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58587|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 에어리즘 코튼` — products=2; non_null_families=tshirt; missing=false; tuples=tops/short_sleeve/tshirt/short_sleeve || tops/long_sleeve/tshirt/long_sleeve; ids=E474592,E474832
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58611|KIDS|원피스 & 스커트 > 원피스 > 슬리브리스` — products=3; non_null_families=dress; missing=true; tuples=∅/∅/∅/∅ || dresses/one_piece/dress/sleeveless; ids=E483340,E488976,E489063
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58651|KIDS|이너웨어 > 언더웨어 > 쇼츠` — products=4; non_null_families=underwear; missing=false; tuples=underwear/underwear/underwear/unknown || underwear/women_panty/underwear/unknown; ids=E482008,E482009,E482015,E485435
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58691|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 쇼트팬츠` — products=2; non_null_families=pants,skirt; missing=false; tuples=bottoms/shorts/pants/short_sleeve || skirts/skirt/skirt/short_sleeve; ids=E481788,E481791
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58715|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 크롭레깅스` — products=3; non_null_families=leggings; missing=true; tuples=leggings/three_quarter_leggings/leggings/three_quarter || ∅/∅/∅/∅; ids=E481779,E481780,E481782
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58716|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 쇼트팬츠` — products=4; non_null_families=pants; missing=true; tuples=bottoms/shorts/pants/short_sleeve || ∅/∅/∅/∅; ids=E481786,E481787,E481790,E485322
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58721|BABY|영유아(6개월~5세) > 홈웨어 & 파자마 > 긴팔` — products=12; non_null_families=underwear; missing=true; tuples=homewear/loungewear/underwear/unknown || ∅/∅/∅/∅; ids=E486425,E486426,E486427,E486428,E486448,E486449,E486450,E486451,E488642,E488643,E489540,E489541
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94359|WOMEN|파자마 & 홈웨어 > 라운지 팬츠 > 앵클 팬츠` — products=2; non_null_families=underwear,pants; missing=false; tuples=homewear/loungewear/underwear/unknown || bottoms/long_pants/pants/long_sleeve; ids=E482243,E483896
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95364|WOMEN|니트 & 가디건 > 니트 > 반팔 니트` — products=5; non_null_families=knit_cardigan; missing=true; tuples=tops/knit_top/knit_cardigan/short_sleeve || ∅/∅/∅/∅ || outerwear/cardigan/knit_cardigan/short_sleeve; ids=E469409,E484075,E485306,E485307,E488333
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95365|WOMEN|니트 & 가디건 > 니트 > 긴팔 니트` — products=6; non_null_families=knit_cardigan; missing=false; tuples=tops/knit_top/knit_cardigan/unknown || outerwear/cardigan/knit_cardigan/long_sleeve || tops/knit_top/knit_cardigan/long_sleeve; ids=E469410,E475053,E481731,E485310,E488210,E491086
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95381|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 긴팔` — products=18; non_null_families=shirt; missing=false; tuples=tops/blouse/shirt/long_sleeve || tops/shirt/shirt/long_sleeve; ids=E487526,E488206,E488520,E488522,E488559,E488560,E489227,E489406,E489407,E489408,E489409,E489427,E489508,E489509,E491294,E491297,E491380,E492123
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95383|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 반팔` — products=3; non_null_families=shirt; missing=false; tuples=tops/blouse/shirt/short_sleeve || tops/shirt/shirt/short_sleeve; ids=E483881,E484849,E488448
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95385|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 레이온` — products=7; non_null_families=shirt; missing=false; tuples=tops/blouse/shirt/unknown || tops/blouse/shirt/three_quarter || tops/blouse/shirt/short_sleeve; ids=E479071,E482825,E483875,E484240,E487528,E489229,E489230
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95386|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 리넨` — products=7; non_null_families=shirt; missing=true; tuples=tops/shirt/shirt/unknown || ∅/∅/∅/∅ || tops/shirt/shirt/three_quarter || tops/blouse/shirt/sleeveless || tops/shirt/shirt/short_sleeve; ids=E475647,E475648,E475649,E483869,E483872,E483890,E484256
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95399|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > GU` — products=3; non_null_families=tshirt,shirt; missing=false; tuples=tops/sleeveless/tshirt/sleeveless || tops/shirt/shirt/unknown || tops/shirt/shirt/short_sleeve; ids=E486696,E486697,E486701
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95407|MEN|니트 & 가디건 > 니트 > 터틀넥` — products=2; non_null_families=knit_cardigan; missing=true; tuples=∅/∅/∅/∅ || tops/knit_top/knit_cardigan/unknown; ids=E450544,E486066
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95439|MEN|셔츠 > 폴로셔츠 (카라티) > 에어리즘 코튼` — products=4; non_null_families=tshirt; missing=false; tuples=tops/polo_shirt/tshirt/short_sleeve || tops/polo_shirt/tshirt/unknown; ids=E465196,E475367,E479724,E482303
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98312|WOMEN|이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드` — products=4; non_null_families=underwear,leggings; missing=false; tuples=underwear/underwear/underwear/unknown || leggings/long_leggings/leggings/long_sleeve; ids=E469765,E471601,E480342,E487201
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98314|WOMEN|이너웨어 > 히트텍 > 히트텍 울트라 웜` — products=2; non_null_families=underwear,leggings; missing=false; tuples=underwear/underwear/underwear/unknown || leggings/long_leggings/leggings/long_sleeve; ids=E478965,E480966
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98376|MEN|라운지 팬츠 > 라운지 팬츠 > 롱 팬츠` — products=7; non_null_families=pants,underwear; missing=false; tuples=bottoms/long_pants/pants/long_sleeve || homewear/loungewear/underwear/unknown; ids=E461420,E478670,E479134,E482259,E484784,E486468,E486471

</details>

<details>
<summary>product decision과 충돌하는 active mapping row 전수 182건</summary>

- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100097|KIDS|이너웨어 > 히트텍 > 긴팔` — products=3, dimensions=garment_type,comparison_family,length,category,detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100098|KIDS|이너웨어 > 히트텍 > 히트텍 엑스트라 웜` — products=2, dimensions=category,detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100100|KIDS|이너웨어 > 히트텍 > 레깅스` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100315|MEN|니트 & 가디건 > 니트 > 긴팔 니트` — products=3, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102253|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 후드` — products=3, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102589|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > UNIQLO and JW ANDERSON` — products=2, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102687|MEN|니트 & 가디건 > 니트 > GU` — products=2, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105468|WOMEN|스포츠 유틸리티 웨어 > 아우터 > 풀집 후디` — products=1, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107786|WOMEN|팬츠 > 진(청바지) > UNIQLO and JW ANDERSON` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107791|MEN|팬츠 > 진(청바지) > GU` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112643|MEN|스포츠 유틸리티 웨어 > 팬츠 > 울트라 스트레치 팬츠` — products=2, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|113378|MEN|팬츠 > 쇼트 팬츠(반바지) > 데님 & 코튼` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114719|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 데님` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114926|MEN|팬츠 > 캐주얼 팬츠 > 울트라 스트레치` — products=4, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|115519|WOMEN|UV Protection > 팬츠 & 레깅스 > 팬츠` — products=3, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116336|WOMEN|니트 & 가디건 > 니트 > 폴로 니트` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116871|WOMEN|리넨 > 팬츠 > 팬츠` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|117033|WOMEN|티셔츠 & UT > 그래픽티셔츠 > 그 외` — products=3, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120173|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > STUDIO GHIBLI` — products=3, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|122475|WOMEN|원피스 & 스커트 > 스커트 > 미니` — products=1, dimensions=body_length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123531|MEN|팬츠 > 진(청바지) > 스트레이트` — products=7, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123533|MEN|이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드` — products=2, dimensions=garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124364|WOMEN|원피스 & 스커트 > 원피스 > GU` — products=1, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124370|MEN|팬츠 > 와이드 팬츠 > GU` — products=1, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124436|WOMEN|GU > 상의 > 스웨트` — products=2, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124440|WOMEN|GU > 원피스 & 스커트 > 스커트` — products=2, dimensions=body_length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124442|WOMEN|GU > 팬츠 > 팬츠` — products=3, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124445|MEN|GU > 상의 > 티셔츠` — products=2, dimensions=category,detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124449|MEN|GU > 팬츠 > 진` — products=1, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124450|MEN|GU > 팬츠 > 팬츠` — products=4, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|126400|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS` — products=12, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|126401|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > PEANUTS` — products=12, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127491|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > NY POP ART` — products=12, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128018|WOMEN|티셔츠 & UT > 그래픽티셔츠 > miffy in bloom` — products=6, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128055|BABY|영유아(6개월~5세) > 그래픽티셔츠 > The Picture Book Collection` — products=4, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128382|WOMEN|니트 & 가디건 > 가디건 > 메리노` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128388|WOMEN|니트 & 가디건 > 가디건 > 그 외` — products=5, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128427|MEN|니트 & 가디건 > 가디건 > 수플레 얀` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|132869|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL ICONS` — products=10, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|134783|BABY|영유아(6개월~5세) > 그래픽티셔츠 > Sanrio characters` — products=3, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135246|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Pokémon` — products=3, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135282|WOMEN|니트 & 가디건 > 가디건 > 스무드 코튼` — products=3, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136135|KIDS|티셔츠 & UT > 그래픽티셔츠 > mofusand` — products=6, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136609|WOMEN|니트 & 가디건 > 가디건 > 브이넥` — products=3, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|140590|KIDS|티셔츠 & UT > 그래픽티셔츠 > Monchhichi` — products=6, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|140591|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Monchhichi` — products=6, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141498|WOMEN|이너웨어 > 코튼 이너탑 > 캐미솔` — products=5, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141499|WOMEN|이너웨어 > 코튼 이너탑 > 탱크탑` — products=5, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141560|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Disney/PIXAR` — products=4, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141892|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 큐롯` — products=5, dimensions=length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|142637|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 폴로셔츠 (카라티) > 반팔` — products=2, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|142678|WOMEN|티셔츠 & UT > 그래픽티셔츠 > mofusand` — products=4, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143662|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > PIXAR ANIMATION STUDIOS` — products=4, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143924|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Andy Warhol Transformation` — products=4, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144221|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > ONE PIECE` — products=4, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144517|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Mickey & Friends` — products=4, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144587|WOMEN|티셔츠 & UT > 그래픽티셔츠 > ZO&FRIENDS` — products=4, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144588|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MARIO KART WORLD` — products=4, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|145016|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > YOASOBI` — products=4, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146107|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Jason Polan` — products=7, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146992|KIDS|티셔츠 & UT > 그래픽티셔츠 > CHIIKAWA` — products=7, dimensions=detail,garment_type,comparison_family,category
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146993|WOMEN|티셔츠 & UT > 그래픽티셔츠 > CHIIKAWA` — products=7, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149272|WOMEN|팬츠 > 진(청바지) > 레귤러` — products=3, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149796|MEN|팬츠 > 진(청바지) > 배기` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58119|WOMEN|아우터 > 파카 & 블루종 > 파카` — products=1, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58130|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 퍼프테크` — products=5, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58132|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 재킷` — products=1, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58142|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 긴팔` — products=7, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58190|WOMEN|팬츠 > 와이드 팬츠 > 데님` — products=3, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58209|WOMEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 스웨트` — products=5, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58221|WOMEN|팬츠 > 슬랙스(트라우저) > 스마트 팬츠` — products=4, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58225|WOMEN|팬츠 > 레깅스 > 울트라 스트레치` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58231|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 반바지` — products=3, dimensions=length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58245|WOMEN|원피스 & 스커트 > 스커트 > 롱 (맥시)` — products=2, dimensions=body_length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58246|WOMEN|원피스 & 스커트 > 스커트 > 플리츠` — products=2, dimensions=body_length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58247|WOMEN|원피스 & 스커트 > 스커트 > 플레어` — products=3, dimensions=body_length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58274|WOMEN|이너웨어 > 에어리즘 > 탱크탑` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58275|WOMEN|이너웨어 > 에어리즘 > 캐미솔` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58276|WOMEN|이너웨어 > 에어리즘 > 반팔` — products=1, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58292|WOMEN|이너웨어 > 히트텍 > 크루넥` — products=1, dimensions=garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58322|WOMEN|이너웨어 > 레깅스 & 타이즈 > 히트텍` — products=3, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58336|WOMEN|파자마 & 홈웨어 > 라운지 팬츠 > 쇼트 팬츠` — products=5, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58374|MEN|아우터 > 파카 & 블루종 > 코치재킷` — products=1, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58386|MEN|아우터 > 경량 패딩 (PUFFTECH) > 퍼프테크` — products=5, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58388|MEN|아우터 > 경량 패딩 (PUFFTECH) > 베스트` — products=1, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58389|MEN|아우터 > 경량 패딩 (PUFFTECH) > 그 외` — products=2, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58390|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 에어리즘 코튼` — products=5, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58393|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > DRY-EX` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58400|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 그 외` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58401|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 스웨트셔츠` — products=3, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58407|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > (X)그래픽 스웨트` — products=4, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58442|MEN|팬츠 > 와이드 팬츠 > 슬랙스` — products=1, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58444|MEN|팬츠 > 와이드 팬츠 > 데님` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58446|MEN|팬츠 > 치노 팬츠 > 슬림` — products=1, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58450|MEN|팬츠 > 진(청바지) > 슬림` — products=3, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58453|MEN|팬츠 > 진(청바지) > 와이드` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58460|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 스웨트` — products=5, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58466|MEN|팬츠 > 감탄 팬츠 > 감탄 팬츠` — products=2, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58467|MEN|팬츠 > 감탄 팬츠 > 감탄 팬츠(라이트)` — products=1, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58472|MEN|팬츠 > 슬랙스(트라우저) > 그 외` — products=2, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58475|MEN|팬츠 > 쇼트 팬츠(반바지) > 이지(허리 밴딩)` — products=3, dimensions=length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58498|MEN|스포츠 유틸리티 웨어 > 팬츠 > 기어 팬츠` — products=1, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58511|MEN|이너웨어 > 에어리즘 > 브리프 (레귤러)` — products=2, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58512|MEN|이너웨어 > 에어리즘 > 브리프 (로라이즈)` — products=3, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58517|MEN|이너웨어 > 히트텍 > 긴팔` — products=1, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58519|MEN|이너웨어 > 히트텍 > 반팔` — products=1, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58523|MEN|이너웨어 > 히트텍 > 타이즈` — products=3, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58545|MEN|라운지 팬츠 > 라운지 팬츠 > 쇼트 팬츠` — products=2, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58580|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트셔츠` — products=4, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58581|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트파카` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58582|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트팬츠` — products=2, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58586|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 걸즈` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58587|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 에어리즘 코튼` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58599|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 스웨트 팬츠` — products=1, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58600|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 진` — products=4, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58601|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 조거 팬츠` — products=3, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58603|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 스트레치 팬츠` — products=1, dimensions=detail,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58607|KIDS|청바지 & 팬츠 > 반바지 > 반바지` — products=6, dimensions=garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58608|KIDS|청바지 & 팬츠 > 반바지 > 스커트 팬츠` — products=8, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58635|KIDS|이너웨어 > 에어리즘 > 탱크탑` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58636|KIDS|이너웨어 > 에어리즘 > 캐미솔` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58648|KIDS|이너웨어 > 레깅스 & 타이즈 > HEATTECH` — products=2, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58689|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 레깅스` — products=4, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58691|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 쇼트팬츠` — products=2, dimensions=category,detail,length,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58714|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 레깅스` — products=7, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58715|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 크롭레깅스` — products=3, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58716|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 쇼트팬츠` — products=4, dimensions=category,detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58949|WOMEN|티셔츠 & UT > PEACE FOR ALL > 그래픽 티셔츠` — products=10, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58951|MEN|티셔츠 & 스웨트셔츠 & UT > PEACE FOR ALL > 그래픽 티셔츠` — products=28, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62686|MEN|팬츠 > 진(청바지) > UNIQLO and JW ANDERSON` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62687|MEN|팬츠 > 캐주얼 팬츠 > 리넨` — products=1, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62974|MEN|팬츠 > 캐주얼 팬츠 > 웜 팬츠` — products=2, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62979|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 그 외` — products=1, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63082|WOMEN|팬츠 > 진(청바지) > 배기` — products=3, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63083|WOMEN|팬츠 > 진(청바지) > 유니섹스` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63086|WOMEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 유니섹스` — products=1, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63087|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 유니섹스` — products=5, dimensions=length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|78155|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > other` — products=1, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|79441|MEN|팬츠 > 쇼트 팬츠(반바지) > 카고 & 기어` — products=2, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81250|KIDS|티셔츠 & UT > 그래픽티셔츠 > STUDIO GHIBLI` — products=1, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81253|BABY|영유아(6개월~5세) > 그래픽티셔츠 > STUDIO GHIBLI` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82136|WOMEN|에어리즘 > 팬츠 > 조거` — products=2, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82144|MEN|에어리즘 > 이너웨어 상의 > 크루넥` — products=1, dimensions=garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95364|WOMEN|니트 & 가디건 > 니트 > 반팔 니트` — products=5, dimensions=detail,category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95365|WOMEN|니트 & 가디건 > 니트 > 긴팔 니트` — products=6, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95369|WOMEN|니트 & 가디건 > 니트 > 램스울` — products=1, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95370|WOMEN|니트 & 가디건 > 니트 > 3D 니트` — products=1, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95373|WOMEN|니트 & 가디건 > 니트 > 워셔블` — products=1, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95375|WOMEN|니트 & 가디건 > 니트 > 가디건` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95376|WOMEN|니트 & 가디건 > 니트 > 크루넥 니트` — products=2, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95379|WOMEN|니트 & 가디건 > 니트 > 유니섹스` — products=1, dimensions=category,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95381|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 긴팔` — products=18, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95382|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 7부` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95383|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 반팔` — products=3, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95384|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 슬리브리스` — products=2, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95385|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 레이온` — products=7, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95386|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 리넨` — products=7, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95388|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 코튼` — products=1, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95399|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > GU` — products=3, dimensions=detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95405|MEN|니트 & 가디건 > 니트 > 크루넥 니트` — products=4, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95408|MEN|니트 & 가디건 > 니트 > 반팔 니트` — products=4, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95422|MEN|셔츠 > 캐주얼셔츠 > 반팔` — products=7, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95430|MEN|셔츠 > 캐주얼셔츠 > 오픈 칼라` — products=5, dimensions=length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95431|MEN|셔츠 > 캐주얼셔츠 > 긴팔` — products=30, dimensions=detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95435|MEN|셔츠 > 캐주얼셔츠 > GU` — products=4, dimensions=length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95436|MEN|셔츠 > 폴로셔츠 (카라티) > 그 외` — products=1, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95439|MEN|셔츠 > 폴로셔츠 (카라티) > 에어리즘 코튼` — products=4, dimensions=length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96141|WOMEN|원피스 & 스커트 > 스커트 > 스코츠` — products=2, dimensions=body_length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96142|WOMEN|원피스 & 스커트 > 스커트 > 미디` — products=2, dimensions=body_length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96145|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트풀집` — products=1, dimensions=category,detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98253|WOMEN|아우터 > 파카 & 블루종 > 재킷` — products=6, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98308|WOMEN|이너웨어 > 레깅스 & 타이즈 > 레깅스` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98312|WOMEN|이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드` — products=4, dimensions=garment_type,comparison_family,category,detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98314|WOMEN|이너웨어 > 히트텍 > 히트텍 울트라 웜` — products=2, dimensions=garment_type,comparison_family,category,detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98331|MEN|아우터 > 파카 & 블루종 > 재킷` — products=5, dimensions=detail,garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98354|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > DRY` — products=1, dimensions=detail,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98360|MEN|팬츠 > 치노 팬츠 > 와이드` — products=2, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98361|MEN|팬츠 > 치노 팬츠 > 레귤러` — products=1, dimensions=detail,garment_type,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98371|MEN|이너웨어 > 히트텍 > 히트텍 엑스트라 웜` — products=1, dimensions=category,detail,garment_type,comparison_family,length
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98372|MEN|이너웨어 > 히트텍 > 히트텍 울트라 웜` — products=1, dimensions=garment_type,comparison_family
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98376|MEN|라운지 팬츠 > 라운지 팬츠 > 롱 팬츠` — products=7, dimensions=category,detail,garment_type,comparison_family
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:가디건:KNIT CARDIGAN|FEMALE|ZARA > 여성 > 가디건 > KNIT CARDIGAN` — products=1, dimensions=category,garment_type,comparison_family

</details>

<details>
<summary>category-only confirmed 위험 mapping 전수 1358건</summary>

**musinsa (358)**

- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001002|UNKNOWN|상의 > 셔츠/블라우스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001003|UNKNOWN|상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001004|UNKNOWN|상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001005|UNKNOWN|상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|001006|UNKNOWN|상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002001|UNKNOWN|아우터 > 블루종/MA-1` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002002|UNKNOWN|아우터 > 레더/라이더스 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002003|UNKNOWN|아우터 > 슈트/블레이저 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002004|UNKNOWN|아우터 > 스타디움 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002006|UNKNOWN|아우터 > 나일론/코치 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002007|UNKNOWN|아우터 > 겨울 싱글 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002008|UNKNOWN|아우터 > 환절기 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002009|UNKNOWN|아우터 > 겨울 기타 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002012|UNKNOWN|아우터 > 숏패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002013|UNKNOWN|아우터 > 롱패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002014|UNKNOWN|아우터 > 사파리/헌팅 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002018|UNKNOWN|아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002019|UNKNOWN|아우터 > 아노락 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002020|UNKNOWN|아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002021|UNKNOWN|아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002022|UNKNOWN|아우터 > 후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002023|UNKNOWN|아우터 > 플리스/뽀글이` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002024|UNKNOWN|아우터 > 겨울 더블 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002025|UNKNOWN|아우터 > 무스탕/퍼` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002027001|UNKNOWN|아우터 > 경량 패딩/패딩 베스트 > 경량 패딩` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|002027002|UNKNOWN|아우터 > 경량 패딩/패딩 베스트 > 패딩 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|003002|UNKNOWN|바지 > 데님 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|003004|UNKNOWN|바지 > 트레이닝/조거 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|003005|UNKNOWN|바지 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|003007|UNKNOWN|바지 > 코튼 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|003008|UNKNOWN|바지 > 슈트 팬츠/슬랙스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|003009|UNKNOWN|바지 > 숏 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016001|UNKNOWN|스포츠/레저 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016004|UNKNOWN|스포츠/레저 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016006|UNKNOWN|스포츠/레저 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016007|UNKNOWN|스포츠/레저 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016008|UNKNOWN|스포츠/레저 > 상의 > 기타상의` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016010|UNKNOWN|스포츠/레저 > 상의 > 언더레이어` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017016011|UNKNOWN|스포츠/레저 > 상의 > 유니폼` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017017002|UNKNOWN|스포츠/레저 > 스커트 > 미니스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017017003|UNKNOWN|스포츠/레저 > 스커트 > 미디스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018001|UNKNOWN|스포츠/레저 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018003|UNKNOWN|스포츠/레저 > 아우터 > 나일론/코치 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018006|UNKNOWN|스포츠/레저 > 아우터 > 스타디움 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018007|UNKNOWN|스포츠/레저 > 아우터 > 아노락 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018008|UNKNOWN|스포츠/레저 > 아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018009|UNKNOWN|스포츠/레저 > 아우터 > 플리스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018010|UNKNOWN|스포츠/레저 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018011|UNKNOWN|스포츠/레저 > 아우터 > 레인코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018013|UNKNOWN|스포츠/레저 > 아우터 > 롱 패딩/롱 헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018014|UNKNOWN|스포츠/레저 > 아우터 > 숏 패딩/숏 헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018015|UNKNOWN|스포츠/레저 > 아우터 > 하프 패딩/하프 헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018016|UNKNOWN|스포츠/레저 > 아우터 > 후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018018|UNKNOWN|스포츠/레저 > 아우터 > 패딩 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017018019|UNKNOWN|스포츠/레저 > 아우터 > 블레이저` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017020001|UNKNOWN|스포츠/레저 > 하의 > 기타 바지` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017020002|UNKNOWN|스포츠/레저 > 하의 > 숏팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017020003|UNKNOWN|스포츠/레저 > 하의 > 조거 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017020004|UNKNOWN|스포츠/레저 > 하의 > 트레이닝 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017020006|UNKNOWN|스포츠/레저 > 하의 > 유니폼` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017020007|UNKNOWN|스포츠/레저 > 하의 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017020010|UNKNOWN|스포츠/레저 > 하의 > 언더레이어` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017020012|UNKNOWN|스포츠/레저 > 하의 > 일자 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|017022005|UNKNOWN|스포츠/레저 > 수영복/비치웨어 > 워터 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|100004|UNKNOWN|원피스/스커트 > 미니스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|100005|UNKNOWN|원피스/스커트 > 미디스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|100006|UNKNOWN|원피스/스커트 > 롱스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|102005001003|UNKNOWN|디지털/라이프 > 반려동물 > 반려동물 의류 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|102005001004|UNKNOWN|디지털/라이프 > 반려동물 > 반려동물 의류 > 블라우스/셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|102005001005|UNKNOWN|디지털/라이프 > 반려동물 > 반려동물 의류 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|102005001007|UNKNOWN|디지털/라이프 > 반려동물 > 반려동물 의류 > 원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|102005001008|UNKNOWN|디지털/라이프 > 반려동물 > 반려동물 의류 > 팬츠/치마` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|103007001|UNKNOWN|신발 > 패딩/퍼 신발 > 패딩/퍼 부츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|103007002|UNKNOWN|신발 > 패딩/퍼 신발 > 패딩/퍼 슬리퍼` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001001001|UNKNOWN|부티크 > 의류 > 상의 > 반소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001001002|UNKNOWN|부티크 > 의류 > 상의 > 긴소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001001003|UNKNOWN|부티크 > 의류 > 상의 > 민소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001001004|UNKNOWN|부티크 > 의류 > 상의 > 셔츠/블라우스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001001005|UNKNOWN|부티크 > 의류 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001001006|UNKNOWN|부티크 > 의류 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001001007|UNKNOWN|부티크 > 의류 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001001008|UNKNOWN|부티크 > 의류 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002001|UNKNOWN|부티크 > 의류 > 아우터 > 후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002002|UNKNOWN|부티크 > 의류 > 아우터 > 블루종/MA-1` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002003|UNKNOWN|부티크 > 의류 > 아우터 > 레더/라이더스 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002004|UNKNOWN|부티크 > 의류 > 아우터 > 무스탕/퍼` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002005|UNKNOWN|부티크 > 의류 > 아우터 > 슈트/블레이저 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002006|UNKNOWN|부티크 > 의류 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002007|UNKNOWN|부티크 > 의류 > 아우터 > 플리스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002008|UNKNOWN|부티크 > 의류 > 아우터 > 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002009|UNKNOWN|부티크 > 의류 > 아우터 > 숏패딩/롱패딩` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002011|UNKNOWN|부티크 > 의류 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002012|UNKNOWN|부티크 > 의류 > 아우터 > 나일론/코치 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002013|UNKNOWN|부티크 > 의류 > 아우터 > 아노락 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002014|UNKNOWN|부티크 > 의류 > 아우터 > 스타디움 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001002015|UNKNOWN|부티크 > 의류 > 아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001003001|UNKNOWN|부티크 > 의류 > 하의 > 데님 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001003002|UNKNOWN|부티크 > 의류 > 하의 > 코튼 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001003003|UNKNOWN|부티크 > 의류 > 하의 > 슈트 팬츠/슬랙스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001003004|UNKNOWN|부티크 > 의류 > 하의 > 트레이닝/조거 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001003005|UNKNOWN|부티크 > 의류 > 하의 > 숏 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001003006|UNKNOWN|부티크 > 의류 > 하의 > 점프슈트/오버올` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001003007|UNKNOWN|부티크 > 의류 > 하의 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001003008|UNKNOWN|부티크 > 의류 > 하의 > 스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001004001|UNKNOWN|부티크 > 의류 > 원피스 > 미니원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001004002|UNKNOWN|부티크 > 의류 > 원피스 > 미디원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001004003|UNKNOWN|부티크 > 의류 > 원피스 > 맥시원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001006001|UNKNOWN|부티크 > 의류 > 속옷/홈웨어 > 남성 팬티` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001006003|UNKNOWN|부티크 > 의류 > 속옷/홈웨어 > 브래지어` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|105001006004|UNKNOWN|부티크 > 의류 > 속옷/홈웨어 > 여성 속옷 하의` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106004004|KIDS|키즈 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106004005|KIDS|키즈 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106004006|KIDS|키즈 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106004011|KIDS|키즈 > 상의 > 셔츠/블라우스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106004012|KIDS|키즈 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106005001|KIDS|키즈 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106005002|KIDS|키즈 > 아우터 > 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106005003|KIDS|키즈 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106006001|KIDS|키즈 > 바지 > 코튼 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106006002|KIDS|키즈 > 바지 > 데님 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106006003|KIDS|키즈 > 바지 > 숏 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106006004|KIDS|키즈 > 바지 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106006007|KIDS|키즈 > 바지 > 트레이닝 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106006008|KIDS|키즈 > 바지 > 조거 팬츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|106007002|KIDS|키즈 > 원피스/스커트 > 스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001001001|UNKNOWN|아울렛 > 의류 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001001002|UNKNOWN|아울렛 > 의류 > 상의 > 셔츠/블라우스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001001003|UNKNOWN|아울렛 > 의류 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001001004|UNKNOWN|아울렛 > 의류 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001001005|UNKNOWN|아울렛 > 의류 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001001006|UNKNOWN|아울렛 > 의류 > 상의 > 긴소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001001008|UNKNOWN|아울렛 > 의류 > 상의 > 민소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002001|UNKNOWN|아울렛 > 의류 > 아우터 > 블루종/MA-1` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002002|UNKNOWN|아울렛 > 의류 > 아우터 > 레더/라이더스 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002003|UNKNOWN|아울렛 > 의류 > 아우터 > 슈트/블레이저 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002004|UNKNOWN|아울렛 > 의류 > 아우터 > 스타디움 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002005|UNKNOWN|아울렛 > 의류 > 아우터 > 나일론/코치 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002006|UNKNOWN|아울렛 > 의류 > 아우터 > 겨울 싱글 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002007|UNKNOWN|아울렛 > 의류 > 아우터 > 환절기 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002009|UNKNOWN|아울렛 > 의류 > 아우터 > 숏패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002010|UNKNOWN|아울렛 > 의류 > 아우터 > 롱패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002011|UNKNOWN|아울렛 > 의류 > 아우터 > 사파리/헌팅 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002013|UNKNOWN|아울렛 > 의류 > 아우터 > 패딩 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002015|UNKNOWN|아울렛 > 의류 > 아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002016|UNKNOWN|아울렛 > 의류 > 아우터 > 아노락 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002017|UNKNOWN|아울렛 > 의류 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002018|UNKNOWN|아울렛 > 의류 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002019|UNKNOWN|아울렛 > 의류 > 아우터 > 후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002020|UNKNOWN|아울렛 > 의류 > 아우터 > 플리스/뽀글이` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002021|UNKNOWN|아울렛 > 의류 > 아우터 > 겨울 더블 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001002022|UNKNOWN|아울렛 > 의류 > 아우터 > 무스탕/퍼` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001003001|UNKNOWN|아울렛 > 의류 > 바지 > 데님 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001003002|UNKNOWN|아울렛 > 의류 > 바지 > 트레이닝/조거 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001003003|UNKNOWN|아울렛 > 의류 > 바지 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001003005|UNKNOWN|아울렛 > 의류 > 바지 > 코튼 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001003006|UNKNOWN|아울렛 > 의류 > 바지 > 슈트 팬츠/슬랙스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001003007|UNKNOWN|아울렛 > 의류 > 바지 > 숏 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001003008|UNKNOWN|아울렛 > 의류 > 바지 > 점프슈트/오버올` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001004001|UNKNOWN|아울렛 > 의류 > 원피스 > 미니원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001004002|UNKNOWN|아울렛 > 의류 > 원피스 > 미디원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001004003|UNKNOWN|아울렛 > 의류 > 원피스 > 맥시원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001005001|UNKNOWN|아울렛 > 의류 > 스커트 > 미니스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001005002|UNKNOWN|아울렛 > 의류 > 스커트 > 미디스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001005003|UNKNOWN|아울렛 > 의류 > 스커트 > 롱스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001006001|UNKNOWN|아울렛 > 의류 > 속옷/홈웨어 > 여성 속옷 상의` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001006002|UNKNOWN|아울렛 > 의류 > 속옷/홈웨어 > 여성 속옷 하의` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107001006004|UNKNOWN|아울렛 > 의류 > 속옷/홈웨어 > 남성 속옷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009001001|UNKNOWN|아울렛 > 키즈 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009001002|UNKNOWN|아울렛 > 키즈 > 상의 > 셔츠/블라우스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009001003|UNKNOWN|아울렛 > 키즈 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009001004|UNKNOWN|아울렛 > 키즈 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009001005|UNKNOWN|아울렛 > 키즈 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009001006|UNKNOWN|아울렛 > 키즈 > 상의 > 긴소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009001007|UNKNOWN|아울렛 > 키즈 > 상의 > 반소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009001008|UNKNOWN|아울렛 > 키즈 > 상의 > 민소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009002001|UNKNOWN|아울렛 > 키즈 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009002002|UNKNOWN|아울렛 > 키즈 > 아우터 > 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009002003|UNKNOWN|아울렛 > 키즈 > 아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009002004|UNKNOWN|아울렛 > 키즈 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009003001|UNKNOWN|아울렛 > 키즈 > 바지 > 코튼 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009003002|UNKNOWN|아울렛 > 키즈 > 바지 > 데님 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009003003|UNKNOWN|아울렛 > 키즈 > 바지 > 숏 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009003004|UNKNOWN|아울렛 > 키즈 > 바지 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009003006|UNKNOWN|아울렛 > 키즈 > 바지 > 점프 슈트/오버올` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009003007|UNKNOWN|아울렛 > 키즈 > 바지 > 트레이닝 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009003008|UNKNOWN|아울렛 > 키즈 > 바지 > 조거 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009004|UNKNOWN|아울렛 > 키즈 > 원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107009005|UNKNOWN|아울렛 > 키즈 > 스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011001001|UNKNOWN|아울렛 > 스포츠/레저 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011001002|UNKNOWN|아울렛 > 스포츠/레저 > 상의 > 긴소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011001003|UNKNOWN|아울렛 > 스포츠/레저 > 상의 > 나시/민소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011001004|UNKNOWN|아울렛 > 스포츠/레저 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011001005|UNKNOWN|아울렛 > 스포츠/레저 > 상의 > 반소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011001006|UNKNOWN|아울렛 > 스포츠/레저 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011001007|UNKNOWN|아울렛 > 스포츠/레저 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011001009|UNKNOWN|아울렛 > 스포츠/레저 > 상의 > 브라탑` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011002002|UNKNOWN|아울렛 > 스포츠/레저 > 하의 > 숏 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011002003|UNKNOWN|아울렛 > 스포츠/레저 > 하의 > 조거 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011002004|UNKNOWN|아울렛 > 스포츠/레저 > 하의 > 트레이닝 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011002007|UNKNOWN|아울렛 > 스포츠/레저 > 하의 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011002008|UNKNOWN|아울렛 > 스포츠/레저 > 하의 > 언더레이어` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003001|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003003|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 나일론/코치 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003004|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 스타디움 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003005|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 아노락 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003006|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003007|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 플리스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003008|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003009|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 레인코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003010|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 롱패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003011|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 숏패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003012|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 하프패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003013|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003014|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 패딩 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011003015|UNKNOWN|아울렛 > 스포츠/레저 > 아우터 > 블레이저` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011004001|UNKNOWN|아울렛 > 스포츠/레저 > 스커트 > 미니스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011004002|UNKNOWN|아울렛 > 스포츠/레저 > 스커트 > 미디스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011005001|UNKNOWN|아울렛 > 스포츠/레저 > 원피스 > 미니원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|107011005002|UNKNOWN|아울렛 > 스포츠/레저 > 원피스 > 미디원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001001|UNKNOWN|어스 > 의류 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001002|UNKNOWN|어스 > 의류 > 상의 > 셔츠/블라우스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001003|UNKNOWN|어스 > 의류 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001004|UNKNOWN|어스 > 의류 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001005|UNKNOWN|어스 > 의류 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001006|UNKNOWN|어스 > 의류 > 상의 > 긴소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001007|UNKNOWN|어스 > 의류 > 상의 > 반소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001008|UNKNOWN|어스 > 의류 > 상의 > 민소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001001009|UNKNOWN|어스 > 의류 > 상의 > 스포츠 상의` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002001|UNKNOWN|어스 > 의류 > 아우터 > 블루종/MA-1` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002002|UNKNOWN|어스 > 의류 > 아우터 > 레더/라이더스 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002003|UNKNOWN|어스 > 의류 > 아우터 > 슈트/블레이저 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002005|UNKNOWN|어스 > 의류 > 아우터 > 나일론/코치 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002006|UNKNOWN|어스 > 의류 > 아우터 > 겨울 싱글 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002007|UNKNOWN|어스 > 의류 > 아우터 > 환절기 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002009|UNKNOWN|어스 > 의류 > 아우터 > 숏패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002010|UNKNOWN|어스 > 의류 > 아우터 > 롱패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002011|UNKNOWN|어스 > 의류 > 아우터 > 사파리/헌팅 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002013|UNKNOWN|어스 > 의류 > 아우터 > 패딩 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002014|UNKNOWN|어스 > 의류 > 아우터 > 트러커 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002015|UNKNOWN|어스 > 의류 > 아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002016|UNKNOWN|어스 > 의류 > 아우터 > 아노락 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002017|UNKNOWN|어스 > 의류 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002018|UNKNOWN|어스 > 의류 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002019|UNKNOWN|어스 > 의류 > 아우터 > 후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002020|UNKNOWN|어스 > 의류 > 아우터 > 플리스/뽀글이` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001002021|UNKNOWN|어스 > 의류 > 아우터 > 겨울 더블 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001003001|UNKNOWN|어스 > 의류 > 바지 > 데님 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001003002|UNKNOWN|어스 > 의류 > 바지 > 트레이닝/조거 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001003003|UNKNOWN|어스 > 의류 > 바지 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001003005|UNKNOWN|어스 > 의류 > 바지 > 코튼 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001003006|UNKNOWN|어스 > 의류 > 바지 > 슈트 팬츠/슬랙스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001003007|UNKNOWN|어스 > 의류 > 바지 > 숏 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001003008|UNKNOWN|어스 > 의류 > 바지 > 점프슈트/오버올` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001003009|UNKNOWN|어스 > 의류 > 바지 > 스포츠 하의` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001004001|UNKNOWN|어스 > 의류 > 원피스 > 미니원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001004002|UNKNOWN|어스 > 의류 > 원피스 > 미디원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001004003|UNKNOWN|어스 > 의류 > 원피스 > 맥시원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001005001|UNKNOWN|어스 > 의류 > 스커트 > 미니스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001005002|UNKNOWN|어스 > 의류 > 스커트 > 미디스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001005003|UNKNOWN|어스 > 의류 > 스커트 > 롱스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001006001|UNKNOWN|어스 > 의류 > 속옷/홈웨어 > 여성 속옷 상의` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001006002|UNKNOWN|어스 > 의류 > 속옷/홈웨어 > 여성 속옷 하의` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108001006004|UNKNOWN|어스 > 의류 > 속옷/홈웨어 > 남성 속옷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108008001009|UNKNOWN|어스 > 반려동물 > 반려동물 의류 > 레인코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108009005002|UNKNOWN|어스 > 뷰티 > 프레그런스 > 드레스퍼퓸` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010001001|UNKNOWN|어스 > 스포츠/레저 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010001002|UNKNOWN|어스 > 스포츠/레저 > 상의 > 긴소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010001003|UNKNOWN|어스 > 스포츠/레저 > 상의 > 나시/민소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010001004|UNKNOWN|어스 > 스포츠/레저 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010001005|UNKNOWN|어스 > 스포츠/레저 > 상의 > 반소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010001006|UNKNOWN|어스 > 스포츠/레저 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010001007|UNKNOWN|어스 > 스포츠/레저 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010001009|UNKNOWN|어스 > 스포츠/레저 > 상의 > 브라탑` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010002002|UNKNOWN|어스 > 스포츠/레저 > 하의 > 숏 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010002003|UNKNOWN|어스 > 스포츠/레저 > 하의 > 조거 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010002004|UNKNOWN|어스 > 스포츠/레저 > 하의 > 트레이닝 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010002007|UNKNOWN|어스 > 스포츠/레저 > 하의 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003001|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003003|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 나일론/코치 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003005|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 아노락 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003006|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003007|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 플리스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003008|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003009|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 레인코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003010|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 롱패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003011|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 숏패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003012|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 하프패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010003013|UNKNOWN|어스 > 스포츠/레저 > 아우터 > 후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010004001|UNKNOWN|어스 > 스포츠/레저 > 스커트 > 미니스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010004002|UNKNOWN|어스 > 스포츠/레저 > 스커트 > 미디스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010005001|UNKNOWN|어스 > 스포츠/레저 > 원피스 > 미니원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|108010005002|UNKNOWN|어스 > 스포츠/레저 > 원피스 > 미디원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109001001|UNKNOWN|유즈드 > 상의 > 맨투맨/스웨트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109001002|UNKNOWN|유즈드 > 상의 > 셔츠/블라우스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109001003|UNKNOWN|유즈드 > 상의 > 후드 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109001004|UNKNOWN|유즈드 > 상의 > 니트/스웨터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109001005|UNKNOWN|유즈드 > 상의 > 피케/카라 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109001006|UNKNOWN|유즈드 > 상의 > 긴소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109001007|UNKNOWN|유즈드 > 상의 > 반소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109001008|UNKNOWN|유즈드 > 상의 > 민소매 티셔츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002001|UNKNOWN|유즈드 > 아우터 > 블루종/MA-1` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002002|UNKNOWN|유즈드 > 아우터 > 레더/라이더스 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002003|UNKNOWN|유즈드 > 아우터 > 슈트/블레이저 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002004|UNKNOWN|유즈드 > 아우터 > 스타디움 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002005|UNKNOWN|유즈드 > 아우터 > 나일론/코치 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002006|UNKNOWN|유즈드 > 아우터 > 겨울 싱글 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002007|UNKNOWN|유즈드 > 아우터 > 환절기 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002009|UNKNOWN|유즈드 > 아우터 > 숏패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002010|UNKNOWN|유즈드 > 아우터 > 롱패딩/헤비 아우터` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002011|UNKNOWN|유즈드 > 아우터 > 사파리/헌팅 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002012|UNKNOWN|유즈드 > 아우터 > 기타 아우터` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002013|UNKNOWN|유즈드 > 아우터 > 패딩 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002014|UNKNOWN|유즈드 > 아우터 > 트러커 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002015|UNKNOWN|유즈드 > 아우터 > 트레이닝 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002016|UNKNOWN|유즈드 > 아우터 > 아노락 재킷` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002017|UNKNOWN|유즈드 > 아우터 > 카디건` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002018|UNKNOWN|유즈드 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002019|UNKNOWN|유즈드 > 아우터 > 후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002020|UNKNOWN|유즈드 > 아우터 > 플리스/뽀글이` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002021|UNKNOWN|유즈드 > 아우터 > 겨울 더블 코트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109002022|UNKNOWN|유즈드 > 아우터 > 무스탕/퍼` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109003001|UNKNOWN|유즈드 > 바지 > 데님 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109003002|UNKNOWN|유즈드 > 바지 > 트레이닝/조거 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109003003|UNKNOWN|유즈드 > 바지 > 레깅스` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109003005|UNKNOWN|유즈드 > 바지 > 코튼 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109003006|UNKNOWN|유즈드 > 바지 > 슈트 팬츠/슬랙스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109003007|UNKNOWN|유즈드 > 바지 > 숏 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109003008|UNKNOWN|유즈드 > 바지 > 점프슈트/오버올` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109004001|UNKNOWN|유즈드 > 원피스/스커트 > 미니원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109004002|UNKNOWN|유즈드 > 원피스/스커트 > 미디원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109004003|UNKNOWN|유즈드 > 원피스/스커트 > 맥시원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109004004|UNKNOWN|유즈드 > 원피스/스커트 > 미니스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109004005|UNKNOWN|유즈드 > 원피스/스커트 > 미디스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109004006|UNKNOWN|유즈드 > 원피스/스커트 > 롱스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109005004|UNKNOWN|유즈드 > 키즈 > 원피스/스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|109006007|UNKNOWN|유즈드 > 스포츠/레저 > 원피스/스커트` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112002006|UNKNOWN|스포츠 구단 > MLB > 시카고 화이트삭스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112002010|UNKNOWN|스포츠 구단 > MLB > 시카고 컵스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112002026|UNKNOWN|스포츠 구단 > MLB > 신시내티 레즈` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112002027|UNKNOWN|스포츠 구단 > MLB > 워싱턴 내셔널스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112004013|UNKNOWN|스포츠 구단 > 해외축구 > 뉴캐슬 유나이티드` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112004015|UNKNOWN|스포츠 구단 > 해외축구 > 울버햄튼` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112005005|UNKNOWN|스포츠 구단 > KBL > 고양 소노 스카이거너스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112011002|UNKNOWN|스포츠 구단 > 축구 국가대표팀 > 브라질` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112011012|UNKNOWN|스포츠 구단 > 축구 국가대표팀 > 코트디부아르` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112012004|UNKNOWN|스포츠 구단 > NFL > 마이애미 돌핀스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112012005|UNKNOWN|스포츠 구단 > NFL > 뉴욕 자이언츠` — category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112012006|UNKNOWN|스포츠 구단 > NFL > 시카고 베어스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|112012008|UNKNOWN|스포츠 구단 > NFL > 뉴올리언스 세인츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|113006002|UNKNOWN|캐릭터 > 워너브라더스 > 루니툰즈` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|113009001|UNKNOWN|캐릭터 > 피너츠 > 찰리브라운` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|113010011|UNKNOWN|캐릭터 > 글로벌/클래식 캐릭터 > 베티붑` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|113012007|UNKNOWN|캐릭터 > 게임 > 트릭컬 리바이브` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|114002005|UNKNOWN|만화/애니메이션 > 일본 만화/애니메이션 > 원피스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|117001005|UNKNOWN|음악 > K-POP > BTS` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|118001019|UNKNOWN|영화/드라마 > 해외 영화 > 백 투 더 퓨쳐` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|118001021|UNKNOWN|영화/드라마 > 해외 영화 > 죠스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `musinsa|0a0fab7a-e6a6-45b9-ab5c-3426aba173e3|118001022|UNKNOWN|영화/드라마 > 해외 영화 > E.T.` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail

**uniqlo (935)**

- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100074|WOMEN|니트 & 가디건 > 니트 > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100075|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100076|WOMEN|팬츠 > 슬랙스(트라우저) > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100083|MEN|니트 & 가디건 > 니트 > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100084|MEN|셔츠 > 캐주얼셔츠 > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100085|MEN|팬츠 > 와이드 팬츠 > UNIQLO : C` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100087|MEN|팬츠 > 슬랙스(트라우저) > 와이드 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100089|KIDS|니트 & 셔츠 > 니트 > 가디건` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100091|KIDS|니트 & 셔츠 > 셔츠 > 셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100097|KIDS|이너웨어 > 히트텍 > 긴팔` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100098|KIDS|이너웨어 > 히트텍 > 히트텍 엑스트라 웜` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100099|KIDS|이너웨어 > 히트텍 > 히트텍 울트라 웜` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100100|KIDS|이너웨어 > 히트텍 > 레깅스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100101|MEN|팬츠 > 진(청바지) > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100102|KIDS|니트 & 셔츠 > 니트 > 스웨터` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100314|KIDS|원피스 & 스커트 > 원피스 > 스코츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100315|MEN|니트 & 가디건 > 니트 > 긴팔 니트` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100381|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Louvre Camille Henrot` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100396|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 파카` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|100397|MEN|아우터 > 경량 패딩 (PUFFTECH) > 파카` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|101617|WOMEN|아우터 > 재킷 & 코트 > Uniqlo U` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|101618|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|101620|WOMEN|니트 & 가디건 > 니트 > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|101621|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|101623|MEN|니트 & 가디건 > 니트 > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|101624|MEN|셔츠 > 캐주얼셔츠 > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102253|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 후드` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102589|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102590|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > UNIQLO and COMPTOIR DES COTONNIERS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102591|WOMEN|팬츠 > 와이드 팬츠 > UNIQLO and COMPTOIR DES COTONNIERS` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102592|WOMEN|팬츠 > 슬랙스(트라우저) > UNIQLO and COMPTOIR DES COTONNIERS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102594|MEN|셔츠 > 캐주얼셔츠 > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102595|MEN|팬츠 > 와이드 팬츠 > UNIQLO and JW ANDERSON` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102686|WOMEN|니트 & 가디건 > 니트 > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|102687|MEN|니트 & 가디건 > 니트 > GU` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|103249|WOMEN|니트 & 가디건 > 니트 > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|103250|WOMEN|팬츠 > 와이드 팬츠 > UNIQLO and JW ANDERSON` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|103255|MEN|니트 & 가디건 > 니트 > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|103564|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > ARCANE LEAGUE OF LEGENDS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|103565|WOMEN|티셔츠 & UT > 그래픽티셔츠 > ARCANE LEAGUE OF LEGENDS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|103994|WOMEN|팬츠 > 캐주얼 팬츠 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104030|KIDS|티셔츠 & UT > 그래픽티셔츠 > DRAGON BALL / DRAGON BALL DAIMA` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104031|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104032|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > (X)PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104033|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > DRAGON BALL / DRAGON BALL DAIMA` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104034|WOMEN|티셔츠 & UT > 그래픽티셔츠 > DRAGON BALL / DRAGON BALL DAIMA` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104171|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Sesame Street` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104172|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Sesame Street` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104203|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > NY POP ART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|104204|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)NY POP ART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105181|KIDS|티셔츠 & UT > 그래픽티셔츠 > NY POP ART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105253|KIDS|아우터 > 재킷 & 파카 > 후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105313|BABY|영유아(6개월~5세) > 아우터 > 후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105468|WOMEN|스포츠 유틸리티 웨어 > 아우터 > 풀집 후디` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105470|KIDS|원피스 & 스커트 > 스커트 > 스커트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105622|KIDS|티셔츠 & UT > 그래픽티셔츠 > SpongeBob SquarePants■Cactus Plant Flea Market` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105623|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > SpongeBob SquarePants■Cactus Plant Flea Market` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105666|WOMEN|티셔츠 & UT > 그래픽티셔츠 > SpongeBob SquarePants■Cactus Plant Flea Market` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105843|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Keith Haring X Coca-Cola®` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105895|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Curated by Tate` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|105986|KIDS|에어리즘 > 팬츠 > 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107319|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Disney’s Mickey Faces` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107558|WOMEN|Special Collaborations > Uniqlo U > Skirt` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107560|WOMEN|Special Collaborations > Uniqlo U > Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107562|WOMEN|Special Collaborations > Uniqlo U > Cardigan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107566|WOMEN|Special Collaborations > UNIQLO : C > Shirts and Blouses` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107569|WOMEN|Special Collaborations > UNIQLO : C > Sweats` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107571|WOMEN|Special Collaborations > UNIQLO : C > Skirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107596|WOMEN|Special Collaborations > UNIQLO and JW ANDERSON > Skirt` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107598|WOMEN|Special Collaborations > UNIQLO and JW ANDERSON > Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107604|MEN|Special Collaborations > Uniqlo U > T-Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107605|MEN|Special Collaborations > Uniqlo U > Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107606|MEN|Special Collaborations > Uniqlo U > Sweaters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107610|MEN|Special Collaborations > UNIQLO : C > Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107612|MEN|Special Collaborations > UNIQLO : C > Sweats` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107622|MEN|Special Collaborations > UNIQLO and JW ANDERSON > Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107759|KIDS|티셔츠 & UT > 그래픽티셔츠 > Minecraft` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107760|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Dan Da Dan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107761|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MANGA curation` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107762|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MAGNUM PHOTOS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107786|WOMEN|팬츠 > 진(청바지) > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107791|MEN|팬츠 > 진(청바지) > GU` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|107860|WOMEN|티셔츠 & UT > 그래픽티셔츠 > MAGNUM PHOTOS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|108044|KIDS|티셔츠 & UT > 그래픽티셔츠 > Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|108046|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MoMA Art Icons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|109440|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Pablo Picasso` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|109442|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Universal Movies` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|109443|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Universal Movies` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112078|BABY|신생아(0개월~2세) > 그래픽티셔츠 > Jason Polan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112079|BABY|영유아(6개월~5세) > 그래픽티셔츠 > other02` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112139|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Pablo Picasso` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112140|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Keith Haring X Coca-Cola®` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112210|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Henri Matisse` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112314|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)miffy` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112602|WOMEN|티셔츠 & UT > 그래픽티셔츠 > MANGA curation` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112603|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Dan Da Dan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112604|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Curated by Tate` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112605|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Disney’s Mickey Faces` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112643|MEN|스포츠 유틸리티 웨어 > 팬츠 > 울트라 스트레치 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112644|MEN|아우터 > 파카 & 블루종 > 윈드블럭` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112705|KIDS|티셔츠 & UT > 그래픽티셔츠 > mofusand` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112706|KIDS|티셔츠 & UT > 그래픽티셔츠 > Disney in Blue` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112709|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Disney in Blue` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112710|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Disney in Blue` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112711|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112712|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112753|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|112812|WOMEN|스포츠 유틸리티 웨어 > 팬츠 > 울트라 스트레치` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|113236|WOMEN|Special Collaborations > UNIQLO and COMPTOIR DES COTONNIERS > T-Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|113237|WOMEN|Special Collaborations > UNIQLO and COMPTOIR DES COTONNIERS > Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|113375|WOMEN|니트 & 가디건 > 니트 > UNIQLO and COMPTOIR DES COTONNIERS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|113378|MEN|팬츠 > 쇼트 팬츠(반바지) > 데님 & 코튼` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|113563|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Mobile Suit GUNDAM 45th Anniversary` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114719|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 데님` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114720|MEN|아우터 > 파카 & 블루종 > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114721|MEN|아우터 > 재킷 & 블레이저 > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114801|WOMEN|UV Protection > 가디건 > 가디건` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114802|WOMEN|UV Protection > 팬츠 & 레깅스 > 레깅스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|114926|MEN|팬츠 > 캐주얼 팬츠 > 울트라 스트레치` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|115018|WOMEN|팬츠 > 쇼트 팬츠(반바지) > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|115446|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Doraemon meets the Louvre` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|115447|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE ONE PIECE` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|115513|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)UT ARCHIVE ONE PIECE` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|115514|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|115519|WOMEN|UV Protection > 팬츠 & 레깅스 > 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116008|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 박시 크롭` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116009|WOMEN|에어리즘 > 팬츠 > 쇼트 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116010|MEN|팬츠 > 캐주얼 팬츠 > 스웨트 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116011|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > Girls` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116219|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE Super Mario` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116336|WOMEN|니트 & 가디건 > 니트 > 폴로 니트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116338|MEN|셔츠 > 폴로셔츠 (카라티) > 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116571|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL TIMELESS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116869|WOMEN|리넨 > 셔츠 & 티셔츠 > 셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116870|WOMEN|리넨 > 셔츠 & 티셔츠 > 티셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116871|WOMEN|리넨 > 팬츠 > 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116876|MEN|리넨 > 셔츠 > 셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116877|MEN|리넨 > 팬츠 > 롱팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116878|MEN|리넨 > 팬츠 > 쇼트팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|116907|MEN|아우터 > 재킷 & 블레이저 > 감탄 재킷 (CUSTOM ORDER)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|117028|KIDS|티셔츠 & UT > 그래픽티셔츠 > NY POP ART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|117033|WOMEN|티셔츠 & UT > 그래픽티셔츠 > 그 외` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|117094|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Mickey&Friends Sports` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|117292|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 조거 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|117301|WOMEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 조거 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|117524|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 쇼트 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|118119|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)TOY STORY` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|118120|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > TOY STORY` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|118121|KIDS|티셔츠 & UT > 그래픽티셔츠 > TOY STORY` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|118744|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Ai Yazawa Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|118745|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > ONE PIECE` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|119481|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 액티브` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120002|MEN|팬츠 > 캐주얼 팬츠 > 슬랙스(트라우저)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120172|KIDS|티셔츠 & UT > 그래픽티셔츠 > STUDIO GHIBLI` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120173|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > STUDIO GHIBLI` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120196|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120197|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)The Brands` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120300|WOMEN|리넨 > 셔츠 & 티셔츠 > 오픈칼라셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120494|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > UTGP2025 x TATE MODERN` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120495|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)UTGP2025 x TATE MODERN` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120668|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > The Brands` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120757|KIDS|티셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL TIMELESS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120758|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)MAGIC FOR ALL TIMELESS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120759|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Disney Art` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|120988|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Disney Art` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|121219|KIDS|티셔츠 & UT > 그래픽티셔츠 > CHIIKAWA x JOKE BEAR AND FRIENDS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|121384|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)ONE PIECE` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|121385|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)STUDIO GHIBLI` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|121582|KIDS|티셔츠 & UT > 그래픽티셔츠 > POP MART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|121692|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Sylvanian Families` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|121813|WOMEN|티셔츠 & UT > 그래픽티셔츠 > The Super Mario Galaxy Movie` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|122143|KIDS|티셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|122475|WOMEN|원피스 & 스커트 > 스커트 > 미니` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|122483|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Keith Haring` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|122485|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Keith Haring` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|122905|BABY|영유아(6개월~5세) > 그래픽티셔츠 > Clay Animation` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|122906|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Jean-Michel Basquiat` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123154|WOMEN|팬츠 > 진(청바지) > 슬림` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123155|WOMEN|팬츠 > 쇼트 팬츠(반바지) > RELACO(7부)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123267|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > WARNER BROS. MOVIES` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123268|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)WARNER BROS. MOVIES` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123298|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Sesame Street` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123299|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Sesame Street` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123529|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123531|MEN|팬츠 > 진(청바지) > 스트레이트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123532|MEN|아우터 > 경량 패딩 (PUFFTECH) > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123533|MEN|이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123587|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > (X)Anime Chainsaw Man` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123762|WOMEN|팬츠 > 슬랙스(트라우저) > 플레어` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123764|BABY|신생아(0개월~2세) > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|123826|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)WARNER BROS. MOVIES` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124091|BABY|영유아(6개월~5세) > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124361|WOMEN|팬츠 > 와이드 팬츠 > GU` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124362|WOMEN|팬츠 > 캐주얼 팬츠 > GU` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124363|WOMEN|팬츠 > 쇼트 팬츠(반바지) > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124364|WOMEN|원피스 & 스커트 > 원피스 > GU` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124365|WOMEN|원피스 & 스커트 > 스커트 > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124366|WOMEN|아우터 > 재킷 & 코트 > GU` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124370|MEN|팬츠 > 와이드 팬츠 > GU` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124371|MEN|팬츠 > 캐주얼 팬츠 > GU` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124435|WOMEN|GU > 상의 > 티셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124436|WOMEN|GU > 상의 > 스웨트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124437|WOMEN|GU > 상의 > 셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124438|WOMEN|GU > 상의 > 니트 & 가디건` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124440|WOMEN|GU > 원피스 & 스커트 > 스커트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124441|WOMEN|GU > 팬츠 > 진` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124442|WOMEN|GU > 팬츠 > 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124445|MEN|GU > 상의 > 티셔츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124446|MEN|GU > 상의 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124447|MEN|GU > 상의 > 셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124448|MEN|GU > 상의 > 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124449|MEN|GU > 팬츠 > 진` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124450|MEN|GU > 팬츠 > 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|124882|KIDS|티셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|125113|WOMEN|팬츠 > 진(청바지) > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|125773|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)WAGARA (Animals)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|125774|WOMEN|팬츠 > 캐주얼 팬츠 > 코튼 앵클` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|125775|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > (X)후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|125776|MEN|팬츠 > 진(청바지) > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|125806|WOMEN|팬츠 > 캐주얼 팬츠 > 워셔블 니트` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|126280|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 후리스레깅스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|126400|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|126401|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|126802|WOMEN|Special Collaborations > UNIQLO and JW ANDERSON > Sweaters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|126806|MEN|Special Collaborations > UNIQLO and JW ANDERSON > Sweaters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127027|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Yu Nagaba` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127489|KIDS|티셔츠 & UT > 그래픽티셔츠 > NY POP ART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127490|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)NY POP ART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127491|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > NY POP ART` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127493|WOMEN|티셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL TIMELESS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127799|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Tamagotchi` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127800|WOMEN|파자마 & 홈웨어 > 라운지 팬츠 > 후리스 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|127801|MEN|라운지 팬츠 > 라운지 팬츠 > 후리스 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128018|WOMEN|티셔츠 & UT > 그래픽티셔츠 > miffy in bloom` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128051|KIDS|티셔츠 & UT > 그래픽티셔츠 > Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128054|BABY|신생아(0개월~2세) > 그래픽티셔츠 > The Picture Book Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128055|BABY|영유아(6개월~5세) > 그래픽티셔츠 > The Picture Book Collection` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128056|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128057|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128382|WOMEN|니트 & 가디건 > 가디건 > 메리노` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128383|WOMEN|니트 & 가디건 > 가디건 > 수플레 얀` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128384|WOMEN|니트 & 가디건 > 가디건 > 캐시미어` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128386|WOMEN|니트 & 가디건 > 가디건 > 케이블` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128387|WOMEN|니트 & 가디건 > 가디건 > 유니섹스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128388|WOMEN|니트 & 가디건 > 가디건 > 그 외` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128389|WOMEN|니트 & 가디건 > 가디건 > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128396|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 후리스레깅스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128425|MEN|니트 & 가디건 > 가디건 > 메리노` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128426|MEN|니트 & 가디건 > 가디건 > 램스울` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128427|MEN|니트 & 가디건 > 가디건 > 수플레 얀` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128429|MEN|니트 & 가디건 > 가디건 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128430|MEN|니트 & 가디건 > 가디건 > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128545|KIDS|티셔츠 & UT > 그래픽티셔츠 > ZOOTOPIA` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128578|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Disney` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128579|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > ZOOTOPIA` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128633|KIDS|티셔츠 & UT > 그래픽티셔츠 > Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|128636|KIDS|티셔츠 & UT > 그래픽티셔츠 > Minecraft` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|130723|WOMEN|니트 & 가디건 > 가디건 > 후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|131453|WOMEN|팬츠 > 캐주얼 팬츠 > 후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|131941|KIDS|티셔츠 & UT > 그래픽티셔츠 > Jason Polan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|131942|BABY|영유아(6개월~5세) > 그래픽티셔츠 > Jason Polan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|132571|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MoMA Poster Art Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|132572|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Elliott Erwitt` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|132868|KIDS|티셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL ICONS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|132869|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL ICONS` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|132870|WOMEN|티셔츠 & UT > 그래픽티셔츠 > BABYMONSTER` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|133396|MEN|니트 & 가디건 > 니트 > 워셔블` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|133562|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Cheerful characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|133594|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Curated by Tate: From the Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|133595|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > The Louvre` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|134044|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|134562|WOMEN|Special Collaborations > UNIQLO and JW ANDERSON > Polo` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|134577|MEN|Special Collaborations > UNIQLO and JW ANDERSON > Polo` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|134782|BABY|신생아(0개월~2세) > 그래픽티셔츠 > Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|134783|BABY|영유아(6개월~5세) > 그래픽티셔츠 > Sanrio characters` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135246|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135280|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)MoMA Poster Art Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135281|WOMEN|니트 & 가디건 > 가디건 > UV Protection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135282|WOMEN|니트 & 가디건 > 가디건 > 스무드 코튼` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135482|WOMEN|Special Collaborations > UNIQLO : C > Coats` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135484|WOMEN|Special Collaborations > UNIQLO : C > Blousons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135495|MEN|Special Collaborations > UNIQLO : C > Coats` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|135706|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL TIMELESS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136135|KIDS|티셔츠 & UT > 그래픽티셔츠 > mofusand` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136168|KIDS|티셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136201|KIDS|티셔츠 & UT > 그래픽티셔츠 > POP MART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136234|WOMEN|티셔츠 & UT > 그래픽티셔츠 > POP MART` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136606|WOMEN|아우터 > 파카 & 블루종 > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136609|WOMEN|니트 & 가디건 > 가디건 > 브이넥` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136612|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 디자인 블라우스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136615|WOMEN|팬츠 > 와이드 팬츠 > 긴 기장` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136617|MEN|아우터 > 파카 & 블루종 > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136618|MEN|팬츠 > 와이드 팬츠 > 긴 기장` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136621|KIDS|이너웨어 > 코튼 이너 > 탱크탑` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136650|BABY|영유아(6개월~5세) > 그래픽티셔츠 > other01` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136804|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > The Super Mario Galaxy Movie` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|136805|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Musical Icons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|137653|WOMEN|Special Collaborations > UNIQLO and COMPTOIR DES COTONNIERS > Sweaters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|137686|WOMEN|Special Collaborations > UNIQLO and COMPTOIR DES COTONNIERS > Skirt` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|137691|WOMEN|Special Collaborations > UNIQLO and COMPTOIR DES COTONNIERS > Polo` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|138052|BABY|신생아(0개월~2세) > 그래픽티셔츠 > other` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|138812|MEN|팬츠 > 와이드 팬츠 > 유니섹스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|139436|WOMEN|Special Collaborations > Uniqlo U > Blousons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|139462|MEN|Special Collaborations > Uniqlo U > Blousons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|139468|MEN|Special Collaborations > Uniqlo U > Shorts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|139475|MEN|Special Collaborations > Uniqlo U > Tank Top` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|139480|MEN|Special Collaborations > Uniqlo U > Sweat` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|139701|MEN|팬츠 > 쇼트 팬츠(반바지) > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|139969|KIDS|티셔츠 & UT > 그래픽티셔츠 > The Super Mario Galaxy Movie` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|140590|KIDS|티셔츠 & UT > 그래픽티셔츠 > Monchhichi` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|140591|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Monchhichi` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|140770|MEN|Special Collaborations > The Roger Federer Collection > DRY-EX Polo Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|140771|MEN|Special Collaborations > The Roger Federer Collection > Ultra Stretch Shorts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|140772|MEN|Special Collaborations > The Roger Federer Collection > 3D Knit` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141284|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > BLUE LOCK` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141498|WOMEN|이너웨어 > 코튼 이너탑 > 캐미솔` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141499|WOMEN|이너웨어 > 코튼 이너탑 > 탱크탑` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141560|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Disney/PIXAR` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|141892|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 큐롯` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|142637|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 폴로셔츠 (카라티) > 반팔` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|142639|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 폴로셔츠 (카라티) > 스웨터` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|142640|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 폴로셔츠 (카라티) > 유니섹스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|142641|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 폴로셔츠 (카라티) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|142678|WOMEN|티셔츠 & UT > 그래픽티셔츠 > mofusand` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143067|WOMEN|Special Collaborations > UNIQLO and Cecilie Bahnsen > T-Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143069|WOMEN|Special Collaborations > UNIQLO and Cecilie Bahnsen > Skirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143073|KIDS|Special Collaborations > UNIQLO and Cecilie Bahnsen > T-Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143660|BABY|신생아(0개월~2세) > 그래픽티셔츠 > Mickey＆Friends` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143661|BABY|영유아(6개월~5세) > 그래픽티셔츠 > Mickey＆Friends` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143662|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > PIXAR ANIMATION STUDIOS` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|143924|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Andy Warhol Transformation` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144221|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > ONE PIECE` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144485|WOMEN|이너웨어 > 에어리즘 > 쇼츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144517|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Mickey & Friends` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144584|KIDS|티셔츠 & UT > 그래픽티셔츠 > MARIO KART WORLD` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144585|BABY|영유아(6개월~5세) > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144586|BABY|신생아(0개월~2세) > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144587|WOMEN|티셔츠 & UT > 그래픽티셔츠 > ZO&FRIENDS` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144588|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MARIO KART WORLD` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|144816|BABY|영유아(6개월~5세) > 그래픽티셔츠 > Disney Winnie the Pooh` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|145016|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > YOASOBI` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|145309|WOMEN|Special Collaborations > UNIQLO F.RISSO > T-Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|145311|WOMEN|Special Collaborations > UNIQLO F.RISSO > Skirt` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|145321|MEN|Special Collaborations > UNIQLO F.RISSO > T-Shirts` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|145573|BABY|영유아(6개월~5세) > 그래픽티셔츠 > PAW Patrol` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146107|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Jason Polan` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146116|MEN|Special Collaborations > UNIQLO : C > Cardigan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146992|KIDS|티셔츠 & UT > 그래픽티셔츠 > CHIIKAWA` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|146993|WOMEN|티셔츠 & UT > 그래픽티셔츠 > CHIIKAWA` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|147619|WOMEN|팬츠 > 캐주얼 팬츠 > 립` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148329|WOMEN|라운지 & 언더웨어 컬렉션 > Minimalist Classics > 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148333|WOMEN|라운지 & 언더웨어 컬렉션 > 팬츠 > 쇼트 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148351|WOMEN|라운지 & 언더웨어 컬렉션 > Effortless Charm > 쇼트 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148355|WOMEN|라운지 & 언더웨어 컬렉션 > 니트 & 가디건 > 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148361|WOMEN|라운지 & 언더웨어 컬렉션 > Effortless Charm > 가디건` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148374|WOMEN|라운지 & 언더웨어 컬렉션 > 니트 & 가디건 > 가디건` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148873|MEN|팬츠 > 와이드 팬츠 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148874|MEN|팬츠 > 쇼트 팬츠(반바지) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|148875|WOMEN|팬츠 > 와이드 팬츠 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149177|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 슬림` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149178|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 레귤러` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149179|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 릴랙스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149272|WOMEN|팬츠 > 진(청바지) > 레귤러` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149275|WOMEN|팬츠 > 진(청바지) > 긴 기장` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149796|MEN|팬츠 > 진(청바지) > 배기` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149797|MEN|팬츠 > 캐주얼 팬츠 > 치노` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149934|WOMEN|팬츠 > 배럴 레그 팬츠 > 데님` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149935|WOMEN|팬츠 > 배럴 레그 팬츠 > 긴 기장` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149936|WOMEN|팬츠 > 배럴 레그 팬츠 > 유니섹스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149937|MEN|팬츠 > 배럴 레그 팬츠 > 데님` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149938|WOMEN|팬츠 > 배럴 레그 팬츠 > 저지` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149939|MEN|팬츠 > 배럴 레그 팬츠 > 코튼` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149940|MEN|팬츠 > 배럴 레그 팬츠 > 긴 기장` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|149995|WOMEN|이너웨어 > 히트텍 > 히트텍 캐시미어` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|151483|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58119|WOMEN|아우터 > 파카 & 블루종 > 파카` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58124|WOMEN|아우터 > 재킷 & 코트 > 감탄 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58125|WOMEN|아우터 > 재킷 & 코트 > 캐주얼 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58129|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 울트라 라이트 다운` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58130|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 퍼프테크` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58131|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 베스트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58132|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 재킷` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58134|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58135|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58140|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > AIRism` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58141|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 립` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58142|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 긴팔` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58146|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 유니섹스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58147|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58154|WOMEN|티셔츠 & UT > 스웨트셔츠 & 후드집업 > 스웨트셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58155|WOMEN|티셔츠 & UT > 스웨트셔츠 & 후드집업 > 스웨트 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58156|WOMEN|티셔츠 & UT > 스웨트셔츠 & 후드집업 > 그래픽 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58188|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)CAT PHOTOGRAPHS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58189|WOMEN|팬츠 > 와이드 팬츠 > 슬랙스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58190|WOMEN|팬츠 > 와이드 팬츠 > 데님` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58193|WOMEN|팬츠 > 와이드 팬츠 > 유틸리티(커브ㆍ카고)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58196|WOMEN|팬츠 > 진(청바지) > 스키니` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58199|WOMEN|팬츠 > 진(청바지) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58204|WOMEN|팬츠 > 캐주얼 팬츠 > 울트라 스트레치` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58205|WOMEN|팬츠 > 캐주얼 팬츠 > 리넨` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58206|WOMEN|팬츠 > 캐주얼 팬츠 > 큐롯` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58209|WOMEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 스웨트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58210|WOMEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 드라이 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58212|WOMEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58221|WOMEN|팬츠 > 슬랙스(트라우저) > 스마트 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58222|WOMEN|팬츠 > 슬랙스(트라우저) > 감탄 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58224|WOMEN|팬츠 > 슬랙스(트라우저) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58225|WOMEN|팬츠 > 레깅스 > 울트라 스트레치` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58226|WOMEN|팬츠 > 레깅스 > 에어리즘` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58227|WOMEN|팬츠 > 레깅스 > 크롭 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58229|WOMEN|팬츠 > 레깅스 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58231|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 반바지` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58240|WOMEN|원피스 & 스커트 > 원피스 > UNIQLO and Cecilie bahnsen` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58245|WOMEN|원피스 & 스커트 > 스커트 > 롱 (맥시)` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58246|WOMEN|원피스 & 스커트 > 스커트 > 플리츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58247|WOMEN|원피스 & 스커트 > 스커트 > 플레어` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58249|WOMEN|원피스 & 스커트 > 스커트 > 짧은 기장` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58250|WOMEN|원피스 & 스커트 > 스커트 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58251|WOMEN|스포츠 유틸리티 웨어 > 아우터 > 베스트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58252|WOMEN|스포츠 유틸리티 웨어 > 아우터 > 재킷 & 블루종` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58254|WOMEN|스포츠 유틸리티 웨어 > 아우터 > 코트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58257|WOMEN|스포츠 유틸리티 웨어 > 상의 > 에어리즘` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58258|WOMEN|스포츠 유틸리티 웨어 > 팬츠 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58261|WOMEN|스포츠 유틸리티 웨어 > 팬츠 > 레깅스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58262|WOMEN|스포츠 유틸리티 웨어 > 팬츠 > 쇼트 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58263|WOMEN|스포츠 유틸리티 웨어 > 팬츠 > 조거 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58274|WOMEN|이너웨어 > 에어리즘 > 탱크탑` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58275|WOMEN|이너웨어 > 에어리즘 > 캐미솔` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58276|WOMEN|이너웨어 > 에어리즘 > 반팔` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58277|WOMEN|이너웨어 > 에어리즘 > 긴팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58279|WOMEN|이너웨어 > 에어리즘 > 레깅스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58282|WOMEN|이너웨어 > 에어리즘 > 쇼츠 (저스트 웨이스트)` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58283|WOMEN|이너웨어 > 에어리즘 > 쇼츠 (힙허거)` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58284|WOMEN|이너웨어 > 에어리즘 > 쇼츠 (비키니)` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58287|WOMEN|이너웨어 > 히트텍 > 반팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58288|WOMEN|이너웨어 > 히트텍 > 캐미솔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58292|WOMEN|이너웨어 > 히트텍 > 크루넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58293|WOMEN|이너웨어 > 히트텍 > 하이넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58294|WOMEN|이너웨어 > 히트텍 > 터틀넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58296|WOMEN|이너웨어 > 히트텍 > 타이즈` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58298|WOMEN|이너웨어 > 히트텍 > 레깅스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58321|WOMEN|이너웨어 > 레깅스 & 타이즈 > 에어리즘` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58322|WOMEN|이너웨어 > 레깅스 & 타이즈 > 히트텍` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58336|WOMEN|파자마 & 홈웨어 > 라운지 팬츠 > 쇼트 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58371|MEN|아우터 > 파카 & 블루종 > 블루종` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58372|MEN|아우터 > 파카 & 블루종 > 셔츠재킷` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58373|MEN|아우터 > 파카 & 블루종 > 파카` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58374|MEN|아우터 > 파카 & 블루종 > 코치재킷` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58379|MEN|아우터 > 재킷 & 블레이저 > 컴포트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58380|MEN|아우터 > 재킷 & 블레이저 > 감탄 재킷` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58381|MEN|아우터 > 재킷 & 블레이저 > 쇼트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58382|MEN|아우터 > 재킷 & 블레이저 > 셋업` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58385|MEN|아우터 > 경량 패딩 (PUFFTECH) > 울트라 라이트 다운` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58386|MEN|아우터 > 경량 패딩 (PUFFTECH) > 퍼프테크` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58387|MEN|아우터 > 경량 패딩 (PUFFTECH) > 재킷` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58388|MEN|아우터 > 경량 패딩 (PUFFTECH) > 베스트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58389|MEN|아우터 > 경량 패딩 (PUFFTECH) > 그 외` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58390|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 에어리즘 코튼` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58393|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > DRY-EX` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58399|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > (X)브이넥` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58400|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 그 외` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58401|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 스웨트셔츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58402|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > (X)후드 집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58404|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58406|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 드라이스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58407|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > (X)그래픽 스웨트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58441|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58442|MEN|팬츠 > 와이드 팬츠 > 슬랙스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58443|MEN|팬츠 > 와이드 팬츠 > 유틸리티(카고ㆍ커브)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58444|MEN|팬츠 > 와이드 팬츠 > 데님` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58446|MEN|팬츠 > 치노 팬츠 > 슬림` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58447|MEN|팬츠 > 치노 팬츠 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58450|MEN|팬츠 > 진(청바지) > 슬림` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58451|MEN|팬츠 > 진(청바지) > 셀비지` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58452|MEN|팬츠 > 진(청바지) > 레귤러` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58453|MEN|팬츠 > 진(청바지) > 와이드` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58455|MEN|팬츠 > 캐주얼 팬츠 > 유틸리티(카고ㆍ커브)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58456|MEN|팬츠 > 캐주얼 팬츠 > 조거` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58458|MEN|팬츠 > 캐주얼 팬츠 > 이지(허리 밴딩)` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58460|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 스웨트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58461|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 드라이 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58466|MEN|팬츠 > 감탄 팬츠 > 감탄 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58467|MEN|팬츠 > 감탄 팬츠 > 감탄 팬츠(라이트)` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58468|MEN|팬츠 > 감탄 팬츠 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58470|MEN|팬츠 > 슬랙스(트라우저) > 감탄 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58471|MEN|팬츠 > 슬랙스(트라우저) > 스마트 앵클 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58472|MEN|팬츠 > 슬랙스(트라우저) > 그 외` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58473|MEN|팬츠 > 쇼트 팬츠(반바지) > 치노` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58474|MEN|팬츠 > 쇼트 팬츠(반바지) > 울트라 스트레치` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58475|MEN|팬츠 > 쇼트 팬츠(반바지) > 이지(허리 밴딩)` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58485|MEN|스포츠 유틸리티 웨어 > 아우터 > 재킷 & 블루종` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58494|MEN|스포츠 유틸리티 웨어 > 상의 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58495|MEN|스포츠 유틸리티 웨어 > 팬츠 > 스웨트 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58496|MEN|스포츠 유틸리티 웨어 > 팬츠 > 조거 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58497|MEN|스포츠 유틸리티 웨어 > 팬츠 > 반바지` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58498|MEN|스포츠 유틸리티 웨어 > 팬츠 > 기어 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58509|MEN|이너웨어 > 에어리즘 > 긴팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58511|MEN|이너웨어 > 에어리즘 > 브리프 (레귤러)` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58512|MEN|이너웨어 > 에어리즘 > 브리프 (로라이즈)` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58514|MEN|이너웨어 > 에어리즘 > V넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58515|MEN|이너웨어 > 에어리즘 > 크루넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58517|MEN|이너웨어 > 히트텍 > 긴팔` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58519|MEN|이너웨어 > 히트텍 > 반팔` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58520|MEN|이너웨어 > 히트텍 > V넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58521|MEN|이너웨어 > 히트텍 > 크루넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58522|MEN|이너웨어 > 히트텍 > 터틀넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58523|MEN|이너웨어 > 히트텍 > 타이즈` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58545|MEN|라운지 팬츠 > 라운지 팬츠 > 쇼트 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58576|KIDS|아우터 > 재킷 & 파카 > 패딩` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58580|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트셔츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58581|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트파카` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58582|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58586|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 걸즈` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58587|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 에어리즘 코튼` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58589|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > DRY-EX` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58591|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58597|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 카고 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58599|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 스웨트 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58600|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 진` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58601|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 조거 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58603|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 스트레치 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58607|KIDS|청바지 & 팬츠 > 반바지 > 반바지` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58608|KIDS|청바지 & 팬츠 > 반바지 > 스커트 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58610|KIDS|원피스 & 스커트 > 원피스 > 긴팔` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58611|KIDS|원피스 & 스커트 > 원피스 > 슬리브리스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58612|KIDS|원피스 & 스커트 > 원피스 > 반팔` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58626|KIDS|스포츠 유틸리티 웨어 > 하의 > 바지` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58627|KIDS|스포츠 유틸리티 웨어 > 하의 > 반바지` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58628|KIDS|스포츠 유틸리티 웨어 > 하의 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58634|KIDS|이너웨어 > 에어리즘 > 반팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58635|KIDS|이너웨어 > 에어리즘 > 탱크탑` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58636|KIDS|이너웨어 > 에어리즘 > 캐미솔` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58643|KIDS|이너웨어 > 히트텍 > 반팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58648|KIDS|이너웨어 > 레깅스 & 타이즈 > HEATTECH` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58672|BABY|신생아(0개월~2세) > 바디수트 > 코튼` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58673|BABY|신생아(0개월~2세) > 바디수트 > 코튼메쉬` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58674|BABY|신생아(0개월~2세) > 바디수트 > 긴팔` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58675|BABY|신생아(0개월~2세) > 바디수트 > 반팔` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58676|BABY|신생아(0개월~2세) > 바디수트 > 슬리브리스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58677|BABY|신생아(0개월~2세) > 바디수트 > 티셔츠 타입` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58678|BABY|신생아(0개월~2세) > 바디수트 > 전면 오픈 타입` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58680|BABY|신생아(0개월~2세) > 아우터 > 패딩` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58686|BABY|신생아(0개월~2세) > 티셔츠 & 스웨트셔츠 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58688|BABY|신생아(0개월~2세) > 티셔츠 & 스웨트셔츠 > 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58689|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 레깅스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58690|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 크롭레깅스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58691|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 쇼트팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58694|BABY|신생아(0개월~2세) > 레깅스 & 팬츠 > 롱팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58704|BABY|영유아(6개월~5세) > 아우터 > 패딩` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58709|BABY|영유아(6개월~5세) > 티셔츠 & 스웨트셔츠 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58712|BABY|영유아(6개월~5세) > 티셔츠 & 스웨트셔츠 > 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58714|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 레깅스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58715|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 크롭레깅스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58716|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 쇼트팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58719|BABY|영유아(6개월~5세) > 레깅스 & 팬츠 > 롱팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58949|WOMEN|티셔츠 & UT > PEACE FOR ALL > 그래픽 티셔츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|58951|MEN|티셔츠 & 스웨트셔츠 & UT > PEACE FOR ALL > 그래픽 티셔츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|59443|WOMEN|원피스 & 스커트 > 스커트 > 리넨` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|60533|KIDS|스포츠 유틸리티 웨어 > 상의 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|61192|MEN|스포츠 유틸리티 웨어 > 팬츠 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|61225|WOMEN|팬츠 > 진(청바지) > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|61227|WOMEN|팬츠 > 와이드 팬츠 > Uniqlo U` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|61228|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 버뮤다` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62519|WOMEN|아우터 > 파카 & 블루종 > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62520|WOMEN|아우터 > 파카 & 블루종 > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62521|WOMEN|아우터 > 재킷 & 코트 > UNIQLO and COMPTOIR DES COTONNIERS` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62523|WOMEN|아우터 > 재킷 & 코트 > UNIQLO and JW ANDERSON` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62553|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Andy Warhol Flowers Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62554|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Disney Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62555|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Henri Matisse` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62556|WOMEN|티셔츠 & UT > 그래픽티셔츠 > LOVE, SUNSHINE & PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62557|WOMEN|티셔츠 & UT > 그래픽티셔츠 > miffy` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62558|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Musee Du Louvre Blossoms Of Diversity` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62559|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS Dance Time with Snoopy` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62560|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)Yu Nagaba` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62561|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Pokémon All-Stars` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62562|WOMEN|티셔츠 & UT > 그래픽티셔츠 > UTGP2023: MAGIC FOR ALL` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62563|WOMEN|티셔츠 & UT > 그래픽티셔츠 > KAWS + Warhol` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62564|WOMEN|팬츠 > 진(청바지) > 히트텍` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62566|WOMEN|팬츠 > 캐주얼 팬츠 > Uniqlo U` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62567|WOMEN|팬츠 > 캐주얼 팬츠 > UNIQLO and COMPTOIR DES COTONNIERS` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62569|WOMEN|팬츠 > 캐주얼 팬츠 > UNIQLO : C` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62570|WOMEN|팬츠 > 슬랙스(트라우저) > 웜 팬츠(기모)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62571|WOMEN|팬츠 > 레깅스 > 히트텍 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62572|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62574|WOMEN|원피스 & 스커트 > 원피스 > Uniqlo U` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62575|WOMEN|원피스 & 스커트 > 원피스 > UNIQLO : C` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62576|WOMEN|원피스 & 스커트 > 원피스 > UNIQLO and JW ANDERSON` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62577|WOMEN|원피스 & 스커트 > 스커트 > UNIQLO and COMPTOIR DES COTONNIERS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62578|WOMEN|원피스 & 스커트 > 스커트 > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62579|WOMEN|스포츠 유틸리티 웨어 > 팬츠 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62619|MEN|아우터 > 파카 & 블루종 > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62620|MEN|아우터 > 파카 & 블루종 > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62622|MEN|아우터 > 재킷 & 블레이저 > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62624|MEN|아우터 > 경량 패딩 (PUFFTECH) > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62625|MEN|아우터 > 경량 패딩 (PUFFTECH) > UNIQLO and Engineered Garments` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62641|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Andy Warhol x Kosuke Kawamura` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62646|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Disney Good Vibes` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62651|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > KAWS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62652|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Keith Haring Subway Drawings` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62662|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Mickey Stands` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62677|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE Andy Warhol / Keith Haring / Jean-Michel Basquiat` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62684|MEN|팬츠 > 진(청바지) > 히트텍` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62686|MEN|팬츠 > 진(청바지) > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62687|MEN|팬츠 > 캐주얼 팬츠 > 리넨` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62974|MEN|팬츠 > 캐주얼 팬츠 > 웜 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62979|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 그 외` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|62980|MEN|팬츠 > 슬랙스(트라우저) > 히트텍 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63005|KIDS|티셔츠 & UT > 그래픽티셔츠 > Andy Warhol x Kosuke Kawamura` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63006|KIDS|티셔츠 & UT > 그래픽티셔츠 > Andy Warhol Flowers Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63007|KIDS|티셔츠 & UT > 그래픽티셔츠 > Animal Crossing New Horizons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63008|KIDS|티셔츠 & UT > 그래픽티셔츠 > Disney Beyond Time` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63009|KIDS|티셔츠 & UT > 그래픽티셔츠 > Disney Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63010|KIDS|티셔츠 & UT > 그래픽티셔츠 > Disney Heroines` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63011|KIDS|티셔츠 & UT > 그래픽티셔츠 > Disney Mickey Mouse & Minnie Mouse art by Yuni Yoshida` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63012|KIDS|티셔츠 & UT > 그래픽티셔츠 > KAWS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63013|KIDS|티셔츠 & UT > 그래픽티셔츠 > LEGO® NINJAGO®` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63014|KIDS|티셔츠 & UT > 그래픽티셔츠 > LOVE, SUNSHINE & PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63015|KIDS|티셔츠 & UT > 그래픽티셔츠 > Mickey Stands` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63016|KIDS|티셔츠 & UT > 그래픽티셔츠 > MINECRAFT` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63017|KIDS|티셔츠 & UT > 그래픽티셔츠 > Minions: The Rise of Gru` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63018|KIDS|티셔츠 & UT > 그래픽티셔츠 > Monster Hunter Rise` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63019|KIDS|티셔츠 & UT > 그래픽티셔츠 > National Museum of Nature and Science, Tokyo` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63020|KIDS|티셔츠 & UT > 그래픽티셔츠 > New York weekend trip` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63021|KIDS|티셔츠 & UT > 그래픽티셔츠 > PAUL & JOE` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63022|KIDS|티셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63023|KIDS|티셔츠 & UT > 그래픽티셔츠 > PEANUTS Charlie Brown's Baseball Team` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63024|KIDS|티셔츠 & UT > 그래픽티셔츠 > Peanuts Holiday` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63025|KIDS|티셔츠 & UT > 그래픽티셔츠 > Peanuts x Yu Nagaba` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63026|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon Masters EX` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63027|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon Meets Artist` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63028|KIDS|티셔츠 & UT > 그래픽티셔츠 > RETRO PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63030|KIDS|티셔츠 & UT > 그래픽티셔츠 > Splatoon 3` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63031|KIDS|티셔츠 & UT > 그래픽티셔츠 > SPYxFAMILY` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63032|KIDS|티셔츠 & UT > 그래픽티셔츠 > Sumikkogurashi` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63033|KIDS|티셔츠 & UT > 그래픽티셔츠 > THE SUPER MARIO BROS. MOVIE` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63034|KIDS|티셔츠 & UT > 그래픽티셔츠 > UNIVERSITY LOGO` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63035|KIDS|티셔츠 & UT > 그래픽티셔츠 > UTGP2023: MAGIC FOR ALL` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63036|KIDS|청바지 & 팬츠 > 청바지 & 팬츠 > 웜 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63048|BABY|영유아(6개월~5세) > 그래픽티셔츠 > The Picture Book Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63073|WOMEN|아우터 > 파카 & 블루종 > 유니섹스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63074|WOMEN|아우터 > 재킷 & 코트 > 유니섹스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63075|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 유니섹스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63081|WOMEN|팬츠 > 와이드 팬츠 > 유니섹스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63082|WOMEN|팬츠 > 진(청바지) > 배기` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63083|WOMEN|팬츠 > 진(청바지) > 유니섹스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63084|WOMEN|팬츠 > 캐주얼 팬츠 > 웜 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63085|WOMEN|팬츠 > 캐주얼 팬츠 > 유니섹스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63086|WOMEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 유니섹스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63087|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 유니섹스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63106|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Alice In Wonderland` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63107|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Animal Crossing New Horizons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63108|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Celebrating Sofia Coppola` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63109|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Disney Dearest Friends` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63110|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Disney Pajama Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63111|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Doraemon Sustainability Mode` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63112|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)UT ARCHIVE Super Mario` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63113|WOMEN|티셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL FOREVER` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63114|WOMEN|티셔츠 & UT > 그래픽티셔츠 > MARVEL Essentials` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63115|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Mickey Motifs` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63116|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Mickey Shines` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63117|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Monster Hunter Rise` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63118|WOMEN|티셔츠 & UT > 그래픽티셔츠 > My Life with Animals` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63119|WOMEN|티셔츠 & UT > 그래픽티셔츠 > OF THEIR NATURE` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63120|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Anime Chainsaw Man` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63121|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS Holiday` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63122|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS Lounge` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63123|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Mobile Suit GUNDAM 45th Anniversary` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63124|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Peanuts Vintage` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63125|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS × Reyn Spooner` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63126|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Roy Lichtenstein` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63127|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)MoMA Art Icons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63128|WOMEN|티셔츠 & UT > 그래픽티셔츠 > The Brands The World of Record Stores` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63129|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)ZOOTOPIA` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63130|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Troye Sivan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63158|KIDS|티셔츠 & UT > 그래픽티셔츠 > Disney Furry Friends` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63159|KIDS|티셔츠 & UT > 그래픽티셔츠 > Disney Heroines in Blooming` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63160|KIDS|티셔츠 & UT > 그래픽티셔츠 > Disney Memories` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63161|KIDS|티셔츠 & UT > 그래픽티셔츠 > Doraemon Sustainability Mode` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63162|KIDS|티셔츠 & UT > 그래픽티셔츠 > Doraemon’s Wonderful Day` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63163|KIDS|티셔츠 & UT > 그래픽티셔츠 > Jason Polan` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63164|KIDS|티셔츠 & UT > 그래픽티셔츠 > Jurassic World x HAJIME SORAYAMA` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63165|KIDS|티셔츠 & UT > 그래픽티셔츠 > LEGO® City` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63166|KIDS|티셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL TIMELESS FAVORITES` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63167|KIDS|티셔츠 & UT > 그래픽티셔츠 > Marvel Studios The Infinity Saga` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63168|KIDS|티셔츠 & UT > 그래픽티셔츠 > Mickey & Friends Art by Steven Harrington` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63169|KIDS|티셔츠 & UT > 그래픽티셔츠 > MICKEY MOUSE PHOTO DAYS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63170|KIDS|티셔츠 & UT > 그래픽티셔츠 > Monochrome Mickey Mouse Art by Joshua Vides` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63171|KIDS|티셔츠 & UT > 그래픽티셔츠 > PIXAR COLLECTION` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63172|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon – Become a Pokémon Professor!` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63173|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon All-Stars` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63174|KIDS|티셔츠 & UT > 그래픽티셔츠 > The Smithsonian National Museum of Natural History` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|63175|KIDS|티셔츠 & UT > 그래픽티셔츠 > UTGP2022 × PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|64822|KIDS|티셔츠 & UT > 그래픽티셔츠 > Micky Stands` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|64823|KIDS|티셔츠 & UT > 그래픽티셔츠 > PEANUTS Sports Club` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|64824|KIDS|티셔츠 & UT > 그래픽티셔츠 > mofusand Fruits Paradise` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|64825|KIDS|티셔츠 & UT > 그래픽티셔츠 > Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|64856|KIDS|이너웨어 > 히트텍 > 반팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65614|WOMEN|아우터 > 파카 & 블루종 > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65647|WOMEN|팬츠 > 와이드 팬츠 > UNIQLO : C` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65648|WOMEN|팬츠 > 진(청바지) > UNIQLO : C` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65650|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS Sports Club` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65713|KIDS|티셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE Andy Warhol / Keith Haring / Jean-Michel Basquiat` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65714|BABY|신생아(0개월~2세) > 그래픽티셔츠 > STUDIO GHIBLI` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65746|WOMEN|원피스 & 스커트 > 스커트 > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65747|WOMEN|원피스 & 스커트 > 스커트 > UNIQLO and JW ANDERSON` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65779|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Andy Warhol’s Collages` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65780|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Disney Vintage Poster Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65781|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Fighting Game Legends` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65782|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > HUNTER×HUNTER` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65783|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > METAL GEAR Archive` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65785|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > PEANUTS You Can Be Anything!` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65786|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE Andy Warhol / Keith Haring / Jean-Michel Basquiat` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65790|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Jean-Michel Basquiat King Pleasure` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|65791|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MoMA Art Icons` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|66013|WOMEN|팬츠 > 레깅스 > Uniqlo U` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|69641|WOMEN|아우터 > 파카 & 블루종 > UNIQLO x Marimekko` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|71884|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > CAPCOM 40th` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|71885|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Curated by Tate` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|73042|KIDS|티셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL Girls Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|75613|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Find Your TREASURE` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|78154|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Hello Kitty 50th anniversary.` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|78155|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > other` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|78156|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > PEANUTS You Can Be Anything!` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|79210|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 코튼` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|79243|KIDS|티셔츠 & UT > 그래픽티셔츠 > Chiikawa × Sanrio characters: Sweets Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|79276|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon: A New Adventure` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|79441|MEN|팬츠 > 쇼트 팬츠(반바지) > 카고 & 기어` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81220|KIDS|티셔츠 & UT > 그래픽티셔츠 > MINECRAFT` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81221|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Star Wars: Remastered by Kosuke Kawamura` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81222|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > The Legend of Zelda: Tears of the Kingdom` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81226|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 코튼` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81236|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Disney Beach Trip Collection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81250|KIDS|티셔츠 & UT > 그래픽티셔츠 > STUDIO GHIBLI` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81251|WOMEN|티셔츠 & UT > 그래픽티셔츠 > STUDIO GHIBLI` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81252|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > (X)STUDIO GHIBLI` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81253|BABY|영유아(6개월~5세) > 그래픽티셔츠 > STUDIO GHIBLI` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81257|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Kaiju No.8` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81373|WOMEN|티셔츠 & UT > 그래픽티셔츠 > UTGP2024: The Louvre` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81374|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > UTGP2024: The Louvre` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81718|WOMEN|팬츠 > 캐주얼 팬츠 > 유틸리티(커브ㆍ카고)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81751|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > 【OSHI NO KO】` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81752|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > FINAL FANTASY` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|81753|KIDS|티셔츠 & UT > 그래픽티셔츠 > 【OSHI NO KO】` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82113|WOMEN|에어리즘 > 브라탑 > 캐미솔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82114|WOMEN|에어리즘 > 브라탑 > 탱크탑` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82121|MEN|스포츠 유틸리티 웨어 > 상의 > DRY-EX` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82125|KIDS|에어리즘 > 이너웨어 상의 > 탱크탑` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82126|KIDS|에어리즘 > 이너웨어 상의 > 캐미솔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82128|WOMEN|에어리즘 > 이너웨어 상의 > AIRism` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82129|WOMEN|에어리즘 > 이너웨어 상의 > 캐미솔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82130|WOMEN|에어리즘 > 이너웨어 상의 > 탱크탑` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82131|WOMEN|에어리즘 > 이너웨어 상의 > 반팔` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82132|WOMEN|에어리즘 > 이너웨어 상의 > 긴팔` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82134|WOMEN|에어리즘 > 상의 > 반팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82135|WOMEN|에어리즘 > 상의 > 긴팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82136|WOMEN|에어리즘 > 팬츠 > 조거` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82138|WOMEN|에어리즘 > 팬츠 > 레깅스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82139|MEN|에어리즘 > 이너웨어 상의 > AIRism` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82140|MEN|에어리즘 > 이너웨어 상의 > 코튼` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82141|MEN|에어리즘 > 이너웨어 상의 > 반팔` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82142|MEN|에어리즘 > 이너웨어 상의 > 슬리브리스` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82143|MEN|에어리즘 > 이너웨어 상의 > V넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82144|MEN|에어리즘 > 이너웨어 상의 > 크루넥` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_level_resolution_required,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82145|MEN|에어리즘 > 상의 > 폴로셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82146|MEN|에어리즘 > 상의 > 반팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82147|MEN|에어리즘 > 상의 > 긴팔` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82148|MEN|에어리즘 > 상의 > 슬리브리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82479|WOMEN|에어리즘 > 이너웨어 상의 > 브라` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82482|WOMEN|에어리즘 > 상의 > 티셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82483|MEN|에어리즘 > 상의 > 티셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82485|KIDS|에어리즘 > 이너웨어 상의 > 메쉬` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82488|KIDS|에어리즘 > 티셔츠 > 티셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82708|MEN|이너웨어 > 에어리즘 > 슬리브리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|82977|KIDS|에어리즘 > 이너웨어 상의 > 코튼 블렌드` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|83236|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Kaiju No.8` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|83302|MEN|에어리즘 > 이너웨어 상의 > 메쉬` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|83401|WOMEN|스포츠 유틸리티 웨어 > 상의 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|83567|KIDS|티셔츠 & UT > 그래픽티셔츠 > mofusand` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|83632|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE Andy Warhol / Keith Haring / Jean-Michel Basquiat` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|84787|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 리넨` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|84853|WOMEN|티셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE Andy Warhol / Keith Haring / Jean-Michel Basquiat` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|86432|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Mickey Stands` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|86457|MEN|스포츠 유틸리티 웨어 > 상의 > 폴로 셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|86459|KIDS|티셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|86460|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|86465|MEN|팬츠 > 쇼트 팬츠(반바지) > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|86692|KIDS|티셔츠 & UT > 그래픽티셔츠 > TV animation ONE PIECE 25th` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|86693|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > TV animation ONE PIECE 25th` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|87337|MEN|팬츠 > 감탄 팬츠 > 반바지` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|87344|WOMEN|티셔츠 & UT > 그래픽티셔츠 > (X)MAGIC FOR ALL ICONS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|87954|WOMEN|팬츠 > 캐주얼 팬츠 > 이지(허리 밴딩)` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|87957|KIDS|청바지 & 팬츠 > 반바지 > 울트라 스트레치` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|87966|KIDS|티셔츠 & UT > 그래픽티셔츠 > Sanrio characters` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94166|KIDS|티셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL with Yu Nagaba` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94167|WOMEN|티셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL with Yu Nagaba` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94168|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > MAGIC FOR ALL with Yu Nagaba` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94356|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS You Can Be Anything!` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94357|WOMEN|팬츠 > 진(청바지) > 와이드` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94361|MEN|아우터 > 파카 & 블루종 > 포켓터블` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94362|MEN|아우터 > 파카 & 블루종 > 블록테크` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94366|KIDS|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 그래픽 티셔츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94546|WOMEN|티셔츠 & UT > 그래픽티셔츠 > Pokémon` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94951|WOMEN|아우터 > 파카 & 블루종 > 울트라 스트레치(액티브)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94952|WOMEN|아우터 > 재킷 & 코트 > 재킷` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|94953|MEN|아우터 > 재킷 & 블레이저 > 재킷` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95363|WOMEN|니트 & 가디건 > 니트 > KAWS WINTER` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95364|WOMEN|니트 & 가디건 > 니트 > 반팔 니트` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95365|WOMEN|니트 & 가디건 > 니트 > 긴팔 니트` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95366|WOMEN|니트 & 가디건 > 니트 > 메리노 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95367|WOMEN|니트 & 가디건 > 니트 > 수플레 얀` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95368|WOMEN|니트 & 가디건 > 니트 > 캐시미어` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95369|WOMEN|니트 & 가디건 > 니트 > 램스울` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95370|WOMEN|니트 & 가디건 > 니트 > 3D 니트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95372|WOMEN|니트 & 가디건 > 니트 > UV Protection` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95373|WOMEN|니트 & 가디건 > 니트 > 워셔블` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95374|WOMEN|니트 & 가디건 > 니트 > 디자인 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95375|WOMEN|니트 & 가디건 > 니트 > 가디건` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95376|WOMEN|니트 & 가디건 > 니트 > 크루넥 니트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95377|WOMEN|니트 & 가디건 > 니트 > V넥 니트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95378|WOMEN|니트 & 가디건 > 니트 > 터틀넥` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95379|WOMEN|니트 & 가디건 > 니트 > 유니섹스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95380|WOMEN|니트 & 가디건 > 니트 > 스무드 코튼` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95381|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 긴팔` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95382|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 7부` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95383|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 반팔` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95384|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 슬리브리스` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95385|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 레이온` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95386|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 리넨` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95388|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 코튼` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95389|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 오버사이즈` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95392|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 플란넬` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95394|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 데님` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95398|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 스키퍼(V넥)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95399|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > GU` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95400|MEN|니트 & 가디건 > 니트 > 메리노` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95401|MEN|니트 & 가디건 > 니트 > 수플레 얀` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95402|MEN|니트 & 가디건 > 니트 > 램스울` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95403|MEN|니트 & 가디건 > 니트 > 캐시미어` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95404|MEN|니트 & 가디건 > 니트 > 밀라노 립` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95405|MEN|니트 & 가디건 > 니트 > 크루넥 니트` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95406|MEN|니트 & 가디건 > 니트 > 브이넥` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95407|MEN|니트 & 가디건 > 니트 > 터틀넥` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95408|MEN|니트 & 가디건 > 니트 > 반팔 니트` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95409|MEN|니트 & 가디건 > 니트 > 가디건` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95410|MEN|니트 & 가디건 > 니트 > 베스트` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95411|MEN|니트 & 가디건 > 니트 > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95412|MEN|셔츠 > 정장셔츠 (와이셔츠) > 슈퍼 논 아이론` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95414|MEN|셔츠 > 정장셔츠 (와이셔츠) > 이지 케어` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95415|MEN|셔츠 > 정장셔츠 (와이셔츠) > 슈퍼 논 아이론 저지` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95417|MEN|셔츠 > 정장셔츠 (와이셔츠) > 버튼 다운` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95418|MEN|셔츠 > 정장셔츠 (와이셔츠) > 세미 와이드` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95421|MEN|셔츠 > 정장셔츠 (와이셔츠) > 그 외` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95422|MEN|셔츠 > 캐주얼셔츠 > 반팔` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95423|MEN|셔츠 > 캐주얼셔츠 > 플란넬` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95424|MEN|셔츠 > 캐주얼셔츠 > 옥스포드` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95425|MEN|셔츠 > 캐주얼셔츠 > 데님 & 샴브레이` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95426|MEN|셔츠 > 캐주얼셔츠 > 브로드 클로스(코튼100%)` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95427|MEN|셔츠 > 캐주얼셔츠 > 리넨` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95428|MEN|셔츠 > 캐주얼셔츠 > 코듀로이` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95429|MEN|셔츠 > 캐주얼셔츠 > 오버사이즈` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95430|MEN|셔츠 > 캐주얼셔츠 > 오픈 칼라` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95431|MEN|셔츠 > 캐주얼셔츠 > 긴팔` — product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95432|MEN|셔츠 > 캐주얼셔츠 > 프린트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95433|MEN|셔츠 > 캐주얼셔츠 > 스트라이프` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95435|MEN|셔츠 > 캐주얼셔츠 > GU` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95436|MEN|셔츠 > 폴로셔츠 (카라티) > 그 외` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95438|MEN|셔츠 > 폴로셔츠 (카라티) > 드라이 피케` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95439|MEN|셔츠 > 폴로셔츠 (카라티) > 에어리즘 코튼` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95440|MEN|셔츠 > 폴로셔츠 (카라티) > DRY-EX` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|95441|MEN|셔츠 > 폴로셔츠 (카라티) > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96139|WOMEN|팬츠 > 와이드 팬츠 > 치노` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96140|WOMEN|팬츠 > 와이드 팬츠 > 이지(허리 밴딩)` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96141|WOMEN|원피스 & 스커트 > 스커트 > 스코츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96142|WOMEN|원피스 & 스커트 > 스커트 > 미디` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96144|MEN|팬츠 > 와이드 팬츠 > 치노` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96145|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트풀집` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96146|MEN|아우터 > 재킷 & 블레이저 > 캐주얼 재킷` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96147|KIDS|티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트후디` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96342|WOMEN|티셔츠 & UT > 그래픽티셔츠 > miffy's stories` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96370|WOMEN|팬츠 > 쇼트 팬츠(반바지) > 스코츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96645|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > KAWS + Warhol` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96734|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96735|WOMEN|티셔츠 & UT > 그래픽티셔츠 > PEANUTS` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|96799|WOMEN|셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 유니섹스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98251|WOMEN|아우터 > 파카 & 블루종 > 포켓터블` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98252|WOMEN|아우터 > 파카 & 블루종 > 후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98253|WOMEN|아우터 > 파카 & 블루종 > 재킷` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98254|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 코트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98255|WOMEN|아우터 > 경량 패딩 (PUFFTECH) > 컴팩트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98273|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 히트텍 후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98276|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 미니T` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98277|WOMEN|티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 터틀넥 & 하이넥` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98278|WOMEN|티셔츠 & UT > 스웨트셔츠 & 후드집업 > 드라이 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98279|WOMEN|티셔츠 & UT > 스웨트셔츠 & 후드집업 > 보아 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98281|WOMEN|티셔츠 & UT > 스웨트셔츠 & 후드집업 > 후드집업` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98282|WOMEN|티셔츠 & UT > 스웨트셔츠 & 후드집업 > 블루종` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98295|WOMEN|팬츠 > 슬랙스(트라우저) > 와이드 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98296|WOMEN|팬츠 > 슬랙스(트라우저) > 테이퍼드 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98297|WOMEN|팬츠 > 슬랙스(트라우저) > 셋업` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98298|WOMEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 보아 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98308|WOMEN|이너웨어 > 레깅스 & 타이즈 > 레깅스` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98309|WOMEN|이너웨어 > 레깅스 & 타이즈 > 타이즈` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98310|WOMEN|이너웨어 > 히트텍 > 히트텍 울트라 라이트` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98312|WOMEN|이너웨어 > 히트텍 > 히트텍 캐시미어 블렌드` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98313|WOMEN|이너웨어 > 히트텍 > 히트텍 엑스트라 웜` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98314|WOMEN|이너웨어 > 히트텍 > 히트텍 울트라 웜` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98323|WOMEN|스포츠 유틸리티 웨어 > 상의 > 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98324|WOMEN|스포츠 유틸리티 웨어 > 팬츠 > 스커트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98331|MEN|아우터 > 파카 & 블루종 > 재킷` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98333|MEN|아우터 > 파카 & 블루종 > 후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98334|MEN|아우터 > 경량 패딩 (PUFFTECH) > 컴팩트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98335|MEN|아우터 > 경량 패딩 (PUFFTECH) > 코트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98351|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > (X)소프트 브러시드` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98353|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > pick up` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98354|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > DRY` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98355|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > GU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98356|MEN|티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > (X)터틀넥` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98357|MEN|티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 보아 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98358|MEN|팬츠 > 캐주얼 팬츠 > 후리스 팬츠` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98359|MEN|팬츠 > 캐주얼 팬츠 > 코듀로이 팬츠` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98360|MEN|팬츠 > 치노 팬츠 > 와이드` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98361|MEN|팬츠 > 치노 팬츠 > 레귤러` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98362|MEN|팬츠 > 슬랙스(트라우저) > 셋업` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98363|MEN|팬츠 > 스웨트 팬츠 & 조거 팬츠 > 보아 스웨트` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98371|MEN|이너웨어 > 히트텍 > 히트텍 엑스트라 웜` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98372|MEN|이너웨어 > 히트텍 > 히트텍 울트라 웜` — invalid_semantic_tuple,category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98376|MEN|라운지 팬츠 > 라운지 팬츠 > 롱 팬츠` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98389|BABY|신생아(0개월~2세) > 아우터 > 후리스` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98393|WOMEN|아우터 > 파카 & 블루종 > 퍼프테크` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98490|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE Demon Slayer / Jujutsu Kaisen` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98491|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > KENSHI YONEZU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98492|WOMEN|티셔츠 & UT > 그래픽티셔츠 > UT ARCHIVE Demon Slayer / Jujutsu Kaisen` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|98493|WOMEN|티셔츠 & UT > 그래픽티셔츠 > KENSHI YONEZU` — category_only_missing_product_axis_or_detail
- `uniqlo|6b0627ec-e64b-44da-a403-6ae10976629c|99869|MEN|티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > Louvre x Camille Henrot` — category_only_missing_product_axis_or_detail

**zara (65)**

- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2417770|FEMALE|여성 > 컬렉션 > 자켓 | 점퍼` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2417772|FEMALE|여성 > 컬렉션 > 자켓 | 점퍼 > 모두 보기` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2419242|FEMALE|여성 > 컬렉션 > 진 | 데님팬츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420293|FEMALE|여성 > 컬렉션 > 니트웨어` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420368|FEMALE|여성 > 컬렉션 > 셔츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420416|FEMALE|여성 > 컬렉션 > 티셔츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420417|FEMALE|여성 > 컬렉션 > 티셔츠 > 모두 보기` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420453|FEMALE|여성 > 컬렉션 > 스커트` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420482|FEMALE|여성 > 컬렉션 > 쇼츠 | 버뮤다 팬츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420794|FEMALE|여성 > 컬렉션 > 팬츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420795|FEMALE|여성 > 컬렉션 > 팬츠 > 모두 보기` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2420944|FEMALE|여성 > 컬렉션 > 블레이저` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2431993|MALE|남성 > 컬렉션 > 셔츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2431994|MALE|남성 > 컬렉션 > 셔츠 > 모두 보기` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2432040|MALE|남성 > 컬렉션 > 티셔츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2432042|MALE|남성 > 컬렉션 > 티셔츠 > 모두 보기` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2432056|MALE|남성 > 컬렉션 > 피케 | 카라 티셔츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2432095|MALE|남성 > 컬렉션 > 팬츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2432096|MALE|남성 > 컬렉션 > 팬츠 > 모두 보기` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2432130|MALE|남성 > 컬렉션 > 데님팬츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2432163|MALE|남성 > 컬렉션 > 반바지 | 버뮤다팬츠` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2432264|MALE|남성 > 컬렉션 > 니트 | 여름 니트` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2436309|MALE|남성 > 컬렉션 > 블레이저` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2536906|MALE|남성 > 컬렉션 > 점퍼 | 자켓 > 모두 보기` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2537410|MALE|남성 > 컬렉션 > 점퍼 | 자켓` — category_only_missing_product_axis_or_detail
- `zara|42114e31-3542-4113-b8af-f5bc56b09bed|2664273|FEMALE|여성 > 컬렉션 > 점퍼 | 자켓` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:바지:B. Pant Denim|MALE|ZARA > 남성 > 바지 > B. Pant Denim` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:바지:F. Pant Resto|MALE|ZARA > 남성 > 바지 > F. Pant Resto` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:버뮤다반바지:F.Bermuda Resto|MALE|ZARA > 남성 > 버뮤다반바지 > F.Bermuda Resto` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:버뮤다반바지|MALE|ZARA > 남성 > 버뮤다반바지` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:브레이저:Blasier|MALE|ZARA > 남성 > 브레이저 > Blasier` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:브레이저|MALE|ZARA > 남성 > 브레이저` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:셔츠:B. Camisería|MALE|ZARA > 남성 > 셔츠 > B. Camisería` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:셔츠|MALE|ZARA > 남성 > 셔츠` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:스웨터:B. Jersey M/C|MALE|ZARA > 남성 > 스웨터 > B. Jersey M/C` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:스웨터|MALE|ZARA > 남성 > 스웨터` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:스웨트 셔츠:F. Sudadera|MALE|ZARA > 남성 > 스웨트 셔츠 > F. Sudadera` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:스웨트 셔츠|MALE|ZARA > 남성 > 스웨트 셔츠` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:스포츠 재킷:B. Cazadora|MALE|ZARA > 남성 > 스포츠 재킷 > B. Cazadora` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:스포츠 재킷|MALE|ZARA > 남성 > 스포츠 재킷` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|MAN:티셔츠|MALE|ZARA > 남성 > 티셔츠` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:가디건:KNIT CARDIGAN|FEMALE|ZARA > 여성 > 가디건 > KNIT CARDIGAN` — category_only_missing_product_axis_or_detail,product_decision_conflict
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:가디건|FEMALE|ZARA > 여성 > 가디건` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:바지:B.FOLDER PANTS|FEMALE|ZARA > 여성 > 바지 > B.FOLDER PANTS` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:버뮤다반바지:T.BERMUDAS|FEMALE|ZARA > 여성 > 버뮤다반바지 > T.BERMUDAS` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:버뮤다반바지|FEMALE|ZARA > 여성 > 버뮤다반바지` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:브레이저:B.BLAZER|FEMALE|ZARA > 여성 > 브레이저 > B.BLAZER` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:브레이저|FEMALE|ZARA > 여성 > 브레이저` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:셔츠:B.SHIRT|FEMALE|ZARA > 여성 > 셔츠 > B.SHIRT` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:셔츠|FEMALE|ZARA > 여성 > 셔츠` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:스포츠 재킷:T.SHORT-OUTWEAR|FEMALE|ZARA > 여성 > 스포츠 재킷 > T.SHORT-OUTWEAR` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:스포츠 재킷|FEMALE|ZARA > 여성 > 스포츠 재킷` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:치마:T.SKIRT|FEMALE|ZARA > 여성 > 치마 > T.SKIRT` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:치마|FEMALE|ZARA > 여성 > 치마` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:티셔츠:C.CTAS BASICAS|FEMALE|ZARA > 여성 > 티셔츠 > C.CTAS BASICAS` — category_only_missing_product_axis_or_detail
- `zara|69c66573-5611-48cc-b0af-f6cf9ca56681|WOMAN:티셔츠|FEMALE|ZARA > 여성 > 티셔츠` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|MAN:바지:Sastrería Pant.|MALE|ZARA > 남성 > 바지 > Sastrería Pant.` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|MAN:셔츠:F. Camisería|MALE|ZARA > 남성 > 셔츠 > F. Camisería` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|MAN:스포츠 재킷:F. Cazadora|MALE|ZARA > 남성 > 스포츠 재킷 > F. Cazadora` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|MAN:티셔츠:Camiseta M/L|MALE|ZARA > 남성 > 티셔츠 > Camiseta M/L` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|MAN:티셔츠:F. Camiseta|MALE|ZARA > 남성 > 티셔츠 > F. Camiseta` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|WOMAN:바지:B.PANTS|FEMALE|ZARA > 여성 > 바지 > B.PANTS` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|WOMAN:스포츠 재킷:B.SHORT-OUTWEAR|FEMALE|ZARA > 여성 > 스포츠 재킷 > B.SHORT-OUTWEAR` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|WOMAN:티셔츠:C.CTAS FANTASI|FEMALE|ZARA > 여성 > 티셔츠 > C.CTAS FANTASI` — category_only_missing_product_axis_or_detail
- `zara|a0e7a937-4035-4673-a629-455c68e128f0|WOMAN:티셔츠:C.CTAS POSICIO|FEMALE|ZARA > 여성 > 티셔츠 > C.CTAS POSICIO` — category_only_missing_product_axis_or_detail

</details>

Source mapping과 product decision이 충돌하는 current product의 dimension 분포:

| 값 | 건수 |
| --- | --- |
| source_mapping_vs_product_decision:detail | 485 |
| source_mapping_vs_product_decision:garment_type | 325 |
| source_mapping_vs_product_decision:comparison_family | 284 |
| source_mapping_vs_product_decision:category | 230 |
| source_mapping_vs_product_decision:length | 195 |
| source_mapping_vs_product_decision:body_length | 12 |

<details>
<summary>source mapping/product decision conflict product 전수 573건</summary>

**musinsa (0)**

없음

**uniqlo (572)**

`uniqlo:E444715`, `uniqlo:E447780`, `uniqlo:E450540`, `uniqlo:E450543`, `uniqlo:E453754`, `uniqlo:E454326`, `uniqlo:E454328`, `uniqlo:E455476`, `uniqlo:E457111`, `uniqlo:E457517`, `uniqlo:E457857`, `uniqlo:E457912`, `uniqlo:E457913`, `uniqlo:E458325`, `uniqlo:E458462`, `uniqlo:E458788`, `uniqlo:E459561`, `uniqlo:E459564`

`uniqlo:E459565`, `uniqlo:E459567`, `uniqlo:E460776`, `uniqlo:E461001`, `uniqlo:E461003`, `uniqlo:E461013`, `uniqlo:E463820`, `uniqlo:E464536`, `uniqlo:E465163`, `uniqlo:E465185`, `uniqlo:E465196`, `uniqlo:E465206`, `uniqlo:E465491`, `uniqlo:E465734`, `uniqlo:E466168`, `uniqlo:E467574`, `uniqlo:E468495`, `uniqlo:E468496`

`uniqlo:E469409`, `uniqlo:E469411`, `uniqlo:E469617`, `uniqlo:E469742`, `uniqlo:E469765`, `uniqlo:E469836`, `uniqlo:E469863`, `uniqlo:E469871`, `uniqlo:E470061`, `uniqlo:E470118`, `uniqlo:E470143`, `uniqlo:E470362`, `uniqlo:E470374`, `uniqlo:E470542`, `uniqlo:E470549`, `uniqlo:E471157`, `uniqlo:E471601`, `uniqlo:E471808`

`uniqlo:E471809`, `uniqlo:E472516`, `uniqlo:E472517`, `uniqlo:E472519`, `uniqlo:E472520`, `uniqlo:E473486`, `uniqlo:E473559`, `uniqlo:E473696`, `uniqlo:E473715`, `uniqlo:E474152`, `uniqlo:E474321`, `uniqlo:E474462`, `uniqlo:E474481`, `uniqlo:E474592`, `uniqlo:E474832`, `uniqlo:E475386`, `uniqlo:E475598`, `uniqlo:E475647`

`uniqlo:E475649`, `uniqlo:E475762`, `uniqlo:E475763`, `uniqlo:E475800`, `uniqlo:E476209`, `uniqlo:E476225`, `uniqlo:E476353`, `uniqlo:E476354`, `uniqlo:E476355`, `uniqlo:E476528`, `uniqlo:E476975`, `uniqlo:E476997`, `uniqlo:E477869`, `uniqlo:E478456`, `uniqlo:E478628`, `uniqlo:E478634`, `uniqlo:E478637`, `uniqlo:E478670`

`uniqlo:E478702`, `uniqlo:E478814`, `uniqlo:E478965`, `uniqlo:E479000`, `uniqlo:E479071`, `uniqlo:E479073`, `uniqlo:E479134`, `uniqlo:E479182`, `uniqlo:E479183`, `uniqlo:E479184`, `uniqlo:E479450`, `uniqlo:E479467`, `uniqlo:E479525`, `uniqlo:E479538`, `uniqlo:E479575`, `uniqlo:E479620`, `uniqlo:E479755`, `uniqlo:E480342`

`uniqlo:E480346`, `uniqlo:E480814`, `uniqlo:E480815`, `uniqlo:E480850`, `uniqlo:E480851`, `uniqlo:E480966`, `uniqlo:E480997`, `uniqlo:E481030`, `uniqlo:E481040`, `uniqlo:E481249`, `uniqlo:E481441`, `uniqlo:E481442`, `uniqlo:E481582`, `uniqlo:E481583`, `uniqlo:E481731`, `uniqlo:E481779`, `uniqlo:E481780`, `uniqlo:E481786`

`uniqlo:E481787`, `uniqlo:E481788`, `uniqlo:E481791`, `uniqlo:E481808`, `uniqlo:E481809`, `uniqlo:E481881`, `uniqlo:E481930`, `uniqlo:E481931`, `uniqlo:E481951`, `uniqlo:E481994`, `uniqlo:E482148`, `uniqlo:E482172`, `uniqlo:E482260`, `uniqlo:E482279`, `uniqlo:E482280`, `uniqlo:E482281`, `uniqlo:E482286`, `uniqlo:E482299`

`uniqlo:E482321`, `uniqlo:E482461`, `uniqlo:E482479`, `uniqlo:E482480`, `uniqlo:E482481`, `uniqlo:E482483`, `uniqlo:E482497`, `uniqlo:E482498`, `uniqlo:E482502`, `uniqlo:E482514`, `uniqlo:E482646`, `uniqlo:E482658`, `uniqlo:E482751`, `uniqlo:E482756`, `uniqlo:E482758`, `uniqlo:E482769`, `uniqlo:E482770`, `uniqlo:E482804`

`uniqlo:E482825`, `uniqlo:E482856`, `uniqlo:E482868`, `uniqlo:E482880`, `uniqlo:E482920`, `uniqlo:E482937`, `uniqlo:E482942`, `uniqlo:E482944`, `uniqlo:E483001`, `uniqlo:E483128`, `uniqlo:E483129`, `uniqlo:E483255`, `uniqlo:E483258`, `uniqlo:E483261`, `uniqlo:E483265`, `uniqlo:E483281`, `uniqlo:E483285`, `uniqlo:E483327`

`uniqlo:E483329`, `uniqlo:E483373`, `uniqlo:E483374`, `uniqlo:E483394`, `uniqlo:E483395`, `uniqlo:E483406`, `uniqlo:E483411`, `uniqlo:E483412`, `uniqlo:E483443`, `uniqlo:E483502`, `uniqlo:E483512`, `uniqlo:E483546`, `uniqlo:E483556`, `uniqlo:E483732`, `uniqlo:E483807`, `uniqlo:E483869`, `uniqlo:E483872`, `uniqlo:E483875`

`uniqlo:E483880`, `uniqlo:E483881`, `uniqlo:E483890`, `uniqlo:E483903`, `uniqlo:E483912`, `uniqlo:E483913`, `uniqlo:E483924`, `uniqlo:E483970`, `uniqlo:E484064`, `uniqlo:E484066`, `uniqlo:E484121`, `uniqlo:E484209`, `uniqlo:E484240`, `uniqlo:E484244`, `uniqlo:E484245`, `uniqlo:E484256`, `uniqlo:E484260`, `uniqlo:E484287`

`uniqlo:E484425`, `uniqlo:E484472`, `uniqlo:E484473`, `uniqlo:E484474`, `uniqlo:E484475`, `uniqlo:E484476`, `uniqlo:E484477`, `uniqlo:E484478`, `uniqlo:E484479`, `uniqlo:E484480`, `uniqlo:E484481`, `uniqlo:E484482`, `uniqlo:E484498`, `uniqlo:E484500`, `uniqlo:E484501`, `uniqlo:E484502`, `uniqlo:E484508`, `uniqlo:E484598`

`uniqlo:E484607`, `uniqlo:E484610`, `uniqlo:E484664`, `uniqlo:E484705`, `uniqlo:E484717`, `uniqlo:E484758`, `uniqlo:E484759`, `uniqlo:E484765`, `uniqlo:E484766`, `uniqlo:E484776`, `uniqlo:E484777`, `uniqlo:E484784`, `uniqlo:E484807`, `uniqlo:E484849`, `uniqlo:E484854`, `uniqlo:E484860`, `uniqlo:E484876`, `uniqlo:E484904`

`uniqlo:E484905`, `uniqlo:E484920`, `uniqlo:E484924`, `uniqlo:E484928`, `uniqlo:E484938`, `uniqlo:E484939`, `uniqlo:E484992`, `uniqlo:E484993`, `uniqlo:E485035`, `uniqlo:E485036`, `uniqlo:E485037`, `uniqlo:E485053`, `uniqlo:E485054`, `uniqlo:E485058`, `uniqlo:E485059`, `uniqlo:E485062`, `uniqlo:E485064`, `uniqlo:E485067`

`uniqlo:E485069`, `uniqlo:E485071`, `uniqlo:E485143`, `uniqlo:E485162`, `uniqlo:E485224`, `uniqlo:E485265`, `uniqlo:E485306`, `uniqlo:E485307`, `uniqlo:E485308`, `uniqlo:E485310`, `uniqlo:E485312`, `uniqlo:E485321`, `uniqlo:E485322`, `uniqlo:E485340`, `uniqlo:E485347`, `uniqlo:E485359`, `uniqlo:E485369`, `uniqlo:E485481`

`uniqlo:E485482`, `uniqlo:E485495`, `uniqlo:E485584`, `uniqlo:E485593`, `uniqlo:E485610`, `uniqlo:E485612`, `uniqlo:E485653`, `uniqlo:E485679`, `uniqlo:E485709`, `uniqlo:E485710`, `uniqlo:E485711`, `uniqlo:E485717`, `uniqlo:E485735`, `uniqlo:E485739`, `uniqlo:E485744`, `uniqlo:E485745`, `uniqlo:E485778`, `uniqlo:E486071`

`uniqlo:E486074`, `uniqlo:E486080`, `uniqlo:E486107`, `uniqlo:E486119`, `uniqlo:E486120`, `uniqlo:E486121`, `uniqlo:E486159`, `uniqlo:E486171`, `uniqlo:E486220`, `uniqlo:E486295`, `uniqlo:E486320`, `uniqlo:E486471`, `uniqlo:E486578`, `uniqlo:E486585`, `uniqlo:E486586`, `uniqlo:E486587`, `uniqlo:E486588`, `uniqlo:E486590`

`uniqlo:E486591`, `uniqlo:E486594`, `uniqlo:E486595`, `uniqlo:E486596`, `uniqlo:E486598`, `uniqlo:E486600`, `uniqlo:E486602`, `uniqlo:E486612`, `uniqlo:E486614`, `uniqlo:E486615`, `uniqlo:E486630`, `uniqlo:E486637`, `uniqlo:E486638`, `uniqlo:E486683`, `uniqlo:E486684`, `uniqlo:E486691`, `uniqlo:E486695`, `uniqlo:E486696`

`uniqlo:E486697`, `uniqlo:E486699`, `uniqlo:E486701`, `uniqlo:E486703`, `uniqlo:E486706`, `uniqlo:E486722`, `uniqlo:E486723`, `uniqlo:E486724`, `uniqlo:E486725`, `uniqlo:E486726`, `uniqlo:E486729`, `uniqlo:E486734`, `uniqlo:E486736`, `uniqlo:E486738`, `uniqlo:E486739`, `uniqlo:E486743`, `uniqlo:E486746`, `uniqlo:E486747`

`uniqlo:E486819`, `uniqlo:E486834`, `uniqlo:E487001`, `uniqlo:E487005`, `uniqlo:E487118`, `uniqlo:E487119`, `uniqlo:E487120`, `uniqlo:E487121`, `uniqlo:E487125`, `uniqlo:E487127`, `uniqlo:E487128`, `uniqlo:E487201`, `uniqlo:E487206`, `uniqlo:E487209`, `uniqlo:E487216`, `uniqlo:E487220`, `uniqlo:E487261`, `uniqlo:E487263`

`uniqlo:E487272`, `uniqlo:E487273`, `uniqlo:E487337`, `uniqlo:E487338`, `uniqlo:E487339`, `uniqlo:E487340`, `uniqlo:E487345`, `uniqlo:E487348`, `uniqlo:E487396`, `uniqlo:E487404`, `uniqlo:E487408`, `uniqlo:E487462`, `uniqlo:E487465`, `uniqlo:E487466`, `uniqlo:E487516`, `uniqlo:E487526`, `uniqlo:E487528`, `uniqlo:E487538`

`uniqlo:E487688`, `uniqlo:E487689`, `uniqlo:E487742`, `uniqlo:E487751`, `uniqlo:E487806`, `uniqlo:E487891`, `uniqlo:E487939`, `uniqlo:E487942`, `uniqlo:E487957`, `uniqlo:E487959`, `uniqlo:E487989`, `uniqlo:E487996`, `uniqlo:E488008`, `uniqlo:E488010`, `uniqlo:E488041`, `uniqlo:E488044`, `uniqlo:E488045`, `uniqlo:E488046`

`uniqlo:E488071`, `uniqlo:E488072`, `uniqlo:E488157`, `uniqlo:E488163`, `uniqlo:E488200`, `uniqlo:E488204`, `uniqlo:E488206`, `uniqlo:E488209`, `uniqlo:E488246`, `uniqlo:E488247`, `uniqlo:E488248`, `uniqlo:E488269`, `uniqlo:E488270`, `uniqlo:E488280`, `uniqlo:E488304`, `uniqlo:E488305`, `uniqlo:E488306`, `uniqlo:E488307`

`uniqlo:E488333`, `uniqlo:E488357`, `uniqlo:E488358`, `uniqlo:E488364`, `uniqlo:E488371`, `uniqlo:E488397`, `uniqlo:E488426`, `uniqlo:E488448`, `uniqlo:E488520`, `uniqlo:E488522`, `uniqlo:E488559`, `uniqlo:E488560`, `uniqlo:E488572`, `uniqlo:E488630`, `uniqlo:E488684`, `uniqlo:E488694`, `uniqlo:E488700`, `uniqlo:E488726`

`uniqlo:E488729`, `uniqlo:E488738`, `uniqlo:E488743`, `uniqlo:E488785`, `uniqlo:E488787`, `uniqlo:E488789`, `uniqlo:E488790`, `uniqlo:E488793`, `uniqlo:E488794`, `uniqlo:E488795`, `uniqlo:E488796`, `uniqlo:E488797`, `uniqlo:E488798`, `uniqlo:E488814`, `uniqlo:E488816`, `uniqlo:E488828`, `uniqlo:E488829`, `uniqlo:E488860`

`uniqlo:E488866`, `uniqlo:E488884`, `uniqlo:E488901`, `uniqlo:E488922`, `uniqlo:E488923`, `uniqlo:E488925`, `uniqlo:E488926`, `uniqlo:E488927`, `uniqlo:E488928`, `uniqlo:E488934`, `uniqlo:E488936`, `uniqlo:E488939`, `uniqlo:E488997`, `uniqlo:E489044`, `uniqlo:E489049`, `uniqlo:E489065`, `uniqlo:E489070`, `uniqlo:E489071`

`uniqlo:E489072`, `uniqlo:E489074`, `uniqlo:E489075`, `uniqlo:E489076`, `uniqlo:E489110`, `uniqlo:E489125`, `uniqlo:E489136`, `uniqlo:E489138`, `uniqlo:E489152`, `uniqlo:E489153`, `uniqlo:E489154`, `uniqlo:E489155`, `uniqlo:E489156`, `uniqlo:E489157`, `uniqlo:E489158`, `uniqlo:E489159`, `uniqlo:E489160`, `uniqlo:E489227`

`uniqlo:E489229`, `uniqlo:E489230`, `uniqlo:E489367`, `uniqlo:E489386`, `uniqlo:E489387`, `uniqlo:E489389`, `uniqlo:E489392`, `uniqlo:E489393`, `uniqlo:E489394`, `uniqlo:E489398`, `uniqlo:E489399`, `uniqlo:E489406`, `uniqlo:E489407`, `uniqlo:E489408`, `uniqlo:E489409`, `uniqlo:E489412`, `uniqlo:E489413`, `uniqlo:E489414`

`uniqlo:E489415`, `uniqlo:E489427`, `uniqlo:E489483`, `uniqlo:E489508`, `uniqlo:E489509`, `uniqlo:E489551`, `uniqlo:E489552`, `uniqlo:E489563`, `uniqlo:E489565`, `uniqlo:E489908`, `uniqlo:E489909`, `uniqlo:E489910`, `uniqlo:E489911`, `uniqlo:E489912`, `uniqlo:E489913`, `uniqlo:E489914`, `uniqlo:E489915`, `uniqlo:E489916`

`uniqlo:E490277`, `uniqlo:E490278`, `uniqlo:E490279`, `uniqlo:E490285`, `uniqlo:E490697`, `uniqlo:E491000`, `uniqlo:E491001`, `uniqlo:E491002`, `uniqlo:E491104`, `uniqlo:E491115`, `uniqlo:E491116`, `uniqlo:E491209`, `uniqlo:E491210`, `uniqlo:E491211`, `uniqlo:E491212`, `uniqlo:E491213`, `uniqlo:E491279`, `uniqlo:E491280`

`uniqlo:E491281`, `uniqlo:E491284`, `uniqlo:E491285`, `uniqlo:E491294`, `uniqlo:E491297`, `uniqlo:E491380`, `uniqlo:E491602`, `uniqlo:E491779`, `uniqlo:E491991`, `uniqlo:E492123`, `uniqlo:E492538`, `uniqlo:E493044`, `uniqlo:E493045`, `uniqlo:E493046`

**zara (1)**

`zara:547276687`

</details>

### UNIQLO category 82144

| source identity | decision | eligibility | semantic category | garment | family | reason | matched products |
| --- | --- | --- | --- | --- | --- | --- | --- |
| uniqlo\|6b0627ec-e64b-44da-a403-6ae10976629c\|82144\|MEN\|에어리즘 > 이너웨어 상의 > 크루넥 | confirmed | true | underwear | base_layer_top | base_layer_top | approved final classification artifact | 1 |

현재 82144는 category-level direct confirmed/eligible이며 `underwear/base_layer_top/base_layer_top`을 부여한다. 동일 category에 standalone T-shirt와 base-layer가 공존하므로 product-level resolution이 필요하다. Phase 1B에서는 active row 직접 수정이 아니라 successor release에서 `review_required/eligibility=false/reason=product_level_resolution_required` 후보로 바꿔야 한다.

## 7. product decision conflict 목록

Decision review reason 분포:

| 값 | 건수 |
| --- | --- |
| release_not_active | 5026 |
| independent_evidence_missing | 4819 |
| comparison_family_inactive_or_missing | 3826 |
| garment_type_not_stored_or_unambiguously_inferable | 3826 |
| product_not_in_current_catalog | 3819 |
| detail_not_active_under_category | 728 |
| required_sleeve_axis_invalid_or_missing | 357 |
| requires_user_confirmation | 330 |
| category_inactive_or_missing | 249 |
| fingerprint_mismatch | 222 |
| required_pants_axis_invalid_or_missing | 166 |
| current_history_conflict | 128 |
| required_body_axis_invalid_or_missing | 36 |

현재 schema에는 `authority_status`와 `garment_type_code`가 없다. 따라서 5,056건 전부를 verified로 볼 근거가 없고, 독립 evidence 237건과 self-consistency fixture-only 4814건을 분리해야 한다.

<details>
<summary>current history와 충돌하는 product decision 전수 128건</summary>

- `musinsa:3138552` — decision=bottoms/long_pants/pants/long_sleeve; current=bottoms/long_pants/pants/long_sleeve; fingerprint=mismatch; release=retired
- `musinsa:5074988` — decision=bottoms/long_pants/denim/long_sleeve; current=bottoms/long_pants/denim/long_sleeve; fingerprint=mismatch; release=retired
- `musinsa:5329359` — decision=outerwear/jumper/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:5343592` — decision=outerwear/fleece/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:5673055` — decision=outerwear/mouton/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6145321` — decision=bottoms/shorts/pants/short_sleeve; current=bottoms/shorts/pants/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6590793` — decision=tops/short_sleeve/tshirt/short_sleeve; current=tops/short_sleeve/tshirt/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6686050` — decision=outerwear/jacket/outerwear/unknown; current=outerwear/windbreaker/outerwear/unknown; fingerprint=mismatch; release=retired
- `musinsa:6686197` — decision=outerwear/jacket/outerwear/unknown; current=outerwear/jacket/outerwear/unknown; fingerprint=mismatch; release=retired
- `musinsa:6686260` — decision=tops/long_sleeve/tshirt/long_sleeve; current=tops/long_sleeve/tshirt/long_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6702426` — decision=bottoms/long_pants/pants/long_sleeve; current=bottoms/long_pants/pants/long_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6702453` — decision=outerwear/jacket/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6716203` — decision=tops/sleeveless/tshirt/sleeveless; current=tops/sleeveless/tshirt/sleeveless; fingerprint=mismatch; release=retired
- `musinsa:6716212` — decision=tops/sleeveless/tshirt/sleeveless; current=tops/sleeveless/tshirt/sleeveless; fingerprint=mismatch; release=retired
- `musinsa:6778715` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6778769` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6800912` — decision=tops/blouse/shirt/short_sleeve; current=tops/blouse/shirt/unknown; fingerprint=mismatch; release=retired
- `musinsa:6800975` — decision=dresses/one_piece/dress/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6805433` — decision=tops/short_sleeve/tshirt/short_sleeve; current=tops/short_sleeve/tshirt/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6814919` — decision=outerwear/jacket/outerwear/unknown; current=outerwear/jacket/outerwear/unknown; fingerprint=mismatch; release=retired
- `musinsa:6829741` — decision=outerwear/fleece/outerwear/unknown; current=outerwear/fleece/outerwear/unknown; fingerprint=mismatch; release=retired
- `musinsa:6833448` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6833866` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6837242` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6839271` — decision=tops/short_sleeve/tshirt/short_sleeve; current=tops/short_sleeve/tshirt/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6842612` — decision=tops/short_sleeve/tshirt/short_sleeve; current=tops/short_sleeve/tshirt/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6843694` — decision=tops/sleeveless/tshirt/sleeveless; current=tops/sleeveless/tshirt/sleeveless; fingerprint=mismatch; release=retired
- `musinsa:6849281` — decision=tops/polo_shirt/tshirt/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6852823` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6858118` — decision=tops/short_sleeve/tshirt/short_sleeve; current=tops/short_sleeve/tshirt/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6876277` — decision=tops/sleeveless/tshirt/sleeveless; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6878575` — decision=bottoms/long_pants/pants/long_sleeve; current=bottoms/long_pants/pants/long_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6883774` — decision=outerwear/fleece/outerwear/unknown; current=outerwear/fleece/outerwear/unknown; fingerprint=mismatch; release=retired
- `musinsa:6884177` — decision=bottoms/shorts/pants/short_sleeve; current=bottoms/shorts/pants/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6896595` — decision=tops/shirt/shirt/unknown; current=tops/blouse/shirt/unknown; fingerprint=mismatch; release=retired
- `musinsa:6903639` — decision=bottoms/long_pants/pants/long_sleeve; current=bottoms/long_pants/pants/long_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6907230` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6907832` — decision=bottoms/shorts/pants/short_sleeve; current=bottoms/shorts/pants/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6907891` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6908583` — decision=outerwear/padding/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6908905` — decision=outerwear/light_padding/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6912863` — decision=outerwear/jumper/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6914789` — decision=tops/long_sleeve/tshirt/long_sleeve; current=tops/long_sleeve/tshirt/long_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6927386` — decision=tops/short_sleeve/tshirt/short_sleeve; current=tops/short_sleeve/tshirt/short_sleeve; fingerprint=mismatch; release=retired
- `musinsa:6929142` — decision=outerwear/padding/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6929984` — decision=outerwear/padding/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6932766` — decision=tops/sweatshirt/sweatshirt/unknown; current=tops/sweatshirt/sweatshirt/unknown; fingerprint=mismatch; release=retired
- `musinsa:6933792` — decision=outerwear/jumper/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6957088` — decision=outerwear/padding/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `musinsa:6987932` — decision=outerwear/windbreaker/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E450535` — decision=tops/knit_top/knit_cardigan/unknown; current=tops/knit_top/knit_cardigan/unknown; fingerprint=mismatch; release=retired
- `uniqlo:E450536` — decision=tops/knit_top/knit_cardigan/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E455942` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E461420` — decision=bottoms/long_pants/pants/long_sleeve; current=homewear/loungewear/underwear/unknown; fingerprint=mismatch; release=retired
- `uniqlo:E465193` — decision=tops/long_sleeve/tshirt/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E465484` — decision=outerwear/cardigan/knit_cardigan/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E469410` — decision=tops/knit_top/knit_cardigan/unknown; current=tops/knit_top/knit_cardigan/long_sleeve; fingerprint=mismatch; release=retired
- `uniqlo:E473791` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E475344` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E477345` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E480345` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E481004` — decision=tops/knit_top/knit_cardigan/short_sleeve; current=tops/knit_top/knit_cardigan/short_sleeve; fingerprint=mismatch; release=retired
- `uniqlo:E482883` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483349` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483350` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483660` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483662` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483665` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483671` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483674` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483675` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483676` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483677` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483678` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483681` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483682` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483686` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483707` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483708` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E483896` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E484212` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E484214` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E484217` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E484218` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E484219` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E484220` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E484875` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E485318` — decision=tops/knit_top/knit_cardigan/unknown; current=tops/knit_top/knit_cardigan/unknown; fingerprint=mismatch; release=retired
- `uniqlo:E485530` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E485803` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E486042` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E486066` — decision=tops/knit_top/knit_cardigan/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E486103` — decision=tops/long_sleeve/tshirt/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E486176` — decision=outerwear/padding/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E486468` — decision=bottoms/long_pants/pants/long_sleeve; current=homewear/loungewear/underwear/unknown; fingerprint=mismatch; release=retired
- `uniqlo:E486704` — decision=tops/long_sleeve/tshirt/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E486982` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E487585` — decision=null/null/null/null; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E487589` — decision=bottoms/long_pants/pants/long_sleeve; current=homewear/loungewear/underwear/unknown; fingerprint=mismatch; release=retired
- `uniqlo:E487846` — decision=outerwear/blouson/outerwear/unknown; current=outerwear/blazer/outerwear/unknown; fingerprint=mismatch; release=retired
- `uniqlo:E488193` — decision=tops/hoodie/hoodie/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E488202` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E488203` — decision=bottoms/shorts/pants/short_sleeve; current=bottoms/shorts/pants/short_sleeve; fingerprint=mismatch; release=retired
- `uniqlo:E488239` — decision=dresses/one_piece/dress/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E488309` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E488652` — decision=outerwear/blazer/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E488739` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E488827` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E488976` — decision=dresses/one_piece/dress/sleeveless; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E489025` — decision=outerwear/blazer/outerwear/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E489026` — decision=outerwear/padding/outerwear/unknown; current=outerwear/blazer/outerwear/unknown; fingerprint=mismatch; release=retired
- `uniqlo:E489063` — decision=dresses/one_piece/dress/sleeveless; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E489168` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E489170` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E489171` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E489257` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E489258` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E491086` — decision=tops/knit_top/knit_cardigan/unknown; current=tops/knit_top/knit_cardigan/long_sleeve; fingerprint=mismatch; release=retired
- `uniqlo:E491096` — decision=outerwear/blouson/outerwear/unknown; current=outerwear/blouson/outerwear/unknown; fingerprint=mismatch; release=retired
- `uniqlo:E491231` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E491232` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E491233` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E491282` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E491283` — decision=tops/short_sleeve/tshirt/short_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E491287` — decision=tops/hoodie/hoodie/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E491288` — decision=tops/hoodie/hoodie/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E491289` — decision=tops/hoodie/hoodie/unknown; current=null/null/null/null; fingerprint=mismatch; release=retired
- `uniqlo:E492881` — decision=bottoms/long_pants/pants/long_sleeve; current=null/null/null/null; fingerprint=mismatch; release=retired

</details>

Fingerprint 상태는 match 1015, mismatch 222, current product absent 3819다. Retired release decision은 5026건이며, 이를 일괄 revoke하거나 legacy 기능을 일괄 차단해서는 안 된다.

## 8. local/DB/Closet/Compare mismatch

### Fixture local vs DB

현재 실행 결과:

| Test/audit | 결과 | 범위 | 비고 |
| --- | --- | --- | --- |
| CategoryValidation5026AuditTests | PASS | 5,026/5,026 | legacy fixture self-consistency |
| CategoryLive300ShadowAuditTests | PASS | 300 | confirmed 243 / review 29 / unclassified 28 |
| DBLogicReliabilityAuditTests | FAIL | 207 adjudicated; 31 products / 64 assertions | expected를 현재 결과에 맞춰 바꾸지 않음 |
| CurrentUniqloCatalogAuditTests | SKIPPED | fixture 880 rows | opt-in 환경이 XCTest process에 전달되지 않아 현재 실행 미검증 |
| Category/Closet/Compare offline boundary tests | PASS | 24 total: 13 pass / 11 live-only skip | MixedTop 2 + ReferenceClosetSetup 22; failure 0 |
| CategoryLiveComparisonAuditTests live corpus | NOT RUN | 71 products / 6 coverage gaps | explicit live-network opt-in; static path/fixture만 감사 |
| Closet sync tests | PASS | 2 | mock/local, DB write 없음 |
| Comparison sync tests | PASS | 2 | mock/local, DB write 없음 |
| Supabase resolver/DTO tests | PASS | 10 | 기존 additive JSON decode contract |

Result bundles: `/tmp/FitMatchPhase1A-20260825.xcresult`, `/tmp/FitMatchPhase1A-SyncDTO-20260825.xcresult`, `/tmp/FitMatchPhase1A-CategoryPath-20260825.xcresult`.

Fixture inventory:

| Fixture | rows | 감사 용도 |
| --- | --- | --- |
| CategoryValidation5026Inputs.json | 5,026 | local/DB legacy parity와 92 divergence 전수 |
| CategoryLiveComparisonInputs.json | 71 products + 6 gaps | source/detail/compare live manifest; live 실행은 보류 |
| CurrentUniqloCatalogInputs.json | 880 | current official catalog; 현 실행 SKIP |
| DBLogicReliabilityAdjudicationInputs.json | 207 | 독립 adjudication; 31 products/64 assertions 실패 |
| Musinsa1037ClassificationInputs.json | 1,037 | MUSINSA classification regression |
| Uniqlo243ClassificationInputs.json | 243 | UNIQLO classification/skort sentinel |
| LegacyMixed320ClassificationInputs.json | 320 | mixed-source legacy |
| LegacyUniqloThird320ClassificationInputs.json | 320 | UNIQLO legacy |
| LegacyUniqloRetest320ClassificationInputs.json | 320 | UNIQLO retest |
| LegacyMusinsaFourth320ClassificationInputs.json | 320 | MUSINSA legacy |
| LiveReleaseQA1200Inputs.json | 1,200 | release QA corpus |
| Musinsa1037FitPairInputs.json | 1,037 | MUSINSA comparison pairs |
| Uniqlo243FitPairInputs.json | 243 | UNIQLO comparison pairs |
| ThreeProductActualSizeFixtures.json | 3 | actual-size comparison sentinel |

5,026 local/DB mismatch:

| dimension | count |
| --- | --- |
| mismatch products | 92 |
| category | 1 |
| detail | 86 |
| family | 39 |
| length | 42 |
| eligibility | 0 |

<details>
<summary>5,026 fixture local/DB mismatch 전수 92건</summary>

- `uniqlo:E465196` AIRism코튼피케폴로셔츠(반팔) — detail; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/polo_shirt/tshirt/short_sleeve/false
- `uniqlo:E474152` STUDIO GHIBLI오픈칼라셔츠(반팔)C — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E482479` 오픈칼라셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E482480` 오픈칼라셔츠(반팔·프린트)A — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E482481` 오픈칼라셔츠(반팔·프린트)C — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E482483` 오픈칼라셔츠(반팔·프린트)B — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E482497` 박시셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E482498` 박시셔츠(반팔)체크 — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E482502` 코튼리넨셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E483875` 레이온블라우스(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/blouse/shirt/short_sleeve/false
- `uniqlo:E483881` 코튼도비V넥블라우스(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/blouse/shirt/short_sleeve/false
- `uniqlo:E483890` 리넨블렌드블라우스(슬리브리스) — detail,family; local=tops/sleeveless/tshirt/sleeveless/false; DB=tops/blouse/shirt/sleeveless/false
- `uniqlo:E484240` 레이온블라우스(반팔)도트 — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/blouse/shirt/short_sleeve/false
- `uniqlo:E484256` 프리미엄리넨스키퍼박시셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E484849` 옥스포드박시셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E484876` 프리미엄리넨오버사이즈셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E485584` 라이트코튼핀턱블라우스(슬리브리스) — detail,family; local=tops/sleeveless/tshirt/sleeveless/false; DB=tops/blouse/shirt/sleeveless/false
- `uniqlo:E486095` 워셔블니트팬츠(스무드) — family; local=homewear/loungewear/underwear/unknown/false; DB=homewear/loungewear/knit_cardigan/unknown/false
- `uniqlo:E486701` GU테크쇼트셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E486734` GU이지케어브로드클로스셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E486736` GU나일론포켓셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E486738` GU텍스처패턴셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E486834` GU드라이코치셔츠(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E487989` 엠브로이더리블라우스(슬리브리스) — detail,family; local=tops/sleeveless/tshirt/sleeveless/false; DB=tops/blouse/shirt/sleeveless/false
- `uniqlo:E488163` KIDS드라이스웨트와이드팬츠 — family; local=bottoms/long_pants/tshirt/long_sleeve/false; DB=bottoms/long_pants/pants/long_sleeve/false
- `musinsa:4448521` Striped Polo T-Shirt - Navy — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:4897679` 스트라이프 반팔 폴로 티셔츠(4colors) NPO4105 — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:4898835` [쿨]수피마_쿨맥스 피케 티셔츠 - 3color — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:4918856` 피그먼트 절개 카라 숏 슬리브 티셔츠 3 COLOR COOSTS258 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5005313` 클래식 세미 오버핏 코튼 피케 티셔츠 [블랙] — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:3325429` Olly Linen Like Short-Sleeve Knit - 5COL — length; local=tops/knit_top/knit_cardigan/short_sleeve/false; DB=tops/knit_top/knit_cardigan/unknown/false
- `musinsa:5049615` 백리본 나시 블라우스 (화이트) — detail,family; local=tops/sleeveless/tshirt/sleeveless/false; DB=tops/blouse/shirt/sleeveless/false
- `musinsa:5083349` (W) 우먼즈 트랙 라인 카라 크롭 티셔츠_핑크 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5155214` SQUARE NECK FRILL SLEEVELESS BLOUSE WHITE STAR — detail,family; local=tops/sleeveless/tshirt/sleeveless/false; DB=tops/blouse/shirt/sleeveless/false
- `musinsa:5328890` 자수 골지 세미크롭 사이드 버튼 후드 롱 슬림 긴팔 티셔츠 _ 3COLOR — detail,family; local=tops/hoodie/hoodie/long_sleeve/false; DB=tops/long_sleeve/tshirt/long_sleeve/false
- `musinsa:5369031` 와플 헨리넥 데일리 티셔츠 - 3color — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:557450` 루즈핏 카라티셔츠  네이비 JKST2066 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5996770` 와플 크롭 헨리넥 티셔츠 아이보리 — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6003424` [COOLMAX] 피케 반팔 티셔츠 아이보리 — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6007618` 시스루 립 티셔츠 (3color) — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6021383` 소프트 레이어드 헨리넥 티셔츠 블랙 — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6102710` 핀 스트라이프 세미 오버핏 카라 반팔 티셔츠 - 2color — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6111911` 피그먼트 폴로 티셔츠(3colors) NPO4986 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6136093` 오리진 로고 피케 반팔 티셔츠(MAGBTS13MNY) — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6196208` 키치 그래픽 카라 티셔츠 - BLACK — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6208753` (W) 로렌 피케 폴로 반팔 티셔츠 네이비 — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6233850` 그래픽 오프숄더 티셔츠  네이비 — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6245702` 오픈넥 소프트 반달피케 티셔츠  블랙 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6295936` ROUND COLLAR SHIRRING S/S TEE(STRIPE GREY) — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6295937` ROUND COLLAR SHIRRING S/S TEE(STRIPE RED) — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6405582` 체론 홀터넥 케이블 니트 슬리브리스 — detail,family; local=tops/sleeveless/tshirt/sleeveless/false; DB=tops/knit_top/knit_cardigan/sleeveless/false
- `musinsa:6411581` 누벨 세미 오버핏 코튼 피케 반팔 티셔츠 [블랙] — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6411626` 누벨 세미 오버핏 코튼 피케 반팔 티셔츠 [네이비] — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6523455` 썸머 슬리브 오픈버튼 루즈 카라 티셔츠 네이비 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6596322` Sheer button raglan t-shirt — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6786647` 스파링 클럽 롱슬리브 티셔츠 - 남성 M BXRW-SPCLLST [워시드 토푸] — detail,family; local=tops/sweatshirt/sweatshirt/long_sleeve/false; DB=tops/long_sleeve/tshirt/long_sleeve/false
- `uniqlo:E488426` KIDS드라이스웨트팬츠 — family; local=bottoms/long_pants/tshirt/long_sleeve/false; DB=bottoms/long_pants/pants/long_sleeve/false
- `uniqlo:E489136` 브로드셔츠(반팔)프린트A — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E489138` 옥스포드오버사이즈셔츠(반팔)프린트 — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E489229` 레이온블라우스(반팔) — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/blouse/shirt/short_sleeve/false
- `uniqlo:E489230` 레이온블라우스(반팔)도트 — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/blouse/shirt/short_sleeve/false
- `uniqlo:E490285` 오픈칼라셔츠(반팔·프린트)D — detail,family; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=tops/shirt/shirt/short_sleeve/false
- `uniqlo:E491320` KIDS PEANUTS코치재킷 — category,detail,family,length; local=tops/short_sleeve/tshirt/short_sleeve/false; DB=outerwear/windbreaker/outerwear/unknown/false
- `musinsa:4120496` [MXM1UWSHL001BL]Oversized-Smock Woven Shirt Long-Sleeve — length; local=tops/shirt/shirt/long_sleeve/false; DB=tops/shirt/shirt/unknown/false
- `musinsa:6220136` 레이어드 시어 텐셀 티셔츠 [NAVY] — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5180692` 린넨 시어 스트라이프 래글런 티셔츠 - 스카이 블루 — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6780850` Dusty Raglan Tee_Beige — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6208754` (W) 로렌 피케 폴로 반팔 티셔츠 화이트 — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:3324515` Becky Short-Sleeve Knit - 5COL — length; local=tops/knit_top/knit_cardigan/short_sleeve/false; DB=tops/knit_top/knit_cardigan/unknown/false
- `musinsa:4766684` 슬림 사이드 오프 레이어드 티셔츠_블랙 — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5976326` SITP5244 슬림 래글런 배색 티셔츠_Navy — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6916604` 나그랑 그래픽 티셔츠_MIWLWG944A — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5005669` 클래식 세미 오버핏 코튼 피케 티셔츠 [네이비] — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:4129471` [2PACK] 뉴웨이브 볼륨 카라 반팔티셔츠 6종 SJST1457 — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5892306` 브이넥 레이스 랩 티셔츠 ( 화이트 ) — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:2019456` 클래식 코튼 피케 카라 티셔츠 [블랙] — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5073514` [2PACK] 24수 링스펀 아시안핏 피케 카라 티셔츠 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:4992652` 시티보이 오버핏 럭비 카라 반팔 티셔츠 3Color — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5059809` Multi Stripe Rugby Collar T-shirt Red — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6821713` [KOIN SEOUL X WAS] 럭비 더블 스트라이프 카라 티셔츠 (NAVY) — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6780853` Dusty Raglan Tee_Dusty Blue — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5910000` Urban Muse Tee White — detail,length; local=tops/long_sleeve/tshirt/long_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5207928` POP 브러쉬 여성 폴로 티셔츠_Brown — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6120078` [MEN] 멀티 스트라이프 카라 티셔츠_레드 9156222211 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5063831` HENRYNECK RUGBY TEE GREY STRIPE — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6927129` T/C PK 폴로 무지 카라 반팔 티셔츠 -블랙 — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6788553` 남성 스위스 스키 팀그래픽 폴로 반팔 티셔츠 화이트 SR321SPS81 — detail; local=tops/polo_shirt/tshirt/short_sleeve/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5432501` ASCII Daybreak LS Hooded Tee Navy — detail,family,length; local=tops/hoodie/hoodie/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:6523456` 썸머 슬리브 오픈버튼 루즈 카라 티셔츠 아이보리 — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:5040898` MTN DIV 럭비 티셔츠 와인_FR2KT27U — detail,length; local=tops/polo_shirt/tshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:4753792` Chouette Point Sweat T-shirt (ivory) LFTAM25205IVX — detail,family,length; local=tops/sweatshirt/sweatshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false
- `musinsa:4753842` Chouette Point Sweat T-shirt (violet) LFTAM25205VLT — detail,family,length; local=tops/sweatshirt/sweatshirt/unknown/false; DB=tops/short_sleeve/tshirt/short_sleeve/false

</details>

<details>
<summary>207 adjudicated fixture 실패 product 전수 31건</summary>

- `musinsa:5049615` 백리본 나시 블라우스 (화이트) — detail,family
- `musinsa:5155214` SQUARE NECK FRILL SLEEVELESS BLOUSE WHITE STAR — detail,family
- `musinsa:6405582` 체론 홀터넥 케이블 니트 슬리브리스 — detail,family
- `uniqlo:E474152` STUDIO GHIBLI오픈칼라셔츠(반팔)C — detail,family
- `uniqlo:E482479` 오픈칼라셔츠(반팔) — detail,family
- `uniqlo:E482480` 오픈칼라셔츠(반팔·프린트)A — detail,family
- `uniqlo:E482481` 오픈칼라셔츠(반팔·프린트)C — detail,family
- `uniqlo:E482483` 오픈칼라셔츠(반팔·프린트)B — detail,family
- `uniqlo:E482497` 박시셔츠(반팔) — detail,family
- `uniqlo:E482498` 박시셔츠(반팔)체크 — detail,family
- `uniqlo:E482502` 코튼리넨셔츠(반팔) — detail,family
- `uniqlo:E483875` 레이온블라우스(반팔) — detail,family
- `uniqlo:E483881` 코튼도비V넥블라우스(반팔) — detail,family
- `uniqlo:E483890` 리넨블렌드블라우스(슬리브리스) — detail,family
- `uniqlo:E484240` 레이온블라우스(반팔)도트 — detail,family
- `uniqlo:E484256` 프리미엄리넨스키퍼박시셔츠(반팔) — detail,family
- `uniqlo:E484849` 옥스포드박시셔츠(반팔) — detail,family
- `uniqlo:E484876` 프리미엄리넨오버사이즈셔츠(반팔) — detail,family
- `uniqlo:E485584` 라이트코튼핀턱블라우스(슬리브리스) — detail,family
- `uniqlo:E486701` GU테크쇼트셔츠(반팔) — detail,family
- `uniqlo:E486734` GU이지케어브로드클로스셔츠(반팔) — detail,family
- `uniqlo:E486736` GU나일론포켓셔츠(반팔) — detail,family
- `uniqlo:E486738` GU텍스처패턴셔츠(반팔) — detail,family
- `uniqlo:E486834` GU드라이코치셔츠(반팔) — detail,family
- `uniqlo:E487989` 엠브로이더리블라우스(슬리브리스) — detail,family
- `uniqlo:E489136` 브로드셔츠(반팔)프린트A — detail,family
- `uniqlo:E489138` 옥스포드오버사이즈셔츠(반팔)프린트 — detail,family
- `uniqlo:E489229` 레이온블라우스(반팔) — detail,family
- `uniqlo:E489230` 레이온블라우스(반팔)도트 — detail,family
- `uniqlo:E490285` 오픈칼라셔츠(반팔·프린트)D — detail,family
- `uniqlo:E491320` KIDS PEANUTS코치재킷 — category,detail,family,length

</details>

207 adjudicated mismatch는 category 1, detail 31, family 31, length 1, confirmation 0으로 총 64 assertion이다.

### iOS production authority/call-path audit

| File | 현재 역할 | mismatch/risk |
| --- | --- | --- |
| Models/ParsedClosetClassification.swift | local category/detail/family/length 판정과 safety audit | local authority가 DB와 독립; 5,026에서 92건 divergence |
| Models/CanonicalComparisonProfile.swift | DB/bundle family와 length axis를 app enum으로 변환 | garment와 comparison family가 하나의 app family로 축약됨 |
| Models/GarmentComparisonAttributes.swift | family별 display/attribute helper | classification authority가 아니라 presentation layer |
| Services/CanonicalComparisonProfileResolver.swift | canonical profile을 Product/UserFit에 적용 | `appGarmentFamily`를 product/item garmentType에 기록 |
| Services/CanonicalTaxonomyBundleStore.swift | bundled mappings/policies와 family transform 로드 | active DB release와 별도 snapshot; drift 가능 |
| Services/FitMatchSupabaseProductResolver.swift | observation submit, resolve/runtime/closet/comparison RPC DTO | classification DTO에 garment_type/authority 없음 |
| Services/ComparisonProfileMatcher.swift | local category/family/length/measurement eligibility 및 후보 선택 | DB evaluator와 독립 구현 |
| Services/RecommendationService.swift | matcher와 measurement engine을 이용해 추천 | confirmed comparison 결과만 채택하지만 입력 profile authority는 local |
| ViewModels/ShoppingProductViewModel.swift | local 결과를 production UI에 사용하고 DB는 shadow 비교 | DB confirmed도 local을 대체하지 않음; 관찰 submit은 app runtime write 경로 |
| Views/LinkClosetRegistrationView.swift | link import 후 local classification으로 garment family 설정 | DB garment authority를 직접 사용하지 않음 |
| Views/CompareFlowSheet.swift | local parsed classification과 matcher로 selection/eligibility 구성 | DB candidate/begin과 별도 local gate |
| Views/AddComparedProductToClosetSheet.swift | user category 확정 후 local tuple 재생성·저장 | manual flow 보존 필요 |
| Services/FitMatchClosetSyncCoordinator.swift | closet RPC sync와 DB classification snapshot 적용 | DB familyCode를 garmentTypeRawValue로 저장 |
| Services/FitMatchComparisonSyncCoordinator.swift | runtime → candidates → begin comparison DB flow와 local parity 확인 | 두 authority 불일치 시 parity warning/fail-closed |

### Closet path

| metric | count |
| --- | --- |
| total | 6 |
| active | 1 |
| soft_deleted | 5 |
| confirmed | 6 |
| manual_override | 6 |
| linked_product | 0 |
| garment_type_present | 6 |

현재 active closet item 1건은 manual override `tops/short_sleeve/tshirt`, garment_type `tshirt`, product_id 없음이다. 삭제 포함 6건 모두 manual override이고 garment_type은 존재한다. 따라서 이번 production row만으로 linked-product automatic classification 회귀를 동적으로 입증할 수는 없다.

정적 call path에서 `FitMatchClosetSyncCoordinator.applyClassification`은 DB `familyCode`를 `garmentTypeRawValue`로 넣는다. granular garment와 comparison family가 분리되면 잘못된 저장이 되므로 Phase 1B DB 응답의 garment code를 별도 소비하기 전까지 linked flow는 보수적으로 fail closed해야 한다. 단, 이번 Phase에서는 Swift를 수정하지 않았다.

현재 `public.fitmatch_list_closet_items`는 기존 category/detail/family/length/snapshot key를 반환하지만 `garment_type_code`는 반환하지 않는다. signature/security/search_path는 위 baseline과 같으며 Phase 1B 필드 추가는 additive여야 한다.

### Compare path

Current active closet item과 fixture-overlap product 1,207건에 대해 동일 DB comparison policy evaluator에 DB current tuple과 local fixture tuple을 각각 넣은 shadow 결과:

| metric | count |
| --- | --- |
| evaluated | 1207 |
| db_auto_ready | 36 |
| local_tuple_auto_ready | 55 |
| db_allowed_local_blocked | 0 |
| db_blocked_local_allowed | 19 |
| db_manual_ready | 134 |
| local_tuple_manual_ready | 133 |
| db_manual_allowed_local_blocked | 2 |
| db_manual_blocked_local_allowed | 1 |

이 shadow는 `ComparisonProfileMatcher` Swift를 실제 실행한 결과가 아니라, 동일 measurement/policy 데이터에 local tuple을 주입한 DB-side parity 검사다. DB blocked/local allowed 19건, DB allowed/local blocked 0건이며 manual override 허용 방향도 각각 1/2건이다.

<details>
<summary>Closet/Compare policy shadow divergence 전수 22건</summary>

- `uniqlo:E469410` — auto DB/local=false/false (family_incompatible/length_classification_missing); manual DB/local=true/false (null/length_classification_missing)
- `uniqlo:E474152` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E482479` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E482480` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E482481` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E482483` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E482497` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E482498` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E482502` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E483875` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E483881` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E484876` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E486701` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E486734` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E486736` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E486738` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E489138` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E489229` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E489230` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `uniqlo:E490285` — auto DB/local=false/true (family_incompatible/null); manual DB/local=true/true (null/null)
- `musinsa:6800912` — auto DB/local=false/false (length_classification_missing/family_incompatible); manual DB/local=false/true (length_classification_missing/null)
- `uniqlo:E491086` — auto DB/local=false/false (family_incompatible/length_classification_missing); manual DB/local=true/false (null/length_classification_missing)

</details>

실제 DB comparison history는 0건이어서 migration 영향 row는 0이다. `fitmatch_find_reference_candidates`와 `fitmatch_begin_comparison`은 current history tuple을 쓰고, iOS `FitMatchComparisonSyncCoordinator`는 DB runtime/candidates/begin 결과를 local profile과 다시 대조한다.

## 9. 전체 product reclassification preview

Machine-readable manifest: [FitMatchClassificationGlobalBaseline-20260825.jsonl](./FitMatchClassificationGlobalBaseline-20260825.jsonl)

- JSONL rows: 1608; unique `source + external_product_id`: 1608; production products coverage: 100.0%.
- JSONL SHA256: `086ee910b6f17d7b2c813edddd1b14ba400831367396135c4808d2b59edd8ed6`.
- 모든 row에 요청 필드, current/proposed tuple, change_type, evidence, confidence basis, conflict dimensions, manual review, affected closet/comparison count를 포함했다.
- Preview precedence: owner/manual verified evidence → clear active source mapping → eligible name/path profile → matching legacy decision → verified exclusion → review_required.
- 실제 DB에 authority_status가 없으므로 “verified”는 owner Golden, official structured source, 명시 adjudication/correction evidence로 제한했다.
- Preview는 data 변경용 SQL이 아니며 current expected를 자동 승인하지 않는다.

Change type:

| change_type | TOTAL | musinsa | uniqlo | zara |
| --- | --- | --- | --- | --- |
| unchanged_valid | 32 | 32 | 0 | 0 |
| correctable_mapping | 0 | 0 | 0 | 0 |
| correctable_product_decision | 3 | 0 | 3 | 0 |
| invalid_confirmed | 949 | 239 | 689 | 21 |
| ambiguous | 276 | 6 | 261 | 9 |
| not_comparable | 4 | 1 | 3 | 0 |
| stale_history | 344 | 116 | 228 | 0 |
| missing_evidence | 0 | 0 | 0 | 0 |

Proposed status:

| 값 | 건수 |
| --- | --- |
| review_required | 1120 |
| not_comparable | 296 |
| confirmed | 192 |

Confidence basis:

| basis | rows |
| --- | --- |
| source_mapping_requires_product_evidence | 831 |
| exclusion_profile_or_mapping | 296 |
| missing_or_ambiguous_evidence | 289 |
| auto_eligible_name_profile | 118 |
| clear_complete_source_mapping | 36 |
| self_consistency_fixture_only_backward_compatibility | 27 |
| auto_eligible_path_profile | 5 |
| owner_verified | 3 |
| adjudicated_fixture_backward_compatibility | 2 |
| official_structured_source_backward_compatibility | 1 |

`requires_manual_review=true`는 1,147건, false는 461건이다.

### 세 Golden case

Tuple 표기: `category/detail/garment/family/length/body/status`.

| product | current | proposed | current product fingerprint | evidence | manual review |
| --- | --- | --- | --- | --- | --- |
| E482514 | underwear / underwear / ∅ / underwear / unknown / ∅ / confirmed | tops / short_sleeve / tshirt / tshirt / short_sleeve / ∅ / confirmed | 33119909d27567ab432c0b27c6f6aae8 | owner_verified_standalone_tshirt | no |
| E454311 | underwear / underwear / ∅ / underwear / unknown / ∅ / confirmed | tops / base_layer_top / base_layer_top / base_layer_top / short_sleeve / ∅ / confirmed | 670669aa2beb25167e781f721ed7d9ed | verified_base_layer_top | no |
| E456567 | underwear / underwear / ∅ / underwear / unknown / ∅ / confirmed | tops / base_layer_top / base_layer_top / base_layer_top / short_sleeve / ∅ / confirmed | 67852370ebdc165b23b66e497ac074fc | verified_base_layer_top | no |

세 행의 proposed decision_version은 `authoritative-product-2026-08-25-v1`이다. E454311/E456567은 반드시 `tops/base_layer_top/base_layer_top/base_layer_top/short_sleeve/confirmed`이며 underwear로 저장하지 않는다.

### 대표 source/hybrid subset

아래는 owner Golden이 아니라 기존 production/fixture에서 추출한 대표 감사 subset이다. `official_structured_source` 외에는 검토용 sentinel로만 사용한다.

| product | name | current category/detail/family/status | preview category/detail/garment/family/status | trust | change |
| --- | --- | --- | --- | --- | --- |
| musinsa:3132891 | 리즌 트레일 피그먼트 반팔티 마젠타 | tops/short_sleeve/tshirt/confirmed | tops/short_sleeve/tshirt/tshirt/confirmed | self_consistency_fixture_only | stale_history |
| musinsa:1884480 | [2PACK] 코스모 밴딩 숏팬츠 2PACK JMSP2332 | bottoms/shorts/pants/confirmed | bottoms/shorts/other_standard_pants/standard_pants/confirmed | self_consistency_fixture_only | invalid_confirmed |
| musinsa:5661658 | 우먼즈 체크 텍스처드 베이비 돌 블라우스 [블랙] | tops/blouse/shirt/confirmed | tops/shirt_blouse/shirt_blouse/shirt_blouse/review_required | none | invalid_confirmed |
| musinsa:4513309 | 헤비 플리스 집업 후드 - 스카이 캡틴 / T4029683 | outerwear/fleece/outerwear/confirmed | outerwear/fleece/fleece_jacket/fleece_jacket/review_required | self_consistency_fixture_only | invalid_confirmed |
| musinsa:4821229 | 메트로폴리스 퍼텍스 오버셔츠 재킷 - 블랙 / 18CLOS020A110033A999 | outerwear/jacket/outerwear/confirmed | outerwear/jacket/generic_jacket/unclassified_outerwear/review_required | self_consistency_fixture_only | invalid_confirmed |
| musinsa:4800605 | [여름/사계절] 시비코 세미 오버핏 싱글 셋업 수트 [그레이] | ∅/∅/∅/review_required | ∅/∅/∅/∅/review_required | self_consistency_fixture_only | stale_history |
| uniqlo:E422992 | 크루넥T | tops/short_sleeve/tshirt/confirmed | tops/short_sleeve/tshirt/tshirt/confirmed | self_consistency_fixture_only | stale_history |
| uniqlo:E450259 | 옥스포드셔츠 | tops/shirt/shirt/confirmed | tops/shirt_blouse/shirt_blouse/shirt_blouse/review_required | self_consistency_fixture_only | invalid_confirmed |
| uniqlo:E450535 | 메리노크루넥스웨터 | tops/knit_top/knit_cardigan/confirmed | tops/cardigan/knit_sweater/knit_sweater/review_required | adjudicated_fixture | invalid_confirmed |
| uniqlo:E476997 | 워셔블니트폴로스웨터(반팔) | tops/knit_top/knit_cardigan/confirmed | tops/short_sleeve/knit_sweater/knit_sweater/review_required | self_consistency_fixture_only | invalid_confirmed |
| uniqlo:E454063 | GIRLS AIRism코튼블렌드캐미솔 | underwear/women_camisole/underwear/confirmed | underwear/women_camisole/∅/∅/review_required | self_consistency_fixture_only | invalid_confirmed |
| uniqlo:E487348 | PUFFTECH베스트 | outerwear/padding/outerwear/confirmed | outerwear/vest/puffer_vest/puffer_vest/review_required | self_consistency_fixture_only | invalid_confirmed |
| uniqlo:E488203 | 코듀로이큐롯 | bottoms/shorts/pants/confirmed | bottoms/shorts/other_standard_pants/standard_pants/review_required | self_consistency_fixture_only | invalid_confirmed |
| uniqlo:E488814 | 스마트큐롯(프린트) | bottoms/shorts/pants/confirmed | bottoms/shorts/other_standard_pants/standard_pants/review_required | self_consistency_fixture_only | invalid_confirmed |
| zara:545406831 | 아론 레빈 x ZARA 스웨이드 레더 재킷 | outerwear/jacket/outerwear/confirmed | outerwear/jacket/generic_jacket/unclassified_outerwear/review_required | official_structured_source | invalid_confirmed |
| zara:545892778 | 숏 슬리브 티셔츠 | tops/short_sleeve/tshirt/confirmed | tops/short_sleeve/tshirt/tshirt/review_required | official_structured_source | ambiguous |
| zara:548577264 | 배럴 팬츠 | bottoms/long_pants/pants/confirmed | bottoms/long_pants/other_standard_pants/standard_pants/review_required | official_structured_source | invalid_confirmed |
| zara:552163213 | AARON LEVINE X ZARA 트윌 체크 셔츠 | tops/shirt/shirt/confirmed | tops/shirt_blouse/shirt_blouse/shirt_blouse/review_required | official_structured_source | invalid_confirmed |
| zara:558215502 | ZW 컬렉션 프린트 롱 원피스 | dresses/one_piece/dress/confirmed | dresses/one_piece/∅/∅/review_required | official_structured_source | invalid_confirmed |

Hybrid/ambiguous keyword coverage:

| case | production current candidates | fixture evidence | 판정 |
| --- | --- | --- | --- |
| shirt jacket / overshirt | 3/3 | MUSINSA 4821229, UNIQLO E481388/E482452 등 | outerwear vs shirt product-level review |
| knit polo | 3 | UNIQLO E476997/E485612/E486746 | detail/family/length 분리 검토 |
| bra top/camisole | 12 | UNIQLO E454063/E465707 등 | tops base-layer와 underwear 충돌 검토 |
| padded vest | 7 | UNIQLO E487348 등 | puffer vest/vest group 검토 |
| skort/culotte | production keyword 0 | E488203, E488694, E488814, MUSINSA 4200529 | fixture-only; shorts/skirt hybrid 명시 review |
| jumpsuit/set-up | 4 | MUSINSA 4800605/5097306/6111537 등 | single item vs set-up not_comparable 검토 |
| unknown/malformed | production explicit candidate 0 | unknown/malformed negative fixture | confirmed 금지, review/not_comparable |
| COS | production DB products 0 | 1229297007 fail-closed; 1349394002 official size guide | app-only sentinel; DB end-to-end 미검증 |

COS production path는 `COSParser`와 URL routing에 실제 존재한다. Fixture `1229297007`은 공식 metadata는 보존하되 size chart가 없으면 partial/fail-closed, `1349394002`는 공식 garment size guide의 S/M 실측을 파싱한다. 그러나 production DB source row가 없으므로 classification authority까지 검증됐다고 간주하지 않는다.

### Manifest schema

각 JSONL row는 다음 핵심 키를 가진다.

`source`, `external_product_id`, `product_name`, `source_category_path`, `source_category_codes`, `input_fingerprint`, `current`, `proposed`, `change_type`, `evidence`, `confidence_basis`, `conflict_dimensions`, `requires_manual_review`, `affected_closet_item_count`, `affected_comparison_history_count`, `comparison_readiness`.

## 10. 유지할 기존 구조

- `fitmatch_catalog.products`, observations, snapshots, sizes/measurements의 identity와 원본 데이터.
- `product_classification_history`의 append/supersede 구조와 product별 single-current invariant.
- `source_category_mappings`의 release-scoped successor publishing 구조.
- public canonical taxonomy/measurement/comparison policy 테이블과 UUID FK 모델.
- existing RPC signatures와 기존 JSON key; 신규 필드는 additive.
- manual closet override 우선권과 soft-delete.
- private catalog RLS/service-only 접근, public RPC SECURITY DEFINER와 `search_path=""`.
- legacy decision의 backward compatibility. authority를 붙이되 일괄 revoke/차단하지 않는다.
- fixture expected는 독립 adjudication 전에는 그대로 보존한다.

## 11. Phase 1B에서 수정할 DB object 정확한 목록

Phase 1B는 아래 대상으로 한정한다.

1. `fitmatch_catalog.product_classification_decisions`
   - additive `garment_type_code`, `authority_status`, verified completeness CHECK.
   - garment code uniqueness/data validation 후에만 FK.
2. `fitmatch_catalog.product_classification_history`
   - additive `garment_type_code`; 기존 current/superseded 구조 유지.
3. `fitmatch_catalog.releases`, `fitmatch_catalog.source_category_mappings`
   - active 3,492 mappings을 복제한 validated successor release.
   - 82144와 본 audit의 risky/conflict manifest에서 승인된 mapping만 최소 수정.
   - expected count/checksum/report/gate 통과 후 activation.
4. `fitmatch_catalog.classification_name_profiles`, `classification_path_profiles`, `classification_exclusion_profiles`
   - legacy family vocabulary를 canonical garment/group vocabulary로 versioned 재생성하거나 ambiguous를 auto-ineligible로 전환.
5. `fitmatch_catalog.runtime_resolve_product_classification_v4`
   - verified product → clear mapping → verified profile → legacy exact → verified exclusion → review 순서와 additive response.
6. `fitmatch_catalog.runtime_resolve_and_promote_product`
   - fingerprint뿐 아니라 decision_version, mapping_release_id, garment_type_code를 비교하고 다르면 supersede+insert.
7. `fitmatch_catalog.runtime_record_product_classification_v2`
   - garment 기록; 기존 function은 signature-preserving wrapper.
8. `public.fitmatch_resolve_product`, `public.fitmatch_get_product_runtime`
   - existing keys 유지, garment/authority/release/version/status/confidence/evidence additive.
9. `public.fitmatch_upsert_closet_item`, `public.fitmatch_list_closet_items`
   - garment code → garment_type_id lookup, invalid/missing은 confirmed로 위장하지 않음, manual override 유지.
10. `public.fitmatch_find_reference_candidates`, `public.fitmatch_begin_comparison` 및 내부 comparison evaluator
    - strict canonical garment/group/length와 measurement policy를 사용하고 legacy generic family를 자동 허용하지 않음. 외부 signatures 유지.
11. `fitmatch_catalog.data_quality_issues`와 release gate object
    - local migration 114와 production 상태를 먼저 reconcile. 없는 `data_quality_review_queue`를 gate 우회 없이 도입.
12. Canonical row set `public.garment_types` / `public.comparison_groups`
    - dresses/underwear/homewear 등 현재 confirmed이지만 active garment/group으로 표현할 수 없는 범위를 “신규 canonical row 추가” 또는 “not_comparable/review” 중 owner 결론으로 확정. 새 테이블은 만들지 않는다.
13. 세 Golden product decision/current history
    - current product name/path로 계산된 fingerprint를 사용해 verified decision 생성, 기존 current 삭제 없이 supersede, 새 current 정확히 1건.

## 12. 수정하지 않을 object

- `fitmatch_catalog.products`, `product_observations`, `source_product_snapshots` 원본 row.
- size, variant, normalized measurement, source measurement evidence.
- 기존 classification history 삭제 또는 current history 대량 삭제.
- `public.closet_items`의 별도 garment 문자열 column 추가.
- manual closet override 값과 사용자 실측.
- comparison history 원본(현재 0건이어도 contract 보존).
- existing RPC argument signature와 기존 JSON keys.
- active release row의 in-place update.
- production Swift/DTO/UI. iOS 변경은 별도 Phase에서만 수행.
- fixture expected 자동 변경.
- RLS/GRANT/SECURITY DEFINER/search_path baseline.
- 새 table 생성은 Phase 1B 분류 contract에도 필요하지 않다.

## 13. data migration/backfill plan

1. Production migration ledger와 local 113/114를 대조하고 release gate를 먼저 설치·검증한다.
2. canonical garment/group/detail compatibility matrix를 owner-reviewed artifact로 고정한다. dresses/underwear/homewear 처리 결론 전에는 backfill하지 않는다.
3. additive decision/history columns와 CHECK를 idempotent하게 추가한다. 기존 decision은 default `legacy`.
4. active mapping 3,492건을 successor candidate에 그대로 복제하고 82144 및 승인된 conflict/risk row만 수정한다.
5. name/path/exclusion profile을 새 policy version으로 생성하고 ambiguous row는 auto-eligible에서 제외한다.
6. Gold 3건을 실제 current fingerprint로 verified seed한다.
7. 동일 Phase 1A preview schema로 products 1,608건을 재계산한다. proposed/current version·release·garment가 다르면 기존 current를 supersede하고 새 history를 append한다.
8. linked closet item만 valid garment code를 UUID로 매핑한다. manual override와 measurements는 보존한다. 현재 production에는 linked closet item이 0건이다.
9. strict comparison readiness를 재계산하고 candidates/begin parity를 검증한다.
10. candidate release checksum/expected mapping count/validation report/QA/security 검증 완료 후에만 activation한다.

## 14. rollback plan

- Successor release 활성화 전: candidate를 active로 만들지 않고 그대로 폐기/retire한다. 기존 active release는 수정하지 않는다.
- 활성화 후 mapping rollback: 이전 release `65d72393-4a40-4e99-b701-fdc1ff865774`를 동일 gate를 거친 rollback release의 source로 사용한다. active row를 직접 변조하지 않는다.
- verified decision rollback: 잘못된 새 decision을 `revoked`로 전환하고 legacy row는 보존한다.
- history rollback: 새 current를 삭제하지 않고 supersede한 뒤 이전 tuple을 새 rollback current row로 append한다. product별 current=1 invariant를 transaction constraint로 확인한다.
- schema additive columns/functions은 기존 client와 호환되므로 즉시 drop하지 않는다. old wrappers를 유지해 traffic을 되돌린다.
- closet/measurement/product/snapshot/observation data는 어느 단계에서도 삭제하지 않는다.
- RLS/GRANT/function-definition baseline md5를 migration 전후 비교하고 unexpected drift가 있으면 activation을 중단한다.

## 15. Phase 1B acceptance criteria

- migration idempotency와 release gate validation PASS; gate 우회 0.
- 새 table 0, 삭제 table 0, production Swift 변경 0.
- products 1608건과 active mappings 3492건을 다시 100% 계량.
- product별 current history 정확히 1, stale current 0.
- verified confirmed tuple은 category/detail/garment/group/major/length/policy 규칙을 100% 통과.
- legacy confirmed는 authority_status로 명시되고 기능 보존 범위가 별도 집계되며 대량 차단/삭제 없음.
- revoked decision resolver 사용 0; changed fingerprint verified decision 재사용 0.
- mapping/product decision silent conflict 0; 82144 category-only auto-confirmed 0.
- Gold:
  - E482514 = `tops/short_sleeve/tshirt/tshirt/short_sleeve/confirmed`
  - E454311 = `tops/base_layer_top/base_layer_top/base_layer_top/short_sleeve/confirmed`
  - E456567 = E454311과 동일
- public RPC 기존 keys/signatures 유지, garment/authority additive.
- closet manual override regression 0; valid linked classification만 garment_type_id 저장.
- strict measurement policy와 candidates/begin comparison parity PASS.
- products/observations/snapshots/sizes/measurements/closet counts가 예상 밖으로 감소하지 않음.
- 5,026 QA에서 예상 밖 실패 0. 현재 92 local/DB divergence와 207 adjudicated의 31-product/64-assertion 실패는 owner evidence로 명시적으로 해결하며 expected를 결과에 맞춰 자동 수정하지 않음.
- RLS/GRANT/SECURITY DEFINER/search_path unexpected drift 0.

## 16. 확인되지 않은 내용

- `CurrentUniqloCatalogAuditTests` 880건은 현 실행에서 opt-in 환경이 XCTest process에 전달되지 않아 SKIP됐다. fixture row 수만 확인했으며 PASS로 기록하지 않는다.
- `CategoryLiveComparisonAuditTests`의 71-product live network corpus는 실행하지 않았다. offline boundary subset은 13 pass/11 live-only skip이지만 live parser 결과로 확대 해석하지 않는다.
- COS는 app parser/fixture가 있으나 production DB product/mapping/decision이 0건이다. DB end-to-end classification/closet/compare contract는 확인되지 않았다.
- Skort/culotte는 기존 fixtures에 있으나 현재 production product keyword candidate는 0건이다. production truth로 승격하지 않았다.
- active release는 expected/actual mapping count가 일치하고 `validated_at`이 있지만 `expected_qa_count=0`, `qa_full_validation_included=false`, production release-gate queue 부재이므로 gate가 실제 통과됐다고 확인할 수 없다.
- current production에는 linked closet item과 comparison history가 없어 실제 사용자 linked migration 효과를 동적 검증할 수 없다.
- 1,207-row comparison shadow는 동일 DB evaluator에 local tuple을 넣은 결과다. Swift `ComparisonProfileMatcher` 자체의 전수 실행은 아니며, 5,026 fixture 중 production product와 겹치지 않는 row는 DB current comparison shadow 대상이 아니다.
- 기존 5,026 expected와 decision evidence 대부분은 같은 QA corpus에서 파생되어 독립 정답이 아니다. PASS는 self-consistency 증거이지 semantic correctness 증거가 아니다.
- dresses/underwear/homewear confirmed를 위한 canonical garment/group을 추가할지, 비교 불가/review로 내릴지는 owner taxonomy 결정이 필요하다.
- 이 audit session이 실행한 statement는 SELECT/metadata 조회뿐이다. 동시간대 다른 actor의 write 여부까지 증명하지는 않는다.
