import Foundation

struct OutageWarning: Equatable {
    var start: Date
    var back: Date
    var runsOutAt: Date
    var shortMinutes: Int
    var loadW: Int
    var cutW: Int
    var socPct: Int
    var fromModel: Bool

    var fireAt: Date { start - OutageAhead.lead }

    var title: String {
        String(format: String(localized: "Outage at %@, %lld min short"), time(start), shortMinutes)
    }

    var body: String {
        if fromModel {
            return String(format: String(localized: "YASNO: off %@–%@. You usually use about %lld W at those hours, so the battery runs out near %@. Cut about %lld W to last. Forecast from your usage."), time(start), time(back), loadW, time(runsOutAt), cutW)
        }
        return String(format: String(localized: "YASNO: off %@–%@. At the current %lld W the battery runs out near %@. Cut about %lld W to last."), time(start), time(back), loadW, time(runsOutAt), cutW)
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

enum OutageNotice: Equatable {
    case remove, schedule(at: Date), deliverNow, nothing

    // `notified` is the start of the outage the user was last told about, whether delivered or scheduled.
    static func action(for warning: OutageWarning?, now: Date, notified: Date?) -> OutageNotice {
        guard let warning else { return .remove }
        if warning.fireAt > now { return .schedule(at: warning.fireAt) }
        return now < warning.start && notified != warning.start ? .deliverNow : .nothing
    }
}

enum OutageAhead {
    static let lead: TimeInterval = 30 * 60
    static let horizon: TimeInterval = 6 * 3600
    static let margin = 1.1
    static let step: TimeInterval = 5 * 60

    // The charge is assumed unchanged until the outage starts. nil when the battery lasts or no outage is near.
    static func check(_ r: Reading, floorPct: Int, answer: ScheduleAnswer, model: LoadModel?, recentW: Double, now: Date, calendar: Calendar = .current) -> OutageWarning? {
        guard case let .off(start, back) = answer, start > now, start.timeIntervalSince(now) <= horizon, back > start else { return nil }
        let found: (runsOutAt: Date, loadW: Double, cutW: Int)?
        if let model {
            found = walk(r, floorPct: floorPct, start: start, back: back, model: model, recentW: recentW, calendar: calendar)
        } else {
            found = Outage.shortfall(r, floorPct: floorPct, load: r.offgridW, from: start, back: back).map { ($0.runsOutAt, r.offgridW, $0.cutW) }
        }
        guard let (runsOutAt, loadW, cutW) = found else { return nil }
        return OutageWarning(
            start: start, back: back, runsOutAt: runsOutAt,
            shortMinutes: Int((back.timeIntervalSince(runsOutAt) / 60).rounded()),
            loadW: Int(loadW.rounded()), cutW: cutW,
            socPct: r.socPct, fromModel: model != nil
        )
    }

    // The model gives a load per 5 min step, so the run-out time is a step end.
    private static func walk(_ r: Reading, floorPct: Int, start: Date, back: Date, model: LoadModel, recentW: Double, calendar: Calendar) -> (runsOutAt: Date, loadW: Double, cutW: Int)? {
        let usable = QuickEstimate.usableWh(r, floorPct: Double(floorPct))
        var used = 0.0, loadSum = 0.0, runsOutAt: Date?
        var t = start
        while t < back {
            let end = min(t.addingTimeInterval(step), back)
            let seconds = end.timeIntervalSince(t)
            let load = model.watts(at: t, recentW: recentW, calendar: calendar)
            loadSum += load * seconds
            used += load * seconds / 3600 * margin
            if runsOutAt == nil, used >= usable { runsOutAt = end }
            t = end
        }
        guard let runsOutAt, runsOutAt < back else { return nil }
        let window = back.timeIntervalSince(start)
        let loadW = loadSum / window
        let cut = max(0, loadW - usable / margin / (window / 3600))
        return (runsOutAt, loadW, Int((cut / 10).rounded(.up)) * 10)
    }
}
