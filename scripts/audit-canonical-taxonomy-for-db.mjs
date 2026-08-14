import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const outDir = join(root, "Docs/Research/CanonicalTaxonomyAudit-20260814");
const readJSON = async (path) => JSON.parse(await readFile(join(root, path), "utf8"));
const normalize = (value = "") => value.normalize("NFC").trim().replace(/\s+/g, " ");
const key = (source, path) => `${source}|${normalize(path)}`;
const hash = (value) => createHash("sha256").update(value).digest("hex");
const countBy = (values) => Object.fromEntries([...Map.groupBy(values, (value) => value)].map(([value, rows]) => [value, rows.length]).sort());
const dominant = (counts) => {
  const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const total = sorted.reduce((sum, [, count]) => sum + count, 0);
  return sorted.length ? { value: sorted[0][0], count: sorted[0][1], total, ratio: sorted[0][1] / total } : null;
};

const [bundle, comparison, manifest, appTaxonomy, musinsaSnapshot, uniqloSnapshot, aResults, liveA] = await Promise.all([
  readJSON("FitMatch/CanonicalTaxonomyBundle/FitMatchSourceCategoryMappings.json"),
  readJSON("FitMatch/CanonicalTaxonomyBundle/FitMatchComparisonPolicies.json"),
  readJSON("FitMatch/CanonicalTaxonomyBundle/FitMatchTaxonomyBundleManifest.json"),
  readJSON("FitMatch/FitMatchTaxonomy.json"),
  readJSON("Docs/Research/OfficialTaxonomySnapshot-20260803/musinsa-official-taxonomy-snapshot.json"),
  readJSON("Docs/Research/OfficialTaxonomySnapshot-20260803/uniqlo-official-taxonomy-snapshot.json"),
  readJSON("Docs/Research/CanonicalTaxonomyAudit-20260814/current-production-5026-results.json"),
  readJSON("Docs/TestEvidence/LiveA100-20260814/results.json"),
]);

const familyTransforms = comparison.currentAppFamilyTransforms;
const validAppCategories = new Set(appTaxonomy.categories.map((category) => category.code));
const snapshots = [...musinsaSnapshot.nodes, ...uniqloSnapshot.nodes];
const mappingByIdentity = new Map(bundle.records.map((record) => [record.sourceIdentity, record]));
const mappingBySourceNode = new Map(bundle.records.map((record) => [
  `${record.source}|${record.snapshotID}|${record.externalCategoryID}|${record.target}|${normalize(record.normalizedPath)}`,
  record,
]));

const productEvidence = [...aResults];
for (const testCase of liveA.cases) {
  for (const item of [testCase.closet, testCase.comparison_product]) {
    const [category = "", detail = ""] = item.fitmatch_category.split(" / ");
    productEvidence.push({
      source: item.source,
      sourcePath: item.shopping_mall_category,
      productID: item.product_id,
      productName: item.product_name,
      finalCategoryCode: ({ 상의: "tops", 하의: "bottoms", 아우터: "outerwear", 스커트: "skirts", 원피스: "dresses", 레깅스: "leggings", 속옷: "underwear" })[category] ?? "other",
      finalDetailCode: detail,
      garmentFamily: null,
      classificationIsValid: true,
      userConfirmationRequired: false,
      evidenceSource: "live-a100",
    });
  }
}
const evidenceByPath = Map.groupBy(productEvidence, (row) => key(row.source, row.sourcePath));

const nonGarment = /(^| > )(가방|지갑\/가방|패션소품|액세서리|소품|신발|뷰티|디지털\/라이프|가구\/인테리어|반려동물|모터스)( > |$)|브리프\s*케이스|briefcase/i;
const mixedNavigation = /(^| > )(기타|그 외|전체|컬렉션|유니폼|캐릭터|스포츠 구단|Special Collaborations)( > |$)/i;
const garmentToken = /티셔츠|셔츠|블라우스|폴로|피케|니트|스웨터|가디건|카디건|맨투맨|스웨트|후드|민소매|슬리브리스|팬츠|바지|데님|슬랙스|트라우저|치노|카고|조거|레깅스|스커트|재킷|자켓|블루종|아노락|바람막이|플리스|패딩|코트|무스탕|원피스|드레스|브라|팬티|속옷|이너웨어|t-?shirts?|shirts?|blouses?|polos?|knit|sweaters?|cardigans?|sweats?|hoodies?|pants?|jeans?|leggings?|skirts?|jackets?|coats?|dresses?/i;

