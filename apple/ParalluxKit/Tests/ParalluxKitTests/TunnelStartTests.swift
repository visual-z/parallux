import Foundation
@testable import ParalluxKit
import Testing

/// A failed start must reach the app as an error it
/// can show, and a new build must replace the extension it finds installed.
@Suite struct TunnelStartTests {
    /// Stands in for gomobile's `Universeerror`, a class nesessionmanager has
    /// not loaded: archived under a name no process can resolve.
    final class ForeignError: NSError, @unchecked Sendable {
        override class var supportsSecureCoding: Bool { true }
    }

    @Test func providerErrorsSurviveSecureDecodingAsPlainNSError() throws {
        let foreign = ForeignError(domain: "go", code: 1, userInfo: [NSLocalizedDescriptionKey: "start router: dial udp 223.5.5.5:53"])
        // The unfixed path: the foreign class itself cannot be decoded.
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("Universeerror", for: ForeignError.self)
        archiver.encode(ProviderError.portable(foreign), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        // nesessionmanager drops a message it cannot decode; report that here
        // as a failure instead of an uncaught exception.
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        let decoded = unarchiver.decodeObject(of: NSError.self, forKey: NSKeyedArchiveRootObjectKey)
        let error = try #require(decoded, "decoding failed: \(String(describing: unarchiver.error))")
        #expect(type(of: error) == NSError.self)
        #expect(error.domain == ProviderError.domain)
        #expect(error.localizedDescription == "start router: dial udp 223.5.5.5:53")
        #expect(error.userInfo[NSUnderlyingErrorKey] == nil, "the underlying error would bring the foreign class back")
        #expect(error.userInfo.values.allSatisfy { $0 is String })
    }

    @Test func startErrorSummariesKeepTheFirstCauseAndStayShort() {
        #expect(ProviderError.summary("") == "")
        #expect(ProviderError.summary("one") == "one")
        let many = (0..<40).map { "initialize rule-set[\($0)]: lookup example.com: operation not permitted" }.joined(separator: " | ")
        let summary = ProviderError.summary("start router: (" + many + ")")
        #expect(summary.hasPrefix("start router: (initialize rule-set[0]: lookup example.com: operation not permitted"))
        #expect(summary.count <= ProviderError.summaryLimit)
        #expect(summary.contains("39"), "says how many more causes were dropped")
        let long = String(repeating: "x", count: 5000)
        #expect(ProviderError.summary(long).count <= ProviderError.summaryLimit)
    }

    @Test func aNewBuildReplacesTheInstalledExtension() {
        let bundled = ExtensionVersion(short: "0.0.1", build: "20261119061905")
        #expect(ExtensionVersion.needsActivation(installed: nil, bundled: bundled))
        #expect(ExtensionVersion.needsActivation(installed: ExtensionVersion(short: "0.0.1", build: "20261119060604"), bundled: bundled))
        #expect(ExtensionVersion.needsActivation(installed: ExtensionVersion(short: "0.0.2", build: "20261119061905"), bundled: bundled))
        #expect(!ExtensionVersion.needsActivation(installed: bundled, bundled: bundled))
        // Downgrades too: the app talks to the Mach service of its own build.
        #expect(ExtensionVersion.needsActivation(installed: ExtensionVersion(short: "0.0.1", build: "20261120000000"), bundled: bundled))
    }
}
