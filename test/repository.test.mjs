import assert from "node:assert/strict";
import { access, readFile, readdir } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const root = fileURLToPath(new URL("..", import.meta.url));
const read = (path) => readFile(join(root, path), "utf8");
const readJson = async (path) => JSON.parse(await read(path));

async function walk(directory, suffix) {
  const entries = await readdir(directory, { withFileTypes: true });
  const results = [];
  for (const entry of entries) {
    if (entry.name === ".git" || entry.name === "node_modules") continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) results.push(...await walk(path, suffix));
    else if (path.endsWith(suffix)) results.push(path);
  }
  return results;
}

test("all repository JSON documents parse", async () => {
  const files = await walk(root, ".json");
  assert.ok(files.length >= 7);
  for (const file of files) JSON.parse(await readFile(file, "utf8"));
});

test("stage tracker uses an allowed state and identifies one active stage", async () => {
  const tracker = await readJson("docs/stages/stage-status.json");
  const schema = await readJson("docs/stages/stage-status.schema.json");
  const allowed = schema.properties.stages.items.properties.status.enum;
  const active = tracker.stages.filter((stage) => stage.id === tracker.activeStage);
  assert.equal(active.length, 1);
  assert.ok(allowed.includes(active[0].status));
  assert.equal(active[0].branch, "stage/02-local-hub-pairing");
  assert.equal(active[0].version, "0.2.0-rc.1");
});

test("local Markdown links resolve inside the repository", async () => {
  const markdownFiles = await walk(root, ".md");
  const missing = [];
  const linkPattern = /\[[^\]]*\]\(([^)]+)\)/g;
  for (const file of markdownFiles) {
    const content = await readFile(file, "utf8");
    for (const match of content.matchAll(linkPattern)) {
      const target = match[1].split("#", 1)[0];
      if (!target || /^(?:https?:|mailto:)/.test(target)) continue;
      const decoded = decodeURIComponent(target.replace(/^<|>$/g, ""));
      const resolved = resolve(dirname(file), decoded);
      if (!resolved.startsWith(root)) missing.push(`${file}: ${target} escapes repository`);
      else {
        try {
          await access(resolved, constants.F_OK);
        } catch {
          missing.push(`${file}: ${target}`);
        }
      }
    }
  }
  assert.deepEqual(missing, []);
});

test("CI is least-privilege, cancellable, pinned, and short-retention", async () => {
  const workflow = await read(".github/workflows/stage-00-quality.yml");
  assert.match(workflow, /permissions:\n  contents: read/);
  assert.match(workflow, /cancel-in-progress: true/);
  assert.match(workflow, /retention-days: 7/);
  const actionRefs = [...workflow.matchAll(/uses:\s+([^\s]+)/g)].map((match) => match[1]);
  assert.ok(actionRefs.length >= 3);
  for (const ref of actionRefs) assert.match(ref, /@[0-9a-f]{40}$/);
  assert.doesNotMatch(workflow, /pull_request_target/);
});

test("ignore rules cover generated output without hiding canonical packages", async () => {
  const ignore = await read(".gitignore");
  for (const pattern of ["DerivedData/", "*.xcarchive/", "**/bin/", "**/obj/", "node_modules/", ".artifacts/test-results/", "*.msi", "*.pkg"]) assert.ok(ignore.includes(pattern), pattern);
  assert.doesNotMatch(ignore, /^packages\/$/m);
});

test("README and license identify pre-release status and terms", async () => {
  const [readme, license] = await Promise.all([read("README.md"), read("LICENSE")]);
  assert.match(readme, /Stages 00 and 01 are merged\. Stage 02 is ready for developer testing/);
  assert.match(readme, /MIT License/);
  assert.match(license, /^MIT License/);
});
