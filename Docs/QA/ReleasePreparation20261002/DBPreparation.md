# Development DB test preparation — 2026-10-02

## Status and evidence boundary

- **PASS — read-only inspection:** Supabase MCP identifies `hnkplvyegonlhumlejst` as `FitMatch`, `ACTIVE_HEALTHY`, PostgreSQL 17.6.1.147. Inspected deployed function definitions, RPC signatures, RLS metadata, and a reference-data-only tuple validator. No user rows, personal sessions, or credentials were read.
- **PASS — offline safety guards:** `python3 -m unittest discover -s scripts -p test_release_qa_db.py -v`: 9 tests, 0 failures. These are local harness guard tests, not real DB cases.
- **BLOCKED — authenticated DB smoke:** no dedicated two-user credentials were supplied in this shell. [db-preflight.json](db-preflight.json) records missing variable names, `request_count=0`, `real_db_case_count=0`, and `mock_case_count=0`. No Auth, RPC mutation, schema operation, migration, or Production request was executed.
- **NOT RUN — app-owner/device proof:** this prepared harness calls public HTTP RPCs with normal user tokens. It does not execute `FitMatchSupabaseDomainClient`, the sync coordinator, SwiftData persistence, app UI, or physical-device flows. `FitMatchServerAuthorityIntegrationTests` uses `ServerAuthorityRemoteStub`; its results must remain separate from DB evidence.

Baseline inspected: branch `QA`, commit `086617f`. Production `aqhrupgjpmrtnystottx` is excluded. QA Xcode work must use `FitMatch-QA` / `Debug-QA`; a branch name alone does not select a DB.

## Deployed contract map

| Public RPC / parameters | Deployed owner and verified boundary |
|---|---|
| `fitmatch_vnext_upsert_closet_item(p_request jsonb)` | `upsert_closet_item_with_group_for_swift` → preserved group wrapper; manual branch → `upsert_closet_item_for_swift` → `upsert_closet_item`. Requires `auth.uid()`; locks user + `client_item_id`; same request fingerprint returns the same item with `idempotent=true`; changed request for the same client ID raises conflict. |
| `fitmatch_vnext_get_closet_item(p_closet_item_id uuid)` | `list_closet_items(uuid)` → snapshot projection; base filters `ci.user_id=auth.uid()`, `deleted_at is null`, and exact ID. Response is an array of 0–1 items. |
| `fitmatch_vnext_list_closet_items()` | Same owner-scoped active-row projection plus current comparison-group data. No unowned rows may appear. |
| `fitmatch_vnext_update_closet_item(p_closet_item_id uuid, p_request jsonb)` | `update_closet_item` checks authenticated owner and active exact ID before mutation. Manual path → `update_closet_item_snapshot_base`; it requires an explicit valid classification tuple even for a metadata edit. |
| `fitmatch_vnext_delete_closet_item(p_closet_item_id uuid)` | `soft_delete_closet_item`; authenticated owner + active exact ID; sets `deleted_at`, returns `closet_item_id` and `deleted_at`. This is not physical deletion. |

The read-only check returned RLS enabled on `closet_items`, `closet_item_measurements`, `closet_item_source_measurements`, and `comparisons`. Inspected SELECT policies limit Closet/comparison parents to `auth.uid()` and canonical measurements to an owned Closet parent. RPC helpers include `SECURITY DEFINER` owners, so the deployed explicit owner predicates matter as well as table RLS. Metadata inspection alone does not prove authenticated isolation.

Current linked create/update retains exact product/variant/size/observation receipts and separate raw/canonical snapshots. The manual smoke deliberately avoids shared retailer ingestion and catalog mutations. Linked raw-measurement persistence, comparison groups, candidates, begin/complete/history, tombstone sync, and multiple devices require additional authenticated evidence; they are not covered by this smoke.

## Prepared executable

`scripts/release_qa_db.py` exposes:

```bash
python3 scripts/release_qa_db.py preflight --output /tmp/fitmatch-db-preflight.json
python3 scripts/release_qa_db.py smoke --run-id "$(uuidgen)" --output /tmp/fitmatch-db-smoke.json
python3 scripts/release_qa_db.py cleanup --ledger /tmp/fitmatch-db-smoke.json.ledger.json --output /tmp/fitmatch-db-cleanup.json
```

Exit codes: **0 PASS, 1 FAIL, 2 BLOCKED**. Reports print only safe metadata and case results, never tokens, raw HTTP error bodies, or account email addresses. Reports and ledgers are mode 0600. A pre-existing run ledger blocks another smoke at the same output path.

