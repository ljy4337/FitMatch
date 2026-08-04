# Identity 집계 정정 및 위험 기반 상품 표본 검수

- 조사 시각: 2026-08-03
- 데이터 표현: **observed official taxonomy snapshot**
- 범위: 해당 수집 시점의 관찰 범위. Musinsa namespace 상한 미확인, 양 플랫폼 활성 상태 미확인.
- DB·스키마·앱 변경: 없음

## 1. 2,032 대 2,031 불일치의 정확한 원인

coverage를 행 수처럼 더한 것이 오류였다. KIDS Pokémon 동일 경로에는 DB 3행과 snapshot 4노드가 공존한다. 신규 snapshot ID `151483`이 path fallback으로 기존 DB 3행 모두에 연결되므로 “매칭된 snapshot node”는 DB 물리 행보다 1개 많다.

| 지표 | 전체 | Musinsa | Uniqlo |
|---|---:|---:|---:|
| DB 물리 행 | 2,031 | 314 | 1,717 |
| DB 고유 PK | 2,031 | 314 | 1,717 |
| DB 고유 external ID | 2,031 | 314 | 1,717 |
| DB 고유 external ID+target | 2,031 | 314 | 1,717 |
| DB 고유 normalized lookup path+target | 1,986 | 314 | 1,672 |
| snapshot 물리/고유 node | 4,008 | 2,277 | 1,731 |
| DB→snapshot 고유 매칭 DB | 2,031 | 314 | 1,717 |
| snapshot→DB 고유 매칭 node | 2,032 | 314 | 1,718 |
| 매칭 edge | 2,034 | 314 | 1,720 |
| 미매칭 DB | 0 | 0 | 0 |
| 미매칭 snapshot | 1,976 | 1,963 | 13 |

계산식:

- `4,008 snapshot - 1,976 미매칭 = 2,032 매칭 snapshot node`.
- `2,031 DB - 0 미매칭 = 2,031 매칭 DB row`.
- `2,028개의 1:1 component = 2,028 edge`.
- Pokémon N:N component는 `3개의 ID edge + 신규 151483의 path edge 3개 = 6 edge`.
- 전체 edge `2,028 + 6 = 2,034`.
- component는 `2,028 1:1 + 1 N:N = 2,029`.
- 1:N component 0, N:1 component 0, N:N component 1이다.

### 불일치를 만든 N:N component

공식 snapshot node:

- KIDS `112753`, `134044`, `86459`, 신규 `151483`
- 공통 경로: `티셔츠 & UT > 그래픽티셔츠 > Pokémon`

DB 행:

| DB PK | external ID | target | DB 경로 | snapshot 연결 | 방식 |
|---|---|---|---|---|---|
| `1e36797e-226a-4112-839a-9cc8e7da0ee6` | 112753 | KIDS | 동일 | 112753, 151483 | ID+target / path+target |
| `ec5b7bfa-b9d8-4c21-ad03-9f2c31aa572f` | 134044 | KIDS | 동일 | 134044, 151483 | ID+target / path+target |
| `d83f1f18-ca8d-4c17-9474-55947a3669f6` | 86459 | KIDS | 동일 | 86459, 151483 | ID+target / path+target |

`151483`은 기존 ID를 대체했다고 입증되지 않았다. 네 ID가 현재 payload에 함께 있으므로 ID 재발급/alias로 합치지 않고 별도 source category로 보존해야 한다. 공통 display path는 identity가 아니다.

## 2. 정규화 중복

Uniqlo live DB에는 normalized lookup path+target 중복 group 32개, 초과행 45개가 있다. 그중 1개 초과행은 `Minecraft`/`MINECRAFT` case-fold로 새로 충돌한다. 따라서 case-preserving path 고유 수 1,673과 lookup case-fold 고유 수 1,672를 구분한다. identity 매칭에는 1,672를 사용했다.

## 3. identity 충돌 판정

전체 145개 판정은 `identity-conflict-adjudications.csv`에 있다.

### Musinsa KIDS 121건

- ID와 경로는 공식 snapshot/DB가 동일하다.
- 충돌은 DB target=NULL, 공식 subtree target=KIDS인 audience assignment 차이다.
- ID alias, rename, ID 재발급이 아니다.
- canonical source category는 하나로 유지할 수 있다.
- category identity와 target assignment를 분리하고, 과거 NULL assignment와 신규 KIDS assignment를 snapshot history로 보존한다.
- 자동 DB 수정은 하지 않으며 121건 모두 수동 검토 대상으로 둔다.

### Uniqlo 경로 변경 23건

- external ID+target이 동일하므로 source identity는 유지한다.
- 이름 변경 또는 parent 표시 경로 변경으로 판정한다.
- 기존 경로를 삭제하지 않고 `source_category_path_history(snapshot_id, category_id, raw_path, parent_id, valid_from/to)`로 보존한다.
- canonical category를 합칠 수 있으나 과거/현재 path를 덮어쓰면 안 된다.
- 23건 모두 snapshot version 변경과 수동 검토를 기록한다.

### 동일 경로/다중 ID

