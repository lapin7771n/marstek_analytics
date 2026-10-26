import Foundation
import Testing
@testable import BatteryETA

struct OutageActivityTests {
    private typealias State = OutageActivityAttributes.ContentState

    private let readAt = Date(timeIntervalSince1970: 1_760_000_000)

    private func snapshot(_ r: Reading) -> Snapshot { Snapshot(reading: r, error: nil, checkedAt: r.time) }

    // 3276.8 Wh at 64 %: usable (3276.8 - 614.4) / 1.09 = 2442.57 Wh. At 800 W with the 1.1 margin it runs out after 2.7756 h.
    @Test func anActivityRunsOnlyDuringAnOutage() throws {
        let load = reading(soc: 64, acW: 819.6, offgridW: 800, capacityWh: 3276.8)
        let runsOutAt = readAt.addingTimeInterval(2.7756 * 3600)
        let short = readAt.addingTimeInterval((3 * 60 + 35) * 60)
        let started = readAt.addingTimeInterval(-600)
        func state(_ r: Reading, back: Date?, start: Date? = nil, now: Date? = nil) -> State? {
            OutageActivityAttributes.state(snapshot(r), floorPct: 12, powerBack: back, outageStart: start, now: now ?? readAt)
        }

        let runs = try #require(state(load, back: short))
        #expect(runs.loadW == 800)
        #expect(runs.back == short)
        #expect(!runs.lasts)
        #expect(abs(try #require(runs.runsOutAt).timeIntervalSince(runsOutAt)) < 5)

        let spare = readAt.addingTimeInterval(3600)
        let lasts = try #require(state(load, back: spare))
        #expect(lasts.lasts)
        #expect(lasts.back == spare)
        #expect(abs(try #require(lasts.runsOutAt).timeIntervalSince(runsOutAt)) < 5)

        let idle = reading(soc: 64, acW: 0, offgridW: 150, capacityWh: 3276.8)
        #expect(try #require(state(idle, back: short)).loadW == 150)

        let noBackupLoad = reading(soc: 64, acW: 20, offgridW: 0, capacityWh: 3276.8)
        let charging = reading(soc: 64, acW: -500, offgridW: 0, capacityWh: 3276.8)
        let stale = readAt.addingTimeInterval(Face.staleAfter)
        #expect(state(load, back: nil) == nil)
        #expect(state(noBackupLoad, back: short) == nil)
        #expect(state(charging, back: short) == nil)
        #expect(state(load, back: short.addingTimeInterval(3600), now: stale) == nil)
        #expect(state(load, back: short, now: short) == nil)
        #expect(OutageActivityAttributes.state(Snapshot(reading: nil, error: .noLink, checkedAt: readAt), floorPct: 12, powerBack: short, outageStart: nil, now: readAt) == nil)

        #expect(state(load, back: short, start: readAt.addingTimeInterval(1800)) == nil)
        #expect(state(load, back: short, start: started) == runs)
        #expect(state(load, back: short, start: readAt) == runs)
    }

    @Test func theOutageStartComesFromTheScheduleOnlyWhenTheScheduleSetTheEnd() {
        let store = scratchStore()
        let now = kyiv("2026-10-15 12:30")
        let day = ScheduleDay(date: kyiv("2026-10-15 00:00"), status: "ScheduleApplies", slots: [ScheduleSlot(start: 12 * 60, end: 17 * 60, type: "Definite")])
        let tomorrow = ScheduleDay(date: kyiv("2026-10-16 00:00"), status: "WaitingForSchedule", slots: [])
        store.outageGroup = OutageGroup(group: 19, subgroup: 1, address: "")
        store.schedule = ScheduleState(key: "19.1", checkedAt: now, days: GroupDays(today: day, tomorrow: tomorrow))
        store.powerBack = kyiv("2026-10-15 17:00")
        store.powerBackFromSchedule = true
        #expect(OutageActivityAttributes.outageStart(store, now: now) == kyiv("2026-10-15 12:00"))
        store.powerBackFromSchedule = false
        #expect(OutageActivityAttributes.outageStart(store, now: now) == nil)
    }

    // One reading, one outage 12:00-17:00: the card, the cut, the notification and the activity name the same run-out time and cut.
    @Test func everySurfaceUsesTheSameOutageRule() throws {
        let start = kyiv("2026-10-15 12:00"), back = kyiv("2026-10-15 17:00")
        let r = Reading(time: start, socPct: 82, acW: 750, offgridW: 750, capacityWh: 4198.4, ratedWh: 5120)
        let expected = start.addingTimeInterval(3288.0734 / 825 * 3600)

        guard case let .short(cardRunsOut, _, _)? = Outage.verdict(r, floorPct: 12, powerBack: back, now: start) else { Issue.record("no short verdict"); return }
        let warning = try #require(OutageAhead.check(r, floorPct: 12, answer: .off(from: start, until: back), model: nil, recentW: 750, now: start.addingTimeInterval(-60), calendar: Schedule.kyiv))
        let activity = try #require(OutageActivityAttributes.state(snapshot(r), floorPct: 12, powerBack: back, outageStart: start, now: start))

        #expect(abs(cardRunsOut.timeIntervalSince(expected)) <= 1)
        #expect(warning.runsOutAt == cardRunsOut)
        #expect(activity.runsOutAt == cardRunsOut)
        #expect(Outage.cut(r, floorPct: 12, back: back, now: start) == 160)
        #expect(warning.cutW == 160)
    }

    @Test func theActivityIsStartedUpdatedOrEndedOnChange() {
        let a = State(socPct: 64, loadW: 820, runsOutAt: readAt, back: readAt, lasts: false)
        var b = a
        b.socPct = 63
        let table: [(State?, State?, Bool, OutageActivityStep)] = [
            (a, nil, true, .start),
            (a, nil, false, .nothing),
            (a, a, true, .nothing),
            (b, a, false, .update),
            (nil, a, false, .end),
            (nil, nil, true, .nothing),
        ]
        for (new, running, canStart, step) in table {
            #expect(OutageActivityStep.decide(new: new, running: running, canStart: canStart) == step)
        }
    }
}
