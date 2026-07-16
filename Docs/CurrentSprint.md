# Current Sprint

Updated: 2026-07-16

## Branch
feature/measurement-standardization

## Completed
- Added Musinsa standard-size-chart fallback for products without actual measurements, keeping body chest circumference separate from garment measurements and preserving the existing actual-measurement path.
- Musinsa and Uniqlo now share canonical upper-body and verified lower-body width measurement codes while retaining distinct sleeve, pants-outseam, pants-inseam, and skirt-length paths.
- Measurement migration v6 upgrades stored UserFit/ProductSize upper mappings and verified lower mappings; Uniqlo waist/hip circumferences are halved exactly once while source metadata and raw values remain intact.
- History detail re-comparison now replaces the selected history route with the newly persisted history ID, so dismissing the garment picker keeps the recalculated result detail on screen instead of popping to the list.
- Successful reference-garment changes from RecommendationResultView now replace the persisted same-product history through the existing graph-reuse store; insufficient evidence or save failure keeps the previous screen and record intact.
- Consolidated recommendation and product-parser diagnostics behind a DEBUG-only Korean logger; per-size score output is now one line and duplicated parser metadata logs are removed from Release builds.
- Recommendation result reference changes now dismiss only after a successful recalculation; insufficient measurement evidence keeps the picker open with comparable/excluded items and an optional reference-only comparison.
- Compare flow sheets now receive the root TabBarVisibilityController, preventing RecommendationResultView environment-object crashes; DEBUG logs identify Korean screen/action/status transitions.
- Selecting Uniqlo or Musinsa in new Closet registration now defaults measurement input to that platform's size chart; direct registration still defaults to FitMatch measurement.
- Simplified new Closet registration to Uniqlo official store, Musinsa, or direct registration with source-specific measurement choices.
- Direct registration now skips measurement-source selection and stores FitMatch-standard measurement records; legacy `otherSizeChart` remains editable without conversion.
- Recompare persistence now reuses stored Product/ProductSize objects by identity or normalized size name and removes unreferenced duplicate product graphs.
- Added 12-second request timeouts to Uniqlo parsing, matching the bounded Musinsa recompare requests.
- Musinsa recompare now bypasses redirect-page loading for canonical product URLs and bounds all Musinsa requests with a 12-second timeout.
- Recompare history saving now reuses the persisted deterministic ProductSize and Product graph instead of inserting duplicate SwiftData identities.
- Updated the Musinsa launch shortcut to the current OneLink in Home and Compare flow.
- Fixed the Closet edit measurement-label type inference and display-kind conversion build errors.
- Restored file-local size/difference formatting used by Compare flow and removed cross-file `fileprivate` dependencies from Closet validation.
- Added a four-page first-launch onboarding shown after Splash, persisted with AppStorage and hidden on later launches.
- Added a settings replay path that presents onboarding without changing first-launch completion state.
- Replaced the simple usage steps with an eleven-topic, single-expanded-item accordion matched to current FitMatch behavior.
- Restored the MY tab root to My Closet; settings remains accessible from the existing top-header account navigation.
- Replaced the mock signed-in profile header with FitMatch introductory copy.
- Marked unavailable settings rows as `준비 중` without navigation affordances and added a five-step FitMatch usage guide.
- Added the versioned, bundled FitMatch taxonomy JSON and provider abstraction with controlled fallback and legacy Korean aliases.
- Added optional stable classification and normalized product-type codes without removing persisted Korean snapshots or source-category metadata.
- Switched Closet add classification selectors to provider-backed gender/category/detail options and atomic length/form details.
- Added centralized verified knit/sweater and T-shirt source mappings, gender-aware automatic matching, and normalized-type-aware reference uniqueness.
- Added taxonomy contract/DB documentation and focused validation, migration, matching, reference, and fallback tests.
- Source category UI now uses only `sourceCategoryPath`; internal category fallback was removed.
- Closet comparison flow is `대분류 > 세부 카테고리 > 옷` with no source filter.
- Candidates use `UserFit.category/detailCategory` across all shops and brands.
- Resolved/history-matched categories are preselected.
- Reference garments are prioritized; source is display-only metadata.
- Added root `AGENTS.md`.
- iOS Simulator build and `git diff --check` passed.
- Replaced conditional top-header rendering with `CollapsibleTopChrome` in Home, Recommend, History, and My Closet while preserving the existing scroll modifiers.
- Moved only `FitMatchNavigationHeader` into root-level `CollapsibleTopChrome` containers on all four screens so it can reappear while content remains scrolled.
- Kept History and My Closet filter controls inside their `ScrollView` content; filters no longer collapse with the app header.
- Kept `hidesBottomTabBarOnScroll(tab:topChrome:)` attached to each actual `ScrollView`.
- Added persistent source-category-to-FitMatch mapping reuse with `sourceCategoryDepth1...4` as the primary key and `sourceCategoryPath` only as fallback.
- Compare flow now skips category confirmation for a single stored/history mapping or a valid parser inference.
- Unmapped categories show a dedicated FitMatch mapping screen; confirmed mappings are saved for subsequent products.
- Reset unresolved picker values so the first picker always uses `ClothingCategory` and the second uses `ClosetDetailCategory`.
- Updated the shared root chrome scroll handler so any meaningful upward scroll immediately restores both the app header and bottom tab bar.
- Reverified that only `FitMatchNavigationHeader` is collapsible and History/My Closet filters remain ordinary scroll content.
- Removed the per-event 3pt cutoff from root chrome tracking so slow, small scroll deltas accumulate and trigger header/tab hiding.
- Simplified root chrome tracking to hide immediately on positive scroll delta and restore immediately on negative delta; bottom-boundary events are no longer discarded before hiding.
- Replaced root chrome snapshot/clamping/boundary detection with direct `ScrollGeometry.contentOffset.y` tracking.
- Removed synchronous animated header/tab mutations from the geometry callback after confirming they changed the parent height and fed layout-generated offsets back into direction detection.
- Added a single root chrome coordinator that coalesces visibility decisions onto the next main run loop, ignores geometry during application, and resets the raw-offset baseline afterward.
- Bottom overscroll rebound is ignored instead of being treated as an upward user scroll.
- Root chrome direction tracking now stores `previousMaxOffset`; geometry events with a max-offset change over 1pt only refresh the baseline and never change visibility.
- Stable-layout direction changes require at least 2pt raw-offset movement, and both raw/max baselines reset after visibility application.
- Removed duplicate screen-level header animations.
- Removed `CollapsibleTopChrome` animation entirely so header height changes immediately and cannot produce per-frame `maxOffset` changes near the bottom.
- Replaced the no-same-category comparison UX with a dedicated `같은 분류의 옷이 없어요` screen and compare-cancel action.
- Removed category/detail pickers from the similar-garment flow.
- Similar garments now show only existing `UserFit` items, grouped by inferred exact classification, same main category, and remaining closet items.
- Selected similar garments continue through the existing temporary reference comparison path.
- Rebuilt Home as a personal dashboard with a wordmark-only header, conditional clipboard and latest-comparison cards, reference-garment readiness, and a reusable guide card.
- Home reference-garment actions now open My Closet, while clipboard comparison and result-detail navigation reuse the existing flows.
- Closet editing now supports changing internal category and detail category for both manual and URL-imported garments.
- URL-imported garment edits keep parsed product fields and source measurements read-only while saving user-selected closet classification.
- Moving a reference garment into a classification with an existing reference now requires confirmation before replacing it.
- My Closet list cards now show the source platform with the parsed original category path, without the old `출처:` label or internal-category fallback.
- Added a shared comparison-profile matcher derived from source category depth/path, product name, internal detail category, and valid measurements.
- Automatic comparison now requires matching major category, known garment family, known compatible length type, and at least two common core measurements.
- Reference garments now rank first only among compatible candidates; brand, shopping mall, and prior manual selections do not influence automatic compatibility.
- Same-family length conflicts and unknown profiles now require manual selection, limited to the same major category with same-family items first.
- Manual sleeve/pants-length mismatches exclude the incompatible measurement, lower confidence, and add a concise result explanation.
- Added focused matcher tests for sleeve/pants conflicts, compatible long sleeves, unknown length, selection isolation, and manual exclusion.
- Standardized all confirmed Closet-add action buttons to `내 옷장에 추가` while preserving navigation, save behavior, and distinct method-selection labels.

