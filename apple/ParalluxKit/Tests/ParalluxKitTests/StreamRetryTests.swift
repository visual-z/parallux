@testable import ParalluxKit
import Testing

@Suite struct StreamRetryTests {
    @Test func streamRetriesGrowAndStopAtTheLimit() throws {
        #expect(StreamRetry.attemptLimit > 1, "a reload needs more than one try")
        let first = try #require(StreamRetry.delay(after: 0))
        #expect(first > .zero && first <= .seconds(1))
        _ = try #require(StreamRetry.delay(after: 1))
        var previous = Duration.zero
        for attempt in 0..<StreamRetry.attemptLimit {
            let delay = try #require(StreamRetry.delay(after: attempt))
            #expect(delay >= previous)
            previous = delay
        }
        #expect(StreamRetry.delay(after: StreamRetry.attemptLimit) == nil)
        #expect(StreamRetry.delay(after: StreamRetry.attemptLimit + 100) == nil)
        #expect(StreamRetry.delay(after: -1) == nil)
    }
}
