# FitMatch Classification Measurement Policy Checksum Correction — 2026-08-26

## 결론

`measurement_policy_checksum_mismatch`의 원인은 measurement policy 데이터 차이가 아니라 `numeric` typmod에 따른 `weight` JSON 직렬화 차이다.

- Production `public.app_category_measurement_policies.weight`: `numeric(6,3)`
- Candidate local fixture `weight`: unconstrained `numeric`
- Production raw checksum: `6ad654049b08f6d19bd6a59c2a50482f550ee9edf6a0b9faad5d6f74b31a18a2`
- Candidate raw checksum: `d2a98b24f29ddfb57c0e2afa3215a7d9920a2a5f110fe50e301267c443ec4713`
- `trim_scale(weight)` + explicit `COLLATE "C"` canonical checksum: `42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0` on both datasets

Production의 runtime policy 값이 맞다. Candidate가 고정한 raw checksum은 fixture의 numeric 표현에 종속되어 gate contract로는 부적절하다. Production policy rows는 수정하지 않으며, 119는 동일 숫자값이 typmod와 locale에 무관하게 같은 checksum을 갖도록 gate checksum을 canonicalize한다.

## 63-row exact diff

Logical key `(category_code, measurement_key, dimension_code)` 기준 결과:

- Production rows: `63`
- Candidate rows: `63`
- Unique logical keys: `63 / 63`
- Missing/extra rows: `0 / 0`
- Runtime-semantic diff rows: `0`
- Metadata-only diff rows: `0`
- `evidence_note` diff rows: `0`
- Serialization-only diff rows: `63`

Checksum 입력의 모든 필드를 비교했다: `category_code`, `measurement_key`, `dimension_code`, `weight`, `is_primary`, `is_comparable`, `cross_source_mode`, `required_group_code`, `required_group_min_dimensions`, `display_order`, `selection_priority`, `is_active`, `evidence_note`.

차이가 난 유일한 column은 `weight`의 문자열 scale이다. PostgreSQL numeric 값 비교는 63/63 모두 equal이다.

| Candidate text | Production text | Rows |
|---:|---:|---:|
| `0.6` | `0.600` | 5 |
| `0.7` | `0.700` | 2 |
| `0.8` | `0.800` | 4 |
| `0.9` | `0.900` | 4 |
| `1` | `1.000` | 5 |
| `1.0` | `1.000` | 6 |
| `1.1` | `1.100` | 1 |
| `1.2` | `1.200` | 14 |
| `1.3` | `1.300` | 6 |
| `1.4` | `1.400` | 14 |
| `1.5` | `1.500` | 2 |

Category별 serialization-only rows는 `bottoms 11`, `dresses 7`, `homewear 9`, `leggings 7`, `outerwear 8`, `skirts 6`, `tops 6`, `underwear 9`다.

모든 logical key와 before/after value는 [FitMatchClassificationMeasurementPolicyChecksumDiff-20260826.jsonl](./FitMatchClassificationMeasurementPolicyChecksumDiff-20260826.jsonl)에 63행으로 기록했다. Artifact SHA-256은 `4074f8389d0ba19f3e50bce35115019684f1a9fec2f1f74be6db58f31f9f3756`이다.

### Diff 판정

| 구분 | 결과 |
|---|---:|
| A. 실제 runtime 의미가 다른 row/column | `0` |
| B. `evidence_note` 등 metadata만 다른 row/column | `0` |
| C. ordering/serialization/numeric representation 문제 | `63`, 모두 `weight` scale serialization |
| D. candidate expected checksum 문제 | `YES`; unconstrained numeric fixture의 raw encoding을 expected로 고정 |

Row ordering 차이는 관측된 raw checksum 차이의 직접 원인이 아니지만, deterministic contract를 위해 119는 measurement key ordering에 explicit `COLLATE "C"`도 고정한다.

## Authority 판단

Production actual policy values를 authority로 유지한다.

- 63행의 numeric 값과 나머지 12개 필드는 candidate와 exact semantic parity다.
- Production의 `numeric(6,3)` 값은 잘못된 데이터가 아니다.
- Candidate raw checksum을 맞추기 위한 Production row rewrite는 runtime 의미 없이 저장 표현만 바꾸므로 하지 않는다.
- `evidence_note`를 checksum에서 제외하지 않는다. 119 canonical checksum은 기존 13개 필드를 전부 계속 검증한다.
- Correct expected checksum은 semantic canonical checksum `42d5aa...`다.

## 119 corrective migration

Created [119_classification_measurement_policy_checksum_correction.sql](../supabase/migrations/119_classification_measurement_policy_checksum_correction.sql).

