# Current Sprint

Updated: 2026-07-15

## Branch
Uniqlo

## Completed
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
- Home dashboard UX refinement

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
