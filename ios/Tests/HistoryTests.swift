import Foundation
import Testing
@testable import BatteryETA

struct HistoryTests {
    // Midnight UTC, 9 Oct 2025.
    private let start = Date(timeIntervalSince1970: 1_759_968_000)

    private func at(_ minutes: Double, soc: Int = 80, acW: Double = 400) -> Reading {
        var r = reading(soc: soc, acW: acW)
        r.time = start.addingTimeInterval(minutes * 60)
        return r
    }

    private func store() -> Store {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        store.settings = BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 12)
        return store
    }

    @Test func aGoodFetchAddsASample() async {
        let store = store()
        _ = await Refresher.refresh(store, now: start) { _ in at(0) }
        #expect(store.history.samples == [Sample(time: start, socPct: 80, acW: 400)])
    }

    @Test func aFailedFetchAddsNothing() async {
        let store = store()
        store.snapshot = Snapshot(reading: at(-10), error: nil, checkedAt: start.addingTimeInterval(-600))
        _ = await Refresher.refresh(store, now: start) { _ in throw DeviceError.timeout }
        #expect(store.history.samples.isEmpty)
    }

    @Test func aReusedSnapshotAddsNothing() async {
        let store = store()
        _ = await Refresher.refresh(store, now: start) { _ in at(0) }
        _ = await Refresher.refresh(store, now: start.addingTimeInterval(5 * 60), maxAge: 10 * 60) { _ in at(5) }
        #expect(store.history.samples.count == 1)
    }

    @Test func readingsUnderFiveMinutesApartAreThinned() {
        var history = History()
        for minute in stride(from: 0.0, through: 10, by: 0.5) { history.add(at(minute)) }
        #expect(history.samples.map(\.time) == [0.0, 5, 10].map { start.addingTimeInterval($0 * 60) })
    }

    @Test func fortyNineHoursOfPollingKeepFortyEight() throws {
        var history = History()
        for minute in stride(from: 0.0, through: 49 * 60, by: 0.5) { history.add(at(minute)) }
        let last = try #require(history.samples.last).time
        #expect(history.samples.count <= 577)
        #expect(history.samples.allSatisfy { last.timeIntervalSince($0.time) <= 48 * 3600 })
        #expect(try JSONEncoder().encode(history).count < 32_000)
    }

    @Test func aClockMovedBackDropsTheFutureSamples() {
        var history = History()
        history.add(at(60))
        history.add(at(0))
        #expect(history.samples.map(\.time) == [start])
    }

    @Test func anEmptyHistoryDoesNotTriggerAFetch() async {
        let store = store()
        store.snapshot = Snapshot(reading: at(0), error: nil, checkedAt: start)
        var fetched = false
        _ = await Refresher.refresh(store, now: start.addingTimeInterval(60), maxAge: 10 * 60) { _ in
            fetched = true
            return at(1)
        }
        #expect(!fetched)
        #expect(store.history.samples.isEmpty)
    }

    @Test func theReuseCheckIgnoresHistory() async {
        let store = store()
        store.snapshot = Snapshot(reading: at(0), error: nil, checkedAt: start)
        store.history.add(at(14))
        var fetched = false
        _ = await Refresher.refresh(store, now: start.addingTimeInterval(15 * 60), maxAge: 10 * 60) { _ in
            fetched = true
            return at(15)
        }
        #expect(fetched)
    }

    @Test func anOldSnapshotStillDecodes() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let old = #"{"reading":{"time":782000000,"socPct":80,"acW":400,"offgridW":0,"capacityWh":4121,"ratedWh":5120},"checkedAt":782000000}"#
        defaults.set(Data(old.utf8), forKey: "snapshot")
        let store = Store(defaults: defaults)
        #expect(store.snapshot?.reading?.socPct == 80)
        #expect(store.history.samples.isEmpty)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func history(_ readings: Reading...) -> History {
        var history = History()
        readings.forEach { history.add($0) }
        return history
    }

    @Test func theDayStartsAtMidnight() {
        let day = history(at(-30, soc: 50), at(10, soc: 70), at(20, soc: 90))
            .day(now: start.addingTimeInterval(30 * 60), latest: nil, calendar: utc)
        #expect(day.segments.flatMap(\.samples).map(\.socPct) == [70, 90])
        #expect(day.low == 70)
        #expect(day.high == 90)
        #expect(abs(day.usedWh - 400.0 / 6) < 0.01)
    }

    @Test func aGapOverAnHourIsDottedAndTheLiveReadingIsLast() {
        let day = history(at(0), at(10), at(90))
            .day(now: start.addingTimeInterval(92 * 60), latest: at(92, soc: 81), calendar: utc)
        #expect(day.segments.map(\.dotted) == [false, true, false])
        #expect(day.segments.map(\.samples.count) == [2, 2, 2])
        #expect(day.segments.last?.samples.last?.socPct == 81)
    }

    @Test func energyIntegratesTheStoredPower() {
        let day = history(at(0, acW: -1200), at(30, acW: 600), at(60, acW: 600), at(200, acW: 600))
            .day(now: start.addingTimeInterval(200 * 60), latest: nil, calendar: utc)
        #expect(abs(day.chargedWh - 600) < 0.01)
        #expect(abs(day.usedWh - 300) < 0.01)
    }

    @Test func historyAndTheChartSendNoExtraRequests() async {
        let store = store()
        let counter = ReadingCounter()
        _ = await Refresher.refresh(store, now: start) { _ in await counter.fetch(at(0)) }
        _ = await Refresher.refresh(store, now: start.addingTimeInterval(10 * 60)) { _ in await counter.fetch(at(10)) }
        var day: DaySummary?
        for _ in 0..<3 {
            day = store.history.day(now: start.addingTimeInterval(11 * 60), latest: store.snapshot?.reading, calendar: utc)
        }
        #expect(day?.segments.flatMap(\.samples).count == 2)
        #expect(store.history.samples.count == 2)
        #expect(await counter.count == 2)
    }

    @Test func onBatteryCountsDischargeBetweenCloseReadings() {
        let day = history(at(0, acW: 20), at(10, acW: 400), at(30, acW: -800), at(35, acW: 400), at(135, acW: 400))
            .day(now: start.addingTimeInterval(135 * 60), latest: nil, calendar: utc)
        #expect(day.onBattery == 20 * 60)
    }

    @Test func eachHourBarIsTheMeanPowerWithChargingUp() {
        let day = history(at(0, acW: 400), at(30, acW: 200), at(60, acW: -800))
            .day(now: start.addingTimeInterval(70 * 60), latest: nil, calendar: utc)
        #expect(day.hours == [
            DaySummary.HourBar(hour: start, watts: -300),
            DaySummary.HourBar(hour: start.addingTimeInterval(3600), watts: 800),
        ])
    }

    @Test func oneReadingIsEmpty() {
        #expect(history(at(0)).day(now: start.addingTimeInterval(60), latest: nil, calendar: utc).isEmpty)
    }
}

actor ReadingCounter {
    var count = 0

    func fetch(_ reading: Reading) -> Reading {
        count += 1
        return reading
    }
}
