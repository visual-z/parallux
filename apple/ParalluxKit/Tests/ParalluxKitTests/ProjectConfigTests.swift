import Foundation
import Testing

/// project.yml is the source of both Info.plist files (decision 8). macOS
/// refuses to activate a network system extension whose plist lacks
/// NSSystemExtensionUsageDescription (author's test, 2026-11-19).
@Suite struct ProjectConfigTests {
    private func packetTunnelBlock() throws -> [String] {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("project.yml")
        let text = try String(contentsOf: project, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("  PacketTunnel:") })
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("  ") && !$0.hasPrefix("   ") } ?? lines.count
        return Array(lines[start..<end]).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    @Test func theSystemExtensionDeclaresItsUsageDescription() throws {
        #expect(try packetTunnelBlock().contains { $0.hasPrefix("NSSystemExtensionUsageDescription:") })
    }

    /// Without these the sandboxed core gets EPERM on
    /// its first DNS query; SFM's signed extension carries both.
    @Test func theSystemExtensionCanOpenNetworkSockets() throws {
        let block = try packetTunnelBlock()
        #expect(block.contains("com.apple.security.network.client: true"))
        #expect(block.contains("com.apple.security.network.server: true"))
    }
}
