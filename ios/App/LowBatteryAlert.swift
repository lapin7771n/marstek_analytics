import Foundation

enum LowBattery: Equatable {
    case soon(minutes: Int, watts: Int)
    case reserve(socPct: Int, watts: Int?)

    var title: String {
        switch self {
        case .soon: String(localized: "Under 30 min left")
        case .reserve: String(localized: "Battery at reserve")
        }
    }

    var body: String {
        switch self {
        case let .soon(minutes, watts):
            String(localized: "Empty in \(minutes) min at \(Self.power(watts)). Turn off heavy loads.")
        case let .reserve(socPct, watts?):
            String(localized: "\(Self.percent(socPct)) left, \(Self.power(watts)). The battery stops at the reserve.")
        case let .reserve(socPct, nil):
            String(localized: "\(Self.percent(socPct)) left. The battery stops at the reserve.")
        }
    }

    // The percent goes in as text: a bare % in a localized format key reads as a format specifier.
    static func percent(_ pct: Int) -> String { "\(pct) %" }

    // An Int interpolated into String(localized:) gets locale grouping ("−1 850 W"); %lld through String(format:) does not.
    private static func power(_ watts: Int) -> String { String(format: String(localized: "−%lld W"), watts) }
}

enum LowBatteryAlert {
    static let soonHours = 0.5
    static let rearmPct = 5
    static let rearmHours = 1.0

    static func check(_ snapshot: Snapshot, floorPct: Int, state: inout AlertState, now: Date = .now) -> LowBattery? {
        guard state.on, snapshot.error == nil, let r = snapshot.reading,
              now.timeIntervalSince(r.time) < Face.staleAfter else { return nil }
        let est = QuickEstimate.estimate(r, floorPct: Double(floorPct))
        if est.mode == .charging || (r.socPct > floorPct + rearmPct && (est.hours ?? .infinity) >= rearmHours) {
            state.soonAlerted = false
            state.reserveAlerted = false
            return nil
        }
        let watts = Int(abs(r.acW).rounded())
        if r.socPct <= floorPct {
            let first = !state.reserveAlerted
            state.soonAlerted = true
            state.reserveAlerted = true
            return first ? .reserve(socPct: r.socPct, watts: est.mode == .discharging ? watts : nil) : nil
        }
        if est.mode == .discharging, let hours = est.hours, hours < soonHours, !state.soonAlerted {
            state.soonAlerted = true
            return .soon(minutes: min(29, max(1, Int((hours * 60).rounded()))), watts: watts)
        }
        return nil
    }
}
