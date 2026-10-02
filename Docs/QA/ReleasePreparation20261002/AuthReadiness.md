> 최신 보완: 인증 Swift runner·독립 ledger 정리는 현재 작성/컴파일/발견 완료. 아래 조사 당시 미구현 기록은 과거 상태다. 실제 계정 인증·DB 실행은 여전히 BLOCKED. AuthenticatedCoverage.md와 Resume40Report.md를 먼저 확인한다.

# Development Auth readiness — 2026-10-02

## Result

**BLOCKED — authenticated QA execution:** two confirmed, dedicated development-account sessions are not available in the current shell. Normal email signup is enabled, but email confirmation is required. This review created no accounts, signed in no users, sent no email, and performed **zero DB writes**.

Target: development project `hnkplvyegonlhumlejst` (`FitMatch`). Production `aqhrupgjpmrtnystottx` was excluded; no Production request was made. Baseline remains QA commit `086617f`; existing working-tree changes were preserved.

## Read-only findings

| Check | Observed result |
|---|---|
| Supabase project metadata | **PASS:** `ACTIVE_HEALTHY`, PostgreSQL `17.6.1.147`, region `ap-northeast-2`. |
| Public configuration | **PASS:** the `Debug-QA` build settings already contain the exact development HTTPS URL and a publishable key. The key was consumed in memory and was not printed or saved by this review. |
| Public Auth settings | **PASS:** `GET https://hnkplvyegonlhumlejst.supabase.co/auth/v1/settings` returned HTTP 200 with the QA publishable key. Redirects were disabled. |
| Signup / confirmation | `disable_signup=false`, `external.email=true`, `mailer_autoconfirm=false`. Email signup is enabled; **email confirmation is required**. Actual signup, delivery, confirmation, and login remain **NOT RUN**. |
| Other providers | `external.anonymous_users=false`, `external.apple=true`, `external.phone=false`, `phone_autoconfirm=false`. Provider enablement alone is not successful sign-in evidence. |
| Dedicated QA environment | All seven variables listed in [environment.example](environment.example) were absent. Only presence booleans were printed; no credentials were searched for in Keychain, app sessions, or unrelated files. |
| Existing DB preflight | **BLOCKED:** `request_count=0`, `real_db_case_count=0`, `mock_case_count=0`; missing-variable names only. |

