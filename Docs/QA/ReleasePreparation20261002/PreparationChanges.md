# Preparation changes after storage cleanup — 2026-10-02

This is an additive preparation revision; original evidence in `evidence/FitMatchPrepSmokeFinal` remains historical and unchanged. Production Swift, DB, policies, UI, and frozen retailer fixtures were not changed.

## Changed inputs

- `preparation-resume-baseline.json` records the previous four plan hashes.
- `smoke-selectors.json` adds two continuous production-owner sequences and the intercepted HTTP transport fault suite. Existing cases and expectations are retained.
- `plan-SHA256SUMS` is regenerated for that documented selector addition. `oracle.json`, `policy-expectations.json`, and retailer `data/SHA256SUMS` retain their original values.
- Source assertions remain explicit; adding a source file is not test execution evidence. The current run's xcresult/discovery determines execution.

## Runner repairs

Two independent review findings were reproduced by regression tests before the implementation was changed:

1. A report with missing mode could return PASS despite absent required cases. Missing/unknown modes now produce FAIL.
2. A interrupted output directory without results.json could contain old xcresult/live-parser artifacts and be reused. All nonempty output directories are now rejected before execution; report mode remains the way to review existing results.

RED: `python3 -m unittest discover -s scripts/tests -p test_release_qa.py -v`, exit 1 (two test methods, three failing subcases). GREEN: same command exit 0, 13 tests. Evidence: `evidence/Resume20261002/FitMatchPrepRunnerRed.log` and `FitMatchPrepRunnerGreen.log`.

During initial test construction, the command-line guard regression accidentally allowed recursive runner self-test invocation. That test was corrected to stub execution boundaries before recording the reproducible RED run; owned processes were stopped/finished, no DB mutation occurred. This was a test-tool construction issue, not an app defect.

## Independent policy review

Historical `Docs/flows/12_FitConfidenceFlow.md` and `Docs/무신사_유니클로_카테고리별_사이즈저장_비교표.md` describe the 100−5×difference rule. They also contain superseded comparison gates/weights. `Docs/flows/11_RecommendationFlow.md` describes an obsolete automatic-reference flow. These documents help trace history but do not establish current, independently approved rounding/final tie-break policy. No old rule is promoted over the current MeasurementPolicy. Arithmetic fixtures remain characterization, and the unresolved policy gate is retained.

## Safety

The current QA branch and both QA build configurations target development `hnkplvyegonlhumlejst`. Dedicated account credentials are absent; actual authenticated mutation remains BLOCKED. See `AuthReadiness.md`. No production target, migration, account creation, credentials in source, commit, push, or merge.

## Initial added-sequence failure

The first resumed smoke compiled and ran all selected tests: 35 method results passed and 2 failed (47 passed / 2 failed parameter-expanded executions). Existing 32 methods and 15 transport-fault executions passed. Both sequence tests stopped at product construction before candidate authorization. A diagnostic-only focused rerun showed `calls=[observation,runtime]` and the production invalid-product message.

Cause: the reused synthetic runtime exposed one expanded historical code `chest_width_pit_to_pit`; the current runtime single-measurement gate requires an active canonical code. Existing fixtures with two scalar dimensions did not expose this inconsistency. The sequence fixture now supplies `runtimeMetrics` with active `chest_width`, preserving the original approved comparison evidence and values. No product check or assertion was removed to allow invalid runtime evidence.

After correcting the runtime fixture, both sequences progressed to their later assertions. The remaining failures were test assumptions that local `RecommendationHistory.id` equals the server comparison UUID. Production intentionally uses `permit.clientHistoryID` for local history and `permit.runID` for `batch.comparisonID` (RecommendationService.makeCompletedVNextHistory). The test now verifies both identities separately instead of comparing unrelated ID domains. Flow 3 also passes the real screen's `hasMeasurementEligibilityProof` argument obtained from the validated registration context. Existing expected measurement values, explicit user selection, new authorization/completion, and immutable prior results remain required.
