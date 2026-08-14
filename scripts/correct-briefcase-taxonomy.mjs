import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const bundleDirectories = [
  join(root, "FitMatch/CanonicalTaxonomyBundle"),
  join(root, "Docs/Research/CanonicalTaxonomyBundle-20260803"),
];
const briefcaseIDs = new Set(["004008", "105003002009", "107003001007", "108003001007"]);
const sha256 = (data) => createHash("sha256").update(data).digest("hex");

for (const directory of bundleDirectories) {
  const mappingPath = join(directory, "FitMatchSourceCategoryMappings.json");
  const manifestPath = join(directory, "FitMatchTaxonomyBundleManifest.json");
  const mapping = JSON.parse(await readFile(mappingPath, "utf8"));
  const corrected = [];
  for (const record of mapping.records) {
    if (record.source !== "musinsa" || !briefcaseIDs.has(record.externalCategoryID)) continue;
    if (!/가방|브리프\s*케이스/i.test(record.normalizedPath ?? "")) {
      throw new Error(`Refusing unexpected briefcase identity: ${record.sourceIdentity}`);
    }
    corrected.push(record.externalCategoryID);
    Object.assign(record, {
      appMapping: null,
      comparisonFamily: null,
      decisionReasonSummary: "briefcase is a bag and not a FitMatch-comparable garment",
      decisionStatus: "rejected",
      eligibility: false,
      exclusionReasonCode: "not_fitmatch_comparable",
      extension: null,
      extensionRequired: false,
      fallbackInputs: [],
      fallbackRequired: false,
      resolutionMethod: "explicit_non_garment_context_correction",
      semanticCategoryCode: null,
      semanticGarmentType: null,
    });
  }
  if (corrected.length !== briefcaseIDs.size) {
    throw new Error(`Expected ${briefcaseIDs.size} corrections in ${directory}, got ${corrected.length}`);
  }
  const mappingBody = `${JSON.stringify(mapping, null, 2)}\n`;
  await writeFile(mappingPath, mappingBody);

  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  manifest.statusCounts.confirmed = mapping.records.filter((record) => record.decisionStatus === "confirmed").length;
  manifest.statusCounts.review_required = mapping.records.filter((record) => record.decisionStatus === "review_required").length;
  manifest.statusCounts.rejected = mapping.records.filter((record) => record.decisionStatus === "rejected").length;
  manifest.statusCounts.unsupported = mapping.records.filter((record) => record.decisionStatus === "unsupported").length;
  manifest.mappingCounts = {
    direct: mapping.records.filter((record) => record.appMapping?.mappingStatus === "direct").length,
    transform_required: mapping.records.filter((record) => record.appMapping?.mappingStatus === "transform_required").length,
  };
  manifest.extensionRegistryCount = mapping.records.filter((record) => record.extensionRequired).length;
  manifest.files["FitMatchSourceCategoryMappings.json"] = {
    rows: mapping.records.length,
    bytes: Buffer.byteLength(mappingBody),
    sha256: sha256(mappingBody),
  };
  for (const name of ["FitMatchComparisonPolicies.json", "FitMatchMeasurementPolicies.json"]) {
    const body = await readFile(join(directory, name));
    manifest.files[name].bytes = body.length;
    manifest.files[name].sha256 = sha256(body);
  }
  manifest.bundleChecksum = sha256(
    Object.entries(manifest.files).sort(([a], [b]) => a.localeCompare(b))
      .map(([name, file]) => `${name}\0${file.sha256}\n`).join(""),
  );
  await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(JSON.stringify({ directory, corrected, statusCounts: manifest.statusCounts, mappingCounts: manifest.mappingCounts }));
}
