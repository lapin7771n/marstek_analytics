import ActivityKit
import Foundation

struct OutageActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var socPct: Int
        var loadW: Int
        var runsOutAt: Date?
        var back: Date
        var lasts: Bool
    }

    // Built from the stored snapshot only: it never asks the battery. `outageStart` is nil when the user set the time by hand.
    static func state(_ snapshot: Snapshot?, floorPct: Int, powerBack: Date?, outageStart: Date?, now: Date) -> ContentState? {
        guard let r = snapshot?.reading, let powerBack,
              outageStart.map({ $0 <= now }) ?? true,
              r.offgridW > QuickEstimate.idleW, now.timeIntervalSince(r.time) < Face.staleAfter,
              let outage = Outage.verdict(r, floorPct: floorPct, powerBack: powerBack, now: now) else { return nil }
        let runsOutAt: Date? = switch outage {
        case let .short(runsOut, _, _): runsOut
        case .lasts: Outage.runsOutAt(r, floorPct: floorPct, load: r.offgridW, from: r.time)
        }
        return ContentState(socPct: r.socPct, loadW: Int(r.offgridW.rounded()), runsOutAt: runsOutAt, back: outage.back, lasts: outage.lasts)
    }

    // The start of the YASNO outage the stored end time belongs to; nil when the user set the end time by hand.
    static func outageStart(_ store: Store, now: Date) -> Date? {
        guard store.powerBackFromSchedule, let schedule = store.schedule, schedule.key == store.outageGroup?.key,
              let days = schedule.days, case let .off(start, _) = Schedule.answer(days, now: now) else { return nil }
        return start
    }
}

enum OutageActivityStep: Equatable {
    case start, update, end, nothing

    static func decide(new: OutageActivityAttributes.ContentState?, running: OutageActivityAttributes.ContentState?, canStart: Bool) -> OutageActivityStep {
        guard let new else { return running == nil ? .nothing : .end }
        guard let running else { return canStart ? .start : .nothing }
        return running == new ? .nothing : .update
    }
}
