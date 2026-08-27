# FitMatch Classification Production Deployment — 2026-08-26

## Final status

`PRODUCTION CLASSIFICATION AUTHORITY DEPLOYMENT = GO`

The owner-approved 119 corrective migration was applied after exact checksum and Production preimage verification. Candidate and rollback-successor gates passed, the atomic v4 activation committed after its transaction-critical smoke, and all SELECT-only Production postflight checks passed. No rollback was required and no half-active state occurred.

## Operator and artifacts

- Repository HEAD: `c251b2a824b9a99e2f99b809f2cb23cb1721c9ab`
- Branch: `connectDB`
- Operator: Codex through the authenticated Supabase Production connection
- Production project: `hnkplvyegonlhumlejst`
- Final postflight window: `2026-08-26T13:12:16Z` through `2026-08-26T13:28:36Z`
- Immutable 118 SHA-256: `0eb9bfe801fd26bc33c084f5b9921aaf32aa5dc9b9c44a7ebfa17b7a3ccf5fb6`
- Approved 119 SHA-256: `0c873e441eed10e68b01fbaaed24b420e84395140fe8eff495f879e87b417df5`
- Atomic activation artifact SHA-256: `177b57b242d65a7f5817b0cdf060cec6d99acf9b9539cadd2d3401a7173b13a9`
- Atomic rollback artifact SHA-256: `b36d0cb040c893aa4fd2609f1a965fd46cca99a63ae942bde8e436c384ed782b`
- Rollback-successor artifact SHA-256: `f6b15381bfe69c1d52487ccd4f5474c38fcb0853dbc3623671064804d91d77ed`

## Preflight and encrypted rollback preimage

Production preflight was exact immediately before the first 119 write:

- Products and unique keys: `1,608 / 1,608`
- Product fingerprint checksum: `c1ed8a45c6548149b1b434c3551a4a674b41e627a642f6ed72db7ea55bee061a`
- Decisions: `5,056`; targeted manifest preimage: `121`
- Targeted decision xmin checksum: `9d15941dd7fc4dd2221f76c9d2392ff4676474cea6f8e10602d1f1dbd79e25d8`
- History/current: `1,860 / 1,608`
- Existing active release: exactly one, `65d72393-4a40-4e99-b701-fdc1ff865774`
- Existing active mappings: `3,492`
- Final candidate: validated/inactive with `3,509` mappings
- 119 ledger/successor before apply: absent/absent
- Candidate sole blocker: `measurement_policy_checksum_mismatch`

Encrypted backup files remained outside the repository at `/private/tmp/FitMatchClassificationProductionPreimage-20260826`, mode `0600`, with successful AES-256-CBC/PBKDF2 read-back:

- Main cipher SHA-256: `844fec409490a04c4a14ea0ccdb22da6c130facf806ff27b8be8bd288522e22b`
- Main decrypted/read-back SHA-256: `22d34b6889f14dcf4de66eeed649be85e981dfcd6290ca10b3954da169c3314d`
- Legacy-taxonomy cipher SHA-256: `253a088456b9a34e58bc9a53b55dd38c23fe860dfb1f45e860e08f5a5a00a6f2`
- Legacy-taxonomy decrypted/read-back SHA-256: `64c248aeb55692adb362e5db8735c6c22c796b1bb77bdf07eaeaab92fe1dcd39`
- Recoverable logical-key preimages include active mappings `3,492`, targeted decisions `121`, and function definitions/owner/grant/security metadata `19`.

## 119 controlled apply

- Ledger version: `20260826131310`
- Ledger name: `classification_measurement_policy_checksum_correction`
- 118 file and ledger were not changed or reapplied.
- Measurement policy rows remained `63` and no measurement policy value was updated.
- Production raw checksum remained `6ad654049b08f6d19bd6a59c2a50482f550ee9edf6a0b9faad5d6f74b31a18a2`.
- Canonical semantic checksum became `42d5aa308b2138e0aa844ae12268125a0f5ef47ce35f9f187e082be7511c13f0`.
- `runtime_policy_contract_report_v1` retained owner `postgres`, `STABLE`, `SECURITY INVOKER`, empty `search_path`, and service-role-only execution.
- Policy gate, final gate, and release gate all returned `eligible=true`, `blockers=[]`.
- Old parent remained active until the later atomic activation transaction.

## Rollback successor

