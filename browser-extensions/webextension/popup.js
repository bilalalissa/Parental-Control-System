const HOST = "com.bilalalissa.parental_control";
const status = document.querySelector("#status");
const browser = navigator.userAgent.includes("Edg/") ? "edge" : "chrome";

chrome.storage.local.get("profileID").then(({ profileID }) => {
  chrome.runtime.sendNativeMessage(HOST, {
    type: "configuration.query",
    browser,
    profile: profileID || "uninitialized",
    tabs: []
  }).then((response) => {
    status.textContent = response?.enabled
      ? "Sharing is enabled by your parent"
      : "Sharing is disabled";
  }).catch(() => {
    status.textContent = "Local child endpoint unavailable";
  });
});
