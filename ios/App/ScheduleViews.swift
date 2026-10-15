import SwiftUI

struct ScheduleNote: View {
    let group: OutageGroup
    let state: ScheduleState?
    let now: Date

    var body: some View {
        line
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var line: some View {
        if let state, state.key == group.key {
            if let days = state.days {
                switch Schedule.answer(days, now: now) {
                case let .off(from, until):
                    Text("YASNO, group \(group.key): off \(Text(from, style: .time))–\(Text(until, style: .time)).")
                case .emergency:
                    Text("YASNO, group \(group.key): emergency outages, no end time.")
                case .clear:
                    Text("YASNO, group \(group.key): no outage ahead.")
                }
            } else if state.failed {
                Text("YASNO did not answer.")
            }
        }
    }
}
