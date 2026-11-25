#!/usr/bin/env bash
# Builds the legacy AppIcon.icns from the icon macOS resolves for a built app.
# The Icon Composer .icon compiles into Assets.car only; actool also writes an
# .icns but stops at 256 px, and the notification / Finder paths ask for
# 512 px and 1024 px renditions (docs/tasks/chore-notification-app-icon.md).
#   scripts/make-appicon-icns.sh <.app> <out.icns>
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"
app="${1:?usage: scripts/make-appicon-icns.sh <Parallux.app> <out.icns>}"
out="${2:?usage: scripts/make-appicon-icns.sh <Parallux.app> <out.icns>}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat >"$work/icon.swift" <<'SWIFT'
import AppKit
let img = NSWorkspace.shared.icon(forFile: CommandLine.arguments[1])
img.size = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
// A bundle macOS cannot read yields the generic placeholder (blue-grey). The
// shipped icon is cream over two warm halves, so red >= green >= blue; if that
// does not hold, fail loudly instead of shipping the placeholder as the icon.
func sample(_ x: Int, _ y: Int) -> (Double, Double, Double) {
    guard let px = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return (0, 0, 0) }
    return (px.redComponent, px.greenComponent, px.blueComponent)
}
for (x, y) in [(512, 512), (512, 300), (300, 700), (700, 300)] {
    let (r, g, b) = sample(x, y)
    guard r >= g, g >= b else {
        FileHandle.standardError.write("make-appicon-icns: \(img) at \(x),\(y) is not the Parallux artwork (r=\(r) g=\(g) b=\(b))\n".data(using: .utf8)!)
        exit(1)
    }
}
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
SWIFT
swift "$work/icon.swift" "$app" "$work/icon_1024.png"
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
while read -r name size; do
  sips -z "$size" "$size" "$work/icon_1024.png" --out "$iconset/$name.png" >/dev/null
done <<'SIZES'
icon_16x16 16
icon_16x16@2x 32
icon_32x32 32
icon_32x32@2x 64
icon_128x128 128
icon_128x128@2x 256
icon_256x256 256
icon_256x256@2x 512
icon_512x512 512
icon_512x512@2x 1024
SIZES
iconutil -c icns "$iconset" -o "$out"
# iconutil writes with the caller's umask; a 0600 icon still loads but ships a
# bundle whose resources differ by machine (docs/tasks/chore-notification-app-icon.md).
chmod 644 "$out"
echo "wrote $out"
