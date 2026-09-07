#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="0.6.5-rc.6"
STAGING="$ROOT_DIR/.artifacts/package-staging/stage-06e"
COMPONENTS="$STAGING/component-packages"
CHILD_PAYLOAD="$STAGING/child-payload"
CHILD_SCRIPTS="$STAGING/child-scripts"
CONTROLLER_PAYLOAD="$STAGING/controller-payload"
CONTROLLER_COMPONENTS="$ROOT_DIR/agents/endpoint-macos/Installer/ControllerComponents.plist"
CHILD_COMPONENTS="$ROOT_DIR/agents/endpoint-macos/Installer/ChildComponents.plist"
RESOURCES="$STAGING/resources"
EXPANDED="$STAGING/expanded"
RC_DIR="$ROOT_DIR/.artifacts/release-candidate"
PKG="$RC_DIR/ParentalControlSystem-$VERSION.pkg"
CHECKSUM="$PKG.sha256"
CHILD_APP="$ROOT_DIR/dist/Parental Control Child.app"
CONTROLLER_APP="$ROOT_DIR/dist/ParentalControlController.app"
SAFARI_APP="$ROOT_DIR/dist/Parental Control Safari.app"
BROWSER_ZIP="$RC_DIR/ParentalControlBrowserSharing-$VERSION.zip"
BROWSER_STABLE="$CHILD_PAYLOAD/Library/Application Support/ParentalControlBrowserExtension/Chromium"

retry() {
  local description="$1"
  shift
  for attempt in 1 2 3; do
    if "$@"; then return 0; fi
    if [[ "$attempt" == 3 ]]; then
      echo "$description failed after three attempts." >&2
      return 1
    fi
    echo "$description attempt $attempt failed; retrying in 2 seconds." >&2
    sleep 2
  done
}

"$ROOT_DIR/script/build_app.sh" Release >/dev/null
"$ROOT_DIR/script/build_endpoint_app.sh" Release >/dev/null
"$ROOT_DIR/script/build_safari_extension.sh" >/dev/null
"$ROOT_DIR/script/package_browser_extension.sh" >/dev/null
rm -rf -- "$STAGING"
rm -f -- "$PKG" "$CHECKSUM"
mkdir -p \
  "$COMPONENTS" \
  "$CHILD_PAYLOAD/Applications" \
  "$CHILD_PAYLOAD/Library/PrivilegedHelperTools" \
  "$CHILD_PAYLOAD/Library/LaunchDaemons" \
  "$CHILD_PAYLOAD/Library/LaunchAgents" \
  "$CHILD_PAYLOAD/Library/Google/Chrome/NativeMessagingHosts" \
  "$CHILD_PAYLOAD/Library/Microsoft/Edge/NativeMessagingHosts" \
  "$CHILD_PAYLOAD/Library/Application Support/Mozilla/NativeMessagingHosts" \
  "$CHILD_PAYLOAD/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts" \
  "$CHILD_PAYLOAD/Library/Application Support/ParentalControlAgent" \
  "$BROWSER_STABLE" \
  "$CHILD_PAYLOAD/usr/local/bin" \
  "$CHILD_SCRIPTS" \
  "$CONTROLLER_PAYLOAD/Applications" \
  "$RESOURCES" \
  "$RC_DIR"

cp -R "$CONTROLLER_APP" "$CONTROLLER_PAYLOAD/Applications/Parental Control.app"
cp -R "$CHILD_APP" "$CHILD_PAYLOAD/Applications/Parental Control Child.app"
cp -R "$SAFARI_APP" "$CHILD_PAYLOAD/Applications/Parental Control Safari.app"
cp "$CHILD_APP/Contents/Helpers/ParentalControlAgentDaemon" "$CHILD_PAYLOAD/Library/PrivilegedHelperTools/com.bilalalissa.ParentalControlAgent.daemon"
cp "$CHILD_APP/Contents/Helpers/ParentalControlAgentCtl" "$CHILD_PAYLOAD/usr/local/bin/parental-control-agentctl"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/com.bilalalissa.ParentalControlAgent.daemon.plist" "$CHILD_PAYLOAD/Library/LaunchDaemons/"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/com.bilalalissa.ParentalControlAgent.user.plist" "$CHILD_PAYLOAD/Library/LaunchAgents/"
cp "$ROOT_DIR/browser-extensions/webextension/native-host-manifest.json" \
  "$CHILD_PAYLOAD/Library/Google/Chrome/NativeMessagingHosts/com.bilalalissa.parental_control.json"
cp "$ROOT_DIR/browser-extensions/webextension/native-host-manifest.json" \
  "$CHILD_PAYLOAD/Library/Microsoft/Edge/NativeMessagingHosts/com.bilalalissa.parental_control.json"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/postinstall" "$CHILD_SCRIPTS/postinstall"
