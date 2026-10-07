# Policy authority repair — 2026-10-05

## Applied / Prepared
- Work branch: codex/fix-policy-authority-20261005, from origin/main b0c908822702bf11f3d2a620ee5d8a0620d0a351.
- Persistent isolated checkout: /Users/jinyoung/Developer/FitMatchLocal/FitMatchPolicyRepair.
- Original checkout and dirty documentation preserved. No commit/push/merge or QA/main promotion.
- Development hnkplvyegonlhumlejst: APPLIED repair_comparison_group_provenance, remote migration 20261005095512.
- Production aqhrupgjpmrtnystottx: APPLIED after the user's explicit scoped approval. Remote migration 20261005105711. The earlier safety rejection and approval blocker are resolved; no retry occurred before this approval.
- Local migration 20261005095057_repair_comparison_group_provenance.sql is prepared, tested and now applied to development and Production under their separate remote ledger versions.

## Change
comparison_target_context reads mapping_source instead of source. It preserves RETAILER_CATEGORY and PRODUCT_OVERRIDE and rejects missing/unknown mapped provenance. Explicit session selection remains SESSION_USER_SELECTED. Group, policy, hierarchy, structure, scoring, owner and grants remain unchanged. Existing completed History is not rewritten. Old PRODUCT_OVERRIDE contexts have a stale fingerprint and require fresh server verification.

## Verification
- Expected FAIL before repair: isolated real SQL reported PRODUCT_OVERRIDE as RETAILER_CATEGORY.
- PASS after repair: real context SQL runs in PGlite 0.3.14 with isolated dependency fixtures. Covers mapped/override/unmapped/session, source rejection, changed group fingerprint, old override fingerprint, excluded product, variant mismatch, structure exclusion, inactive policy, ACL preservation, and guarded rollback.
- PASS: existing comparison_preview_20260928.mjs 14-case regression (stub policy/eligibility helpers, not authenticated E2E).
- PASS: development deployed definition hash 64fa01b9fdba8224476bf0bb51d4f6bc, source/fail-closed checks, exact signature/ACL/SECURITY DEFINER/search_path preserved; anon EXECUTE false.
- PASS: Production hash 64fa01b9fdba8224476bf0bb51d4f6bc equals development. All three fix flags true; owner/signature/ACL/SECURITY DEFINER/search_path/anon/authenticated/service_role privileges match preflight. Remote ledger receipt verified. Fresh isolated provenance test PASS. Evidence ProductionProvenanceApplied20261005.json.
- NOT RUN: app build, authenticated Closet/comparison E2E, full QA Release Gate.
- No retailer mapping, user, Closet, comparison or History row changes.

## Musinsa mapping
- Missing draft keys 54: A5/B16/C12/D5/E8/F7/G1.
- musinsa:003008 already matches an existing runtime category path and C group. Actual new paths 53.
- Draft notes explicitly require current live API and product regression before activation.
- BLOCKED: curl category 100004 and app details API 7122627 both HTTP 403. Normal browser category page loads and displays current products; direct observed-product 7309004 details API browser navigation returns ERR_BLOCKED_BY_CLIENT. A category listing is not proof of parser/API exact classification or measurement structure.
- No automatic promotion of drafts or product-name inference. Candidate list archived in MusinsaPendingCategoryReview20261005.json.

## Security advisors
Development advisor scan succeeded. Three existing exposed authenticated SECURITY DEFINER functions and disabled leaked-password protection were reported; the repaired private function was not among those exposed-function findings. No permission/Auth changes were made. No claim that all security warnings were resolved.
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## Remaining
1. Obtain accessible current Musinsa API category evidence for the new paths, then validate scoped mapping migration in development.
2. Authenticated QA acceptance and final branch promotion are separate from SQL test success.

## Production Advisor Postflight
Existing INFO RLS-without-policy 14, WARN anonymous SECURITY DEFINER 1, authenticated SECURITY DEFINER 4, and leaked password protection disabled 1 remain. Repaired private function is not in exposed-function findings. No Auth/security settings changed and no claim that all security notices were resolved.
- [Anonymous function advisory](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable)
- [Authenticated function advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
- [Password protection advisory](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
