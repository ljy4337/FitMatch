import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const research = join(root, "Docs/Research/CanonicalTaxonomyBundle-20260803");
const runtime = join(root, "FitMatch/CanonicalTaxonomyBundle");
const policyVersion = "taxonomy-refined-2026-08-03";
const names = {
  mappings: "FitMatchSourceCategoryMappings.json",
  comparison: "FitMatchComparisonPolicies.json",
  measurement: "FitMatchMeasurementPolicies.json",
  manifest: "FitMatchTaxonomyBundleManifest.json",
};
const parse = async (dir, name) => JSON.parse(await readFile(join(dir, name), "utf8"));
const [mappings, comparison, measurement, manifest, proposal] = await Promise.all([
  parse(research, names.mappings), parse(research, names.comparison),
  parse(research, names.measurement), parse(research, names.manifest),
  parse(research, "FitMatchReviewRequiredClassificationProposal.json"),
]);
if (proposal.proposals.length !== 894) throw new Error("Expected 894 proposals");
const byIdentity = new Map(proposal.proposals.map((item) => [item.sourceIdentity, item]));
if (byIdentity.size !== 894) throw new Error("Proposal identities must be unique");

for (const record of mappings.records) {
  record.policyVersion = policyVersion;
  const decision = byIdentity.get(record.sourceIdentity);
  if (!decision) continue;
  record.decisionStatus = decision.outcome;
  record.decisionReasonSummary = decision.reason;
  record.resolutionMethod = decision.outcome === "review_required"
    ? "product_level_fallback" : "review_required_refinement";
  if (decision.outcome === "confirmed") {
    record.semanticCategoryCode = decision.semanticCategoryCode;
    record.semanticGarmentType = decision.semanticGarmentType;
    record.comparisonFamily = decision.comparisonFamily;
    record.eligibility = true;
    record.exclusionReasonCode = null;
    record.fallbackInputs = [];
    record.fallbackRequired = false;
    record.extension = null;
    record.extensionRequired = false;
    const transformed = comparison.currentAppFamilyTransforms[decision.comparisonFamily];
    record.appMapping = {
      categoryCode: decision.semanticCategoryCode,
      currentComparisonFamily: decision.comparisonFamily,
      currentLengthType: null,
      detailCode: decision.appDetailCode,
      lossiness: transformed ? "semantic_to_app_loss" : "none",
      mappingStatus: transformed ? "transform_required" : "direct",
      transformationRule: "category refinement; product resolver supplements missing length/construction",
    };
  } else if (decision.outcome === "rejected") {
    record.semanticCategoryCode = null;
    record.semanticGarmentType = null;
    record.comparisonFamily = null;
    record.eligibility = false;
    record.exclusionReasonCode = "not_fitmatch_comparable";
    record.fallbackInputs = [];
    record.fallbackRequired = false;
    record.appMapping = null;
    record.extension = null;
    record.extensionRequired = false;
  }
}
if ([...byIdentity.keys()].some((key) => !mappings.records.some((record) => record.sourceIdentity === key))) {
  throw new Error("Proposal contains an unmatched source identity");
}
mappings.policyVersion = policyVersion;

comparison.policyVersion = policyVersion;
if (!comparison.families.some((family) => family.code === "leather_jacket")) {
  comparison.families.push({
    code: "leather_jacket", current_app_family_code: "leather_jacket",
    is_active: true, minimum_comparable_measurements: 2,
  });
}
comparison.families.sort((a, b) => a.code.localeCompare(b.code));
const outerPolicy = comparison.garmentPolicies.find((item) => item.comparisonFamily === "outerwear");
comparison.garmentPolicies = comparison.garmentPolicies.filter((item) => item.comparisonFamily !== "leather_jacket");
comparison.garmentPolicies.push({
  ...outerPolicy,
  comparisonFamily: "leather_jacket",
  requiredMeasurements: ["chest", "total_length"],
  optionalMeasurements: ["shoulder", "sleeve_length"],
  minimumComparableMeasurements: 2,
});
comparison.garmentPolicies.sort((a, b) => a.comparisonFamily.localeCompare(b.comparisonFamily));
comparison.compatibility = comparison.compatibility.filter((rule) =>
  rule.fromFamily !== "leather_jacket" && rule.toFamily !== "leather_jacket");
