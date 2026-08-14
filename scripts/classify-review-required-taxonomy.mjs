import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const bundleDir = join(root, "Docs/Research/CanonicalTaxonomyBundle-20260803");
const inputPath = join(bundleDir, "FitMatchSourceCategoryMappings.json");
const outputPath = join(bundleDir, "FitMatchReviewRequiredClassificationProposal.json");
const reportPath = join(bundleDir, "FitMatchReviewRequiredClassificationReport.md");
const bundle = JSON.parse(await readFile(inputPath, "utf8"));

const reviewRecords = bundle.records.filter((record) => record.decisionStatus === "review_required");
const fallbackInputs = ["product_name", "detail_information", "raw_path", "official_size_chart", "measurements"];

const rejectedRootPattern = /^(F&amp;B|뷰티|디지털\/라이프|모터스|K-커넥트)$/i;
const mixedRootPattern = /^(스포츠 구단|만화\/애니메이션|캐릭터|영화\/드라마|음악|콘텐츠|Special Collaborations)$/i;
const ambiguousPattern = /(^|\s|>|\/)(기타|그 외|전체|컬렉션|굿즈|유니폼)(\s|$|>|\/)/i;
const nonHumanPattern = /반려동물|드레스룸가구|조명|키친웨어|테이블웨어|텍스타일|쥬얼리|악세서리|머플러|벨트|앨범|아트 토이/i;
const nonGarmentContainerPattern = /(^| > )(가방|지갑\/가방)( > |$)|브리프\s*케이스|briefcase/i;

const rules = [
  { pattern: /블루종|MA-1|스타디움 재킷/i, garment: "blouson", family: "blouson", category: "outerwear", detail: "blouson" },
  { pattern: /레더|라이더스/i, garment: "leather_jacket", family: "leather_jacket", category: "outerwear", detail: "leather_jacket" },
  { pattern: /나일론|코치 재킷|바람막이|윈드브레이커/i, garment: "windbreaker", family: "windbreaker", category: "outerwear", detail: "windbreaker" },
  { pattern: /아노락/i, garment: "anorak", family: "anorak", category: "outerwear", detail: "anorak" },
  { pattern: /플리스|후리스/i, garment: "fleece_jacket", family: "fleece_jacket", category: "outerwear", detail: "fleece_jacket" },
  { pattern: /무스탕|퍼 재킷/i, garment: "mouton", family: "mouton", category: "outerwear", detail: "mouton" },
  { pattern: /패딩.*베스트|패딩.*조끼/i, garment: "puffer_vest", family: "puffer_vest", category: "outerwear", detail: "puffer_vest" },
  { pattern: /패딩|헤비 아우터/i, garment: "puffer_jacket", family: "puffer_jacket", category: "outerwear", detail: "puffer_jacket" },
  { pattern: /블레이저|슈트.*재킷/i, garment: "blazer", family: "blazer", category: "outerwear", detail: "blazer" },
  { pattern: /코트|레인코트/i, garment: "coat", family: "coat", category: "outerwear", detail: "coat" },
  { pattern: /사파리|헌팅 재킷|트레이닝 재킷/i, garment: "jacket", family: "jacket", category: "outerwear", detail: "jacket" },
  { pattern: /아우터.*베스트|(^| > )베스트$/i, garment: "outer_vest", family: "outer_vest", category: "outerwear", detail: "outer_vest" },
  { pattern: /후드.*집업/i, garment: "zip_hoodie", family: "zip_hoodie", category: "tops", detail: "zip_hoodie" },
  { pattern: /후드/i, garment: "hoodie", family: "hoodie", category: "tops", detail: "hoodie" },
  { pattern: /맨투맨|스웨트셔츠/i, garment: "sweatshirt", family: "sweatshirt", category: "tops", detail: "sweatshirt" },
  { pattern: /카디건|가디건/i, garment: "cardigan", family: "cardigan", category: "tops", detail: "cardigan" },
  { pattern: /니트 베스트|니트 조끼/i, garment: "knit_vest", family: "knit_vest", category: "tops", detail: "knit_vest" },
  { pattern: /피케|카라 티셔츠|폴로/i, garment: "polo_shirt", family: "polo_shirt", category: "tops", detail: "polo_shirt" },
  { pattern: /니트|스웨터|Knitwear/i, garment: "knit_sweater", family: "knit_sweater", category: "tops", detail: "knit_sweater" },
  { pattern: /민소매|탱크탑|슬리브리스/i, garment: "tank_top", family: "tank_top", category: "tops", detail: "sleeveless" },
  { pattern: /티셔츠|반팔|반소매|긴팔|긴소매/i, garment: "tshirt", family: "tshirt", category: "tops", detail: "tshirt" },
  { pattern: /셔츠|블라우스/i, garment: "shirt_blouse", family: "shirt_blouse", category: "tops", detail: "shirt_blouse" },
  { pattern: /데님|청바지|진즈/i, garment: "denim_pants", family: "denim_pants", category: "bottoms", detail: "denim_pants" },
  { pattern: /슬랙스|트라우저/i, garment: "slacks_trousers", family: "slacks_trousers", category: "bottoms", detail: "slacks_trousers" },
  { pattern: /카고/i, garment: "cargo_pants", family: "cargo_pants", category: "bottoms", detail: "cargo_pants" },
  { pattern: /조거|트레이닝.*팬츠|스웨트.*팬츠/i, garment: "sweat_jogger_pants", family: "sweat_jogger_pants", category: "bottoms", detail: "sweat_jogger_pants" },
  { pattern: /레깅스|타이즈/i, garment: "leggings", family: "leggings", category: "leggings", detail: "leggings" },
  { pattern: /스커트/i, garment: "skirt", family: "skirt", category: "skirts", detail: "skirt" },
  { pattern: /원피스|드레스/i, garment: "dress", family: "dress", category: "dresses", detail: "dress" },
  { pattern: /점프슈트|오버올|커버올|롬퍼/i, garment: "coverall_romper", family: "casual_pants", category: "bottoms", detail: "coverall_romper" },
  { pattern: /숏 팬츠|쇼츠|반바지|캐주얼 팬츠|와이드 팬츠|배럴 레그 팬츠|치노|코튼 팬츠|라운지 팬츠/i, garment: "casual_pants", family: "casual_pants", category: "bottoms", detail: "casual_pants" },
  { pattern: /브라/i, garment: "bra", family: "bra", category: "underwear", detail: "bra" },
  { pattern: /여성 속옷 하의|팬티|브리프/i, garment: "underwear_bottom", family: "underwear_bottom", category: "underwear", detail: "underwear_bottom" },
  { pattern: /히트텍.*(반팔|반소매)/i, garment: "base_layer_top", family: "base_layer_top", category: "tops", detail: "short_sleeve" },
  { pattern: /히트텍.*(긴팔|긴소매)/i, garment: "base_layer_top", family: "base_layer_top", category: "tops", detail: "long_sleeve" },
];

