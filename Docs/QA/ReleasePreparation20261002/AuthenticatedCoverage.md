# Authenticated Swift coverage preparation — 2026-10-02

## Status and boundary

**NOT RUN:** live authentication, RPC mutations, and all live A–H cases. No accounts were created and no DB writes were performed while preparing these tests. Credentials are absent; this is not a pending approval request.

`FitMatchReleaseAuthenticatedTests.swift` and `FitMatchReleaseAuthenticatedSupport.swift` prepare two opt-in selectors. They call the real Supabase SDK and `FitMatchSupabaseDomainClient`, actual payload adaptation, `VNextComparisonEngineAdapter`, `VNextHistoryCacheHydrator`, and `FitMatchClosetDeletionTransaction`. They do not replace network responses or server authority. They do not prove button interaction, ViewModel routing, app relaunch, SwiftData projection, or physical-device UI. A–H below means the explicitly described domain-owner coverage, not complete UI acceptance or independent approval of the scoring formula.

Root-runner compilation/execution evidence is recorded separately. Initial root compilations found a test-only measurement initializer mismatch and then nonoptional field requirements; after reading `GarmentMeasurements`, the fixture uses shoulder 48, chest 52, total length 70, sleeve 24. Syntax parsing is not type-check/build evidence.

## Safe invocation contract

The runner must perform the existing Python credential preflight before selecting either test. Use only `FitMatch-QA` / `Debug-QA`; the support code independently accepts only the exact HTTPS development URL `https://hnkplvyegonlhumlejst.supabase.co` (optional trailing slash). Production, unknown hosts, URL suffixes/ports/paths, privileged keys, foreign/elevated/anonymous/expired user JWTs, and duplicate users are rejected before network calls.

In addition to the seven variables in [environment.example](environment.example), supply real normal-session `FITMATCH_QA_DB_USER_A_REFRESH_TOKEN` and `FITMATCH_QA_DB_USER_B_REFRESH_TOKEN`. Each access token must have more than ten minutes remaining at setup, and each fresh client requires more than two minutes remaining. `FITMATCH_QA_AUTH_RUN_ID` is a fresh UUID and `FITMATCH_QA_AUTH_OUTPUT` is a new absolute JSON file path, unique for each selector. Both accounts must start with empty active Closet and History lists.

