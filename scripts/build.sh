#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_app="${1:-$repo_root/build/Separate.app}"
build_temp="$(mktemp -d "${TMPDIR:-/tmp}/separate-build.XXXXXX")"
trap 'rm -rf "$build_temp"' EXIT
module_cache="${TMPDIR:-/tmp}/separate-swift-module-cache"
mkdir -p "$module_cache" "$output_app/Contents/MacOS" "$output_app/Contents/Resources"

for architecture in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -warnings-as-errors -module-name Separate \
    -target "$architecture-apple-macosx13.0" -module-cache-path "$module_cache" \
    -file-prefix-map "$repo_root"=. -debug-prefix-map "$repo_root"=. \
    -framework AppKit -framework PDFKit -framework UniformTypeIdentifiers \
    "$repo_root/Sources/main.swift" -o "$build_temp/Separate-$architecture"
done
xcrun lipo -create "$build_temp/Separate-arm64" "$build_temp/Separate-x86_64" \
  -output "$output_app/Contents/MacOS/Separate"

# Derive standard macOS icon sizes from the committed high-resolution artwork.
iconset="$build_temp/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$repo_root/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$repo_root/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$output_app/Contents/Resources/AppIcon.icns"
cp "$repo_root/Resources/Info.plist" "$output_app/Contents/Info.plist"
plutil -lint "$output_app/Contents/Info.plist"
codesign --force --sign - "$output_app"
codesign --verify --deep --strict "$output_app"
xcrun lipo "$output_app/Contents/MacOS/Separate" -verify_arch arm64 x86_64
echo "Built universal app: $output_app"