cp "$ROOT_DIR/browser-extensions/webextension/firefox-native-host-manifest.json" \
  "$CHILD_PAYLOAD/Library/Application Support/Mozilla/NativeMessagingHosts/com.bilalalissa.parental_control.json"
cp "$ROOT_DIR/browser-extensions/webextension/native-host-manifest.json" \
  "$CHILD_PAYLOAD/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.bilalalissa.parental_control.json"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/preinstall" "$CHILD_SCRIPTS/preinstall"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/Distribution.xml" "$STAGING/Distribution.xml"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/Welcome.html" "$RESOURCES/Welcome.html"
/usr/bin/unzip -q "$BROWSER_ZIP" -d "$STAGING/browser-extension"
cp -R "$STAGING/browser-extension/ParentalControlBrowserSharing/." "$BROWSER_STABLE/"

XPC_MANIFEST="$CHILD_PAYLOAD/Library/Application Support/ParentalControlAgent/xpc-clients.plist"
/usr/bin/plutil -create xml1 "$XPC_MANIFEST"
/usr/libexec/PlistBuddy -c "Add :version integer 1" "$XPC_MANIFEST"
/usr/libexec/PlistBuddy -c "Add :clients array" "$XPC_MANIFEST"
add_xpc_client() {
  local index="$1"
  local identifier="$2"
  local installed_path="$3"
  local packaged_binary="$4"
  local digest
  digest="$(/usr/bin/shasum -a 256 "$packaged_binary" | /usr/bin/awk '{print $1}')"
  /usr/libexec/PlistBuddy -c "Add :clients:$index dict" "$XPC_MANIFEST"
  /usr/libexec/PlistBuddy -c "Add :clients:$index:identifier string $identifier" "$XPC_MANIFEST"
  /usr/libexec/PlistBuddy -c "Add :clients:$index:path string $installed_path" "$XPC_MANIFEST"
  /usr/libexec/PlistBuddy -c "Add :clients:$index:sha256 string $digest" "$XPC_MANIFEST"
}
add_xpc_client 0 com.bilalalissa.ParentalControlChild \
  "/Applications/Parental Control Child.app/Contents/MacOS/ParentalControlChild" \
  "$CHILD_APP/Contents/MacOS/ParentalControlChild"
add_xpc_client 1 com.bilalalissa.ParentalControlAgent.user \
  "/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlAgentUser" \
  "$CHILD_APP/Contents/Helpers/ParentalControlAgentUser"
add_xpc_client 2 com.bilalalissa.ParentalControlAgent.ctl \
  "/usr/local/bin/parental-control-agentctl" \
  "$CHILD_PAYLOAD/usr/local/bin/parental-control-agentctl"
add_xpc_client 3 com.bilalalissa.ParentalControlBrowserHost \
  "/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlBrowserHost" \
  "$CHILD_APP/Contents/Helpers/ParentalControlBrowserHost"
add_xpc_client 4 com.bilalalissa.ParentalControlSafari.Extension \
  "/Applications/Parental Control Safari.app/Contents/PlugIns/Parental Control Safari Extension.appex/Contents/MacOS/Parental Control Safari Extension" \
  "$CHILD_PAYLOAD/Applications/Parental Control Safari.app/Contents/PlugIns/Parental Control Safari Extension.appex/Contents/MacOS/Parental Control Safari Extension"
/bin/chmod 600 "$XPC_MANIFEST"
chmod 755 \
  "$CHILD_SCRIPTS/postinstall" \
  "$CHILD_SCRIPTS/preinstall" \
  "$CHILD_PAYLOAD/Library/PrivilegedHelperTools/com.bilalalissa.ParentalControlAgent.daemon" \
  "$CHILD_PAYLOAD/usr/local/bin/parental-control-agentctl"

retry "controller pkgbuild" /usr/bin/pkgbuild \
  --root "$CONTROLLER_PAYLOAD" \
  --component-plist "$CONTROLLER_COMPONENTS" \
  --identifier com.bilalalissa.ParentalControlController.component \
  --version 0.6.5.6 \
  --install-location / \
  --ownership recommended \
  "$COMPONENTS/ParentalControlController.pkg"

retry "child pkgbuild" /usr/bin/pkgbuild \
  --root "$CHILD_PAYLOAD" \
  --component-plist "$CHILD_COMPONENTS" \
  --scripts "$CHILD_SCRIPTS" \
  --identifier com.bilalalissa.ParentalControlChild.component \
  --version 0.6.5.6 \
  --install-location / \
  --ownership recommended \
  "$COMPONENTS/ParentalControlChild.pkg"

retry "productbuild" /usr/bin/productbuild \
  --distribution "$STAGING/Distribution.xml" \
  --resources "$RESOURCES" \
  --package-path "$COMPONENTS" \
  "$PKG"

