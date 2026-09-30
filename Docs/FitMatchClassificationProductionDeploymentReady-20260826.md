# FitMatch Classification Production Deployment Readiness — 2026-08-26

Status: **READY FOR A SEPARATELY APPROVED CONTROLLED DEPLOYMENT**. This document is a runbook only. This task performed no Production apply, write, release activation, history backfill, or iOS call-site change.

## 1. Preconditions

- Owner explicitly approves the Production window, operator, rollback owner, and change ticket.
- Repository commit is immutable and contains the validated exact files 113–118 plus their validation/manifest artifacts.
- Production SELECT-only preflight matches: products `1,608`, decisions `5,056`, history/current `1,860/1,608`, releases `5`, active release `65d72393-4a40-4e99-b701-fdc1ff865774`, active mappings `3,492`, latest ledger `20260821090138`.
- Recompute and match the frozen baseline, manifest, and shadow checksums from the Closure report.
- Repeat the complete disposable PostgreSQL 17 apply/reapply validation from the exact deployment commit.
- Block retailer ingestion, automated classification writes, and release activation jobs for the activation window. App reads may remain available until the atomic switch.

## 2. Exact migration order

Apply content in this order only:

1. `113_p3_data_quality_observability.sql`
2. `114_release_gate_and_quality_review_queue.sql`
3. `115_authoritative_classification_foundation.sql`
4. `116_classification_candidate_release.sql`
5. `117_classification_candidate_revision_safe_data.sql`
6. `118_classification_db_final_closure.sql`

Why strict: 114 consumes 113 observability columns; 115 hard-checks 114 gates/views/grants; 116–118 are additive candidate revisions pinned to the preceding release contract.

Do not use an unordered `db push`. Do not apply 115–118 alone.

## 3. Migration ledger naming and reconciliation

Production uses timestamp ledger versions, while repository files 113–118 use ordinal names. The current latest version is `20260821090138`, so never mark the numeric names as already applied and never run a speculative migration repair.

For the approved deployment bundle, use these monotonic ledger identities for the exact checksummed file contents:

| Repository file | Controlled ledger version/name |
|---|---|
| 113 | `20260826090113_p3_data_quality_observability` |
| 114 | `20260826090114_release_gate_and_quality_review_queue` |
| 115 | `20260826090115_authoritative_classification_foundation` |
| 116 | `20260826090116_classification_candidate_release` |
| 117 | `20260826090117_classification_candidate_revision_safe_data` |
| 118 | `20260826090118_classification_db_final_closure` |

The deployment runner must apply each exact file transactionally and then verify one corresponding ledger row before proceeding. Record content SHA-256 beside each ledger identity in the change ticket. If any version/name already exists with a different checksum, stop; do not repair or overwrite the ledger.

## 4. Preimage backup requirements

Before the first write, export a transactionally consistent, encrypted preimage with row counts and SHA-256 for:

- `fitmatch_catalog.releases`
- the active release's `source_category_mappings`
- every exact product-decision key present in manifests 116, 117, and 118, including all columns and `xmin`/update timestamp evidence
- `classification_path_profiles`, `classification_name_profiles`, and `classification_exclusion_profiles`
- taxonomy rows touched by 115–118: `app_categories`, `comparison_groups`, `garment_types`, `comparison_length_classes`
- `comparison_policies`, `fitmatch_taxonomy.comparison_compatibility_rules`, and `app_category_measurement_policies`
- current function definitions, owners, volatility/security mode, `search_path`, and grants for resolver/recorder/evaluator plus affected public RPCs
- current classification-history row counts and current-row key checksum; do not mutate history during schema/candidate deployment

Backups must be restorable by logical key, not only by generated UUID. Store them outside the Production database and verify a read-back checksum before applying 113.

## 5. Candidate apply and gate

Migrations 113–118 may create only an inactive/validated candidate. After every migration:

- verify expected object count, grants, and ledger row;
- run the corresponding validation SQL in an explicit transaction that ends in `ROLLBACK`;
- verify active release ID and active mapping count remain unchanged.

Before activation, require both:

- existing release gate v2 succeeds;
- `fitmatch_catalog.runtime_classification_db_final_gate_v1(candidate_release_id)` returns `eligible=true`, empty blockers, matching four runtime versions/checksums, Gold `3/3`, safety leaks `0`, shadow `1,608`, and `production_write_count=0` from the candidate report.

Any checksum, cardinality, grant, tuple, or gate mismatch is a stop condition.

## 6. Atomic activation transaction

Activation needs a separately reviewed SQL transaction. It must:

1. acquire the existing release advisory transaction lock;
2. lock current and candidate release rows;
3. recheck the current active release preimage and candidate gate;
4. materialize only the exact verified decision manifest after comparing every preimage;
5. make the candidate active and retire the old release in the same transaction, preserving the single-active unique constraint;
6. switch the approved internal/public function definitions to v4 with the new active release contract;
7. re-run gate/smoke assertions before commit;
8. commit once, or roll back everything.

Never activate mappings first and switch functions later. Do not perform history backfill in this transaction.

## 7. Internal v3/v2 → v4 switch list

The candidate runtime exists but current public flows still consume older paths. The controlled integration migration must update existing functions in place; do not create parallel v5 APIs.

