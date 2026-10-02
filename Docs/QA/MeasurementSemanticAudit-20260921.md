# 실측 의미와 비교 그룹 결합 — 읽기 전용 감사

대상: Supabase hnkplvyegonlhumlejst. 2026-09-21 재조회. 코드: connectDB / 7a61fbbe8737acac98254c993c52944b3e6da5f9 + 기존 미커밋 변경. DB·앱 코드 수정/마이그레이션 적용/commit/push 없음. 이전 Apply SQL도 적용하지 않음.

## 1. ROOT CAUSE (근본 원인)

### R1. 기존 잘못된 정의를 일부 카테고리만 보정

- `supabase/migrations/20260818013019_align_product_runtime_policy_v1.sql:160`은 knit-body-length-front를 back_length로 매핑하고 tops/outerwear/dresses/underwear/homewear에 확장한다. 당시 근거 문자열도 front length를 body length로 합친다고 명시한다. 현재 정책상 앞뒤 측정 시작점을 합칠 수 없다.
- 현재 vNext의 잘못된 E/F/G alias 3행 created_at/updated_at은 2026-08-27 07:37:34 UTC다. tops/outerwear의 정상 alias는 2026-09-11 06:47:40 UTC 생성됐으며 옛 두 행은 비활성화되어 있다.
- `supabase/sql/145_measurement_basis_completion_Apply.sql:134`–135의 보정 seed에는 tops/outerwear만 있다. 185–197의 비활성화 조건도 **seed와 동일한 category**만 선택한다. 따라서 E/F/G의 옛 행은 손대지 않는다.
- 같은 Verify SQL은 앞기장을 tops 한 문맥에서만 확인한다. Apply의 마지막 assertions도 둘레/등너비/소매부리에 집중하고 모든 front alias 문맥을 검사하지 않는다. 이는 회귀검사가 놓친 구체적 범위다.
- 8월 legacy 정의, 현재 행 timestamp, 9월 보정 SQL의 범위가 일치한다. 단 vNext 최초 복사 실행자/원본 실행 SQL까지 증명하는 감사 로그는 확보하지 못했다. `schema_migrations` 조회에 해당 145 보정의 명시적 이름은 없어 파일 자체를 배포 실행 증명으로 취급하지 않는다.

### R2. 비교 그룹이 실측 의미 해석의 문맥을 덮어씀

아래는 하나의 직선 호출이 아니라, 일반 그룹 경로와 사용자 선택 그룹 경로가 갈라졌다가 같은 resolver로 합쳐지는 구조다.

1. `resolve_measurement`: source/parser/raw code 또는 label + garment/category 조건으로 alias를 고른다. priority가 가장 높은 후보가 복수 의미면 AMBIGUOUS (모호함), 아니면 source→canonical 변환. 그룹 자체는 인자가 아니지만 **caller가 그룹 카테고리를 주입**한다.
2. `canonical_measurements_for_size`: products.garment_type_code와 garment_types.category_code를 써서 raw를 해석한다. AIRism base_layer_top/tops에서는 4개 모두 나온다.
3. `effective_target_classification` → `comparison_group_tuple`: F를 comparison_group_innerwear/underwear로 만든다. detailed garment가 아닌 그룹용 분류를 effective context로 돌려준다.
4. `canonical_measurements_for_size_with_context`: GLOBAL_CONFIRMED면 2번을 쓰지만 CATEGORY_GROUP/USER_EXPLICIT이면 **제품 원래 분류 대신 context의 garment/category**로 모든 원본을 재해석한다(배포 정의 49–61행). F에서 어깨와 등중심 소매 alias가 없어 2개로 줄어든다.
5. `canonical_measurements_for_session_group`: SESSION_USER_SELECTED를 일시적으로 CATEGORY_GROUP으로 바꿔 4번을 호출한다. 사용자 그룹 선택도 같은 결합을 갖는다. 이는 그룹 변경 없이 안정적인 원본 표준화가 보장되지 않는 구조다.
6. `get_product_runtime_for_swift`는 기본 runtime이 만든 각 size의 canonical_measurements를 4번 결과로 **덮어쓴다**. 따라서 원래 함수가 4개를 반환해도 앱 전달 시 2개가 된다.

### R3. 표준화 성공·비교 자격·점수 사용의 상태가 혼재

