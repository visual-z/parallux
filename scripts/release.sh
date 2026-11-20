#!/usr/bin/env bash
# Builds a release of Parallux (PLAN decisions 19 and 26, docs/RELEASE.md):
# both-arch core → archive → Developer ID export → check-release.sh →
# notarize and staple the app → DMG → notarize and staple the DMG →
# Sparkle appcast. Never uploads or publishes anything.
#
#   scripts/release.sh <version>             full release (needs credentials)
#   scripts/release.sh <version> --dry-run   build, sign check and DMG only
#
# Environment (all optional):
#   PARALLUX_NOTARY_PROFILE     notarytool keychain profile        (parallux)
#   PARALLUX_SPARKLE_ACCOUNT    keychain account of the EdDSA key  (the bundle id)
#   PARALLUX_UPDATE_FEED        the stable appcast's https URL
#   PARALLUX_UPDATE_BETA_FEED   the beta appcast's https URL
#   PARALLUX_DOWNLOAD_PREFIX    where the DMG will be downloaded from
#
# Exit codes: 0 ok, 1 a step failed, 2 a credential is missing (the message
# says exactly what to run).
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
# The EdDSA key is looked up by account, never just by Sparkle's service
# name: a key another app's releases put in the same keychain is not ours.
sparkle_account="${PARALLUX_SPARKLE_ACCOUNT:-io.github.visual-z.parallux}"
# Where installed copies look for updates. These end up in the app's
# Info.plist, so they are part of what a release is, not a per-machine
# setting: GitHub Pages of this repository (docs/RELEASE.md, 上传).
feed="${PARALLUX_UPDATE_FEED:-https://visual-z.github.io/parallux/appcast.xml}"
beta_feed="${PARALLUX_UPDATE_BETA_FEED:-https://visual-z.github.io/parallux/appcast-beta.xml}"
# The DMG is a GitHub Release asset; the appcast points there.
download_prefix="${PARALLUX_DOWNLOAD_PREFIX:-https://github.com/visual-z/parallux/releases/download/v$version/}"

# Sparkle's tools (generate_keys, generate_appcast) come with the same
# sha256-pinned asset as Sparkle.xcframework (scripts/fetch-sparkle.sh).
scripts/fetch-sparkle.sh
sparkle_bin=".build/sparkle/bin"

team="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' apple/Config/Local.xcconfig 2>/dev/null | tr -d ' ')"
missing() { echo "MISSING  $*" >&2; exit 2; }

[ -n "$team" ] || missing "DEVELOPMENT_TEAM in apple/Config/Local.xcconfig (copy Local.xcconfig.example)"

has_sparkle_key() { security find-generic-password -s "https://sparkle-project.org" -a "$sparkle_account" >/dev/null 2>&1; }
has_developer_id() { security find-identity -v -p codesigning 2>/dev/null | grep -q '"Developer ID Application: '; }

# Credentials are checked first so a full run never builds for minutes and
# then fails at the end.
if [ "$dry_run" = 0 ]; then
  has_sparkle_key || missing "the Sparkle EdDSA key for account $sparkle_account in the login keychain. Run once:
    $sparkle_bin/generate_keys --account $sparkle_account
  and back the key up (generate_keys -x): without it, installed copies can never be updated."
  has_developer_id || missing "a Developer ID Application certificate in the keychain (Xcode › Settings › Accounts › Manage Certificates)."
  if ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    missing "notarytool credentials. Run once:
    xcrun notarytool store-credentials $notary_profile --apple-id <Apple ID> --team-id $team
  (it asks for an app-specific password from appleid.apple.com), or set PARALLUX_NOTARY_PROFILE to a profile you already have."
  fi
fi
case "$feed" in https://*) ;; *) echo "PARALLUX_UPDATE_FEED must be https: $feed" >&2; exit 1 ;; esac

# The public key in the app is read from the key that will sign the appcast,
# at release time, so the two cannot drift apart.
public_key=""
if has_sparkle_key; then
  public_key="$("$sparkle_bin/generate_keys" --account "$sparkle_account" -p 2>/dev/null | tail -n 1)"
fi
if [ "$dry_run" = 0 ] && [ -z "$public_key" ]; then
  echo "could not read the public key of the Sparkle key for $sparkle_account" >&2
  exit 1
fi

# >>> notarize
# Uploads to the notary service fail now and then for reasons that have
# nothing to do with the file: on 2026-11-20 a connect timeout in the DMG's
# upload failed a release after everything else had passed. A submission
# that did not complete is tried again; a verdict is not, because an Invalid
# submission stays invalid however often it is sent.
#
# Why 3 attempts: one flaky upload in a row is ordinary, three in a row means
# the network or the service is down and someone should look. Why 20 s
# between them: long enough for a dropped route to come back, short next to
# the minutes a submission takes. Why 30 minutes per wait: Apple's notary
# service usually answers in 2 to 5; without a limit a stuck submission would
# hold the release forever. All three are assumed values.
notary_attempts=3
notary_retry_delay=20
notary_wait_limit=30m

