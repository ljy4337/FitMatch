# Offline transport failure coverage

## Prepared test selectors

Prefer the complete Swift Testing type selector: `FitMatchTests/FitMatchReleaseTransportFaultTests`.

| Function | Cases | Actual production boundary |
|---|---|---|
| `mutationRPCFaultsReachRealHTTPBoundaryAndNeverReturnSuccess` | 7 parameter values; each exercises 5 RPCs | `FitMatchSupabaseDomainClient` → actual Supabase/PostgREST SDK → injected URLSession; linked create/update, begin, complete and History hide must throw rather than return success. Each case verifies its exact RPC path and POST method were reached. |
| `closetDeleteTransportFailurePreservesIntentAndPreventsLocalCommit` | 7 parameter values | `FitMatchClosetDeletionTransaction.run` → actual domain delete RPC → injected URLSession; deletion intent remains recorded and local commit never runs. |
| `successfulDeleteReceiptReachesRealDecoderAndCommitsExactlyOnce` | 1 control | HTTP 200 exact delete receipt is decoded through the real SDK and domain client; the transaction commits once. |

The 7 parameter values are offline (`URLError.notConnectedToInternet`), HTTP 403, HTTP 429, HTTP 500, timeout (`URLError.timedOut`), HTTP 200 malformed JSON, and transport cancellation (`URLError.cancelled`). Total planned execution: 15 invocations / 43 intercepted RPC requests.

## Isolation and evidence

- Each test fixture uses its own random `.invalid` host and an ephemeral URLSession. The URLProtocol handles every URL; unregistered URLs fail locally. No request can fall through to a development or Production endpoint.
- A synthetic, unexpired session exists only in a locked in-memory `AuthLocalStorage`; no real token, account, keychain or project configuration is read. Auto refresh is disabled. Nothing is written to a database.
- The injected seam is URLSession, not a fake domain-service implementation. Request construction, HTTP handling, PostgREST errors, response decoding, domain error mapping and the deletion transaction run in production owners. Recorded requests prevent a missing-auth or payload-preflight rejection from masquerading as an exercised network boundary.
- The 200 deletion control distinguishes an operational transport fixture from one that always fails before the tested RPC.

PASS: Swift frontend syntax parse and `git diff --check` when prepared. XCTest compile/execution: NOT RUN by this subtask; the main task's single Xcode run supplies final results.

## Remaining boundaries

This does not prove deployed server/RLS decisions, real connectivity, retry timing, UI error copy, alert dismissal, task cancellation/disappearance, or save/edit local-cache behavior after every failure. Transport cancellation is intentionally distinguished from `Task.cancel()`. The create/update/begin/complete/hide cases establish failed real RPC results; only deletion additionally exercises the local transaction commit guard. Existing action/coordinator tests supply separate cache/presentation evidence and must not be combined into an unexecuted end-to-end claim.

The pinned SDK's actual source was used for its `SupabaseClientOptions.global.session`, `AuthLocalStorage` and session-storage API. Official [Swift initialization documentation](https://supabase.com/docs/reference/swift/initializing) also documents custom storage and URLSession. The changelog Markdown fetch was unavailable in the web tool; no SDK upgrade or production behavior change was made.
