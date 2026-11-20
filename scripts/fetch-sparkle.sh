#!/usr/bin/env bash
# Puts Sparkle 2.10.1 (PLAN decision 19) into apple/Frameworks/Sparkle.xcframework
# and its tools (generate_keys, generate_appcast, sign_update) into
# .build/sparkle/bin, from the release asset Sparkle publishes for SwiftPM.
#
# Why not an SPM package dependency: xcodebuild's binary-artifact download
# hung indefinitely on this machine while curl fetched the same URL in 3 s,
# and the gate must not depend on it.
# The asset is checked against its pinned sha256 (GitHub's digest for it,
# gh api repos/sparkle-project/Sparkle/releases/tags/2.10.1, 2026-11-19),
# which is also the checksum in Sparkle's own Package.swift.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

version=2.10.1
sha256=4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a
stamp=.build/sparkle/version

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$version" ] && [ -d apple/Frameworks/Sparkle.xcframework ] && [ -x .build/sparkle/bin/generate_appcast ]; then
  exit 0
fi

mkdir -p .build/sparkle apple/Frameworks
zip=".build/sparkle/Sparkle-for-Swift-Package-Manager-$version.zip"
if [ ! -f "$zip" ] || [ "$(shasum -a 256 "$zip" | cut -d' ' -f1)" != "$sha256" ]; then
  # Why 120 s: the asset is 10 MB; a stalled download must fail, not hang the gate.
  curl -fsSL --max-time 120 -o "$zip.part" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-for-Swift-Package-Manager.zip"
  mv "$zip.part" "$zip"
fi
if [ "$(shasum -a 256 "$zip" | cut -d' ' -f1)" != "$sha256" ]; then
  echo "FAIL Sparkle $version asset does not match its pinned sha256" >&2
  rm -f "$zip"
  exit 1
fi

rm -rf apple/Frameworks/Sparkle.xcframework .build/sparkle/bin .build/sparkle/unpacked
unzip -q "$zip" -d .build/sparkle/unpacked
mv .build/sparkle/unpacked/Sparkle.xcframework apple/Frameworks/
mv .build/sparkle/unpacked/bin .build/sparkle/bin
rm -rf .build/sparkle/unpacked
echo "$version" >"$stamp"
echo "fetched Sparkle $version"
