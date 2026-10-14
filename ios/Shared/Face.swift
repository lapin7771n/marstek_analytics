import Foundation

enum Tone: Equatable {
    case neutral, good, warn, bad
}

struct Face: Equatable {
    var percent = "··"
    var fill = 0.0
    var charging = false
    var power = ""
    var etaLabel = "BATTERY"
    var eta = "··"
    var tone = Tone.neutral
    var stale = true
    var problem: String?
    var updated: Date?
}

extension Face {
    init(_ snapshot: Snapshot?, floorPct: Int) {
        self.init()
        problem = snapshot?.error?.text
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
        stale = snapshot?.error != nil
        updated = r.time

        switch est.mode {
        case .charging:
            power = "+\(watts) W"
            tone = .good
            etaLabel = "FULL IN"
            eta = r.socPct >= 100 ? "FULL" : etaText
        case .discharging:
            power = "−\(watts) W"
            tone = r.socPct < 20 || (est.hours ?? 0) < 0.5 ? .bad : .warn
            etaLabel = "EMPTY IN"
            eta = etaText
        case .idle:
            power = "IDLE"
            etaLabel = est.hours == nil ? "ETA" : "IF OUTAGE"
            eta = est.hours == nil ? (r.socPct >= 100 ? "FULL" : "—") : etaText
        }
    }

    static let sample = Face(
        percent: "82%", fill: 0.82, charging: false, power: "−412 W", etaLabel: "EMPTY IN", eta: "6h20",
        tone: .warn, stale: false, problem: nil, updated: .now
    )
}
