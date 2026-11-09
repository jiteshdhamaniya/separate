#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$repo_root/build/Separate.app}"
test_temp="$(mktemp -d "${TMPDIR:-/tmp}/separate-tests.XXXXXX")"
trap 'rm -rf "$test_temp"' EXIT
module_cache="${TMPDIR:-/tmp}/separate-swift-module-cache"
mkdir -p "$module_cache"
xcrun swiftc -module-cache-path "$module_cache" "$repo_root/Tests/make-fixtures.swift" -o "$test_temp/make-fixtures"
"$test_temp/make-fixtures" "$test_temp/fixtures"
(cd "$test_temp/fixtures" && shasum -a 256 ./* > "$test_temp/before.sha256")
"$app/Contents/MacOS/Separate" --self-test "$test_temp/fixtures"
(cd "$test_temp/fixtures" && shasum -a 256 -c "$test_temp/before.sha256")
plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict "$app"
xcrun lipo "$app/Contents/MacOS/Separate" -verify_arch arm64 x86_64
test -s "$app/Contents/Resources/AppIcon.icns"
echo 'PASS: universal package, signature, icon and unchanged input files'