## Current Task
- Standardize Closet source UX and repeated-comparison persistence

## Remaining Bugs
- Compare's source-category fallback still exposes compatibility enum bindings; it should adopt stable-code state when the compare ViewModel persistence contract is migrated.
- Existing legacy garment-family details such as 셔츠/니트/후드 cannot be safely converted to the new length-only detail without source/name evidence, so their snapshots remain unresolved rather than being guessed.
- Manual verification of scroll jitter/crash fix
- Comparison-profile tests are compiled but simulator execution is blocked while the test runner waits for simulator workers to materialize.
- Discount UI

## Rules
- Do not commit
- Do not push
- Follow `AGENTS.md`.

## Working Tree
- Modified: `FitMatchCard.swift` and this sprint document.
- No staged or untracked files.
- No untracked files.
- No commit or push performed in the latest task.

## Verification
- Musinsa standard-chart detection, option normalization, fallback/mixed comparison, and unavailable-result regression tests compile with the generic iOS device test bundle; no simulator was launched.
- Home card polish differentiates Closet and recent-comparison purposes with restrained Material surfaces, tightens carousel density, and preserves result-first typography and existing actions.
- Cross-platform measurement tests cover common upper measurements, sleeve exclusion, lower width conversion/comparison, outseam/inseam separation, raglan preservation, and idempotent v6 migration; app and test bundles compile for generic iOS devices.
- History-detail route retention passed the generic iOS device Debug build; the picker dismissal remains local to RecommendationResultView and protected scroll files/call sites are unchanged.
- Last-reference persistence tests cover latest UserFit/recommended-size replacement, single-history retention, stable ProductSize/measurement-record identities, and insufficient-evidence record preservation; app and test bundles compile for generic iOS devices.
- Performance-diagnostic logging passed generic iOS device Debug and Release builds; Release binary inspection found no DEBUG logger or detailed recommendation-score strings.
- Recommendation result reference-change regression tests cover compatible success and insufficient-evidence outcomes; the generic iOS device Debug build succeeded without launching a simulator.
- Compare sheet environment injection and Korean DEBUG transition logs passed the generic iOS device Debug build and protected-scroll diff checks.
- Closet source UX and repeated-comparison changes passed the generic iOS Simulator Debug build, test-target build, and `git diff --check`; selected simulator tests were stopped after the test runner did not return results.
- Musinsa canonical-URL fast-path and request timeout changes passed the generic iOS Simulator Debug build and `git diff --check`.
- Recompare deterministic-size regression coverage was added; the app Debug build succeeded, while test execution is blocked by a pre-existing Swift Testing macro compile error in `fitmatchMeasuredEntryCreatesComparableStandardRecords`.
- Generic iOS Simulator Debug build succeeded after resolving the measurement-label and file-private helper compile errors; `git diff --check` passed.
- Closet product saving now reuses an already persisted deterministic `ProductSize` and its source `Product`, avoiding SwiftData unique-ID conflicts when another size of the same product is added.
- Home `기준 옷` now toggles immediately like the favorite action, uses a red selected state, and asks only when replacing a conflicting reference garment; the generic iOS Simulator Debug build and `git diff --check` passed.
- Home recent Closet cards use the compact `기준 옷` label while preserving state-specific icons and accessibility actions; the generic iOS Simulator Debug build and `git diff --check` passed.
- Home recent Closet cards replace the passive status footer with a safe reference-garment action and an edit action using the existing detail editor; the generic iOS Simulator Debug build and `git diff --check` passed.
- Home Closet status now shows up to five recently registered garments using the same lazy horizontal 204pt card pattern as recent comparisons; the generic iOS Simulator Debug build and `git diff --check` passed.
- Restored the recent comparison card width to 204pt while retaining lazy horizontal scrolling and the current card UI; the generic iOS Simulator Debug build and `git diff --check` passed.
- Recent comparison uses a lazy horizontal list with viewport-relative cards, leaving roughly one-sixth of the next card visible while preserving the existing card UI; the generic iOS Simulator Debug build and `git diff --check` passed.
- Recent comparison cards now use a softer result container and balanced bottom favorite/recompare actions while preserving result-first navigation; the generic iOS Simulator Debug build and `git diff --check` passed.
- Home final polish improves result hierarchy, card density, empty-state affordance, and closet stat wording without changing navigation or section structure; the generic iOS Simulator Debug build and `git diff --check` passed.
- Home dashboard now prioritizes comparison-ready closet counts, a full-card recent-comparison empty CTA, and result-first recent cards; the generic iOS Simulator Debug build and `git diff --check` passed.
- First-launch onboarding, replay presentation, and accordion usage guide passed the generic iOS Simulator build and `git diff --check`.
- MY settings navigation and usage guide passed the generic iOS Simulator build and `git diff --check`.
- Protected scroll modifier call sites have no added or removed lines from this task.
- Data-driven taxonomy app build and test-bundle compilation passed for the generic iOS Simulator destination.
- Taxonomy, legacy mapping, reference uniqueness, and matcher tests executed successfully; Xcode's test runner stalled only while finalizing simulator workers after reporting passes.
- Bundled `FitMatchTaxonomy.json` was verified inside the built app, and `git diff --check` passed.
- `xcodebuild` passed for the generic iOS Simulator destination.
- `git diff --check` passed.
- Search confirmed all four target screens use root-level `CollapsibleTopChrome`, while History/My Closet filters remain in scroll content.
- Category mapping persistence and automatic-skip changes passed the same build and diff checks.
- Shared top/bottom chrome restoration change passed `xcodebuild` and `git diff --check`.
- No-same-category and similar-garment selection changes passed the same build and diff checks.
- Reentrant chrome fix passed `xcodebuild` and `git diff --check`; no AttributeGraph or SwiftUI recursive-update report was found in local logs.
- Simulator boot was attempted on iPhone 17 Pro but remained blocked at `Waiting on System App`, so automated launch/gesture reproduction could not complete.
- `5fdff00` was verified as the direct ancestor of current local/remote `Uniqlo` HEAD `8302869` before applying the max-offset stabilization patch.
- Max-offset stabilization passed `xcodebuild` and `git diff --check`.
- Immediate-height `CollapsibleTopChrome` change passed `xcodebuild` and `git diff --check`.
- Home dashboard composition passed the iOS Simulator Debug build and `git diff --check`.
- Closet category editing passed the iOS Simulator Debug build and `git diff --check`.
- My Closet source-category card layout passed the iOS Simulator Debug build and `git diff --check`.
- Comparison-profile matcher app build passed for the generic iOS Simulator destination; focused test bundle compiled successfully.
- Closet-add button label standardization passed the generic iOS Simulator build and `git diff --check`.

## Next Task
Manually verify slow scroll, flick/inertia, top/bottom bounce, rapid direction changes, list/grid switches, and repeated tab changes without freezes or crashes. Then verify source category auto-mapping reuse.