- Release ID: `11800000-0000-4000-8000-00000000b001`
- Release key: `fitmatch-classification-rollback-successor-2026-08-26-v1`
- Final status: `validated`, inactive
- Mapping rows: `3,492`
- Source/successor mapping checksum: `28a7700805e95d9e643b0cb860770fde8e12acd86057cace879082ff82a307f2`
- Release gate: `eligible=true`, `blockers=[]`
- History and decision counts were unchanged during successor creation.

## Atomic activation

The checked activation artifact ran as one transaction with advisory lock, release-row locks, exact preimage assertions, candidate/successor gate assertions, targeted-decision materialization, function switch, release-pointer switch, full-shadow critical smoke, and history-count postcondition.

- Candidate `11800000-0000-4000-8000-000000000118`: `validated → active`
- Previous active parent `65d72393-4a40-4e99-b701-fdc1ff865774`: `active → retired`
- Active release count after commit: exactly `1`
- Active mappings: `3,509`
- Targeted decisions: `121/121` null-safe semantic exact
- Total decisions: unchanged `5,056`
- History/current: unchanged `1,860 / 1,608`
- History bulk backfill/delete: `0 / 0`
- Rollback invoked: no

## Classification and policy smoke

The transaction-critical smoke and an independent Production SELECT-only 1,608-product shadow both passed:

- Distribution: `348 confirmed / 1,113 review_required / 147 not_comparable`
- Source distribution:
  - Musinsa: `121 / 266 / 7`
  - UNIQLO: `227 / 817 / 140`
  - ZARA: `0 / 30 / 0`
- Gold: `3/3 PASS`
- Set: `7/7 not_comparable`; garment/comparison leak `0`
- Structured discriminator: `7` confirmed
- Structured exclusion: `54` not comparable, including UNIQLO typed accessory `47`
- Verified path/profile methods: path `65`, exclusion `93`, unverified profile confirmed `0`
- Confirmed invalid tuple: `0`
- Confirmed with authority conflict: `0`
- Arbitrary unknown confirmed: `0`
- Comparison: `tshirt ↔ base_layer_top BLOCK`, `sweatshirt ↔ hoodie ALLOW`, `homewear_top ↔ homewear_bottom BLOCK`
- Mapping scopes: `CATEGORY_DIRECT 55 / PRODUCT_REQUIRED 1,019 / REVOKED 2,435`
- Structured/path/name/exclusion rows: `21 / 12 / 0 / 15`
- Comparison matrix: `990`
- Measurement policies: `63`

The candidate gate also retains the Closure evidence for synthetic fixtures `29/29 PASS` and all recorded safety-leak counts `0`.

## RPC and security smoke

- `fitmatch_get_product_runtime` executed under an isolated non-customer authenticated claim and returned active release `11800000-0000-4000-8000-000000000118`; Gold `E482514` resolved as confirmed `tops/tshirt/short_sleeve` through `canonical_product_decision`.
- Its runtime state was `classification_promotion_required`, which is expected because this deployment intentionally performed no v4 history backfill.
- `fitmatch_find_reference_candidates` executed read-only and returned `target_classification_required` against the same active release, also expected until a new v4 observation is recorded.
- `fitmatch_list_closet_items` returned zero rows for the isolated claim and did not touch customer data.
- Public resolver/get-runtime definitions call resolver v4; promoter/process-observation call the updated promoter and recorder v2; reference-candidate/begin-comparison definitions call evaluator v4.
- Function owners, fixed search paths, SECURITY DEFINER/INVOKER mode, and anon/authenticated/service-role grants matched the approved contract. Anon execution on the activated public authority RPCs is disabled.
- Write-oriented closet/comparison RPCs were contract/security checked without creating dummy Production customer records.
- Product intake, closet, and comparison-run counts remained `3 / 6 / 0` across the smoke.

## Final Production state

Final stability postflight at `2026-08-26T13:28:36.784812Z`:

- Ledger 118: `20260826090118 / classification_db_final_closure`
- Ledger 119: `20260826131310 / classification_measurement_policy_checksum_correction`
- Active release: `11800000-0000-4000-8000-000000000118`
- Active release count: `1`
- Active mappings: `3,509`
- Product decisions: `5,056`
- Classification history/current: `1,860 / 1,608`
- Rollback successor: validated/inactive and gate PASS
- Candidate/final/policy gates: PASS, blockers `[]`
- Runtime: resolver v4, evaluator v4, recorder v2
- Production history bulk backfill/delete: `0 / 0`
- Swift/iOS behavior changes: `0`
- Git commit/push: `0`

The remaining implementation work is the separately scoped iOS Closet/Compare server-authority integration and subsequent app/device validation. No additional classification DB audit is required.
