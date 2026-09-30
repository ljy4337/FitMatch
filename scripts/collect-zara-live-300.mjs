#!/usr/bin/env node

import { createHash } from "node:crypto";
import { gunzipSync } from "node:zlib";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "..");
const catalogPath = path.join(
  repositoryRoot,
  "Docs/Research/FitMatchCategoryMappingV2-20260824-shadow/zara_products.jsonl"
);
const outputDirectory = path.resolve(
  process.argv[2] ?? path.join(repositoryRoot, "ZARAAudit/live_zara_300_20260825")
);
const targetCount = 300;
const sitemapIndexURL = "https://www.zara.com/sitemaps/sitemap-index.xml.gz";
const productSitemapURL = "https://www.zara.com/sitemaps/sitemap-product-kr-ko.xml.gz";
const userAgent = "FitMatch-QA/1.0 (+live-zara-classification-validation)";
const observedAt = new Date().toISOString();

await mkdir(outputDirectory, { recursive: true });

const [indexResponse, productResponse] = await Promise.all([
  fetchOfficial(sitemapIndexURL),
  fetchOfficial(productSitemapURL),
]);
const indexLocations = sitemapLocations(indexResponse.body);
if (!indexLocations.includes(productSitemapURL)) {
  throw new Error("ZARA KR product sitemap is absent from the current official sitemap index");
}

const officialURLs = sitemapLocations(productResponse.body);
const officialURLByReference = new Map();
for (const url of officialURLs) {
  const reference = styleReference(url);
  if (reference && !officialURLByReference.has(reference)) {
    officialURLByReference.set(reference, url);
  }
}

const catalogRows = (await readFile(catalogPath, "utf8"))
  .split(/\r?\n/u)
  .filter((line) => line.trim() !== "")
  .map((line) => JSON.parse(line));

const candidateByReference = new Map();
for (const row of catalogRows) {
  const reference = styleReference(row.product_url ?? "");
  if (!reference || !officialURLByReference.has(reference)) continue;
  if (row.product_structure !== "STANDARD_PRODUCT") continue;
  if ([null, undefined, "", "UNMAPPED", "EXCLUDED"].includes(row.fitmatch_major_candidate)) continue;

  const existing = candidateByReference.get(reference);
  if (!existing || evidenceQuality(row) > evidenceQuality(existing)) {
    candidateByReference.set(reference, row);
  }
}

const candidates = [...candidateByReference].map(([reference, row]) => ({
  ...row,
  style_reference: reference,
  archive_product_url: row.product_url,
  product_url: officialURLByReference.get(reference),
  official_listed: true,
  observed_at: observedAt,
  sale_evidence: "OFFICIAL_ZARA_KR_PRODUCT_SITEMAP",
  review_status: "PENDING_HUMAN_REVIEW",
  human_category: "",
  human_detail: "",
  reviewer_notes: "",
  gold_approved: false,
}));

const selected = nestedRoundRobinSample(
  candidates,
  (row) => `${row.fitmatch_major_candidate}|${row.section}`,
  (row) => `${row.family_name ?? ""}|${row.subfamily_name ?? ""}`,
  targetCount
);

const uniqueReferences = new Set(selected.map((row) => row.style_reference));
if (selected.length !== targetCount || uniqueReferences.size !== targetCount) {
  throw new Error(`Expected ${targetCount} unique ZARA products, got ${uniqueReferences.size}`);
}
if (!selected.every((row) => officialURLByReference.get(row.style_reference) === row.product_url)) {
  throw new Error("At least one sampled URL is not the current official sitemap URL");
}

const jsonl = selected.map((row) => JSON.stringify(row)).join("\n") + "\n";
const csv = toCSV(selected);
const jsonlPath = path.join(outputDirectory, "zara_live_300.jsonl");
const csvPath = path.join(outputDirectory, "zara_live_300_review.csv");
await writeFile(jsonlPath, jsonl, "utf8");
await writeFile(csvPath, csv, "utf8");

const summary = {
  contract_version: "fitmatch-zara-live-300-review-v1",
  observed_at: observedAt,
  mode: "shadow_review_only",
  production_import_allowed: false,
  gold_fixture_approval_allowed: false,
  independent_human_label_count: 0,
  method: "official ZARA KR product sitemap intersected with archived structured source facts; no PDP bulk crawl",
  official_source: {
    sitemap_index: responseEvidence(sitemapIndexURL, indexResponse),
    product_sitemap: responseEvidence(productSitemapURL, productResponse),
    sitemap_url_count: officialURLs.length,
    unique_style_reference_count: officialURLByReference.size,
  },
  archive_row_count: catalogRows.length,
  live_structured_intersection_count: candidates.length,
  sample_count: selected.length,
  unique_sample_reference_count: uniqueReferences.size,
  section_counts: counts(selected, (row) => row.section),
  major_candidate_counts: counts(selected, (row) => row.fitmatch_major_candidate),
  section_major_counts: counts(selected, (row) => `${row.section}|${row.fitmatch_major_candidate}`),
  family_count: new Set(selected.map((row) => `${row.section}|${row.family_name ?? ""}`)).size,
  structured_path_count: new Set(
    selected.map((row) => `${row.section}|${row.family_name ?? ""}|${row.subfamily_name ?? ""}`)
  ).size,
  pending_human_review_count: selected.filter((row) => row.review_status === "PENDING_HUMAN_REVIEW").length,
  files: {
    jsonl: {
      path: path.basename(jsonlPath),
      bytes: Buffer.byteLength(jsonl),
      sha256: sha256(jsonl),
    },
    review_csv: {
      path: path.basename(csvPath),
      bytes: Buffer.byteLength(csv),
      sha256: sha256(csv),
    },
  },
};
await writeFile(
  path.join(outputDirectory, "official_source_evidence.json"),
  JSON.stringify(summary, null, 2) + "\n",
  "utf8"
);

