import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

const [stage, decision, threatModel, privacy, security, capability, masterPrompt, tracker] = await Promise.all([
  read("../docs/stages/stage-06c.md"),
  read("../docs/adr/0003-router-level-wan-pause-feasibility.md"),
  read("../docs/architecture/threat-model.md"),
  read("../PRIVACY.md"),
  read("../SECURITY.md"),
  read("../docs/architecture/capability-matrix.md"),
  read("../CODEX_MASTER_PROMPT.md"),
  read("../docs/stages/stage-status.json"),
]);

test("Stage 06C rejects unsupported ARRIS automation without overclaiming", () => {
  for (const document of [stage, decision]) {
    assert.match(document, /ARRIS NVG448BQ/);
    assert.match(document, /no-go/i);
    assert.match(document, /manual-only/i);
    assert.match(document, /no documented least-privilege (?:automation )?API/i);
    assert.match(document, /CGI\/HTML|HTML\/CGI/i);
  }
  assert.match(decision, /No credential was entered/i);
  assert.match(decision, /no router state was changed/i);
  assert.match(capability, /must not expose a router-pause capability/i);
});

test("future WAN pause contract preserves local control and expires independently", () => {
  for (const document of [stage, decision, security]) {
    assert.match(document, /router-owned/i);
    assert.match(document, /IPv4/);
    assert.match(document, /IPv6/);
    assert.match(document, /Wi-Fi/);
    assert.match(document, /Ethernet/);
    assert.match(document, /authenticated local (?:Parent Controller|controller)/i);
  }
  assert.match(decision, /maximum-eight-hour lease/i);
  assert.match(decision, /controller quits, sleeps, changes interface, or loses power/i);
  assert.match(decision, /Unknown—verify router/);
  assert.match(threatModel, /Stale router deny rule/);
  assert.match(threatModel, /Partial IP-family enforcement/);
});

test("Stage 06C remains content-minimal and credential-safe", () => {
  for (const document of [stage, decision, privacy, security]) {
    assert.match(document, /network-content inspection/i);
    assert.match(document, /Keychain/i);
  }
  assert.match(decision, /Do not store packet data, DNS history, URL\/domain history, or unrelated client inventory/i);
  assert.match(privacy, /creates no router login, credential, configuration, firewall rule/i);
  assert.match(security, /will not store its broad Device Access Code/i);
  assert.match(masterPrompt, /Do not submit router credentials/i);
});

test("Stage 06C is a source dossier and later adapters remain separately gated", () => {
  const state = JSON.parse(tracker);
  const stage06c = state.stages.find((candidate) => candidate.id === "STAGE-06C");
  assert.equal(stage06c.version, "0.6.3-rc.1");
  assert.equal(stage06c.status, "MERGED");
  assert.match(stage, /changes no executable or installed component/i);
  assert.match(decision, /do not produce an executable or installer/i);
  assert.match(decision, /MikroTik RouterOS/);
  assert.match(decision, /OpenWrt/);
  assert.match(decision, /separately gated/i);
});
