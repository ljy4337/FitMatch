# Uniqlo KR Catalog Collector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a resumable, API-first collector that archives the complete UNIQLO Korea clothing catalog's retailer responses and produces source-traceable normalized records.

**Architecture:** Extend the existing UNIQLO discovery and size-chart collectors with an isolated Python raw-archive/normalization package. The collector records local immutable receipts and run state first; a later, explicitly authorized migration exposes an equivalent server-owned catalog store without altering existing Closet, comparison, or mapping pipelines.

**Tech Stack:** Python 3 standard library, existing curl-backed UNIQLO API calls, JSON/CSV local artifacts, unittest, Supabase SQL migrations (prepared only; no remote application in this plan).

**Spec:** `docs/superpowers/specs/2026-09-28-uniqlo-kr-catalog-design.md`

## Global Constraints

- Scope is UNIQLO Korea's entire clothing catalog; the initial run is local/non-production only.
- Use official API responses as the primary source. Selenium is limited to discovery/request-contract fallback and must not bypass access controls.
- Preserve all original product, variant, size, category, and measurement facts, including unmapped or malformed-for-normalization values.
- Archive request URL, response status/body/content hash, timestamp, collector version, and outcome before normalizing a receipt.
- Use explicit deferred/failed outcomes for 403, 429, CAPTCHA, empty charts, malformed payloads, and schema drift; never fabricate success.
- Keep raw archive, normalized catalog, canonical mapping, comparison eligibility, Closet, comparison history, and product policy separated.
- Do not apply migrations or write to a connected database without separate explicit authorization.
- Do not expose catalog write access to app clients or introduce client-side service keys.

## Review Focus

- A changed response for the same product/URL must create a new immutable receipt, while the same hash must not duplicate it (Task 1 test).
- A partial or failed discovery must not mark a formerly visible product as unavailable (Task 2 test).
- A size chart with unknown labels or non-numeric measurements must retain its raw source record and report normalization defects rather than discard the receipt (Task 3 test).
- An HTTP 403/429 or CAPTCHA-shaped response must be deferred with no Selenium bypass attempt (Task 2 test).
- A normalized size/measurement must always reference the precise source receipt and exact product/variant/size identity (Task 3 test).

---

## File Structure

- Create `scripts/uniqlo_catalog/archive.py`: immutable receipt and run-manifest storage, content hashing, atomic writes, and duplicate detection.
- Create `scripts/uniqlo_catalog/normalize.py`: pure UNIQLO payload-to-normalized-record conversion that never mutates source payloads.
- Create `scripts/uniqlo_catalog/models.py`: typed result/status constants shared by archive, fetch orchestration, and normalization.
- Create `scripts/collect-uniqlo-raw-catalog.py`: resumable command-line orchestration over the existing discovery checkpoint and official size-chart request contract.
- Create `scripts/test_uniqlo_catalog_archive.py`: receipt identity, hash deduplication, and atomic manifest regression tests.
- Create `scripts/test_uniqlo_catalog_normalize.py`: exact source identity and raw-measurement preservation tests.
- Create `scripts/test_collect_uniqlo_raw_catalog.py`: incomplete discovery, access-deferred, and resume behavior tests.
- Create `supabase/migrations/<generated>_uniqlo_catalog_raw_archive.sql`: prepared, additive private catalog tables/RLS/server-only grants; generate its timestamp via `supabase migration new` when implementation begins.
- Create `supabase/sql/uniqlo_catalog_raw_archive_Verify.sql`: read-only schema/RLS/grant verification script for the prepared migration.
- Modify `scripts/run-uniqlo-incremental-catalog.py`: optionally emit a compatible discovery checkpoint reference; do not alter its existing database-ingest behavior.
- Modify `Docs/CodexSessionHandoff.md`: record actual implementation, local test evidence, and un-applied migration status only after work is performed.

### Task 1: Local immutable raw archive

**Files:**
- Create: `scripts/uniqlo_catalog/models.py`
- Create: `scripts/uniqlo_catalog/archive.py`
- Test: `scripts/test_uniqlo_catalog_archive.py`

**Interfaces:**
- Produces `archive_receipt(root: Path, receipt: RawReceipt) -> ArchiveResult`.
- Produces `load_run_manifest(root: Path, run_id: str) -> dict[str, object]`.
- `RawReceipt` includes `source`, `storefront`, `external_product_id`, `request_url`, `http_status`, `content_type`, `body`, `collected_at`, `collector_version`, and `outcome`.

- [ ] **Step 1: Write failing archive tests**

```python
def test_same_product_and_hash_reuses_receipt_but_records_observation():
    first = archive_receipt(root, receipt(body=b'{"id":"E1"}'))
    second = archive_receipt(root, receipt(body=b'{"id":"E1"}'))
    assert second.receipt_id == first.receipt_id
    assert second.deduplicated is True

def test_changed_body_creates_a_new_immutable_receipt():
    assert archive_receipt(root, receipt(body=b'{"v":1}')).receipt_id != \
        archive_receipt(root, receipt(body=b'{"v":2}')).receipt_id
```

