import Foundation
import Testing
@testable import BatteryETA

struct DebugLogTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func store() -> Store {
        scratchStore()
    }

    @Test func itKeepsOnlyTheNewestLines() {
        var log = DebugLog()
        for i in 0..<(DebugLog.limit + 25) { log.add("line \(i)", at: start.addingTimeInterval(Double(i))) }
        #expect(log.lines.count == DebugLog.limit)
        #expect(log.lines.first?.text == "line 25")
        #expect(log.lines.last?.text == "line \(DebugLog.limit + 24)")
    }

    @Test func itSurvivesAReloadFromTheStore() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")
        let dir = tempDirectory()
        Store(defaults: defaults, directory: dir).log("saved 10.255.255.1:30000", at: start)
        Store(defaults: defaults, directory: dir).log("widget reload", at: start.addingTimeInterval(1))
        #expect(Store(defaults: defaults, directory: dir).log.lines.map(\.text) == ["saved 10.255.255.1:30000", "widget reload"])
    }

    @Test func itsTextHoldsTheInfoAndTheLinesNewestFirst() throws {
        var log = DebugLog()
        log.add("first", at: start)
        log.add("second", at: start.addingTimeInterval(60))
        let text = log.text(info: [("App", "1.0 (1)"), ("Battery", "10.255.255.1:30000")])
        #expect(text.hasPrefix("App: 1.0 (1)\nBattery: 10.255.255.1:30000\n\n"))
        let second = try #require(text.range(of: "second"))
        let first = try #require(text.range(of: "first"))
        #expect(second.lowerBound < first.lowerBound)
        #expect(text.contains("\(DebugLog.stamp(start))  first"))
    }

    @Test func aRefreshLogsItsResult() async {
        let store = store()
        store.settings = BatterySettings(host: "10.255.255.1", port: 30000, floorPct: 12)
        _ = await Refresher.refresh(store) { _ in reading(acW: -320) }
        _ = await Refresher.refresh(store) { _ in throw DeviceError.timeout }
        _ = await Refresher.refresh(store) { _ in throw DeviceError.blocked }
        let texts = store.log.lines.map(\.text)
        #expect(texts.count == 3)
        #expect(texts[0].hasPrefix("OK: "))
        #expect(texts[1] == "noLink: no reply (timeout)")
        #expect(texts[2] == "blocked: Local Network permission denied")
    }
}
