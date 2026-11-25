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
# (docs/tasks/fix-sysext-error-text.md).
umask 022
