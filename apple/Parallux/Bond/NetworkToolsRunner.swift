import Foundation
import Libbox
import Observation

/// SFM #97 网络质量 and #98 STUN, through a chosen outbound of the running core.
@MainActor @Observable
final class NetworkToolsRunner {
    struct Quality: Equatable {
        var download: Int64 // bits per second
        var upload: Int64
        var downloadRPM: Int32
        var uploadRPM: Int32
        var idleLatencyMs: Int32
    }

    struct STUN: Equatable {
        var externalAddress: String
        var latencyMs: Int32
        var mapping: String
        var filtering: String
    }

    private(set) var quality: Quality?
    private(set) var stun: STUN?
    private(set) var running: String?
    private(set) var error: String?

    /// Why 20 s: libbox's default (LibboxNetworkQualityDefaultMaxRuntimeSeconds) is in this range; a bound keeps a stuck test finite.
    nonisolated static let qualitySeconds: Int32 = 20

    func runQuality(outbound: String) {
        guard running == nil else { return }
        running = "网络质量"
        error = nil
        let handler = QualityHandler { [weak self] result, message in
            Task { @MainActor in
                self?.running = nil
                self?.quality = result
                self?.error = message
            }
        }
        Task.detached {
            do {
                guard let client = LibboxNewStandaloneCommandClient() else { throw CocoaError(.featureUnsupported) }
                handler.session = try client.startNetworkQualityTest(LibboxNetworkQualityDefaultConfigURL, outboundTag: outbound,
                                                                     serial: false, maxRuntimeSeconds: Self.qualitySeconds, http3: false, handler: handler)
            } catch {
                handler.finish(nil, error.localizedDescription)
            }
        }
    }

    func runSTUN(outbound: String) {
        guard running == nil else { return }
        running = "STUN"
        error = nil
        let handler = STUNHandler { [weak self] result, message in
            Task { @MainActor in
                self?.running = nil
                self?.stun = result
                self?.error = message
            }
        }
        Task.detached {
            do {
                guard let client = LibboxNewStandaloneCommandClient() else { throw CocoaError(.featureUnsupported) }
                handler.session = try client.startSTUNTest(LibboxSTUNDefaultServer, outboundTag: outbound, handler: handler)
            } catch {
                handler.finish(nil, error.localizedDescription)
            }
        }
    }

    private final class QualityHandler: NSObject, LibboxNetworkQualityTestHandlerProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var done: ((Quality?, String?) -> Void)?
        var session: LibboxNetworkQualityTestSession?
        init(_ done: @escaping (Quality?, String?) -> Void) { self.done = done }
        func finish(_ value: Quality?, _ message: String?) {
            lock.lock(); let callback = done; done = nil; lock.unlock()
            callback?(value, message)
        }
        func onError(_ message: String?) { finish(nil, message ?? "失败") }
        func onProgress(_: LibboxNetworkQualityProgress?) {}
        func onResult(_ result: LibboxNetworkQualityResult?) {
            guard let result else { return finish(nil, "没有结果") }
            finish(Quality(download: result.downloadCapacity, upload: result.uploadCapacity, downloadRPM: result.downloadRPM,
                           uploadRPM: result.uploadRPM, idleLatencyMs: result.idleLatencyMs), nil)
        }
    }

    private final class STUNHandler: NSObject, LibboxSTUNTestHandlerProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var done: ((STUN?, String?) -> Void)?
        var session: LibboxSTUNTestSession?
        init(_ done: @escaping (STUN?, String?) -> Void) { self.done = done }
        func finish(_ value: STUN?, _ message: String?) {
            lock.lock(); let callback = done; done = nil; lock.unlock()
            callback?(value, message)
        }
        func onError(_ message: String?) { finish(nil, message ?? "失败") }
        func onProgress(_: LibboxSTUNTestProgress?) {}
        func onResult(_ result: LibboxSTUNTestResult?) {
            guard let result else { return finish(nil, "没有结果") }
            finish(STUN(externalAddress: result.externalAddr, latencyMs: result.latencyMs,
                        mapping: result.natTypeSupported ? LibboxFormatNATMapping(result.natMapping) : "不支持",
                        filtering: result.natTypeSupported ? LibboxFormatNATFiltering(result.natFiltering) : "不支持"), nil)
        }
    }
}
