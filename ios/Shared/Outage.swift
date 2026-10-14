import Foundation

enum Outage: Equatable {
    case lasts(until: Date, spareHours: Double?)
    case short(runsOutAt: Date, shortHours: Double, back: Date)

    var lasts: Bool {
        if case .lasts = self { true } else { false }
    }

    var back: Date {
        switch self {
        case let .lasts(until, _): until
        case let .short(_, _, back): back
        }
    }

    static func verdict(_ r: Reading, floorPct: Int, powerBack: Date, now: Date) -> Outage? {
        guard powerBack > now else { return nil }
        let est = QuickEstimate.estimate(r, floorPct: Double(floorPct))
        if est.mode == .charging { return nil }
        guard let hours = est.hours else { return .lasts(until: powerBack, spareHours: nil) }
        let runsOut = r.time.addingTimeInterval(hours * 3600)
        let spare = runsOut.timeIntervalSince(powerBack) / 3600
        return spare >= 0 ? .lasts(until: powerBack, spareHours: spare) : .short(runsOutAt: runsOut, shortHours: -spare, back: powerBack)
    }

    static func nextTime(_ picked: Date, after now: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: picked)
        return calendar.nextDate(after: now, matching: time, matchingPolicy: .nextTime) ?? picked
    }

    static func moved(_ back: Date, tomorrow: Bool, now: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: back)
        let day = calendar.startOfDay(for: now).addingTimeInterval(tomorrow ? 86_400 : 0)
        let moved = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? back
        return moved > now ? moved : back
    }
}

func formatSpan(_ hours: Double) -> String {
    let minutes = max(0, Int((hours * 60).rounded()))
    if minutes < 60 { return String(localized: "\(minutes) min") }
    return String(localized: "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min")
}
