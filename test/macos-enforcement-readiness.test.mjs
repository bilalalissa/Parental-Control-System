import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

const [host, network, execution, checker, stage, decision, tracker] = await Promise.all([
  read("../agents/endpoint-macos/Enforcement/Entitlements/HostApp.entitlements"),
  read("../agents/endpoint-macos/Enforcement/Entitlements/NetworkFilter.entitlements"),
  read("../agents/endpoint-macos/Enforcement/Entitlements/ExecutionFilter.entitlements"),
  read("../script/check_stage06d_readiness.sh"),
  read("../docs/stages/stage-06d.md"),
  read("../docs/adr/0004-macos-enforcement-extension-readiness.md"),
  read("../docs/stages/stage-status.json"),
]);

test("Stage 06D entitlement templates request only their supported boundaries", () => {
  assert.match(host, /com\.apple\.developer\.system-extension\.install[\s\S]*<true\/>/);
  assert.match(network, /com\.apple\.developer\.networking\.networkextension[\s\S]*content-filter-provider-systemextension/);
  assert.match(execution, /com\.apple\.developer\.endpoint-security\.client[\s\S]*<true\/>/);

  const combined = `${host}\n${network}\n${execution}`;
  for (const forbidden of ["packet-tunnel-provider", "dns-proxy", "app-proxy-provider", "content-filter-provider-app-proxy"])
    assert.doesNotMatch(combined, new RegExp(forbidden));
});

test("readiness checker validates local identity, explicit profiles, capabilities, and Team alignment", () => {
  for (const identifier of [
    "com.bilalalissa.ParentalControlChild",
    "com.bilalalissa.ParentalControlNetworkFilter",
    "com.bilalalissa.ParentalControlExecutionFilter",
  ]) assert.match(checker, new RegExp(identifier.replaceAll(".", "\\.")));

  assert.match(checker, /security find-identity -v -p codesigning/);
  assert.match(checker, /security cms -D -i/);
  assert.match(checker, /application-identifier/);
  assert.match(checker, /com\.apple\.developer\.team-identifier/);
  assert.match(checker, /Team ID alignment/);
  assert.match(checker, /mktemp -d/);
  assert.match(checker, /STAGE-06D READINESS: BLOCKED/);
  assert.match(checker, /exit 2/);
  assert.doesNotMatch(checker, /cat\s+[^\n]*decoded/);
});

test("readiness checker help is dependency-free and documents all private profile inputs", () => {
  const checkerPath = fileURLToPath(new URL("../script/check_stage06d_readiness.sh", import.meta.url));
  const output = execFileSync("bash", [checkerPath, "--help"], {
    encoding: "utf8",
  });
  assert.match(output, /--host-profile PATH/);
  assert.match(output, /--network-profile PATH/);
  assert.match(output, /--execution-profile PATH/);
  assert.match(output, /never copied/);
});

test("Stage 06D amendment separates browser tests from deferred system-extension gates", () => {
  const state = JSON.parse(tracker);
  const active = state.stages.find((candidate) => candidate.id === state.activeStage);
  assert.equal(active.id, "STAGE-06D");
  assert.equal(active.version, "0.6.4-rc.1");
  assert.ok(["IMPLEMENTING", "READY_FOR_DEVELOPER_TEST", "BLOCKED"].includes(active.status));
  assert.match(stage, /MANAGED BROWSER WEBSITE BLOCKING/);
  assert.match(stage, /Firefox.*unsigned|unsigned.*Firefox/i);
  assert.match(stage, /automatic updates.*require/i);
  assert.match(stage, /Safari.*unsupported|Excluded: Safari/i);
  assert.match(decision, /Developer ID/);
  assert.match(decision, /same Team ID/i);
  assert.match(decision, /physical acceptance matrix/i);
  assert.match(decision, /no (?:application UI may expose these controls as operational|operational control)/i);
});

test("Stage 06D contract is content-minimal, bounded, and recoverable", () => {
  assert.match(decision, /stable code identity, not display name or mutable filesystem path/i);
  assert.match(decision, /IDNA-normalized/i);
  assert.match(decision, /does not perform substring matching/i);
  assert.match(decision, /maximum-eight-hour|capped at eight hours/i);
  assert.match(decision, /authenticated local Parent Controller/i);
  assert.match(decision, /DHCP/);
  assert.match(decision, /DNS/);
  assert.match(decision, /time traffic/);
  assert.match(decision, /fails open/i);
  assert.match(decision, /no URLs, paths, queries, DNS history, packets, payloads, browsing history/i);
});
