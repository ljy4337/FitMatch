# Uniqlo KR Catalog Raw-Data Collector

## Status

Design approved on 2026-09-28. Implementation has not started.

## Goal

Build the first FitMatch catalog-ingestion adapter for the complete UNIQLO Korea clothing catalog. The system must collect and retain source data so that product, color, size, measurement, and category facts remain traceable to their original retailer response.

## Scope

- Discover all clothing products in the UNIQLO Korea storefront.
- Fetch official product, color/variant, and size-chart responses.
- Archive each response with its request URL, collection time, HTTP status, SHA-256 content hash, collector version, and failure context.
- Normalize products, variants, sizes, measurement rows, and category paths into a catalog store.
- Run an initial full snapshot followed by hash-based incremental refreshes.

## Non-goals

- Do not write user Closet records, comparison history, retailer mapping, or comparison-group policy.
- Do not decide FitMatch comparison eligibility or canonical measurement policy during ingestion.
- Do not evade retailer access controls, CAPTCHA, 403, or 429 responses.
- Do not expose catalog write access to iOS clients.

## Architecture

The collector is a one-way pipeline:

`catalog-discoverer -> product-fetcher -> raw-archive -> normalizer -> catalog-store`

1. **Catalog discoverer** obtains current UNIQLO Korea clothing category paths, product IDs, product URLs, and discovery provenance.
2. **Product fetcher** calls the official retailer endpoints for product/variant and size-chart payloads. The official API is the primary route. Selenium is limited to browser-mediated request-contract discovery or an API-failure fallback; it must capture responses rather than scrape rendered text where possible.
3. **Raw archive** writes immutable source receipts before any normalized data changes. Identical payload hashes may reference an existing receipt without duplicating the body.
4. **Normalizer** extracts retailer facts without deleting unknown labels, values, units, bases, or structural fields. Every normalized row carries the raw receipt ID that produced it.
5. **Catalog store** supplies a read-only, normalized FitMatch catalog surface. Product-policy interpretation remains a separate downstream concern.

## Data contract

### Immutable raw receipts

Each receipt stores:

- collection run and item ID
- retailer and storefront (`uniqlo`, `kr`)
- request URL and request identity excluding secrets
- response status, body, SHA-256 hash, content type, collection timestamp
- collector/parser version and extraction outcome
- retryable/non-retryable error classification where applicable

### Normalized catalog

The normalized layer stores:

- product identity and retailer URL
- color/variant identity and display facts
- size code and display name
- category/breadcrumb path
- every received measurement row: source label/code, original value and unit, basis/body-part/component fields when present
- source receipt ID and parser version

No measurement is dropped because FitMatch cannot currently canonicalize it. Raw source facts, catalog normalization, canonical mapping, and comparison eligibility are distinct states.

## Execution and recovery

- A run records discovery, fetch, archive, normalization, and load states for each item.
- A complete run reports discovered, archived, normalized, unchanged, deferred, and failed counts by category.
- 403, 429, CAPTCHA, malformed payloads, and empty size charts are stored as explicit outcomes. The collector may back off and retry safe requests but does not bypass access controls.
- A new raw payload hash creates a new receipt and a corresponding normalized catalog version. Unchanged content reuses the existing receipt.
- Parser upgrades support replaying archived raw receipts into a new normalized version without re-fetching retailer data.

## Access boundary

The collector uses a server-side service identity restricted to catalog ingestion. The iOS app reads approved normalized catalog data through server-owned APIs/RPCs and has no catalog write permission. The collector never mutates Closet, comparison, history, or product-policy data.

## Verification criteria

- Per-category execution accounting reconciles discovered product IDs with terminal item states.
- Referential-integrity tests show every product, variant, size, and measurement row points to a raw receipt.
- Hash-deduplication tests preserve receipt identity for unchanged responses.
- Replay tests demonstrate parser changes against stored raw payloads.
- Sampled live official responses match archived hashes and exact product/variant/size identities.
- Tests cover empty payloads, schema changes, 403/429 responses, and incomplete measurement charts without fabricating successful catalog data.

## Delivery sequence

1. Inspect and freeze the current UNIQLO API request/response contracts and discovery routes.
2. Add isolated raw-archive and normalized catalog schema, with server-only write access.
3. Implement discovery and fetch adapters with resumable run state.
4. Implement normalization and archived-payload replay.
5. Run a small non-production smoke collection, validate receipts and normalized identities, then expand to the full catalog only after result review.

## Approval record

The user approved the API-first hybrid collector, full UNIQLO Korea clothing scope, immutable raw-data preservation, normalized catalog separation, server-only catalog writes, and the stated verification model.
