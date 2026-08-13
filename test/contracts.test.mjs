import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const readJson = async (path) => JSON.parse(await readFile(new URL(path, import.meta.url), "utf8"));

const protocolSchema = await readJson("../packages/protocol/message.schema.json");
const policySchema = await readJson("../packages/policy-engine-spec/policy.schema.json");
const validMessages = await readJson("../packages/test-fixtures/protocol-valid.json");
const invalidMessages = await readJson("../packages/test-fixtures/protocol-invalid.json");
const policyFixture = await readJson("../packages/test-fixtures/policy-vectors.json");

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const identifier = /^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$/;
const localTime = /^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/;
const restrictiveActions = new Set(["warningOnly", "lock", "logoff", "restart", "shutdown"]);

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validDateTime(value) {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function validateProtocol(message) {
  const errors = [];
  const required = protocolSchema.required;
  const allowed = new Set(Object.keys(protocolSchema.properties));
  for (const field of required) if (!(field in message)) errors.push(`missing ${field}`);
  for (const field of Object.keys(message)) if (!allowed.has(field)) errors.push(`unknown ${field}`);
  if (!uuid.test(message.id ?? "")) errors.push("invalid id");
  if (message.protocolVersion !== protocolSchema.properties.protocolVersion.const) errors.push("unsupported protocolVersion");
  if (!identifier.test(message.deviceId ?? "")) errors.push("invalid deviceId");
  if (!validDateTime(message.sentAt)) errors.push("invalid sentAt");
  if (message.expiresAt !== undefined && !validDateTime(message.expiresAt)) errors.push("invalid expiresAt");
  if (validDateTime(message.sentAt) && validDateTime(message.expiresAt) && Date.parse(message.expiresAt) <= Date.parse(message.sentAt)) errors.push("invalid expiry order");
  if (!Number.isSafeInteger(message.sequence) || message.sequence < 0) errors.push("invalid sequence");
  if (!protocolSchema.properties.type.enum.includes(message.type)) errors.push("unsupported type");
  if (!isObject(message.payload) || Object.keys(message.payload ?? {}).length > 64) errors.push("invalid payload");
  if (!isObject(message.auth)) {
    errors.push("invalid auth");
  } else {
    const authKeys = Object.keys(message.auth);
    if (authKeys.some((key) => !["algorithm", "keyId", "signature"].includes(key))) errors.push("unknown auth field");
    if (message.auth.algorithm !== "Ed25519") errors.push("invalid auth algorithm");
    if (!identifier.test(message.auth.keyId ?? "")) errors.push("invalid auth keyId");
    if (typeof message.auth.signature !== "string" || message.auth.signature.length < 16) errors.push("invalid auth signature");
  }
  return errors;
}

function validatePolicy(policy) {
  const errors = [];
  const required = policySchema.required;
  const allowed = new Set(Object.keys(policySchema.properties));
  for (const field of required) if (!(field in policy)) errors.push(`missing ${field}`);
  for (const field of Object.keys(policy)) if (!allowed.has(field)) errors.push(`unknown ${field}`);
  if (!uuid.test(policy.policyId ?? "")) errors.push("invalid policyId");
  if (!Number.isSafeInteger(policy.version) || policy.version < 1) errors.push("invalid version");
  if (!identifier.test(policy.deviceId ?? "")) errors.push("invalid deviceId");
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: policy.timezone }).format(new Date());
  } catch {
    errors.push("invalid timezone");
  }
  if (!validDateTime(policy.effectiveAt)) errors.push("invalid effectiveAt");
  if (policy.expiresAt !== undefined && (!validDateTime(policy.expiresAt) || Date.parse(policy.expiresAt) <= Date.parse(policy.effectiveAt))) errors.push("invalid expiresAt");
  if (!restrictiveActions.has(policy.defaultAction)) errors.push("invalid defaultAction");
  if (!Array.isArray(policy.warningOffsetsMinutes) || policy.warningOffsetsMinutes.length > 8 || policy.warningOffsetsMinutes.some((n) => !Number.isInteger(n) || n < 1 || n > 1440) || new Set(policy.warningOffsetsMinutes).size !== policy.warningOffsetsMinutes.length) errors.push("invalid warning offsets");
  if (!Number.isInteger(policy.gracePeriodSeconds) || policy.gracePeriodSeconds < 0 || policy.gracePeriodSeconds > 900) errors.push("invalid grace period");
  if (!Array.isArray(policy.weeklyAllowed) || policy.weeklyAllowed.length > 64) errors.push("invalid weeklyAllowed");
  for (const window of policy.weeklyAllowed ?? []) {
    if (!policySchema.$defs.day.enum.includes(window.day) || !localTime.test(window.start ?? "") || !localTime.test(window.end ?? "") || window.start === window.end) errors.push("invalid weekly window");
  }
  for (const interval of policy.blockedIntervals ?? []) {
    if (!uuid.test(interval.id ?? "") || !validDateTime(interval.start) || !validDateTime(interval.end) || Date.parse(interval.end) <= Date.parse(interval.start) || !restrictiveActions.has(interval.action) || !interval.reason) errors.push("invalid blocked interval");
  }
  for (const exception of policy.exceptions ?? []) {
    if (!uuid.test(exception.id ?? "") || !validDateTime(exception.start) || !validDateTime(exception.end) || Date.parse(exception.end) <= Date.parse(exception.start) || !["allow", "block"].includes(exception.decision) || (exception.decision === "block" && !restrictiveActions.has(exception.action)) || !exception.reason) errors.push("invalid exception");
  }
  if (!Number.isInteger(policy.dailyQuotaMinutes) || policy.dailyQuotaMinutes < 0 || policy.dailyQuotaMinutes > 1440) errors.push("invalid daily quota");
  if (!Number.isInteger(policy.bonusMinutes) || policy.bonusMinutes < 0 || policy.bonusMinutes > 1440) errors.push("invalid bonus");
  if (typeof policy.childExplanation !== "string" || policy.childExplanation.length < 1 || policy.childExplanation.length > 500) errors.push("invalid child explanation");
  if (!isObject(policy.signature) || policy.signature.algorithm !== "Ed25519" || !identifier.test(policy.signature.keyId ?? "") || typeof policy.signature.value !== "string" || policy.signature.value.length < 16) errors.push("invalid signature metadata");
  return errors;
}

const dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function localParts(at, timeZone) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "long",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23"
  });
  const parts = Object.fromEntries(formatter.formatToParts(new Date(at)).map(({ type, value }) => [type, value]));
  return { day: parts.weekday, minutes: Number(parts.hour) * 60 + Number(parts.minute) };
}

function minutes(value) {
  const [hour, minute] = value.split(":").map(Number);
  return hour * 60 + minute;
}

function inRecurringWindow(policy, at) {
  const local = localParts(at, policy.timezone);
  const currentIndex = dayNames.indexOf(local.day);
  const previousDay = dayNames[(currentIndex + 6) % 7];
  return policy.weeklyAllowed.some((window) => {
    const start = minutes(window.start);
    const end = minutes(window.end);
    if (start < end) return window.day === local.day && local.minutes >= start && local.minutes < end;
    return (window.day === local.day && local.minutes >= start) || (window.day === previousDay && local.minutes < end);
  });
}

function inAbsoluteRule(rule, at) {
  const instant = Date.parse(at);
  return instant >= Date.parse(rule.start) && instant < Date.parse(rule.end);
}

function evaluate(policy, input) {
  if (input.adultOverrideActive) return { decision: "allow", source: "adultOverride" };
  if (input.immediateAction) return { decision: "block", action: input.immediateAction, source: "immediateCommand" };
  const exception = policy.exceptions.find((rule) => inAbsoluteRule(rule, input.at));
  if (exception) return exception.decision === "allow" ? { decision: "allow", source: "exception" } : { decision: "block", action: exception.action ?? policy.defaultAction, source: "exception" };
  const blocked = policy.blockedIntervals.find((rule) => inAbsoluteRule(rule, input.at));
  if (blocked) return { decision: "block", action: blocked.action, source: "blockedInterval" };
  if (input.activeUseMinutes >= policy.dailyQuotaMinutes + policy.bonusMinutes) return { decision: "block", action: policy.defaultAction, source: "dailyQuota" };
  if (inRecurringWindow(policy, input.at)) return { decision: "allow", source: "weeklyWindow" };
  return { decision: "block", action: policy.defaultAction, source: "default" };
}

test("canonical schemas use JSON Schema 2020-12 and reject extra root fields", () => {
  for (const schema of [protocolSchema, policySchema]) {
    assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
    assert.equal(schema.type, "object");
    assert.equal(schema.additionalProperties, false);
  }
  assert.ok(protocolSchema.properties.type.enum.includes("action.unlock-temporary"));
  for (const prohibited of ["shell", "powershell", "applescript", "process.launch", "file.read"]) {
    assert.ok(!protocolSchema.properties.type.enum.includes(prohibited));
  }
});

test("all synthetic valid protocol messages satisfy the canonical contract", () => {
  assert.ok(validMessages.length > 0);
  for (const message of validMessages) assert.deepEqual(validateProtocol(message), [], message.id);
});

test("all synthetic invalid protocol messages fail closed", () => {
  assert.ok(invalidMessages.length > 0);
  for (const fixture of invalidMessages) assert.ok(validateProtocol(fixture.message).length > 0, fixture.reason);
});

test("policy fixture satisfies the canonical contract", () => {
  assert.deepEqual(validatePolicy(policyFixture.policy), []);
});

test("policy golden vectors implement the documented precedence", async (t) => {
  for (const vector of policyFixture.vectors) {
    const policy = { ...policyFixture.policy, ...vector.policyPatch };
    await t.test(vector.name, () => assert.deepEqual(evaluate(policy, vector.input), vector.expected));
  }
});

test("fixtures contain synthetic identifiers only", () => {
  const fixtureText = JSON.stringify({ validMessages, invalidMessages, policyFixture });
  assert.match(fixtureText, /synthetic-/);
  assert.doesNotMatch(fixtureText, /BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|@(?:gmail|outlook|icloud)\./i);
});
