import Foundation
import Libbox
import Observation
import ParalluxKit

/// 单线程下载测速: one serial (single-connection) network quality test per
/// link outbound, then one through the bond, all inside the extension's core.
@MainActor @Observable
final class SpeedTestRunner {
    private(set) var results: [SpeedTest.Result] = []
    private(set) var current: String?
    private(set) var error: String?
    var isRunning: Bool { current != nil }

    /// Why 10 s: long enough for TCP to leave slow start on a few hundred Mbps,
    /// short enough to run four paths in under a minute. Assumed.
    nonisolated static let secondsPerPath: Int32 = 10

    func run(paths: [(label: String, outbound: String, isBond: Bool)]) {
        guard !isRunning else { return }
        results = []
        error = nil
        Task {
            for path in paths {
                current = path.label
                let rate = await Self.measure(outbound: path.outbound)
                results.append(SpeedTest.Result(label: path.label, rate: rate, isBond: path.isBond))
            }
            current = nil
        }
    }

    /// Bytes per second, or nil when the test fails.
    nonisolated static func measure(outbound: String) async -> Int64? {
        await withCheckedContinuation { continuation in
            let handler = Handler { continuation.resume(returning: $0) }
            Task.detached {
                guard let client = try? CommandTarget.standalone() else {
                    handler.finish(nil)
                    return
                }
                do {
                    let session = try client.startNetworkQualityTest(LibboxNetworkQualityDefaultConfigURL, outboundTag: outbound,
                                                                     serial: true, maxRuntimeSeconds: secondsPerPath, http3: false, handler: handler)
                    handler.session = session
                } catch {
                    handler.finish(nil)
                }
            }
        }
    }

    private final class Handler: NSObject, LibboxNetworkQualityTestHandlerProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var done: ((Int64?) -> Void)?
        var session: LibboxNetworkQualityTestSession?

        init(_ done: @escaping (Int64?) -> Void) { self.done = done }

        func finish(_ value: Int64?) {
            lock.lock()
            let callback = done
            done = nil
            lock.unlock()
            callback?(value)
        }

        func onError(_ message: String?) { finish(nil) }
        func onProgress(_ progress: LibboxNetworkQualityProgress?) {}
        // Capacity is bits per second (sing-box common/networkquality FormatBitrate).
        func onResult(_ result: LibboxNetworkQualityResult?) {
            finish(result.map { $0.downloadCapacity / 8 })
        }
    }
}
