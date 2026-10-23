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

    // Energy above the reserve that reaches the load, after discharge losses.
    static func usableWh(_ r: Reading, floorPct: Double) -> Double {
        max(0, r.capacityWh - floorPct / 100 * r.ratedWh) / dischargeRatio
    }

    static func estimate(_ r: Reading, floorPct: Double) -> Estimate {
        let wh = usableWh(r, floorPct: floorPct)
        if r.acW < -idleW {
            let missingWh = max(0, r.ratedWh - r.capacityWh)
            return Estimate(mode: .charging, hours: capped(missingWh / (-r.acW * chargeRatio)))
        }
        if r.acW > idleW {
            return Estimate(mode: .discharging, hours: capped(wh / r.acW))
        }
        if r.offgridW > idleW {
            return Estimate(mode: .idle, hours: capped(wh / r.offgridW))
        }
        return Estimate(mode: .idle, hours: nil)
    }

    private static func capped(_ hours: Double) -> Double {
        min(maxHours, hours)
    }
}
