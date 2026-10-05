# FitMatch Markdown 파일 목록

확인일: 2026-10-03. `git ls-files -z '*.md'`, `git ls-files --others --exclude-standard '*.md'`, `rg --files -g '*.md'` 결과를 대조했다. Git 추적은 파일 관리 여부이며 현행 정책/최신성 승인과 다르다. 조회된 ignore 문서는 별도 분류하며 저장소 밖 문서는 포함하지 않는다.

Git 추적 218개, 로컬 미추적 2개(신규 기준 문서와 이 목록), Git ignore된 과거 인계 문서 1개. 조회된 총 221개. macOS 한글 파일명의 Unicode 정규화 차이는 동일 경로로 대조했다.

## 현행 기준 문서

- `AGENTS.md`
- `FitMatch Behavior Map.md`
- `FitMatch Swift Feature Map.md`
- `Docs/FitMatchMeasurementPolicy.md`
- `Docs/FitMatchReleaseGate.md`
- `Docs/CodexSessionHandoff.md`
- `Docs/FitMatchBuildEnvironments.md`

## Git 추적 파일

### root

- `AGENTS.md`
- `FitMatch Behavior Map.md`
- `FitMatch Swift Feature Map.md`
- `FitMatch-ZARA-Phase1.5-Blocker-Resolution-20260821.md`
- `FitMatch_Hardcoded_Product_Classification_Audit_20260828.md`

### Docs

