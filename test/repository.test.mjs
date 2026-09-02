import assert from "node:assert/strict";
import { access, readFile, readdir } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const root = fileURLToPath(new URL("..", import.meta.url));
const read = (path) => readFile(join(root, path), "utf8");
const readJson = async (path) => JSON.parse(await read(path));

async function walk(directory, suffix) {
  const entries = await readdir(directory, { withFileTypes: true });
  const results = [];
  for (const entry of entries) {
    if (entry.name === ".git" || entry.name === "node_modules") continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) results.push(...await walk(path, suffix));
    else if (path.endsWith(suffix)) results.push(path);
  }
  return results;
}

test("all repository JSON documents parse", async () => {
  const files = await walk(root, ".json");
  assert.ok(files.length >= 7);
  for (const file of files) JSON.parse(await readFile(file, "utf8"));
});

test("stage tracker uses an allowed state and identifies one active stage", async () => {
  const tracker = await readJson("docs/stages/stage-status.json");
  const schema = await readJson("docs/stages/stage-status.schema.json");
  const allowed = schema.properties.stages.items.properties.status.enum;
  const active = tracker.stages.filter((stage) => stage.id === tracker.activeStage);
  assert.equal(active.length, 1);
  assert.ok(allowed.includes(active[0].status));
  assert.equal(active[0].branch, "stage/06a-manual-mdm-feasibility");
  assert.equal(active[0].version, "0.6.1-rc.1");
  assert.equal(active[0].status, "READY_FOR_RETEST");
  const idPattern = new RegExp(schema.properties.stages.items.properties.id.pattern);
  assert.ok(tracker.stages.every((stage) => idPattern.test(stage.id)));
});

test("Stage 04 installer defaults to the parent and offers an explicit child choice", async () => {
  const [distribution, choices] = await Promise.all([
    read("agents/endpoint-macos/Installer/Distribution.xml"),
    read("agents/endpoint-macos/Installer/ci-child-choices.xml"),
  ]);
  assert.match(distribution, /choice id="parent-controller"[\s\S]*start_selected="true"/);
  assert.match(distribution, /choice id="child-endpoint"[\s\S]*start_selected="false"/);
  assert.match(distribution, /ParentalControlController\.pkg/);
  assert.match(distribution, /ParentalControlChild\.pkg/);
  assert.match(choices, /<string>parent-controller<\/string>[\s\S]*<integer>0<\/integer>/);
  assert.match(choices, /<string>child-endpoint<\/string>[\s\S]*<integer>1<\/integer>/);
});

test("Stage 04 keeps the visible helper alive and refreshes its launch registration", async () => {
  const [launchAgent, preinstall, postinstall] = await Promise.all([
    read("agents/endpoint-macos/Installer/com.bilalalissa.ParentalControlAgent.user.plist"),
    read("agents/endpoint-macos/Installer/preinstall"),
    read("agents/endpoint-macos/Installer/postinstall"),
  ]);
  assert.match(launchAgent, /<key>KeepAlive<\/key>/);
  assert.match(launchAgent, /<key>KeepAlive<\/key><true\/>/);
  assert.match(postinstall, /for attempt in 1 2 3/);
  assert.match(postinstall, /launchctl bootout "\$USER_SERVICE"/);
  assert.match(postinstall, /launchctl bootstrap "gui\/\$CONSOLE_UID"/);
  assert.match(postinstall, /launchctl kickstart -k "\$USER_SERVICE"/);
  const rc5Daemon = /0bb256f6135e59e5b217d11894d9848c6f64529ec5dccd6c4c0d14d853b52a66/;
  assert.match(preinstall, rc5Daemon);
  assert.match(postinstall, rc5Daemon);
  assert.match(preinstall, /configuration\.json/);
  assert.match(preinstall, /\.rc5-daemon-upgrade/);
  assert.match(postinstall, /\.rc5-daemon-upgrade/);
  assert.doesNotMatch(preinstall, /security|delete-generic-password|device-/);
});

test("Stage 04 activity controls use an explicit accessible expansion button", async () => {
  const devices = await read(
    "apps/controller-macos/Sources/ParentalControlController/Views/DevicesView.swift",
  );
  assert.match(devices, /devices\.paired-disclosure|pairedDeviceDisclosure/);
  assert.match(devices, /devices\.activity-sharing|activitySharingToggle/);
  assert.doesNotMatch(devices, /DisclosureGroup/);
});

