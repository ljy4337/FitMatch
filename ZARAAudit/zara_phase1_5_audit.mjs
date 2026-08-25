import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const auditDirectory = path.dirname(fileURLToPath(import.meta.url));
const inputPath = path.join(auditDirectory, "zara_phase1_5_identity_samples.jsonl");
const cacheDirectory = path.join(auditDirectory, "cache");
const manifestPath = path.join(auditDirectory, "zara_phase1_5_samples.csv");
const baseURL = "https://www.zara.com/itxrest/4/catalog/store/11717/product";
const capturedAt = new Date().toISOString();

await mkdir(cacheDirectory, { recursive: true });

const samples = (await readFile(inputPath, "utf8"))
  .split(/\r?\n/)
  .filter(Boolean)
  .map((line) => JSON.parse(line));

const rows = [];
for (const sample of samples) {
  rows.push(await auditSample(sample));
}

await writeFile(manifestPath, toCSV(rows), "utf8");
process.stdout.write(`${JSON.stringify(summarize(rows), null, 2)}\n`);

async function auditSample(sample) {
  const productID = sample.internal_product_id;
  const requestURL = `${baseURL}/${productID}/size-measure-guide?locale=ko_KR`;
  const cachePath = path.join(cacheDirectory, `${productID}.json`);
  let status = 0;
  let body;
  let fromCache = false;

  try {
    body = await readFile(cachePath);
    status = 200;
    fromCache = true;
  } catch {
    const response = await fetchOnceWithSingle5xxRetry(requestURL);
    status = response.status;
    body = Buffer.from(await response.arrayBuffer());
    if (status === 200) {
      await writeFile(cachePath, body);
    }
  }

  const bodyText = body.toString("utf8");
  const challengeDetected = /bm-verify|triggerInterstitialChallenge|access denied/i.test(bodyText);
  const responseHash = createHash("sha256").update(body).digest("hex");
  let responseType = status === 403 || challengeDetected ? "blocked" : "parse_error";
  let measureGuidePresent = false;
  let sizeGuidePresent = false;
  let rawMeasurementCodes = [];
  let units = [];
  let notes = fromCache ? "cached response reused" : "live public response";

  if (status === 404 || status === 410) {
    responseType = "unavailable";
  } else if (status === 200 && !challengeDetected) {
    try {
      const json = JSON.parse(bodyText);
      measureGuidePresent = hasGuide(json.measureGuideInfo);
      sizeGuidePresent = hasGuide(json.sizeGuideInfo);
      if (measureGuidePresent && sizeGuidePresent) responseType = "both";
      else if (measureGuidePresent) responseType = "garment_measure";
      else if (sizeGuidePresent) responseType = "body_only";
      else responseType = "empty";

      const measures = (json.measureGuideInfo?.sizes ?? []).flatMap((size) => size.measures ?? []);
      rawMeasurementCodes = [...new Set(measures.map((measure) => measure.tableTitleZone ?? measure.zoneId).filter(Boolean))].sort();
      units = [...new Set(measures.flatMap((measure) => measure.dimensions ?? []).map((dimension) => dimension.unitId).filter(Boolean))].sort();
    } catch (error) {
      notes = `${notes}; invalid JSON: ${error.message}`;
    }
  }

  return {
    sample_id: sample.sample_id,
    captured_at: capturedAt,
    product_url: sample.product_url,
    section: sample.section,
    family: sample.family,
    subfamily: sample.subfamily,
    product_name: sample.product_name,
    style_number: sample.style_number,
    catentry_id: sample.catentry_id,
    internal_product_id: productID,
    identity_resolution_source: sample.identity_resolution_source,
    http_status: status,
    challenge_detected: challengeDetected,
    response_type: responseType,
    measure_guide_present: measureGuidePresent,
    size_guide_present: sizeGuidePresent,
    raw_measurement_codes: rawMeasurementCodes.join("|"),
    unit: units.join("|"),
    measurement_basis_status: measureGuidePresent ? "PROBABLE" : "NOT_APPLICABLE",
    category_resolution_status: sample.section === "UNKNOWN" ? "UNKNOWN" : "STRUCTURED_SOURCE_HINT",
    notes,
    response_hash: responseHash,
    fixture_path: status === 200 ? path.relative(auditDirectory, cachePath) : ""
  };
}

async function fetchOnceWithSingle5xxRetry(url) {
  const options = {
    method: "GET",
    headers: {
      Accept: "application/json",
      "Accept-Language": "ko-KR,ko;q=0.9",
      "User-Agent": "FitMatch/1.0 (iPhone; iOS 18.0)"
    },
    redirect: "follow",
    signal: AbortSignal.timeout(15000)
  };
  let response = await fetch(url, options);
  if (response.status >= 500 && response.status <= 599) {
    response = await fetch(url, options);
  }
  return response;
}

function hasGuide(guide) {
  return Boolean(guide && Array.isArray(guide.sizes) && guide.sizes.length > 0);
}

function summarize(rows) {
  return rows.reduce((summary, row) => {
    summary.total += 1;
    summary[row.response_type] = (summary[row.response_type] ?? 0) + 1;
    return summary;
  }, { total: 0 });
}

function toCSV(rows) {
  const headers = Object.keys(rows[0] ?? {});
  const lines = [headers.join(",")];
  for (const row of rows) {
    lines.push(headers.map((header) => csvValue(row[header])).join(","));
  }
  return `${lines.join("\n")}\n`;
}

function csvValue(value) {
  const text = String(value ?? "");
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}
