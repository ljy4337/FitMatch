import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const output = join(root, "Docs/Research/OfficialTaxonomySnapshot-20260803");
const collectedAt = new Date().toISOString();
const hash = value => createHash("sha256").update(value).digest("hex");
const normalize = value => value.normalize("NFC").trim().replace(/\s+/g, " ");
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function fetchText(url) {
  const response = await fetch(url, { headers: { "user-agent": "Mozilla/5.0 FitMatch taxonomy audit" }, signal: AbortSignal.timeout(15000) });
  const text = await response.text();
  if (!response.ok) throw new Error(`${response.status} ${url}`);
  return { text, finalURL: response.url, responseHash: hash(text) };
}

function nextState(html) {
  const marker = "window.__PRELOADED_STATE__";
  const start = html.indexOf(marker);
  if (start < 0) throw new Error("UNIQLO preloaded taxonomy state not found");
  const equal = html.indexOf("=", start) + 1;
  const end = html.indexOf("</script>", equal);
  return JSON.parse(html.slice(equal, end).trim());
}

async function collectUniqlo() {
  const url = "https://www.uniqlo.com/kr/ko/men_navigation";
  const response = await fetchText(url);
  const taxonomy = nextState(response.text).taxonomies;
  const groups = ["genders", "classes", "categories", "subcategories"];
  const nodes = [];
  for (const group of groups) {
    for (const item of taxonomy[group]) {
      const parents = item.parents ?? [];
      const target = group === "genders" ? item.name : parents[0]?.name ?? "UNKNOWN";
      const pathParts = group === "genders" ? [item.name] : [...parents.slice(1).map(p => p.name), item.name];
      const parent = parents.at(-1);
      nodes.push({
        source: "uniqlo",
        external_category_id: String(item.id),
        parent_external_category_id: parent ? String(parent.id) : null,
        raw_name: item.name,
        raw_full_path: pathParts.join(" > "),
        normalized_full_path: pathParts.map(normalize).join(" > "),
        depth: group === "genders" ? 0 : parents.length,
        target,
        is_leaf: group === "subcategories",
        activity_status: "unknown",
        source_url: response.finalURL,
        endpoint_kind: "official_navigation_preloaded_taxonomies",
        collected_at: collectedAt,
        source_evidence: { group, key: item.key ?? item.genderKey ?? null, parent_count: parents.length },
        raw_response_hash: response.responseHash
      });
    }
  }
  return { nodes, raw: { url: response.finalURL, hash: response.responseHash, counts: Object.fromEntries(groups.map(g => [g, taxonomy[g].length])) } };
}

function musinsaPage(html) {
  const script = html.match(/<script id="__NEXT_DATA__" type="application\/json">(.*?)<\/script>/s);
  if (!script) return null;
  const data = JSON.parse(script[1]);
  const meta = data?.props?.pageProps?.meta?.data;
  if (!meta?.categoryCode) return null;
  const entries = [...html.matchAll(/data-category-id="([0-9]+)"[^>]*data-category-name="([^"]+)"/g)]
    .map(match => ({ id: match[1], path: match[2].split("|").map(normalize) }));
  const countMatch = html.match(/>([0-9][0-9,]*)<!-- -->개<\/span>/);
  const productIds = [...new Set([...html.matchAll(/data-item-id="([0-9]+)"/g)].map(match => match[1]))].slice(0, 15);
  return { meta, entries: [...new Map(entries.map(e => [e.id, e])).values()], productCount: countMatch ? Number(countMatch[1].replaceAll(",", "")) : null, productIds };
}

