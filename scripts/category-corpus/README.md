# FitMatch category corpus collector

This research-only tool builds category evidence without changing the FitMatch
app or connecting to Supabase.

## Bootstrap (no network)

```bash
python3 scripts/category-corpus/corpus_collector.py bootstrap
```

The default input is the restored `Docs/Research/LiveProductSurvey-20260723`
survey. Output is written to `Docs/Research/CategoryCorpus-bootstrap`.
Bootstrap validates the 11 files and the 300/200/100 product and 30/5 category
path counts before producing any output.

The restored survey does not contain original HTTP response bodies. Bootstrap
therefore leaves `raw/` without synthesized responses and documents that fact.

## Live dry-run (no network)

```bash
python3 scripts/category-corpus/corpus_collector.py live \
  --source all \
  --output Docs/Research/CategoryCorpus-live \
  --dry-run
```

The dry-run prints the request upper bound and checkpoint location. It performs
zero requests.

## Limited live collection (explicit network use)

Do not run this until live collection is separately approved.

```bash
python3 scripts/category-corpus/corpus_collector.py live \
  --source all \
  --output Docs/Research/CategoryCorpus-live \
  --musinsa-limit 60 \
  --uniqlo-limit 60 \
  --uniqlo-men-limit 20 \
  --uniqlo-women-limit 20 \
  --uniqlo-kids-limit 10 \
  --uniqlo-baby-limit 10 \
  --max-category-pages 60 \
  --delay-ms 250 \
  --retries 2
```

Resume an interrupted run with the same arguments plus `--resume`. The
checkpoint is `<output>/checkpoint.json` and is updated after each category
page, request attempt, and product response. Checkpoint version 2 stores
separate queue, visited-category, discovered-product, and hydration-confirmed
product state for MEN, WOMEN, KIDS, and BABY. A valid version-1 checkpoint is
migrated in memory; if its URLs or raw evidence cannot be assigned safely, the
command exits without overwriting it.

`--uniqlo-limit` caps all Uniqlo product-detail requests. The four
`--uniqlo-*-limit` options cap accepted products by the audience confirmed in
the product hydration breadcrumb, not by the discovery URL. If both limits are
present, whichever is reached first applies. Reaching one audience limit does
not stop the remaining audience queues. A queue/hydration mismatch is recorded,
unknown audience is unresolved, and over-quota observations remain in raw
evidence without being counted toward the requested audience sample.

Category pages are visited round-robin across the four audience queues.
`--max-category-pages` is a per-source total rather than a per-audience limit.
The dry-run reports both the logical request maximum and the worst-case request
attempt maximum including retries.

Uniqlo category anchors are accepted only after validating the original
`href`. Relative and absolute URLs are normalized to the exact HTTPS
`www.uniqlo.com/kr/ko/<audience>/...` structure. Placeholder components,
duplicated locale paths, fragments, foreign hosts/locales, and empty paths are
excluded before entering a queue and retained in checkpoint evidence as
`rejected_category_urls`. Resume applies the same validation to an existing
queue, so completed category requests are preserved while invalid pending URLs
are skipped rather than requested.

Uniqlo category discovery first uses explicit HTML links. The saved BABY home
page also exposes audience-scoped evidence in
`window.__PRELOADED_STATE__.cms["/home/v2"].components.body[*].baby[*]` and
taxonomy ancestry in `window.__PRELOADED_STATE__.taxonomies`. The collector
accepts only category URLs whose parsed URL audience matches the current
audience. Product IDs from the BABY CMS section retain their full raw value and
are normalized to the already-observed Uniqlo product URL identifier format.
Taxonomy keys are preserved as evidence but are never converted into guessed
URLs.

## Fixed BABY probe (maximum five requests)

The probe reads its four product IDs from the saved medium BABY root raw in
original CMS array order. It permits exactly one saved category URL followed by
those four known product URLs, stops after a category or first-product
validation failure, and rejects any unexpected requested or final URL.

```bash
python3 scripts/category-corpus/corpus_collector.py baby-probe \
  --medium-dir Docs/Research/CategoryCorpus-live-medium \
  --output Docs/Research/CategoryCorpus-live-baby-probe \
  --delay-ms 250 \
  --retries 2
```

It never resumes or modifies the medium output. Probe raw responses, request
metrics, the CMS-to-hydration manifest, unresolved evidence, and a summary are
written only under the new output path.

