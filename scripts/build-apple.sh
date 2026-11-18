#!/usr/bin/env bash
# Compiles the app and the system extension without signing: the gate's proof
# that the Swift side builds and links Libbox.xcframework. A signed build for
# installing the extension needs apple/Config/Local.xcconfig (see the example).
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"
# Rebuild the Go framework when it is missing or older than the Go sources
# it is built from, so the Swift build never links a stale core.
stamp="apple/Frameworks/Libbox.xcframework/Info.plist"
if [ ! -f "$stamp" ] || [ -n "$(find go.mod go.sum core -newer "$stamp" -print -quit)" ]; then
  scripts/build-core.sh
fi
scripts/gen-xcodeproj.sh
xcodebuild -project apple/Parallux.xcodeproj -scheme Parallux -configuration Debug \
  -derivedDataPath .build/xcode -quiet \
  CODE_SIGNING_ALLOWED=NO build
