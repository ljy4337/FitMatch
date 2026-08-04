# Taxonomy staging 적재 실행 보고서

- 실행일: 2026-08-03
- Supabase 프로젝트: FitMatch (`hnkplvyegonlhumlejst`)
- migration: `create_taxonomy_staging_v1`
- import run: `40677f85-e8a0-4a72-ad27-45524f385bcf`
- 상태: `completed`
- canonical 승격: 0

## 적용 범위

`fitmatch_staging` private schema에 다음 12개 테이블을 생성했다.

- `import_runs`
- `source_snapshots`
- `source_category_nodes`
- `source_category_hierarchy`
- `classification_candidates`
- `identity_components`
- `identity_matching_edges`
- `identity_conflict_adjudications`
- `sampling_runs`
- `sampled_category_results`
- `sampled_product_evidence`
- `validation_results`

public/anon/authenticated에는 schema/table 권한을 부여하지 않았다. 기존 public table은 identity edge의 `ON DELETE RESTRICT` FK로만 참조하며 수정하지 않았다.

## 적재 결과

| 테이블/관계 | 행 수 |
|---|---:|
| source snapshot | 2 |
| raw source category node | 4,008 |
| hierarchy edge | 3,978 |
| provisional candidate | 1,976 |
| identity component | 2,029 |
| identity matching edge | 2,034 |
| identity conflict/adjudication | 145 |
| sampling run | 1 |
| sampled category | 100 |
| sampled product evidence | 906 |
| validation result | 17 |

Snapshot IDs:

- Musinsa: `0a0fab7a-e6a6-45b9-ab5c-3426aba173e3`
- Uniqlo: `6b0627ec-e64b-44da-a403-6ae10976629c`
- sampling run: `6d15f604-5271-4309-a93a-1c7700f11fe3`

## 상태 검증

- provisional_confirmed 170
- review_required 839
- provisional_rejected 927
- provisional_unsupported 40
- 합계 1,976
- A/B/C/D/E/F: 927/40/175/103/414/317, 합계 1,976
- product_observed/navigation_only/activity_unknown: 1,650/317/9, 합계 1,976
- canonical promotion: blocked 1,049 / not_eligible 927
- approved/promoted: 0

Identity는 매칭 DB 2,031행, 매칭 snapshot 2,032노드, edge 2,034, N:N component 1개다. 중복 edge와 orphan FK는 0이다.

Sampling은 category 100, product 906, 수집 실패 0, 일관성 통과 34, review 필요 66이다.

## Checksum 및 불변성

- import input checksum: `c65ff8700bed46840f12f70af4ed138a8319abf49b00dabc387d83e2efcdc4be`
- import output checksum: `35406eb293f58da32fe03227c07fc8c2`
- Musinsa snapshot SHA-256: `6bb0dbdfd64f715797b68aae979805a1901377d141823c40d20608a8eb13d4aa`
- Uniqlo snapshot SHA-256: `6b534b68e52650e4593d7d29c8b70c28ee12db8018c3db81bd27902d80ad0ef9`
- 기존 public checksum 사전/사후: `03c069ba1ccb198b4195d825dc40d82b`
- 기존 source category: 2,031 → 2,031
- 기존 status: confirmed 979 / review_required 492 / rejected 560, 변경 없음
- validation 실패: 0
- policy version 누락: 0

## 재실행과 복구

모든 staging ID는 입력 identity에서 deterministic 생성했고 unique constraint와 `ON CONFLICT DO NOTHING`을 사용한다. 동일 import 재실행은 중복 행을 만들지 않는다.

복구는 `006_taxonomy_staging_rollback.sql`에 정의했다. import run 한 건만 삭제하며 staging 내부 FK만 cascade된다. public source category FK는 restrict이고 public 데이터는 삭제·수정하지 않는다.

## 남은 작업

미검수 category는 1,876개다. 다음 단계는 우선순위 1 잔여 → 우선순위 2 → C 그룹 순으로 별도 sampling run을 추가하는 것이다. 기존 snapshot/candidate를 덮어쓰지 않고 신규 sampling evidence와 수동 adjudication만 추가해야 한다.