Provide these through a secure local environment before execution; do not put credentials into tracked files, command-line arguments, chat, or test logs:

| Environment variable | Required value |
|---|---|
| `FITMATCH_QA_DB_URL` | `https://hnkplvyegonlhumlejst.supabase.co` |
| `FITMATCH_QA_DB_PUBLIC_KEY` | This project's publishable key or legacy `anon` JWT. Secret/service-role keys are rejected. |
| `FITMATCH_QA_DB_DEDICATED_USERS` | `1`, affirming both users are disposable QA accounts authorized for this run. |
| `FITMATCH_QA_DB_USER_A_TOKEN` | Fresh normal authenticated-user access token for the dedicated owner account. |
| `FITMATCH_QA_DB_USER_A_ID` | Expected exact owner UUID. |
| `FITMATCH_QA_DB_USER_B_TOKEN` | Fresh normal authenticated-user token for a distinct dedicated observer account. |
| `FITMATCH_QA_DB_USER_B_ID` | Expected exact observer UUID. |

The harness never signs up accounts, changes Auth settings, impersonates users, reads Keychain/app sessions, or uses admin SQL to represent user access. Existing `Tools/FitMatchReleaseE2ERunner/main.swift` has an authenticated Swift client seam but currently loads one Keychain account and app Info.plist configuration. It was not executed or treated as a safely isolated two-user runner.

## Isolation, cases, and cleanup

Before network calls, exact HTTPS hostname parsing rejects Production, suffix/subdomain tricks, credentials in URLs, ports, query/fragment/path overrides, privileged keys, foreign JWT issuers, expired tokens, anonymous users, mismatched UUIDs, and duplicate user identities. Redirects are disabled. JWT decoding is only a local guard; `/auth/v1/user` independently verifies both tokens before RPC work.

Before any write, both dedicated accounts must have empty active Closet lists. Existing items cause failure without mutation. A fresh UUID client identity, run marker, account pair, and development project are journaled before create, including the ambiguous-response window. The run creates one manual Closet item for A; B creates no row. Its known explicit tuple (`UNISEX`, `tshirt`, `short_sleeve`, `SINGLE`) was accepted by the deployed read-only validator, and `chest_width` is active. The payload retains `notes=fitmatch-release-qa:<run UUID>` throughout.

Prepared real RPC cases, **all currently NOT RUN**:

1. `DB-CREATE-READ`: create and exact authoritative read-back of UUID, marker, satisfaction, and one `USER_MANUAL` chest-width measurement (52 cm).
2. `DB-IDEMPOTENT-RETRY`: repeat the same create request; same server UUID, `idempotent=true`, one active row. This is a real repeated request when run, not a simulated lost-response test.
3. `DB-OTHER-USER-READ`: B's exact get and list cannot see A's run row.
4. `DB-OTHER-USER-MUTATION`: B's valid update and delete requests are rejected; A's authoritative row remains unchanged after each attempt.
5. `DB-EDIT-READ`: A edits satisfaction with the full valid manual tuple and re-reads exact identity/measurement values.
6. `DB-DELETE-READ`: soft-delete A's run row; exact get and list show no active run row.

Cleanup runs in `finally` after creation attempts. It re-authenticates on a separate cleanup invocation, validates ledger project/account pair/run marker, resolves only the ledger client UUID, verifies marker + manual identity, and requires any recorded server UUID to match before deletion. Duplicate identities, mismatches, or uncertain responses stop cleanup and leave the ledger for retry. No prefix-wide, user-wide, SQL, or catalog cleanup is permitted.

Successful cleanup proves **zero active rows for this run** through normal app RPCs. Soft-deleted parent records and child snapshots can remain physically stored. Hard deletion/Auth-user removal is outside the harness and was not performed. Stale responses after account changes, deliberate timeout injection, app retry UI, local cache reconciliation, and concurrent sync serialization remain separate Swift/mock/device checks.

## Verification notes

- Initial `py_compile` encountered the host Python cache write restriction, then was retried with a `/tmp` cache root; only the successful retry is syntax evidence.
- Narrow protected-scroll and whitespace checks apply to these supporting files; the parent release report owns final workspace-wide build/test results.
- Current Supabase [Swift password sign-in documentation](https://supabase.com/docs/reference/swift/auth-signinwithpassword) was consulted for the existing authenticated-client route. The changelog Markdown fetch was unsupported by the browser fetcher; this work added no Supabase SDK dependency or API feature.
