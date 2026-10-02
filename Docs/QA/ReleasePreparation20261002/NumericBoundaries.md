# Numeric boundary characterization

Status: **CHARACTERIZATION**. Formula, rounding and tie-break product approval remain **UNRESOLVED**. This additive sheet leaves the frozen `oracle.json`, `policy-expectations.json` and their existing locks unchanged. The old expectation file's “tests avoid half-boundary ambiguity” describes the original oracle; this new sheet explicitly tests the observed half behavior without resolving policy approval.

Five additional methods in `FitMatchReleasePreparationTests` call the real decoder → adapter → scoring engine → completion-payload path. Inputs and literal hand-calculated answers are recorded in [oracle-boundaries-v1.json](oracle-boundaries-v1.json). No engine output generated expected values.

| Added method | Literal expectation | Regression detected |
|---|---|---|
| `perItemHalfRoundsBeforeWeightedMean` | 97.5→98, 92.5→93; 335.5/3.5→96 | Rounding only the final mean yields 95; ties-to-even changes the second item to 92. |
| `weightedMeanHalfRoundsAfterIntegerItemScores` | (100×2+80+90)/4=92.5→93 | Final truncation or ties-to-even yields 92. |
| `scoreEndpointsClampBelowZeroAndPreserveLargeDeltaEvidence` | Δ0/20/21→100/0/0 | Missing lower clamp yields −5; replacing evidence with a clamped delta destroys the original 21. |
| `equalScoreUsesWeightedDeltaBeforeExactUUID` | Both score99; UUID2 wins with .75/3.5 rather than 1/3.5 | UUID-first/input-order/unweighted-delta ranking chooses UUID1. Both input orders are checked. |
| `negativeAbsoluteEvidenceCannotBecomeAnAboveHundredScore` | Exact `invalidEvidence(UUID1)` error | Invalid negative absolute difference must fail before becoming a clamped score. |

Selector prefix: `FitMatchTests/FitMatchReleasePreparationTests/`. Reuse the existing `identicalScoreAndDeltaUseExactUUIDTieBreakIndependentOfInputOrder` for the final exact-UUID tie stage and `inconsistentSignedDifferenceCannotProduceAnOracleResult` for signed-difference mismatch.

All half-boundary inputs are integer or binary-exact `.5` values. Completion checks preserve signed versus absolute differences, the original targets, authorized evidence order and exact size IDs even when ranking changes. Every candidate deliberately has the same visible label `M`. These are synthetic server-approved snapshots, not new authority or real persisted comparisons.

The maximum reachable score for valid nonnegative absolute evidence is 100 at Δ0. This checks that endpoint; it does **not** claim the upper-clamp branch can be reached with valid evidence. Negative absolute evidence is separately rejected.

Verification at authoring: **NOT RUN** for Xcode; the parent run records compilation/execution separately. No DB/Auth request, production-code change or policy edit was made.

Parent verification: **PASS** in `/tmp/FitMatchResume30Focused.xcresult`: all nine methods in this suite passed, including the five added boundaries. The combined command exited65 solely because a different mounted-view test had an incorrect fixture identity assertion. No product-policy approval is implied.
