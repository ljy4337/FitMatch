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
- Modified: comparison/source-category views plus Home, Recommend, History, and My Closet header views.
- Untracked: `AGENTS.md`, `Docs/CurrentSprint.md`.

## Next Task
Manually verify top chrome collapse and remaining scroll jitter on Home, Recommend, History, and My Closet.
