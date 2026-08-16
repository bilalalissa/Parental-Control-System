#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT_DIR/browser-extensions/webextension"
ICON_SOURCE="$ROOT_DIR/packages/design-assets/browser-extension-icon.svg"
STAGING="$ROOT_DIR/.artifacts/package-staging/stage-05-extension"
PACKAGE_ROOT="$STAGING/ParentalControlBrowserSharing"
RENDER_ROOT="$STAGING/icon-render"
RC_DIR="$ROOT_DIR/.artifacts/release-candidate"
ZIP="$RC_DIR/ParentalControlBrowserSharing-0.5.0-rc.2.zip"
CHECKSUM="$ZIP.sha256"
PACKAGE_LIST="$STAGING/package-files.txt"

rm -rf -- "$STAGING"
rm -f -- "$ZIP" "$CHECKSUM"
mkdir -p "$PACKAGE_ROOT/icons" "$RENDER_ROOT" "$RC_DIR"
cp "$SOURCE/manifest.json" "$PACKAGE_ROOT/manifest.json"
cp "$SOURCE/service-worker.js" "$PACKAGE_ROOT/service-worker.js"
cp "$SOURCE/popup.html" "$PACKAGE_ROOT/popup.html"
cp "$SOURCE/popup.js" "$PACKAGE_ROOT/popup.js"

/usr/bin/qlmanage -t -s 1024 -o "$RENDER_ROOT" "$ICON_SOURCE" >/dev/null 2>&1
RENDERED="$RENDER_ROOT/$(basename "$ICON_SOURCE").png"
test -f "$RENDERED"
for size in 16 32 48 128; do
  /usr/bin/sips -z "$size" "$size" "$RENDERED" --out "$PACKAGE_ROOT/icons/icon$size.png" >/dev/null
done

node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
  "$PACKAGE_ROOT/manifest.json"
node --check "$PACKAGE_ROOT/service-worker.js"
node --check "$PACKAGE_ROOT/popup.js"
(
  cd "$STAGING"
  /usr/bin/zip -X -q -r "$ZIP" "$(basename "$PACKAGE_ROOT")"
)
/usr/bin/unzip -t "$ZIP" >/dev/null
/usr/bin/unzip -Z1 "$ZIP" > "$PACKAGE_LIST"
test "$(/usr/bin/grep -E -c '^ParentalControlBrowserSharing/(manifest.json|service-worker.js|popup.html|popup.js|icons/icon(16|32|48|128)\.png)$' "$PACKAGE_LIST")" -eq 8
if /usr/bin/grep -E -i '\.(pem|key|p12|pfx)$' "$PACKAGE_LIST" >/dev/null; then
  echo "Refusing an extension package containing signing secrets." >&2
  exit 1
fi
/usr/bin/shasum -a 256 "$ZIP" > "$CHECKSUM"
rm -rf -- "$STAGING"
echo "$ZIP"
