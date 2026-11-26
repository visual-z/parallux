#!/usr/bin/env bash
# Runs server/install.sh for real into a scratch root, with stand-ins for the
# commands only a Linux server has (systemctl, ip, ss, id). The binary is the
# real parallux-server built for this machine, so its -check and -link run.
# Called by scripts/build-server.sh (gate step "server-build").
#
# What it proves: a fresh install, a reinstall, the move of an older
# install's key out of config.json (losing it would break the link the app
# already has), --new-psk, a busy port, a bad --host, and the relay role.
# Keys here are generated in the scratch root and never printed.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
go build -o "$work/parallux-server" ./server/cmd/parallux-server

shims="$work/shims"
mkdir -p "$shims"
# systemctl: "active" once a restart was asked for; everything else succeeds.
cat >"$shims/systemctl" <<'EOF'
#!/bin/sh
state="$SHIM_STATE/active-$2$3"
case "$1" in
is-active) for arg in "$@"; do [ -f "$SHIM_STATE/active-$arg" ] && exit 0; done; exit 3 ;;
restart) : >"$state" ;;
esac
exit 0
EOF
printf '#!/bin/sh\necho 0\n' >"$shims/id"
# ip: the address the kernel would send from.
printf '#!/bin/sh\necho "1.1.1.1 via 203.0.113.1 dev eth0 src ${SHIM_SRC:-203.0.113.24} uid 0"\n' >"$shims/ip"
# ss: a listener on the port when SHIM_BUSY is set.
printf '#!/bin/sh\n[ -n "${SHIM_BUSY:-}" ] && echo "LISTEN 0 128 *:39000 *:*"\nexit 0\n' >"$shims/ss"
chmod +x "$shims"/*

fail() { echo "test-install: FAIL: $*" >&2; exit 1; }

# install <root> [args…]: runs the installer; its output goes to $work/out.
install_into() {
  local root="$1"; shift
  mkdir -p "$root/usr/local/bin" "$root/etc/systemd/system" "$root/state"
  PATH="$shims:$PATH" SHIM_STATE="$root/state" PARALLUX_INSTALL_ROOT="$root" \
    sh server/install.sh --binary "$work/parallux-server" "$@" >"$work/out" 2>"$work/err"
}

mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
link_field() { sed -n "s/.*[?&]$1=\\([^&#]*\\).*/\\1/p" "$work/out" | tail -n 1; }

# --- a fresh aggregation server ---------------------------------------------
root="$work/fresh"
install_into "$root" --name test || fail "a fresh install exited $? ($(cat "$work/err"))"
psk_file="$root/etc/parallux-server/psk"
[ -f "$psk_file" ] || fail "no psk file after a fresh install"
[ "$(mode_of "$psk_file")" = 600 ] || fail "the psk file's mode is $(mode_of "$psk_file"), want 600"
first="$(tr -d '\n' <"$psk_file")"
[ "${#first}" -eq 43 ] || fail "the generated key has ${#first} characters, want 43"
[ ! -e "$root/etc/parallux-server/config.json" ] || fail "a fresh install wrote config.json; the unit runs from flags"
unit="$root/etc/systemd/system/parallux-server.service"
grep -q -- "^ExecStart=$root/usr/local/bin/parallux-server -port 39000 -psk-file $psk_file -self 203.0.113.24\$" "$unit" \
  || fail "the unit does not start the server from flags with -self: $(grep ExecStart "$unit")"
if grep -q -- "$first" "$unit"; then fail "the unit file contains the key"; fi
[ "$(link_field host)" = 203.0.113.24 ] || fail "the link's host is $(link_field host)"
[ "$(link_field psk)" = "$first" ] || fail "the link does not carry the key in the psk file"
[ "$(grep -c -- "$first" "$work/out")" -eq 1 ] || fail "the key is printed more than once"

# --- reinstalling keeps the key ---------------------------------------------
install_into "$root" || fail "a reinstall exited $?"
[ "$(tr -d '\n' <"$psk_file")" = "$first" ] || fail "a reinstall replaced the key"

