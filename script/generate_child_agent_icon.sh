#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_SVG="$ROOT_DIR/packages/design-assets/child-agent-icon.svg"
OUTPUT_ICNS="${1:-$ROOT_DIR/.artifacts/derived-data/stage-04/ChildAgentIcon.icns}"
WORK_DIR="$ROOT_DIR/.artifacts/derived-data/stage-04/icon-generation"
ICONSET_DIR="$WORK_DIR/ChildAgentIcon.iconset"
rm -rf -- "$WORK_DIR"
mkdir -p "$ICONSET_DIR" "$(dirname "$OUTPUT_ICNS")"
/usr/bin/qlmanage -t -s 1024 -o "$WORK_DIR" "$SOURCE_SVG" >/dev/null 2>&1
RENDERED="$WORK_DIR/$(basename "$SOURCE_SVG").png"
test -f "$RENDERED"
for specification in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  read -r pixels filename <<<"$specification"
  /usr/bin/sips -z "$pixels" "$pixels" "$RENDERED" --out "$ICONSET_DIR/$filename" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
rm -rf -- "$WORK_DIR"
echo "$OUTPUT_ICNS"
