# FitMatch 최신 누적 인수인계서

## 2026-08-31 HJ-P0-001 USER_EXPLICIT completed Result/History remediation — PASS

- Work ran on `connectDB` at local/fetched `origin/connectDB` HEAD `8855874a7ff372ef9b0e6159740c6faee4750985`. The pre-existing dirty documentation, Headless matrix/results/defect ledger, simulator artifacts, and test source were preserved. No reset/restore/stash/clean, commit/push, Production access/write, migration, SQL/Edge edit, or test-expectation change occurred.
- The Headless failure was reproduced before the change: J07 (USER_EXPLICIT polo↔tshirt same-sleeve manual), J09 (hoodie↔sweatshirt same-sleeve manual), J11 (knit_sweater↔sweatshirt same-sleeve manual), and J13 (REVIEW_REQUIRED → Recovery → USER_EXPLICIT automatic resume) each reached server `begin_comparison` → production engine → `complete_comparison`, then lost the local completed result/history.
- Root cause was `RecommendationService.makeCompletedVNextHistory(...)`: it required local `product.classificationAuthorityProvenance == .serverConfirmed`, so it returned nil after an otherwise successful current server-backed USER_EXPLICIT run. `ShoppingProductViewModel.completeVNextRecommendation(...)` and the Result persistence path now pass the successful completion DTO into that history builder.
- The replacement gate is deliberately narrower than `serverConfirmed || userExplicit`. It requires an allowed permit, exact run/comparison identity, successful matching completion/recommended size, PENDING vNext begin snapshot, exact target Product/variant/reference UUIDs, exact non-duplicated authorized candidate UUID set, authority fingerprints, and current runtime effective-tuple equality. USER_EXPLICIT additionally requires V4, a current active personal projection, exact revision, candidate fingerprint/set hash, input/evidence fingerprints, resolver version, and `USER_EXPLICIT` effective source. Snapshot reference UUID comparison parses UUIDs rather than depending on PostgreSQL/Foundation string case. A local/manual, stale, cleared, wrong-target, wrong-reference, wrong-run, stale candidate/hash/input/evidence/revision, or unauthorized-size USER_EXPLICIT path returns nil.
- `RecommendationResultView` now reuses only the current already-calculated authorized batch for alternate-size presentation. It permits a completed server-backed USER_EXPLICIT result only with the exact server-history/current-batch evidence; absent/stale/local batches cannot invoke a fresh scorer.
- Post-fix Headless suite PASS `5/5`, including all canonical `45/45` valid scenarios, `45` executed, `45 PASS`, `0 FAIL`, `0 unexecuted`. J07/J09/J11/J13 each now execute `effective authority → reference/eligible → begin → MeasurementComparisonEngine → complete → local Result/History` successfully. The direct server-proof regression also verifies valid USER_EXPLICIT alternate-size presentation and all required negative cases.
- Critical regression suites PASS `64/64`, fail/skip `0/0`: Recovery, vNext contract, permit sequencing, comparison sync, server-authority integration, and Supabase resolver. App build PASS and test-target build-for-testing PASS on Xcode 26.3/iPhone 17 Pro Simulator iOS 26.3.1.
- Full `FitMatchTests` completed at `513 PASS / 1 FAIL / 37 SKIP` (551 total). The one failing test remains the known legacy `DBLogicReliabilityAuditTests.testDBLogicAdjudicationMatchesProductionClassifier` corpus (64 assertions); no HJ-P0-001-related failure or expected-value edit was introduced.
- Static gates PASS: `git diff --check`; TabBar modifier/protected scroll call-site diff `0`; DB/migration/Edge/Share/SwiftData/navigation source diff `0`. Production writes are `0`; P0 from HJ-P0-001 is `0` locally. Physical iPhone signed-in USER_EXPLICIT select/reselect/clear and real Production comparison E2E remain unverified.
- Current verdict: `HJ-P0-001 REMEDIATION PASS`. Next step: independent Codex Ultra PRE-E2E re-audit, followed only by the already-scoped signed-in physical iPhone Recovery E2E if that audit remains P0-free.

## 2026-08-31 Recovery Production Simulator E2E — PARTIAL (authenticated execution blocked)

- Git authority is `connectDB` / local and fetched `origin/connectDB` `8855874a7ff372ef9b0e6159740c6faee4750985`. Tracked source was clean; the prior untracked postflight ZIP was preserved. No Swift, migration, SQL, test, Edge, project, or configuration source was modified.
- Xcode 26.3 current-source app build PASS (268.5s), test-target build-for-testing PASS (218.7s), focused Recovery/vNext suites PASS `88/88`, fail/skip 0. Actual current Debug app was installed and launched on iPhone 17 Pro Simulator/iOS 26.3.
- Real UI reached “Continue with Apple”. Tapping it produced the system “Apple 계정에 로그인 — 설정에서 Apple 계정에 로그인해야 합니다.” alert. It was closed without Settings/credentials. App termination and cold relaunch returned to the same real auth gate. Screenshots/logs are in `Docs/TestEvidence/RecoverySimulatorProductionE2E-20260831/`.
- All checked local Simulator Supabase Keychains contained 0 FitMatch sessions; no approved QA credential/JWT exists in repo/docs/config, and the execution Simulator has no Apple account. Fake `-fitmatchUITesting` auth was not used because it disables Production Supabase, and no Auth user was created. Therefore USER_EXPLICIT select/relaunch/reselect/clear, negative UI, manual-cross, scorer timestamps, and multi-Simulator sync are NOT RUN rather than PASS.
- Production SELECT-only target discovery selected primary UNIQLO E450259/옥스포드셔츠 (`bf835b1d-f245-4248-861d-3c97020f6fb7`), REVIEW_REQUIRED MEN/SINGLE, exactly 3 candidates: shirt_blouse long, shirt_blouse short, polo_shirt short; fixed MEN/tops/SINGLE and unknown garment+sleeve. Backups are E482514 (2 candidates) and E467574 (1); negatives E482868 (0), E422992 (UNKNOWN), E482652 (NOT_APPLICABLE).
- All selected products have availability observations/current sizes `0/0`; after Recovery this may legitimately stop at temporal NO_AVAILABLE_SIZE. No availability refresh occurred. Post-attempt Production rows are override 0, feedback 0, comparisons 0, and primary remains global REVIEW_REQUIRED/null garment. Normal app writes 0; admin/global Production writes 0.
- Final verdict is `SIMULATOR PRODUCTION E2E PARTIAL`, P0 found 0 but authenticated functional gates remain unverified. Exact unblocker is one approved existing QA Apple-authenticated Simulator session (credentials must not be put in chat and no new Production user should be invented), followed by autonomous select→cold relaunch→reselect→clear and negative/multi-Simulator execution. Full report: `Docs/FitMatchRecoverySimulatorProductionE2E-20260831.txt`.

## 2026-08-31 REVIEW_REQUIRED Recovery Production postflight — PASS

- Strict Production READ-ONLY postflight completed against `hnkplvyegonlhumlejst`; this audit performed Production writes 0. Branch/local HEAD/fetched `origin/connectDB` are `connectDB` / `2aa7c792f45384b08ca1f55f247c1c6fd0ed516a` / identical. Migration SHA-256 remains 90000 `aabce9afd186fdae6de1f7f52ef5ef2e33fcbcdf1d25b0ca1c94bf94745f3a21`, 91000 `2687da317e5ac7d51ca9942bb7441987179e36f4f6a8949a4470f6fc2d31dcd8`.
- Production ledger contains exactly `20260830090000/vnext_leaf_specificity_correction` and `20260830091000/vnext_review_required_recovery`, once each, with no replacement/duplicate Recovery migration.
- Current Production is Products 1,608; `CONFIRMED 346 / REVIEW_REQUIRED 1,165 / NOT_APPLICABLE 97`; invalid CONFIRMED, duplicate Product, variant/size/measurement orphan are all 0. Leaf-specificity remediation audit proves exactly 143 intended REVIEW_REQUIRED→CONFIRMED, unexpected transition 0, hierarchy evidence missing 0, selected mapping mismatch 0, and all 143 remain valid CONFIRMED.
- Fresh resolver review reasons are non-SINGLE structure 424, product-exact verified evidence required 389, and no active verified mapping 352; the old false equal-top descendant/ancestor group is 0. The correction uses recursive `parent_signal_id`, not product name/path prefix/evidence_order specificity.
- Recovery envelope for the 389 PRODUCT_REQUIRED cases is candidates `0=270 / 1=7 / 2=5 / 3=107 / >3=0`, recoverable 119, unrecoverable 270, invalid/inactive garment/inactive policy candidates 0, and 47-type fallback 0. UNKNOWN/non-SINGLE review remains blocked (424).
- Both Recovery tables exist with RLS, owned SELECT, no authenticated direct writes, append-only feedback trigger, USER_EXPLICIT/revision/fingerprint/hash/cleared lifecycle constraints, and no Closet dependency. Current override/feedback rows are `0/0`. Recovery user RPCs have no PUBLIC/anon EXECUTE, SECURITY DEFINER search paths are fixed, raw tuple authority is impossible, and no BOLA/IDOR was found.
- Effective authority is Global NOT_APPLICABLE block → Global CONFIRMED → valid active owned USER_EXPLICIT only while global REVIEW_REQUIRED → REVIEW_REQUIRED. `cleared_at is null` excludes cleared rows from current authority and superseded reconciliation. Set/reselect/clear are optimistic-concurrency and server-candidate based; Global Product auto-promotion path is 0.
- Effective-context measurements feed readiness/reference/authorization/eligible sizes/begin. Manual-cross remains exact three active same-sleeve rules and explicit-only. Begin recomputes exact candidates/staleness and emits snapshot v4; Swift release flow reaches `MeasurementComparisonEngine` only from a valid begin permit and completes server-side before local History. Production comparisons/completed rows are `0/0`, so old-row mutation is 0 and physical mutation behavior remains unverified.
- Readiness is `READY 0 / NO_AVAILABLE_SIZE 344 / NO_MEASUREMENT_DATA 2 / CLASSIFICATION_REQUIRED 1,165 / NOT_APPLICABLE 97`. READY 0 is a temporal expired-availability state, not repaired or labeled PASS. Edge remains product-observation v5 with `verify_jwt=true`; Auth/Edge/Storage changes 0. Protected SwiftData/navigation/Share/TabBar diffs are 0.
- Final verdict: `PRODUCTION POSTFLIGHT PASS`, remaining P0 0. P1 operational gates are physical signed-in USER_EXPLICIT Recovery, multi-device/restart/reselect/clear E2E, and fresh retailer availability before re-observing Golden readiness. Exact next step: physical signed-in iPhone Recovery E2E → targeted multi-device/restart E2E → final PRE-E2E/release audit. Full report: `Docs/FitMatchReviewRequiredRecoveryProductionPostflight-20260830.txt`.

## 2026-08-30 REVIEW_REQUIRED Recovery Production deployment — Git/dry-run PASS, apply BLOCKED

- This section supersedes the immediately following earlier Git-authority BLOCKED attempt. Fresh fetch confirmed local `connectDB`, local HEAD, and `origin/connectDB` are all `fb3dde5252c8f50733491d9e90a44d35c452c6f9`; the checkout was clean before report generation, conflict paths were 0, and all Recovery Swift/UX/tests/validation/handoff artifacts are now published.
- Git-authoritative migration SHA-256 values exactly match the reviewed sources: 90000 `aabce9afd186fdae6de1f7f52ef5ef2e33fcbcdf1d25b0ca1c94bf94745f3a21`, 91000 `2687da317e5ac7d51ca9942bb7441987179e36f4f6a8949a4470f6fc2d31dcd8`. Existing Recovery UI reuse, no second Recovery screen, reselect/reset strings, and the `cleared_at is null` effective-authority filter are present in remote Git.
- Production SELECT-only preflight at `2026-08-30T12:44:45.873710Z`: Products 1,608; classifications `203 CONFIRMED / 1,308 REVIEW_REQUIRED / 97 NOT_APPLICABLE`; invalid CONFIRMED/duplicate Product/variant-size-measurement orphans all 0; active garment/policy 47/39; readiness `READY 0 / NO_AVAILABLE_SIZE 201 / NO_MEASUREMENT_DATA 2 / CLASSIFICATION_REQUIRED 1,308 / NOT_APPLICABLE 97`. READY 0 is natural expired availability and was not repaired.
- Manual-cross remains exactly hoodie↔sweatshirt, knit_sweater↔sweatshirt, polo_shirt↔tshirt, all active and `require_same_sleeve=true`; authorization-v3 marker is present. Target migration ledger rows and Recovery tables/functions are all absent.
- Production set-based SELECT-only 90000 dry-run PASS: exactly 143 REVIEW_REQUIRED→CONFIRMED, projected `346/1,165/97`; existing CONFIRMED status/tuple changes 0, NOT_APPLICABLE changes 0, invalid new tuple 0, unsafe hierarchy rows 0, unexpected transition 0. Exact 143-row evidence is `Docs/FitMatchReviewRequiredRecoveryProductionPreflight-20260830.jsonl`, 144 lines / 201,520 bytes, SHA-256 `c9ce23dcf75abb08c3d1bbcacd66941399cd390392f2b4a218d412adbb343b8f`.
- Deployment stopped immediately before the first write. The available authenticated Supabase migration connector does not accept a caller-supplied version and has previously recorded an execution-time version on this project. The official Supabase CLI is not installed/linked/authenticated here. Applying through the connector would knowingly violate the owner-required exact ledger versions `20260830090000/20260830091000`; manual SQL/ledger insertion, repair, fake marking, and ad-hoc write were not used.
- Stop-state SELECT-only postflight at `2026-08-30T12:51:48.474257Z` exactly matches preflight: products/classifications/counts and Product/variant/size/measurement/comparison hashes unchanged, target ledger 0, Recovery objects absent. 90000/91000 apply count `0/0`, every Production write class 0, partial deployment 0.
- Current verdict is `BLOCKED`. Exact next step is an authenticated project-linked official Supabase CLI environment: run `supabase db push --dry-run`, require exactly 90000 and 91000 pending and nothing else, then `supabase db push` followed by the full postflight. Physical signed-in, multi-device, restart/reselect/clear E2E and fresh Golden availability remain unverified.

## 2026-08-30 REVIEW_REQUIRED Recovery Production deployment — BLOCKED at Git authority gate

- Controlled Production deployment preflight ran on branch `connectDB`. Local HEAD and freshly fetched `origin/connectDB` are both `b419f159962e1447ae2981be3747436117d7faef`; unresolved merge/conflict paths are 0 and the existing dirty working tree was preserved.
- The mandatory Git-authority gate failed. `supabase/migrations/20260830090000_vnext_leaf_specificity_correction.sql` and `supabase/migrations/20260830091000_vnext_review_required_recovery.sql` exist only as local untracked files and are absent from `origin/connectDB`. Their local SHA-256 values are respectively `aabce9afd186fdae6de1f7f52ef5ef2e33fcbcdf1d25b0ca1c94bf94745f3a21` and `2687da317e5ac7d51ca9942bb7441987179e36f4f6a8949a4470f6fc2d31dcd8`.
- The focused Recovery test is also untracked/absent remotely, and the final Recovery DTO/service/coordinator/ViewModel/CompareFlow/Result changes differ from the remote commit. Therefore the reviewed implementation and final reselect/reset/cleared-override patch are not yet published to Git authority.
- Per the owner’s absolute safety rule, execution stopped before any Production connection. Production SELECT/introspection, 90000 dry-run, migration apply, ledger write, security postflight, and Recovery distribution checks were all NOT RUN. Migration 90000/91000 apply count is `0/0`; every Production write class is 0 and there is no partial deployment.
- Local work for this stopped attempt is limited to `Docs/FitMatchReviewRequiredRecoveryProductionDeployment-20260830.txt`, this handoff entry, and the companion ZIP. Swift, migration, validation SQL, Edge, and Production source were not modified by this deployment attempt.
- Final verdict is `BLOCKED`, not PARTIAL: no approved migration was applied. Exact next action is to publish the complete reviewed Recovery implementation, exact migrations/validation/tests, final UX patch, reports, and current handoff to `origin/connectDB`, then rerun the controlled deployment from an authoritative checkout. This task performed no commit or push.

## 2026-08-26 Classification Authority Phase 1B-2 — Candidate Data + 1,608 Shadow PASS

> 이 절이 아래 Phase 1B-1/1B-1V의 “다음 Phase” 상태를 대체한다. Phase 1B-2 repository/local artifact는 GO지만 Production activation은 NO-GO다.

### 결론과 산출물

- Branch/HEAD는 `connectDB` / `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab`이며 commit/push는 하지 않았다.
- Migration `supabase/migrations/116_classification_candidate_release.sql`, validation `supabase/sql/116_classification_candidate_release_validation.sql`, local fixture `supabase/sql/116_classification_candidate_release_local_fixture.sql`을 추가했다.
- Exact machine input은 `supabase/sql/fixtures/116_classification_candidate_manifest.jsonl` 4,644 rows, SHA-256 `f542025c3cd84a4b785903e746b276f4f07ad1b9152d2c4c0301e4983d6d66ea`다.
- Shadow는 `Docs/FitMatchClassificationPhase1B2Shadow-20260826.jsonl` 1,608 rows, SHA-256 `b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385`다.
- 전체 보고서는 `Docs/FitMatchClassificationPhase1B2Candidate-20260826.md`다.

### Candidate contract

- Local candidate release ID/key는 `9f9c8155-61d9-41ce-9dd1-bf695ecc2140` / `fitmatch-classification-authority-candidate-2026-08-26-v1`, parent는 Production active `65d72393-4a40-4e99-b701-fdc1ff865774`다.
- Active mapping 3,492 exact successor는 CATEGORY_DIRECT 34 / PRODUCT_REQUIRED 989 / INVALID_MAPPING 369 / OTHER_EXISTING 2,100이다. Identity loss/overlap 0, direct tuple invalid 0이다.
- Decision manifest 114는 verified 113 + revoked ZARA 1이다. Production/non-transactional decision write는 0이다. Gold E482514/E454311/E456567은 3/3 exact, collision 0이다.
- Review issue 1,037은 existing `data_quality_issues` contract로 적재한다. 일괄 product decision/history downgrade는 하지 않았다. Shadow에서 1,009 review, verified direct mapping 근거가 있는 28 confirmed이며 review issue는 유지한다.
- BOTH_UNTRUSTED original 310 중 owner Gold E482514 1만 exact verified로 해소되고, 나머지 309는 review_required다. Untrusted authority path unsafe confirm은 0이다.
- Phase 1A.5의 E450536/E486066 `knit_top`은 candidate validation 값이었으나 current taxonomy에서 inactive/missing detail이라 115 validator가 차단했다. Verified tuple은 validator-valid `knit_sweater/knit_sweater/knit_sweater/long_sleeve`로 고정했고 independent expected는 수정하지 않았다.

### Runtime gate와 local validation

- Runtime versions는 classifier `db-auto-classifier-2026-08-18-v2`, comparison `v1`, compatibility `db-comparison-2026-08-18-v2`, measurement `2026.07.1`로 분리 고정한다.
- Policy row/checksum, `runtime_policy_contract_validated`, mapping/decision/review parity, shadow/Gold/fail-closed evidence를 114 gate에 additive로 확장했다. 기존 114 blocker는 제거하지 않았다.
- Homebrew PostgreSQL 17.11, cluster `/tmp/FitMatchPostgres17-20260826-01`, port 55432에서 production-shaped non-user fixture→113→114→115→116 actual apply PASS(4.06s)다.
- Validation transaction은 manifest/SQL parity, field/row/checksum/flag negative gates, negative trigger, exact decision upsert, positive gate/activation, recorder append/supersede를 실행하고 ROLLBACK했다.
- 116 reapply는 insert 0/0/0, 0.33s PASS다. Reapply 후 validation output은 1차와 byte-identical이다.
- Post-rollback local state는 products 1,608, decisions 5,056, history 0, parent active, candidate validated, candidate decision exact matches 0이다. Trigger/FK/service grant PASS, anon gate execute false다.
- 검증 후 local server를 중지하고 cluster와 temporary support symlink를 삭제했다. `brew services start`, port 5432, 추가 설치, user/auth/closet/comparison-history copy는 0이다.

### Shadow 결과와 다음 gate

- Status는 confirmed 177 / review_required 1,431 / not_comparable 0 / unclassified 0이다. Method는 verified decision 113 / verified category mapping 64 / unknown 1,431이다.
- Current transition은 confirmed→confirmed 172, confirmed→review 934, notComparable→review 169, review→confirmed 5, review→review 328이다.
- Confirmed invalid tuple, product-required-alone confirm, invalid-mapping-alone confirm, BOTH_UNTRUSTED unsafe confirm, unknown arbitrary fallback, generic underwear leak, tshirt/base-layer leak은 모두 0이다.
- Independent expected 207은 수정 0. Current overlap 137의 literal exact/mismatch/review는 16/121/27이다. 기존 31 failure corpus는 overlap 28 + current-missing 3이며 전부 Phase 2 대상이다. DB target 5는 confirmed verified지만 legacy/canonical vocabulary 때문에 literal exact 2, mismatch 3을 그대로 기록했다.
- Production postflight는 products 1,608, decisions 5,056, history/current 1,860/1,608, active mapping 3,492, candidate release 0, latest ledger `20260821090138`다. Production write/apply/temp/RPC mutation/activation/history change 0, Swift production diff 0이다.
- 다음 정확한 단계는 `Phase 1B-3 — Controlled Activation Transaction + Rollback Successor Dry Run (Local/Staging Only, Production Apply 0)`이다. Exact 114-row preimage, v2 gate rollback successor, v4/v2/evaluator call-site switch를 한 transaction의 cutover/rollback으로 검증한다. Production apply/activation, history backfill, Phase 2 Swift는 자동 시작하지 않는다.

## 2026-08-26 Migration 115 Final Correction — Local Runtime PASS

> 이 절이 아래 Phase 1B-1V 절의 policy-version contract를 대체하는 최신 권위 상태다.

### 결론

- **Phase 1B-2 candidate-data 작업은 GO, production migration/activation은 NO-GO**다. Phase 1B-2를 자동 시작하지 않았다.
- 지정된 두 결함만 수정했다. Resolver v4의 raw `p_payload.classifier_policy_version` override는 완전히 제거됐고 classifier version은 selected release contract만 사용한다.
- Evaluator v4는 `comparison_policy_version`, `compatibility_rule_version`, `measurement_policy_version`을 분리한다. 이전 단일 `compatibility_policy_version` shadow key/lookup은 제거했다.
- Production SELECT-only vocabulary는 classifier `db-auto-classifier-2026-08-18-v2`, comparison policy `v1`, current compatibility rule `db-comparison-2026-08-18-v2`, measurement `2026.07.1`로 서로 다름을 재확인했다.
- 보고서: `Docs/FitMatchClassificationPhase1B1Validation-20260825.md`.
- Final SHA256: migration 115 `1d09dcde02a2d1728322b2bcb5b1eb567f4918ecbd9936f386a817f5d0a1e799`; validation `06a54982540da4b6ffa8f3ea05ffe1e662072bb3e8cf40e90b06c3ace230d0e4`; fixture `2830bea1fe32018b04b55a53a647707ac6677a3e9a82f461e5b62bd114d66980`.

### Contract와 fixture

- Runtime policy contract는 classifier/comparison-policy/compatibility-rule/measurement 네 field다.
- Missing contract/row reason은 `runtime_policy_contract_missing`, `comparison_policy_version_missing`, `compatibility_rule_version_missing`, `measurement_policy_version_missing`으로 구분한다.
- Fixture vocabulary는 classifier `classifier-v1`, comparison `comparison-policy-v1`, rule `compatibility-rule-v1`/wrong `compatibility-rule-wrong`, measurement `measure-v1`/wrong `measure-v2`다.
- Payload spoof assertion: selected release `classifier-v2`에 raw payload `classifier-v1`을 넣어도 result는 review, returned version은 `classifier-v2`, source는 release contract였다. Spoof-confirmed 0이다.
- Good comparison/rule version pair, missing comparison, missing rule, missing measurement, wrong-row non-use, multiple measurement-version non-mixing을 모두 runtime assertion으로 고정했다.

### Local actual validation

- PostgreSQL `17.11 (Homebrew)` formula binaries만 사용했다. Cluster `/tmp/FitMatchPostgres17-20260826-072435`, port `55432`, Unix socket only였다. `brew services start`, port 5432, cloud preview branch, 추가 설치는 사용하지 않았다.
- Fixture `0.11s`, 113 `0.04s`, 114 `0.03s`, corrected 115 initial apply `0.04s` PASS.
- Validation은 두 번 explicit `ROLLBACK` PASS(`0.10s`, `0.09s`), current exact-file 115 reapply `0.04s` PASS다.
- 114 gate/trigger/view/grants 및 115 four functions/CHECK/FK/recorder/evaluator 실제 compile/runtime PASS다.
- Post-rollback counts는 `1/1/1/1/1/0/0/0`, old internal/public eight-function hash는 pre/post `dc9e989eb233b066d6c7a973b57e9010`으로 동일했다.
- service_role foundation grants 4/4, anon/authenticated grants 0/8, evaluator 16-arg overload 1, duplicate object 0, waiting lock 0이다.
- 검증 후 local server를 stop하고 cluster root와 temporary formula support symlink를 삭제했다.

### Production unchanged와 다음 gate

- Final production SELECT-only counts: products 1,608, decisions 5,056, history/current 1,860/1,608, measurements 28,418, active release 1. Latest ledger는 `20260821090138`다.
- Production 114/115 columns/functions는 계속 absent이고 existing eight-function combined hash는 `0551eee819d6ae2db5ccd40c0f66a275`다. Production DDL/DML/RPC write/apply/temp object 0이다.
- Production activation 전에 gate가 네 runtime policy field 존재, 각 required row/checksum, `runtime_policy_contract_validated=true` 또는 동등 evidence를 검증해야 한다. Migration 114는 이번에 수정하지 않았다.
- Candidate 작업에서도 BOTH_UNTRUSTED 310, manual review 1,037, invalid replacement 미확정, live network 71을 자동 confirmed로 올리지 않는다.
- 다음 작업은 사용자 별도 명령이 있을 때만 Phase 1B-2 candidate release/data migration 작성 및 local-only validation이다. Production apply/activation, history backfill, public RPC/iOS 전환은 자동 시작하지 않는다.

## 2026-08-26 Classification Authority Phase 1B-1V — Final Contract + Local Runtime PASS

### 결론

- **Phase 1B-2 candidate-data 작업은 GO, production migration/activation은 아직 NO-GO**다. Phase 1B-2를 자동 시작하지 않았다.
- PostgreSQL 17.11 Homebrew formula 전용 binary로 `/tmp/FitMatchPostgres17-20260826-035209`, port `55432` disposable cluster를 사용했다. `brew services start`, port 5432, existing libpq 18 client는 사용하지 않았다.
- Production DB는 SELECT/introspection only다. 종료 postflight는 products 1,608, decisions 5,056, history/current 1,860/1,608, measurements 28,418, active release 1이며 114/115 objects는 계속 absent다. Production write/apply/release/history 변경 0이다.
- 보고서: `Docs/FitMatchClassificationPhase1B1Validation-20260825.md`.
- Final SHA256: migration 115 `b4464bca6549c76f794a8d7eee522f68ada012fdf47070fefd53e30bed8f5bbd`; validation `2627dde9fdf29e38a6be838f4727ce7870654df14e9b07b31ea5ae2fb64b260d`; local fixture `7b82e5dfcb7492cb28c0e003247354dd0bd9d3704a3f5885690d5b3ec393068b`.

### Contract correction

- Resolver v4 classifier version은 trusted payload override -> selected release `validation_report.runtime_policy_contract.classifier_policy_version` 순서다. `release.policy_version` fallback을 제거했다. Missing version은 name/path/exclusion을 사용하지 않고 evidence에 남긴다.
- Evaluator v4 최종 signature는 기존 15 arguments 뒤 `p_release_id uuid default null`을 추가한 16 arguments다. Compatibility/measurement versions는 selected release contract에 exact pin된다.
- Hard-coded compatibility version과 multi-version measurement aggregation을 제거했다.
- `allowed`, `fallback_allowed`, `length_match_required`, mismatch exclusions, minimum/required/required-any/weights, directional, policy version을 모두 사용한다. Tshirt/base-layer explicit block과 dresses/underwear/homewear fail-close는 유지한다.
- Verified direct/profile과 conflicting legacy decision은 계속 review다.

### Local actual validation

- Synthetic production-shaped fixture: `supabase/sql/115_authoritative_classification_foundation_local_fixture.sql`. Production/user/auth/closet/comparison-history data copy 0이다.
- 113 apply/compile PASS (`0.04s`), 114 PASS (`0.03s`), 115 PASS (`0.04s`).
- 114 signature issue/triage/view, release gate trigger deny/allow, grants runtime PASS.
- 115 tuple/resolver/recorder/evaluator, CHECK/FK RESTRICT, service-only grants runtime PASS.
- Validation은 두 차례 `BEGIN ... ROLLBACK` PASS (`0.09s`), post-rollback counts/hash 불변.
- Final 115 reapply PASS (`0.05s`), duplicate columns/constraints/functions/triggers 0. Evaluator v4 16-arg overload 1, old 15-arg overload 0.
- Waiting locks 0. Synthetic one-row EXPLAIN만으로 garment FK child index 필요성이 입증되지 않아 index 추가 0이다.
- Cluster와 temporary Homebrew share/lib support symlink는 검증 종료 후 제거했다.

### 다음 작업 제한

- 다음 명령은 Phase 1B-2 candidate release/data migration을 작성하고 동일 local 방식으로 검증하는 것이다.
- Candidate release에 classifier/compatibility/measurement 세 runtime policy version을 명시한다.
- Active release mutation/activation, production apply, history backfill, Swift production 변경은 별도 승인 전 금지다.
- BOTH_UNTRUSTED 310, manual review 1,037, invalid replacement 미확정, live network 71은 자동 확정하지 않는다.
- Foundation의 exact activation map을 그대로 사용하며 v5/parallel resolver/evaluator를 만들지 않는다.

## 2026-08-25 Classification Authority Phase 1B-1 — DB Foundation & Shadow Contract

### 결론과 산출물

- **Repository-level Phase 1B-1 foundation은 구현 완료, Phase 1B-2 실행 gate는 현재 NO-GO**다. 안전한 local/staging DB에서 113 -> 114 -> 115 actual apply와 validation SQL을 실행하지 못한 것이 단일 foundation 검증 blocker다.
- Migration: `supabase/migrations/115_authoritative_classification_foundation.sql`; SHA256 `d782e98d03320e99feb9ccfa6ac4125a988ea012093be3d2a5d4f9cafec8d072`.
- Validation: `supabase/sql/115_authoritative_classification_foundation_validation.sql`; SHA256 `25da75261eb51592b1f76adff11403e30ee02bb6c5a85d7cd1e4f6133c8da19a`.
- 보고서: `Docs/FitMatchClassificationPhase1B1Foundation-20260825.md`.
- 시작/종료 branch/HEAD는 `connectDB` / `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab`다.
- Production DB에는 SELECT/introspection만 사용했다. DB write 0, migration apply 0, active release/history change 0, Swift production 수정 0이다. Phase 1B-2를 시작하지 않았다.

### Migration 114와 production 상태

- Repository의 `114_release_gate_and_quality_review_queue.sql`을 수정하거나 115에서 중복 정의하지 않았다.
- Production ledger latest는 `20260821090138`이며 local 113/114/115는 미적용이다. 114 gate functions/view/columns도 production에 없다. 기존 single-active index만 pre-114 object로 존재한다.
- Repository numeric migration과 production timestamp ledger version은 동일하지 않다. Numeric 113–115는 latest timestamp보다 정렬상 과거이므로 일반 `db push`가 자동으로 순서 적용한다고 가정하지 말고 preview에서 controlled apply와 ledger reconciliation을 검증해야 한다.
- 115는 114 functions/view와 trusted grant boundary를 hard prerequisite로 검사한다. 114 view가 113 columns를 사용하므로 apply 순서는 113 -> 114 -> 115다.
- Supabase CLI, container runtime, local PostgreSQL server, preview branch가 없고 repository migration이 080부터 시작해 pre-080 production baseline schema도 포함하지 않으므로 실제 fresh apply는 SKIP했다. PostgreSQL static parser에서는 113/114/115/validation top-level SQL과 115/validation PL/pgSQL이 PASS했다. 114 trigger function 보조 parse는 `NEW`/`OLD` record에 대한 parser JSON serializer 한계로 actual DB compile 검증에 남겼다.

### 115 final candidate contract

- `product_classification_decisions`: nullable `garment_type_code`, non-null default `authority_status='legacy'`, authority/verified-completeness checks, safe nullable FK를 추가한다. Existing 5,056 row update는 없다.
- `product_classification_history`: nullable `garment_type_code`만 추가한다. Existing 1,860 row update/current supersede/append는 없다.
- 신규 table 0, DROP/TRUNCATE/data DML 0이다.
- 최종 후보 internal functions:
  - `runtime_validate_classification_tuple_v1`
  - `runtime_resolve_product_classification_v4`
  - `runtime_record_product_classification_v2`
  - `runtime_evaluate_comparison_profiles_v4`
- 모두 PUBLIC/anon/authenticated execute를 revoke하고 service_role만 허용한다. Public preview RPC는 만들지 않았고, existing v2/v3/public RPC caller는 전환하지 않았다.
- Resolver는 verified exact -> verified direct -> independently verified profile -> conflict-free legacy -> verified exclusion -> review 순서다. Current mapping은 새 authority contract가 없으므로 자동 trusted로 승격되지 않는다.
- Evaluator는 tuple/garment/group/measurement policy를 검증하고 tshirt/base-layer를 차단한다. Dresses/underwear/homewear는 policy-ready 전 fail-close다.

### Homewear owner 결정 반영

- 이전 Phase 1A.5의 homewear owner 질문은 이번 사용자 결정으로 해소됐다.
- Option A: display/canonical major `homewear` 유지, future `homewear_top`/`homewear_bottom`/`homewear_set`, Phase 1B auto=false다.
- Tops/bottoms 강제 이동, generic homewear family 자동 비교, 이번 migration taxonomy/policy seed는 모두 하지 않았다.
- Current `garment_types`/`comparison_groups` major CHECK는 dresses/underwear/homewear를 허용하지 않는다. Future seed 전 non-destructive constraint 확장 정책을 별도 승인해야 하며, 승인 전에는 v4가 fail-close한다.

### 검증

- Production validators v1/v2/v3는 SELECT-only PASS, 5,026/5,026 parity mismatch 0이다.
- Local `CategoryValidation5026AuditTests`: 1/1 PASS, input/unique/output 5,026, invalid 0.
- Local `CategoryLive300ShadowAuditTests`: 1/1 PASS, confirmed/review/unclassified 243/29/28, silent conflict 0, strict leak 0.
- 5,026/Live300은 regression/self-consistency 증거이며 Phase 1A.5 semantic error가 해소됐다는 뜻이 아니다.
- Validation SQL은 columns/count/hash, old/new role grant matrix, 114 security, tuple cases, resolver authority cases, recorder rollback, comparison fail-close를 전부 assertion하지만 safe DB가 없어 실제 실행은 SKIP했다.
- 115 idempotency guard static check는 PASS했다: 3 columns `IF NOT EXISTS`, named constraint guards, 4 `CREATE OR REPLACE FUNCTION`, repeat-safe grants/comments. Actual reapply는 staging에서 아직 SKIP이다.
- PostgreSQL best-practices audit에서 nullable garment FK supporting index를 검토했지만 exact columns/functions scope를 넘어 추가하지 않았다. Existing 5,056 garment 값은 모두 NULL이며, staging advisor/EXPLAIN 후 별도 additive index 승인 여부를 결정한다.

### Activation과 다음 작업

- Phase 1B-2는 active 3,492 mapping clone에 direct 34/product-required 989/invalid 369 authority metadata를 연결하고, targeted decision 114에 garment/verified|revoked authority를 채우는 candidate-only 작업이다. BOTH_UNTRUSTED 310과 manual review 1,037은 자동 확정하지 않는다.
- Activation에서는 `runtime_resolve_and_promote_product`와 public resolve/runtime을 v4+recorder v2로, product compatibility/candidate/begin comparison을 evaluator v4로 연결한다. v5/parallel algorithm은 계획하지 않는다.
- Phase 2 Swift는 `FitMatchSupabaseProductResolver`, closet/comparison sync, shopping/compare recommendation call sites가 additive garment/authority/release/tuple/policy fields와 server measurement gate를 소비한다. Local classifier/matcher는 server-confirmed authority가 아니라 offline/UI/manual 보조로 내린다.
- 이번 네 object는 Phase 1B-1 production caller가 의도적으로 0이지만 activation consumer가 전부 지정되어 dead code가 아니다.
- 다음 명령은 pre-080 production baseline schema가 있는 disposable clone/staging에서 113 -> 114 -> 115 apply와 `115_authoritative_classification_foundation_validation.sql` rollback fixture를 실행하는 검증이어야 한다. PASS 전 Phase 1B-2, production push, activation, history backfill은 금지다.

## 2026-08-25 Classification Authority Phase 1A.5 — Root Cause Adjudication

### 결론과 산출물

- **Phase 1B gate는 NO-GO**다. Phase 1B를 시작하지 않았다.
- 보고서: `Docs/FitMatchClassificationPhase1A5Adjudication-20260825.md`.
- machine manifest: `Docs/FitMatchClassificationPhase1A5Adjudication-20260825.jsonl`; 5,700 JSONL rows; SHA256 `029ca5a036ad4884d7735672ad7a9b8ff23a91a0cd5fcd4613430a4a9a3ccecc`.
- 기준은 `connectDB` / `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab`, Supabase `hnkplvyegonlhumlejst`다.
- Production DB에는 SELECT만 사용했다. DB write 0, migration apply 0, Swift production 수정 0이다.

### 전수 root cause

- invalid confirmed 952 = category/detail mismatch 167 + required length axis 109 + legacy taxonomy shape 640 + actual product misclassification 4 + conflict를 tuple invalidity에 합친 행 32. Structural tuple error는 920이다.
- stale 1,472 = old mapping release only 201 + old decision only 35 + fingerprint changed 94 + current mapping changed 761 + metadata-only combined stale 381. Stale 원인 기준 metadata-only는 617, re-resolve는 855다.
- conflict 573 = product decision correct 105 + source mapping correct 1 + product-required mixed 72 + source mapping wrong 85 + both untrusted 310.
- risky mapping 1,358 = product-required 989 + structurally invalid 369. Phase 1A invalid semantic 238 외에 current `app_categories` detail/major mismatch 173을 찾았고 overlap 42라 union이 369다.
- 전체 active confirmed mapping 1,392는 category direct 34 / product-required 989 / invalid 369다.
- mixed 59/285 = safe with existing evidence 3/21 + product-required 46/202 + already rejected/excluded 10/62.

### Verified product truth와 review

- independently verified actual current product error는 8: Gold E482514/E454311/E456567, musinsa 6800912, UNIQLO E450536/E465193/E486066/E486103.
- Phase 1A manual-review preview 1,147 중 conflict verified 105와 DB mismatch 5를 해소해 remaining manual-review product는 1,037이다.
- 207 adjudicated expected는 모두 independent manual evidence다. Current DB overlap 137, exact 132, DB change target 5다.
- 기존 31 products / 64 assertions는 local Swift logic regression이며 전부 iOS Phase 2 대상이다. Test expectation correction 0이다.

### Current UNIQLO 880 / live 71

- `CurrentUniqloCatalogAuditTests`를 실제 실행했다: 880/880 fixture·local·DB coverage, raw 5,193, parsed 5,181, A-test 2,246/2,246 PASS, test 1/1 PASS(135.907s).
- Local operational proxy는 confirmed 439 / review 0 / notComparable 300 / unclassified 141. DB current는 670 / 100 / 110 / 0이다.
- Local/DB exact 482, mismatch 398; conflict 431; mixed product 102; missing DB measurement policy 196.
- Gold 3은 fixture에 모두 존재하며 local classification도 모두 충돌한다. 따라서 A-test PASS는 semantic accuracy가 아니라 self-consistency다.
- Live fixture 71(M 40/U 31)은 DB coverage 33, historical detail match/mismatch 18/15, DB invalid 31, conflict 17이다. Runtime ready 21 / strict 18이며 E488204/E488364/E488738 3건이 silent propagation risk다.
- 새 network/live parse/measurement/recommendation 71건은 전부 SKIP이며 PASS로 기록하지 않았다.

### Dresses / underwear / homewear

- Base-layer top은 `tops/base_layer_top/base_layer_top`, sleeve required, upper_core min 2다. Bra/panty underwear family와 합치지 않는다.
- Dresses는 `dresses/dress/dress`, body-length required, Phase 1B auto=false로 fail-close한다.
- Underwear는 bottom/bra/top subtype group으로 분리하고 Phase 1B auto=false다. Functional base layer는 product-level로 tops에 보낸다.
- Owner 질문은 homewear의 display/canonical major 1건만 남긴다. 권장 A는 homewear major를 유지하되 non-auto top/bottom/set group을 두는 방식이다. B는 canonical tops/bottoms와 display metadata 분리, C는 전부 review/notComparable이다.
- Current policy scope는 dresses 48 + underwear 142 + homewear 47 = 237 products; linked closet 0, comparison history 0이다.

### Phase 1B blocker와 exact scope

- Blocker: homewear owner 결정, BOTH_UNTRUSTED conflict 310, manual review 1,037, invalid mapping 369의 미확정 replacement 값.
- Schema/RPC/mapping/history/release exact object와 rollback/acceptance는 Phase 1A.5 보고서 10–12절에 있다. Baseline 11–15절의 원칙을 유지했다.
- Targeted product-decision plan은 114 rows(verified/corrected 113 + ZARA supersede-to-review 1)이며 JSONL에 전수 기록했다.
- Mapping successor는 active 3,492를 clone한다. Active release in-place 수정, legacy decision bulk revoke, invalid confirmed bulk review, history delete는 금지다.
- History expected append/supersede는 1,601–1,608; 기존 1,860을 보존하고 current는 항상 1,608이다. Closet linked migration 0, comparison history migration 0이다.
- Swift `CanonicalComparisonProfile.appGarmentFamily`의 `base_layer_top -> underwear`와 adjudicated 31/64는 iOS Phase 2로 defer한다.

## 2026-08-25 Classification Authority Phase 1A — Global Baseline Audit

### 범위와 산출물

- 기준 branch/HEAD는 `connectDB` / `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab`로 exact match했다.
- Supabase project `hnkplvyegonlhumlejst`를 SELECT-only로 감사했다. migration/seed/RPC/production DB write와 Swift production 변경은 0건이다.
- 보고서: `Docs/FitMatchClassificationGlobalBaseline-20260825.md`
- 1,608-product manifest: `Docs/FitMatchClassificationGlobalBaseline-20260825.jsonl`; 1,608 rows, unique source+external ID 1,608, required key 누락 0.
- Phase 1B는 시작하지 않았다.

### Production baseline

- active release: `65d72393-4a40-4e99-b701-fdc1ff865774` / `fitmatch-active-with-zara-official-tree-2026-08-13-v1__zara-sample30-2026-08-21`.
- active mappings expected/actual 3,492/3,492. release QA count는 0이고 `qa_full_validation_included=false`.
- latest production migration ledger는 `20260821090138`. local numeric 114의 `data_quality_review_queue`/release gate는 production에 없다.
- products 1,608, current history 1,608, decisions 5,056, snapshots 3,842, closet items 6(active 1, linked product 0), comparison history 0.
- decision/history에 `garment_type_code`, decision에 `authority_status`가 없다.

### 전수 결과

- current status: confirmed 1,106, review_required 333, not_comparable 169.
- confirmed 1,106 중 strict canonical tuple valid 154, invalid confirmed 952.
- stale current history 1,472; source mapping/product decision conflict products 573.
- active mapping: confirmed 1,392, review 608, rejected 1,452, unsupported 40.
- category-only confirmed 위험 mapping 1,358; mapping/product-decision conflict rows 182.
- mapping row target duplicate/mixed target은 0이지만 observed product decision tuple mixed bucket은 59개/285 products다. 실제 non-null family 2개 이상은 14 buckets/56 products.
- decisions는 authority column이 없어 5,056건 모두 implicit legacy. active release 30, retired 5,026, independent evidence 237, strict auto-eligible 8, must-review 5,048.
- comparison readiness: current runtime ready 622, strict policy ready 504; runtime가 118건 과대 허용.
- 보수적 preview: confirmed 192, review_required 1,120, not_comparable 296.

### Golden과 회귀

- current Gold 3건은 모두 `underwear/underwear/underwear/unknown/confirmed`로 잘못됐다.
- preview:
  - E482514 → `tops/short_sleeve/tshirt/tshirt/short_sleeve/confirmed`, fingerprint `33119909d27567ab432c0b27c6f6aae8`.
  - E454311 → `tops/base_layer_top/base_layer_top/base_layer_top/short_sleeve/confirmed`, fingerprint `670669aa2beb25167e781f721ed7d9ed`.
  - E456567 → E454311과 동일, fingerprint `67852370ebdc165b23b66e497ac074fc`.
- production DB validators v1/v2/v3 PASS, 5,026 parity 100%, profile cases 2,536/mismatch 0. 같은 QA corpus 계보의 self-consistency이므로 semantic correctness 증거로 해석하지 않는다.
- local run: 5,026 PASS, live300 shadow PASS, adjudicated 207 FAIL(31 products/64 assertions), CurrentUniqlo 880 SKIP.
- sync/DTO 14/14 PASS. 추가 category/Closet/Compare offline boundary run은 24 total, 13 PASS/11 live-only SKIP/0 FAIL.
- 5,026 local/DB divergence는 92 products: category 1, detail 86, family 39, length 42, eligibility 0.

### Phase 1B 전에 필요한 결론

- dresses/underwear/homewear를 canonical garment/group row로 추가할지 review/not_comparable로 내릴지 owner taxonomy 결정이 필요하다.
- 82144는 successor release에서 product-level resolution required로 바꿔야 하며 active release를 직접 수정하거나 gate를 우회하면 안 된다.
- legacy 5,026 decisions를 일괄 revoke/차단하지 말고 authority_status=legacy로 보존한다.
- Phase 1B exact DB object, backfill 순서, rollback, acceptance criteria는 baseline 보고서 11–15절에 고정했다.

## 2026-08-24 Category Engine v2.3 ZIP — 신규 Shadow 데이터만 흡수

### 쉽게 설명한 결론

- **사용자 화면, 분류 규칙, 비교점수, 추천 순위는 바꾸지 않았다.** 이번 작업은 실제 판매 목록 표본 300개를 개발 검사용 문제지로 추가한 것이다.
- 이 300개에는 사람이 확인한 정답이 0개다. 따라서 Gold 정답지가 아니라 Shadow 검사 자료이며, 운영 상품·분류 규칙·DB seed로 자동 승격할 수 없다.
- 새 ZIP의 분류엔진, 비교엔진, `fm_*` DB schema, 자동 생성 `manual PASS`, “오분류 0건” 주장은 흡수하지 않았다.

### 흡수한 데이터

- `Docs/Research/FitMatchCategoryMappingV2-20260824-shadow/live300-v2_3/live_products_300.jsonl`
  - Musinsa 100, Uniqlo 100, ZARA 100, 합계 300건.
  - 기존 corpus와 비교하면 Musinsa 43건 중복/57건 신규, Uniqlo 100건 중복, ZARA 100건 중복이다.
  - Uniqlo/ZARA sitemap 확인은 공식 목록 노출을 뜻할 뿐 현재 PDP category·재고 상태의 독립 증명은 아니다.
- `official_source_evidence.json`은 ZIP이 기록한 수집 URL/status/checksum 출처 메타데이터다. 원격 응답 본문은 없으므로 provenance이지 독립 재현 증명은 아니다.
- archive SHA256 `9bf813ae7d2dbd250fffe8ff8ea7fa634e994458540185b358cb826e5d7d4cfa`와 입력/evidence checksum을 기존 manifest에 고정했다.

### 안전장치

- manifest의 live sample 계약에 `independentLabelCount=0`, `productionImportAllowed=false`, `goldFixtureApprovalAllowed=false`를 고정했다.
- `scripts/audit-category-mapping-shadow-corpus.mjs`가 300행/쇼핑몰별 100행, 중복, 상품명, HTTPS URL, URL↔상품 ID, Gold label 부재, 기존 corpus overlap/new count, checksum을 검사한다.
- ZARA `ZARA_KR_*`는 계속 archive-local pseudo identity로만 허용한다. verified runtime `catentryId`로 취급하면 검사가 실패한다.
- ZIP의 `build_live_manual_audit.mjs`는 모든 행에 `silent_misclassification_observed=false`를 자동 입력하므로 결과와 정확도 주장은 폐기했다.

### 현재 FitMatch Shadow 실행 결과

- 신규 `CategoryLive300ShadowAuditTests`가 현재 Musinsa/Uniqlo parser mapping과 `ParsedClosetClassification`을 사용해 source fact를 감사한다.
- 300건 결과: provisional confirmed 243, `review_required` 29, `unclassified` 28, 사람 Gold 검토 후보 57건.
  - Musinsa 94/6/0, Uniqlo 83/14/3, ZARA 66/9/25 순서로 confirmed/review/unclassified다.
- explicit conflict silent confirmation 0, strict comparison conflict leak 0이다.
- `current_fitmatch_gold_review_candidates.json`에 57건을 별도 저장했다. 이 목록도 정답이 아니라 사람이 정답을 붙일 후보 목록이다.
- ZARA는 ZIP에 현재 PDP HTML과 verified `catentryId`가 없으므로 current runtime parser 검증 0건이다. archive source candidate로 fail-closed 안전성만 검사했고, ZARA 정확도라고 해석하지 않는다.

### 테스트

- `node scripts/audit-category-mapping-shadow-corpus.mjs` → base 5,723행 + live 300행 integrity/safety audit passed.
- `xcodebuild build-for-testing -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/FitMatchP3DerivedData` → `TEST BUILD SUCCEEDED`.
- `xcodebuild test-without-building ... -resultBundlePath /tmp/FitMatch-Live300Shadow-20260824-v1.xcresult -only-testing:FitMatchTests/CategoryLive300ShadowAuditTests` → 1/1 passed.
- `xcodebuild test-without-building ... -resultBundlePath /tmp/FitMatch-Live300-P1-ZARA-Regression-20260824-v1.xcresult -only-testing:FitMatchTests/FitMatchP0ProductionPathTests -only-testing:FitMatchTests/ZARAParserPhase1_5Tests` → 48/48 passed.
- 최초 sandbox build는 CoreSimulator/SwiftPM cache 접근 권한으로 실패했고 동일 명령을 승인된 Xcode 권한으로 재실행해 성공했다. 코드 실패가 아니었다.

### 남은 작업 — 사람이 해야 하는 것

- 57개 후보에 실제 정답 category/detail을 사람이 붙여야 한다. 확인 전에는 Gold 테스트나 운영 규칙으로 승격하면 안 된다.
- ZARA 후보는 공식 PDP를 현재 runtime parser로 다시 읽어 verified `catentryId`, family/subfamily, product name parity를 확인해야 한다.
- Production DB write/migration/seed/commit/push는 0건이다.

## 2026-08-24 외부 Category Mapping v2 유효 요소 4건 흡수

### 결론 — 쉽게 설명

- **사용자가 보는 화면·점수·추천 순위는 바뀌지 않았다.** 이번 변경은 잘못된 상품 데이터나 미검증 release가 사용자 추천으로 들어가기 전에 개발 단계에서 잡는 안전장치다.
- 첨부 ZIP의 엔진·DB table·상태값은 현재 FitMatch보다 약하거나 중복돼 버렸다. 실제로 도움이 되는 상품 corpus, 출시 차단 기준, 검수 방식, parser 출처 기록만 현재 구조에 흡수했다.
- Swift 변경은 build와 67개 회귀가 통과했다. DB 변경은 migration 파일만 작성했고 Production에는 적용하지 않았다.

### 흡수 1 — 새 상품 shadow 검증 자료

- `Docs/Research/FitMatchCategoryMappingV2-20260824-shadow`에 Musinsa 51건, Uniqlo 1,689건, ZARA 3,983건을 편입했다.
- Musinsa 51건은 명시적 기대 garment label이 있어 신규 regression 후보로 쓸 수 있다.
- Uniqlo와 ZARA는 독립적인 사람 정답이 0건이므로 자동 Gold 승격을 금지했다. ZARA의 `ZARA_KR_*` ID는 runtime `catentryId`가 아닌 pseudo ID이고 상품명 누락도 8건 있어 production identity import를 금지했다.
- `node scripts/audit-category-mapping-shadow-corpus.mjs`가 5,723행의 checksum, row count, 중복 ID, label 등급, ZARA pseudo-ID 계약을 검사하며 통과했다.

### 흡수 2 — 미검증 release 활성화 차단

- `supabase/migrations/114_release_gate_and_quality_review_queue.sql`은 기존 `fitmatch_catalog.releases`를 확장한다. 새 release/master/status table은 만들지 않았다.
- activation 전에 checksum, mapping count parity, QA fixture 수, 전체 회귀, 현재 동작 parity, product identity 검증, 독립 label 충분성, unsafe auto accept 0건, classification conflict leak 0건, measurement alias conflict 0건을 모두 확인한다.
- 하나라도 빠지면 trigger와 `runtime_activate_validated_release`가 `active` 전환을 거부하고 blocker 목록을 남긴다. 현재 Production active release는 `expected_qa_count=0`, `qa_full_validation_included=false`라 새 gate 기준으로 재활성화할 수 없는 상태임을 read-only 감사에서 확인했다.
- Production migration apply/write는 0건이다. 실행 검증용 `supabase/sql/114_release_gate_and_quality_review_queue_verification.sql`은 local/staging 전용이며 rollback한다.

### 흡수 3 — 문제 상품 검수 큐

- 새 `review_queue` table 대신 기존 `fitmatch_catalog.data_quality_issues`에 담당자, 우선순위, 검수 메모, 확인 시각을 추가했다.
- `data_quality_review_queue` view는 open/acknowledged 이슈를 위험도와 우선순위 순으로 보여 준다. `runtime_triage_data_quality_issue`로 open/acknowledged/resolved/ignored를 관리하며 resolved/ignored는 이유 없이는 처리할 수 없다.
- P3 fingerprint/occurrence_count 집계를 그대로 재사용하므로 동일 문제가 상품마다 무한히 새 행으로 쌓이지 않는다. app role은 release 활성화나 검수 mutation을 실행할 수 없고 service role만 사용한다.

### 흡수 4 — parser 데이터 출처 기록

- `ParsedProductInfo`에 optional `ProductParserProvenance`를 추가하고 Musinsa/Uniqlo/ZARA/COS parser route의 성공·partial 결과에 parser code를 기록한다.
- source URL은 사용자 입력, 상품명/브랜드/source category는 retailer parser, category/detail은 iOS parser classification, measurement는 기존 `ParsedMeasurement.evidence`라는 구분을 observation payload에 보존한다.
- 확인되지 않은 parser implementation version은 추측하지 않고 `not_declared`로 기록한다. parser service를 거치지 않은 과거/legacy record는 `legacy_unknown`으로 남겨 잘못된 출처 추정을 막는다.

### 테스트 결과

- `xcodebuild build-for-testing -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/FitMatchP3DerivedData` → `TEST BUILD SUCCEEDED`.
- 같은 prefix의 `test-without-building -resultBundlePath /tmp/FitMatchAbsorbFour-Resolver-Final-20260824.xcresult -only-testing:FitMatchTests/FitMatchSupabaseProductResolverTests` → 10/10 passed.
- 같은 prefix의 `test-without-building -resultBundlePath /tmp/FitMatchAbsorbFour-P1P2Regression-Final-20260824.xcresult -only-testing:FitMatchTests/FitMatchP0ProductionPathTests -only-testing:FitMatchTests/ZARAParserPhase1_5Tests -only-testing:FitMatchTests/FitMatchClosetSyncCoordinatorTests -only-testing:FitMatchTests/MeasurementPolicyConsolidationTests -only-testing:FitMatchTests/FitMatchComparisonSyncCoordinatorTests` → 57/57 passed.
- shadow corpus audit → 5,723/5,723 integrity/safety checks passed.

### 아직 실제 서비스에서 안 켜진 것

- migration 114는 Production에 적용하지 않았으므로 release gate와 검수 큐는 아직 운영 DB에서 작동하지 않는다.
- 이 환경의 `psql/initdb`는 client-only 설치로 PostgreSQL server binary가 없어 migration 114와 rollback verification SQL을 실제 local DB에서 실행하지 못했다. staging/local Supabase에서 migration 113→114 적용, verification SQL, security/performance advisor 확인이 필요하다.
- 첨부 corpus는 자동 분류 정답이나 production 상품으로 import하지 않았다. Musinsa 51건은 현재 FitMatch classifier와 대조해 사람이 불일치 이유를 확인한 뒤 regression으로 승격해야 하며, Uniqlo/ZARA는 독립 label 확보가 먼저다.
- 사용자 착용 테스트나 UX 변경은 이번 네 가지 흡수 작업과 무관하다. production score와 화면 연결은 0건이다.

## 2026-08-24 P3 Experimental Scoring & Data Quality Observability

### 1. Executive Conclusion

- Production `MeasurementComparisonEngine.compare()`와 추천 정렬에는 P3 변경이 없다. 사용자가 보는 점수·추천 1위·comparison eligibility는 그대로다.
- test target에만 `ExperimentalMeasurementScoreV2`를 두어 production이 이미 선택·정규화한 comparable measurement와 weight를 재사용하고, 차이를 점수로 바꾸는 단계만 shadow 계산한다.
- 실제 fixture에서는 Musinsa 4개 후보 중 중간 순위 2개가 바뀌고 1위는 유지됐다. Uniqlo 7개와 validated ZARA 5개는 순위가 모두 유지됐다. 사용자 정답 데이터가 없으므로 experimental verdict는 `NEEDS_USER_VALIDATION`이다.
- 기존 `fitmatch_catalog.data_quality_issues`를 source+issue+raw signature로 집계하는 migration과 rollback verification SQL을 작성했다. Production DB에는 적용하지 않았다.

### 2. Production Score Baseline

- production item score는 계속 `round(clamp(100 - abs(candidate-reference) * 5, 0...100))`이고 기존 weight의 weighted average다.
- 9개 measurement kind × `-3/-1/0/+1/+3cm`, 총 45개 대칭 case에서 parity configuration의 shadow score와 production score가 정확히 일치했다.
- 기존 same/cross-source 비교 parity 16/16도 통과했다. production score 파일은 P3에서 수정하지 않았다.

### 3. Experimental Algorithm

- production result의 `comparedItems`만 입력으로 받는다. record 선택, canonical code, same/cross-source compatibility, width/circumference와 unit normalization, exclusion, required gating, coverage, weight는 다시 구현하지 않는다.
- 각 item은 `effectiveDelta=max(0, abs(delta)-tolerance)`와 방향별 multiplier, 명시적으로 검증된 stretch multiplier만 적용한다. production 호출 경로와 연결되지 않는다.

### 4. Experimental Parameters

- version은 `EXPERIMENTAL-fixture-hypothesis-2026-08-24-v1`이다. production policy가 아니다.
- 기본 tolerance 0.5cm/방향 multiplier 1.0, chest·waist `1.2/0.8`, hip `1.15/0.85`, thigh `1.1/0.9`, length·sleeve `1.0/1.0`을 오직 deterministic shadow fixture 가설로 사용했다.
- 별도 production-parity config는 tolerance 0, 양 방향 1.0이다.

### 5. Synthetic Test Results

- 45개 measurement 방향/차이 case가 production parity를 통과했다.
- tolerance 1cm에서 +1cm는 100점, -3cm×1.5는 85점, +3cm×0.5는 95점으로 경계와 방향이 분리됨을 확인했다.
- 일반 상의, 셔츠, 니트, 아우터, 팬츠, 데님, 레깅스, 스커트, 원피스 9종은 production eligibility/weight를 그대로 재사용해 모두 confirmed/recommendable이었다.

### 6. Real Fixture Results

- Musinsa: `L 84→87`, `M 84→85`, `S 79→80`, `XL 83→86`.
- Uniqlo E475941: `3XL 51→58`, `4XL 40→48`, `L 89→92`, `M 100→100`, `S 89→90`, `XL 74→79`, `XXL 62→68`.
- validated ZARA pants `08372248/582770476`: `L 91→94`, `M 100→100`, `S 91→92`, `XL 81→86`, `XS 81→81`.

### 7. Candidate Ranking Changes

- 전체 16개 candidate 중 동일 rank 14, 변경 2, top recommendation 변경 0이다.
- Musinsa는 `XL 3→2`, `M 2→3`; Uniqlo와 ZARA는 전부 동일하다. 전체 평균 score delta는 `+2.94`다.
- pants fixture 기준 9개 중 2개 rank 변경, shirt fixture 7개 중 변경 0이다. rank 변화 자체를 개선으로 판정하지 않는다.

### 8. Coverage / Eligibility Findings

- 기존 `MeasurementComparisonResult.score`, `comparisonCoverage`, `status`를 그대로 사용한다. 새 production DTO/필드를 만들지 않았다.
- similarity 100, coverage 0.25여도 production status가 `insufficientEvidence`면 experimental `recommendable=false`임을 회귀로 고정했다.

### 9. Undersize vs Oversize Findings

- measurement별 undersize/oversize multiplier를 독립 실험할 수 있다. 낮은 쪽이 항상 나쁘다고 production 전제하지 않았다.
- 방향별 행동 차이는 확인했지만 사용자 fit 정답이 없어 어느 쪽이 더 적절한지는 검증되지 않았다.

### 10. Stretch Findings

- 현재 parser/product metadata에 scoring에 쓸 수 있는 검증된 stretch flag/composition contract가 없다. `KNIT == VERIFIED_STRETCH`로 추측하지 않는다.
- shadow scorer도 호출자가 명시적 evidence와 multiplier를 전달할 때만 반영한다. synthetic test에서만 `85→93`을 확인했고 실제 fixture에는 stretch를 쓰지 않았다.

### 11. Experimental Verdict

- `NEEDS_USER_VALIDATION`. 행동 차이는 있으나 사용자 선호/착용 ground truth가 없어 `PROMISING`, `BETTER`, `MORE_ACCURATE`라고 결론 내리지 않는다.

### 12. Data Quality Existing Architecture

- 신규 `unmapped_observation` table을 만들지 않고 migration 105의 private/RLS-enabled `fitmatch_catalog.data_quality_issues`를 확장한다.
- 기존 `occurrence_count`, `first_seen_at`, `last_seen_at`, `evidence`, `resolution`, `status`를 유지한다.

### 13. Unknown Category Observation

- source category path/code signature가 active source mapping에 없으면 `UNKNOWN_SOURCE_CATEGORY`를 기록하고, 같은 mapping이 생긴 뒤 재관측되면 resolved로 전환하는 경로를 migration에 추가했다.
- unknown category를 억지 canonical category로 승격하지 않는다.

### 14. Unknown Measurement Observation

- 최신 `runtime_normalize_measurement_v2`를 raw code, raw label, unit, classification category scope와 함께 사용한다.
- `measurement_alias_not_found`만 `UNKNOWN_MEASUREMENT_ALIAS`로 기록한다. unsupported unit/comparison basis/measurement kind는 `UNSUPPORTED_MEASUREMENT_BASIS`로 분리하고, intentional non-comparable alias와 섞지 않는다.
- Swift observation payload가 unknown raw code/label/value/representation/evidence를 손실 없이 보존하는 test가 통과했다.

### 15. Classification Conflict Observation

- P1 `ParsedClosetClassification.auditExplicitContradictions` 결과를 observation `raw_payload`에 dimension, trusted→explicit evidence, safety policy version으로 보존한다.
- backend processing migration은 이를 `CLASSIFICATION_CONFLICT` high-severity issue로 집계하고 최신 observation/product/classification history ID를 evidence에 남긴다.
- `CATEGORY_NAME_CONTRADICTION`은 같은 사실을 중복 row로 만들지 않고 `CLASSIFICATION_CONFLICT` evidence로 표현한다.

### 16. Aggregation / Fingerprint Behavior

- fingerprint는 normalized `source + issue_code + raw_signature`의 MD5다. unique partial index와 upsert로 상품별 무한 row 생성을 막는다.
- 재관측 시 같은 ID의 `occurrence_count`를 올리고 `last_seen_at`/latest evidence를 갱신한다. resolved issue 재관측은 이전 resolution을 evidence에 보존하고 active resolution을 비운 뒤 open으로 재개방한다.
- rollback verification SQL에 1→2회 집계, resolve, 3회째 reopen 및 anon/authenticated execute 차단 검증을 포함했다.

### 17. Semantic Feature Decision

- FIT/MATERIAL/LEG_SHAPE/STRETCH/NECKLINE의 현재 typed consumer가 확인되지 않았고 stretch source도 검증되지 않았다. `product_classification_features` 같은 신규 schema를 만들지 않았다.
- category/detail/comparison family/length/body length 핵심 계약은 그대로 typed 구조다.

### 18. Evidence Storage Decision

- 현재 `product_classification_history.evidence`와 `data_quality_issues.evidence` JSONB로 rule/conflict/source 분석 근거를 보존할 수 있다. 검증된 별도 analytics query 요구가 없어 normalized evidence table을 만들지 않았다.

### 19. DB/Migration Files Created

- `supabase/migrations/113_p3_data_quality_observability.sql`: 기존 issue ledger에 source/signature/fingerprint, service-role helper, observation issue 연결을 추가한다.
- `supabase/sql/113_p3_data_quality_observability_verification.sql`: staging/local 전용이며 항상 rollback한다.
- Supabase 공식 함수 보안 원칙에 맞춰 app role execute를 revoke하고 helper는 empty search path/security invoker로 작성했다. Production apply/write는 0건이다.

### 20. Changed Files

- `FitMatch/Services/FitMatchSupabaseProductResolver.swift`
- `FitMatchTests/ExperimentalMeasurementScoreV2Tests.swift`
- `supabase/migrations/113_p3_data_quality_observability.sql`
- `supabase/sql/113_p3_data_quality_observability_verification.sql`
- `Docs/CodexSessionHandoff.md`

### 21. Exact Test Commands and Results

- build: `xcodebuild build-for-testing -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/FitMatchP3DerivedData` → `TEST BUILD SUCCEEDED`.
- P3: 같은 prefix의 `test-without-building -resultBundlePath /tmp/FitMatchP3Shadow-20260824-v3.xcresult -only-testing:FitMatchTests/ExperimentalMeasurementScoreV2Tests` → 9/9 passed. 실제 fixture log에 candidate별 reference/product 값, signed/absolute delta, tolerance/effective delta, 방향/multiplier, old/new item score, weight, coverage, eligibility, old/new rank를 저장했다.
- P1/P2/ZARA/sync: `-resultBundlePath /tmp/FitMatchP3-P1P2Regression-20260824.xcresult -only-testing:FitMatchTests/FitMatchP0ProductionPathTests -only-testing:FitMatchTests/ZARAParserPhase1_5Tests -only-testing:FitMatchTests/FitMatchClosetSyncCoordinatorTests -only-testing:FitMatchTests/MeasurementPolicyConsolidationTests -only-testing:FitMatchTests/FitMatchComparisonSyncCoordinatorTests` → 57/57 passed.
- comparison parity: `/tmp/FitMatchP3-ComparisonParity-20260824.xcresult`에 P2 handoff의 16개 exact identifier를 `-only-testing`으로 실행 → 16/16 passed.
- 5,026 corpus: `-resultBundlePath /tmp/FitMatchP3-Classification5026-20260824.xcresult -only-testing:'FitMatchTests/CategoryValidation5026AuditTests/testCurrentProductionClassifierReclassifiesAll5026Products()'` → 1/1 passed, `invalid_classification_count=0`, `user_confirmation_required_count=329`.
- `git diff --check` → clean. SQL은 delimiter/static contract check만 통과했고 DB 실행은 하지 않았다.

### 22. P1/P2 Regression Results

- P1 fail-closed 분류, ZARA parser, closet/sync 경로 57건과 5,026 corpus가 모두 통과했다.
- P2 source identity/policy 5건은 57건 묶음에 포함됐고, same/cross-source/width-circumference/required gating 16건도 전부 통과했다.
- production score와 top recommendation을 바꾸는 P3 연결은 0건이다.

### 23. NOT_VERIFIED Items

- 사용자 착용 선호 ground truth가 없어 experimental accuracy는 검증하지 않았다.
- 실제 source의 verified stretch/material contract가 없어 stretch 실데이터 평가는 하지 않았다.
- COS/H&M 또는 미검증 ZARA measurement 의미를 추측하지 않았다.
- `UNMAPPED_PRODUCT`, `UNKNOWN_ATTRIBUTE_VALUE`는 현재 확인된 별도 consumer/signature가 없어 신규 중복 issue를 만들지 않았다. 실제 운영 요구가 확인되면 기존 ledger code로 추가한다.

### 24. Remaining Blockers

- Supabase CLI와 local PostgreSQL server가 없어 migration 113 및 rollback verification SQL을 실제 DB에서 실행하지 못했다. Production apply는 요청상 금지다.
- staging/local migration apply, verification SQL 실행, advisor 재확인 전에는 DB 관측 경로를 production-ready로 판정할 수 없다.
- shadow score의 채택 여부는 실제 사용자 pairwise 선호/착용 결과로 검증해야 한다.

### 25. P3 Verdict

- `INCOMPLETE`: Swift shadow infrastructure와 회귀는 완료됐지만 DB migration의 실행 검증이 남아 있다. Production score/rank는 안전하게 그대로이며, migration을 적용하거나 실험 점수를 노출하지 않았다.

### 사용자용 남은 작업 체크리스트 — 쉽게 설명

#### 아직 실제 서비스에 구현되지 않은 기능

- [ ] **새 실험 점수로 추천하기**
  - 현재 상태: 새 계산법은 테스트 안에서만 결과를 비교할 수 있다. 사용자가 보는 점수와 추천에는 연결하지 않았다.
  - 왜 안 켰나: Musinsa에서 중간 사이즈 순위가 바뀌었지만 어느 결과가 실제로 더 잘 맞는지 착용 정답이 없다.
  - 완료 기준: 사용자가 여러 후보를 직접 입어 보고 선호 결과를 제공한 뒤, 기존 점수보다 안전하다는 근거와 별도 승인까지 있어야 한다.

- [ ] **운영 DB에서 미등록 category·measurement·분류 충돌 자동 집계**
  - 현재 상태: 구현 migration은 작성됐지만 Production DB에 적용하지 않았으므로 실제 운영에서는 아직 작동하지 않는다.
  - 구현 예정 동작: 같은 미등록 문제가 상품마다 새 행으로 쌓이지 않고 한 건의 발생 횟수로 누적된다.
  - 완료 기준: staging/local DB에서 migration과 rollback verification이 통과하고, 승인 후 별도 배포 절차로 Production에 적용해야 한다.

- [ ] **stretch를 반영한 실제 추천 점수**
  - 현재 상태: 테스트용 구조만 있고 실제 상품에는 사용하지 않는다.
  - 왜 안 켰나: 현재 상품 데이터에 검증된 stretch 값이 없다. 상품명이 ‘니트’라는 이유만으로 잘 늘어난다고 추측하면 잘못된 추천이 될 수 있다.
  - 완료 기준: 판매처 공식 stretch/material 속성과 그 의미가 검증돼야 한다.

- [ ] **서버가 스스로 category와 상품명 충돌을 재검사하는 기능**
  - 현재 상태: 최신 iOS 앱이 발견한 충돌 근거를 DB로 전달하는 경로는 구현했다. 하지만 구버전 앱이나 별도 backend batch가 충돌 표시를 보내지 않으면 서버가 독립적으로 다시 찾아내지는 않는다.
  - 완료 기준: 기존 DB classifier 계약 안에서 동일한 P1 conflict 판정을 재현하고 iOS 결과와 parity test를 통과해야 한다.

- [ ] **DB measurement policy를 앱 비교의 완전한 source of truth로 사용**
  - 현재 상태: 앱은 검증된 embedded fallback을 사용하므로 offline 비교는 안전하다. DB policy와 Swift policy가 일부 다르고 richer DB metadata가 local record까지 완전히 hydration되지 않는다.
  - 완료 기준: DB↔embedded policy의 필드별 parity, version 동기화, hydration 손실 없음이 확인돼야 한다.

#### 개발환경에서 직접 실행해야 하는 테스트

- [ ] **migration 113 실제 DB 실행 테스트 — 개발자/AI 작업**
  - 할 일: local 또는 staging DB에 migration 113을 적용한 뒤 `supabase/sql/113_p3_data_quality_observability_verification.sql`을 실행한다.
  - 확인할 것: 동일 issue 집계, occurrence 1→2→3 증가, resolve 후 재발 시 reopen, unknown category/measurement/conflict 3종 생성, app role 접근 차단.
  - 현재 blocker: 이 환경에는 Supabase CLI와 실행 중인 local PostgreSQL server가 없다.

- [ ] **Supabase advisor 재확인 — 개발자/AI 작업**
  - 할 일: staging 적용 뒤 security/performance advisor를 확인한다.
  - 확인할 것: RLS/권한 노출, 잘못된 index, function execute 권한 문제가 새로 생기지 않았는지 확인한다.

- [ ] **전체 FitMatch test suite 실행 — 개발자/AI 작업**
  - 현재 완료: P3 9건, P1/P2/ZARA/sync 57건, 비교 parity 16건, 5,026개 분류 corpus 1건은 통과했다.
  - 아직 필요한 것: repository 전체 unit suite를 최종 코드로 완주하고 기존에 알려진 unrelated failure와 신규 failure를 구분한다.

- [ ] **실제 관측 E2E — 실제 iPhone·로그인 필요**
  - 할 일: 승인된 staging 환경에서 로그인한 실제 앱으로 unknown category 상품, unknown measurement 상품, category/name 충돌 상품을 각각 한 번 분석한다.
  - 확인할 것: 앱은 계속 fail-closed이고, backend issue만 누적되며, 사용자 추천이 잘못 열리지 않는지 확인한다.

#### 사용자가 직접 확인해야 하는 테스트

- [ ] **사이즈 추천 착용 비교**
  - 가장 필요한 데이터: 같은 기준 옷에 대해 한 단계 작은 후보, 비슷한 후보, 한 단계 큰 후보를 직접 입어 본 결과.
  - 알려줄 내용: 어떤 사이즈가 가장 적절했는지, 작은 쪽과 큰 쪽 중 어느 불편이 더 컸는지, 가슴·허리·총장 중 무엇이 결정적이었는지.
  - 이 결과가 있어야 undersize/oversize penalty와 tolerance가 실제로 도움이 되는지 판단할 수 있다.

- [ ] **실제 iPhone 상품 분석 확인**
  - 확인할 화면: Musinsa·Uniqlo·검증된 ZARA 상품 분석과 비교 화면.
  - 확인할 내용: 기존 추천 점수와 1위가 바뀌지 않았는지, 분류 충돌 상품은 확인 요청으로 멈추는지, offline에서도 기존 비교가 되는지.

#### 지금 당장 사용자에게 바뀌는 것

- 현재 앱 화면과 추천 결과에는 의도적인 변화가 없다.
- 잘못 검증된 새 점수를 사용자에게 보여 주지 않도록 막아 둔 상태다.
- 이번에 완성된 것은 **안전하게 실험하고 문제를 추적하기 위한 개발 기반**이며, DB migration과 새 점수의 production 활성화는 아직 남은 작업이다.

## 2026-08-24 P2 측정 출처·비교 정책 안전 통합

- 실제 로컬 경로는 parser의 `ParsedMeasurement` → `GarmentMeasurementRecord`/SwiftData → `MeasurementComparisonEngine`이며, DB runtime DTO의 richer measurement metadata는 아직 이 로컬 비교 record로 hydration되지 않는다. 앱의 production score와 추천 순위 source of truth는 계속 로컬 엔진이다.
- `MeasurementComparisonEngine`과 직접 비교 가능성 판정에 있던 `uniqlo`/`musinsa`/`fitmatch`/`manual` 문자열 분기를 제거했다. 먼저 `Product.sourcePlatformCode`, `UserFit.sourcePlatformCode`의 canonical source를 사용하고, 없는 과거 로컬 record만 `methodSource` 첫 machine token으로 해석한다. `html`, `actual-size`, `unknown` 같은 generic channel은 source로 인정하지 않으며 `manual_*`만 기존 동작을 위해 `fitmatch` legacy fallback으로 유지한다.
- canonical source가 있는 검증된 신규 merchant는 공통 엔진에 이름을 추가하지 않아도 동일 source/profile/raw field 비교가 가능하다. canonical source도 없고 generic `methodSource`뿐인 record는 raw field 직접 비교를 열지 않아 fail-closed다. 기존 `methodSource`, `methodProfile`, `rawCode`, `rawLabel`, `rawValueText`는 삭제하거나 변경하지 않았다.
- 기존 Swift policy 수치를 `MeasurementComparisonPolicySnapshot.embeddedProductionV1`으로 분리하고 버전 `fitmatch-production-measurement-policy-2026-08-24-v1`, source `embedded_fallback`을 엔진에서 조회할 수 있게 했다. 비교 때 Supabase를 조회하지 않으며 DB/offline 장애가 비교 기능을 막지 않는다. 점수식 `100 - abs(delta) * 5`, clamp/round, weight 합산과 순위 로직은 변경하지 않았다.
- DB↔Swift policy 감사 결과는 다음과 같다.

| 항목 | 판정 | 근거/처리 |
|---|---|---|
| measurement weight | `SWIFT_MORE_SPECIFIC` | Swift production 값은 category/detail별 수치가 완전하나 현재 local DB bundle의 garment policy와 완전 parity가 아니다. 값은 변경 없이 versioned embedded fallback으로 이동했다. |
| required measurement | `CONFLICT` | bundle은 예: tshirt/shirt에 chest+total length를 요구하지만 Swift는 shoulder/chest 중 1개와 총 2개를 요구한다. production 결과 보존을 위해 DB 값을 활성화하지 않았다. |
| required-any/minimum-required-any | `SWIFT_MORE_SPECIFIC` | 상의·하의의 any-gating이 Swift에 더 구체적이다. 그대로 유지했다. |
| minimum common measurement | `SAME`/category별 `CONFLICT` | 공통적으로 2개인 범위가 많지만 outer/dress 등 필수 축 의미는 다르다. 숫자만 같다고 parity로 간주하지 않았다. |
| short/sleeveless detail override | `SWIFT_MORE_SPECIFIC` | 소매 weight 0/0.2 override가 Swift에 있다. 유지했다. |
| source alias/raw representation/comparison basis | `DB_MORE_SPECIFIC` | DB DTO는 richer metadata를 제공하지만 local hydration이 아직 없어 Swift가 raw label legacy 판정을 사용한다. 이번 변경에서 추측 매핑하지 않았다. |
| policy version/source trace | `MISSING_IN_SWIFT` → 보완 | embedded fallback의 version/source를 명시했다. validated DB snapshot 연결은 parity 완료 전까지 비활성이다. |

- 새 회귀 `MeasurementPolicyConsolidationTests` 5/5는 canonical source 우선, merchant-agnostic legacy fallback, generic unknown fail-closed, 신규 merchant raw direct comparison, embedded policy 값/버전을 검증한다. 기존 measurement/무신사/유니클로 회귀 16/16, P0+ZARA+closet hydration 50/50, build-for-testing이 모두 통과했다. 최종 코드 기준 xcresult는 `/tmp/FitMatchP2BaselineDerivedData/Logs/Test/Test-FitMatch-2026.08.24_12-08-58-+0900.xcresult`(새 회귀 5건), `/tmp/FitMatchP2BaselineDerivedData/Logs/Test/Test-FitMatch-2026.08.24_12-10-02-+0900.xcresult`(기존 측정 회귀 16건), `/tmp/FitMatchP2BaselineDerivedData/Logs/Test/Test-FitMatch-2026.08.24_12-04-06-+0900.xcresult`(P0+ZARA+closet 50건)다.
- 정확한 공통 명령 prefix는 `xcodebuild test-without-building -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/FitMatchP2BaselineDerivedData`다. 여기에 새 회귀는 `-only-testing:FitMatchTests/MeasurementPolicyConsolidationTests`, 50건 회귀는 `-only-testing:FitMatchTests/FitMatchP0ProductionPathTests -only-testing:FitMatchTests/ZARAParserPhase1_5Tests -only-testing:FitMatchTests/FitMatchClosetSyncCoordinatorTests`를 사용했다. 16건 회귀 identifier는 `samePlatformAndFormatUsesMatchingSourceFieldsDirectly()`, `comparisonSelectsOfficialCircumferenceOrFitMatchWidthBySourceFormat()`, `differentPlatformFormatsRequireCanonicalMeasurementCodes()`, `measurementComparisonUsesOnlyIdenticalVerifiedCodes()`, `measurementComparisonExcludesDifferentSleeveDefinitions()`, `bottomComparisonRequiresTwoCoreWidthMeasurements()`, `bottomWidthAndLengthAloneDoNotConfirmRecommendation()`, `outerComparisonRequiresChestAndOneAdditionalMeasurement()`, `outerShoulderAndSleeveWithoutChestAreInsufficient()`, `musinsaAndUniqloCompareCommonUpperMeasurementsButExcludeSleeve()`, `crossPlatformBottomWidthsCompareWhileOutseamAndInseamStaySeparate()`, `uniqloBottomCircumferencesBecomeWidthsAndPreserveRawValues()`, `musinsaActualSizePreservesRawFieldsAndRaglanMeaning()`, `uniqloOfficialTopComparisonKeepsSleeveAndHasNoManualPenalty()`, `musinsaBottomWidthsAndExplicitLengthsUseCommonCodes()`, `migrationVersionSevenHalvesUniqloCircumferencesExactlyOnce()`이며 각각 `-only-testing:FitMatchTests/FitMatchTests/<identifier>`로 지정했다. 첫 변경 전 명령은 identifier에 `()`를 빠뜨려 0건 실행됐으므로 baseline 통과 근거에 포함하지 않았다.
- 운영 Supabase write, migration apply/create, seed, UPDATE, DELETE, backfill, commit, push는 수행하지 않았다. DB policy와 embedded policy가 현재 내용상 충돌하므로 validated snapshot을 production provider로 연결하지 않았다.
- 남은 P2 blocker는 (1) production DB policy export와 embedded fallback의 필드별 parity 확정, (2) DB runtime measurement의 `comparison_basis`/policy version을 local record로 손실 없이 hydration하는 backward-compatible 계약, (3) raw representation을 SwiftData schema 변경 없이 보존할 방법 또는 명시적 schema migration, (4) `GarmentLengthInferencePolicy`의 merchant별 길이 threshold를 검증된 policy data로 옮기는 작업이다. 외부 측정 의미를 추측하지 않고 `NOT_VERIFIED_EXTERNAL`로 유지한다. 따라서 전체 P2 verdict는 현재 `INCOMPLETE`이며, 이번 적용분 자체는 production score/rank를 바꾸지 않는 안전한 기반 보완이다.

## 2026-08-24 P1 명시적 분류 충돌 fail-closed 보완

- `ParsedClosetClassification`의 기존 상품명·source 해석기를 재사용해 공식 source category/detail과 상품명이 명시적으로 반대되는 category, garment family, length를 별도 safety audit로 기록한다. 새 generic engine이나 taxonomy table은 만들지 않았고, 기존 분류 결과 및 점수식은 변경하지 않았다.
- 긴소매 source/반팔 상품명, 반소매 source/긴팔 니트 가디건, 상의/스커트, 속옷/그래픽 티셔츠는 자동 확정 대신 `classification_conflict`와 `canonicalEligibility=false`로 표시된다. 비교 화면은 기존 카테고리 확인 UI로 보내며, 사용자가 직접 확인한 뒤 제품을 다시 만들 때만 비교가 가능하다.
- standard-size fallback을 포함한 모든 `RecommendationService` 진입점에서 product/reference의 canonical eligibility를 확인한다. 따라서 분류 충돌 상품이나 기준 옷은 실측 비교뿐 아니라 기준표 우회 경로로도 추천·strict comparison에 진입하지 않는다. canonical profile hydration도 이미 기록된 conflict 상태를 덮어쓰지 않는다.
- 조거 팬츠/파라슈트 카고 팬츠, ZARA Sleeveless Tops/Fine Knit Top, 복합 셔츠재킷, UNIQLO Innerwear의 검증된 cotton T 예외, 민소매 T source의 bra-construction 예외는 오탐으로 차단하지 않는 regression fixture로 고정했다.
- 검증 결과: `build-for-testing` 성공. `FitMatchP0ProductionPathTests` 28/28, `ZARAParserPhase1_5Tests` 20/20, `CategoryValidation5026AuditTests.testCurrentProductionClassifierReclassifiesAll5026Products` 1/1 통과했다. 결과 번들은 `/tmp/FitMatchP1P0Tests-20260824-v2.xcresult`, `/tmp/FitMatchP1ZARATests-20260824.xcresult`, `/tmp/FitMatchP1Corpus5026-20260824.xcresult`다.
- Production Supabase write/migration/seed/backfill/commit/push는 수행하지 않았다. 현재 conflict는 앱 로컬 eligibility/debug trace까지 연결되며 `data_quality_issues` 영속 집계에는 아직 쓰지 않는다. 운영 DB runtime resolver 자체의 conflict 판정 동등화와 read-only production 재검증은 별도 승인·연결 환경이 필요하다.

## 2026-08-21 ZARA 식별자 정정·사용자 가시 WKWebView PoC (현재 권위 상태)

- 아래의 `ZARA KR 공식 실측·카테고리 연동 초안`에서 `analytics.productId`를 size API ID로 본 결론은 폐기됐다. 실제 endpoint는 URL `v1`과 일치하는 `analytics.catentryId`를 사용한다. style, v1/catentry, 내부 productId, productRef는 서로 별도로 보존한다.
- DEBUG 전용 `ZARAWebViewMetadataAudit`를 추가했다. 일반 browser 동작의 ephemeral WKWebView를 사용자에게 보이게 렌더링하고, 사용자가 `비필수 쿠키 거부 후 읽기`를 명시적으로 선택한 뒤 analytics/JSON-LD를 읽는다. CAPTCHA/challenge 우회, custom fingerprint, private cookie는 사용하지 않는다.
- iPhone 17 Pro Simulator(iOS 26.3)에서 티셔츠 `04087432/585646273`, 셔츠 `04166166/545490346`, 팬츠 `06861017/555813567` 3개가 identity 검증과 `catentryId` size API `garment_measure` 응답에 성공했다. 최초 쿠키 선택 전 자동 capture는 `identity_unresolved`였고, 선택 후 성공했다.
- `ZARAParser`는 이제 size API에 catentry만 전달한다. targeted ZARA 15/15, URL dispatch·기존 ZARA·provider 선택 회귀 5/5가 통과했다. 전체 unit suite와 실제 iPhone은 미실행이다.
- 일반 사용자 ZARA 지원은 `ZARAIntegrationAvailability` gate로 닫혀 있다. 공개 공식 metadata API/제휴 권한, 실제 iPhone 안정성, measurement basis, staging DB mapping이 검증되기 전에는 production 지원으로 표시하지 않는다. 운영 Supabase migration/seed/write는 수행하지 않았다.
- 현재 증거 manifest는 `ZARAAudit/zara_webview_poc_samples.jsonl`, 상세 정정은 `FitMatch-ZARA-Phase1.5-Blocker-Resolution-20260821.md`에 있다. 과거 internal productId cache/body-only 결과는 잘못된 API ID의 역사적 증거로만 남긴다.

## 2026-08-21 ZARA KR 공식 실측·카테고리 연동 초안

> 후속 상태: 위 `ZARA 식별자 정정·사용자 가시 WKWebView PoC`로 식별자와 API coverage 결론이 대체됐다.

- 공식 실측 endpoint `itxrest/4/catalog/store/11717/product/{productId}/size-measure-guide?locale=ko_KR`를 확인했다. 명시적 iPhone User-Agent, JSON Accept, 한국어 Accept-Language로 실제 `498702922` 응답은 200 JSON이었고, 헤더 없는 기본 요청은 403이었다. `measureGuideInfo`만 의류 실측으로 쓰고 `sizeGuideInfo` 단독 응답은 신체 권장치이므로 절대 비교 데이터로 대체하지 않는다.
- `ZARAParser`는 명확한 chest/front-back length/sleeve/shoulder/하의 실측 코드만 매핑한다. `back-width`와 `arm-width` 같은 불명확 정의는 unknown record로 보존하며 다른 치수로 추정하지 않는다. measure guide가 없거나 body-size guide만 있으면 partial/자동 비교 불가로 fail-closed다.
- 공식 상품 UI에는 `zara.analyticsData.productId`가 있지만, 앱과 같은 URLSession으로 상품 HTML을 직접 받으면 Akamai interstitial이 관찰됐다. 따라서 현재 URL parser는 challenge를 감지해 중단한다. URL에서 내부 productId를 안정적으로 resolver하는 공식 계약 또는 실기기 검증 전에는 ZARA URL 붙여넣기 성공을 보장할 수 없다.
- 공식 KR GNB와 product metadata `MAN/WOMAN + family`를 기준으로 남성 11개·여성 15개 의미 기반 의류 category seed를 `fitmatch_supabase_seed_zara_categories.sql`에 만들었다. 혼합 landing category는 자동 매핑하지 않는다. `supabase/migrations/20260820223726_add_zara_observation_source.sql`은 observation source allowlist에 zara를 추가한다.
- 운영 Supabase에는 migration/seed를 아직 적용하지 않았고, ZARA parser XCTest는 빌드가 진행 중인 derived data lock 때문에 완료 판정을 내리지 못했다. 상세 근거와 적용 순서는 `Docs/ZARAIntegrationAnalysis-20260821.md`에 있다.

## 2026-08-21 COS KR 공식 실측·카테고리 연동 초안

- COS KR 실제 상품 페이지 `1349394002`에서 article 번호와 색상 상품 코드가 다름을 확인했다. 페이지의 `slitmCd=40B1490048`와 `sectId=254652`로 공식 `getSizeGuide` 엔드포인트를 요청해야 하며, article 번호는 `styleNo`로만 보존한다.
- 해당 상품의 공식 사이즈 가이드는 S–XXL 의류 실측이다. M 기준 어깨 43.0cm, 가슴단면 53.5cm, 등기장 64.0cm, 소매 25.25cm를 실제 COS UI에서 확인했다. `COSParser`는 공식 페이지에서 두 API 식별자를 추출하고, 공식 차트의 어깨·가슴단면·등기장·소매 등 정의가 명확한 값만 FitMatch comparison measurement로 매핑한다. 실패 시 추정하지 않고 partial/자동 비교 불가로 반환한다.
- 서버 직접 요청은 COS Akamai 403이었으나 브라우저의 공식 상품 페이지/사이즈 가이드는 정상 확인됐다. 따라서 API 응답의 실제 JSON 원문 계약을 별도 실기기에서 재검증해야 한다. 현재 decoder는 HTML 표와 header/row 형식 JSON을 보수적으로 처리하며, 맞지 않으면 fail-closed다.
- 공식 GNB는 여성·남성 합계 99개 노드였다. 캠페인/에디트/신상품/모두보기처럼 여러 구조를 혼합한 landing node를 제외하고 FitMatch 의류 분류에 쓸 60개 노드를 `fitmatch_supabase_seed_cos_categories.sql`로 생성했다. COS `sectId`를 external ID로 보존하고, leaf의 FitMatch 대·세부 카테고리를 모두 채운다. `public.sources(code='cos')` 선행이 필요하며 운영 DB에는 아직 실행하지 않았다.
- COS 접근 URL, 식별자, 매핑 원칙과 실행 순서는 `Docs/COSIntegrationAnalysis-20260821.md`에 있다. `COSParser` size guide fixture 테스트 2건을 추가했다. 코드 컴파일은 진행됐으나 Simulator 서비스/SwiftPM cache 권한 오류로 테스트 실행 완료 판정을 내리지 못했다.

## 2026-08-20 connectDB 회원 탈퇴 및 로그인 제공자 확장 경계

- My 화면에 복구 불가능한 삭제 범위를 알리는 2차 확인형 `회원 탈퇴`를 추가했다. 성공 시 Supabase 계정과 사용자 소유 서버 row를 삭제하고, 로컬 `UserFit`·`RecommendationHistory`·동기화 owner/pending-delete 캐시를 제거한 뒤 로그인 화면으로 돌아간다. 공용 쇼핑몰 상품 카탈로그는 삭제하지 않는다.
- 앱은 `FitMatchAccountDeletionServicing` 경계를 통해 인증된 `delete-account` Edge Function만 호출한다. 앱에는 publishable key만 유지하며 service-role key는 서버 함수 안에서만 사용한다. 함수는 confirmation token, gateway JWT, `auth.getUser()`를 모두 확인한 뒤 hard delete한다.
- 운영 Supabase에 `delete-account` v1을 배포했다. 상태 `ACTIVE`, `verify_jwt=true`, 함수 ID `8ce51490-2669-46ca-b4aa-44a9ec538bce`, 인증 헤더 없는 실제 호출은 `401 UNAUTHORIZED_NO_AUTH_HEADER`로 차단됐다.
- `auth.users` 참조를 재검증한 결과 사용자 소유 FK 18개는 `ON DELETE CASCADE`, 분류 감사의 `product_classification_history.reviewed_by` 1개만 의도적으로 `SET NULL`, Storage bucket은 0개다. 따라서 현재 DB에는 계정 hard delete를 막는 restrict/storage owner가 없다. 기존 advisor INFO/WARN 외 이번 함수 때문에 생긴 DB schema 문제는 없으며 DDL은 변경하지 않았다.
- `FitMatchAuthSessionStoreTests`와 `FitMatchClosetSyncCoordinatorTests` 6개가 통과했다. 최초 실행은 새 테스트 파일의 Foundation import 누락으로 빌드 중단됐고 보완 후 최종 `/tmp/FitMatchAccountDeletion-20260820-3.xcresult`에서 6/6 통과했다.
- Apple 공식 요구사항상 Sign in with Apple 계정은 가능하면 Apple REST API로 provider token도 revoke해야 한다. 현재 Supabase `signInWithIdToken`/admin user delete만으로 Apple token은 자동 revoke되지 않으며, 기존 로그인은 Apple authorization code/refresh token을 저장하지 않아 자동 revoke가 불가능하다. Apple 공식 fallback에 따라 탈퇴 확인창과 앱 개인정보처리방침에 `iPhone 설정 > Apple 계정 > Apple로 로그인 > FitMatch 제거` 안내를 추가했다. 완전 자동화를 하려면 후속 단계에서 authorization code를 서버로 보내 Apple token을 교환·암호화 보관하고 삭제 전에 revoke하는 별도 보안 작업이 필요하다.
- 카카오·네이버는 지금 버튼/SDK를 추가하지 않았다. 추후 각 identity를 같은 Supabase user에 명시적으로 link하고, FitMatch 계정 삭제는 현재 provider-neutral 함수를 재사용하되 각 제공자의 원격 권한 revoke adapter를 삭제 전 단계에 추가한다. 이메일이 같다는 이유만으로 계정을 자동 병합하면 안 된다.
- 앱 내 개인정보처리방침과 `Docs/AppStorePrivacyPolicyDraft-20260806.md`를 계정·Supabase 동기화·회원 탈퇴 기준으로 갱신했다. 실제 Apple 계정 가입→데이터 저장→탈퇴 destructive E2E, 공개 웹 개인정보처리방침 게시, App Store Connect App Privacy 답변 갱신은 아직 수행하지 않았다.

## 2026-08-19 connectDB Apple 정식 로그인 1단계

- 기존 `ContentView.LoginView`를 그대로 사용하면서 가짜 로컬 로그인 분기를 제거하고, `SignInWithAppleButton`의 native credential을 Supabase `signInWithIdToken(provider: .apple)`에 nonce와 함께 전달하도록 연결했다. Google·Kakao·Naver 버튼 호출부는 요청대로 주석 처리했다.
- `FitMatchAuthSessionStore`가 Supabase 세션 복구/auth state 변화/로그아웃을 단일 관리한다. `ContentView`는 인증 전 로그인 화면, 인증 후 기존 메인 탭을 표시하며 My 화면의 로그아웃 메뉴도 실제 Supabase 로그아웃에 연결됐다.
- 앱 entitlement에 `com.apple.developer.applesignin = Default`를 추가했다. 앱에는 기존 publishable key만 사용하고 secret/service-role key는 사용하지 않는다. DB 도메인 클라이언트의 자동 anonymous sign-in은 제거해 정식 사용자 세션만 사용자 전용 RPC에 전달되도록 했다.
- generic iOS Simulator `build-for-testing`이 성공했고, Apple nonce 생성/해시 단위 테스트 2/2가 iPhone 17 Pro Simulator에서 통과했다. 결과는 `/tmp/FitMatchAuthTests-20260819-0728.xcresult`다.
- 사용자가 Apple Developer App ID capability와 Supabase Apple provider/Client ID 설정을 완료했다고 확인했다. 이후 generic iOS 실기기용 자동 서명 빌드도 성공했으며, 서명 결과에 `application-identifier=Y344H87QC5.com.ljy4337.fitmatch`, `com.apple.developer.applesignin=[Default]`, 기존 App Group이 모두 포함됐다. 연결된 iPhone 14 Pro가 `unavailable` 상태여서 설치·실제 계정 로그인 검증은 아직 수행하지 못했다.
- 실제 계정 E2E의 남은 작업은 iPhone 연결 복구 후 최초 로그인·앱 재실행 세션 복구·로그아웃 확인이다.
- 옷장/비교 UI의 DB source-of-truth 전환은 사용자 지시대로 아직 시작하지 않았다. Apple 로그인 실기기 검증을 통과한 뒤 별도 단계로 진행한다.

## 2026-08-19 connectDB 도메인 경계·상품 런타임 조회 계약

- 2026-08-18의 `FitMatchSupabaseProductResolver` 단일 RPC 구현을 확장해 `FitMatchSupabaseDomainClient`와 `FitMatchDatabaseDomainServicing` 경계를 만들었다. 하나의 인증 세션으로 상품 resolve/runtime 조회, 옷장 등록, 기준 옷 후보 조회, 비교 시작, 비교 결과 저장 RPC를 호출한다. 기존 resolver 이름은 typealias로 유지했다.
- 상품 runtime DTO에 공용 상품, 현재 canonical 분류, variant, DB `product_size_id`, raw/canonical 실측, 비교 가능 여부·정규화 정책 버전을 포함했다. 이 단계는 계약/클라이언트 구현이며 옷장·비교 화면의 source of truth는 아직 로컬 엔진에서 DB로 전환하지 않았다.
- UUID만 알면 private catalog 전체를 읽는 초기 RPC 안은 보안 검토에서 폐기했다. 운영 Supabase에 `add_scoped_product_runtime_read_contract`(20260818154520)를 적용했다. 같은 retailer API payload의 source/product ID/name/path fingerprint와 제공된 audience/category codes가 DB current와 일치할 때만 `fitmatch_get_product_runtime(jsonb)`가 필요한 projection을 반환한다. anon 실행권은 없고 authenticated/service_role만 실행 가능하다.
- 운영 인증 컨텍스트에서 `E492538`은 `ready`, comparison ready, variant 2, size 12, measurement 72를 반환했다. 이름·경로를 변조한 동일 ID 호출은 `product_evidence_mismatch`로 차단됐다. DB 테스트 transaction은 rollback됐고 운영 상품/사용자 데이터는 변경하지 않았다. 적용 후 `fitmatch_qa.validate_product_runtime_v3()`도 `passed=true`, Gold 5,026/5,026, 모순/공개 권한 누수 0을 유지했다.
- 앱 전체 generic iOS Simulator `build-for-testing`이 성공했다. `FitMatchSupabaseProductResolverTests` 6건이 iPhone 17 Pro Simulator에서 모두 통과했다. 새 검증은 runtime JSON의 size UUID와 canonical measurement decoding을 포함한다. xcresult는 `/tmp/FitMatchConnectDBDomain/Logs/Test/Test-FitMatch-2026.08.19_00-49-26-+0900.xcresult`다.
- Supabase advisor에 새 schema/index 오류는 없고, 새 공개 RPC는 기존 앱 RPC와 같은 `authenticated SECURITY DEFINER` WARN이 추가됐다. 고정 search path, auth 확인, strict payload evidence, anon revoke로 의도적으로 제한했다. private catalog의 RLS+무정책 INFO와 leaked-password protection WARN은 기존대로 남아 있다.
- 남은 실제 전환 작업은 정식 로그인 또는 anonymous auth 선택, 옷장/비교 화면 orchestration 연결, DB 입력↔Swift 입력 및 결과 전 필드 shadow parity다. 인증과 parity 없이 DB 결과를 사용자-facing source of truth로 켜면 안 된다.

## 2026-08-18 connectDB 1단계 shadow 연동

> 후속 상태: 위 2026-08-19 도메인 경계·상품 런타임 조회 계약으로 확장됐다.

- `connectDB` 브랜치에 공식 `supabase-swift` 2.53.0을 추가하고 `fitmatch_resolve_product` RPC용 DTO/클라이언트를 구현했다. 앱에는 publishable key만 포함하며 secret/service-role key는 포함하지 않는다.
- 상품 API 파싱 완료 후 `ShoppingProductViewModel`이 DB를 shadow 조회한다. 현 단계에서는 로컬 분류/추천 결과를 사용자에게 그대로 제공하고, DB 결과는 `matched`, `mismatch`, `reviewRequired`, `unavailable` 상태와 Debug 로그로만 기록한다. DB 장애가 기존 앱 동작을 막지 않는다.
- 알려진 상품의 DB current+confirmed 결과가 로컬과 완전 일치할 때만 matched다. 신규·변경·검토 필요·미분류·비교 불가 결과는 자동 채택하지 않고 reviewRequired로 남긴다.
- DB 검증에서 `E482202 립브라탑(컬러블록)`이 `underwear/women_bra`인데 family만 `tshirt`인 모순 1건을 발견했다. migration 097을 운영 DB에 적용해 family를 `underwear`로 교정했고, 로컬 분류도 쇼핑몰 T셔츠 경로보다 확정된 속옷 major를 우선하도록 수정했다.
- 적용 후 `fitmatch_qa.validate_product_runtime_v3()`는 `passed=true`, 상품 1,577, 스냅샷 3,842, Gold 5,026/5,026, category-family 모순 0이다.
- 신규 테스트 3건은 iPhone 17 Pro Simulator에서 모두 통과했고 generic iOS `build-for-testing`과 서명 제외 Release iOS 빌드도 성공했다. 기존 DB 판정 207건과 현재 production 5,026건 분류 회귀도 각각 통과했다. 5,026건 결과는 output 5,026, invalid 0, 사용자 확인 필요 329다. 현재 유니클로 전체 카탈로그 감사는 첫 상품 처리 직후 simulator test host가 잘못된 포인터 free로 종료되어 통과로 계산하지 않는다. 실패 결과 번들은 `/tmp/FitMatchConnectDBSimulator/Logs/Test/Test-FitMatch-2026.08.18_23-45-57-+0900.xcresult`, 5,026 통과 번들은 `/tmp/FitMatchConnectDBSimulator/Logs/Test/Test-FitMatch-2026.08.18_23-48-27-+0900.xcresult`다.
- 현재 Supabase 프로젝트는 anonymous sign-in이 비활성화되어 있다. `fitmatch_resolve_product`는 authenticated 전용이므로 실제 앱 shadow 호출을 사용하려면 Dashboard에서 anonymous sign-in을 활성화하거나 정식 로그인 세션을 먼저 도입해야 한다. 권한을 anon으로 낮추거나 secret key를 앱에 넣으면 안 된다.
- 아직 DB 분류를 사용자 결과의 source of truth로 전환하지 않았고, 옷장 저장·비교 후보·실측 준비·결과 저장 RPC도 앱에 연결하지 않았다. 다음 단계는 shadow 로그 표본 검증 후 승인받아 진행한다.

## 2026-08-16 DB·앱 207건 판정 적용

- 사용자 명시 승인으로 운영 DB에 074를 직접 실행했고, 이어 최신 production XCTest 첨부 5,026건 전체를 QA와 `product_classification_decisions` 양쪽에 `swift-production-2026-08-16-v3`로 직접 동기화했다. 최초 전 필드 대조에서 133건의 잔여 차이를 발견해 일부만 맞추는 방식을 중단하고 전수 결과를 canonical source로 사용했다.
- 최종 검증은 앱 첨부, DB decision, DB QA를 source/product/category/detail/family/length/confirmation 순으로 정렬하고 동일 NULL 표기 체크섬으로 비교했다. 세 집합 모두 5,026행, MD5 `d314b6d208ffed1d0d4282786e62ff94`, exact 5,026, mismatch 0, review_required 329다. 따라서 보유 corpus에서 앱↔DB 전 필드 동등성은 100%로 확정했다.
- 사용자가 072·073을 실행했다. DB QA↔canonical decision 자체는 5,026/5,026이었지만 최신 앱 첨부 결과와 확인 여부 총계가 DB 327/앱 329로 달라 추가 대조했다. 레이어드 세트 3개(5979739, 6247131, 6361801)는 앱처럼 확인 필요가 정답이고, 명시적 `METAL HALF T-SHIRT` 6833691은 앱의 `tops/short_sleeve/tshirt/short_sleeve` 자동확정이 정답이다.
- 위 4건을 QA와 product decision 양쪽에 맞추고 5,026 DB 내부 postcondition을 검사하는 `supabase/sql/074_post_parity_four_case_alignment.sql`을 생성했다. 사용자가 실행한 뒤 review_required=329인지 확인해야 최종 앱↔DB 완료다.
- 후속으로 `supabase/sql/073_product_classification_decisions_runtime.sql`을 추가했다. 072 적용을 선행조건으로 검사한 뒤 검증된 5,026개 상품 decision을 `fitmatch_catalog.product_classification_decisions`에 승격하고, 상품 ID뿐 아니라 상품명·공식 경로 fingerprint까지 동일할 때만 canonical 결과를 반환하는 service-role 전용 함수를 생성한다.
- 새 함수는 현재 5,026건을 전 필드로 다시 조회해 5,026/5,026이 아니면 transaction 전체를 예외로 중단한다. 신상품 또는 이름·경로 변경 상품은 오래된 규칙 결과를 자동 확정하지 않고 suggestion만 포함한 `requires_user_confirmation=true`로 반환한다.
- 운영 DB에는 072와 073 모두 아직 실행하지 않았다. 사용자가 순서대로 실행한 뒤 마지막 집계와 `E492123` 결과를 받아야 DB 100% 완료로 확정할 수 있다.
- 사용자 승인 후 `ParsedClosetClassification`의 일반 규칙을 보정했다. 셔츠·블라우스 family, 상의 경로 BRA-IN/브라탑, 명시적 T셔츠와 아우터 단어 충돌, `sweat shirt`, 9부 상의 길이, 속옷·홈웨어 길이 오염, 복합 레이어드 세트를 수정했으며 상품 ID별 예외는 추가하지 않았다.
- 독립 판정 207건을 번들 fixture와 XCTest로 고정했다. production parser와 resolver를 실제 실행해 207/207의 대분류·세부분류·family·길이·확인 여부가 모두 일치했고 실패 0이었다. 전체 5,026건도 입력/출력 5,026, 사용자 확인 329, invalid 0, 실패 0으로 다시 통과했다. xcresult는 `/tmp/FitMatchDBLogicAdjudication-After2.xcresult`, `/tmp/FitMatchDBLogicGlobal-20260816.xcresult`다.
- DB QA release `568c3153-a45e-4d4e-b9a7-59c2179733be`의 207건을 같은 정답으로 맞추는 idempotent transaction SQL을 `supabase/sql/072_db_app_adjudication_qa_alignment.sql`로 생성했다. 5,026행/207개 target 사전조건과 207개 postcondition을 포함한다. 운영 DB에는 아직 실행하지 않았다.
- 원격 읽기 전용 점검에서 `fitmatch_taxonomy.evaluate_runtime_classification`과 규칙 세트 `app-hardcoded-parity-2026-08-06-v1`(활성 84개)을 확인했다. 이 별도 DB 실행 함수는 최신 Swift 분류기보다 오래되어 현재 5,026 QA와 런타임 동등하지 않다. QA 정답 데이터 정렬과 DB 실행 함수 동등화를 같은 완료로 보고하면 안 된다.
- `E492123 데님릴렉스셔츠재킷`의 최종 정답은 사용자 확정대로 `tops / shirt / shirt / long_sleeve / 자동확정`이다.

## 2026-08-15 DB·앱 분류 신뢰성 감사

- Supabase와 앱 production 코드는 수정하지 않고 읽기 전용으로 비교했다. 기존 QA 5,026개와 오늘 최신 배치 중 QA에 없던 346개를 합쳐 총 5,372개 고유 상품을 검사했다.
- 현재 main 5,026건 XCTest는 5,026 output, 자동분류 4,703, 확인 필요 323, invalid 0으로 통과했다. DB QA 기대값과 대분류·세부분류·family·길이·확인 여부를 상품별 비교한 결과 4,819개 완전 일치, 207개 불일치, 동등성 95.88%였다.
- 공식 상품 의미 근거가 확정된 challenge 231개에서 앱은 220개, DB는 91개가 근거와 일치했다. 앱만 맞음 129, DB만 맞음 0, 양쪽 모두 맞음 91, 양쪽 모두 잔여 오류 11이다. 전체 신뢰도 우세 판정은 현재 앱 로직이다.
- 오늘 신규 346개는 무신사 148/유니클로 198이며 앱 자동분류 280, 확인 필요 66이다. raw 앱 분류기는 DB rejected 양말 88개를 속옷으로 분류하지만 실제 비교 경로에서는 내장 canonical eligibility가 차단한다. DB는 제외·버전 정책이 강하고 앱은 상품명 구조·세부분류가 강하다.
- 공식 경로·명시적 구조로 확정한 잔여 오류를 보수적으로 102/5,372로 잡은 제품 분류 신뢰도는 98.10%다. 사용자가 정한 90% 분류 기준은 통과하지만 앱 전체 출시 승인은 privacy/support URL, 전체 회귀, 실제 iPhone 동선, archive/TestFlight 게이트와 별개다.
- 근거는 `Docs/TestEvidence/DBLogicReliability-20260815/`의 `report.md`, `summary.json`, 207개 mismatch CSV, 신규 346개 JSON과 `/tmp/FitMatchDBLogicReliability-20260815.xcresult`, `/tmp/FitMatchCurrentBatchReliability-20260815.xcresult`다. 분류/DB 수정은 사용자 승인 전 수행하지 않는다.
- 207개 불일치를 상품명·공식 경로·FitMatch 비교 정책으로 전수 판정했다. 앱 정답 153, DB 정답 16, 양쪽 수정 38, 실물 확인 필요 0이다. `E492123 데님릴렉스셔츠재킷`은 사용자 결정으로 `상의 / 셔츠 / shirt family / 긴팔`로 확정했다. 정답 목표값과 근거는 `db-app-5026-adjudication.csv`에 있으며 아직 앱·DB에는 적용하지 않았다.

## 2026-08-15 커밋 대상 생성 SQL 정리

- 재생성 가능한 최신 누적/유니클로/무신사 스냅샷 SQL 출력 3개를 `../FitMatchArchive/Docs/GeneratedSQL/`로 이동하고 `.gitignore`에 패턴을 추가했다.
- SQL 생성기, 운영 복구·매핑 SQL, DB 최적화 계획, 보고서, 앱 코드와 테스트가 직접 읽는 `CurrentUniqloCatalogInputs.json`은 커밋 대상에 유지했다.
- 코드와 테스트 동작은 변경하지 않았으며 테스트는 실행하지 않았다.

## 2026-08-15 최신 누적 상품 스냅샷 운영 DB 실행 결과

- 사용자가 `FitMatch_LatestCumulativeSnapshots_20260815.sql.txt`를 Supabase SQL Editor에서 실행했다.
- 현재 무신사 스냅샷은 total/distinct 384/384, mapping gaps 0, conditional 342, excluded_review 28, unclassified 14다. 신규 `6842888`은 conditional이며 매핑 연결됐다.
- 현재 유니클로 스냅샷은 total/distinct 1,156/1,156, mapping gaps 5, conditional 326, excluded_review 221, unclassified 0이다. 나머지 609개는 comparable이다.
- 로컬 상세 반영 대상 53건은 유니클로 52 + 무신사 1이며 중복 0, 매핑 미연결 0이다. 유니클로 신규 52건은 conditional 27, excluded_review 25다.
- 유니클로 mapping gaps 5는 직전 운영 상태의 의도적 미연결 액세서리 5건과 수가 같지만, 최종 종료 전에 현재 5개 ID와 상태를 조회해 동일한지 확인해야 한다.

## 2026-08-15 최신 유니클로·무신사 누적 스냅샷 SQL 생성

- 바탕화면 최신 결과를 기반으로 `Docs/FitMatch_LatestCumulativeSnapshots_20260815.sql.txt`와 재생성기 `scripts/generate-latest-cumulative-snapshots-sql.mjs`를 추가했다. 운영 DB에는 실행하지 않았다.
- 유니클로 `20260815-181456`은 발견 1,157개 중 상세 실패 `E479751`을 제외한 1,156개를 `partial` 스냅샷으로 만든다. 로컬 상세 52개를 삽입하고 나머지 1,104개는 DB 전체 성공/부분성공 이력에서 상품별 최신 행을 복원한다. 최신 실행 한 건에만 의존하지 않아 재등장 상품을 보존한다.
- 무신사 `20260815-120901`은 기존 누적 383개를 유지하고 `6842888` 1개를 추가해 384개 성공 스냅샷을 만든다. 98만 건 전체 인덱스는 적재하지 않는다.
- SQL은 advisory transaction lock, 활성 릴리스/기존 행 수 preflight, 배치 범위 재실행, 총행·고유 ID·로컬 신규 수 검증을 포함한다. 하나라도 맞지 않으면 두 공급사 변경 전체가 롤백된다.
- 생성기 입력 검증 결과 유니클로 discovered 1,157/stored 1,156/local payload 52, 무신사 total 384/new 1이었다. SQL은 아직 Supabase에서 실행·검증되지 않았다.

## 2026-08-15 무신사 전체 인덱스·선택 상세 배치 전환

- `scripts/run-musinsa-full-catalog.py`의 기본 실행을 전상품 상세 수집에서 전체 상품 인덱스 탐색(`--phase discover`)으로 변경했다. 상품 상세·실측·옵션은 `--phase collect`와 명시적인 `--product-id` 또는 `--max-products`가 있을 때만 수집한다.
- 카테고리 한 건의 파싱·네트워크 실패가 전체 탐색을 중단하지 않고 해당 카테고리만 현재 실행에서 보류한 뒤 다음 카테고리를 계속 처리한다. 보류 카테고리는 다음 실행 시작 시 재시도된다.
- 상세 수집은 기본 500개 단위로만 메모리에 올려 기존처럼 수십만 개 Future를 한꺼번에 생성하지 않는다.
- 요약에 `index_complete`와 `detail_collection_complete`를 분리했다. 전체 상품 인덱스 완료가 배치 성공 기준이며, 모든 상품 상세 선행 수집은 완료 조건이 아니다.
- 기존 바탕화면 SQLite 약 62만 건은 삭제하지 않고 그대로 이어 쓸 수 있다. 다만 변경 전 이미 실행 중인 Python 프로세스에는 새 코드가 적용되지 않으므로 Control-C 종료 후 바탕화면 command를 다시 실행해야 한다.
- Python 컴파일과 전용 단위 테스트 3건이 통과했다. 새 테스트는 첫 카테고리 파싱 실패 후 다음 카테고리가 정상 완료되는 것을 검증한다. 실제 네트워크 전체 737개 재실행은 수행하지 않았다.

## 2026-08-15 카테고리 DB 적재·앱스토어 출시 진단 최신 상태

### Supabase 상품 스냅샷과 매핑

- 사용자가 Supabase SQL Editor에서 제공된 SQL을 직접 실행하는 방식으로 진행했다. Codex가 운영 DB를 직접 변경하지 않았다.
- 활성 카테고리 릴리스 기반 `fitmatch_catalog.product_collection_runs`, `source_product_snapshots`, `source_category_mappings` 연결을 사용한다. `current_source_products`는 공급사별 최신 `succeeded/partial` 실행 전체를 보여주므로, 신규 행만 별도 성공 실행으로 만들면 기존 상품이 최신 조회에서 사라진다는 점을 반드시 지킨다.
- 유니클로 증분 배치 `20260815-111623`은 현재 발견 1,039, 신규 상세 226/226 성공, 재시도 0, 이전 목록 미발견 67이었다. DB 실행 ID는 `6618738d-d0c5-4a7a-b630-848119c9bc9b`이며 최신 스냅샷 1,039개가 저장됐다.
- 최초 유니클로 SQL이 기존 813개를 carry-forward하면서 `source_mapping_identity`를 null로 복사한 결함이 있었고 복구 SQL로 기존 링크를 복원했다. 원본 생성기도 이후 기존 링크를 보존하도록 수정했다.
- 신규 유니클로 `E485389`의 leaf `150446`은 기존 KIDS 복서브리프 `58650`과 같은 `rejected / not_fitmatch_comparable` 정책으로 활성 릴리스에 명시적 거부 매핑을 추가했다. 상품은 `excluded_review`이며 매핑 identity가 연결됐다.
- 유니클로 최종 운영 의도는 1,039개 중 실제 매핑 누락 0이다. 스카프·장갑 5개는 `excluded_review` 상태의 의도적 미연결이며 오류로 세지 않는다.
- 무신사 증분 배치 `20260815-115051`은 상위 카테고리 4개 첫 페이지에서 188개를 발견했고, 기존 200과 중복 5, 신규 183/183 상세·실측·옵션 수집 성공, 재시도 0이었다. 이 탐색은 전체 무신사 카탈로그가 아니므로 미발견 195개를 판매 종료 또는 삭제로 처리하지 않는다.
- 무신사는 baseline 200개를 유지하고 신규 183개를 더한 누적 스냅샷 383개를 실행 ID `a141f6bf-5218-4c87-9ce2-e77557472f37`로 저장했다.
- baseline 200개 중 category code가 없던 legacy path 18종/80개를 의미가 같은 활성 confirmed mapping에 alias로 연결했다. 최종 무신사 결과는 total 383, linked 383, mapping gaps 0, conditional 341, excluded_review 28, unclassified 14, legacy alias linked 80이다.
- 무신사 unclassified 14개는 링크 실패가 아니라 연결된 `review_required` 정책 결과다. baseline 8, incremental 6이며 상품 분류기 또는 사용자 확인 대상이다.
- 현재 상품 스냅샷은 유니클로 1,039 + 무신사 383 = 1,422개다. DB는 카테고리 후보·정책·이력을 제공하지만 앱 런타임은 아직 DB를 조회하지 않는다.

관련 실행 SQL·생성기:

- `Docs/FitMatch_UniqloCurrentSnapshot_20260815_111623.sql.txt`
- `Docs/FitMatch_UniqloSnapshot_RestoreMappingLinks_20260815.sql.txt`
- `Docs/FitMatch_AddUniqlo150446RejectedMapping_20260815.sql.txt`
- `Docs/FitMatch_MusinsaCumulativeSnapshot_20260815_115051.sql.txt`
- `Docs/FitMatch_LinkMusinsaBaseline80_20260815.sql.txt`
- `scripts/generate-uniqlo-current-snapshot-sql.mjs`
- `scripts/generate-musinsa-cumulative-snapshot-sql.mjs`

### 배치 인수 규칙

- 이후 배치 결과를 받을 때 `summary.json`, `discovered_products.csv`, `new_product_inputs.json`, `pending_retry.csv`를 우선 확인한다.
- 신규 수, 상세 endpoint 성공, 중복 ID, retry, category mapping gap을 검증한다. 탐색이 전체 카탈로그임이 증명되지 않으면 미발견 상품을 삭제하거나 inactive로 확정하지 않는다.
- `current_source_products`에 노출할 성공 실행은 기존 유지 상품과 신규 상품이 모두 포함된 완전한 누적 스냅샷이어야 한다.
- 신규 category code는 기존 의미 동등 mapping을 확인한다. 확실하지 않으면 잘못 confirmed로 만들지 말고 `review_required` 또는 `excluded_review`로 남긴다.

### DB와 앱 통합 상태

- 현재 앱은 `ParsedClosetClassification`, canonical bundle, parser와 matcher의 로컬 규칙으로 동작한다. Supabase 카테고리·상품 스냅샷을 앱이 직접 조회하거나 DB procedure로 최종 분류하는 연결은 아직 없다.
- 권장 최종 흐름은 `상품 API 데이터 → DB category mapping/version 조회 → 기존 상품명·실측 classifier → category/detail/comparisonFamily/status 반환`이다.
- 상품명·실측 규칙 전체를 PL/pgSQL로 복제하면 Swift와 DB 규칙이 갈라질 위험이 크므로, 1차 출시 후 단일 앱 분류 서비스에 읽기 전용 DB lookup, 버전 고정, 캐시, timeout, 오프라인 embedded fallback을 붙이는 방향이 우선이다.

### 1차 App Store 출시 진단

- 진단 기준은 로컬 `main`, HEAD `9264814ea2a8c535ba82de495a69ce75336f16d0`과 현재 미커밋 작업 트리다. 앱·테스트·문서 변경과 untracked 생성물이 많으므로 출시 전 정확한 source revision을 커밋·태그로 고정해야 한다.
- `FitMatch/Info.plist`의 `FitMatchPrivacyPolicyURL`, `FitMatchSupportURL`은 여전히 빈 문자열이다. 공개 HTTPS URL을 넣기 전에는 archive 감사와 App Store 제출 게이트를 통과할 수 없다.
- 로그인 진입은 `ContentView`에서 의도적으로 비활성화됐고 MY의 계정·로그아웃 UI도 비활성화됐다. 현재 1.0은 계정 없는 로컬 SwiftData 앱으로 출시할 수 있으며 로그인은 필수 기능이 아니다.
- iPhone 17 Pro/iOS 26.3 Simulator에서 현재 작업본 Debug build/install/launch가 성공했다. Bundle ID는 `com.ljy4337.fitmatch`, 홈 화면 접근성 요소까지 확인했다. UI 자동화 중 지원 화면 탭 이후 예상과 다른 등록 온보딩 화면으로 전환돼 전체 핵심 흐름 통과로 계산하지 않는다.
- XcodeBuildMCP 전체 test 호출은 300초 제한으로 결과를 받지 못했다. 이후 `-only-testing:FitMatchTests`로 실행했으며 362개를 발견했지만 테스트 프로세스가 조기 종료돼 실제 집계는 passed 6, failed 7, skipped 0이었다. 결과 번들은 `~/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-e60223af795a/result-bundles/test_sim_2026-08-15T03-33-38-128Z_pid47700_95ea5f21.xcresult`이다.
- 실패 7건 중 `LiveReleaseQA1200Tests/testSelectedTenCaseBatchOnPhysicalDevice`는 `FITMATCH_LIVE_QA_BATCH` 환경변수 없이 일반 suite에 포함돼 unwrap 실패했다. `FitPairCorpusXCTests/testUniqlo243OfficialMeasurementCorpus`는 expectation failure다. Current Uniqlo audit와 여러 대형 live/corpus test는 signal kill 또는 test host early exit이므로 제품 실패로 단정할 수 없지만 통과로도 계산할 수 없다.
- 따라서 현재 상태는 빌드 가능이나 자동 회귀 green이 아니며, 오늘 즉시 제출은 NO다. 이전 2026-08-06의 279 pass/0 fail 기록은 최신 P0 수정 이후 현재 작업본의 출시 증거를 대신하지 않는다.

### 출시 전략 결정

- 권고는 DB·로그인을 기다리지 않고 현재 로컬형 MVP를 안정화해 1.0을 먼저 출시하는 것이다. 이미 일정이 약 2주 지연됐으므로 1.0에 Supabase Auth·동기화까지 추가하는 범위 확대는 권하지 않는다.
- 1.0 전 필수: 테스트를 빠른 오프라인 회귀/전수 분류/라이브 네트워크로 분리, 병렬 대형 테스트로 인한 signal kill 제거, 실제 expectation failure 해결, 전체 핵심 회귀 실패 0, 공개 privacy/support URL 연결, 실제 iPhone 6개 핵심 동선, Distribution archive 감사, TestFlight 확인이다.
- 1.1에서 DB mapping lookup과 오프라인 fallback을 연결한다. 로그인·다기기 동기화가 실제 제품 요구로 확정될 때 1.2에서 Auth/RLS/소유권 정책/로컬 데이터 migration/충돌 해결/앱 내 계정 삭제/개인정보 문서와 App Privacy 갱신을 함께 제공한다.
- 계획 추정은 1.0 안정화·제출 준비 2~4일, DB 연동 포함 시 추가 1~2주, DB+로그인+동기화 포함 시 추가 2~3주다. Apple 심사 시간은 별도다.

### 다음 테스트 순서

1. 빠른 오프라인 회귀: 외부 네트워크·환경변수 필요 테스트를 제외하고 병렬 비활성화, 실패 0을 만든다.
2. 상품 전수 분류: 기존 5,026 semantic oracle, 유니클로 현재 상품, 무신사 누적 상품을 공급사/fixture shard별 순차 실행한다. 위험 자동 확정·invalid·parser 계약 오류는 0이어야 하며 `review_required`는 별도 집계한다.
3. 실제 iPhone 수동 6개: 신규 설치/온보딩, 내 옷 직접 등록, 유니클로 링크 비교, 무신사 링크 비교, Share Sheet 왕복, 네트워크 단절·복구. 앱 재실행 후 옷장·기록 보존도 확인한다.
4. 공개 URL 입력 후 Release archive → `scripts/audit-app-store-archive.sh` → Validate App → TestFlight → 동일 핵심 동선 재확인 → 심사 제출 순으로 진행한다.

### 작업 안전 상태

- 이번 출시 진단과 인수인계 갱신에서 앱 소스·DB를 변경하지 않았다. `Docs/CodexSessionHandoff.md`만 갱신한다.
- 보호 파일 `FitMatch/Components/TabBarScrollVisibilityModifier.swift`와 보호 modifier call site에는 diff가 없다.
- commit, push, archive 업로드, App Store 제출은 수행하지 않았다.

## 2026-08-15 무신사 전체 공개 의류 수집 배치

- `scripts/run-musinsa-full-catalog.py`를 추가했다. canonical taxonomy에서 무신사 `confirmed` 및 `review_required` 의류 후보 카테고리 코드 737개를 구성하고, 각 공개 카테고리 응답이 제공하는 서명된 `nextPageUrl`을 마지막 페이지까지 따른다.
- 무신사 현재 목록 응답은 페이지당 60개였다. 서명 URL의 `size=60`을 임의로 `size=200`으로 바꾸면 HTTP 403이므로 고정 200 수집을 가정하지 않는다.
- 원본 HTML·API JSON·이미지는 영구 저장하지 않는다. 상품 메타데이터, 쇼핑몰 카테고리, 성별, 사이즈 실측, 옵션을 바탕화면 `무신사_전체의류_데이터/state.sqlite3`에 저장하고 gzip CSV 3개와 실패 CSV, `summary.json`을 생성한다.
- SQLite에 카테고리별 다음 서명 URL·페이지와 상품별 endpoint 완료 상태를 저장하므로 Control-C 중단 뒤 동일 배치를 다시 실행하면 이어서 수행한다. lock 파일로 동시 중복 실행을 차단한다.
- 실제 소량 검증에서 카테고리 `001001` 1페이지 60개 발견, 상품 1개 상세·실측·옵션 완료, 재실행 시 다음 상품 1개 완료로 58개가 남는 것을 확인했다. 2상품 기준 실측 20행, API 실패 0이며 gzip CSV를 실제 해제해 헤더·행을 확인했다.
- 바탕화면에 `무신사_전체의류_수집.command`를 생성했다. `caffeinate -i`로 실행 중 시스템 유휴 잠자기를 방지한다. 전체 배치는 아직 시작하지 않았다.

## 2026-08-15 무신사 증분 카탈로그 배치

- `scripts/run-musinsa-incremental-catalog.py`를 추가했다. 무신사 공개 카테고리에서 현재 노출 상품 ID를 찾고 누적 state와 비교한 뒤, 신규 ID에만 공식 상품 상세·실측·옵션 API를 요청한다.
- 결과는 `summary.json`, `new_products.csv`, `missing_product_ids.csv`, `pending_retry.csv`로 확인한다. 현재 카탈로그에서 사라진 상품은 검토 목록에만 기록하며 state에서 자동 삭제하지 않는다. 실패한 신규 상품도 state에 저장하지 않아 다음 실행에서 재시도된다.
- 공용 corpus collector의 Musinsa `--discovery-only`가 상세 API를 호출하지 않고 탐색 요약과 요청 지표를 저장하도록 수정했다. dry-run 상세 요청 예상치도 0으로 맞췄다.
- Python 컴파일, 과거 Musinsa checkpoint 기반 신규/누락 오프라인 비교, 실제 상품 994588의 상세·실측·옵션 HTTP 200과 8개 사이즈 행을 확인했다. 전용 단위 테스트 2건은 통과했다.
- 기존 category corpus 전체 단위 테스트 38건 중 29건 통과, 7건 skip, 2건은 아카이브로 이동된 `Docs/Research/CategoryCorpus-live-medium` 원본 fixture 부재로 오류였다. 이번 변경 로직 실패는 아니다.
- 실제 전체 무신사 증분 배치는 아직 실행하지 않았다. 첫 실행은 기본 baseline의 무신사 200개를 기준으로 현재 노출 상품을 신규 수집하므로 요청량과 실행 시간이 클 수 있다.

## 2026-08-14 상세 화면 실기기 성능 진단 로그

- Simulator를 사용하지 않고 실기기에서 내 옷 상세 및 비교 결과 상세 진입 버벅임을 구간별로 확인하도록 `[DetailPerformance]` 로그를 추가했다.
- 화면 생성 기준 `on_appear`, 다음 main run loop, 250ms 안정화까지 elapsed_ms와 SwiftData 조회 개수, 상품 사이즈·실측 사용·제외 개수를 기록한다.
- 상세 화면의 상품·기준 옷 썸네일에 한해 메모리 캐시 적중, 다운로드 시간·바이트·HTTP 상태, 백그라운드 디코딩 시간·픽셀, 전체 준비 시간을 기록한다. 목록 썸네일에는 로그를 켜지 않아 출력 폭증을 막았다.
- 현재 코드 검토상 두 상세 화면 모두 진입 즉시 전체 UserFit/RecommendationHistory 정렬 Query를 수행하는 점이 우선 의심 대상이지만, 로그 증거 전에는 구조를 변경하지 않는다.

## 2026-08-14 유니클로 에어리즘 크루넥 T 분류 보정

- 상품 `E482522`(`AIRism코튼크루넥T`)는 유니클로 원본 경로가 `이너웨어 > 에어리즘 > 코튼`이어서 기존 canonical resolver가 실제 티셔츠 구조를 속옷으로 확정했고, 티셔츠 기준 옷과의 비교가 차단됐다.
- 유니클로 `innerwear`는 실제 속옷과 일반 티셔츠가 섞인 판매 진열 분류임을 실제 E482522 페이지 데이터로 확인했다. `AIRism` 단어 자체는 분류 근거에서 제외하고, 명시적 속옷명 → 명시적 티셔츠 구조명 → 모호한 이너웨어 순서로 판정한다.
- 이너웨어 경로여도 상품명에 `티셔츠`, `크루넥T`, `V넥T`, `T-shirt`가 명시되면 `상의 / 반팔`, `tshirt` family로 분류한다. 상품명에 긴팔 표기가 있으면 `상의 / 긴팔`을 유지한다.
- 브라·브리프·복서 등 명시적 속옷 판정은 이 예외보다 먼저 적용되므로 기존 속옷 상품은 영향을 받지 않는다.
- 저장소의 유니클로 AIRism 고유 사례 79개를 점검했다. 공식 경로 기준 속옷계열 48, 상의 20, 하의 7, 원피스 2, 아우터 1, 기타 1이며 AIRism은 어느 대분류도 뜻하지 않는 기능·소재 라인임을 규칙으로 고정했다.
- 이너웨어 경로의 모든 `...T`를 상의로 올리지 않는다. 코튼 라인이면서 T 구조가 명시된 상품만 상의로 구제하고, 일반·메쉬 AIRism 및 HEATTECH 베이스레이어는 이너웨어를 유지한다. 탱크탑·캐미솔·브라탑·복서·브리프·트렁크·속바지도 속옷을 유지한다.
- 5,026건 1차 전수 검사는 5,026 output, invalid 0, classified 4,698, 사용자 확인 328로 통과했다. 결과 의미 검토에서 이전 실행 결과의 `AIRism속바지(E482154) → bottoms/long_pants`를 발견했으며, 현재 production resolver의 명시적 속옷 우선 규칙과 전용 회귀 테스트로 `underwear/women_panty`를 고정했다.
- AIRism 속옷·상의·조거팬츠·원피스가 각각 `underwear/tops/bottoms/dresses`로 유지되는 대분류 회귀 검사를 추가했다.
- 반팔 및 긴팔 에어리즘 코튼 크루넥 T 회귀 기대값을 추가했고, Simulator용 앱·단위 테스트·UI 테스트 target 전체 `build-for-testing`이 성공했다. 이번 명령은 테스트 실행이 아니라 테스트 바이너리 컴파일 검증이다.

## 2026-08-14 유니클로 공유 URL 선택 색상 썸네일 보정

- 유니클로 공유 URL이 `/E487957-000/00?colorDisplayCode=08` 형태일 때 기존 resolver가 경로의 `-000`을 query의 `08`보다 먼저 읽어 기본색 썸네일을 선택하는 오류를 수정했다.
- 색상 선택 우선순위는 원본 공유 URL `colorDisplayCode` → 최종 redirect URL `colorDisplayCode` → 경로/HTML fallback → 기본 `00`으로 변경했다.
- `colorDisplayCode=08`이 있으면 API 색상 `008`, 이미지 색상 `08`로 정규화되는 회귀 테스트를 추가했다.
- 변경 코드는 Simulator용 앱·테스트 target 전체 컴파일을 통과했다. 두 차례 단일 필터 실행은 Swift Testing 식별자가 매칭되지 않아 `Executed 0 tests`였으므로 단위 테스트 실행 통과로 계산하지 않는다.

## 2026-08-14 iPhone 실기기 A200 시도와 자동화 인프라 차단

- iPhone 14 Pro(iOS 26.6)에서 실제 무신사·유니클로 URL을 사용하는 200개 사용자 여정 테스트를 시작했다. 테스트 저장은 `-fitmatchUITesting` 메모리 전용이라 실제 사용자 옷장과 기록은 변경하지 않았다.
- 최초 실행에서 11개 여정이 오류 없이 완료됐다. 12번 유니클로 코듀로이쇼트재킷은 앱이 무신사 코트를 `사용자 선택 확장 비교 · 공통 실측 4개` 후보로 정상 표시했으나, 자동화가 지정 상품명만 찾도록 고정돼 후보를 누르지 못했다.
- 자동화가 화면의 대체 실측 후보를 선택하고 `추천 결과 아님`도 정상 차단으로 인정하도록 보완했다. A200 메서드는 첫 assertion에서 중단하도록 바꿔 실패 뒤의 케이스를 PASS로 잘못 출력하지 않는다.
- 보완 후 두 번 재실행했지만 UI 테스트 러너가 각각 약 197초, 95초 후 Xcode IDE 연결을 잃고 code 74로 종료됐다. 두 결과는 앱 비교 실패가 아니라 실기기 자동화 인프라 실패이며 200건 통과로 계산하지 않는다.
- 현재 유효 결과는 11건 통과, 앱 비교 실패 확정 0, 하네스 오판정 1, runner 종료 2회다. 상세 보고서는 `Docs/PhysicalA200Report-20260814.md`다.
- 후속은 기기 연결을 새로 만든 뒤 20건 단위 독립 xcresult 배치로 분할하고, 완결된 배치만 합산해 200건을 판정한다.

## 2026-08-14 실기기 URL 사용자 여정 및 기준 옷 재등록 UX

- 비교할 옷이 없는 화면의 등록 CTA가 수동 등록으로 바로 이동하던 연결을 수정했다. 이제 `상품 링크로 불러오기`와 `직접 입력하기`를 먼저 선택하며, 등록 완료 후 진행 중인 비교로 돌아와 후보를 다시 계산한다.
- 연결된 iPhone 14 Pro에서 `-fitmatchUITesting` 메모리 전용 저장소를 사용해 실제 사용자 데이터와 분리된 실기기 테스트를 수행했다.
- 유니클로·무신사 기준 옷 2벌 URL 등록과 비교 상품 2건 직접 URL 입력: 1 test / pass / 0 failures, `/tmp/FitMatchPhysicalDirectURL-20260814-v2.xcresult`.
- 실제 무신사 하의·아우터 10개 직접 URL 비교: 10/10 사용자 여정 완료, 1 test / pass / 0 failures, `/tmp/FitMatchPhysicalA10-20260814.xcresult`.
- 유니클로 옷 URL 등록 → 비교 → 비교 기록이 있는 옷 삭제 → 동일 상품 비교 시 필요한 옷 부재 안내 → 등록 방법 선택 → URL 재등록 → 비교 후보 복구: 1 test / pass / 0 failures, `/tmp/FitMatchPhysicalDeleteRecovery-20260814-v2.xcresult`.
- 첫 삭제 자동화는 상세 화면에서 바로 삭제 버튼을 찾는 잘못된 테스트 경로로 실패했다. 실제 사용자 경로인 `상세 → 편집 → 삭제`로 수정해 재실행한 결과 통과했다.
- 첫 직접 URL 자동화는 현재 UI의 `비교할 옷 선택` 문구를 인식하지 못해 중단했다. 현재 문구와 등록 CTA를 인식하도록 테스트를 보완한 뒤 재실행해 통과했다.

## 2026-08-14 저장소 대용량 생성 자료 외부 아카이브

- 앱 코드, 앱 번들 데이터, 테스트 입력 fixture, 설계·정책 문서와 이 누적 인수인계서는 저장소에 유지했다.
- 생성된 연구 코퍼스, 원본 수집 체크포인트, 테스트 증빙과 날짜별 과거 handoff 약 4.0GB를 저장소의 형제 폴더 `../FitMatchArchive/Docs/`로 이동했다.
- 동일 계열 생성물이 다시 Git 변경 목록에 잡히지 않도록 `.gitignore`에 경로 패턴을 추가했다.
- 기존에 Git이 추적하던 아카이브 대상은 다음 커밋에서 삭제로 기록되며, 과거 커밋의 용량은 별도 히스토리 정리 전까지 유지된다.
- 코드와 Xcode 프로젝트 파일은 이 정리에서 수정하지 않았고 빌드·테스트는 실행하지 않았다.

## 2026-08-14 공유 상품 선택 색상 썸네일 보존

- 유니클로 공유 URL에서 해석한 `colorDisplayCode`와 상품 번호가 일치하는 색상별 이미지 URL을 우선 사용하도록 수정했다.
- 색상별 사이즈표 조회가 실패해 `000` 기본색으로 재시도되더라도 기본색 이미지가 공유 URL의 선택 색상 썸네일을 덮어쓰지 않도록 했다.
- 무신사 공유 URL에 `goodsNo`, `goods_no`, `productId`, `product_id` variant 식별자가 있으면 경로의 대표 상품 번호보다 우선하도록 수정했다. 최종 상품 API의 해당 variant 썸네일을 사용한다.
- 회귀 테스트 2건(`uniqloSelectedColorThumbnailIsNotReplacedByGenericSizeChartImage`, `musinsaURLResolverPrefersExplicitVariantProductID`)을 iPhone 17 Pro Simulator에서 실행했고 2 tests / pass / 0 failures였다. 결과: `/tmp/FitMatchColorThumbnailDerivedData/Logs/Test/Test-FitMatch-2026.08.14_12-25-12-+0900.xcresult`.
- 실제 쇼핑 앱이 공유 payload에 색상 또는 variant 정보를 포함하지 않는 경우에는 선택 상태를 복원할 수 없다. 실제 iPhone Share Sheet 검수는 남아 있다.

## 2026-08-14 기준 옷 부재 안내 및 반팔·긴팔 부분 비교 (빌드 미확인)

- `CompareFlowSheet`의 기준 옷 부재 화면을 빈 옷장, 필요한 성인/아동 의류 부재, 필요한 의류 카테고리 부재로 구분했다.
- 화면에 가져온 상품명과 FitMatch 분류, 현재 옷장의 카테고리별 보유 수량을 표시하고, 필요한 기준 옷을 직접 등록하는 CTA를 추가했다. 등록 화면은 가져온 상품 자체가 아니라 사용자가 보유한 기준 옷을 수동 등록하며 기준 옷 토글을 기본 ON으로 연다.
- 반팔↔긴팔 상의는 같은 garment family이고 어깨·가슴·총장 중 공통 실측이 2개 이상일 때만 사용자가 직접 선택하는 확장 비교를 허용한다. 자동 기준 옷 선택은 여전히 동일 길이를 우선하며 길이가 다른 상의를 자동 선택하지 않는다.
- 반팔↔긴팔 확장 비교에서는 `sleeveLength`를 비교·점수에서 제외하고, 결과 근거에 소매 구조 차이와 몸판 공통 실측만 사용했음을 기록한다.
- 긴바지↔반바지와 아우터 몸판 길이 차이는 핵심 구조 차이이므로 계속 차단한다.
- 관련 회귀 기대값을 수정했으나 사용자가 회사에서 Xcode 빌드와 실기기 화면을 확인하기로 했으므로 이번 세션에서는 빌드·테스트를 실행하지 않았다. 컴파일 및 실제 레이아웃은 미확인 상태다.

### 사용자 지정 테스트 명칭

- 사용자가 말하는 `A테스트`는 2026-08-14 수행한 2,000건 사용자 여정 QA 방식을 뜻한다.
- 실제 무신사·유니클로 상품으로 가상 옷장을 구성하고 기준 옷 ON/OFF, 자동 비교, 수동 선택, 정상 차단, 분류 오류, 비교 오류를 현재 production 파서·분류·비교 로직과 실제 FitMatch UI/UX 문구까지 함께 검증한다.
- 사용자가 `A테스트 N건 진행`이라고 요청하면 같은 형식으로 N건을 수행하고, 쇼핑몰 분류와 FitMatch 분류를 명확히 구분하며 실제 상품명·링크·옷장 구성·기준 옷 상태·표시 UI·내부 QA 판정을 기록한다.

### 안내 문구 전수 정리 후속 수정

- 반팔↔긴팔 부분 비교에서 `sleeveLengthMismatch` 제외 사유를 별도로 저장해 결과 화면에 `반팔과 긴팔은 소매 구조가 달라 제외했습니다.`라고 표시한다. 일반 `categoryPolicy` 사유와 구분한다.
- 결과 화면에서 다른 기준 옷이 없을 때 빈 옷장, 아동복 부재, 성인 의류 부재, 필요한 세부 종류 부재를 구분해 안내하고 현재 옷장 카테고리 수량을 표시한다.
- 구형 `ShoppingProductFormView`의 `비교 가능한 상품이 없습니다`, `정확도가 낮아질 수 있습니다`, `내 옷장에 추가` 문구를 기준 옷 등록·호환 실측 제외 중심 문구로 교체했다.
- 비교한 쇼핑 상품 저장 기능은 실제 구매 완료 상품을 바로 등록하는 정상 흐름 때문에 제거하지 않았다. 대신 결과와 등록 시트 전체를 `보유한 옷으로 등록`으로 바꾸고 `실제로 가지고 있는 상품인 경우에만`, `구매 후보는 등록하지 마세요`를 명시했다.
- 이번 후속 수정도 사용자가 회사에서 Xcode 빌드와 실기기 UI를 확인하기로 한 상태라 빌드·테스트는 실행하지 않았다.

- 최종 갱신: 2026-08-13 (Asia/Seoul)
- 저장소: `/Users/jinyoung/Documents/Projects/FitMatch/FitMatch`
- 브랜치: `리뉴얼_1`
- 기준 HEAD: `49834c7`

> 이 파일이 새 세션에서 읽을 단일 최신 누적 인수인계서다. 아래 과거 수치와 최신 상태가 충돌하면 `0. 현재 최신 상태`와 실제 코드를 우선한다. 날짜가 붙은 `CodexSessionHandoff-YYYYMMDD.md`는 당시 상세 기록으로만 보존한다.

## 0. 현재 최신 상태

- 커밋·푸시하지 않은 대규모 로컬 변경이 존재한다. 사용자 작업과 조사 자료를 임의로 초기화·삭제·정리하지 않는다.
- `FitMatch/Components/TabBarScrollVisibilityModifier.swift`와 보호된 modifier 호출부는 변경하지 않았다.
- Supabase 작업은 사용자가 재개하기 전까지 보류한다.
- 커밋·푸시·배포는 사용자의 명시적 요청이 있어야 한다.

### 현재 작업 컨텍스트 — 다음 실행 전 읽기

- 2026-08-13 카테고리 분류 정책 수정이 완료됐다. 최신 정책은 `20. 2026-08-13 카테고리 증거 우선순위 데이터 감사`가 우선이다.
- 공식 URL/API production 파서를 사용하는 비-UI Simulator XCTest 비교 감사는 실행·구조화 증거 생성까지 완료했다. 최신 권위값은 이 절의 `비교 자격 정리 후 최종 재실행`을 따른다.
- 테스트 목표:
  1. 유니클로·무신사 공식 숫자 실측 상품만 production 파서로 분석한다.
  2. 유니클로 기준옷 → 유니클로·무신사 비교상품, 무신사 기준옷 → 유니클로·무신사 비교상품 순으로 각각 독립된 메모리 상태에서 비교한다.
  3. 기준옷 등록 가능 여부, 자동/수동 비교 가능 여부, 추천 생성 여부, 비교 불가 사유와 UX 복구 경로를 기록한다.
- 기준옷·비교상품은 실제 사용자 SwiftData 옷장에 저장하지 않는다. `Product → UserFit → ComparisonProfileMatcher → RecommendationService` production 경로의 테스트 객체만 사용한다.
- `기타`·복합·공식 경로 모호 상품은 새 정책대로 자동 43개 taxonomy에 억지 배정하지 않는다. 사용자 카테고리 선택 필요 상태로 따로 기록한다.
- 비교 불가 사유 분류: 공식 실측 없음, 파싱 실패, 분류 모호, 성별/연령 보호, 구조 불일치, 길이 불일치, 공통 실측 부족, 같은 구조 기준옷 없음.
- 비교 불가 UX는 실제 화면 실행으로 주장하지 않는다. 이번 범위에서는 ViewModel/View 분기의 안내 상태와 다음 행동(분류 선택, 기준옷 직접 선택, 유사 의류 수동 비교, 내 옷장 추가, 재시도)을 코드 기준으로 기록한다.
- 완료 기준: 허용 비교는 추천 생성까지 확인하고, 차단은 사유와 다음 행동이 모두 설명 가능해야 한다. production 수정은 사용자 승인 전 금지다.

### 최신 제품·UX 정책

- FitMatch는 체형 추정이 아니라 사용자가 잘 입는 기준 옷의 실측과 구매 상품의 실측을 비교한다.
- 온보딩에서 처음 등록하는 잘 맞는 옷만 기준 옷 토글을 기본 ON으로 제공하며 일반 등록은 기본 OFF다.
- 링크 상품 미리보기는 다른 URL을 다시 불러오기 위해 유지하지만 중복 읽기 전용 확인 화면은 제거했다.
- 기준 옷 후보를 누르면 중복 확인 없이 즉시 비교하고 처리 중에는 후보 입력을 잠근다.
- 기준 옷 순위는 브랜드보다 의류 구조·측정 방식·공통 실측·실측 유사도를 우선한다.
- 동일 종류 자동 후보가 없으면 기존 화면에서 유사 옷 직접 선택 또는 해당 상품 내 옷장 추가를 제공한다.
- 비교 상품 저장 후 자기 자신과 비교하지 않고 홈으로 복귀한다.
- 저장 성공은 Alert가 아니라 비차단 토스트로 표시하고 연속 저장을 막는다.
- 반팔·민소매 상의는 공통 핵심 실측 2개 이상일 때 사용자 선택 확장 비교를 허용한다. 자동 선택은 동일 구조 중심을 유지한다.
- 긴팔 티셔츠, 셔츠, 니트는 서로 별도 구조군이다. 스웨트셔츠와 후드는 직접 호환한다.
- 셔츠는 반팔·긴팔 티셔츠 세부군으로 덮어쓰지 않고 셔츠 구조를 보존하며 길이는 canonical 속성으로 관리한다.

### 최신 자동 검증 요약

- 무신사 3개 긴바지 상품: 6개 방향 × 기준 사이즈 4개 = 24개 조합을 production 경로로 두 차례 실행했고 결과가 일치했다.
- 카테고리 라이브 감사: 71개 선택, 70개 로드, 2,970개 전 방향·전 기준 사이즈 조합 실행.
- 비교 허용 1,757개는 모두 추천 완료, 정책상 차단 1,213개, 근거 부족 0개, 비결정성 0개, 최고점이 아닌 추천 0개다.
- 기존 저장 데이터 `0. S` 표시 정규화와 과거 `canonicalEligibility=false` 긴바지의 재진입·backfill·비교 회귀 6개가 통과했다.
- 혼합 유니클로 카테고리 수정 후 단위 회귀 2개, 실상품 라이브 3개, 전체 2,970개 조합 재검증이 통과했다.
- Safari 시스템 공유 시트 E2E는 Simulator에서 FitMatch 확장이 노출되지 않아 앱 비교 단계 이전 환경 차단으로 분류했다.

### 최신 남은 문제

- 유니클로 `E488923 BT릴랙스핏레깅스(10부·프린트)`는 공식 사이즈표는 있으나 베이비 상품 형식을 production 파서가 처리하지 못해 성인 비교에서 제외했다. 키즈·베이비 파서 지원 과제로 분리한다.
- 무신사 숏 레깅스와 유니클로 라운지웨어·블레이저·원피스·재킷·패딩은 실제 실측 표본이 플랫폼별 3개 미만이라 이번 카테고리 전수 감사에서 완료로 계산하지 않았다.
- 전체 핵심 스위트의 `manualLengthMismatchAllowsExplicitExtendedComparison` 기대값 2건은 긴팔 니트↔반팔 니트와 긴바지↔쇼츠를 허용하는 구형 정책이다. 현재 production 로직은 승인된 정책대로 두 조합을 차단하므로 로직 수정 대상이 아니며, 테스트 기대값 갱신만 보류돼 있다.
- 미구매 비교상품을 `내 옷장`에 저장하는 현재 기능은 사용자가 실제 보유한 옷과 구매 후보를 섞을 수 있다. 기능은 유지 중이지만 명칭 분리·저장 위치·정책은 아직 제품 결정이 필요하다.
- 실제 아이폰의 쇼핑몰 앱 Share Sheet → FitMatch → 저장 → 기록 재진입은 최종 사람 검수가 필요하다.

### 2026-08-13 공식 실측 교차 비교 최신 재실행

- 정확한 XCTest 브리지 2건을 공식 URL/API로 재실행해 2 tests / pass / 0 failures를 확인했다. 잘못된 메서드명으로 0건 실행된 첫 번들은 증거에서 제외했다.
- [확장 실행으로 대체됨] 유니클로 기준옷 17개 × 실제 로드 대상 70개의 비구조화 실행에서는 strict 59가 한 번 관찰됐으나 이후 동일 빌드에서 재현되지 않았다.
- 무신사 기준옷 30개 × 실제 로드 대상 70개: 2,097조합, strict 71, manual extended 134, blocked 1,892, recommendation failure 0.
- 공식 입력 71개 중 유니클로 `E488923` 1개는 사이즈 정보를 찾지 못해 두 실행 모두 제외됐다.
- 중간보고: `Docs/TestEvidence/OfficialMeasurementComparison-20260813/report.md`.
- [후속 보강 완료] 당시에는 조합별 차단 사유 JSON이 없었으나 아래 구조화·확장 실행에서 보강됐다.

#### 구조화 조합 증거 후속 보강

- `CategoryLiveComparisonAuditTests`가 각 조합마다 공식 실측/파싱/분류/등록/자동·수동 호환/추천/차단 사유/UX 상태/다음 행동을 JSON 한 줄로 출력하도록 보강했다. Production 앱 동작은 변경하지 않았다.
- 최신 권위 실행: `/tmp/FitMatchOfficialStructuredAuthoritative-20260813.xcresult`, 2 tests / pass / 0 failures.
- [확장 전 역사값] `combinations.json` 최초 구조화 실행은 3,287행, 자동 138, 수동 확장 186, 차단 2,963이었다. 현재 파일은 아래 확장 실행의 3,567행으로 교체됐다.
- production matcher의 실제 첫 차단 조건 기준 pair 분포: 의류 구조 2,638, 분류 모호 210, 길이 69, 성별·연령 46, 공통 실측 부족 0. 같은 구조 기준옷 없음은 target-level 상태로 유니클로 기준 31개, 무신사 기준 4개다.
- 유니클로 구조화 실행을 동일 빌드로 반복했고 사유·UX 표시를 제외한 1,190개 핵심 비교 결과 SHA-256 `a7cf8cb54e2751a38698ea83cca2e1ea33d128f85c897448cd6531fc6e956a0d`가 완전히 일치했다. strict 67, manual extended 52, blocked 1,071로 재현됐다. 앞선 strict 59 관찰은 최신 동일 빌드에서 재현되지 않았다.
- [확장 전 역사값] 당시 기준옷 커버리지는 유니클로 17/43, 무신사 30/43이었다. 최신은 아래 18/43, 33/43이다.

#### 확장 기준옷 후보 70개 후속 실행

- 기존 상위 3개 후보를 제외한 유니클로 35개와 무신사 35개를 공식 URL/API production 등록 probe로 검사했다.
- 신규 등록 성공:
  - 유니클로 `E450259 옥스포드셔츠` → `tops/shirt`.
  - 무신사 `4661063 우먼즈 코튼 자카드 퍼프 슬리브 블라우스` → `tops/blouse`.
  - 무신사 `4568168 멀티포켓 후드 다운 점퍼` → `outerwear/short_padding`.
  - 무신사 `5320032 2WAY 절개 라인 빈티지 피그먼트 스웨트 집업` → `outerwear/other_outerwear`.
- 확장 후 기준옷: 유니클로 18/43, 무신사 33/43.
- 확장 전체 교차 실행: `/tmp/FitMatchOfficialExpandedAuthoritative-20260813.xcresult`, 2 tests / pass / 0 failures.
- 3,567조합: 자동 153, 수동 확장 204, 차단 3,210, 추천 실패 0, UX 복구 경로 없음 0.
- pair 차단 분포: 의류 구조 2,798, 분류 모호 280, 길이 84, 성별·연령 48, 공통 실측 부족 0. 같은 세부 구조 기준옷 없음은 유니클로 기준 대상 16개, 무신사 기준 대상 3개.
- 최신 `combinations.json`과 `summary.json`은 확장 실행 결과로 교체했다.

#### 유니클로 공식 카테고리·무신사 심층 후보 후속

- 유니클로 공식 카테고리 탐색 체크포인트에서 기존 코퍼스에 없던 53개 후보를 추출해 production 등록 probe를 실행했다.
- 신규 확보: `E486703` → `tops/hoodie`, `E471808` → `tops/sweatshirt`. 유니클로 기준옷은 20/43이 됐다.
- 유니클로 `short_pants` 공식 카테고리 후보들은 production에서 대부분 `bottoms/shorts`로 저장됐고, 경량패딩 후보 `E489110`은 `outerwear/padding`으로 저장됐다.
- 무신사 코퍼스 후보 깊이를 target당 10→50으로 늘려 신규 80개(`short_pants` 40, `jumper` 40)를 probe했으나 등록 성공은 0개였다.
  - `short_pants`는 공식 숫자 실측이 있는 로드 상품이 모두 `bottoms/shorts`로 저장됐다.
  - `jumper`는 `jacket`, `windbreaker`, `anorak`, `padding`, `fleece`, `blazer` 등 더 구체적인 코드로 저장됐다.
  - 따라서 두 코드는 추가 상품 탐색만으로 채워질 가능성이 낮고, 43 taxonomy에서 독립 코드를 유지할지 병합할지 정책 결정이 필요하다. Production 코드는 수정하지 않았다.
- 최신 교차 실행: `/tmp/FitMatchOfficialExpanded20x33-20260813.xcresult`, 2 tests / pass / 0 failures.
- 유니클로 20개 + 무신사 33개 기준옷, 대상 70개, 3,707조합: 자동 173, 수동 확장 204, 차단 3,330, 추천 실패 0, UX 복구 없음 0.
- 최신 pair 차단 분포: 의류 구조 2,914, 분류 모호 280, 길이 86, 성별·연령 50, 공통 실측 부족 0. 동일 세부 구조 reference 없음은 유니클로 기준 대상 8개, 무신사 기준 대상 3개.

#### 비교 자격 정리 후 최종 재실행

- 공식 숫자 실측과 저장 taxonomy는 통과했지만 `canonicalEligibility=false`인 무신사 기준옷 4개(`1958464`, `4154987`, `1195307`, `5320032`)를 `ReferenceClosetRegisteredButIneligibleMusinsa.json`으로 분리했다.
- `outerwear/jacket`은 eligibility=true 후보 `1576682`로 대체했다. 따라서 무신사는 등록 성공 target code 33개와 실제 비교 가능한 기준옷 30개를 구분한다. 유니클로 비교 가능 기준옷은 20개다.
- 최신 권위 실행: `/tmp/FitMatchOfficialEligible20x30-20260813.xcresult`, `/tmp/FitMatchOfficialEligible20x30-20260813.log`; 정확한 XCTest 2건 / pass / 0 failures, 145.113초.
- 대상 70개에 대해 3,497조합을 기록했다. 이론상 3,500에서 무신사 기준옷과 동일 상품인 3쌍(`1108007`, `1572220`, `2387085`)은 자기 비교 방지로 제외됐다.
- 자동 171, 수동 확장 204, 차단 3,122, 추천 실패 0, 복구 경로 없음 0. pair 차단 사유는 의류 구조 2,986, 길이 85, 성별·연령 50, 분류 모호 1이다.
- target-level UX 상태는 자동 비교 결과 2,159, 기준옷 선택 728, 자동 후보 없음 590, 사용자 카테고리 선택 20이다. 동일 세부 구조 기준옷이 없는 고유 대상은 유니클로 기준 9개, 무신사 기준 3개다.
- `Docs/TestEvidence/OfficialMeasurementComparison-20260813/combinations.json`, `summary.json`, `report.md`를 이 실행으로 교체했다. 이전 20×33 수치는 eligibility 정리 전 역사값이다.

#### 로컬 전체 공식 코퍼스 누락 후보 보강 재실행

- 남은 사용량 78% 시점에서 체크포인트가 75% 잔여로 수정됐다.
- 로컬 전체 공식 실측 코퍼스 2,370개 ID와 cumulative production 분류를 43개 기준옷 taxonomy에 다시 대조했다. 과거 probe에서 빠진 57개(유니클로 27, 무신사 30)를 `ReferenceClosetRemainingLocalOfficialProbeCandidates.json`으로 전수 probe했다.
- probe는 `/tmp/FitMatchRemainingLocalOfficialProbe-20260813.xcresult`에서 1 test / pass. 등록 성공 22개 중 키즈·베이비를 제외하고 성인 단품 3개만 채택했다: 유니클로 `E487394` padding, 무신사 `5386464` jumper, `4787764` three_quarter_leggings.
- 최신 비교 가능 기준옷은 유니클로 21/43, 무신사 32/43이다. 공식 실측·저장 taxonomy 등록 target code는 무신사 35/43이나 canonical eligibility 때문에 실제 비교 가능 수와 구분한다.
- 최신 권위 교차 실행: `/tmp/FitMatchOfficialEligible21x32-20260813.xcresult`, `/tmp/FitMatchOfficialEligible21x32-20260813.log`; 2 tests / pass / 0 failures.
- 3,707조합: 자동 173, 수동 확장 219, 차단 3,315, 추천 실패 0, UX 복구 없음 0. 차단 사유는 의류 구조 3,176, 길이 86, 성별·연령 53, 분류 모호 0이다.
- 동일 세부 구조 기준옷 없는 대상은 유니클로 기준 8개, 무신사 기준 3개로 감소했다. `combinations.json`, `summary.json`, `report.md`를 최신 실행으로 교체했다.
- 목표의 “각 상품” 증거를 조합 원장과 분리하기 위해 `Docs/TestEvidence/OfficialMeasurementComparison-20260813/products.json`을 추가했다. 71개 입력(무신사 40, 유니클로 31), 로드 70, 파싱 실패 `E488923` 1개와 재시도 행동을 모두 기록한다.
- 보고서에 요구사항별 권위 증거 매트릭스를 추가했다. 3,707 pair 필수 필드 누락 0, 비교 허용 후 추천 누락 0, 차단 사유 누락 0, UX 복구 누락 0, 자기 비교 0을 재확인했다.
- 상품 유입 처리 방침과 실제 공식 상품 10개 예시는 `Docs/TestEvidence/OfficialMeasurementComparison-20260813/processing-policy-and-10-examples.md`에 정리했다. 조합 JSON의 `automaticComparisonAvailable`은 실제 대표 기준옷 자동 선택 여부가 아니라 pair 단위 기본 compatibility 허용값이므로, 화면 자동 선택(`referenceSelectionPlan`에서 선호 대표 기준옷 정확히 1개)과 구분해야 한다.
- 비교군 분류 마감에서 감사 필드를 `pairComparisonLevel`, `directComparisonAvailable`, `baseExtendedComparisonAvailable`, `automaticCandidateAvailable`, `automaticallySelectedReference`, `referenceSelectionRequired`로 분리했다. 기준옷 `UserFit`에는 실제 semantics대로 `isRepresentative=true`를 설정했다.
- 최신 권위 실행은 `/tmp/FitMatchOfficialRepresentativeFinal-20260813.xcresult`와 `.log`: 2 tests / pass. 3,707 pair 중 direct 130, 기본 확장 43, 수동 확장 219, 차단 3,315, 실제 자동 후보 pair 130, 실제 자동 선택 84, 추천 실패 0이다.
- 대표 기준옷 자동 선택, 복수 대표 결정성, 비대표 단일/복수 후보 사용자 선택, short-top 수동 확장, exact-product 기타 선택 재사용, polo↔티셔츠 호환 등 7개 경계 정책을 XCTest bridge로 실행했다. `/tmp/FitMatchComparisonClassificationBoundariesBridge-20260813.xcresult`, 1 test / pass(내부 정책 7개).

## 1. 새 세션에서 가장 먼저 할 일

1. `AGENTS.md`와 이 문서를 끝까지 읽는다.
2. 현재 작업 트리를 보존한다. `reset`, `clean`, `stash`, `commit`, `push`를 사용자가 명시적으로 요청하지 않는 한 실행하지 않는다.
3. 다음 명령으로 현 상태만 확인한다.

```bash
cd /Users/jinyoung/Documents/Projects/FitMatch/FitMatch
git status --short
python3 scripts/review-fit-pair-candidates.py --summary
```

현재 작업 트리는 대규모 미커밋 상태다. 조사 원본과 회귀 코퍼스도 포함되어 있으므로 용량이 크다는 이유로 삭제하면 안 된다.

Supabase 작업은 사용자가 집에서 하기로 하고 보류했다. 사용자가 명시적으로 재개하기 전에는 원격 DB에 SQL을 적용하거나 보안 설정을 변경하지 않는다.

## 2. 사용자의 최종 목표

FitMatch로 들어온 무신사·유니클로 상품을 다음 순서로 안정적으로 처리하는 것이 목표다.

1. 브랜드 공식 URL/API/HTML에서 상품 정체성, 공식 카테고리, 사이즈표를 수집한다.
2. 브랜드 공식 카테고리를 우선 근거로 FitMatch 대분류·세부분류에 매핑한다.
3. 공식 카테고리만으로 길이·구조를 확정할 수 없을 때에만 상품명과 검증된 키워드를 보조 근거로 사용한다.
4. 내 옷장 기준 옷과 비교 상품이 같은 의류군·길이·구조이고 정확한 실측 코드가 호환될 때만 자동 비교한다.
5. 실측 근거가 부족하거나 의미가 다르면 높은 신뢰도를 표시하지 않고 비교 보류 또는 수동 선택으로 보낸다.
6. 현재 앱의 하드코딩 분류 동작과 DB 규칙을 동등하게 관리해, 나중에 하드코딩을 제거하고 DB 조회로 바꿔도 기존 동작이 유지되게 한다.
7. 향후 Zara, COS, H&M 등도 동일한 공급사 어댑터와 표준 분류·실측 계약에 붙일 수 있게 한다.

보존해야 하는 제품 원칙은 다음과 같다.

- Reference Garment 개념을 유지한다.
- `category`와 `detailCategory` 구조를 유지한다.
- 가슴둘레와 가슴단면, 일반 소매와 화장, 앞기장과 뒤기장을 같은 값으로 취급하지 않는다.
- 공급사가 제공하지 않은 실측값을 추정해서 만들지 않는다.
- 자동 비교가 불가능한 경우 억지로 추천하지 않는다.
- 기존 UX와 아키텍처는 사용자의 명시적 요청 없이 바꾸지 않는다.

## 3. 현재 상태 한눈에 보기

| 영역 | 현재 상태 | 해석 |
|---|---:|---|
| 전체 앱 완성도 | 약 95% | 방향성 평가이며 테스트 통과율이 아님 |
| 핵심 코드·자동검증 | 약 99% | 현재 정의된 자동 게이트는 실패 0 |
| 누적 고유 상품 분류 | 2,560건 | 무신사 1,545 + 유니클로 1,015 |
| 분류 의미 감사 | 오류 0건 | 명시적 상품 신호·유효 분류 감사 통과 |
| 실제 내 옷장–비교 상품 쌍 | 879쌍 | 무신사 699 + 유니클로 180 |
| 비교쌍 자동 무결성 감사 | 오류 0건 | 카테고리·실측 의미·산술·신뢰도 계약 통과 |
| 전체 자동 회귀 | 284개 | 279 통과, 실패 0, 실서버 전용 5 스킵 |
| 사람 독립 검수 | 0/200 | 아직 체감 핏 정확도를 확정할 수 없음 |
| 최신 Release archive | 성공 | 서명 제외 arm64 archive |
| App Store 제출 감사 | 4개 실패 | 공개 URL 2개 + 배포 서명 2개 |

중요한 해석:

- `2,560/2,560`은 현재 분류 로직이 유효한 결과를 만들고 명시적 의미 감사에서 오류가 없었다는 뜻이다. 사람 기준 분류 정확도 100%를 의미하지 않는다.
- `879/879`은 비교쌍의 구조, 측정 의미, 산술과 신뢰도 계약이 일관됐다는 뜻이다. 사용자가 느끼는 핏 만족도 100%를 의미하지 않는다.
- 과거 문서의 `915쌍`은 후속 의류군 우선순위·호환성 정제 전 수치다. 최신 기준은 `879쌍`이다.
- 더 많은 320/1,280건 상품 수집보다 200쌍 사람 검수와 실제 기기 QA가 지금 더 유의미하다.

## 4. 지금까지 완료한 작업

### 4.1 실제 상품 데이터 수집과 누적 회귀

- 첫 320건, 중복 없는 재검증 320건, 세 번째 320건, 무신사 네 번째 320건을 누적했다.
- 이후 기존 1,280건과 중복 없는 신규 1,280건을 추가했다.
  - 신규 무신사 1,037건
  - 신규 유니클로 243건
- 최종 누적 분류 코퍼스는 중복 없는 2,560건이다.
  - 무신사 1,545건
  - 유니클로 1,015건
- 상품 ID 색상 변형을 별도 상품으로 부풀리지 않았다.
- 분류 결과의 공급사 상품 ID, 상품명, 공식 카테고리 경로, FitMatch 대분류·세부분류를 JSON/CSV로 데이터화했다.
- 명시적 반팔·긴팔·민소매, 쇼트팬츠·크롭·긴바지, 가디건·레깅스·원피스 신호를 독립 감사하는 스크립트를 추가했다.

최신 분류 감사 근거:

- `Docs/Research/FitPairHumanReview-20260806/classification_semantic_audit_report.json`
- 결과: `passed`, 2,560건, 오류 0건

### 4.2 앱 분류 로직 보강

- 브랜드 공식 카테고리의 가장 구체적인 depth를 우선 사용한다.
- 공식 카테고리가 모호할 때만 상품명으로 길이·세부 의류군을 보완한다.
- 대분류, 세부분류, 의류군, 길이, 구조를 별도 축으로 유지한다.
- 반팔·긴팔·민소매·7부 상의, 쇼츠·크롭·7부·9부·긴바지, 레깅스 길이를 구분한다.
- 가디건, 후디, 스웨트셔츠, 셔츠, 티셔츠, 데님, 일반 팬츠, 레깅스, 스커트, 아우터, 레더 재킷 등의 비교 의류군을 구분한다.
- 파자마·홈웨어, 속옷, 원피스, 스커트, 유아 의류처럼 상위 경로만으로 오판하기 쉬운 사례의 우선순위를 교정했다.
- 개별 상품 ID 예외를 추가하는 대신 재사용 가능한 카테고리·의미 규칙으로 수정했다.

핵심 파일:

- `FitMatch/Models/ParsedClosetClassification.swift`
- `FitMatch/Models/ClothingCategory.swift`
- `FitMatch/Models/CanonicalComparisonProfile.swift`
- `FitMatch/Services/ComparisonProfileMatcher.swift`

### 4.3 무신사·유니클로 파서 보강

- 무신사는 actual-size API를 우선하고, 공식 응답이 없거나 유효하지 않을 때만 안전한 fallback을 사용한다.
- 공식 API에서 제공하는 `ONE SIZE`, `OS`, `1 (M)`, `블랙_S` 같은 비표준 사이즈명은 공식 근거가 있는 범위에서 허용한다.
- HTTP 성공이어도 실측 행이 없거나 값이 전부 0이면 임의 수치를 만들지 않는다.
- 유니클로 색상별 상품 ID에 사이즈표가 없으면 공통 `-000` ID를 한 번만 재조회한다.
- 유니클로의 `허리 [하의]` 둘레는 검증된 경우에만 0.5를 적용해 단면으로 변환한다.
- 의미가 다른 gathered body width, 속치마, 목둘레, 불명확한 측면 길이는 비교 근거에서 제외한다.
- 공식 호스트와 위장 도메인을 구분하고, 지원하지 않는 URL에 범용 파서를 호출하지 않도록 했다.
- 실질 구현 없이 실패하던 `GenericProductParser.swift`는 삭제했고 서비스 디스패치에서 사용하지 않는다. 일부 과거 아키텍처 문서에는 아직 이름이 남아 있어 코드가 우선이다.

핵심 파일:

- `FitMatch/Services/MusinsaActualSizeAPIParser.swift`
- `FitMatch/Services/MusinsaFallbackSizeParser.swift`
- `FitMatch/Services/MusinsaParser.swift`
- `FitMatch/Services/MusinsaProductMetadataParser.swift`
- `FitMatch/Services/MusinsaURLResolver.swift`
- `FitMatch/Services/MusinsaWebViewParser.swift`
- `FitMatch/Services/UniqloParser.swift`
- `FitMatch/Services/ProductURLParserService.swift`
- `FitMatch/Services/ParsedSizeValidator.swift`
- `FitMatch/Services/SizeTokenNormalizer.swift`

### 4.4 실제 내 옷장–비교 상품 쌍 검증

- 공급사 공식 실측을 앱 운영 파서, 검증기, 후보 선택기, 최종 비교 엔진 순서로 실행했다.
- 최종 독립 감사 대상은 879쌍이다.
  - 무신사 699쌍
  - 유니클로 180쌍
  - 상의 389, 하의 203, 아우터 284, 원피스 1, 기타 2
- 신뢰도 분포:
  - 높은 신뢰도 715
  - 충분한 비교 147
  - 최소 기준 충족 16
  - 근거 부족 1
- 근거 부족 1건은 실패를 숨긴 것이 아니라 앱 계약대로 확정 추천을 하지 않는 결과다.
- 대분류 불일치, 세부분류 불일치, 중복 쌍, 부호·절댓값 계산, 가중 점수, 커버리지, 신뢰도 라벨 계약을 독립 검사했다.
- 자동 후보는 같은 대분류, 호환 가능한 의류군·길이·구조·성별 정책과 최소 공통 실측을 충족해야 한다.
- 같은 세부분류를 기준 옷 여부나 실측 개수보다 먼저 선택하도록 했다.
- 교차 분류는 자동 매칭하지 않고, 사용자가 직접 선택한 임시 비교에서만 감점·안내와 함께 사용할 수 있다.

최신 근거:

- `Docs/Research/FitPairHumanReview-20260806/actual_fit_pairs_enriched.json`
- `Docs/Research/FitPairHumanReview-20260806/automated_integrity_report.json`
- `Docs/Research/FitPairHumanReview-20260806/fit_pair_human_review_candidates_200.json`
- `Docs/Research/FitPairHumanReview-20260806/README.md`

### 4.5 측정 의미와 추천 신뢰도

- canonical measurement code가 정확히 같은 항목만 직접 비교한다.
- 둘레와 단면, 아웃심과 인심, 일반 소매와 화장을 혼합하지 않는다.
- 비교 항목 수와 필수 항목 충족 여부에 따라 확정, 최소 근거, 근거 부족을 나눈다.
- 호환되지 않는 길이 측정은 제외하고 사용자에게 제외 사유를 설명한다.
- 근거가 부족하면 `추천 결과 아님` 또는 비교 불충분 화면을 보여 높은 신뢰도로 오인시키지 않는다.

핵심 파일:

- `FitMatch/Models/MeasurementCode.swift`
- `FitMatch/Services/MeasurementComparisonEngine.swift`
- `FitMatch/Services/MeasurementLegacyBackfillService.swift`
- `FitMatch/Services/RecommendationService.swift`
- `FitMatch/Views/CompareFlowSheet.swift`
- `FitMatch/Views/RecommendationResultView.swift`

### 4.6 공유 확장과 실제 사용자 여정

- 앱과 공유 확장 사이의 App Group URL 저장·소비 흐름을 보강했다.
- 앱 활성화와 딥링크가 연속으로 발생해 비교 요청이 사라지던 경합을 수정했다.
- 공유 URL은 비교 화면이 표시되기 전에 삭제하지 않는다.
- 공유 확장의 성공 문구를 실제 보장 범위에 맞췄다.
- 공유 확장 표시 이름을 `FitMatch`로 정리했다.
- 시뮬레이터에서 유니클로·무신사 링크 옷장 등록과 공유 URL 수신, 앱 복귀 후 분석 시작까지 확인했다.
- 실제 아이폰에서 개발 서명 빌드 설치, 앱 실행, 딥링크 수신 후 프로세스 생존까지 확인했다.
- 2026-08-07 실기기에서 `extensionContext.open`이 실패한 뒤 비활성화된 `FitMatch 앱을 직접 열어주세요` 버튼이 표시되는 회귀를 확인했다. 예전에 동작한 responder-chain 앱 열기를 다시 1순위로 복구하고 `extensionContext.open`은 fallback으로 내렸으며, 두 경로가 실패해도 `FitMatch 다시 열기` 버튼을 활성 상태로 유지하도록 수정했다.
- 공유 확장 `보러가기` 자동 전환과 두 쇼핑몰 최종 결과 화면은 실제 아이폰에서 최종 확인이 남았다.

핵심 파일과 증거:

- `FitMatch/Services/SharedURLStore.swift`
- `FitMatch/ContentView.swift`
- `FitMatchShareExtension/ShareViewController.swift`
- `FitMatchShareExtension/Info.plist`
- `FitMatchUITests/FitMatchLiveUserJourneyUITests.swift`
- `Docs/LiveUserJourneyBugReport-20260806.md`
- `Docs/TestEvidence/LiveUserJourney-Summary-20260806/`

### 4.7 개인정보·품질지표·App Store 준비

- 앱 실행, 공유 수신·소비, 파싱 시도·성공·실패, 비교 시도·결과·차단, 옷장 저장을 로컬 집계한다.
- 상품명, URL, 상품 ID, 실측값, 옷장 이름, 사용자 식별자를 집계 데이터에 저장하지 않는다.
- MY → 문의 및 지원에서 사용자가 품질 진단 정보를 직접 내보낼 수 있다.
- 자동 서버 전송은 없다. Supabase가 재개되기 전까지 로컬 저장·수동 내보내기 방식이다.
- 앱과 공유 확장에 Privacy Manifest를 추가했다.
- Release에서 상품·옷장·실측·비교 상세 진단 로그를 비활성화했다.
- 개인정보처리방침과 고객지원 화면 및 HTTPS 구성 검증을 추가했다.
- App Store archive 감사 스크립트가 번들 ID, 버전, URL scheme, arm64, Privacy Manifest, dSYM, 앱·확장 배포 서명을 확인한다.

새 파일:

- `FitMatch/Services/FitMatchMetricsRecorder.swift`
- `FitMatch/Views/ReleaseInformationView.swift`
- `FitMatch/PrivacyInfo.xcprivacy`
- `FitMatchShareExtension/PrivacyInfo.xcprivacy`
- `FitMatchTests/FitMatchMetricsRecorderTests.swift`
- `FitMatchTests/FitMatchReleaseConfigurationTests.swift`
- `scripts/audit-app-store-archive.sh`

## 5. 자동검증과 빌드 증거

### 5.1 최신 자동 회귀

- 결과 번들: `/tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult`
- 총 284개
- 통과 279개
- 실패 0개
- 스킵 5개
- 스킵 5개는 일반 회귀에서 의도적으로 제외한 실서버 전용 테스트다.

확인 명령:

```bash
xcrun xcresulttool get test-results summary \
  --path /tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult
```

### 5.2 품질 진단 추가 검증

- 단위 테스트: `/tmp/FitMatchMetricsExport-20260807.xcresult`, 5/5 통과
- UI 테스트: `/tmp/FitMatchMetricsExportUI-20260807.xcresult`, 1/1 통과

이 테스트는 최신 전체 회귀 이후 추가된 품질 진단 내보내기 변경을 별도로 검증한다. 해당 변경을 포함한 최신 Release archive도 성공했다.

### 5.3 최신 Release archive

- 경로: `/tmp/FitMatch-AppStoreUnsigned-MetricsExport-20260807.xcarchive`
- 상태: `ARCHIVE SUCCEEDED`
- 앱: `com.ljy4337.fitmatch`, 1.0 (4)
- 공유 확장: `com.ljy4337.fitmatch.shareextension`, 1.0 (4)
- arm64, 앱·확장 Privacy Manifest, 앱·확장 dSYM 포함
- 서명 제외 archive이므로 배포 서명 실패는 예상된 결과다.

감사 명령:

```bash
scripts/audit-app-store-archive.sh \
  /tmp/FitMatch-AppStoreUnsigned-MetricsExport-20260807.xcarchive
```

현재 실패는 정확히 4개다.

1. 공개 개인정보처리방침 HTTPS URL 없음
2. 공개 고객지원 HTTPS URL 없음
3. 앱 Apple Distribution 서명 없음
4. 공유 확장 Apple Distribution 서명 없음

`/tmp` 산출물은 재부팅이나 정리로 사라질 수 있다. 경로가 없으면 실패로 오해하지 말고 같은 소스에서 다시 실행해 새 증거를 만든다.

## 6. 만든 데이터·문서·도구 파일

### 6.1 주요 데이터 디렉터리

- `Docs/Research/NewClothingCorpus-320-20260806/`
  - 최초 320건 원본, 분류 입력·결과, 카테고리별 그룹 CSV/JSON, 차단 상품 보고
- `Docs/Research/NewClothingCorpus-320-Retest-20260806/`
  - 기존과 중복 없는 재검증 320건
- `Docs/Research/NewClothingCorpus-320-Third-20260806/`
  - 세 번째 320건과 누적 960 회귀
- `Docs/Research/MusinsaNew320Collection-20260806/`
  - 신규 무신사 320 수집 원본
- `Docs/Research/NewClothingCorpus-320-MusinsaFourth-20260806/`
  - 네 번째 320건, 누적 1,280 회귀와 무신사 실측 근거
- `Docs/Research/CategoryCorpus-live-uniqlo-1280-20260806/`
  - 유니클로 신규 후보 수집 원본
- `Docs/Research/NewClothingCorpus-1037-MusinsaFifthEighth-20260806/`
  - 신규 무신사 1,037건 분류 입력과 실측 근거
- `Docs/Research/NewClothingCorpus-243-UniqloFifth-20260806/`
  - 채택된 신규 유니클로 243건 분류 입력과 실측 근거
- `Docs/Research/NewClothingCorpus-300-UniqloFifth-20260806/`
  - 유니클로 후보 300건 조사 근거
- `Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/`
  - 신규 1,280건, 누적 2,560 Swift 분류 결과, 무신사·유니클로 실측 비교 결과
- `Docs/Research/FitPairHumanReview-20260806/`
  - 최종 879쌍, 자동 감사 결과, 사람 검수 후보 200쌍

위 디렉터리 일부는 raw HTML/API 응답 때문에 수백 MB다. 중복 상품 검증과 공식 근거 추적에 필요하므로 임의 삭제하지 않는다.

### 6.2 주요 보고 문서

- `Docs/FitMatch_무신사_유니클로_데이터_및_출시검증_리포트_20260806.md`
  - 초기부터의 장문 보고서. 앞부분 일부 수치는 과거 기준이므로 최신 수치는 이 인수인계 문서를 우선한다.
- `Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/progress_report.md`
  - 신규 1,280 및 누적 2,560 진행 상세. 이 문서의 915쌍은 후속 정제 전 수치다.
- `Docs/Research/RuntimeClassificationParity-20260806.md`
  - 앱 하드코딩과 DB 분류 규칙 동등화 설계·과거 실행 결과
- `Docs/AppStoreReadiness-20260806.md`
  - 최신 출시 준비 상태
- `Docs/AppStoreSubmissionRunbook-20260806.md`
  - URL 준비부터 서명·Validate·업로드까지 실행 순서
- `Docs/AppStorePrivacyPolicyDraft-20260806.md`
  - 실제 운영자 정보와 URL을 채워야 하는 초안
- `Docs/HomeDeviceQAChecklist.md`
  - 실제 아이폰에서 남은 검증 항목
- `Docs/Research/SupabaseSecurityReview-20260806.md`
  - 수행한 보안 검토와 대시보드 수동 조치

### 6.3 만든 자동화 스크립트

- `scripts/build-new-clothing-corpus.py`: 수집 결과를 회귀 코퍼스로 구성
- `scripts/group-new-clothing-by-fitmatch-category.py`: FitMatch 카테고리별 CSV/JSON 그룹 생성
- `scripts/validate-320-direct-logic.py`: 320건 직접 분류 검증
- `scripts/collect-new-uniqlo-retest.py`: 중복 없는 유니클로 재수집
- `scripts/collect-new-musinsa-balanced.py`: 무신사 카테고리 균형 수집
- `scripts/collect-musinsa-size-evidence.py`: 무신사 공식 실측 근거 수집
- `scripts/collect-uniqlo-size-evidence.py`: 유니클로 공식 실측 근거 수집
- `scripts/generate-regression-corpus-seed.py`: DB 회귀 seed 생성
- `scripts/generate-runtime-classification-parity-seed.py`: 런타임 규칙 동등성 seed 생성
- `scripts/generate-swift-classification-expectation-seed.py`: Swift 2,560 기대값 SQL 생성
- `scripts/build-musinsa-fit-pair-inputs.py`: 무신사 실제 비교쌍 입력 생성
- `scripts/build-uniqlo-fit-pair-inputs.py`: 유니클로 실제 비교쌍 입력 생성
- `scripts/audit-classification-semantics.py`: 2,560 분류 의미 감사
- `scripts/audit-fit-pair-integrity.py`: 879 비교쌍 독립 무결성 감사
- `scripts/build-fit-pair-human-review-set.py`: 위험도·계층 기반 사람 검수 200쌍 생성
- `scripts/review-fit-pair-candidates.py`: 사람 검수 입력·즉시 저장·재개 CLI
- `scripts/audit-app-store-archive.sh`: 제출 archive 자동 감사

### 6.4 추가한 회귀 입력과 테스트

- `FitMatchTests/LegacyMixed320ClassificationInputs.json`
- `FitMatchTests/LegacyUniqloRetest320ClassificationInputs.json`
- `FitMatchTests/LegacyUniqloThird320ClassificationInputs.json`
- `FitMatchTests/LegacyMusinsaFourth320ClassificationInputs.json`
- `FitMatchTests/Musinsa1037ClassificationInputs.json`
- `FitMatchTests/Musinsa1037FitPairInputs.json`
- `FitMatchTests/Uniqlo243ClassificationInputs.json`
- `FitMatchTests/Uniqlo243FitPairInputs.json`
- `FitMatchTests/FitMatchTests.swift`
- `FitMatchTests/LiveMusinsaValidationTests.swift`
- `FitMatchUITests/FitMatchUITests.swift`
- `FitMatchUITests/FitMatchLiveUserJourneyUITests.swift`

공유 scheme도 새로 만들었다.

- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatch.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchShareExtension.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchLiveValidation.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchLiveUserJourney.xcscheme`

일반 `FitMatch` scheme은 실서버 테스트를 스킵한다. 실서버 검증은 `FitMatchLiveValidation`, Safari 공유 전체 여정은 `FitMatchLiveUserJourney`를 명시적으로 사용한다.

## 7. 앱 하드코딩과 DB 규칙 상태

현재 앱은 DB에서 분류 규칙을 조회하지 않는다. `ParsedClosetClassification`과 관련 모델·서비스의 하드코딩 규칙이 실제 런타임 소스다.

DB 쪽에는 향후 전환을 위한 미러 구조와 평가기를 준비했다.

| 테이블 | 역할 |
|---|---|
| `fitmatch_taxonomy.runtime_rule_sets` | 앱 소스 체크섬, 규칙 버전, 실행 순서 |
| `fitmatch_taxonomy.runtime_classification_rules` | 공급사·단계·입력 범위·키워드·출력 매핑 |
| `fitmatch_staging.runtime_classification_regression_cases` | 현재 앱 기대 결과 |
| `fitmatch_staging.runtime_classification_parity_runs` | 일치·불일치·체크섬 이력 |

로컬 SQL:

- `supabase/sql/016_...`~`071_...`: 런타임 분류 미러, 독립 평가기, 코퍼스 seed, 2,560 Swift 기대값, 공급사 우선순위 정렬
- `supabase/sql/072_restrict_handle_new_user_execution.sql`: `handle_new_user()`의 불필요한 공개 실행 권한 회수

확인된 과거 상태:

- 당시 Swift↔DB 분류 category/detail은 2,560/2,560 일치했다.
- 이후 자동 비교 의류군·세부분류 호환 정책을 더 정제해 최종 비교쌍이 879개가 됐다.
- 이 최종 비교 호환 정책은 원격 DB에 미러링·검증했다고 간주하면 안 된다.
- `Docs/Research/SupabaseSecurityReview-20260806.md`에는 072 조치가 원격 적용되고 관련 Advisor 경고가 제거됐다고 기록돼 있다.
- 유출 비밀번호 보호는 Supabase Dashboard에서 사용자가 직접 활성화한 뒤 Auth 회귀가 필요하다.
- taxonomy/staging 스키마는 앱 클라이언트 공개용이 아니며 `anon`, `authenticated` 접근을 허용하지 않는 기본 거부 구조다.

주의:

- 로컬 SQL에 `038_runtime_musinsa_1037_seed_chunk_5.sql`과 `038_runtime_uniqlo_243_seed.sql`이라는 동일 번호 파일이 둘 있다. 자동 일괄 적용 전에 원격 migration ledger와 실제 실행 순서를 반드시 대조한다.
- 현재 원격 DB가 로컬 SQL 전체와 동일하다고 추정하지 않는다.
- DB 런타임 전환 전에는 현재 Swift 결과와 DB 평가 결과를 같은 고정 코퍼스에서 건별 비교하고, 한 건이라도 다르면 하드코딩 제거를 차단한다.
- 앱에서 DB를 직접 읽게 할 때는 읽기 전용 API 경계, 버전 고정, 캐시, timeout, 오프라인 fallback, RLS/권한을 별도로 설계한다.

## 8. 현재 작업 트리 상태

2026-08-07 점검 당시:

- tracked 수정: 48개
- tracked 삭제: 1개 (`FitMatch/Services/GenericProductParser.swift`)
- untracked 경로: 111개
- tracked diff: 49개 파일, 약 3,993줄 추가 / 722줄 삭제
- commit/push 없음

변경 범위는 모델, 파서, 비교 엔진, 공유 확장, 화면, 테스트, 문서, 조사 데이터, Supabase SQL 전반에 걸쳐 있다. 새 세션에서 일부만 보고 “나머지는 불필요하다”고 삭제하지 않는다.

보호 파일:

- `FitMatch/Components/TabBarScrollVisibilityModifier.swift`는 현재 diff가 없다.
- Swift modifier 호출부에도 추가·삭제 diff가 없다.
- 전체 diff grep에는 `Docs/CurrentSprint.md`의 설명 문장 하나가 잡히지만 Swift 호출부 변경은 아니다.
- 보호 파일이나 `hidesBottomTabBarOnScroll`, `tracksTabBarVisibilityOnScroll`, `hidesTopChromeOnScroll` 호출부는 사용자가 파일과 스크롤 동작을 명시적으로 승인하지 않는 한 수정하지 않는다.

현재 Release archive에서 보호 파일 관련 Swift actor-isolation 경고 4개가 있었지만 빌드·archive를 막지 않는다. 경고 제거를 이유로 보호 파일을 수정하면 안 된다.

## 9. 다음에 해야 할 일

### P0 — 사람 독립 검수 200쌍

현재 가장 먼저 할 일이다.

```bash
python3 scripts/review-fit-pair-candidates.py --summary
python3 scripts/review-fit-pair-candidates.py --reviewer "검수자 이름"
```

- 일부만 진행할 때는 `--limit 20`을 붙인다.
- 각 판정은 즉시 JSON에 저장되므로 중단 후 재개할 수 있다.
- 검수 항목은 카테고리 호환, 측정 의미, 차이 방향, 신뢰도 라벨, 전체 결과 수용 가능성이다.
- `category_compatibility`, `measurement_semantics_correct`, `signed_differences_correct`의 오류 허용치는 0건이다.
- 높은 신뢰도 표본의 `reliability_label_appropriate` 오류 허용치도 0건이다.
- 오류가 나오면 해당 규칙과 같은 계층 전체를 수정하고 879쌍 감사와 영향 범위 회귀를 다시 실행한다.
- 검수 완료 전에는 후보셋을 골드셋 또는 정확도 수치로 부르지 않는다.

예상 시간: 오류가 없으면 약 1~2시간. 오류가 있으면 규칙 수정·재검증 시간이 추가된다.

### P0 — 실제 아이폰 QA

`Docs/HomeDeviceQAChecklist.md`를 실제 기기에서 수행한다.

필수 항목:

- 기존 데이터가 앱 업데이트 후 유지되는지 확인
- 옷장 등록·수정·삭제와 기준 옷 교체
- 무신사·유니클로 URL 비교 완료
- Safari와 무신사 앱의 공유 확장 왕복
- 공유 확장 `보러가기` 후 FitMatch 자동 전환
- 앱 실행 중·백그라운드·완전 종료 상태의 공유 비교
- 네트워크 단절 안내와 복구 후 재시도
- 분석 취소, 빠른 연속 요청, 중복 기록 방지
- 하단 바운스·감속 중 헤더/탭바 스크롤 동작

예상 시간: 30~60분. 실패가 있으면 화면 녹화, URL, 시간, 기기·OS를 기록한다.

### P0 — App Store 외부 입력과 서명

사용자에게 필요한 입력:

- 실제 개인정보처리방침 HTTPS URL
- 실제 고객지원 HTTPS URL
- Apple Distribution 인증서와 App Store 배포 프로파일

URL을 받으면 `FitMatch/Info.plist`의 다음 빈 값을 채운다.

- `FitMatchPrivacyPolicyURL`
- `FitMatchSupportURL`

그 다음 Apple Distribution으로 앱과 공유 확장을 서명한 archive를 만들고 다음을 실행한다.

```bash
scripts/audit-app-store-archive.sh /path/to/FitMatch.xcarchive
```

`RESULT: passed` 확인 후 Organizer의 `Validate App`, 업로드, TestFlight 실기기 최종 검증 순으로 진행한다.

예상 시간: 공개 URL과 Apple 계정·프로파일이 준비돼 있으면 20~40분. URL 호스팅 준비 시간은 별도다.

### P1 — 출시 제품 결정

- 비교 화면의 ZARA 버튼은 현재 `준비중`이다.
- 앱의 추천 영역도 일부 로드맵/준비중 인상을 줄 수 있으므로 1.0에서 유지할지 숨길지 사용자가 결정해야 한다.
- 이는 기술적으로 임의 결정하지 않는다. UX 변경 전에 사용자 승인을 받는다.

### 보류 — Supabase

- 사용자가 재개할 때만 원격 상태를 먼저 읽기 전용으로 감사한다.
- 로컬 016~072를 무조건 재적용하지 않는다.
- 현재 Swift 분류 결과, DB 평가기, 최종 자동 비교 호환 규칙의 차이를 먼저 확인한다.
- 중앙 품질지표 전송을 추가한다면 전송 데이터, 보존기간, 동의, 개인정보처리방침, App Store Privacy 답변을 함께 바꾼다.

## 10. 더 이상 반복하지 않아도 되는 작업

- 특별한 신규 결함이나 신규 공급사 계약 검증이 없는 한 320개씩 무한 수집하지 않는다.
- 자동 감사 통과 수를 사람 정확도 100%라고 표현하지 않는다.
- 과거 242/248/265/273 테스트 수를 최신 전체 회귀 수로 보고하지 않는다. 최신 전체 회귀는 284개 기준이다.
- 과거 915쌍을 최신 비교쌍 수로 보고하지 않는다. 최신은 879쌍이다.
- `GenericProductParser`를 복구해 지원하지 않는 URL을 억지로 파싱하지 않는다.
- 원본 실측이 없는 상품에 임의 치수를 생성하지 않는다.
- DB 전환이 끝나기 전에 앱 하드코딩을 제거하지 않는다.

## 11. 출시 완료 정의

다음이 모두 충족돼야 1.0 출시 준비 완료로 본다.

- 전체 자동 회귀 실패 0
- 분류 의미 감사 오류 0
- 실제 비교쌍 독립 무결성 오류 0
- 200쌍 사람 검수 완료 및 중대 의미 오류 0
- 실제 아이폰 핵심 동선 전 항목 통과
- 공개 개인정보처리방침·고객지원 URL 실제 열림 확인
- 앱과 공유 확장 Apple Distribution 서명
- archive 감사 `RESULT: passed`
- App Store `Validate App` 통과
- TestFlight 신규 설치·업데이트·공유 확장·비교 재검증 통과

코드가 이후 변경되면 변경 영향 범위의 타깃 회귀를 실행하고, 출시 archive 직전에는 전체 회귀와 archive 감사를 다시 실행한다.

## 12. 작업 종료 전 필수 안전 확인

모든 새 세션은 작업 종료 전에 다음을 실행한다.

```bash
git diff --check
git diff -- FitMatch/Components/TabBarScrollVisibilityModifier.swift
git diff -- '*.swift' | grep -E \
  "hidesBottomTabBarOnScroll|tracksTabBarVisibilityOnScroll|hidesTopChromeOnScroll"
```

사용자 승인 없는 보호 파일·Swift modifier 호출부 변경이 없어야 한다. 문서 설명 문장이 전체 diff grep에 잡히는 것은 Swift 호출부 변경과 구분한다.

## 13. 2026-08-10 추가 작업

- 유니클로 `rising-length`가 일반 `length` 부분 일치 때문에 총장으로 오염되던 문제를 수정했다. 밑위·인심 상품 46개에서 수정 전 오염 37개, 수정 후 0개였다.
- P0 production 경로 22개, 일반 단위 테스트 248개를 당시 기준으로 통과했다.
- 누적 분류 코퍼스를 5,026건까지 확장하고 실제 실측 비교 706쌍을 검증했다.
- Simulator에서 링크 입력·옷장 등록·비교·기록 경로와 30쌍 실제 앱 UI 흐름을 자동화했다.
- UI 자동화는 element 존재와 실제 사용자 task 완료를 구분해 기록하도록 보완했다.
- 상세 당시 기록은 `Docs/CodexSessionHandoff-20260810.md`에 보존돼 있다.

## 14. 2026-08-11 UX 작업

### 반영 완료

- 온보딩의 첫 잘 맞는 옷만 기준 옷 기본 ON.
- URL 상품의 중복 읽기 전용 확인 화면 제거.
- 저장 성공 Alert 제거 및 `FitMatchSuccessToast` 도입.
- 저장 중 CTA 잠금과 빠른 연속 탭 중복 생성 방지.
- 기준 옷 선택 후 재확인 화면 제거 및 비교 중 입력 잠금.
- 브랜드보다 구조·측정 방식·실측 유사도를 우선하는 기준 옷 후보 순위.
- 후보 없음 화면과 기준 옷 선택 화면에 `이 상품을 내 옷장에 추가` 경로 제공.
- 유사 옷 직접 선택 후 기존 결과 화면에서 내 옷장 등록 가능.
- 저장한 비교 상품을 자기 자신과 즉시 비교하던 흐름 제거.
- 빈 홈 중복 안내 카드 제거.
- 파싱이 끝난 상품은 등록 중간 화면을 건너뛰도록 진입점 일관화.
- 반팔 니트·티셔츠·민소매 등 반팔/민소매 상의의 조건부 수동 확장 비교 허용.
- 긴팔 구조군 및 직접 반팔↔긴팔 비교는 차단.

### `E476997`가 정책 변경의 계기가 된 과정

- 유니클로 `E476997 워셔블니트폴로스웨터(반팔)`는 공식 분류가 `니트 & 가디건 > 니트 > 반팔 니트`여서 기존 matcher에서 AIRism·Umbro 반팔 티셔츠와 구조군이 다르다는 이유로 후보가 0개였다.
- 당시 아이폰에 최신 로컬 빌드가 설치되지 않은 문제도 있었지만, 최신 로컬 코드에서도 `knitCardigan ↔ tshirt`가 차단됐으므로 구버전 설치만의 문제는 아니었다.
- 이를 계기로 자동 기준 옷 선택은 같은 구조 중심으로 유지하되, 사용자가 직접 고르는 확장 비교에서는 반팔·민소매 상의끼리 공통 핵심 실측 2개 이상이면 구조군 간 비교를 허용했다.
- 정책 행렬에서 반팔 니트 ↔ 반팔티·민소매·반팔 셔츠·반팔 스웨트·반팔 후드는 허용하고, 긴팔티·긴팔 셔츠·긴팔 니트는 차단했다. 공통 핵심 실측 1개는 차단, 2개부터 허용한다.
- 저장된 canonical metadata나 measurement records가 비어 있어도 상품명·카테고리·scalar 실측으로 반팔 후보를 복원하는 기존 데이터 경로도 검증했다.

### 당시 검증

- 온보딩 UI 테스트 6개와 기본 UI 테스트 5개 통과.
- 빠른 저장 이중 탭 후 토스트 1회·옷장 상품 1개 생성 검증 통과.
- 관련 단위 테스트와 253개 분할 회귀를 수행했다. 마지막 production 수정 이후 단일 전체 스위트 재실행은 아니므로 전체 단일 통과로 표현하지 않는다.
- iPhone 17 Pro Simulator에서 저장 CTA `doubleTap()` 후 토스트 1회와 동일 옷장 상품 1개 생성을 함께 검증했다.
- 253개 분할 실행 중 발견한 긴팔 티↔셔츠, 반팔 니트↔긴팔 니트, 긴 재킷↔반소매 코트의 잘못된 수동 확장을 수정하고 관련 회귀 3개를 다시 통과시켰다.
- 상세 당시 기록은 `Docs/CodexSessionHandoff-20260811.md`에 보존돼 있다.

## 15. 2026-08-12 비교·분류·회귀 작업

### 세 무신사 상품 전수 비교

- 대상 상품 ID: `6566713`, `5020093`, `3467384`.
- production `ShoppingProductViewModel` 등록 경로를 사용하도록 테스트를 보완했다.
- 세 상품의 S/M/L/XL, 6개 하의 실측을 고정 fixture로 보존했다.
- 6개 방향 × 기준 사이즈 4개 = 24개를 실행하고 최고 점수 후보 선택을 검증했다.
- 라이브 전체 실행 2회의 결과가 동일했다.

### 긴바지 fallback 및 기존 데이터

- `product_level_fallback`으로 저장된 명확한 긴바지는 바지/데님 계열, 세트 아님, 긴 길이, 핵심 하의 실측 3개 이상일 때 과거 `canonicalEligibility=false`를 재평가한다.
- 세트, 반바지, 실측 부족, 다른 정책 결정은 복구하지 않는다.
- 무신사 옵션 순서 접두사 `0. S`, `1. M`은 유효 사이즈 토큰에만 적용해 `S`, `M`으로 표시한다.
- 신규 파싱 경로뿐 아니라 홈·비교·결과·기록·내 옷장 저장 화면의 기존 데이터 표시에도 같은 정규화를 적용했다.
- 과거 형태 데이터를 SwiftData에 저장하고 재로드한 뒤 앱 시작과 같은 measurement backfill, 비교, 추천까지 확인했다.

### 카테고리별 라이브 감사

- 입력: `FitMatchTests/CategoryLiveComparisonInputs.json`.
- 생성기: `scripts/build-category-live-comparison-inputs.py`.
- 테스트: `FitMatchTests/CategoryLiveComparisonAuditTests.swift`.
- 결과 문서: `Docs/TestEvidence/CategoryLiveAudit-20260812/report.md`.
- 무신사 일반 10개 세부군 × 3개 + 기타 유입 10개 = 40개.
- 유니클로 일반 7개 세부군 × 3개 + 기타 유입 10개 = 31개.
- 71개 중 70개 로드, 2,970개 조합, 허용 1,757개 모두 추천 성공, 차단 1,213개.
- 동일 파싱 입력의 추천을 두 번 계산했고 전체 라이브 실행도 두 차례 반복했다. 비결정성 및 최고점이 아닌 추천은 0개였다.

### 유니클로 혼합 카테고리 버그 수정

- 공급사 혼합 경로 `셔츠 & 블라우스`, `티셔츠 & 스웨트셔츠`의 특정 단어가 상품명을 덮어쓰던 문제를 수정했다.
- 구체적인 상품명 의류 구조를 혼합 공급사 bucket보다 우선한다.
- 셔츠를 `normalizedSizes()`와 유니클로 소매 추론 후처리에서 반팔·긴팔 티셔츠군으로 덮어쓰지 않는다.
- 최종 실상품 결과:
  - `E488520 옥스포드박시셔츠` → 셔츠
  - `E488448 나일론박시쇼트셔츠(5부)` → 셔츠
  - `E488648 AIRism코튼UT(그래픽T)` → 반팔
- 단위 회귀 2개, 실상품 라이브 회귀 1개, 전체 카테고리 2,970개 조합 재실행이 통과했다.

### 공유확장 자동화 한계

- Safari 상품 페이지와 공유 시트까지는 실행·캡처했다.
- Simulator 시스템 공유 시트가 FitMatch 확장을 노출하지 않아 확장 선택 이후 흐름은 미검증이다.
- 이를 앱 비교 실패로 기록하지 않고 환경 차단으로 분류했다.

## 16. 인수인계 관리 규칙

1. 새 세션은 `AGENTS.md`와 이 파일을 먼저 끝까지 읽는다.
2. 모든 의미 있는 production 수정, UX 정책 결정, 테스트 결과, 새 데이터·문서, 미해결 문제를 작업 종료 전에 이 파일에 누적한다.
3. 이전 내용을 삭제하지 않는다. 정책이 바뀌면 과거 내용은 이력으로 남기고 최신 상태에 변경·폐기 여부를 명시한다.
4. 날짜별 상세 문서는 선택적으로 추가하되, 날짜별 문서만 갱신하고 이 누적 문서를 빠뜨리면 안 된다.
5. 테스트는 실행한 범위와 미실행 범위를 구분하고, 중단·skip·환경 차단을 통과로 기록하지 않는다.
6. 새 세션이 이 파일 하나로 현재 상태·주의사항·다음 작업을 이해할 수 있어야 한다.

## 17. 마지막 날짜별 인수인계 이후 전체 작업 로그

이 절은 `CodexSessionHandoff-20260811.md` 작성 이후부터 2026-08-13 문서 갱신 시점까지 수행한 내용을 누락 없이 다시 정리한 것이다. 위 15절과 일부 중복되더라도 다음 세션이 작업의 이유와 실패했던 접근까지 알 수 있도록 보존한다.

### 17.1 협업·판단 원칙 확정

- 사용자는 무조건적인 찬성을 원하지 않는다. 제품·UX·테스트 제안에는 가장 강한 찬성 근거와 반대 근거를 모두 검토하고, 틀렸다면 명확히 반박해야 한다.
- 이 원칙을 `AGENTS.md`의 `Decision Collaboration` 규칙으로 저장했다.
- 실기기에서만 가능한 사람 검수와 Codex가 수행 가능한 코드·Simulator·실서버 자동 검증을 구분했다.
- 반복 테스트 수 자체를 품질로 보지 않고, production 경로·실제 데이터·기대 결과·부정 경계·결정성을 포함하는지 평가하기로 했다.

### 17.2 UX 감사에서 승인·반영한 흐름

- 첫 옷을 무조건 기준 옷으로 만들지 않고 온보딩에서 등록하는 잘 맞는 첫 옷만 기준 옷 기본 ON으로 처리했다.
- 상품 URL을 다시 입력할 수 있도록 첫 미리보기는 유지하고 중복 읽기 전용 확인 화면만 제거했다.
- 기준 옷 후보 선택 후 다시 확인하는 화면을 제거하고 즉시 비교한다.
- 같은 쇼핑몰·브랜드가 아니라 구조·실측 호환성·실측 유사도가 기준 옷 순위를 결정한다.
- 저장 성공 Alert를 제거하고 토스트로 대체했다.
- 저장 및 비교 후보의 연속 탭을 잠가 중복 저장·중복 계산을 막았다.
- 자동 비교 가능한 동일 종류가 없을 때 새 화면을 추가하지 않고 기존 화면에서 `다른 옷 직접 선택`, `이 상품을 내 옷장에 추가`, `다른 상품 비교하기`를 상태에 맞게 제공한다.
- 다른 상품군과 비교한 뒤에는 기존 결과 화면의 내 옷장 추가 경로를 사용한다.
- 비교 상품을 내 옷장에 저장한 직후 자기 자신을 기준으로 비교하지 않는다.
- 반팔 상품은 반팔티·민소매·반팔 니트처럼 구조가 달라도 공통 핵심 실측 2개 이상이면 사용자가 명시적으로 확장 비교할 수 있다.
- 긴팔은 티셔츠·셔츠·니트 구조를 분리하고 스웨트셔츠·후드만 호환한다.
- 후보가 실제로 0개이면 비활성 선택 버튼을 보여주지 않는다.

### 17.3 세 상품 비교에서 발견한 기존 테스트 방식의 문제와 보완

- 최초 회귀 방식은 테스트에서 `Product`를 직접 조립해 실제 `ShoppingProductViewModel` 변환 경로를 우회했다. 이 때문에 production 앱이 `0. S`를 유지하는 결함을 놓쳤다.
- 이후 라이브 파서 결과를 `ShoppingProductViewModel.apply`와 `makeProductForClosetRegistration`으로 변환하도록 바꿨다.
- 실제 production 경로에서 `makeSizeForm`도 사이즈 정규화를 적용하도록 수정했다.
- 세 상품의 공식 실측 응답을 `ThreeProductActualSizeFixtures.json`으로 고정했다.
- 단순히 추천이 존재하는지만 보지 않고 모든 대상 사이즈를 독립 분석해 선택 결과가 실제 최고 점수인지 검증했다.
- 명확한 긴바지 fallback 복구뿐 아니라 실측 부족, 세트, 반바지, 다른 resolution method는 복구되지 않는 부정 경계를 추가했다.
- 같은 호출 반복과 전체 라이브 재실행 결과를 비교해 비결정성을 검사했다.
- 최종 세 상품 라이브 결과는 24/24 완료됐고 두 실행의 결과 행이 동일했다.

### 17.4 기존 저장 데이터 호환

- 새 상품만 정규화하면 기존 SwiftData의 `0. S`가 홈·결과·기록·등록 화면에서 그대로 보이는 문제를 발견했다.
- `AddComparedProductToClosetSheet`, `CompareFlowSheet`, `RecommendationResultView`, `RecommendationHistoryView`, `HomeView`의 표시 경로를 동일한 `SizeTokenNormalizer` 규칙으로 연결했다.
- DB 원본 문자열은 파괴적으로 바꾸지 않고 사용자 표시와 새 저장값만 정상화한다.
- 구형 scalar 실측만 가진 데이터를 테스트 저장소에 넣고 재로드했을 때 처음에는 추천이 실패했다. 이는 실제 앱 시작 시 수행하는 `MeasurementLegacyBackfillService`를 테스트가 생략했기 때문이었다.
- 테스트에 실제 앱 시작 순서와 공식 measurement record를 반영한 뒤 재로드·backfill·eligibility 복구·추천까지 통과했다.
- 이 시행착오는 앞으로 저장 데이터 테스트에서 model 생성만 하지 말고 앱 lifecycle 보정 단계를 포함해야 한다는 근거다.

### 17.5 긴바지 product-level fallback 정책

- 무신사 상품의 공식 실측이 충분하지만 과거 `canonicalEligibility=false`와 `product_level_fallback`으로 저장돼 비교가 막히는 문제를 수정했다.
- 복구 조건은 하의 대분류, pants/denim family, 상품명에 명시적 바지 계열 표현, 세트 아님, 긴 길이, 허리·엉덩이·허벅지·밑위·밑단·총장 중 3개 이상이다.
- Product와 UserFit 모두 같은 조건으로 재평가하며 resolution method는 `product_level_fallback_resolved`로 기록한다.
- 정책상 거부된 상품을 무조건 허용하는 방식은 사용하지 않았다.

### 17.6 카테고리별 71개 라이브 감사 상세

- 기존 실제 실측 비교 자료에서 상품 ID 순으로 결정적인 표본 manifest를 생성했다.
- 일반 그룹은 플랫폼별 3개, 역사적으로 `기타`로 들어온 그룹은 플랫폼별 10개를 선택했다.
- 실측 증거가 요청 수보다 적은 카테고리는 다른 상품으로 부풀리지 않고 coverage gap으로 남겼다.
- live test는 `ProductURLParserService` → `ShoppingProductViewModel` → `Product/UserFit` → `ComparisonProfileMatcher` → `RecommendationService` production 경로를 사용했다.
- 일반 카테고리는 같은 역사적 세부군의 모든 방향을 실행했고 기타 20개도 모든 방향에서 허용·차단 정책을 확인했다.
- 각 허용 조합은 추천을 두 번 계산하고 대상의 모든 사이즈 분석 최고점과 대조했다.
- 1차와 2차 결과: 선택 71, 로드 70, 파싱 실패 1, 조합 2,970, 허용 1,757, 차단 1,213, 추천 1,757, 근거 부족 0, 비결정성 0, 비최고점 0으로 동일했다.
- 유니클로 `E488923`은 공식 사이즈표는 있으나 베이비 상품 형식을 production 파서가 처리하지 못해 지속 실패했다.

### 17.7 기타 유입 상품의 현재 분류

- 무신사 기타 표본 10개는 현재 후드 또는 스웨트셔츠로 구체화됐다.
- 유니클로 기타 표본 10개는 현재 긴팔 계열로 구체화됐다.
- 무신사 `4.5부 레깅스`, `바이커 레깅스`가 숏 레깅스로 바뀐 것은 상품명과 일치하는 정상 개선으로 판단했다.
- 유니클로 `데님블라우스`의 블라우스 분류와 `데님미니스코츠`의 반바지/스커트팬츠 분류도 합리적인 결과로 판단했다.
- 자동 변화 27건 전체를 무조건 오류로 보지 않고 상품 의미에 따라 정상 개선과 버그 후보를 분리했다.

### 17.8 유니클로 혼합 bucket 버그의 2단계 수정

- 1차 원인: 혼합 공급사 경로의 `블라우스`, `스웨트` 토큰이 명시적인 상품명을 이겼다.
- `ParsedClosetClassification`에서 명확한 상품명 의류 구조를 혼합 bucket보다 우선하고, 혼합 셔츠/블라우스 및 티셔츠/스웨트 bucket을 단일 의류 근거로 사용하지 않도록 수정했다.
- 1차 단위 테스트는 통과했지만 실상품에서는 두 셔츠가 `긴팔`, `반팔`로 다시 변환됐다.
- 2차 원인: `ParsedProductInfo.normalizedSizes()`와 `UniqloProductMetadata.withInferredSleeveDetail()`이 셔츠 구조를 소매 길이 티셔츠 detail로 덮어썼다.
- 두 후처리는 미분류 `.other`에만 길이 detail을 추론하도록 제한했다.
- 최종 라이브 결과는 옥스포드박시셔츠=셔츠, 나일론박시쇼트셔츠=셔츠, AIRism 코튼 UT=반팔이다.
- 수정 후 단위 회귀 2개, 실상품 라이브 3개, 전체 2,970개 조합이 통과했다.

### 17.9 테스트 실행 중 통과로 기록하지 않은 항목

- 개별 Swift Testing 함수 필터가 실제로 0개를 실행하고 `TEST SUCCEEDED`를 반환한 적이 있다. 실행 로그에서 test count를 확인해 이를 통과로 인정하지 않았다.
- 해당 테스트를 독립 suite로 분리해 실제 1개/2개 테스트가 실행됐음을 확인한 뒤에만 통과로 기록했다.
- 전체 `FitMatchTests` 스위트는 대형 코퍼스 테스트가 장시간 실행돼 중단했다.
- 중단 전 신규 혼합 bucket 테스트는 통과했지만, 기존 `manualLengthMismatchAllowsExplicitExtendedComparison` 기대값 2건이 현재 정책과 충돌하는 것도 확인했다.
- 따라서 마지막 production 수정 이후 전체 단일 suite 통과라고 주장하지 않는다.
- 시스템 공유 시트 E2E도 FitMatch 확장 미노출로 중단됐으므로 실행 완료로 기록하지 않는다.

### 17.10 이번 기간의 신규·수정 테스트 자산

- `FitMatchTests/LiveThreeProductComparisonTests.swift`
- `FitMatchTests/ThreeProductActualSizeFixtures.json`
- `FitMatchTests/CategoryLiveComparisonAuditTests.swift`
- `FitMatchTests/CategoryLiveComparisonInputs.json`
- `scripts/build-category-live-comparison-inputs.py`
- `Docs/TestEvidence/CategoryLiveAudit-20260812/report.md`
- 기존 `FitMatchTests/FitMatchTests.swift`, `FitMatchTests/LiveMusinsaValidationTests.swift`의 관련 회귀도 함께 보강했다.

### 17.11 이번 기간의 production 변경 범위

- 분류·정규화: `ParsedClosetClassification.swift`, `ProductURLParserService.swift`, `UniqloParser.swift`, `SizeTokenNormalizer.swift`, `ShoppingProductViewModel.swift`.
- 비교·추천: `ComparisonProfileMatcher.swift`, `RecommendationService.swift`.
- 기존 데이터 표시·저장: `AddComparedProductToClosetSheet.swift`, `CompareFlowSheet.swift`, `RecommendationResultView.swift`, `RecommendationHistoryView.swift`, `HomeView.swift`.
- 앞선 UX 승인 반영: `AddClosetItemViewModel.swift`, `AddClosetItemView.swift`, `FitMatchOnboardingView.swift`, `LinkClosetRegistrationView.swift`, `FitMatchSuccessToast.swift` 및 관련 UI 테스트.
- 현재 working tree에는 그 이전 분류·taxonomy·코퍼스 변경도 함께 존재한다. 위 목록만 선택해 되돌리거나 정리하지 않는다.

### 17.12 인수인계 체계 변경

- `Docs/CodexSessionHandoff.md`를 단일 최신 누적 인수인계서로 지정했다.
- 날짜별 `CodexSessionHandoff-YYYYMMDD.md`는 당시 세부 기록으로 보존한다.
- `AGENTS.md`에 새 세션 시작 시 누적 문서를 끝까지 읽고 의미 있는 작업 종료 전 반드시 갱신하도록 규칙을 추가했다.
- 이 절까지가 마지막 날짜별 인수인계서 이후 현재까지의 최신 작업 범위다.

## 18. 2026-08-13 플랫폼별 기준 옷장 비교 감사

### 목적과 실행 방식

- 사용자 요청에 따라 실제 공식 사이즈표를 production `ProductURLParserService → ShoppingProductViewModel → Product/UserFit → ComparisonProfileMatcher → RecommendationService` 경로로 실행했다.
- 1차는 유니클로 상품을 현재 세부 분류별 기준 옷 1개·대표 사이즈 1개로 `UserFit` 등록하고, 무신사·유니클로의 나머지 라이브 상품을 모두 비교했다.
- 2차는 같은 방법으로 무신사 상품을 기준 옷으로 등록했다.
- 기준 옷은 해당 공급사·현재 세부 분류별 상품 ID 오름차순 첫 상품이며, 여러 사이즈 중 중앙 index 사이즈를 사용했다. 비교 상품과 같은 ID인 기준 옷은 제외했다.
- 자동 후보, strict 직접 비교, 사용자 선택 확장 비교, 실제 추천 생성 실패를 각각 분리해 기록했다.
- 전용 실행 scheme: `FitMatchUniqloReferenceAudit.xcscheme`, `FitMatchMusinsaReferenceAudit.xcscheme`.
- 감사 테스트: `FitMatchTests/CategoryLiveComparisonAuditTests.swift`.

### 범위 한계

- 이번 실행은 기존 라이브 manifest의 71개 공식 실측 표본을 사용했다. 70개가 로드됐고 유니클로 `E488923` 1개는 공식 사이즈표는 있으나 베이비 형식 production 파싱에 실패했다.
- 따라서 활성 73개 전체 세부 카테고리를 채운 전수 감사가 아니다. 현재 공식 실측을 재확인할 수 있는 표본 안에서의 최대 비교이며, 유니클로 기준 9개·무신사 기준 14개만 실제 기준 옷으로 구성됐다.
- 43개 의류·신발 비교 세부 카테고리 전체를 채우려면 부족 카테고리의 공식 실측 상품을 별도 수집한 뒤 동일 harness를 재실행해야 한다.

### 1차 — 유니클로 기준 옷장

- Simulator: iPhone 17 Pro, iOS 26.3.1.
- 기준 옷 9개: 가디건, 긴바지, 긴팔, 롱 레깅스, 반바지, 반팔, 블라우스, 셔츠, 스커트.
- 70개 로드, 621개 쌍 비교.
- strict 직접 비교 허용 45개, 수동 확장 1개, 정책 차단 575개.
- 허용된 직접 비교에서 추천 생성 실패는 0개였다.
- 같은 세부 카테고리인데 자동 후보가 없는 사례 10개, 같은 세부 카테고리 pair 차단 9개가 관찰됐다.

### 2차 — 무신사 기준 옷장

- Simulator: iPhone 17 Pro, iOS 26.3.1.
- 기준 옷 14개: 블레이저, 긴바지, 후드, 코트, 스웨트, 민소매, 셔츠, 재킷, 반바지, 롱 레깅스, 숏 레깅스, 바람막이, 반팔, 긴팔.
- 70개 로드, 966개 쌍 비교.
- strict 직접 비교 허용 62개, 수동 확장 39개, 정책 차단 865개.
- 허용된 직접 비교에서 추천 생성 실패는 0개였다.
- 같은 세부 카테고리인데 자동 후보가 없는 사례 22개, 같은 세부 카테고리 pair 차단 17개가 관찰됐다.

### 발견 사항과 판정

- 정상 차단: 유니클로 유아·키즈 반팔/레깅스/반바지와 성인·공용 무신사 기준 옷의 차단은 성별·연령 정책에 따른 정상 결과다. `E488648`, `E488738`, `E488922`, `E488925` 등이 해당한다.
- 정상 차단: 유니클로 긴팔 셔츠 기준과 반팔·5부 셔츠(`E488280`, `E488448`)의 차단은 승인된 직접 반팔↔긴팔 차단 정책에 따른 정상 결과다.
- 수정 후보 P1: 무신사 `2080488 하프 집업 스웻셔츠`, `2738737 시그니처 레더 패치드 스웻셔츠`가 source category는 맨투맨/스웨트인데 화면상 세부 분류가 `셔츠`로 등록됐다. 실제 셔츠 기준과 비교하면 구조가 다르다며 차단된다.
  - 추정 원인: `스웻셔츠` 표기가 현재 명시 스웨트 키워드의 `스웨트셔츠`와 일치하지 않고, 뒤의 `셔츠` 토큰으로 분류되는 경로.
  - 권장 최소 수정: `ParsedClosetClassification`과 무신사 detail 추론에서 `스웻`, `스웻셔츠`를 스웨트셔츠의 선행 동의어로 처리하고 셔츠 판단보다 먼저 적용한다.
  - 이번 감사에서는 production 코드를 수정하지 않았다.
- `E488923 BT릴랙스핏레깅스(10부·프린트)`는 공식 사이즈표는 있으나 베이비 상품 형식을 production 파서가 처리하지 못해 기준 옷·비교 상품으로 만들 수 없었다. 공급사 데이터 부재가 아니라 키즈·베이비 지원 범위 문제로 확정했다.

### 실행 증거

- `/tmp/FitMatchUniqloReferenceAudit-2.xcresult`: 3개 중 실제 1개 실행·통과, 2개는 의도적으로 skip. 실실행 시간 약 51초.
- `/tmp/FitMatchMusinsaReferenceAudit.xcresult`: 3개 중 실제 1개 실행·통과, 2개는 의도적으로 skip.
- 전용 scheme의 실행 플래그가 없는 첫 시도는 3개 모두 skip됐으며 통과로 계산하지 않는다.

## 19. 2026-08-13 기준옷 선정 선행 원칙 및 등록 전용 검증

### 19.1 순서 정정

- 사용자 지시: 비교를 시작하기 전, 기준옷을 먼저 설정하고 설정한 개수부터 보고한다.
- 기존 9/14는 71개 역사 표본에서만 나온 수치였으므로 전체 기준옷 수로 사용하면 안 된다.
- 29개/26개 중간 후보안도 과거 비교 결과의 표시 detail을 기준으로 했으므로 폐기했다.

### 19.2 사용자 지정 1차 기준

- 총 43개 세부 코드: 상의 9 + 하의 7 + 레깅스 5 + 아우터 18 + 스커트 2 + 원피스 2.
- 길이·구조 변형을 추가해 61~81벌로 늘리는 것은 이 1차의 목표가 아니다. 43개 세부 코드당 한 벌이 먼저다.

### 19.3 현재 로컬 공식 실측 원본 기반 선정 결과

- 근거:
  - 무신사: `NewClothingCorpus-1037-MusinsaFifthEighth-20260806/raw/musinsa/actual_size`에서 실제 API sizes 행이 있는 상품.
  - 유니클로: 로컬 원본 상품 페이지 코퍼스 4개(`raw/uniqlo/products`).
  - 현행 분류: `swift_production_classification_results_cumulative_2560.json`.
- 후보:
  - 유니클로 21개: 상의 4, 하의 3, 레깅스 3, 아우터 9, 스커트 1, 원피스 1.
  - 무신사 22개: 상의 4, 하의 4, 레깅스 3, 아우터 11.
  - 합계 43개는 두 플랫폼에 중복된 세부 코드가 포함된 수다. 43개 세부 카테고리를 모두 커버했다는 뜻이 아니며, 고유 커버리지는 25/43이다.
  - 양쪽 로컬 공식 실측 원본에서 후보가 없는 18개: blouse, hoodie, knit_top, light_padding, long_padding, nine_tenths_leggings, nine_tenths_pants, other_dresses, other_leggings, other_outerwear, other_skirts, padded_vest, shirt, short_padding, short_pants, sweatshirt, three_quarter_pants, vest.

### 19.4 등록 전용 Simulator 실행

- 신규 후보 manifest: `FitMatchTests/ReferenceClosetCandidates.json`.
- 생성 스크립트: `scripts/build-reference-closet-candidates.py`.
- 전용 scheme: `FitMatchReferenceClosetSetup.xcscheme`.
- test: `CategoryLiveComparisonAuditTests.registersOneOfficialMeasurementReferencePerStoredCategoryWithoutComparing`.
- Simulator: iPhone 17 Pro, iOS 26.3.
- 결과: PASS, 182.6초. 43개 후보 모두 `URL parse → Product 생성 → 대표 사이즈 → UserFit 기준옷 객체 생성`에 성공했다.
- 이 테스트는 matcher/recommendation을 호출하지 않으며 비교 0회다. 실제 영구 SwiftData 옷장을 오염시키지 않는 테스트 런의 기준옷 객체 설정이다.

### 19.5 다음 단계 경계

- 이 결과만으로 “유니클로 기준옷 43개”, “무신사 기준옷 43개”가 완성됐다고 말하면 안 된다.
- 유니클로 1차 비교는 유니클로 쪽에 부족한 22개 세부 코드 후보를 공식 실측으로 추가 확보한 뒤 시작한다.
- 무신사 2차 비교도 무신사 쪽에 부족한 21개 세부 코드 후보를 추가 확보한 뒤 시작한다.
- 본 실행 전의 71개 표본 비교 및 9/14 기준옷 audit은 역사적 회귀 증거로만 남기며, 43개 기준옷 전수 테스트 성공으로 해석하지 않는다.

### 19.6 사용량 제안 순서 규칙 (사용자 지시)

- 사용량·시간·비용 또는 테스트 범위가 걸린 요청에서는 싼 절충안부터 제안하지 않는다.
- 앞으로 반드시 다음 순서로 보고한다.
  1. 사용자가 말한 목표를 제대로 완료하는 데 필요한 **충분 예산**.
  2. 재시도·수집 실패·회귀를 포함한 **안전 예산**.
  3. 사용자가 제시한 상한에서의 **절충안**.
  4. 절충으로 포기되는 정확한 범위·근거·위험.
- 예산 추정의 근거가 실제 실행값인지, 이전 실행 기반 추정인지, 계획 가정인지 구분하고, 사용량과 품질 효과를 별도로 설명한다.

### 19.7 등록 검증 정정 및 아노락 팬츠 분류 결함

- 19.4의 `43개 후보 모두 성공`은 Xcode 결과 번들상 테스트 실행 수가 0건이었던 실행을 잘못 해석한 것이므로 철회한다.
- 재설계: Swift Testing의 `-only-testing` 선택이 이 도구체인에서 0건 처리되는 문제를 피하려고 `ReferenceClosetSetupXCTests` XCTest 래퍼를 추가했다. 앱 production 코드는 변경하지 않았다.
- 실제 실행 증거: iPhone 17 Pro (iOS 26.3.1), `ReferenceClosetSetupXCTests/testOfficialMeasurementReferenceRegistration`, 106.074초, **1 test / pass**.
  - 후보 66개(유니클로 26, 무신사 40) 중 실제 기준옷 객체로 등록 가능한 것은 35개(유니클로 10, 무신사 25)였다.
  - 31개는 후보 추출 목표와 공식 실시간 분류가 다르거나 공식 실측이 없었다. 비교는 0회다.
  - 따라서 플랫폼별 43개 기준옷을 만든 뒤 비교한다는 1·2차 전수 비교는 아직 시작할 근거가 없다.
- `6032712 테크라인 립포켓 아노락 팬츠` 회귀 테스트도 실제 실행했다. 공식 경로는 `스포츠/레저 > 하의 > 일자 팬츠`인데 현재 `ParsedClosetClassification`이 이름의 `아노락`을 우선해 `outerwear/anorak`으로 반환한다.
  - `ReferenceClosetSetupXCTests/testAnorakPantsRetainsBottomTaxonomy`: **1 test / 2 failures**, 기대 `bottoms/long_pants`, 실제 `outerwear/anorak`.
  - 원인: `ParsedClosetClassification.resolve`에서 `crossCategoryOuterwearDetail(in: name)`가 명시적 하의 source path보다 먼저 평가된다.
  - 권장 최소 수정(미적용): source path가 하의/바지/팬츠이면 이름의 아우터 키워드로 교차 카테고리를 덮어쓰지 않도록 우선순위를 수정하고 위 회귀 테스트를 통과시킨다.

### 19.8 아노락 팬츠 분류 수정 (사용자 승인)

- 승인 후 `ParsedClosetClassification.resolve`의 아우터 교차 분류에 하의 공식 경로 보호 조건을 추가했다.
  - 하의/바지/팬츠/슬랙스/데님/레깅스/스커트 등 명시 lower-body source path는 상품명 안의 아노락·재킷·패딩 단어보다 우선한다.
  - 아우터 공식 경로에서의 기존 명시 아우터 상품명 보정은 유지된다.
- 검증: iPhone 17 Pro (iOS 26.3.1), `ReferenceClosetSetupXCTests/testAnorakPantsRetainsBottomTaxonomy`.
  - 실제 결과 번들: **1 test / pass / 0 failures**, 실행 0.026초.
  - `스포츠/레저 > 하의 > 일자 팬츠` + `테크라인 립포켓 아노락 팬츠`가 `bottoms/long_pants`로 확정됨.
- 보호 범위 재검증: 동일 XCTest 클래스의 최종 실행은 **3 tests / pass / 0 failures**, 96.041초였다.
  - 아노락 팬츠 하의 보존.
  - 일반 상의 경로의 `라이트 바람막이 재킷`은 여전히 `outerwear/windbreaker`로 교차 보정됨.
  - 기존 공식 실측 기준옷 등록 감사 1건도 함께 재실행됐으며, 비교는 0회다.

### 19.9 플랫폼별 기준옷 후보 재선정 및 실제 교차 비교

#### 테스트 하네스 정정

- 사용자 요청의 43개 코드 기준옷 검증을 위해, 상품명 키워드만으로 후보를 확정하지 않고 `URL parse → 공식 숫자 실측표 → Product/UserFit 등록 → 저장 taxonomy 일치`까지 Simulator에서 확인하도록 보강했다.
- 후보 생성: `scripts/build-reference-closet-target-candidates.py`.
  - 키즈·유아·이너웨어·세트 상품은 성인/공용 기준옷 대체 후보에서 제외한다.
  - 유니클로 상위 경로인 `반팔 & 긴팔`, `원피스 & 스커트`가 각각의 개별 세부 코드로 중복 해석되지 않도록 보정했다.
- 검증 통과 후보 저장: `scripts/build-validated-reference-manifest.py`, `FitMatchTests/ReferenceClosetValidatedUniqlo.json`, `FitMatchTests/ReferenceClosetValidatedMusinsa.json`.
- `CategoryLiveComparisonAuditTests`는 실제 통과한 위 매니페스트를 기준옷으로 로드하도록 변경했다. 이전처럼 71개 비교 샘플에서 임의로 같은 플랫폼 기준옷을 고르지 않는다.
- 무신사 기준옷 탐색은 `MusinsaActualSizeAPIParser`만 사용한다. API/HTML 숫자 실측이 없을 때 사용자 UI가 시도하는 이미지 OCR 복구는 이 카탈로그 감사에서는 실행하지 않는다. OCR 대기 때문에 전체 검증이 멈추거나, 공식 숫자표가 없는 상품을 기준옷으로 오인하지 않기 위한 테스트 경계다. Production 동작 변경은 없다.

#### 기준옷 실제 등록 결과

- Simulator: iPhone 17 Pro, iOS 26.3.1.
- 유니클로 후보 67개(목표 코드가 있는 23개, 현 로컬 표본에서 후보 자체가 없는 코드 20개): 33건 등록 성공, **고유 목표 코드 17개** 확정.
  - `ReferenceClosetValidatedUniqlo.json`에 저장했다.
  - 현재 로컬/공식 표본의 한계로 43개 플랫폼별 기준옷에는 도달하지 못했다.
- 무신사 후보 111개(목표 코드가 있는 38개, 현 로컬 표본에서 후보 자체가 없는 코드 5개): 68건 등록 성공, **고유 목표 코드 30개** 확정.
  - 실행 결과: `Test-FitMatchReferenceClosetSetup-2026.08.13_09-06-52-+0900.xcresult`, **1 test / pass / 0 failures**, 테스트 본문 20.770초.
  - `ReferenceClosetValidatedMusinsa.json`에 저장했다.
- 43개를 모두 채운 것으로 표현하면 안 된다. 현재 검증 가능한 플랫폼별 커버리지는 유니클로 17/43, 무신사 30/43이다.

#### 1차 — 유니클로 기준옷 교차 비교

- 기준옷: 검증 완료 유니클로 17개.
- 대상: 기존 공식 실측 라이브 manifest 71개 중 70개 로드(무신사 40, 유니클로 30). 유니클로 1개는 현재 사이즈표를 확보하지 못했다.
- 실행 결과: `Test-FitMatchReferenceClosetSetup-2026.08.13_09-09-32-+0900.xcresult`, **1 test / pass / 0 failures**, 테스트 본문 86.213초.
- 쌍 비교 1,190개:
  - strict 자동/직접 비교 허용 67개
  - 사용자 선택 확장 비교 52개
  - 정책 차단 1,071개
  - 추천 생성 실패 **0개**
  - 같은 세부 구조 기준옷이 없어 자동 후보가 없는 대상 13개
  - 기준옷 17개 한계 때문에 같은 세부 구조 reference 자체가 없는 대상 31개
- 차단의 예: 유니클로 베이비 반팔·반바지와 성인/공용 기준옷의 연령·성별 차단, 서로 길이 구조가 다른 스커트 차단은 정상 보호 결과다.

#### 2차 — 무신사 기준옷 교차 비교

- 기준옷: 검증 완료 무신사 30개.
- 대상: 동일하게 실제 로드된 70개.
- 실행 결과: `Test-FitMatchReferenceClosetSetup-2026.08.13_09-11-26-+0900.xcresult`, **1 test / pass / 0 failures**, 테스트 본문 52.072초.
- 쌍 비교 2,097개:
  - strict 자동/직접 비교 허용 71개
  - 사용자 선택 확장 비교 134개
  - 정책 차단 1,892개
  - 추천 생성 실패 **0개**
  - 자동 후보 없음 28개
  - 같은 세부 구조 reference 자체가 없는 대상 4개
- 자동 후보 없음이 유니클로 기준보다 늘어난 것은 버그로 단정하지 않는다. 무신사 기준옷의 카테고리 폭이 넓어 수동 확장으로는 비교 가능하지만, 자동 비교는 성별·길이·구조 안전 규칙에 따라 후보를 제외하는 경우가 있기 때문이다.

#### 발견된 수정 후보와 미확정 항목

- P1 후보: `short_pants` 공식 source 분류 상품(예: 무신사 `1388516`, `1884480`, `2273549`)이 현재 모두 `bottoms/shorts`로 저장된다. 사용자 정의 43개 taxonomy에서 `숏팬츠`와 `반바지`가 독립 코드라면 source-to-taxonomy 매핑 결함이다. 다만 두 코드를 제품 비교상 별도로 유지할지 먼저 정책 확인이 필요하다.
- P1 후보: `light_padding`, `short_padding`, `padding`, `padded_vest`는 후보의 이름·원본 경로와 현재 저장 코드가 여러 방식으로 엇갈린다. 일부는 후보 선택기의 상위 경로 오인, 일부는 `경량 패딩`을 `패딩`으로 합치는 실제 parser 결과다. production 수정 전 각 target에 대해 실제 공식 source path가 명시된 대체 후보를 더 확보해 재현해야 한다.
- P2 후보: `mouton` 공식 원본 경로가 레더/라이더 재킷으로만 온 상품은 현재 `jacket`으로 저장될 수 있다. 원본 쇼핑몰 taxonomy에 무스탕 전용 code가 없을 때 이름 기반 보정을 어디까지 허용할지 정책 결정이 필요하다.
- 테스트 하네스 발견: 한 XCTest에 이미지 OCR fallback 후보 111개를 묶으면 Simulator가 약 69초 후 재시작해 결과 번들이 손상됐다. 이 실행은 무효로 폐기했다. actual-size API 전용으로 바꾼 후 111개 probe는 20.770초에 정상 완료됐다.

#### 다음 작업 경계

- 아직 각 플랫폼 43개 기준옷을 채우지 못했으므로, 이 결과는 **검증 가능한 공식 실측 표본 70개에 대한 부분 교차 감사**다. 43×각 플랫폼 전수 비교 성공으로 표현하지 않는다.
- 다음 단계는 부족 코드별로 공개 공식 카탈로그에서 성인 단품·공식 숫자 실측 상품을 수집하고, 동일 Simulator 등록 probe를 통과한 뒤 유니클로 43개·무신사 43개 매니페스트를 확정하는 것이다.
- 그 후에만 1차/2차를 43개 기준옷 전체로 재실행한다. 이번 단계에서는 production 분류·비교 로직을 추가 수정하지 않았다.

## 20. 2026-08-13 카테고리 증거 우선순위 데이터 감사

- 사용자와 다음 방향을 합의했다: 공식 공급사 경로에서 명확한 의류 대분류를 찾으면 자동 분류에서 잠그고, 상품명·실측은 이를 몰래 뒤집지 않는다. 세부분류가 기타·복합·누락일 때만 상품명과 실측을 보조 근거로 사용하며, 끝까지 모호하거나 강하게 충돌하면 사용자에게 2~3개 후보와 사유를 제시한다. 사용자 선택은 우선 로컬에 저장한다.
- 구현 전에 기존 코퍼스로 정책 영향을 측정하기 위해 `scripts/audit-category-evidence-policy.py`와 `Docs/Research/CategoryEvidencePolicyAudit-20260813/`를 생성했다. Production 앱 코드는 이 단계에서 변경하지 않았다.
- 기준 모집단은 누적 5,026개 고유 상품이다: 기존 2,560 + 신규 2,000 + fresh 466. 별도 supplement 726개는 외부 검증군으로 분리했다.
- 휴리스틱 공식 경로만으로 대분류 잠금 후보 5,012/5,026, 미해결 13, 내부 충돌 1이 나왔다. 이 수치는 문자열 휴리스틱의 coverage 추정이지 정확도 확정값이 아니다.
- 기존 canonical decision bundle을 공식 ID/경로로 연결하면 4,563/5,026이 매칭됐다: confirmed 3,891, review_required 336, rejected 336, 미매칭 463.
- 현재 runtime 결과가 존재하면서 canonical bundle의 앱 매핑과 다른 행은 90개다. 대표적으로 아노락 팬츠, 언더웨어 쇼츠, 라운지 팬츠, 팬츠&레깅스 혼합 버킷이 포함된다.
- canonical bundle도 정답지로 취급하면 안 된다. 일부 니트/스웨터 공식 경로가 아우터/가디건으로 광범위하게 매핑되는 등 현재 제품 정책과 충돌하는 결정이 관찰됐다. 따라서 90개를 유형별로 사람 판정한 후 정책·코드를 변경해야 한다.
- 상품명과 공식 경로의 단순 어휘 충돌은 170개였지만 언더웨어 쇼츠·바이커 쇼츠처럼 실제 대분류 충돌이 아닌 문맥 사례가 많다. 단순 단어 충돌마다 사용자 확인을 띄우면 UX가 과도하게 방해되므로 복합 표현과 공급사 카테고리 ID를 우선해야 한다.
- 사용자 최종 목표를 다음으로 확정했다: 공식 카테고리 정규화로 내 옷장 카테고리 선택과 비교 기준 옷 선택 횟수를 최대한 줄이고, 자동화가 어쩔 수 없이 모호할 때는 사용자의 판단을 최종값으로 사용한다. 그 판단을 로컬에 저장해 동일 상품 재분석 시 다시 묻지 않는다.
- 기존 `SourceCategoryHistoryMatcher`가 사용자 선택을 로컬 `UserDefaults`에 저장하고 비교 흐름에서 재사용하는 기반을 이미 갖고 있음을 확인했다. 다만 이전 구현은 한 상품의 선택을 공급사 category path 전체에 저장해 `기타 상의` 같은 혼합 bucket의 다른 상품까지 잘못 자동 분류할 수 있었다.
- 이를 상품별 공급사 식별자(`sourceType + sourceName + productCode`) 우선 저장·조회로 변경했다. 안정적인 상품 ID가 있는 상품은 과거 path-wide 단일 선택을 적용하지 않고, 동일 경로의 다른 상품은 옷장 이력 집계가 실제로 일치할 때만 후보가 된다. 상품 ID가 없는 수동/구형 데이터만 기존 path fallback을 유지한다.
- 비교 흐름뿐 아니라 비교 상품을 내 옷장에 저장할 때 사용자가 확정한 카테고리도 동일 로컬 매핑에 저장하도록 연결했다.
- 회귀 검증:
  - `userCategoryChoiceIsReusedForTheExactProviderProductOnly`: 실제 1 test / pass. 동일 상품은 선택을 재사용하고 같은 기타 경로의 다른 상품에는 전파하지 않는다.
  - `shortSleeveSourceHistoryDoesNotOverrideDetectedLongSleeve`: 실제 1 test / pass. 저장 이력이 명확한 길이 충돌을 덮어쓰지 않는 기존 보호를 유지한다.
- 사용자 전제를 추가로 명확히 했다: 사용자는 해당 옷을 어느 내 옷장 카테고리에 넣고 어떤 옷과 비교할지 알고 있으며, 모호한 경우 사용자의 선택이 최종 정답이다. 시스템은 사용자를 대신해 속단하는 것이 아니라 반복 선택을 줄이고 안전한 비교 후보를 좁히는 역할이다.
- 이 전제에 맞춰 명확한 공식 상의/하의/아우터 대분류는 상품명으로 뒤집지 않도록 잠갔다. 상품명에 `아노락`, `바람막이`, `브라`, `홈웨어`가 포함되어도 공식 대분류가 명확하면 대분류를 변경하지 않고, 공식 대분류가 `.other`일 때만 제한적으로 보완한다.
- 유니클로 공식 경로에서 어떤 대분류 근거도 찾지 못했을 때 기존처럼 `.top`으로 기본 확정하지 않고 `.other`를 반환하도록 변경했다. 이후 제한적 보완으로도 확정되지 않으면 사용자 선택 단계로 넘겨야 한다.
- 관련 XCTest 3건(`testAnorakPantsRetainsBottomTaxonomy`, `testOfficialTopTaxonomyIsNotOverriddenByOuterwearName`, `testOuterwearNameCanResolveMissingOfficialMajorCategory`)은 iPhone 17 Pro Simulator에서 3/3 통과했다. 결과: `Test-FitMatch-2026.08.13_10-25-04-+0900.xcresult`.
- 동일 상품에 저장된 사용자 선택은 이후 파서 추정과 충돌해도 최종값으로 반환하도록 변경했다. 공식 경로별 옷장 이력 후보에는 기존 대분류·길이 충돌 보호를 유지하고, 정확한 공급사 상품 ID에 사용자가 직접 저장한 답만 이 보호보다 우선한다.
- 자동 정규화가 유효한 경우 `CompareFlowSheet`가 raw parser category가 아니라 `ParsedClosetClassification`의 canonical category/detail을 화면 상태에 반영한 뒤 진행하도록 수정했다. 공식 대분류 누락을 제한적 fallback으로 해결한 경우에도 실제 비교 분류와 UI 상태가 일치한다.
- 분류 선택 안내 문구는 “같은 쇼핑몰 카테고리” 전체에 적용된다는 잘못된 표현을 제거하고, 선택이 “이 상품”에 저장되어 재사용된다고 명시했다.
- 비교 상품을 옷장에 저장할 때 garment family/length/construction/normalized type을 과거 parser 결과가 아니라 사용자가 최종 선택한 category/detail로 다시 계산하도록 수정했다. 화면의 저장 카테고리와 내부 비교 프로필이 서로 다른 상태를 막는다.
- 추가 검증:
  - 사용자 선택/경로 보호/유니클로 unknown 기본값 관련 4 tests / pass. 결과: `test_sim_2026-08-13T01-31-55-448Z_pid17306_7e3a8aa7.xcresult`.
  - 자동 기준옷 선택 안전 조건 11 tests / pass. 유효한 대표 기준옷 하나만 자동 선택하고, 비대표 단일 후보·복수 유사 후보·근거 부족은 사용자 선택을 유지한다.
  - 2,560개 production 분류 export 회귀 1 test / pass. 결과: `test_sim_2026-08-13T01-35-25-491Z_pid17306_bc49f946.xcresult`.
  - P0 production path 전체 22 tests / pass. 여기에는 모호한 무신사 기타 상의가 사용자 확인을 요구하는 검증이 포함된다. 결과: `test_sim_2026-08-13T01-36-06-465Z_pid17306_1f1daf65.xcresult`.
  - 최종 수정 후 iOS Simulator app build / success.
- 5,026개 증거 감사 스크립트를 최종 수정 상태에서 다시 실행했다. 입력 5,026/고유 5,026/중복 0, 공식 경로 lock 후보 5,012, conflict 1, unresolved 13으로 재현됐다. 현재 runtime label과 경로 정책의 단순 mismatch는 138개이며, canonical bundle과 runtime mapping mismatch 90개는 그대로다. 앞 수치는 판정 정확도가 아니라 검토 대상을 찾는 coverage 지표다.
- 실제 UI 완료 감사를 위해 Debug 전용 `-fitmatchAmbiguousCategoryFixture`와 로컬 매핑 초기화 인자를 추가하고, `testAmbiguousCategoryChoiceIsReusedForTheExactProduct` UI 테스트를 만들었다. Release 동작에는 포함되지 않는다.
- UI 테스트는 첫 실행에서 `스포츠/레저 > 상의 > 기타상의` 상품이 `FitMatch 분류 연결` 화면을 표시하는지 확인하고, 사용자가 `상의/반팔`을 선택한 뒤 비교 단계까지 진행한다. 앱을 종료해 in-memory closet을 새로 만든 후 같은 공급사 상품 ID로 다시 분석했을 때 분류 연결 화면 없이 비교 단계로 바로 진행하고, 재질문하지 않는 것을 검증한다.
- 실제 실행 결과: `test_sim_2026-08-13T01-56-06-137Z_pid17306_492790b7.xcresult`, **1 UI test / pass / 0 failures**, 53.3초.
- 동일 구조의 안전한 대표 기준옷 하나가 있을 때 자동 선택되는 별도 회귀 `singleExactRepresentativeForUserResolvedCategoryIsAutomaticallySelected`도 통과했다. UI fixture에서는 비교 프로필이 확장 후보로 판정되어 사용자 기준옷 선택을 유지했으며, 이는 함부로 자동 선택하지 않는 안전 정책에 해당한다.
- 최종 `git diff --check` 통과. 보호 파일 `TabBarScrollVisibilityModifier.swift` 및 보호 modifier call site 변경 없음.

## 21. 2026-08-13 카테고리 병렬 정확도 감사

- 다른 세션의 공식 기준옷 교차 테스트와 중복되지 않게 공식 70개 runtime 결과, 5,026개 코퍼스 위험 보정, 사용자 선택/기준옷 회귀를 병렬 감사했다.
- 5,026개 감사의 `runtime-vs-heuristic 138건`은 검증된 오류 수가 아니다. 감사 휴리스틱이 `후드 집업`의 `후드`를 상의로 읽어 명백한 아우터 28건을 오탐했다. `name conflict 170건`도 부분 문자열 오탐을 포함하므로 정확도 지표로 사용하지 않는다.
- 고위험 후보는 언더웨어 쇼츠→하의 31건, 아노락/윈드브레이커 팬츠→아우터 4건, 쇼트 재킷/커버롤 재킷→하의 4건, 명시 상의 경로를 이름만으로 아우터화한 최소 8건이다. 라운지/파자마 26건은 형태 분류와 용도 분류 중 어느 쪽을 우선할지 정책 판정이 필요하다.
- canonical `review_required` 336건 중 332건과 canonical 미등록 463건 중 최소 437건은 공식 경로만으로 대분류를 잠글 수 있는 잠재치다. 현재 production UI가 canonical status 자체로 묻지는 않지만, 세부분류가 모호하다는 이유로 대분류까지 초기화하지 않도록 계속 보장해야 한다.
- 공식 70개 로그에서 실제 세부분류 오류를 발견했다. `상의 > 맨투맨/스웨트`의 `하프 집업 스웻셔츠`, `시그니처 ... 스웻셔츠`가 영문/한글 `셔츠` 부분 문자열 때문에 `셔츠`로 저장됐다. `스웻셔츠` 변형을 sweatshirt로 먼저 처리하고 영문 `shirt`는 단어 경계일 때만 인정하도록 수정했다.
- 회귀 `musinsaSweatshirtNamesDoNotBecomeShirtsBySubstring`은 iPhone 17 Pro Simulator에서 통과했다. 결과: `test_sim_2026-08-13T03-26-12-868Z_pid35760_e5b8d7a4.xcresult`.
- 최신 공식 70개(무신사 40/유니클로 30) source-path 대조 결과 대분류 역전 0, other/기타 0, 불필요 사용자 확인 0이다. 수정 전 live 결과의 명백 detail 오분류는 위 스웻셔츠 2/70이었다. 복합 세트 1건, 반소매 스웨트 1건, 반팔 니트 2건은 길이와 구조 taxonomy 중 무엇을 우선할지 정책 검토 대상으로 남겼다.
- 기존 handoff에 pass로 인용된 일부 Swift Testing 결과 번들(`01-20-07`, `01-21-45`, `01-31-55`, `01-33-38`, `01-35-25`)은 `xcresulttool` 직접 조회에서 totalTestCount=0/result=unknown이었다. 해당 주장은 유효 증거에서 철회한다. 유효한 증거는 UI persistence 1/1, P0 22/22, 분류 잠금 XCTest 3/3이다.
- 같은 공급사 경로의 다른 상품으로 사용자 선택이 전파되지 않음을 실제 실행으로 보강하기 위해 P0 XCTest `p0ExactProductCategoryChoiceDoesNotSpreadToSiblingProduct`를 추가했고 1 test / pass를 확인했다. 결과: `test_sim_2026-08-13T03-33-22-082Z_pid35760_1d31caf6.xcresult`.
- 기준옷 정책의 정확한 현재 동작: 복수 일반 후보는 사용자 선택을 유지하지만, exact detail/direct compatible로 사용자가 대표 기준옷을 여러 개 지정한 경우에는 가장 최근 대표옷 하나를 자동 선택한다. “모든 복수 후보는 수동”이라고 표현하면 안 된다.

## 22. 2026-08-13 카테고리 단독 최종 production 검증

- 사용자가 병렬 세션 대신 이 세션 단독 진행을 선택했다. 실행 ID는 `CategoryValidation-20260813T153530+0900`, 시작 HEAD는 `49834c7332e7d4f64639e6a7068373afc423d35c`, Simulator는 iPhone 17 Pro / iOS 26.3.1이다.
- 최종 보고서와 원본 증거는 `Docs/TestEvidence/CategoryValidation-20260813T153530+0900/`에 있다. 최종·수정 전 실패·0-test 제외 번들은 `test-evidence-index.json`에서 구분한다.
- 수정한 production 결함:
  - 혼합 니트/가디건 경로의 최하위 leaf와 명시적 가디건 보존.
  - 공식 major 누락 시 parser detail+상품명에 모두 명시된 스웨트만 제한 복구.
  - `other/other` placeholder 자동확정 금지.
  - 스웨트풀집파카를 패딩이 아닌 `outerwear/jumper`로 처리.
  - 명백한 복합 세트를 자동 단일 카테고리로 확정하지 않음.
  - 팬츠/레깅스 혼합 경로에서 아래에서 위로 가장 가까운 단일 가족 노드를 적용. 5,026개 전수 diff는 의도한 8개 팬츠만 교정됐고 명시 레깅스 3개는 보존됐다.
- 시작/종료 production hash 비교에서 변경된 production 파일은 `ParsedClosetClassification.swift`, `UniqloParser.swift`, DEBUG UI fixture용 `ProductURLParserService.swift` 세 개다. 다른 production 파일의 중간 동시 변경은 없었다.
- 공식 70개 최종 재수집:
  - 실제 XCTest 2/2 pass.
  - raw 142 = 71 manifest × 2 audits, 고유 71, 로드 70, 파싱 실패 `E488923` 1건.
  - 동일 실행에서 `products.json`, `combinations.json`, `summary.json`, `report.md` 생성, 교차 산출물 불일치 0.
  - 3,707 combinations = direct 135, base extended 43, manual extended 219, blocked 3,310.
  - 허용 비교 추천 실패 0, 차단 복구 경로 누락 0, 스웻셔츠 `2080488`/`2738737` 모두 `tops/sweatshirt`.
  - 기존 `Docs/TestEvidence/OfficialMeasurementComparison-20260813` 네 핵심 산출물도 이 동일 실행 파일로 교체했다.
- 현재 Swift production 분류기 5,026개 최종 전수:
  - 실제 XCTest 1/1 pass, 입력/고유/출력 모두 5,026, taxonomy invalid 0.
  - offline 자동 4,697, 후보 329. 후보 329개를 실제 `ProductURLParserService → ShoppingProductViewModel → canonical` 경로로 재수집했고 실제 XCTest 1/1 pass, live success 329/failure 0.
  - 최종 자동 진행 4,978, 사용자 확인 48, 위험 placeholder 자동확정 0.
  - 확인 48 = 베이비 커버올/살로페트 9, 복합 세트 36, 기타 진짜 모호 3.
- 감사 도구도 production 결과와 함께 검증했다. 과거 저장 경로와 live source path를 섞지 않게 overlay하고 후드집업 compound를 처리했다. 기존 138건은 버그 수가 아니며 최종 heuristic 후보는 18건, 후드집업 오탐은 0이다.
  - 남은 18건은 스코츠 8, 이너웨어 레깅스 7, 속바지 1, 이너웨어 크루넥T 1, 명시 가디건 1의 형태-vs-판매목적 정책 경계다. 검증된 자동 대분류 버그로 세지 않는다.
  - 라운지 공식 경로는 현재 목적 우선 `homewear/loungewear` 정책이다. 일반 팬츠 형태를 우선할지는 별도 제품 정책 변경이다.
- 고위험 실상품 결과: 아노락/윈드브레이커 팬츠 6개 `bottoms/long_pants`, 언더웨어 쇼츠 `underwear`, 쇼트 재킷/커버롤 4개 `outerwear/jacket`, `E488939` `outerwear/jumper`, `E450540` `outerwear/cardigan`, 복합 세트는 사용자 확인.
- Simulator UI XCTest 1/1 pass로 최초 선택 → 종료/재실행 → 동일 상품 재질문 없음 → 같은 경로 다른 product ID에는 전파 없음 → mapping 초기화 후 원상품 재질문을 한 흐름에서 증명했다.
- 최종 경계/고위험 XCTest 8/8 pass, P0 production 전체 23/23 pass. 잘못된 suite filter로 0건 실행된 두 번은 명시적으로 제외했고, 테스트 시작 전 샌드박스/빌드 실패도 성공 증거로 사용하지 않았다.
- 현재 판단: 이번 데이터와 회귀 범위의 성인 카테고리 로직 수정·자동 검증은 완료됐다. 실제 아이폰에서는 문구·화면 전환 체감만 소수 확인하면 된다. 베이비 전용 taxonomy/비교 정책은 아직 별도 작업이며 `E488923`도 공식 parser 실패라 베이비 완전 지원으로 표현하면 안 된다.
- `git diff --check` 통과. 보호 파일과 보호 modifier call site는 변경하지 않았다.

## 23. 2026-08-13 하의 길이 안내 문구 수정

- 비교 가능한 옷 안내에서 공용 길이 값 `long`이 항상 `긴팔`로 표시되어 팬츠가 `긴팔 팬츠`로 노출되던 문구 오류를 수정했다.
- 길이 표시를 의류군 문맥에 맞게 분리했다. 팬츠/데님은 `긴바지`, `반바지`, `7부 팬츠`, `9부 팬츠`, `크롭 팬츠`로, 레깅스는 레깅스 전용 문구로 표시한다. 상의의 `긴팔`/`반팔` 표현은 유지한다.
- 비교 가능 여부·카테고리 분류·추천 계산 로직은 변경하지 않았고 화면 표시 조합만 수정했다.
- 동일 오류 재발 방지를 위한 길이 문구 단위 테스트를 추가했다. 사용자 요청에 따라 Simulator는 실행하지 않았다.

## 24. 2026-08-13 기준 옷 직접 선택 UX 문구 수정

- 자동 기준 옷이 없는 상태가 오류처럼 보이지 않도록 `기준 옷을 직접 선택해 주세요`와 `내 옷장에서 기준 옷 선택` 중심의 다음 단계 안내로 변경했다.
- 직접 선택 화면은 `기준 옷 직접 선택`으로 제목을 바꾸고, 자동 선택할 기준 옷이 없어 사용자가 직접 고르는 단계임을 명시했다.
- 직접 선택한 옷은 이번 비교에만 기준으로 사용되며 기존 기준 옷 설정은 변경되지 않는다고 안내한다.
- 이 흐름의 `이 상품을 내 옷장에 추가` CTA를 모두 제거했다. 비교 가능한 옷 자체가 없을 때는 `다른 상품 비교하기`만 제공한다.
- 관련 UI 테스트와 비교 감사의 기대 문구를 새 UX에 맞게 갱신했다. 사용자 요청에 따라 Simulator는 실행하지 않았다.

## 25. 2026-08-13 폴로셔츠 비교군 정책 수정

- 폴로셔츠·피케셔츠·카라티를 일반 직물 셔츠가 아닌 `tshirt` 비교 구조군으로 변경했다.
- 같은 소매 길이의 폴로셔츠↔일반 티셔츠와 폴로셔츠↔폴로셔츠는 자동 비교할 수 있다.
- 폴로셔츠↔와이셔츠·옥스포드셔츠·블라우스의 기존 `tshirt↔shirt` 예외 허용을 제거해 자동 비교를 차단한다.
- 과거 `shirt`로 저장된 폴로셔츠도 상품명·원본 카테고리 증거가 있으면 런타임에서 `tshirt`로 교정한다. canonical `polo_shirt`의 앱 변환도 `tshirt`로 변경했다.
- 관련 회귀 테스트를 새 정책에 맞춰 변경하고 일반 셔츠 차단 테스트를 추가했다.
- Simulator를 실행하지 않은 iPhoneOS Debug 앱 빌드는 성공했다. 테스트 타깃 build-for-testing은 샌드박스의 SwiftPM 캐시 쓰기 제한으로 실행되지 않았으며 코드 실패 증거가 아니다.

## 26. 2026-08-13 폴로셔츠 앱 세부분류 보완

- 직전 수정은 폴로셔츠의 비교 구조군만 `tshirt`로 바꾸고 앱 세부분류를 `shirt`로 남긴 불완전한 수정이었다.
- 앱 taxonomy `2026.08.2`에 활성 `tops/polo_shirt`(`상의 > 폴로셔츠`)를 추가하고 `ClosetDetailCategory.poloShirt`를 연결했다.
- 무신사 `피케/카라 티셔츠`와 유니클로 `폴로셔츠(카라티)` 경로 및 명시적 폴로 상품명은 이제 `상의 > 폴로셔츠`로 저장·표시한다.
- 비교 구조군은 계속 `tshirt`이고 소매 길이는 별도 축으로 유지한다. 따라서 같은 소매 길이의 일반 티셔츠와 자동 비교하고 일반 직물 셔츠·블라우스와는 차단한다.
- 폴로 분류·길이·비교 구조군 회귀 기대값을 보강했다. Simulator 없이 iPhoneOS Debug 앱 빌드가 성공했다.

## 27. 2026-08-13 출시 전 1,200건 증거 재감사

- 사용자 요청으로 계정 잔여 사용량 75%에서 시작해 65% 도달 시 중단하는 목표를 설정했다. 계정 잔여율은 세션 도구에서 직접 조회할 수 없으므로 사용자 또는 시스템 표시값이 필요하다.
- Simulator를 새로 실행하지 않고, 기존에 production 경로로 실행된 실제 공식 실측 비교 결과와 matcher 차단 결과를 현재 5,026개 분류 원장에 다시 대조했다.
- `scripts/build-release-qa-1200.py`를 추가했다. 입력은 무신사 비교 엔진 실행 597건, 유니클로 비교 엔진 실행 180건, 공식 교차 matcher 3,707건, 현재 분류 5,026건이다.
- 과거 실행 카테고리와 현재 분류가 달라진 36건은 통과 증거로 사용하지 않고 `excluded-stale-evidence.json`으로 분리했다. 주요 변화는 하의→레깅스/스커트/홈웨어/아우터 정규화다.
- 최초 원장은 무신사/유니클로 대상 비율이 907/293으로 불균형해 완료 근거에서 제외하고 균형 원장으로 교체했다.
- 최종 원장은 무신사 대상 600건, 유니클로 대상 600건이며 기준 옷 ON 600건, OFF 600건이다.
- 최종 결과는 PASS 1,200 / FAIL 0이다. 실행된 실측 비교 엔진 771건, production matcher 허용 57건, production matcher 차단 372건이다. 차단은 길이 68, 성별·연령 54, 의류 구조 250이다.
- 흐름은 자동 기준 옷 414건, 수동 기준 옷 선택 414건, 기준 옷 ON 상태 차단 186건, 기준 옷 OFF 상태 자동 후보 없음 186건이다. 자동/수동 UI를 새 앱 바이너리로 다시 실행한 결과가 아니라 실행된 pair 증거에 현재 선택 정책을 적용한 시나리오임을 구분한다.
- 10건 단위 120개 배치 원장을 `Docs/TestEvidence/ReleaseQA-1200-20260813/batches.json`에 생성했고 모든 배치가 10/10 PASS다.
- 상세 원장과 요약은 `Docs/TestEvidence/ReleaseQA-1200-20260813/cases.json`, `summary.json`이다.
- 사람이 읽는 최종 판정은 `Docs/TestEvidence/ReleaseQA-1200-20260813/report.md`에 추가했다.
- Excel 생성에 필요한 Spreadsheets skill의 `load_workspace_dependencies` 기능이 현재 세션에 제공되지 않고 연결된 Excel document session도 없어 `.xlsx` 작성은 아직 완료하지 못했다. 다른 라이브러리로 우회하지 않았다.

## 28. 2026-08-13 실제 iPhone 1,280 fixture 추가 검사

- 연결된 `이진영의 iPhone`(iPhone 14 Pro, iOS 26.6, UDID `00008120-001E08612290C01E`)에 개발 서명 테스트 빌드를 설치해 무신사 1,037개와 유니클로 243개 공식 API fixture를 production 파서·분류·비교 경로로 검사했다. 개인 옷장이나 Supabase에 1,280개 상품을 저장한 검사가 아니라 테스트 호스트 메모리에서 처리한 검사다.
- 최초 설치는 무선 연결 중단으로 실패했으나 재연결 후 실행됐다. 이 실패는 로직 결과에 포함하지 않는다.
- 실기기에서 `lookbehind is not currently supported` 오류를 발견했다. `ParsedClosetClassification`, `ProductURLParserService`, `MusinsaFallbackSizeParser`의 lookbehind를 iOS 호환 경계식으로 교체했고 production/test 전체에서 lookbehind 패턴 0개를 확인했다.
- 유니클로 243개 최종 엄격 결과: 통과. 비교 가능 238개, 실측 행 1,574개, confirmed 비교 쌍 184개다. 제외 5개는 베이비 커버올 4개 taxonomy 미지원과 공식 실측 행이 없는 와이어리스 브라 1개다. 결과 번들 `/tmp/FitMatchPhysicalUniqlo243Excluded.xcresult`.
- Swift Testing 함수를 XCTest에서 직접 호출하면 `#expect` 실패가 XCTest 실패로 전파되지 않는 하네스 결함을 발견했다. corpus 핵심 검증을 `try #require`로 변경해 불일치가 반드시 실기기 테스트 실패가 되게 했다.
- 무신사 1,037개는 최초 비엄격 브리지 실행에서 173.829초에 처리 완료했지만, 엄격 브리지로 바꾼 통합 실행과 단독 재실행은 모두 약 76초에 테스트 호스트가 `signal kill`됐다. assertion 실패는 관찰되지 않았지만 엄격 통과로 주장하지 않는다.
- 다음 필수 작업은 무신사 1,037개를 100~200개 단위의 독립 XCTest 배치로 분할해 각 배치의 strict assertion을 실제 iPhone에서 실행하는 것이다. 현 상태에서 유니클로는 실기기 통과, 무신사는 실기기 하네스 안정성 때문에 미확정이다.
- 상세 요약은 `Docs/TestEvidence/ReleaseQA-1200-20260813/physical-device-1280-summary.json`, 사람용 설명은 같은 폴더의 `report.md`에 기록했다.
- `.xlsx`는 스프레드시트 스킬이 요구하는 `load_workspace_dependencies`가 이 세션에 없어 계속 차단 상태다. 우회 라이브러리는 사용하지 않았다.

## 29. 2026-08-14 사용자 안내 문구 31개 흐름 전수 정비

- 사용자가 확정한 온보딩, 홈, 내 옷장, 기준 옷 설정·삭제, 직접·링크 등록, 상품 분석·분류, 기준 옷 없음, 아동·성인 분리, 수동 후보 선택, 실측 부족·제외, 사이즈표 복구, 오류, 결과·기록·브랜드·추천 탭의 문구를 실제 SwiftUI 화면에 반영했다.
- 반팔↔긴팔은 의류 구조 전체를 차단하지 않고 가슴·어깨·총장 등 공통 실측으로 부분 비교하며, 소매길이는 점수와 결과에서 제외하고 `반팔과 긴팔은 소매 구조가 달라 비교에서 제외했어요.`라고 표시한다. 제외 사유는 추천 결과와 참고 비교에도 보존된다.
- 자동 기준 옷이 없을 때 오류처럼 보이지 않도록 `비교할 옷 선택`과 이번 비교에만 사용하는 수동 선택임을 명시했다. 빈 옷장, 필요한 종류 없음, 아동복 없음, 성인복 없음은 가져온 상품·현재 옷장 구성·등록해야 할 종류를 각각 안내한다.
- 결과 화면의 사용자 용어를 `핏 매칭률`에서 `사이즈 유사도`로 통일하고, 추천 신뢰도 산정과 확장 비교 신뢰도 하향 이유를 설명한다.
- 무신사 자동 사이즈표 분석 실패, 이미지 분석 실패, 유니클로 사이즈표 없음, 세트 상품, URL·네트워크 오류 문구를 확정안으로 교체했다.
- 비교 상품의 옷장 등록은 `보유한 옷으로 등록`으로 명확히 하고 실제 보유 상품만 등록하도록 확인 문구를 강화했다.
- 변경된 화면 문구를 참조하는 UI 테스트 기대값도 함께 갱신했다.
- 앱·단위 테스트·UI 테스트 Swift 파일 전체 `swiftc -frontend -parse`와 `git diff --check`를 통과했다. 사용자 요청에 따라 Xcode 빌드와 실기기 화면 확인은 회사에서 후속 수행한다.
- 보호 파일 `FitMatch/Components/TabBarScrollVisibilityModifier.swift`와 보호 modifier 호출부는 변경하지 않았다.

## 30. 2026-08-14 확장 A테스트 5,000건

- 사용자가 별도 건수를 지정하지 않아 직전 합의에서 권장한 확장형 A테스트 5,000건으로 진행했다.
- `scripts/build-release-qa-2000.py`에 `--count` 옵션을 추가하고 현재 안내 문구 계약, 플랫폼 균형, 기준 옷 ON/OFF 균형, 고유 상품 쌍·상태 및 커버리지 집계를 반영했다. `scripts/build-release-qa-1200.py`는 `insufficient_evidence`를 정상 추천 보류로 검증하도록 수정했다.
- 최초 실행은 4,998/5,000으로 표시됐다. 실패 2건은 같은 재킷 쌍의 ON/OFF 상태로, 앱 오류가 아니라 필수 실측 누락 때문에 정상 `insufficient_evidence`가 된 사례를 생성기가 실패로 잘못 센 것이었다. 생성기 판정을 바로잡고 재실행했다.
- 최종 결과는 5,000/5,000 PASS, 무신사/유니클로 2,500/2,500, 기준 옷 ON/OFF 2,500/2,500이다.
- 결과는 자동 비교 1,247, 수동 선택 1,247, 정상 추천 보류 6, 정상 차단 2,500이다. 차단 사유는 의류 구조 2,214, 길이 구조 178, 성별·연령 보호 108이다.
- 실제 상품 쌍은 2,500개이며 ON/OFF를 포함한 고유 상품 쌍·상태는 5,000개다. 중복 상품 쌍·상태는 0이다.
- 출처 교차는 무신사→무신사 2,348, 유니클로→무신사 152, 유니클로→유니클로 1,120, 무신사→유니클로 1,380이다.
- 10건 단위 500개 배치가 모두 10/10 PASS이며 `failures.json`과 `ux-explanation-gaps.json`은 각각 0건이다.
- 결과 위치는 `Docs/TestEvidence/ReleaseQA-5000-20260814/`이며 `cases.json`, `batches.json`, `summary.json`, `report.md`를 포함한다.
- 이 검사는 5,000회의 신규 네트워크 호출이나 실제 iPhone UI 자동화가 아니라, 이전에 production 파서·분류·비교 엔진으로 실행된 실상품 증거를 현재 UX 계약으로 재생한 A테스트다. 개인 iPhone과 옷장 데이터는 변경하지 않았다.
- 실상품 증거가 없는 taxonomy 세부분류, 빈 옷장, 파서 실패 화면은 이번 5,000건 통과 범위에 포함하지 않는다. 이 항목까지 포함한 완전 확장형 A테스트에는 별도 fixture/UI 검증이 필요하다.
- Python 구문 검사, `git diff --check`, 보호 파일 및 보호 modifier 호출부 검사를 통과했다. Simulator는 실행하지 않았다.
- 기존 A테스트 정의에 포함됐던 Excel 결과는 Spreadsheets skill이 요구하는 `load_workspace_dependencies`가 현재 세션에 없어 생성하지 못했다. JSON과 Markdown 원장은 완료됐다.

## 31. 2026-08-14 현재 production Swift 경로 A테스트 재실행

- 직전 5,000건 JSON 재생 결과와 구분하기 위해 현재 앱의 Swift production 분류·파서·matcher·추천 코드를 iOS Simulator 테스트 호스트에서 직접 실행했다. 개인 iPhone 옷장과 Supabase 데이터는 변경하지 않았다.
- 5,026개 production 분류 전수 XCTest는 통과했다. 처리 5,026, 분류 성공 4,698, 사용자 확인 328, invalid 0, placeholder other 80이며 폴로셔츠 190, 후드 126, 맨투맨 157을 식별했다. 결과 번들은 `/tmp/FitMatchA5000Category5026.xcresult`다.
- 전체 `FitMatchMusinsaReferenceAudit` scheme 재실행은 2,462초 동안 346개 테스트를 수행해 324 pass / 8 fail / 14 skip으로 끝났다. 무신사 기준 옷장 교차비교는 101.87초에 통과했고 유니클로 기준 옷장 교차비교도 91.97초에 통과했다. 무신사 1,037개 및 유니클로 243개 공식 실측 corpus 테스트와 5,026개 분류 테스트도 이 실행에서 통과했다. 결과 번들은 `/tmp/FitMatchA5000MusinsaFullRetry.xcresult`다.
- 실패 8개 중 `LiveReleaseQA1200Tests` 1개는 실기기 배치 번호 환경 변수가 없는 Simulator 전체-suite 실행으로 인한 하네스 실패다. 나머지 7개는 현재 앱 동작과 기존 회귀 기대값의 충돌로 출시 전 정리가 필요하다: 폴로 2개, 반팔·긴팔/확장 비교 정책 3개, source history 1개, 자동 기준 옷 선택 1개다.
- 잘못된 Swift Testing 식별자로 0건 실행된 두 번과 최초 Simulator test host launch 실패는 테스트 실적으로 계산하지 않았다.
- 현재 판정은 핵심 실상품 교차비교와 대규모 corpus는 통과했지만 전체 회귀 suite가 green은 아니다. 7개 정책 회귀의 기대값이 낡은 것인지 production 구현 결함인지 확인한 뒤 수정·재실행해야 출시 승인 근거가 된다.

## 32. 2026-08-14 A테스트 정책 회귀 보정

- 일반 셔츠가 혼합 쇼핑몰 경로의 `폴로셔츠` 문자열에 오염되지 않도록 상의 분류 증거 우선순위를 구체적인 공급사 leaf, 상품명의 명시적 소매 길이, 경로의 단일 길이, 상품명의 의류 구조 순으로 정리했다. 명확한 피케·카라·폴로 leaf는 `polo_shirt`로 유지한다.
- 반팔↔긴팔 상의는 자동 비교에서 제외하되 사용자가 직접 선택하면 소매길이를 제외한 공통 실측으로 참고용 부분 비교할 수 있다.
- 긴바지↔반바지는 자동 비교에서 제외하되 사용자가 직접 선택하면 총장·밑단을 제외하고 허리·엉덩이·허벅지 등 공통 실측으로 참고용 부분 비교할 수 있다.
- 같은 착용 부위의 아우터 길이·세부 종류 차이는 기존 P0 정책대로 자동 비교하지 않고 수동 참고 비교만 허용한다. 상의↔하의처럼 착용 부위가 다르면 수동 선택도 계속 차단한다.
- 현재 상품의 명확한 분류 증거와 과거 저장 선택이 충돌하면 현재 증거를 우선한다. 정상 측정 정의를 가진 정확한 대표 옷 1벌은 자동 선택된다는 회귀 fixture도 보강했다.
- 수정 전 실패했던 8개 집중 정책 테스트는 8/8 통과했다. 이후 전체 회귀 실행에서 5,026개 분류 감사 invalid 0, 무신사 공식 실측 1,037개 통과, 유니클로 243개 입력·238개 상품·1,574개 행·184개 비교쌍 복구를 확인했다.
- 전체 회귀 묶음은 실시간 네트워크/OCR 검사가 포함돼 30분 이상 소요되어 사용자 요청에 따라 마지막 저장 무신사 비교쌍 검사 도중 중단했다. 따라서 전체 suite 최종 green은 아직 주장하지 않는다.

## 33. 2026-08-14 실제 URL 균형 A테스트 100건

- `scripts/run-live-a-test-100.py`를 추가했다. iPhone·Simulator·DB를 사용하지 않고 무신사 상품/실측 API와 유니클로 사이즈 API를 새로 조회한 뒤 현재 FitMatch 정책으로 비교 시나리오를 재생한다.
- seed `2026081401`로 실제 접근·실측 가능한 고유 상품 206개를 확인하고 100개 비교쌍을 만들었다.
- 출처 조합은 무신사→무신사, 무신사→유니클로, 유니클로→무신사, 유니클로→유니클로 각각 25건이다. 기준 옷 ON 52 / OFF 48이다.
- 결과는 자동 비교 17, 수동 선택·참고 비교 25, 정상 차단 58이며 정책 모순 0건이다.
- 재감사 과정에서 실행기 자체의 아우터 대분류 과잉 허용, 상위 `반팔 & 긴팔` 경로 오염, 혼합 셔츠 경로의 폴로 오염을 발견해 앱과 동일한 증거 우선순위로 보정했다. 앱 production 로직 추가 변경은 없었다.
- 상세 실제 URL·상품명·쇼핑몰 분류·FitMatch 분류·UI 판정은 `Docs/TestEvidence/LiveA100-20260814/results.json`에 저장했다.

## 34. 2026-08-14 출시 전 최종 판정과 실기기 확인 항목

- 실제 URL A테스트 100건은 무신사·유니클로의 현재 상품/실측 API 가용성을 확인하고 별도 headless 실행기에서 현재 FitMatch 정책을 재생한 검사다. iPhone 앱 바이너리, Simulator, 개인 옷장, Supabase 데이터는 사용하지 않았다.
- 따라서 `100/100 PASS`는 실제 앱 전체 사용자 흐름이 100회 성공했다는 뜻이 아니다. 비교 정책상 모순을 찾지 못했다는 사전 감사 결과다.
- 특히 공유 확장 → 앱 열기 → 상품 파싱 → 옷장 조회 → 기준 옷 자동 선택/수동 선택 → 결과 UI → 기록 저장 → 재실행 후 복원은 실제 앱 환경에서 별도로 확인해야 한다.
- 출시 전 현재 App Store 제출용 Release 빌드와 동일한 버전으로 다음 6건을 iPhone에서 확인한다.
  1. 무신사 상품 공유 후 정상 자동 비교
  2. 유니클로 상품 공유 후 정상 자동 비교
  3. 반팔↔긴팔 조합에서 자동 비교 제외, 수동 부분 비교 제공, 소매길이 제외 문구 표시
  4. 기준 옷 OFF 상태에서 오류 화면이 아니라 `비교할 옷 선택` 화면 표시
  5. 비교 결과와 내 옷장 저장 정상 동작
  6. 앱 강제 종료·재실행 후 옷장 및 비교 기록 유지
- 위 6건에서 크래시, 멈춤, 잘못된 분류, 비정상 자동 비교, 저장 유실, 잘못된 안내 문구가 없으면 출시 승인 조건을 충족한 것으로 판단한다.
- 전체 네트워크/OCR 회귀 묶음은 앞서 장시간 실행 후 사용자 요청으로 중단했으므로 전체 suite green을 출시 근거로 주장하지 않는다.

## 35. 2026-08-14 브리프케이스 taxonomy 오분류 보정

- canonical bundle에서 무신사 `가방 > 브리프 케이스` 계열 4건이 `브리프` 키워드 때문에 남성 속옷으로 confirmed 처리된 것을 발견했다.
- 앱 내장 bundle과 연구 원본 bundle 모두 해당 4건을 `rejected / not_fitmatch_comparable`로 변경하고 앱 매핑·비교 family·extension을 제거했다.
- 상태 합계는 confirmed 1,327 / review_required 608 / rejected 1,451 / unsupported 40 / navigation_only 582로 바뀌었다. runtime mapping 3,426과 전체 4,008은 유지된다.
- 재생성 방지를 위해 taxonomy staging/refinement 생성 규칙에서 가방·브리프케이스 문맥을 속옷 키워드보다 우선하도록 수정했다.
- 운영 DB용 `073_briefcase_taxonomy_correction.sql`, 읽기 전용 검증 `074`, 백업 기반 rollback `075`를 추가했다. 운영 DB에는 아직 실행하지 않았다.
- 내장 bundle checksum과 manifest를 재생성했고 `canonicalTaxonomyRejectsMusinsaBriefcasesAsBags()` 회귀 테스트 1건이 Simulator에서 통과했다.
- 상의 611개는 상품 수가 아니라 confirmed 쇼핑몰 category path 수다. 분해 중 캐릭터 탐색 경로 2건이 `bra`, 유니클로 스웨트팬츠 1건이 상의/후드로 들어간 추가 이상 데이터도 발견했으며 후속 전수 정제가 필요하다.

## 36. 2026-08-14 DB 반영 전 canonical taxonomy 4,008건 전수검수

- 현재 production Swift 분류기로 5,026개 상품을 다시 실행했다. 5,026개 고유 입력, 분류 완료 4,697, 사용자 확인 329, invalid 0이며 테스트가 12.031초에 통과했다. xcresult는 `/tmp/FitMatchTaxonomyDBAudit5026.xcresult`다.
- 공식 taxonomy snapshot 4,008개 전체와 runtime mapping 3,426개를 current production 5,026건 및 Live A100의 200개 상품 관측과 교차검증했다. 상품 증거가 존재하는 고유 경로는 426개다.
- 구조 검증은 source 4,008, runtime 3,426, snapshot 매칭 3,426, source identity 고유성 모두 통과했다.
- 최종 감사 결과는 무변경 3,082, navigation 유지 582, confirmed 승격 후보 10, rejected 전환 9, review_required 전환 325다. high/critical 334건 중 실제 production/Live 상품 증거가 있는 행은 129, 없는 행은 205다.
- 명백한 rejected 전환 9건은 반려동물 의류 6건, 패딩/퍼 신발 2건, 드레스퍼퓸 1건이다. 이 외에는 자동 확정하지 않고 review_required로 보수적으로 제안했다.
- 산출물은 `Docs/Research/CanonicalTaxonomyAudit-20260814/`의 `audit-results.json`, `high-risk.json`, `db-candidate-audit.csv`, `report.md`, `manifest.json`, `current-production-5026-results.json`이다.
- `scripts/audit-canonical-taxonomy-for-db.mjs`와 검증기 `scripts/validate-canonical-taxonomy-audit.mjs`를 추가했다. 검증 결과 4,008행, runtime 3,426행, high-risk 334행, 4개 산출물 checksum 모두 통과했다.
- 운영 Supabase에는 쓰지 않았다. 334개 고위험 행의 정책 확정과 사용자 승인 후에만 새 버전 migration/validation/rollback을 생성한다.

## 37. 2026-08-14 taxonomy·A테스트 DB 적재 사전 브리핑 및 Excel 후속 작업

- 사용자 결정: A테스트에서 수집·검증한 5,026개 상품 데이터도 DB 적재 대상에서 제외하지 않는다. 다만 앱이 직접 사용하는 운영 taxonomy 데이터와 섞지 않고 회귀검증용 staging 데이터로 분리한다.
- 운영 taxonomy 원장은 `fitmatch_taxonomy` 스키마에 둔다. 공식 쇼핑몰 taxonomy node 4,008개, runtime mapping 3,426개, 분류 결정·앱 매핑·비교 family·실측 정책이 이 영역에 해당한다.
- A테스트 5,026개 상품은 기존 `fitmatch_staging.runtime_classification_regression_cases`에 적재하는 방향이다. 핵심 필드는 `rule_set_code`, `corpus_key`, `source_code`, `external_product_id`, `product_name`, `source_category_path`, 기대 대분류·세부분류·비교 가능 여부이며 URL·family·length·사용자 확인 필요 여부·원본 증거는 컬럼 확장 또는 `evidence jsonb` 사용을 검토한다.
- A테스트 실행 단위 요약은 기존 `fitmatch_staging.runtime_classification_parity_runs`에 보존한다. 현재 `details jsonb`만으로 개별 실행 결과 추적이 부족하면 별도 `runtime_classification_regression_results` staging 테이블 추가를 제안하되, 사용자 검토 전에는 생성하지 않는다.
- staging 회귀 데이터는 앱 런타임 조회 대상이 아니다. `anon`/`authenticated` CRUD는 계속 차단하고 backend batch 또는 `service_role`만 적재·검증한다. 추후 앱이 서버 taxonomy를 읽을 때도 좁은 RPC/view를 별도로 설계한다.
- Excel 사전 검수 파일에는 최소 다음 시트를 포함한다: `00_브리핑`, `01_테이블맵`, `02_Taxonomy요약`, `03_카테고리매핑샘플`, `04_A테스트적재설계`, `05_검수대상334`, `06_적재순서검증`, `07_전체4008`, `08_A테스트5026`.
- Excel에는 4,008개 taxonomy 전체 행, high/critical 검수 대상 334개 전체, current production A테스트 상품 5,026개 전체를 넣는다. 현재 수량은 confirmed 1,327 / review_required 608 / rejected 1,451 / unsupported 40 / navigation_only 582이며 감사 제안은 keep 3,082 / navigation 유지 582 / confirmed 후보 10 / rejected 전환 9 / review_required 전환 325다.
- 334개 제안은 자동 DB 정답이 아니다. 실제 상품 증거가 있는 행 129개와 없는 행 205개를 구분해 Excel에서 검토 상태로 표시하고, 사용자 승인 후 migration → read-only validation → promotion 순서로 진행한다.
- 현재 세션에는 Spreadsheets skill이 필수로 요구하는 `load_workspace_dependencies`가 노출되지 않았고 `@oai/artifact-tool` import도 실패했다. 규칙상 `openpyxl`, `xlsxwriter` 등으로 우회하지 않았으므로 `.xlsx`는 생성되지 않았다. 다음 세션에서 해당 도구가 제공되면 Excel 생성부터 재개한다.
- Excel 작성 전후 모두 Supabase에는 쓰지 않는다. Excel 검수·사용자 승인 후에만 schema 보완 여부와 seed/migration/validation/rollback SQL을 작성한다.

## 38. 2026-08-14 DB 적재 최종 설계 점검 및 실측 정책 보정

- 운영 데이터는 `fitmatch_catalog`의 release/document/source mapping 3개 테이블, 회귀 데이터는 `fitmatch_qa`의 classification case/validation run 2개 테이블로 분리하는 5테이블 설계로 정리했다. 기존 Supabase 테이블은 삭제하거나 변경하지 않았다.
- canonical runtime mapping은 4,008행이 아니라 실제 bundle의 `records` 3,426행이다. navigation 582개는 bundle에 개별 행이 없고 집계값만 있으므로 runtime mapping 행으로 생성하지 않는다.
- confirmed 1,327개 `appMapping.detailCode`를 현재 `FitMatchTaxonomy.json`과 전수 대조했다. 현재 detail과 직접 일치 558, NULL 186, 현재 taxonomy에 없는 legacy/semantic detail 583이다. 따라서 canonical `appMapping`은 `legacy_app_mapping`으로 원형 보존하고 현재 앱 `detailCategory` FK나 운영 기본값으로 사용하지 않는다. 최종 앱 detail은 기존 product classifier와 5,026개 회귀 결과로 검증한다.
- comparison family transform 31개와 confirmed 1,327개 resolved app family는 모두 현재 Swift `ComparisonGarmentFamily` 값으로 변환 가능했다.
- comparison/garment policy의 measurement 참조 137개를 전수 대조해 유일하게 정의가 없던 `foot_length` 3개 참조를 확인했다. `FitMatchMeasurementPolicies.json`의 canonical measurement definitions에 `foot_length`를 추가했으며 raw source alias는 공식 근거 없이 만들지 않았다.
- measurement definitions는 21→22개가 됐다. 새 measurement file SHA-256은 `5bcec02403caeb389efafffb7cd3dde6cefa15f49c8f6098ee1a40c036ce8883`, 새 canonical bundle checksum은 `acb5d29f00840773f3283fc9ea5e8703078d7bb205a844e4da245940fdca0467`이다. manifest의 bytes, count, checksum을 함께 갱신했다.
- 로컬 checksum·bytes·manifest·bundle checksum과 모든 comparison measurement 참조를 다시 검증했고 누락 0이었다. Source mapping 3,426개, source identity 고유 3,426개, QA 5,026개(확정 4,697, 사용자 확인 329)는 유지됐다.
- QA 329개 중 최종 분류 출력 전체 NULL은 249개, `other/other` placeholder가 있는 보류는 80개다. QA 기대 결과 컬럼은 조건부 nullable이어야 하며 원본에 없는 `canonicalEligibility`를 5,026개 기대값으로 만들지 않는다.
- 검수용 Excel 생성은 승인됐지만 이 세션의 callable tool 목록에 Spreadsheets skill 필수 도구인 `load_workspace_dependencies`가 실제로 노출되지 않아 계속 차단됐다. 다른 Excel 라이브러리로 우회하지 않았으며 Supabase에도 쓰지 않았다.

## 39. 2026-08-14 Supabase 카테고리 release store 생성 및 적재

- 사용자 최종 지시에 따라 Excel 단계는 제외하고 FitMatch Supabase 프로젝트(`hnkplvyegonlhumlejst`)에 직접 반영했다.
- 원격 의존성을 먼저 확인했다. 기존 `public`, `fitmatch_taxonomy`, `fitmatch_staging` 데이터는 사용자 옷장 및 기존 taxonomy FK와 연결돼 있어 삭제하거나 수정하지 않았다.
- migration `create_private_category_release_store`로 비공개 `fitmatch_catalog`, `fitmatch_qa` 스키마와 5개 테이블을 생성했다: `releases`, `documents`, `source_category_mappings`, `classification_cases`, `validation_runs`.
- `anon`, `authenticated`, `public`의 schema/table 권한을 모두 회수하고 RLS를 켰다. 의도적으로 client policy를 만들지 않아 앱 클라이언트는 접근할 수 없고 `service_role` backend만 접근한다. Supabase advisor의 `rls_enabled_no_policy` INFO는 이 deny-by-default 설계에 따른 예상 경고다.
- release `observed-official-2026-08-03__taxonomy-refined-2026-08-03`에 manifest, 앱 taxonomy, comparison policy, measurement policy, source mapping metadata 문서 5개를 checksum/byte 수와 함께 적재했다.
- 대형 source mapping 원문을 문서와 행 데이터로 이중 저장하지 않았다. runtime mapping 3,426개를 조회용 projection 컬럼과 `raw_record jsonb` 원형으로 각각 적재했다.
- 기존 `/tmp/FitMatchTaxonomyDBAudit5026.xcresult`에서 실제 production classifier 첨부 결과를 추출해 입력 fixture와 결합하고 `fitmatch_qa.classification_cases`에 5,026개를 적재했다. 원본에 없는 기대값은 생성하지 않았고 보류 행의 기대 분류 컬럼은 NULL을 허용했다.
- DB 자체 검증 결과 documents 5, mappings 3,426, source identity distinct 3,426, mapping projection error 0, QA 5,026, 사용자 확인 329, full NULL 249, `other/other` 80, QA projection error 0으로 모두 통과했다. release 상태는 `validated`, validation run은 `passed`다.
- Supabase performance advisor가 지적한 `validation_runs.release_id` FK 인덱스는 후속 migration `index_category_validation_release_fk`로 추가했다. 새 조회 인덱스의 unused 경고는 생성 직후라 정상이다.
- 기존 `fitmatch_staging` 일부 테이블의 RLS 비활성 보안 경고는 발견했지만, 기존 접근 계약을 모르는 상태에서 RLS를 켜면 기능이 중단될 수 있으므로 이번 작업에서는 변경하지 않았다.

## 40. 2026-08-14 현재 앱 taxonomy 정규화 및 corrected 정책 버전 반영

- 사용자 승인 후 기존 DB를 다시 감사했다. `fitmatch_taxonomy.source_categories` 4,008건은 무신사 2,277/유니클로 1,731이며 navigation 582, non-navigation 3,426이다. 새 bundle mapping 3,426건과 복합 identity를 대조해 3,426/3,426 일치, 누락 0을 확인했다.
- 기존 `taxonomy-refined-2026-08-03`은 confirmed 1,331/rejected 1,447로 현재 bundle보다 브리프케이스 4건이 뒤처져 있었다. 기존 버전을 update하지 않고 immutable successor `taxonomy-corrected-2026-08-14`를 생성했다.
- corrected 정책에는 decision 4,008, length axes 4,008, evidence 4,019, audit 4,008, confirmed legacy/semantic app mapping 1,327건을 복제했다. 브리프케이스 4건만 confirmed→rejected로 바꾸고 garment/family/default mapping을 제거했다. 최종 상태는 confirmed 1,327/review_required 608/rejected 1,451/unsupported 40/navigation_only 582이며 정책 상태는 `validated`다.
- 현재 앱 `FitMatchTaxonomy.json`을 release-scoped `fitmatch_catalog.app_categories` 11건과 `app_category_details` 75건으로 정규화했다. 기존 `public.app_categories` 99건은 semantic garment type이 섞인 legacy 구조라 삭제·수정하지 않았다.
- `fitmatch_catalog.source_to_fitmatch_mappings` security-invoker view를 추가했다. confirmed 1,327건은 유효한 앱 대분류만 연결하고 앱 세부분류는 강제로 확정하지 않는다. 모든 confirmed 행의 `detail_resolution_strategy`는 `product_classifier_required`이고 최종 detail은 API 상품명/경로를 사용하는 production classifier가 결정한다. 원래 appMapping은 `legacy_app_mapping`으로만 노출한다.
- corrected DB 3,426행과 현재 bundle을 status/category/garment/family 단위로 전수 대조해 불일치 0이었다. 앱 대분류 FK 불일치 0, 강제 app detail 0이며 `078_current_taxonomy_validation.sql`도 통과했다.
- 적용 migration은 `normalize_current_app_taxonomy`, `add_corrected_taxonomy_policy_20260814`, `add_source_to_fitmatch_mapping_view`다. 재현/검증/rollback SQL은 `supabase/sql/076_normalize_current_app_taxonomy.sql`, `077_add_corrected_taxonomy_policy.sql`, `078_current_taxonomy_validation.sql`, `079_current_taxonomy_rollback.sql`에 기록했다.
- QA 상품명 5,026건은 운영 taxonomy와 연결하지 않았고 `fitmatch_qa` 회귀 fixture로만 유지했다. 기존 사용자/Auth/public/legacy taxonomy 데이터는 삭제하거나 수정하지 않았다.
- Supabase advisor에서 새 구조의 unindexed FK 경고는 0이다. RLS policy 없음 INFO는 private schema에서 anon/authenticated를 의도적으로 전면 차단한 결과이고, unused index INFO는 생성 직후 예상 상태다.

## 41. 2026-08-14 DB 기반 A테스트 실행

- DB corrected 정책과 bundle runtime mapping을 먼저 전수 대조했다. 3,426건이 모두 identity로 결합됐고 identity/status/category/garment/family mismatch는 각각 0이었다. 정규 앱 taxonomy도 category 11/detail 75를 확인했다.
- DB의 `fitmatch_qa.classification_cases` 기대 집계는 5,026건, 사용자 확인 329, 전체 NULL 249, `other/other` 80, projection error 0이었다.
- 현재 Swift production classifier를 `CategoryValidation5026AuditTests/testCurrentProductionClassifierReclassifiesAll5026Products`로 새로 실행했다. 5,026 unique input/output, classified 4,697, 사용자 확인 329, invalid 0, placeholder 80이며 11.595초에 통과했다.
- DB 기대 집계와 새 XCTest 결과가 일치했다. 결과 bundle은 `/tmp/FitMatchDBBackedATest-20260814-2.xcresult`다.
- Supabase `fitmatch_qa.validation_runs`에 validator `db_backed_a_test_v1`, run id `51943e7b-9068-4dcb-8584-606181db2c8f`로 기록했다. status `passed`, mapping_count 3,426, qa_count 5,026, error_count 0이다.
- 최초 sandbox 실행은 CoreSimulatorService 권한 및 SwiftSoup 네트워크 해석 제한으로 실행 전 실패했다. 권한이 허용된 정상 환경에서 재실행한 결과만 A테스트 실적으로 기록했다.

## 42. 2026-08-14 실기기 비교 결과 화면 진입 성능 진단 및 1차 보완

- 실기기 로그 3건에서 비교 결과 화면 `on_appear`는 52.1~93.3ms, 다음 main runloop 도달은 30.7~65.2ms 추가 지연됐다. 등록 데이터는 user fit 3건/history 3건으로 작아 현재 병목을 대량 SwiftData 조회로 보기는 어렵다.
- 상품·기준 옷 썸네일은 cache hit 0.0ms였고 첫 기준 옷 이미지도 download 4.8ms + decode 3.1ms, 총 7.9ms였다. 따라서 이번 재현의 주 병목은 네트워크나 이미지가 아니라 결과 화면의 초기 SwiftUI 구성·계산·layout이다.
- `settled_250ms`의 311.6~355.9ms는 의도적으로 예약한 250ms 타이머를 포함하므로 300ms 정지 시간으로 해석하지 않는다.
- `RecommendationResultView`의 최상위 결과 카드 스택을 `LazyVStack`으로 바꿔 화면 아래 카드를 최초 프레임에 모두 만들지 않도록 했다. 추천 카드와 실측 카드에서는 실측 종류, 신뢰도, 차이·제외 목록을 한 렌더링 안에서 재사용하고 각 행의 실측값 조회 중복을 제거했다.
- 로그에 별도로 `<OnScrollGeometryChange Modifier> tried to update multiple times per frame` 경고가 1회 있다. 이는 결과 화면 진입 병목과 분리된 스크롤 상태 갱신 경고이므로 보호 대상 tab bar scroll modifier는 이번 변경에서 건드리지 않았다.
- Simulator는 사용하지 않았다. generic iOS device 무서명 빌드가 통과했으며, 동일한 실기기 동작을 다시 실행해 `on_appear`와 `next_main_runloop` 전후 수치를 비교해야 체감 개선을 확정할 수 있다.

## 43. 2026-08-14 상세 화면 스크롤 성능 진단 추가

- 비교 결과와 내 옷 상세의 실제 ScrollView에 DEBUG 전용 `ScrollPerformanceDiagnostics`를 추가했다. 공용 탭바/상단 헤더의 보호된 스크롤 modifier와 해당 call site는 변경하지 않았다.
- CADisplayLink 기준으로 스크롤 중 24ms 이상 프레임은 `long_frame`, 40ms 이상은 `severe_frame`으로 기록한다. 화면 종료 시 전체 프레임 수, 긴 프레임 수, 심한 프레임 수, 동일 프레임 geometry 중복 갱신 수, 최장 프레임을 `monitor_summary`로 출력한다.
- iOS 18 이상에서는 스크롤 phase 전환, 0.25초 간격 offset/velocity/content/container 표본, 한 display frame 안의 geometry 중복 갱신도 `[ScrollPerformance]` 로그로 남긴다. Release에서는 진단 modifier가 제거돼 출시 성능에 영향을 주지 않는다.
- Simulator는 사용하지 않았다. generic iOS device 무서명 빌드가 통과했다. 실기기에서 비교 결과와 내 옷 상세를 각각 위아래로 빠르게 2~3회 스크롤한 로그가 있어야 실제 병목 위치를 판정할 수 있다.

## 44. 2026-08-14 실기기 스크롤 로그 판정 및 ProMotion 허용

- 비교 결과 실제 스크롤 로그에서 40ms 이상 severe frame은 0건이었다. 대표 실행은 3.714초/229 frames/long frame 6/스크롤 중 worst 25.0ms, 다른 실행은 1.972초/117 frames/long frame 2였다. 반복적인 메인 스레드 정지가 스크롤 병목이라는 증거는 없었다.
- 실기기 `maximumFramesPerSecond`는 120인데 측정 cadence는 약 60fps였고 앱 Info.plist에 `CADisableMinimumFrameDurationOnPhone`이 없었다. Apple 공식 정의상 기본값 NO에서는 iPhone의 시스템 기본값보다 높은 프레임률에 접근할 수 없으므로 해당 키를 YES로 추가했다.
- 이 설정은 120Hz를 강제 고정하지 않고 높은 프레임률 접근만 허용한다. 실제 주사율은 저전력 모드, 발열, 화면 상태 등에 따라 iOS가 동적으로 조정한다.
- 최초 진단기의 `multiple_geometry_updates_in_frame` 14~73건은 120Hz geometry callback을 60Hz CADisplayLink tick으로 묶어 과대 집계했을 가능성이 높다. DEBUG monitor가 기기 최대 FPS를 요청하도록 보정하고 monitor 시작 전 callback은 무시하도록 수정했다.
- 내 옷 상세 기록에는 `interacting/decelerating` phase가 없어 실제 스크롤 동작이 포함되지 않았다. 화면 진입 성능만 확인됐고 내 옷 상세 스크롤 자체는 아직 미검증이다.
- plist lint와 generic iOS device 무서명 빌드가 통과했다. Simulator는 사용하지 않았고 보호된 tab bar scroll modifier와 call site는 변경하지 않았다.

## 45. 2026-08-14 기록→결과 전환 및 결과 스크롤 진단 보정

- ProMotion 적용 후 결과 화면의 대표 실제 드래그는 2.636초/291 frames로 약 110fps였고 long/severe frame은 모두 0, worst 19.0ms였다. 따라서 지속적인 렌더링 성능 부족은 재현되지 않았다.
- 결과 화면 콘텐츠 685pt/컨테이너 619pt로 실제 스크롤 범위가 약 66pt뿐인데 드래그는 bottom 150pt, top -69pt까지 overscroll했다. 사용자가 느낀 일부 저항감은 대부분 정상 스크롤보다 짧은 콘텐츠의 양 끝 bounce 구간일 가능성이 있다. UX 변경 없이 bounce 정책은 아직 바꾸지 않았다.
- DEBUG 진단기가 navigation transition 첫 260ms 동안 `multiple_geometry_updates_in_frame`을 26회 개별 print하고 있었다. 메인 스레드 콘솔 출력이 진입 애니메이션을 방해할 수 있어 개별 출력은 제거하고 summary 집계만 유지했다.
- 스크롤 monitor 시작을 화면 onAppear 즉시에서 350ms 뒤로 늦춰 navigation transition과 초기 safe-area/content layout 측정에 진단기가 개입하지 않도록 했다.
- 기록 카드 탭부터 결과 `onAppear`, 첫 main runloop까지 `[NavigationPerformance] route=history_to_result`로 측정하는 로그를 list/grid/recompare 경로에 추가했다. 다음 실기기 로그에서 실제 탭→화면 전환 지연과 결과 화면 내부 렌더 지연을 분리할 수 있다.
- generic iOS device 무서명 빌드가 통과했다. Simulator는 사용하지 않았고 보호된 tab bar scroll modifier와 call site는 변경하지 않았다.

## 46. 2026-08-14 결과 화면 초기 SwiftData 조회 지연 로딩

- 보정된 실기기 로그에서 기록 카드 탭→결과 onAppear는 58.1~107.1ms, 첫 main runloop는 95.9~155.9ms였다. 이미지 cache miss도 총 6.9ms뿐이라 전환 병목은 결과 화면 생성 전후의 메인 스레드 작업으로 확정했다.
- 결과 스크롤 monitor는 1.707초/194 frames와 2.739초/317 frames로 약 114~116fps였고 long/severe frame 0, duplicate update 0이었다. 지속적인 드래그 렌더링 병목은 재현되지 않았다.
- `RecommendationResultView`가 진입 즉시 실행하던 `UserFit` 전체 @Query와 `RecommendationHistory` 전체 @Query를 제거했다. 기준 옷 목록은 picker sheet 내부 @Query로 옮기고, 기존 비교 기록은 사용자가 실제로 다른 기준 옷을 선택해 저장할 때만 fetch한다.
- legacy ranking 계산도 해당 UI가 실제 평가될 때만 UserFit을 fetch하도록 바꿨다. 현재 결과 화면의 기능·저장 방식·추천 결과는 변경하지 않았다.
- generic iOS device 무서명 빌드가 통과했다. Simulator는 사용하지 않았고 보호된 tab bar scroll modifier와 call site는 변경하지 않았다.

## 47. 2026-08-14 root visibility 레이아웃 영향 대조 로그 판정

- 새 실기기 캡처에서 history root visibility가 true→false로 바뀔 때와 bottom overscroll 이후 false→true로 바뀔 때 `contentSize=1252`, `containerSize=852`, `insetTop=59`, `insetBottom=34`, `maxOffset=493`가 모두 유지됐다. visibility 변경이 ScrollView safe area/frame/padding/content size를 바꾸는 피드백 루프 증거는 이번 캡처에서 없었다.
- visibility 재표시는 bottom overscroll offset 498.3에서 새 upward drag로 460.7까지 돌아온 시점이었다. bottomLock 해제와 visibility=true가 같은 사용자 드래그에서 발생해 현재 요구 동작과 일치했다. 원인으로 확정되지 않았으므로 보호된 scroll modifier 및 UI는 변경하지 않았다.
- 결과 화면 실제 드래그 3건은 각각 401/299/210 frames, long 0, severe 0, duplicate 0, worst 19.8~22.1ms였다. 측정 구간 평균은 약 117~119fps로 카드 렌더링·LazyVStack·스크롤 엔진을 우선 수정할 근거가 없다.
- SwiftData 초기 조회 지연 적용 후 history→result warm path의 first main runloop는 70.3/97.4/86.1ms로 기존 95.9~155.9ms보다 개선됐다. 다만 첫 cold path는 152.7ms로 남아 있다.
- 남은 우선 조사 대상은 첫 cold navigation의 99.3ms pre-onAppear와 이후 53.4ms main-runloop 구간이다. 이미지 miss는 6.7ms라 우선순위가 낮고, UI 변경 전에 실제 기기 Time Profiler로 destination 생성, SwiftData relationship fault, SwiftUI body/layout, navigation transition stack을 분리해야 한다.

## 48. 2026-08-14 실제 iPhone Time Profiler 캡처

- 연결된 `iPhone 14 Pro`의 실행 중 FitMatch 프로세스(pid 29267)에 Instruments Time Profiler를 20초간 attach해 기록→결과 진입을 실제 기기에서 캡처했다. Simulator는 사용하지 않았다.
- trace는 `/tmp/FitMatchHistoryColdNavigation-2.trace`에 저장됐고 크기는 약 14MB다. 대상 OS는 iOS 26.6, Instruments/Xcode는 26.0이며 time-profile/time-sample/runloop/hang 테이블이 포함됐다.
- `xcrun xctrace export --toc`는 성공했지만 time-profile call tree를 XML로 내보내는 Xcode 26 CLI가 Bus error 10으로 종료됐다. 따라서 trace 캡처는 성공했으나 상위 CPU stack을 CLI에서 판독해 원인을 확정하지 못했다. Instruments GUI에서 해당 trace의 Main Thread, 기록 카드 탭 시점 전후 약 160ms 범위를 열어 SwiftUI/SwiftData/navigation stack을 확인해야 한다.
- call tree 증거가 아직 없으므로 카드, LazyVStack, root scroll visibility, safe area, bounce 동작은 추가 변경하지 않았다.

## 49. 2026-08-15 실제 iPhone Time Profiler GUI 1차 판독

- `/tmp/FitMatchHistoryColdNavigation-2.trace`를 Instruments GUI에서 열어 전체 22초 구간의 Main Thread call tree를 확인했다. FitMatch 전체 sample weight는 5.90초, Main Thread는 2.87초(48.7%)였다.
- Main Thread에서는 UIKit update sequence와 SwiftUI `AttributeGraph` 갱신, `NavigationStackCoordinator.update`, `UIHostingController`, layout/view-size cache 및 preference 결합 계열 stack이 주로 관찰됐다. 전체 구간 기준으로 SwiftData fetch나 이미지 decode가 최상위 CPU 병목이라는 증거는 보이지 않았다.
- 이 결과는 첫 cold navigation의 원인 후보를 SwiftUI destination 생성·AttributeGraph·UIKit layout/update로 좁히지만, 22초 전체 aggregate이므로 약 150ms 전환 구간의 단일 원인을 확정하는 증거는 아니다.
- macOS 화면 기록 권한은 정상 동작했지만 `System Events` 자동화가 오류 `-10827`로 응답하지 않았고, CoreGraphics 입력 이벤트도 Instruments 타임라인 선택에 반영되지 않았다. 선택 구간 call tree를 확보하기 전에는 UI/동작을 추가 변경하지 않는다.

## 50. 2026-08-15 무신사·유니클로 3시간 출시 A테스트 전수 감사

- 로컬 `main` HEAD `9264814` 기준으로 프로젝트의 공식 상품 corpus 5,026개(무신사 4,011/유니클로 1,015)를 production `ParsedClosetClassification`에 다시 통과시켰다. 입력/고유/출력 5,026, 구조적으로 유효 4,701, 사용자 확인 325, invalid 0, placeholder other 79였다. 상품별 쇼핑몰 경로→FitMatch 대분류/세부분류/family/length 내역은 archive CSV에 저장했다.
- 실제 iPhone 14 Pro(iOS 26.6, arm64)에서 5,026개 production 분류 테스트와 애매/other 325개 production live parser 재검증을 완료했다. 두 XCTest 모두 실패 0이었다. 325개는 parsing 325/325, 최종 사용자 확인 49, 위험한 other 자동 확정 0, parser 실패 0이었다. 이 중 최신 무신사 경로에서 `bottoms/other_bottoms`로 구조 분류된 점프수트·오버올 55개는 embedded canonical mapping이 `rejected`, `eligibility=false`, app mapping 없음이라 최종 비교 후보에서 제외된다. Simulator는 사용하지 않았다.
- 공식 endpoint 5,026개를 저속 재조회했다. 전체 도달, rate limit 0, unavailable 0, 공식 실측 즉시 확인 4,569(무신사 3,561/유니클로 1,008), 직접 실측 응답 없음 457(무신사 450/유니클로 7)이다. 무신사 450개는 HTML/OCR fallback 또는 수동 입력 대상이므로 곧바로 앱 parser 실패로 해석하지 않는다.
- 현재 의미 분류 결함은 고유 233개이며, canonical bundle과 matcher의 최종 product-level 교정을 적용한 뒤에도 비교 후보 선택·차단에 직접 영향을 주는 P0는 128개(무신사 113/유니클로 15)다. 이 중 116개는 현재 공식 실측까지 즉시 내려온다. family 방향 교차감사에서 `E480966`, `E485369`, `E487201` 히트텍 레깅스 3개가 `base_layer_top`/T-shirt family로 라우팅되는 결함도 확인했다.
- 가장 치명적인 회귀는 최신 로컬 커밋 `9264814`가 추가한 `explicitUnderwearDetail`의 부분 문자열 검사다. `브라운`/`브라이트`/`CHAMBRAY`/`무브라이트` 87개를 여성 브라로, `brief lined` 러닝 하의 3개를 남성 브리프로 바꿨다. 90개 모두 이전 corpus에서는 속옷이 아니었고 84개는 현재 공식 실측이 직접 제공된다. 안전한 `containsExplicitBra` 함수가 이미 있지만 새 helper가 그보다 먼저 실행된다.
- 기존 Swift Testing 회귀 `brownBottomNamesDoNotBecomeBras()`는 실제 두 브라운 팬츠를 하의로 요구하지만 현재 production 5,026 출력은 둘 다 `underwear/women_bra`다. 최신 HEAD가 기존 테스트 계약과 모순되므로 전체 suite green을 주장할 수 없다.
- 그 외 활성 P0는 명시적 가디건 10, 다중 구조 세트 11, 스코츠 major/family 8, 상의 경로 브라탑 major/family 6, 블라우스→T-shirt 4, 히트텍 레깅스→상체 base-layer 3, 하이픈 소매 길이 2, 옵션/레이어/다중 길이 3, 유니클로 코치재킷 1이다. 일반 셔츠 83, 블라우스 22 등의 구조 세부분류 손실과 긴바지를 `같은 긴팔`로 표시할 수 있는 문구 1곳은 P1이다.
- 유니클로 AIRism 이름 97개를 별도 전수 확인했다. 속옷 경로 54개만 속옷이고 나머지는 티셔츠·폴로·팬츠·원피스·레깅스·아우터 등 공식 경로대로 분리되어, AIRism 문자열만으로 모두 속옷 처리하는 문제는 재현되지 않았다.
- 명시적 폴로셔츠 140개(무신사 122/유니클로 18)를 추가 대조했다. bundle이 중간에 `shirt`를 저장하지만 비교 직전 `storedGarmentType`이 inferred T-shirt family로 교정하며 Product/UserFit 양쪽에 적용된다. 기존 테스트도 저장값 `shirt`인 폴로↔티셔츠 허용과 폴로↔우븐 셔츠 차단을 검증한다. 내장 정책과 생성 스크립트의 레거시 표기는 정리 권장이지만 실행 P0는 아니다.
- 무신사 상품 4534935는 공식 `goodsNm` 자체에 `https://bizest...detailCMD...` 관리자 URL이 붙어 있고 앱 parser가 이를 그대로 사용한다. 정상 `goodsNmEng`가 있으므로 URL/관리자 패턴 검출 후 fallback하는 방어가 필요하다.
- 기존 5,000건 A테스트는 위험 상품이 포함된 520건을 출시 근거에서 제외하고 안전한 4,480/4,480만 유효 PASS로 재판정했다. 신규 라이브 700건도 위험 상품 86건을 제외한 614/614가 유효 PASS다. 정상 분류 상품의 정책 흐름은 대체로 안정적이지만 현재 P0 때문에 전체 출시는 보류다.
- Release arm64 generic iPhone 무서명 빌드는 성공했다. Debug generic iPhone arm64 `build-for-testing`도 앱·Share Extension·unit/UI test 타깃 전부 컴파일되어 `TEST BUILD SUCCEEDED`를 확인했다. 추가 P0 실제 iPhone 회귀 실행은 build/sign까지 완료됐으나 기기가 잠겨 launch 전 대기하여 중단했으므로 테스트 실적으로 계산하지 않는다.
- 최종 보고서 정리 후에도 Simulator 없이 generic iOS Release를 새로 전체 빌드했고 앱·Share Extension 포함 `BUILD SUCCEEDED`와 store validation 단계를 다시 확인했다.
- 추적 보고서는 `Docs/ReleaseATestReport-20260815.md`, machine-readable evidence는 `../FitMatchArchive/Docs/TestEvidence/ReleaseATest-20260815/`에 있다. 앱 로직·DB는 이번 감사에서 수정하지 않았다. 다음 작업은 P0/P1 로직 수정 → 233개 fixture 고정 → 5,026 semantic oracle와 A테스트 재실행 → 실제 iPhone 핵심 사용자 여정 6건이다.
- 감사 기준 local `main`은 `origin/main`보다 1커밋 앞이고, 기존 상세 화면 성능 진단 관련 작업 트리가 미커밋 상태다. 분류기·matcher·canonical bundle의 미커밋 변경은 없지만 build 검증은 현재 작업 트리를 포함하므로, 출시 전 정확한 source revision을 커밋으로 고정해야 한다.

## 51. 2026-08-15 A테스트 P0 분류 결함 소스 보정

- 사용자 지시에 따라 재전수검사보다 소스 수정을 먼저 진행했다. `ParsedClosetClassification`에서 `브라운`·`브라이트`·`CHAMBRAY`를 브라로 보던 부분 문자열 검사를 명시적 브라 토큰 검사로 교체했고, 일반 하의의 `brief lined`는 속옷 경로에서만 브리프로 확정하도록 제한했다.
- 일반 셔츠·블라우스 상품명 구조가 반팔·긴팔 속성보다 먼저 세부분류에 반영되도록 우선순위를 고쳤다. `short-sleeve`/`long-sleeve` 하이픈 표기도 길이 속성으로 인식한다.
- 명시적 가디건은 쇼핑몰의 상의 merchandising bucket과 무관하게 아우터/가디건 구조로 통일했다. 스코츠는 팬츠 상위 경로에서도 스커트 family로 통일하고, canonical 저장값이 pants여도 비교 직전 스커트로 교정한다.
- 상품명에 명시된 레깅스는 히트텍/이너웨어 경로보다 우선해 하의 레깅스로 분류하며, 하의 화면 분류에 상체 canonical family가 저장된 경우 matcher가 하체 inferred family로 복구한다. 속옷 화면 분류는 비교 family도 underwear로 고정한다.
- 공식 metadata가 그래픽 티 경로로 내려온 `KIDS PEANUTS코치재킷` 같은 강한 아우터 상품명은 상의/기타 경로에서 아우터로 복구한다.
- `[SET] T-shirt + Shorts`, 탑+가디건 세트처럼 서로 다른 의류 구조가 함께 있는 세트와 민소매/반팔 옵션·레이어 충돌 상품은 단일 의류로 자동 확정하지 않고 사용자 분류 확인으로 보낸다.
- 무신사 `goodsNm`에 URL·관리자 경로가 섞인 경우 정상 `goodsNmEng`가 있으면 이를 표시 상품명으로 선택하는 방어를 추가했다.
- 위 정책을 고정하는 Swift Testing 회귀를 추가했다. Simulator와 실제 iPhone 데이터는 사용하지 않았다. generic iOS Debug `build-for-testing`을 두 번 실행했고 앱, Share Extension, unit/UI test 타깃이 모두 `TEST BUILD SUCCEEDED`로 컴파일됐다. 테스트 실행과 5,026건 semantic oracle 재검사는 다음 단계이며, 이 결과만으로 출시 가능 판정을 내리지는 않는다.

## 52. 2026-08-15 유니클로 현재 판매 상품 전수 A테스트

- 유니클로 한국 공식몰 MEN/WOMEN/KIDS/BABY 공개 카테고리 199페이지를 수집했다. 1,028개 노출, 상품 ID 914개, 정규화 identity 881개 중 상세 페이지가 현재 열리는 상품은 880개였다. `E479751-000` 한 건은 공식 카테고리에 남아 있지만 상세가 404라 활성 상품과 분리했다.
- 880개 원본 사이즈 행 5,193개를 production 파서로 통과시켜 고유 사이즈 행 5,181개를 만들었다. 차이 12개는 동일 상품·색상 안의 중복 사이즈 표기이며 파싱 누락이 아니다. 사용할 수 있는 사이즈가 있는 상품은 752개다.
- 중간 의미 감사에서 `니트 > 브이넥/터틀넥/워셔블/GU`처럼 일반 leaf 아래의 니트 구조가 사라지는 경계, `Cut & Sewn` 상의 경계, 일반 이너웨어 T가 canonical 분류 전에 사이즈 변환돼 가슴·총장 실측이 소실되는 결함을 발견해 수정했다. AIRism/HEATTECH 기능명은 의류 구조가 아니라 공식 경로를 우선하도록 유지했고, AIRism 코튼 외출용 T 예외도 보존했다.
- 연결된 iPhone 14 Pro(iOS 26.6)에서 최종 production 사용자 흐름을 실행했다. 활성 880개, raw 5,193, parsed 5,181, 자동 비교 정책 검사 대상 610개, A테스트 2,288건이 모두 통과했다. 구성은 빈 옷장 752, 기준 옷 없음/수동 후보 512, 동일 프로필 기준 옷 자동 비교 512, 타 대분류 오비교 차단 512다.
- FitMatch 대분류 결과는 상의 340, 하의 108, 아우터 95, 속옷 98, 홈웨어 36, 레깅스 24, 스커트 23, 원피스 15, 자동 분류·비교 제외 또는 사용자 확인 141이다. 마지막 141건은 양말·벨트·우산·모자·신발 등 비의류와 브라·바디수트·커버올·수납 파우치 등 현재 전용 비교 정책 밖 항목으로 별도 CSV에 이유를 전수 기록했다.
- Simulator, 개인 iPhone 옷장 데이터, Supabase 운영 데이터는 사용하지 않았다. 최종 원본 결과는 `/tmp/FitMatchCurrentUniqloCatalog-20260815-7.xcresult`, 보고서는 `Docs/CurrentUniqloCatalogATestReport-20260815.md`, 전수 CSV/JSON은 `Docs/TestEvidence/CurrentUniqloCatalog-20260815/`에 있다.
- 자동화 범위에서는 유니클로 경로를 출시 가능(GO)으로 판정했다. 실제 공유 시트 진입·색상 썸네일·안내 버튼 이동·네트워크 재시도는 화면/OS 통합 영역이라 출시 전 실기기 수동 4개 흐름을 별도로 확인해야 한다.

## 53. 2026-08-15 유니클로 증분 수집기 신뢰성 보정

- 동일한 유니클로 카테고리 URL이 HTTP 200을 반환하면서도 hydration에는 다른 카테고리 검색 결과가 들어오는 사례를 확인했다. 요청 경로와 정확히 일치하는 `search` hydration key가 있을 때만 해당 페이지의 상품 ID를 수집하도록 엄격 검증을 추가했다.
- 응답 경로가 다르면 고유 캐시 우회 query로 수집기가 허용하는 최대값인 기본 5회 의미 재시도를 수행하고 원본을 `category-page-mismatches`에 보존한다. 실제 동일 URL 병렬 표본 4회 중 정상 3회/오염 1회로 변동성이 확인됐다. 재시도 후에도 불일치하면 그 페이지의 상품·하위 카테고리를 합치지 않고 `category_response_failures`와 `discovery_complete=false`를 결과에 남긴 뒤 종료 코드 2로 실패를 알린다. 불완전 수집에서는 기존 상품을 `not seen`으로 판정하지 않는다.
- 증분 상태는 상세 HTML뿐 아니라 공식 사이즈 응답의 `result_found`까지 확인된 상품만 `stored`로 승격한다. 과거 `known_unavailable` 상품은 다시 노출되면 재수집하며 실제 상품명을 상태에 보존한다.
- 상태 JSON 저장을 임시 파일 교체 방식으로 바꾸고 state별 비차단 파일 잠금을 추가해 중단·동시 실행 시 손상 가능성을 줄였다. 결과 용어도 `newly_seen`, `not_seen_this_run`, `pending_retry`로 바꿔 판매 시작·종료를 단정하지 않도록 했다.

## 54. 2026-08-18 DB 기반 상품 런타임 기반 완성

- Supabase 운영 프로젝트 `hnkplvyegonlhumlejst`에 migration 5개를 적용했다: `create_product_runtime_foundation_v1`(20260818011818), `create_product_runtime_procedures_v1`(20260818012026), `align_product_runtime_policy_v1`(20260818013019), `validate_product_runtime_v1`(20260818013251), `index_product_runtime_foreign_keys_v1`(20260818013611).
- 공용 상품·분류 이력·variant·size·canonical measurement 저장소와 사용자별 상품 intake, 옷장 canonical snapshot/override, 비교 run/result/measurement result를 추가했다. 기존 `source_product_snapshots` 3,842건은 공용 상품 1,542개에 모두 연결했고 현재 분류 이력 1,195건을 생성했다.
- 앱 공개 RPC는 `fitmatch_resolve_product`, `fitmatch_register_closet_item`, `fitmatch_set_closet_classification_override`, `fitmatch_clear_closet_classification_override`, `fitmatch_begin_comparison`, `fitmatch_complete_comparison`이다. 신규/변경 상품은 공개 클라이언트가 공용 catalog를 직접 쓰지 않고 `product_intake_requests`에 넣으며, 검증된 batch/Edge Function/service role만 공용 상품과 실측을 승격한다.
- `SECURITY DEFINER` RPC는 빈 `search_path`, `auth.uid()` 검증, 소유권 검증, anon 실행권 제거를 적용했다. 공용 상품 내부 schema는 RLS+무정책 기본 거부이며 authenticated 직접 쓰기를 차단했다. FK 인덱스 advisor 지적은 `086`에서 해소했다.
- 최종 Supabase advisor의 신규 runtime 관련 보안 표시는 private table의 의도적 `RLS+무정책` INFO와, 위 6개 인증 사용자용 `SECURITY DEFINER` RPC WARN뿐이다. 둘 다 설계 의도이며 공개 권한 검증을 통과했다. 프로젝트 설정에는 별도로 leaked-password protection 미활성 WARN이 남아 있어 Auth 출시 점검에서 활성화해야 한다. 새 runtime FK의 미인덱스 지적은 0건이고, 막 생성된 인덱스의 unused INFO는 트래픽 전이므로 삭제 근거가 아니다.
- 정책 버전 `db-runtime-2026-08-18-v1`을 추가하고 비교 허용을 family compatibility뿐 아니라 `required_any_measurements`/최소 충족 개수로 fail-closed 처리했다. Uniqlo/Musinsa 실측 alias와 단면·둘레 변환을 검증했다.
- 명확한 기존 DB 모순 4건을 교정했다. Uniqlo `E482204`, `E489180`은 underwear family, `E488163`, `E488426`은 pants family가 정답이다. DB QA gold도 같은 기준으로 갱신됐으므로 앱 연결 브랜치에서 로컬 JSON fixture와 분류 출력의 4건 parity를 반드시 맞춰야 한다.
- 최종 `fitmatch_qa.validate_product_runtime()`은 `passed=true`, 상품 1,542, snapshot 3,842/연결 3,842, 현재 분류 1,195, duplicate current 0, gold 5,026/5,026(100%), category-family contradiction 0, invalid comparable measurement 0, 공개 definer 권한 누수 0을 반환했다.
- 실제 인증 사용자로 known/unknown resolve, 옷장 등록/override/복원, 비교 시작, idempotent ingest, 동시 upsert 동일 UUID, Uniqlo↔Musinsa canonical 실측 3개 비교를 검증했고 임시 데이터는 모두 제거했다. exact lookup은 약 0.204ms, 최근 상품+현재 분류 조회는 약 2.143ms였다.
- 현재 운영 `product_sizes`와 `product_measurements`는 0건이다. 기존 batch snapshot에 실제 사이즈표 행이 없기 때문이다. 따라서 DB 구조·권한·프로시저는 준비됐지만, 앱에서 DB 비교를 활성화하기 전에 신뢰된 backend/batch가 실제 variant/size/measurement payload를 적재해야 한다.
- 구현 계약과 AS-IS/TO-BE, RPC 입출력, Swift 연동 순서, 실패 상태는 `Docs/FitMatchDBRuntimeContract-20260818.md`에 정리했다. 앱 출시용 현재 로컬 엔진은 이번 작업에서 변경하지 않았다. DB 전환은 새 브랜치에서 feature flag/dual-run parity로 단계적으로 수행한다.
- 관련 파일: `supabase/migrations/082_product_runtime_foundation.sql`부터 `086_product_runtime_fk_indexes.sql`, 안전 rollback `supabase/sql/087_product_runtime_safe_rollback.sql`, 운영 검증 쿼리 `supabase/sql/088_product_runtime_validation_queries.sql`.

## 55. 2026-08-18 신규 상품 자동 분류·비교 후보 정책 보완

- 사용자의 `보완해` 지시에 따라 앱 코드는 수정하지 않고 Supabase DB 구조/프로시저만 보완했다. 운영 프로젝트 `hnkplvyegonlhumlejst`에 `trusted_product_auto_classification_v2`, `comparison_candidate_policy_parity_v2`, `validate_product_runtime_v2`, `fix_product_exclusion_resolution_v3`, `backfill_product_runtime_v2_classifications` 5개 migration을 적용했다. 로컬 재현 파일은 `supabase/migrations/089`~`093`이다.
- 신규/변경 상품 자동 분류는 공개 앱 payload와 신뢰된 backend payload를 분리했다. `public.fitmatch_resolve_product`는 API가 보낸 audience/category codes까지 기존 공용 상품과 비교하지만 불일치 시 intake만 만들고 공용 사실을 쓰지 않는다. 검증된 batch/Edge Function만 `fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)`를 호출해 상품·분류 이력을 승격한다.
- 5,026 Gold에서 `source+normalized path` 및 `source+path+product-name structural signature`별로 최소 2건 이상, 사용자 확인 0건, 최종 tuple 1종인 경우만 immutable profile로 만들었다. 신상품 ID로 바꾼 재생 기준 자동 확정 2,536건, 2,536/2,536 일치, 자동 오답 0이다. 나머지는 old runtime suggestion으로 확정하지 않고 `review_required`다.
- 최신 snapshot에서 동일 상품이 `excluded_review`로 검증된 경우와 동일 path의 2개 이상 상품이 전부 제외인 경우를 `not_comparable`로 승격한다. 유니클로 스카프 5개 같은 의도적 제외가 mapping row 부재 때문에 단순 gap으로 보이지 않게 했다. 자동 제외 path는 40개다.
- 기존 공용 상품 1,542개 중 current 분류가 없던 347개를 새 정책으로 backfill했다. 최종 current는 1,542/1,542이고 confirmed 1,114, not_comparable 184, review_required 244, current 중복 0이다. review 244는 제거 대상 데이터가 아니라 자동 확정 근거가 부족해 의도적으로 막힌 상태다.
- 비교 정책에 major category, gender/age, family, detail, sleeve/pants length, outer body length, canonical measurement overlap을 모두 포함했다. `fitmatch_find_reference_candidates(uuid)`는 `automatic`, `manual_selection`, `measurements_required`, `no_compatible_garment`를 구분한다. 반팔↔긴팔 상의는 자동 차단 후 소매길이 제외 manual extended, 긴바지↔반바지는 총장·밑단 제외 manual extended, sweatshirt↔hoodie는 direct, 상의↔하의는 항상 차단한다.
- 실제 인증 사용자 컨텍스트의 rollback 통합 검사에서 유니클로 `E422992` 반팔 T를 옷장 기준으로, `E492123` 긴팔 셔츠를 대상으로 넣었을 때 후보 상태 `manual_selection`, 자동 begin `blocked`, manual begin `pending`, 공통 실측 3개를 확인했다. `E447780` 하의 대상은 `no_compatible_garment`였다. 생성한 size/measurement/closet/run은 rollback 후 모두 0건임을 확인했다.
- trusted promotion rollback 검사에서 신규 긴팔 셔츠는 `verified_path_profile`로 confirmed, 기존 `E492123`의 category code 일치는 current 재사용, 다른 code는 `catalog_state=changed`+intake로 분리됐다. 공용 데이터 오염 없이 모두 rollback됐다.
- 최종 `fitmatch_qa.validate_product_runtime_v3()`은 `passed=true`, Gold 5,026/5,026, 신상품 자동 profile mismatch 0, category-family contradiction 0, invalid comparable measurement 0, cross-major blocked true, manual extended supported true, anon candidate RPC execute false를 반환한다.
- Supabase advisor의 새 항목은 비공개 profile 세 테이블의 `RLS enabled/no policy` INFO와 인증 사용자용 `fitmatch_find_reference_candidates` SECURITY DEFINER WARN이다. 전자는 deny-by-default, 후자는 `auth.uid()`와 user ownership filter를 가진 의도된 공개 RPC다. 신규 migration 관련 performance advisor 항목은 없었다.
- 계약서는 `Docs/FitMatchDBRuntimeContract-20260818.md`에 v2 흐름/상태/수량을 반영했고, `supabase/sql/087_product_runtime_safe_rollback.sql`과 `088_product_runtime_validation_queries.sql`도 신규 RPC/validator/profile 검증을 포함하도록 갱신했다.
- 남은 핵심은 운영 size/measurement 적재다. 현재 이 두 테이블은 0건이므로 앱 연결 브랜치에서 retailer fetch 결과를 trusted ingest로 적재하기 전에는 실제 DB 비교 점수 경로를 켜면 안 된다. 또한 신상품 자동 분류는 검증 가능한 2,536 profile 범위만 자동이며 모든 미래 상품 100% 자동 확정을 보장하지 않는다. 미지원/충돌은 review로 막는 것이 현재의 의도된 안전 동작이다.

## 56. 2026-08-18 유니클로·무신사 로컬 증분 배치 실행

- 앱 코드와 Supabase 운영 DB는 변경하지 않고 로컬 배치만 실행했다. 유니클로는 `python3 scripts/run-uniqlo-incremental-catalog.py --run-id 20260818-152230`, 무신사는 `python3 scripts/run-musinsa-incremental-catalog.py --run-id 20260818-152745`로 실행했다.
- 유니클로 최초 실행 `20260818-152132`는 샌드박스 네트워크 연속 실패로 수집 시작 전에 종료됐다. 상태 원장은 갱신되지 않았고 실패 증거로 `Docs/TestEvidence/UniqloCatalogIncremental/runs/20260818-152132/discovery/checkpoint.json`만 남겼다. 외부 네트워크가 허용된 재실행은 정상 완료됐다.
- 유니클로 재실행은 카테고리 200페이지, 요청 248회, 고유 상품 1,223개를 관측했다. category hydration 경로 불일치 47회는 의미 재요청으로 모두 복구됐고 `category_response_failures=0`, `discovery_complete=true`다. 요청 상태는 HTTP 200 247회, 404 1회였으며 최종 탐색 완전성에는 영향을 주지 않았다.
- 유니클로 상태 원장은 1,159개에서 1,235개로 늘었다. 신규/재시도 후보 77개 중 76개는 상품명·경로·상세·공식 사이즈표를 모두 확보했고, 공식 사이즈 행 471개와 실측 항목 2,219개가 수집됐다. MEN 22, WOMEN 40, KIDS 8, BABY 6이며 상품 ID 중복과 빈 상품명·빈 경로는 0개다.
- 유니클로 미완료 1개 `E479751`은 신규 상품이 아니라 2026-08-15부터 반복 노출되지만 상세를 가져올 수 없는 기존 `known_unavailable` 항목이다. 이번에도 `pending_retry`로 유지했다. 이번 탐색에서 보이지 않은 기존 상품 12개는 `missing_product_ids.csv`에만 기록했으며 삭제나 판매 종료 처리는 하지 않았다.
- 무신사 실행은 카테고리 감시 페이지 5개, 요청 5회, 고유 상품 230개를 관측했다. HTTP 200 5/5, 신규 48개, 상품 상세 저장 48개, 재시도 0개이며 상태 원장은 384개에서 432개로 늘었다. 상품 ID 중복과 빈 상품명·빈 카테고리 경로는 0개다.
- 무신사 신규 48개 중 공식 실측 행이 있는 상품은 34개이고 총 121개 사이즈 행을 확보했다. 실측 행이 0개인 14개는 모두 나일론/코치 재킷 계열 상품이며 상세 정보는 정상 저장됐지만 현재 공식 actual-size 응답에 실측이 없다. 이 14개는 상품·카테고리 증거로는 쓸 수 있지만 DB 실측 비교 데이터로 승격하면 안 된다.
- 무신사 `missing_from_current_catalog=202`는 판매 종료 수가 아니다. 현재 증분 수집기가 무신사 전체 약 62만 상품을 탐색하지 않고 제한된 5개 감시 페이지만 확인하므로, 기존 원장에 있으나 이번 표본에 없던 수량일 뿐이다. 삭제·비활성 판단에 사용하지 않는다.
- 최종 산출물은 `Docs/TestEvidence/UniqloCatalogIncremental/runs/20260818-152230/`과 `Docs/TestEvidence/MusinsaCatalogIncremental/runs/20260818-152745/`에 있다. 핵심 인수 파일은 각 폴더의 `summary.json`, `discovered_products.csv`, `new_product_ids.csv`, `new_product_inputs.json`, `new_products.csv`, `missing_product_ids.csv`이며 무신사는 `pending_retry.csv`, 유니클로는 `new_products/uniqlo_size_evidence.json`을 추가 확인한다.
- 이번 단계는 수집과 로컬 상태 원장 갱신까지만 완료했다. 신규 124개(유니클로 76, 무신사 48)를 Supabase `products`/`product_sizes`/`product_measurements`에 적재하거나 canonical 분류 프로시저를 실행하지 않았다. 운영 DB 반영은 별도 승인 후 trusted ingest 경로에서 수행해야 한다.

## 57. 2026-08-18 retailer 배치의 Supabase 적재·자동 분류 연결

- 바탕화면 사용자 진입점을 유니클로 command 1개, 무신사 command 1개로 유지했고 결과 폴더도 쇼핑몰별 1개씩 유지했다. 관련 사용자 항목은 총 4개다. 내부 연구/테스트 helper는 삭제하지 않았다.
- 두 증분 배치가 Supabase에서 현재 관측 ID의 batch marker/current 분류 존재 여부를 먼저 확인한다. 로컬 신규와 DB 미적재를 합쳐 상세·공식 사이즈를 수집하고, 상품별 DB 적재가 성공한 경우에만 로컬 원장을 완료 처리한다. DB 미완료가 하나라도 있으면 종료 코드 3과 재시도 ID를 남긴다.
- 공통 Python adapter `scripts/catalog_batch_common.py`를 추가했다. 유니클로 official sizeChart와 무신사 actual-size를 공용 product/variant/size/measurement payload로 변환하며 key는 환경/Keychain에서만 읽는다.
- 운영 DB migration `batch_product_ingest_api_v1`, `batch_measurement_scope_and_uniqlo_aliases_v1`, `grant_batch_taxonomy_read_v1`을 적용했다. public batch RPC 두 개는 `service_role`만 실행 가능하고 anon/authenticated는 모두 false다.
- `fitmatch_batch_ingest_product`는 한 트랜잭션에서 trusted product promotion/canonical classification 후 실측 적재를 수행한다. 분류 category를 measurement scope로 주입해 무신사 `허리단면`의 tops/bottoms 의미를 구분한다. 유니클로 현재 official sizeChart raw label 12개를 canonical alias로 보강했고 등 중심~소매는 기준이 달라 비교 불가로 보수 처리했다.
- service-role rollback 통합 테스트에서 신규 유니클로 반팔 T가 `tops/short_sleeve`, `가슴너비 55cm`가 `chest_width=55`, comparable=true로 기록됐다. rollback 후 테스트 상품 0건, 운영 product 1,542/size 0/measurement 0은 유지됐다.
- 최근 로컬 결과 124건을 adapter로 변환한 결과 유니클로 76상품/471사이즈/2,216 numeric 실측, 무신사 48상품/121사이즈/398실측, 빈 상품명·경로 0이다. 아직 Keychain에 secret key가 없어 실제 124건 backfill 배치는 실행하지 않았다. 최초 command 실행 때 키를 한 번 입력하면 현재 관측 범위를 backfill하고 이후 batch version 기준 증분 처리한다.
- 유니클로 `E479751`처럼 base URL이 `/00` 404로 잘못 redirect되는 경우를 위해 상세 수집기가 base → `/01` → `/00` 후보를 순서대로 재시도하도록 보완했다.
- 앱/Swift 연결 로직은 이번 작업에서 수정하지 않았다. Supabase advisor에 새 batch 관련 보안/성능 경고는 없고 기존 private RLS INFO, 인증 사용자용 definer WARN, leaked-password protection WARN만 유지된다.

## 58. 2026-08-19 인증 사용자 옷장 CRUD 계약 적용

- 운영 Supabase 프로젝트 `hnkplvyegonlhumlejst`에 `authenticated_closet_crud_contract_v1`을 적용했다. 로컬 재현 파일은 `supabase/migrations/099_authenticated_closet_crud_contract.sql`이다.
- `closet_items`에 앱 UUID 기반 멱등 키 `client_item_id`, fit memo/preference/satisfaction, 원본 실측 record, client snapshot/timestamp, `sync_revision`을 추가했다. `(user_id, client_item_id)` 중복과 동일 사용자·성별·category/detail 내 복수 대표 옷을 DB constraint/index로 막는다.
- 앱 공개 RPC는 `fitmatch_upsert_closet_item`, `fitmatch_list_closet_items`, `fitmatch_set_closet_reference`, `fitmatch_delete_closet_item` 네 개다. 모든 함수는 authenticated 전용, `auth.uid()`/소유권 검증, 빈 `search_path`를 적용했다. authenticated의 `closet_items` 직접 DML 권한은 회수했다.
- catalog-linked 옷장은 current canonical classification을 snapshot으로 사용한다. 수동/unlinked 옷장은 안전하게 번역 가능한 broad family만 garment type으로 연결하며 지원하지 못하는 조합은 `review_required`로 저장해 자동 비교를 fail-closed한다.
- Swift의 `FitMatchSupabaseDomainClient`에 네 RPC용 DTO와 호출 API를 추가했다. 기존 `MyClosetView`와 SwiftData CRUD는 사용자의 별도 앱 연결 지시 전까지 변경하지 않았다.
- unauthenticated list 호출은 `authentication_required`를 반환했고 새 RPC 네 개의 anon execute=false/authenticated execute=true를 확인했다. generic iOS Simulator Debug build가 성공했고 `FitMatchSupabaseProductResolverTests` 7/7이 통과했다. 새 옷장 응답의 canonical snapshot, null 축, 원본 실측 record 디코딩도 회귀로 고정했다.
- 다음 단계는 실제 Apple 로그인 세션으로 upsert→list→reference 전환→soft delete를 통합 검증한 뒤, SwiftData를 캐시/outbox로 두는 화면 sync 계층을 연결하는 것이다.

## 59. 2026-08-19 SwiftData 옷장과 Supabase 동기화 연결

- 운영 Supabase에 `closet_sync_hydration_contract_v1`을 적용했다. 로컬 재현 파일은 `supabase/migrations/100_closet_sync_hydration_contract.sql`이다. `fitmatch_list_closet_items`가 재설치 복원에 필요한 `external_product_id`, `product_audience`, `source_category_codes`를 사용자 소유 옷장 행을 통해 반환한다. anon execute=false/authenticated execute=true와 함수 본문을 재검증했다.
- `FitMatchClosetSyncCoordinator`를 추가하고 `ContentView`의 로그인 세션·SwiftData 변경 감지에 연결했다. `UserFit.id`를 서버 `client_item_id`로 재사용해 SwiftData schema 변경 없이 멱등 upsert한다. 기존 화면은 로컬 SwiftData를 계속 읽고 서버는 장기 원본 역할을 한다.
- 서버 최신 항목은 로컬에 적용하고, 로컬 최신/신규 항목은 catalog resolve 후 옷장 RPC로 저장한다. catalog가 없거나 안전한 family를 만들 수 없는 항목은 공용 상품을 오염시키지 않고 unlinked/manual snapshot으로 저장한다. 부분 실패는 `pendingRetry`로 남겨 다음 pass에서 재시도한다.
- `MyClosetView`와 `ClosetItemDetailView`의 로컬 삭제 뒤 사용자별 tombstone을 기록하고 서버 soft-delete가 성공할 때 제거하도록 연결했다. 계정이 바뀌면 이전 계정의 옷장·비교 기록을 지운 뒤 새 계정 서버 데이터를 복원하며, 공용 상품 캐시는 유지한다.
- 서버 단독 유니클로 옷장 행을 빈 SwiftData에 복원하는 회귀 테스트를 추가했다. stable item UUID, 공용 상품/사이즈 FK, `E492123`, 원본 category code, FitMatch tops/shirt, 실측값 복원을 검증했다.
- generic iOS Simulator Debug 전체 build가 통과했고 Supabase DTO/옷장 동기화 targeted test는 8/8 통과했다. 결과 bundle은 `/tmp/FitMatchClosetSyncDerivedData/Logs/Test/Test-FitMatch-2026.08.19_09-39-19-+0900.xcresult`다.
- 남은 작업은 (1) 현재 추천 화면에 reference-candidate/begin/complete comparison RPC를 연결하면서 수동 측정 옷의 overlap 판정을 보완하고, (2) 실제 Apple 로그인 계정으로 저장·재조회·삭제·계정 전환·오프라인 재시도를 실기기 검증하는 것이다.

## 60. 2026-08-19 로컬 비교 결과와 Supabase 비교 이력 동기화 연결

- 운영 Supabase에 `comparison_sync_contract_v1`, `manual_closet_comparison_fallback`을 순서대로 적용했다. 로컬 재현 파일은 `supabase/migrations/101_comparison_sync_contract.sql`, `102_manual_closet_comparison_fallback.sql`이다.
- `comparison_runs.client_history_id`와 `(user_id, client_history_id)` unique partial index를 추가했다. 앱의 `RecommendationHistory.id`를 멱등 키로 보내므로 네트워크 재시도나 앱 재실행이 같은 비교 run을 중복 생성하지 않는다.
- 수동 옷장은 catalog `product_size_id`가 없어도 정규화된 `measurement_records` 또는 숫자 `measurements`에서 canonical 실측 겹침을 계산한다. 수동 옷의 유효 분류는 사용자 override → canonical snapshot → `app_category/app_detail_category` 순으로 읽어 기존 수동 옷장도 후보/비교 시작에 사용할 수 있게 했다.
- `FitMatchComparisonSyncCoordinator`를 추가하고 로그인 완료 및 옷장 동기화 성공 뒤 실행하도록 `ContentView`에 연결했다. 기존 로컬 비교 엔진과 화면 결과는 그대로 유지하고, DB에는 대상 상품 resolve/runtime UUID, reference closet UUID, 추천 size UUID, 점수·신뢰도·사용/제외 실측 근거를 저장한다.
- 대상 상품은 retailer `source + external_product_id + 이름/카테고리 증거`로 다시 확인하며 current+confirmed runtime만 사용한다. 추천 로컬 size가 색상·표기까지 고려해 DB size 하나로 확정되지 않으면 저장을 재시도 상태로 남긴다.
- 서버 안전 정책이 로컬 결과를 차단하면 결과를 억지로 완료하지 않고 `blocked` run과 parity warning으로 남긴다. 수동/지원 외 쇼핑몰처럼 DB 대상 상품 UUID를 만들 수 없는 비교는 로컬 UX를 유지하되 서버 비교 이력에는 넣지 않는다.
- 운영 rollback probe에서 수동 반팔 상의가 유니클로 반팔 대상의 automatic 후보가 되고 공통 실측 3개로 평가되는 것을 확인했다. 같은 `client_history_id`로 비교 시작을 두 번 호출했을 때 동일 run UUID가 반환됐고, 테스트 run/closet row는 모두 삭제했다.
- generic iOS Simulator Debug build가 통과했다. 인증 nonce, 옷장 hydration, 상품/RPC DTO, 비교 성공·차단 동기화 targeted test는 12/12 통과했다. 결과 bundle은 `/Users/jinyoung/Library/Developer/Xcode/DerivedData/FitMatch-gykzeotdbwpwwsdieiheccopizfu/Logs/Test/Test-FitMatch-2026.08.19_10-11-57-+0900.xcresult`다.
- 남은 단계는 실제 Apple 로그인 계정으로 옷장 upsert/list/reference/delete, 비교 begin/complete, 재로그인·계정 전환·오프라인 재시도를 실기기에서 검증하는 것이다. 서버 comparison 이력을 재설치 후 로컬 `RecommendationHistory`로 복원하는 read/hydration API는 아직 구현하지 않았다.

## 61. 다음 세션 즉시 인수 체크리스트

- 현재 로컬 브랜치는 `connectDB`다. 2026-08-19 인증·옷장·비교 연동 변경은 아직 커밋하지 않았으므로 현재 dirty worktree를 보존하고 사용자가 요청하기 전 commit/push/merge하지 않는다.
- 운영 Supabase 적용 완료 범위는 migration `097`~`102`다. 마지막 두 운영 migration 이름은 `comparison_sync_contract_v1`, `manual_closet_comparison_fallback`이며 migration history에서 확인됐다.
- 앱에는 publishable key만 사용한다. secret/service-role key는 배치의 macOS Keychain 외에는 넣지 않으며 iOS bundle·Info.plist·소스에 절대 추가하지 않는다.
- 다음 작업의 첫 순서는 실제 iPhone에서 Apple 로그인 성공 확인이다. 그 뒤 수동 옷 1개 등록 → 앱 재실행 후 유지 → 대표 옷 전환 → 유니클로/무신사 비교 1건씩 생성 → Supabase `closet_items`, `comparison_runs`, `comparison_results`, `comparison_measurement_results` 저장 확인 → 삭제/로그아웃/재로그인/다른 계정 전환 → 오프라인 생성 후 온라인 재시도를 검증한다.
- 통과 기준은 사용자 간 row 혼합 0, 중복 `client_history_id` 0, 삭제 항목 재등장 0, 서버 차단 비교의 완료 결과 0, 네트워크 실패 시 로컬 UX 손실 0이다. 실패하면 UI를 먼저 바꾸지 말고 coordinator 상태와 RPC 응답을 추적한다.
- 현재 자동화 증거는 Debug build 성공과 targeted test 12/12다. 실계정·실기기 통합 검증은 아직 수행하지 않았으므로 운영 완료라고 표현하지 않는다.
- 재설치 후 옷장은 복원되지만 서버 비교 기록을 로컬 `RecommendationHistory` 화면으로 복원하는 read RPC/coordinator는 미구현이다. 이는 출시 필수 여부를 사용자와 결정한 뒤 별도 단계로 구현한다.
- Supabase advisor의 비교 RPC `SECURITY DEFINER` WARN은 authenticated 진입을 의도한 것이다. 함수 내부 `auth.uid()`·소유권 검사, 빈 `search_path`, anon execute=false를 유지한다. 막 생성된 인덱스의 unused INFO는 삭제 근거로 사용하지 않는다.
- 보호 대상 `FitMatch/Components/TabBarScrollVisibilityModifier.swift`와 `fitMatchHidesTabBarWhenScrolling` 호출부는 변경하지 않았다. 다음 수정 후에도 반드시 diff 0을 확인한다.

## 62. Remaining issues / Next To Do

### Remaining issues

- 현재 3단계 DB 연결 목표의 필수 미완료는 실제 Apple 계정·실기기 end-to-end 검증 하나다. 자동 테스트가 통과했어도 실제 Auth token, 네트워크, 앱 lifecycle까지 검증하기 전에는 운영 완료로 판정하지 않는다.
- 재설치 후 옷장 복원은 구현됐지만 서버의 과거 비교 결과를 로컬 `RecommendationHistory` 화면으로 복원하는 기능은 미구현이다. 현재 출시 필수 blocker가 아니라 후속 기능 후보다.

### Next To Do

1. 실제 iPhone에서 Apple 로그인하고 Supabase Auth 사용자 생성·세션 유지 여부를 확인한다.
2. 수동 옷 1개와 쇼핑몰 연동 옷 1개를 등록하고 `closet_items` 저장·앱 재실행 복원을 확인한다.
3. 대표 옷 변경과 삭제를 실행해 단일 대표 constraint, soft delete, 삭제 항목 미복원을 확인한다.
4. 유니클로·무신사 비교를 각 1건 생성해 `comparison_runs` → `comparison_results` → `comparison_measurement_results` 저장을 확인한다.
5. 동일 비교 재시도로 run 중복 0, 서버 차단 비교의 완료 result 0을 확인한다.
6. 로그아웃·동일 계정 재로그인·다른 계정 전환으로 사용자 데이터 혼합 0을 확인한다.
7. 오프라인에서 옷장/비교를 만든 뒤 온라인 복귀하여 outbox 재시도와 로컬 UX 보존을 확인한다.
8. 위 검증이 모두 통과하면 현재 3단계를 완료 처리하고, 비교기록 hydration을 출시 전 포함할지 후속 버전으로 미룰지 결정한다.

## 63. 2026-08-19 상품 원본 관측·정규화 백엔드 파이프라인

- 운영 Supabase에 migration `product_observation_pipeline`을 적용했다. 로컬 재현 파일은 `supabase/migrations/103_product_observation_pipeline.sql`이며 마지막 운영 migration으로 확인됐다.
- `product_observations`는 동일 payload를 fingerprint로 중복 제거하면서 최초/최종 관측 시각과 횟수를 보존한다. payload가 바뀌면 새 immutable 이력으로 남는다. 제출 사용자와 원본 실측 행은 각각 `product_observation_submissions`, `product_observation_measurements`에 분리했다.
- 인증 사용자는 검증 RPC로 원본만 제출할 수 있고 private 관측 테이블을 직접 읽거나 공용 상품 current row를 승격할 수 없다. backend 전용 처리 RPC만 분류 후 category scope를 사용해 원본 실측을 canonical 실측으로 정규화한다.
- JWT 검증이 켜진 Edge Function `product-observation` version 1을 배포했고 ACTIVE 상태를 확인했다. iOS에는 service-role key를 넣지 않고 사용자 세션으로 Edge Function만 호출한다.
- `ShoppingProductViewModel`의 기존 로컬 분류·비교 결과를 바꾸지 않고 DB shadow 작업에서 파서가 얻은 상품/사이즈/`measurementRecords`를 먼저 제출하도록 연결했다. 관측 저장 실패는 로컬 사용자 흐름과 기존 DB 조회를 차단하지 않는다.
- 운영 rollback probe에서 동일 payload 2회 제출은 observation UUID 1개/observation_count 2/raw row 2로 확인했다. 실제 등록상품 `E492123` probe는 raw 2행을 `chest_width`, `back_length` canonical 2행으로 변환했고 confirmed 분류를 유지했다. 두 probe의 QA 상품·관측은 rollback되어 운영 잔존 0이다.
- generic iOS Simulator Debug build와 전체 `build-for-testing`이 성공했다. Supabase security advisor의 신규 WARN은 `fitmatch_submit_product_observation` SECURITY DEFINER authenticated 진입점 1개이며, `auth.uid()` 필수·입력 상한·private table no-grant·빈 search_path를 둔 의도된 경계다. 신규 unused-index INFO는 생성 직후라 삭제 근거가 아니다.
- 아직 실기기 Apple 로그인 세션으로 Edge Function의 실제 HTTP 호출을 끝까지 실행하지 않았다. 또한 현재 payload는 파서가 추출한 모든 실측 원본을 보존하지만 쇼핑몰 HTTP 응답 body 전체를 보존하는 구조는 아니다.

## 64. Remaining issues / Next To Do

### Remaining issues

- 필수: 실제 iPhone + Apple 로그인 계정으로 유니클로/무신사 링크 각 1개를 분석해 Edge Function 호출, observation 생성, canonical measurement 승격을 end-to-end 확인한다.
- 필수: DB canonical runtime을 실제 추천 계산 입력으로 사용하고 기존 Swift 엔진 결과와 parity를 자동 검증하는 전환은 아직 남았다. 현재는 로컬 결과 유지 + DB 관측/정규화/shadow 단계다.
- 후속 후보: 서버 비교 기록을 앱 재설치 후 `RecommendationHistory`로 복원하는 hydration API는 미구현이다.
- 선택 사항: 쇼핑몰 HTTP 원문 body 전체 보관은 용량·개인정보·약관을 먼저 검토해야 한다. 비교에 필요한 파서 추출 실측 원본은 이번 단계에서 이미 보존한다.

### Next To Do

1. 실기기에서 Apple 로그인 후 유니클로 `E492123`과 무신사 실측 보유 상품 1개를 분석한다.
2. `product_observations.processing_status=promoted`, 원본 실측 행 수, `product_measurements.is_comparable` 및 canonical code를 확인한다.
3. 옷장 CRUD·대표 옷·비교 begin/complete·로그아웃/계정 전환·오프라인 재시도를 기존 체크리스트대로 검증한다.
4. DB runtime DTO를 추천 입력 adapter에 연결하되 로컬 계산도 동시에 실행해 category/detail/family/length/실측/추천 size/score 전 필드 parity를 저장한다.
5. 충분한 parity 표본에서 차이가 0이고 fail-closed가 유지될 때만 DB/backend 입력을 기본 경로로 승격한다.

## 65. 2026-08-20 유니클로 E485454 분류·내 옷장 썸네일 보완

- 상품 `E485454`(`바이컬러T`)의 공식 `__PRELOADED_STATE__`에는 `Special Collaborations > UNIQLO and JW ANDERSON > Cut & Sewn`과 category ID `107543/107552/107621`이 있었지만, 기존 iOS 파서는 더 짧은 JSON-LD breadcrumb를 먼저 선택해 leaf와 ID를 버렸다. 그 결과 로컬은 `기타/기타`, DB는 검수 정답 fingerprint 불일치로 `review_required`가 됐다.
- `UniqloProductMetadataParser`가 embedded product breadcrumb를 읽고, JSON-LD/HTML/product-group 후보 중 가장 구체적인 공식 경로를 사용하도록 수정했다. category ID도 `ProductMetadata.categoryDepth1Code...4Code`에 전달한다. E485454는 `상의/반팔/tshirt/short_sleeve`로 판정된다.
- 운영 Supabase에 `preserve_specific_uniqlo_category_evidence` migration을 적용했다. `runtime_upsert_product`는 category ID가 호환되는 기존 상세 경로를 새 parent-only 관측으로 덮어쓰지 않으며 fingerprint도 실제 보존 경로로 계산한다. 로컬 재현 파일은 `supabase/migrations/104_preserve_specific_uniqlo_category_evidence.sql`이다.
- 기존 검수 결정을 재사용해 운영 E485454 current를 `confirmed`, `tops/short_sleeve/tshirt/short_sleeve`, `canonical_product_decision`, 사용자 확인 불필요로 복구했다. 짧은 경로 재입력 rollback probe에서도 `Cut & Sewn` 경로와 fingerprint가 유지됐다.
- 유니클로 이미지 CDN과 E485454 색상 65 이미지가 HTTP 200 JPEG임을 확인했다. 앱의 썸네일 문제는 CDN 부재가 아니라 (1) 같은 상품/사이즈의 과거 SwiftData 상품을 재사용할 때 새 이미지 URL을 버릴 수 있고, (2) 최초 다운로드 실패 후 같은 화면에서 재시도하지 않는 두 경로였다.
- `Product.refreshExternalPresentation`을 추가하고 추천 기록 병합 및 비교상품→옷장 등록 시 새 retailer 이미지/URL을 기존 상품에 반영한다. 빈 후속 값은 정상 이미지를 지우지 않는다. `ProductThumbnailImageLoader`는 이미지 요청 헤더와 1회 짧은 재시도를 사용하고 화면 재진입 시 실패 URL도 다시 시도할 수 있게 했다.
- iPhone 17 Pro Simulator에서 신규 회귀 테스트 2개(`embedded breadcrumb/category ID/E485454 image URL`, `persisted product thumbnail refresh`)가 2/2 통과했다. 기존 선택 색상 이미지 보존 테스트도 1/1 통과했다. Supabase `validate_product_runtime_v3()`은 `passed=true`, Gold 5,026/5,026, 자동 profile mismatch 0이다.
- Supabase advisor에는 이번 migration으로 생긴 신규 치명/성능 경고가 없다. 기존 authenticated SECURITY DEFINER RPC WARN과 leaked-password protection WARN, 생성 직후/미사용 index INFO는 유지된다.
- 보호 대상 `FitMatch/Components/TabBarScrollVisibilityModifier.swift`와 관련 호출부는 변경하지 않았다.

## 66. Remaining issues / Next To Do

### Remaining issues

- 이번 증상의 코드·DB 원인은 수정됐고 자동 회귀 검사는 통과했다. 다만 실제 iPhone 네트워크에서 `E485454` 링크 등록 전 미리보기와 저장 후 내 옷장 썸네일까지 보는 수동 확인은 남아 있다.
- 기존 전체 연결 작업의 필수 잔여 항목인 Apple 로그인 실기기 E2E와 DB canonical runtime↔Swift 추천 parity 전환은 그대로 남아 있다.

### Next To Do

1. 실제 iPhone에서 E485454 색상 65 링크를 입력해 불러오기 화면 썸네일, 저장 확인 화면, 내 옷장 목록/상세 썸네일을 확인한다.
2. 같은 상품을 먼저 비교 기록에 저장한 뒤 내 옷장에 추가해 과거 SwiftData 상품 재사용 경로에서도 이미지가 유지되는지 확인한다.
3. 이후 기존 체크리스트대로 Apple 로그인, observation 승격, 옷장/비교 동기화, DB↔Swift parity를 진행한다.

## 67. 2026-08-20 회원 탈퇴 완료 및 현재 인수 상태

> 이 절과 아래 68절이 현재 권위 상태다. 61~66절의 체크리스트는 작업 당시 이력이며, 완료 여부가 충돌하면 68절을 따른다.

- `connectDB` 브랜치에 로그인 사용자용 회원 탈퇴를 구현했다. My 화면에서 2차 확인 후 인증된 `delete-account` Edge Function을 호출하고, 성공하면 Supabase 계정과 사용자 소유 서버 row, 로컬 `UserFit`·`RecommendationHistory`·동기화 캐시를 제거한다. 공용 쇼핑몰 상품 카탈로그는 보존한다.
- 운영 프로젝트 `hnkplvyegonlhumlejst`에 `delete-account` version 1을 배포했다. 상태는 `ACTIVE`, `verify_jwt=true`, 함수 ID는 `8ce51490-2669-46ca-b4aa-44a9ec538bce`이며 인증 헤더 없는 호출은 HTTP 401로 차단된다.
- 앱은 publishable key로 사용자 세션만 전달하고, 계정 hard delete에 필요한 service-role key는 Edge Function 환경에서만 사용한다. iOS 소스와 bundle에는 secret/service-role key를 넣지 않았다.
- `auth.users` 참조 FK 19개를 재확인했다. 사용자 소유 FK 18개는 `ON DELETE CASCADE`, 분류 감사의 `product_classification_history.reviewed_by`만 `ON DELETE SET NULL`이고 Storage bucket은 0개다. 현재 DB에는 사용자 hard delete를 막는 참조가 없다.
- `FitMatchAuthSessionStoreTests`와 `FitMatchClosetSyncCoordinatorTests`는 최종 6/6 통과했다. 결과 번들은 `/tmp/FitMatchAccountDeletion-20260820-3.xcresult`다. 실제 Apple 계정 destructive E2E는 아직 실행하지 않았다.
- 카카오·네이버는 아직 로그인 버튼이나 SDK를 추가하지 않았다. 추후 동일 Supabase user에 identity를 명시적으로 연결하고, FitMatch 계정 삭제는 현재 provider-neutral 삭제 함수를 재사용한다. 동일 이메일만으로 자동 계정 병합하지 않는다.
- Apple provider token 자동 revoke는 아직 미구현이다. 현재 로그인 경로가 authorization code/refresh token을 서버에 보존하지 않기 때문이다. 앱에는 Apple 설정에서 FitMatch 연결을 직접 제거하는 안내를 넣었지만, 로그인 포함 버전을 App Store에 제출하기 전에는 자동 revoke 구현 또는 심사 정책상 허용 가능한 최종 방식을 다시 확정해야 한다.
- 앱 내 개인정보처리방침과 `Docs/AppStorePrivacyPolicyDraft-20260806.md`는 Supabase 저장·동기화·탈퇴 기준으로 갱신했다. 공개 HTTPS 문서 게시와 App Store Connect App Privacy 답변 갱신은 남아 있다.

## 68. 현재 Remaining issues / Next To Do 체크리스트

### 완료

- [x] Apple 로그인용 Supabase 세션 관리와 기존 로그인 화면 연결
- [x] SwiftData 옷장 ↔ Supabase `closet_items` 동기화 계약 및 coordinator 구현
- [x] 로컬 비교 결과 → Supabase 비교 run/result/measurement 결과 저장 구현
- [x] 상품 원본 실측 보존 → canonical 실측 정규화 backend 경계 구현
- [x] 인증 사용자 회원 탈퇴 Edge Function, 앱 UI, 로컬 사용자 데이터 정리 구현
- [x] 회원 탈퇴 DB FK 삭제 정책, 무인증 차단, targeted test 6/6 검증
- [x] 향후 카카오·네이버를 추가해도 재사용 가능한 provider-neutral FitMatch 계정 삭제 경계 마련

### 체크 규칙

- `[x]`는 실행 증거까지 확인된 경우에만 표시한다. 코드가 있다는 이유만으로 실기기 검증을 완료 처리하지 않는다.
- Developer가 실제 기기 흐름을 실행한 뒤 실행 시각과 화면 결과를 전달하면, AI가 같은 시각의 Supabase row와 로그를 대조해 완료 여부를 판정한다.
- access token, refresh token, Supabase secret/service-role key, Apple private key는 채팅이나 저장소에 붙이지 않는다. 외부 Dashboard, Keychain 또는 Edge Function Secret에만 설정한다.

### Developer To Do — 사용자가 직접 수행

#### P0 — 로그인 포함 버전 출시 전에 필수

- [ ] `DEV-P0-01` 실제 iPhone에서 Apple 신규 로그인 → 앱 완전 종료/재실행 → 세션 복구 → 로그아웃 → 동일 계정 재로그인을 실행한다.
- [ ] `DEV-P0-02` 실제 계정으로 수동 옷 1개와 쇼핑몰 상품 1개를 등록하고, 대표 옷 변경·삭제·앱 재실행 복원을 실행한다.
- [ ] `DEV-P0-03` 유니클로와 무신사 비교를 각각 1건 실행한다. AI가 DB를 대조할 수 있도록 실행 시각, 쇼핑몰, 상품 코드, 성공/실패 화면만 전달한다.
- [ ] `DEV-P0-04` 테스트용 Apple 계정으로 회원 탈퇴를 실행한다. 탈퇴 전 필요한 테스트 데이터만 만들고, 실행 시각과 화면 결과를 전달한다.
- [ ] `DEV-P0-05` Apple provider token 자동 revoke에 필요한 Apple Developer 설정과 서버 Secret 사용을 승인·준비한다. private key 자체는 AI에게 전달하지 않는다.
- [ ] `DEV-P0-06` 공개 개인정보처리방침/고객지원 HTTPS URL을 게시하고 URL을 확정한다.
- [ ] `DEV-P0-07` AI가 제공하는 최종 체크표에 따라 App Store Connect App Privacy 답변과 로그인 포함 빌드 설정을 반영한다.

#### P1 — 제품 결정·수동 화면 확인

- [ ] `DEV-P1-01` 실제 iPhone에서 `E485454` 링크의 미리보기·저장·옷장 목록/상세 썸네일과 기존 상품 재사용 경로를 확인한다.
- [ ] `DEV-P1-02` 서버 비교 기록을 재설치 후 앱 기록 화면으로 복원하는 기능을 로그인 포함 첫 버전에 넣을지 후속 버전으로 미룰지 결정한다.
- [ ] `DEV-P1-03` 카카오·네이버 로그인 도입 순서와 계정 연결 UX를 확정하고 각 제공자 개발자 콘솔을 설정한다.

### AI To Do — Codex가 수행

#### P0 — Developer 실기기 테스트 지원 및 출시 차단 해소

- [x] `AI-P0-01` Developer가 그대로 따라 할 수 있는 실기기 E2E 체크표와 Supabase 확인 쿼리를 작성했다. `Docs/ConnectDBPhysicalE2EChecklist-20260820.md`, `supabase/sql/connectdb_e2e_readonly_verification.sql`을 사용한다.
- [ ] `AI-P0-02` `DEV-P0-01~04` 실행 결과를 받아 Auth session, `product_observations`, `closet_items`, 비교 3개 테이블, 계정 삭제 cascade를 DB에서 대조한다.
- [ ] `AI-P0-03` E2E에서 발견된 앱·RPC·동기화 결함을 수정하고 영향 범위 자동 회귀를 실행한다.
- [ ] `AI-P0-04` `DEV-P0-05` 준비 후 Apple authorization code 교환·refresh token 보안 보관·탈퇴 전 provider token revoke를 서버에 구현하고 검증한다.
- [ ] `AI-P0-05` 확정된 개인정보처리방침/고객지원 URL의 앱 연결 상태와 App Store Privacy 답변 체크표를 최종 감사한다.

#### P1 — DB를 추천의 기본 경로로 전환

- [ ] `AI-P1-01` DB runtime DTO와 Swift 추천 입력을 dual-run으로 실행해 category/detail/family/length/canonical measurement/추천 size/score 전 필드 parity를 기록한다.
- [ ] `AI-P1-02` 충분한 실제 표본에서 parity 차이 0, 사용자 간 데이터 혼합 0, false-compatible 0을 확인한 뒤 사용자 승인 후 DB/backend 결과를 source of truth로 승격한다.
- [ ] `AI-P1-03` 오프라인 옷장 등록·비교 후 온라인 복귀 시 outbox 재시도와 로컬 UX 보존을 자동화하고 실기기 결과와 대조한다.
- [ ] `AI-P1-04` `DEV-P1-02` 결정이 출시 포함이면 비교 기록 hydration RPC/coordinator와 회귀 테스트를 구현한다.

#### P2 — 후속 로그인 제공자

- [ ] `AI-P2-01` `DEV-P1-03` 설정 후 카카오·네이버 OAuth/SDK callback과 명시적 Supabase identity link를 구현한다.
- [ ] `AI-P2-02` 각 제공자의 원격 동의·토큰 해제가 필요하면 `delete-account` 실행 전 provider revoke adapter로 연결한다.
- [ ] `AI-P2-03` Apple·카카오·네이버 조합의 계정 연결, 로그아웃, 탈퇴, 재가입, 동일 이메일 충돌 회귀를 추가한다.
- [ ] `AI-P2-04` 이메일/비밀번호 로그인을 도입하는 경우 Supabase leaked-password protection과 관련 Auth 정책을 감사한다. OAuth-only 상태에서는 현재 출시 blocker가 아니다.

## 69. 2026-08-20 실기기 E2E 실행서·읽기 전용 DB 스냅샷

- 복잡했던 실기기 작업을 Apple 로그인, 내 옷장 저장, 유니클로·무신사 비교, 탈퇴 전 DB 기록, 회원 탈퇴의 5단계로 줄인 `Docs/ConnectDBPhysicalE2EChecklist-20260820.md`를 추가했다.
- `supabase/sql/connectdb_e2e_readonly_verification.sql`은 테스트 사용자 UUID 하나로 Auth identity/session, 사용자 소유 옷장·비교·관측 제출, 최근 상세 행과 공용 catalog 총계를 JSON 하나로 반환한다. `SELECT`만 사용하며 운영 데이터를 변경하지 않는다.
- 같은 SQL을 탈퇴 전후에 실행한다. 탈퇴 후 Auth와 모든 사용자 소유 count는 0, 최근 사용자 배열은 빈 배열이어야 하며 공용 상품·관측·실측 총계는 줄어들면 안 된다.
- 운영 Supabase의 실제 `auth`, `public`, `fitmatch_catalog` 컬럼과 다시 대조해 쿼리를 작성했다. 사용자 UUID를 비운 안전한 상태로 운영 DB에서 실제 실행해 문법·테이블·컬럼 오류가 없음을 확인했다. 2026-08-20 22:49 KST 기준 공용 총계는 상품 1,578, 상품 관측 2, 원본 관측 실측 56, canonical 실측 27,548이다.
- 다음 작업은 Developer가 체크표 1~5단계를 실제 iPhone에서 실행하고 결과를 전달하는 것이다. 그 전에는 P1 DB 기본 경로 전환이나 P2 로그인 제공자 확장을 시작하지 않는다.

## 70. 2026-08-20 비교 품질 지표 분리·데이터 품질 이슈 원장

> 이 절이 첨부 Master Package 검토 후 실제로 선별 반영한 최신 DB 상태다. 앱의 추천 source of truth는 아직 로컬 Swift 엔진이며, 이 변경은 결과를 바꾸지 않고 DB 감사 가능성을 높인다.

- 패키지 제안 중 `원본 실측 → 정규화 실측`, 상품 분류의 method/confidence/version/evidence, 비교 불가 fail-closed, 실측별 포함·제외 근거는 기존 `product_observation_measurements` → `product_measurements`, `product_classification_history`, comparison RPC, `comparison_measurement_results`에 이미 구현되어 있어 중복 구조를 만들지 않았다.
- 운영 Supabase에 migration `comparison_quality_and_data_issue_contract`(version `20260820141731`)를 적용했다. 로컬 재현 파일은 `supabase/migrations/105_comparison_quality_and_data_issue_contract.sql`이다.
- `comparison_results.similarity_score`는 0~100의 핏 유사도 점수로 유지하고, `coverage_ratio`, `data_quality_score`, `confidence_score`, 사용/제외 실측 수, `quality_metrics_version`을 별도 컬럼으로 추가했다. 이제 “핏이 비슷한가”와 “근거를 얼마나 믿을 수 있는가”를 한 점수로 섞지 않는다.
- `fitmatch_complete_comparison`은 새 지표가 없는 기존 앱 요청도 계속 허용한다. 새 앱 요청에서는 지표를 0~1 constraint로 검증하고, 사용/제외 실측 수는 클라이언트 숫자를 믿지 않고 `measurements[].included`에서 DB가 다시 계산한다.
- Swift `FitMatchComparisonSyncCoordinator`는 coverage, 측정 정의 품질, 사용 실측 개수에 따른 evidence breadth를 분리 계산한다. 최종 confidence는 confirmed 결과만 `min(coverage, dataQuality) × evidenceBreadth`로 계산하고, 버전 `fitmatch-comparison-quality-2026-08-20-v1`과 함께 전송한다.
- backend-only `fitmatch_catalog.data_quality_issues` 원장을 추가했다. observation/product/classification/measurement 중 정확히 하나만 대상이 되며, issue code별 발생 횟수·심각도·증거·해결 상태를 보존한다. authenticated/anon은 직접 접근할 수 없고 service role만 관리한다.
- `fitmatch_process_product_observation` 실패는 `observation_processing_failed` 이슈를 중복 행 없이 누적하고, 동일 관측을 재처리해 성공하면 기존 이슈를 resolved로 전환한다.
- 운영 rollback probe에서 이슈 2회 누적 → 발생 횟수 2 → 해결 상태 전환, 비교 지표 0.75/0.90/0.675 저장, 포함/제외 실측 수 1/1 DB 재계산을 확인했다. 테스트 행은 전부 rollback되어 운영 잔존 데이터는 없다.
- iPhone 17 Pro Simulator에서 새 JSON key까지 확인하는 `FitMatchComparisonSyncCoordinatorTests` 2/2가 통과했다. 최종 결과 bundle은 `/tmp/FitMatchComparisonQuality-20260820-2.xcresult`다.
- 현재 1,578상품/2,578 variant/6,559 size/27,548 measurement에서 실측 signature가 완전히 같은 중복 size chart는 0건이었다. 따라서 `measurement_set` 공용화는 현재 이득 없이 FK·ingest·조회 복잡도만 늘리므로 도입하지 않았다. 실제 중복률이 의미 있게 증가할 때 다시 측정한 뒤 결정한다.
- Supabase advisor의 신규 대상 결과는 private 원장의 `RLS enabled/no policy` INFO와 생성 직후 `unused index` INFO뿐이다. no-policy는 authenticated 접근을 차단하려는 의도이며, 기존 authenticated SECURITY DEFINER RPC WARN은 함수 내부 `auth.uid()`·소유권 검사·빈 search path를 둔 의도된 API 경계다.

## 71. 현재 Remaining issues / Next To Do

### 완료

- [x] 비교 결과의 핏 점수·coverage·데이터 품질·confidence 분리 저장
- [x] 비교 근거 사용/제외 개수를 DB에서 재계산하는 하위 호환 RPC
- [x] 상품 관측 처리 실패의 backend-only 품질 이슈 누적·해결 원장
- [x] Swift 요청 계약, targeted test 2/2, 운영 rollback probe

### Developer To Do

- [ ] 68절 `DEV-P0-01~07` 실기기 로그인·옷장·비교·탈퇴·출시 설정 검증을 진행한다.
- [ ] 유니클로와 무신사 비교 각 1건 후 실행 시각·상품 코드·화면 결과를 전달한다. AI가 새 quality 컬럼과 measurement 결과를 함께 대조한다.

### AI To Do

- [ ] 실기기 비교 결과에서 `similarity_score`, `coverage_ratio`, `data_quality_score`, `confidence_score`, 사용/제외 실측 수와 원본 상세 행의 일관성을 확인한다.
- [ ] 68절 `AI-P1-01~02`의 DB runtime↔Swift dual-run parity를 구현하고 충분한 실제 표본을 검증한 뒤에만 사용자 승인으로 DB/backend를 기본 경로로 승격한다.
- [ ] 상품 실측 signature 중복률을 운영 지표로 관찰한다. 현재 0건이므로 `measurement_set` 구조는 만들지 않는다.

## 72. 2026-08-20 COS 1단계 링크·DB 수용 경계

- COS는 유니클로·무신사와 달리 현재 확인된 공식 웹 계약에서 안정적인 상품별 사이즈/실측 API를 제공하지 않는다. 개발 환경의 일반 HTTP 요청은 COS CDN에서 `Access Denied`로 응답했다. 비공개 API를 추측해 사용하지 않는다.
- 앱은 `cos.com` 공식 URL과 URL 안의 10자리 COS 상품번호를 인식한다. 공식 페이지가 허용될 때 JSON-LD/Open Graph의 상품명·이미지·가격과 URL 경로의 성별·카테고리 단서를 보존한다.
- 완전한 **사이즈별 의류 실측표**가 없으면 `ProductURLParserPartialError`로 종료한다. 즉 상품 정보는 보일 수 있어도 자동 비교·억지 실측 변환은 하지 않는 fail-closed 정책이다.
- `FitMatchSupabaseProductResolver`, 옷장 동기화, 비교 기록 동기화가 source `cos`를 기존 상품 resolve/runtime 경계로 전달한다. 기존 로컬 추천 엔진과 유니클로·무신사 처리에는 새 분기를 넣지 않았다.
- 운영 Supabase에 migration `add_cos_observation_source`를 적용했다. `product_observations`와 authenticated observation RPC, service-role batch inquiry RPC가 `cos`를 명시적으로 허용한다. 다른 임의 source는 계속 거절한다. DB probe에서 source constraint에 COS 포함, `fitmatch_batch_products_needing_ingest('cos', ...)` 1건 반환, observation RPC 본문 COS 허용을 확인했다.
- 새 COS fixture는 상품번호·공식 메타데이터·경로 분류 단서 보존 및 실측 부재 시 fail-closed를 검증한다. Swift 컴파일은 통과했으나 후속 Simulator service가 중단되어 실제 XCTest 실행은 아직 재시도 필요하다.

## 73. 2026-08-21 유니클로 내 옷장 저장 후 썸네일 보존

- 상품 정보 화면의 유니클로 썸네일 URL은 정상이나, 내 옷장 저장 경로가 `ProductSize.id`만으로 기존 행을 찾아 같은 사이즈명(M 등)의 다른 상품을 `UserFit.sourceProduct`로 연결할 수 있었다.
- `AddComparedProductToClosetSheet`는 이제 상품 URL(우선)과 쇼핑몰·상품코드(대체)로 동일 상품을 먼저 찾는다. 저장된 동일 상품에는 새 썸네일 URL을 보충하고, 새 상품은 먼저 SwiftData context에 삽입한 뒤 선택한 사이즈를 그 상품에 연결한다.
- 회귀 테스트는 같은 유니클로 상품 URL의 끝 슬래시는 동일 상품으로, 다른 상품코드는 다른 상품으로 판정하도록 추가했다. Simulator XCTest는 CoreSimulator/build database 동시 실행 상태가 해소된 뒤 재실행한다.

## 74. 2026-08-21 ZARA 검증 표본 category DB staging

- 사용자의 명시적 승인 후 운영 Supabase에 migration `seed_zara_verified_categories`(version `20260821032148`)를 적용했다. 로컬 재현 파일은 `supabase/migrations/107_seed_zara_verified_categories.sql`이다.
- `public.sources`에 `zara`를 등록했지만 `is_active=false`로 유지했다. API 사용 허가, 실제 iPhone, staging E2E가 끝나기 전에는 production provider로 활성화하지 않는다.
- 실제 ZARA structured analytics 표본에서 확인한 section/family/subfamily만 `public.source_categories`에 36건 저장했다: 남성 17, 여성 19. 전체 ZARA taxonomy라고 간주하지 않는다.
- FitMatch canonical detail이 명확한 27건만 연결했다. 분류 상태는 `EXACT=26`, `RULE_BASED=1`, `AMBIGUOUS=7`, root `UNMAPPED=2`다. 티셔츠·일반 바지처럼 세부 유형이 갈리는 항목은 category까지만 저장하고 detail을 비웠다.
- 사후 DB 검증에서 부모 누락 0, identity 중복 0, canonical FK 오류 0, production eligible 0을 확인했다. migration은 먼저 동일 SQL을 rollback probe로 실행한 뒤 적용했다.
- active `fitmatch_catalog.source_category_mappings`의 ZARA row는 0, ZARA product observation은 0이다. observation source CHECK도 계속 `uniqlo`, `musinsa`, `cos`만 허용한다. 따라서 이 작업은 catalog staging이며 runtime 분류/수집 활성화가 아니다.
- 다음 DB 작업은 실제 iPhone metadata/guide E2E, 공식 API 사용 권한, measurement basis 검증 뒤에만 진행한다: ZARA runtime release mapping, observation allowlist, raw measurement mapping 순서다.

## 75. 2026-08-21 ZARA 테스트용 category·observation DB 연결 완료

> 이 절이 74절보다 최신 권위 상태다. 74절의 비활성/source mapping 0/observation 미허용 상태는 이후 사용자 승인 작업으로 변경됐다.

- 사용자가 제공한 `zara_fitmatch_collection_20260813.zip`을 별도 temp directory에서 검증했다. validator 전체 `PASS`, generator 재실행 `PASS_BYTE_IDENTICAL`, category 213행과 mapping 213행의 manifest SHA-256 일치를 확인했다.
- 운영 Supabase `hnkplvyegonlhumlejst`에 다음 migration을 순서대로 적용했다.
  - `add_zara_observation_source` version `20260821042246`
  - `enable_zara_testing_categories` version `20260821042251`
  - `seed_zara_official_category_tree` version `20260821042258`
  - `publish_zara_client_category_mappings` version `20260821042806`
- `public.sources.zara.is_active=true`다. category는 현재 parser가 보내는 analytics namespace 36건과 공식 숫자 ID namespace 213건, 총 249건이다. 두 namespace는 metadata로 구분하며 서로 덮어쓰지 않는다.
- `public.source_category_mappings`와 `public.client_source_category_mappings`는 각각 confirmed 56, review_required 51, rejected 142로 일치한다. canonical 근거가 없는 원피스·점프수트·란제리, 혼합/집계 category는 confirmed로 올리지 않았다.
- active runtime release는 `fitmatch-active-with-zara-official-tree-2026-08-13-v1`이다. expected/actual 3,483건이 일치하며 provider별 Musinsa 1,922, Uniqlo 1,505, ZARA 56이다. 기존 provider row는 복제 보존했다.
- runtime source resolver probe는 analytics 셔츠와 숫자형 공식 셔츠를 confirmed로 찾았다. 원피스 review 표본과 unknown code는 `found=false`였다. batch ingest inquiry는 ZARA probe ID를 정상 반환했다.
- observation CHECK와 submit/batch RPC allowlist에 `zara`가 포함됐다. authenticated submit의 실제 사용자 row 생성은 사용자가 실기기에서 로그인한 뒤 확인한다.
- 공통 product classifier는 positive source mapping만으로 신규 상품을 자동 confirmed하지 않으므로 현재 ZARA product resolution은 `review_required`다. measurement basis도 미검증이어서 ZARA measurement mapping은 만들지 않았다. 따라서 category/observation DB 테스트는 가능하지만 추천 사이즈·매칭률 production 출시는 불가하다.
- Supabase advisor에는 이번 작업으로 만든 신규 table/index가 없다. 표시된 private schema RLS-no-policy INFO와 authenticated SECURITY DEFINER RPC WARN은 기존 구조이며, 이번 migration은 기존 권한/RLS를 완화하지 않았다.
- iPhone 17 Pro Simulator(iOS 26.3.1)에서 `ZARAParserPhase1_5Tests`와 `FitMatchSupabaseProductResolverTests`를 함께 재실행해 24/24 통과했다. 결과 bundle은 `/tmp/FitMatchZARADBReadyDerivedData/Logs/Test/Test-FitMatch-2026.08.21_13-31-37-+0900.xcresult`다.

## 76. 2026-08-21 ZARA 운영 30상품 A-test 적재

> 이 절이 ZARA DB 표본과 비교 가능 여부에 대한 최신 권위 상태다. 75절의 249 category/56 confirmed mapping은 이번 작업 후 262 category/65 confirmed mapping으로 증가했다.

- 사용자의 명시적 승인에 따라 제공된 ZARA 수집 패키지에서 실제 상품 30건을 선정하고, 공개 size guide를 동시성 1/cache 우선/5xx 최대 1회 재시도로 수집했다.
- 운영 canonical DB에는 ZARA product 30, 실제 source variant 45, size 188, raw measurement 870건이 존재한다. runtime 계약이 만든 빈 `__default__` placeholder variant 30건은 실제 색상 variant 수에 포함하지 않는다.
- guide 결과는 42 variant garment-measure, 3 variant body-only다. body-only 값은 garment measurement로 변환하지 않았다. garment raw field도 공식 basis가 미검증이므로 870건 전부 `is_comparable=false`, `measurement_alias_not_found`로 보존했다.
- product classification은 29건 confirmed, `자수 프린트 스커트 팬츠` 1건 review-required다. 신규 상품의 general classifier를 느슨하게 만들지 않고, bounded A-test의 실제 structured metadata를 근거로 product-specific decision을 사용했다.
- 인증 사용자를 가장하지 않고 service-role 전용 `fitmatch_batch_ingest_product`를 사용했다. 따라서 ZARA `product_observations`는 0건이며, 이 30건은 사용자 observation이 아니라 관리자 canonical preload 표본이다.
- 실제 앱 parser 경로 `ZARA > 남성/여성 > family > subfamily` 및 `SECTION:FAMILY:SUBFAMILY` code로 payload를 정렬했다. app-path source resolver와 product resolver probe가 confirmed category를 찾고 `comparison_ready=false`를 반환하는 것을 확인했다.
- migration `extend_zara_production_sample_categories` version `20260821080945`를 운영 적용했다. 로컬 파일은 `supabase/migrations/111_extend_zara_production_sample_categories.sql`이다. 신규 leaf 13건 중 9 confirmed, 4 review-required이며, 최종 ZARA category 262, public/client mapping 각각 confirmed 65/review 55/rejected 142, active runtime ZARA mapping 65다.
- ZARA structured category를 product-name heuristic으로 재분류하지 않게 했고, `지퍼 재킷`이 `퍼 재킷` substring 때문에 mouton이 되는 오류를 word-boundary 규칙으로 수정했다.
- 테스트 결과는 ZARA Phase 1.5 targeted 17/17, `FitMatchP0ProductionPathTests` + `FitMatchSupabaseProductResolverTests` 32/32 통과다. 결과 bundle은 각각 `/tmp/FitMatchZARA30DerivedData/Logs/Test/Test-FitMatch-2026.08.21_16-56-31-+0900.xcresult`, `/tmp/FitMatchZARA30DerivedData/Logs/Test/Test-FitMatch-2026.08.21_17-13-04-+0900.xcresult`다.
- 운영 advisor에는 ERROR가 없다. 기존 RLS-no-policy INFO, authenticated SECURITY DEFINER RPC WARN, leaked-password protection WARN, unused/unindexed index INFO는 유지되며 이번 ZARA category migration이 신규 table/RLS 경계를 만들지는 않았다. 일반 참고: https://supabase.com/docs/guides/database/database-linter

### 현재 ZARA 판정

- [x] 30상품 canonical 적재
- [x] structured category와 FitMatch category 결정 29건 확정, 1건 fail-closed review
- [x] variant/size/raw measurement 원형 보존
- [x] ZARA category/client/runtime mapping 확장
- [ ] canonical measurement alias 및 공식 basis 검증
- [ ] ZARA↔무신사·유니클로 comparison-ready 전환
- [ ] 공식 API 사용 권한, 실제 iPhone resolver, staging E2E, App Store build 검증

산출물은 `ZARAAudit/zara_production_sample_30_manifest.jsonl`(variant 45행), `zara_production_sample_30_payloads.jsonl`(상품 30행), `zara_production_sample_30_decisions.jsonl`(결정 30행), `prepare_production_sample_30.mjs`다. 전체 결과는 `FitMatch-ZARA-Phase1.5-Blocker-Resolution-20260821.md` M절에 기록했다.

## 77. 2026-08-21 ZARA category별 measurement mapping 승인 전 감사

- 이번 절은 읽기 전용 조사다. 앱 코드, 운영 DB alias, 기존 870개 measurement row는 변경하지 않았다.
- 30상품/45 variant 표본의 garment guide는 세 가지 schema로 수렴한다.
  - 티셔츠·셔츠·가디건·아우터: `chest`, `front-length`, `sleeve-length`, `arm-width`, `back-width`
  - 팬츠: `waist`, `hips`, `front-length-lower`, `front-rise`, `back-rise`
  - 원피스: `chest`, `waist-full-body`, `hips`, `front-length-full-body`
- 실제 ZARA KR 제품 사이즈 UI에서 상의·팬츠·원피스를 열어 모두 “옷을 평평하게 편 상태에서 측정”한다는 공식 문구와 cm 표를 확인했다. UI는 `가슴/허리/엉덩이 둘레`라고 표시하지만 값은 평평하게 놓은 한쪽 폭이다. 따라서 canonical width로 확정되는 경우 multiplier는 `1.0`이며 2로 나누거나 2를 곱하지 않는다. cm도 단위 변환이 없다.
- 다만 공식 UI 본문만으로 가슴선의 정확한 양 끝점, 앞면/총 기장의 시작점, 소매의 set-in/raglan 시작점은 아직 확인되지 않았다. 따라서 `chest→pit-to-pit`, `front-length→HPS-to-hem`, `sleeve→shoulder-seam-to-cuff`, `front-length-lower→waist-to-hem`은 현재 PROBABLE이며 바로 comparable alias로 승격하지 않는다.
- `back-width`는 shoulder가 아니고 `arm-width`는 현재 FitMatch canonical key가 없으므로 raw-only를 유지한다. `back-rise`도 front rise와 한 kind로 섞지 않고 raw-only가 안전하다. `sizeGuideInfo` body-only 3 variant는 계속 비교에서 제외한다.
- 운영 DB의 ZARA raw row는 `raw_code=A/B/C/D/E`, `raw_label=zone-name-*`로 저장돼 있다. A~E는 category별 의미가 다르고 upper schema에서도 D/E 순서가 바뀌므로 위치 문자를 alias key로 사용하면 안 된다. 현재 normalization 함수는 raw_code가 존재하면 label fallback을 하지 않으므로, 구현 시 ZARA의 `raw_code`를 stable `tableTitleZone`으로 바꾸고 원래 `zoneId`는 evidence에 보존해야 한다. `category_scope`도 payload에 명시해야 한다.
- 현재 parser candidate table은 실제 표본의 복수형 `zone-name-hips`, `waist-full-body`, `front-length-full-body`, `front-length-lower`를 처리하지 않는다. 검증된 항목만 typed mapping에 추가하고 mapping version을 올려야 한다.
- FitMatch 비교 최소 조건은 상의/셔츠/가디건 2개(shoulder 또는 chest 중 1개 포함), 아우터 2개(chest 필수), 팬츠 2개(waist/hip/thigh 중 2개), 원피스 2개(chest/waist/hip 중 1개)다. 따라서 팬츠는 waist+hip, 원피스는 chest+waist/hip이 검증되면 비교 가능하다. 상의·아우터는 chest만으로 부족하므로 front-length 또는 다른 두 번째 항목의 측정 기준 검증이 필요하다.
- 전체 검증 후 예상 최대치는 confirmed 29상품 중 garment guide가 있는 27상품이다. body-only 상품 2건과 review-required 상품 1건은 계속 제외한다. 수평 폭만 먼저 승인하고 상의 길이를 보류하면 팬츠 6상품+원피스 2상품, 총 8상품만 정책 최소 조건을 만족한다.
- 승인 후 권장 순서는 (1) upper/pants/dress 공식 측정 도식·설명 근거 확보, (2) ZARA raw identity/category_scope 및 Swift typed mapping 수정, (3) category-scoped alias migration과 기존 30상품 재정규화, (4) ZARA↔Musinsa↔Uniqlo pair regression과 rollback probe다. comparison score/weight와 기존 provider 로직은 변경하지 않는다.

## 78. 2026-08-21 ZARA 검증 measurement subset 운영 반영

> 이 절이 77절의 승인 전 상태를 대체하는 최신 권위 상태다. 전체 ZARA가 아니라 공식 근거가 확인된 팬츠·원피스 subset만 활성화했다.

- ZARA KR 공식 상품 사이즈 UI의 “옷을 평평하게 편 상태에서 측정” 문구와 category별 표를 대조했다. 활성 mapping은 전부 cm 단면→cm 단면 `×1.0`이며 나누기·곱하기 변환이 없다.
- 팬츠는 `waist→waist_width`, `hips→hip_width`, `front-rise→front_rise`; 원피스는 `chest→chest_width`, `waist-full-body→waist_width`, `hips→hip_width`만 comparable이다.
- 상의 length/sleeve/arm/back, 팬츠 total length/back rise, 원피스 full-body length는 측정 endpoint 또는 canonical 대응이 부족해 raw-only다. `sizeGuideInfo` body guidance도 계속 제외한다.
- `ZARAParser`는 stable `tableTitleZone`을 raw code로 사용하고 기존 A~E `zoneId`를 `raw_zone_id` evidence로 보존한다. 팬츠 waist+hip, 원피스 chest/waist/hip 중 2개라는 최소 조건을 parser가 다시 검사한다.
- 운영 migration `seed_zara_verified_measurement_subset` version `20260821090138`을 적용했다. 로컬 재현 파일은 `supabase/migrations/112_seed_zara_verified_measurement_subset.sql`이다. policy version은 `zara-measurement-2026-08-21-v1`, source alias는 category-scoped 5건이다.
- 30상품을 service-role ingest로 재정규화한 현재 DB는 measurement 870, comparable 177, raw-only 693이다. `raw_zone_id`와 full `source_dimensions`는 870건 모두 보존됐고 A~E raw code는 0건이다. classification은 confirmed 29/review-required 1을 유지한다.
- runtime DB probe는 ZARA↔ZARA 팬츠와 ZARA↔Uniqlo 팬츠를 comparison-ready로 판정했다. ZARA↔Musinsa 팬츠는 핵심 공통 폭이 waist 하나뿐이라 `required_any_measurements_missing`, ZARA 원피스끼리는 공식 length classification이 없어 `length_classification_missing`, review 상품은 `classification_not_confirmed`로 fail-closed다.
- 기존 Uniqlo↔Musinsa 팬츠 probe는 comparison-ready다. 점수·reliability·comparison policy와 기존 provider 분기는 변경하지 않았다.
- targeted ZARA suite 20/20, closet hydration suite 2/2가 iPhone 17 Pro Simulator(iOS 26.3.1)에서 통과했다. 전체 `FitMatchTests` struct는 260 passed, 기존 COS/category taxonomy expectation 9 failed, 장시간 Musinsa corpus 1 canceled다. ZARA 실패는 없었지만 전체 suite 통과로 표현하지 않는다. bundle은 `/tmp/FitMatchZARACommonFinalDerivedData/Logs/Test/Test-FitMatch-2026.08.21_18-16-04-+0900.xcresult`다.
- Supabase advisor는 ZARA 관련 신규 항목 0건이다. 전체 security는 INFO 47/WARN 14, performance는 INFO 89이며 기존 RLS-no-policy, SECURITY DEFINER, leaked-password protection, unused/unindexed index 항목이다: https://supabase.com/docs/guides/database/database-linter
- 남은 blocker는 (1) ZARA↔Musinsa의 두 번째 공통 핵심 팬츠 치수 부족, (2) 원피스 공식 length classification, (3) 상의 두 번째 verified 치수, (4) API 사용 허가, 실제 iPhone/App Store/staging E2E다. production release는 계속 NO다.
## 2026-08-24 ZARA URL variant·카테고리 출시 준비 보완

- ZARA URL `-p########.html` reference, URL `v1`, page `zara.analyticsData.catentryId`, 내부 `productId`, `productRef`의 기존 분리 계약을 유지했다. URL `v1`이 있으면 embedded analytics의 현재 `catentryId`와 정확히 일치할 때만 `url_variant_verified_by_embedded_analytics`로 확정하고, `v1`이 없으면 페이지가 명시한 현재 variant를 `embedded_analytics_selected_variant`로 기록한다. ID를 계산하거나 불일치 variant를 추측하지 않는다.
- `ProductMetadata`에 `variantSelectionMethod`, `variantSelectionConfidence`, `categoryMappingPolicyVersion` provenance를 추가했다. URL variant 검증은 confidence 1.0, page-selected variant는 0.9로 구분한다. 기존 raw URL/reference/variant/internal product ID는 모두 보존한다.
- ZARA category parser에 production sample DB migration 111에서 `confirmed`로 검토된 9개 exact `section|family|subfamily` mapping을 우선 적용하는 versioned embedded snapshot을 추가했다. exact mapping 다음에만 기존 broad structured-family fallback을 사용하며 unknown/mixed/excluded category는 계속 `.other`로 fail-closed다. 새 generic engine/table은 만들지 않았고 production DB write/migration apply는 하지 않았다.
- `measureGuideInfo`만 의류 실측으로 사용하는 기존 계약, `sizeGuideInfo` 비교 금지, challenge/access failure 중단, 검증되지 않은 상의 실측 raw-only 처리는 변경하지 않았다. ZARA release gate도 아직 열지 않았다.
- 검증: `xcodebuild build-for-testing ... -derivedDataPath /tmp/FitMatchZARAURLCategoryDerivedData` → `TEST BUILD SUCCEEDED`. `ZARAParserPhase1_5Tests` → 22/22 passed (`/tmp/FitMatchZARAURLCategory-20260824.xcresult`). `FitMatchP0ProductionPathTests` + `FitMatchSupabaseProductResolverTests` → 38/38 passed (`/tmp/FitMatchZARAURLCategoryRegression-20260824.xcresult`). `git diff --check` clean.
- 남은 출시 blocker: (1) 확인된 공식 structured product/variant API 계약이 없어 현재는 페이지 embedded analytics가 권위 경로다. CSS DOM 텍스트 파싱은 사용하지 않는다. (2) 여러 variant 목록에서 URL color를 별도 선택하는 공식 payload는 아직 검증되지 않았다. 현재 URL/page가 선택한 variant만 처리한다. (3) DB의 ZARA 249개 source mapping 중 client snapshot 기준 confirmed 56, review_required 51, rejected 142이므로 전체 category 자동 확정 상태가 아니다. 앱 embedded exact snapshot은 실제 production sample로 검증된 9개만 포함한다. (4) 실제 iPhone에서 ZARA KR URL 공유→페이지 metadata→size guide→비교 E2E와 접근 안정성이 미검증이다. (5) 이 네 항목 검증 전 release `ZARAIntegrationAvailability`는 의도적으로 닫혀 있다.

## 2026-08-24 ZARA 사용자 확정 4상품 카테고리 반영

- 사용자 검토로 다음 네 상품의 분류를 확정했고 원본 링크와 근거를 `ZARAAudit/zara_user_adjudicated_category_decisions_20260824.jsonl`에 보존했다.
  - [JEANS Z1975 로우라이즈 레귤러](https://www.zara.com/kr/ko/jeans-z1975-%E1%84%85%E1%85%A9%E1%84%8B%E1%85%AE%E1%84%85%E1%85%A1%E1%84%8B%E1%85%B5%E1%84%8C%E1%85%B3-%E1%84%85%E1%85%A6%E1%84%80%E1%85%B2%E1%86%AF%E1%84%85%E1%85%A5-p01934230.html?v1=585050955): 데님팬츠
  - [봄바초 팬츠](https://www.zara.com/kr/ko/%E1%84%87%E1%85%A5%E1%86%AF%E1%84%85%E1%85%AE%E1%86%AB-%E1%84%91%E1%85%A2%E1%86%AB%E1%84%8E%E1%85%B3-p05644812.html): 긴바지
  - [자수 프린트 스커트 팬츠](https://www.zara.com/kr/ko/%E1%84%8C%E1%85%A1%E1%84%89%E1%85%AE-%E1%84%91%E1%85%A2%E1%84%90%E1%85%A5%E1%86%AB-%E1%84%89%E1%85%B3%E1%84%8F%E1%85%A5%E1%84%90%E1%85%B3-%E1%84%91%E1%85%A2%E1%86%AB%E1%84%8E%E1%85%B3-p01377700.html): 긴바지
  - [스트라이프 봄버 재킷](https://www.zara.com/kr/ko/%E1%84%89%E1%85%B3%E1%84%90%E1%85%B3%E1%84%85%E1%85%A1%E1%84%8B%E1%85%B5%E1%84%91%E1%85%B3-%E1%84%87%E1%85%A9%E1%86%B7%E1%84%87%E1%85%A5-%E1%84%8C%E1%85%A2%E1%84%8F%E1%85%B5%E1%86%BA-p07782343.html): 재킷
- `C.PTON-LEGGING`, `L. PANT. PIJAMA`는 검증된 source path 단위로 긴바지에 연결했다. 현재 production canonical taxonomy는 조거를 별도 비교 family로 나누지 않고 `bottoms/long_pants/pants`로 비교하므로 봄바초 팬츠도 긴바지로 저장한다. 앱의 `트레이닝 팬츠` 표시 enum을 새 taxonomy 계약으로 승격하지 않았다.
- `B.FOLDER PANTS`와 `B.BLAZER`는 한 source subfamily 안에 다른 구조의 상품이 존재하므로 전체 subfamily를 데님/재킷으로 바꾸지 않았다. URL의 안정적인 8자리 style number `01934230`, `07782343`에만 사용자 확정 override를 적용한다. `02753522` 같은 실제 `B.BLAZER` 블레이저는 계속 블레이저다.
- ZARA embedded category snapshot 버전은 `zara-kr-structured-category-2026-08-24-v3`이며 parser가 URL style number를 classifier에 전달한다. ID를 계산하거나 상품명만으로 확정하지 않는다.
- 검증: `ZARAParserPhase1_5Tests` 25/25 통과(`/tmp/FitMatchZARAUserConfirmedV2-20260824.xcresult`), `FitMatchP0ProductionPathTests` + `FitMatchSupabaseProductResolverTests` 38/38 통과(`/tmp/FitMatchZARAUserConfirmedRegression-20260824.xcresult`), adjudication JSONL 전체 `jq` parse 통과, `git diff --check` clean.
- 운영 Supabase write/migration apply는 하지 않았다. 따라서 앱 로컬 분류는 반영됐지만 운영 DB의 기존 `자수 프린트 스커트 팬츠=review_required`, `스트라이프 봄버 재킷=blazer` product decision은 아직 사용자 확정값으로 승격되지 않았다. 다음 DB 작업은 이 JSONL을 근거로 기존 history를 보존한 새 manual-review history/decision을 staging에서 먼저 검증한 뒤 별도 승인을 받아 적용해야 한다.
- ZARA 전체 서비스 출시는 여전히 별도 문제다. 이번 작업은 사용자 확정 4건의 카테고리 ambiguity를 닫았고, 공식 API/접근 안정성·실제 iPhone 공유 E2E·나머지 review/rejected category·일부 measurement basis blocker는 그대로 남는다.

## 2026-08-24 ZARA 쉐도우 3,983건 실제 분류기 안전성 흡수

- 외부 파일의 ZARA 3,983건을 정답/Gold로 자동 승인하지 않고, 현재 앱의 실제 `ZARACategoryClassifier`에 통과시키는 회귀 테스트로 흡수했다. 3,983건 중 구조화된 일반상품 3,691건을 평가했고, 2,931건은 현재 계약으로 분류됐으며 760건은 안전하게 미분류로 남았다.
- 최초 감사에서 외부 파일의 대분류 후보와 앱 분류가 다른 항목은 187건이었다. 이 수치는 곧 오류 187건이 아니다. 가디건·니트 베스트를 외부 파일은 상의로, FitMatch 기존 계약은 아우터로 보는 기준 차이와 외부 후보 자체의 모순이 포함돼 있어 자동으로 덮어쓰지 않았다.
- 실제 안전 결함은 부분 문자열과 구조 충돌이었다. `WAISTCOAT`의 `coat`, `OVERSHIRT`의 `shirt`, `OVERALL|B.PANTS`의 `pants` 때문에 각각 아우터·상의·하의로 조용히 확정될 수 있었고, `SHIRT|F. Jacket`, `WIND-JACKET|ATH BSweatshirt`처럼 family와 subfamily가 다른 옷 구조를 말해도 한쪽 키워드가 이길 수 있었다.
- 정책 v4에서는 `OVERALL/점프수트`, `TOPS AND OTHERS`, `WAISTCOAT`, `OVERSHIRT`를 검토 전용 family로 fail-closed 처리한다. 이 선택은 운영 DB의 공식 ZARA 메뉴 자료에서도 점프수트·오버셔츠가 `review_required/unresolved`인 상태와 일치한다. 새 taxonomy나 generic engine은 만들지 않았다.
- exact source mapping이 없는 generic fallback에서는 family와 subfamily가 서로 다른 대분류를 명시하면 내부 `미확정` sentinel로 보류한다. 이 값은 사용자 카테고리 `기타/기타`로 확정하거나 표시하기 위한 값이 아니며 자동 비교 차단에만 사용한다. 사용자에게는 `분류 미확정` 또는 카테고리 선택 요청으로 표현해야 한다. 검토된 exact mapping과 사용자가 확정한 4상품 결과는 유지한다.
- 최종 전체-corpus 결과는 `rows=3983`, `evaluated=3691`, `structured_paths=152`, `classified=2931`, `unclassified=760`, `source_domain_mismatches=0`, `ambiguous_family_leaks=0`, `shadow_candidate_differences=66`이다. 마지막 66건은 Gold 오류 수가 아니라 현재 FitMatch 계약과 독립 정답이 없는 외부 후보의 차이이므로 NOT_VERIFIED로 유지한다.
- 검증: `node scripts/audit-category-mapping-shadow-corpus.mjs` 통과. `ZARAParserPhase1_5Tests` 27/27 통과(`/tmp/FitMatchZARAShadowAuditSuiteV3-20260824.xcresult`). `FitMatchP0ProductionPathTests` + `FitMatchSupabaseProductResolverTests` 38/38 통과(`/tmp/FitMatchZARAShadowRegression-20260824.xcresult`). `CategoryLive300ShadowAuditTests` 1/1 통과(`/tmp/FitMatchZARAShadowLive300-20260824.xcresult`), silent conflict 0, strict comparison conflict leak 0을 유지했다.
- 운영 Supabase write, migration apply, seed, backfill, commit, push는 하지 않았다. 신규 migration도 만들지 않았다. 현재 작업은 앱의 embedded fail-closed fallback과 로컬 테스트/문서만 보완했다.
- 남은 일: (1) 760 미분류 중 서비스할 source family를 현재 ZARA KR PDP/구조화 응답으로 재검증해 exact mapping 후보로 승격, (2) 66 계약 차이는 상품별 사람 검수 또는 독립 Gold로 판정, (3) 실제 iPhone에서 ZARA URL 공유→상품/variant→size guide→비교 E2E, (4) 공식 structured product/variant API 계약 및 다중 색상 선택 payload 확인, (5) 승인된 사용자 4상품의 운영 DB history/decision 반영은 별도 쓰기 승인 후 staging-first로 수행한다.

## 2026-08-24 ZARA 미확정 분류 UX를 무신사·유니클로 흐름과 통일

- 문제 근거: ZARA parser는 구조화 category가 미확정이면 size guide 조회 전에 `ProductURLParserPartialError`를 던졌고, `CompareFlowSheet`는 모든 partial error를 오류 화면으로 보냈다. 반면 무신사·유니클로는 실측 상품을 만든 뒤 기존 `categoryConfirmation` 화면으로 연결할 수 있었다. 결과적으로 같은 fail-closed 분류인데 ZARA만 사용자가 복구할 수 없었다.
- `ProductAnalysisRecoveryAction`을 추가해 `confirmCategoryBeforeMeasurements`와 `enterMeasurementsManually`를 오류 문구와 분리했다. UI는 sourceName 또는 문자열 비교로 ZARA를 추론하지 않고 typed recovery state만 사용한다.
- 미확정 ZARA는 이제 오류 화면 대신 기존 “상품 종류 확인” 화면으로 간다. category/detail 선택지에서 내부 `.other`는 계속 제외되므로 사용자에게 `기타/기타`가 표시·선택·저장되지 않는다. 디버그 로그도 내부 sentinel을 `분류 미확정`으로 표현한다.
- 사용자가 category/detail을 선택하면 같은 URL을 ZARA parser capability로 다시 분석한다. 선택한 category는 재조회 중 유지한다. 팬츠·원피스의 검증된 measurement subset이 최소 조건을 충족하면 자동 비교를 계속하고, 상의·아우터처럼 canonical measurement basis가 부족하면 추측하지 않고 기존 직접 입력 sheet를 연다.
- ZARA 초기 production release gate는 그대로 닫혀 있다. 이번 변경은 debug/staging에서의 복구 UX와 내부 경로를 완성한 것이며 실제 iPhone·접근 안정성·공식 사용 조건 확인 없이 production provider를 활성화하지 않는다.
- DB/schema/migration 변경과 production DB write는 없었다. comparison score, ranking, Musinsa/Uniqlo parser 정책도 변경하지 않았다.
- 검증:
  - `ZARAParserPhase1_5Tests` 30/30 통과. 미확정 recovery state, 사용자 확정 팬츠의 waist/hip 자동 재개, 미검증 상의의 직접 입력 전환, ViewModel의 사용자 category 보존을 포함한다. 결과: `/tmp/FitMatchZARARecovery-Final2-20260824.xcresult`.
  - 같은 suite의 3,983 shadow corpus 결과는 `source_domain_mismatches=0`, `ambiguous_family_leaks=0` 유지.
  - `FitMatchP0ProductionPathTests` + `FitMatchReleaseConfigurationTests` + `FitMatchSupabaseProductResolverTests` 39/39 통과. 결과: `/tmp/FitMatchZARARecovery-P0-20260824.xcresult`.
  - `git diff --check` clean.
- 남은 출시 작업: (1) 실제 iPhone에서 ZARA URL 공유→미확정 category 선택→size guide→비교/직접 입력 전환을 눈으로 확인, (2) ZARA 상의·아우터의 두 번째 canonical measurement endpoint 검증, (3) 공식 structured product/variant API 계약과 다중 색상 payload 검증, (4) release gate 활성화는 위 조건 통과 후 별도 결정한다.

## 2026-08-24 ZARA 상의·아우터 공식 측정 기준 반영

- 사용자가 제공한 ZARA KR 공식 상품 화면 캡처 4장으로 상의·아우터 측정 endpoint를 확인했다. 화면의 공식 설명은 (1) 가슴 둘레=`암홀 높이에서 한쪽 끝부터 다른 쪽 끝`, (2) 등 너비=`한쪽 어깨 소매 심라인에서 반대쪽 어깨 소매 심라인`, (3) 소매 길이=`한쪽 어깨 소매 심라인에서 소매 하단`이다. 따라서 각각 기존 typed contract인 `chest_width_pit_to_pit`, `shoulder_width_seam_to_seam`, `sleeve_shoulder_seam_to_cuff`와 일치한다.
- 같은 화면의 앞면 길이는 `어깨 심라인에서 밑단`으로 설명된다. 현재 FitMatch의 상의 앞길이 코드는 `어깨 최고점(HPS)에서 앞 밑단`이므로 동일하다고 보지 않았다. 팔 너비도 현재 typed canonical code가 없다. 두 항목은 값과 raw code/label/info를 그대로 보존하지만 비교·점수에서는 제외한다.
- `ZARASizeGuideParser` mapping version을 `zara_kr_measure_guide_verified_subset_v4`로 올렸다. 상의는 verified field 2개 이상이며 shoulder/chest 중 하나가 있을 때, 아우터는 2개 이상이며 chest가 있을 때만 `actualMeasurements`로 통과한다. 한 항목만 있거나 단위/값이 불완전하면 기존처럼 manual/fail-closed다.
- 실제 표본 링크:
  - [숏 슬리브 티셔츠](https://www.zara.com/kr/ko/%E1%84%89%E1%85%AD%E1%86%BA-%E1%84%89%E1%85%B3%E1%86%AF%E1%84%85%E1%85%B5%E1%84%87%E1%85%B3-%E1%84%90%E1%85%B5%E1%84%89%E1%85%A7%E1%84%8E%E1%85%B3-p03431633.html): 공식 표의 S/M 값 `가슴 43/46, 앞면 길이 55/56.5, 소매 16.5/17, 등 너비 39/40, 팔 너비 13.5/14`와 저장 fixture가 일치한다.
  - [스트라이프 봄버 재킷](https://www.zara.com/kr/ko/%E1%84%89%E1%85%B3%E1%84%90%E1%85%B3%E1%84%85%E1%85%A1%E1%84%8B%E1%85%B5%E1%84%91%E1%85%B3-%E1%84%87%E1%85%A9%E1%86%B7%E1%84%87%E1%85%A5-%E1%84%8C%E1%85%A2%E1%84%8F%E1%85%B5%E1%86%BA-p07782343.html): 공식 표의 S/M 값 `가슴 56/58, 앞면 길이 58/59, 소매 49/50, 등 너비 60.5/61.5, 팔 너비 25.5/26`과 저장 fixture가 일치한다.
- 기존 공통 `MeasurementComparisonEngine`에는 `zara` 분기를 추가하지 않았다. ZARA가 만든 canonical code를 기존 cross-source 경로가 Musinsa와 비교하는 회귀를 추가했고 confirmed/score 95를 확인했다. production score 공식, weight, ranking은 변경하지 않았다.
- 운영 Supabase는 read-only로 확인했다. 현재 `source_measurement_aliases`의 ZARA comparable row는 기존 policy `zara-measurement-2026-08-21-v1` 5개뿐이다. `measurement_definitions`에는 `chest_width`, `shoulder_width`, `sleeve_length`가 존재하고, runtime resolver도 새 basis를 각각 `chest`, `shoulder`, `sleeve_length`로 해석함을 SELECT로 검증했다.
- 로컬 migration 후보 `20260824100350_extend_zara_verified_upper_measurements.sql`을 Supabase CLI로 생성했다. 새 policy `zara-measurement-2026-08-24-v2`에 기존 5개와 upper/outer `back-width`, `sleeve-length`, 확장된 `chest` scope를 합쳐 comparable alias 7개를 versioned insert한다. 새 table/EAV/engine은 없으며 migration apply, seed, backfill, UPDATE, DELETE, production write는 실행하지 않았다.
- 검증:
  - `ZARAParserPhase1_5Tests` 31/31 통과: `/tmp/FitMatchZARAUpperMeasurements-Final-20260824.xcresult`.
  - `MeasurementPolicyConsolidationTests` 6/6 통과: `/tmp/FitMatchZARACrossSource-20260824.xcresult`.
  - `FitMatchP0ProductionPathTests + FitMatchReleaseConfigurationTests + FitMatchSupabaseProductResolverTests + MeasurementPolicyConsolidationTests + ZARAParserPhase1_5Tests` 76/76 통과: `/tmp/FitMatchZARAUpperP0Regression-20260824.xcresult`.
- 남은 출시 작업: (1) migration은 staging에서 parity/rollback 검증 후 별도 승인으로 production 적용, (2) 기존 ZARA 저장 measurement 재정규화는 별도 backfill 승인이 필요, (3) 실제 iPhone URL 공유→선택 variant→상의/아우터 자동 비교 E2E, (4) 앞면 길이의 HPS 대응 여부와 팔 너비 consumer는 추가 공식 근거/제품 요구가 생기기 전까지 raw-only, (5) 공식 structured product/variant API 계약·다중 색상 payload·release gate는 여전히 미완료다.

## 2026-08-24 connectDB → main 조건부 머지·출시 점검

- 사용자 지시는 현재 브랜치 테스트에 이상이 없을 때만 main에 머지하는 것이었다. 점검 시작 시 `connectDB`, `main`, `origin/connectDB`, `origin/main`은 모두 동일 HEAD `43add48bf083dd0e01036038ee34254e8579025f`였고, 이후 작업은 대규모 미커밋 변경으로 존재했다.
- XcodeBuildMCP로 iPhone 17 Pro Simulator(iOS 26.3.1) Debug 앱을 새로 빌드·설치·실행했다. 빌드와 실행은 성공했고 최초 화면의 Apple 로그인 CTA까지 확인했다. 파서 actor-isolation 경고는 ZARA 1건, COS 7건이었다.
- `xcodebuild build -project FitMatch.xcodeproj -scheme FitMatch -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/FitMatchReleaseCandidateDevice-20260824 CODE_SIGNING_ALLOWED=NO`는 `BUILD SUCCEEDED`였다. 이는 무서명 Release 컴파일 성공 근거이며 배포 서명·archive·Validate App 통과 근거는 아니다.
- 전체 `FitMatchTests` 실행은 green이 아니었다. XcodeBuildMCP 실행은 300초 도구 제한으로 결과 번들 없이 종료됐고, 결과 번들을 남기는 직접 재실행에서는 다음이 관찰됐다.
  - `CategoryLive300ShadowAuditTests` 1/1 통과. silent conflict confirmation 0, strict comparison conflict leak 0.
  - 5,026개 production 분류 XCTest 1/1 통과. invalid 0, 사용자 확인 329.
  - `CurrentUniqloCatalogAuditTests` 중 test host가 `pointer being freed was not allocated`로 종료 후 재시작했다.
  - 대형 Musinsa/Uniqlo corpus 실행에서도 test host가 반복 재시작됐다.
  - `LiveReleaseQA1200Tests.testSelectedTenCaseBatchOnPhysicalDevice`는 일반 scheme에서 필수 batch 환경변수가 없어 `XCTUnwrap` 1건 실패했다. 실기기 전용 테스트를 일반 회귀에서 skip/격리하지 못한 하네스 문제다.
  - 이어진 `testMusinsaDeepReferenceCandidateProbe`에서는 현재 parser 결과와 저장된 target taxonomy 사이의 다수 mismatch 로그가 발생했고 네트워크 장시간 실행이 이어져, 이미 확인된 실패·crash 뒤 수동 중단했다. 중단 실행을 전체 통과로 계산하지 않는다.
- 운영 Supabase migration ledger를 read-only로 재확인했다. 최신 적용은 `20260821090138 seed_zara_verified_measurement_subset`이다. 로컬 `113_p3_data_quality_observability`, `114_release_gate_and_quality_review_queue`, `20260824100350_extend_zara_verified_upper_measurements`는 운영에 적용되지 않았다.
- Release 앱의 `FitMatchPrivacyPolicyURL`, `FitMatchSupportURL`은 여전히 빈 문자열이고, `ZARAIntegrationAvailability`는 Release에서 항상 false다.
- 결론: 사용자 조건인 “테스트 이상 없음”이 충족되지 않아 commit/merge/push를 실행하지 않았다. main은 `43add48`에 그대로 있고 working tree도 보존했다. 현재 코드는 Debug/Release 컴파일 가능하지만 출시 승인은 NO다.
- 다음 순서: (1) 일반 회귀에서 실기기·환경 의존 테스트를 명시적으로 skip/전용 scheme으로 격리, (2) test host 메모리 종료를 단독 재현·원인 수정, (3) Musinsa deep-reference 기대 taxonomy의 현재 정책 적합성 검수, (4) 전체 offline unit/UI regression 실패 0 재실행, (5) 실제 iPhone Apple 로그인·옷장·비교·탈퇴·공유 E2E, (6) 공개 privacy/support URL, 배포 서명 archive, archive audit, Validate App, TestFlight 확인 후에만 출시 승인한다.

## 2026-08-24 조건부 머지 재검수 결과와 남은 사용자 판정

- 이전 전체 테스트의 메모리 종료는 앱 실행 중 메모리 누수로 확인된 것이 아니라, 수백~수천 개 상품을 한 프로세스에서 순차 분석하는 대형 감사 테스트와 실시간 네트워크 테스트가 일반 회귀에 함께 들어가 test host가 재시작한 문제였다. 장시간 corpus·Vision OCR·실기기/네트워크 감사에는 명시적 환경변수 gate를 추가해 기본 offline 회귀에서 격리했다. 해당 테스트 자체를 삭제하거나 기대값을 완화하지 않았다.
- `ShoppingProductViewModel`은 deinit 시 진행 중인 `databaseResolutionTask`를 취소하도록 보완했다. Intel Simulator에서 관찰된 `ShoppingProductViewModel.__deallocating_deinit` invalid-free 재현 경로를 제거했고, 현재 Uniqlo catalog 감사의 단독 재실행이 정상 종료됐다.
- 현재 Uniqlo 880상품 감사 결과는 `raw_size_rows=5193`, `parsed_size_rows=5181`, `eligible=439`, `scenarios=2237`, `pass=2237`, `fail=0`이다. Musinsa 1,037 corpus는 1/1 통과(428.059초), Uniqlo 243 corpus는 1/1 통과(57.7초), 장시간 이미지 OCR 감사도 1/1 통과(30.5초)했다.
- 분류 안전성은 다음을 보완했다. 셔츠/블라우스 같은 typed detail이 broad `tops.tshirt` source family에 의해 티셔츠로 덮이지 않는다. 민소매 구조가 저장된 긴소매 추론에 밀리지 않는다. product name의 명시적 polo는 일반 셔츠보다 먼저 판정하되, broad source umbrella의 polo 문구는 typed 셔츠를 덮지 않는다. trusted 상의 taxonomy와 `코치재킷` 상품명이 충돌하는 경우 상품명만으로 아우터를 자동 확정하지 않는다. COS `/t-shirts/`도 generic `shirt` 부분 문자열에 오분류되지 않는다.
- ZARA 상의 공식 화면에서 검증된 가슴·등 너비·소매만 canonical measurement로 사용하고, endpoint가 다른 앞면 길이와 typed code가 없는 팔 너비는 raw-only로 유지하는 regression을 고정했다. production score·weight·ranking 계산식은 변경하지 않았다.
- 일반 offline 전체 suite에서 오래된 adjudication 1개만 제외한 결과는 441 tests, 407 passed, 34 skipped, 0 failed다. 결과 번들은 `/tmp/FitMatchFullOfflineSerialExceptStaleGold-r4-20260824.xcresult`이다. skipped 34건은 환경변수/실기기/네트워크가 필요한 명시적 감사 테스트다.
- 제외한 `DBLogicReliabilityAuditTests.testDBLogicAdjudicationMatchesProductionClassifier`는 207개 판정 중 31상품에서 64개 assertion이 현재 안전 정책과 과거 fixture가 다르다. 주요 차이는 과거 fixture가 반팔/민소매 셔츠·블라우스를 `tshirt` family로 저장한 반면 현재 typed contract는 종류를 `shirt`/`blouse`로 유지하고 길이를 `short_sleeve`/`sleeveless`로 별도 저장한다는 점이다. 또 `uniqlo|E491320 KIDS PEANUTS코치재킷`은 과거 fixture가 outerwear/windbreaker지만 현재 authority 정책은 trusted top 분류를 상품명 하나로 덮지 않는다.
- 영향 상품은 Musinsa `5049615, 5155214, 6405582`, Uniqlo `E474152, E482479, E482480, E482481, E482483, E482497, E482498, E482502, E483875, E483881, E483890, E484240, E484256, E484849, E484876, E485584, E486701, E486734, E486736, E486738, E486834, E487989, E489136, E489138, E489229, E489230, E490285, E491320`이다. 이 fixture는 과거 사람 판정이 포함된 Gold 성격이라 사용자 승인 없이 기대값을 바꾸지 않았다.
- 권장 판정은 셔츠/블라우스의 garment type을 유지하고 반팔/민소매는 length로 분리하는 현재 정책을 승인해 fixture를 재판정하는 것이다. `E491320`은 공식 trusted category가 상의라면 자동 비교를 차단하고 review 대상으로 두는 현재 fail-closed 정책을 권장한다. 사용자가 이 의미를 승인해야 fixture 갱신 후 진짜 전체 suite 0 failure를 확인할 수 있다.
- 정확한 주요 명령과 결과:
  - `env TEST_RUNNER_FITMATCH_RUN_FIT_PAIR_CORPUS_AUDIT=1 xcodebuild ... -only-testing:FitMatchTests/FitMatchTests/fitPairRuleCorpusMusinsa1037` → 1 passed, 428.059s.
  - `env TEST_RUNNER_FITMATCH_RUN_FIT_PAIR_CORPUS_AUDIT=1 xcodebuild ... -only-testing:FitMatchTests/FitMatchTests/fitPairRuleCorpusUniqlo243` → 1 passed, 57.7s.
  - `env TEST_RUNNER_FITMATCH_RUN_LONG_IMAGE_AUDIT=1 xcodebuild ... -only-testing:FitMatchTests/FitMatchTests/longImageAudit` → 1 passed, 30.5s.
  - `xcodebuild test -project FitMatch.xcodeproj -scheme FitMatch -configuration Debug -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchCrashIsolation-20260824 -parallel-testing-enabled NO -collect-test-diagnostics never -only-testing:FitMatchTests -skip-testing:FitMatchTests/DBLogicReliabilityAuditTests/testDBLogicAdjudicationMatchesProductionClassifier -resultBundlePath /tmp/FitMatchFullOfflineSerialExceptStaleGold-r4-20260824.xcresult` → 441 total, 407 passed, 34 skipped, 0 failed.
- 출시 blocker는 추가로 남아 있다. `FitMatchPrivacyPolicyURL`과 `FitMatchSupportURL`은 빈 문자열이고 Release의 `ZARAIntegrationAvailability.isEnabled`는 `false`다. 운영 DB 최신 migration은 `20260821090138`이며 로컬 `113`, `114`, `20260824100350`은 미적용이다. 실제 iPhone에서 ZARA 공유 URL·variant·size guide·카테고리 확인·자동 비교/직접 입력 전환 E2E도 아직 수행하지 않았다.
- 결론: 현재 branch는 `connectDB`, HEAD는 `43add48bf083dd0e01036038ee34254e8579025f`다. Gold 판정 31상품 승인 전에는 전체 테스트 실패 0 조건이 아니므로 commit/merge/push와 출시를 하지 않는다.

## 2026-08-24 ZARA 99% 신뢰성 추가 감사

- ZARA KR 공식 상품 페이지 5개(티셔츠·셔츠·팬츠·재킷·원피스)를 실제 브라우저에서 열어 구조화 데이터 계약을 다시 확인했다. 각 페이지에서 JSON-LD `ProductGroup.productGroupID`, variant URL의 `v1`, embedded analytics의 `catentryId`, 내부 `productId`, `productRef`가 함께 제공됐다. 이는 CSS DOM 텍스트에 의존하지 않고 상품 reference와 선택 variant를 상호 검증할 수 있는 근거다.
- `ZARAProductPageParser.identity()`는 JSON-LD가 제공될 경우 analytics style이 `productGroupID`와 일치하고, analytics `catentryId`가 JSON-LD variant URL 목록 안에 있을 때만 identity를 확정하도록 보강했다. 과거 저장 fixture처럼 richer JSON-LD 필드가 없는 자료는 계속 읽되, 서로 모순되는 최신 구조화 데이터는 fail-closed한다.
- 정상 상품 페이지의 JavaScript bundle 안에 문자열 `triggerInterstitialChallenge`가 포함돼 있다는 이유만으로 CAPTCHA로 오판하던 실제 결함을 발견했다. challenge 판정은 이제 `bm-verify`, 화면의 Access Denied title/body 같은 강한 신호를 우선하고, 해당 bundle 문자열만 있을 때는 유효한 analytics와 Product JSON-LD가 모두 없는 경우에만 차단한다. 회귀 테스트를 추가했다.
- iPhone 17 Pro Simulator에서 visible WebView 감사를 실행한 결과, 수정 전에는 정상 페이지가 `challenge_detected`로 실패했으나 수정 후에는 공식 티셔츠 URL에서 `style=04174325`, `v1/catentry=547793140`, `productId=545408873`, `productRef=04174325-I2026`과 `garment_measure` 응답까지 확인했다. 즉 공식 페이지를 사용자 브라우저와 같은 WebView로 읽는 경로 자체는 동작한다.
- 다만 실제 기본 `ZARAProductPageLoader`는 여전히 background `URLSession` 경로다. opt-in live production-loader test를 추가해 같은 공식 URL을 호출한 결과 `automaticParsingUnavailable`로 실패했다. 별도 DEBUG WebView 감사만 성공하고 production/default import path는 실패하므로 현재 상태를 ZARA 서비스 준비 완료 또는 99% 신뢰성이라고 판정할 수 없다.
- 검증 결과: 구조화 identity/challenge 회귀를 포함한 기본 `ZARAParserPhase1_5Tests`는 최종 35개 중 34 통과, 명시적 live 1개 skip으로 성공했다(`/tmp/FitMatchZARA99DefaultFinal-20260824.xcresult`). P0/release/resolver/measurement/ZARA focused regression은 79/79 통과했다(`/tmp/FitMatchZARA99FocusedRegression-20260824.xcresult`). opt-in live default-loader 감사는 35개 중 34 통과, live 1건 실패(`/tmp/FitMatchZARALiveDefaultLoader-r5-20260824.xcresult`)이며 이 실패가 현재 출시 blocker다.
- 99% 수치도 아직 입증할 수 없다. 현재 ZARA shadow corpus 3,983건은 독립 정답이 아니라 후보 데이터이고, 사용자가 직접 확정한 Gold는 4상품뿐이다. 객관적인 99% precision 근거를 만들려면 분류군·성별·구조·미확정 사례가 섞인 대표 표본을 독립 검수해야 한다. 권장 최소 검증팩은 약 300상품이며, 오류 0건일 때도 이를 운영 전체에 대한 절대 보장으로 표현하지 않고 표본 기반 신뢰 근거로만 사용한다.
- 아래 2026-08-25 작업으로 앞서 적은 WebView-first 제안은 폐기하고 `URL v1 실측 API 우선 + WebKit fallback`으로 구현했다. 남은 우선순위는 (1) 300상품 독립 Gold 검수팩과 오분류/보류율 집계, (2) 7일 반복 drift 감사, (3) 실제 iPhone 공유 확장 E2E다. production score, ranking, DB 데이터는 변경하지 않았고 commit/merge/push도 하지 않았다.

## 2026-08-25 ZARA URL v1·실측 API 우선 경로와 WebKit fallback 구현

- 사용자 승인에 따라 수집 순서를 `URL identity 우선 → v1 실측 API 선조회 → 일반 HTTP 상품 구조 확인 → 필요한 경우에만 WebKit 구조화 데이터 fallback`으로 변경했다. URL `p########`은 style reference, query `v1`은 선택 색상의 catalog-entry ID로 계속 분리하며 서로 계산하지 않는다.
- `v1`이 있으면 `size-measure-guide`를 상품 페이지보다 먼저 호출한다. 다만 선조회 응답은 이후 공식 상품 페이지의 analytics와 JSON-LD가 같은 style/variant를 독립적으로 확인한 경우에만 소비한다. URL의 임의·오래된 `v1`을 그대로 신뢰하거나 다른 색상 ID로 바꾸지 않는다.
- `v1`이 없으면 기존처럼 상품 구조화 데이터에서 현재 `catentryId`를 확인한 후 실측 API를 호출한다. 따라서 다중 색상 상품에서 reference만 보고 임의 variant를 고르는 동작은 없다.
- 일반 `URLSession` 상품 페이지가 403/빈 구조/JavaScript 미실행 등으로 identity를 만들지 못할 때만 `ZARAWebViewProductPageLoader`를 사용한다. fallback은 비영구 WebKit data store, JavaScript 활성화, 공식 ZARA host 제한으로 동작하고 DOM 문구 전체가 아니라 `zara.analyticsData` script와 Product JSON-LD만 캡처한다. URL의 `bm-verify`, 화면 Access Denied, navigation 401/403/429는 실패로 종료하며 challenge 해결·쿠키 복제·우회 로직은 없다.
- ZARA가 짧은 `/item-p...` URL을 localized canonical 상품명 URL로 교체할 때 WebKit이 이전 navigation을 `NSURLErrorCancelled(-999)`로 알리는 정상 동작을 실제 라이브 검사에서 발견했다. 이 취소만 계속 기다리고 실제 네트워크 오류는 실패시키도록 수정했다.
- 신규 회귀 테스트는 (1) `v1`이 있으면 guide→page 순서, (2) `v1`이 없으면 page→guide 순서, (3) direct page가 유효하지 않을 때 fallback을 사용하면서 같은 variant를 유지하는지 검증한다. 기본 focused regression에서는 opt-in live test 2개만 skip되고 나머지가 모두 통과했다.
- 이전에 `automaticParsingUnavailable`로 실패했던 공식 티셔츠 URL `https://www.zara.com/kr/ko/item-p04174325.html?v1=547793140`을 실제 기본 `ZARAParser()`로 재실행했다. 수정 후 상품명, style `04174325`, catentry `547793140`, internal product ID `545408873`, 상의/반팔, `actualMeasurements`와 비어 있지 않은 사이즈를 확인했다. 또한 `v1=547793140`을 `ZARASizeGuideLoader`에 직접 전달하는 별도 live test가 상품 페이지를 읽지 않고 공식 `measureGuideInfo`의 cm 실측 행을 받는 것도 확인했다. live ZARA suite 39/39 통과(`/tmp/FitMatchZARAURLFirstDirectAPILive-r2-20260825.xcresult`).
- P0/release/resolver/measurement/ZARA final focused regression은 총 84건에서 실패 0건이었다(기본 실행에서 opt-in live 2건 skip, 나머지 통과, `/tmp/FitMatchZARAURLFirstFinalFocused-20260825.xcresult`). XcodeBuildMCP로 iPhone 17 Pro Simulator에 새 Debug 앱을 빌드·설치·실행했고 Apple 로그인 시작 화면을 확인했다. arm64 generic iOS Release 무서명 빌드도 `BUILD SUCCEEDED`였다(`/tmp/FitMatchZARAURLFirstRelease-20260825`).
- 사용자 영향: `v1` 포함 링크는 실측 조회를 먼저 시작하므로 불필요한 WebKit 의존을 줄이고, 일반 HTTP 상품 페이지가 실패해도 공식 브라우저 구조화 데이터로 자동 복구할 수 있다. fallback은 내부 비표시 WebKit 세션이므로 추가 페이지 화면을 사용자에게 강제로 노출하지 않는다.
- 변경하지 않은 것: production score·weight·ranking, category taxonomy, 운영 DB, migration, release gate. `ZARAIntegrationAvailability`는 Release에서 여전히 false이며 실제 iPhone 공유 확장 E2E, 300상품 독립 Gold, 반복 drift 검증, 운영 migration/release 승인 전에는 99% 또는 production 출시 완료로 판정하지 않는다. commit/merge/push도 실행하지 않았다.

## 2026-08-25 UNIQLO 색상별 상품 이미지 복구

- 사용자 캡처의 `크루넥T`, `E422992`, `XXL`은 현재 UNIQLO fixture의 실측값과 일치하며 저장된 `Product.imageURLString`이 비어 있어 홈·옷장 목록·상세 화면이 모두 같은 placeholder를 표시하는 문제였다. UI 세 곳의 개별 문제가 아니라 legacy 저장 상품의 이미지 복구 경로가 없던 공통 결함이었다.
- 선택 색상 이미지가 있으면 계속 최우선으로 사용한다. 해당 URL 로딩이 실패하면 같은 goods ID의 공식 기본색 `_00_` URL을 두 번째 후보로 시도한다. 다른 판매처나 알 수 없는 URL을 UNIQLO로 추정하지 않는다.
- 공유 URL이 generic color `00`이고 size API가 실제 대표 색상 이미지(이 상품은 `_11_`)를 제공하면, 같은 goods ID임을 확인한 뒤 그 공식 이미지를 채택한다. 명시적으로 선택된 색상(예: `03`)은 generic/다른 색상 이미지로 덮어쓰지 않는다.
- 이미 저장된 legacy UNIQLO 상품의 이미지가 nil이어도 canonical source code, 공식 URL host 또는 제한된 legacy source name으로 UNIQLO임이 확인된 경우에만 `productCode`에서 같은 상품의 공식 `_00_` 표시 URL을 런타임에 파생한다. 6자리 코드만 같은 Musinsa/unknown 상품에는 적용하지 않는다. DB/local backfill 없이 앱 업데이트만으로 기존 옷장 카드가 복구된다. 원본 `methodSource`, 상품 데이터, 비교 점수·순위는 변경하지 않았다.
- 공통 표시 경로(Home, My Closet 카드/목록, Closet 상세, 비교/추천/검색)를 `imageURLStringForDisplay`로 통일했다. 저장된 원본 URL은 그대로 보존하고 화면 표시에서만 복구 후보를 사용한다.
- 실제 CDN 확인: `E422992` 기본색 `_00_`과 size API 대표색 `_11_` 모두 2026-08-25 기준 HTTP 200 `image/jpeg`였다.
- 검증: iPhone 17 Pro Simulator Debug build/install/launch 성공. 최종 `FitMatchTests/FitMatchTests` 실행 결과 287 total, 284 passed, 3 explicit skips, 0 failed (`/tmp/FitMatchUniqloImageFallbackSuite-r2-20260825.xcresult`). 신규 회귀는 선택 색상 보존, generic 00의 공식 대표색 채택, 선택색→기본색 fallback 순서, nil legacy 상품의 기본 썸네일 파생, non-UNIQLO 6자리 코드 오탐 방지를 고정한다.
- 남은 확인: 로그인된 실제 사용자 데이터가 있는 iPhone에서 앱 업데이트 후 동일 `E422992` 카드가 홈·옷장·상세에서 표시되는지 눈으로 확인해야 한다. Simulator는 Apple 로그인 화면까지만 접근 가능해 사용자 계정의 기존 저장 row를 직접 재현하지 못했다. 이 확인은 구현 blocker가 아니라 실제 계정 데이터/UI 최종 확인이다.

## 2026-08-25 ZARA 공식 300상품 A 분류 테스트

- `scripts/collect-zara-live-300.mjs`로 공식 ZARA KR sitemap과 현재 구조화 상품 자료가 교차 확인된 300개 고유 style reference를 수집했고, 원본은 `ZARAAudit/live_zara_300_20260825/zara_live_300.jsonl`, 사람이 링크를 열어 판정할 표는 `zara_live_300_review.csv`에 보존했다. 전부 `official_listed=true`, `PENDING_HUMAN_REVIEW`, `gold_approved=false`이며 자동 Gold 승격은 하지 않았다.
- A 테스트는 300개 snapshot을 현재 실제 `ZARACategoryClassifier`와 `ParsedClosetClassification`의 conflict/atomic category 조건에 통과시켰다. 대분류 또는 세부분류가 `기타`이면 confirmed로 세지 않고 안전 미분류로 집계하도록 테스트 기준을 강화했다.
- 최종 결과: 300건 중 `confirmed=147`(49.0%), `review_required=19`(6.3%), `unclassified=134`(44.7%). `source_domain_mismatches=0`, `silent_conflict_confirmations=0`, `strict_conflict_leaks=0`이다. 따라서 잘못된 대분류 확정/충돌 비교 유출은 발견되지 않았지만 자동 서비스 범위는 절반 수준이라 99% 준비 완료로 볼 수 없다.
- 자동 확정 세부 분류: 스커트 26, 긴바지 23, 블레이저 21, 원피스 18, 재킷 16, 셔츠 15, 반팔 11, 데님 6, 스웨트 5, 코트 3, 가디건/반바지/폴로셔츠 각 1.
- 미분류가 가장 많이 몰린 source family: `SWIMSUIT|Swimwear` 23, `PANTY/UNDERPANT|Underwear` 20, `SWIMSUIT|BIKINI` 13, `SWIMSUIT|SWIMSUIT BIKINI` 9, `BERMUDA|B.BERMUDAS` 5, `BODYSUIT|BODY` 4, `OVERSHIRT|Overshirt` 4, `WAISTCOAT|B.VEST` 3. 수영복/바디수트처럼 현재 FitMatch 비교 계약 밖인 항목은 억지 매핑하지 않고, 버뮤다·오버셔츠·베스트·속옷은 상품 링크 사람 검수 후 exact source rule 후보로 분리해야 한다.
- `ZARAParserPhase1_5Tests` 최종 40 total, 38 passed, 2 explicit live-network skips, 0 failed(`/tmp/FitMatchZARALive300-A-final-20260825.xcresult`). 300건 A 분류 audit 자체는 실행·통과했다. production DB write/migration apply, score/ranking 변경, commit/push는 하지 않았다.
- 다음 단계: review CSV의 링크를 보고 300건에 `human_category`, `human_detail`, `reviewer_notes`, `gold_approved`를 채우는 독립 사람 판정이 필요하다. 그 뒤 A 결과와 Gold를 비교해야 precision/오분류율을 말할 수 있다. 현재 결과는 안전성과 coverage 결과이지 accuracy 99% 근거가 아니다.

## 2026-08-25 ZARA 공유 URL 버튼 비활성화 수정

- 사용자 실제 기기에서 ZARA 공유 URL `p05372320.html?v1=549582583&utm_...`을 입력해도 “상품 정보 불러오기”가 비활성화되고 “복사된 상품 링크가 없어요”가 남는 문제를 재현 근거로 조사했다. URL 형식이나 tracking query 문제가 아니라 `ZARAIntegrationAvailability`가 Debug launch argument에서만 true이고 Release에서는 항상 false였기 때문에 정상 `zara.com` URL도 `ProductURLSupport`에서 unsupported로 판정한 것이 직접 원인이었다.
- 사용자 승인으로 ZARA URL import를 공용 지원 provider로 활성화했다. gate만 제거했으며 parser 내부의 공식 host/style/variant 상호검증, category conflict 보류, verified measurement 부족 시 partial/manual 전환, 401/403/429/challenge fail-closed는 유지했다.
- 붙여넣기 UX도 수정했다. 입력창에 이미 URL이 있으면 pasteboard가 비어 있어도 “복사된 링크 없음”을 표시하지 않는다. 비어 있지 않은 입력은 empty-pasteboard 경고를 즉시 지우며, 실제 unsupported host일 때는 별도의 “지원하지 않는 상품 링크” 안내를 표시한다.
- 사용자가 제공한 전체 percent-encoded URL과 `v1`, `utm_campaign`, `utm_medium`, `utm_source`를 그대로 넣은 지원 판정 regression을 추가했다. ZARA 공식 URL은 `supportedProviderName == ZARA`, lookalike `zara.com.example.com`은 계속 거부한다.
- iPhone 17 Pro Simulator Debug build/install/launch 성공. `FitMatchTests/FitMatchTests` 287 total, 284 passed, 3 explicit skips, 0 failed. arm64 generic iOS Release 무서명 build도 `BUILD SUCCEEDED`(`/tmp/FitMatchZARALinkRelease-20260825`).
- 실제 사용자 URL을 `ProductURLParserService`에 전달하는 opt-in live regression도 추가했다. style `05372320`, selected variant `549582583`, source `ZARA 공식몰`을 확인했고 ZARA suite는 live network 포함 41/41 통과했다(`XcodeBuildMCP .../result-bundles/test_sim_2026-08-24T23-33-04-725Z_pid15783_affc597a.xcresult`).
- UI-testing 인증 상태의 iPhone 17 Pro Simulator에서 링크 추가 sheet를 직접 열고 동일 style/variant/utm 형식 URL을 입력했다. `closet.linkLoad`가 enabled target으로 나타났고, 버튼을 누른 뒤 공식 상품명 `와플 텍스처 레귤러핏 스웨트셔츠`와 활성 `다음` 버튼까지 확인했다. production DB write/migration apply, score/ranking 변경, commit/push는 하지 않았다. 실제 사용자 iPhone에는 이 수정이 포함된 새 빌드를 설치해야 하며, 설치 후 같은 링크로 한 번 확인하면 된다.

## 2026-08-25 세 쇼핑몰 내일 실기기 테스트 준비 감사

- ZARA 앱 내부 URL 입력 경로는 활성화돼 있었지만 `FitMatchShareExtension/ShareViewController.swift`가 무신사와 유니클로 host만 허용해 Safari/ZARA 앱의 공유하기에서 공식 ZARA URL을 거부하는 누락을 발견했다. 공식 `zara.com`과 그 하위 host를 공유 확장 허용 목록 및 metric provider에 추가했다. lookalike host는 허용하지 않는다.
- ZARA가 partial/manual recovery로 넘어갈 때 source가 `manual`로 바뀌는 문제도 수정했다. `ClosetProductSourceOption.zara`를 추가해 상품 출처·브랜드를 `ZARA 공식몰`/`ZARA`로 보존하고, 검증되지 않은 ZARA 자체 사이즈표를 주장하지 않도록 측정 방식은 FitMatch 직접 측정만 허용했다.
- 운영 Supabase를 read-only로 확인했다. source는 musinsa/uniqlo/zara 모두 active다. 상품은 Musinsa 394, Uniqlo 1,184, ZARA 30개이며 현재 분류는 Musinsa confirmed 311/review 82/not-comparable 1, Uniqlo confirmed 766/review 250/not-comparable 168, ZARA confirmed 29/review 1이다. 측정 row는 Musinsa 2,229, Uniqlo 25,319, ZARA 870이다.
- 운영 migration ledger 최신은 `20260821090138 seed_zara_verified_measurement_subset`이다. 로컬 `113_p3_data_quality_observability`, `114_release_gate_and_quality_review_queue`, `20260824100350_extend_zara_verified_upper_measurements`는 운영 미적용 상태다. 운영 `data_quality_issues`는 0건이라 unknown category/measurement/conflict 집계가 실제로 작동한다고 아직 입증할 수 없다. production DB write나 migration apply는 수행하지 않았다.
- 변경 후 focused 회귀는 live ZARA parser를 포함해 88/88 통과했다. `FitMatchTests/FitMatchTests`는 288 total, 285 passed, 3 explicit skips, 0 failed다. 전체 offline `FitMatchTests`는 과거 Gold 판정 1개를 명시 제외하고 457 total, 420 passed, 37 explicit skips, 0 failed(`/tmp/FitMatchTomorrowReadiness-20260825.xcresult`)다. 제외된 Gold는 이전부터 남은 31상품/64 assertion 정책 재판정 항목이며 기대값을 임의 변경하지 않았다.
- 첫 focused 빌드에서 `AddClosetItemView`의 새 ZARA enum case를 switch에 표시하지 않아 exhaustive-switch compile error가 발생했고 즉시 ZARA 안내 case를 추가했다. 같은 명령을 다시 실행해 88/88 통과로 확인했다.
- 내일 실제 iPhone에서는 새 빌드를 설치한 뒤 무신사/유니클로/ZARA 공유하기와 직접 붙여넣기, 유니클로 선택 색상 이미지, ZARA style/v1 유지, 자동 실측 비교와 직접 입력 전환을 각각 확인해야 한다. 이를 `Docs/ConnectDBPhysicalE2EChecklist-20260820.md`에 쉬운 확인표로 추가했다.
- arm64 generic iOS Release 무서명 빌드는 공유 확장을 앱에 포함하고 embedded binary validation까지 통과해 `BUILD SUCCEEDED`였다(`/tmp/FitMatchTomorrowRelease-20260825`). 수정 후 iPhone 17 Pro Simulator Debug build/install/launch도 성공했다.
- 정확한 최종 명령과 결과:
  - `xcodebuild test -project FitMatch.xcodeproj -scheme FitMatch -configuration Debug -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchTomorrowReadiness-20260825 -parallel-testing-enabled NO -collect-test-diagnostics never -only-testing:FitMatchTests -skip-testing:FitMatchTests/DBLogicReliabilityAuditTests/testDBLogicAdjudicationMatchesProductionClassifier -resultBundlePath /tmp/FitMatchTomorrowReadiness-20260825.xcresult` → 457 total, 420 passed, 37 skipped, 0 failed.
  - `xcodebuild build -project FitMatch.xcodeproj -scheme FitMatch -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/FitMatchTomorrowRelease-20260825 CODE_SIGNING_ALLOWED=NO` → `BUILD SUCCEEDED`.
- 남은 출시 blocker는 실제 iPhone 공유 확장 E2E, 빈 `FitMatchPrivacyPolicyURL`/`FitMatchSupportURL`, 과거 Gold fixture 31상품 사용자 판정, ZARA 300상품 독립 사람 Gold, 운영 미적용 migration의 승인·검증이다. production score/ranking은 변경하지 않았고 commit/merge/push도 수행하지 않았다.

## 2026-08-25 자동 처리 가능한 잔여 작업 보완

- ZARA 공식 300건의 `section|family|subfamily`와 상품명을 다시 대조했다. 동일 공식 경로 안의 관측 상품이 전부 같은 의류 구조인 경우만 category snapshot `zara-kr-structured-category-2026-08-25-v5`에 추가했다.
  - 남성 버뮤다 10건: 쇼츠 8, 데님 2
  - 남성 브리프 21건
  - 여성 브라 4건, 팬티 2건
  - 여성 버뮤다 4건
- 여성 `BERMUDA|B.BERMUDAS` 5건은 일반 버뮤다와 스커트형 팬츠가 섞여 있어 계속 미분류다. `BERMUDA|W.FOLDER PANTS` 1건은 구조 경로가 긴바지 후보지만 상품명이 쇼츠라서 계속 `review_required`다. 둘 다 자동 비교로 넘어가지 않는 회귀 테스트를 추가했다.
- ZARA 300건 분류 결과는 `confirmed 147 → 188`, `review_required 19`, `unclassified 134 → 93`이다. `source_domain_mismatch=0`, `silent_conflict_confirmation=0`, `strict_conflict_leak=0`을 정확한 fixture 기대값으로 고정했다. 즉 안전성을 낮추지 않고 자동 처리 가능 건만 41건 늘었다.
- parser의 Swift concurrency 경고를 없애기 위해 상태를 읽지 않는 ZARA/COS JSON·문자열 helper만 `nonisolated`로 표시했다. 파싱 규칙이나 결과는 변경하지 않았다.
- 미적용 migration `114_release_gate_and_quality_review_queue.sql`에 active release가 동시에 둘 생기지 못하는 partial unique index와 activation advisory lock을 추가했다. production에는 적용하지 않았다. migration 113/114 및 ZARA measurement migration과 verification SQL 총 5개는 PostgreSQL parser 문법 검사를 통과했다. 로컬 PostgreSQL server/Supabase CLI/Docker가 없어 실제 transaction 실행 검증은 아직 못 했다.
- 개인정보 처리방침 초안의 쇼핑몰 외부 통신 설명에 현재 활성 provider인 ZARA를 추가했다. 운영자명, 지원 이메일, 시행일과 공개 HTTPS URL은 소유자가 확정해야 하므로 빈 값은 임의로 채우지 않았다.
- 검증 결과:
  - `ZARAParserPhase1_5Tests`: 41 tests, 38 passed, 3 explicit live-network skips, 0 failed. `/tmp/FitMatchZaraV5Retry.xcresult`
  - 전체 `FitMatchTests`: 458 total, 420 passed, 37 skipped, 기존 Gold 판정 1 test failed. 실패 내용은 이전부터 남아 있던 31상품(무신사 3, 유니클로 28)의 과거 기대값과 현재 분류 차이이며 ZARA 변경 회귀가 아니다. `/tmp/FitMatchAllUnit-20260825.xcresult`
  - 위 기존 Gold test 1개만 명시 제외한 전체 회귀: 457 total, 420 passed, 37 skipped, 0 failed. `/tmp/FitMatchAllUnitExceptKnownGold-20260825.xcresult`
  - arm64 generic iOS Release 무서명 빌드와 공유 확장 embedded binary validation: `BUILD SUCCEEDED`. `/tmp/FitMatchTomorrowReleaseV5-20260825`
- 사람 또는 외부 환경이 꼭 필요한 남은 작업:
  1. 실제 iPhone에 새 빌드를 설치해 무신사·유니클로·ZARA 공유하기/붙여넣기와 유니클로 색상 이미지를 눈으로 확인한다.
  2. ZARA 300건 review CSV의 링크를 열어 독립 Gold를 입력한다. 현재 188건은 분류 가능 coverage이지 99% 정확도 근거가 아니다.
  3. 과거 Gold 불일치 31상품의 분류를 사람이 확정한 뒤에만 fixture를 갱신한다. 실패 기대값을 자동으로 바꾸지 않았다.
  4. 운영자명·지원 이메일·시행일·공개 개인정보/지원 HTTPS URL을 확정하고 `Info.plist`와 App Store Connect에 입력한다.
  5. migration 113/114/ZARA 상의 measurement 확장은 local/staging PostgreSQL에서 verification SQL을 통과시키고 별도 승인 후에만 production 적용한다.
- production score, weight, ranking, production DB 데이터는 변경하지 않았고 production migration apply, seed, backfill, UPDATE, DELETE, commit, merge, push도 수행하지 않았다.

## 2026-08-26 Classification Review-Required Evidence Audit

- Phase 1B-2 shadow SHA-256 `b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385`가 지정 baseline과 일치했다. `review_required`는 정확히 1,431건이며 Musinsa 391 / UNIQLO 1,010 / ZARA 30이다.
- `Docs/FitMatchClassificationReviewEvidenceAudit-20260826.jsonl`에 1 product = 1 row로 1,431행을 생성했다. unique `source+external_product_id` 1,431, primary root cause와 NO_NAME verdict는 각 product당 정확히 하나다. JSONL SHA-256은 `cbcfa931a01c152f6b8205cf26a3d2696af73ad5b3ec0f9585f52831eec81ddb`다.
- Primary root cause는 authority conflict 718, unused stored typed evidence 160, unverified/incomplete path 153, incomplete legacy decision 112, product-required without authority 99, invalid mapping 86, no mapping 53, name-only candidate 49, revoked exact decision 1이다.
- 엄격한 `SAFE_NO_NAME_RESOLVABLE`은 0이다. NO_NAME 상호배타 verdict는 structured-present-but-unverified 143, structured-missing 219, name-adds-only 47, manual 1,001, Phase 1A.5 exact evidence가 있지만 complete v4 tuple이 없어 blocked 21이다. Candidate manifest manual flag는 별도로 1,009이며 exact-blocked와 8건 겹친다.
- 실제 stored typed evidence는 Musinsa `size_type` informative 165, UNIQLO `product_type_kr` informative 47, ZARA family/subfamily/official category 30이다. ZARA 30은 path/codes에 동일 taxonomy가 있어 additive raw-only signal은 Musinsa 165 + UNIQLO 47 = 212다. 이를 직접 소비하려면 backend contract change가 필요하지만 confirmed coverage로 계산하지 않았다.
- 동일 deterministic tokenizer로 name signature와 structured-evidence signature를 비교했을 때 상품명이 추가 token을 제공한 상품은 246건(Musinsa 86 / UNIQLO 152 / ZARA 8)이다. Verified-complete name/path profile은 모두 0이므로 S4/S5 confirmed credit는 0이며 새 profile을 만들지 않았다.
- 보수적 DB-data-only 후보는 105건이다: Resolver에서 적용되지 않은 related verified category-direct 84건과 Phase 1A.5 expected-confirmed지만 v4 garment tuple이 incomplete한 21건. 이는 자동 승격 허가가 아니다.
- Production full-parity SELECT `2026-08-26T01:22:24.475019Z`, final postflight `2026-08-26T01:37:23.496830Z`: Phase 1B-2 product key/fingerprint 1,608/1,608 exact, mismatch 0; products 1,608, decisions 5,056, history/current 1,860/1,608, active release `65d72393-4a40-4e99-b701-fdc1ff865774`, active mappings 3,492, candidate release/review issue 0, latest migration `20260821090138`로 불변이다.
- 생성 보고서는 `Docs/FitMatchClassificationReviewEvidenceAudit-20260826.md`다. Production write/apply/activation/history change, migration/Swift/Resolver/Evaluator 변경, live retailer API 호출, Phase 1B-3 시작은 모두 0이다. Owner는 name 금지, verified name 보조, structured API 확대 후 name 최후 보조 중 정책을 결정해야 한다.

## 2026-08-26 Classification Authority Conflict Cohort Adjudication

- 지정 baseline checksum 두 개가 exact match했다: Phase 1B-2 shadow `b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385`, Review Evidence Audit `cbcfa931a01c152f6b8205cf26a3d2696af73ad5b3ec0f9585f52831eec81ddb`. A conflict 718, B DB-only 105, C invalid products 171도 exact다.
- A/B/C overlap은 A only 621, B only 91, C only 84, A∩B only 12, A∩C only 85, B∩C only 2, triple 0이며 unique union은 895다. Manual flag는 union 719 / conflict 599 / DB-only 37 / invalid 171이다.
- Conflict 718은 source + mapping identity + decision version + conflict dimensions + Phase1A.5 class로 압축했다. Independent exact-but-incomplete winner를 unverified peer와 섞지 않도록 Phase1A.5 class를 우선 분리해 최종 279 cohorts(UNIQLO 267 / ZARA 12)다. Verdict는 cohort/product 기준 `BOTH_UNTRUSTED 137/394`, `PRODUCT_REQUIRED 67/165`, `NEEDS_PRODUCT_ADJUDICATION 64/147`, `VERIFIED_DECISION_WINS 11/12`다. Verified semantic winner 12 중 conflict에서 immediate safe v4 completion은 E482522 1건뿐이고 잔여 conflict는 717이다.
- DB-only 105는 safe 86 / owner vocabulary 확인 7 / semantic adjudication 12로 재판정했다. Musinsa related `CATEGORY_DIRECT` 84는 6개 verified base mapping이 모두 `target=UNKNOWN`인데 Resolver v4가 이를 wildcard로 쓰지 않고 product audience와 exact-match하는 것이 공통 root cause다. Code가 빈 45건은 path exact, path 표기가 다른 2건은 leaf code exact라서, observed literal target별 17 candidate mapping clone이 84건을 안전하게 커버한다.
- Phase1A.5 exact-but-incomplete 21은 `SAFE_TUPLE_COMPLETION_DB_ONLY 2`(UNIQLO E482522/E485454), `VOCABULARY_TRANSLATION_NEEDS_OWNER_CONFIRM 7`, `SEMANTIC_ADJUDICATION_REQUIRED 12`다. Expected 값을 active taxonomy로 자동 번역하지 않았다.
- Invalid products 171은 64 unique mapping rows(Musinsa 6/50 products, UNIQLO 58/121)다. Verified replacement 0, `SHOULD_BE_PRODUCT_REQUIRED` 10 rows/25 products, `SHOULD_BE_REVOKED_NO_REPLACEMENT` 30/75, `TAXONOMY_VOCABULARY_REPAIR` 24/71이다. Invalid mapping verified-safe Top1/5/10/all coverage는 모두 0이다.
- Proposal manifest는 concrete logical row 102개다: P0 17, P1 0, P2 33, P3 40, P4 12. Independently verified safe gain은 P0 84, P0+P1 84, P0+P1+P2 86, all verified-safe 86이다. 실제 적용을 가정한 projection만 `confirmed 177→263`, `review_required 1,431→1,345`이며 실제 승격은 0이다.
- 산출물은 `Docs/FitMatchClassificationConflictCohortAdjudication-20260826.md`, `Docs/FitMatchClassificationConflictCohorts-20260826.jsonl` 279 rows, `Docs/FitMatchClassificationDBOnly105-20260826.jsonl` 105 rows, `Docs/FitMatchClassificationInvalidMappingRows-20260826.jsonl` 64 rows, `Docs/FitMatchClassificationRemediationPlan-20260826.jsonl` 102 rows다.
- Production final SELECT postflight `2026-08-26T04:30:33.040547Z`: product key/fingerprint 1,608/1,608 exact, mismatch 0; products 1,608, decisions 5,056, history/current 1,860/1,608, active release `65d72393-4a40-4e99-b701-fdc1ff865774`, active mappings 3,492, candidate release/issues 0, latest migration `20260821090138`로 불변이다. Resolver v4와 decision authority/garment columns도 Production에 없다.
- Structured typed signal 212, Musinsa `size_type` 165, UNIQLO `product_type_kr` 47, name-add 246, clean name-only 47은 safe gain에서 제외했다. Production write/DDL, migration create/apply, release/decision/mapping/profile/history write, Swift/Resolver/Evaluator 변경, live retailer API, Phase 1B-3는 모두 0이며 owner 승인 전 중지한다.

## 2026-08-26 Classification Candidate Revision + Full Shadow Revalidation

- 지정한 6개 baseline SHA-256이 모두 exact match했다. Additive revision manifest는 84 records(meta 1, clone 17, decision 2, product-required 10, revoke 30, untouched invalid-vocabulary parity 24), SHA-256 `997f8fca3726ef38b728e5bc0c2e2dcd4cb72e578a70d3a26d3d3fda6aee3f16`이다.
- Approved delta는 exact하다: Musinsa observed-target clone 17 rows/84 products, UNIQLO E482522/E485454 exact decisions 2, PRODUCT_REQUIRED 10 rows/25 products, revoke/no-replacement 30 rows/75 products. Baseline mapping identities 3,492/3,492 retained, revision mappings 3,509, unintended identity/base-row mismatch와 clone semantic diff는 0이다.
- Full resolver v4 shadow는 1,608/1,608 unique, fingerprint mismatch 0이다. 실제 결과는 confirmed 256 / review_required 1,352이며 source별 Musinsa 80/314, UNIQLO 176/1,008, ZARA 0/30이다. Shadow SHA-256은 `bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916`이다.
- 예상 263/1,345가 재현되지 않아 최종 판정은 `NO-GO (PARTIAL)`이다. Clone mapping은 84/84 exact selected됐지만 77만 confirmed됐다. `musinsa:5982920`, `6515855`, `6534177`, `6781113`, `6797265`, `6797266`, `6797271`은 existing incomplete `swift-production-2026-08-16-v3` decision과 새 verified mapping의 `product_decision_source_mapping_conflict`로 fail-closed한다. Exact decisions 2/2는 confirmed여서 approved safe gain은 79/86이다.
- Transition은 confirmed→confirmed 177, review→confirmed 79, review→review 1,352다. Approved 86 밖 unexpected transition 0, 기존 177의 status/tuple/method/authority/comparison allowed-reason regression 0이다. Gold 3/3, confirmed invalid tuple/product-required mapping-alone/revoked mapping/BOTH_UNTRUSTED/unknown fallback/generic underwear/tshirt-base-layer leak는 모두 0이다. Original conflict 718 중 E482522만 approved exact decision으로 confirmed, 717은 review다.
- Unapproved parity는 vocabulary 7 review, invalid vocabulary 24 rows/71 products review, name-add 246 review, clean name-only 47 review다. Structured typed 212의 authority는 추가하지 않았다. 이 cohort 중 33은 category clone으로 confirmed됐고 typed signal을 사용하지 않은 것이며, unresolved typed subset은 179다.
- PostgreSQL 17.11 fresh DB에서 fixture→113→114→115→116→117→validation ROLLBACK→117 reapply→validation ROLLBACK을 exact 실행했다. First/reapply mapping count 3,509, persistent decisions 5,056, history 0, mapping checksum `bb968aa7b7acb23a4d48693b4596aeff09a57dd7fe26b3d04b22658bf05c0dd0`, 두 shadow output은 byte-identical이다. PRODUCT_REQUIRED reasonCodes 재적용 중복 가능성을 발견해 order-preserving dedup으로 고쳤고 clean first/reapply checksum parity를 확인했다.
- Local release row는 `validated`지만 revision gate는 exact-decision validation transaction 안에서도 blocker `approved_transition_shortfall` 하나로 `eligible=false`다. Production postflight `2026-08-26T05:41:28.451116Z`: products 1,608, decisions 5,056, history/current 1,860/1,608, releases 5, active release `65d72393-4a40-4e99-b701-fdc1ff865774`, mappings 3,492, candidate v1/v2 release/mapping 0, migration 117 absent, latest migration `20260821090138`로 불변이다.
- Production write/DDL/apply/activation, decision/mapping/profile/history write, Swift/Resolver/Evaluator/Recorder diff, structured/name authority, retailer live API, Phase 1B-3는 모두 0이다. Owner가 7 legacy decisions의 exact disposition 또는 실제 256/1,352 baseline 수용을 새로 승인하기 전까지 중지한다. Structured Typed Evidence 212 read-only validation도 자동 시작하지 않았다.

## 2026-08-26 DB Classification Final Closure

- 117 shadow checksum `bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916`과 1,608 product key/fingerprint checksum `c1ed8a45c6548149b1b434c3551a4a674b41e627a642f6ed72db7ea55bee061a`가 exact parity다. 이전 Phase 1B-2/audit/conflict/DB-only/invalid/remediation checksum도 모두 지정값과 일치했다.
- `118_classification_db_final_closure.sql`은 local validated/inactive release만 만든다. generic structured discriminator table 1개, resolver v4 in-place precedence, legacy incomplete non-authority, exhaustive mapping scope, verified path/exclusion data, taxonomy/comparison/measurement completion을 구현했다. resolver v5/DSL/ML/source-specific resolver branch/name keyword authority는 만들지 않았다.
- 최종 mappings 3,509는 `CATEGORY_DIRECT 55 / PRODUCT_REQUIRED 1,019 / REVOKED 2,435`로 other/invalid/legacy runtime scope 0이다. Musinsa mixed sleeveless `001011/017016003` 7 rows는 PRODUCT_REQUIRED로 safety downgrade했다. Structured rules 21은 Musinsa canonical 5 rules(현 상품 7 confirmations), UNIQLO accessory exclusion 14 values(47 products), generic set/non-apparel 2다.
- set validation은 기존 `ParsedClosetClassification.isExplicitCompositeGarmentSet`와 `MusinsaUnsupportedProductPolicy.isTopBottomSet` 의미를 adapter fact `structured_facts.product_structure=set`으로 전달하는 contract다. 알려진 set 7개는 모두 `not_comparable`; set garment-confirmed/comparison-allowed 0이다. Swift behavior는 수정하지 않았다.
- taxonomy active comparison groups 44/auto 39, explicit unordered comparison matrix 990(allow 40/block 950, generic fallback 0), active measurement policy rows 63이고 active comparable family의 comparison/measurement policy gap은 모두 0이다. base-layer top은 tops이며 tshirt/underwear cross는 explicit block, homewear set은 non-auto/excluded다. MeasurementComparisonEngine score/weight algorithm diff 0이다.
- full final shadow는 1,608/1,608, fingerprint drift 0, `confirmed 348 / review_required 1,113 / not_comparable 147`; source는 Musinsa `121/266/7`, UNIQLO `227/817/140`, ZARA `0/30/0`이다. confirmed authority는 exact 120/category 156/structured 7/path 65, exclusions는 path 93/structured 54다. comparison possible 179, insufficient measurements 169다. Shadow SHA-256 `fa836a5d45c73da135e4c2b5f064b7291b4babbe20f5571ad66eff31cc77c93e`.
- 117 transition은 confirmed→confirmed 248, intentional mixed-sleeveless confirmed→review 8, review→confirmed 100, review→not-comparable 147, review→review 1,105다. Existing valid confirmed unintended regression 0, unexpected confirmed gain 0. Gold E482514/E454311/E456567 exact 3/3다.
- future/synthetic fixtures 29/29 PASS. confirmed invalid/arbitrary fallback/set leak/revoked-invalid leak/PRODUCT_REQUIRED-alone/BOTH_UNTRUSTED/unverified name-path/base-layer-tshirt/generic underwear leak는 전부 0이다. Real name profile은 0이고 verified-name-last-resort contract만 synthetic으로 검증했다.
- PostgreSQL 17.11 fresh disposable DB에서 fixture→113→114→115→116→117→118→validation ROLLBACK→118 reapply→validation ROLLBACK을 PASS했고 manifest 보완 후 118 reapply/full validation도 동일 결과로 PASS했다. Closure gate eligible true/blockers empty. Manifest 442 rows SHA-256 `f21e61545f194347aec02f620daefc9ea5dd56645fd1b9a77b0bc56f897163be`.
- Production SELECT-only pre/post는 products 1,608, decisions 5,056, history/current 1,860/1,608, releases 5, active release `65d72393-4a40-4e99-b701-fdc1ff865774`, active mappings 3,492, latest ledger `20260821090138`로 exact 불변이다. Production write/DDL/migration/apply/activation/history write 0, live retailer network 0, Swift/public RPC call-site switch 0이다.
- Closure 판정은 owner stop condition B를 만족하는 `DB CLASSIFICATION CLOSURE = GO`다. 남은 1,113은 DB 설계 gap이 아니라 independent product truth 부족으로 명시 review다. 산출물은 final migration/validation/manifest/shadow, `FitMatchClassificationDBClosure-20260826.md`, `FitMatchClassificationProductionDeploymentReady-20260826.md`다. 다음은 별도 승인된 controlled Production deployment, iOS server-authority integration, 실제 사용자 검증뿐이며 추가 DB audit Phase는 제안하지 않는다.

## 2026-08-26 Controlled Production Deployment — 118 FK Gate Rollback

- Owner가 승인한 SHA-256 `ac4f20b37b543f25e9557e7bf41f7a4fe96bba4247651991d976816fbdb770fc`의 118을 controlled transaction으로 시도했으나, `comparison_compatibility_rules.to_family_code=unclassified_outerwear`가 Production `fitmatch_taxonomy.comparison_families`에 없다는 FK gate에서 실패했다. 같은 transaction의 ledger insert 전 오류여서 118 전체가 자동 ROLLBACK됐다.
- Rollback 확인값은 ledger 118 = 0, final candidate = 0, rollback successor = 0, active release 정확히 1(`65d72393-4a40-4e99-b701-fdc1ff865774`), active mappings 3,492, decisions 5,056, history/current 1,860/1,608이다. candidate gate·successor·activation은 Production에서 시작하지 않았다.
- 원인은 `public.comparison_groups`와 legacy FK registry `fitmatch_taxonomy.comparison_families` 간 active-code parity를 118이 보장하지 않은 migration defect다. source/garment 분기 없이 active comparison group을 legacy family registry에 보완하고 parity를 assert하는 generic data sync를 118에 추가했다. validation에도 같은 conditional parity gate를 추가했다.
- 수정된 118 SHA-256은 `8934f427523c736f4e506ad65e4540625c36ce64904b6a05eee46091b8b2ddd3`, validation SHA-256은 `4d0a9b28fc3e830552f8789d12150d0a6da95ee00a998841a3218986fd99e376`이다. 승인 checksum과 달라 Production에는 재시도하지 않았다.
- PostgreSQL 17.11에서 legacy policy-version/comparison-family FK를 재현한 fresh production-shaped copy로 113→118, 118 reapply/idempotency, full 1,608 validation을 통과했다. 결과는 348/1,113/147, Gold 3/3, synthetic 29/29, matrix 990, family registry gap 0, safety leaks 0이다. Local xmin/role만 local 값으로 치환한 atomic activation dry-run도 candidate 단일 active/mappings 3,509/decisions 5,056/history write 0으로 PASS했다.
- 암호화 preimage cipher는 mode 0600, SHA-256 `844fec409490a04c4a14ea0ccdb22da6c130facf806ff27b8be8bd288522e22b`; decrypt read-back plain SHA-256 `22d34b6889f14dcf4de66eeed649be85e981dfcd6290ca10b3954da169c3314d`가 재확인됐다. history bulk backfill, history DELETE, Swift/iOS 변경, commit/push는 수행하지 않았다.
- SHA `8934f427523c736f4e506ad65e4540625c36ce64904b6a05eee46091b8b2ddd3`는 owner가 재승인했지만 두 번째 controlled transaction이 `classification_path_profiles_policy_version_fkey`에서 실패했다. `db-classifier-2026-08-26-final`이 Production `fitmatch_taxonomy.policy_versions`에 먼저 등록되지 않은 순서 결함이며, ledger insert 전 오류라 118 전체가 다시 자동 ROLLBACK됐다.
- 두 번째 rollback 뒤에도 ledger 118/candidate/successor는 0/0/0, 기존 active release 1, active mappings 3,492, decisions 5,056, history/current 1,860/1,608이다. Production candidate gate·successor·activation은 여전히 시작하지 않았다.
- 118 registry block이 exact classifier checksum `0b7d91f4726c413bb169659cda749de44992070d4ba31bcbf3b6731c5f8712f4`와 comparison checksum을 모두 FK-dependent row보다 먼저 등록하고 기존 row drift를 fail하도록 보강했다. 새 migration SHA-256은 `b1f2e35a584e05a64e31e53886aad04dd6cad6d619f8f8c69d50683dfdf03e30`이다.
- 모든 relevant Production policy-version/family FK를 재현한 새 PostgreSQL 17.11 copy에서 113→118, 118 reapply/idempotency, full validation 2회, candidate gate, rollback-successor gate, local atomic activation과 post-activation full validation이 PASS했다. 1,608 = 348/1,113/147, Gold 3/3, synthetic 29/29, profile 12/0/15, matrix 990, policy/family registry gap 0, safety leak/history write 0이다.
- legacy taxonomy supplemental preimage를 평문 파일 없이 `/private/tmp/FitMatchClassificationProductionPreimage-20260826/classification-preimage-legacy-taxonomy-v1.json.enc`에 AES-256-CBC/PBKDF2로 저장했다. mode 0600, plaintext/read-back SHA-256 `64c248aeb55692adb362e5db8735c6c22c796b1bb77bdf07eaeaab92fe1dcd39`, cipher SHA-256 `253a088456b9a34e58bc9a53b55dd38c23fe860dfb1f45e860e08f5a5a00a6f2`다.
- 다음 Production write는 최신 118 exact SHA `b1f2e35a584e05a64e31e53886aad04dd6cad6d619f8f8c69d50683dfdf03e30`에 대한 owner 재승인 후에만 가능하다.
- SHA `b1f2e35a584e05a64e31e53886aad04dd6cad6d619f8f8c69d50683dfdf03e30`도 owner가 재승인했지만 세 번째 controlled transaction이 Production `classification_exclusion_profiles_sample_check(sample_count >= 2)`에서 실패했다. Final manifest의 independently verified UNIQLO singleton accessory path 4개가 sample_count 1이기 때문이다. ledger insert 전 오류로 118 전체가 다시 자동 ROLLBACK됐고 Production state는 ledger/candidate/successor 0/0/0, old active 1, mappings 3,492, decisions 5,056, history/current 1,860/1,608로 불변이다.
- 기존 two-sample 품질 기준을 일반적으로 제거하지 않고, sample_count=1이면서 auto-eligible, non-apparel/accessory, evidence authority verified, complete-profile인 경우에만 허용하도록 check를 좁게 확장했다. Validation은 singleton exact 4와 해당 authority 조건을 별도 gate로 고정한다.
- Production sample/FK constraints를 모두 재현한 fresh PostgreSQL 17.11 copy에서 113→118, full validation, 118 reapply/idempotency, 두 번째 full validation이 348/1,113/147, Gold 3/3, synthetic 29/29, exclusions 15(singleton 4), safety leak 0으로 PASS했다.
- 최신 migration SHA-256은 `0eb9bfe801fd26bc33c084f5b9921aaf32aa5dc9b9c44a7ebfa17b7a3ccf5fb6`, validation SHA-256은 `5920e74cdfa6cead8e18557e4d11c76c7d3235bf7f7905a24900955ae0c36b5b`다. 다음 Production write는 이 최신 migration SHA에 대한 owner 재승인 후에만 가능하다.

## 2026-08-26 Controlled Production Deployment — 118 Applied, Candidate Gate NO-GO

- Owner가 재승인한 `118_classification_db_final_closure.sql` SHA-256 `0eb9bfe801fd26bc33c084f5b9921aaf32aa5dc9b9c44a7ebfa17b7a3ccf5fb6`을 exact 확인하고 Production에 controlled transaction으로 적용했다. Ledger `20260826090118 / classification_db_final_closure`가 같은 source/idempotency SHA와 함께 기록됐다.
- 118 apply 뒤에도 기존 release `65d72393-4a40-4e99-b701-fdc1ff865774`가 유일한 active release이고 active mappings는 3,492다. Final candidate `11800000-0000-4000-8000-000000000118`은 validated/inactive, mappings 3,509 상태다.
- Mandatory candidate gate 두 개가 모두 `eligible=false`로 실패했다. 유일한 blocker는 `measurement_policy_checksum_mismatch`이며 Production actual은 `6ad654049b08f6d19bd6a59c2a50482f550ee9edf6a0b9faad5d6f74b31a18a2`, candidate expected는 `d2a98b24f29ddfb57c0e2afa3215a7d9920a2a5f110fe50e301267c443ec4713`이다. Row count 63과 classifier/comparison/compatibility/structured/mapping contract는 일치한다.
- Owner stop rule에 따라 rollback successor 생성, atomic activation, Gold/set/structured/comparison/RPC Production smoke를 시작하지 않았다. 따라서 activation commit 0, half-active 0이며 기존 runtime은 v4 resolver/evaluator로 전환되지 않았다.
- Final read-only postflight `2026-08-26T12:17:13.873069Z`: active releases 1, active mappings 3,492, decisions 5,056, history/current 1,860/1,608, history write/delete 0, rollback successor 0이다. Swift/iOS 변경, history bulk backfill, Git commit/push는 수행하지 않았다.
- 최종 판정은 `PRODUCTION CLASSIFICATION AUTHORITY DEPLOYMENT = NO-GO`다. 118 additive migration/ledger는 적용됐지만 runtime은 기존 safe authority 그대로다. Measurement policy checksum 불일치를 우회하거나 자동 rebaseline하지 않고 중단했다.

## 2026-08-26 Measurement Policy Checksum Blocker — Targeted Resolution

- Production `2026.07.1` measurement policies 63행과 candidate 63행을 `(category_code,measurement_key,dimension_code)` logical key로 전수 비교했다. Missing/extra/duplicate 0, runtime-semantic diff 0, metadata/evidence_note diff 0이다. 63행 모두 유일한 차이는 `weight` text scale이며 Production `numeric(6,3)`의 `0.700/1.200/1.000`과 unconstrained-numeric fixture의 `0.7/1.2/1 또는 1.0` 표현 차이다.
- Raw checksums는 Production `6ad654049b08f6d19bd6a59c2a50482f550ee9edf6a0b9faad5d6f74b31a18a2`, candidate `d2a98b24f29ddfb57c0e2afa3215a7d9920a2a5f110fe50e301267c443ec4713`이지만 `trim_scale(weight)`와 explicit C collation을 적용한 semantic checksum은 양쪽 모두 `42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0`이다. Production policy data가 맞고 candidate raw checksum contract가 fixture typmod에 종속된 것이 root cause다.
- 신규 `supabase/migrations/119_classification_measurement_policy_checksum_correction.sql`은 적용된 118을 건드리지 않고 `runtime_policy_contract_report_v1(uuid)`의 measurement checksum만 scale/collation canonicalization하도록 동일 signature로 `CREATE OR REPLACE`한다. Measurement row write는 0이며 candidate validation report의 checksum만 canonical value로 교정한다. SHA-256은 `0c873e441eed10e68b01fbaaed24b420e84395140fe8eff495f879e87b417df5`다.
- Validation SQL SHA-256은 `20ec007f925099e82b82742769a554616fc1b84dcfd72d5c9d921d09df686860`. Exact 63-row diff JSONL은 63/63 unique, SHA-256 `4074f8389d0ba19f3e50bce35115019684f1a9fec2f1f74be6db58f31f9f3756`이다.
- PostgreSQL 17 production-shaped copies에서 119 apply/reapply, candidate policy/final/release gates, rollback-successor gate, atomic activation, post-activation full validation, atomic rollback을 모두 PASS했다. Full result는 1,608 = confirmed 348 / review 1,113 / not-comparable 147, Gold 3/3, synthetic 29/29, mappings 55/1,019/2,435, structured 21, path/name/exclusion 12/0/15, comparison 990, safety leaks 0, history write/delete 0으로 불변이다.
- Production final SELECT-only postflight `2026-08-26T12:56:35.010754Z`: ledger 118/119 `1/0`, active release exactly 1 (`65d72393-4a40-4e99-b701-fdc1ff865774`), active mappings 3,492, candidate validated/inactive 3,509 mappings, successor absent, products/decisions 1,608/5,056, history/current 1,860/1,608다. Sole gate blocker도 기존 checksum mismatch 그대로다.
- 이번 turn Production write/DDL/migration apply/activation/history write/delete 0, Swift/iOS diff 0, Git commit/push 0이다. 다음 action은 owner가 119 exact SHA를 승인한 뒤 기존 controlled deployment를 119 apply부터 재개하는 것뿐이다.

## 2026-08-26 Controlled Production Deployment — 119 + Atomic v4 Activation GO

- Owner-approved 119 SHA-256 `0c873e441eed10e68b01fbaaed24b420e84395140fe8eff495f879e87b417df5`를 exact 확인했다. Immutable 118은 SHA `0eb9bfe801fd26bc33c084f5b9921aaf32aa5dc9b9c44a7ebfa17b7a3ccf5fb6` 그대로이며 수정/재적용하지 않았다.
- 첫 write 전 encrypted preimage 두 개를 AES-256-CBC/PBKDF2 read-back했다. Main cipher/plain SHA는 `844fec409490a04c4a14ea0ccdb22da6c130facf806ff27b8be8bd288522e22b` / `22d34b6889f14dcf4de66eeed649be85e981dfcd6290ca10b3954da169c3314d`; legacy taxonomy는 `253a088456b9a34e58bc9a53b55dd38c23fe860dfb1f45e860e08f5a5a00a6f2` / `64c248aeb55692adb362e5db8735c6c22c796b1bb77bdf07eaeaab92fe1dcd39`다. Files/key mode는 0600이고 mappings 3,492, decisions 121, functions 19 logical-key recovery scope를 확인했다.
- 119는 Production ledger `20260826131310 / classification_measurement_policy_checksum_correction`으로 controlled apply됐다. Measurement rows는 63 그대로이고 raw checksum은 `6ad654...` 불변, semantic checksum은 `42d5aa...`로 gate와 일치했다. Policy/final/release gates가 eligible true/blockers empty다.
- Rollback successor `11800000-0000-4000-8000-00000000b001`은 old active bundle 3,492 mappings를 exact clone했다. Source/successor checksum `28a7700805e95d9e643b0cb860770fde8e12acd86057cace879082ff82a307f2`, status validated/inactive, gate PASS다.
- SHA `177b57b242d65a7f5817b0cdf060cec6d99acf9b9539cadd2d3401a7173b13a9` atomic activation artifact가 내부 advisory lock/preimage/gate/full-shadow/Gold/set/comparison/security/history smoke를 통과해 COMMIT했다. Final candidate `11800000-0000-4000-8000-000000000118`이 sole active, old parent는 retired, active mappings 3,509다. Targeted decisions 121/121 null-safe exact, total decisions 5,056 불변이다.
- Production SELECT-only full shadow는 1,608 unique/fingerprint exact, `348 confirmed / 1,113 review_required / 147 not_comparable`; source는 Musinsa `121/266/7`, UNIQLO `227/817/140`, ZARA `0/30/0`이다. Gold 3/3, set 7/7 excluded, structured confirmed/excluded 7/54, UNIQLO typed accessory exclusion 47, invalid/conflict/arbitrary/unverified leaks 0이다. Comparison tshirt↔base-layer BLOCK, sweatshirt↔hoodie ALLOW, homewear cross BLOCK이다.
- RPC/security smoke PASS: isolated non-customer authenticated claim에서 get-runtime은 active 118/E482514 confirmed exact, find-reference는 history backfill이 없어서 expected `target_classification_required`, list-closet은 0 rows였다. Public/internal resolver/promoter/evaluator call chains가 v4/v4/recorder v2를 사용하며 owner/search_path/grants/anon boundary가 contract와 일치한다. Dummy customer write는 만들지 않았다.
- Final stability postflight `2026-08-26T13:28:36.784812Z`: active release count 1, active ID final candidate, mappings 3,509, decisions 5,056, history/current 1,860/1,608, successor validated/gated, all candidate gates PASS다. Product intake/closet/comparison rows는 3/6/0으로 smoke 전후 불변이다. History bulk backfill/delete, Swift/iOS change, Git commit/push는 0이고 rollback은 필요하지 않았다.
- 최종 판정은 `PRODUCTION CLASSIFICATION AUTHORITY DEPLOYMENT = GO`. 남은 것은 별도 iOS Closet/Compare server-authority integration과 app/device validation뿐이다.

## 2026-08-27 iOS Closet/Compare Server-Authority Integration

- Production classification authority v4를 iOS 실제 sourced Closet 등록과 Compare 경로에 연결했다. Parser/adapter raw facts는 `structured_facts`로 전달되고, 앱은 resolve → 필요한 경우 기존 product-observation Edge promoter → runtime 재조회 결과를 최종 authority로 사용한다.
- Authority provenance를 `server_confirmed / user_explicit / local_hint / server_review_required / server_not_comparable / server_unavailable`로 분리했다. Server confirmed tuple이 local hint를 덮고, review/not-comparable/network·promotion failure는 comparison/reference 불가로 fail-closed한다. 실제 사용자 picker/manual 입력만 override가 되며 sourced stale v3와 remote-only automatic row는 active-v4 lazy resolve 전 authority가 아니다.
- 기존 set semantics를 재사용해 `structured_facts.product_structure=set`을 전달한다. sourced/manual/legacy explicit set은 canonical comparison authority와 representative/reference 후보가 될 수 없다.
- Musinsa literal `size_type`, UNIQLO selected hydration product의 verbatim `productTypeKr`, ZARA structured taxonomy facts를 generic payload로 보존·재전달한다. Numeric Musinsa size type을 typed discriminator로 대체하는 경로는 제거했다.
- Compare는 target/reference active-v4 authority와 local/remote tuple·measurement parity를 확인하고 evaluator v4 candidate/begin permit가 ALLOW한 뒤에만 기존 `MeasurementComparisonEngine` scorer를 실행한다. tshirt↔base-layer 및 homewear cross는 block, sweatshirt↔hoodie는 allow로 검증했다. `MeasurementComparisonEngine.swift` scoring/weight diff는 0이다.
- Gold E482514/E454311/E456567 3/3, promotion, set, malformed/network failure, stale authority, manual override, Musinsa/UNIQLO/ZARA, comparison sequencing 및 measurement regression focused suite는 147 total / 144 PASS / 3 explicit live-opt-in SKIP / 0 failure다. Full offline `FitMatchTests`는 517 total / 480 PASS / 37 explicit live-opt-in SKIP / 0 failure다. Debug build-for-testing PASS이며 Release unsigned generic iOS build를 별도로 검증했다.
- 이번 작업의 Production DB migration/schema/data write, classification history bulk write/delete, SwiftData schema migration, Git commit/push는 모두 0이다. 남은 단계는 실제 iPhone에서 Musinsa/UNIQLO/manual/set/network-error Closet 등록과 Compare 사용자 흐름을 검증하는 것뿐이다.

## 2026-08-29 FitMatch vNext Production Database Final Remediation — 82 → 100

### Scope / repository

- Production project/schema: `hnkplvyegonlhumlejst / fitmatch_vnext`.
- Branch was and remains `connectDB`. Start HEAD and end HEAD are both `6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`; commit/push was not performed.
- Existing user files and untracked vNext migrations were preserved. No reset, revert, stash, guessed classification, UNKNOWN availability promotion, legacy schema copy, history rewrite, or unrelated Swift/UI change was performed.
- Production and local vNext migration ledgers now have exact `version_name` parity: 21 local / 21 remote, local-only 0, remote-only 0.

### Applied additive migrations

- `20260829031514_vnext_ingestion_contract.sql`: service-only, idempotent new-product vNext ingestion; immutable receipt provenance; current raw-evidence versioning; raw measurement resolution; verified classification replay; observed availability; readiness/runtime response. It does not call or write legacy FitMatch business authorities.
- `20260829031527_vnext_readiness_policy_metrics.sql`: readiness v2 counts only active CANONICAL metrics in the current active policy, requires explicit unexpired AVAILABLE evidence, and excludes semantic-conflict sizes.
- `20260829031549_vnext_candidate_size_authority.sql`: owner-checked DB-generated eligible size set. UNKNOWN, no-observation, SOLD_OUT, expired/unbounded AVAILABLE, semantic-conflict, insufficient, or unauthorized sizes are excluded.
- `20260829031601_vnext_comparison_begin_provenance.sql`: begin v3 derives the candidate set in DB; a retained client array must exactly equal it. It snapshots candidate measurements/availability fingerprints, product-linked reference identity, classifier/mapping/taxonomy authority, and versioned policy metrics/weights/exclusions.
- `20260829031612_vnext_completion_validation.sql`: completion requires exact authorized ranking/evidence sets and validates size, metric, exclusions, reference/target snapshot values, signed/absolute difference, weight, coverage, recommendation, and retry fingerprint before immutable completion.
- `20260829031622_vnext_reference_candidate_discovery.sql`: target-based DB discovery returns `AUTOMATIC`, `MANUAL_EXTENDED`, `MEASUREMENTS_REQUIRED`, or blocked diagnostics with eligible size IDs and deterministic exclusions/policy provenance.
- `20260829031636_vnext_final_security_regression.sql`: fixed-search-path and least-privilege gate; global ingestion/classification apply is service-only; authenticated users have no direct domain-table write grants.
- `20260829032944_vnext_completion_ingestion_hardening.sql`: explicit `PRODUCT_EXACT`/`PRODUCT_STRUCTURE` input must agree with observed identity/structured facts; fractional rank/reliability values are rejected instead of being rounded by PostgreSQL casts.

### Edge Function cutover

- `supabase/functions/product-observation/index.ts` now verifies the signed-in user, creates the service client only server-side, and calls only `fitmatch_vnext.ingest_product_observation`. Legacy `fitmatch_submit_product_observation` / `fitmatch_process_product_observation` occurrences are 0.
- Production `product-observation` is ACTIVE version 4, `verify_jwt=true`, hash `5cd94356fdd35fef7762416414a57b569834454c7cda73a37a0ff98dcacf8502`. Remote and local `index.ts` are byte-for-byte equal.
- The established iOS DTO is preserved with `processing.status=promoted`; the actual additive vNext state is returned as `processing.vnext_status=processed|ignored_stale`.
- Domain input/constraint errors return 422. Unexpected database errors return a generic 500 and do not expose internal error text. Unauthenticated live POST returned HTTP 401 `UNAUTHORIZED_NO_AUTH_HEADER` on version 4.

### Data status before / after

- Products remain 1,608. Identity duplicates, baseline identity loss, vNext-only extras, orphan variants/sizes/measurements: all 0.
- Classification remains evidence-conservative: `CONFIRMED 203 / REVIEW_REQUIRED 1,308 / NOT_APPLICABLE 97`. Invalid CONFIRMED, missing sleeve/lower/body axis, non-SINGLE CONFIRMED, inactive garment, missing provenance, inactive/unverified mapping use, invalid DIRECT mapping, top-priority conflict, 1,608 replay mismatch, stored-result mismatch: all 0.
- Readiness remains `READY 3 / NO_AVAILABLE_SIZE 198 / NO_MEASUREMENT_DATA 2 / CLASSIFICATION_REQUIRED 1,308 / NOT_APPLICABLE 97`; `MAPPING_REQUIRED 0 / INSUFFICIENT_MEASUREMENTS 0`. False READY and false non-READY are both 0. Current expired/unbounded AVAILABLE rows are 0.
- Golden READY stayed unchanged: Musinsa `6805433 / XS`, UNIQLO `E482856 / 28`, ZARA `561264931 / EU 38 (KR 30)`.
- Source coverage after remediation:
  - Musinsa: total 394, confirmed/potential-ready 68, review 311, not-applicable 15, evidence-ready 1, no-size 236, no-measurement 237, no-available-size 67, mapping-required 0.
  - UNIQLO: total 1,184, confirmed/potential-ready 121, review 981, not-applicable 82, evidence-ready 1, no-size 190, no-measurement 271, no-available-size 120, mapping-required 0.
  - ZARA: total 30, confirmed/potential-ready 14, review 16, not-applicable 0, evidence-ready 1, no-size 0, no-measurement 2, no-available-size 11, mapping-required 0.
- No broad coverage backfill was performed. The isolated ingestion, Golden comparison, failure, and concurrency fixtures were rolled back or deleted by exact generated IDs. Final test pollution: product 0, receipt 0, comparison 0, concurrency closet item/measurement 0.

### Verification results

- PASS — `supabase/sql/121_vnext_final_remediation_tests.sql` executed unchanged in Production. One transaction covered not-present→vNext ingest→identity/variant/size/raw measurement/signal/availability→CONFIRMED→READY→runtime, identical retry idempotency, legacy observation count unchanged, and spoofed exact/structure rejection; the transaction rolled back.
- PASS — the same regression executed the full Musinsa/UNIQLO/ZARA path: READY→product-linked closet→atomic reference→reference discovery→DB candidate set→begin v3→validated completion→idempotent retry→immutable history. Fixture/provider count 3/3.
- PASS — candidate negatives: no observation, UNKNOWN, SOLD_OUT, expired AVAILABLE, client set mismatch, wrong hierarchy, unauthorized recommendation, and unavailable size recommendation are blocked.
- PASS — completion negatives: `[{}]`, duplicate rank, duplicate metric evidence, wrong policy weight, reference/target snapshot mismatch, excluded metric, unauthorized size, fractional rank/reliability, and conflicting retry are blocked. Valid completion requires recommendation/label/score/reliability/coverage/engine/ranking/evidence/completed_at.
- PASS — automatic long/short mismatch blocks; manual without explicit selection blocks; explicit permitted mismatch returns `MANUAL_EXTENDED`; `total_length`/`hem_width` exclusions are deterministic and excluded evidence is rejected.
- PASS — current raw measurement resolver replay 28,514/28,514 with mismatch 0; usable semantic conflict 0; active alias top-priority conflict 0; width/circumference representation errors 0.
- PASS — policy boundary matrix 19/19: TOP, OUTER, and BOTTOM minimum/required-any cases match the contract.
- PASS — anonymous runtime/comparison and authenticated global ingestion are blocked; cross-user closet/candidate/completion access is blocked; broad authenticated table writes 0; selected user-facing SECURITY DEFINER functions all use fixed `search_path`; sensitive RLS disabled count 0.
- PASS — actual two-session concurrent `set_closet_reference` race. Session A held the scope advisory lock while session B attempted replacement; both calls completed, exactly one of two same-scope rows was reference, and all exact fixture rows were removed afterward.
- PASS — completed immutability trigger, completion payload trigger, immutable ingestion receipt trigger, ingestion fact trigger, atomic reference partial unique index, and client idempotency unique constraints are present.
- PASS — selected vNext core function definitions contain zero `fitmatch_catalog.` or `public.fitmatch_*` business references. Edge source contains zero legacy observation RPC references.
- PASS — Supabase advisors after DDL: `fitmatch_vnext` security WARN/ERROR 0 and performance WARN/ERROR 0. Security INFO has four intentional RLS-no-policy service-only/internal tables; performance INFO has 18 unindexed-FK and 11 unused-index observations, retained until representative workload evidence exists.
- PASS — post-verification PostgreSQL log sample from `2026-08-29T03:42:14Z` onward contained ERROR/FATAL/PANIC 0. Earlier ERROR entries were intentional negative fixtures or corrected audit-development probes.
- NOT RUN — authenticated positive HTTP invocation of the Edge Function, because no signed fixture-user JWT was available and creating a Production Auth user would violate the no-pollution boundary. The exact underlying service RPC positive path passed, deployed source equals local, JWT enforcement and unauthenticated transport passed. Exercise the authenticated transport in the next signed-in Swift/iPhone E2E.
- NOT RUN — Swift build/unit tests and physical iPhone E2E; no Swift source was changed in this DB remediation.
- FAIL — 0.

### Final READ-ONLY audit

- `supabase/sql/122_vnext_final_read_only_audit.sql` ran against actual Production rows and returned `score=100/100`, `p0_count=0`, `verdict=VNext PRE-E2E READY`.
- All 20 independent 5-point contract gates were true: identity; hierarchy; classification tuple/axis/provenance/mapping/replay; measurement determinism/semantic separation; strict readiness; Golden readiness; 19/19 policy matrix; runtime capabilities; service-only ingestion; RLS/grants/search path; legacy independence; immutable completion; ingestion protection; atomic reference; migration parity; fixture cleanliness.

### Remaining work / Swift Production Integration

- These are not remaining DB P0s. Coverage stays intentionally low until verified retailer evidence is ingested; never convert REVIEW/UNKNOWN by heuristic merely to raise counts.
- Swift should call the authenticated `product-observation` Edge boundary for new/changed retailer facts, then consume the vNext runtime response. It must accept the compatibility `promoted` status and may record `vnext_status` as provenance.
- Swift must use DB `find_reference_candidates`, DB-generated eligible candidate IDs from begin, and DB authorization mode/exclusions. It must not reconstruct garment/axis/availability compatibility or silently filter candidate sizes locally.
- Completion must submit every authorized candidate exactly once and the exact per-candidate comparison measurements captured by begin, with policy snapshot weights and derived coverage. A stale or locally altered snapshot must surface as a conflict and restart, not be forced through.
- Next gate: signed-in Swift Production Integration followed by real iPhone E2E for each provider plus new-product observation. The database is ready for that phase; the physical E2E itself has not been claimed here.

## 2026-08-29 vNext ingress PostgREST transport correction — superseding closeout verdict

- A live anonymous PostgREST schema probe after Edge v4 deployment returned HTTP 406 / `PGRST106`: Production exposes only `public` and `graphql_public`, not `fitmatch_vnext`. Therefore `adminClient.schema("fitmatch_vnext").rpc("ingest_product_observation", ...)` cannot reach the internal function even with a service-role client. The preceding DB-only `100/100` audit remains valid, but the overall ingress closeout verdict above is superseded.
- Production preflight confirmed the internal function exists, service-role EXECUTE is true, anon/authenticated EXECUTE are false, and no public vNext ingestion bridge currently exists. Edge Function v4 remains ACTIVE with `verify_jwt=true`, but its positive authenticated path is not operationally proven and is expected to fail at PostgREST schema selection.
- Prepared but did not apply `supabase/migrations/20260829040000_vnext_ingestion_postgrest_bridge.sql`. It adds one fixed-search-path SECURITY DEFINER function in the already exposed `public` schema, revokes public/anon/authenticated EXECUTE, grants only service_role, checks `auth.jwt().role=service_role`, and delegates directly to `fitmatch_vnext.ingest_product_observation`. It contains no classifier, mapping, or ingestion logic of its own.
- Updated the repository Edge source to call `public.fitmatch_vnext_ingest_product_observation` through the default public RPC boundary. This local source is intentionally not deployed until the bridge migration is approved and applied; Production remains on v4.
- Disposable local PostgreSQL `17.11 (Homebrew)`, socket directory `/tmp/FitMatchVNextBridgePG17-20260829-1259`, port `55439`: migration compile PASS, service_role execute true, anon/authenticated execute false, actual wrapper delegation PASS, reapply PASS with exactly one overload. The cluster was stopped and deleted.
- The Production migration attempt was rejected before execution because this exact persistent SECURITY DEFINER/grant change needs explicit owner approval. Production bridge DDL/data write count for this correction is 0. No migration-ledger row, product, receipt, history, closet, or comparison row changed.
- Current overall verdict: `VNext PRE-E2E NOT READY`; mandatory P0 = 1 (`product-observation` cannot yet traverse PostgREST to the internal vNext ingestion authority). The DB read-only contract sub-audit remains `100/100, P0=0`, but it is not the final ingress score.
- Exact next action: owner explicitly approves applying `20260829040000_vnext_ingestion_postgrest_bridge.sql` to Production and then deploying the prepared `product-observation` source. Afterward run the no-auth/invalid-JWT checks, an authenticated positive ingress probe, idempotency/fail-closed verification, and rerun `122_vnext_final_read_only_audit.sql`.

## 2026-08-29 vNext ingress bridge activated — current final closeout state

- This section supersedes the preceding transport-correction deployment state. The additive bridge was applied to Production as ledger row `20260829043247 / vnext_ingestion_postgrest_bridge`; the repository file was renamed to the exact ledger identity `supabase/migrations/20260829043247_vnext_ingestion_postgrest_bridge.sql`. SQL SHA-256 is `4302072e83423bca71fc6fa091860cab803c22f6c6ada8bee45cd75d1200e769`.
- `public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)` is owned by `postgres`, SECURITY DEFINER with `search_path=""`, delegates only to `fitmatch_vnext.ingest_product_observation`, and contains no legacy observation reference. EXECUTE is service_role=true and anon/authenticated=false. An actual anon PostgREST call reached the exposed public RPC and returned HTTP 401 / PostgreSQL `42501 permission denied`, proving that the former `PGRST106` schema-transport gap is closed without exposing ingestion to clients.
- Production `product-observation` is ACTIVE version 5 with `verify_jwt=true`, bundle SHA-256 `4d99d44634bd9bebd15a87e1fbdfb5ecea8a27eea972019c88d706c40280fce9`. Remote `index.ts` is byte-for-byte equal to repository source SHA-256 `93ea79a8cffc064d1886d2f0d7be723af594cf5ba0097e432adba8a56afffeb3`. It calls the public service-only bridge exactly once, custom-schema calls are 0, and legacy submit/process RPC calls are 0.
- Live transport negatives on version 5 PASS: missing Authorization returned HTTP 401 `UNAUTHORIZED_NO_AUTH_HEADER`; malformed JWT returned HTTP 401 `UNAUTHORIZED_INVALID_JWT_FORMAT`. Service-role secret is neither returned nor logged; the handler logs only unexpected database error codes. Actor provenance is still derived exclusively from `auth.getUser().user.id`, never from request payload.
- The final Production READ-ONLY audit reran at `2026-08-29T04:39:03.284593Z` and returned DB score `100/100`, `p0_count=0`, verdict `VNext PRE-E2E READY`, policy gates 19/19, products 1,608, classifications 203/1,308/97, deterministic replay mismatches 0, invalid confirmed 0, false READY/non-READY 0/0, Golden READY 3/3, identity/orphan issues 0, and selected legacy business references 0. Postflight still has products 1,608, ingestion receipts 0, classifications 203/1,308/97, synthetic anonymous users 0.
- Production and repository vNext migration order are now exact 22/22, local-only 0, remote-only 0. Local and remote `connectDB` both remain at HEAD `6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`; the required source is preserved only in the local working tree until the owner commits/pushes it.
- Supabase advisors after the bridge: bridge-specific security/performance findings 0; security has no ERROR and 14 pre-existing WARNs outside the bridge, performance has INFO-only findings. The bridge did not add a table, RLS policy, index, classifier, or business authority.
- NOT RUN — a valid-user positive HTTP call through Edge v5. No reusable signed fixture JWT exists in the repository. A proposed ephemeral Production Auth identity plus stale-receipt-only Golden probe and exact cleanup was rejected before execution because that account lifecycle and Production receipt write/delete require explicit owner authorization. It created no user, receipt, product, history, closet, or comparison row. Do not describe authenticated positive ingress, Edge-level idempotency, or Edge-level Golden success as PASS until that exact probe or a user-supplied existing valid JWT is used.
- Current overall closeout verdict is therefore `VNext PRE-E2E NOT READY` despite the DB contract sub-audit being `100/100, P0=0`: one mandatory verification gate remains, not a known schema/data correctness defect. Exact safe next action is either (a) owner supplies a short-lived existing-user JWT for read/write-safe stale-observation probes, or (b) owner explicitly authorizes creation of one anonymous audit user, three `IGNORED_STALE` Golden receipts, repeated Edge calls, exact receipt deletion, and immediate account deletion. After cleanup, rerun the READ-ONLY audit and only then issue the final 100/100 closeout.

## 2026-08-29 authenticated Edge v5 probe — Auth provider blocker

- Owner explicitly authorized one Production anonymous audit user, three Golden `IGNORED_STALE` receipts, two identical Edge calls per Golden, exact receipt-ID deletion, immediate audit-user deletion, and final READ-ONLY pollution verification.
- Preflight fixed the complete relevant state: products 1,608; variants 2,656; sizes 6,771; raw measurements 28,514; availability rows 15; product/source signals 4,393/2,434; receipts 0; anonymous Auth users 0; closet/closet measurements/comparisons 6/24/0; classifications 203/1,308/97; Golden READY 3/3. Stable full-row hashes were recorded for all product, variant, size, measurement, availability, and classification-signal tables.
- The approved probe stopped at its first operation. `POST /auth/v1/signup` with an anonymous signup payload returned HTTP 422 `anonymous_provider_disabled`. No audit user or token was created, so Edge v5 and vNext ingestion were not called, and no receipt existed to delete. The sole failure cause is the Production Auth configuration: Anonymous Sign-Ins are disabled.
- No workaround or broader Auth change was made. In particular, no real-user credential was accessed, no email user was substituted, no manual `auth.users` row/session/JWT was created, and Anonymous Sign-Ins were not enabled without authorization.
- Immediate READ-ONLY postflight proved receipts 0, anonymous Auth users 0, all seven preflight table hashes unchanged, products/variants/sizes/measurements/availability/signals unchanged, legacy observations/submissions 6/6, closets/measurements/comparisons unchanged, classifications 203/1,308/97, and Golden READY 3/3.
- The full final READ-ONLY audit reran at `2026-08-29T05:07:00.191889Z`: score 100/100, DB `p0_count=0`, 19/19 policy boundaries, confirmed invalid 0, deterministic replay/store mismatch 0, duplicate/orphan/parity errors 0, false readiness 0, fixture pollution 0, selected legacy business references 0.
- Overall closeout remains `VNext PRE-E2E NOT READY` solely because the mandatory authenticated positive transport probe is still unexecuted. The one minimal required user action is to temporarily enable **Allow anonymous sign-ins** for project `hnkplvyegonlhumlejst` and report that it is enabled. Then rerun the already-approved exact probe immediately, delete its exact receipts/user, complete postflight, and stop; do not start another DB phase.

## 2026-08-29 authenticated Edge v5 probe — admin-user execution boundary

- Owner rejected enabling Anonymous Sign-Ins and instead authorized exactly one temporary email/password audit user created through the Supabase server-side Admin API, email-confirmed, followed by ordinary password sign-in, the already-scoped Golden stale/idempotency probe, exact receipt deletion, and exact Auth-user deletion.
- The current execution environment exposes database migration/SQL/Edge deployment/read tools but no Auth Admin create-user tool or secret-key retrieval. No service-role credential exists in the local process environment, no matching server credential is stored in project Vault, no Supabase CLI authentication context is present, and no signed-in Dashboard browser is connected. The deployed `delete-account` boundary can delete a signed-in user but cannot bootstrap one.
- No unsafe substitute was used: Anonymous Sign-Ins remained disabled; public signup was not used; `auth.users`/`auth.identities`/sessions were not inserted directly; no JWT was minted; no service-role token was used as a user token; no temporary public bootstrap Edge endpoint was deployed; no existing user credential was accessed.
- Therefore the approved Admin API creation step could not start and no audit user, receipt, Edge call, or database change occurred. This is an execution-environment credential boundary, not a newly observed vNext DB or Edge correctness failure. The most limited safe next action is for the owner to connect a signed-in Supabase Dashboard browser session for project `hnkplvyegonlhumlejst`; the audit password can then be generated and retained only in the in-memory browser/test session while Dashboard invokes the Admin API.

## 2026-08-29 Swift ↔ vNext production integration implementation

- Branch and HEAD remained `connectDB / 6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`; commit, push, reset, revert, and stash were not performed. Existing vNext migrations, reports, Edge source, and user worktree changes were preserved.
- Phase 0 was implemented as the additive repository migration `20260829050000_vnext_swift_user_contract.sql`. It adds only nullable user-owned `closet_items.satisfaction` plus its 1...5 CHECK; no new table, global Product mutation, classification/mapping/release write, history rewrite, or SwiftData schema change exists. The final CHECK creation is idempotent and avoids drop/re-add locking on migration reapply.
- The Phase 0 internal contracts are vNext-only edit, soft-delete, reference unset, personal classification override/clear, enriched list, Swift runtime projection, and immutable history projection. Public Data API bridges are thin `SECURITY INVOKER` delegates. All mutating internal functions use fixed `search_path`, `auth.uid()`, exact row ownership checks, and least-privilege grants. Product-linked personal edits cannot rewrite global Product classification.
- Swift now has exact vNext DTOs for runtime, closet, reference candidates, authorization, eligible size set, begin snapshot, completion, and immutable history. Sourced observation uses Edge v5; release code contains zero `fitmatch_submit_product_observation` or `fitmatch_process_product_observation` calls. Garment type and sleeve/lower/body axes remain separate and unknown enum/state values fail closed.
- Sourced comparison now follows candidate discovery → authorization → exact eligible size set → begin snapshot → vNext adapter → full candidate completion → local immutable-cache hydration. The adapter scores exactly the AVAILABLE, server-authorized candidate IDs using begin-snapshot metric inclusion/exclusion and DB weights. `REVIEW_REQUIRED`, `NOT_APPLICABLE`, blocked compatibility, a missing begin snapshot, unauthorized size, or base-layer/tshirt mismatch invokes no sourced scorer.
- A final local `RecommendationHistory` is created only after successful server completion. Sync no longer begins/uploads a locally scored history; it recovers only server PENDING rows and hydrates COMPLETED immutable history without current-state recomputation. Legacy local history remains offline-readable but is never promoted to vNext authority.
- “다른 옷과 비교” preserves the current target and creates/completes a new server comparison for the selected reference without reparsing. “다른 사이즈와 비교” is presentation-only over the stored authorized batch, creates no comparison/history, and cannot score a Product size outside that batch.
- Product-linked closet save resolves an exact Product/variant/size identity, calls vNext upsert, then hydrates from vNext list. Reference set/unset refreshes the authoritative list atomically. Manual closet remains a personal tuple path. The first-sync cache cannot unset a remote reference merely because the local cache began empty.
- Per-size observation evidence is transient and provider-fact-only. Explicit size evidence is preserved; absent evidence remains `UNKNOWN`, and product-level verified status is applied only to the explicitly checked size rather than every parsed size.
- PostgreSQL 17.11 disposable validation after the final constraint cleanup PASS: fixture → migration first apply → transaction ownership/runtime tests → ROLLBACK → migration reapply → the same tests → ROLLBACK. Cross-user edit/unset/override/delete were denied; global Product hash was unchanged; post-rollback counts were closet/measurements/comparisons `0/0/0`, public bridges 15, new internal functions 7. Cluster `/tmp/FitMatchVNextSwiftPG17.HQlAod`, port 55441, was stopped and deleted.
- Swift simulator validation earlier in this implementation PASSed app and test-target builds plus five focused suites (`FitMatchVNextContractTests`, comparison sync, permit sequencing, closet sync, server-authority integration): 54 tests, 0 failures. After the last exact-variant and Swift isolation annotations, all 18 changed/new Swift files PASSed `swiftc -frontend -parse`; however repeated `xcodebuild`/XcodeBuildMCP compile attempts stopped producing output and were terminated, so a final post-tweak type-check/test rerun is explicitly NOT RUN rather than PASS.
- Final static gates PASS: `git diff --check`; protected TabBar modifier diff 0; protected tab/scroll symbol diff 0; SwiftData schema diff 0; Share Extension diff 0; release Swift/Edge legacy observation RPC references 0. No UI/navigation redesign was made.
- Production remained SELECT-only for this implementation. Postflight is unchanged at products 1,608, classifications `CONFIRMED 203 / REVIEW_REQUIRED 1,308 / NOT_APPLICABLE 97`, confirmed invalid/required-axis-missing/non-SINGLE `0/0/0`, duplicate Product/variant orphan/size orphan/measurement orphan `0/0/0/0`, readiness `READY 3 / NO_AVAILABLE_SIZE 198 / NO_MEASUREMENT_DATA 2 / CLASSIFICATION_REQUIRED 1,308 / NOT_APPLICABLE 97`, Golden READY 3/3. Edge `product-observation` is still ACTIVE v5, `verify_jwt=true`, its repository and deployed `index.ts` are exact byte matches, bridge reference is present, and legacy submit/process references are 0.
- Migration `20260829050000_vnext_swift_user_contract` is deliberately absent from the Production ledger. Production `closet_items.satisfaction` and `public.fitmatch_vnext_update_closet_item(uuid,jsonb)` are absent. An attempted persistent migration call was rejected before execution by the production safety approval boundary; no DDL or data write occurred and it was not retried or bypassed.
- Current verdict: `SWIFT VNEXT PRE-E2E NOT READY`. The one known functional P0 is that the new Swift release path depends on the repository-only vNext user bridges, which are not deployed in Production. Additional mandatory verification gates are the post-tweak simulator build/test rerun and signed-in real iPhone MUSINSA/UNIQLO/ZARA/manual/offline UX E2E; neither is claimed as PASS.
- Exact next action: obtain explicit owner approval for applying only `20260829050000_vnext_swift_user_contract.sql`, run its production structural/security postflight, then rerun the focused Swift suites when Xcode responds and proceed to signed-in iPhone E2E. Do not start a new DB authority phase or reintroduce legacy fallback.

## 2026-08-29 Swift vNext final Xcode verification — superseding validation state

- Validation-only work ran on `connectDB` at the exact expected HEAD `6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`. All existing tracked/untracked user changes were preserved; no reset, restore, stash, clean, commit, push, formatting, Swift/SQL/Edge production-source edit, Production DB operation, migration apply, or Edge deployment occurred.
- The first XcodeBuildMCP build request stopped returning output. Process inspection showed no active `xcodebuild`, `XCBBuildService`, or Swift compiler, so that one request was terminated and not retried indefinitely. The permitted alternate direct-Xcode path then completed; this supersedes the prior post-tweak `NOT RUN` state.
- Xcode 26.3 (`17C529`), project `FitMatch.xcodeproj`, scheme `FitMatch`, Debug, existing iPhone 17 Pro simulator `03BAF093-552E-4E53-ABFB-7DE0653BE676`, iOS 26.3.1 (`23D8133`), x86_64: app `build` PASS (`** BUILD SUCCEEDED **`) and `build-for-testing` PASS (`** TEST BUILD SUCCEEDED **`). Build products include `FitMatch.app`, embedded `FitMatchTests.xctest`, and `FitMatchUITests-Runner.app`.
- Actual simulator focused tests PASS 76 / FAIL 0 / SKIP 0. Suites: `FitMatchVNextContractTests` 5/5, `FitMatchComparisonSyncCoordinatorTests` 3/3, `FitMatchComparisonPermitSequencingTests` 4/4, `FitMatchClosetSyncCoordinatorTests` 19/19, `FitMatchServerAuthorityIntegrationTests` 23/23, and `FitMatchSupabaseProductResolverTests` 22/22. xcresult summaries independently report 54/54 and 22/22 passed.
- Authority invariants PASS: scorer-before-authorization 0; scorer-before-begin 0; unauthorized candidate/size scoring 0; excluded metric use 0; BLOCKED/REVIEW_REQUIRED/NOT_APPLICABLE scorer calls 0. Alternate-item flow reuses the target and performs server candidate authorization → eligible set → begin → scorer → complete → new local cache. Alternate-size flow is presentation-only over the stored authorized batch, with parser/authorization/comparison/history creation 0. Pending history recovery starts only from immutable server begin snapshots and local history is never promoted to authority.
- Release Swift/Edge references to `fitmatch_submit_product_observation`, `fitmatch_process_product_observation`, `fitmatch_resolve_product`, and `fitmatch_get_product_runtime` are all 0. Local classification/matcher symbols remain only as parser/manual/presentation/DEBUG support and do not override sourced server authority; the focused release-call-site tests passed.
- Final protected checks PASS: `git diff --check`; protected TabBar modifier diff 0; protected tab/scroll symbol diff 0; SwiftData schema/entity/container diff 0; navigation-structure addition diff 0; Share Extension diff 0.
- Current verdict for this task: `FINAL XCODE VALIDATION PASS`. No new compile/test blocker exists. The known functional P0 remains unchanged: `20260829050000_vnext_swift_user_contract.sql` is repository-only and deliberately not applied to Production. Signed-in physical iPhone E2E remains unexecuted and is not claimed as PASS.
- Exact next action: explicit owner approval and Production application of only `supabase/migrations/20260829050000_vnext_swift_user_contract.sql`, followed by security/data postflight; then proceed to signed-in real iPhone E2E. Do not start another DB authority phase.
- Detailed evidence is preserved in `Docs/FitMatchSwiftVNextFinalXcodeVerification-20260829.txt` and its companion ZIP.

## 2026-08-29 Production vNext Swift user contract activation — current state

- Owner approved applying only repository SQL `supabase/migrations/20260829050000_vnext_swift_user_contract.sql`. Preflight ran on `connectDB` at HEAD `6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`; the existing dirty worktree was preserved. The source was reread in full, destructive/global-authority DML was absent, prerequisites were complete, file length was 32,195 bytes, and SHA-256 was `ad23bad212999c882b114c50b95ad7df7b95f275e0aadf8b0a7a7f37daa0dbd6`.
- Production preflight at `2026-08-29T11:08:18.191303Z`: target migration rows 0; `satisfaction`/check/15 target public bridges absent; missing prerequisite tables/functions 0; Products 1,608; classifications `CONFIRMED 203 / REVIEW_REQUIRED 1,308 / NOT_APPLICABLE 97`; invalid CONFIRMED 0; readiness `READY 3 / NO_AVAILABLE_SIZE 198 / NO_MEASUREMENT_DATA 2 / CLASSIFICATION_REQUIRED 1,308 / NOT_APPLICABLE 97`; Golden READY 3/3; duplicate Product and variant/size/measurement orphans 0. Counts were variants 2,656, sizes 6,771, raw measurements 28,514, closet/closet measurements/comparisons 6/24/0. Stable hashes were products `82c444272cba8f273ea7d14077f1b55e`, variants `b9cc1a677fa6b49dc58ac22f8f21b6af`, sizes `e8744393f6a28260b7726ad3137f626a`, measurements `a6762986ee86739f1ff022203f4ba4ba`, classification `29510033fad4e32d2350959d00f68ead`.
- The exact approved SQL applied atomically and no other SQL/migration was applied. However, the Supabase MCP migration API accepts name + SQL but no caller-supplied version, so it recorded the row as `20260829110853 / vnext_swift_user_contract`, not repository version `20260829050000`. The name exists exactly once, the exact requested version exists zero times, and it is the sole ledger row after prior tail `20260829043247`. No ledger repair, manual fake marking, duplicate apply, migration edit/rename, or additional migration was attempted.
- Structural/security postflight PASS: nullable `satisfaction smallint` and validated 1...5 CHECK; existing non-null values 0; internal functions 9/9; public Swift bridges 15/15; JSONB signatures; all 24 fixed `search_path`; internal SECURITY DEFINER/public SECURITY INVOKER split; anon EXECUTE 0; authenticated/service_role intended EXECUTE 24/24; authenticated protected-table write grants 0; `closet_items` RLS and own-row SELECT policy unchanged; target mutation functions contain global Product DML references 0.
- The first runtime validation statement was rejected by the PostgreSQL parser before transaction execution because the probe used reserved local variable name `authorization`; it performed no writes. The exact same probe with only the test variable renamed to `authorization_value` PASSed and ended in ROLLBACK.
- Successful Production rollback test PASS: manual and product-linked closet upsert, repeated-call idempotency, edit, satisfaction, personal override set/clear, reference set/unset, soft delete, list/hydration, exact Product/variant/size plus category/garment/axis fields, and global Product non-mutation. Cross-user edit/delete/reference-unset/override were blocked 4/4 and anon bridge execution was blocked. Golden Musinsa rollback comparison passed public find → authorize → eligible sizes → begin immutable snapshot → complete → immutable history projection.
- Final postflight at `2026-08-29T11:16:10.447991Z`: Products 1,608; classifications 203/1,308/97; invalid CONFIRMED 0; required axes missing 0; deterministic replay mismatch 0; readiness unchanged; Golden READY 3/3; duplicates/orphans 0; counts 2,656/6,771/28,514 and closet/measurements/comparisons 6/24/0. All five hashes match preflight exactly. Named closet fixture, comparison-engine fixture, and non-null satisfaction pollution are 0.
- Supabase advisors found migration-target-related security/performance findings 0. Project-wide security remains INFO 51/WARN 14 unrelated to this migration; performance remains INFO-only 115, target-related 0. No advisor-driven remediation was made.
- Current strict verdict: `SWIFT VNEXT IMPLEMENTATION DB CONTRACT NOT READY`. The deployed functional/security/data contract itself passed; the sole failed user-mandated gate is repository/Production ledger version parity (`20260829050000` vs `20260829110853`). Resolving it requires a new explicit owner decision because every possible ledger repair/rename/reapply/additional migration action was prohibited in this task. Do not advance to the independent PRE-E2E audit while claiming exact ledger parity.
- Full evidence is in `Docs/FitMatchVNextProductionUserContractActivation-20260829.txt` and its companion ZIP.

## 2026-08-29 Codex Ultra independent PRE-E2E audit — current verdict

- This section supersedes the preceding activation handoff's instruction not to begin the independent audit: the owner explicitly requested and this turn completed that audit. Branch/HEAD remained `connectDB / 6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`; the existing dirty tree was preserved. Production writes, migrations, Edge deploys, Swift fixes, expectation changes, commits, and pushes were all 0.
- Final overall verdict is `FITMATCH PRE-E2E NO-GO`, readiness `82/100`, with `P0 3 / P1 8 / P2 3`. The Production DB sub-audit itself remains `100/100, DB P0=0`; the NO-GO is caused by three independently confirmed Swift release-path contracts, not by reopened DB remediation.
- P0-1: `RecommendationHistoryStore.saveUnique` applies legacy URL/code/name and size-label dedupe after a successful vNext completion. It can replace exact server Product/ProductSize UUIDs, remove distinct same-target server comparison caches, and break Other Size's authorized-ID intersection. Fix only the server-vNext persistence branch: exact UUID reuse, exact comparison-ID dedupe, no label fallback, no deletion of other immutable comparisons.
- P0-2: a soft-deleted reference retained in immutable server comparison history is rebuilt by `VNextHistoryCacheHydrator.makeReference` as an ordinary active `UserFit`. `MyClosetView` queries all UserFit rows with no history-only/deleted marker, so the deleted item deterministically reappears in the active Closet. Preserve historical evidence using a history-only representation/tombstone excluded from Closet, picker, and sync.
- P0-3: `FitMatchClosetSyncCoordinator.synchronizeReferenceAuthority` sends `set(true)` only for the first local reference and sends `unset(false)` only when no local references remain. With different-type A/B references, local A=false/B=true never sends A's unset and the authoritative refresh restores A=true. Diff exact clientItemID reference state and send every changed set/unset while retaining first-login empty-cache protection.
- Production READ-ONLY audit at `2026-08-29T12:19:56.872017Z`: products 1,608; classifications `CONFIRMED 203 / REVIEW_REQUIRED 1,308 / NOT_APPLICABLE 97`; confirmed invalid/axis missing/non-SINGLE 0; deterministic replay/store mismatch 0; duplicate Product and variant/size/measurement orphans 0; readiness `READY 3 / NO_AVAILABLE_SIZE 198 / NO_MEASUREMENT_DATA 2 / CLASSIFICATION_REQUIRED 1,308 / NOT_APPLICABLE 97`; Golden READY 3/3; 19/19 policy boundaries PASS; fixture pollution 0.
- Deployed `product-observation` is ACTIVE v5 with `verify_jwt=true`; deployed/local `index.ts` are byte-exact. Missing and malformed JWT HTTP probes returned 401, actor identity is derived from `auth.getUser()`, service key exposure was not found, legacy submit/process calls are 0, and the vNext bridge is used. A valid ordinary-user positive transport call was NOT RUN because no audit-user JWT was available; do not claim it PASS before physical E2E.
- Production user-contract structure independently matches the repository SQL: satisfaction CHECK, public bridges 15/15, internal functions 9/9, fixed search paths, intended grants/RLS, and no broad protected-table user writes. Fresh Production mutation/negative fixtures were NOT RUN in this read-only audit; ownership denial was verified structurally.
- Fresh Xcode 26.3 validation on iPhone 17 Pro simulator iOS 26.3.1: app build PASS, test-target build PASS, critical focused tests 76 PASS / 0 FAIL / 0 SKIP. Full FitMatchTests was `492 PASS / 1 FAIL / 37 SKIP`; the sole test is the known legacy/local adjudication corpus with 64 assertion mismatches, not sourced vNext authority. Scheme-wide was `496 PASS / 11 FAIL / 43 SKIP`; the ten UI failures were independently traced to eight stale copy assertions, one obsolete pre-vNext authority expectation, and one random test-user/cache-owner harness defect. They are not hidden as PASS and later UI steps remain NOT VERIFIED.
- Migration ledger mismatch is P1, not P0: Production stores `20260829110853 / vnext_swift_user_contract`, while the repo filename is `20260829050000`; stored SQL and repo SQL are exact 32,195-byte/SHA-256 `ad23bad212999c882b114c50b95ad7df7b95f275e0aadf8b0a7a7f37daa0dbd6` matches and applied once. Future CLI tooling can still treat the repo version as pending. No ledger repair/fake marking/reapply was performed.
- Repository reproducibility is P1: `origin/connectDB` equals the current commit, but the current vNext migrations are untracked/absent remotely and the remote Edge source is legacy while the local/deployed source is v5. Publishing is operationally required after review but is not current Production correctness.
- Protected checks remain PASS: `git diff --check`; TabBar modifier and protected call-site diffs 0; SwiftData schema/container destructive diff 0; navigation structure diff 0; Share Extension diff 0.
- Detailed evidence is `Docs/FitMatchCodexUltraIndependentPreE2EAudit-20260829.txt` and its companion ZIP. Do not reopen old DB phases. The exact next work is limited to the three P0 roots and their stated targeted regressions, then rerun the critical 76 suites and this audit. Only after overall P0=0 proceed to physical signed-in iPhone E2E.

## 2026-08-29 Swift final three-P0 remediation — ready for independent re-audit

- Branch/HEAD remained `connectDB / 6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`; the dirty worktree was preserved. Reset/restore/stash/clean, commit/push, Production DB write/migration, DB/Edge edit/deploy, scorer/policy change, and protected navigation/TabBar/Share work were all 0.
- P0-1 was reproduced before the fix: the two new exact-history regressions failed 0/2 because legacy URL/code/name and size-label dedupe replaced server UUIDs and collapsed two same-target comparisons. `RecommendationHistoryStore.saveCompletedVNext` now provides an explicit schema-v2 server-completed branch using exact Product UUID, ProductSize UUID, and immutable comparison/history UUID only. URL/code/name/label fallback and same-product history deletion remain confined to unchanged legacy/manual `saveUnique`. Release vNext call sites use the exact branch only after successful server completion.
- P0-2 was reproduced before the fix: a history-created reference entered Closet upsert and USER_EXPLICIT/USER_EDITED/RETAILER_SNAPSHOT snapshots remained ordinary active UserFit rows. Missing immutable-history references now use reserved existing-field identity `fitmatch_vnext_history_reference_snapshot`; computed `isActiveClosetItem` excludes them from every active Closet/picker surface, authority snapshots, task revisions, and closet mutations while History still retains the reference. No SwiftData stored property/entity/version or migration was added. If the exact UUID is genuinely active remotely, final authoritative hydration may reactivate it; a soft-deleted/absent remote row remains history-only.
- P0-3 was reproduced before the fix: exact A unset and inverse A set failed. Reference synchronization now computes exact clientItemID deltas: false→true set, true→false unset, unchanged no mutation. It refreshes after sets so DB same-tuple atomic replacement remains authoritative, and ignores remote-only rows as unset intent so first-login empty-cache hydration cannot clear remote references.
- Cross-P0 regression retains two exact A/B histories and authorized ProductSize UUIDs, keeps deleted A history-readable but inactive, keeps B active, sends no A upsert/reference mutation on repeated sync, and preserves the remote tombstone in the lifecycle stub. Exact history-ID replay is idempotent.
- Xcode 26.3 on the existing iPhone 17 Pro simulator iOS 26.3.1: app build PASS and test-target build-for-testing PASS. Final critical suites are 86 PASS / 0 FAIL / 0 SKIP: P0 regression 4, vNext contract 5, comparison sync 4, permit sequencing 4, closet sync 24, server-authority integration 23, Supabase resolver 22.
- Full `FitMatchTests` is 502 PASS / 1 FAIL / 37 SKIP (540 total). The only failure remains the unchanged legacy `DBLogicReliabilityAuditTests/testDBLogicAdjudicationMatchesProductionClassifier` mismatch for MUSINSA 5049615 (`sleeveless` vs expected `blouse`); no expected values were changed and no new failure was added.
- Best-effort UI run is 4 PASS / 10 FAIL / 6 SKIP, exactly the prior Ultra baseline count. The ten failures remain the recorded stale onboarding/copy/pre-vNext/cache-owner harness debt; they were not fixed or hidden, and stopped downstream UI steps remain NOT VERIFIED.
- Final invariant audit: scorer-before-authorization/begin, unauthorized/excluded/BLOCKED/REVIEW_REQUIRED/NOT_APPLICABLE scoring, complete-before-history violation, vNext size-label fallback, history-only Closet mutation, first-login reference clearing, and release legacy submit/process/resolve/runtime RPC references are all 0. `git diff --check` PASS; protected TabBar modifier/call-site, navigation, Share Extension, task DB/Edge, and SwiftData stored-schema diffs are 0.
- Current remediation verdict is `SWIFT P0 REMEDIATION READY FOR ULTRA RE-AUDIT`; remaining P0 from the three audited findings is 0, subject to the required independent audit rerun. Ultra P1/P2 findings remain unchanged and were not remediated. Full evidence is `Docs/FitMatchFinal3P0Remediation-20260829.txt` and its companion ZIP. Next step is the same Codex Ultra independent PRE-E2E audit; only an independent overall P0=0 verdict advances to physical signed-in iPhone E2E.

## 2026-08-30 Codex Ultra independent PRE-E2E re-audit — current verdict

- This section supersedes the preceding re-audit request. The independent audit completed on `connectDB` at HEAD `6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`; the dirty working tree was preserved. Production writes/migrations, Edge deployments, Swift/source fixes, expectation changes, commits, and pushes were all 0.
- Final verdict is `FITMATCH PRE-E2E GO`, readiness `93/100`, with `P0 0 / P1 9 / P2 6`. The next stage is Physical iPhone E2E; no new DB/Swift remediation phase was opened.
- Fresh Production READ-ONLY audit at `2026-08-29T22:08:30.700693Z` returned `score=100`, `p0_count=0`, Products 1,608, classifications `203 CONFIRMED / 1,308 REVIEW_REQUIRED / 97 NOT_APPLICABLE`, invalid confirmed 0, deterministic replay/store mismatch 0, duplicate/orphan/parity defects 0, readiness `READY 3 / NO_AVAILABLE_SIZE 198 / NO_MEASUREMENT_DATA 2 / CLASSIFICATION_REQUIRED 1,308 / NOT_APPLICABLE 97`, Golden READY 3/3, policy boundary 19/19, and selected legacy business references 0.
- Deployed `product-observation` is ACTIVE v5 with `verify_jwt=true`. Remote/local source is exact 3,334 bytes and SHA-256 `93ea79a8cffc064d1886d2f0d7be723af594cf5ba0097e432adba8a56afffeb3`; it derives actor identity from `auth.getUser().user.id`, calls only the service-role public vNext bridge, and contains legacy submit/process references 0. Fresh no-auth and malformed-JWT negative requests returned 401. A physical signed-in positive path remains NOT RUN by design for the next E2E stage.
- The prior three Swift P0s are independently closed. `saveCompletedVNext` uses exact history/Product/ProductSize UUID only and preserves distinct same-target comparisons. Immutable-history-only references are marked with an existing-field sentinel and excluded from all active Closet/picker/sync paths. Reference reconciliation now sends exact clientItemID set/unset deltas while preserving first-login remote-only hydration and DB same-tuple atomic replacement.
- Xcode 26.3 on iPhone 17 Pro simulator iOS 26.3.1: App build PASS; test-target build PASS; critical suites `86 PASS / 0 FAIL / 0 SKIP` including four P0 regressions. Full FitMatchTests is `502 PASS / 1 FAIL / 37 SKIP`; the only failure is the unchanged legacy DBLogic adjudication corpus. UI target is `4 PASS / 10 FAIL / 6 SKIP`; failures reproduce stale copy/pre-vNext/cache-owner harness debt, not a new sourced vNext P0.
- Comparison release order is server runtime/candidates → authorize → exact eligible UUID set → immutable begin → scorer → complete → exact local cache. Scorer-before-authorization/begin, unauthorized/excluded/fail-closed-state scoring, and complete-before-history violations are 0. Other Item creates a new server comparison without reparsing; Other Size is safe for the current authorized in-memory batch and fails closed after restart.
- Production user-contract parity independently passed: stored/repo SQL exact 32,195 bytes and SHA-256 `ad23bad212999c882b114c50b95ad7df7b95f275e0aadf8b0a7a7f37daa0dbd6`; 24/24 target functions present, security-mode mismatch 0, fixed search-path missing 0, anon execute 0, closet RLS enabled, target global Product DML references 0. Fresh mutating cross-user fixtures were NOT RUN because this audit forbade Production writes; deployed owner predicates/grants/RLS were verified structurally.
- Migration ledger mismatch remains P1: repo prefix `20260829050000`, Production ledger `20260829110853 / vnext_swift_user_contract`; SQL is exact and applied once, so current E2E correctness impact is 0, but blind future migration push can attempt reapplication. No repair/fake marking/reapply occurred.
- Repository publishing remains P1: all 23 vNext migration sources and current Swift integration remain in the local working tree but are untracked/absent from `origin/connectDB`; local/deployed Edge v5 matches while origin contains an older Edge source. Publish only through explicit owner review; this is not a current Production correctness P0.
- Other retained P1s are legacy callable SECURITY DEFINER surface, missing personal-override clear UI, Other Size restart recovery, server-history hide/delete semantics, cross-device soft-delete cache reconciliation, the one legacy adjudication unit failure, and stale UI harness debt. Retained P2s are unknown-readiness diagnostic collapse, leaked-password protection, index/performance hygiene, missing dynamic completion-failure injection, duplicate-history payload-equivalence defense, and pre-DB normalized size-label observation identity.
- Protected checks PASS: `git diff --check`; TabBar modifier/call sites, navigation structure, SwiftData persisted schema, and Share Extension diffs are 0. Detailed evidence is `Docs/FitMatchCodexUltraIndependentPreE2EAudit-20260830.txt` and its ZIP.

## 2026-08-30 Manual cross-comparison migration lineage recovery — Git parity ready

- Work ran on `connectDB` at HEAD `1d53c0ca3d92a2012686655ec309dcd2c3764ca5`; `origin/connectDB` was the same commit and the initially clean working tree was preserved. Reset/revert/stash/clean, commit, and push were not performed.
- Exact local/Git/history/temp searches found neither manual-cross migration source, so the pre-recovery state was CASE D. The source was then recovered from the authoritative Production ledger payloads `supabase_migrations.schema_migrations.statements[1]`, not reconstructed from current schema/function definitions.
- Recovered exact files are `supabase/migrations/20260830003812_add_manual_cross_comparison_rules.sql` and `supabase/migrations/20260830003907_constrain_manual_cross_comparisons_by_sleeve.sql`. Their local byte counts/SHA-256 values exactly match Production ledger payloads: `9883 / d309886152575a991e1b234652c492e893ddd22716d729eeb4d6689386bad229` and `9349 / 024e47eff6a924ee063b368a22bd3150ee87881a079ac4b0aaf8fc5cb04489a4`.
- Production SELECT-only parity PASS: the seven-column `fitmatch_vnext.manual_cross_comparison_rules` table, order CHECK/composite PK, three active rules, `require_same_sleeve=true`, SECURITY DEFINER/fixed-search-path authorize function, manual lookup, same-sleeve guard, `MANUAL_EXTENDED`, and `fitmatch-vnext-authorization-v3` marker all match.
- Disposable PostgreSQL 17.11 replay on `/tmp/FitMatchManualCrossPG17-fyqULDUP`, port 55449, PASSed first apply and reapply. The resulting function definition SHA-256 `4dd5c5fc4e6ba824fedbb079824032b0d46decb2b780f3975387c4513b6e2b0d` exactly matched Production. Runtime probes confirmed automatic cross BLOCKED, same-sleeve explicit cross MANUAL_EXTENDED, sleeve-mismatch explicit cross BLOCKED. The server was stopped and the exact disposable directory was deleted.
- Production writes/migrations/function replacement/data change/ledger repair were 0. Swift and Edge changes were 0. Final verdict: `GIT ↔ PRODUCTION MANUAL-CROSS PARITY READY`.
- Remaining operational item: the exact recovered files and report are local working-tree artifacts and are not yet published to `origin/connectDB`, because commit/push were explicitly prohibited. The next authorized stage is the existing Chat 5.6 Pro REVIEW_REQUIRED Recovery READ-ONLY audit; do not add new comparison behavior.
- Detailed evidence is `Docs/FitMatchManualCrossMigrationParityRecovery-20260830.txt` and its companion ZIP.

## 2026-08-30 REVIEW_REQUIRED recovery implementation — local validation PASS

- Work ran on `connectDB` from start through end at HEAD `b419f159962e1447ae2981be3747436117d7faef`; preflight `origin/connectDB` matched. The existing/manual-cross baseline was exact, the initially clean tree was preserved, and reset/restore/stash/clean/commit/push were not performed.
- Production remained SELECT/introspection-only. Production writes, migrations, release/classification/mapping/measurement/availability/history mutation, Auth changes, and Edge deployment were all 0. Actual classification remains Products 1,608 and `CONFIRMED 203 / REVIEW_REQUIRED 1,308 / NOT_APPLICABLE 97`, with invalid confirmed/replay mismatch/duplicate/orphans 0.
- Phase 0 is the independent migration `20260830090000_vnext_leaf_specificity_correction.sql`. It uses only actual `parent_signal_id` ancestry to remove an equal-authority PRODUCT_REQUIRED ancestor when a verified DIRECT descendant competes. Full-corpus dry-run moved exactly 143 false reviews, projecting `346 / 1,165 / 97`; existing CONFIRMED changes, NOT_APPLICABLE changes, and new invalid tuples were all 0. No product-name, string-prefix, or evidence-order specificity heuristic exists.
- Phase 1–4B is `20260830091000_vnext_review_required_recovery.sql`. It adds a bounded server recovery envelope, product-scoped USER_EXPLICIT projection, append-only feedback evidence, deterministic set/clear, one effective-classification resolver, effective-context measurements/readiness, integration into reference discovery/authorization/eligible sizes/begin, and immutable snapshot schema v4. Global CONFIRMED and NOT_APPLICABLE retain precedence; raw client tuples and global auto-promotion are impossible by contract.
- Current exact-product-evidence-required distribution is 389: candidate counts `0=270 / 1=7 / 2=5 / 3=107 / >3=0`; recoverable v1 is 119 and unrecoverable is 270. Candidate derivation uses verified descendant DIRECT evidence, active taxonomy/policy, tuple validity, shared fixed-fact intersection, and a 1...3 bound. It never offers a broad taxonomy fallback.
- Swift adds recovery/effective/snapshot-v4 DTOs, server client calls, coordinator-owned safe sequencing, ViewModel states, and minimal CompareFlowSheet UI. Selection saves only an opaque server candidate, refetches effective authority, then restarts find refs → authorize → eligible → begin → scorer → complete. Target classification confirmation remains independent from manual reference intent.
- Measurement regression proves an equivalent global CONFIRMED polo/short product and REVIEW_REQUIRED plus USER_EXPLICIT polo/short product have equal canonical measurements, eligible size UUIDs, policy, exclusions, and engine inputs. Existing manual-cross behavior remains: short polo↔short tshirt automatic BLOCK/manual MANUAL_EXTENDED; sleeve mismatch BLOCK; rules and authorization-v3 are unchanged.
- PostgreSQL 17.11 disposable validation on final cluster `/tmp/FitMatchReviewRecoveryPG17-final2`, port 55469, PASSed fixture → 90000 → 91000 first apply, transaction contract/security/lifecycle tests, ROLLBACK, migration reapply, validation re-run, and second ROLLBACK. Post-rollback override/feedback/comparison rows were `0/0/0`; the cluster was stopped and deleted.
- Xcode 26.3 on the existing iPhone 17 Pro simulator iOS 26.3.1: app build PASS and test-target build PASS. Focused authority/recovery regressions are `90 PASS / 0 FAIL / 0 SKIP`. Full FitMatchTests is `506 PASS / 1 FAIL / 37 SKIP` (544 total); the only failure is the unchanged legacy DBLogic adjudication corpus mismatch, with no expectation edit and no new Recovery failure.
- Final static gates PASS: `git diff --check`; release Swift/Edge legacy submit/process/resolve/runtime references 0; protected TabBar/scroll, SwiftData persisted schema, navigation, Share, Edge, and existing DB/manual-cross diffs 0.
- At the final SELECT-only timestamp the three Golden availability evidence rows had naturally expired at `2026-08-30 01:42:43.426905Z`, so readiness was `READY 0 / NO_AVAILABLE_SIZE 201 / NO_MEASUREMENT_DATA 2 / CLASSIFICATION_REQUIRED 1,308 / NOT_APPLICABLE 97`. This temporal fail-closed change was not caused by this work and was not repaired or mislabeled PASS.
- Current verdict is `IMPLEMENTATION PASS` for the repository/local contract. It is not a Production or physical-device claim. Remaining gates are explicit owner review/application of migrations 90000/91000 with Production security/data postflight, normal retailer refresh before asserting Golden READY 3/3, and signed-in physical iPhone/multi-device Recovery E2E. Do not auto-start deployment or another DB/Swift phase.
- Detailed evidence is `Docs/FitMatchReviewRequiredRecoveryImplementation-20260830.txt`; the companion ZIP contains every changed source, migration, validation, test, report, and this handoff.

## 2026-08-30 REVIEW_REQUIRED Recovery final UX/lifecycle patch — PASS

- Work remained on `connectDB` at HEAD `b419f159962e1447ae2981be3747436117d7faef`; the existing dirty Recovery implementation was preserved. Reset/revert/stash/clean, commit/push, Production write/migration apply, and Edge deployment were 0.
- Active USER_EXPLICIT targets now expose minimal “상품 종류 다시 확인” and “내 선택 초기화” actions in the existing Compare flow, including the Result surface. Reselect always fetches the latest server Recovery contract, submits the current revision, refetches effective authority, and restarts the existing reference-discovery comparison chain. It never jumps to the scorer or implies manual-reference intent.
- Existing Recovery UI reuse is explicit: the sole candidate-confirmation surface remains `CompareFlowSheet.categoryConfirmationContent` → `reviewRecoveryContent`. No second Recovery View, sheet, route, navigation flow, or generic/parallel picker was created; the actions only re-enter the existing CompareFlow state machine.
- Clear uses the existing server RPC, invalidates transient/local Recovery comparison state, and refetches runtime. Global REVIEW_REQUIRED returns to constrained confirmation with no scorer/begin; Global CONFIRMED uses Global authority and the normal comparison chain; NOT_APPLICABLE remains blocked. Closet and completed History are unchanged.
- The final `effective_target_classification(uuid)` now selects only `cleared_at is null` personal rows. Cleared evidence stays append-only but cannot produce current SUPERSEDED_MATCH/SUPERSEDED_CONFLICT or comparison authority. SQL regression proves active matching/conflicting rows retain their intended superseded states, while clear followed by Global CONFIRMED returns plain GLOBAL_CONFIRMED.
- PostgreSQL 17.11 disposable replay on port 55473 PASSed fixture → 90000 → patched 91000 → validation/ROLLBACK, migration reapply, validation rerun/second ROLLBACK. Post-rollback override/feedback/comparison rows were `0/0/0`; the cluster was stopped and deleted.
- Xcode 26.3 on iPhone 17 Pro Simulator: app build PASS; test-target build-for-testing PASS; focused Recovery `6/6`; critical vNext + Recovery `88/88`. Full FitMatchTests is `508 PASS / 1 FAIL / 37 SKIP`; the sole failure remains the unchanged legacy DBLogic adjudication corpus (64 assertions), with no expectation edits and no new failure.
- Revision regressions cover EDITED revision `1→2`, stale candidate/hash rejection, stale old revision rejection, clear and CLEARED evidence preservation. The SQL transaction additionally covers clear revision `2→3`, active SUPERSEDED_MATCH/CONFLICT, and cleared-row exclusion after later Global CONFIRMED.
- `git diff --check` PASS. This patch has no MeasurementComparisonEngine, weights/formulas, manual-cross policy, SwiftData schema, Share, navigation, protected TabBar/header-scroll, or Edge change. Global Product Production mutation count and all Production writes remain 0.
- Final verdict: `FINAL RECOVERY PATCH PASS`. Both Recovery migrations remain unapplied to Production; physical signed-in iPhone E2E and physical multi-device reselection/clear E2E remain pending. Detailed evidence is `Docs/FitMatchReviewRequiredRecoveryFinalPatch-20260830.txt` and its companion changed-files ZIP.

## 2026-08-31 Owner-policy implementation — PC-HISTORY-001 + PC-PROVIDER-001

- Scope was intentionally limited to the two owner-decided policies. Existing dirty Recovery/headless/audit work was preserved. No reset, restore, stash, clean, commit, push, Production access, Production data write, migration apply, Edge deployment, Auth change, or unrelated Sol Ultra remediation was performed.
- PC-HISTORY-001 is implemented by the additive, unapplied migration `supabase/migrations/20260831010000_vnext_comparison_history_visibility.sql`. It adds the owner-keyed `fitmatch_vnext.user_comparison_history_visibility` suppression table, RLS, owner-checked/idempotent authenticated RPC `fitmatch_vnext_hide_comparison_history(uuid[])`, and makes the existing immutable comparison-history projection exclude only the caller's hidden comparison IDs. It never updates/deletes completed comparison evidence or snapshots. The function verifies owned, visible, completed client comparison IDs and uses SECURITY DEFINER with fixed `search_path`; direct authenticated table mutation and anon execution are denied.
- Swift now persists the durable hide before removing server-backed vNext History locally. A failed hide leaves the item visible and retryable. Sync/re-hydration receives the filtered server projection, so a hidden completed comparison does not reappear after modeled reconstruction or another device session. Closet deletion batches the same durable hides for its server-backed completed histories before local removal; legacy/local-only History retains the existing local-only path and never fabricates server tombstone authority. User-facing deletion remains a durable list removal without exposing internal tombstone terminology.
- PC-PROVIDER-001 is implemented at the official URL support boundary: COS no longer has a supported provider name, is rejected before `ProductURLParserService` dispatches any provider parser, and user-facing unsupported-link/onboarding/release-support copy now names only approved official provider surfaces. The Share Extension already allowed only MUSINSA/UNIQLO/ZARA and remains COS-unsupported. The isolated internal `COSParser` source and its direct parser tests remain intact for future/experimental use; historical/manual COS source labels were not rewritten.
- Disposable PostgreSQL 17 validation only (no Production connection) applied the new migration and reapplied it successfully. It verified first hide, idempotent repeat, history filtering, cross-user rejection, authenticated direct table-write denial, anon RPC denial, and fixed SECURITY DEFINER/search-path contract. The temporary server was stopped; no persistent test data was retained.
- Xcode 26.3 on the existing iPhone 17 Pro simulator (iOS 26.3.1) passed app + test-target `build-for-testing`. Focused `FitMatchComparisonSyncCoordinatorTests`: 9 PASS / 0 FAIL / 0 SKIP, including the Closet-delete associated server History path. COS boundary + Share configuration: 4 PASS / 0 FAIL / 0 SKIP. Retained internal COS parser: 2 PASS / 0 FAIL / 0 SKIP. Additional Closet sync + Supabase product-resolver regression was 46 PASS / 0 FAIL / 0 SKIP. Existing compiler warnings only were unchanged nullable/coalescing/interpolation warnings in unrelated live-audit tests.
- Final local checks PASS: `git diff --check`, protected TabBar modifier diff, and protected scroll-symbol diff are all 0. Deployment is explicitly **NOT DEPLOYED**; a separately authorized Production migration/postflight is required. All other Sol Ultra findings, including HJ-P0-001 and the one-shot remediation package, remain pending and were not started by this work.

## 2026-08-31 Final real-user headless release acceptance — RELEASE HOLD

- The current `connectDB` working tree was tested at published base/local HEAD `8855874a7ff372ef9b0e6159740c6faee4750985`. Existing dirty owner-policy/P0 changes and the unapplied History-visibility migration were preserved. Reset/stash/clean, product fixes, commit, push, Production mutation, migration deployment, Edge deployment, and Auth changes were 0.
- A new user-feature catalog froze 137 scenarios: Register 22, Closet Manage 19, Compare 39, Result 13, History 17, Entry/Share 12, Retry/Race 15. A strict second evidence audit rejected partial gates and label-only old Headless axes as execution. Final accounting is `20 executed / 15 PASS / 5 FAIL / 117 NOT_EXECUTED`, score `10.9/100`; verdict `RELEASE HOLD — PRODUCT DEFECTS`.
- Five failed rows represent four defect families: (1) CR-017 P0 shopping USER_EXPLICIT is retained as Closet `.userExplicit` without separate Closet intent; (2) HI-002/HI-003 P0 V4 personal History hydration flattens provenance to `.serverConfirmed` and shares one mutable Product across revisions; (3) CP-031 P1 effective USER_EXPLICIT null axes are field-wise filled from Global, creating a server-unissued hybrid tuple; (4) EN-004 P2 stale pending Share URLs never expire and can auto-open later.
- Exact retained PASS rows are `CP-008/009/010/011/014/030/033`, `RS-002`, `HI-006/008/015/016/017`, and `RX-004/014`. All other rows without exact fixture + production-symbol + terminal evidence are explicitly NOT_EXECUTED. Static high-risk unexecuted rows include CM-015 cross-account cache exposure and RS-005/HI-013 other-reference Result/History behavior.
- Test evidence: final acceptance `4 PASS / 4 FAIL` (8); old Headless core `5/5` test methods PASS but not treated as blanket final coverage; critical eight-suite batch `97/97` PASS. Full FitMatchTests is `522 PASS / 6 FAIL / 37 SKIP` (565): four acceptance failures, the existing MUSINSA 5049615 DBLogic corpus mismatch, and a SwiftData invalidation crash in `closetDeletionHidesAssociatedCompletedServerHistoryWithoutDeletingRemoteEvidence`. The same test passed in the separate critical batch, but the full-suite crash cause remains unverified.
- Build-for-testing succeeded with 0 errors/warnings on the headless iPhone 17 Pro Simulator host (iOS 26.3.1, Xcode 26.3). This is not interactive Simulator or physical-device E2E.
- The local, unapplied `20260831010000_vnext_comparison_history_visibility.sql` SHA-256 is `e20880ba716dde5a51b1bd03c0c2fc5c4de40c5295e79edb587609e8bcdc4ee3`. Disposable PostgreSQL apply/reapply/security/immutability validation PASSed; the temporary server was stopped. The migration remains **NOT DEPLOYED** to Production.
- Production writes were 0. Protected TabBar/scroll diffs and `git diff --check` are required as final gates. Detailed artifacts are `Docs/FitMatchFinalReleaseUserScenarioCatalog-20260831.txt`, `Docs/FitMatchFinalReleaseHeadlessScenarioResults-20260831.jsonl`, `Docs/FitMatchFinalReleaseHeadlessManagerReport-20260831.txt`, and `Docs/FitMatchFinalReleaseHeadlessTechnicalReport-20260831.txt`.
- Next step is a separate implementation task for the four reproduced defect families plus the full-suite crash and safe headless orchestration seams. Re-run 137/137 before any History-visibility Production deployment/postflight or physical iPhone release checklist.

## 2026-08-31 Final 137-scenario remediation — PARTIAL, independent acceptance not yet authorized

- Work remained on `connectDB` at published/local committed base `8855874a7ff372ef9b0e6159740c6faee4750985`; the pre-existing dirty owner-policy/HJ-P0 work and the unapplied History visibility migration were preserved. Reset/restore/stash/clean, commit, push, Production DB/API writes, migration deployment/repair, Auth mutation, and Edge deployment were all `0`.
- CR-017 is fixed with production-used `FitMatchComparedProductClosetRegistration.makeUserFit`, called by `AddComparedProductToClosetSheet`. A shopping Product’s `.userExplicit` is now product-scoped during new sourced Closet registration and produces `.localHint` unless the user makes a distinct Closet picker edit. Existing Closet user authority survives a size-only edit; Global confirmed remains Global.
- HI-002/HI-003 are fixed by v4 immutable historical projections in `VNextHistoryCacheHydrator`. Fresh hydration preserves each completed comparison’s USER_EXPLICIT provenance, revision, candidate fingerprint, effective tuple, and independent Product/ProductSize/reference projection. It refreshes identity maps from current ModelContext state, repairing the stale SwiftData object path observed after deletion.
- CP-031 is fixed by `VNextRuntimeClassificationTuple`; resolver and ViewModel now consume server effective classification atomically. Individual effective fields are never coalesced with Global fields; Global fallback occurs only when the whole effective object is absent.
- EN-004 is fixed by `SharedURLStore` with a 15-minute internal TTL, injectable clock, opaque generation tokens, and generation-safe acknowledgement. Missing/invalid/stale pending payloads fail closed; acknowledging old A cannot erase new B. `ContentView` and Share Extension use the token lifecycle.
- A production cache-ownership seam `FitMatchClosetSyncCoordinator.prepareLocalCache(for:modelContext:)` now runs before MainTab rendering. On A→B account switch it purges foreign UserFit/History SwiftData cache before remote sync; an unresolved preparation error withholds user-owned rows and offers retry. The focused test passes.
- Focused remediation probes are `9/9 PASS`; CR-017 production builder is `1/1 PASS`; the exact History/Closet SwiftData reproducer passes `10/10` with a relaunched test process per repeat. Final full FitMatchTests is `568 total / 530 PASS / 1 FAIL / 37 SKIP`; no SwiftData invalidation crash recurred. The sole failure remains `DBLogicReliabilityAuditTests.testDBLogicAdjudicationMatchesProductionClassifier` (MUSINSA 5049615 / a 31-product, 64-assertion legacy Gold fixture conflict). Current Handoff evidence identifies contradictory legacy expectations and local-classifier policy drift; no expected values or sourced vNext authority were changed without owner re-adjudication.
- Frozen catalog accounting was updated without deletion or expectation change: `137 total / 20 executed / 20 PASS / 0 FAIL / 117 NOT_EXECUTED`, score `14.6/100`. The five prior failure rows `CR-017`, `CP-031`, `HI-002`, `HI-003`, and `EN-004` now have exact focused production-path evidence. The remaining 117 remain explicitly unexecuted; no label-only/static test was promoted to PASS.
- `git diff --check` passes. Protected `FitMatch/Components/TabBarScrollVisibilityModifier.swift` and the protected scroll call-site diff are `0`. No change was made to scorer formulas/weights/ranking, manual-cross policy/sleeve rule, Recovery candidate safety, global DB authority, server comparison order, SwiftData persisted schema, or Edge architecture.
- Detailed evidence: `Docs/FitMatchFinalReleaseRemediationReport-20260831.txt` and `Docs/FitMatchFinalReleaseHeadlessSeamMap-20260831.txt`, alongside the updated frozen JSONL/manager/technical reports. The History visibility migration remains **NOT DEPLOYED**.
- Exact next step: complete production-used headless seams for every remaining frozen scenario and run an independent Sol Ultra acceptance against the unchanged 137-scenario catalog. Do not deploy the History visibility migration or claim release readiness before `137 executed / 137 PASS / 0 NOT_EXECUTED` and owner resolution of the legacy DBLogic corpus status.

## 2026-08-31 Final 137-scenario headless completion — ready for independent acceptance

- The current working candidate remains on `connectDB` at published base `8855874a7ff372ef9b0e6159740c6faee4750985`. Existing dirty owner-policy/HJ-P0 work and the unapplied History-visibility migration were preserved. Reset/stash/clean, commit, push, Production DB/API writes, migration deployment/repair, Auth mutation, and Edge deployment were all `0`.
- The four reproduced defect families remain fixed: CR-017 separates shopping USER_EXPLICIT from Closet intent; HI-002/HI-003 hydrates immutable per-comparison V4 personal projections; CP-031 consumes server effective tuples atomically; EN-004 uses a fixed 15-minute Share TTL with generation-safe acknowledgement. The SwiftData stale-identity hydration/delete crash did not recur.
- New production-used headless actions cover direct/link/result/history Closet paths, edit/reference/delete/hide, account cache isolation, startup, entry/share data routing, duplicate comparison submission, Result URL selection, and current authority/history projection. Views and tests call the same actions; no test-side classifier, scorer, reference policy, manual-cross evaluator, or authority implementation was added.
- Final frozen catalog reconciliation is `137 total`: `123 HEADLESS PASS`, `10 STATIC CONTRACT PASS`, `4 PHYSICAL_SMOKE_PENDING`, `0 FAIL`, `0 NOT_EXECUTED`. Static rows are `CR-010 CM-001 CM-013 CM-018 HI-011 HI-012 EN-003 EN-006 EN-010 EN-011`. Physical-only UI portions are `CR-019 EN-002 EN-007 EN-012`; their data/state routing remains headless-tested.
- Evidence: final scenario execution suite `11/11 PASS`, initial run plus four fresh-state repeats (`5 consecutive PASS`); final acceptance `21/21 PASS`; old 45-journey production-path suite `5/5 PASS`; full non-UI `FitMatchTests` `557 PASS / 0 FAIL / 37 SKIP` at `/tmp/FitMatchFinal137FullCoreRegression.xcresult`. The prior SwiftData invalidation crash was absent.
- The legacy 207-row DBLogic assertion was corrected from a false sourced-authority gate into a parser-fact audit: parser/local Closet output is no longer required to equal the server-owned global Product authority. The parser audit is `2/2 PASS`; no parser rule, Product tuple, or Production classification was changed. The historical expected tuples remain in the corpus for audit context, but are no longer incorrectly asserted as local parser output.
- Final validation: `build-for-testing` completed with `TEST BUILD SUCCEEDED` on the iPhone 17 Pro simulator target; `git diff --check`, the protected TabBar modifier diff, and the protected scroll-symbol diff are all clean. `20260831010000_vnext_comparison_history_visibility.sql` remains **NOT DEPLOYED** and was not applied to Production in this task.
- Exact next step: run an independent Sol Ultra acceptance against the unchanged frozen 137 catalog, then perform the four real-iPhone system-UI smoke cases. Do not deploy the History visibility migration before both acceptances complete.

## 2026-09-01 Final 137 remediation evidence refresh — ready for second independent acceptance

- Current Git identity is unchanged: branch `connectDB`, published/local committed base `8855874a7ff372ef9b0e6159740c6faee4750985`. The release candidate is the current uncommitted working tree. Existing owner-policy, Recovery, HJ-P0, and History-visibility work was preserved; reset/restore/stash/clean, commit, push, Production write, Production migration apply, Auth mutation, and Edge deployment were all `0`.
- Four known user-facing defect families remain corrected and focused-tested: CR-017 keeps shopping USER_EXPLICIT separate from explicit Closet classification intent; HI-002/HI-003 retain immutable per-comparison V4 target/reference projections; CP-031 consumes the server effective tuple atomically; EN-004 uses a 15-minute generation-safe shared Share payload. Result recompare is detached from the old completed Result/History, Home retains distinct comparison identities, and invalid/COS URL entry returns a meaningful fail-closed state.
- A further real CM-015 account-switch race was corrected: both Closet and History sync coordinators bind in-flight work to the requested user, discard late outgoing-user results, and execute a newest same-user follow-up pass. ContentView does not present/sync user-owned data until cache ownership preparation completes.
- Final frozen accounting is now `137 total = 131 HEADLESS_PASS + 2 STATIC_CONTRACT_PASS (EN-010, EN-011) + 4 PHYSICAL_SMOKE_PENDING (CR-019, EN-002, EN-007, EN-012) + 0 FAIL + 0 NOT_EXECUTED`. The four physical rows have their data/state/business logic headlessly exercised; only Apple/system presentation and physical Share Sheet lifecycle remain.
- Current local validation: full non-UI FitMatchTests `592 PASS / 0 FAIL / 37 SKIP`; focused production evidence `103 PASS / 0 FAIL`; SwiftData delete/hydration `14 PASS × 10`; Recovery/race `15 PASS × 5`; Share TTL/CAS `26 PASS × 5`; account cache isolation `29 PASS × 5`; Debug app/test build-for-testing PASS.
- Clean disposable PostgreSQL validation against current local migration/contract sources reports `RECOVERY_VALIDATION_PASS`, `ROLLBACK_PASS`, and `MANUAL_CROSS_CONTRACT_PASS`. It covers same-client-ID begin replay and all three protected manual-cross pairs in both directions. The disposable server was stopped. Production was not contacted or changed.
- The History visibility migration `20260831010000_vnext_comparison_history_visibility.sql` remains **NOT DEPLOYED**. No physical iPhone claim is made. Protected TabBar/header-scroll code has no task-induced diff.
- Current evidence files are `Docs/FitMatchFinalReleaseHeadlessScenarioResults-20260831.jsonl`, `Docs/FitMatchFinalReleaseHeadlessManagerReport-20260831.txt`, `Docs/FitMatchFinalReleaseHeadlessTechnicalReport-20260831.txt`, `Docs/FitMatchFinalReleaseRemediationReport-20260831.txt`, and `Docs/FitMatchFinalReleaseHeadlessSeamMap-20260831.txt`.
- Exact next step: run a **second independent Sol Ultra acceptance** against the unchanged frozen 137-scenario catalog. Only after it passes should the owner perform the four physical-system smoke cases and separately authorize History visibility migration deployment plus Production postflight.

## 2026-09-01 Final 137 closure remediation — ready for last independent acceptance

- Starting independent baseline was `73 HEADLESS_PASS / 1 STATIC_CONTRACT_PASS / 2 PHYSICAL_SMOKE_PENDING / 7 FAIL / 54 INCOMPLETE` for the unchanged frozen 137 catalog. This closure changed no scenario ID, expected outcome, Product policy, scorer, manual-cross policy, or server authority contract.
- The five confirmed production families are now fixed and focused-tested: owner-safe A→B cache/session isolation (CM-015, EN-007); immutable same-client-ID begin replay proof (RX-005); exact current USER_EXPLICIT Product projection without Global coalescing (CP-031); canonical hydrated History URL/recompare routing without mutation of old History (HI-005, HI-013); and reasoned fail-closed Share handoff errors (EN-004).
- All 54 evidence gaps now have a concrete production-path test fixture/action/terminal assertion. The final additions include Result evidence and USER_EXPLICIT reselect/clear (RS-003, RS-013), real captured UNIQLO/MUSINSA/ZARA direct-entry routing (EN-001, CP-032), startup retry (EN-009), offline cache reconnect (RX-006), deterministic begin delay → reference mutation → stale response rejection (RX-003), Recovery reconstruction (RX-013), and exact authority/reference/eligible/begin retry gates (RX-009/RX-010). No test-side classifier, scorer, reference selector, manual-cross evaluator, measurement/size eligibility evaluator, or authority resolver was added.
- Final accounting is `137 total = 133 HEADLESS_PASS + 2 STATIC_CONTRACT_PASS (EN-010, EN-011) + 2 PHYSICAL_SMOKE_PENDING (EN-002, EN-012) + 0 FAIL + 0 INCOMPLETE + 0 OWNER_SCOPE_DECISION_REQUIRED`. CR-019 signed-out registration routing and EN-007 auth/session/cache-isolation behavior are now fully headless production-state evidence, not physical-only rows.
- Current validation: Headless User Journey `39 PASS / 0 FAIL`; final scenario/provider/Closet sync/ZARA bundle `118 PASS / 0 FAIL / 3 SKIP`; full non-UI `FitMatchTests` `649 PASS / 0 FAIL / 37 SKIP`; final scenario fresh-state `36 PASS × 2`; and headless/History/Share/account/sync repeat group `113 PASS × 5` in relaunched processes. The SwiftData delete/sync/hydration path remained stable.
- App plus test-target `build-for-testing` passed. Production writes, Production migration apply, Auth mutation, Edge deployment, commit, and push are all `0`. The History visibility migration `20260831010000_vnext_comparison_history_visibility.sql` remains **NOT DEPLOYED**. This task introduced no protected TabBar/header-scroll change.
- Exact next step: a final independent Sol Ultra read-only acceptance against this unchanged frozen 137 catalog; then only the real-iPhone Share Sheet smoke for EN-002/EN-012, separately authorized History migration deployment, and Production postflight.

## 2026-09-02 Live retailer structure / audience-policy P0 fix — ready for limited independent review

- Work ran on `connectDB` at local HEAD `40a6a4d9eb8a4c5e82bcd9870dea83a534cc5e93`. The candidate remains an uncommitted working tree; reset/checkout/clean/stash/revert, commit/push, Production DB write, Production migration apply, Auth mutation, and Edge deployment were all `0`.
- Production SELECT-only preflight found missing structure facts on the latest receipt for all sampled/current provider rows: MUSINSA `395` latest receipts missing the key (`57/395` products effective `UNKNOWN`; `338` had a prior explicit structure at risk of regression), and UNIQLO `1,184` missing the key (`370/1,184` effective `UNKNOWN`; `814` at risk). Explicit UNKNOWN receipts were `0` for both sources. No Production change was made.
- Swift now carries a typed retailer `product_structure` fact (`SINGLE`, `SET`, `MULTIPACK`, `UNKNOWN`) with source/evidence through parser provenance, SwiftData replay, resolution, and observation payloads. MUSINSA requires its official product-detail physical-offer fields and rejects ambiguous/missing evidence; UNIQLO requires the exact selected PDP entity or an explicit provider bundle field. Explicit composite provider facts win; absence never implies SINGLE, and no local garment category is used as structure authority.
- New unapplied migration `20260902031749_live_retailer_structure_and_adult_audience_policy.sql` distinguishes MISSING from EXPLICIT_UNKNOWN at the existing ingress action. Missing preserves only a prior real product-structure evidence link and never fabricates a new observation; explicit UNKNOWN remains fail-closed. It safely rebuilds the existing PostgREST bridge after the v1 function rename, builds only unambiguous UNIQLO official ID-parent paths, and copies only a sole verified valid DIRECT mapping across an equivalent audience path. PRODUCT_REQUIRED/conflicting/no-parent candidates remain REVIEW_REQUIRED.
- Production preflight found four multi-audience UNIQLO category IDs (`95355`, `95357`, `100315`, `95405`); only `100315` has the uniquely safe MEN DIRECT `knit_sweater/long_sleeve` tuple. `95357` and `95405` are PRODUCT_REQUIRED/not safely generalizable. The migration uses audience-specific verified mappings, rather than an ANY rewrite, because the existing authority is signal/audience scoped and the latter could broaden unrelated authority.
- Active policies were `39` SAME_OR_UNISEX before this change. The migration changes exactly `32` general adult policies to existing `ADULT_ANY` and retains exactly `7` anatomy-specific policies (`men_briefs`, `men_trunks`, `men_undershirt`, `women_bra`, `women_camisole`, `women_panty`, `women_slip`) as SAME_OR_UNISEX. Structural, measurement, manual-cross, unsupported, and fail-closed classification gates are unchanged.
- General and Golden coverage: `RetailerProductStructureContractTests` proves provider SINGLE/SET/MULTIPACK/unknown and payload forwarding; Golden regression inputs `6976301`, `E486080`, and `E453754` exist only in tests/local validation, not in production Swift or the migration. E453754 remains PRODUCT_REQUIRED/REVIEW_REQUIRED. The local validation uses the actual existing public ingress bridge, server classifier, and authorization function; it does not duplicate business rules.
- Disposable PostgreSQL 17 validation applied the production-shaped fixture plus migrations `12117`, `31514`, `43247`, `90000`, `91000`, and the new migration. It passed `LIVE_RETAILER_GENERAL_CONTRACT_PASS` after rollback-only probes for explicit SINGLE/SET/MULTIPACK/UNKNOWN, missing preservation, explicit UNKNOWN, PostgREST bridge rebinding, UNIQLO equivalent authority vs PRODUCT_REQUIRED protection, Golden inputs, adult MEN/WOMEN/UNISEX authorization, structural mismatch, and anatomy-specific blocks. Both temporary servers were stopped; Production was never targeted for mutation.
- Final regression evidence: focused Swift provider/resolver contracts `31 PASS / 0 FAIL / 0 SKIP`; frozen final scenario execution `36 PASS / 0 FAIL / 0 SKIP`; full non-UI `FitMatchTests` `659 PASS / 0 FAIL / 37 SKIP`; app/test `build-for-testing` PASS; `git diff --check` PASS. An intermediate full run exposed an unintended global multipack-title classification effect on the unchanged ZARA shadow corpus; that global change was removed, provider structure handling remained scoped, and the final full suite passed.
- Frozen catalog integrity remains `137` unique IDs: CR `22`, CM `19`, CP `39`, RS `13`, HI `17`, EN `12`, RX `15`, with no duplicate IDs. The unchanged frozen accounting remains `133 HEADLESS_PASS + 2 STATIC_CONTRACT_PASS + 2 PHYSICAL_SMOKE_PENDING + 0 FAIL + 0 INCOMPLETE`.
- Protected TabBar modifier/call-site diff is `0`; protected scroll symbols are absent from task diff. History visibility migration `20260831010000_vnext_comparison_history_visibility.sql` remains **NOT DEPLOYED**. Current task verdict: `READY FOR LIMITED INDEPENDENT REVIEW`; do not apply the new migration to Production or commit/push without separate authorization.

## 2026-09-02 Comparison-unit P0 correction — ready for limited independent review

- This corrective P0 preserves the existing authority boundary: retailer/parser supplies observed product facts; Supabase owns global classification; Swift consumes the returned authority. It removes the unsafe identity-only UNIQLO and generic MUSINSA metadata fallbacks that synthesized `SINGLE` without cardinality evidence.
- `product_structure` is now distinct from an observed `comparison_measurement_contract`. Explicit `SINGLE`, `MULTIPACK`, and mixed `SET` remain retailer facts; no fact remains `UNKNOWN`. A homogeneous `MULTIPACK` or an `UNKNOWN` product may pass only the structure gate when actual provider measurement records establish one coherent garment contract. Mixed sets and multiple component contracts remain blocked, and later classification, audience, measurement-minimum, manual-cross, authorization, begin, engine, Result, and History gates are unchanged.
- Persisted replay serializes only stored structured facts and can no longer turn a legacy display name into new observed retailer structure evidence. At ingress, MISSING, explicit UNKNOWN, and explicit values remain distinct; a missing observation preserves a prior effective fact without fabricating fresh observation evidence. Duplicate and stale payloads leave current fact/provenance/authority state unchanged, while receipts retain their raw observation truth and runtime returns final effective state.
- The unapplied forward migration `20260902031749_live_retailer_structure_and_adult_audience_policy.sql` replaces the destructive v1-call-then-repair ingress path with a guarded v2 path. It permits UNIQLO audience-scoped DIRECT propagation only with matching complete immutable provider category paths, a unique verified tuple, and no conflict, PRODUCT_REQUIRED, ambiguity, cycle, or depth truncation. It keeps the approved 32 general adult `ADULT_ANY` / 7 anatomy-specific restricted partition and has no Golden ID branch.
- Local disposable PostgreSQL validation applied the production-shaped fixture and actual forward migration, then passed `LIVE_RETAILER_GENERAL_CONTRACT_PASS`. It covers explicit/missing structure semantics, comparison-unit eligibility, mixed SET blocking, homogeneous MULTIPACK, UNKNOWN-plus-coherent contract, raw receipt versus effective state, duplicate/stale handling, complete versus truncated/cyclic/conflicting UNIQLO hierarchy, PRODUCT_REQUIRED preservation/recovery, adult audience behavior, and restricted/KIDS/BABY/UNKNOWN blocks. Production was not mutated.
- Current regression evidence: targeted provider/resolver contracts `33 PASS / 0 FAIL / 0 SKIP` (`38` device executions including dynamic parameters); frozen final scenario execution `36 PASS / 0 FAIL / 0 SKIP`; full non-UI `FitMatchTests` `661 PASS / 0 FAIL / 37 SKIP`; app/test `build-for-testing` `TEST BUILD SUCCEEDED`; and `git diff --check` PASS. Frozen catalog remains 137 unique IDs and its existing accepted accounting remains unchanged.
- No commit/push, Production write, Production migration deployment, History migration deployment, or protected TabBar/scroll change occurred. The new live-retailer migration is **NOT DEPLOYED**. Next action is only the requested limited independent review; do not deploy or commit from this handoff.

## 2026-09-02 Live retailer P0 limited-acceptance remediation — ready for independent re-review

- Started from exact `connectDB` / `origin/connectDB` baseline `9f91a915f93f184a3ce07fa97ea54aab71c2da2a`. The candidate remains uncommitted; the only staged path is the new immutable test-owned `FitMatchTests/Fixtures/DBLogicReliabilityCurrentBatchInputs.json` fixture. No commit or push occurred.
- Closed the independent structure-gate finding in `product_comparison_unit_decision`: only `SINGLE`, `MULTIPACK`, or `UNKNOWN` **with** `SINGLE_COHERENT` can be structure-eligible. `SET`, `MULTIPLE_COMPONENT`, and `SINGLE` with `ABSENT` or `UNKNOWN` contract are fail-closed; downstream authority, authorization, size, begin, engine, Result, and History gates are unchanged.
- The Swift retailer measurement-contract fact now uses typed canonical measurement regions and actual imported records. It permits optional upper-garment columns to be absent, rejects upper/lower component tables that merely overlap on a generic total-length axis, and returns `ABSENT` without provider records. Explicit provider component descriptions identify mixed sets; an ambiguous set name alone does not.
- The unapplied forward migration was hardened without changing an applied migration: v2 directly computes receipt truth and effective state, rejects a `SINGLE_COHERENT` claim with zero raw measurements, never fabricates PRODUCT_STRUCTURE evidence for a MISSING observation, and preserves duplicate/stale immutability. The complete UNIQLO hierarchy proof now requires a processed/current receipt, matching audience, explicit full-breadcrumb marker, and exact noncyclic parent chain; auto-promoted v3 mappings are revalidated and deactivated on later conflict. PRODUCT_REQUIRED remains excluded.
- Migration ACL/preflight protections now cover the public authorization/readiness wrappers and renamed v1 functions: no PUBLIC/anon/authenticated execute, service-role-only access, fixed expected security mode, fixed search paths, and mutation-before-preflight is prevented. The active policy guard preserves the exact 32 `ADULT_ANY` / 7 anatomy-specific partition.
- Disposable PostgreSQL 17 applied the production-shaped chain plus `20260902031749` and reported `LIVE_RETAILER_GENERAL_CONTRACT_PASS`. The role matrix confirmed no PUBLIC/anon/authenticated execute for authorization, ingress v1/v2, or readiness wrappers; a deliberately invalid ingress ACL preimage failed before rename/policy mutation (`v1=0`, `v2=0`, `ADULT_ANY=0`). Production was never targeted for a write.
- Regression after the final exact provenance-envelope expectation update: `RetailerProductStructureContractTests` 13 PASS; current-batch DBLogic fixture test 1 PASS; `FitMatchSupabaseProductResolverTests` 22 PASS; frozen final scenario execution 36 PASS / 0 FAIL / 0 SKIP; full non-UI `FitMatchTests` XCResult summary 700 total / 663 PASS / 0 FAIL / 37 SKIP; iPhone 17 Pro app/test `build-for-testing` exited successfully; `git diff --check` is clean. The earlier full run's sole failure was the exact old structured-fact envelope; it was strengthened to expect the two new complete-breadcrumb provenance facts and the final full run passed.
- Production writes, migration deployment, Auth mutation, Edge deployment, commit, push, and protected TabBar/scroll changes are all `0`. The History visibility migration remains **NOT DEPLOYED**. Next action is only the requested limited independent re-review; do not deploy or commit from this handoff.
