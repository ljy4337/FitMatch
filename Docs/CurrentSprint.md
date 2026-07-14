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

## Current Task
- Compare Default
- Clipboard Refresh

## Remaining Bugs
- Scroll jitter
- Discount UI

## Rules
- Do not commit
- Do not push
- Follow `AGENTS.md`.

## Working Tree
- Modified: `HomeView.swift`, `RecommendView.swift`, `MyClosetView.swift`, `RecommendationHistoryView.swift`, and this sprint document.
- No untracked files.
- No commit or push performed in the latest task.

## Verification
- `xcodebuild` passed for the generic iOS Simulator destination.
- `git diff --check` passed.
- Search confirmed all four target screens use root-level `CollapsibleTopChrome`, while History/My Closet filters remain in scroll content.
- Category mapping persistence and automatic-skip changes passed the same build and diff checks.
- Shared top/bottom chrome restoration change passed `xcodebuild` and `git diff --check`.

## Next Task
Manually verify source category auto-mapping reuse, then top chrome collapse and remaining scroll jitter.
