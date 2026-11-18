#!/usr/bin/env bash
# Regenerates apple/Parallux.xcodeproj from apple/project.yml (XcodeGen).
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT/apple"
xcodegen generate --quiet
