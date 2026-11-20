#!/usr/bin/env bash
# Checks the files XcodeGen generated from apple/project.yml for what a signed
# app and system extension need at runtime. Unsigned builds (the gate) do not
# embed entitlements, so without this check an empty entitlements file would
# only surface when the extension fails to activate on a signed build.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT/apple"

failures=0
fail() { echo "FAIL  $*" >&2; failures=$((failures + 1)); }

# has <plist> <key path> <expected value or empty for "present">
has() {
  local value
  if ! value="$(plutil -extract "$2" raw -o - "$1" 2>/dev/null)"; then
    fail "$1: missing $2"; return
  fi
  if [ -n "${3:-}" ] && [ "$value" != "$3" ]; then
    fail "$1: $2 is '$value', want '$3'"
  fi
}

app=Parallux/Parallux.entitlements
ext=PacketTunnel/PacketTunnel.entitlements
has "$app" "com\.apple\.developer\.system-extension\.install" true
has "$app" "com\.apple\.developer\.networking\.networkextension.0" '$(PARALLUX_NE_PROVIDER)'
has "$app" "com\.apple\.security\.application-groups.0" '$(PARALLUX_APP_GROUP)'
has "$ext" "com\.apple\.security\.app-sandbox" true
has "$ext" "com\.apple\.security\.network\.client" true
has "$ext" "com\.apple\.security\.network\.server" true
has "$ext" "com\.apple\.developer\.networking\.networkextension.0" '$(PARALLUX_NE_PROVIDER)'
has "$ext" "com\.apple\.security\.application-groups.0" '$(PARALLUX_APP_GROUP)'

info=PacketTunnel/Info.plist
has "$info" CFBundlePackageType SYSX
# macOS refuses to activate a network system extension without it (author's
# manual test, 2026-11-19; SFM sets it). An empty string is enough.
has "$info" NSSystemExtensionUsageDescription
has "$info" NetworkExtension.NEMachServiceName '$(PARALLUX_TUNNEL_MACH_SERVICE)'
has "$info" "NetworkExtension.NEProviderClasses.com\.apple\.networkextension\.packet-tunnel" '$(PRODUCT_MODULE_NAME).PacketTunnelProvider'
has Parallux/Info.plist ParalluxTunnelMachService '$(PARALLUX_TUNNEL_MACH_SERVICE)'

# The Mach service must sit inside the App Group and change with the version
# and the build number.
mach="$(sed -n 's/^PARALLUX_TUNNEL_MACH_SERVICE *= *//p' Config/Base.xcconfig)"
case "$mach" in
  '$(PARALLUX_APP_GROUP).'*'$(MARKETING_VERSION)'*'$(CURRENT_PROJECT_VERSION)'*) ;;
  *) fail "Config/Base.xcconfig: PARALLUX_TUNNEL_MACH_SERVICE '$mach' must start with \$(PARALLUX_APP_GROUP). and contain \$(MARKETING_VERSION) and \$(CURRENT_PROJECT_VERSION)" ;;
esac

# Root helper. Its Info.plist is linked
# into the tool and names the service it listens on; the launchd plist
# template is expanded at build time with the same variables.
helper=ParalluxHelper/Info.plist
has "$helper" ParalluxHelperMachService '$(PARALLUX_HELPER_MACH_SERVICE)'
has "$helper" ParalluxAppGroup '$(PARALLUX_APP_GROUP)'
has "$helper" ParalluxAppBundleID '$(BUNDLE_ID)'
has Parallux/Info.plist ParalluxHelperMachService '$(PARALLUX_HELPER_MACH_SERVICE)'
has Parallux/Info.plist ParalluxHelperLabel '$(PARALLUX_HELPER_LABEL)'
has PacketTunnel/Info.plist ParalluxHelperMachService '$(PARALLUX_HELPER_MACH_SERVICE)'
daemon=Config/helper-launchd.plist
has "$daemon" Label '$(PARALLUX_HELPER_LABEL)'
has "$daemon" BundleProgram 'Contents/Library/HelperTools/$(PARALLUX_HELPER_LABEL)'
has "$daemon" "MachServices.\$(PARALLUX_HELPER_MACH_SERVICE)" true
has "$daemon" AssociatedBundleIdentifiers.0 '$(BUNDLE_ID)'
helper_mach="$(sed -n 's/^PARALLUX_HELPER_MACH_SERVICE *= *//p' Config/Base.xcconfig)"
case "$helper_mach" in
  '$(PARALLUX_APP_GROUP).helper.'*'$(MARKETING_VERSION)'*'$(CURRENT_PROJECT_VERSION)'*) ;;
  *) fail "Config/Base.xcconfig: PARALLUX_HELPER_MACH_SERVICE '$helper_mach' must start with \$(PARALLUX_APP_GROUP).helper. and contain \$(MARKETING_VERSION) and \$(CURRENT_PROJECT_VERSION)" ;;
esac

# Widget and Control Center toggle.
# Without the extension point the system never loads it; without the App
# Group it shows no state; without the NE entitlement its toggle cannot
# start the VPN configuration.
widget=ParalluxWidget/Info.plist
widget_ent=ParalluxWidget/ParalluxWidget.entitlements
has "$widget" NSExtension.NSExtensionPointIdentifier com.apple.widgetkit-extension
has "$widget" ParalluxAppGroup '$(PARALLUX_APP_GROUP)'
has "$widget_ent" "com\.apple\.security\.app-sandbox" true
has "$widget_ent" "com\.apple\.security\.application-groups.0" '$(PARALLUX_APP_GROUP)'
has "$widget_ent" "com\.apple\.developer\.networking\.networkextension.0" '$(PARALLUX_NE_PROVIDER)'
# parallux:// and SFM's sing-box:// import links.
has Parallux/Info.plist CFBundleURLTypes.0.CFBundleURLSchemes.0 parallux
has Parallux/Info.plist CFBundleURLTypes.1.CFBundleURLSchemes.0 sing-box

if [ "$failures" -gt 0 ]; then
  echo "check-apple-config: $failures problem(s)" >&2
  exit 1
fi
echo "check-apple-config: entitlements and Info.plist keys present"
