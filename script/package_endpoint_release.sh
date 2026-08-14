#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="0.3.0-rc.1"
STAGING="$ROOT_DIR/.artifacts/package-staging/stage-03"
PAYLOAD="$STAGING/payload"
SCRIPTS="$STAGING/scripts"
EXPANDED="$STAGING/expanded"
RC_DIR="$ROOT_DIR/.artifacts/release-candidate"
PKG="$RC_DIR/ParentalControlChild-$VERSION-universal.pkg"
CHECKSUM="$PKG.sha256"
APP="$ROOT_DIR/dist/Parental Control Child.app"

"$ROOT_DIR/script/build_endpoint_app.sh" Release >/dev/null
rm -rf -- "$STAGING"
rm -f -- "$PKG" "$CHECKSUM"
mkdir -p "$PAYLOAD/Applications" "$PAYLOAD/Library/PrivilegedHelperTools" "$PAYLOAD/Library/LaunchDaemons" "$PAYLOAD/Library/LaunchAgents" "$PAYLOAD/usr/local/bin" "$SCRIPTS" "$RC_DIR"
cp -R "$APP" "$PAYLOAD/Applications/Parental Control Child.app"
cp "$APP/Contents/Helpers/ParentalControlAgentDaemon" "$PAYLOAD/Library/PrivilegedHelperTools/com.bilalalissa.ParentalControlAgent.daemon"
cp "$APP/Contents/Helpers/ParentalControlAgentCtl" "$PAYLOAD/usr/local/bin/parental-control-agentctl"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/com.bilalalissa.ParentalControlAgent.daemon.plist" "$PAYLOAD/Library/LaunchDaemons/"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/com.bilalalissa.ParentalControlAgent.user.plist" "$PAYLOAD/Library/LaunchAgents/"
cp "$ROOT_DIR/agents/endpoint-macos/Installer/postinstall" "$SCRIPTS/postinstall"
chmod 755 "$SCRIPTS/postinstall" "$PAYLOAD/Library/PrivilegedHelperTools/com.bilalalissa.ParentalControlAgent.daemon" "$PAYLOAD/usr/local/bin/parental-control-agentctl"

for attempt in 1 2 3; do
  rm -f -- "$PKG"
  if /usr/bin/pkgbuild --root "$PAYLOAD" --scripts "$SCRIPTS" --identifier com.bilalalissa.ParentalControlChild.pkg --version 0.3.0 --install-location / --ownership recommended "$PKG" >/dev/null; then break; fi
  if [[ "$attempt" == 3 ]]; then echo "pkgbuild failed after three attempts." >&2; exit 1; fi
  echo "pkgbuild attempt $attempt failed; retrying in 2 seconds." >&2
  sleep 2
done

/usr/sbin/pkgutil --expand-full "$PKG" "$EXPANDED"
test -f "$EXPANDED/Bom" || test -d "$EXPANDED/Payload"
rm -rf -- "$EXPANDED"
/usr/bin/shasum -a 256 "$PKG" > "$CHECKSUM"
rm -f -- "$RC_DIR/ParentalControlController-0.2.0-rc.1-arm64.dmg" "$RC_DIR/ParentalControlController-0.2.0-rc.1-arm64.dmg.sha256"
rm -rf -- "$STAGING"
echo "$PKG"