async function collectMusinsa() {
  const pages = new Map();
  const roots = [];
  const failures = [];
  const candidates = Array.from({ length: 200 }, (_, i) => String(i).padStart(3, "0"));
  for (let offset = 0; offset < candidates.length; offset += 10) {
    await Promise.all(candidates.slice(offset, offset + 10).map(async code => {
      const url = `https://www.musinsa.com/category/${code}`;
      try {
        const response = await fetchText(url);
        const parsed = musinsaPage(response.text);
        if (parsed?.meta?.categoryCode === code) {
          roots.push(code);
          pages.set(code, { ...response, parsed });
        }
      } catch (error) {
        failures.push({ code, url, error: String(error) });
      }
    }));
    await sleep(80);
  }
  const queue = [...roots];
  const queued = new Set(queue);
  while (queue.length) {
    const parents = queue.splice(0, 10);
    const children = parents.flatMap(code => pages.get(code)?.parsed.entries.filter(e => e.id !== code) ?? [])
      .filter(child => !pages.has(child.id) && !queued.has(child.id));
    children.forEach(child => queued.add(child.id));
    for (let offset = 0; offset < children.length; offset += 10) {
      await Promise.all(children.slice(offset, offset + 10).map(async child => {
        const url = `https://www.musinsa.com/category/${child.id}`;
        try {
          const response = await fetchText(url);
          const parsed = musinsaPage(response.text);
          pages.set(child.id, { ...response, parsed: parsed ?? { meta: { categoryCode: child.id, categoryTitle: child.path.at(-1) }, entries: [child] } });
          queue.push(child.id);
        } catch (error) {
          failures.push({ code: child.id, url, error: String(error) });
        }
      }));
      await sleep(80);
    }
  }
  const childIds = new Set();
  for (const page of pages.values()) for (const item of page.parsed.entries) if (item.id !== page.parsed.meta.categoryCode) childIds.add(item.id);
  const nodes = [...pages.entries()].map(([id, page]) => {
    const own = page.parsed.entries.find(e => e.id === id);
    const renderedPath = own?.path ?? [page.parsed.meta.categoryTitle];
    const path = renderedPath.at(-1) === "전체" ? renderedPath.slice(0, -1) : renderedPath;
    const parentId = id.length > 3 ? id.slice(0, -3) : null;
    const children = page.parsed.entries.filter(e => e.id !== id && e.id.startsWith(id));
    return {
      source: "musinsa",
      external_category_id: id,
      parent_external_category_id: parentId,
      raw_name: path.at(-1) ?? page.parsed.meta.categoryTitle,
      raw_full_path: path.join(" > "),
      normalized_full_path: path.map(normalize).join(" > "),
      depth: Math.max(0, id.length / 3 - 1),
      target: id.startsWith("106") ? "KIDS" : "UNKNOWN",
      is_leaf: children.length === 0,
      activity_status: "unknown",
      source_url: page.finalURL,
      endpoint_kind: "official_category_next_page",
      collected_at: collectedAt,
      source_evidence: { root_probe_range: "000-199", rendered_child_count: children.length, product_count: page.parsed.productCount ?? null, sample_product_ids: page.parsed.productIds ?? [] },
      raw_response_hash: page.responseHash
    };
  }).sort((a, b) => a.external_category_id.localeCompare(b.external_category_id));
  return { nodes, raw: { roots: roots.sort(), pages: pages.size, failures } };
}

function extractSeed(path) {
  const text = awaitableRead(path);
  return text;
}

function parseSeed(text) {
  const marker = "$fitmatch_source_categories$";
  const start = text.indexOf(marker) + marker.length;
  const end = text.indexOf(marker, start);
  return JSON.parse(text.slice(start, end));
}

let awaitableRead = () => { throw new Error("not initialized"); };

