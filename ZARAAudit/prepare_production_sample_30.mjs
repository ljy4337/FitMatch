import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, join } from "node:path";

const inputPath = process.argv[2];
const outputDirectory = process.argv[3] ?? new URL(".", import.meta.url).pathname;
if (!inputPath) {
  throw new Error("usage: node prepare_production_sample_30.mjs <zara_products.json> [output-directory]");
}

const sourceRows = JSON.parse(await readFile(inputPath, "utf8"));
const byProduct = Map.groupBy(sourceRows, (row) => String(row.product_id));
const reviewSampleID = "545473154";
const selected = [...byProduct.entries()]
  .filter(([productID, rows]) => rows[0].fitmatch_mapping_status === "LOCKED" || productID === reviewSampleID)
  .sort(([left], [right]) => left.localeCompare(right))
  .slice(0, 30);

if (selected.length !== 30) {
  throw new Error(`expected 30 products, found ${selected.length}`);
}

const capturedAt = new Date().toISOString();
const cacheDirectory = join(outputDirectory, "production_sample_30_cache");
await mkdir(cacheDirectory, { recursive: true });

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const normalizeSizeIdentity = (value) => value.trim().toLowerCase().replaceAll(/[^a-z0-9가-힣]+/g, "_").replaceAll(/^_|_$/g, "");

async function requestGuide(variantID) {
  const cachePath = join(cacheDirectory, `${variantID}.json`);
  try {
    const cached = await readFile(cachePath, "utf8");
    return { ...JSON.parse(cached), cachePath };
  } catch {}

  const url = `https://www.zara.com/itxrest/4/catalog/store/11717/product/${variantID}/size-measure-guide?locale=ko_KR`;
  let attempt = 0;
  let record;
  while (attempt < 2) {
    const response = await fetch(url, {
      headers: {
        accept: "application/json",
        "accept-language": "ko-KR,ko;q=0.9",
        "user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Version/18.6 Mobile/15E148 Safari/604.1"
      },
      redirect: "follow"
    });
    const body = await response.text();
    const challengeDetected = /akamai|captcha|reference\s*#|access denied/i.test(body)
      || (response.headers.get("content-type") ?? "").includes("text/html");
    let json = null;
    if (!challengeDetected) {
      try { json = JSON.parse(body); } catch {}
    }
    record = {
      captured_at: capturedAt,
      request_url: url,
      http_status: response.status,
      challenge_detected: challengeDetected,
      response_hash: sha256(body),
      response: json
    };
    if (response.status < 500 || response.status > 599 || attempt === 1) break;
    attempt += 1;
    await delay(500);
  }
  await writeFile(cachePath, `${JSON.stringify(record, null, 2)}\n`);
  await delay(300);
  return { ...record, cachePath };
}

function classificationFor(row) {
  if (row.fitmatch_mapping_status !== "LOCKED") {
    return {
      category_code: row.official_major_preserved === "하의" ? "bottoms" : null,
      detail_code: null,
      comparison_family: null,
      length_type: "unknown",
      requires_user_confirmation: true
    };
  }
  if (row.family_name === "브레이저") {
    return { category_code: "outerwear", detail_code: "blazer", comparison_family: "outerwear", length_type: "unknown", requires_user_confirmation: false };
  }
  if (row.family_name === "가디건") {
    return { category_code: "outerwear", detail_code: "cardigan", comparison_family: "knit_cardigan", length_type: "unknown", requires_user_confirmation: false };
  }
  if (row.family_name === "스포츠 재킷") {
    return { category_code: "outerwear", detail_code: "jacket", comparison_family: "outerwear", length_type: "unknown", requires_user_confirmation: false };
  }
  if (row.family_name === "티셔츠") {
    const longSleeve = /m\/l|long sleeve|롱 슬리브|긴팔/i.test(`${row.subfamily_name ?? ""} ${row.name}`);
    return {
      category_code: "tops",
      detail_code: longSleeve ? "long_sleeve" : "short_sleeve",
      comparison_family: "tshirt",
      length_type: longSleeve ? "long_sleeve" : "short_sleeve",
      requires_user_confirmation: false
    };
  }
  if (row.family_name === "셔츠") {
    return { category_code: "tops", detail_code: "shirt", comparison_family: "shirt", length_type: "unknown", requires_user_confirmation: false };
  }
  if (row.family_name === "바지") {
    return { category_code: "bottoms", detail_code: "long_pants", comparison_family: "pants", length_type: "long_sleeve", requires_user_confirmation: false };
  }
  if (row.family_name === "드레스") {
    return { category_code: "dresses", detail_code: "one_piece", comparison_family: "dress", length_type: "unknown", requires_user_confirmation: false };
  }
  return { category_code: null, detail_code: null, comparison_family: null, length_type: "unknown", requires_user_confirmation: true };
}