- `product_measurement_readiness`: 4번의 결과를 **활성 CANONICAL 정책 metric과 다시 교집합**한다. 반환 `policy_measurement_count`와 ready_sizes의 `resolved_measurement_count`는 전체 표준화 성공 개수가 아니라 정책에서 쓰는 개수다.
- `effective_product_readiness` → product_readiness / product_readiness_with_context → product_measurement_readiness가 실제 runtime 경로다.
- `eligible_candidate_sizes`: requested group가 없으면 4인자 경로→with_context, 있으면 5인자 경로→session_group. authorize overload도 같은 방향으로 연결된다.
- `comparison_evidence_20260908`: 이미 해석한 target canonical과 Closet canonical을 활성 policy metric·정확한 code/unit/basis·양수 weight 조건으로 교집합한다. **여기가 그룹별 점수 항목 선택을 맡기기 적절한 기존 경계**다.
- `begin_comparison`: requested group가 없으면 legacy_20260914로 위임하지만 이름과 달리 현재 active path다. 양쪽 모두 승인된 evidence/policy를 snapshot으로 고정한다. 이 mutation 함수는 실행하지 않고 정의만 읽었다.
- Swift `VNextComparisonEngineAdapter.swift:111,132`가 snapshot metric 수와 authorized evidence를 소비하고, `MeasurementComparisonEngine.swift:252`가 `max(0,min(100,100-절대차이×5))`를 weight로 평균해 점수를 낸다. canonical 해석 단계에서 빠진 값은 엔진이 복구할 수 없다. `complete_comparison` 역시 정의만 확인하고 실행하지 않았다.
- 추가 불일치: resolve_measurement의 EXACT_CODE는 source.is_comparable를 요구하지만 ALIAS 경로에는 같은 조건이 없다. 실제 total-length alias는 source_total_length로 RESOLVED, 동일 source code를 직접 넣으면 UNMAPPED다. **정규화 가능 여부와 점수 사용 가능 여부를 분리해야 한다는 추가 근거**이며 임의로 점수에 포함하라는 뜻은 아니다.

## 2. 실제 영향 범위

재조회 범위: products 69, current raw 2,212, alias 227(활성·verified 223), source 51, mapping 48, canonical 42, policy 44, metric 647. 정의 24개와 사전 전체는 이전 조회 대비 동일(줄바꿈 정규화 후 대조).

| 사례 | 원본 | 제품 원래 문맥 | 그룹 문맥 | 실제 점수 정책과 겹치는 항목 |
|---|---:|---:|---:|---|
| E454311 | 8사이즈×4 | 4 | F에서 2 | 가슴 1 |
| E471717 | 8사이즈×4 | 4 | F에서 2 | 가슴 1 |
| E482514 | 8사이즈×4 | 4 | F에서 2 | 가슴 1 |
| E482522 | 8사이즈×4 | 4 | F에서 2 | 가슴 1 |

- 128개 원본은 남아 있다. shoulder-width/sleeve-length-cb 합계 **64개 current row가 해석에서 누락**된다. 삭제된 raw 64개가 아니다.
- 4상품 readiness는 READY. 최소 1개 정책 실측 조건을 충족하기 때문이다. READY는 4개가 모두 보존·비교됐다는 보증이 아니다.
- generic_underwear에는 shoulder_width, sleeve_center_back_length, back_length가 없고 chest_width가 있다. alias만 추가해도 기존 F 점수 입력은 여전히 가슴 중심이다. 반대로 A/tshirt에는 back/chest/shoulder가 있지만 sleeve_center_back_length는 없다. **A로 옮겨도 등중심 소매를 일반 소매로 바꾸거나 4개 모두 점수에 쓸 수 없다.** 정책 확장은 별도 근거/승인이 필요하다.
- 현재 해당 4상품에 연결된 활성 Closet item은 모두 0건. 따라서 이 4상품에 대한 현재 활성 옷장 저장 오염은 확인되지 않았다. 삭제된 item/과거 History의 전체 재계산 영향은 검증하지 않았다.
- 현재 잘못된 앞기장 E/F/G alias에 해당하는 실제 해석 사례는 확인되지 않았다. 저장 앞기장 21행은 E450543(14행, A/tops)와 E491086(7행, 그룹 미정)이다. **잘못된 규칙 존재는 확정**, 현 데이터에서 잘못 계산된 결과 21건이라는 뜻은 아니다.
- 추가 html raw code 3종(chest/skirt/waist)의 current row는 0. 현재 호출되지 않는 잠재적 잘못된 규칙이지, 7개의 사용자 오류가 이미 발생했다는 뜻이 아니다.

전체 raw를 원래 문맥과 그룹 문맥으로 대조한 추가 결과:

