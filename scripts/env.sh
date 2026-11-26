# Sourced by the other scripts. Points the Apple toolchain at a full Xcode when
# xcode-select still names the Command Line Tools (gomobile and xcodebuild both
# need the macOS SDK and xcodebuild, which the CLT do not ship).
# Override with DEVELOPER_DIR=… in the environment.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  case "$(xcode-select -p 2>/dev/null)" in
    */CommandLineTools|"") export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ;;
  esac
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
# Artifacts must not inherit the caller's umask: with 077 the built binaries
# land at 0700, sysextd logs "all executable bits are expected to be set" for
# the extension, and a DMG cut from that tree ships the same way
# (docs/archive/tasks/fix-sysext-error-text.md).
umask 022

# Every copy of Parallux.app that LaunchServices knows about competes for the
# bundle ID, and Notification Center may draw a stale copy's icon: on the
# author's Mac 27 build products were registered and banners showed a blank
# tile although /Applications had the full-size icon
# (docs/tasks/chore-forget-build-registrations.md). Build products are not
# meant to be opened in place, so each script forgets what it built, nested
# bundles (Sparkle's Updater.app, the widget) included. Files stay; only the
# registration goes.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
forget_build() {
  local root bundle
  for root in "$@"; do
    [ -d "$root" ] || continue
    while IFS= read -r bundle; do
      "$lsregister" -u "$bundle" >/dev/null 2>&1 || true
    done < <(find "$root" \( -name '*.app' -o -name '*.appex' \) -type d -prune -print 2>/dev/null; \
             find "$root" -path '*.app/*' \( -name '*.app' -o -name '*.appex' \) -type d 2>/dev/null)
  done
}
