import Testing
@testable import ParalluxKit

@Suite struct StatusLineTests {
    @Test func aCoreStreamErrorReplacesConnectedInTheStatusLine() {
        #expect(StatusLine.text(setup: .ready, tunnel: .connected, actionError: nil, coreError: nil, linkKind: "Wi‑Fi") == "已连接 · 1 条线路（Wi‑Fi）")
        #expect(StatusLine.text(setup: .ready, tunnel: .connected, actionError: nil, coreError: nil, linkKind: nil) == "已连接")
        #expect(StatusLine.text(setup: .ready, tunnel: .connected, actionError: nil, coreError: nil, linkKind: "叠加 · 3 条线路") == "已连接 · 叠加 · 3 条线路")
        let failed = StatusLine.text(setup: .ready, tunnel: .connected, actionError: nil, coreError: "dial xpc: connection refused", linkKind: "Wi‑Fi")
        #expect(failed.contains("dial xpc: connection refused"))
        #expect(!failed.hasPrefix("已连接 ·"))
        // A stale stream error does not linger once the tunnel is down.
        #expect(StatusLine.text(setup: .ready, tunnel: .disconnected, actionError: nil, coreError: "old", linkKind: nil) == "未连接")
    }

    @Test func setupAndActionErrorsComeFirst() {
        #expect(StatusLine.text(setup: .awaitingApproval, tunnel: .disconnected, actionError: nil, coreError: nil, linkKind: nil) == "需要在系统设置中授权")
        #expect(StatusLine.text(setup: .failed("x"), tunnel: .disconnected, actionError: nil, coreError: nil, linkKind: nil) == "x")
        #expect(StatusLine.text(setup: .ready, tunnel: .connected, actionError: "读不到配置", coreError: nil, linkKind: nil) == "读不到配置")
        #expect(StatusLine.text(setup: .ready, tunnel: .connecting, actionError: nil, coreError: nil, linkKind: nil) == "正在连接…")
        #expect(StatusLine.text(setup: .ready, tunnel: .disconnecting, actionError: nil, coreError: nil, linkKind: nil) == "正在断开…")
    }
}
