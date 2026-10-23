import Foundation
import Testing
@testable import BatteryETA

struct OutageActivityTests {
    private typealias State = OutageActivityAttributes.ContentState

    private let readAt = Date(timeIntervalSince1970: 1_760_000_000)

    private func snapshot(_ r: Reading) -> Snapshot { Snapshot(reading: r, error: nil, checkedAt: r.time) }

    @Test func anActivityRunsOnlyDuringAnOutage() throws {
        let load = reading(soc: 64, acW: 819.6, offgridW: 800, capacityWh: 3276.8)
        let short = readAt.addingTimeInterval((3 * 60 + 35) * 60)
        let verdict = try #require(Outage.verdict(load, floorPct: 12, powerBack: short, now: readAt))
        guard case let .short(runsOut, _, _) = verdict else { Issue.record("\(verdict)"); return }

        let runs = try #require(OutageActivityAttributes.state(snapshot(load), floorPct: 12, powerBack: short, now: readAt))
        #expect(runs == State(socPct: 64, loadW: 820, runsOutAt: runsOut, back: short, lasts: false))

        let spare = readAt.addingTimeInterval(3600)
        let lasts = try #require(OutageActivityAttributes.state(snapshot(load), floorPct: 12, powerBack: spare, now: readAt))
        #expect(lasts.lasts)
        #expect(lasts.back == spare)
        #expect(lasts.runsOutAt != nil)

        let noLoad = reading(soc: 64, acW: 20, offgridW: 0, capacityWh: 3276.8)
        let unbounded = try #require(OutageActivityAttributes.state(snapshot(noLoad), floorPct: 12, powerBack: spare, now: readAt))
        #expect(unbounded.lasts)
        #expect(unbounded.runsOutAt == nil)

        let charging = reading(soc: 64, acW: -500, offgridW: 0, capacityWh: 3276.8)
        let idle = reading(soc: 64, acW: 0, offgridW: 150, capacityWh: 3276.8)
        let stale = readAt.addingTimeInterval(Face.staleAfter)
        #expect(OutageActivityAttributes.state(snapshot(load), floorPct: 12, powerBack: nil, now: readAt) == nil)
        #expect(OutageActivityAttributes.state(snapshot(charging), floorPct: 12, powerBack: short, now: readAt) == nil)
        #expect(OutageActivityAttributes.state(snapshot(idle), floorPct: 12, powerBack: short, now: readAt) == nil)
        #expect(OutageActivityAttributes.state(snapshot(load), floorPct: 12, powerBack: short.addingTimeInterval(3600), now: stale) == nil)
        #expect(OutageActivityAttributes.state(snapshot(load), floorPct: 12, powerBack: short, now: short) == nil)
        #expect(OutageActivityAttributes.state(Snapshot(reading: nil, error: .noLink, checkedAt: readAt), floorPct: 12, powerBack: short, now: readAt) == nil)
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
