import Foundation
import Testing

/// project.yml is the source of both Info.plist files (decision 8). macOS
/// refuses to activate a network system extension whose plist lacks
/// NSSystemExtensionUsageDescription (author's test, 2026-11-19).
@Suite struct ProjectConfigTests {
    @Test func theSystemExtensionDeclaresItsUsageDescription() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("project.yml")
        let text = try String(contentsOf: project, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("  PacketTunnel:") })
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("  ") && !$0.hasPrefix("   ") } ?? lines.count
        let target = lines[start..<end]
        #expect(target.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("NSSystemExtensionUsageDescription:") })
    }
}
