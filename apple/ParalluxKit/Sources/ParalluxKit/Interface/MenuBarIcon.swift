import AppKit

/// Each template uses the two halves of the app icon. The upper half carries
/// the proxy fill and the fault cut. The lower half describes aggregation.
public enum MenuBarIcon {
    fileprivate enum Shape: Hashable, Sendable {
        case disconnected, connecting, disconnecting
        case proxyOnly, waitingForLinks, balance, bond, failover
    }

    public struct State: Hashable, CaseIterable, Sendable {
        fileprivate let shape: Shape
        fileprivate let proxy: Bool
        fileprivate let warning: Bool

        fileprivate init(_ shape: Shape, proxy: Bool = false, warning: Bool = false) {
            self.shape = shape
            self.proxy = proxy
            self.warning = warning
        }

        public static let disconnected = Self(.disconnected)
        public static let connecting = Self(.connecting)
        public static let disconnecting = Self(.disconnecting)
        public static let connectionFailed = Self(.disconnected, warning: true)
        public static let balance = Self(.balance)
        public static let bond = Self(.bond, proxy: true)
        public static let failover = Self(.failover)
        public static let degraded = Self(.balance, warning: true)

        private static let running: [Self] = [
            Self(.proxyOnly, proxy: true),
            Self(.waitingForLinks), Self(.waitingForLinks, proxy: true),
            .balance, Self(.balance, proxy: true),
            .failover, Self(.failover, proxy: true), .bond,
        ]
        public static let allCases = [disconnected, connecting, disconnecting, connectionFailed]
            + running.flatMap { [$0, Self($0.shape, proxy: $0.proxy, warning: true)] }

        /// The filled upper half means the switch is on. A rule can still send an
        /// individual connection directly. A saved preference is idle when off.
        public static func resolve(tunnel: StatusLine.Tunnel, switches: ConnectionSwitches,
                                   effectiveMode: AggregationMode?, serviceError: Bool, linkError: Bool) -> Self {
            switch tunnel {
            case .disconnected: return serviceError ? .connectionFailed : .disconnected
            case .connecting: return .connecting
            case .disconnecting: return .disconnecting
            case .connected: break
            }
            guard switches != .none else { return .disconnecting }
            guard switches.aggregation else { return Self(.proxyOnly, proxy: true, warning: serviceError) }
            let shape: Shape = switch effectiveMode {
            case nil: .waitingForLinks
            case .balance: .balance
            case .failover: .failover
            // 直连流量绕过聚合服务器，叠加在此组合下按主备运行（决策 21）。
            case .bond: switches.proxy ? .bond : .failover
            }
            return Self(shape, proxy: switches.proxy, warning: serviceError || linkError)
        }

        public var title: String {
            let route: String
            switch shape {
            case .disconnected: return warning ? "连接异常" : "未连接"
            case .connecting: return "正在连接"
            case .disconnecting: return "正在断开"
            case .proxyOnly: route = "仅代理"
            case .waitingForLinks: route = "聚合待命"
            case .balance: route = AggregationMode.balance.title
            case .bond: route = AggregationMode.bond.title
            case .failover: route = AggregationMode.failover.title
            }
            let setting = shape == .proxyOnly ? "" : (proxy ? " · 代理开启" : " · 代理关闭")
            return route + setting + (warning ? " · 异常" : "")
        }
    }

    public static let pointSize: CGFloat = 18

    public static func image(for state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(state, in: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Parallux " + state.title
        return image
    }

    private enum HalfStyle { case solid, outline, arc }

    /// The endpoints ease into the diameter like the two layers in AppIcon.icon.
    /// The same contour bounds both the hollow and the filled half.
    private static func addCap(to path: CGMutablePath, halfWidth w: CGFloat, height h: CGFloat, base: CGFloat) {
        path.move(to: CGPoint(x: -0.92 * w, y: base))
        path.addQuadCurve(to: CGPoint(x: -0.994 * w, y: base - 0.10 * h),
                          control: CGPoint(x: -w, y: base))
        path.addCurve(to: CGPoint(x: 0, y: base - h),
                      control1: CGPoint(x: -0.94 * w, y: base - 0.63 * h),
                      control2: CGPoint(x: -0.51 * w, y: base - h))
        path.addCurve(to: CGPoint(x: 0.994 * w, y: base - 0.10 * h),
                      control1: CGPoint(x: 0.51 * w, y: base - h),
                      control2: CGPoint(x: 0.94 * w, y: base - 0.63 * h))
        path.addQuadCurve(to: CGPoint(x: 0.92 * w, y: base),
                          control: CGPoint(x: w, y: base))
        path.closeSubpath()
    }

    private static func half(_ context: CGContext, at center: CGPoint, radius: CGFloat, style: HalfStyle,
                             lower: Bool = false, interrupted: Bool = false) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center.x, y: center.y)
        if lower { context.rotate(by: .pi) }

        // These dimensions are optical adjustments for the existing 18 pt canvas.
        // One common rim stays legible at 1× and matches the weight of nearby system symbols.
        let rim: CGFloat = 1.5
        if interrupted {
            // Trim the tip perpendicular to the seam. The flat end is wide
            // enough to read at 1× and leaves the active fill and lower half visible.
            let extent = radius + rim
            let cutAt = 0.45 * radius
            context.clip(to: CGRect(x: -extent, y: -extent, width: extent + cutAt, height: 2 * extent))
        }

        if style == .arc {
            context.setLineWidth(rim)
            context.setLineCap(.round)
            context.addArc(center: .zero, radius: radius - rim / 2,
                           startAngle: .pi + 0.12, endAngle: 2 * .pi - 0.12, clockwise: false)
            context.strokePath()
        } else {
            let path = CGMutablePath()
            addCap(to: path, halfWidth: radius, height: radius, base: 0)
            if style == .outline {
                addCap(to: path, halfWidth: radius - rim * 1.25, height: radius - 2 * rim, base: -rim)
            }
            context.addPath(path)
            context.drawPath(using: .eoFill)
        }
    }

    private static func draw(_ state: State, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let ink = CGColor(gray: 0, alpha: 1)
        context.setFillColor(ink)
        context.setStrokeColor(ink)
        context.translateBy(x: pointSize / 2, y: pointSize / 2)
        context.rotate(by: -35 * .pi / 180)

        let primary: HalfStyle = state.proxy ? .solid : .outline
        let styles: (upper: HalfStyle, lower: HalfStyle) = switch state.shape {
        case .disconnected: (.arc, .arc)
        case .connecting: (.outline, .arc)
        case .disconnecting: (.arc, .outline)
        case .proxyOnly: (primary, .arc)
        case .waitingForLinks: (primary, .outline)
        case .balance, .failover, .bond: (primary, .solid)
        }

        // Measured against the master mark: the two centers differ by about half
        // a radius along the seam. In 叠加 both centers sit on one axis.
        let radius: CGFloat = 6.55
        let offset: CGFloat = state.shape == .bond ? 0 : 1.65
        // A 1.6 pt seam stays open even across diagonally adjacent 1× pixels.
        let halfGap: CGFloat = state.shape == .bond ? 0.80 : 1.06
        let secondRadius = state.shape == .failover ? radius * 0.62 : radius
        half(context, at: CGPoint(x: -offset, y: -halfGap), radius: radius, style: styles.upper,
             interrupted: state.warning)
        half(context, at: CGPoint(x: offset, y: halfGap), radius: secondRadius, style: styles.lower, lower: true)
    }
}
