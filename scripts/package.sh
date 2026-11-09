#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$repo_root/build/Separate.app}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
dist="$repo_root/dist"
mkdir -p "$dist"
codesign --verify --deep --strict "$app"
archive="Separate-$version-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/$archive"
(cd "$dist" && shasum -a 256 "$archive" > SHA256SUMS.txt)
echo "Packaged: $dist/$archive"
