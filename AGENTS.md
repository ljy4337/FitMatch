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

## Cumulative Handoff

- At the start of every new session, read `Docs/CodexSessionHandoff.md` completely before changing code.
- `Docs/CodexSessionHandoff.md` is the single current cumulative handoff; dated handoff files are historical detail only.
- Before finishing meaningful work, update the cumulative handoff with production changes, product/UX decisions, tests actually run, unverified areas, and remaining issues.
- Preserve prior history. When a policy changes, mark the old state as superseded and record the new current state instead of silently deleting context.
- Never describe skipped, interrupted, environment-blocked, or unexecuted tests as passed.

## Decision Collaboration
- Do not agree with the user reflexively or mirror the user's latest opinion.
- For product, UX, architecture, and testing decisions, present both the strongest supporting case and the strongest opposing case when a real tradeoff exists.
- Clearly say no when a proposal would worsen UX, correctness, safety, maintainability, or FitMatch's product principles, and explain the concrete reason.
- Distinguish verified facts, inference, and preference instead of presenting them as equally certain.
- Recommend the best synthesized option after evaluating tradeoffs; optimize for the product outcome, not agreement.
- If the user's revised idea is better, say why it is better. If it is not, defend the stronger alternative with evidence.

## Budgeted Work Proposals

- When a request has a usage, time, cost, or test-scope constraint, do not start with the cheapest compromise.
- Present estimates in this mandatory order before recommending a plan:
  1. **Sufficient budget**: the expected usage/time needed to complete the user's stated goal with the required verification scope.
  2. **Safe budget**: sufficient budget plus realistic retry, collection failure, and regression margin.
  3. **User-budget option**: what can be completed within the user's proposed cap.
  4. **Explicit tradeoff**: the exact coverage, evidence, or risk that the lower-budget option gives up.
- State whether each estimate is measured evidence, an inference from prior runs, or a planning assumption.
- For budgeted testing, give expected output and product-quality effect separately from execution cost. Do not imply that a partial sample validates the complete stated goal.
- If the user asks for a compromise, first state the full-goal estimate; only then offer the compromise and recommend one.

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