function runtimeCategoryFor(row) {
  const section = row.gender === "male" ? "MAN" : "WOMAN";
  const sectionName = row.gender === "male" ? "남성" : "여성";
  const family = String(row.family_name ?? "").trim();
  const subfamily = String(row.subfamily_name ?? "").trim();
  return {
    path: ["ZARA", sectionName, family, subfamily].filter(Boolean).join(" > "),
    codes: [section, family ? `${section}:${family}` : null, subfamily ? `${section}:${family}:${subfamily}` : null].filter(Boolean)
  };
}

const verifiedMeasurementCodes = (categoryScope, rawCode) => {
  if (categoryScope === "bottoms") {
    return new Set(["zone-name-waist", "zone-name-hips", "zone-name-front-rise"]).has(rawCode);
  }
  if (categoryScope === "dresses") {
    return new Set(["zone-name-chest", "zone-name-waist-full-body", "zone-name-hips"]).has(rawCode);
  }
  return false;
};

function sizesFromGuide(guide, fallbackOptions, variantID, categoryScope) {
  const guideSizes = guide?.measureGuideInfo?.sizes;
  if (Array.isArray(guideSizes) && guideSizes.length > 0) {
    return guideSizes.map((size, sizeIndex) => ({
      size_identity: String(size.id ?? normalizeSizeIdentity(size.name ?? `size_${sizeIndex}`)),
      external_size_id: size.id == null ? null : String(size.id),
      size_label: String(size.name ?? size.id ?? `size_${sizeIndex}`),
      normalized_size_label: String(size.name ?? size.id ?? `size_${sizeIndex}`),
      display_order: sizeIndex,
      stock_status: "unknown",
      raw_payload: { source: "zara_size_measure_guide", variant_id: variantID },
      measurements: (Array.isArray(size.measures) ? size.measures : []).flatMap((measure) => {
        const dimension = (Array.isArray(measure.dimensions) ? measure.dimensions : [])
          .find((item) => String(item.unitId).toLowerCase() === "cm");
        const value = Number(dimension?.value);
        if (!Number.isFinite(value) || value <= 0 || !measure.tableTitleZone) return [];
        const rawCode = String(measure.tableTitleZone);
        const mappingAllowed = verifiedMeasurementCodes(categoryScope, rawCode);
        return [{
          measurement_identity: `${measure.zoneId ?? "unknown"}:${measure.tableTitleZone}`,
          parser_code: "zara_kr_size_measure_guide_v1",
          category_scope: categoryScope,
          raw_code: rawCode,
          raw_label: rawCode,
          raw_value: value,
          raw_unit: "cm",
          raw_representation: measure.descriptionZone ?? null,
          observed_at: capturedAt,
          evidence: {
            source: "measureGuideInfo",
            raw_zone_id: measure.zoneId == null ? null : String(measure.zoneId),
            description_zone: measure.descriptionZone ?? null,
            source_dimensions: Array.isArray(measure.dimensions) ? measure.dimensions : [],
            measurement_basis_status: mappingAllowed ? "verified" : "unverified",
            canonical_mapping_allowed: mappingAllowed,
            variant_id: variantID
          }
        }];
      })
    }));
  }
  return (Array.isArray(fallbackOptions) ? fallbackOptions : []).map((size, index) => ({
    size_identity: String(size.id ?? normalizeSizeIdentity(size.name ?? `size_${index}`)),
    external_size_id: size.id == null ? null : String(size.id),
    size_label: String(size.name ?? size.id ?? `size_${index}`),
    normalized_size_label: String(size.name ?? size.id ?? `size_${index}`),
    display_order: index,
    stock_status: size.availability ?? "unknown",
    raw_payload: { source: "zara_catalog_size_option", sku: size.sku ?? null, reference: size.reference ?? null },
    measurements: []
  }));
}

const manifests = [];
const payloads = [];
const decisions = [];