function classify(record) {
  const path = record.normalizedPath;
  const segments = path.split(" > ");
  const rootName = segments[0];
  const leaf = segments.at(-1);
  const parent = segments.at(-2) ?? "";

  if (rejectedRootPattern.test(rootName) || nonHumanPattern.test(path) || nonGarmentContainerPattern.test(path)) {
    return { outcome: "rejected", reason: "명확한 비의류 또는 사람용 핏 비교 대상이 아님" };
  }

  if (mixedRootPattern.test(rootName)) {
    return { outcome: "review_required", reason: "브랜드/콘텐츠 탐색 경로로 여러 상품 종류가 혼재함" };
  }

  if (ambiguousPattern.test(path)) {
    return { outcome: "review_required", reason: "기타/컬렉션/유니폼 등 상품 단위 판정이 필요한 혼합 카테고리" };
  }

  const contextual = (() => {
    if (/스커트.*원피스|원피스.*스커트/.test(parent) && /스커트.*원피스|원피스.*스커트/.test(leaf)) return null;
    if (/스웨트셔츠 & 후드집업/.test(parent) && /팬츠/.test(leaf)) return { garment: "sweat_jogger_pants", family: "sweat_jogger_pants", category: "bottoms", detail: "sweat_jogger_pants" };
    if (/^팬츠$/.test(leaf)) return { garment: "casual_pants", family: "casual_pants", category: "bottoms", detail: "casual_pants" };
    if (/레깅스|타이즈/.test(parent)) return { garment: "leggings", family: "leggings", category: "leggings", detail: "leggings" };
    if (/스커트/.test(parent)) return { garment: "skirt", family: "skirt", category: "skirts", detail: "skirt" };
    if (/원피스/.test(parent)) return { garment: "dress", family: "dress", category: "dresses", detail: "dress" };
    if (/청바지/.test(parent)) return { garment: "denim_pants", family: "denim_pants", category: "bottoms", detail: "denim_pants" };
    if (/와이드 팬츠|캐주얼 팬츠|배럴 레그 팬츠|반바지/.test(parent)) return { garment: "casual_pants", family: "casual_pants", category: "bottoms", detail: "casual_pants" };
    if (/재킷 & 블레이저/.test(parent)) return { garment: "blazer", family: "blazer", category: "outerwear", detail: "blazer" };
    if (/재킷 & 코트/.test(parent)) return { garment: "jacket", family: "jacket", category: "outerwear", detail: "jacket" };
    if (/파카 & 블루종/.test(parent)) return { garment: "blouson", family: "blouson", category: "outerwear", detail: "blouson" };
    if (/스웨트셔츠 & 후드집업/.test(parent)) return null;
    if (/이너웨어 > 에어리즘/.test(path) && /쇼츠|브리프|비키니|힙허거/.test(leaf)) return { garment: "underwear_bottom", family: "underwear_bottom", category: "underwear", detail: "underwear_bottom" };
    if (/이너웨어 > 히트텍/.test(path) && /반팔|반소매|긴팔|긴소매/.test(leaf)) return { garment: "base_layer_top", family: "base_layer_top", category: "tops", detail: /반팔|반소매/.test(leaf) ? "short_sleeve" : "long_sleeve" };
    return undefined;
  })();
  if (contextual === null) {
    return { outcome: "review_required", reason: "스웨트셔츠와 후드집업이 혼재한 상위 카테고리" };
  }
  const matched = contextual ?? rules.find((rule) => rule.pattern.test(leaf));
  if (!matched) {
    return { outcome: "review_required", reason: "안전한 category-level 의류 규칙 없음" };
  }

  return {
    outcome: "confirmed",
    reason: `명시적 의류 경로 규칙: ${matched.garment}`,
    semanticGarmentType: matched.garment,
    comparisonFamily: matched.family,
    semanticCategoryCode: matched.category,
    appDetailCode: matched.detail,
  };
}

