import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const directory = join(root, "Docs/Research/CanonicalTaxonomyAudit-20260814");
const manifest = JSON.parse(await readFile(join(directory, "manifest.json"), "utf8"));
const audit = JSON.parse(await readFile(join(directory, "audit-results.json"), "utf8"));
const fail = (message) => { throw new Error(message); };
const sha256 = (data) => createHash("sha256").update(data).digest("hex");

if (audit.rows.length !== 4008) fail(`Expected 4008 rows, got ${audit.rows.length}`);
if (audit.rows.filter((row) => row.sourceIdentity).length !== 3426) fail("Runtime mapping coverage mismatch");
if (new Set(audit.rows.map((row) => `${row.source}|${row.externalCategoryID}|${row.target}|${row.path}`)).size !== 4008) fail("Duplicate source rows");
if (Object.values(audit.summary.proposedActions).reduce((sum, count) => sum + count, 0) !== 4008) fail("Action totals mismatch");
if (!Object.values(audit.summary.structuralChecks).every(Boolean)) fail("Structural check failed");
for (const [name, expected] of Object.entries(manifest.files)) {
  const body = await readFile(join(directory, name));
  if (sha256(body) !== expected) fail(`Checksum mismatch: ${name}`);
}
console.log(JSON.stringify({ passed: true, rows: audit.rows.length, runtimeMappings: 3426, highRisk: audit.summary.highRiskCount, files: Object.keys(manifest.files).length }));
