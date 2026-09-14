# FitMatch Agent Rules

## Goal

Maintain and improve FitMatch while preserving current product behavior, architecture boundaries, server contracts, and existing UX unless the user explicitly requests a change.

## Response

- Keep responses concise.
- Do not explain implementation details unless asked.
- Implement first when sufficiently specified.
- Plans must be no more than 3 bullets.
- Never restate the request.
- Never report work that was not actually performed.

For implementation tasks, finish with only: Changed files, Summary, Verification, Remaining issues.

Verification status must be PASS, FAIL, NOT RUN, or BLOCKED. Never describe skipped, interrupted, environment-blocked, or unexecuted tests/builds as passed.

## Coding and Work Style

- Preserve the existing architecture unless explicitly changed.
- Modify only related files; keep diffs small and coherent.
- Avoid opportunistic refactoring; reuse existing components, services, actions, coordinators, resolvers, DTOs, and domain models.
- Search existing implementation first. Fix the existing owner instead of duplicating logic or moving responsibilities between layers.
- Do not hide contract violations with fallback values or silently change UX.
- Preserve unrelated dirty working-tree changes.
- Think before editing. Stop only when ambiguity materially affects correctness, data integrity, architecture, authorization, irreversible behavior, or a consequential product decision.

## Sources of Authority

- `AGENTS.md`: stable operating, architecture-boundary, safety, Git, and verification rules.
- `Docs/AgentArchitectureMap.md`: detailed Swift ownership/navigation map; read only relevant sections before broad searches.
- `Docs/CodexSessionHandoff.md`: current implementation state, recent product decisions, Production changes, and unresolved issues.

At the start of every new session, read the current-state portion of `Docs/CodexSessionHandoff.md` completely before changing code. Before finishing meaningful work, update it with actual changes, decisions, tests/builds run, unverified areas, and remaining issues. Preserve history and mark superseded policy explicitly. Never describe prepared SQL as applied or unexecuted work as passed.

## Architecture and Product Authority

Retailer parsers provide retailer facts, not a second FitMatch policy engine. For server-authoritative flows, server/database results are authoritative; Swift transports, validates, adapts, persists, and presents them. Required missing, null, empty, unknown, malformed, or mismatched values must fail closed or enter explicit recovery. Never use local inference, first-item selection, visible labels, or defaults to replace required server authority.

FitMatch comparison groups and active group policy are the current comparison authority. Detailed garment classification is not a primary Closet-registration or readiness gate. Do not reintroduce superseded detailed-category gating or fabricate a confirmed group.

The old Reference Garment concept is deprecated as product/UX policy. Do not create automatic reference selection, require a permanent reference, restore its UX, or treat legacy `reference*` names as current policy. The current flow uses comparison groups and user-selectable Closet candidates.

Preserve original retailer facts and measurements separately from FitMatch canonical/group data. Never substitute product, variant, size, local, historical, or another Closet identity for the exact server/user-selected identity.

- ZARA: keep `internalProductID` and `catentryID` separate; never assume they are equal.
- UNIQLO: preserve official category/breadcrumb and all meaningful collection/category/length facts.
- MUSINSA: preserve official source category paths/codes and actual measurements; do not use product-name heuristics as canonical group authority without explicit approval.

## Persistence and Database Safety

Do not report user-visible success before authoritative persistence succeeds. Local cache mutation is not server success; retries must preserve identity and idempotency.

Before any Supabase/database write, migration, destructive SQL, RPC mutation, or schema operation, identify the target environment, classify it, and confirm authorization. Production mutation is opt-in. Read-only inspection, SQL analysis, migration proposals, verification-query preparation, and positively identified local/dev validation are allowed by default. Never delete/truncate, alter schema, impersonate users, bypass RLS/authentication, or write Production without explicit authorization. After authorized Production mutations, perform read-only postflight and report exactly what was applied.

Never commit credentials, tokens, keys, passwords, or secrets. Redact them from output and use existing environment/secret mechanisms.

## Git and Working Tree Safety

At the start of editing, inspect `git status --short --branch`. Never force-push, rewrite history, commit, push, merge, switch branches, pull/rebase, reset, or stash unless required and authorized. Inspect overlapping diffs before editing and preserve unrelated changes.

## Protected Scroll Visibility Behavior

`FitMatch/Components/TabBarScrollVisibilityModifier.swift` and its modifier call sites are protected unless the user explicitly requests a change to bottom-tab/top-header scroll visibility and names the protected behavior/file. Do not modify, refactor, rename, move, format, or incidentally change them for unrelated work.

Protected modifiers: `hidesBottomTabBarOnScroll`, `hidesBottomTabBarOnScroll(tab:topChrome:)`, `tracksTabBarVisibilityOnScroll`, `hidesTopChromeOnScroll`.

Required behavior: scrolling down hides header and tab bar; bottom bounce, deceleration, and reaching the bottom keep them hidden; they reappear only after bounce ends and a new upward drag; reaching the top shows them; navigation-detail and modal hidden reasons remain independent.

Before completing any task, run:

```bash
git diff -- FitMatch/Components/TabBarScrollVisibilityModifier.swift
if git diff | grep -qE 'hidesBottomTabBarOnScroll|tracksTabBarVisibilityOnScroll|hidesTopChromeOnScroll'; then
  echo 'PROTECTED_SCROLL_DIFF_FOUND'
  exit 1
else
  echo 'PROTECTED_SCROLL_OK'
fi
```

If unauthorized protected behavior changes are required, stop and report the conflict.

## Verification and Review

Use the narrowest meaningful verification. For Swift changes, run focused tests/builds and `git diff --check` when practical. For server changes, validate DTO/contract assumptions and use read-only Production postflight. Do not invent schemes, destinations, environments, or test targets. Report PASS, FAIL, NOT RUN, or BLOCKED accurately.

Before completion, inspect the final diff; confirm only related files changed, no hidden fallback was introduced, server authority and exact identities remain intact, comparison-group policy was not replaced by legacy behavior, and protected-scroll checks pass.

## Decision Collaboration

For consequential product, UX, architecture, data, database, or release tradeoffs, evaluate the strongest supporting and opposing cases, distinguish fact from inference and recommendation, and choose the option best serving correctness, UX, maintainability, and release quality. Do not invent product or architecture decisions.

## Rule Maintenance

Keep this file limited to stable operating rules and high-level navigation. Put temporary blockers, current DB state, incidents, one-off test results, and pending evidence in `Docs/CodexSessionHandoff.md`. Keep detailed ownership/navigation in `Docs/AgentArchitectureMap.md`. Update those sources when stable architecture or product rules change.
