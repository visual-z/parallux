#!/usr/bin/env bash
# Checks that a built Parallux.app is fit to ship (docs/tasks/feat-release.md D2):
# every bundle Developer ID signed with hardened runtime and a secure
# timestamp, no get-task-allow, the -systemextension NE entitlement, and a
# Sparkle feed and public key. Reports every problem before exiting 1.
#   scripts/check-release.sh <path to Parallux.app>
set -euo pipefail
app="${1:?usage: scripts/check-release.sh <Parallux.app>}"
if [ ! -d "$app" ]; then
  echo "FAIL  $app does not exist" >&2
  exit 1
fi

failures=0
fail() { echo "FAIL  $*" >&2; failures=$((failures + 1)); }

bundles=("$app")
for dir in "$app/Contents/Library/SystemExtensions" "$app/Contents/PlugIns"; do
  [ -d "$dir" ] || continue
  for b in "$dir"/*; do [ -e "$b" ] && bundles+=("$b"); done
done
if [ -d "$app/Contents/Library/HelperTools" ]; then
  for tool in "$app/Contents/Library/HelperTools"/*; do [ -f "$tool" ] && bundles+=("$tool"); done
fi

for b in "${bundles[@]}"; do
  name="${b#"$app"/}"
  [ "$b" = "$app" ] && name="Parallux.app"
  # Capture first: piping codesign into grep -q dies of SIGPIPE under pipefail.
  details="$(codesign -dvvv "$b" 2>&1 || true)"
  grep -q '^Authority=Developer ID Application: ' <<<"$details" || fail "$name: not signed with Developer ID Application"
  grep -q 'flags=.*runtime' <<<"$details" || fail "$name: hardened runtime off"
  grep -q '^Timestamp=' <<<"$details" || fail "$name: no secure timestamp"
  entitlements="$(codesign -d --entitlements - --xml "$b" 2>/dev/null || true)"
  if grep -q 'com.apple.security.get-task-allow' <<<"$entitlements"; then
    fail "$name: has get-task-allow (a development build)"
  fi
  if grep -q 'com.apple.developer.networking.networkextension' <<<"$entitlements" &&
    ! grep -q 'packet-tunnel-provider-systemextension' <<<"$entitlements"; then
    fail "$name: Network Extension entitlement lacks -systemextension (Developer ID needs it)"
  fi
done

if ! codesign --verify --deep --strict "$app" 2>/dev/null; then
  fail "Parallux.app: codesign --verify --deep --strict failed"
fi

info="$app/Contents/Info.plist"
for key in SUFeedURL SUPublicEDKey; do
  value="$(plutil -extract "$key" raw -o - "$info" 2>/dev/null || true)"
  case "$value" in
    "" | '$('*) fail "Info.plist: $key is missing or empty (set PARALLUX_UPDATE_FEED / PARALLUX_UPDATE_PUBLIC_KEY)" ;;
  esac
done

if [ "$failures" -gt 0 ]; then
  echo "check-release: $failures problem(s) in $app" >&2
  exit 1
fi
echo "check-release: $app is fit to ship"
