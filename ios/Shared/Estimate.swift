import Foundation

enum Mode: Equatable {
    case charging, discharging, idle
}

struct Estimate: Equatable {
    let mode: Mode
    let hours: Double?
}

enum QuickEstimate {
    static let idleW = 30.0
    static let chargeRatio = 0.88
    static let dischargeRatio = 1.09
    static let maxHours = 240.0

    static func estimate(_ r: Reading, floorPct: Double) -> Estimate {
        let usableWh = max(0, r.capacityWh - floorPct / 100 * r.ratedWh)
        if r.acW < -idleW {
            let missingWh = max(0, r.ratedWh - r.capacityWh)
            return Estimate(mode: .charging, hours: capped(missingWh / (-r.acW * chargeRatio)))
        }
        if r.acW > idleW {
            return Estimate(mode: .discharging, hours: capped(usableWh / dischargeRatio / r.acW))
        }
        if r.offgridW > idleW {
            return Estimate(mode: .idle, hours: capped(usableWh / dischargeRatio / r.offgridW))
        }
        return Estimate(mode: .idle, hours: nil)
    }

    private static func capped(_ hours: Double) -> Double {
        min(maxHours, hours)
    }
}