function strongMajor(path) {
  const normalized = normalize(path);
  const segments = normalized.split(" > ");
  const root = segments[0] ?? "";
  const parent = segments.at(-2) ?? "";
  const leaf = segments.at(-1) ?? "";
  if (/반려동물|브리프\s*케이스|briefcase/i.test(path)) return "non_garment";
  if (/가방|지갑|신발|액세서리|패션소품/.test(leaf)) return "non_garment";
  if (/이너웨어|언더웨어|에어리즘|히트텍/.test(root) || /이너웨어|언더웨어/.test(parent)) {
    if (/레깅스|타이즈/.test(leaf)) return "leggings";
    return "underwear";
  }
  if (/아우터/.test(root) || /아우터/.test(parent)) return "outerwear";
  if (/팬츠|바지|청바지|하의/.test(root) || /팬츠|바지|청바지|하의/.test(parent)) {
    if (/스커트|스코츠/.test(leaf)) return "skirts";
    return "bottoms";
  }
  if (/니트|가디건|티셔츠|셔츠|상의/.test(root) || /니트|가디건|티셔츠|셔츠|상의/.test(parent)) {
    if (/팬츠|바지/.test(leaf)) return "bottoms";
    return "tops";
  }
  if (/원피스|드레스/.test(leaf)) return "dresses";
  if (/스커트/.test(leaf)) return "skirts";
  if (/레깅스|타이즈/.test(leaf)) return "leggings";
  if (/팬츠|바지|데님|슬랙스|트라우저|쇼츠|반바지/.test(leaf)) return "bottoms";
  if (/재킷|자켓|코트|패딩|점퍼|블루종|아노락|바람막이|플리스|무스탕|아우터/.test(leaf)) return "outerwear";
  if (/티셔츠|셔츠|블라우스|폴로|피케|니트|스웨터|가디건|맨투맨|스웨트|후드|민소매|슬리브리스/.test(leaf)) return "tops";
  if (/브라|팬티|브리프|속옷|언더웨어/.test(leaf)) return "underwear";
  return null;
}

const allowedFamilyCategory = {
  tshirt: "tops", shirt: "tops", knit_cardigan: "tops", sweatshirt: "tops", hoodie: "tops",
  pants: "bottoms", denim: "bottoms", leggings: "leggings", skirt: "skirts", dress: "dresses",
  outerwear: "outerwear", leather_jacket: "outerwear", underwear: "underwear",
};

function mappingForNode(node) {
  const exact = mappingBySourceNode.get(`${node.source}|${node.source_snapshot_id ?? node.snapshot_id ?? (node.source === "musinsa" ? manifest.sourceSnapshots[0].snapshotID : manifest.sourceSnapshots[1].snapshotID)}|${node.external_category_id}|${node.target}|${normalize(node.normalized_full_path)}`);
  if (exact) return exact;
  const candidates = bundle.records.filter((record) => record.source === node.source && record.externalCategoryID === node.external_category_id && record.target === node.target && normalize(record.normalizedPath) === normalize(node.normalized_full_path));
  return candidates.length === 1 ? candidates[0] : null;
}