function integrity(nodes) {
  const ids = new Map();
  const paths = new Map();
  for (const node of nodes) {
    (ids.get(node.external_category_id) ?? ids.set(node.external_category_id, []).get(node.external_category_id)).push(node);
    const key = `${node.target}|${node.normalized_full_path}`;
    (paths.get(key) ?? paths.set(key, []).get(key)).push(node);
  }
  const identity = new Set(nodes.map(n => `${n.target}|${n.external_category_id}`));
  const byId = new Map(nodes.map(n => [n.external_category_id, n]));
  let cycles = 0;
  for (const node of nodes) {
    const seen = new Set([node.external_category_id]);
    let parent = node.parent_external_category_id;
    while (parent) {
      if (seen.has(parent)) { cycles += 1; break; }
      seen.add(parent);
      parent = byId.get(parent)?.parent_external_category_id ?? null;
    }
  }
  return {
    total_nodes: nodes.length,
    leaf_nodes: nodes.filter(n => n.is_leaf).length,
    by_target: Object.fromEntries([...Map.groupBy(nodes, n => n.target)].map(([k, v]) => [k, v.length])),
    duplicate_id_groups: [...ids.values()].filter(v => new Set(v.map(n => `${n.target}|${n.raw_full_path}`)).size < v.length).length,
    id_path_conflicts: [...ids.values()].filter(v => new Set(v.map(n => n.raw_full_path)).size > 1).length,
    duplicate_path_rows: [...paths.values()].reduce((sum, v) => sum + Math.max(0, v.length - 1), 0),
    path_id_conflicts: [...paths.values()].filter(v => new Set(v.map(n => n.external_category_id)).size > 1).length,
    target_conflict_ids: [...ids.values()].filter(v => new Set(v.map(n => n.target)).size > 1).length,
    orphan_parents: nodes.filter(n => n.parent_external_category_id && !identity.has(`${n.target}|${n.parent_external_category_id}`) && !nodes.some(p => p.external_category_id === n.parent_external_category_id)).length,
    cycles,
    depth_errors: nodes.filter(n => n.depth < 0 || !Number.isInteger(n.depth)).length,
    parent_child_depth_errors: nodes.filter(n => n.parent_external_category_id && byId.has(n.parent_external_category_id) && byId.get(n.parent_external_category_id).depth + 1 !== n.depth).length,
    activity_unknown: nodes.filter(n => n.activity_status === "unknown").length
  };
}

function compare(snapshot, db) {
  const dbByTargetId = new Map(db.map(n => [`${n.audience ?? "UNKNOWN"}|${n.external_category_id}`, n]));
  const dbById = Map.groupBy(db, n => n.external_category_id);
  const dbByTargetPath = new Map(db.map(n => [`${n.audience ?? "UNKNOWN"}|${normalize(n.original_path)}`, n]));
  const dbByPath = Map.groupBy(db, n => normalize(n.original_path));
  const matchedDb = new Set();
  const rows = snapshot.map(node => {
    let match = dbByTargetId.get(`${node.target}|${node.external_category_id}`);
    let method = match ? "id_target" : null;
    if (!match && dbById.get(node.external_category_id)?.length === 1) { match = dbById.get(node.external_category_id)[0]; method = "id"; }
    if (!match) { match = dbByTargetPath.get(`${node.target}|${node.normalized_full_path}`); if (match) method = "path_target"; }
    if (!match && dbByPath.get(node.normalized_full_path)?.length === 1) { match = dbByPath.get(node.normalized_full_path)[0]; method = "path"; }
    if (match) matchedDb.add(`${match.source_code}|${match.audience ?? ""}|${match.external_category_id}|${match.original_path}`);
    return { ...node, match_method: method ?? "missing_in_db", db_external_category_id: match?.external_category_id ?? null, db_path: match?.original_path ?? null, db_target: match?.audience ?? null, path_changed: Boolean(match && normalize(match.original_path) !== node.normalized_full_path), target_changed: Boolean(match && (match.audience ?? "UNKNOWN") !== node.target) };
  });
  const dbOnly = db.filter(n => !matchedDb.has(`${n.source_code}|${n.audience ?? ""}|${n.external_category_id}|${n.original_path}`));
  return { rows, dbOnly, summary: { snapshot_total: snapshot.length, id_target: rows.filter(r => r.match_method === "id_target").length, id_only: rows.filter(r => r.match_method === "id").length, path_target: rows.filter(r => r.match_method === "path_target").length, path_only: rows.filter(r => r.match_method === "path").length, missing_in_db: rows.filter(r => r.match_method === "missing_in_db").length, db_not_in_snapshot: dbOnly.length, id_path_differences: rows.filter(r => r.path_changed && r.match_method.startsWith("id")).length, target_differences: rows.filter(r => r.target_changed).length } };
}

