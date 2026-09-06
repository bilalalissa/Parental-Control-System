/* Domain-only rules: no request listeners, payload access, or page scripts. */
globalThis.WebsitePolicy = (() => {
  function validate(policy) {
    if (!policy || !Number.isSafeInteger(policy.version) || policy.version <= 0 ||
        !Array.isArray(policy.domains) || policy.domains.length > 256 ||
        policy.domains.reduce((size, domain) => size + (typeof domain === "string" ? domain.length : 32769), 0) > 32768) throw new Error("Invalid policy");
    const domains = policy.domains.map((domain) => {
      if (typeof domain !== "string" || domain.length > 253 || domain !== domain.toLowerCase() ||
          domain.endsWith(".local") || domain.endsWith(".localhost")) throw new Error("Invalid domain");
      const labels = domain.split(".");
      if (labels.length < 2 || !/[a-z]/.test(labels.at(-1)) || labels.some((label) =>
          !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) throw new Error("Invalid domain");
      return domain;
    });
    return { version: policy.version, domains: [...new Set(domains)].sort() };
  }
  function rulesFor(policy, browser = "chromium") {
    if (browser === "safari") {
      return policy.domains.map((domain, index) => ({
        id: index + 1, priority: 1, action: { type: "block" },
        condition: { urlFilter: `||${domain}^`, resourceTypes: ["main_frame", "sub_frame"] }
      }));
    }
    return policy.domains.length ? [{ id: 1, priority: 1, action: { type: "block" },
      condition: { requestDomains: policy.domains, resourceTypes: ["main_frame", "sub_frame"] } }] : [];
  }
  function hostnameForURL(value) {
    if (typeof value !== "string") return null;
    try {
      const url = new URL(value);
      if (url.protocol !== "http:" && url.protocol !== "https:") return null;
      return url.hostname.toLowerCase().replace(/\.+$/, "");
    } catch {
      return null;
    }
  }
  function matchingDomain(value, policy) {
    const hostname = hostnameForURL(value);
    if (!hostname) return null;
    return validate(policy).domains.find((domain) =>
      hostname === domain || hostname.endsWith(`.${domain}`)) || null;
  }
  async function cached(api) {
    const stored = await api.storage.local.get("websitePolicy");
    return stored.websitePolicy ? validate(stored.websitePolicy) : null;
  }
  async function enforceTab(api, tab, policy) {
    if (!tab || tab.incognito === true || !Number.isSafeInteger(tab.id) ||
        !matchingDomain(tab.url, policy)) return false;
    await api.tabs.update(tab.id, { url: api.runtime.getURL("blocked.html") });
    return true;
  }
  async function enforceOpenTabs(api, policy) {
    const validated = validate(policy);
    const tabs = await api.tabs.query({});
    let blocked = 0;
    for (const tab of tabs) {
      try {
        if (await enforceTab(api, tab, validated)) blocked += 1;
      } catch {
        // A tab can close or become a protected browser page during reconciliation.
      }
    }
    return blocked;
  }
  function sameRules(actual, expected) {
    const normalized = (rules) => JSON.stringify(rules.map((rule) => ({
      id: rule.id, priority: rule.priority, action: rule.action,
      condition: {
        ...rule.condition,
        requestDomains: rule.condition.requestDomains
          ? [...rule.condition.requestDomains].sort() : undefined,
        resourceTypes: [...(rule.condition.resourceTypes || [])].sort()
      }
    })).sort((left, right) => left.id - right.id));
    return normalized(actual) === normalized(expected);
  }
  async function apply(api, incoming, browser = "chromium") {
    const policy = validate(incoming);
    const { websitePolicy: cached } = await api.storage.local.get("websitePolicy");
    if (cached && (policy.version < cached.version ||
        (policy.version === cached.version && JSON.stringify(policy) !== JSON.stringify(validate(cached))))) {
      throw new Error("Stale policy");
    }
    const expected = rulesFor(policy, browser);
    const current = await api.declarativeNetRequest.getDynamicRules();
    if (!sameRules(current, expected)) {
      await api.declarativeNetRequest.updateDynamicRules({ removeRuleIds: current.map((r) => r.id), addRules: expected });
    }
    if (!sameRules(await api.declarativeNetRequest.getDynamicRules(), expected)) throw new Error("Rule verification failed");
    await api.storage.local.set({ websitePolicy: policy });
    return policy.version;
  }
  return {
    validate, rulesFor, hostnameForURL, matchingDomain, cached, enforceTab, enforceOpenTabs,
    sameRules, apply
  };
})();
