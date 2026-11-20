#!/bin/sh
# Installs the Parallux aggregation server (聚合服务器) on a Linux VPS with
# systemd, then prints the import link the app takes (PLAN decision 18;
# format: docs/research/aggregation-server-link.md).
#
#   sudo sh install.sh --binary ./parallux-server [--port 39000] [--host 203.0.113.24] [--name "Tokyo VPS"]
#
# What it does: copies the binary to /usr/local/bin, generates a random
# pre-shared key, writes /etc/parallux-server/config.json (0600, root), installs
# and starts parallux-server.service. It changes no firewall rules; it prints
# the port to open. Re-running it keeps the existing key unless --new-psk.
#
# The key is printed exactly once, inside the final import link. Nothing else
# echoes it.
#
# With --relay it installs a relay host instead (中继主机, PLAN decision 24;
# link format: docs/research/relay-link.md): a machine on your LAN that
# dials out for the Mac, so it adds its own egress quota as one more link.
#
#   sudo sh install.sh --relay --binary ./parallux-server [--port 39100] [--host 10.0.0.21] [--name worker-1]
#
# That writes /etc/parallux-server/relay.key (0600, root) and installs
# parallux-relay.service; both roles can live on one machine.
set -eu

# Release downloads arrive with M6 (no releases exist yet). Until then pass
# --binary; set PARALLUX_SERVER_URL to fetch from your own mirror.
PARALLUX_SERVER_URL="${PARALLUX_SERVER_URL:-}"

PORT=""
RELAY=0
HOST=""
NAME=""
BINARY=""
NEW_PSK=0
CONFIG_DIR=/etc/parallux-server
CONFIG="$CONFIG_DIR/config.json"
BIN=/usr/local/bin/parallux-server
UNIT=/etc/systemd/system/parallux-server.service
RELAY_KEY="$CONFIG_DIR/relay.key"
RELAY_UNIT=/etc/systemd/system/parallux-relay.service

die() { echo "install.sh: $*" >&2; exit 1; }

usage() {
	sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--binary) [ $# -ge 2 ] || die "--binary needs a path"; BINARY="$2"; shift 2 ;;
	--port) [ $# -ge 2 ] || die "--port needs a number"; PORT="$2"; shift 2 ;;
	--host) [ $# -ge 2 ] || die "--host needs an address"; HOST="$2"; shift 2 ;;
	--name) [ $# -ge 2 ] || die "--name needs a value"; NAME="$2"; shift 2 ;;
	--new-psk) NEW_PSK=1; shift ;;
	--relay) RELAY=1; shift ;;
	-h | --help) usage 0 ;;
	*) echo "install.sh: unknown option $1" >&2; usage 2 ;;
	esac
done

[ "$(id -u)" -eq 0 ] || die "run as root (sudo sh install.sh …)"
command -v systemctl >/dev/null 2>&1 || die "systemd is required"
# The relay's default port differs so one machine can run both roles.
if [ -z "$PORT" ]; then
	if [ "$RELAY" -eq 1 ]; then PORT=39100; else PORT=39000; fi
fi
case "$PORT" in '' | *[!0-9]*) die "--port must be a number" ;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "--port must be 1–65535"

# --- binary -----------------------------------------------------------------
if [ -z "$BINARY" ]; then
	[ -n "$PARALLUX_SERVER_URL" ] || die "pass --binary PATH (release downloads arrive with M6)"
	case "$(uname -m)" in
	x86_64 | amd64) arch=amd64 ;;
	aarch64 | arm64) arch=arm64 ;;
	*) die "unsupported architecture $(uname -m)" ;;
	esac
	BINARY="$(mktemp)"
	trap 'rm -f "$BINARY"' EXIT
	curl -fsSL "$PARALLUX_SERVER_URL/parallux-server-linux-$arch" -o "$BINARY" || die "download failed"
fi
[ -f "$BINARY" ] || die "binary $BINARY not found"
install -m 0755 "$BINARY" "$BIN"

# --- relay host -------------------------------------------------------------
# The binary generates the key and builds the link (tested there); this
# script only installs the service. A relay's address is normally private,
# so unlike the aggregation server there is no public-address check.
if [ "$RELAY" -eq 1 ]; then
	umask 077
	mkdir -p "$CONFIG_DIR"
	chmod 0700 "$CONFIG_DIR"
	if [ "$NEW_PSK" -eq 1 ]; then rm -f "$RELAY_KEY"; fi
	"$BIN" -role relay -key-file "$RELAY_KEY" -generate-key || die "could not generate the relay key"
	"$BIN" -role relay -check -port "$PORT" -key-file "$RELAY_KEY" || die "the relay configuration does not validate"

	cat >"$RELAY_UNIT" <<UNIT_EOF
