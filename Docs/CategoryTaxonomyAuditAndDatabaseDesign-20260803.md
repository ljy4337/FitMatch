# FitMatch 카테고리 taxonomy 읽기 전용 감사 및 DB 설계

- 감사 시각: 2026-08-03 (Asia/Seoul)
- 범위: Supabase `FitMatch` public 스키마 SELECT/메타데이터, 로컬 저장소와 수집 자료
- 변경 통제: DB/데이터/앱 소스 변경 없음. 이 문서만 생성함.
- 결론: **현재 자료는 정규화 DB 설계에는 사용 가능하지만, 무신사·유니클로의 수집 시점 기준 전수성과 모든 행의 의미 판정을 입증하지 못했으므로 migration/적재 승격은 보류한다.**

## A. 환경 및 기준점

| 항목 | 결과 |
|---|---|
| 저장소 | `/Users/jinyoung/Documents/Projects/FitMatch/FitMatch` |
| 브랜치 | `카테고리분류작업` |
| HEAD | `17e9a8b149e8103f35fa8da4c1dde562e913b215` |
| origin/main 차이 | ahead 0 / behind 0, 즉 HEAD와 origin/main 동일 |
| upstream | 현재 브랜치의 유효한 upstream을 확인하지 못함 |
| 기준 앱 로직 | 안정 기준은 HEAD/main. 아래 7개 미커밋 Swift 변경은 별도 제안 로직으로 대조하되 확정 기준과 분리 |
| Supabase MCP | 연결 정상 |
| 연결 프로젝트 | `FitMatch` (`hnkplvyegonlhumlejst`, ACTIVE_HEALTHY), `JY's Project` (`qtvqjwiveecnnprvklqd`, INACTIVE) |
| 감사 프로젝트 | 이름과 저장소 맥락이 일치하는 `FitMatch` |

기존 미커밋 변경은 `GarmentComparisonAttributes.swift`, `ParsedClosetClassification.swift`, `ComparisonProfileMatcher.swift`, `MeasurementComparisonEngine.swift`, `RecommendationService.swift`, `SourceCategoryHistoryMatcher.swift`, `FitMatchTests.swift`에 있으며 289 insertions/20 deletions이다. 7부·크롭·9부, leggings family, denim/pants 호환, 공식 형식 비교 보완을 포함한다. `RemoteComparisonPolicyStore`는 검색 결과 존재하지 않았다. 기존 변경은 수정하거나 되돌리지 않았다.

## B. 현재 DB 진단

public에는 테이블 28개, view 2개(`source_categories_readable`, `v_category_mapping_review`), materialized view 0개, PostgreSQL enum 0개가 있다. 28개 테이블은 모두 RLS 활성 상태이며 policy는 39개다. 주요 테이블은 다음과 같다.

| 영역 | 테이블과 실제 행 수 |
|---|---|
| 원본/매핑 | `sources` 2, `source_categories` 2,031, `source_category_mappings` 2,031, `client_source_category_mappings` 2,031 |
| 의미/비교 | `garment_types` 38, `comparison_groups` 30, `comparison_policies` 30, `comparison_policy_length_axes` 30, `comparison_length_classes` 15 |
| 앱 매핑 | `app_categories` 99, `category_aliases` 24, `app_category_comparison_policies` 3 |
| 실측 | `measurement_items` 25, `source_measurement_mappings` 21, `measurement_basis_conversions` 5, `app_category_measurement_policies` 25, overrides 2, `category_measurement_items` 0 |
| 길이 | `garment_length_classes` 10, `garment_length_classification_rules` 23 |
| 사용자 | `profiles` 1, 나머지 주요 사용자/상품 테이블은 0 |

메타데이터 감사에서 컬럼 타입/null/default, PK/FK, unique/check, index, trigger/function, RLS/policy를 조회했다. 현재 핵심 결함은 `source_categories`에 원본 경로와 `app_category`, `app_detail_category`, 길이 결과가 함께 있어 원본→semantic→앱 3계층이 분리되지 않는다는 점이다. 상태 check도 `confirmed/review_required/rejected`만 허용해 `unsupported/inactive/unknown`을 손실 없이 표현할 수 없다.

### 데이터 품질 집계

