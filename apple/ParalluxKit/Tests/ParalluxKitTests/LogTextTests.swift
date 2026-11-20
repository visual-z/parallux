@testable import ParalluxKit
import Testing

@Suite struct LogTextTests {
    @Test func logMessagesDropTerminalColorCodes() {
        let esc = "\u{1B}"
        func message(_ raw: String) -> String { LogEntry(id: 1, level: .info, message: raw).message }
        #expect(message("\(esc)[36mINFO\(esc)[0m[0061] [\(esc)[38;5;224m2116080080\(esc)[0m 0ms] outbound/direct[link-en0]: outbound connection to 223.5.5.5:53")
            == "INFO[0061] [2116080080 0ms] outbound/direct[link-en0]: outbound connection to 223.5.5.5:53")
        #expect(message("") == "")
        #expect(message("plain [link-en7] text") == "plain [link-en7] text")
        #expect(message("\(esc)[2Kcleared") == "cleared", "any CSI, not only colours")
        #expect(message("tail \(esc)[") == "tail ")
        #expect(message("tail \(esc)[38;5") == "tail ")
    }
}
