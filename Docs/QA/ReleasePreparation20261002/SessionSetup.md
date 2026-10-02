# Dedicated development session setup

**Provider clarification (2026-10-02):** This password helper requires email/password accounts, but the existing Swift and HTTP test harnesses do not require the email provider. A deliberately supplied normal Apple access/refresh session can satisfy the same exact-user/development/expiry checks. No such session is currently connected. Do not change an Apple account's provider/password or extract private app sessions to make this helper work. See [DedicatedAccountReadiness.md](DedicatedAccountReadiness.md) for the latest reset authorization and execution status.

This helper is prepared for **two existing, confirmed, disposable development accounts**. No accounts or sessions were created during implementation. Real Auth, DB and Swift authenticated tests remain **NOT RUN / BLOCKED** until those accounts are supplied. It does not sign up users, send confirmation mail, use personal app sessions, or change Auth/RLS settings.

## 1. Review without connecting

```bash
python3 scripts/release_qa_session.py
```

Default execution does not read credentials, connect to Auth, or create files. Development is exactly `https://hnkplvyegonlhumlejst.supabase.co`. Production `aqhrupgjpmrtnystottx` is rejected.

## 2. Supply existing account information locally

Use a trusted local secret/environment mechanism. Keep values out of chat, command arguments, shell history, repository files and logs. Disable shell tracing before handling credentials.

| Environment variable | Required input |
|---|---|
| `FITMATCH_QA_DB_URL` | Exact development URL above |
| `FITMATCH_QA_DB_PUBLIC_KEY` | Development publishable key or legacy development `anon` key; never a secret/service-role key |
| `FITMATCH_QA_DB_DEDICATED_USERS` | `1`, attesting both accounts are dedicated, disposable and authorized for QA |
| `FITMATCH_QA_DB_USER_A_ID` | A's independently known, exact Auth UUID |
| `FITMATCH_QA_DB_USER_B_ID` | B's independently known, distinct Auth UUID |
| `FITMATCH_QA_DB_USER_A_EMAIL` / `USER_A_PASSWORD` | Optional secure environment inputs; otherwise requested using hidden terminal prompts |
| `FITMATCH_QA_DB_USER_B_EMAIL` / `USER_B_PASSWORD` | Optional secure environment inputs; otherwise requested using hidden terminal prompts |

All names in the last two rows use the `FITMATCH_QA_DB_` prefix. The UUIDs must come from the known account records, not be guessed from the login response. If existing confirmed accounts are unavailable, stop here; account creation is a separate action.

## 3. Explicitly create normal sessions

Run in a local interactive terminal only when ready to sign in:

```bash
set +x
python3 scripts/release_qa_session.py --sign-in
```

This performs two password logins and two authenticated `/auth/v1/user` reads, using the exact development host with redirects disabled. It verifies both expected UUIDs, normal authenticated/non-anonymous accounts, issuer and token expiry. Each access token must have more than 600 seconds remaining to satisfy the existing Swift test contract. Auth creation changes session state but performs no application RPC or application-data mutation.

Success prints only the absolute path to a new `sessions.env` file. The file is mode `0600` inside a fresh `0700` temporary directory outside Git. Arbitrary symlinked output paths are rejected. Optional `--output-dir` must name an existing system temporary directory outside Git; do not use a repository path. The file contains only the existing runner's URL/public key/attestation/UUID/access token/refresh token variables. Passwords and emails are never saved.

Failures print a redacted reason and create no session file. A partially successful or interrupted login can still leave an Auth session on the server; the helper does not automatically revoke sessions or retry. A successful preparation is not DB-test evidence.

## 4. Load and verify, then use the existing test runner

In the same trusted local shell, paste only the path printed by the helper when prompted:

```bash
set +x
read -r -p 'Session file path: ' qa_session_file
source "$qa_session_file"
python3 scripts/release_qa_db.py preflight
```

Preflight makes two Auth verification reads. It performs no application-data mutation. After it passes, use the separately scoped smoke/full/cleanup commands in [DBPreparation.md](DBPreparation.md) and [AuthenticatedCoverage.md](AuthenticatedCoverage.md). Full A–H still requires the independently verified exact seed manifest. The empty-account guards and ownership ledger remain mandatory. Do not count bootstrap or preflight as CRUD/RLS/Swift test passes.

Keep the private file until the authorized run and any ledger cleanup are finished. Afterwards remove that exact file and its now-empty directory, and close the shell to discard exported tokens. The helper does not manage refresh-token rotation; obtain fresh normal sessions before another run if the runner reports expiry or a consumed refresh token.

## Offline verification

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p test_release_qa_session.py -v
```

The tests replace HTTP responses with synthetic fixtures. They check no-network default, target/key/identity rejection, failure redaction/no file, SDK freshness, distinct owners, protected file permissions and Git/symlink output rejection. They are not evidence of successful live login.

Protocol references: [Supabase password authentication](https://supabase.com/docs/guides/auth/passwords) and [official Auth REST schema](https://github.com/supabase/auth/blob/master/openapi.yaml) (`POST /token?grant_type=password`, `GET /user`). Current docs were reviewed; the changelog fetch was unavailable in this environment.
