import ActivityKit
import Foundation

enum OutageActivityController {
    typealias Activities = Activity<OutageActivityAttributes>

    // An ended activity can stay in the list until it is dismissed.
    private static var live: [Activities] {
        Activities.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    static var isRunning: Bool { !live.isEmpty }

    // Works from the stored snapshot: it sends nothing to the battery.
    static func sync(_ store: Store, canStart: Bool, now: Date = .now) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let new = OutageActivityAttributes.state(store.snapshot, floorPct: store.settings.floorPct, powerBack: store.powerBack, outageStart: OutageActivityAttributes.outageStart(store, now: now), now: now)
        let running = live.first
        for extra in live.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        switch OutageActivityStep.decide(new: new, running: running?.content.state, canStart: canStart) {
        case .start:
            guard let new else { return }
            do {
                _ = try Activities.request(attributes: OutageActivityAttributes(), content: .init(state: new, staleDate: new.back), pushType: nil)
            } catch {
                store.log("Live activity not started: \(error.localizedDescription)")
            }
        case .update:
            guard let new else { return }
            await running?.update(.init(state: new, staleDate: new.back))
        case .end:
            for activity in Activities.activities { await activity.end(nil, dismissalPolicy: .default) }
        case .nothing:
            break
        }
    }
}
