#!/usr/bin/env bash
# Runs ParalluxKit's Swift Testing suite and writes a JUnit report for keel.
#   scripts/swift-test.sh <junit-path> [filter]
# SwiftPM writes Swift Testing results next to the requested path with a
# "-swift-testing" suffix; this moves that file to where keel expects it.
set -euo pipefail
source "$(dirname "$0")/env.sh"
junit="$1"; shift
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
args=(--package-path "$ROOT/apple/ParalluxKit" --xunit-output "$tmp/report.xml")
if [ $# -gt 0 ] && [ -n "$1" ]; then args+=(--filter "$1"); fi
status=0
swift test "${args[@]}" || status=$?
if [ -f "$tmp/report-swift-testing.xml" ]; then
  mv "$tmp/report-swift-testing.xml" "$junit"
fi
exit "$status"
