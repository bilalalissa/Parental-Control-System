import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("..", import.meta.url));
const shellScript = fileURLToPath(new URL("../tools/cleanup.sh", import.meta.url));
const powershellScript = fileURLToPath(new URL("../tools/cleanup.ps1", import.meta.url));
const temporaryRoots = new Set();

test.after(async () => {
  await Promise.all([...temporaryRoots].map((path) => rm(path, { recursive: true, force: true })));
});

async function exists(path) {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function createTestTree() {
  const root = await mkdtemp(join(tmpdir(), "parental-control-cleanup-"));
  temporaryRoots.add(root);
  await writeFile(join(root, ".parental-control-cleanup-test-root"), "synthetic test root\n");
  await mkdir(join(root, "build"), { recursive: true });
  await writeFile(join(root, "build", "generated.txt"), "generated\n");
  await mkdir(join(root, "component", "obj"), { recursive: true });
  await writeFile(join(root, "component", "obj", "generated.txt"), "generated\n");
  await mkdir(join(root, "swift-component", ".build", "debug"), { recursive: true });
  await writeFile(join(root, "swift-component", ".build", "debug", "generated"), "generated\n");
  await mkdir(join(root, ".artifacts", "release-candidate"), { recursive: true });
  await writeFile(join(root, ".artifacts", "release-candidate", "keep.txt"), "keep\n");
  await writeFile(join(root, "source.txt"), "keep\n");
  return root;
}

test("POSIX cleanup is dry-run by default and preserves retained files", async () => {
  const root = await createTestTree();
  const result = spawnSync("bash", [shellScript], {
    cwd: repositoryRoot,
    env: { ...process.env, PARENTAL_CONTROL_CLEANUP_TEST_ROOT: root },
    encoding: "utf8"
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Dry run only/);
  assert.equal(await exists(join(root, "build", "generated.txt")), true);
  assert.equal(await exists(join(root, "source.txt")), true);
});

test("POSIX cleanup applies only to allowlisted generated paths", async () => {
  const root = await createTestTree();
  const outside = await mkdtemp(join(tmpdir(), "parental-control-outside-"));
  temporaryRoots.add(outside);
  const outsideFile = join(outside, "outside.txt");
  await writeFile(outsideFile, "outside\n");
  await symlink(outside, join(root, "dist"));

  const result = spawnSync("bash", [shellScript, "--apply"], {
    cwd: repositoryRoot,
    env: { ...process.env, PARENTAL_CONTROL_CLEANUP_TEST_ROOT: root },
    encoding: "utf8"
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(await exists(join(root, "build")), false);
  assert.equal(await exists(join(root, "component", "obj")), false);
  assert.equal(await exists(join(root, "swift-component", ".build")), false);
  assert.equal(await exists(join(root, "dist")), false);
  assert.equal(await exists(join(root, "source.txt")), true);
  assert.equal(await exists(join(root, ".artifacts", "release-candidate", "keep.txt")), true);
  assert.equal((await readFile(outsideFile, "utf8")).trim(), "outside");
});

test("cleanup scripts encode explicit apply gates and repository-root guards", async () => {
  const shell = await readFile(shellScript, "utf8");
  const powershell = await readFile(powershellScript, "utf8");
  assert.match(shell, /--apply/);
  assert.match(shell, /Refusing cleanup outside/);
  assert.match(powershell, /\[switch\]\$Apply/);
  assert.match(powershell, /Refusing cleanup outside/);
  assert.doesNotMatch(shell, /git clean/);
  assert.doesNotMatch(powershell, /git clean/);
});

test("Windows cleanup is dry-run first and scoped when PowerShell is available", { skip: process.platform !== "win32" }, async () => {
  const root = await createTestTree();
  const dryRun = spawnSync("powershell.exe", ["-NoProfile", "-File", powershellScript, "-Root", root], { encoding: "utf8" });
  assert.equal(dryRun.status, 0, dryRun.stderr);
  assert.match(dryRun.stdout, /Dry run only/);
  assert.equal(await exists(join(root, "build", "generated.txt")), true);
  const apply = spawnSync("powershell.exe", ["-NoProfile", "-File", powershellScript, "-Root", root, "-Apply"], { encoding: "utf8" });
  assert.equal(apply.status, 0, apply.stderr);
  assert.equal(await exists(join(root, "build")), false);
  assert.equal(await exists(join(root, "source.txt")), true);
  assert.equal(await exists(join(root, ".artifacts", "release-candidate", "keep.txt")), true);
});