| 계산 | 전체 | Musinsa | Uniqlo |
|---|---:|---:|---:|
| 원본 행 | 2,031 | 314 | 1,717 |
| 부모 / leaf | 264 / 1,767 | 합계 포함 | 합계 포함 |
| active / inactive / unknown | 2,031 / 0 / 0 | 314 / 0 / 0 | 1,717 / 0 / 0 |
| confirmed | 979 | 플랫폼 합계에 포함 | 플랫폼 합계에 포함 |
| review_required | 492 | 플랫폼 합계에 포함 | 플랫폼 합계에 포함 |
| rejected | 560 | 플랫폼 합계에 포함 | 플랫폼 합계에 포함 |
| target | MEN 570, WOMEN 823, KIDS 237, BABY 87, UNISEX 0, NULL 314 | NULL 314 | 나머지 1,717 |
| external ID/path/source/status 누락 | 0/0/0/0 | 0 | 0 |
| garment type 누락 | 964 | 합계 포함 | 합계 포함 |
| 앱 category 누락 | 183 | 합계 포함 | 합계 포함 |
| legacy 단일 length 누락 | 2,003 | 합계 포함 | 합계 포함 |
| policy version 누락 | 0 | 0 | 0 |
| parent orphan / cycle | 0 / 0 | 0 | 0 |
| source+external ID+target 중복 | 0 | 0 | 0 |
| source+target+정규화 경로 중복 초과행 | 45 | 0 | 45 |
| 정규화 전 경로가 다른 충돌 key | 1 | 합계 포함 | 합계 포함 |

계산식은 `979 + 492 + 560 = 2,031`, `314 + 1,717 = 2,031`, `264 + 1,767 = 2,031`, `570 + 823 + 237 + 87 + 0 + 314 = 2,031`이다. garment type 누락 964는 rejected 560과 review_required 중 404의 합이다. confirmed 중 garment type 또는 policy version 누락은 0이다. review/rejected의 evidence 빈 객체도 0이다.

조회 키 비교:

| 키 | 사용 가능 | distinct | 중복 초과행 | 의미 충돌 | 판정 |
|---|---:|---:|---:|---:|---|
| Musinsa source+external ID(+target) | 314 | 314 | 0 | 0 | parser가 depth code를 얻는 정상 경로에서 최우선 |
| Uniqlo source+API code+target | 0 | 0 | - | - | 현재 parser가 category ID/code를 확보하지 못해 불가 |
| Uniqlo source+target+normalized path | 1,717 | 1,672 | 45 | 현재 데이터상 0 | 현재 최선의 복합 키, snapshot/version 필요 |
| source+normalized path | 대상 공유 시 위험 | - | - | target별 정책 충돌 가능 | fallback 전용 |

경로에 `/`가 포함된 행은 250개다. `/`를 depth 구분자로 사용하면 카테고리명 자체를 훼손한다. 정규화는 Unicode NFC, HTML entity decode, trim/연속 공백 축약, 오직 구조화된 breadcrumb segment 결합만 수행하고 raw segment 배열을 함께 보존해야 한다.

## C. 전수 수집 진단

### Uniqlo

공식 페이지에서 MEN/WOMEN/KIDS/BABY 및 baby/toddler/newborn 하위 분류가 확인된다. 로컬 live 코퍼스 snapshot `2026-07-28T00:21:47Z`에는 실상품에서 관측한 노드 170개(중간 64, direct-product leaf 103, unresolved 3, 최대 depth 3)가 있고 DB 후보 165개 중 기존 source category와 직접 일치 표시는 3개뿐이다. 이는 DB의 1,717행이 틀렸다는 뜻이 아니라, DB seed taxonomy와 실상품 breadcrumb taxonomy가 서로 다른 관측 축이며 snapshot/provenance 분리가 필요하다는 증거다. 공식 사이트의 전체 taxonomy endpoint나 모든 navigation payload를 하나의 재현 가능한 snapshot으로 확보하지 못했으므로 **수집 시점 기준 전수 완료를 주장할 수 없다.**

### Musinsa

DB에는 314개 external category ID가 있고 ID 중복은 없다. parser는 goods detail API에서 depth 1~4 name/code를 얻을 수 있으나, 현재 DB 314행은 target이 전부 NULL이다. 공식 전체 category tree의 당시 snapshot, 중간노드/비의류/비활성 노드를 모두 포함했다는 독립 증거를 확보하지 못했다. 따라서 **314개를 공식 전체 taxonomy로 간주할 수 없다.** 접근 제한을 우회하지 않았으며, 승인 전 후속 수집은 공식 navigation/category API 응답을 raw evidence로 저장하는 방식이어야 한다.