| Current consumer | Required switch |
|---|---|
| `fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)` | v2 resolver call → `runtime_resolve_product_classification_v4(..., active_release_id)`; pass `structured_facts` unchanged; recorder remains v2 |
| `public.fitmatch_resolve_product(jsonb)` | shadow candidate v2 call → pinned v4; current-history fast path remains authoritative only for the active contract/fingerprint |
| `public.fitmatch_process_product_observation(jsonb)` | verify its indirect promotion uses the updated promoter and preserves issue/queue behavior |
| `public.fitmatch_find_reference_candidates(uuid)` | evaluator v3 calls → `runtime_evaluate_comparison_profiles_v4(..., active_release_id)` |
| `public.fitmatch_begin_comparison(uuid,uuid,boolean,uuid)` | evaluator v3 call → v4 and final policy version; insufficient measurements remains blocked |

`runtime_record_product_classification_v2` stays v2. Resolver/evaluator v5 and duplicate public RPCs are prohibited.

## 8. Public RPC and read-contract smoke list

After the atomic switch, verify authenticated and service-role behavior for:

- `fitmatch_resolve_product`
- product-observation Edge Function → `fitmatch_process_product_observation`
- `fitmatch_get_product_runtime`
- `fitmatch_register_closet_item`
- `fitmatch_upsert_closet_item`
- `fitmatch_list_closet_items`
- `fitmatch_find_reference_candidates`
- `fitmatch_begin_comparison`
- `fitmatch_complete_comparison`

Anonymous execution must remain denied where currently denied. Confirm `SECURITY DEFINER`, fixed empty `search_path`, owner, and grants after every `CREATE OR REPLACE`.

## 9. Closet / Compare and iOS integration call sites

No Swift file was changed in Closure. The next integration change must wire these existing locations to server authority:

- `FitMatchSupabaseProductResolver.swift`: `FitMatchSupabaseDomainClient.resolve`, `fetchProductRuntime`, `findReferenceCandidates`, `beginComparison`, and existing RPC DTOs.
- `FitMatchClosetSyncCoordinator.swift`: remote resolve/register/hydration path; local `ParsedClosetClassification.resolve` must not overwrite a server-confirmed tuple.
- `FitMatchComparisonSyncCoordinator.swift`: resolve → reference candidates → begin comparison → complete comparison sequence.
- Parser/adapters for Musinsa, UNIQLO, and ZARA: forward typed `structured_facts` and the existing set/exclusion result; do not embed canonical decisions.

The app may use local classification for presentation/recovery only when the server returns no confirmed authority. Server-confirmed and server-not-comparable states win.

## 10. Production smoke products

Mandatory read/resolve checks after activation:

- Gold: UNIQLO `E482514`, `E454311`, `E456567`
- exact decision completion: `E482522`, `E485454`
- structured canonical examples from each of the five Musinsa scoped rules
- pure Musinsa short/long T-shirt categories
- UNIQLO sleeveless T-shirt and base-layer categories
- verified path examples for dress, skirt, blazer, trunks, briefs
- UNIQLO typed accessory exclusion
- unknown ID + pure category; unknown ID + PRODUCT_REQUIRED + structured discriminator; unknown ID + PRODUCT_REQUIRED without discriminator
- insufficient-measurements confirmed product
- explicit blocked pair: T-shirt ↔ base-layer top
- explicit allowed same-family pair and sweatshirt↔hoodie policy case

## 11. Set-product smoke fixtures

Required known rows: Musinsa `4800605`, `5982920`, `6593581`, `6786576`, `6797265`, `6797266`, `6797271`.

Also run synthetic set-in-T-shirt-category and homewear-set payloads. Every case must resolve `not_comparable`, never create a garment-confirmed history row, never enter reference candidates, and always block `fitmatch_begin_comparison`. A normal color/variant single T-shirt must remain non-set.

## 12. Gold and release acceptance

Before and after activation:

- full `1,608` key/fingerprint parity;
- Gold exact `3/3`;
- invalid tuples, arbitrary fallback, set leaks, revoked/invalid leaks, PRODUCT_REQUIRED-alone confirmation, unverified name/path confirmations: all `0`;
- final candidate distribution matches the approved artifact unless an explicitly reviewed ingestion drift forces stop;
- existing valid-confirmed unintended regression `0`;
- comparison matrix `990`; active comparable family without comparison or measurement policy `0`.

Do not edit expected values to make the gate pass.

## 13. Rollback successor

Rollback is forward-only. Do not delete history, reactivate a retired release directly, or drop additive schema during an incident.

Prepare a new rollback-successor release before activation. It clones the exact pre-activation active mapping bundle and policy identifiers under a new release ID/key, has its own checksums, and passes the same release gate. The rollback transaction must:

1. acquire the release advisory lock;
2. verify the failed active release and backup checksums;
3. restore exact decision preimages using logical keys and optimistic preimage checks;
4. replace switched function definitions/grants with their backed-up definitions;
5. activate the validated rollback successor and retire the failed release atomically;
6. run Gold, set, safety, current-row, and public RPC smokes before commit.

Additive tables/columns can remain unused. Schema removal is a separate maintenance change after recovery.

## 14. Rollback acceptance criteria

- previous classification/read/compare behavior restored for the backed-up universe;
- active release exactly one; active mapping count/checksum equals rollback successor manifest;
- exact decision rows equal preimage checksum;
- history rows were not deleted; current-row uniqueness preserved;
- Gold `3/3`; set comparison leak `0`; invalid/revoked leak `0`;
- public RPC grants and signatures match the preimage;
- Production error rate and latency return to the pre-change baseline.

## 15. Deployment completion evidence

Archive the change ticket, operator/timestamps, exact commit, six migration checksums and ledger rows, pre/post snapshots, preimage backup checksum, candidate and activation gate JSON, full shadow checksum, Gold/set/safety outputs, public RPC smoke results, and rollback-successor ID/checksum.

Only after this evidence passes may the separate iOS server-authority integration and user-device validation proceed.
