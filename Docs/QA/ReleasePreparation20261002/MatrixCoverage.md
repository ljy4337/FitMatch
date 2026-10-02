# 756-case matrix binding

## Prepared, not bulk executed

The original `data/comparison-cases.jsonl` and `data/comparison-dataset.json` remain unchanged. Corpus SHA-256: `6c1b712d806068cc3e44689149f8dd35421ac22a99c1bd964d690f48e3e114e0`.

`matrix-binding-v2.json` connects every original ID to a production Swift owner probe, with six unique synthetic UUIDs for comparison, reference Closet, target product, target variant, target size and deliberately unapproved size. All 756 IDs, original direction/group/pattern fields and 4,536 UUIDs were checked locally. These are test identities, never real product or account identities.

| Dimension | Planned rows |
|---|---:|
| 3×3 directed provider pairs | 84 per direction |
| Requested A–G groups | 108 per group |
| 12 source/missing-data patterns | 63 per pattern |
| Total original IDs | 756 |

The requested group and provider direction remain metadata. No fresh real mapping, approved A–G policy receipt, owned Closet row, eligible size or begin receipt exists in this corpus. A synthetic probe PASS cannot establish any of those facts. Every emitted row retains `authenticated_authorization_status`, `retailer_pair_authorization_status` and `group_policy_authorization_status` as **BLOCKED**.

## Swift selectors

- Smoke: `FitMatchTests/FitMatchReleaseMatrixTests/smokeRepresentativeCorpusCases` — exactly the three IDs in `matrix-binding-v2.json.smoke_case_ids`.
- Full: `FitMatchTests/FitMatchReleaseMatrixTests/fullSyntheticCorpusCases` — all 756 original IDs. **NOT RUN by this preparation subtask.**

The smoke covers a cross-provider canonical probe, the current MUSINSA zero-display policy, and an exact-size identity mismatch. Every result is emitted before the aggregate XCTest assertion, so a failing case does not silently prevent later cases from being inspected.

## What each pattern actually exercises

| Corpus pattern | Production owner / scoped assertion | Still unproven |
|---|---|---|
| complete_shared_canonical | `VNextComparisonEngineAdapter`: exact supplied size, single approved canonical metric, literal current-contract score 90 for delta 2, confidence 1, coverage 1 | Retailer normalization, current group policy and real server approval |
| no_common_metric | Adapter rejects empty approved evidence | Server's decision that no common metric exists |
| missing_unit | DTO decoding rejects missing `unit_code` | Raw-unit resolution and verified conversion |
| unit_conflict | Adapter rejects explicitly excluded canonical evidence | Actual pairwise unit conflict detection/conversion by server |
| basis_conflict | Adapter rejects explicitly excluded canonical evidence | Server proof that reference/target bases differ |
| component_conflict | Adapter rejects explicitly excluded canonical evidence | Server proof that garment components differ |
| raw_zero | `MeasurementResolver.sourceDisplayRows` keeps MUSINSA zero as one noncanonical `-` row and hides other-provider zeros; raw zero is preserved and empty score evidence rejected | Real parser ingestion/storage and deployed zero policy |
| unknown_raw_positive | Source display preserves positive unknown fact without canonical promotion; completion contains only separately supplied canonical evidence | Server dictionary/mapping and raw DB persistence |
| group_unmapped | Adapter rejects an unconfirmed target | Actual A–G picker interaction and subsequent authorization |
| different_group | Adapter honors scripted server denial | Actual same-group candidate/authorization filtering |
| exact_identity_mismatch | `VNextBeginComparisonDTO` rejects mismatched outer/snapshot approved size sets before the adapter with exact `FitMatchVNextContractError.conflictingProof("authorized_candidate_product_size_ids")` | Real product/variant/Closet ownership and server identity resolution |
| same_retailer_different_schema | Only explicitly supplied canonical evidence is scored; no `RETAILER_EXACT` activation | Schema equality/difference determination; cross-provider rows already require canonical-only handling |

