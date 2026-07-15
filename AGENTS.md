# FitMatch Agent Rules

## Goal
Maintain and improve FitMatch without changing existing UX or architecture unless explicitly requested.

## Response
- Keep responses concise.
- Do not explain unless asked.
- Implement first.
- Plans must be under 3 bullets.
- Never restate the request.

After implementation output only:
- Changed files
- Summary
- Remaining issues

## Coding
- Preserve architecture.
- Modify only related files.
- Avoid unnecessary refactoring.
- Reuse existing components.
- Keep diffs small.

## Git
- Never force push.
- Never rewrite history.
- Never commit or push unless explicitly requested.

## Work Style
- Think before editing.
- Search existing implementation first.
- Prefer fixing over rewriting.
- Stop if requirements are ambiguous.

## FitMatch Rules
- Preserve Reference Garment concept.
- Respect category/detailCategory structure.
- Preserve existing UX.

`FitMatch/Components/TabBarScrollVisibilityModifier.swift` is a protected file.

Do not modify, refactor, rename, move, simplify, format, or replace this file unless the user explicitly requests a change to the bottom-tab or top-header scroll visibility behavior and explicitly names this file.

This restriction includes:

- UI cleanup
- navigation changes
- tab-bar changes
- home/history/closet/recommend screen changes
- performance refactoring
- animation changes
- safe-area or padding changes
- general bug fixes
- code formatting
- dead-code cleanup

Do not modify any call site of the following modifiers unless explicitly requested:

- `hidesBottomTabBarOnScroll`
- `hidesBottomTabBarOnScroll(tab:topChrome:)`
- `tracksTabBarVisibilityOnScroll`
- `hidesTopChromeOnScroll`

Required behavior that must not regress:

- Scrolling down hides the top header and bottom tab bar.
- Bottom bounce must never be interpreted as an upward user scroll.
- Reaching the bottom keeps the header and tab bar hidden.
- Deceleration and bounce keep them hidden.
- They may reappear only after bounce has ended and the user starts a new upward drag.
- Reaching the top shows them.
- Navigation-detail and modal hidden reasons remain independent.
Before completing any task, run:

`git diff -- FitMatch/Components/TabBarScrollVisibilityModifier.swift`

Also verify protected modifier call sites were not changed:

`git diff | grep -E "hidesBottomTabBarOnScroll|tracksTabBarVisibilityOnScroll|hidesTopChromeOnScroll"`

If the user did not explicitly authorize these changes, both checks must return no relevant diff.

If a requested task appears to require modifying this protected behavior, stop and report the conflict instead of changing it.
