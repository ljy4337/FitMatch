# Git publication scope — 2026-09-30

Publish the reviewed application/environment changes and missing release support files to main and QA. SQL files are archived, not executed.

## Retained locally, excluded from publication

- .build, temporary logs, research outputs and unrelated untracked work.
- FitMatchTests/Fixtures/ReleaseAuditPreviouslyCompleted20260930.json
- FitMatchTests/Fixtures/ReleaseAuditSessionHistory20260930.json
- FitMatchTests/FrozenReleaseHistoryAuditTests.swift (depends on the actual personal comparison snapshots above).

## Database boundary

Historical SQL, production metadata/ledger and generators are included. Do not replay historical migrations against the production bootstrap ledger. Original bootstrap SQL/seed files remain outside Git; this publication does not establish full database reproducibility.

## Verification

Git index exported to /tmp/fitmatch-clean-publication-20260930 for an app build without untracked source dependencies. See latest Handoff for the completed result. Production routing owner: six checks across production/QA conditions PASS. Dump preparation safety tests: seven PASS. Credential-pattern, staged diff and protected-scroll checks PASS. Device E2E and DB changes NOT RUN.

## Selected files

- `.gitignore`
- `Docs/CodexSessionHandoff.md`
- `Docs/FitMatchBuildEnvironments.md`
- `FitMatch Behavior Map.md`
- `FitMatch.xcodeproj/project.pbxproj`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatch-Production.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatch-QA.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchLiveUserJourney.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchLiveValidation.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchMusinsaReferenceAudit.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchReferenceClosetSetup.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchUniqloReferenceAudit.xcscheme`
- `FitMatch/FitMatch.entitlements`
- `FitMatch/Info.plist`
- `FitMatch/Services/FitMatchProductEntryRouting.swift`
- `FitMatch/Services/SharedURLStore.swift`
- `FitMatch/Services/VNextCompletedReplayPolicy.swift`
- `FitMatchShareExtension/FitMatchShareExtension.entitlements`
- `FitMatchShareExtension/Info.plist`
- `FitMatchShareExtension/ShareViewController.swift`
- `FitMatchTests/ClosetRegistrationDuplicateRawTests.swift`
- `FitMatchTests/FitMatchEnvironmentRoutingTests.swift`
- `FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests.swift`
- `FitMatchTests/FitMatchFinalReleaseProviderSnapshotTests.swift`
- `FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests.swift`
- `FitMatchTests/LiveReleaseRetailerProofTests.swift`
- `FitMatchTests/SuppliedLinkRawPreservationAuditTests.swift`
- `scripts/build-production-sql-bundle.py`
- `scripts/prepare-production-dump.py`
- `scripts/tests/test-prepare-production-dump.py`
- `supabase/migrations/20260916000904_explicit_cross_group_comparison_common_measurements.sql`
- `supabase/migrations/20260921090000_measurement_semantic_context_separation.sql`
- `supabase/migrations/20260923110000_same_comparison_group_only.sql`
- `supabase/migrations/20260924100000_linked_closet_size_snapshot_updates.sql`
- `supabase/migrations/20260924101000_closet_detail_snapshot_round_trip.sql`
- `supabase/migrations/20260924102000_comparison_history_tombstone_sync.sql`
- `supabase/migrations/20260924103000_retailer_exact_evidence_v2_preflight.sql`
- `supabase/migrations/20260924120000_closet_single_item_readback.sql`
- `supabase/migrations/20260924121000_runtime_skip_discarded_projections.sql`
- `supabase/migrations/20260924130000_selected_comparison_candidate.sql`
- `supabase/migrations/20260928160000_latest_comparison_result_per_product.sql`
- `supabase/migrations/20260929132500_verified_native_canonical_fallback.sql`
- `supabase/production-bootstrap/DATA-SCOPE.md`
- `supabase/production-bootstrap/FINAL-REVIEW.md`
- `supabase/production-bootstrap/PRODUCTION-COMPLETE.md`
- `supabase/production-bootstrap/README.md`
- `supabase/production-bootstrap/auth-trigger-review.sql`
- `supabase/production-bootstrap/data-selection-counts.json`
- `supabase/production-bootstrap/data-selection-counts.sql`
- `supabase/production-bootstrap/data-selection-fk-check.sql`
- `supabase/production-bootstrap/data-selection-fk-results.json`
- `supabase/production-bootstrap/data-selection-path-parity-results.json`
- `supabase/production-bootstrap/data-selection-path-parity.sql`
- `supabase/production-bootstrap/data-selection.json`
- `supabase/production-bootstrap/edge-functions-audit.json`
- `supabase/production-bootstrap/full-restore-verification.json`
- `supabase/production-bootstrap/inventory.sql`
- `supabase/production-bootstrap/manifest.json`
- `supabase/production-bootstrap/mcp-export-snapshot.sql`
- `supabase/production-bootstrap/mcp-transfer-proof.json`
- `supabase/production-bootstrap/production-apply-journal.json`
- `supabase/production-bootstrap/production-edge-auth-status.json`
- `supabase/production-bootstrap/production-function-normalization-check.json`
- `supabase/production-bootstrap/production-postflight-comparison.json`
- `supabase/production-bootstrap/production-postflight-counts.json`
- `supabase/production-bootstrap/production-postflight-inventory.json`
- `supabase/production-bootstrap/production-postflight-migrations.json`
- `supabase/production-bootstrap/remote-migration-ledger-audit.json`
- `supabase/production-bootstrap/seed-preflight.sql`
- `supabase/production-bootstrap/source-inventory-audit.json`
- `supabase/production-bootstrap/sql-bundle-manifest.json`
- `supabase/production-bootstrap/target-inventory-before.json`
- `supabase/sql/20260923_same_comparison_group_only_Rollback.sql`
- `supabase/sql/20260923_same_comparison_group_only_Verify.sql`
- `supabase/sql/20260924100000_linked_closet_size_snapshot_updates_Rollback.sql`
- `supabase/sql/20260924100000_linked_closet_size_snapshot_updates_Verify.sql`
- `supabase/sql/20260924101000_closet_detail_snapshot_round_trip_Rollback.sql`
- `supabase/sql/20260924101000_closet_detail_snapshot_round_trip_Verify.sql`
- `supabase/sql/20260924102000_comparison_history_tombstone_sync_Rollback.sql`
- `supabase/sql/20260924102000_comparison_history_tombstone_sync_Verify.sql`
- `supabase/sql/20260924103000_retailer_exact_evidence_v2_preflight_Rollback.sql`
- `supabase/sql/20260924103000_retailer_exact_evidence_v2_preflight_Verify.sql`
- `supabase/sql/20260924120000_closet_single_item_readback_Rollback.sql`
- `supabase/sql/20260924121000_runtime_skip_discarded_projections_Rollback.sql`
- `supabase/sql/20260924130000_selected_comparison_candidate_Rollback.sql`
- `supabase/sql/20260924_registration_performance_Verify.sql`
- `supabase/sql/20260924_selected_comparison_candidate_Verify.sql`
- `supabase/sql/core_registration_candidate_contract_Apply.sql`
- `supabase/sql/core_registration_candidate_contract_Verify.sql`
- `supabase/sql/cross_group_outerwear_domain_Apply.sql`
- `supabase/sql/cross_group_outerwear_domain_Verify.sql`
- `supabase/sql/explicit_cross_group_comparison_Apply.sql`
- `supabase/sql/explicit_cross_group_comparison_Verify.sql`
- `supabase/sql/latest_comparison_result_per_product_Rollback.sql`
- `supabase/sql/latest_comparison_result_per_product_Verify.sql`
- `supabase/sql/measurement_dictionary_verified_zara_Apply.sql`
- `supabase/sql/measurement_dictionary_verified_zara_Verify.sql`
- `supabase/sql/measurement_semantic_context_separation_Verify.sql`
- `supabase/sql/musinsa_bottom_total_length_Apply.sql`
- `supabase/sql/musinsa_bottom_total_length_Verify.sql`
- `supabase/sql/retailer_category_group_approved_20260916_Apply.sql`
- `supabase/sql/retailer_category_group_approved_20260916_Rollback.sql`
- `supabase/sql/retailer_category_group_approved_20260916_Verify.sql`
- `supabase/sql/retire_reference_candidate_authority_Apply.sql`
- `supabase/sql/tests/20260924_comparison_candidates_Baseline.sql`
- `supabase/sql/tests/20260924_comparison_candidates_Regression.sql`
- `supabase/sql/tests/20260924_comparison_history_tombstone_sync_LocalRegression.sql`
- `supabase/sql/tests/20260924_linked_closet_snapshot_round_trip_LocalRegression.sql`
- `supabase/sql/tests/20260924_performance_before_fixture.sql`
- `supabase/sql/tests/20260924_performance_tables_fixture.sql`
- `supabase/sql/tests/20260924_registration_performance_LocalRegression.sql`
- `supabase/sql/tests/20260924_retailer_exact_evidence_v2_preflight_LocalRegression.sql`
- `supabase/sql/tests/closet_raw_measurement_snapshots_LocalRegression.sql`
- `supabase/sql/tests/cross_group_outerwear_domain_Regression.sql`
- `supabase/sql/tests/explicit_cross_group_comparison_Regression.sql`
- `supabase/sql/tests/measurement_semantic_context_separation_LocalRegression.sql`
- `supabase/sql/tests/retired_reference_candidates_LocalRegression.sql`
- `supabase/sql/tests/same_comparison_group_only_Regression.sql`
- `supabase/sql/tests/same_comparison_group_only_RollbackRegression.sql`
- `supabase/sql/tests/uniqlo_front_length_airism_LocalRegression.sql`
- `supabase/sql/tests/verified_native_canonical_fallback_Regression.sql`
- `supabase/sql/tests/zara_exact_category_identity_LocalRegression.sql`
- `supabase/sql/uniqlo_front_length_airism_Apply.sql`
- `supabase/sql/uniqlo_front_length_airism_Verify.sql`
- `supabase/sql/uniqlo_path_zara_skirt_20260916_Apply.sql`
- `supabase/sql/uniqlo_path_zara_skirt_20260916_Verify.sql`
- `supabase/sql/verified_native_canonical_fallback_Rollback.sql`
- `supabase/sql/verified_native_canonical_fallback_Verify.sql`
- `supabase/sql/zara_exact_category_identity_Apply.sql`
- `supabase/sql/zara_top_chest_alias_Apply.sql`
- `supabase/sql/zara_top_chest_alias_Verify.sql`