- `Docs/AppStorePrivacyPolicyDraft-20260806.md`
- `Docs/AppStoreReadiness-20260806.md`
- `Docs/AppStoreSubmissionRunbook-20260806.md`
- `Docs/Architecture.md`
- `Docs/Backlog.md`
- `Docs/BottomMeasurementComparisonPolicy.md`
- `Docs/ButtonExceptionCopyAudit.md`
- `Docs/COSIntegrationAnalysis-20260821.md`
- `Docs/CategoryTaxonomyAuditAndDatabaseDesign-20260803.md`
- `Docs/CodexSessionHandoff.md`
- `Docs/ConnectDBPhysicalE2EChecklist-20260820.md`
- `Docs/CoreFlowLiveAudit-20260915.md`
- `Docs/CurrentSprint.md`
- `Docs/CurrentUniqloCatalogATestReport-20260815.md`
- `Docs/CurrentUniqloProductCategoryCatalog-20260815.md`
- `Docs/DBOptimizationPlan-20260815/README.md`
- `Docs/DataSupport/FitMatch_데이터지원명세.md`
- `Docs/DataSupport/보완대장.md`
- `Docs/DataSupport/실측연결목록.md`
- `Docs/DataSupport/원본실측등록목록.md`
- `Docs/DataSupport/카테고리목록.md`
- `Docs/Decisions.md`
- `Docs/FitMatch-ZARA-Phase1-Production-Audit-20260821.md`
- `Docs/FitMatchBuildEnvironments.md`
- `Docs/FitMatchClassificationConflictCohortAdjudication-20260826.md`
- `Docs/FitMatchClassificationDBClosure-20260826.md`
- `Docs/FitMatchClassificationGlobalBaseline-20260825.md`
- `Docs/FitMatchClassificationMeasurementPolicyChecksumCorrection-20260826.md`
- `Docs/FitMatchClassificationPhase1A5Adjudication-20260825.md`
- `Docs/FitMatchClassificationPhase1B1Foundation-20260825.md`
- `Docs/FitMatchClassificationPhase1B1Validation-20260825.md`
- `Docs/FitMatchClassificationPhase1B2Candidate-20260826.md`
- `Docs/FitMatchClassificationPhase1B2R-20260826.md`
- `Docs/FitMatchClassificationProductionDeployment-20260826.md`
- `Docs/FitMatchClassificationProductionDeploymentReady-20260826.md`
- `Docs/FitMatchClassificationReviewEvidenceAudit-20260826.md`
- `Docs/FitMatchContractClosure5GapResult-20260907.md`
- `Docs/FitMatchDBRuntimeContract-20260818.md`
- `Docs/FitMatchDevelopmentReport.md`
- `Docs/FitMatchMeasurementPolicy.md`
- `Docs/FitMatchMeasurementStandardV1.md`
- `Docs/FitMatchProjectStatus.md`
- `Docs/FitMatch_External_Product_Storage_ReadOnly_Audit_20260821.md`
- `Docs/FitMatch_무신사_유니클로_데이터_및_출시검증_리포트_20260806.md`
- `Docs/GitPublicationScope-20260930.md`
- `Docs/HomeDeviceQAChecklist.md`
- `Docs/LiveUserJourneyBugReport-20260806.md`
- `Docs/MeasurementBasisPolicy-20260911.md`
- `Docs/OuterMeasurementComparisonPolicy.md`
- `Docs/PhysicalA200Report-20260814.md`
- `Docs/ProductVision.md`
- `Docs/QA/20260915/README.md`
- `Docs/QA/20260915/cleanup-executed/README.md`
- `Docs/QA/20260915/cleanup-review.md`
- `Docs/QA/20260915/repair/README.md`
- `Docs/QA/20260915/repair/slacks-server-applied.md`
- `Docs/QA/20260915/root-cause-analysis.md`
- `Docs/QA/20260924-Comparison-Performance-Plan.md`
- `Docs/QA/20260924-Comparison-Performance.md`
- `Docs/QA/20260924-FiveRepairsMigrationManifest.md`
- `Docs/QA/20260924-NonE2E-Release-Closure-Plan.md`
- `Docs/QA/20260924-Registration-Performance.md`
- `Docs/QA/20260924-Release-Technical-Score.md`
- `Docs/QA/20260928-Comparison-Reuse.md`
- `Docs/QA/AppStorePreparation20261002.md`
- `Docs/QA/ApprovedSafeRepair-20260916.md`
- `Docs/QA/AuthenticatedJourney-20260916.md`
- `Docs/QA/ClothingURLs-20260916/README.md`
- `Docs/QA/DevelopmentDBCleanupAudit-20260930/Report.md`
- `Docs/QA/FirstReleaseAudit-20260929.md`
- `Docs/QA/FirstReleaseChecklist-20260929.md`
- `Docs/QA/FirstReleaseFrozenDataLogicAudit-20260930.md`
- `Docs/QA/FirstReleaseRepairPlan-20260929.md`
- `Docs/QA/FitMatchProductionMigrationReview-20260930.md`
- `Docs/QA/HistoryRestoreRepair-20260930.md`
- `Docs/QA/LiveReleaseProof-20260930/Report.md`
- `Docs/QA/MainMergeAudit20261002.md`
- `Docs/QA/MeasurementDictionaryReinforcement-20260916.md`
- `Docs/QA/MeasurementMasterLaunch-20260916/검토보고서.md`
- `Docs/QA/MeasurementRepairHandoff-20260921/README.md`
- `Docs/QA/MeasurementRepairHandoff-20260921/Terra-Prompt.md`
- `Docs/QA/MeasurementSemanticAudit-20260921-Evidence/confirmed-aliases.md`
- `Docs/QA/MeasurementSemanticAudit-20260921.md`
- `Docs/QA/Phase2RepairVerification-20260929.md`
- `Docs/QA/Phase3ReleasePreparation-20260929.md`
- `Docs/QA/ReleaseAuditV2-20260916.md`
- `Docs/QA/ReleasePreparation20261002/AuthReadiness.md`
- `Docs/QA/ReleasePreparation20261002/AuthenticatedCoverage.md`
- `Docs/QA/ReleasePreparation20261002/AuthenticatedGapAudit.md`
- `Docs/QA/ReleasePreparation20261002/CleanupPreparation20.md`
- `Docs/QA/ReleasePreparation20261002/Continuation20Report.md`
- `Docs/QA/ReleasePreparation20261002/CoreCoverage.md`
- `Docs/QA/ReleasePreparation20261002/DBPreparation.md`
- `Docs/QA/ReleasePreparation20261002/DataInventory.md`
- `Docs/QA/ReleasePreparation20261002/DataPreparationAudit.md`
- `Docs/QA/ReleasePreparation20261002/DedicatedAccountReadiness.md`
- `Docs/QA/ReleasePreparation20261002/DevelopmentSeedPreparation.md`
- `Docs/QA/ReleasePreparation20261002/ExpectationAudit.md`
- `Docs/QA/ReleasePreparation20261002/FaultStateCoverage.md`
- `Docs/QA/ReleasePreparation20261002/LifecycleCoverage.md`
- `Docs/QA/ReleasePreparation20261002/MatrixCoverage.md`
- `Docs/QA/ReleasePreparation20261002/NumericBoundaries.md`
- `Docs/QA/ReleasePreparation20261002/P03UIExecution.md`
- `Docs/QA/ReleasePreparation20261002/PendingReport.md`
- `Docs/QA/ReleasePreparation20261002/PendingTests.md`
- `Docs/QA/ReleasePreparation20261002/PhoneAuthPreparation.md`
- `Docs/QA/ReleasePreparation20261002/PreparationChanges.md`
- `Docs/QA/ReleasePreparation20261002/PreparationCoverage20.md`
- `Docs/QA/ReleasePreparation20261002/README.md`
- `Docs/QA/ReleasePreparation20261002/Report.md`
- `Docs/QA/ReleasePreparation20261002/Resume15Report.md`
- `Docs/QA/ReleasePreparation20261002/Resume20Report.md`
- `Docs/QA/ReleasePreparation20261002/Resume30Changes.md`
- `Docs/QA/ReleasePreparation20261002/Resume30Report.md`
- `Docs/QA/ReleasePreparation20261002/Resume40Report.md`
- `Docs/QA/ReleasePreparation20261002/ResumeReport.md`
- `Docs/QA/ReleasePreparation20261002/ScorePolicyDecision.md`
- `Docs/QA/ReleasePreparation20261002/SessionPreparationReport.md`
- `Docs/QA/ReleasePreparation20261002/SessionSetup.md`
- `Docs/QA/ReleasePreparation20261002/TaskCancellationCoverage.md`
- `Docs/QA/ReleasePreparation20261002/TestSpecification.md`
- `Docs/QA/ReleasePreparation20261002/TransportFaultCoverage.md`
- `Docs/QA/ReleasePreparation20261002/UserChecklist.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Continuation20/preflight/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/FitMatchPrepFinalPreflight/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/FitMatchPrepResumeFinal/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/FitMatchPrepResumePreflight/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/FitMatchPrepResumeSmoke/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/FitMatchPrepSmoke1/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/FitMatchPrepSmoke2/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/FitMatchPrepSmoke3/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/FitMatchPrepSmokeFinal/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Pending20261002/FitMatchPendingSmokeChecked/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Pending20261002/FitMatchPendingSmokeFinal/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Pending20261002/FitMatchPendingSmokeVerified/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Resume20/smoke/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Resume30/preflight/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Resume30/smoke/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Resume40/FitMatchResume40CleanupNoCredentials/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/Resume40/FitMatchResume40Combined/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/SessionPreparation/FitMatchContinuationPreflight/report.md`
- `Docs/QA/ReleasePreparation20261002/evidence/SessionPreparation/FitMatchContinuationPreflightHost/report.md`
- `Docs/QA/ReportedProductRegression-20260917.md`
- `Docs/QA/RetailerCategoryMeasurements-20260917/README.md`
- `Docs/QA/RetailerDictionaryGap-20260921/Report.md`
- `Docs/QA/SuppliedLinksAudit-20260930/Report.md`
- `Docs/QA/UniqloFrontLengthAirism-20260917.md`
- `Docs/QA/UniqloPathZaraSkirtRepair-20260916.md`
- `Docs/QA/ZaraMappingRegression-20260916.md`
- `Docs/README.md`
- `Docs/ReleaseATestReport-20260815.md`
- `Docs/ReleaseNote.md`
- `Docs/Research/CanonicalTaxonomyBundle-20260803/FitMatchCanonicalBundleApplicationPlan.md`
- `Docs/Research/CanonicalTaxonomyBundle-20260803/FitMatchReviewRequiredClassificationReport.md`
- `Docs/Research/CategoryCorpus-balanced-analysis-20-20-10-10/analysis_report.md`
- `Docs/Research/CategoryCorpus-bootstrap/collection_summary.md`
- `Docs/Research/CategoryCorpus-bootstrap/raw/README.md`
- `Docs/Research/FitMatchCategoryMappingV2-20260824-shadow/README.md`
- `Docs/Research/LiveProductSurvey-20260723/report.md`
- `Docs/Research/LiveProductSurvey-20260723/sources.md`
- `Docs/Research/LiveProductSurvey-20260723/verification.md`
- `Docs/Research/OfficialTaxonomySnapshot-20260803/IdentityResolutionAndRiskSamplingReport.md`
- `Docs/Research/OfficialTaxonomySnapshot-20260803/ProductSamplingPlan.md`
- `Docs/Research/OfficialTaxonomySnapshot-20260803/StagingImportExecutionReport.md`
- `Docs/Research/OfficialTaxonomySnapshot-20260803/TaxonomyCompletenessReport.md`
- `Docs/Research/OfficialTaxonomySnapshot-20260803/final-classification/final-classification-report.md`
- `Docs/Research/RuntimeClassificationParity-20260806.md`
- `Docs/Research/SupabaseSecurityReview-20260806.md`
- `Docs/Research/measurement-length-thresholds.md`
- `Docs/ResultScreenPerformanceAudit.md`
- `Docs/ShareExtensionSetup.md`
- `Docs/Taxonomy.md`
- `Docs/UniversalLinksSetup.md`
- `Docs/ZARAIntegrationAnalysis-20260821.md`
- `Docs/flows/00_UserActionIndex.md`
- `Docs/flows/01_AppLifecycleFlow.md`
- `Docs/flows/02_AuthenticationFlow.md`
- `Docs/flows/03_NavigationFlow.md`
- `Docs/flows/04_HomeFlow.md`
- `Docs/flows/05_ClosetFlow.md`
- `Docs/flows/06_ReferenceGarmentFlow.md`
- `Docs/flows/07_ProductRegistrationFlow.md`
- `Docs/flows/08_URLInputFlow.md`
- `Docs/flows/09_ShareExtensionFlow.md`
- `Docs/flows/10_MusinsaParsingFlow.md`
- `Docs/flows/11_RecommendationFlow.md`
- `Docs/flows/12_FitConfidenceFlow.md`
- `Docs/flows/13_ResultFlow.md`
- `Docs/flows/14_HistoryFlow.md`
- `Docs/flows/15_RecommendTabFlow.md`
- `Docs/flows/16_SwiftDataCRUDFlow.md`
- `Docs/flows/17_ErrorExceptionFlow.md`
- `Docs/flows/18_StateTransitionFlow.md`
- `Docs/flows/19_UnreachableFeatureReport.md`
- `Docs/flows/20_ImplementationGapReport.md`
- `Docs/flows/21_TestCaseMatrix.md`
- `Docs/flows/README.md`
- `Docs/superpowers/plans/2026-09-24-five-confirmed-repairs.md`
- `Docs/superpowers/plans/2026-09-28-uniqlo-kr-catalog-collector.md`
- `Docs/superpowers/specs/2026-09-28-uniqlo-kr-catalog-design.md`
- `Docs/무신사_유니클로_카테고리별_사이즈저장_비교표.md`
- `Docs/유니클로_무신사_FitMatch_사이즈형식.md`
- `Docs/유니클로_하의_원본분류_FitMatch변환표.md`

### FitMatch_Hardcoded_Product_Classification_Ledger_20260828_parts

- `FitMatch_Hardcoded_Product_Classification_Ledger_20260828_parts/README.md`

### data

- `data/reports/comparison-category-groups-20260911/README.md`

### scripts

- `scripts/category-corpus/README.md`

### supabase

- `supabase/production-bootstrap/DATA-SCOPE.md`
- `supabase/production-bootstrap/FINAL-REVIEW.md`
- `supabase/production-bootstrap/PRODUCTION-COMPLETE.md`
- `supabase/production-bootstrap/README.md`

### 카테고리

- `카테고리/README_MUSINSA_COLLECTION.md`
- `카테고리/musinsa_collection_report.md`
- `카테고리/uniqlo_collection_report.md`

## 로컬 미추적 파일

- `Docs/FitMatchMarkdownInventory.md`
- `Docs/FitMatchReleaseGate.md`

## Git ignore된 과거 문서

- `Docs/CodexSessionHandoff-20260810.md` (현행 인계서가 아닌 로컬 보관본)