The public settings establish that email signup is permitted. They do not establish a working inbox, mail delivery, SMTP eligibility, or a completed account session. Do not disable confirmation or use admin-created/impersonated sessions to remove this blocker. The [current Supabase signup documentation](https://supabase.com/docs/reference/swift/auth-signup) states that signup with confirmation enabled returns a user but no session until confirmation.

### Executed scope

- Supabase MCP `get_project` for `hnkplvyegonlhumlejst` only. No SQL was executed during this review.
- Parsed `FitMatch.xcodeproj/project.pbxproj` with `plutil -convert json -o -` in a Python process; selected only the exact `Debug-QA` development URL and publishable-key setting. Printed configuration presence/type, not the key.
- Used that public key for the single successful read-only Auth settings GET above. The initial sandboxed GET failed DNS resolution; the same read-only request then succeeded with network access. No signup, token, admin, RPC, or Auth-user endpoint was called.
- Read `AGENTS.md`, current Handoff entries, [DBPreparation.md](DBPreparation.md), `environment.example`, `scripts/release_qa_db.py`, its guard tests, and the relevant Swift configuration/authenticated-client seams.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p test_release_qa_db.py -v`: **PASS**, 9 tests, zero failures. These are offline guards, not authenticated DB cases.
- `PYTHONDONTWRITEBYTECODE=1 python3 scripts/release_qa_db.py preflight`: **BLOCKED**, exit 2, zero network requests. Report timestamp: `2026-10-02T09:07:57.411104+00:00`.
- `git diff --check` and the required protected-scroll check: **PASS**. No `xcodebuild`, Swift test, or executable runner was run.

## Shortest secure setup

1. Use two distinct disposable accounts belonging to the development project, with email confirmation already completed through their controlled inboxes. If new accounts are needed, complete normal signup and confirmation first. Neither account may have active Closet rows when the smoke begins.
2. Obtain fresh normal-user access tokens through normal login. Supply the following through an existing local secret/environment mechanism in the execution process. Keep values out of `environment.example`, tracked files, shell command arguments/history, chat, and logs.

   | Variable | Value |
   |---|---|
   | `FITMATCH_QA_DB_URL` | `https://hnkplvyegonlhumlejst.supabase.co` |
   | `FITMATCH_QA_DB_PUBLIC_KEY` | Existing QA publishable key from the resolved QA configuration. |
   | `FITMATCH_QA_DB_DEDICATED_USERS` | `1`, affirming that both accounts are disposable and authorized. |
   | `FITMATCH_QA_DB_USER_A_TOKEN` | Fresh normal authenticated access token for A. |
   | `FITMATCH_QA_DB_USER_A_ID` | A's exact UUID. |
   | `FITMATCH_QA_DB_USER_B_TOKEN` | Fresh normal authenticated access token for B. |
   | `FITMATCH_QA_DB_USER_B_ID` | B's exact, distinct UUID. |

3. Run the existing preflight below. It verifies both tokens with `/auth/v1/user`; decoded JWT claims alone are not accepted as authentication proof. Only after preflight passes, follow the existing scoped smoke and ledger-cleanup instructions in [DBPreparation.md](DBPreparation.md).

```bash
python3 scripts/release_qa_db.py preflight --output /tmp/fitmatch-db-preflight.json
```

The Python harness requires more than 120 seconds of remaining token validity at startup and does not refresh tokens. The current missing setup is the two confirmed dedicated identities and their fresh tokens/UUIDs; the development public URL/key already exist.

## Harness gaps and future real Swift feasibility

- `scripts/release_qa_db.py:56` accepts token/UUID pairs only. It has no normal password-login bootstrap, token refresh, or credential-free public-settings mode. Its six prepared smoke cases exercise HTTP RPC contracts; they do not exercise the Swift owner, sync coordinator, SwiftData, UI, or Apple sign-in.
- `Tools/FitMatchReleaseE2ERunner/main.swift:167` reads the source `FitMatch/Info.plist`. That file currently contains literal `$(FITMATCH_SUPABASE_URL)` and `$(FITMATCH_SUPABASE_PUBLISHABLE_KEY)` build placeholders. The runner lacks resolved QA configuration and an exact development-host guard. Its `KeychainCredential.load()` also loads only one account. Do not run it unchanged for this two-user QA scope.
- A real Swift path is structurally feasible: `FitMatch/Services/FitMatchSupabaseProductResolver.swift:1982` already exposes `FitMatchSupabaseDomainClient(authenticatedClient:)`. The existing runner at `main.swift:258` demonstrates normal `client.auth.signIn`, then injection into the real domain client and `FitMatchClosetSyncCoordinator`, with an in-memory SwiftData container.
- Environment configuration alone does not authenticate that Swift client. `authenticatedClient()` at `FitMatchSupabaseProductResolver.swift:3301` requires `client.auth.session`; adding only an Authorization header is insufficient. A future isolated runner must establish a real SDK session through normal Auth, verify the expected dedicated UUID, and inject separate clients for A and B. The existing Python access-token-only variables are not by themselves a complete SDK-session bootstrap contract.
- `FitMatchSupabaseConfiguration.live()` intentionally returns nil under XCTest/UI-testing flags. Future authenticated Swift checks should use the explicit injected-client seam rather than changing that production guard. They must retain the exact development-target checks, dedicated-account scope, and ownership ledger before any mutation.

No Swift authentication runner or session-bootstrap change was implemented or executed in this review. Account creation, confirmation, authenticated RPC smoke, cleanup, actual Swift-owner integration, and device E2E all remain **NOT RUN**.
