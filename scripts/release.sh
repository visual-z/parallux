#!/usr/bin/env bash
# Builds a release of Parallux (PLAN decision 19, docs/RELEASE.md):
# both-arch core → Developer ID archive and export → check-release.sh →
# notarize and staple the app → DMG → notarize and staple the DMG →
# Sparkle appcast. Never uploads or publishes anything.
#
#   scripts/release.sh <version>             full release (needs credentials)
#   scripts/release.sh <version> --dry-run   build, sign check and DMG only
#
# Exit codes: 0 ok, 1 a step failed, 2 a credential or profile is missing
# (the message says exactly what to run).
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

version="${1:-}"
dry_run=0
[ "${2:-}" = "--dry-run" ] && dry_run=1
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "usage: scripts/release.sh <version, e.g. 0.1.0> [--dry-run]" >&2
  exit 1
fi

notary_profile="${PARALLUX_NOTARY_PROFILE:-parallux}"

# Sparkle's tools (generate_keys, generate_appcast) come with the same
# sha256-pinned asset as Sparkle.xcframework (scripts/fetch-sparkle.sh).
sparkle_tools() {
  scripts/fetch-sparkle.sh >&2
  echo ".build/sparkle/bin"
}
team="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' apple/Config/Local.xcconfig 2>/dev/null | tr -d ' ')"
missing() { echo "MISSING  $*" >&2; exit 2; }

[ -n "$team" ] || missing "DEVELOPMENT_TEAM in apple/Config/Local.xcconfig (copy Local.xcconfig.example)"

# Credentials are checked first so a full run never builds for minutes and
# then fails at the end.
if [ "$dry_run" = 0 ]; then
  if ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    missing "notarytool credentials. Run once:
    xcrun notarytool store-credentials $notary_profile --apple-id <Apple ID> --team-id $team
  (it asks for an app-specific password from appleid.apple.com), or set PARALLUX_NOTARY_PROFILE."
  fi
  if ! security find-generic-password -s "https://sparkle-project.org" >/dev/null 2>&1; then
    missing "the Sparkle EdDSA key in the login keychain. Run once (prints the public key for PARALLUX_UPDATE_PUBLIC_KEY):
    $(sparkle_tools)/generate_keys"
  fi
  feed="$(sed -n 's/^PARALLUX_UPDATE_FEED *= *//p' apple/Config/Local.xcconfig | tr -d ' ')"
  [ -n "$feed" ] || missing "PARALLUX_UPDATE_FEED and PARALLUX_UPDATE_PUBLIC_KEY in apple/Config/Local.xcconfig (docs/RELEASE.md)"
fi

out=".build/release/$version"
rm -rf "$out"
mkdir -p "$out" .build/logs
log=".build/logs/release-$version.log"
: >"$log"

echo "==> core (arm64 + x86_64)"
ARCHS=all scripts/build-core.sh >>"$log" 2>&1
scripts/fetch-sparkle.sh
scripts/gen-xcodeproj.sh
scripts/check-apple-config.sh

# Same stamping as build-signed.sh: a unique, increasing build number makes
# macOS replace the installed system extension.
build_number="$(date -u +%Y%m%d%H%M%S)"

# A Developer ID build is signed for distribution, so Xcode needs the Direct
# (Developer ID) profiles for the app, the widget and the system extension.
# -allowProvisioningUpdates lets xcodebuild take them from the team account;
# the author approved that on 2026-11-25 for this step
# (docs/tasks/fix-release-profile-selection.md), which is the one exception to
# decision 15's "Apple Development only".
mode=developer-id
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  if [ "$dry_run" = 0 ]; then
    missing "a Developer ID Application certificate in the login keychain (Xcode › Settings › Accounts › Manage Certificates)"
  fi
  echo "NOTE  no Developer ID Application certificate: --dry-run builds with Apple Development instead;"
  echo "      check-release.sh will fail on signing, which is expected for this fallback."
  mode=development
fi

archive="$out/Parallux.xcarchive"
echo "==> archive ($mode)"
archive_settings=(
  MARKETING_VERSION="$version"
  CURRENT_PROJECT_VERSION="$build_number"
  DEVELOPMENT_TEAM="$team"
)
if ! xcodebuild -project apple/Parallux.xcodeproj -scheme Parallux -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-release \
  -archivePath "$archive" "${archive_settings[@]}" -allowProvisioningUpdates archive >>"$log" 2>&1; then
  grep -E "error:" "$log" | head -20 >&2 || tail -30 "$log" >&2
  exit 1
fi

# The Icon Composer asset compiles into Assets.car plus an AppIcon.icns that
# stops at 256 px; the notification banner asks for a larger flat rendition and
# draws a blank tile without one. Replace it inside the archive — export
# re-signs the app, so the shipped signature covers the new file
# (docs/tasks/chore-notification-app-icon.md).
archived_app="$archive/Products/Applications/Parallux.app"
if [ -d "$archived_app" ]; then
  scripts/make-appicon-icns.sh "$archived_app" "$archived_app/Contents/Resources/AppIcon.icns" >/dev/null
fi

echo "==> export"
cat >"$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$([ "$mode" = developer-id ] && echo developer-id || echo debugging)</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
if ! xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" \
  -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates >>"$log" 2>&1; then
  grep -E "error:" "$log" | tail -20 >&2 || tail -30 "$log" >&2
  exit 1
fi
app="$out/export/Parallux.app"

echo "==> check"
check_status=0
scripts/check-release.sh "$app" || check_status=$?
if [ "$check_status" != 0 ] && [ "$mode" = developer-id ]; then
  echo "release: the exported app is not fit to ship (see FAIL lines above)" >&2
  exit 1
fi

if [ "$dry_run" = 0 ]; then
  echo "==> notarize app"
  ditto -c -k --keepParent "$app" "$out/Parallux.zip"
  xcrun notarytool submit "$out/Parallux.zip" --keychain-profile "$notary_profile" --wait >>"$log" 2>&1 || {
    echo "notarization of the app failed; see $log (xcrun notarytool log <id> --keychain-profile $notary_profile)" >&2
    exit 1
  }
  xcrun stapler staple "$app" >>"$log" 2>&1
  rm -f "$out/Parallux.zip"
fi

echo "==> dmg"
staging="$out/dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
dmg="$out/Parallux-$version.dmg"
hdiutil create -volname "Parallux $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >>"$log" 2>&1
rm -rf "$staging"

if [ "$dry_run" = 0 ]; then
  echo "==> notarize dmg"
  codesign --sign "Developer ID Application" --timestamp "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait >>"$log" 2>&1 || {
    echo "notarization of the DMG failed; see $log" >&2
    exit 1
  }
  xcrun stapler staple "$dmg" >>"$log" 2>&1

  echo "==> appcast"
  generate_appcast="$(sparkle_tools)/generate_appcast"
  mkdir -p "$out/appcast"
  cp "$dmg" "$out/appcast/"
  "$generate_appcast" "$out/appcast" >>"$log" 2>&1
fi

ln -sfn "$version" .build/release/latest
ln -sfn "export/Parallux.app" "$out/Parallux.app"
echo "release $version ($mode, build $build_number): $out"
[ "$dry_run" = 1 ] && echo "dry run: notarization and appcast skipped; nothing was uploaded"
exit 0