- SHA-256: `0c873e441eed10e68b01fbaaed24b420e84395140fe8eff495f879e87b417df5`
- 118 migration과 ledger를 변경하지 않는다.
- Measurement policy row `INSERT`/`UPDATE`/`DELETE`는 `0`이다.
- Candidate release가 exact 118 ID/key이며 `validated`인지 lock 후 확인한다.
- Policy rows `63`, raw checksum이 known Candidate/Production preimage 중 하나, semantic checksum이 `42d5aa...`인지 모두 확인한다.
- 기존 `runtime_policy_contract_report_v1(uuid)` 이름과 signature를 유지한 `CREATE OR REPLACE`다.
- Measurement checksum에서만 `weight`를 `trim_scale(weight)`로 canonicalize하고 logical-key ordering에 `COLLATE "C"`를 적용한다.
- Function은 `STABLE`, `SECURITY INVOKER`, empty `search_path`, `service_role` execute-only contract를 유지한다.
- Candidate validation report의 measurement checksum만 canonical checksum으로 교정하고 correction metadata를 남긴다.
- Policy report, final gate, release gate가 모두 eligible/blocker-empty인지 같은 transaction 안에서 확인한다.
- Reapply/idempotency를 지원한다.

Validation artifact는 [119_classification_measurement_policy_checksum_correction_validation.sql](../supabase/sql/119_classification_measurement_policy_checksum_correction_validation.sql), SHA-256 `20ec007f925099e82b82742769a554616fc1b84dcfd72d5c9d921d09df686860`이다.

## Local PostgreSQL 17 production-shaped verification

Production-shaped PostgreSQL 17 disposable copies에서 다음을 수행했다.

1. Production `weight numeric(6,3)` 상태에서 113–118 candidate gate의 sole blocker가 `measurement_policy_checksum_mismatch`이고 raw checksum이 `6ad654...`임을 재현했다.
2. 119 apply 후 policy/final/release candidate gate가 모두 `eligible=true`, `blockers=[]`가 됐다.
3. 119를 같은 pre-activation copy에 재적용해 idempotency PASS를 확인했다.
4. Rollback successor `11800000-0000-4000-8000-00000000b001`을 생성하고 release gate PASS를 확인했다.
5. 기존 atomic activation artifact로 candidate activation COMMIT을 수행했다. Candidate가 유일한 active release이고 active mappings는 `3,509`, decisions는 `5,056`이었다.
6. Post-activation 전체 118 validation을 다시 실행했다.
7. Privacy-safe synthetic history cardinality `1,860 / current 1,608`을 가진 별도 copy에서 activation 후 기존 atomic rollback artifact로 rollback successor 복구 COMMIT을 수행했다. History count/current와 decisions `5,056`이 보존되고 active release는 정확히 1개였다. Production history 본문은 복사하지 않았다.

Full validation result:

| Check | Result |
|---|---:|
| Products | `1,608` |
| Confirmed / review_required / not_comparable | `348 / 1,113 / 147` |
| Gold | `3/3 PASS` |
| Synthetic | `29/29 PASS` |
| CATEGORY_DIRECT / PRODUCT_REQUIRED / REVOKED | `55 / 1,019 / 2,435` |
| Structured rules | `21` |
| Path / name / exclusion profiles | `12 / 0 / 15` |
| Comparison matrix | `990` |
| Confirmed invalid tuple | `0` |
| Arbitrary fallback | `0` |
| Set garment-confirmed / comparison-allowed | `0 / 0` |
| History write/delete | `0 / 0` |

따라서 classification 결과와 runtime policies는 118 Closure baseline에서 불변이다.

## Production READ-ONLY postflight

Observed at `2026-08-26T12:56:35.010754Z`:

- Ledger 118: present exactly once
- Ledger 119: absent
- Active release: exactly 1, `65d72393-4a40-4e99-b701-fdc1ff865774`
- Active mappings: `3,492`
- Final candidate: `11800000-0000-4000-8000-000000000118`, `validated`, inactive, mappings `3,509`
- Rollback successor: absent
- Products / decisions: `1,608 / 5,056`
- History / current: `1,860 / 1,608`
- Gate blocker: exact one, `measurement_policy_checksum_mismatch`
- Production measurement raw checksum: unchanged `6ad654...`

이번 작업의 Production write/DDL/migration apply/activation/history write/delete는 모두 `0`이다. Swift/iOS 변경과 Git commit/push도 수행하지 않았다.

## Deployment readiness

119는 이 blocker만 해결하는 최소 corrective migration으로 local PASS 상태다. Owner가 119 exact SHA를 승인하면 기존 controlled sequence를 `119 apply → candidate final gate → rollback successor → atomic activation → smoke → postflight` 순서로 재개할 수 있다.
