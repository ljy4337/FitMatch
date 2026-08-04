# 공식 taxonomy 2차 전수성 조사

- 수집 시각: 2026-08-03T01:51:16.757Z
- DB 기준: Supabase FitMatch public, 2,031행
- 변경 통제: 공식 공개 응답과 Supabase SELECT만 사용. DB·앱 변경 없음.
- 최종 판정: **일부 범위만 확인**
- 적재 판정: **staging 적재만 가능**. canonical 적재는 불가.

## 1. 공식 수집 경로

### Musinsa

- 공식 category 페이지: `https://www.musinsa.com/category/{categoryCode}`
- 공식 Next page data의 `meta.data.categoryCode/categoryTitle`과 렌더링된 `data-category-id`, `data-category-name`을 사용했다.
- 루트 code namespace를 확인하기 위해 `000`~`199`를 probe하고, 유효한 26개 루트에서 발견된 child ID를 재귀 수집했다.
- 유효 루트: 001, 002, 003, 004, 017, 026, 100~109, 111~120.
- 상품 API `https://goods-detail.musinsa.com/api2/goods/{productID}`는 상품별 depth code 증거지만 전체 tree 열거 endpoint는 아니다.
- 페이지에는 ID, 전체 breadcrumb, parent/child, leaf 판정 근거가 있다. 성별과 활성 플래그는 없다. 106 subtree만 공식 이름으로 KIDS를 부여했고 나머지는 UNKNOWN으로 보존했다.
- 200 이상의 루트가 없다는 공식 schema 선언이나 전체 root endpoint는 찾지 못했다. 따라서 이 snapshot은 **공식 페이지에서 확인된 000~199 root namespace 범위**다.

### Uniqlo

- 공식 navigation 페이지: `https://www.uniqlo.com/kr/ko/men_navigation`
- 공식 HTML의 `window.__PRELOADED_STATE__.taxonomies`를 사용했다.
- payload는 `genders` 4, `classes` 43, `categories` 180, `subcategories` 1,504를 한 번에 제공하며 각 node에 ID, name/key, parents가 있다.
- target은 첫 parent gender인 WOMEN/MEN/KIDS/BABY에서 직접 산출했다.
- 개별 활성 플래그와 비활성 taxonomy 별도 endpoint는 없다. 오래된 collection key도 payload에 남을 수 있어 모든 node를 `activity_status=unknown`으로 저장했다.

인증 토큰, 쿠키, 개인정보는 수집·저장하지 않았다. 각 공식 응답은 SHA-256 hash로 추적한다.

## 2. snapshot 및 트리 무결성

| 검사 | Musinsa | Uniqlo |
|---|---:|---:|
| 전체 node | 2,277 | 1,731 |
| leaf | 1,922 | 1,504 |
| target | UNKNOWN 2,156 / KIDS 121 | WOMEN 829 / MEN 574 / KIDS 240 / BABY 88 |
| 중복 ID group | 0 | 0 |
| 같은 ID 경로 충돌 | 0 | 0 |
| 중복 normalized path 초과행 | 0 | 42 |
| 같은 경로 ID 충돌 group | 0 | 30 |
| target 충돌 ID | 0 | 0 |
| orphan parent | 0 | 0 |
| cycle | 0 | 0 |
| depth 오류 | 0 | 0 |
| parent-child depth 오류 | 0 | 0 |
| 활성 여부 미확인 | 2,277 | 1,731 |
| 수집 실패 | 0 | 0 |

계산식:

- Musinsa `1,922 leaf + 355 non-leaf = 2,277`.
- Musinsa `2,156 UNKNOWN + 121 KIDS = 2,277`.
- Uniqlo `1,504 subcategories + 180 categories + 43 classes + 4 genders = 1,731`.
- Uniqlo `829 + 574 + 240 + 88 = 1,731`.
- 각 orphan/cycle/depth error는 해당 조건을 만족하는 node count이며 모두 0이다.

Uniqlo의 동일 경로/다른 ID 30 group은 target을 포함한 경로 기준이다. collaboration/collection 등 같은 표시 경로에 별도 ID가 존재하므로 external ID를 primary identity로 사용해야 한다.

## 3. 기존 DB coverage

키 우선순위는 `(source, external ID, target)` → `(source, external ID)` → `(source,target,normalized path)` → `(source,normalized path)`다.

| 결과 | Musinsa | Uniqlo |
|---|---:|---:|
| 공식 snapshot 전체 | 2,277 | 1,731 |
| ID+target 일치 | 193 | 1,717 |
| ID만 일치 | 121 | 0 |
| target+path만 일치 | 0 | 1 |
| path만 일치 | 0 | 0 |
| 공식에는 있으나 DB에 없음 | 1,963 | 13 |
| DB에는 있으나 snapshot에 없음 | 0 | 0 |
| ID 동일·경로 차이 | 0 | 23 |
| 경로 동일·ID 차이 | 0 | 1 |
| target 차이 | 121 | 0 |