test("child notification authorization avoids actor-isolated completion callbacks", async () => {
  const child = await read(
    "agents/endpoint-macos/Sources/ParentalControlChild/ParentalControlChild.swift",
  );
  assert.match(
    child,
    /let center = UNUserNotificationCenter\.current\(\)[\s\S]*Task\s*\{[\s\S]*try\?\s+await\s+center\.requestAuthorization/,
  );
  assert.doesNotMatch(child, /requestAuthorization\([^)]*\)\s*\{\s*_,\s*_\s+in/);
});

test("child can replace a pending time request without enabling rapid duplicate submissions", async () => {
  const child = await read(
    "agents/endpoint-macos/Sources/ParentalControlChild/ParentalControlChild.swift",
  );
  assert.match(child, /state == \.pending \? "Update Request" : "Send Request"/);
  assert.match(child, /guard !isSubmittingTimeRequest else \{ return \}/);
  assert.match(child, /\.disabled\(model\.isSubmittingTimeRequest\)/);
  assert.doesNotMatch(child, /\.disabled\(model\.latestTimeRequest\?\.state == \.pending\)/);
});

test("parent foreground notification delegate matches the macOS SDK signature", async () => {
  const controllerApp = await read(
    "apps/controller-macos/Sources/ParentalControlController/App/ParentalControlControllerApp.swift",
  );
  assert.match(
    controllerApp,
    /nonisolated func userNotificationCenter\([\s\S]*?willPresent[\s\S]*?withCompletionHandler completionHandler:\s*@escaping \(UNNotificationPresentationOptions\) -> Void\s*\)\s*\{/,
  );
  assert.doesNotMatch(
    controllerApp,
    /withCompletionHandler completionHandler:\s*@escaping @Sendable/,
  );
});

test("Stage 04 presence refreshes without interaction and wake reconnect remains bounded", async () => {
  const [store, daemon] = await Promise.all([
    read("apps/controller-macos/Sources/ParentalControlController/Stores/ControllerStore.swift"),
    read("agents/endpoint-macos/Sources/ParentalControlAgentDaemon/main.swift"),
  ]);
  assert.match(store, /Presence is derived from lastSeen plus the current time/);
  assert.doesNotMatch(store, /if status != hubStatus \{ hubStatus = status \}/);
  assert.match(daemon, /EndpointReconnectPolicy/);
  assert.match(daemon, /onEstablishedConnectionLoss/);
});

test("parent hub startup coalesces concurrent status and pairing requests", async () => {
  const [client, store] = await Promise.all([
    read("apps/controller-macos/Sources/ParentalControlController/Services/HubClient.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Stores/ControllerStore.swift"),
  ]);
  assert.match(client, /startupCoordinator\.run/);
  assert.match(client, /runtime\.processID == process\.processIdentifier/);
  assert.match(client, /if let startupTask[\s\S]*return try await startupTask\.value/);
  assert.match(client, /if process\.isRunning \{ process\.terminate\(\) \}/);
  assert.match(client, /func statusIfRunning\(\)/);
  assert.match(client, /helperStartupPollCount = 900/);
  assert.match(client, /helperStartupPollMilliseconds = 100/);
  assert.match(store, /hubClient\.statusIfRunning\(\)/);
  assert.doesNotMatch(store, /while !Task\.isCancelled[\s\S]*hubClient\.status\(\)/);
});

test("macOS packages can use one stable signing identity without requiring CI credentials", async () => {
  const [controllerBuild, endpointBuild] = await Promise.all([
    read("script/build_app.sh"),
    read("script/build_endpoint_app.sh"),
  ]);
  for (const build of [controllerBuild, endpointBuild]) {
    assert.match(build, /SIGN_IDENTITY="\$\{MACOS_SIGNING_IDENTITY:--\}"/);
    assert.match(build, /codesign[\s\S]*--sign "\$SIGN_IDENTITY"/);
  }
});

test("Stage 05 Chromium extension is shared, opt-in, bounded, and content-minimal", async () => {
  const [manifest, nativeManifest, worker, popup, packager, postinstall, authorization] = await Promise.all([
    readJson("browser-extensions/webextension/manifest.json"),
    readJson("browser-extensions/webextension/native-host-manifest.json"),
    read("browser-extensions/webextension/service-worker.js"),
    read("browser-extensions/webextension/popup.html"),
    read("script/package_browser_extension.sh"),
    read("agents/endpoint-macos/Installer/postinstall"),
    read("agents/endpoint-macos/Sources/EndpointCore/BrowserNativeMessaging.swift"),
  ]);
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.version, "0.6.0.9");
  assert.equal(manifest.version_name, "0.6.0-rc.9");
  assert.deepEqual(manifest.permissions.sort(), ["alarms", "nativeMessaging", "storage", "tabs"]);
  for (const forbidden of ["history", "webRequest", "cookies", "downloads", "debugger"])
    assert.ok(!manifest.permissions.includes(forbidden));
  assert.equal(nativeManifest.allowed_origins.length, 1);
  assert.match(nativeManifest.allowed_origins[0], /^chrome-extension:\/\/[a-p]{32}\/$/);
  assert.match(worker, /tab\.incognito !== true/);
  assert.match(worker, /return url\.origin/);
  assert.match(worker, /\.slice\(0, MAX_TABS\)/);
  assert.match(worker, /configuration\.query/);
  assert.match(worker, /configuration\.browser \|\| browser/);
  assert.doesNotMatch(worker, /chrome\.(history|webRequest|cookies|debugger)/);
  assert.match(popup, /Private tabs, page contents, forms, cookies, passwords, query strings, fragments/);
  assert.match(packager, /ZIP="\$RC_DIR\/ParentalControlBrowserSharing-0\.6\.0-rc\.9\.zip"/);
  assert.match(packager, /Refusing an extension package containing signing secrets/);
  assert.match(packager, /\/usr\/bin\/grep/);
  assert.doesNotMatch(packager, /(?:^|\s)rg(?:\s|$)/m);
  assert.match(postinstall, /Arc\/User Data\/NativeMessagingHosts/);
  assert.match(postinstall, /launchctl print "\$DAEMON_SERVICE"/);
  assert.match(postinstall, /launchctl kickstart -k "\$DAEMON_SERVICE"/);
  assert.doesNotMatch(postinstall, /launchctl bootout system/);
  assert.doesNotMatch(postinstall, /(?:Chrome|Edge|Arc)[^\n]*Extensions\//);
  assert.match(authorization, /company\.thebrowser\.Browser/);
  assert.match(authorization, /S6N382Y83G/);
});

test("endpoint XPC clients reconnect after the privileged daemon is replaced", async () => {
  const xpc = await read("agents/endpoint-macos/Sources/EndpointCore/EndpointXPC.swift");
  assert.match(xpc, /next\.interruptionHandler/);
  assert.match(xpc, /next\.invalidationHandler/);
  assert.match(xpc, /private func discard\(_ candidate: NSXPCConnection\)/);
  assert.match(xpc, /private func remoteProxy/);
  assert.doesNotMatch(xpc, /private let connection: NSXPCConnection/);
});

test("Stage 05 chat feedback uses system-controlled audio, unread badges, and explicit read visibility", async () => {
  const [controller, childHelper, childApp, chat, root] = await Promise.all([
    read("apps/controller-macos/Sources/ParentalControlController/Stores/ControllerStore.swift"),
    read("agents/endpoint-macos/Sources/ParentalControlAgentUser/main.swift"),
    read("agents/endpoint-macos/Sources/ParentalControlChild/ParentalControlChild.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Views/ChatShellView.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Views/ControllerRootView.swift"),
  ]);
  assert.match(controller, /content\.sound = \.default/);
  assert.match(controller, /accepted > 0 \{ NSSound\.beep\(\) \}/);
  assert.doesNotMatch(
    childHelper,
    /^\s*(?:let\s+\w+\s*=\s*)?UNUserNotificationCenter\.current\(\)/m,
  );
  assert.doesNotMatch(childHelper, /import UserNotifications/);
  assert.match(childHelper, /NSSound\.beep\(\)/);
  assert.match(childHelper, /AVSpeechSynthesizer/);
  assert.match(childHelper, /message\.audience == \.announcement/);
  assert.match(childApp, /ChildAppDelegate/);
  assert.match(childApp, /completionHandler\(\[\.banner, \.sound\]\)/);
  assert.match(childApp, /IncomingMessageNotificationTracker/);
  assert.match(childApp, /UNMutableNotificationContent/);
  assert.match(childApp, /content\.sound = \.default/);
  assert.match(childApp, /Open Parental Control to read/);
  assert.match(childApp, /result\.isSuccess \{ NSSound\.beep\(\) \}/);
  assert.match(childApp, /badge: model\.unreadMessageCount/);
  assert.match(childApp, /ChildTabButton/);
  assert.match(root, /SidebarCountBadge\(count: store\.unreadChatCount/);
  assert.match(root, /SidebarCountBadge\([\s\S]*store\.pendingTimeRequestCount/);
  assert.match(chat, /markVisibleMessagesRead/);
  assert.match(chat, /editParentChatMessage/);
  assert.match(chat, /deleteParentChatMessage/);
  assert.doesNotMatch(controller, /message\.text/);
});

test("Stage 05 retains only bounded, content-minimal open-tab observations", async () => {
  const [database, devices] = await Promise.all([
    read("apps/controller-macos/Sources/HubCore/Persistence/HubDatabase.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Views/DevicesView.swift"),
  ]);
  assert.match(database, /maximumBrowserObservationRecordsPerDevice = 512/);
  assert.match(database, /saveBrowserObservations/);
  assert.match(database, /DELETE FROM browser_tabs[\s\S]*browser = \?[\s\S]*profile_id = \?[\s\S]*title = \?[\s\S]*origin = \?/);
  assert.match(devices, /Recently observed open tabs are retained/);
  assert.match(devices, /Active when observed/);
  assert.match(devices, /ScrollView\(\.vertical\)/);
  assert.match(devices, /scrollIndicators\(\.visible\)/);
  assert.doesNotMatch(devices, /activity\.prefix\(8\)/);
  assert.doesNotMatch(devices, /browserTabs\.prefix\(8\)/);
  assert.doesNotMatch(database, /chrome_history|browser_history|full_url|page_content/);
});

test("Stage 05 activity alerts are classified narrowly and rate limited", async () => {
  const [alerts, controller, devices] = await Promise.all([
    read("apps/controller-macos/Sources/HubCore/Models/ActivityAlerts.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Stores/ControllerStore.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Views/DevicesView.swift"),
  ]);
  assert.match(alerts, /youtube\.com/);
  assert.match(alerts, /possibleGame/);
  assert.match(alerts, /30 \* 60/);
  assert.match(alerts, /tab\.origin/);
  assert.doesNotMatch(alerts, /pageContent|fullURL|privateTab/);
  assert.match(controller, /YouTube activity detected/);
  assert.match(controller, /Possible game activity detected/);
  assert.match(devices, /Observed activity alerts/);
});

test("Stage 05 release UI uses one real paired-device list and the shared visual language", async () => {
  const [devices, dashboard, store, theme, child, popup] = await Promise.all([
    read("apps/controller-macos/Sources/ParentalControlController/Views/DevicesView.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Views/DashboardView.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Stores/ControllerStore.swift"),
    read("apps/controller-macos/Sources/DesignSystem/ControlTheme.swift"),
    read("agents/endpoint-macos/Sources/ParentalControlChild/ParentalControlChild.swift"),
    read("browser-extensions/webextension/popup.html"),
  ]);
  assert.match(devices, /ForEach\(store\.pairedDevices\)/);
  assert.match(devices, /selectedPairedDevice/);
  assert.doesNotMatch(devices, /Paired macOS devices|store\.devices|safeAreaInset/);
  assert.match(dashboard, /ForEach\(store\.pairedDevices\)/);
  assert.doesNotMatch(dashboard, /synthetic shell data|Privacy-first preview|Mock token/);
  assert.match(store, /removeLegacySyntheticPreviewData/);
  assert.match(theme, /public enum ControlTheme/);
  assert.match(theme, /displayTitle/);
  assert.match(child, /\.controlTheme\(\)/);
  assert.match(popup, /--accent: #ff5843/);
  assert.match(popup, /ui-monospace/);
});

test("Stage 06 policy enforcement is signed, bounded, visible, and allowlisted", async () => {
  const [policy, runtime, daemon, helper, child, schedule, devices, store, security] = await Promise.all([
    read("apps/controller-macos/Sources/HubCore/Policy/PolicyModels.swift"),
    read("agents/endpoint-macos/Sources/EndpointCore/EndpointPolicyRuntime.swift"),
    read("agents/endpoint-macos/Sources/ParentalControlAgentDaemon/main.swift"),
    read("agents/endpoint-macos/Sources/ParentalControlAgentUser/main.swift"),
    read("agents/endpoint-macos/Sources/ParentalControlChild/ParentalControlChild.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Views/ScheduleEditorView.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Views/DevicesView.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Stores/ControllerStore.swift"),
    read("SECURITY.md"),
  ]);
  assert.match(policy, /Curve25519\.Signing\.PublicKey/);
  assert.match(policy, /adultOverride[\s\S]*immediateCommand[\s\S]*exception[\s\S]*blockedInterval[\s\S]*dailyQuota/);
  assert.match(runtime, /replayedVersion/);
  assert.match(runtime, /maximumFailedAttempts = 3/);
  assert.match(runtime, /lockoutDuration: TimeInterval = 5 \* 60/);
  assert.match(runtime, /mach_continuous_time/);
  assert.match(runtime, /posixPermissions: 0o600/);
  assert.match(daemon, /repeating: 15/);
  assert.match(helper, /ScreenSaverEngine\.app/);
  assert.match(helper, /kAEShowRestartDialog/);
  assert.match(helper, /kAEShowShutdownDialog/);
  assert.doesNotMatch(helper, /kAERestart|kAEShutDown/);
  assert.match(child, /Settings are read-only here/);
  assert.match(schedule, /Sign and Apply Policy/);
  assert.match(devices, /Offline — short-lived actions are unavailable/);
  assert.match(store, /displayedAuditEvents/);
  assert.match(security, /Receipts acknowledge endpoint acceptance, not completion/);
});

test("Stage 06A transition installer is versioned, upgrade-safe, and capability-honest", async () => {
  const [
    controllerBuild,
    endpointBuild,
    packaging,
    distribution,
    preinstall,
    postinstall,
    readiness,
    agent,
    devices,
    child,
    workflow,
  ] = await Promise.all([
    read("script/build_app.sh"),
    read("script/build_endpoint_app.sh"),
    read("script/package_endpoint_release.sh"),
    read("agents/endpoint-macos/Installer/Distribution.xml"),
    read("agents/endpoint-macos/Installer/preinstall"),
    read("agents/endpoint-macos/Installer/postinstall"),
    read("apps/controller-macos/Sources/HubCore/Models/LoginEnforcementReadiness.swift"),
    read("agents/endpoint-macos/Sources/EndpointCore/EndpointAgent.swift"),
    read("apps/controller-macos/Sources/ParentalControlController/Views/DevicesView.swift"),
    read("agents/endpoint-macos/Sources/ParentalControlChild/ParentalControlChild.swift"),
    read(".github/workflows/stage-03-macos.yml"),
  ]);
  for (const build of [controllerBuild, endpointBuild]) {
    assert.match(build, /VERSION="0\.6\.1-rc\.1"/);
    assert.match(build, /CFBundleVersion string 6101/);
    assert.match(build, /derived-data\/stage-06a/);
  }
  assert.match(packaging, /ParentalControlSystem-\$VERSION\.pkg/);
  assert.match(packaging, /--version 0\.6\.1\.1/);
  assert.doesNotMatch(packaging, /package_browser_extension\.sh/);
  assert.match(distribution, /version="0\.6\.1\.1"/);
  assert.match(preinstall, /configuration\.json/);
  assert.doesNotMatch(preinstall + postinstall, /delete-generic-password|rm[^\n]*configuration\.json/);
  assert.match(readiness, /session-enforcement/);
  assert.match(readiness, /managed-identity-login/);
  assert.match(agent, /HubLoginEnforcementCapability\.session\.rawValue/);
  assert.match(devices, /Managed pre-login enforcement not configured/);
  assert.match(child, /It does not replace macOS Login Window authentication/);
  assert.match(workflow, /ParentalControlSystem-0\.6\.1-rc\.1\.pkg/);
  assert.doesNotMatch(workflow, /ParentalControlBrowserSharing-0\.6\.1-rc\.1/);
});

test("local Markdown links resolve inside the repository", async () => {
  const markdownFiles = await walk(root, ".md");
  const missing = [];
  const linkPattern = /\[[^\]]*\]\(([^)]+)\)/g;
  for (const file of markdownFiles) {
    const content = await readFile(file, "utf8");
    for (const match of content.matchAll(linkPattern)) {
      const target = match[1].split("#", 1)[0];
      if (!target || /^(?:https?:|mailto:)/.test(target)) continue;
      const decoded = decodeURIComponent(target.replace(/^<|>$/g, ""));
      const resolved = resolve(dirname(file), decoded);
      if (!resolved.startsWith(root)) missing.push(`${file}: ${target} escapes repository`);
      else {
        try {
          await access(resolved, constants.F_OK);
        } catch {
          missing.push(`${file}: ${target}`);
        }
      }
    }
  }
  assert.deepEqual(missing, []);
});

test("CI is least-privilege, cancellable, pinned, and short-retention", async () => {
  const workflow = await read(".github/workflows/stage-00-quality.yml");
  assert.match(workflow, /permissions:\n  contents: read/);
  assert.match(workflow, /cancel-in-progress: true/);
  assert.match(workflow, /retention-days: 7/);
  const actionRefs = [...workflow.matchAll(/uses:\s+([^\s]+)/g)].map((match) => match[1]);
  assert.ok(actionRefs.length >= 3);
  for (const ref of actionRefs) assert.match(ref, /@[0-9a-f]{40}$/);
  assert.doesNotMatch(workflow, /pull_request_target/);
});

test("Stage 06 CI verifies the fresh default install before child customization", async () => {
  const workflow = await read(".github/workflows/stage-03-macos.yml");
  const parentInstall = workflow.indexOf("- name: Install default parent choice");
  const childInstall = workflow.indexOf(
    "- name: Install, verify upgrade persistence, and uninstall child choice",
  );
  assert.ok(parentInstall >= 0);
  assert.ok(childInstall > parentInstall);
  assert.match(workflow, /BEFORE_SHA: \$\{\{ github\.event\.before \}\}/);
  assert.match(workflow, /git diff --quiet "\$BASE_SHA" HEAD/);
  assert.doesNotMatch(workflow, /git diff --quiet HEAD\^ HEAD/);
  assert.match(
    workflow,
    /Install default parent choice[\s\S]*?codesign --verify --deep --strict[\s\S]*?pkgutil --forget com\.bilalalissa\.ParentalControlController\.component/,
  );
  assert.match(workflow, /Verify child in-place upgrade preserves endpoint identity/);
  assert.match(workflow, /test "\$first_device_id" = "\$second_device_id"/);
  assert.match(workflow, /test "\$PWD" = "\$GITHUB_WORKSPACE"/);
  assert.match(
    workflow,
    /sudo \/bin\/rm -rf --[\s\S]*?"\$PWD\/dist"[\s\S]*?"\$PWD\/\.artifacts\/derived-data"[\s\S]*?"\$PWD\/\.artifacts\/package-staging"/,
  );
  assert.doesNotMatch(workflow, /sudo \.\/tools\/cleanup\.sh/);
});

test("macOS packaging retries transient disk-image failures without skipping verification", async () => {
  const packaging = await read("script/package_release.sh");
  assert.match(packaging, /HDIUTIL_ATTEMPTS=3/);
  assert.match(packaging, /HDIUTIL_RETRY_DELAY_SECONDS=2/);
  assert.match(packaging, /retry_hdiutil create create_dmg/);
  assert.match(packaging, /retry_hdiutil verify verify_dmg/);
  assert.match(packaging, /hdiutil verify/);
});

test("ignore rules cover generated output without hiding canonical packages", async () => {
  const ignore = await read(".gitignore");
  for (const pattern of ["DerivedData/", "*.xcarchive/", "**/bin/", "**/obj/", "node_modules/", ".artifacts/test-results/", "*.msi", "*.pkg"]) assert.ok(ignore.includes(pattern), pattern);
  assert.doesNotMatch(ignore, /^packages\/$/m);
});

test("README and license identify pre-release status and terms", async () => {
  const [readme, license] = await Promise.all([read("README.md"), read("LICENSE")]);
  assert.match(readme, /Stages 00–06 are merged; STAGE-06A is ready for installer retest; STAGE-07 has not begun/);
  assert.match(readme, /enforce the last valid signed policy while offline/);
  assert.match(readme, /MIT License/);
  assert.match(license, /^MIT License/);
});
