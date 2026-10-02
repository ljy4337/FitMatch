# Preparation coverage — scoped revision 20

This audit covers automated **preparation + small smoke** only. It does not require a full campaign, actual DB mutation, device run, release qualification, or product/policy change to call a prepared probe runnable. The historical runner's combined `BLOCKED` result remains unchanged.

## Current evidence

- Current root Resume20 smoke app: **PASS**,61 methods/85 executions,0 failures/0 skips; actual app owners with synthetic remote. This supersedes prior run as current local evidence.

- Preserved `evidence/Resume30/smoke/app-summary.json`: **PASS**, 56 methods / 75 parameter-expanded executions, 0 failures/0 skips. These are prior executions, not new runs here. Its exact test tree is `app-tests.json`.
- Separate prior live parser run: three providers, one URL each, sizes MUSINSA2 / UNIQLO7 / ZARA4. This does not prove persistence.
- New `FitMatchReleaseHistoryOracleTests/literalCompletedHistoryKeepsNumbersAndIdentityAfterDiskReopen`: **PASS**: focused exit0 (combined12 methods/17 executions), then current smoke61 methods/85 executions. See evidence/Resume20/.
- [requirement-coverage-v1.json](requirement-coverage-v1.json) is the executable mapping: source line + exact selector + input + owner/view output + counts + fresh-read + unaffected state + policy + evidence limits for every A–H / 1–10 item. A local count or fake remote receipt is never labeled an actual DB count.

## A–H and continuous 1–10

| Requirement | Selected current preparation | Exact evidence boundary |
|---|---|---|
| A | A, duplicate/8, committed-response-lost | Real save/projector; immutable retry; local1/fake accepted1; live DB0 requests |
| B | B/rejection, sequence1, sequence4.async | Current async edit/read-back/new comparison; control row retained |
| C | C, C/6, sequence1, ambiguous delete | Target-only removal after receipt; associated snapshot retained |
| D | D/partial/tie/malformed and five numeric boundaries | Literal preview/detail/completion oracle; new persisted History bridge below |
| E | E/failure | Synthetic tombstone across new container/coordinator; existing additional unrelated-History selector mapped but not counted as run |
| F | F/stale, sequence2.mounted | Exact restored size IDs; real mounted Result selection/cache |
| G | G, sequence2/mounted | Explicit second Closet, fresh begin/complete, old batch preserved |
| H | H/retry, sequence3 | Result→exact selected owned size→read-back→new comparison |
| 1 | sequence1 | Register/read/async edit/read/delete/read in one identity-preserving chain |
| 2 | sequence2 + mounted | Size→other Closet→size; actual Result disappears/remounts, no physical taps |
| 3 | sequence3 | Registered receipt becomes next selected candidate, not unrelated fixture substitution |
| 4 | sequence4.async | Edited50→56 read-back supplies comparison ref56/target57 |
| 5 | 5 + F; new History oracle | Existing disk reopen tuple/reliability and alternative restoration; numeric persisted bridge new |
| 6 | C/6 | Hide+delete with immutable synthetic remote evidence retained |
| 7 | 7 + F-stale | A→B→late A plus account switch; third new A submission not claimed |
| 8 | duplicate/8 | Concurrent action tasks; one accepted interaction, not rapid physical taps |
| 9 | committed-response-lost | Fake commit→timeout→exact retry→read-back/local1; actual DB deduplication untested |
| 10 | empty-closet/no-common/no-size | Fail closed without implicit candidate or invented size; valid retry recovers |

## Required fault boundaries

All seven explicit transport cases (offline/403/429/500/timeout/malformed/cancelled) reach real DomainClient + SDK + intercepted URLSession across six mutation RPCs. Save additionally checks fresh local state, unrelated row and exact retry JSON; delete additionally checks retained intent and commit0. Actual Task.cancel has three existing owner probes (four runs including the link noncancel control). Delayed generation/account replies and fake commit-before-lost-response have separate probes. See JSON for exact selectors.

This satisfies the required *prepared boundary mapping*. It does not claim every fault was combined with every UI surface, callback, account change and app restart. Such a Cartesian campaign was not part of the original preparation request. Existing limitations remain explicit evidence boundaries rather than automatically becoming new mandatory tests.

## One genuine preparation addition

The previous D oracle stopped at completion payload. Existing disk History reopen asserted tuple/reliability; F reconstructed expected persisted values with the production engine. Neither established independent literal numerical persistence. The added test supplies literal schema4/v2 completed JSON, then calls the production hydrator, saves disk state, edits the active Closet, and opens a new ModelContainer.

Expected values are independently fixed: chest ref50/target52, signed+2/absolute2, score90, reliability1, coverage1, one History and two UserFit projections (active + immutable History reference). It checks exact recommended/ref projection identities, unchanged whole History envelope, original History ref50 after active chest61, and preserved active memo. It uses no engine to generate expected values. This characterizes existing score behavior and leaves formula/rounding/tie product approval **UNRESOLVED**.

No other new harness, fault×screen matrix, credentials collection, actual DB campaign, or product fix is needed to make this scoped addition reviewable. Actual execution results must be recorded by the root; this author ran no Xcode or remote request.

## Policy and count basis

AGENTS Persistence/Architecture; MeasurementPolicy3 (exact selected identity/raw facts/authoritative read-back), 4.3 (server-approved evidence, weights/confidence), 5 (immutable history). Current behavior characterization is labeled separately from independent product approval. Captured raw replay sizes/facts remain U8/32, M4/24, Z4/20; source, display, canonical, policy and common-approved counts are distinct. Authenticated DB count verification remains later execution work, not a missing local fixture invention.
