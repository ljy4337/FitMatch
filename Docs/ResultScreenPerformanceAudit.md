## 2026-09-15 Follow-up implementation / BUILD PASS, 14 TESTS PASS

User provided physical-device DEBUG logs: first result onAppear 96.0 ms, next main run loop 847.5 ms; one scroll summary 29 long / 2 severe / worst 52.7 ms, another 51 long / 4 severe / worst 84.2 ms. These demonstrate delays, not a Time Profiler attribution. CoreData WAL messages alone do not prove checkpointing caused the delays.

- Added a single-entry view-lifetime memo around existing supplemental MeasurementComparisonEngine.compare. Key captures exact size/reference IDs, category, every record scalar and resolved source identity; same-ID edits invalidate it. Original engine result and authorized-kind filtering remain unchanged.
- TemporarySizeAnalysis now constructs its immutable calculation snapshot once. Result reliability consumes the already decoded persisted snapshot; server-approved scoring/reliability values remain unchanged.
- DEBUG scroll monitor retains counters/start/summary but per-frame/geometry/phase console output requires FITMATCH_VERBOSE_SCROLL_DIAGNOSTICS=1. No protected scroll modifier or call site changed. No detent/layout/navigation or image changes.
- Replaced misleading missing-reference local detail/family diagnostics with actual server plan block reasons. This changes diagnostics only.
- ZARA 549678665 failed because zone-name-chest had a verified dresses alias but no tops alias. Actual session A canonical results had no chest_width and zero common policy measurements with either owned long-sleeve/sweatshirt. Applied guarded zara_top_chest_alias_Apply.sql to owner-designated development-use project hnkplvyegonlhumlejst: added exactly one tops alias to the existing verified chest-width definition. No authorization/scoring/group function or user/raw measurement row was edited by this repair. Read-only postflight: four sizes resolve 50/53/56/59 cm chest_width with zero semantic conflicts; all eight size/Closet pairs now have one common canonical chest metric. Existing dresses alias retained. Sleeve mapping remains unresolved; no guessed equivalence or policy bypass introduced.
- Authenticated candidate/begin/complete execution after this repair and before/after physical-device frame profiling are NOT RUN. Database canonical/evidence postflight is not a claim of authenticated end-to-end completion.

Validation: app/test build PASS; 14 tests / 3 suites PASS (4 new presentation-cache/snapshot tests, existing measurement-policy and permit-sequencing suites). Test tool response timed out at 300 seconds, but the underlying build/test continued; final log and xcresult confirm TEST EXECUTE SUCCEEDED. Result bundle: /Users/jinyoung/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-26291420f5b2/result-bundles/test_sim_2026-09-15T12-17-42-877Z_pid32595_7406dd7d.xcresult. Physical performance delta remains NOT RUN.

---

# Result screen performance audit — 2026-09-15

## Scope and evidence

Code-first inspection of current local connectDB, baseline ae69b30 plus existing uncommitted diagnostics/navigation changes. No app code, server, protected scroll behavior or existing dirty work changed. No device/simulator frame trace captured in this audit. Findings below are confirmed call paths, not measured causes or improvement claims.

Both 비교 결과 and 개별 비교 결과 use RecommendationResultView; the title depends on onShowComparisonList. 다른 사이즈 비교 is its alternativeSizeComparisonSheet, not a separate screen file.

## Prioritized hypotheses

1. **Render-time comparison work** — RecommendationResultView.swift:853 builds reportMeasurementPresentations and calls supplementalMeasurementItems (:905). For matching retailer sources in actual-measurement mode, that property synchronously calls MeasurementComparisonEngine.compare (:917). The engine loops through policy kinds, filters product/reference records and matches pairs (MeasurementComparisonEngine.swift:376). This happens when the presentation property is evaluated, not solely when the user requests a new comparison. It is the first CPU cost to measure during result rendering/re-evaluation. It does not run for every product and is not proven to run on every scroll tick. Preserve these supplemental facts and their exclusion from authorized scoring if moving their calculation.
2. **Sheet transition overlaps preparation** — presentAlternativeSizeComparison (:1034) presents the sheet, then schedules prepareAlternativeSizeAnalyses (:963) on MainActor. The task validates the existing batch, traverses sizes and prepares caches, then publishes them. Task.yield allows scheduling but does not move work off MainActor. The sheet can initially render unavailable summaries and rebuild after preparation. Existing cached server-approved analyses are reused; this is not a fresh network comparison for each row. Measure preparation and layout separately before changing loading UX.
3. **Repeated decoding and broad dependencies** — init (:45) decodes comparisonData and sorts product sizes whenever the parent reconstructs this view. comparisonReliability (:1396) still calls serverApprovedVNextReliability, whose calculationSnapshot getter JSON-decodes the envelope (RecommendationHistory.swift:180). The view also queries the entire Closet and scans it for the selected reference. These are potential repeated costs on invalidation; actual frequency has not been measured. Any presentation snapshot must invalidate when exact result/reference/size inputs change.
4. **Layout/render cost, lower confidence** — result cards contain shadows; alternative cards use nested LazyVGrid/text sizing inside LazyVStack and a medium/large sheet. Profiling must separate layout/compositing from CPU work. Do not remove appearance or alter detents based solely on this hypothesis.

## Existing protections / findings that narrow the search

- Result and alternative-size lists already use LazyVStack; adding it is not a fix.
- Alternative sizes already have a cache and exact server-size identity mapping. Preserve group/fingerprint and identity authorization.
- ProductThumbnailView already uses ImageIO thumbnail downsampling. No evidence here that full-size main-thread image decoding is the principal cause.
- DEBUG ScrollPerformanceDiagnostics adds CADisplayLink/geometry sampling and console output; it may perturb measurements. Its existing result monitor starts after 350 ms and does not specifically instrument the alternative sheet. Existing frame thresholds (24/40 ms) are not sufficient proof of smoothness on a 120 Hz device, and run-loop navigation timestamps are not presented-frame timings.
- No network call was found in the inspected body/alternative cache preparation path. This does not exclude preceding sync work or other concurrent tasks.

## Verification plan

- Reproduce the same result with fixed data: enter result, scroll down/up, open alternative sizes, scroll/select/apply. Capture result entry and sheet entry separately, including first and warm openings.
- Use physical iPhone performance capture with build configuration recorded; compare DEBUG diagnostics enabled/disabled and an optimized build. Inspect main-thread stacks, SwiftUI updates/layout and frame hitches. Never call simulator timings physical-device proof.
- First measure supplemental comparison, envelope decoding and MainActor preparation. If significant, reuse a correctly invalidated display projection and existing approved batch; preserve all displayed facts, IDs, scores and protected scroll behavior. Then repeat the same capture to verify improvement.

Status: static call-path review PASS; runtime reproduction/profiling NOT RUN; principal cause UNCONFIRMED. User confirmed physical iPhone launched from the app icon. Debug/Release build configuration is unknown; icon launch does not establish optimized compilation or disable DEBUG instrumentation.