### 교차 자료

- `fitmatch_supabase_seed_musinsa_categories.sql`, `fitmatch_supabase_seed_uniqlo_categories.sql`: 현재 DB seed 계열이며 원본 공식 snapshot과 수동 판정이 혼합되어 source-of-truth로 단독 승격 불가.
- `Docs/Research/CategoryCorpus-live-uniqlo-full`: live public response 기반 상품/경로 증거. taxonomy 전수본이 아니라 표본 기반 관측 자료.
- `Docs/Research/LiveProductSurvey-20260723`: 58개 category CSV 데이터행 규모의 parser/실측 표본.
- `Docs/FitMatch_플랫폼_카테고리_매칭표_080119.xlsx`와 생성 스크립트는 기존 미추적 사용자 자료이므로 수정하지 않았고, 파일명이나 confirmed 표기만으로 확정 자료로 채택하지 않았다.

## D. 현재 FitMatch 로직 진단

| 흐름 | 실제 확보/판정 | 위험 |
|---|---|---|
| Musinsa parser | goods detail API에서 product ID, category depth 1~4 이름/code, path, gender를 확보. HTML fallback은 category가 약함 | external deepest code 우선 가능하나 API 실패 fallback 식별률 별도 관리 필요 |
| Uniqlo parser | JSON-LD/breadcrumb에서 최대 depth 4 path와 target, 상품 ID, 사이즈표 raw label/code/unit 확보 | stable category ID/API code 없음. target+path가 필요 |
| `ProductMetadata → Product` | source path/depth를 전달하지만 임의 depth N과 taxonomy snapshot/version은 저장하지 않음 | taxonomy 변경 시 재현 불가 |
| `ParsedClosetClassification` | keyword/path/measurement로 category/detail/family/단일 length 추론 | 독립 sleeve/pants/leggings/skirt/body 축 표현 불가 |
| `ComparisonGarmentFamily` | HEAD는 넓은 family 중심. WT는 leggings 및 denim/pants 호환 보완 | garment type과 family가 1:1 아님 |
| 비교/추천 | `ComparisonProfileMatcher`와 `MeasurementComparisonEngine`, `RecommendationService`가 family/length/공통 실측으로 후보와 점수를 결정 | 정책 버전 없는 저장 분류가 화면별 시점 차이를 만들 수 있음 |
| 공식 실측 | WT는 동일 플랫폼 공식 형식을 보존하고 교차 플랫폼은 canonical basis 사용, 둘레→단면 0.5 규칙 존재 | alias provenance와 변환 버전이 DB에서 분리돼야 함 |
| 기록/SwiftData | garment/sleeve/construction raw value를 저장. Schema V1, migration stage 없음 | 재분류 정책 버전 및 원판정 snapshot 없음 |

HEAD/main에는 7부·크롭·9부 및 leggings 세분화가 없고, 현재 WT에는 제안 구현이 있다. DB semantic taxonomy는 WT를 무조건 정답으로 고정하지 않고 이 의미를 lookup code로 수용하며 앱 매핑 상태를 `transform_required`로 기록해야 한다. 현재 단일 `ComparisonLengthType`은 sleeve와 pants 의미를 혼합하고 skirt/body/leggings를 독립 표현하지 못한다.

같은 상품이 최초 결과/상세/다른 사이즈/기록 재진입에서 달라질 위험은 (1) 저장된 raw classification과 재실행 heuristic 혼용, (2) source history matcher의 과거 경로 결과 전파, (3) 정책 버전 부재, (4) 공식 raw 형식과 canonical 형식 선택 경로 차이다. 해결은 immutable classification decision ID와 comparison result snapshot에 policy/version과 normalized inputs를 함께 저장하는 것이다.

## E. 원본 → semantic → 앱 매핑

현재 2,031행 중 confirmed 979만 기존 DB 의미 판정의 확정 후보이며, 전수성/provenance 검증 전에는 신규 canonical DB의 `confirmed`로 자동 승격하지 않는다. review_required 492는 product-level 증거가 필요하고 rejected 560은 rejected 사유를 보존한다. unsupported/inactive/unknown은 현재 DB에 별도 상태가 없어 0으로 집계할 수 있는 것이 아니라 **측정 불가능**하다.

