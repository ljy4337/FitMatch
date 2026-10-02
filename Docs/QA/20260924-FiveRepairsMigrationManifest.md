# 2026-09-24 Five Repairs — Migration Candidate Manifest

## Scope

This is a **Git inclusion, replay-order, and deployment correspondence manifest**.
The three approved contracts below were applied to development project `hnkplvyegonlhumlejst` on 2026-09-24; v2 remains unapplied.
The current working tree keeps them untracked until an explicit review/commit.

## Forward order

1. `20260921090000_measurement_semantic_context_separation.sql`
   - Existing semantic-context prerequisite. It is not changed by this task.
2. `20260921110000_closet_raw_measurement_snapshots.sql`
   - Adds selected-observation raw Closet snapshots. Required by 3 and 7.
3. `20260923110000_same_comparison_group_only.sql`
   - Existing same-group candidate/authorization policy. Its Verify/Rollback
     and SQL regressions remain separate from this repair set.
4. `20260924100000_linked_closet_size_snapshot_updates.sql`
   - Linked M→L update owner: parent, canonical, and source snapshot replace
     atomically with an exact observation.
5. `20260924101000_closet_detail_snapshot_round_trip.sql`
   - Exact explicit `closet_detail_code_snapshot` list/update round trip.
6. `20260924102000_comparison_history_tombstone_sync.sql`
   - Additive, owner-scoped deleted History tombstone sync RPC.
7. `20260924103000_retailer_exact_evidence_v2_preflight.sql`
   - Additive inactive server evidence helper only. It does **not** alter
     candidate, authorize, begin, complete, or History contracts.

## Verification files

- `supabase/sql/20260924100000_linked_closet_size_snapshot_updates_Verify.sql`
- `supabase/sql/20260924101000_closet_detail_snapshot_round_trip_Verify.sql`
- `supabase/sql/20260924102000_comparison_history_tombstone_sync_Verify.sql`
- `supabase/sql/20260924103000_retailer_exact_evidence_v2_preflight_Verify.sql`
- `supabase/sql/tests/20260924_linked_closet_snapshot_round_trip_LocalRegression.sql`
- `supabase/sql/tests/20260924_comparison_history_tombstone_sync_LocalRegression.sql`
- `supabase/sql/tests/20260924_retailer_exact_evidence_v2_preflight_LocalRegression.sql`

Run Verify after each corresponding forward migration. The local regression
harnesses create only minimal owner/table fixtures; they are not proof that a
full production baseline replayed successfully.

## Rollback order

Run only after a read-only impact check and in reverse dependency order:

1. `20260924103000_retailer_exact_evidence_v2_preflight_Rollback.sql`
2. `20260924102000_comparison_history_tombstone_sync_Rollback.sql`
3. `20260924101000_closet_detail_snapshot_round_trip_Rollback.sql`
4. `20260924100000_linked_closet_size_snapshot_updates_Rollback.sql`

The v2 and tombstone rollbacks only drop additive functions. The linked raw
snapshot rollback is intentionally non-destructive: it must not delete user
raw evidence or completed comparison history.

## Reproducibility status

- Isolated owner/harness execution: PASS for 4, 5, 6, and inactive 7.
- Empty full Supabase replay: BLOCKED. This checkout has neither Supabase CLI
  nor Docker/local Supabase bootstrap, so a true Git-only baseline database
  replay was not fabricated from synthetic fixtures.
- Connected DB deployment: PASS for 4, 5, and 6 after explicit user approval.
  Read-only postflight verified function contracts and restricted grants.
  Full Git-only replay and authenticated mutation/device E2E remain unverified.

## Actual remote migration correspondence (2026-09-24)

| Local file prefix | Remote version | Remote name |
|---|---|---|
| 20260924100000 | 20260924014952 | linked_closet_size_snapshot_updates |
| 20260924101000 | 20260924015007 | closet_detail_snapshot_round_trip |
| 20260924102000 | 20260924015014 | comparison_history_tombstone_sync |

Names and versions were read back from supabase_migrations.schema_migrations.
Local filenames are not the remote version IDs. Do not blindly reapply them
with a CLI until migration history reconciliation is explicitly planned.
The first migration includes the metadata-only server-measurement routing repair
validated RED (exit3) then GREEN (exit0) in an isolated PostgreSQL17 harness.
Existing candidate/begin/complete function hashes were unchanged after deployment.
No user rows were rewritten or created for testing. New files remain untracked;
remote deployment does not imply Git publication or full-baseline reproducibility.

## 2026-09-24 content verification and bootstrap blocker

Read-only remote migration SQL content hashes match the local bytes exactly:

| Local version | Recorded SQL MD5 |
|---|---|
| 20260924100000 | 77bf764998f66d45a286c6f2ce0a09f5 |
| 20260924101000 | 9db3581e0550e6fef35d3216d8860159 |
| 20260924102000 | 340fe5940070e3ac7be5229fafe1bfd9 |

Metadata inventory: `20260924-RemoteMigrationInventory.json` (129 applied migrations).
MD5 here checks exact content correspondence, not security or replay equivalence.
An empty isolated PostgreSQL17 first-migration attempt exited3 at
`20260801034325_create_garment_length_classification_rules.sql:17`:
`relation "public.sources" does not exist`.
Log: `/tmp/fitmatch-deploy-bootstrap-u266t7rd/run.log`.
The existing migration chain assumes an application baseline. Installing a CLI
alone does not supply this table. Do not invent a minimal replacement to make
replay appear to pass. A reviewed schema-only baseline export, required catalog
seed evidence, and a complete isolated replay remain necessary; no connected
DB or migration-history changes were made during this verification.
