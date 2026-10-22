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
        let spare = runsOut.timeIntervalSince(powerBack)
        return spare > -60 ? .lasts(until: powerBack, spareHours: max(spare, 0) / 3600) : .short(runsOutAt: runsOut, shortHours: -spare / 3600, back: powerBack)
    }

    // Watts to shed so the battery lasts until `back`, rounded up to 10 W; nil when it already lasts.
    static func cut(_ r: Reading, floorPct: Int, back: Date, now: Date) -> Int? {
        let est = QuickEstimate.estimate(r, floorPct: Double(floorPct))
        guard est.mode != .charging, let hours = est.hours else { return nil }
        let load = r.acW > QuickEstimate.idleW ? r.acW : r.offgridW
        let usableWh = max(0, r.capacityWh - Double(floorPct) / 100 * r.ratedWh) / QuickEstimate.dischargeRatio
        let hoursLeft = back.timeIntervalSince(now) / 3600
        guard hoursLeft > 0, hours < hoursLeft else { return nil }
        return Int((max(0, load - usableWh / hoursLeft) / 10).rounded(.up)) * 10
    }

    static func nextTime(_ picked: Date, after now: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: picked)
        return calendar.nextDate(after: now, matching: time, matchingPolicy: .nextTime) ?? picked
    }

    static func retimed(_ back: Date?, to picked: Date, now: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: picked)
        if let back, let sameDay = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: back), sameDay > now {
            return sameDay
        }
        return nextTime(picked, after: now, calendar: calendar)
    }

    static func moved(_ back: Date, tomorrow: Bool, now: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: back)
        guard let day = calendar.date(byAdding: .day, value: tomorrow ? 1 : 0, to: calendar.startOfDay(for: now)),
              let moved = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) else { return back }
        return moved > now ? moved : back
    }
}

func formatSpan(_ hours: Double) -> String {
    let minutes = max(0, Int((hours * 60).rounded()))
    if minutes < 60 { return String(localized: "\(minutes) min") }
    return String(localized: "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min")
}
