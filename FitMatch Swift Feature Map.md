# FitMatch Swift Feature Map

This document is repository navigation for coding agents. It is not a chronological project log and does not override AGENTS.md.

Use it selectively:

• Consult the relevant section before broad repository searches.
• Inspect actual call sites before changing behavior.
• Treat ownership descriptions as navigation hints, not permission to edit every listed file.
• When file ownership materially changes, update this map in the same task.
• Current product/UX policy and recent implementation state belong in Docs/CodexSessionHandoff.md; stable operating rules belong in AGENTS.md.

────────

## App Root / Authentication / Startup

### FitMatch/FitMatchApp.swift

App bootstrap and application-level setup.

### FitMatch/ContentView.swift

Primary authenticated application root.

Owns/co-ordinates major root concerns including:

• authentication presentation
• onboarding/root presentation
• authenticated cache ownership preparation
• Closet synchronization
• comparison/history synchronization
• startup migration/recovery
• deep-link/share handoff
• main tab/root presentation

Do not move domain comparison/classification policy into ContentView.

Related services:

• FitMatch/Services/FitMatchAuthSessionStore.swift
• FitMatch/Services/FitMatchAuthenticatedRootPresentationAction.swift
• FitMatch/Services/FitMatchStartupAction.swift
• FitMatch/Services/FitMatchClosetSyncCoordinator.swift
• FitMatch/Services/FitMatchComparisonSyncCoordinator.swift
• FitMatch/Services/SharedURLStore.swift

### FitMatch/Views/AppTab.swift

Main tab identity/model.

────────

## Home

### FitMatch/Views/HomeView.swift

Home-screen presentation and Home entry interactions.

Do not duplicate Closet, classification, or comparison policy in Home just to alter Home presentation.

Reuse the existing domain/presentation owner.

────────

## Product Link / Retailer Product Loading

### FitMatch/Views/ShoppingProductFormView.swift

Product URL/form presentation used by shopping-product flows.

### FitMatch/ViewModels/ShoppingProductViewModel.swift

Major product-flow orchestrator.

Currently coordinates state related to:

• retailer product loading
• parsed retailer facts
• product loading errors/recovery
• server authority state
• classification recovery
• exact runtime size identities
• comparison request lifecycle
• Closet registration eligibility/context
• comparison preparation/result flow

This ViewModel is already broad.

Do not add new canonical business policy here when an existing Service/Action/Coordinator owns it.

In particular, it must not become a second database classification engine.

Related routing/input helpers:

• FitMatch/Services/FitMatchProductEntryRouting.swift
• FitMatch/Services/FitMatchProductLinkInput.swift
• FitMatch/Services/FitMatchProductURLOpeningAction.swift

────────

## Retailer Parsing

### Primary router

FitMatch/Services/ProductURLParserService.swift

Routes supported retailer URLs into retailer-specific parsing.

Retailer implementations include:

### UNIQLO

• FitMatch/Services/UniqloParser.swift

### MUSINSA

• FitMatch/Services/MusinsaParser.swift
• FitMatch/Services/MusinsaActualSizeAPIParser.swift
• FitMatch/Services/MusinsaFallbackSizeParser.swift
• FitMatch/Services/MusinsaProductMetadataParser.swift
• FitMatch/Services/MusinsaURLResolver.swift
• FitMatch/Services/MusinsaWebViewParser.swift

### ZARA

• FitMatch/Services/ZARAParser.swift
• FitMatch/Services/ZARAWebViewMetadataAudit.swift

### COS / legacy research support

• FitMatch/Services/COSParser.swift

Parser responsibility:

```text
Retailer response
→ retailer facts
```

Not:

```text
Retailer response
→ invented FitMatch canonical policy
```

────────

## Server Authority / Supabase Contract

### FitMatch/Services/FitMatchProductAuthorityPayloadBuilder.swift

Builds product authority payloads from retailer facts.

Do not add unsupported inferred facts merely to satisfy a server request.

### FitMatch/Services/FitMatchServerAuthorityCoordinator.swift

Coordinates server-authoritative product/classification/runtime flows.

Start here when investigating:

• server authority state
• classification runtime
• recovery contract
• promotion/runtime identity
• server-first product flow

### FitMatch/Services/FitMatchSupabaseProductResolver.swift

Supabase transport/domain implementation for server product/runtime operations.

Start here for:

• RPC/API transport
• server response handling
• HTTP/domain errors
• remote runtime fetching
• persistence transport

Do not weaken client validation merely to accept a malformed server response.

### FitMatch/Services/FitMatchVNextDTOs.swift

vNext server request/response DTO contract.

### FitMatch/Services/FitMatchVNextContractValidator.swift

vNext contract validation.

Unknown/malformed server results must remain explicit contract failures.

────────

## Closet — Manual Registration

### FitMatch/Views/AddClosetItemView.swift

Manual Closet registration/edit presentation.

### FitMatch/ViewModels/AddClosetItemViewModel.swift

Owns manual Closet form state such as:

• source
• brand
• category/detail display state
• size
• measurements
• measurement source
• fit memo/preference/satisfaction
• edit-mode form state

Do not use this form model as canonical server classification authority.

Related actions:

• FitMatch/Services/FitMatchClosetFormAction.swift
• FitMatch/Services/FitMatchClosetManualRegistrationAction.swift
• FitMatch/Services/FitMatchClosetRegistrationPersistence.swift

────────

## Closet — Product Link Registration

### FitMatch/Views/LinkClosetRegistrationView.swift

