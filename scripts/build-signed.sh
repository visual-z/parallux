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
# A unique build number per signed build: macOS keeps an installed system
# extension whose version did not change, so without it a rebuilt extension
# never replaces the running one (docs/tasks/fix-signed-run-hazards.md).
build_number="$(date -u +%Y%m%d%H%M%S)"
if ! xcodebuild -project apple/Parallux.xcodeproj -scheme Parallux -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-signed \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  CURRENT_PROJECT_VERSION="$build_number" build >"$log" 2>&1; then
  grep -E "error:" "$log" | head -40 >&2 || tail -40 "$log" >&2
  exit 1
fi
app=.build/xcode-signed/Build/Products/Debug/Parallux.app
sysext="$app/Contents/Library/SystemExtensions/io.github.visual-z.parallux.tunnel.systemextension"
# A signed build must carry the team's identity on both bundles; an ad-hoc
# signature would build fine and then fail to activate.
# Capture first: with pipefail, `codesign | grep -q` fails at random when grep
# exits on its match and codesign then dies of SIGPIPE.
for bundle in "$app" "$sysext"; do
  details="$(codesign -dv "$bundle" 2>&1 || true)"
  if ! grep -q '^TeamIdentifier=[A-Z0-9]\{10\}$' <<<"$details"; then
    echo "FAIL $bundle is not signed with a team identity" >&2
    exit 1
  fi
done
codesign --verify --deep --strict "$app"
# Both bundles must carry the stamped number, and the Mach service with it.
for plist in "$app/Contents/Info.plist" "$sysext/Contents/Info.plist"; do
  if [ "$(plutil -extract CFBundleVersion raw -o - "$plist")" != "$build_number" ]; then
    echo "FAIL $plist does not carry build $build_number" >&2
    exit 1
  fi
done
mach="$(plutil -extract NetworkExtension.NEMachServiceName raw -o - "$sysext/Contents/Info.plist")"
case "$mach" in *".$build_number") ;; *) echo "FAIL Mach service $mach does not end in .$build_number" >&2; exit 1 ;; esac
echo "signed $app (build $build_number, $mach)"
if [ "${1:-}" = "--install" ]; then
  osascript -e 'tell application "Parallux" to quit' >/dev/null 2>&1 || true
  rm -rf /Applications/Parallux.app
  cp -R "$app" /Applications/
  echo "installed /Applications/Parallux.app"
fi
