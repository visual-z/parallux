#!/usr/bin/env bash
# Builds apple/Frameworks/Libbox.xcframework: sing-box's experimental/libbox
# plus core/pxbridge, bound by gomobile into one macOS framework.
#
# Mirrors sing-box's own Apple build (cmd/internal/build_libbox, v1.14.4):
# same gomobile fork, same tags and linker flags, macOS only, and the
# deployment target raised to 26.0 (PLAN decision 2).
#
#   scripts/build-core.sh          release build (stripped)
#   DEBUG=1 scripts/build-core.sh  keeps symbols and adds the `debug` tag
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

BIN="$ROOT/.build/bin"
OUT="$ROOT/apple/Frameworks/Libbox.xcframework"
mkdir -p "$BIN" "$(dirname "$OUT")"

# gomobile and gobind at the versions go.mod pins (core/tools.go).
go build -o "$BIN/gomobile" github.com/sagernet/gomobile/cmd/gomobile
go build -o "$BIN/gobind" github.com/sagernet/gomobile/cmd/gobind
export PATH="$BIN:$PATH"

SINGBOX_VERSION="$(go list -m -f '{{.Version}}' github.com/sagernet/sing-box)"
SINGBOX_VERSION="${SINGBOX_VERSION#v}"
CORE_VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo 0.0.0-dev)"

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

rm -rf "$OUT"
gomobile bind -v \
  -target macos \
  -macosversion=26.0 \
  -libname=box \
  -trimpath -buildvcs=false \
  -ldflags "$LDFLAGS" \
  -tags "$TAGS" \
  -o "$OUT" \
  github.com/sagernet/sing-box/experimental/libbox \
  github.com/visual-z/parallux/core/pxbridge

echo "built $OUT (sing-box $SINGBOX_VERSION, core $CORE_VERSION)"