신규 semantic 후보는 기존 38개 garment type을 초기 seed로 쓰되 bodysuit, coverall/romper, vest 계열, swimwear, bra/brief, socks, one-piece dress, skort 등 공식/실상품 근거가 있는 코드를 별도 검토한다. 신규 앱 enum을 이번 단계에서 추가하지 않는다.

길이축은 반드시 다섯 개를 분리한다: `sleeve`, `pants`, `leggings`, `skirt`, `body`. 각 축에는 `unknown`과 `not_applicable`를 별도 code로 둔다. skirt length와 body length는 측정 의미와 비교 제외 실측이 달라 합치지 않는다.

## F. 충돌 유형

| 충돌 | 현재 결과 | 권장 결과 | 위험도 |
|---|---|---|---|
| Uniqlo 정규화 path 중복 | 45 초과행, 현재 의미 충돌 0 | target+snapshot+segment hash로 identity, path는 보조 key | 중 |
| 정규화 충돌 | 서로 다른 raw path가 같은 normalized key 1건 | raw segment/hash 보존, 자동 승격 금지 | 높음 |
| Musinsa target NULL | 314행 | source taxonomy identity와 audience assignment를 별도 다대다 테이블로 분리 | 높음 |
| 상태 모델 | unsupported/inactive/unknown 미표현 | lookup 상태와 lifecycle 상태 분리 | 높음 |
| 길이 모델 | 2,003행 legacy length NULL, 독립 축 없음 | decision별 5축 row 모델 | 높음 |
| app/semantic 혼합 | source table에 app column | 별도 app mapping version | 높음 |
| 실상품 breadcrumb vs seed tree | live 170노드 중 기존 직접표시 3 | 서로 다른 snapshot/evidence로 보존 후 검수 | 높음 |

행별 “기존 DB vs 앱 vs 신규 권장” 전체 목록은 공식 taxonomy snapshot과 product sampling이 완결되지 않아 생성하면 추측을 확정하는 결과가 된다. 이 단계에서는 충돌 유형만 확정하고 행별 승격 목록은 보류한다.

## G. 목표 ERD

```text
source_platforms ── source_taxonomy_snapshots ── source_categories
                                                ├─ source_category_edges
                                                ├─ source_category_audiences
                                                └─ collection_evidence
                                                          │
                                                          ▼
policy_versions ── category_classification_decisions ── semantic_garment_types
                         ├─ decision_length_classes       ├─ comparison_families
                         ├─ decision_evidence             └─ garment_measurement_policies
                         ├─ category_app_mappings ── fitmatch_categories/details
                         └─ classification_audit_history

product_classification_overrides ── product evidence
comparison_families ── comparison_compatibility_rules ── measurement_definitions
source_measurement_aliases ── measurement_conversion_rules
import_runs ── staging_source_categories/staging_classification_results
            └─ validation_results ── canonical promotion
```

## H. 테이블별 DDL 설계

업무 code는 변경 가능하므로 PostgreSQL enum 대신 lookup table+FK를 사용한다. UUID PK, stable text code unique, `created_at/updated_at`, version FK를 공통으로 둔다. 시간·import 상태처럼 폐쇄적 기술 상태만 check constraint를 쓴다.