# --- --new-psk replaces it --------------------------------------------------
install_into "$root" --new-psk || fail "--new-psk exited $?"
second="$(tr -d '\n' <"$psk_file")"
[ "$second" != "$first" ] && [ "${#second}" -eq 43 ] || fail "--new-psk kept the old key"

# --- an older install: the key was inside config.json -----------------------
root="$work/legacy"
mkdir -p "$root/etc/parallux-server"
legacy="legacy-key-0123456789abcdefghijklmnopqrstuv"
cat >"$root/etc/parallux-server/config.json" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    { "type": "multipath", "tag": "mp-in", "listen": "::", "listen_port": 39000, "psk": "$legacy" }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
install_into "$root" || fail "upgrading an older install exited $? ($(cat "$work/err"))"
[ "$(tr -d '\n' <"$root/etc/parallux-server/psk")" = "$legacy" ] || fail "the older install's key was not carried over"
[ ! -e "$root/etc/parallux-server/config.json" ] || fail "the older install's config.json is still there"
[ "$(link_field psk)" = "$legacy" ] || fail "the link after an upgrade does not carry the older key"

# --- a private address needs --host; --host is what -self gets ---------------
root="$work/nat"
if SHIM_SRC=10.0.0.5 install_into "$root"; then fail "a private source address was accepted without --host"; fi
grep -q -- "--host" "$work/err" || fail "the error for a private address does not mention --host"
[ ! -e "$root/etc/systemd/system/parallux-server.service" ] || fail "a failed install left a unit behind"
SHIM_SRC=10.0.0.5 install_into "$root" --host vps.example.com || fail "--host with a name exited $? ($(cat "$work/err"))"
grep -q -- " -self vps.example.com\$" "$root/etc/systemd/system/parallux-server.service" || fail "the unit's -self is not the --host value"
if install_into "$work/badhost" --host 'vps.example.com;reboot'; then fail "a --host with a shell character was accepted"; fi
# Refused by the script itself, before the value reaches any command line.
grep -q -- "--host must be an address or a host name" "$work/err" || fail "a bad --host was not refused by the script's own check: $(cat "$work/err")"
[ ! -e "$work/badhost/etc/parallux-server/psk.tmp" ] || fail "a bad --host got as far as writing a key"

# --- the port belongs to something else (a node, a panel) -------------------
root="$work/busy"
if SHIM_BUSY=1 install_into "$root"; then fail "a busy port was accepted"; fi
grep -q "already in use" "$work/err" || fail "the error for a busy port does not say so: $(cat "$work/err")"
[ ! -e "$root/etc/parallux-server/psk" ] || fail "a busy port still wrote a key"
# Our own running service holding the port is a reinstall, not a conflict.
install_into "$root" || fail "an install on a free port exited $?"
SHIM_BUSY=1 install_into "$root" || fail "a reinstall was refused because our own service holds the port"

# --- a relay host -----------------------------------------------------------
root="$work/relay"
SHIM_SRC=10.0.0.21 install_into "$root" --relay --name worker-1 || fail "a relay install exited $? ($(cat "$work/err"))"
key_file="$root/etc/parallux-server/relay.key"
[ "$(mode_of "$key_file")" = 600 ] || fail "the relay key's mode is $(mode_of "$key_file"), want 600"
grep -q -- "^ExecStart=$root/usr/local/bin/parallux-server -role relay -port 39100 -key-file $key_file\$" "$root/etc/systemd/system/parallux-relay.service" \
  || fail "the relay unit is wrong: $(grep ExecStart "$root/etc/systemd/system/parallux-relay.service")"
tail -n 1 "$work/out" | grep -q '^parallux://relay?v=1&host=10.0.0.21&port=39100&method=2022-blake3-aes-128-gcm&key=[A-Za-z0-9%]*#worker-1$' \
  || fail "the relay link has the wrong shape"
relay_key="$(tr -d '\n' <"$key_file")"
SHIM_SRC=10.0.0.21 install_into "$root" --relay || fail "a relay reinstall exited $?"
[ "$(tr -d '\n' <"$key_file")" = "$relay_key" ] || fail "a relay reinstall replaced the key"

echo "test-install: 7 scenarios ok"
