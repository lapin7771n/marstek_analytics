import SwiftUI

struct OutageRow: View {
    let outage: Outage
    let stale: Bool
    let cut: Int?

    private var color: Color { stale ? Palette.stale : outage.lasts ? Palette.good : Palette.bad }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: outage.lasts ? "checkmark" : "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    code.font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(color)
                    sentence.font(.system(size: 15, design: .rounded))
                }
            }
            if case .short = outage, let cut {
                Text("Cut about \(cut) W to last until \(Text(outage.back, style: .time)).")
                    .font(.system(size: 14, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 5)
    }

    private var code: Text {
        switch outage {
        case .lasts: Text("LASTS")
        case let .short(runsOut, _, _): Text("RUNS OUT \(Text(runsOut, style: .time))")
        }
    }

    private var sentence: Text {
        switch outage {
        case let .lasts(until, spare?): Text("Lasts until \(Text(until, style: .time)), \(formatSpan(spare)) to spare.")
        case let .lasts(until, nil): Text("Lasts until \(Text(until, style: .time)).")
        case let .short(runsOut, short, _): Text("Runs out at \(Text(runsOut, style: .time)), \(formatSpan(short)) short.")
        }
    }
}

struct OutageLine: View {
    let outage: Outage

    var body: some View {
        Group {
            switch outage {
            case let .lasts(_, spare?): Text("Power back \(Text(outage.back, style: .time)) · +\(formatDuration(spare))")
            case .lasts(_, nil): Text("Power back \(Text(outage.back, style: .time))")
            case let .short(_, short, _): Text("Power back \(Text(outage.back, style: .time)) · −\(formatDuration(short))")
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(outage.lasts ? Palette.good : Palette.bad)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