# notarize <file>: submits it and waits. Succeeds only when the service
# says "status: Accepted".
notarize() {
  local file="$1" attempt output verdict
  for attempt in $(seq 1 "$notary_attempts"); do
    output="$(xcrun notarytool submit "$file" --keychain-profile "$notary_profile" --wait --timeout "$notary_wait_limit" 2>&1)" || true
    printf '%s\n' "$output" >>"$log"
    # The verdict is a line of its own ("  status: Accepted"); the progress
    # line ("Current status: In Progress...") does not start with it.
    verdict="$(sed -n 's/^ *status: *//p' <<<"$output" | tail -n 1)"
    if [ "$verdict" = "Accepted" ]; then
      return 0
    fi
    if [ -n "$verdict" ]; then
      echo "the notary service answered \"$verdict\" for $(basename "$file"); see $log and: xcrun notarytool log <id> --keychain-profile $notary_profile" >&2
      return 1
    fi
    echo "NOTE  the submission of $(basename "$file") did not complete (attempt $attempt of $notary_attempts)" >&2
    if [ "$attempt" -lt "$notary_attempts" ]; then
      sleep "$notary_retry_delay"
    fi
  done
  echo "notarization of $(basename "$file") failed: no submission completed in $notary_attempts attempts; see $log" >&2
  return 1
}
# <<< notarize

out=".build/release/$version"
rm -rf "$out"
mkdir -p "$out" .build/logs
log=".build/logs/release-$version.log"
: >"$log"

echo "==> core (arm64 + x86_64)"
ARCHS=all scripts/build-core.sh >>"$log" 2>&1
scripts/gen-xcodeproj.sh
scripts/check-apple-config.sh

# Same stamping as build-signed.sh: a unique, increasing build number makes
# macOS replace the installed system extension, and it is what Sparkle
# compares (sparkle:version).
build_number="$(date -u +%Y%m%d%H%M%S)"

# The archive is signed for development and the export re-signs it with
# Developer ID: that is Apple's flow for a Network Extension system
# extension, whose entitlement value differs between the two
# (packet-tunnel-provider vs …-systemextension). Xcode 27's export rewrites
# the value and creates the Developer ID profiles it manages; older Xcodes
# do not, and check-release.sh below fails on what they produce.
# -allowProvisioningUpdates: the author approved Xcode-managed profiles for
# development (decision 15) and for Developer ID (decision 26).
mode=developer-id
if ! has_developer_id; then
  echo "NOTE  no Developer ID Application certificate: --dry-run exports a development build instead;"
  echo "      check-release.sh will fail on signing, which is expected for this fallback."
  mode=development
fi

archive="$out/Parallux.xcarchive"
echo "==> archive"
if ! xcodebuild -project apple/Parallux.xcodeproj -scheme Parallux -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-release \
  -archivePath "$archive" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_STYLE=Automatic \
  PARALLUX_NE_PROVIDER=packet-tunnel-provider \
  PARALLUX_UPDATE_FEED="$feed" \
  PARALLUX_UPDATE_BETA_FEED="$beta_feed" \
  PARALLUX_UPDATE_PUBLIC_KEY="$public_key" \
  archive >>"$log" 2>&1; then
  grep -E "error:" "$log" | head -20 >&2 || tail -30 "$log" >&2
  exit 1
fi

echo "==> export ($mode)"
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
if [ "$check_status" != 0 ] && [ "$dry_run" = 0 ]; then
  echo "release: the exported app is not fit to ship (see FAIL lines above)" >&2
  exit 1
fi

if [ "$dry_run" = 0 ]; then
  echo "==> notarize app"
  ditto -c -k --keepParent "$app" "$out/Parallux.zip"
  notarize "$out/Parallux.zip" || exit 1
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
  notarize "$dmg" || exit 1
  xcrun stapler staple "$dmg" >>"$log" 2>&1

  echo "==> appcast"
  mkdir -p "$out/appcast"
  cp "$dmg" "$out/appcast/"
  "$sparkle_bin/generate_appcast" --account "$sparkle_account" --download-url-prefix "$download_prefix" \
    --link "https://github.com/visual-z/parallux" "$out/appcast" >>"$log" 2>&1
  # generate_appcast writes an item without a signature when it cannot read
  # the key; an unsigned item would be refused by every installed copy.
  if ! grep -q 'sparkle:edSignature="' "$out/appcast/appcast.xml"; then
    echo "the appcast has no EdDSA signature; see $log" >&2
    exit 1
  fi
  if ! grep -q "url=\"$download_prefix$(basename "$dmg")\"" "$out/appcast/appcast.xml"; then
    echo "the appcast does not point at $download_prefix$(basename "$dmg")" >&2
    exit 1
  fi
fi

ln -sfn "$version" .build/release/latest
ln -sfn "export/Parallux.app" "$out/Parallux.app"
echo "release $version ($mode, build $build_number): $out"
[ "$dry_run" = 1 ] && echo "dry run: notarization and appcast skipped; nothing was uploaded"
exit 0
