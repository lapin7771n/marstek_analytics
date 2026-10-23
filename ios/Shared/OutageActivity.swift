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

    // Built from the stored snapshot only: it never asks the battery.
    static func state(_ snapshot: Snapshot?, floorPct: Int, powerBack: Date?, now: Date) -> ContentState? {
        guard let r = snapshot?.reading, let powerBack,
              r.acW > 0, now.timeIntervalSince(r.time) < Face.staleAfter,
              let outage = Outage.verdict(r, floorPct: floorPct, powerBack: powerBack, now: now) else { return nil }
        let runsOutAt: Date? = switch outage {
        case let .short(runsOut, _, _): runsOut
        case .lasts: QuickEstimate.estimate(r, floorPct: Double(floorPct)).hours.map { r.time.addingTimeInterval($0 * 3600) }
        }
        return ContentState(socPct: r.socPct, loadW: Int(r.acW.rounded()), runsOutAt: runsOutAt, back: outage.back, lasts: outage.lasts)
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