const audits = [];
for (const node of snapshots) {
  const record = mappingForNode(node);
  const evidence = evidenceByPath.get(key(node.source, node.normalized_full_path)) ?? [];
  const validEvidence = evidence.filter((row) => row.classificationIsValid && !row.userConfirmationRequired);
  const major = dominant(countBy(validEvidence.map((row) => row.finalCategoryCode).filter(Boolean)));
  const family = dominant(countBy(validEvidence.map((row) => row.garmentFamily).filter(Boolean)));
  const issues = [];
  let severity = "none";
  let proposedAction = record ? "keep" : "keep_navigation_only";
  let proposedStatus = record?.decisionStatus ?? "navigation_only";

  const raise = (level, code) => {
    issues.push(code);
    if ({ none: 0, low: 1, medium: 2, high: 3, critical: 4 }[level] > { none: 0, low: 1, medium: 2, high: 3, critical: 4 }[severity]) severity = level;
  };

  if (!record) {
    if (node.is_leaf && garmentToken.test(node.normalized_full_path)) raise("medium", "garment_leaf_missing_runtime_mapping");
  } else {
    const appCategory = record.appMapping?.categoryCode ?? record.semanticCategoryCode;
    const appFamily = familyTransforms[record.comparisonFamily] ?? record.comparisonFamily ?? record.appMapping?.currentComparisonFamily;
    const pathMajor = strongMajor(node.normalized_full_path);

    if (record.decisionStatus === "confirmed") {
      if (!record.eligibility || !record.semanticCategoryCode || !record.semanticGarmentType || !record.comparisonFamily || !record.appMapping) raise("critical", "confirmed_invariant_missing");
      if (nonGarment.test(node.normalized_full_path) && !/의류/.test(node.normalized_full_path)) {
        raise("critical", "confirmed_non_garment_context"); proposedAction = "change_to_rejected"; proposedStatus = "rejected";
      }
      if (pathMajor === "non_garment") {
        raise("critical", "confirmed_non_garment_leaf"); proposedAction = "change_to_rejected"; proposedStatus = "rejected";
      } else if (pathMajor && appCategory && pathMajor !== appCategory) {
        raise("high", "strong_path_major_mismatch"); proposedAction = "change_to_review_required"; proposedStatus = "review_required";
      }
      if (appFamily && allowedFamilyCategory[appFamily] && allowedFamilyCategory[appFamily] !== appCategory) {
        raise("critical", "family_major_incompatible"); proposedAction = "change_to_review_required"; proposedStatus = "review_required";
      }
      if (major && major.total >= 2 && major.ratio >= 0.9 && appCategory && major.value !== appCategory) {
        raise("critical", "a_test_major_consensus_mismatch"); proposedAction = "change_to_review_required"; proposedStatus = "review_required";
      }
      if (family && family.total >= 2 && family.ratio >= 0.9 && appFamily && family.value !== appFamily) {
        raise("high", "a_test_family_consensus_mismatch"); proposedAction = "change_to_review_required"; proposedStatus = "review_required";
      }
      if (mixedNavigation.test(node.normalized_full_path) && validEvidence.length === 0 && !garmentToken.test(node.raw_name)) {
        raise("high", "mixed_navigation_without_product_evidence"); proposedAction = "change_to_review_required"; proposedStatus = "review_required";
      }
      if (appCategory && !validAppCategories.has(appCategory)) raise("critical", "unknown_app_category");
    } else if (record.decisionStatus === "review_required") {
      if (major && family && major.total >= 3 && major.ratio === 1 && family.ratio === 1 && pathMajor === major.value) {
        raise("low", "promotion_candidate_from_a_test_consensus"); proposedAction = "candidate_confirmed";
      }
    } else if (record.decisionStatus === "rejected") {
      if (major && major.total >= 3 && major.ratio === 1 && pathMajor === major.value && pathMajor !== "non_garment") {
        raise("high", "rejected_but_a_test_garment_consensus"); proposedAction = "change_to_review_required"; proposedStatus = "review_required";
      }
    }
  }

  audits.push({
    source: node.source, externalCategoryID: node.external_category_id, target: node.target,
    path: node.normalized_full_path, depth: node.depth, isLeaf: node.is_leaf,
    sourceIdentity: record?.sourceIdentity ?? null, currentStatus: record?.decisionStatus ?? "navigation_only",
    currentCategory: record?.appMapping?.categoryCode ?? record?.semanticCategoryCode ?? null,
    currentDetail: record?.appMapping?.detailCode ?? null, currentGarment: record?.semanticGarmentType ?? null,
    currentFamily: record?.comparisonFamily ?? null, currentAppFamily: record ? (familyTransforms[record.comparisonFamily] ?? record.comparisonFamily ?? null) : null,
    aTestEvidenceCount: evidence.length, aTestValidCount: validEvidence.length,
    aTestMajorConsensus: major, aTestFamilyConsensus: family,
    strongPathMajor: strongMajor(node.normalized_full_path), severity, issues, proposedAction, proposedStatus,
  });
}

