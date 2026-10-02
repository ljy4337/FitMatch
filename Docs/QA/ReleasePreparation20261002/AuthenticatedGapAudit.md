# Authenticated QA recovery gap — 2026-10-02

## Current preparation update — Resume20

The test harness now retires an independently verified prior comparison **before** another completion advances the same product head. Exact run ownership, reference list + exact read, receipt and fresh tombstone are required. Offline RED→GREEN was executed; see [CleanupPreparation20.md](CleanupPreparation20.md). Product/DB contracts were not changed. This prevents the ordinary test sequence from creating the described gap; it does not repair already superseded ledgers or prove real interrupted DB recovery. The historical audit below is preserved.

## Scope and status

**BLOCKED — interrupted A–H recovery:** the existing cleanup contract cannot prove ownership of a superseded completed comparison using its current read path. This agent established the mismatch from repository Swift and SQL definitions. The parent then reported a read-only MCP check of development `hnkplvyegonlhumlejst`: `ACTIVE_HEALTHY`; deployed `comparison_history()` has the completed-row/current-head gate; deployed `comparison_history_sync()` requires completed rows with nonnull `deleted_at` for tombstones; the inspected public comparison-read function names include only history and history-sync. Parent-held MCP evidence corroborates the deployed read-contract mismatch. Neither check executed the authenticated recovery workflow. No Auth, application-data, schema, policy or product-code change was performed for this audit.

The added offline regression is `FitMatchReleaseAuthenticatedLedgerSafetyTests.supersededCompletedComparisonWithoutTombstoneBlocksRestoredCleanup`. It models the documented SQL projection and verifies the existing guard remains closed. Execution evidence belongs to the parent focused-test report; adding this test does not establish live DB recovery.

## Concrete trigger and source evidence

1. `ReleaseAuthenticatedRun.exercise` completes a target in D, then completes the same target again in B and G (`FitMatchReleaseAuthenticatedSupport.swift:699,718,723`). Its ledger retains all generated comparison IDs.
2. `fitmatch_vnext.comparison_history()` includes completed rows only when they are the current `comparison_result_heads` entry (`supabase/migrations/20260928160000_latest_comparison_result_per_product.sql:105–121`). The former completed row is omitted without being deleted.
3. `comparison_history_sync()` delegates its active list to that function. Its tombstones require `result_status='COMPLETED'` and `deleted_at is not null` (`supabase/migrations/20260924102000_comparison_history_tombstone_sync.sql:44–60`). Supersession alone therefore supplies neither an active-row proof nor a tombstone for the older ID.
4. After interruption before the original run's cleanup, `ReleaseAuthenticatedRun.resumeCleanup` validates every comparison against those two collections before any mutation (`FitMatchReleaseAuthenticatedSupport.swift:313–346`). `ReleaseAuthLedgerSafety.validateComparison` rejects the missing older proof with `cleanup_comparison_missing_or_unverified_reference` (`FitMatchReleaseAuthenticatedLedgerSafety.swift:96–108`). Valid proof for the newer same-target comparison cannot prove the older ID.

This is a recovery limitation, not evidence that normal uninterrupted cleanup fails. The original run retains its live ledger and hides its exact completed IDs before removing remaining Closet rows (`FitMatchReleaseAuthenticatedSupport.swift:760–800`). The resumed path treats the supplied ledger as untrusted and deliberately requires independent online proof.

## Existing read paths and safe boundary

No exact-ID read RPC for superseded completed comparisons was found in the inspected repository definitions. `FitMatchSupabaseDomainClient` exposes the active history and sync RPCs (`FitMatchSupabaseProductResolver.swift:2472–2498`). App alternative-size recovery also filters this same sync response (`FitMatchComparisonSyncCoordinator.swift:195–208`); it does not provide another persisted-row lookup.

The source migration declares `comparisons_select_own` (`20260829013456_vnext_runtime_rls_grants.sql:32–34`), but this audit did not establish current Data API schema exposure or direct-table SELECT grants. A normal-user direct-table read must not be assumed available from that policy alone.

Keep recovery **BLOCKED** for this condition. Do not treat absence as hidden, trust a saved ID as ownership proof, substitute the current result, use administrator authority for user isolation evidence, or weaken RLS. A future repair requires a positively verified normal-user read path that proves the exact stored comparison tuple, or a separately reviewed change to test sequencing. This audit adds neither.

## Remaining execution prerequisites

- Manual RPC/Swift CRUD can run after two distinct confirmed disposable development accounts have fresh normal sessions and both active Closet/History lists are empty. `release_qa_session.py` supports normal password login for existing accounts and verifies independently known UUIDs; the public URL/key alone cannot establish a session.
- Full A–H additionally requires the independently verified exact product/variant/size/observation manifest and expected raw/canonical counts described in `AuthenticatedCoverage.md`. Readiness must be checked through the current normal-user runtime; raw catalog classification alone is insufficient.
- With email confirmation required, normal signup still needs controlled confirmation delivery. Any separately authorized administrator account provisioning is environment preparation only; actual tests must authenticate normally. This audit did not inspect browser login state, provision accounts, read personal sessions or search credentials.

## Verification boundary

- Source/RPC-definition audit: **PASS** for the stated repository mismatch.
- New regression execution: **NOT RUN by this audit agent**; parent owns the focused Xcode result.
- Deployed read-contract inspection: **PASS**, as reported by the parent's separate read-only MCP check; raw evidence belongs to that parent report.
- Real interrupted cleanup and authenticated A–H: **NOT RUN**.
- Helper ownership rules, existing tests, product UI/code and DB: unchanged by this audit.

Parent execution: **PASS**, ledger safety 7/7 in `/tmp/FitMatchResume30MountedLedger.xcresult` (combined with mounted-state case: 8/8, exit0). Superseded-row guard intentionally returns BLOCKED; this is not successful live recovery. Deployed definition evidence: `evidence/Resume30/deployed-history-contract.json`.
