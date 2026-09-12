#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT_DIR/browser-extensions/webextension"
SAFARI_SOURCE="$ROOT_DIR/browser-extensions/safari"
ICON_SOURCE="$ROOT_DIR/packages/design-assets/browser-extension-icon.svg"
STAGING="$ROOT_DIR/.artifacts/package-staging/stage-06e-safari"
WEB_EXTENSION="$STAGING/web-extension"
PROJECT_ROOT="$STAGING/project"
DERIVED_DATA="$ROOT_DIR/.artifacts/derived-data/stage-06e-safari"
OUTPUT="$ROOT_DIR/dist/Parental Control Safari.app"
PROJECT="$PROJECT_ROOT/Parental Control Safari/Parental Control Safari.xcodeproj"
APP_SOURCE="$PROJECT_ROOT/Parental Control Safari/Parental Control Safari"
EXTENSION_SOURCE="$PROJECT_ROOT/Parental Control Safari/Parental Control Safari Extension"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/Parental Control Safari.app"

rm -rf -- "$STAGING" "$DERIVED_DATA" "$OUTPUT"
mkdir -p "$WEB_EXTENSION/icons" "$PROJECT_ROOT" "$ROOT_DIR/dist"
cp "$SOURCE/service-worker.js" "$SOURCE/website-policy.js" "$SOURCE/blocked.html" \
  "$SOURCE/popup.html" "$SOURCE/popup.js" "$WEB_EXTENSION/"
node "$ROOT_DIR/script/safari_manifest.mjs" "$SOURCE/manifest.json" "$WEB_EXTENSION/manifest.json"

ICON_RENDER="$STAGING/icon-render"
mkdir -p "$ICON_RENDER"
/usr/bin/qlmanage -t -s 1024 -o "$ICON_RENDER" "$ICON_SOURCE" >/dev/null 2>&1
RENDERED="$ICON_RENDER/$(basename "$ICON_SOURCE").png"
test -f "$RENDERED"
for size in 16 32 48 128; do
  /usr/bin/sips -z "$size" "$size" "$RENDERED" --out "$WEB_EXTENSION/icons/icon$size.png" >/dev/null
done

xcrun safari-web-extension-converter "$WEB_EXTENSION" \
  --project-location "$PROJECT_ROOT" \
  --app-name "Parental Control Safari" \
  --bundle-identifier "com.bilalalissa.ParentalControlSafari" \
  --copy-resources --swift --macos-only --no-open --no-prompt --force >/dev/null

cp "$SAFARI_SOURCE/SafariWebExtensionHandler.swift" \
  "$EXTENSION_SOURCE/SafariWebExtensionHandler.swift"
mkdir -p "$APP_SOURCE/Resources"
cp "$RENDERED" "$APP_SOURCE/Resources/Icon.png"

# The converter derives the containing identifier from the display name in current Xcode.
# Normalize only that generated value; the extension identifier is already exact.
/usr/bin/sed -i '' \
  's/com\.bilalalissa\.Parental-Control-Safari/com.bilalalissa.ParentalControlSafari/g' \
  "$PROJECT/project.pbxproj"

xcodebuild -project "$PROJECT" -scheme "Parental Control Safari" \
  -configuration Release -derivedDataPath "$DERIVED_DATA" \
  -jobs 2 CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  MARKETING_VERSION=0.6.5-rc.8 CURRENT_PROJECT_VERSION=6508 \
  MACOSX_DEPLOYMENT_TARGET=14.0 ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" build >/dev/null

APPEX="$BUILT_APP/Contents/PlugIns/Parental Control Safari Extension.appex"
/usr/bin/codesign --force --sign - --options runtime \
  --entitlements "$SAFARI_SOURCE/SafariExtension.entitlements" "$APPEX"
/usr/bin/codesign --force --sign - --options runtime "$BUILT_APP"
/usr/bin/codesign --verify --deep --strict "$BUILT_APP"
/usr/bin/lipo -archs "$BUILT_APP/Contents/MacOS/Parental Control Safari" \
  | /usr/bin/grep -Eq 'arm64.*x86_64|x86_64.*arm64'
/usr/bin/lipo -archs "$APPEX/Contents/MacOS/Parental Control Safari Extension" \
  | /usr/bin/grep -Eq 'arm64.*x86_64|x86_64.*arm64'
cp -R "$BUILT_APP" "$OUTPUT"
rm -rf -- "$STAGING" "$DERIVED_DATA"
echo "$OUTPUT"
