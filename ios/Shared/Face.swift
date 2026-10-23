import Foundation

enum Tone: Equatable {
    case neutral, good, warn, bad
}

struct Face: Equatable {
    var percent = "··"
    var fill = 0.0
    var charging = false
    var power = ""
    var etaLabel = String(localized: "BATTERY")
    var eta = "··"
    var tone = Tone.neutral
    var stale = true
    var problem: String?
    var blocked = false
    var updated: Date?
    var outage: Outage?
    var fixes = false
}

extension Face {
    static let staleAfter: TimeInterval = 30 * 60

    init(_ snapshot: Snapshot?, floorPct: Int, powerBack: Date? = nil, now: Date = .now) {
        self.init()
        problem = snapshot?.error?.text
        blocked = snapshot?.error == .blocked
        fixes = snapshot?.error.map { [.noLink, .blocked, .badReply].contains($0) } ?? false
        guard let r = snapshot?.reading else {
            eta = problem ?? "··"
            return
        }
        let est = QuickEstimate.estimate(r, floorPct: Double(floorPct))
        let watts = Int(abs(r.acW).rounded())
        let etaText = est.hours.map(formatDuration) ?? "—"
        percent = "\(r.socPct)%"
        fill = min(1, max(0, Double(r.socPct) / 100))
        charging = est.mode == .charging
        stale = snapshot?.error != nil || now.timeIntervalSince(r.time) >= Face.staleAfter
        updated = r.time
        outage = powerBack.flatMap { Outage.verdict(r, floorPct: floorPct, powerBack: $0, now: now) }

        switch est.mode {
        case .charging:
            power = String(localized: "+\(watts) W")
            tone = .good
            etaLabel = String(localized: "FULL IN")
            eta = r.socPct >= 100 ? String(localized: "FULL") : etaText
        case .discharging:
            power = String(localized: "−\(watts) W")
            tone = r.socPct < 20 || (est.hours ?? 0) < 0.5 ? .bad : .warn
            etaLabel = String(localized: "EMPTY IN")
            eta = etaText
        case .idle:
            power = String(localized: "IDLE")
            etaLabel = est.hours == nil ? String(localized: "ETA") : String(localized: "IF OUTAGE")
            eta = est.hours == nil ? (r.socPct >= 100 ? String(localized: "FULL") : "—") : etaText
        }
    }

    static let sample = Face(
        percent: "82%", fill: 0.82, charging: false, power: "−412 W", etaLabel: "EMPTY IN", eta: "6h20",
        tone: .warn, stale: false, problem: nil, updated: .now
    )
}