const summary = {
  generatedAt: new Date().toISOString(), sourceNodes: audits.length, runtimeMappings: bundle.records.length,
  aTestProducts: aResults.length, liveAProductsObserved: liveA.cases.length * 2,
  uniqueEvidencePaths: evidenceByPath.size,
  currentStatuses: countBy(audits.map((row) => row.currentStatus)),
  proposedActions: countBy(audits.map((row) => row.proposedAction)),
  severities: countBy(audits.map((row) => row.severity)),
  issueCounts: countBy(audits.flatMap((row) => row.issues)),
  highRiskCount: audits.filter((row) => ["high", "critical"].includes(row.severity)).length,
  evidenceCoverage: {
    pathsWithCurrentProductionOrLiveEvidence: evidenceByPath.size,
    highRiskRowsWithEvidence: audits.filter((row) => ["high", "critical"].includes(row.severity) && row.aTestValidCount > 0).length,
    highRiskRowsWithoutEvidence: audits.filter((row) => ["high", "critical"].includes(row.severity) && row.aTestValidCount === 0).length,
  },
  structuralChecks: {
    sourceNodesMatchManifest: audits.length === manifest.sourceRowCount,
    runtimeMappingsMatchManifest: bundle.records.length === manifest.runtimeMappingRowCount,
    everyMappingMatchedSnapshot: audits.filter((row) => row.sourceIdentity).length === bundle.records.length,
    sourceIdentityUnique: new Set(bundle.records.map((record) => record.sourceIdentity)).size === bundle.records.length,
  },
};

await mkdir(outDir, { recursive: true });
const resultBody = `${JSON.stringify({ summary, rows: audits }, null, 2)}\n`;
await writeFile(join(outDir, "audit-results.json"), resultBody);
await writeFile(join(outDir, "high-risk.json"), `${JSON.stringify(audits.filter((row) => ["high", "critical"].includes(row.severity)), null, 2)}\n`);
const csvFields = ["source","externalCategoryID","target","path","currentStatus","currentCategory","currentDetail","currentGarment","currentFamily","aTestEvidenceCount","strongPathMajor","severity","issues","proposedAction","proposedStatus"];
const csv = [csvFields.join(","), ...audits.map((row) => csvFields.map((field) => `"${String(Array.isArray(row[field]) ? row[field].join("|") : row[field] ?? "").replaceAll('"','""')}"`).join(","))].join("\n") + "\n";
await writeFile(join(outDir, "db-candidate-audit.csv"), csv);
const report = `# Canonical taxonomy DB preflight audit\n\n- Generated: ${summary.generatedAt}\n- Source nodes: ${summary.sourceNodes}\n- Runtime mappings: ${summary.runtimeMappings}\n- A-test product evidence: ${summary.aTestProducts}\n- Unique evidence paths: ${summary.uniqueEvidencePaths}\n- High/critical rows: ${summary.highRiskCount}\n\n## Proposed actions\n\n\`\`\`json\n${JSON.stringify(summary.proposedActions, null, 2)}\n\`\`\`\n\n## Issues\n\n\`\`\`json\n${JSON.stringify(summary.issueCounts, null, 2)}\n\`\`\`\n\n## Structural checks\n\n\`\`\`json\n${JSON.stringify(summary.structuralChecks, null, 2)}\n\`\`\`\n\nThis is a read-only preflight audit. No Supabase data was changed. Rows without product evidence are not represented as A-test verified.\n`;
await writeFile(join(outDir, "report.md"), report);
const productionBody = await readFile(join(outDir, "current-production-5026-results.json"));
await writeFile(join(outDir, "manifest.json"), `${JSON.stringify({ files: { "audit-results.json": hash(resultBody), "db-candidate-audit.csv": hash(csv), "report.md": hash(report), "current-production-5026-results.json": hash(productionBody) }, summary }, null, 2)}\n`);
console.log(JSON.stringify(summary, null, 2));