for (const [productID, rows] of selected) {
  const representative = rows[0];
  const classification = classificationFor(representative);
  const variants = [...Map.groupBy(rows, (row) => String(row.variant_id)).entries()]
    .sort(([left], [right]) => left.localeCompare(right));
  const payloadVariants = [];
  let garmentVariantCount = 0;
  let bodyOnlyVariantCount = 0;
  let blockedVariantCount = 0;

  for (const [variantID, variantRows] of variants) {
    const variant = variantRows[0];
    const guideRecord = await requestGuide(variantID);
    const guide = guideRecord.response;
    const measurePresent = Array.isArray(guide?.measureGuideInfo?.sizes) && guide.measureGuideInfo.sizes.length > 0;
    const bodyPresent = guide?.sizeGuideInfo != null;
    if (measurePresent) garmentVariantCount += 1;
    else if (bodyPresent) bodyOnlyVariantCount += 1;
    else if (guideRecord.http_status !== 200 || guideRecord.challenge_detected) blockedVariantCount += 1;

    payloadVariants.push({
      external_variant_id: variantID,
      variant_name: variant.color ?? null,
      color_code: variant.color_code ?? null,
      color_name: variant.color ?? null,
      sku: variant.sku ?? null,
      raw_payload: {
        listing_product_id: variant.listing_product_id ?? null,
        variant_reference: variant.variant_reference ?? null,
        color_hex: variant.color_hex ?? null,
        guide_response_hash: guideRecord.response_hash,
        guide_http_status: guideRecord.http_status,
        measure_guide_present: measurePresent,
        size_guide_present: bodyPresent
      },
      sizes: sizesFromGuide(guide, variant.size_options, variantID, classification.category_code)
    });

    manifests.push({
      product_id: productID,
      variant_id: variantID,
      name: representative.name,
      gender: representative.gender,
      official_category_id: String(representative.official_category_id),
      official_category_path: representative.official_category_path,
      family_name: representative.family_name,
      subfamily_name: representative.subfamily_name,
      mapping_status: representative.fitmatch_mapping_status,
      http_status: guideRecord.http_status,
      challenge_detected: guideRecord.challenge_detected,
      response_type: measurePresent ? (bodyPresent ? "both" : "garment_measure") : (bodyPresent ? "body_only" : (guideRecord.http_status === 200 ? "empty" : "blocked")),
      measure_guide_present: measurePresent,
      size_guide_present: bodyPresent,
      raw_measurement_codes: [...new Set((guide?.measureGuideInfo?.sizes ?? []).flatMap((size) => (size.measures ?? []).map((measure) => measure.tableTitleZone)).filter(Boolean))],
      response_hash: guideRecord.response_hash,
      fixture_path: guideRecord.cachePath.replace(`${outputDirectory}/`, "")
    });
  }

  const runtimeCategory = runtimeCategoryFor(representative);
  payloads.push({
    source: "zara",
    external_product_id: productID,
    product_name: representative.name,
    canonical_url: representative.canonical_product_url ?? representative.product_url,
    audience: representative.gender,
    source_category_path: runtimeCategory.path,
    source_category_codes: runtimeCategory.codes,
    image_url: representative.image_urls?.[0] ?? null,
    observed_at: capturedAt,
    raw_payload: {
      batch_ingest_version: "zara-production-sample-2026-08-21-v1",
      source_package: basename(inputPath),
      product_id: productID,
      product_code: representative.product_code ?? null,
      model_code: representative.model_code ?? null,
      product_reference: representative.raw_source_reference ?? null,
      official_category_id: String(representative.official_category_id),
      family_id: representative.family_id ?? null,
      family_name: representative.family_name ?? null,
      subfamily_id: representative.subfamily_id ?? null,
      subfamily_name: representative.subfamily_name ?? null,
      price: representative.price ?? null,
      sale_price: representative.sale_price ?? null,
      currency: representative.currency ?? null,
      mapping_status: representative.fitmatch_mapping_status,
      measurement_basis_status: ["bottoms", "dresses"].includes(classification.category_code)
        ? "verified_subset"
        : "unverified",
      canonical_measurement_mapping_allowed: ["bottoms", "dresses"].includes(classification.category_code)
    },
    variants: payloadVariants
  });

  decisions.push({
    source: "zara",
    external_product_id: productID,
    product_name: representative.name,
    source_category_path: runtimeCategory.path,
    ...classification,
    decision_version: "zara-production-sample-2026-08-21-v1",
    evidence: {
      source_package: basename(inputPath),
      official_category_id: String(representative.official_category_id),
      official_category_path: representative.official_category_path,
      family_name: representative.family_name,
      subfamily_name: representative.subfamily_name,
      package_mapping_status: representative.fitmatch_mapping_status,
      measurement_basis_status: "unverified",
      garment_variant_count: garmentVariantCount,
      body_only_variant_count: bodyOnlyVariantCount,
      blocked_variant_count: blockedVariantCount
    }
  });
}

await writeFile(join(outputDirectory, "zara_production_sample_30_manifest.jsonl"), `${manifests.map((row) => JSON.stringify(row)).join("\n")}\n`);
await writeFile(join(outputDirectory, "zara_production_sample_30_payloads.jsonl"), `${payloads.map((row) => JSON.stringify(row)).join("\n")}\n`);
await writeFile(join(outputDirectory, "zara_production_sample_30_decisions.jsonl"), `${decisions.map((row) => JSON.stringify(row)).join("\n")}\n`);

console.log(JSON.stringify({
  products: payloads.length,
  variants: payloads.reduce((sum, payload) => sum + payload.variants.length, 0),
  manifest_rows: manifests.length,
  locked_decisions: decisions.filter((decision) => !decision.requires_user_confirmation).length,
  review_decisions: decisions.filter((decision) => decision.requires_user_confirmation).length,
  response_types: Object.fromEntries([...Map.groupBy(manifests, (row) => row.response_type)].map(([key, rows]) => [key, rows.length]))
}, null, 2));
