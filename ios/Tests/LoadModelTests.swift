import Foundation
import Testing
@testable import BatteryETA

let loadStart = kyiv("2026-10-01 00:00")

// A sample every 15 minutes for `days` days from `from`; `load` returns the backup-socket watts.
func loadSamples(days: Int, from: Date = loadStart, load: (Date) -> Int?) -> [Sample] {
    stride(from: 0, to: days * 96, by: 1).map { i in
        let time = from.addingTimeInterval(Double(i) * 900)
        return Sample(time: time, socPct: 80, acW: 0, offgridW: load(time))
    }
}

func flatModel(watts: Int, days: Int = 14) -> LoadModel {
    LoadModel.fit(loadSamples(days: days) { _ in watts }, now: loadStart.addingTimeInterval(Double(days) * 86400), calendar: Schedule.kyiv)!
}

struct LoadModelTests {
    private let kyivCalendar = Schedule.kyiv
    private let now = loadStart.addingTimeInterval(14 * 86400)

    @Test func aFlatLoadIsLearned() throws {
        let model = try #require(LoadModel.fit(loadSamples(days: 14) { _ in 500 }, now: now, calendar: kyivCalendar))
        #expect(model.days == 14)
        for time in ["2026-10-15 03:00", "2026-10-15 12:00", "2026-10-17 20:00"] {
            #expect(abs(model.watts(at: kyiv(time), recentW: 500, calendar: kyivCalendar) - 500) < 10)
        }
    }

    @Test func anEveningPeakIsLearned() throws {
        let samples = loadSamples(days: 14) { time in (18..<21).contains(kyivCalendar.component(.hour, from: time)) ? 1200 : 300 }
        let model = try #require(LoadModel.fit(samples, now: now, calendar: kyivCalendar))
        #expect(model.watts(at: kyiv("2026-10-15 19:00"), recentW: 500, calendar: kyivCalendar) > 1000)
        #expect(model.watts(at: kyiv("2026-10-15 10:00"), recentW: 300, calendar: kyivCalendar) < 400)
    }

    @Test func theLoadJustBeforeShiftsTheForecast() throws {
        let samples = loadSamples(days: 14) { time in kyivCalendar.component(.day, from: time) % 3 == 0 ? 900 : 300 }
        let model = try #require(LoadModel.fit(samples, now: now, calendar: kyivCalendar))
        let high = model.watts(at: kyiv("2026-10-15 10:00"), recentW: 900, calendar: kyivCalendar)
        let low = model.watts(at: kyiv("2026-10-15 10:00"), recentW: 300, calendar: kyivCalendar)
        #expect(high - low > 300)
    }

    @Test func weekendsAreTold() throws {
        let samples = loadSamples(days: 14) { time in [1, 7].contains(kyivCalendar.component(.weekday, from: time)) ? 800 : 300 }
        let model = try #require(LoadModel.fit(samples, now: now, calendar: kyivCalendar))
        #expect(model.watts(at: kyiv("2026-10-17 10:00"), recentW: 500, calendar: kyivCalendar) - model.watts(at: kyiv("2026-10-14 10:00"), recentW: 500, calendar: kyivCalendar) > 300)
    }

    @Test func underSevenDaysWithTheBackupLoadThereIsNoModel() throws {
        let readings = loadSamples(days: 6) { _ in 500 }
        let blank = loadSamples(days: 3, from: loadStart.addingTimeInterval(6 * 86400)) { _ in nil }
        #expect(LoadModel.fit(readings + blank, now: loadStart.addingTimeInterval(9 * 86400), calendar: kyivCalendar) == nil)
        let seventh = loadSamples(days: 1, from: loadStart.addingTimeInterval(6 * 86400)) { _ in 500 }
        #expect(LoadModel.fit(readings + seventh, now: loadStart.addingTimeInterval(9 * 86400), calendar: kyivCalendar)?.days == 7)
    }

    @Test func samplesOlderThanTwentyEightDaysDoNotCount() throws {
        let old = loadSamples(days: 14, from: loadStart.addingTimeInterval(-60 * 86400)) { _ in 5000 }
        let model = try #require(LoadModel.fit(old + loadSamples(days: 14) { _ in 500 }, now: now, calendar: kyivCalendar))
        #expect(model.days == 14)
        #expect(LoadModel.fit(old + loadSamples(days: 6) { _ in 500 }, now: loadStart.addingTimeInterval(6 * 86400), calendar: kyivCalendar) == nil)
    }
}
