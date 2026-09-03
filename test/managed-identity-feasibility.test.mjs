import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

const [stage, decision, threatModel, privacy, capability, masterPrompt] = await Promise.all([
  read("../docs/stages/stage-06b.md"),
  read("../docs/adr/0002-managed-identity-scheduled-login-feasibility.md"),
  read("../docs/architecture/threat-model.md"),
  read("../PRIVACY.md"),
  read("../docs/architecture/capability-matrix.md"),
  read("../CODEX_MASTER_PROMPT.md"),
]);

test("Stage 06B distinguishes an online identity gate from an offline family schedule", () => {
  for (const document of [stage, decision]) {
    assert.match(document, /conditional go/i);
    assert.match(document, /no-go/i);
    assert.match(document, /OfflineGracePeriod|offline grace/i);
    assert.match(document, /weekly schedule/i);
    assert.match(document, /no weekday|no weekday or start\/end-time|no weekly time-window/i);
  }
  assert.match(decision, /parent controller remains the local policy authority/i);
});

test("Stage 06B preserves adult and FileVault recovery", () => {
  for (const document of [stage, decision]) {
    assert.match(document, /NonPlatformSSOAccounts/i);
    assert.match(document, /personal recovery key|PRK/i);
    assert.match(document, /Apple silicon/i);
    assert.match(document, /Intel/i);
  }
  assert.match(decision, /bypass-login-policy/);
  assert.match(threatModel, /managed identity/i);
  assert.match(threatModel, /adult recovery/i);
});

test("Stage 06B creates no external or installed state", () => {
  assert.match(stage, /No executable changed/i);
  assert.match(stage, /no account, enrollment, extension, profile, credential/i);
  assert.match(decision, /No MDM\/IdP account/i);
  assert.match(privacy, /Stage 06B/i);
  assert.match(capability, /Stage 06B/i);
  assert.match(masterPrompt, /STAGE-06B — Managed-identity feasibility/i);
  assert.match(masterPrompt, /Do not create an account, tenant, certificate, profile, enrollment, managed user, or product integration/i);
});

test("a physical managed-identity pilot remains separately gated", () => {
  assert.match(stage, /future pilot will require a new authorization/i);
  assert.match(decision, /Physical-pilot gates/i);
  assert.match(decision, /synthetic managed identity/i);
  assert.match(decision, /non-primary test Mac/i);
  assert.match(decision, /No installer is produced/i);
});
