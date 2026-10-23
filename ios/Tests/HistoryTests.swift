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
        let store = scratchStore()
        store.settings = BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 12)
        return store
    }

    @Test func aGoodFetchAddsASample() async {
        let store = store()
        _ = await Refresher.refresh(store, now: start) { _ in at(0) }
        #expect(store.history.samples == [Sample(time: start, socPct: 80, acW: 400, offgridW: 0)])
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

    @Test func twentyNineDaysOfPollingKeepTwentyEight() throws {
        var history = History()
        for minute in stride(from: 0.0, through: 29 * 24 * 60, by: 5) { history.add(at(minute)) }
        let last = try #require(history.samples.last).time
        #expect(history.samples.count == 8065)
        #expect(history.samples.allSatisfy { last.timeIntervalSince($0.time) <= 28 * 24 * 3600 })
        #expect(try JSONEncoder().encode(history).count < 600_000)
    }

    @Test func historySurvivesANewStore() async {
        let dir = tempDirectory()
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")
        let first = Store(defaults: defaults, directory: dir)
        first.settings = BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 12)
        _ = await Refresher.refresh(first, now: start) { _ in at(0) }
        #expect(Store(defaults: defaults, directory: dir).history.samples.count == 1)
    }

    @Test func historySavedBy12MovesToTheFile() throws {
        let dir = tempDirectory()
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        defaults.set(Data(#"{"samples":[{"t":781000000,"s":64,"w":0}]}"#.utf8), forKey: "history")
        let store = Store(defaults: defaults, directory: dir)
        #expect(store.history.samples.count == 1)
        #expect(store.history.samples.first?.offgridW == nil)
        store.history = store.history
        #expect(defaults.data(forKey: "history") == nil)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "history.json").path))
        #expect(Store(defaults: defaults, directory: dir).history.samples.count == 1)
    }

    @Test func aSampleKeepsTheBackupLoad() {
        #expect(Sample(reading(acW: 820, offgridW: 640)).offgridW == 640)
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
        let store = Store(defaults: defaults, directory: tempDirectory())
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

    // Kyiv leaves summer time on 25 Oct 2026, so the week below holds a 25-hour day.
    private var kyiv: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }

    private func kyivDay(_ day: Int, _ hour: Double = 0) -> Date {
        let midnight = kyiv.date(from: DateComponents(year: 2026, month: 10, day: day))!
        return midnight.addingTimeInterval(hour * 3600)
    }

    private func sample(_ day: Int, _ hour: Double, acW: Int) -> Sample {
        Sample(time: kyivDay(day, hour), socPct: 50, acW: acW, offgridW: 0)
    }

    @Test func theWeekIsSevenDaysEndingToday() {
        let now = kyivDay(27, 15)
        let history = History(samples: [
            sample(19, 12, acW: 600), sample(19, 12.5, acW: 600),
            sample(24, 10, acW: -1200), sample(24, 10.5, acW: 600), sample(24, 11, acW: 600),
            sample(27, 8, acW: 400), sample(27, 9, acW: 400),
            sample(27, 14.5, acW: 400), sample(27, 15.5, acW: 400),
        ])
        let week = history.week(now: now, calendar: kyiv)
        #expect(week.map(\.day) == (21...27).map { kyivDay($0) })
        #expect(week[3] == DayTotal(day: kyivDay(24), chargedWh: 600, usedWh: 300, onBattery: 1800))
        #expect(week[1] == DayTotal(day: kyivDay(22), chargedWh: 0, usedWh: 0, onBattery: 0))
        #expect(week[6] == DayTotal(day: kyivDay(27), chargedWh: 0, usedWh: 400, onBattery: 3600))
        #expect(week.map(\.usedWh).reduce(0, +) == 700)
        #expect(history.day(now: now, latest: nil, calendar: kyiv).usedWh == week[6].usedWh)
    }

    @Test func eachDayIntegratesOnlyItsOwnSamples() {
        let history = History(samples: [
            sample(26, 22.5, acW: 600), sample(26, 23.5, acW: 600),
            sample(27, 0.5, acW: 600), sample(27, 1.5, acW: 600),
        ])
        let week = history.week(now: kyivDay(27, 3), calendar: kyiv)
        #expect(week[5].usedWh == 600)
        #expect(week[6].usedWh == 600)
    }
}

actor ReadingCounter {
    var count = 0

    func fetch(_ reading: Reading) -> Reading {
        count += 1
        return reading
    }
}