계산식:

- Musinsa `193 + 121 + 0 + 0 + 1,963 = 2,277`.
- Musinsa DB coverage `314 / 2,277 = 13.79%`; 누락률 `1,963 / 2,277 = 86.21%`.
- Uniqlo `1,717 + 0 + 1 + 0 + 13 = 1,731`.
- Uniqlo DB coverage `(1,717 + 1) / 1,731 = 99.25%`; 누락률 `13 / 1,731 = 0.75%`.
- DB 역방향 coverage는 Musinsa `314/314=100%`, Uniqlo `1,717/1,717=100%`다. 즉 기존 DB 행은 모두 공식 snapshot에서 식별됐지만 공식 snapshot을 모두 담지는 않는다.
- 전체 공식 node `2,277 + 1,731 = 4,008`; 식별된 DB 대응 `314 + 1,718 = 2,032`. Uniqlo 한 node가 기존 다른 ID와 path match하므로 DB 고유 행은 여전히 2,031이다.

### 상태별 coverage

기존 DB의 모든 2,031행이 snapshot에서 식별되므로 기존 상태별 역방향 누락은 모두 0이다.

| source | confirmed | review_required | rejected | snapshot에서 식별 | 기존 상태 행 중 미식별 |
|---|---:|---:|---:|---:|---:|
| Musinsa | 80 | 39 | 195 | 314 | 0 |
| Uniqlo | 899 | 453 | 365 | 1,717 | 0 |

공식 신규 누락 1,976개에는 아직 DB 상태가 없으므로 confirmed/review/rejected로 배분하지 않았다.

## 4. 주요 충돌

- Musinsa 121개 KIDS node는 공식 snapshot target=KIDS지만 기존 DB target=NULL이다. ID는 일치하므로 target 보완 후보이며 자동 수정하지 않는다.
- Uniqlo ID 동일·경로 변경 23건이 있다. 예: WOMEN `57993`은 `아우터 > 재킷`에서 `아우터 > 재킷 & 코트`로 변경됐다.
- Uniqlo `151483` KIDS Pokémon은 현재 공식 ID이고, DB에는 같은 path의 `86459`가 있어 ID 교체/세대 변경 검토가 필요하다.
- Uniqlo 신규 13개는 gender root 4개, WOMEN collaboration 5개, MEN collaboration/와플 3개, KIDS 셔츠 1개다.
- 기존 DB에만 존재하는 행은 0이므로 이번 snapshot에서는 과거 taxonomy 후보가 검출되지 않았다. 이것이 비활성 taxonomy 전수 부재를 증명하지는 않는다.

전체 행은 `identity-path-target-conflicts.csv`에 있다.

## 5. 누락 카테고리 준비

`missing-categories.csv`에는 공식 신규 1,976개를 저장했다. 의미를 추측하지 않기 위해 모든 행의 semantic/app 지원 여부를 `unreviewed`로 두었다.

- intermediate node: 상품 표본 0, category-level 의미 확정 대상 아님.
- leaf node: 기본 최소 표본 5, 자동 confirmed 금지, `review_required` 권장.
- 명백한 비의류처럼 보이는 이름도 상품 구성 확인 전 rejected로 확정하지 않는다.
- 신규 garment type/앱 taxonomy 후보는 표본 검수 후 결정한다.

## 6. 비활성 taxonomy

공식 응답에는 개별 `is_active`, 종료일, deprecated marker가 없다. 따라서 다음만 구분 가능하다.

- 현재 공식 payload/page에서 관측: snapshot의 4,008 node.
- 기존 DB에만 존재하는 과거 후보: 이번 비교 0.
- 활성 여부 미확인: 4,008 node 전부.

공식 payload에 존재한다는 사실만으로 판매 활성이라고 확정하지 않는다. 반대로 향후 공식 payload에서 사라져도 즉시 삭제/rejected하지 않고 이전 snapshot에 보존해야 한다.

## 7. 전수성 판정

- Uniqlo: 현재 공식 navigation taxonomy payload 전체를 확보했다. 그러나 개별 활성 상태는 입증하지 못했다.
- Musinsa: 공식 category page의 000~199 root 범위와 그 하위 트리를 확보했다. 전체 root namespace 상한을 선언하는 공식 근거가 없어 플랫폼 전체 전수성은 입증하지 못했다.
- 종합: **일부 범위만 확인**.
- migration: 아직 불가.
- raw snapshot staging: checksum과 provenance를 유지하는 조건으로 가능.
- canonical 승격: Musinsa root completeness, 활성 상태 정책, 신규 leaf 표본 검수 전에는 불가.

## 8. 산출물

- `musinsa-official-taxonomy-snapshot.json/.csv`
- `uniqlo-official-taxonomy-snapshot.json/.csv`
- `db-coverage-summary.json`
- `db-coverage-comparison.csv`
- `missing-categories.csv`
- `db-only-categories.csv`
- `identity-path-target-conflicts.csv`
- `ProductSamplingPlan.md`

