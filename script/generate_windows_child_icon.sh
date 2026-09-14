#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
source_svg="$repo_root/packages/design-assets/child-agent-icon.svg"
target_dir="$repo_root/agents/endpoint-windows/assets"
temporary_png="$target_dir/ParentalControlChild-256.png"
target_ico="$target_dir/ParentalControlChild.ico"

mkdir -p "$target_dir"
rsvg-convert --width 256 --height 256 --output "$temporary_png" "$source_svg"
ffmpeg -hide_banner -loglevel error -y -i "$temporary_png" -frames:v 1 "$target_ico"
rm "$temporary_png"
test -s "$target_ico"