/usr/sbin/pkgutil --expand-full "$PKG" "$EXPANDED"
test -f "$EXPANDED/Distribution"
test -d "$EXPANDED/ParentalControlController.pkg/Payload/Applications/Parental Control.app"
test -d "$EXPANDED/ParentalControlChild.pkg/Payload/Applications/Parental Control Child.app"
test -d "$EXPANDED/ParentalControlChild.pkg/Payload/Applications/Parental Control Safari.app"
test -x "$EXPANDED/ParentalControlChild.pkg/Payload/Applications/Parental Control Safari.app/Contents/PlugIns/Parental Control Safari Extension.appex/Contents/MacOS/Parental Control Safari Extension"
test -x "$EXPANDED/ParentalControlChild.pkg/Payload/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlBrowserHost"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Google/Chrome/NativeMessagingHosts/com.bilalalissa.parental_control.json"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Microsoft/Edge/NativeMessagingHosts/com.bilalalissa.parental_control.json"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Application Support/Mozilla/NativeMessagingHosts/com.bilalalissa.parental_control.json"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.bilalalissa.parental_control.json"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Application Support/ParentalControlAgent/xpc-clients.plist"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Application Support/ParentalControlBrowserExtension/Chromium/manifest.json"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Application Support/ParentalControlBrowserExtension/Chromium/service-worker.js"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Application Support/ParentalControlBrowserExtension/Chromium/website-policy.js"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Application Support/ParentalControlBrowserExtension/Chromium/blocked.html"
/usr/bin/plutil -lint "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Application Support/ParentalControlAgent/xpc-clients.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$EXPANDED/ParentalControlController.pkg/Payload/Applications/Parental Control.app/Contents/Info.plist" \
  | /usr/bin/grep -Fx "$VERSION" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$EXPANDED/ParentalControlChild.pkg/Payload/Applications/Parental Control Safari.app/Contents/Info.plist" \
  | /usr/bin/grep -Fx "$VERSION" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$EXPANDED/ParentalControlChild.pkg/Payload/Applications/Parental Control Child.app/Contents/Info.plist" \
  | /usr/bin/grep -Fx "$VERSION" >/dev/null
rm -rf -- "$EXPANDED"
/usr/bin/shasum -a 256 "$PKG" > "$CHECKSUM"
rm -f -- \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.5.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.5.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.4.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.4.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.2.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.2.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.3.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.3.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.1.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.5-rc.1.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.4-rc.4.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.4-rc.4.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.4-rc.3.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.4-rc.3.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.4-rc.2.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.4-rc.2.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.1-rc.4.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.1-rc.4.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.1-rc.2.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.1-rc.2.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.1-rc.3.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.1-rc.3.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.1-rc.1.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.1-rc.1.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.9.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.9.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.8.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.8.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.8.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.8.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.7.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.7.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.7.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.7.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.6.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.6.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.6.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.6.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.5.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.5.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.5.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.5.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.4.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.4.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.4.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.4.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.3.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.3.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.3.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.3.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.2.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.2.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.2.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.2.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.1.pkg" \
  "$RC_DIR/ParentalControlSystem-0.6.0-rc.1.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.1.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.6.0-rc.1.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.9.pkg" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.9.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.8.pkg" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.8.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.8.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.8.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.7.pkg" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.7.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.7.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.7.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.6.pkg" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.6.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.6.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.6.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.5.pkg" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.5.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.5.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.5.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.4.pkg" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.4.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.4.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.4.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.3.pkg" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.3.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.3.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.3.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.1.pkg" \
  "$RC_DIR/ParentalControlSystem-0.5.0-rc.1.pkg.sha256" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.1.zip" \
  "$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.1.zip.sha256" \
  "$RC_DIR/ParentalControlSystem-0.4.0-rc.5.pkg" \
  "$RC_DIR/ParentalControlSystem-0.4.0-rc.5.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.4.0-rc.3.pkg" \
  "$RC_DIR/ParentalControlSystem-0.4.0-rc.3.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.4.0-rc.2.pkg" \
  "$RC_DIR/ParentalControlSystem-0.4.0-rc.2.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.4.0-rc.1.pkg" \
  "$RC_DIR/ParentalControlSystem-0.4.0-rc.1.pkg.sha256" \
  "$RC_DIR/ParentalControlSystem-0.3.0-rc.2.pkg" \
  "$RC_DIR/ParentalControlSystem-0.3.0-rc.2.pkg.sha256" \
  "$RC_DIR/ParentalControlChild-0.3.0-rc.1-universal.pkg" \
  "$RC_DIR/ParentalControlChild-0.3.0-rc.1-universal.pkg.sha256"
rm -rf -- "$STAGING"
echo "$PKG"
