# Comparison performance implementation

## 2026-09-24 개발 DB 적용 완료 — 이전 승인 차단 해소

- 사용자가 exact 개발 프로젝트 migration 적용 요청에 “승인한다”로 명시 승인하여 `hnkplvyegonlhumlejst`에 `selected_comparison_candidate`를 apply_migration으로 적용했다. 성공 응답 및 migration ledger 확인: remote version `20260924045025`; 로컬 파일 `supabase/migrations/20260924130000_selected_comparison_candidate.sql`과 대응한다. 과거 승인 차단 기록은 이 상태로 대체되며 이력은 보존한다.
- READ ONLY postflight PASS: 신규 endpoint 존재, authenticated 실행 허용, anon 차단, mapped/session private helper 직접 실행 차단(5/5 true). eligible_candidate_sizes 2개, authorize_comparison_with_context 2개, begin_comparison, complete_comparison 총 6개 정의 hash 모두 적용 전과 동일.
- 이번 승인 후 앱 코드 추가 변경/테스트 재실행 없음. 직전 동일 변경의 전체 Swift 결과는 870 PASS / 0 FAIL / 42 skipped, 격리 SQL parity/role/rollback PASS. 배포 후 실제 인증 사용자 비교 E2E 및 실기기 속도 측정은 NOT RUN.
- 사용자 상품·옷장·비교 row 변경 없음. 함수/권한 및 migration ledger만 변경. 앱 성능 경로를 사용하려면 최신 로컬 소스로 빌드 필요. commit/push 없음.


Scope: preserve groups, exact identity, raw facts, scores, final begin/complete and existing dirty work. No commit/push.

1. Selected candidate: share deployed candidate implementation behind optional exact Closet filter; existing list APIs unchanged. New authenticated selected-pair API uses same checks, evaluating only selected row. Keep eligible and begin revalidation: eliminating their stale-check boundary would need a wider contract change.
2. Current result other-clothes: return to current flow's existing candidate display without retailer reingestion; selection still revalidates current Closet and selected pair. Historical recompare unchanged. Clear selected state and retain account/request guards.
3. Initial candidate handoff: use already validated target only for first plan of that load; no persistent/global cache. Subsequent refresh resolves current authority. Keep live server candidate validation.

Verification: deterministic SQL selected/full JSON parity, owner/deleted/missing/group/context; coordinator request routing/reuse/cancellation tests; existing whole Swift suite; final independent review. Device timing is NOT RUN.

Ruling: retain explicit eligible → begin stale/fingerprint boundary. Optimize the all-candidates scan instead of weakening final validation; exact result preservation is higher priority than removing every RPC.

Progress: baseline HEAD 3243e980; existing dirty work retained. No implementation yet.

Step 1 verified locally: coordinator RED 41/42 (selectedCandidateIDs), GREEN 42/42 exit0. SQL RED exact candidate differs, GREEN selected/full JSON parity + rollback exit0. Migrations not yet applied remotely. Preserve explicit eligible and begin.

Step 2: wiring RED 4 PASS/1 FAIL → GREEN 5/5 exit0. Current result uses the same existing comparison-summary callback as the current list button, clears selected item. No new view model/observation. Historical result fallback unchanged. This is source-wiring verification, not device UI verification.
Ruling: reuse the existing session candidate display without a background full-list refresh, matching the existing comparison-list button; chosen pair is freshly checked on every selection. A remote Closet change may remain invisible until refresh/selection, but cannot bypass final validation.
Step 3 GREEN 44/44 exit0. Added actual ViewModel handoff failure/retry/cancel test: PASS in initial whole-suite run. Independent review: no confirmed Important/Critical issues; SQL authenticated/anon role execution subsequently PASS.
Whole suite initially 866 PASS / 4 FAIL /42 skipped: old first-candidate resolve expectation and shifted CP034 runtime queue. Updated dependency checks to retain fresh selected-pair validation and fixed response schedule, without weakening block/history assertions. Whole suite rerun pending.
Final whole suite: 870 PASS /0 FAIL /42 skipped, exit0. SQL roles/rollback PASS. Scoped independent review no Important/Critical findings. Final diff/protected-scroll PASS.
Deployment BLOCKED: same apply_migration action rejected twice by auto-review citing prior read-only/DB-Edge prohibition and insufficient environment authorization. No workaround. Exact current dev migration approval requested asynchronously. Do not mark live deployment complete; new app endpoint requires migration first. Commit/push not performed.
