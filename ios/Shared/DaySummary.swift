import Foundation

struct DaySummary: Equatable {
    struct Segment: Equatable {
        var samples: [Sample]
        var dotted: Bool
    }

    // Charging is positive, as on the face.
    struct HourBar: Equatable {
        var hour: Date
        var watts: Int
    }

    var start: Date
    var now: Date
    var segments: [Segment] = []
    var hours: [HourBar] = []
    var low: Int?
    var high: Int?
    var chargedWh = 0.0
    var usedWh = 0.0
    var onBattery: TimeInterval = 0

    var isEmpty: Bool { segments.flatMap(\.samples).count < 2 }
}

struct DayTotal: Equatable {
    var day: Date
    var chargedWh: Double
    var usedWh: Double
    var onBattery: TimeInterval
}

extension History {
    func day(now: Date, latest: Reading?, calendar: Calendar = .current) -> DaySummary {
        let start = calendar.startOfDay(for: now)
        var all = samples
        if let latest, latest.time > all.last?.time ?? .distantPast { all.append(Sample(latest)) }
        let today = all.filter { $0.time >= start && $0.time <= now }

        var day = DaySummary(start: start, now: now)
        day.low = today.map(\.socPct).min()
        day.high = today.map(\.socPct).max()
        let energy = History.energy(today)
        day.chargedWh = energy.chargedWh
        day.usedWh = energy.usedWh
        day.onBattery = energy.onBattery
        for s in today {
            if let prev = day.segments.last?.samples.last, s.time.timeIntervalSince(prev.time) > History.gap {
                day.segments.append(.init(samples: [prev, s], dotted: true))
                day.segments.append(.init(samples: [s], dotted: false))
            } else if day.segments.isEmpty {
                day.segments.append(.init(samples: [s], dotted: false))
            } else {
                day.segments[day.segments.count - 1].samples.append(s)
            }
        }
        day.hours = Dictionary(grouping: today) { calendar.dateInterval(of: .hour, for: $0.time)?.start ?? $0.time }
            .map { hour, group in DaySummary.HourBar(hour: hour, watts: -group.map(\.acW).reduce(0, +) / group.count) }
            .sorted { $0.hour < $1.hour }
        return day
    }

    func week(now: Date, calendar: Calendar = .current) -> [DayTotal] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -back, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let energy = History.energy(samples.filter { $0.time >= start && $0.time < end && $0.time <= now })
            return DayTotal(day: start, chargedWh: energy.chargedWh, usedWh: energy.usedWh, onBattery: energy.onBattery)
        }
    }

    private static func energy(_ samples: [Sample]) -> (chargedWh: Double, usedWh: Double, onBattery: TimeInterval) {
        var chargedWh = 0.0, usedWh = 0.0, onBattery: TimeInterval = 0
        for (a, b) in zip(samples, samples.dropFirst()) {
            let gap = b.time.timeIntervalSince(a.time)
            guard gap <= History.gap else { continue }
            let wh = Double(a.acW) * gap / 3600
            if wh < 0 { chargedWh -= wh } else { usedWh += wh }
            if Double(a.acW) > QuickEstimate.idleW { onBattery += gap }
        }
        return (chargedWh, usedWh, onBattery)
    }
}
