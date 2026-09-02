#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-Release}"
if [[ "$CONFIGURATION" != "Release" && "$CONFIGURATION" != "Debug" ]]; then echo "usage: $0 [Debug|Release]" >&2; exit 2; fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACKAGE_DIR="$ROOT_DIR/agents/endpoint-macos"
DERIVED="$ROOT_DIR/.artifacts/derived-data/stage-06a"
ARCH_ROOT="$DERIVED/architectures"
DIST="$ROOT_DIR/dist"
APP="$DIST/Parental Control Child.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
HELPERS="$CONTENTS/Helpers"
RESOURCES="$CONTENTS/Resources"
MODE="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"
VERSION="0.6.1-rc.2"
COMMIT="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD)"
SIGN_IDENTITY="${MACOS_SIGNING_IDENTITY:--}"
PRODUCTS=(ParentalControlChild ParentalControlAgentDaemon ParentalControlAgentUser ParentalControlAgentCtl ParentalControlBrowserHost)

mkdir -p "$DERIVED/module-cache" "$DERIVED/cache" "$DERIVED/config" "$DERIVED/security"
for architecture in arm64 x86_64; do
  scratch="$ARCH_ROOT/$architecture"
  CLANG_MODULE_CACHE_PATH="$DERIVED/module-cache" SWIFT_MODULE_CACHE_PATH="$DERIVED/module-cache" \
    swift build --disable-sandbox --package-path "$PACKAGE_DIR" \
      --cache-path "$DERIVED/cache" --config-path "$DERIVED/config" --security-path "$DERIVED/security" \
      --scratch-path "$scratch" --triple "$architecture-apple-macosx14.0" --configuration "$MODE" --jobs 2
done

rm -rf -- "$APP"
mkdir -p "$MACOS" "$HELPERS" "$RESOURCES"
for product in "${PRODUCTS[@]}"; do
  arm_binary="$(find "$ARCH_ROOT/arm64" -type f -path "*/$MODE/$product" -perm +111 -print -quit)"
  intel_binary="$(find "$ARCH_ROOT/x86_64" -type f -path "*/$MODE/$product" -perm +111 -print -quit)"
  if [[ -z "$arm_binary" || -z "$intel_binary" ]]; then echo "Missing architecture build for $product" >&2; exit 1; fi
  destination="$HELPERS/$product"
  if [[ "$product" == "ParentalControlChild" ]]; then destination="$MACOS/$product"; fi
  /usr/bin/lipo -create "$arm_binary" "$intel_binary" -output "$destination"
  chmod 755 "$destination"
  archs="$(/usr/bin/lipo -archs "$destination")"
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || { echo "$product is not universal: $archs" >&2; exit 1; }
done

cp "$ROOT_DIR/agents/endpoint-macos/Installer/uninstall.sh" "$RESOURCES/uninstall.sh"
chmod 755 "$RESOURCES/uninstall.sh"
ICON="$DERIVED/ChildAgentIcon.icns"
if [[ ! -f "$ICON" ]]; then "$ROOT_DIR/script/generate_child_agent_icon.sh" "$ICON" >/dev/null; fi
cp "$ICON" "$RESOURCES/ChildAgentIcon.icns"

/usr/bin/plutil -create xml1 "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ParentalControlChild" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.bilalalissa.ParentalControlChild" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string 'Parental Control Child'" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 'Parental Control Child'" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 6102" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :BuildCommit string $COMMIT" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ChildAgentIcon" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.utilities" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'Connect visibly to the parent controller on your local network.'" "$CONTENTS/Info.plist"

/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier com.bilalalissa.ParentalControlAgent.daemon "$HELPERS/ParentalControlAgentDaemon"
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier com.bilalalissa.ParentalControlAgent.user "$HELPERS/ParentalControlAgentUser"
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier com.bilalalissa.ParentalControlAgent.ctl "$HELPERS/ParentalControlAgentCtl"
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier com.bilalalissa.ParentalControlBrowserHost "$HELPERS/ParentalControlBrowserHost"
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier com.bilalalissa.ParentalControlChild "$MACOS/ParentalControlChild"
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier com.bilalalissa.ParentalControlChild "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

rm -rf -- "$ARCH_ROOT/arm64" "$ARCH_ROOT/x86_64"
echo "$APP"
