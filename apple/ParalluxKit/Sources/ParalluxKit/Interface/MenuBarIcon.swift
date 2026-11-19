import AppKit

/// The two halves describe aggregation. The outbound arrow and the warning
/// occupy different corners so either can change without hiding the other.
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

        /// The proxy arrow means the switch is on. A rule can still send an
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

    /// A circular arc carries the silhouette of the two SVG layers at menu size.
    /// An arc omits its diameter, leaving an open end during a transition.
    private static func half(_ context: CGContext, at center: CGPoint, radius: CGFloat,
                             lower: Bool = false, style: HalfStyle = .solid) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center.x, y: center.y)
        if lower { context.rotate(by: .pi) }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -radius, y: 0))
        path.addArc(center: .zero, radius: radius, startAngle: .pi, endAngle: .pi * 2, clockwise: false)
        if style != .arc { path.closeSubpath() }
        context.addPath(path)
        context.drawPath(using: style == .solid ? .fill : .stroke)
    }

    private static func draw(_ state: State, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let ink = CGColor(gray: 0, alpha: 1)
        context.setFillColor(ink)
        context.setStrokeColor(ink)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.saveGState()
        // Keep the same anchor as the switches and health change. The right
        // edge belongs to the two indicators even when neither is present.
        context.translateBy(x: 7.2, y: 9.4)
        context.rotate(by: -35 * .pi / 180)
        context.setLineWidth(1.4)
        let upper = CGPoint(x: -1.1, y: -1)
        let lower = CGPoint(x: 1.1, y: 1.1)
        let radius: CGFloat = 5.8
        switch state.shape {
        case .disconnected:
            half(context, at: upper, radius: 5.25, style: .outline)
            half(context, at: lower, radius: 5.25, lower: true, style: .outline)
        case .connecting:
            half(context, at: .zero, radius: radius, style: .arc)
            for x: CGFloat in [-3, 0, 3] {
                context.fillEllipse(in: CGRect(x: x - 0.85, y: 1, width: 1.7, height: 1.7))
            }
        case .disconnecting:
            half(context, at: upper, radius: 4.7, style: .arc)
            half(context, at: lower, radius: 4.7, lower: true, style: .arc)
        case .proxyOnly:
            half(context, at: CGPoint(x: 0, y: 1.9), radius: 6.35)
        case .waitingForLinks:
            half(context, at: upper, radius: 5.25, style: .outline)
            context.setLineWidth(1.65)
            context.strokeLineSegments(between: [CGPoint(x: -2.2, y: 2), CGPoint(x: -0.6, y: 2),
                                                 CGPoint(x: 2.4, y: 2), CGPoint(x: 4, y: 2)])
        case .balance:
            half(context, at: upper, radius: radius)
            half(context, at: lower, radius: radius, lower: true)
        case .bond:
            half(context, at: CGPoint(x: 0, y: -0.8), radius: radius)
            half(context, at: CGPoint(x: 0, y: 0.8), radius: radius, lower: true)
            context.fill(CGRect(x: -2.1, y: -1, width: 4.2, height: 2))
        case .failover:
            half(context, at: upper, radius: radius)
            context.setLineWidth(2)
            context.strokeLineSegments(between: [CGPoint(x: -2.5, y: 2.3), CGPoint(x: 5.45, y: 2.3)])
        }
        context.restoreGState()
        if state.proxy {
            context.setLineWidth(1.65)
            context.beginPath()
            context.move(to: CGPoint(x: 12.3, y: 6.65))
            context.addLine(to: CGPoint(x: 16.5, y: 2.45))
            context.move(to: CGPoint(x: 12.9, y: 2.45))
            context.addLine(to: CGPoint(x: 16.5, y: 2.45))
            context.addLine(to: CGPoint(x: 16.5, y: 6.05))
            context.strokePath()
        }
        if state.warning {
            context.setLineWidth(2)
            context.strokeLineSegments(between: [CGPoint(x: 15.8, y: 9.4), CGPoint(x: 15.8, y: 12.8)])
            context.fillEllipse(in: CGRect(x: 14.65, y: 14.75, width: 2.3, height: 2.3))
        }
    }
}
