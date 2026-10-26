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

    // When the battery runs dry at a constant `load` on the backup socket, counted from `start`, with OutageAhead.margin on top.
    static func runsOutAt(_ r: Reading, floorPct: Int, load: Double, from start: Date) -> Date? {
        guard load > QuickEstimate.idleW else { return nil }
        let hours = QuickEstimate.usableWh(r, floorPct: Double(floorPct)) / (load * OutageAhead.margin)
        return start.addingTimeInterval(hours * 3600)
    }

    // nil when the battery lasts from `start` to `back`. The cut is the watts to shed to last, rounded up to 10 W.
    static func shortfall(_ r: Reading, floorPct: Int, load: Double, from start: Date, back: Date) -> (runsOutAt: Date, cutW: Int)? {
        guard let runsOut = runsOutAt(r, floorPct: floorPct, load: load, from: start), runsOut < back else { return nil }
        let hours = back.timeIntervalSince(start) / 3600
        let usable = QuickEstimate.usableWh(r, floorPct: Double(floorPct))
        let cut = max(0, load - usable / OutageAhead.margin / hours)
        return (runsOut, Int((cut / 10).rounded(.up)) * 10)
    }

    static func verdict(_ r: Reading, floorPct: Int, powerBack: Date, now: Date) -> Outage? {
        guard powerBack > now else { return nil }
        if QuickEstimate.estimate(r, floorPct: Double(floorPct)).mode == .charging { return nil }
        guard let runsOut = runsOutAt(r, floorPct: floorPct, load: r.offgridW, from: r.time) else { return .lasts(until: powerBack, spareHours: nil) }
        let spare = runsOut.timeIntervalSince(powerBack)
        return spare > -60 ? .lasts(until: powerBack, spareHours: max(spare, 0) / 3600) : .short(runsOutAt: runsOut, shortHours: -spare / 3600, back: powerBack)
    }

    // Watts to shed so the battery lasts until `back`, rounded up to 10 W; nil when it already lasts.
    static func cut(_ r: Reading, floorPct: Int, back: Date, now: Date) -> Int? {
        guard back > now, QuickEstimate.estimate(r, floorPct: Double(floorPct)).mode != .charging else { return nil }
        return shortfall(r, floorPct: floorPct, load: r.offgridW, from: r.time, back: back)?.cutW
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
