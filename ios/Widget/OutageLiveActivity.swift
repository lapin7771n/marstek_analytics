import ActivityKit
import SwiftUI
import WidgetKit

struct OutageLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OutageActivityAttributes.self) { context in
            OutageCard(state: context.state)
                .padding(16)
                .activityBackgroundTint(Palette.bg)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    OutageCard(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill").foregroundStyle(statusColor(context.state))
            } compactTrailing: {
                Countdown(state: context.state, size: 14).frame(maxWidth: 56)
            } minimal: {
                OutageRing(state: context.state)
            }
        }
    }
}

private func statusColor(_ state: OutageActivityAttributes.ContentState) -> Color {
    state.lasts ? Palette.good : Palette.bad
}

private struct Countdown: View {
    let state: OutageActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if let runsOutAt = state.runsOutAt {
                Text(timerInterval: Date.now...max(.now, runsOutAt), showsHours: true)
            } else {
                Text(verbatim: "—")
            }
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(.white)
    }
}

private struct OutageRing: View {
    let state: OutageActivityAttributes.ContentState

    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0, Double(state.socPct) / 100)))
                .stroke(statusColor(state), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
    }
}

private struct OutageCard: View {
    let state: OutageActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Battery ETA · outage").foregroundStyle(Palette.label)
                Spacer()
                code.foregroundStyle(statusColor(state))
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(1)
            HStack(alignment: .lastTextBaseline) {
                Countdown(state: state, size: 34)
                Text("left").font(.system(size: 15, design: .rounded)).foregroundStyle(Palette.label)
                Spacer()
                HStack(spacing: 4) {
                    Text(verbatim: "\(state.socPct) %")
                    Text(verbatim: "·")
                    Text("−\(state.loadW) W")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            }
            bar
            HStack {
                if !state.lasts, let runsOutAt = state.runsOutAt {
                    Text("Empty \(Text(runsOutAt, style: .time))").foregroundStyle(Palette.bad)
                }
                Spacer()
                Text("Grid \(Text(state.back, style: .time))").foregroundStyle(Palette.label)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
        }
    }

    private var code: Text {
        if state.lasts { return Text("LASTS") }
        guard let runsOutAt = state.runsOutAt else { return Text("") }
        return Text("RUNS OUT \(Text(runsOutAt, style: .time))")
    }

    // The bar spans now to grid return; the coloured part is the stretch the battery covers.
    private var bar: some View {
        let span = max(1, state.back.timeIntervalSinceNow)
        let covered = state.lasts ? 1 : min(1, max(0, (state.runsOutAt?.timeIntervalSinceNow ?? 0) / span))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(statusColor(state)).frame(width: geo.size.width * covered)
            }
        }
        .frame(height: 6)
    }
}
