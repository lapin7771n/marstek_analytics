import ActivityKit
import Foundation

enum OutageActivityController {
    typealias Activities = Activity<OutageActivityAttributes>

    // Works from the stored snapshot: it sends nothing to the battery.
    static func sync(_ store: Store, canStart: Bool, now: Date = .now) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let new = OutageActivityAttributes.state(store.snapshot, floorPct: store.settings.floorPct, powerBack: store.powerBack, now: now)
        let running = Activities.activities.first
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