For a CMS ID shaped like `E488861-000-00`, the probe parses
`E488861-000` as the base product ID and `00` as that observation's variant
suffix. It requests `/kr/ko/products/E488861-000` and permits only the exact
canonical redirect `/kr/ko/products/E488861-000/00`. Host, locale, product ID,
and per-observation suffix must all match; query strings and fragments are
rejected. The suffix is never hard-coded globally.

Every HTTP response body is saved before canonical URL and hydration
validation. Metrics, manifest, unresolved evidence, and summary files are
atomically replaced after each probe outcome, including an early stop.

## BABY 10 limited collection

After a separately approved probe, the BABY-only collector can plan without
network access:

```bash
python3 scripts/category-corpus/corpus_collector.py baby-collect-10 \
  --evidence-dir Docs/Research/CategoryCorpus-live-baby-probe-v2 \
  --output Docs/Research/CategoryCorpus-live-baby-10 \
  --baby-limit 10 \
  --max-logical-requests 25 \
  --delay-ms 250 \
  --retries 2 \
  --dry-run
```

Remove only `--dry-run` for a separately approved execution. Candidate order
comes from the saved BABY PLP hydration
`search["/v2/baby/newborn/bodysuits…"].search.productIds`. Raw observations are
preserved, while acceptance is deduplicated by the existing Uniqlo core product
identity (the `E` number without color and variant). The request uses the first
observed color-bearing base product ID, but it does not automatically accept
that observation's suffix. After the response, the collector validates the
canonical host, scheme, locale, base product ID, query, and fragment, then
selects the earliest raw-order observation for that same base whose explicitly
observed suffix exactly matches the canonical redirect. The selection rule is
recorded as `canonical_redirect_matches_raw_variant`. All observations retain
their original order, including duplicates and unselected variants. If the
canonical suffix is absent from raw evidence, the product is unresolved and
the run stops; no suffix is invented or globally defaulted to `00`.

The run stops at ten accepted hydration-confirmed BABY products even if
candidates remain. It writes raw responses, checkpoint, request metrics,
manifest, unresolved evidence, category evidence, settings, request order,
remaining queue, and summary only to its new output directory.

The collector uses public pages only, has no authentication or blocking-bypass
behavior, and rejects delays below 250 ms. Raw response bodies are stored under
`<output>/raw` with URL, content type, byte count, timestamp, and SHA-256
metadata in the checkpoint. A `Retry-After` response delay is honored. HTTP 403
or 429 stops the collection after recording the response, and five consecutive
network failures stop it without continuing the queue.

## Offline reprocess (no network)

Rebuild category parsing outputs from an existing checkpoint and its saved raw
responses:

```bash
python3 scripts/category-corpus/corpus_collector.py offline-reprocess \
  --output Docs/Research/CategoryCorpus-live-smoke
```

This command never constructs a fetcher or calls the network. It verifies every
raw file against the SHA-256 stored in `checkpoint.json`, preserves the
checkpoint and raw bodies, and rewrites only derived manifest, path, exposure,
inventory, unresolved, and summary outputs.

For Uniqlo, a valid JSON-LD `BreadcrumbList` remains the first choice. If it is
missing or invalid, the collector reads
`window.__PRELOADED_STATE__.entity.pdpEntity.*.product.breadcrumbs`. The target
entry must match the observed product code through `product.productId` or its
entity key. It never selects an arbitrary first entry. If valid JSON-LD and
hydration paths disagree, both are retained as evidence and the result is
marked unresolved.

Hydration preserves `gender`, `class`, `category`, and `subcategory` with their
original order and `id`, `name`, `locale`, and `level`. Gender is stored as the
separate audience. The user-facing source path uses `locale`, falling back to
`name` only when locale is empty.

The initial full-corpus limits are 1,000 Musinsa products and 200 Uniqlo
products. With the default maximum of 250 category pages per source, the
request upper bound is 1,700 requests: at most 500 category pages plus 1,200
product detail pages. The actual count depends on discovered category pages and
products.

## Outputs

- `category_inventory.json`
- `product_manifest.json`
- `raw/`
- `product_category_paths.csv`
- `category_exposures.csv`
- `unresolved_categories.csv`
- `collection_summary.md`

These outputs are research evidence, not database seed data. Known existing
`source_categories` paths and unresolved rules are maintained in
`known_categories.json`.
