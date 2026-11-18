#!/usr/bin/env bash
# Cross-compiles the aggregation server for the Linux VPSes it runs on and
# lints its installer (gate step "server-build"; docs/tasks/feat-bond.md).
#   scripts/build-server.sh           build into .build/server
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"
out=.build/server
mkdir -p "$out"
for arch in amd64 arm64; do
  # CGO off: a static binary that runs on any distribution.
  CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -trimpath -o "$out/parallux-server-linux-$arch" ./server/cmd/parallux-server
done
sh -n server/install.sh
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s sh server/install.sh
fi
echo "built $out/parallux-server-linux-{amd64,arm64}; install.sh ok"
