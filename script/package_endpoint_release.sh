#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="0.5.0-rc.2"
STAGING="$ROOT_DIR/.artifacts/package-staging/stage-05"
COMPONENTS="$STAGING/component-packages"
CHILD_PAYLOAD="$STAGING/child-payload"
CHILD_SCRIPTS="$STAGING/child-scripts"
CONTROLLER_PAYLOAD="$STAGING/controller-payload"
RESOURCES="$STAGING/resources"
EXPANDED="$STAGING/expanded"
RC_DIR="$ROOT_DIR/.artifacts/release-candidate"
PKG="$RC_DIR/ParentalControlSystem-$VERSION.pkg"
CHECKSUM="$PKG.sha256"
CHILD_APP="$ROOT_DIR/dist/Parental Control Child.app"
CONTROLLER_APP="$ROOT_DIR/dist/ParentalControlController.app"

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
  "$CHILD_PAYLOAD/usr/local/bin" \
  "$CHILD_SCRIPTS" \
  "$CONTROLLER_PAYLOAD/Applications" \
  "$RESOURCES" \
  "$RC_DIR"

cp -R "$CONTROLLER_APP" "$CONTROLLER_PAYLOAD/Applications/Parental Control.app"
cp -R "$CHILD_APP" "$CHILD_PAYLOAD/Applications/Parental Control Child.app"
cp "$CHILD_APP/Contents/Helpers/ParentalControlAgentDaemon" "$CHILD_PAYLOAD/Library/PrivilegedHelperTools/com.bilalalissa.ParentalControlAgent.daemon"
cp "$CHILD_APP/Contents/Helpers/ParentalControlAgentCtl" "$CHILD_PAYLOAD/usr/local/bin/parental-control-agentctl"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/com.bilalalissa.ParentalControlAgent.daemon.plist" "$CHILD_PAYLOAD/Library/LaunchDaemons/"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/com.bilalalissa.ParentalControlAgent.user.plist" "$CHILD_PAYLOAD/Library/LaunchAgents/"
cp "$ROOT_DIR/browser-extensions/webextension/native-host-manifest.json" \
  "$CHILD_PAYLOAD/Library/Google/Chrome/NativeMessagingHosts/com.bilalalissa.parental_control.json"
cp "$ROOT_DIR/browser-extensions/webextension/native-host-manifest.json" \
  "$CHILD_PAYLOAD/Library/Microsoft/Edge/NativeMessagingHosts/com.bilalalissa.parental_control.json"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/postinstall" "$CHILD_SCRIPTS/postinstall"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/Distribution.xml" "$STAGING/Distribution.xml"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/Welcome.html" "$RESOURCES/Welcome.html"
chmod 755 \
  "$CHILD_SCRIPTS/postinstall" \
  "$CHILD_PAYLOAD/Library/PrivilegedHelperTools/com.bilalalissa.ParentalControlAgent.daemon" \
  "$CHILD_PAYLOAD/usr/local/bin/parental-control-agentctl"

retry "controller pkgbuild" /usr/bin/pkgbuild \
  --root "$CONTROLLER_PAYLOAD" \
  --identifier com.bilalalissa.ParentalControlController.component \
  --version 0.5.0.2 \
  --install-location / \
  --ownership recommended \
  "$COMPONENTS/ParentalControlController.pkg"

retry "child pkgbuild" /usr/bin/pkgbuild \
  --root "$CHILD_PAYLOAD" \
  --scripts "$CHILD_SCRIPTS" \
  --identifier com.bilalalissa.ParentalControlChild.component \
  --version 0.5.0.2 \
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
test -x "$EXPANDED/ParentalControlChild.pkg/Payload/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlBrowserHost"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Google/Chrome/NativeMessagingHosts/com.bilalalissa.parental_control.json"
test -f "$EXPANDED/ParentalControlChild.pkg/Payload/Library/Microsoft/Edge/NativeMessagingHosts/com.bilalalissa.parental_control.json"
rm -rf -- "$EXPANDED"
/usr/bin/shasum -a 256 "$PKG" > "$CHECKSUM"
rm -f -- \
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
