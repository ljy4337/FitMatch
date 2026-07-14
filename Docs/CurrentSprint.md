# Current Sprint

Updated: 2026-07-14

## Branch
Uniqlo

## Completed
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
- Removed duplicate screen-level header animations; `CollapsibleTopChrome` remains the sole header animation.
- Replaced the no-same-category comparison UX with a dedicated `같은 분류의 옷이 없어요` screen and compare-cancel action.
- Removed category/detail pickers from the similar-garment flow.
- Similar garments now show only existing `UserFit` items, grouped by inferred exact classification, same main category, and remaining closet items.
- Selected similar garments continue through the existing temporary reference comparison path.

## Current Task
- Scroll chrome crash/reentry verification
- Compare Default
- Clipboard Refresh

## Remaining Bugs
- Manual verification of scroll jitter/crash fix
- Discount UI

## Rules
- Do not commit
- Do not push
- Follow `AGENTS.md`.

## Working Tree
- Modified: `TabBarScrollVisibilityModifier.swift` and this sprint document.
- No staged or untracked files.
- No untracked files.
- No commit or push performed in the latest task.

## Verification
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

## Next Task
Manually verify slow scroll, flick/inertia, top/bottom bounce, rapid direction changes, list/grid switches, and repeated tab changes without freezes or crashes. Then verify source category auto-mapping reuse.
