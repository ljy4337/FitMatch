# FitMatch Taxonomy

## Local contract

The app loads `FitMatch/FitMatchTaxonomy.json` through `FitMatchTaxonomyProviding`. UI code depends on the provider, not on the bundled file, so a cached server response can replace it later without changing picker code.

```json
{
  "schemaVersion": 1,
  "taxonomyVersion": "2026.07.1",
  "genders": [{
    "code": "male",
    "displayName": "남성",
    "sortOrder": 0,
    "isActive": true
  }],
  "categories": [{
    "code": "tops",
    "displayName": "상의",
    "sortOrder": 0,
    "isActive": true,
    "details": [{
      "code": "short_sleeve",
      "displayName": "반팔",
      "sortOrder": 1,
      "isActive": true
    }]
  }],
  "normalizedProductTypes": [{
    "code": "tops.knit_sweater",
    "categoryCode": "tops",
    "displayName": "니트/스웨터",
    "sortOrder": 0,
    "isActive": true
  }],
  "legacyAliases": [{
    "type": "detailCategory",
    "value": "반팔티",
    "categoryCode": "tops",
    "targetCode": "short_sleeve"
  }]
}
```

Codes are stable relational identifiers. Korean names are mutable display data. `isActive` controls selection visibility while preserving decode compatibility. Unknown legacy values remain unresolved and retain their persisted snapshot. Source platform category depth/path is independent and is never overwritten by a FitMatch classification correction.

## Data sources

1. Future server taxonomy API response (same JSON shape)
2. Locally cached last valid server response
3. Bundled JSON fallback
4. Minimal controlled in-code fallback when bundled decoding fails

Networking and cache refresh are intentionally not implemented yet.

## Future relational schema

### taxonomy_versions

- `id` PK
- `version`
- `published_at`
- `is_active`

### genders

- `code` PK
- `display_name_ko`
- `sort_order`
- `is_active`
- `taxonomy_version_id` FK

### garment_categories

- `code` PK
- `display_name_ko`
- `sort_order`
- `is_active`
- `taxonomy_version_id` FK

### garment_detail_categories

- `code` PK
- `category_code` FK
- `display_name_ko`
- `sort_order`
- `is_active`
- `taxonomy_version_id` FK

### normalized_product_types

- `code` PK
- `category_code` FK
- `display_name_ko`
- `sort_order`
- `is_active`
- `taxonomy_version_id` FK

### source_category_mappings

- `id` PK
- `platform_code`
- `source_category_path`
- `source_family`
- `gender_code` nullable FK
- `category_code` FK
- `detail_category_code` nullable FK
- `normalized_product_type_code` nullable FK
- `priority`
- `is_active`
- `taxonomy_version_id` FK

Source depth columns or a normalized child table should be added before production migration because current matching prioritizes depth 1–4 over the display path.

### taxonomy_aliases

- `id` PK
- `alias_type`
- `alias_value`
- `target_code`
- `taxonomy_version_id` FK

For detail aliases, production storage also needs a category discriminator because labels such as `7부` exist under multiple parents.

## Persistence compatibility

`UserFit` retains its existing Korean snapshot properties and adds optional stable gender/category/detail/normalized-type codes. `Product` retains source category metadata and adds optional category/normalized-type codes. Existing records resolve codes through aliases at read time; only safely resolved values are used. No destructive migration is performed.

Reference uniqueness uses gender + category + detail + normalized product type when both product types are known. If either type is unknown, the previous conservative category/detail behavior is retained.