process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);

async function fetchOfficial(url) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          Accept: "application/xml,text/xml,*/*;q=0.8",
          "Accept-Language": "ko-KR,ko;q=0.9",
          "User-Agent": userAgent,
        },
        redirect: "follow",
        signal: AbortSignal.timeout(60_000),
      });
      if ([401, 403, 429].includes(response.status)) {
        throw new Error(`Stopped on access-control response ${response.status}: ${url}`);
      }
      if (!response.ok) {
        if (response.status < 500 || attempt === 3) {
          throw new Error(`HTTP ${response.status}: ${url}`);
        }
        continue;
      }
      return {
        status: response.status,
        resolvedURL: response.url,
        contentType: response.headers.get("content-type"),
        body: Buffer.from(await response.arrayBuffer()),
      };
    } catch (error) {
      lastError = error;
      if (/access-control response/u.test(String(error)) || attempt === 3) throw error;
    }
  }
  throw lastError;
}

function sitemapLocations(body) {
  const decoded = body[0] === 0x1f && body[1] === 0x8b ? gunzipSync(body) : body;
  return [...decoded.toString("utf8").matchAll(/<loc>(.*?)<\/loc>/gsu)]
    .map((match) => match[1].trim().replaceAll("&amp;", "&"));
}

function styleReference(url) {
  return String(url).match(/-p(\d{8})\.html/u)?.[1] ?? null;
}

function evidenceQuality(row) {
  return [
    row.family_name,
    row.subfamily_name,
    row.product_name,
    ...(row.source_category_paths ?? []),
  ].filter((value) => typeof value === "string" && value.trim() !== "").length;
}

function stableKey(row) {
  return sha256(`${row.source_product_id}|${row.product_name}`);
}

function nestedRoundRobinSample(rows, outerKey, innerKey, target) {
  const outerGroups = new Map();
  for (const row of rows) {
    const outer = String(outerKey(row) || "UNKNOWN");
    if (!outerGroups.has(outer)) outerGroups.set(outer, []);
    outerGroups.get(outer).push(row);
  }

  const orderedOuterGroups = new Map();
  for (const [outer, group] of outerGroups) {
    orderedOuterGroups.set(outer, roundRobin(group, innerKey));
  }

  const selected = [];
  const outerNames = [...orderedOuterGroups.keys()].sort();
  let offset = 0;
  while (selected.length < target) {
    let advanced = false;
    for (const outer of outerNames) {
      const group = orderedOuterGroups.get(outer);
      if (offset >= group.length) continue;
      selected.push(group[offset]);
      advanced = true;
      if (selected.length === target) break;
    }
    if (!advanced) break;
    offset += 1;
  }
  if (selected.length !== target) {
    throw new Error(`Could only sample ${selected.length} of ${target} requested rows`);
  }
  return selected;
}

function roundRobin(rows, groupKey) {
  const groups = new Map();
  for (const row of rows) {
    const key = String(groupKey(row) || "UNKNOWN");
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  for (const group of groups.values()) group.sort((a, b) => stableKey(a).localeCompare(stableKey(b)));

  const ordered = [];
  const names = [...groups.keys()].sort();
  let offset = 0;
  while (ordered.length < rows.length) {
    let advanced = false;
    for (const name of names) {
      const group = groups.get(name);
      if (offset >= group.length) continue;
      ordered.push(group[offset]);
      advanced = true;
    }
    if (!advanced) break;
    offset += 1;
  }
  return ordered;
}

function counts(rows, key) {
  return Object.fromEntries(
    [...rows.reduce((map, row) => {
      const value = String(key(row) || "UNKNOWN");
      map.set(value, (map.get(value) ?? 0) + 1);
      return map;
    }, new Map())].sort(([a], [b]) => a.localeCompare(b))
  );
}

function responseEvidence(requestedURL, response) {
  return {
    requested_url: requestedURL,
    resolved_url: response.resolvedURL,
    http_status: response.status,
    content_type: response.contentType,
    bytes: response.body.length,
    sha256: sha256(response.body),
  };
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function toCSV(rows) {
  const preferredHeaders = [
    "style_reference",
    "product_name",
    "section",
    "family_name",
    "subfamily_name",
    "fitmatch_major_candidate",
    "product_url",
    "review_status",
    "human_category",
    "human_detail",
    "reviewer_notes",
    "gold_approved",
    "source_product_id",
    "product_code",
    "source_category_paths",
    "observed_at",
  ];
  const headers = [
    ...preferredHeaders,
    ...Object.keys(rows[0] ?? {}).filter((key) => !preferredHeaders.includes(key)),
  ];
  const lines = [headers.join(",")];
  for (const row of rows) {
    lines.push(headers.map((header) => csvValue(row[header])).join(","));
  }
  return `${lines.join("\n")}\n`;
}

function csvValue(value) {
  const text = Array.isArray(value) || (value && typeof value === "object")
    ? JSON.stringify(value)
    : String(value ?? "");
  return /[",\r\n]/u.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}
