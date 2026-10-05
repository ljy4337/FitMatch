# Release asset repair - 2026-10-05

## Changes
- Latest-main work branch codex/fix-release-assets-20261005, HEAD b0c9088; persistent checkout /Users/jinyoung/Developer/FitMatchLocal/FitMatchReleaseAssetRepair.
- Renamed three AppIcon and three SplashBackground image files to ASCII, updated their Contents.json references. Six SHA-256 hashes match original Git image bytes. No images, layouts, colors, interactions or app logic changed.
- Existing archive auditor now rejects missing primary AppIcon metadata; its existing argument/version regression adds missing/present icon cases. A synthetic unsigned bundle remains rejected.
- No commit/push/QA integration/main promotion. Original dirty work and clean main release checkout remain untouched.

## Verification
- Expected FAIL before auditor fix: new missing-icon regression exit 1. PASS afterward: seven archive argument/version/icon cases. bash -n PASS.
- PASS: real actool compile, no icon/splash warnings; partial plist contains AppIcon and assetutil names contain AppIcon/SplashBackground.
- PASS: actual xcodebuild Production Release generic iOS unsigned build exit 0. Log /private/tmp/FitMatchReleaseAssetRepair20261005-build.log. Generated app contains AppIcon PNG, AppIcon/SplashBackground in Assets.car, CFBundleIcons AppIcon, operational bundle ID and Production URL aqhrupgjpmrtnystottx. The prior shared DerivedData build products now contain this repaired work-branch build, not unchanged main artifacts.
- PASS: six file hashes and JSON references, git diff --check and protected-scroll checks.
- PASS: separately rerun provenance SQL safety/mapped/session/ACL/rollback and comparison_preview 14-case regression in PGlite. Isolated helper fixtures, not authenticated E2E.
- PASS: subsequent explicit user approval resolved the Production blocker. Production comparison_target_context repair applied once under remote migration 20261005105711; deployed hash/definition and privileges now match development. Separate evidence: /Users/jinyoung/Developer/FitMatchLocal/FitMatchPolicyRepair/Docs/QA/ProductionProvenanceApplied20261005.json. User rows/UI/scoring unchanged; development not reapplied.
- NOT RUN: authenticated A-E/full Release Gate, signed archive/export/upload and branch promotion.

## Remaining
Approved QA/main integration after required verification. Main itself does not yet contain the asset fix. Production DB repair is already applied, not a remaining approval request. No claim of release-ready or device E2E.