- 그룹 없는 6상품의 119행은 원래 문맥으로 해석되지만 그룹 없이는 해석되지 않는다. MUSINSA 3346165/4818151, ZARA 545450451/547804819/551126671/575944393. 그룹 사용자 선택은 정상 설계이며 이를 미등록 오류나 일괄 매핑 사유로 취급하지 않는다.
- 반대 방향으로 7상품의 **211행**은 detailed category가 없어도 그룹 문맥 덕분에 해석된다: MUSINSA7079949, UNIQLO E479134/E484610/E484875/E487929, ZARA549829596/553623366. 따라서 모든 caller를 canonical_measurements_for_size로 단순 교체하면 이 경로가 회귀한다.
- 위 숫자는 resolver 입력의 정적/읽기 전용 비교다. 실제 로그인한 비교 후보 선택·최종 점수·History 저장 성공/실패 건수가 아니다.

## 3. 잘못된 기존 규칙 전체 목록

현재 사전 전체를 대조해 **확정한 semantic contradiction(의미 충돌)은 10개 alias**다. 행 ID 전체는 Evidence/confirmed-aliases.md에 있다. 다른 모든 실상품의 측정법까지 검증했다는 의미는 아니다.

| 원문 코드 | parser | 해당 문맥 | 행 수 | 잘못된 연결 | 올바른 의미 |
|---|---|---|---:|---|---|
| knit-body-length-front (앞기장) | size_chart | dresses/homewear/underwear | 3 | back_length (뒷기장) | front_length (앞기장) |
| chest-width-html (주름·박음질 포함 몸너비) | official_size_chart | tops/outerwear/dresses/homewear/underwear | 5 | chest_width (가슴단면) | gathered_body_width (주름포함 몸판너비) |
| waist-petticoat-html (페티코트 허리) | official_size_chart | skirts | 1 | waist_circumference (본체 허리둘레) | petticoat_waist_circumference (페티코트허리둘레) |
| skirt-length-html (페티코트 길이) | official_size_chart | skirts | 1 | 본체 스커트길이→total_length | petticoat_length (페티코트길이) |

후자의 7행은 `20260818074841_batch_measurement_scope_and_uniqlo_aliases_v1.sql:75`–78에서 원문 label까지 확인된다. DB에는 9월에 별도 주름/페티코트 source가 추가됐지만, 새 raw code용 보정이 옛 html code들을 대체하지 않아 남았다. DB 사전 자체가 두 의미를 별개로 정의하고 있어 이 모순을 판정할 수 있다.

**확정 오류와 분리할 추가 검토 후보**:

- source `uniqlo.total_length.waist_to_skirt_hem` → canonical `total_length/garment_total_length`: 시작점 구체성이 사라지는 mapping 1건. 무조건 잘못됐다고 단정하지 말고 다른 total_length 유입 및 score 의미를 조사해야 한다.
- product-length→back_length, MUSINSA 화장→raglan 등의 명칭만으로는 시작점이 입증되지 않는다. 공식 측정법 확인 없이 임의 교정 금지.
- 안감/페티코트 source의 is_comparable=false 자체는 오류가 아니다. 표준화·보존은 가능하되 본체 점수에서 분리하는 것이 맞다.
- UNIQLO 둘레→단면 잘못된 0.5 변환, ZARA 등너비→어깨, MUSINSA 소매부리→소매의 과거 유형은 현재 활성 사전에서 추가 확인되지 않았다. 이는 모든 provider 원문 검증 완료를 뜻하지 않는다.

## 4. 수정안

### 우선순위 1 — 의미 보존 계약부터 분리

`raw → measurement semantic resolution → canonical facts → group/policy selection → score evidence`로 경계를 정한다.

- 표준화 입력: provider/parser/version, raw code/label/value/unit, 원본 측정방법, 측정부위, 본체/안감/페티코트 등 구성품, **필요한 경우 검증된 의류 문맥**. 사용자 비교 그룹을 표준화의 의미 입력으로 사용하지 않는다.
- 표준화 출력: raw identity/value + canonical code/value/unit/basis + 구성품 + resolver/사전 version + RESOLVED/UNMAPPED/AMBIGUOUS와 사유. 미정의 raw도 보존·표시한다. 비교 가능한 것만 남기는 compact projection을 전체 데이터로 간주하지 않는다.
- canonical을 반드시 테이블에 영구 저장해야 하는 것은 아니다. 첫 안전한 변경은 재사용 가능한 독립 resolver/view 계약으로 가능하다. 저장한다면 raw fingerprint와 resolver version을 함께 저장하고 버전 변경 시 무효화한다.
- 이름이 여러 의미를 갖는 무신사 총장/허리단면은 category 조건을 무조건 제거하면 안 된다. 원본 측정 문맥을 독립적으로 유지하고 확정 근거가 부족하면 raw-only로 남긴다. 폐기한 detailed garment gate를 다시 등록 선행조건으로 만들지 않는다.

