const HOST = "com.bilalalissa.parental_control";
const status = document.querySelector("#status");
const api = globalThis.browser || chrome;
api.storage.local.get(["websitePolicy", "websitePolicyState"]).then((stored) => {
  document.querySelector("#protection").textContent = stored.websitePolicy
    ? `Stored website policy ${stored.websitePolicy.version}: ${stored.websitePolicy.domains.length} blocked domains. Last application: ${stored.websitePolicyState || "unknown"}.`
    : "No website policy applied yet. Ask your parent to apply a policy.";
});
const browser = navigator.userAgent.includes("Edg/") ? "edge" : "chrome";

chrome.storage.local.get("profileID").then(({ profileID }) => {
  chrome.runtime.sendNativeMessage(HOST, {
    type: "configuration.query",
    browser,
    profile: profileID || "uninitialized",
    tabs: []
  }).then((response) => {
    status.textContent = response?.enabled
      ? `Sharing is enabled by your parent (${response.browser || browser})`
      : "Sharing is disabled";
  }).catch((error) => {
    const detail = String(error?.message || "");
    status.textContent = detail.includes("native messaging host")
      ? "Native host unavailable. Reinstall Parental Control Child, then restart this browser."
      : "Local child endpoint unavailable. Confirm the child app is installed and running.";
  });
});