| 테이블 | 핵심 컬럼/제약 | 인덱스·보안·버전 |
|---|---|---|
| `source_platforms` | id, code unique, name, base_url, active | 공개 read 가능, admin write |
| `source_taxonomy_snapshots` | source_id, snapshot_version, observed_at, source_version, raw_checksum, completeness_status, provenance; unique(source,version) | immutable, admin only |
| `source_categories` | snapshot_id, external_id nullable, api_code nullable, raw_name, raw_display_path, normalized_lookup_path, path_hash, depth, leaf_state, activity_state, raw_payload_hash; unique(snapshot,identity_hash) | raw 값 overwrite 금지 |
| `source_category_edges` | snapshot_id,parent_id,child_id,ordinal; PK(snapshot,parent,child), parent≠child | cycle validation/trigger는 승인 후 별도 검토 |
| `source_category_audiences` | category_id,target_code,evidence_id; PK(category,target) | target를 원본 identity와 분리 |
| `collection_evidence` | snapshot_id, category_id, endpoint_kind, source_url, method, fetched_at, content_hash, evidence jsonb | URL/token redaction check |
| `semantic_garment_types` | code, ko/en name, parent_id, semantic_category, active | lookup, history 보존 |
| `comparison_families` | code, group_code, description, active | lookup |
| `length_axes/classes` | axis code; class(axis,code,ordinal), unknown/not_applicable flags; unique(axis,code) | 5축 독립 |
| `policy_versions` | id, schema/taxonomy/policy/normalization version, status, checksum, effective_at | immutable published version |
| `category_classification_decisions` | category_id, policy_version_id, status_id, garment_type_id nullable, family_id nullable, method, confidence 0..1, reason, reviewed_at/by, is_current | partial unique(category) where current; status별 필수값 check |
| `decision_length_classes` | decision_id, axis_id, class_id, evidence_id; PK(decision,axis), class.axis=axis 검증 | 해당없음도 명시 |
| `decision_evidence` | decision_id,evidence_id,weight,note | provenance |
| `category_app_mappings` | decision_id, app taxonomy version, category/detail/family/length, mapping_status, transform_rule, lossy, extension_required | semantic과 앱 분리 |
| `product_classification_overrides` | source product identity, base_decision_id, override fields/reason/evidence/version | category 혼재 대응 |
| `comparison_compatibility_rules` | from_family,to_family,direction, length_rule,min_common,priority,fallback,version; unique(version,from,to,priority) | 방향성 보존 |
| `measurement_definitions` | code, ko/en, dimension_type, representation, unit, comparable, ranges | lookup |
| `garment_measurement_policies` | version,family,measurement,role(required/optional/excluded),group,weight | unique(version,family,measurement) |
| `source_measurement_aliases` | source,raw_code,raw_label,unit,representation,canonical_id,factor,official_format,parser_method,status | 검증된 active alias의 다중 canonical 충돌 금지 |
| `measurement_conversion_rules` | from/to representation+unit,measurement nullable,factor/formula,lossless,version | 원본값 불변 |
| `classification_audit_history` | decision_id,old/new jsonb,changed_fields,reason,actor,at,import_run | append-only |
| `import_runs` | source,snapshot,input/output checksum,status,started/completed/error,resume_token | idempotency |
| `staging_source_categories` | import_run,row_number,raw jsonb,parsed fields,validation state | canonical FK 없음, admin only |
| `staging_classification_results` | import_run,staging row,proposed decision/evidence | 승격 전용 |
| `validation_results` | import_run,rule_code,severity,entity,count,details | error 0일 때만 승격 |

삭제 정책은 lookup `restrict`, snapshot 이하 `restrict`, staging은 보존기간 후 명시적 관리자 삭제, canonical/audit는 hard delete 금지와 inactive/superseded 처리다. public 앱에는 승인된 read view만 `security_invoker`로 공개하고 raw evidence, staging, audit, actor 정보는 관리자 전용 RLS로 둔다.

## I. 변환 규칙

1. 원본 breadcrumb segment 배열을 authoritative 구조로 저장한다. 표시명 내부 `/`는 분리하지 않는다.
2. lookup path는 HTML entity decode → Unicode NFC → segment별 trim → 연속 공백 1개 → source별 허용된 case fold → literal ` > ` 결합 순서로 deterministic 생성한다.
3. `path_hash = sha256(normalization_version || target || normalized segments JSON)`이며 raw payload/hash도 별도 보존한다.
4. source identity는 external ID 우선, 없으면 API code, 둘 다 없으면 snapshot+target+path hash를 사용한다. fallback identity임을 표시한다.
5. lifecycle(active/inactive/deprecated)과 decision(confirmed/review_required/rejected/unsupported/unknown)을 분리한다.
6. confirmed는 semantic garment와 policy version 필수. review는 reason 필수. rejected는 reason 필수이며 family/policy 연결 금지. unsupported는 semantic garment 필수, 앱 mapping은 unsupported 상태 허용.
7. category가 여러 garment/length를 포함하면 review_required로 두고 product override만 확정한다.
8. 앱 mapping은 direct/transform_required/unsupported_by_current_app/new_taxonomy/new_policy/review/rejected 중 하나이며 손실 여부를 기록한다.
9. 동일 공식 format은 raw field/value로 비교하고, 다른 format/platform은 canonical 변환한다. 원본·변환값과 conversion rule ID를 함께 저장한다.

## J. migration 및 적재 계획

