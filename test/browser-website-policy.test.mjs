import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const context = vm.createContext({ URL });
vm.runInContext(await readFile(new URL('../browser-extensions/webextension/website-policy.js', import.meta.url), 'utf8'), context);
const policy = context.WebsitePolicy;
const plain = (value) => JSON.parse(JSON.stringify(value));
function browser() {
  let rules = [], storage = {}, writes = 0, tabs = [], updates = [];
  return {
    storage: { local: { get: async () => storage, set: async (value) => { storage = { ...storage, ...plain(value) }; } } },
    declarativeNetRequest: {
      getDynamicRules: async () => rules,
      updateDynamicRules: async ({ addRules }) => { rules = plain(addRules); writes++; }
    },
    runtime: { getURL: (path) => `chrome-extension://synthetic/${path}` },
    tabs: {
      query: async () => tabs,
      get: async (id) => tabs.find((tab) => tab.id === id),
      update: async (id, change) => {
        updates.push({ id, change: plain(change) });
        const tab = tabs.find((candidate) => candidate.id === id);
        if (tab && change.url) tab.url = change.url;
      }
    },
    rules: () => rules, writes: () => writes,
    setTabs: (value) => { tabs = plain(value); },
    updates: () => updates
  };
}
test('domain-only rules cover navigations and frames, without observing requests', () => {
  const rules = plain(policy.rulesFor(policy.validate({ version: 1, domains: ['youtube.com', 'example.org'] })));
  assert.deepEqual(rules[0].condition, { requestDomains: ['example.org', 'youtube.com'], resourceTypes: ['main_frame', 'sub_frame'] });
  assert.equal(rules[0].action.type, 'block');
});
test('Safari receives equivalent hostname-only urlFilter rules', () => {
  const rules = plain(policy.rulesFor(
    policy.validate({ version: 1, domains: ['youtube.com', 'example.org'] }), 'safari'));
  assert.deepEqual(rules, [
    { id: 1, priority: 1, action: { type: 'block' },
      condition: { urlFilter: '||example.org^', resourceTypes: ['main_frame', 'sub_frame'] } },
    { id: 2, priority: 1, action: { type: 'block' },
      condition: { urlFilter: '||youtube.com^', resourceTypes: ['main_frame', 'sub_frame'] } }
  ]);
});
test('local hostname matching covers exact, subdomain, restored and SPA URLs without inspecting paths', async () => {
  const api = browser();
  const configured = policy.validate({ version: 2, domains: ['youtube.com'] });
  assert.equal(policy.matchingDomain('https://youtube.com/watch?v=private', configured), 'youtube.com');
  assert.equal(policy.matchingDomain('https://www.youtube.com/shorts/private', configured), 'youtube.com');
  assert.equal(policy.matchingDomain('https://m.youtube.com./feed', configured), 'youtube.com');
  assert.equal(policy.matchingDomain('https://notyoutube.com/watch', configured), null);
  assert.equal(policy.matchingDomain('chrome://settings', configured), null);
  api.setTabs([
    { id: 7, url: 'https://www.youtube.com/watch?v=private', incognito: false },
    { id: 8, url: 'https://example.com/youtube.com', incognito: false },
    { id: 9, url: 'https://youtube.com/', incognito: true }
  ]);
  assert.equal(await policy.enforceOpenTabs(api, configured), 1);
  assert.deepEqual(api.updates(), [
    { id: 7, change: { url: 'chrome-extension://synthetic/blocked.html' } }
  ]);
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

test('Safari packaging removes browser-store identity fields without broadening permissions', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'parental-safari-test-'));
  try {
    const output = join(directory, 'manifest.json');
    execFileSync(process.execPath, [fileURLToPath(new URL('../script/safari_manifest.mjs', import.meta.url)),
      fileURLToPath(new URL('../browser-extensions/webextension/manifest.json', import.meta.url)), output]);
    const generated = JSON.parse(await readFile(output, 'utf8'));
    assert.equal(generated.key, undefined);
    assert.equal(generated.version_name, undefined);
    assert.equal(generated.incognito, undefined);
    assert.ok(generated.permissions.includes('nativeMessaging'));
    assert.ok(generated.permissions.includes('declarativeNetRequest'));
    assert.equal(generated.content_scripts, undefined);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('worker applies blocking with collection off and preserves it through a native outage', async () => {
  const api = browser(), calls = [], updates = [];
  let available = true;
  const event = () => {
    let listener;
    return { addListener(value) { listener = value; }, fire(...args) { return listener?.(...args); } };
  };
  const onInstalled = event(), onStartup = event(), onCreated = event(), onRemoved = event();
  const onActivated = event(), onUpdated = event(), onFocusChanged = event(), onAlarm = event();
  const tabs = [{ id: 17, url: 'https://www.youtube.com/watch?v=private', incognito: false }];
  api.runtime = { onInstalled, onStartup, getURL: (path) => `chrome-extension://synthetic/${path}`,
    sendNativeMessage: async (_host, message) => {
    calls.push(message);
    if (!available) throw Error('host unavailable');
    return { accepted: true, enabled: false, browser: 'firefox', websitePolicy: { version: 7, domains: ['youtube.com'] } };
  } };
  api.tabs = { onCreated, onRemoved, onActivated, onUpdated,
    query: async () => tabs,
    get: async (id) => tabs.find((tab) => tab.id === id),
    update: async (id, change) => {
      updates.push({ id, change: plain(change) });
      const tab = tabs.find((candidate) => candidate.id === id);
      if (tab && change.url) tab.url = change.url;
    } };
  api.windows = { onFocusChanged };
  api.alarms = { onAlarm, create() {} };
  const worker = vm.createContext({ browser: api, chrome: api, WebsitePolicy: policy, URL,
    navigator: { userAgent: 'Firefox/133.0' }, crypto: { randomUUID: () => 'synthetic-profile' },
    setTimeout, clearTimeout });
  vm.runInContext(await readFile(new URL('../browser-extensions/webextension/service-worker.js', import.meta.url), 'utf8'), worker);
  await vm.runInContext('publishTabs()', worker);
  assert.equal(api.rules().length, 1);
  assert.equal(updates.length, 1);
  assert.equal(calls.find(x => x.type === 'policy.ack').policyVersion, 7);
  assert.ok(!calls.some(x => x.type === 'tabs.update'));
  calls.length = 0;
  available = false;
  tabs[0].url = 'https://m.youtube.com/restored';
  await vm.runInContext('publishTabs()', worker);
  assert.equal(api.rules().length, 1);
  assert.equal(updates.length, 2);
  assert.ok(!calls.some(x => x.type === 'policy.ack'));

  tabs[0].url = 'https://youtube.com/spa-route';
  onUpdated.fire(17, { url: tabs[0].url }, tabs[0]);
  await vm.runInContext('enforcement', worker);
  assert.equal(updates.length, 3);

  tabs[0].url = 'https://www.youtube.com/restored-after-startup';
  onStartup.fire();
  await vm.runInContext('enforcement', worker);
  assert.equal(updates.length, 4);
});