function csv(rows, fields) {
  const quote = value => `"${String(value ?? "").replaceAll('"', '""')}"`;
  return [fields.join(","), ...rows.map(row => fields.map(field => quote(typeof row[field] === "object" ? JSON.stringify(row[field]) : row[field])).join(","))].join("\n") + "\n";
}

await mkdir(output, { recursive: true });
awaitableRead = path => readFile(path, "utf8");
const [uniqlo, musinsa, musinsaSeedText, uniqloSeedText] = await Promise.all([
  collectUniqlo(), collectMusinsa(),
  readFile(join(root, "fitmatch_supabase_seed_musinsa_categories.sql"), "utf8"),
  readFile(join(root, "fitmatch_supabase_seed_uniqlo_categories.sql"), "utf8")
]);
const dbRows = [...parseSeed(musinsaSeedText), ...parseSeed(uniqloSeedText)];
const musinsaDb = dbRows.filter(r => r.source_code === "musinsa");
const uniqloDb = dbRows.filter(r => r.source_code === "uniqlo");
const musinsaComparison = compare(musinsa.nodes, musinsaDb);
const uniqloComparison = compare(uniqlo.nodes, uniqloDb);
const fields = ["source","external_category_id","parent_external_category_id","raw_name","raw_full_path","normalized_full_path","depth","target","is_leaf","activity_status","source_url","endpoint_kind","collected_at","source_evidence","raw_response_hash"];
await writeFile(join(output, "musinsa-official-taxonomy-snapshot.json"), JSON.stringify({ metadata: musinsa.raw, integrity: integrity(musinsa.nodes), nodes: musinsa.nodes }, null, 2) + "\n");
await writeFile(join(output, "uniqlo-official-taxonomy-snapshot.json"), JSON.stringify({ metadata: uniqlo.raw, integrity: integrity(uniqlo.nodes), nodes: uniqlo.nodes }, null, 2) + "\n");
await writeFile(join(output, "musinsa-official-taxonomy-snapshot.csv"), csv(musinsa.nodes, fields));
await writeFile(join(output, "uniqlo-official-taxonomy-snapshot.csv"), csv(uniqlo.nodes, fields));
const coverage = { generated_at: collectedAt, musinsa: musinsaComparison.summary, uniqlo: uniqloComparison.summary };
await writeFile(join(output, "db-coverage-summary.json"), JSON.stringify(coverage, null, 2) + "\n");
const coverageRows = [...musinsaComparison.rows, ...uniqloComparison.rows];
await writeFile(join(output, "db-coverage-comparison.csv"), csv(coverageRows, [...fields, "match_method","db_external_category_id","db_path","db_target","path_changed","target_changed"]));
await writeFile(join(output, "missing-categories.csv"), csv(coverageRows.filter(r => r.match_method === "missing_in_db").map(r => ({ ...r, semantic_candidate: "unreviewed", required_product_samples: r.is_leaf ? 5 : 0, auto_decision: false, recommended_status: r.is_leaf ? "review_required" : "not_applicable_intermediate", current_app_support: "unreviewed", new_taxonomy_candidate: "unreviewed" })), [...fields, "semantic_candidate","required_product_samples","auto_decision","recommended_status","current_app_support","new_taxonomy_candidate"]));
await writeFile(join(output, "db-only-categories.csv"), csv([...musinsaComparison.dbOnly, ...uniqloComparison.dbOnly], ["source_code","external_category_id","parent_external_category_id","name","original_path","audience","depth","app_category","app_detail_category","metadata"]));
await writeFile(join(output, "identity-path-target-conflicts.csv"), csv(coverageRows.filter(r => r.path_changed || r.target_changed || ["path_target","path"].includes(r.match_method)), [...fields, "match_method","db_external_category_id","db_path","db_target","path_changed","target_changed"]));
console.log(JSON.stringify({ output, coverage, integrity: { musinsa: integrity(musinsa.nodes), uniqlo: integrity(uniqlo.nodes) }, failures: musinsa.raw.failures.length }, null, 2));
