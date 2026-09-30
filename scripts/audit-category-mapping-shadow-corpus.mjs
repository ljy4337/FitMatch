#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const corpusDirectory = join(
  scriptDirectory,
  "..",
  "Docs",
  "Research",
  "FitMatchCategoryMappingV2-20260824-shadow"
);

function fail(message) {
  throw new Error(`shadow corpus audit failed: ${message}`);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

const manifest = JSON.parse(
  await readFile(join(corpusDirectory, "manifest.json"), "utf8")
);

assert(manifest.mode === "shadow_only", "mode must remain shadow_only");
assert(manifest.productionImportAllowed === false, "production import must remain disabled");
assert(manifest.goldFixtureApprovalAllowed === false, "automatic Gold approval must remain disabled");

const summaries = [];
const baseIdentities = new Map();
for (const file of manifest.files) {
  const buffer = await readFile(join(corpusDirectory, file.path));
  assert(sha256(buffer) === file.sha256, `${file.path} checksum changed`);

  const rows = buffer
    .toString("utf8")
    .split(/\r?\n/u)
    .filter((line) => line.trim() !== "")
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        fail(`${file.path}:${index + 1} is not valid JSON: ${error.message}`);
      }
    });
  assert(rows.length === file.rowCount, `${file.path} row count changed`);

  const identities = new Set();
  let missingProductNameCount = 0;
  for (const [index, row] of rows.entries()) {
    const line = index + 1;
    assert(
      row.retailer_code?.toLowerCase() === file.source,
      `${file.path}:${line} retailer_code mismatch`
    );
    assert(typeof row.source_product_id === "string" && row.source_product_id !== "", `${file.path}:${line} missing product identity`);
    if (typeof row.product_name !== "string" || row.product_name === "") {
      missingProductNameCount += 1;
    }
    assert(Array.isArray(row.source_category_paths), `${file.path}:${line} missing category paths`);
    assert(!identities.has(row.source_product_id), `${file.path}:${line} duplicate product identity`);
    identities.add(row.source_product_id);
  }
  assert(
    missingProductNameCount === file.expectedMissingProductNameCount,
    `${file.path} missing product-name count changed`
  );

  if (file.source === "musinsa") {
    assert(
      rows.every((row) => typeof row.expected_garment_type_code === "string"),
      "every Musinsa row must retain its explicit expected garment label"
    );
    assert(file.independentLabelCount === rows.length, "Musinsa independent label count mismatch");
  }

  if (file.source === "uniqlo") {
    assert(file.independentLabelCount === 0, "Uniqlo must not be marked independently Gold-labelled");
    assert(
      rows.every((row) => row.expected_garment_type_code === undefined),
      "Uniqlo source-derived app categories must not be relabelled as independent expected garment labels"
    );
  }

  if (file.source === "zara") {
    assert(file.independentLabelCount === 0, "ZARA must not be marked independently Gold-labelled");
    assert(file.identityPolicy === "shadow_pseudo_id_only", "ZARA identity must remain shadow-only");
    assert(
      rows.every((row) => /^ZARA_KR_(?:MAN|WOMAN)_(?:\d{8}|T\d{10})$/u.test(row.source_product_id)),
      "ZARA archive IDs no longer match the known pseudo-ID contract"
    );
  }

  summaries.push({
    source: file.source,
    rows: rows.length,
    independentLabels: file.independentLabelCount,
    missingProductNames: missingProductNameCount,
    identityPolicy: file.identityPolicy
  });
  baseIdentities.set(file.source, identities);
}

