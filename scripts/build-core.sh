#!/usr/bin/env bash
# Builds apple/Frameworks/Libbox.xcframework: sing-box's experimental/libbox
# (from the Parallux fork, see go.mod) plus core/pxbridge, bound by gomobile
# into one macOS framework.
#
# Mirrors sing-box's own Apple build (cmd/internal/build_libbox, v1.14.4):
# same gomobile fork, tags and linker flags, macOS only, deployment target 26.0
# (PLAN decision 2).
#
# The build is skipped when its inputs hash to the value in .build/core.stamp:
# go.mod, go.sum, every .go file under core/, this script, and `go version`.
# The core version string carries that hash, so it changes exactly when the
# framework does.
#
#   scripts/build-core.sh                build if stale (arm64 only)
#   scripts/build-core.sh --check-fresh  exit 0 if fresh, 1 if a build is due
#   ARCHS=all scripts/build-core.sh      arm64 + x86_64, for release
#   DEBUG=1 scripts/build-core.sh        keep symbols, add the `debug` tag
#   FORCE=1 scripts/build-core.sh        ignore the stamp
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

OUT="$ROOT/apple/Frameworks/Libbox.xcframework"
STAMP="$ROOT/.build/core.stamp"
LOGS="$ROOT/.build/logs"
BIN="$ROOT/.build/bin"
ARCHS="${ARCHS:-arm64}"

input_hash() {
  {
    echo "archs=$ARCHS debug=${DEBUG:-}"
    go version
    cat go.mod go.sum scripts/build-core.sh
    find core -name '*.go' -type f | LC_ALL=C sort | while read -r f; do
      echo "$f"; cat "$f"
    done
  } | shasum -a 256 | cut -c1-16
}

HASH="$(input_hash)"
fresh() { [ -f "$STAMP" ] && [ -d "$OUT" ] && [ "$(cat "$STAMP")" = "$HASH" ]; }

if [ "${1:-}" = "--check-fresh" ]; then
  if fresh; then echo "core is fresh ($HASH)"; exit 0; fi
  echo "core is stale: inputs hash to $HASH, stamp has $(cat "$STAMP" 2>/dev/null || echo none)"
  exit 1
fi
if [ -z "${FORCE:-}" ] && fresh; then
  echo "core is fresh ($HASH), skipping build"
  exit 0
fi

mkdir -p "$BIN" "$LOGS" "$(dirname "$OUT")"
go build -o "$BIN/gomobile" github.com/sagernet/gomobile/cmd/gomobile
go build -o "$BIN/gobind" github.com/sagernet/gomobile/cmd/gobind
export PATH="$BIN:$PATH"

case "$ARCHS" in
  arm64) TARGET="macos/arm64" ;;
  all) TARGET="macos" ;;
  *) echo "ARCHS must be arm64 or all" >&2; exit 2 ;;
esac

SINGBOX_VERSION="$(go list -m -f '{{.Version}}' github.com/sagernet/sing-box)"
SINGBOX_VERSION="${SINGBOX_VERSION#v}"
CORE_VERSION="0.0.0-dev+$HASH"

# Tag list copied from sing-box v1.14.4 cmd/internal/build_libbox (sharedTags +
# darwinTags). Re-check it whenever go.mod moves sing-box.
TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_naive_outbound,with_clash_api,with_usbip,with_openvpn,with_openconnect,badlinkname,tfogo_checklinkname0"
TAGS="$TAGS,with_tailscale,ts_omit_logtail,ts_omit_ssh,ts_omit_drive,ts_omit_taildrop,ts_omit_webclient,ts_omit_doctor,ts_omit_capture,ts_omit_kube,ts_omit_aws,ts_omit_synology,ts_omit_bird"
TAGS="$TAGS,with_dhcp,grpcnotrace"

LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=$SINGBOX_VERSION"
LDFLAGS="$LDFLAGS -X github.com/visual-z/parallux/core/pxbridge.CoreVersion=$CORE_VERSION"
LDFLAGS="$LDFLAGS -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0"
if [ -n "${DEBUG:-}" ]; then
  TAGS="$TAGS,debug"
else
  LDFLAGS="$LDFLAGS -s -w -buildid="
fi

LOG="$LOGS/build-core.log"
rm -rf "$OUT" "$STAMP"
echo "building Libbox.xcframework ($TARGET, core $CORE_VERSION); log: $LOG"
if ! gomobile bind -v \
  -target "$TARGET" \
  -macosversion=26.0 \
  -libname=box \
  -trimpath -buildvcs=false \
  -ldflags "$LDFLAGS" \
  -tags "$TAGS" \
  -o "$OUT" \
  github.com/sagernet/sing-box/experimental/libbox \
  github.com/visual-z/parallux/core/pxbridge >"$LOG" 2>&1; then
  tail -40 "$LOG" >&2
  exit 1
fi
echo "$HASH" >"$STAMP"
echo "built $OUT (sing-box $SINGBOX_VERSION, core $CORE_VERSION)"
