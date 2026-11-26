import AppKit
import Testing
@testable import ParalluxKit

@MainActor @Suite struct MenuBarSilhouetteTests {
    /// Use the actual AppKit image. A bitmap coordinate here is one physical pixel.
    private struct Ink {
        let side: Int
        let pixels: Set<Int>

        init(_ state: MenuBarIcon.State, scale: Int) throws {
            let image = MenuBarIcon.image(for: state)
            side = Int(image.size.width) * scale
            let bitmap = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            let rgba = try #require(bitmap.data?.assumingMemoryBound(to: UInt8.self))
            pixels = Set((0..<(side * side)).filter { rgba[4 * $0 + 3] >= 128 })
        }

        /// Flood transparent pixels from the canvas perimeter. The remaining
        /// transparent pixels are enclosed by the original silhouette.
        var exterior: Set<Int> {
            var visited = Set<Int>()
            var pending: [Int] = []
            func visit(_ pixel: Int) {
                if !pixels.contains(pixel), visited.insert(pixel).inserted { pending.append(pixel) }
            }
            for n in 0..<side {
                visit(n)
                visit((side - 1) * side + n)
                visit(n * side)
                visit(n * side + side - 1)
            }
            while let pixel = pending.popLast() {
                let x = pixel % side
                let y = pixel / side
                if x > 0 { visit(pixel - 1) }
                if x + 1 < side { visit(pixel + 1) }
                if y > 0 { visit(pixel - side) }
                if y + 1 < side { visit(pixel + side) }
            }
            return visited
        }
    }

    @Test func turningOnTheProxyFillsOnlyAnEnclosedPartOfTheMark() throws {
        // With two switches the three comparable modes are waiting, balance and failover.
        let modes: [AggregationMode?] = [nil, .balance, .failover]
        for scale in [1, 2] {
            for mode in modes {
                let direct = MenuBarIcon.State.resolve(tunnel: .connected, switches: .init(aggregation: true, proxy: false),
                                                       effectiveMode: mode, serviceError: false, linkError: false)
                let proxied = MenuBarIcon.State.resolve(tunnel: .connected, switches: .both,
                                                        effectiveMode: mode, serviceError: false, linkError: false)
                let outline = try Ink(direct, scale: scale)
                let filled = try Ink(proxied, scale: scale)
                let message = Comment(rawValue: "\(direct.title) @\(scale)x")
                try #require(outline.pixels.isStrictSubset(of: filled.pixels), message)
                try #require(filled.pixels.isDisjoint(with: outline.exterior), message)
            }
        }
    }

    @Test func aFaultOnlyRemovesInkFromTheHealthyMark() throws {
        var pairs = [(MenuBarIcon.State.disconnected, MenuBarIcon.State.connectionFailed)]
        for switches in [ConnectionSwitches(aggregation: false, proxy: true),
                         .init(aggregation: true, proxy: false), .both] {
            let modes: [AggregationMode?] = switches.aggregation ? [nil, .balance, .failover] : [nil]
            for mode in modes + (switches == .both ? [.bond] : []) {
                let healthy = MenuBarIcon.State.resolve(tunnel: .connected, switches: switches, effectiveMode: mode,
                                                        serviceError: false, linkError: false)
                let fault = MenuBarIcon.State.resolve(tunnel: .connected, switches: switches, effectiveMode: mode,
                                                      serviceError: true, linkError: false)
                pairs.append((healthy, fault))
            }
        }
        #expect(pairs.count == 9)
        for scale in [1, 2] {
            for (healthy, fault) in pairs {
                let original = try Ink(healthy, scale: scale)
                let interrupted = try Ink(fault, scale: scale)
                try #require(interrupted.pixels.isStrictSubset(of: original.pixels), "\(fault.title) @\(scale)x")
            }
        }
    }
}