- Pokémon KIDS는 3 DB↔4 snapshot N:N이다.
- 서로 다른 ID가 현재 payload에 공존하므로 alias나 ID 교체로 확정할 수 없다.
- 별도 source category로 보존하고 동일 normalized path collision group을 연결한다.
- alias는 공식 redirect/equivalence 증거가 생긴 경우에만 별도 relation으로 추가한다.

## 4. 전수성 표현 정정

| 구분 | Musinsa | Uniqlo |
|---|---|---|
| 공식 페이지에서 관찰 | 2,277 | 1,731 |
| navigation payload에서 관찰 | category page tree | preloaded taxonomy 전체 payload |
| 상품 존재 관찰 | 신규 leaf 포함 1,650개에서 확인 | 신규 9 leaf는 미확인 |
| leaf | 1,922 | 1,504 |
| 비leaf grouping | 355 | 227 |
| 활성 확인 | 0 | 0 |
| 활성 미확인 | 2,277 | 1,731 |
| 과거 DB에만 존재 | 0 | 0 |
| 공식 snapshot에만 존재 | 1,963 | 13 |

Musinsa는 root code `000~199` probe에서 관찰한 범위이며 namespace 상한이 확인되지 않았다. Uniqlo는 현재 navigation payload 전체를 읽었지만 개별 활성 플래그가 없다. 따라서 “공식 전체 활성 taxonomy”라고 표현하지 않는다.

## 5. 신규 1,976개 위험 그룹

| 그룹 | 정의 | Musinsa | Uniqlo | 합계 |
|---|---|---:|---:|---:|
| A | 명백한 비의류 leaf | 927 | 0 | 927 |
| B | 의류지만 앱/비교 지원 검토 | 40 | 0 | 40 |
| C | 경로로 garment type 안정 후보 | 173 | 2 | 175 |
| D | 의류이나 type/길이 혼재 | 103 | 0 | 103 |
| E | 의미 불명확, 상품 표본 필요 | 407 | 7 | 414 |
| F | navigation grouping/non-leaf | 313 | 4 | 317 |
| 합계 |  | 1,963 | 13 | 1,976 |

계산식: Musinsa `927+40+173+103+407+313=1,963`, Uniqlo `0+0+2+0+7+4=13`, 전체 `1,963+13=1,976`.

이 분류는 경로/tree 기반 staging 제안이며 canonical 판정이 아니다. 특히 A도 rejected “후보”로만 유지한다.

## 6. 상품 존재 확인

| 상태 | 수 |
|---|---:|
| `product_observed` | 1,650 |
| `no_product_observed` | 0 |
| `collection_failed` | 0 |
| `navigation_only` | 317 |
| `activity_unknown`인 leaf | 9 |

합계 `1,650 + 0 + 0 + 317 + 9 = 1,976`. 모든 category의 lifecycle activity는 별도 필드에서 여전히 `activity_unknown`이다. 상품 존재는 활성 확정과 동일하지 않다.

## 7. 위험 기반 표본 검수

- 우선순위 1에서 B 6개, C 39개, D 35개, E 20개, 총 100개를 검수했다.
- 공식 Musinsa 상품 API에서 906개 상품을 수집했고 실패는 0이다.
- category별 최대 10개를 사용했다.
- garment type 또는 length가 둘 이상이면 혼재로 처리했다.
- 표본 기준 category-level 일관성 통과 34개, review 필요 66개다.
- 통과 분포: C 20, D 13, E 1. B 6은 의미가 일관돼도 앱 지원 검토가 필요하므로 unsupported를 유지한다.
- 각 category의 상품 ID/URL, garment/length 분포, 예외율, confidence, 검수 시각은 `risk-sampling-results.json`에 있다.

## 8. staging 후보 최종 집계

| 상태 후보 | 수 |
|---|---:|
| confirmed candidate | 170 |
| review_required | 839 |
| rejected candidate | 927 |
| unsupported candidate | 40 |
| inactive | 0 |
| lifecycle activity_unknown | 1,976 |
| 표본 검수 완료 category | 100 |
| 미검수 category | 1,876 |

합계 `170+839+927+40=1,976`, 표본 `100+1,876=1,976`.

`staging-candidates-reviewed.json`은 source identity, snapshot version, raw/normalized path, target, tree, 상품 관찰, semantic/length/family 제안, 상태, confidence, reason, evidence, 앱 지원, manual review를 포함한다.

## 9. 적재 판정

- **staging 적재 승인 가능:** 예. 1,976개 전부 raw/proposal staging에 적재 가능한 형태다. 단, 이번 단계에서는 실제 적재하지 않았다.
- **canonical 적재 승인 불가:** 승인 가능한 행 0개.
- semantic confirmed 후보는 170개지만 이는 승인 완료가 아니라 검수 후보다.
- 현재 canonical 승격 불가능 1,976개. 이유는 activity 미확인, 미검수 1,876개, 충돌/지원 정책 및 사람 승인 미완료다.

## 10. 산출물

- `identity-matching-graph.json`: 전체 edge/component
- `identity-conflict-adjudications.csv`: 121+23+1 전체 판정
- `staging-candidates.csv/.json`: 원본 staging 후보
- `staging-candidates-reviewed.json`: 표본 결과 결합 후보
- `sampling-queue.json`: deterministic 우선순위 queue
- `risk-sampling-results.json`: 100 category/906 product 결과