The unit/basis/component cases intentionally distinguish **honoring a supplied exclusion** from **deriving that exclusion**. The Swift adapter receives one approved metric definition; it is not the owner of raw pairwise semantic adjudication. These tests never manufacture a server semantic proof from retailer labels.

The snapshot is a synthetic schema-3 replay accepted by the existing adapter. Its one-metric policy is a test contract, not an A–G policy definition. Numeric scoring remains current-implementation characterization; the independent formula/rounding policy questions in `policy-expectations.json` remain unresolved.

## Versioned expectation correction: zero display

The v1 binding incorrectly treated a parent interpretation as a later explicit policy override. Independent review found the current MeasurementPolicy §3.1/3.5, commit 5d78a42 and Handoff's 2026-10-01 decision all retain MUSINSA zero as `-`. No later direct reversal was established. See ExpectationAudit.md.

`matrix-binding-v2.json` restores the frozen corpus's existing dash expectation, records the reason and superseded binding, and keeps all original case IDs. The original v1 binding and FAIL evidence are preserved. The product, policy, raw corpus and numeric oracle did not change. The test asserts exactly one noncanonical dash row for MUSINSA; other-provider zeros remain hidden, raw values preserved, empty scoring evidence rejected. This corrects an invalid test expectation rather than a product defect.

## Raw retailer evidence stays separate

All matrix rows retain `source_fixture_binding: null` and `evidence_source: synthetic_contract_fixture`. Synthetic raw samples are labeled synthetic and use unknown evidence level. No archived retailer body is relabeled as a server-authorized comparison. Related real parser replay selectors appear separately in `matrix-binding-v2.json`; their successful raw parsing never fills an A–G assignment or authenticates a matrix row. ZARA's archived guide plus synthetic page shell retains its existing limited evidence scope.

## Machine-readable output contract

Set `FITMATCH_QA_MATRIX_OUTPUT` to an output directory; an Xcode runner can forward `TEST_RUNNER_FITMATCH_QA_MATRIX_OUTPUT`. The tests accept either spelling and atomically create separate files:

- `matrix-smoke.json`
- `matrix-full.json`

Both include `schema_version`, `mode`, corpus and binding SHA-256, `expected_case_ids`, `executed_case_ids`, expected/executed counts, synthetic pass/fail counts and `cases`.

Each case contains the original `id`; `status: PASS|FAIL` for its **scoped synthetic probe**; `evidence_scope: synthetic_production_owner_probe`; provider/group/pattern/probe/expected mode; exact synthetic identities; failure text or null; and all three real-authorization statuses as BLOCKED. Top-level `status` is FAIL if any probe fails, otherwise BLOCKED because real authorization remains missing.

The runner must compare exact original IDs and cardinality, verify both hashes, reject missing/malformed/duplicate cases and keep synthetic result status separate from authority status. Full results must contain 756 IDs; smoke only the three declared IDs. If both methods run in one process, the separate filenames prevent overwriting. A missing output file cannot count as executed coverage.

## Preparation verification

PASS: frontend Swift syntax parse, JSON loading, unchanged source hashes, exact 756 binding IDs and fields, 4,536 unique UUIDs, declared smoke IDs, `git diff --check`.

NOT RUN here: Xcode compile, smoke execution, full 756 execution, authenticated DB, UI and device E2E. The parent task supplies any later execution evidence and updates release gating separately.

Smoke follow-up: the parent's `/tmp/FitMatchPendingSmokeChecked` run exposed that the exact-identity fixture is correctly rejected during DTO decoding, earlier than the test's expected adapter error. The test now asserts the precise production error type and associated field. No error is swallowed; other errors still fail. The MUSINSA zero-hidden expectation and production code remain unchanged. This subtask only reran syntax/diff checks; the parent owns the Xcode rerun.

## Latest executed evidence

`/tmp/FitMatchResume40Focused`: matrix smoke 3/3 scoped probes PASS; combined 10 methods/11 executions PASS. `/tmp/FitMatchResume40Combined`: all selected 48 methods/61 executions PASS, including these same 3 probes. Authenticated matrix remains BLOCKED; full 756 NOT RUN. Original failing runs remain evidence, not retroactively PASS.