Server-first product-link Closet registration UI.

The retailer API result may drive immediate display and user choices.

Persistence/server readiness remains governed by the required current server contract.

Related:

• FitMatch/ViewModels/ShoppingProductViewModel.swift
• FitMatch/Services/FitMatchLinkClosetRegistrationAction.swift
• FitMatch/Services/FitMatchClosetSyncCoordinator.swift
• FitMatch/Services/FitMatchLinkedSizeEditIntent.swift

Do not require an unnecessary DB round trip for a purely retailer-fact presentation decision.

Do not turn that exception into local canonical classification authority.

────────

## Closet — List / Detail / Editing

### FitMatch/Views/MyClosetView.swift

Primary Closet list screen.

### FitMatch/Views/ClosetItemDetailView.swift

Closet item detail/edit screen.

Related services:

• FitMatch/Services/FitMatchClosetPresentation.swift
• FitMatch/Services/FitMatchClosetItemEditAction.swift
• FitMatch/Services/FitMatchClosetDeletionAction.swift
• FitMatch/Services/FitMatchClosetSyncCoordinator.swift

When fixing a list/detail display issue, first determine whether the wrong value originates from:

```text
server record
→ hydration
→ SwiftData model
→ presentation adapter
→ View
```

Do not mask incorrect persistence/hydration at the View level.

────────

## Compare Flow

### FitMatch/Views/CompareFlowSheet.swift

Primary foreground comparison flow.

Owns UI-step orchestration around:

• product input/loading
• comparison candidate selection
• recovery flows
• comparison submission
• result presentation
• result-to-Closet flows

This file still contains legacy reference* names.

Do not interpret those names as current Reference Garment product policy.

Do not expand legacy reference-based behavior.

Related comparison services:

• FitMatch/Services/ComparisonProfileMatcher.swift
• FitMatch/Services/CanonicalComparisonProfileResolver.swift
• FitMatch/Services/VNextComparisonEngineAdapter.swift
• FitMatch/Services/MeasurementComparisonEngine.swift
• FitMatch/Services/FitMatchComparisonSubmissionAction.swift
• FitMatch/Services/FitMatchComparisonSyncCoordinator.swift

Trace comparison bugs through the whole pipeline before changing scoring:

```text
Retailer facts
→ server authority
→ comparison group/readiness
→ candidate/size identity
→ authorization
→ adapter
→ measurement engine
→ completion/persistence
→ result UI
```

Do not call the engine with fabricated, unauthorized, or identity-mismatched data.

────────

## Comparison / Measurement Models

Important domain models include:

• FitMatch/Models/CanonicalComparisonProfile.swift
• FitMatch/Models/GarmentComparisonAttributes.swift
• FitMatch/Models/GarmentMeasurementRecord.swift
• FitMatch/Models/GarmentMeasurements.swift
• FitMatch/Models/MeasurementCode.swift
• FitMatch/Models/FitMatchTaxonomy.swift
• FitMatch/Models/FitMatchClassificationAuthorityProvenance.swift
• FitMatch/Models/FitMatchRetailerAPIEvidence.swift

Do not modify shared domain semantics to fix a single screen unless the domain behavior itself is wrong.

────────

## Result / History

### FitMatch/Views/RecommendationResultView.swift

Comparison/recommendation result presentation.

Do not recompute canonical comparison policy in the result View.

### FitMatch/Views/RecommendationHistoryView.swift

History list/presentation.

Related:

• FitMatch/Services/RecommendationHistoryStore.swift
• FitMatch/Services/FitMatchHistoryPresentation.swift
• FitMatch/Services/FitMatchHistoryVisibilityAction.swift
• FitMatch/Services/VNextHistoryCacheHydrator.swift

Historical data must not be treated as fresh server authorization when the current flow requires reacquiring authority.

────────

## Result → Closet Registration

### FitMatch/Views/AddComparedProductToClosetSheet.swift

Closet registration UI for a compared/result product.

Related:

• FitMatch/Services/FitMatchResultClosetRegistrationPreparationAction.swift
• FitMatch/Services/FitMatchComparedProductClosetRegistration.swift
• FitMatch/Services/FitMatchComparedProductClosetSubmissionAction.swift

Preserve exact selected:

• product
• color/variant
• size
• measurement identity

Do not fall back to the first available variant/size when identity is unresolved.

────────

## Recommend

### FitMatch/Views/RecommendView.swift

Recommendation-tab presentation.

Do not duplicate comparison/scoring/classification policy here. Consume existing domain/service results.

────────

## Search

### FitMatch/Views/GlobalSearchView.swift

Global search presentation.

Use existing Closet/history/product presentation accessors instead of creating search-only interpretations of stored data.

────────

## Settings / Account

Primary views:

• FitMatch/Views/MyPageView.swift
• FitMatch/Views/SettingsView.swift

Related account services:

• FitMatch/Services/FitMatchAuthSessionStore.swift
• FitMatch/Services/FitMatchAccountDeletionAction.swift

Authentication and user-owned data boundaries must remain explicit.

Never render another user’s persisted rows while ownership/cache preparation is unresolved.

────────

## Size Table Recovery

### FitMatch/Views/SizeTableRecoveryView.swift

User-facing size-table recovery UI.

### FitMatch/Services/SizeTableRecoveryFeature.swift

Recovery-domain support.

Recovery must preserve the distinction between:

• retailer facts
• recovered measurements
• server authority
• user-entered information

Do not silently present recovered/guessed measurements as retailer-authoritative facts.
