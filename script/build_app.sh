#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-Release}"
if [[ "$CONFIGURATION" != "Debug" && "$CONFIGURATION" != "Release" ]]; then
  echo "usage: $0 [Debug|Release]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACKAGE_DIR="$ROOT_DIR/apps/controller-macos"
DERIVED_DIR="$ROOT_DIR/.artifacts/derived-data/stage-06"
SWIFTPM_DIR="$DERIVED_DIR/swiftpm"
MODULE_CACHE="$DERIVED_DIR/module-cache"
CACHE_DIR="$DERIVED_DIR/swiftpm-cache"
CONFIG_DIR="$DERIVED_DIR/swiftpm-config"
SECURITY_DIR="$DERIVED_DIR/swiftpm-security"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ParentalControlController"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_HELPERS="$APP_CONTENTS/Helpers"
HUB_BINARY="$APP_HELPERS/ParentalControlHub"
MOCK_BINARY="$APP_HELPERS/ParentalControlMockAgent"
VERSION="0.6.0-rc.6"
COMMIT="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD)"
SIGN_IDENTITY="${MACOS_SIGNING_IDENTITY:--}"

mkdir -p "$MODULE_CACHE" "$CACHE_DIR" "$CONFIG_DIR" "$SECURITY_DIR"

SWIFT_ARGS=(
  --disable-sandbox
  --package-path "$PACKAGE_DIR"
  --cache-path "$CACHE_DIR"
  --config-path "$CONFIG_DIR"
  --security-path "$SECURITY_DIR"
  --scratch-path "$SWIFTPM_DIR"
  --triple arm64-apple-macosx14.0
  --jobs 2
)

if [[ "$CONFIGURATION" == "Release" ]]; then
  BUILD_MODE="release"
else
  BUILD_MODE="debug"
fi

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swift build "${SWIFT_ARGS[@]}" --configuration "$BUILD_MODE"

BIN_DIR="$(
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swift build "${SWIFT_ARGS[@]}" --configuration "$BUILD_MODE" --show-bin-path
)"
BUILD_BINARY="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" || ! -x "$BIN_DIR/ParentalControlHub" || ! -x "$BIN_DIR/ParentalControlMockAgent" ]]; then
  echo "Built executable not found: $BUILD_BINARY" >&2
  exit 1
fi

rm -rf -- "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_HELPERS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BIN_DIR/ParentalControlHub" "$HUB_BINARY"
cp "$BIN_DIR/ParentalControlMockAgent" "$MOCK_BINARY"
chmod +x "$APP_BINARY" "$HUB_BINARY" "$MOCK_BINARY"
CONTROLLER_ICON="$DERIVED_DIR/ControllerIcon.icns"
if [[ ! -f "$CONTROLLER_ICON" ]]; then
  "$ROOT_DIR/script/generate_controller_icon.sh" "$CONTROLLER_ICON" >/dev/null
fi
cp "$CONTROLLER_ICON" "$APP_RESOURCES/ControllerIcon.icns"

/usr/bin/plutil -create xml1 "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.bilalalissa.ParentalControlController" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string 'Parental Control'" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 'Parental Control'" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 6006" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :BuildCommit string $COMMIT" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :ProtocolVersion string 1.0" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ControllerIcon" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.utilities" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'Pair with visible family devices directly on your local network.'" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSBonjourServices array" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSBonjourServices:0 string '_parental-control._tcp'" "$APP_CONTENTS/Info.plist"

/usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

ARCHS="$(/usr/bin/lipo -archs "$APP_BINARY")"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "Unexpected app architecture: $ARCHS" >&2
  exit 1
fi

echo "$APP_BUNDLE"
