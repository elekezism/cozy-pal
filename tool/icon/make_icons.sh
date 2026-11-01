#!/usr/bin/env bash
# Renders the web icons from mochi_icon.svg (needs ImageMagick 7).
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p web/icons
for s in 192 512; do
  magick -background none -density 384 tool/icon/mochi_icon.svg -resize ${s}x${s} web/icons/Icon-$s.png
  cp web/icons/Icon-$s.png web/icons/Icon-maskable-$s.png
done
magick -background none -density 96 tool/icon/mochi_icon.svg -resize 48x48 web/favicon.png