const proposals = reviewRecords.map((record) => ({
  sourceIdentity: record.sourceIdentity,
  source: record.source,
  externalCategoryID: record.externalCategoryID,
  target: record.target,
  normalizedPath: record.normalizedPath,
  previousStatus: record.decisionStatus,
  ...classify(record),
}));

const counts = Object.fromEntries(
  ["confirmed", "rejected", "review_required"].map((status) => [
    status,
    proposals.filter((proposal) => proposal.outcome === status).length,
  ]),
);
const familyCounts = Object.fromEntries(
  [...Map.groupBy(proposals.filter((proposal) => proposal.outcome === "confirmed"), (proposal) => proposal.comparisonFamily)]
    .map(([family, records]) => [family, records.length])
    .sort((a, b) => b[1] - a[1]),
);
const payload = {
  schemaVersion: "1.0",
  basedOnPolicyVersion: bundle.policyVersion,
  mode: "proposal_only",
  safeguards: {
    runtimeBundleModified: false,
    categoryLevelConfirmationRequiresExplicitGarmentPath: true,
    mixedCommercePathsRemainProductFallback: true,
    physicalDeletionAllowed: false,
  },
  counts: { inputReviewRequired: reviewRecords.length, ...counts },
  familyCounts,
  proposals,
};
const body = `${JSON.stringify(payload, null, 2)}\n`;
await mkdir(bundleDir, { recursive: true });
await writeFile(outputPath, body);

const examples = (status) => proposals
  .filter((proposal) => proposal.outcome === status)
  .slice(0, 20)
  .map((proposal) => `- ${proposal.source} \`${proposal.externalCategoryID ?? "path"}\`: ${proposal.normalizedPath}${proposal.comparisonFamily ? ` → ${proposal.comparisonFamily}` : ""}`)
  .join("\n");
const report = `# Review-required classification proposal\n\n` +
  `- Input: ${reviewRecords.length}\n` +
  `- Proposed confirmed: ${counts.confirmed}\n` +
  `- Proposed rejected: ${counts.rejected}\n` +
  `- Product fallback retained: ${counts.review_required}\n` +
  `- Proposal SHA-256: ${createHash("sha256").update(body).digest("hex")}\n` +
  `- Runtime bundle modified: no\n\n` +
  `## Family counts\n\n\`\`\`json\n${JSON.stringify(familyCounts, null, 2)}\n\`\`\`\n\n` +
  `## Confirmed examples\n\n${examples("confirmed")}\n\n` +
  `## Rejected examples\n\n${examples("rejected")}\n\n` +
  `## Product fallback examples\n\n${examples("review_required")}\n`;
await writeFile(reportPath, report);
console.log(JSON.stringify(payload.counts, null, 2));
console.log(JSON.stringify(familyCounts, null, 2));
