import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

const [stage, decision, threatModel, masterPrompt] = await Promise.all([
  read("../docs/stages/stage-06a.md"),
  read("../docs/adr/0001-manual-mdm-login-window-feasibility.md"),
  read("../docs/architecture/threat-model.md"),
  read("../CODEX_MASTER_PROMPT.md"),
]);

test("Stage 06A records the local-account Login Window platform limit", () => {
  for (const document of [stage, decision]) {
    assert.match(document, /network accounts and mobile accounts/i);
    assert.match(document, /local child account/i);
    assert.match(document, /weekly schedule or automatic expiry/i);
  }
});

test("Stage 06A rejects unsafe broad local-login denial and cloud-only recovery", () => {
  assert.match(stage, /adult recovery administrator/i);
  assert.match(stage, /LocalUserLoginEnabled/i);
  assert.match(stage, /must not be deployed/i);
  assert.match(decision, /No MDM account/i);
  assert.match(decision, /No MDM account[\s\S]*configuration profile/i);
  assert.match(threatModel, /third-party MDM/i);
  assert.match(threatModel, /destructive API/i);
});

test("the roadmap amendment remains bounded and preserves the local-first core", () => {
  assert.match(masterPrompt, /STAGE-06A — Manual third-party MDM feasibility/i);
  assert.match(masterPrompt, /optional feasibility exception/i);
  assert.match(stage, /No Parent Controller or child-endpoint MDM integration/i);
  assert.match(stage, /No vendor account, APNs certificate, API key, or enrolled device/i);
});