- [ ] **Step 2: Run the archive tests to verify failure**

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 -m unittest scripts/test_uniqlo_catalog_archive.py -v`

Expected: FAIL because `uniqlo_catalog.archive` does not exist.

- [ ] **Step 3: Implement immutable receipt writes**

Implement `RawReceipt`, `ArchiveResult`, and `archive_receipt`. Store JSON metadata and the exact binary body beneath a SHA-256-derived receipt directory. Use a temporary sibling path plus `Path.replace()` so a partial write is never treated as a receipt. Append each observation to the run manifest even when its body deduplicates.

- [ ] **Step 4: Run archive tests to verify success**

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 -m unittest scripts/test_uniqlo_catalog_archive.py -v`

Expected: PASS.

### Task 2: Resumable official-API fetch orchestration

**Files:**
- Create: `scripts/collect-uniqlo-raw-catalog.py`
- Create: `scripts/test_collect_uniqlo_raw_catalog.py`
- Modify: `scripts/run-uniqlo-incremental-catalog.py`

**Interfaces:**
- Consumes discovery checkpoints with `sources.uniqlo.audiences.*.discovered_products`.
- Consumes `archive_receipt(root, receipt)` from Task 1.
- Produces `run_collection(checkpoint: Path, archive_root: Path, run_id: str, ...) -> CollectionSummary` and `summary.json`.

- [ ] **Step 1: Write failing orchestration tests**

```python
def test_incomplete_discovery_returns_nonzero_without_absence_decisions():
    summary = run_collection(incomplete_checkpoint, archive_root, "run-1", fetcher=fake_fetcher)
    assert summary.discovery_complete is False
    assert summary.unavailable_product_ids == []

def test_429_is_archived_and_deferred_without_browser_fallback():
    summary = run_collection(complete_checkpoint, archive_root, "run-2", fetcher=rate_limited_fetcher)
    assert summary.deferred_product_ids == ["E123456"]
    assert browser_fallback.call_count == 0
```

- [ ] **Step 2: Run orchestration tests to verify failure**

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 -m unittest scripts/test_collect_uniqlo_raw_catalog.py -v`

Expected: FAIL because the raw catalog command does not exist.

- [ ] **Step 3: Implement checkpoint-driven collection**

Implement a CLI with `--checkpoint`, `--archive-root`, `--run-id`, `--resume`, `--limit`, `--delay-ms`, and `--no-network`. Reuse the existing official `size-charts` request conventions. Classify 403/429/CAPTCHA/malformed/empty results before normalization, archive the evidence, and leave those IDs resumable. Do not call Selenium automatically; emit an explicit `discovery_or_contract_review_required` outcome when API contract discovery is missing.

- [ ] **Step 4: Add a compatible discovery handoff**

Add only a documented `raw_collection_checkpoint` field or command output to `run-uniqlo-incremental-catalog.py`; preserve its current `--no-db-sync` and trusted batch-ingestion behavior unchanged. Add a regression assertion for the existing incomplete-discovery exit code.

- [ ] **Step 5: Run orchestration and existing incremental tests**

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 -m unittest scripts/test_collect_uniqlo_raw_catalog.py scripts/test_run_uniqlo_incremental_catalog.py -v`

Expected: PASS.

### Task 3: Source-traceable normalization and replay

**Files:**
- Create: `scripts/uniqlo_catalog/normalize.py`
- Create: `scripts/test_uniqlo_catalog_normalize.py`
- Modify: `scripts/collect-uniqlo-raw-catalog.py`

**Interfaces:**
- Consumes `normalize_size_chart(receipt_id: str, product_id: str, payload: dict[str, object]) -> NormalizationResult`.
- Produces JSONL/JSON normalized product, variant, size, and measurement records with `source_receipt_id`.
- Produces `replay_archive(archive_root: Path, receipt_ids: Iterable[str]) -> ReplaySummary`.

- [ ] **Step 1: Write failing normalization and replay tests**

```python
def test_every_measurement_preserves_source_label_value_unit_and_receipt_id():
    result = normalize_size_chart("receipt-1", "E123456", fixture)
    row = result.measurements[0]
    assert (row["source_receipt_id"], row["raw_label"], row["raw_value"], row["raw_unit"]) == \
        ("receipt-1", "어깨너비", "48", "cm")

def test_unknown_or_non_numeric_value_is_retained_as_raw_issue_not_silently_dropped():
    result = normalize_size_chart("receipt-2", "E123456", unknown_value_fixture)
    assert result.raw_issues[0]["source_receipt_id"] == "receipt-2"
```

