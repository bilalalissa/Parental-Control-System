#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_SVG="$ROOT_DIR/packages/design-assets/controller-icon.svg"
OUTPUT_ICNS="${1:-$ROOT_DIR/.artifacts/derived-data/stage-06a/ControllerIcon.icns}"
WORK_DIR="$ROOT_DIR/.artifacts/derived-data/stage-06a/controller-icon-generation"
ICONSET_DIR="$WORK_DIR/ControllerIcon.iconset"

if [[ ! -f "$SOURCE_SVG" ]]; then
  echo "Missing canonical icon source: $SOURCE_SVG" >&2
  exit 1
fi

rm -rf -- "$WORK_DIR"
mkdir -p "$ICONSET_DIR" "$(dirname "$OUTPUT_ICNS")"

/usr/bin/qlmanage -t -s 1024 -o "$WORK_DIR" "$SOURCE_SVG" >/dev/null 2>&1
RENDERED_PNG="$WORK_DIR/$(basename "$SOURCE_SVG").png"
if [[ ! -f "$RENDERED_PNG" ]]; then
  echo "Quick Look did not render the controller icon." >&2
  exit 1
fi

create_size() {
  local pixels="$1"
  local filename="$2"
  /usr/bin/sips -z "$pixels" "$pixels" "$RENDERED_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
}

create_size 16 icon_16x16.png
create_size 32 icon_16x16@2x.png
create_size 32 icon_32x32.png
create_size 64 icon_32x32@2x.png
create_size 128 icon_128x128.png
create_size 256 icon_128x128@2x.png
create_size 256 icon_256x256.png
create_size 512 icon_256x256@2x.png
create_size 512 icon_512x512.png
create_size 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
rm -rf -- "$WORK_DIR"

echo "$OUTPUT_ICNS"
