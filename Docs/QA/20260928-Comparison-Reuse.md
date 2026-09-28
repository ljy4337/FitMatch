# 2026-09-28 Comparison reuse and requested UI alignment

## Scope

Base: `origin/connectDB` / `4fa184252a3a13ae7597f2920f12acec15af5800`.

1. Exact selected Closet read instead of transporting the full Closet again.
2. Candidate RPC exposes already-computed eligibility evidence. List and detail score the same server inputs and share a bounded arithmetic cache. Changed inputs/minimum recalculate; final authorization and persistence remain server-owned.
3. Fresh selected-candidate eligibility avoids the separate eligible RPC before begin. Begin still validates fingerprints and exact identities; old/automatic callers retain existing eligibility lookup.
4. Previously requested UI alignment: editing shows A–G group only; Closet uses the existing History native swipe style; both screens ask before deleting; product loading shows all three stages and advances existing phase indicators. No protected scroll changes.

The earlier proposal to bypass retailer fetch/observation indefinitely from a product code was **not implemented**. Price, stock, variant identity and original-receipt requirements need a separately established freshness policy. This is a remaining scope item, not a measured speed improvement.

## Development database

Project `hnkplvyegonlhumlejst` (FitMatch), documented development environment.
Applied migration `comparison_preview_evidence`, remote ledger `20260928075844`.
Source: `supabase/sql/comparison_preview_evidence_20260928.sql`.

Preflight captures exact helper definitions and rejects drift. Postflight:

| Function | Before MD5 | After MD5 |
|---|---|---|
| mapped filtered candidates | 21344d8257f7e8604baf658901e00750 | 0f39e3900879b08cec267bc7e0248d4b |
| session filtered candidates | 4ff6de9d9211e3e12cdf919ccd49982c | 338e0bde3a88bc18b37dc80acb611c03 |
| begin_comparison(jsonb) | 18a07616594d0e56b3d904d8b141e990 | unchanged |
| complete_comparison(uuid,jsonb) | 73b596a1bda260e16834b03e9f7368f7 | unchanged |
| eligible, mapped | 3360061ebd04240f4704a4a1cd117277 | unchanged |
| eligible, session | 175c33b6c57ae5cb72e15ffd38810f22 | unchanged |

All six function ACLs unchanged. Candidate helpers remain postgres-only; existing public authenticated wrappers remain entry points. No user product/Closet/History rows mutated. The captured baseline helpers in `supabase/sql/tests/comparison_preview_20260928_baseline.sql` are also the rollback definitions; any live rollback requires environment/authorization and drift review before applying.

## Verification

### PASS — isolated PostgreSQL contract regression

```sh
npm install --prefix /tmp/fitmatch-sql-check @electric-sql/pglite
node supabase/sql/tests/comparison_preview_20260928.mjs /tmp/fitmatch-sql-check/node_modules/@electric-sql/pglite/dist/index.js
```

14 mapped/session/full/selected cases cover own/other-owner/deleted/missing/blocked rows and unspecified multi-variant behavior. Checks exact preview evidence, byte-equivalent JSON values after removing the additive key, unchanged eligibility call sequences, unauthenticated and wrong-variant rejection, and rollback parity. Runs real candidate PL/pgSQL bodies against local fixtures; group/eligibility are stubs. Does **not** prove live scoring or app behavior.

### PASS — limited syntax and source checks

- pglast parses SQL and both PL/pgSQL function bodies.
- Tree-sitter Swift reports no new parse-error fragments compared with HEAD. Two existing files contain grammar-unsupported constructs in both revisions. This is **not Swift typechecking**.
- `git diff --check`; protected scroll file/call-site gate.

### NOT RUN — iOS/Swift and live behavior

Linux environment has no Swift/Xcode. Added Swift regressions cover exact-row transport, preview/detail values, arithmetic reuse, evidence/weight/minimum invalidation, malformed preview identity and mandatory begin rejection despite cached eligibility. These tests are committed but **not executed** here. Build, XCTest, real UI swipe/loading behavior, authenticated comparison/save E2E and before/after timings are NOT RUN. No latency reduction in seconds is claimed.