승인 후에도 4개 migration으로 분리한다: (1) lookup/version/import/staging, (2) source snapshot/hierarchy/evidence, (3) semantic/app/decision/audit, (4) comparison/measurement/RLS/read views. 기존 테이블은 삭제·변경하지 않고 신규 namespace 테이블을 추가한다.

적재 순서는 import run 생성 → raw snapshot/staging COPY → checksum/identity/tree 검증 → semantic lookup seed → 분류 proposal → 사람 검수 → validation error 0 확인 → 새 canonical snapshot/decision insert → current pointer 전환이다. upsert는 immutable snapshot에는 금지하고 staging의 `(import_run_id,row_number)`에만 멱등 적용한다. 실패 시 run을 failed로 남기고 current pointer를 바꾸지 않는다. rollback은 신규 version을 superseded 처리하고 이전 current pointer를 복원한다.

예상 적재 건수는 기존 DB 2,031행이 아니라 공식 snapshot 수집 후 결정한다. 현 시점의 안전한 하한은 기존 2,031행이며, live Uniqlo 관측 경로가 별도 존재하므로 실제 수는 더 클 수 있다.

## K. 검증 SQL 설계

```sql
-- 상태 합계
select status_code, count(*) from category_classification_decisions
where policy_version_id = :version group by status_code;

-- snapshot 원본 손실/중복
select snapshot_id, count(*), count(distinct identity_hash), count(distinct raw_payload_hash)
from source_categories group by snapshot_id;

-- orphan / self edge
select e.* from source_category_edges e
left join source_categories p on p.id=e.parent_id
left join source_categories c on c.id=e.child_id
where p.id is null or c.id is null or e.parent_id=e.child_id;

-- confirmed/review/rejected 불변식
select * from category_classification_decisions
where (status_code='confirmed' and (garment_type_id is null or policy_version_id is null))
   or (status_code='review_required' and nullif(btrim(decision_reason),'') is null)
   or (status_code='rejected' and (nullif(btrim(decision_reason),'') is null or comparison_family_id is not null));

-- 경로 정규화 충돌
select snapshot_id,target_code,normalized_lookup_path,count(*),count(distinct raw_display_path)
from source_categories c join source_category_audiences a on a.category_id=c.id
group by 1,2,3 having count(distinct raw_display_path)>1;

-- alias 충돌
select source_id,raw_code,raw_label,count(distinct canonical_measurement_id)
from source_measurement_aliases where active and validation_status='confirmed'
group by 1,2,3 having count(distinct canonical_measurement_id)>1;

-- staging 승격 gate
select severity,sum(affected_count) from validation_results
where import_run_id=:run group by severity;
```

추가 검증은 recursive CTE cycle, depth continuity, source ID 다중 부모/경로, 길이 class axis 일치, unknown/not_applicable 동시 지정, family 필수 실측 0건, 변환 왕복 오차, policy/audit 누락, input/output checksum을 포함한다.

## L. 위험 및 확인 불가능한 항목

- 2026-08-03 시점 공식 Musinsa/Uniqlo 전체 navigation tree raw snapshot을 확보하지 못해 전수성을 입증하지 못했다.
- 비활성/종료 category를 공식 소스에서 열거하지 못했다.
- 기존 DB는 unsupported/inactive/unknown 상태를 표현하지 못해 해당 수치를 계산할 수 없다.
- 모든 category별 상품 표본 수·garment/length 분포·예외율은 아직 없다. 따라서 979 confirmed도 신규 canonical confirmed로 자동 승격할 수 없다.
- Uniqlo 공식 페이지는 target/대표 category 존재를 지지하지만 전체 tree completeness 증거는 아니다.
- Musinsa target 정책과 UNISEX 처리 규칙은 별도 검토가 필요하다.
- current WT의 새 enum/호환 규칙은 유용한 제안이나 미커밋 상태이므로 DB 확정 정책 근거로 단독 사용하지 않는다.

## M. 실행 승인 전 조건

아직 migration/seed/RPC/function/trigger/RLS 변경이나 앱 수정은 실행하지 않았다. 다음 승인 전에 공식 taxonomy snapshot 수집 방식, 전수성 gate, 979개 기존 confirmed의 표본 검수 수준, Musinsa target 모델을 먼저 확정해야 한다. 그 후 생성할 정확한 migration SQL과 staging 입력 checksum을 별도 리뷰 대상으로 제시한다.

