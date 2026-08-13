#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_NAME="ParentalControlController"
DISPLAY_NAME="Parental Control"
VERSION="0.2.0-rc.1"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
STAGING_DIR="$ROOT_DIR/.artifacts/package-staging/stage-02"
RC_DIR="$ROOT_DIR/.artifacts/release-candidate"
DMG_NAME="ParentalControlController-$VERSION-arm64.dmg"
DMG_PATH="$RC_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
PREVIOUS_DMG_PATH="$RC_DIR/ParentalControlController-0.1.0-rc.2-arm64.dmg"
PREVIOUS_CHECKSUM_PATH="$PREVIOUS_DMG_PATH.sha256"

"$ROOT_DIR/script/build_app.sh" Release >/dev/null

rm -rf -- "$STAGING_DIR"
rm -f -- "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGING_DIR" "$RC_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$DISPLAY_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null
/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null
/usr/bin/shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

rm -f -- "$PREVIOUS_DMG_PATH" "$PREVIOUS_CHECKSUM_PATH"

rm -rf -- "$STAGING_DIR"

echo "$DMG_PATH"
