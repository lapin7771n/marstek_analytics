import SwiftUI

enum Palette {
    static let bg = Color(hex: 0x0F0F12)
    static let track = Color(hex: 0x24242A)
    static let label = Color(hex: 0x8E8E93)
    static let stale = Color(hex: 0x6E6E76)
    static let good = Color(hex: 0x3DDC97)
    static let warn = Color(hex: 0xFFB547)
    static let cardEdge = Color(hex: 0x2A2A30)
    static let bad = Color(hex: 0xFF6B5E)

    static func accent(_ face: Face) -> Color {
        if face.stale { return stale }
        switch face.tone {
        case .neutral: return Color(hex: 0xA3A3AD)
        case .good: return good
        case .warn: return warn
        case .bad: return bad
        }
    }

    static func value(_ face: Face) -> Color {
        face.stale ? stale : .white
    }

    static func unit(_ face: Face) -> Color {
        face.stale ? stale : Color(hex: 0x8E8E97)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct Run: Equatable {
    var text: String
    var digits: Bool
}

func valueRuns(_ text: String) -> [Run] {
    var runs: [Run] = []
    for char in text {
        if let last = runs.last, last.digits == char.isNumber {
            runs[runs.count - 1].text.append(char)
        } else {
            runs.append(Run(text: String(char), digits: char.isNumber))
        }
    }
    return runs
}

struct ValueText: View {
    let text: String
    let size: CGFloat
    let unitSize: CGFloat
    let color: Color
    let unitColor: Color

    var body: some View {
        if text.first?.isNumber == true {
            valueRuns(text).reduce(Text("")) { line, run in
                line + Text(run.text)
                    .font(.system(size: run.digits ? size : unitSize, weight: run.digits ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(run.digits ? color : unitColor)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        } else {
            Text(text)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

struct Bolt: View {
    let color: Color

    var body: some View {
        Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(color)
    }
}

struct Ring: View {
    let face: Face
    var width: CGFloat = 8.5

    var body: some View {
        ZStack {
            arc(1).stroke(Palette.track, style: StrokeStyle(lineWidth: width, lineCap: .round))
            if face.fill > 0 {
                arc(face.fill).stroke(Palette.accent(face), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

    private func arc(_ share: Double) -> some Shape {
        Circle().trim(from: 0, to: 0.75 * share).rotation(.degrees(135))
    }
}

struct SmallFace: View {
    let face: Face

    var body: some View {
        ZStack {
            Ring(face: face).padding(14)
            VStack(spacing: 1) {
                if face.charging && !face.stale {
                    Bolt(color: Palette.accent(face))
                }
                ValueText(text: face.percent, size: 38, unitSize: 17, color: Palette.value(face), unitColor: Palette.unit(face))
                Text(face.problem ?? face.power)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(face.problem == nil ? Palette.accent(face) : Palette.bad)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.top, 4)
            .padding(.horizontal, 26)
        }
    }
}

struct MediumFace: View {
    let face: Face

    var body: some View {
        HStack(spacing: 14) {
            SmallFace(face: face).aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 4) {
                Text(face.etaLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Palette.label)
                ValueText(
                    text: face.eta, size: 46, unitSize: 22,
                    color: face.updated == nil && face.problem != nil ? Palette.bad : Palette.value(face),
                    unitColor: Palette.unit(face)
                )
                if let outage = face.outage, !face.stale {
                    OutageLine(outage: outage)
                } else {
                    Group {
                        if let updated = face.updated {
                            Text("Updated \(Text(updated, style: .time))")
                        } else {
                            Text("Open the app")
                        }
                    }
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(face.stale ? Color(hex: 0xA3A3AD) : Palette.label)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 20)
    }
}

struct CircularFace: View {
    let face: Face

    var body: some View {
        Gauge(value: face.fill) {
            Text("Battery")
        } currentValueLabel: {
            VStack(spacing: 0) {
                if face.charging && !face.stale {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                }
                Text(face.updated == nil ? "··" : face.percent.replacingOccurrences(of: "%", with: ""))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .opacity(face.stale ? 0.7 : 1)
    }
}

struct RectangularFace: View {
    let face: Face

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(face.updated == nil ? String(localized: "Battery") : String(localized: "Battery \(face.percent)"))
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(face.updated == nil ? String(localized: "Open the app") : "\(face.etaLabel) \(face.eta)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Group {
                if let problem = face.problem, let updated = face.updated {
                    Text("\(problem) · \(Text(updated, style: .time))")
                } else {
                    Text(face.problem ?? face.power)
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(face.stale ? 0.7 : 1)
    }
}
