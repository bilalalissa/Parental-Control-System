const HOST = "com.bilalalissa.parental_control";
if (typeof importScripts === "function") importScripts("website-policy.js");
const api = globalThis.browser || chrome;
const MAX_TABS = 128;
let debounceTimer;
let publication = Promise.resolve();
let lastPublishedTabs;

async function nativeMessage(message) {
  try {
    return await api.runtime.sendNativeMessage(HOST, message);
  } catch (error) {
    return { accepted: false, enabled: false, error: String(error?.message || error) };
  }
}

async function profileID() {
  const stored = await api.storage.local.get("profileID");
  if (typeof stored.profileID === "string" && stored.profileID.length <= 80) {
    return stored.profileID;
  }
  const value = crypto.randomUUID();
  await api.storage.local.set({ profileID: value });
  return value;
}

function browserName() {
  if (navigator.userAgent.includes("Firefox/")) return "firefox";
  return navigator.userAgent.includes("Edg/") ? "edge" : "chrome";
}

function sanitizedOrigin(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return url.origin;
  } catch {
    return null;
  }
}

async function sharingEnabled(browser, profile) {
  const response = await nativeMessage({
    type: "configuration.query",
    browser,
    profile,
    tabs: []
  });
  return response;
}

async function publishTabs() {
  const browser = browserName();
  const profile = await profileID();
  const configuration = await sharingEnabled(browser, profile);
  const authorizedBrowser = configuration.browser || browser;
  if (configuration.accepted === true && configuration.websitePolicy) {
    let state = "applied";
    try {
      await WebsitePolicy.apply(api, configuration.websitePolicy);
    } catch { state = "error"; }
    await api.storage.local.set({ websitePolicyState: state });
    await nativeMessage({ type: "policy.ack", browser: authorizedBrowser, profile, tabs: [],
      policyVersion: configuration.websitePolicy.version, policyState: state });
  } else if (configuration.accepted === true) {
    await nativeMessage({ type: "policy.ack", browser: authorizedBrowser, profile, tabs: [],
      policyVersion: null, policyState: "setup-required" });
  }
  // Native outages do not erase durable browser rules or fabricate acknowledgements.
  if (configuration?.enabled !== true) { lastPublishedTabs = undefined; return; }

  const observedAt = Date.now();
  const tabs = (await api.tabs.query({}))
    .filter((tab) => tab.incognito !== true)
    .map((tab) => {
      const origin = sanitizedOrigin(tab.url);
      if (!origin) return null;
      return {
        title: String(tab.title || "Untitled").slice(0, 300),
        origin,
        active: tab.active === true,
        observedAt
      };
    })
    .filter(Boolean)
    .sort((left, right) => Number(right.active) - Number(left.active))
    .slice(0, MAX_TABS);

  const digest = JSON.stringify(tabs.map(({ observedAt: _time, ...tab }) => tab));
  if (digest === lastPublishedTabs) return;
  const result = await nativeMessage({ type: "tabs.update", browser: authorizedBrowser, profile, tabs });
  if (result.accepted) lastPublishedTabs = digest;
}

function schedulePublish() {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    publication = publication.then(publishTabs).catch(() => {});
  }, 500);
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create("bounded-reconciliation", { periodInMinutes: 15 });
  chrome.alarms.create("website-policy-reconciliation", { periodInMinutes: 1 });
  schedulePublish();
});
chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create("website-policy-reconciliation", { periodInMinutes: 1 });
  schedulePublish();
});
chrome.tabs.onCreated.addListener(schedulePublish);
chrome.tabs.onRemoved.addListener(schedulePublish);
chrome.tabs.onActivated.addListener(schedulePublish);
chrome.tabs.onUpdated.addListener((_tabID, change) => {
  if (change.url || change.title || change.status === "complete") schedulePublish();
});
chrome.windows.onFocusChanged.addListener(schedulePublish);
chrome.alarms.onAlarm.addListener((alarm) => {
  if (["bounded-reconciliation", "website-policy-reconciliation"].includes(alarm.name)) schedulePublish();
});
