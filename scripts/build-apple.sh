#!/usr/bin/env bash
# Compiles the app and the system extension without signing: the gate's proof
# that the Swift side builds and links Libbox.xcframework. A signed build for
# installing the extension needs apple/Config/Local.xcconfig (see the example).
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"
# Rebuilds the Go framework only when its inputs changed (content hash, see
# build-core.sh), so the Swift build never links a stale core.
scripts/build-core.sh
scripts/fetch-sparkle.sh
scripts/gen-xcodeproj.sh
scripts/check-apple-config.sh
mkdir -p .build/logs
log=.build/logs/build-apple.log
if ! xcodebuild -project apple/Parallux.xcodeproj -scheme Parallux -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode -quiet \
  CODE_SIGNING_ALLOWED=NO build >"$log" 2>&1; then
  grep -E "error:|Undefined symbols|ld: " "$log" | head -40 >&2 || tail -40 "$log" >&2
  exit 1
fi
echo "built .build/xcode/Build/Products/Debug/Parallux.app; log: $log"
