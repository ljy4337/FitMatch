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

## Current Task
- Header/Filter Scroll
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
- Modified: four comparison/source-category view files.
- Untracked: `AGENTS.md`, `Docs/CurrentSprint.md`.

## Next Task
Header/filter scroll behavior.
