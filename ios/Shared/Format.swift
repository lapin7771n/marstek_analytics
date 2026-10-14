import Foundation

func formatDuration(_ hours: Double) -> String {
    let h = String(localized: "h", comment: "Hours unit, as in 6h20 and 21h")
    let m = String(localized: "m", comment: "Minutes unit, as in 25m")
    let minutes = hours * 60
    if minutes >= 600 { return "\(Int((minutes / 60).rounded()))\(h)" }
    if minutes >= 60 {
        let rounded = Int((minutes / 10).rounded()) * 10
        return "\(rounded / 60)\(h)" + String(format: "%02d", rounded % 60)
    }
    if minutes >= 10 { return "\(Int((minutes / 5).rounded()) * 5)\(m)" }
    return "\(max(0, Int(minutes.rounded())))\(m)"
}
