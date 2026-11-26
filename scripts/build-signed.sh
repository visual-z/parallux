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
scripts/fetch-sparkle.sh
scripts/gen-xcodeproj.sh
scripts/check-apple-config.sh
mkdir -p .build/logs
log=.build/logs/build-signed.log
# A unique build number per signed build: macOS keeps an installed system
# extension whose version did not change, so without it a rebuilt extension
# never replaces the running one.
build_number="$(date -u +%Y%m%d%H%M%S)"
if ! xcodebuild -project apple/Parallux.xcodeproj -scheme Parallux -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-signed \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  CURRENT_PROJECT_VERSION="$build_number" build >"$log" 2>&1; then
  grep -E "error:" "$log" | head -40 >&2 || tail -40 "$log" >&2
  exit 1
fi
app=.build/xcode-signed/Build/Products/Debug/Parallux.app
# xcodebuild keeps the mode of an unchanged file, so an artifact built once
# under a tight umask stays 0700 for every later build from this tree. Normalise
# before signing checks: sysextd expects the extension's binary to be executable
# by all (docs/archive/tasks/fix-sysext-error-text.md). File modes are not sealed by the
# signature, so this does not disturb it.
chmod -R a+rX "$app"
sysext="$app/Contents/Library/SystemExtensions/io.github.visual-z.parallux.tunnel.systemextension"
helper_label="io.github.visual-z.parallux.helper"
helper="$app/Contents/Library/HelperTools/$helper_label"
helper_plist="$app/Contents/Library/LaunchDaemons/$helper_label.plist"
widget="$app/Contents/PlugIns/ParalluxWidget.appex"
[ -d "$widget" ] || { echo "FAIL missing $widget" >&2; exit 1; }
# SMAppService.daemon needs the launchd plist and the program it names.
for path in "$helper" "$helper_plist"; do
  [ -f "$path" ] || { echo "FAIL missing $path" >&2; exit 1; }
done
if [ "$(plutil -extract BundleProgram raw -o - "$helper_plist")" != "Contents/Library/HelperTools/$helper_label" ]; then
  echo "FAIL $helper_plist BundleProgram does not point at the embedded helper" >&2
  exit 1
fi
# A signed build must carry the team's identity on both bundles; an ad-hoc
# signature would build fine and then fail to activate.
# Capture first: with pipefail, `codesign | grep -q` fails at random when grep
# exits on its match and codesign then dies of SIGPIPE.
for bundle in "$app" "$sysext" "$helper" "$widget"; do
  details="$(codesign -dv "$bundle" 2>&1 || true)"
  if ! grep -q '^TeamIdentifier=[A-Z0-9]\{10\}$' <<<"$details"; then
    echo "FAIL $bundle is not signed with a team identity" >&2
    exit 1
  fi
done
codesign --verify --deep --strict "$app"
# The Icon Composer asset compiles to an AppIcon.icns that stops at 256 px, and
# the notification banner draws a blank tile without a larger rendition
# (docs/archive/tasks/chore-notification-app-icon.md). Replace it in place and re-seal
# this bundle only — the nested extension keeps its own signature.
scripts/make-appicon-icns.sh "$app" "$app/Contents/Resources/AppIcon.icns"
identity="$(codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
codesign --force --preserve-metadata=entitlements,flags,requirements --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
# Both bundles must carry the stamped number, and the Mach service with it.
for plist in "$app/Contents/Info.plist" "$sysext/Contents/Info.plist" "$widget/Contents/Info.plist"; do
  if [ "$(plutil -extract CFBundleVersion raw -o - "$plist")" != "$build_number" ]; then
    echo "FAIL $plist does not carry build $build_number" >&2
    exit 1
  fi
done
mach="$(plutil -extract NetworkExtension.NEMachServiceName raw -o - "$sysext/Contents/Info.plist")"
case "$mach" in *".$build_number") ;; *) echo "FAIL Mach service $mach does not end in .$build_number" >&2; exit 1 ;; esac
# The helper's Info.plist is linked into its binary; read it back from there.
helper_info="$(mktemp)"
trap '/bin/rm -f "$helper_info"' EXIT
segedit "$helper" -extract __TEXT __info_plist "$helper_info"
if [ "$(plutil -extract CFBundleVersion raw -o - "$helper_info")" != "$build_number" ]; then
  echo "FAIL $helper does not carry build $build_number" >&2
  exit 1
fi
helper_mach="$(plutil -extract ParalluxHelperMachService raw -o - "$helper_info")"
case "$helper_mach" in *".$build_number") ;; *) echo "FAIL helper Mach service $helper_mach does not end in .$build_number" >&2; exit 1 ;; esac
# plutil key paths split on dots, and the service name is dotted; compare the
# dictionary's keys instead.
services="$(plutil -extract MachServices xml1 -o - "$helper_plist")"
if ! grep -qxF "	<key>$helper_mach</key>" <<<"$services"; then
  echo "FAIL $helper_plist does not declare $helper_mach" >&2
  exit 1
fi
echo "signed $app (build $build_number, $mach)"
if [ "${1:-}" = "--install" ]; then
  osascript -e 'tell application "Parallux" to quit' >/dev/null 2>&1 || true
  rm -rf /Applications/Parallux.app
  # ditto, not cp: cp applies the umask and strips the group/other executable
  # bits, and sysextd refuses an extension whose binary is not 0755
  # ("all executable bits are expected to be set", docs/archive/tasks/fix-sysext-error-text.md).
  ditto "$app" /Applications/Parallux.app
  echo "installed /Applications/Parallux.app"
fi