const liveSampleSummaries = [];
for (const sample of manifest.liveSamples ?? []) {
  assert(sample.contractVersion === "fitmatch-live-shadow-sample-v1", "unsupported live sample contract");
  assert(sample.productionImportAllowed === false, "live sample production import must remain disabled");
  assert(sample.goldFixtureApprovalAllowed === false, "live sample Gold approval must remain disabled");
  assert(sample.independentLabelCount === 0, "live sample must not claim independent labels");

  const buffer = await readFile(join(corpusDirectory, sample.path));
  assert(sha256(buffer) === sample.sha256, `${sample.path} checksum changed`);
  const evidenceBuffer = await readFile(join(corpusDirectory, sample.evidencePath));
  assert(sha256(evidenceBuffer) === sample.evidenceSha256, `${sample.evidencePath} checksum changed`);
  const evidence = JSON.parse(evidenceBuffer.toString("utf8"));

  const rows = buffer
    .toString("utf8")
    .split(/\r?\n/u)
    .filter((line) => line.trim() !== "")
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        fail(`${sample.path}:${index + 1} is not valid JSON: ${error.message}`);
      }
    });
  assert(rows.length === sample.rowCount, `${sample.path} row count changed`);

  const identities = new Set();
  const sourceCounts = new Map();
  const overlapCounts = new Map();
  const newCounts = new Map();
  for (const [index, row] of rows.entries()) {
    const line = index + 1;
    const source = row.retailer_code?.toLowerCase();
    assert(["musinsa", "uniqlo", "zara"].includes(source), `${sample.path}:${line} unsupported retailer`);
    assert(typeof row.source_product_id === "string" && row.source_product_id !== "", `${sample.path}:${line} missing product identity`);
    assert(typeof row.product_name === "string" && row.product_name !== "", `${sample.path}:${line} missing product name`);
    assert(Array.isArray(row.source_category_paths), `${sample.path}:${line} missing category paths`);
    assert(row.official_listed === true, `${sample.path}:${line} is not marked officially listed`);
    assert(typeof row.product_url === "string" && row.product_url.startsWith("https://"), `${sample.path}:${line} invalid product URL`);

    const identity = `${source}:${row.source_product_id}`;
    assert(!identities.has(identity), `${sample.path}:${line} duplicate product identity`);
    identities.add(identity);
    sourceCounts.set(source, (sourceCounts.get(source) ?? 0) + 1);

    if (source === "musinsa") {
      assert(/^\d+$/u.test(row.source_product_id), `${sample.path}:${line} invalid Musinsa identity`);
      assert(row.product_url.includes(row.source_product_id), `${sample.path}:${line} Musinsa URL identity mismatch`);
    } else if (source === "uniqlo") {
      assert(/^E\d+-\d+$/u.test(row.source_product_id), `${sample.path}:${line} invalid Uniqlo identity`);
      assert(row.product_url.includes(row.source_product_id.split("-")[0]), `${sample.path}:${line} Uniqlo URL identity mismatch`);
    } else {
      assert(/^ZARA_KR_(?:MAN|WOMAN)_\d{8}$/u.test(row.source_product_id), `${sample.path}:${line} invalid ZARA shadow identity`);
      assert(row.product_url.includes(row.source_product_id.split("_").at(-1)), `${sample.path}:${line} ZARA URL identity mismatch`);
    }

    assert(row.expected_garment_type_code === undefined, `${sample.path}:${line} must not contain a Gold garment label`);
    assert(row.expected_fitmatch_category_code === undefined, `${sample.path}:${line} must not contain a Gold category label`);

    const isOverlap = baseIdentities.get(source)?.has(row.source_product_id) === true;
    const target = isOverlap ? overlapCounts : newCounts;
    target.set(source, (target.get(source) ?? 0) + 1);
  }

  for (const source of ["musinsa", "uniqlo", "zara"]) {
    assert(sourceCounts.get(source) === sample.perSourceRowCount[source], `${sample.path} ${source} row count changed`);
    assert(overlapCounts.get(source) === sample.expectedOverlapWithBaseCorpus[source], `${sample.path} ${source} overlap changed`);
    assert((newCounts.get(source) ?? 0) === sample.expectedNewRowsAgainstBaseCorpus[source], `${sample.path} ${source} new-row count changed`);
  }
  assert(evidence.total_sample_count === rows.length, `${sample.evidencePath} total sample count mismatch`);
  assert(evidence.unique_product_key_count === identities.size, `${sample.evidencePath} unique identity count mismatch`);

  const shadowAudit = sample.currentFitMatchShadowAudit;
  assert(shadowAudit?.goldReviewCandidateCount >= 0, `${sample.path} missing current FitMatch shadow audit`);
  assert(shadowAudit.silentConflictConfirmationCount === 0, `${sample.path} has a silent conflict confirmation`);
  assert(shadowAudit.strictComparisonConflictLeakCount === 0, `${sample.path} has a strict comparison conflict leak`);
  const summary = JSON.parse(
    await readFile(join(corpusDirectory, shadowAudit.summaryPath), "utf8")
  );
  assert(summary.mode === "shadow_only", `${shadowAudit.summaryPath} mode changed`);
  assert(summary.inputCount === rows.length, `${shadowAudit.summaryPath} input count mismatch`);
  assert(summary.independentGoldLabelCount === 0, `${shadowAudit.summaryPath} must not claim Gold labels`);
  assert(summary.goldReviewCandidateCount === shadowAudit.goldReviewCandidateCount, `${shadowAudit.summaryPath} review candidate count mismatch`);
  assert(summary.silentConflictConfirmationCount === 0, `${shadowAudit.summaryPath} silent conflict confirmation detected`);
  assert(summary.strictComparisonConflictLeakCount === 0, `${shadowAudit.summaryPath} strict comparison conflict leak detected`);
  assert(summary.zaraRuntimeParserVerifiedCount === 0, `${shadowAudit.summaryPath} must not claim ZARA runtime verification`);
  const candidateBuffer = await readFile(join(corpusDirectory, shadowAudit.goldReviewCandidatesPath));
  assert(sha256(candidateBuffer) === shadowAudit.goldReviewCandidatesSha256, `${shadowAudit.goldReviewCandidatesPath} checksum changed`);
  const candidates = JSON.parse(candidateBuffer.toString("utf8"));
  assert(Array.isArray(candidates), `${shadowAudit.goldReviewCandidatesPath} must be an array`);
  assert(candidates.length === shadowAudit.goldReviewCandidateCount, `${shadowAudit.goldReviewCandidatesPath} candidate count changed`);
  assert(candidates.every((row) => row.shadowStatus !== "confirmed"), `${shadowAudit.goldReviewCandidatesPath} contains an auto-confirmed row`);

  liveSampleSummaries.push({
    path: sample.path,
    rows: rows.length,
    independentLabels: sample.independentLabelCount,
    perSourceRows: Object.fromEntries(sourceCounts),
    overlapWithBaseCorpus: Object.fromEntries(overlapCounts),
    newRowsAgainstBaseCorpus: Object.fromEntries(newCounts),
    goldReviewCandidates: candidates.length,
    silentConflictConfirmations: summary.silentConflictConfirmationCount,
    strictComparisonConflictLeaks: summary.strictComparisonConflictLeakCount
  });
}

console.log(JSON.stringify({
  status: "passed",
  contractVersion: manifest.contractVersion,
  productionImportAllowed: manifest.productionImportAllowed,
  goldFixtureApprovalAllowed: manifest.goldFixtureApprovalAllowed,
  sources: summaries,
  liveSamples: liveSampleSummaries
}, null, 2));
