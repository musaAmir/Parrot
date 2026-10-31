#!/bin/bash
# Export macOS icon slots from the full-resolution artwork, retaining transparency.
set -euo pipefail
cd "$(dirname "$0")/.."
MASTER="Artwork/ParrotIcon.png"
DESTINATION="Parrot/Assets.xcassets/AppIcon.appiconset"
for SIZE in 16 32 128 256 512; do
  for SCALE in 1 2; do
    PIXELS=$((SIZE * SCALE))
    SUFFIX=""
    [[ "$SCALE" != 2 ]] || SUFFIX="@2x"
    sips --resampleHeightWidth "$PIXELS" "$PIXELS" "$MASTER" \
      --out "$DESTINATION/icon_${SIZE}x${SIZE}${SUFFIX}.png" >/dev/null
  done
done
sips --resampleHeightWidth 1024 1024 "$MASTER" --out docs/assets/app-icon.png >/dev/null
echo 'Exported all 10 macOS icon sizes and the website icon.'
