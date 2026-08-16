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
  assert.equal(active[0].branch, "stage/05-chromium-extension");
  assert.equal(active[0].version, "0.5.0-rc.4");
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
  const [launchAgent, postinstall] = await Promise.all([
    read("agents/endpoint-macos/Installer/com.bilalalissa.ParentalControlAgent.user.plist"),
    read("agents/endpoint-macos/Installer/postinstall"),
  ]);
  assert.match(launchAgent, /<key>KeepAlive<\/key>/);
  assert.match(launchAgent, /<key>SuccessfulExit<\/key><false\/>/);
  assert.match(postinstall, /for attempt in 1 2 3/);
  assert.match(postinstall, /launchctl bootstrap "gui\/\$CONSOLE_UID"/);
  assert.match(postinstall, /launchctl kickstart -k "\$USER_SERVICE"/);
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
    /Task\s*\{[\s\S]*try\?\s+await\s+UNUserNotificationCenter\.current\(\)\.requestAuthorization/,
  );
  assert.doesNotMatch(child, /requestAuthorization\([^)]*\)\s*\{\s*_,\s*_\s+in/);
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
  const client = await read(
    "apps/controller-macos/Sources/ParentalControlController/Services/HubClient.swift",
  );
  assert.match(client, /startupCoordinator\.run/);
  assert.match(client, /runtime\.processID == process\.processIdentifier/);
  assert.match(client, /if let startupTask[\s\S]*return try await startupTask\.value/);
  assert.match(client, /if process\.isRunning \{ process\.terminate\(\) \}/);
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
  assert.match(packager, /ParentalControlBrowserSharing-0\.5\.0-rc\.4\.zip/);
  assert.match(packager, /Refusing an extension package containing signing secrets/);
  assert.match(packager, /\/usr\/bin\/grep/);
  assert.doesNotMatch(packager, /(?:^|\s)rg(?:\s|$)/m);
  assert.match(postinstall, /Arc\/User Data\/NativeMessagingHosts/);
  assert.match(authorization, /company\.thebrowser\.Browser/);
  assert.match(authorization, /S6N382Y83G/);
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
  assert.match(childHelper, /content\.sound = \.default/);
  assert.match(childHelper, /UNUserNotificationCenterDelegate/);
  assert.match(childHelper, /completionHandler\(\[\.banner, \.sound\]\)/);
  assert.match(childHelper, /NSSound\.beep\(\)/);
  assert.match(childHelper, /AVSpeechSynthesizer/);
  assert.match(childHelper, /message\.audience == \.announcement/);
  assert.match(childApp, /ChildAppDelegate/);
  assert.match(childApp, /completionHandler\(\[\.banner, \.sound\]\)/);
  assert.match(childApp, /result\.isSuccess \{ NSSound\.beep\(\) \}/);
  assert.match(childApp, /badge: model\.unreadMessageCount/);
  assert.match(childApp, /ChildTabButton/);
  assert.match(root, /UnreadChatBadge\(count: store\.unreadChatCount\)/);
  assert.match(chat, /markVisibleMessagesRead/);
  assert.match(chat, /editParentChatMessage/);
  assert.match(chat, /deleteParentChatMessage/);
  assert.doesNotMatch(controller, /message\.text/);
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

test("Stage 05 CI verifies the fresh default install before child customization", async () => {
  const workflow = await read(".github/workflows/stage-03-macos.yml");
  const parentInstall = workflow.indexOf("- name: Install default parent choice");
  const childInstall = workflow.indexOf("- name: Install, diagnose, and uninstall child choice");
  assert.ok(parentInstall >= 0);
  assert.ok(childInstall > parentInstall);
  assert.match(
    workflow,
    /Install default parent choice[\s\S]*?codesign --verify --deep --strict[\s\S]*?pkgutil --forget com\.bilalalissa\.ParentalControlController\.component/,
  );
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
  assert.match(readme, /Stages 00–04 are merged; STAGE-05 `0\.5\.0-rc\.3`/);
  assert.match(readme, /unread Chat counters/);
  assert.match(readme, /MIT License/);
  assert.match(license, /^MIT License/);
});
