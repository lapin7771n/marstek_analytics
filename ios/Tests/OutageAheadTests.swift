import Foundation
import Testing
@testable import BatteryETA

struct OutageAheadTests {
    private let cal = Schedule.kyiv
    private let now = kyiv("2026-10-15 10:00")

    private func read(offgridW: Double = 750) -> Reading {
        Reading(time: now, socPct: 82, acW: offgridW, offgridW: offgridW, capacityWh: 4198.4, ratedWh: 5120)
    }

    private var noon: ScheduleAnswer { .off(from: kyiv("2026-10-15 12:00"), until: kyiv("2026-10-15 17:00")) }

    private func check(_ r: Reading? = nil, _ answer: ScheduleAnswer? = nil, model: LoadModel? = nil, recentW: Double = 750) -> OutageWarning? {
        OutageAhead.check(r ?? read(), floorPct: 12, answer: answer ?? noon, model: model, recentW: recentW, now: now, calendar: cal)
    }

    @Test func aShortOutageWarnsThirtyMinutesBefore() throws {
        // usable (4198.4 - 614.4) / 1.09 = 3288.07 Wh; 750 W with the 1.1 margin is 825 W, so it runs out 3.9855 h after 12:00.
        let warning = try #require(check())
        #expect(warning.fireAt == kyiv("2026-10-15 11:30"))
        #expect(abs(warning.runsOutAt.timeIntervalSince(kyiv("2026-10-15 15:59").addingTimeInterval(8))) <= 1)
        #expect(warning.shortMinutes == 61)
        #expect(warning.cutW == 160)
        #expect(warning.loadW == 750)
        #expect(warning.fromModel == false)
        #expect(warning.socPct == 82)
        #expect(warning.back == kyiv("2026-10-15 17:00"))
    }

    @Test func anOutageTheBatteryLastsIsQuiet() {
        #expect(check(read(offgridW: 400)) == nil)
        // 4212 Wh leaves 3300.2 Wh usable; 600 W with the margin is 660 W, which lasts the 5 h with 3 s to spare.
        let lastsToTheMinute = Reading(time: now, socPct: 82, acW: 600, offgridW: 600, capacityWh: 4212, ratedWh: 5120)
        #expect(check(lastsToTheMinute) == nil)
        // 4205.4 Wh leaves 3294.5 Wh usable: 30 s short of the 5 h, under the minute `verdict` also forgives.
        let thirtySecondsShort = Reading(time: now, socPct: 82, acW: 600, offgridW: 600, capacityWh: 4205.4, ratedWh: 5120)
        #expect(check(thirtySecondsShort) == nil)
    }

    @Test func onlyAnOutageAheadWithinSixHoursWarns() {
        #expect(check(nil, .clear) == nil)
        #expect(check(nil, .off(from: kyiv("2026-10-15 17:00"), until: kyiv("2026-10-15 23:00"))) == nil)
        #expect(check(nil, .off(from: kyiv("2026-10-15 09:00"), until: kyiv("2026-10-15 17:00"))) == nil)
        #expect(check(nil, .emergency) == nil)
        #expect(check(nil, .off(from: kyiv("2026-10-15 16:00"), until: kyiv("2026-10-15 23:00"))) != nil)
    }

    @Test func theModelReplacesTheCurrentLoad() throws {
        #expect(check(read(offgridW: 900), model: flatModel(watts: 300), recentW: 300) == nil)
        let warning = try #require(check(read(offgridW: 100), model: flatModel(watts: 1000), recentW: 1000))
        #expect(warning.fromModel)
        #expect(abs(warning.loadW - 1000) <= 10)
    }

    @Test func theNoticeFollowsTheWarning() throws {
        let warning = try #require(check())
        let early = kyiv("2026-10-15 10:00"), late = kyiv("2026-10-15 11:45"), started = kyiv("2026-10-15 12:00")
        let other = kyiv("2026-10-14 12:00")
        #expect(OutageNotice.action(for: nil, now: early, notified: nil) == .remove)
        #expect(OutageNotice.action(for: warning, now: early, notified: nil) == .schedule(at: kyiv("2026-10-15 11:30")))
        #expect(OutageNotice.action(for: warning, now: late, notified: nil) == .deliverNow)
        #expect(OutageNotice.action(for: warning, now: late, notified: other) == .deliverNow)
        #expect(OutageNotice.action(for: warning, now: late, notified: warning.start) == .nothing)
        #expect(OutageNotice.action(for: warning, now: started, notified: nil) == .nothing)
    }

    @Test func theTextFollowsTheSourceOfTheLoad() throws {
        let fallback = try #require(check())
        let modelled = try #require(check(model: flatModel(watts: 750), recentW: 750))
        #expect(fallback.title.contains("61 min"))
        #expect(modelled.body.contains("Forecast from your usage"))
        #expect(!fallback.body.contains("Forecast from your usage"))
        #expect(fallback.body.contains("At the current 750 W"))
    }
}
