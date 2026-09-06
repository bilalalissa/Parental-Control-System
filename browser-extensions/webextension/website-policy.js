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
  function rulesFor(policy) {
    return policy.domains.length ? [{ id: 1, priority: 1, action: { type: "block" },
      condition: { requestDomains: policy.domains, resourceTypes: ["main_frame", "sub_frame"] } }] : [];
  }
  function sameRules(actual, expected) {
    if (actual.length !== expected.length) return false;
    return !expected.length || (actual[0].id === 1 && actual[0].action.type === "block" &&
      actual[0].priority === 1 && Object.keys(actual[0].condition).sort().join() === "requestDomains,resourceTypes" &&
      [...actual[0].condition.requestDomains].sort().join() === expected[0].condition.requestDomains.join() &&
      [...actual[0].condition.resourceTypes].sort().join() === "main_frame,sub_frame");
  }
  async function apply(api, incoming) {
    const policy = validate(incoming);
    const { websitePolicy: cached } = await api.storage.local.get("websitePolicy");
    if (cached && (policy.version < cached.version ||
        (policy.version === cached.version && JSON.stringify(policy) !== JSON.stringify(validate(cached))))) {
      throw new Error("Stale policy");
    }
    const expected = rulesFor(policy);
    const current = await api.declarativeNetRequest.getDynamicRules();
    if (!sameRules(current, expected)) {
      await api.declarativeNetRequest.updateDynamicRules({ removeRuleIds: current.map((r) => r.id), addRules: expected });
    }
    if (!sameRules(await api.declarativeNetRequest.getDynamicRules(), expected)) throw new Error("Rule verification failed");
    await api.storage.local.set({ websitePolicy: policy });
    return policy.version;
  }
  return { validate, rulesFor, sameRules, apply };
})();
