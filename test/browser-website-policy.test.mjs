import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const context = vm.createContext({});
vm.runInContext(await readFile(new URL('../browser-extensions/webextension/website-policy.js', import.meta.url), 'utf8'), context);
const policy = context.WebsitePolicy;
const plain = (value) => JSON.parse(JSON.stringify(value));
function browser() {
  let rules = [], storage = {}, writes = 0;
  return {
    storage: { local: { get: async () => storage, set: async (value) => { storage = { ...storage, ...plain(value) }; } } },
    declarativeNetRequest: {
      getDynamicRules: async () => rules,
      updateDynamicRules: async ({ addRules }) => { rules = plain(addRules); writes++; }
    },
    rules: () => rules, writes: () => writes
  };
}
test('domain-only rules cover navigations and frames, without observing requests', () => {
  const rules = plain(policy.rulesFor(policy.validate({ version: 1, domains: ['youtube.com', 'example.org'] })));
  assert.deepEqual(rules[0].condition, { requestDomains: ['example.org', 'youtube.com'], resourceTypes: ['main_frame', 'sub_frame'] });
  assert.equal(rules[0].action.type, 'block');
});
test('rejects URL paths, queries, IPs, wildcards, local names, invalid labels and oversized input', () => {
  for (const domain of ['https://example.com', 'example.com/path', 'example.com?q=a', '*.example.com',
    '127.0.0.1', '::1', 'a.local', 'a.localhost', '-a.com', 'a..com', 'EXAMPLE.COM', 'a.com.', 'x'.repeat(64)+'.com']) {
    assert.throws(() => policy.validate({ version: 1, domains: [domain] }));
  }
  assert.throws(() => policy.validate({ version: 1, domains: Array(257).fill('example.com') }));
  assert.throws(() => policy.validate({ version: Number.MAX_SAFE_INTEGER + 1, domains: [] }));
});
test('policy apply reads rules back before acknowledging and is idempotent', async () => {
  const api = browser(), p = { version: 2, domains: ['example.com'] };
  assert.equal(await policy.apply(api, p), 2);
  await policy.apply(api, p);
  assert.equal(api.writes(), 1);
});
test('rejects rollback and same-version mutation, preserving last valid rules', async () => {
  const api = browser();
  await policy.apply(api, { version: 4, domains: ['example.com'] });
  await assert.rejects(policy.apply(api, { version: 3, domains: [] }));
  await assert.rejects(policy.apply(api, { version: 4, domains: [] }));
  assert.equal(api.rules().length, 1);
});
test('explicit newer empty policy removes restrictions', async () => {
  const api = browser();
  await policy.apply(api, { version: 1, domains: ['example.com'] });
  await policy.apply(api, { version: 2, domains: [] });
  assert.equal(api.rules().length, 0);
});
test('failed browser update never stores or acknowledges a new version', async () => {
  const api = browser();
  await policy.apply(api, { version: 1, domains: ['example.com'] });
  api.declarativeNetRequest.updateDynamicRules = async () => { throw Error('denied'); };
  await assert.rejects(policy.apply(api, { version: 2, domains: [] }));
  assert.equal((await api.storage.local.get()).websitePolicy.version, 1);
});
test('readback mismatch does not acknowledge success', async () => {
  const api = browser();
  api.declarativeNetRequest.updateDynamicRules = async () => {};
  await assert.rejects(policy.apply(api, { version: 1, domains: ['example.com'] }));
  assert.equal((await api.storage.local.get()).websitePolicy, undefined);
});
test('browser permissions exclude content/request inspection and private sessions', async () => {
  const manifest = JSON.parse(await readFile(new URL('../browser-extensions/webextension/manifest.json', import.meta.url), 'utf8'));
  assert.equal(manifest.incognito, 'not_allowed');
  assert.ok(manifest.permissions.includes('declarativeNetRequest'));
  for (const forbidden of ['webRequest', 'webRequestBlocking', 'cookies', 'history', 'scripting', 'debugger']) {
    assert.ok(!manifest.permissions.includes(forbidden));
  }
  assert.equal(manifest.content_scripts, undefined);
});

test('Firefox packaging generates a stable explicit identity without duplicating policy source', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'parental-browser-test-'));
  try {
    const output = join(directory, 'manifest.json');
    execFileSync(process.execPath, [fileURLToPath(new URL('../script/firefox_manifest.mjs', import.meta.url)),
      fileURLToPath(new URL('../browser-extensions/webextension/manifest.json', import.meta.url)), output]);
    const generated = JSON.parse(await readFile(output, 'utf8'));
    assert.deepEqual(generated.background.scripts, ['website-policy.js', 'service-worker.js']);
    assert.equal(generated.browser_specific_settings.gecko.id, 'parental-control@bilalalissa.com');
    assert.equal(generated.browser_specific_settings.gecko.strict_min_version, '133.0');
    assert.equal(generated.key, undefined);
    assert.equal(generated.update_url, undefined);
    assert.equal(generated.incognito, 'not_allowed');
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('worker applies blocking with collection off and preserves it through a native outage', async () => {
  const api = browser(), calls = [];
  let available = true;
  const event = { addListener() {} };
  api.runtime = { onInstalled: event, onStartup: event, sendNativeMessage: async (_host, message) => {
    calls.push(message);
    if (!available) throw Error('host unavailable');
    return { accepted: true, enabled: false, browser: 'firefox', websitePolicy: { version: 7, domains: ['example.com'] } };
  } };
  api.tabs = { onCreated: event, onRemoved: event, onActivated: event, onUpdated: event,
    query: async () => { throw Error('must not collect tabs without consent'); } };
  api.windows = { onFocusChanged: event };
  api.alarms = { onAlarm: event };
  const worker = vm.createContext({ browser: api, chrome: api, WebsitePolicy: policy,
    navigator: { userAgent: 'Firefox/133.0' }, crypto: { randomUUID: () => 'synthetic-profile' } });
  vm.runInContext(await readFile(new URL('../browser-extensions/webextension/service-worker.js', import.meta.url), 'utf8'), worker);
  await vm.runInContext('publishTabs()', worker);
  assert.equal(api.rules().length, 1);
  assert.equal(calls.find(x => x.type === 'policy.ack').policyVersion, 7);
  assert.ok(!calls.some(x => x.type === 'tabs.update'));
  calls.length = 0;
  available = false;
  await vm.runInContext('publishTabs()', worker);
  assert.equal(api.rules().length, 1);
  assert.ok(!calls.some(x => x.type === 'policy.ack'));
});
