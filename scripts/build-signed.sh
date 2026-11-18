#!/usr/bin/env bash
# Signed Debug build for installing the system extension on this Mac.
# Needs apple/Config/Local.xcconfig (copy Local.xcconfig.example). With an
# Apple Development certificate, xcodebuild registers the App IDs, the App
# Group and this Mac on first run (-allowProvisioning*); the author approved
# that on 2026-11-18 (PLAN decision 15).
#   scripts/build-signed.sh            build into .build/xcode-signed
#   scripts/build-signed.sh --install  also copy to /Applications (where macOS
#                                      requires the app to be to activate it)
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"
if [ ! -f apple/Config/Local.xcconfig ]; then
  echo "apple/Config/Local.xcconfig is missing; copy Local.xcconfig.example and set DEVELOPMENT_TEAM" >&2
  exit 1
fi
scripts/build-core.sh
scripts/gen-xcodeproj.sh
scripts/check-apple-config.sh
mkdir -p .build/logs
log=.build/logs/build-signed.log
if ! xcodebuild -project apple/Parallux.xcodeproj -scheme Parallux -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-signed \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build >"$log" 2>&1; then
  grep -E "error:" "$log" | head -40 >&2 || tail -40 "$log" >&2
  exit 1
fi
app=.build/xcode-signed/Build/Products/Debug/Parallux.app
sysext="$app/Contents/Library/SystemExtensions/io.github.visual-z.parallux.tunnel.systemextension"
# A signed build must carry the team's identity on both bundles; an ad-hoc
# signature would build fine and then fail to activate.
for bundle in "$app" "$sysext"; do
  if ! codesign -dv "$bundle" 2>&1 | grep -q '^TeamIdentifier=[A-Z0-9]\{10\}$'; then
    echo "FAIL $bundle is not signed with a team identity" >&2
    exit 1
  fi
done
codesign --verify --deep --strict "$app"
echo "signed $app"
if [ "${1:-}" = "--install" ]; then
  osascript -e 'tell application "Parallux" to quit' >/dev/null 2>&1 || true
  rm -rf /Applications/Parallux.app
  cp -R "$app" /Applications/
  echo "installed /Applications/Parallux.app"
fi