- [ ] **Step 2: Run normalization tests to verify failure**

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 -m unittest scripts/test_uniqlo_catalog_normalize.py -v`

Expected: FAIL because `normalize_size_chart` does not exist.

- [ ] **Step 3: Implement pure normalization and replay**

Extract only retailer facts from archived JSON. Preserve product/variant/size identifiers, path and display fields, original measurement values/units/labels, field location, and receipt ID. Emit explicit raw issues for unknown structures; do not apply FitMatch canonical mappings or comparison eligibility. Add `--replay-receipt` to regenerate normalized artifacts without network access.

- [ ] **Step 4: Run normalization/replay tests**

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 -m unittest scripts/test_uniqlo_catalog_normalize.py -v`

Expected: PASS.

### Task 4: Prepared server-side catalog archive contract

**Files:**
- Create: `supabase/migrations/<generated>_uniqlo_catalog_raw_archive.sql`
- Create: `supabase/sql/uniqlo_catalog_raw_archive_Verify.sql`
- Test: `supabase/sql/uniqlo_catalog_raw_archive_Verify.sql`

**Interfaces:**
- Produces private `fitmatch_catalog` run, receipt, normalized product/variant/size/measurement, and normalization-issue tables.
- Produces service-role-only writer access; no client RPC or public grants.
- Does not modify existing `products`, Closet, history, comparison, category-mapping, or policy tables.

- [ ] **Step 1: Discover migration creation and local validation commands**

Run: `supabase migration new --help` and `supabase --version`.

Expected: identify the local CLI's supported migration-generation and validation path before naming the file.

- [ ] **Step 2: Create failing read-only verification SQL**

Write checks that require all catalog archive tables, receipt-to-normalized foreign keys, RLS enabled, `PUBLIC`/`anon`/`authenticated` privileges revoked, and `service_role` grants present.

- [ ] **Step 3: Generate and implement the additive migration**

Use `supabase migration new uniqlo_catalog_raw_archive`. Add only the private, source-traceable tables and constraints from the spec. Each normalized table must reference the source receipt; raw receipt hashes are unique per source/request identity/content hash. Enable RLS and grant only `service_role` appropriate access. Do not apply the migration to any connected database.

- [ ] **Step 4: Run the available local SQL syntax/verification route**

Run the CLI-discovered local validation command if a local database is available; otherwise run a parser/static review and record database validation as NOT RUN.

Expected: no syntax errors; connected database application remains NOT RUN.

### Task 5: Offline smoke collection and final evidence

**Files:**
- Modify: `Docs/CodexSessionHandoff.md`
- Modify: `docs/superpowers/specs/2026-09-28-uniqlo-kr-catalog-design.md` only if implementation changes an approved contract

**Interfaces:**
- Consumes Tasks 1-4.
- Produces an offline or bounded official-API smoke-run manifest and truthful evidence summary.

- [ ] **Step 1: Create a small fixture-backed smoke checkpoint**

Use two product IDs with representative variant/size charts and one deferred response fixture. Do not reuse user-owned or Production catalog data.

- [ ] **Step 2: Run the full Python suite and syntax checks**

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 -m unittest scripts/test_uniqlo_catalog_archive.py scripts/test_collect_uniqlo_raw_catalog.py scripts/test_uniqlo_catalog_normalize.py scripts/test_run_uniqlo_incremental_catalog.py -v`

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 -m py_compile scripts/uniqlo_catalog/*.py scripts/collect-uniqlo-raw-catalog.py`

Expected: PASS.

- [ ] **Step 3: Run a bounded non-production smoke collection only if live collection remains authorized**

Run: `PYTHONPYCACHEPREFIX=/tmp/fitmatch-pycache python3 scripts/collect-uniqlo-raw-catalog.py --checkpoint <fixture-or-approved-live-checkpoint> --archive-root /tmp/fitmatch-uniqlo-raw-smoke --run-id smoke --limit 2`

Expected: receipt metadata/body, normalized output, and `summary.json` agree on exact product/variant/size identity. If live retailer access is unavailable, record BLOCKED rather than treating fixture success as live proof.

- [ ] **Step 4: Review final diff and safeguards**

Run: `git diff --check`.

Run the repository's protected-scroll verification from `AGENTS.md`.

Expected: PASS with no protected scroll changes.

- [ ] **Step 5: Record actual results without claiming database deployment**

Update `Docs/CodexSessionHandoff.md` with changed files, local test results, smoke evidence, access-control behavior, and explicit PASS/FAIL/BLOCKED/NOT RUN statuses. Do not commit or push unless separately authorized.

## Self-review

- Spec coverage: Tasks 1-3 cover immutable receipts, official API collection, retention, normalization, hash increments, and replay. Task 4 covers the server-only additive schema without applying it. Task 5 covers bounded evidence and handoff.
- Type consistency: Task 1 defines receipt/archive types; Task 2 consumes archive writes; Task 3 consumes receipt IDs and emits normalized records; Task 4 mirrors rather than replaces those identities.
- Review-focus coverage: hash deduplication (Task 1), incomplete discovery and access deferral (Task 2), raw issue retention and source references (Task 3), and no browser bypass (Task 2) are all explicitly tested.
- Scope: Existing batch ingest is preserved and only receives a compatible checkpoint handoff. The plan does not change FitMatch product policy, client UX, or connected databases.
