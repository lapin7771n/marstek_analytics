import Foundation
import Testing
@testable import BatteryETA

struct OutageTests {
    private let readAt = Date(timeIntervalSince1970: 1_760_000_000)

    private func hours(_ h: Double) -> Date { readAt.addingTimeInterval(h * 3600) }

    @Test func lastsWithSpare() throws {
        let verdict = Outage.verdict(reading(acW: 400), floorPct: 12, powerBack: hours(6), now: readAt)
        guard case let .lasts(until, spare) = verdict else { Issue.record("\(String(describing: verdict))"); return }
        #expect(until == hours(6))
        #expect(abs(try #require(spare) - 2.0427) < 0.001)
    }

    @Test func runsOutBeforePowerReturns() {
        let verdict = Outage.verdict(reading(acW: 400), floorPct: 12, powerBack: hours(10), now: readAt)
        guard case let .short(runsOut, short, _) = verdict else { Issue.record("\(String(describing: verdict))"); return }
        #expect(abs(runsOut.timeIntervalSince(hours(8.0427))) < 5)
        #expect(abs(short - 1.9573) < 0.001)
    }

    @Test func countsFromTheReadingNotFromNow() {
        let verdict = Outage.verdict(reading(acW: 400), floorPct: 12, powerBack: hours(10), now: hours(1))
        guard case let .short(_, short, _) = verdict else { Issue.record("\(String(describing: verdict))"); return }
        #expect(abs(short - 1.9573) < 0.001)
    }

    @Test func nothingOncePowerIsBack() {
        #expect(Outage.verdict(reading(acW: 400), floorPct: 12, powerBack: hours(6), now: hours(6)) == nil)
    }

    @Test func nothingWhileCharging() {
        #expect(Outage.verdict(reading(acW: -500), floorPct: 12, powerBack: hours(6), now: readAt) == nil)
    }

    @Test func idleWithoutLoadLasts() {
        #expect(Outage.verdict(reading(soc: 60, acW: 0), floorPct: 12, powerBack: hours(6), now: readAt) == .lasts(until: hours(6), spareHours: nil))
    }

    @Test(arguments: [(0.0, "0 min"), (40.0 / 60, "40 min"), (2.05, "2 h 03 min"), (10.0, "10 h 00 min")])
    func spansUseWholeMinutes(hours: Double, text: String) {
        #expect(formatSpan(hours) == text)
    }
}

struct PowerBackTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    private func at(_ text: String) -> Date {
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.date(from: text)!
    }

    @Test(arguments: [("2026-10-15 18:00", "2026-10-15 18:00"), ("2026-10-15 09:30", "2026-10-16 09:30"), ("2026-10-15 14:00", "2026-10-16 14:00")])
    func aPickedTimeIsTodayOrTomorrow(picked: String, expected: String) {
        #expect(Outage.nextTime(at(picked), after: at("2026-10-15 14:00"), calendar: calendar) == at(expected))
    }

    @Test func tomorrowKeepsTheTime() {
        #expect(Outage.moved(at("2026-10-15 18:00"), tomorrow: true, now: at("2026-10-15 14:00"), calendar: calendar) == at("2026-10-16 18:00"))
    }

    @Test func todayOnlyWhileTheTimeIsAhead() {
        let now = at("2026-10-15 14:00")
        #expect(Outage.moved(at("2026-10-16 18:00"), tomorrow: false, now: now, calendar: calendar) == at("2026-10-15 18:00"))
        #expect(Outage.moved(at("2026-10-16 09:00"), tomorrow: false, now: now, calendar: calendar) == at("2026-10-16 09:00"))
    }
}