The pinned SDK 2.53.0 `setSession(accessToken:refreshToken:)` verifies an unexpired access token via `/auth/v1/user`. Genuine refresh tokens are required; no placeholder refresh token or fabricated `Session` is used. Automatic refresh is disabled, session storage is memory-only, and HTTP redirects are refused. See [official session documentation](https://supabase.com/docs/reference/swift/auth-setsession). Keychain and personal app sessions are never read.

Forward only the required variables using the runner's `TEST_RUNNER_` environment mechanism; never place credentials in command-line arguments, manifests, reports, chat, or logs. XCTest launch configuration/result bundles may contain injected environment values: retain raw artifacts only in the runner's private directory with restricted permissions, outside Git. Publish only sanitized summaries. This support code prints fixed status messages and writes no credential values.

| Selector | Required inputs / emitted case IDs |
|---|---|
| `FitMatchTests/FitMatchReleaseAuthenticatedTests/dedicatedDevelopmentAccountsExerciseRealSwiftClosetLifecycle` | Credentials plus run/output; `AUTH-VERIFY`, `A-MANUAL`, `ISOLATION`, `B-MANUAL`, `C-MANUAL`. |
| `FitMatchTests/FitMatchReleaseAuthenticatedTests/dedicatedDevelopmentAccountsExerciseRealSwiftAH` | Same, plus `FITMATCH_QA_DB_CASE_MANIFEST`; `AUTH-VERIFY` and each seed ID followed by `/A`, `/ISOLATION`, `/D`, `/F`, `/B`, `/G`, `/H`, `/E`, `/C`. |

Missing/invalid setup writes a sanitized `BLOCKED` report when an unused output path is available and records a Swift Testing issue. It never skips or returns an empty PASS. Successful reports contain `run_id`, `expected_case_ids`, exact matching PASS cases, `request_count` (completed SDK URLSession tasks), `real_db_case_count`, and cleanup status. `full_ah_status` can pass only in the seeded selector; manual CRUD never implies A–H completion. Failed cleanup changes the overall status to BLOCKED.

## Verified seed manifest

The full selector accepts a local JSON document with `version: 1`, `project: "hnkplvyegonlhumlejst"`, and a nonempty `cases` array. Each case contains a unique `id`, `expectedGroup` (A–G), and `reference`, `secondReference`, `target` seeds. Every seed contains:

- `resolution`: the exact existing `FitMatchProductResolutionRequest` JSON (`source`, `external_product_id`, `product_name`, optional source-category/audience fields, `structured_facts`). Preserve retailer identity distinctions; never equate ZARA internal product and selected catentry IDs.
- `productID`, `variantID`, `sourceObservationID`, `selectedSizeID`, `alternateSizeID`: verified existing development UUIDs. The two reference products must differ; target selected/alternative sizes must differ.
- `sizes`: expected entries `{ "id": "<exact size UUID>", "sourceMeasurementCount": <positive integer>, "canonicalMeasurementCount": <positive integer> }` for both selected and alternative sizes. Counts must come from independently verified source/DB evidence, not be filled from a failed test's output merely to obtain PASS.

No synthetic or guessed seed is supplied. The test re-fetches runtime, requires the expected exact product/variant/sizes, current readiness, confirmed server classification, and the same server comparison group for all three products. It does not ingest shared catalog data, create product observations, override classification, or assign a group from the manifest. Missing/stale/unready seeds stop execution.

Multiple manifest cases can represent distinct retailer pairs/groups. The report counts only supplied, actually executed cases; one seed does not establish a 3×3 retailer matrix or all A–G groups. Case IDs should describe the curated pair; retailer evidence remains in each exact resolution/runtime.

## Executable scope

| ID | Actual owner/contract assertions |
|---|---|
| A | Linked create through domain payload adapter; exact fresh-client read-back; source-observation/product/variant/size manifest and raw/canonical counts; same-request retry retains one client/server identity. |
| B | Linked selected-size update; fresh identity/raw/canonical count verification; second Closet unchanged; previously completed History snapshot unchanged before another comparison replaces its visible head; fresh comparison uses the edited exact Closet. |
| C | Production deletion transaction validates receipt before local commit; fresh exact/list reads hide only the selected run row; second Closet unchanged. The app action's associated-History policy is not established by this narrower transaction. |
| D | Current server eligible sizes/fingerprints; begin with exact chosen reference and target; real engine uses server snapshot; completion and same-ID retry; new-client History identity/evidence equality; B cannot read A's History. |
| E | Exact generated client-comparison ID hide; fresh sync must contain its tombstone and omit it from active History; unrelated Closet and the H comparison of a different target remain unchanged. |
| F | Production completed-History validation/replay reproduces persisted completion evidence and includes the exact approved alternative size. This is replay availability, not private SwiftUI selected-state behavior. |
| G | Explicit second run-created Closet triggers fresh eligibility/begin/complete with a different comparison ID; retained first snapshot still replays unchanged. Hidden older rows are not claimed re-readable via the active-list API. |
| H | The manifest's explicit target alternative must differ from the actual recommendation. Normal linked persistence and exact raw/canonical read-back preserve that size; prior comparison remains unchanged. The new row then receives current server eligibility/begin/complete against the manifest reference product. Server rejection blocks this chain. UI save-sheet interaction remains outside this case. |
| Isolation | B exact get/list empty; B update/delete must raise an accepted database rejection, not merely a transport error; A's full authoritative row remains unchanged after each attempt. |

## Ownership ledger and cleanup

The mode-0600 `<output>.ledger.json` records project, run UUID, both user UUIDs, generated client item/comparison IDs, exact server IDs when received, and per-item run markers **before mutations**. Existing output/ledger files block a new run. Cleanup uses only IDs recorded for that run and validates marker + product/variant + client/server identity before deleting a Closet row. It never enumerates by prefix to delete, mutates catalog data, deletes users, uses SQL, or hard-deletes stored snapshots.

Completed run comparisons are hidden using exact generated client IDs; run Closet rows are soft-deleted and reread with a fresh client. Ambiguous create responses and pending/ambiguous begin results remain BLOCKED with the ledger retained for exact reconciliation. In the original run's automatic cleanup, known Closet cleanup still proceeds when a pending comparison cannot be reconciled. Zero active rows does not mean physical deletion. Do not pass this distinct ledger format to the Python cleanup command.

## Interrupted-run cleanup entry point

The opt-in selector `FitMatchTests/FitMatchReleaseAuthenticatedTests/interruptedDevelopmentRunCleansOnlyValidatedLedger` resumes **cleanup only**. It never repeats create, edit, begin, or complete. Preparation added no network call or DB write; actual interrupted-run cleanup remains **NOT RUN** until dedicated credentials and a real ledger are supplied.

Use the same nine dedicated Auth variables, plus:

| Variable | Value |
|---|---|
| `FITMATCH_QA_AUTH_LEDGER` | Absolute path to the original regular, nonsymlink Swift `.ledger.json` file. |
| `FITMATCH_QA_AUTH_RUN_ID` | That original ledger's run UUID, not a new run ID. |
| `FITMATCH_QA_AUTH_OUTPUT` | A new, separate absolute cleanup report path. Existing output files block execution. |

No seed manifest is needed. After the runner's credential preflight, the test first decodes and validates the ledger's actual stored version/project, original run UUID, exact owner/observer pair, unique client/server IDs, item markers, complete linked identity pairs, and each comparison's reference membership. The decoder explicitly reads stored project/version values; defaults cannot replace a foreign or malformed value.

Both users then authenticate through the real SDK. Before **any cleanup mutation**, one authoritative plan must validate all active run Closet rows by exact client/server ID, marker, product and variant, using both list and exact reads. A missing active row, duplicate row, mismatched marker, or conflicting server ID blocks the whole restored cleanup. A lost create response can be reconciled only when exactly one live row proves the complete run identity. Already-recorded deletions require a known server ID and absent active/exact rows.

For each recorded completed comparison, cleanup requires either its exact visible History tuple and a still-active, marker-verified reference Closet, or one unambiguous owner-scoped tombstone. A tombstone produces no further hide request. Pending comparisons, absent History without a tombstone, visible/tombstone conflicts, or an unverified deleted reference block cleanup. This deliberately preserves unresolved cases instead of inferring ownership from an input file. The initial file remains unchanged if this validation phase fails.

After validation, the existing exact cleanup path hides only validated comparison IDs and soft-deletes only validated run rows, saving progress to the original ledger. Fresh-client postflight requires no active run rows. The new sanitized report uses `evidence_kind=authenticated_swift_ledger_cleanup`, the original `run_id`, and exact `expected_case_ids=["AUTH-VERIFY", "LEDGER-CLEANUP"]`. `full_ah_status` remains BLOCKED: cleanup success does not establish A–H acceptance. Authentication, validation, mutation, or postflight uncertainty yields BLOCKED and preserves the ledger.

`FitMatchReleaseAuthenticatedLedgerSafetyTests` prepares six offline tests against the same pure helper used by this entry point: valid roundtrip; foreign project/version/accounts/run/malformed UUID; duplicate IDs/marker/tuple corruption; exact active-item proof and ambiguous create; recorded-deletion conflict; and exact comparison/tombstone proof. These tests cannot perform Auth, HTTP, or DB operations. Syntax validation passed; XCTest/build execution evidence belongs to the root run report, not this preparation claim.

## Latest execution evidence

The standalone cleanup and both authenticated selectors compiled and were discovered in `/tmp/FitMatchResume40Combined`. Six offline ledger tests passed (also `/tmp/FitMatchResume40Focused`). Actual authenticated calls remain BLOCKED: no dedicated credentials/seeds. `python3 scripts/release_qa.py cleanup --ledger <original Swift ledger> --output <new directory>` forwards only the required session/ledger variables and checks the current-run receipt. Missing credentials were exercised: exit2/BLOCKED, no Xcode/network invocation. Runner Ctrl-C/malformed receipt regressions were tested RED→GREEN; partial cleanup always retains a result report. These are preparation evidence, not a successful real cleanup.
