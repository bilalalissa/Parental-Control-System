const HOST = "com.bilalalissa.parental_control";
const MAX_TABS = 128;
let debounceTimer;

async function nativeMessage(message) {
  try {
    return await chrome.runtime.sendNativeMessage(HOST, message);
  } catch {
    return { accepted: false, enabled: false };
  }
}

async function profileID() {
  const stored = await chrome.storage.local.get("profileID");
  if (typeof stored.profileID === "string" && stored.profileID.length <= 80) {
    return stored.profileID;
  }
  const value = crypto.randomUUID();
  await chrome.storage.local.set({ profileID: value });
  return value;
}

function browserName() {
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
  return response?.enabled === true;
}

async function publishTabs() {
  const browser = browserName();
  const profile = await profileID();
  if (!(await sharingEnabled(browser, profile))) return;

  const observedAt = Date.now();
  const tabs = (await chrome.tabs.query({}))
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

  await nativeMessage({ type: "tabs.update", browser, profile, tabs });
}

function schedulePublish() {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => publishTabs(), 500);
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create("bounded-reconciliation", { periodInMinutes: 15 });
  schedulePublish();
});
chrome.runtime.onStartup.addListener(schedulePublish);
chrome.tabs.onCreated.addListener(schedulePublish);
chrome.tabs.onRemoved.addListener(schedulePublish);
chrome.tabs.onActivated.addListener(schedulePublish);
chrome.tabs.onUpdated.addListener((_tabID, change) => {
  if (change.url || change.title || change.status === "complete") schedulePublish();
});
chrome.windows.onFocusChanged.addListener(schedulePublish);
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "bounded-reconciliation") schedulePublish();
});
