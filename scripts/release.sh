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

# Developer ID needs a Developer ID provisioning profile for the -systemextension
# Network Extension entitlement. Creating one changes the team's account, which
# decision 15 did not authorize, so this script never passes
# -allowProvisioningUpdates for it. --dry-run falls back to Apple Development.
has_developer_id_profile() {
  local dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  [ -d "$dir" ] || return 1
  local f
  for f in "$dir"/*.provisionprofile; do
    [ -e "$f" ] || continue
    local plist
    plist="$(security cms -D -i "$f" 2>/dev/null || true)"
    if grep -q "io.github.visual-z.parallux.tunnel" <<<"$plist" && grep -q "packet-tunnel-provider-systemextension" <<<"$plist" &&
      ! grep -q "<key>ProvisionedDevices</key>" <<<"$plist"; then
      return 0
    fi
  done
  return 1
}

mode=developer-id
if ! has_developer_id_profile; then
  if [ "$dry_run" = 0 ]; then
    missing "a Developer ID provisioning profile for io.github.visual-z.parallux.tunnel with packet-tunnel-provider-systemextension.
  Create it at developer.apple.com › Profiles (Developer ID, App ID io.github.visual-z.parallux.tunnel), or allow
  this script to let Xcode create it (docs/RELEASE.md, step 4). Then download it in Xcode › Settings › Accounts."
  fi
  echo "NOTE  no Developer ID provisioning profile: --dry-run builds with Apple Development instead;"
  echo "      check-release.sh will fail on signing, which is expected for this fallback."
  mode=development
fi

# Manual signing does not pick a profile by bundle id, and one xcodebuild
# setting applies to every target, so each bundle gets its own variable
# (fix-release-profile-selection). Only the Direct (Developer ID) profiles
# count: a Mac Team profile names the same App ID but is tied to this Mac's
# devices, and shipping with it would sign for a device list nobody else has.
bundle_id="$(sed -n 's/^BUNDLE_ID *= *//p' apple/Config/Base.xcconfig | tr -d ' ')"
direct_profile_name() {
  local want="$1" dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" f plist name der
  [ -d "$dir" ] || return 1
  for f in "$dir"/*.provisionprofile; do
    [ -e "$f" ] || continue
    plist="$(security cms -D -i "$f" 2>/dev/null || true)"
    grep -q "<key>ProvisionedDevices</key>" <<<"$plist" && continue
    name="$(sed -n '/<key>Name<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;q;}' <<<"$plist")"
    # Xcode names Direct profiles after the App ID. The DER blob carries the
    # authoritative application-identifier; it is the fallback if that changes.
    if [ "$name" = "Mac Team Direct Provisioning Profile: $want" ]; then
      echo "$name"
      return 0
    fi
    der="$(plutil -extract DER-Encoded-Profile raw -o - - <<<"$plist" 2>/dev/null | base64 -D 2>/dev/null || true)"
    if grep -a -q "$team\.$want" <<<"$der"; then
      echo "$name"
      return 0
    fi
  done
  return 1
}
app_profile="" widget_profile="" tunnel_profile=""
if [ "$mode" = developer-id ]; then
  app_profile="$(direct_profile_name "$bundle_id")" ||
    missing "a Developer ID provisioning profile for $bundle_id (docs/RELEASE.md, step 4)"
  widget_profile="$(direct_profile_name "$bundle_id.widget")" ||
    missing "a Developer ID provisioning profile for $bundle_id.widget (docs/RELEASE.md, step 4)"
  tunnel_profile="$(direct_profile_name "$bundle_id.tunnel")" ||
    missing "a Developer ID provisioning profile for $bundle_id.tunnel (docs/RELEASE.md, step 4)"
fi

archive="$out/Parallux.xcarchive"
echo "==> archive ($mode)"
archive_settings=(
  MARKETING_VERSION="$version"
  CURRENT_PROJECT_VERSION="$build_number"
  DEVELOPMENT_TEAM="$team"
)
if [ "$mode" = developer-id ]; then
  archive_settings+=(
    PARALLUX_NE_PROVIDER=packet-tunnel-provider-systemextension
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="Developer ID Application"
    PARALLUX_PROFILE_APP="$app_profile"
    PARALLUX_PROFILE_WIDGET="$widget_profile"
    PARALLUX_PROFILE_TUNNEL="$tunnel_profile"
  )
fi
if ! xcodebuild -project apple/Parallux.xcodeproj -scheme Parallux -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-release \
  -archivePath "$archive" "${archive_settings[@]}" archive >>"$log" 2>&1; then
  grep -E "error:" "$log" | head -20 >&2 || tail -30 "$log" >&2
  exit 1
fi

echo "==> export"
cat >"$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$([ "$mode" = developer-id ] && echo developer-id || echo debugging)</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>$([ "$mode" = developer-id ] && echo manual || echo automatic)</string>
</dict>
</plist>
PLIST
if ! xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" \
  -exportOptionsPlist "$out/ExportOptions.plist" >>"$log" 2>&1; then
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