### 우선순위 2 — 모든 consumer를 같은 canonical 결과로 연결

- size / with_context / session_group이 원본 표준화 결과를 공유하게 한다. user-selected group은 eligibility/policy 선택에만 사용한다.
- readiness 응답을 raw_count / canonical_resolved_count / unresolved_count / policy_selected_count / common_evidence_count로 분리한다. 최소 공통 1개 정책은 유지한다.
- runtime·Closet 저장·후보·begin snapshot 모두 동일 원본 canonical projection을 소비한다. raw 전체 표시와 score evidence를 별도 필드로 유지한다.
- begin의 identity/ownership/stale fingerprint 보호를 유지하고 표준화 사전 version/fingerprint 변화도 stale 검출에 반영한다. 과거 결과 snapshot을 조용히 재계산하거나 사용자 override를 덮어쓰지 않는다.

### 우선순위 3 — 잘못된 규칙 정리와 정책 선택

- 확정 10행을 올바른 별도 source에 연결하고, 모든 parser 별칭과 의미상 동일한 raw code를 회귀검사한다. 과거 migration 재작성 대신 새 검증 가능한 migration을 작성한다.
- AIRism A 분류는 사용자가 요청한 별도 **상품 정책 변경**으로 관리한다. 이것을 64행 누락의 구조적 해결로 제시하지 않는다. alias 2개/9개 추가는 긴급 완화일 수 있지만 최종 해결이 아니다.
- 기존 브랜드 간 측정 기준/단면·둘레/일반소매·등중심소매 교집합 비교는 유지한다. source-native metric row가 DB에 있다는 이유로 현재 CANONICAL evidence 경로에 자동 포함하지 않는다.

## 5. 회귀 위험과 검증 기준

| 위험 | 필수 확인 |
|---|---|
| 기존 detailed category만 사용해 정상211행 소실 | 위7상품의 canonical code/value/basis 보존 |
| 모든 alias를 category-free로 바꿔 의미 충돌 | 총장→상의 back/outseam, 상의허리/하의허리, 구성품 분리 |
| canonical 증가가 점수 증가로 직결 | 동일 policy의 evidence는 승인된 metric·basis 교집합만, 임의 metric 추가 없음 |
| 앞기장 수정으로 결과 변동 | 올바른 코드로만 비교, 과거 History snapshot 불변, 새 비교 version 구분 |
| 단위/범위/충돌 은폐 | cm/둘레/단면/0/결측/서로다른 값 fail-closed 또는 명시적 보완 |
| 그룹 미정 자료가 재등록 불가 | raw 표시·사용자 그룹 선택 유지, 상세 분류 강제 복구 금지 |
| 업데이트/캐시 오래된 해석 | 사전 version/fingerprint로 stale 재검증, 정확한 product/variant/size 유지 |

수정 완료 기준: AIRism 4상품32사이즈는 A/F/G 등 **비교 그룹을 바꿔도 원본 canonical 4개의 의미·값이 불변**이어야 한다. 실제 비교 허용/점수 사용은 그룹·구조 정책에 따라 달라질 수 있다. 기존 정상211행, 잘못된10행, 미정의/모호/구성품/단위 및 raw 표시 회귀를 별도로 통과시킨다.

## 6. 검증 SQL과 증거

- `MeasurementSemanticAudit-20260921-Verify.sql`: READ ONLY 트랜잭션. 잘못된 alias10, 실제 native/context 차이, readiness, basis 후보, is_comparable 분기, 그룹별 metric 확인.
- `MeasurementSemanticAudit-20260921-Evidence/current-definitions.json` 및 `deployed-functions.sql`: 실제 배포 함수 정의 24개.
- `current-dictionaries.json`: 사전 전체, `current-context.json`: 2,212개 current raw의 문맥 차이 집계, `current-bad_raw.json`: 의심 raw 실사용 조회, `current-closet.json`: 활성 옷장 영향 집계, `current-migrations.json`: 이력 조회, `confirmed-aliases.md`: 확정10행 ID.
- PASS: 실제 READ ONLY 함수/사전 조회와 AIRism native4/context2 재현. READ ONLY 조건 재현이며 실제 앱 등록→비교→저장 E2E는 NOT RUN. 호출의 부수효과 없는 정의/하위 함수 확인 후 조회했다.
- DB write 없음. 앞서 준비한 Apply는 이번 읽기 전용 지시로 실행 대상에서 제외한다. 사용자 추가 승인 없이 적용하지 않는다.