comparison.compatibility.push(
  { allowed: true, directional: false, fallbackAllowed: false, fromFamily: "leather_jacket", lengthMatchRequired: false, lengthMismatchExcludedMeasurements: [], minimumCommonMeasurements: 2, requiredMeasurements: ["chest", "total_length"], toFamily: "leather_jacket", weights: { chest: 0.5, total_length: 0.5 } },
  ...[["leather_jacket", "jacket"], ["jacket", "leather_jacket"], ["leather_jacket", "outerwear"], ["outerwear", "leather_jacket"]].map(([fromFamily, toFamily]) =>
    ({ allowed: false, directional: true, fallbackAllowed: false, fromFamily, lengthMatchRequired: false, lengthMismatchExcludedMeasurements: [], minimumCommonMeasurements: 2, requiredMeasurements: ["chest", "total_length"], toFamily, weights: {} })),
);
comparison.compatibility.sort((a, b) => `${a.fromFamily}|${a.toFamily}`.localeCompare(`${b.fromFamily}|${b.toFamily}`));
measurement.policyVersion = policyVersion;

const statusCounts = Object.fromEntries(["navigation_only", "confirmed", "review_required", "rejected", "unsupported"]
  .map((status) => [status, mappings.records.filter((record) => record.decisionStatus === status).length]));
if (JSON.stringify(statusCounts) !== JSON.stringify({ navigation_only: 0, confirmed: 1331, review_required: 608, rejected: 1447, unsupported: 40 })) {
  throw new Error(`Unexpected runtime status counts: ${JSON.stringify(statusCounts)}`);
}
const sha = (data) => createHash("sha256").update(data).digest("hex");
const bodies = {
  [names.mappings]: `${JSON.stringify(mappings, null, 2)}\n`,
  [names.comparison]: `${JSON.stringify(comparison, null, 2)}\n`,
  [names.measurement]: `${JSON.stringify(measurement, null, 2)}\n`,
};
manifest.policyVersion = policyVersion;
manifest.generatedAt = new Date().toISOString();
manifest.statusCounts = { ...manifest.statusCounts, confirmed: 1331, review_required: 608, rejected: 1447 };
manifest.mappingCounts = {
  direct: mappings.records.filter((record) => record.appMapping?.mappingStatus === "direct").length,
  transform_required: mappings.records.filter((record) => record.appMapping?.mappingStatus === "transform_required").length,
};
manifest.extensionRegistryCount = mappings.records.filter((record) => record.extensionRequired).length;
manifest.lookupValidation.confirmedIdentifiable = 1331;
manifest.lookupValidation.confirmedUnidentifiable = 0;
manifest.files[names.mappings] = { rows: mappings.records.length, bytes: Buffer.byteLength(bodies[names.mappings]), sha256: sha(bodies[names.mappings]) };
manifest.files[names.comparison] = { families: comparison.families.length, compatibilityRules: comparison.compatibility.length, garmentPolicies: comparison.garmentPolicies.length, bytes: Buffer.byteLength(bodies[names.comparison]), sha256: sha(bodies[names.comparison]) };
manifest.files[names.measurement] = { ...manifest.files[names.measurement], bytes: Buffer.byteLength(bodies[names.measurement]), sha256: sha(bodies[names.measurement]) };
manifest.bundleChecksum = sha(Object.keys(manifest.files).sort().map((name) => `${name}\0${manifest.files[name].sha256}\n`).join(""));
const manifestBody = `${JSON.stringify(manifest, null, 2)}\n`;
for (const dir of [research, runtime]) {
  await Promise.all(Object.entries(bodies).map(([name, body]) => writeFile(join(dir, name), body)));
  await writeFile(join(dir, names.manifest), manifestBody);
}
console.log(JSON.stringify({ policyVersion, statusCounts, mappingCounts: manifest.mappingCounts, files: manifest.files, bundleChecksum: manifest.bundleChecksum }, null, 2));