[Unit]
Description=Parallux relay host
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$BIN -role relay -port $PORT -key-file $RELAY_KEY
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=$CONFIG_DIR
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT_EOF
	chmod 0644 "$RELAY_UNIT"
	systemctl daemon-reload
	systemctl enable parallux-relay.service >/dev/null
	systemctl restart parallux-relay.service
	sleep 1
	systemctl is-active --quiet parallux-relay.service || die "the service did not start; see: journalctl -u parallux-relay"

	if [ -z "$HOST" ] && command -v ip >/dev/null 2>&1; then
		HOST="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1)"
	fi
	[ -n "$HOST" ] || die "could not find this machine's address; rerun with --host <address the Mac reaches it at>"
	[ -n "$NAME" ] || NAME="$(hostname 2>/dev/null || echo "$HOST")"
	echo "Parallux relay host is running on port $PORT (TCP and UDP)."
	echo "If this machine has a firewall, allow port $PORT from your Mac. Keep its clock in sync (NTP): the relay rejects peers more than 30 seconds off."
	echo "Paste this link into Parallux › 线路 › 添加中继线路:"
	"$BIN" -role relay -port "$PORT" -key-file "$RELAY_KEY" -host "$HOST" -name "$NAME" -link
	exit 0
fi

# --- key --------------------------------------------------------------------
# 32 random bytes as base64url without padding: 43 characters, URL-safe.
generate_psk() {
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -base64 32
	else
		head -c 32 /dev/urandom | base64
	fi | tr '+/' '-_' | tr -d '=\n'
}

existing_psk() {
	[ -f "$CONFIG" ] || return 1
	sed -n 's/.*"psk": *"\([^"]*\)".*/\1/p' "$CONFIG" | head -n 1
}

PSK=""
if [ "$NEW_PSK" -eq 0 ]; then PSK="$(existing_psk || true)"; fi
[ -n "$PSK" ] || PSK="$(generate_psk)"
[ "${#PSK}" -ge 16 ] || die "could not generate a key"

# --- configuration ----------------------------------------------------------
umask 077
mkdir -p "$CONFIG_DIR"
chmod 0700 "$CONFIG_DIR"
cat >"$CONFIG.tmp" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    { "type": "multipath", "tag": "mp-in", "listen": "::", "listen_port": $PORT, "psk": "$PSK" }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
chmod 0600 "$CONFIG.tmp"
"$BIN" -check -config "$CONFIG.tmp" || { rm -f "$CONFIG.tmp"; die "the generated configuration does not validate"; }
mv "$CONFIG.tmp" "$CONFIG"

cat >"$UNIT" <<EOF
[Unit]
Description=Parallux aggregation server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$BIN -config $CONFIG
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=$CONFIG_DIR
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$UNIT"
systemctl daemon-reload
systemctl enable parallux-server.service >/dev/null
systemctl restart parallux-server.service
sleep 1
systemctl is-active --quiet parallux-server.service || die "the service did not start; see: journalctl -u parallux-server"

# --- address ----------------------------------------------------------------
# No third-party "what is my IP" service: use the address the kernel would
# send from, and ask for --host when that address is not public (NAT).
is_private_v4() {
	case "$1" in
	10.* | 192.168.* | 127.* | 169.254.*) return 0 ;;
	172.1[6-9].* | 172.2[0-9].* | 172.3[01].*) return 0 ;;
	100.6[4-9].* | 100.[7-9][0-9].* | 100.1[01][0-9].* | 100.12[0-7].*) return 0 ;;
	esac
	return 1
}

if [ -z "$HOST" ] && command -v ip >/dev/null 2>&1; then
	HOST="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1)"
	if [ -n "$HOST" ] && is_private_v4 "$HOST"; then
		echo "install.sh: this host's address $HOST is private (behind NAT); rerun with --host <public address>" >&2
		HOST=""
	fi
fi
[ -n "$HOST" ] || die "could not find a public address; rerun with --host <address or domain>"

# --- link -------------------------------------------------------------------
# RFC 3986 query encoding: keep unreserved characters, percent-encode every
# other byte.
urlencode() {
	printf '%s' "$1" | od -An -v -tx1 | tr -s ' \n' '  ' | tr ' ' '\n' | while read -r byte; do
		[ -n "$byte" ] || continue
		case "$byte" in
		2d | 2e | 5f | 7e | 3[0-9] | 4[1-9a-f] | 5[0-9a] | 6[1-9a-f] | 7[0-9a])
			# shellcheck disable=SC2059
			printf "\\$(printf '%03o' "0x$byte")" ;;
		*) printf '%%%s' "$(printf '%s' "$byte" | tr '[:lower:]' '[:upper:]')" ;;
		esac
	done
}

[ -n "$NAME" ] || NAME="$HOST"
echo "Parallux aggregation server is running on port $PORT (TCP)."
echo "Open TCP port $PORT in this server's firewall and your provider's security group."
echo "Paste this link into Parallux › 聚合服务器 › 添加:"
echo "parallux://aggregation-server?v=1&host=$(urlencode "$HOST")&port=$PORT&psk=$(urlencode "$PSK")#$(urlencode "$NAME")"
