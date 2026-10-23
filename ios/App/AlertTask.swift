import BackgroundTasks
import UserNotifications

enum AlertTask {
    static let id = "com.mlapin.marstek.battery.alert"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
    }

    private static func allow() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func turnOn() async -> Bool {
        let granted = await allow()
        Store().alert = AlertState(on: granted)
        if granted { schedule() }
        return granted
    }

    static func turnOnOutageAhead() async -> Bool {
        let granted = await allow()
        Store().outageAhead = granted
        if granted {
            schedule()
            await OutageAheadTask.update(Store())
        }
        return granted
    }

    static func turnOffOutageAhead() {
        Store().outageAhead = false
        OutageAheadTask.remove()
        if !Store().alert.on { cancel() }
    }

    // One ES.GetStatus at most, no retry: a failed read waits for the next run.
    @Sendable static func fetchOnce(_ settings: BatterySettings) async throws -> Reading {
        try await MarstekClient(host: settings.host, port: UInt16(settings.port), retry: false, trace: { Store().log($1, at: $0) }).reading()
    }

    static func evaluate(
        _ store: Store = Store(),
        gate: SharedRefresh = .shared,
        now: Date = .now,
        fetch: @escaping @Sendable (BatterySettings) async throws -> Reading = AlertTask.fetchOnce
    ) async -> LowBattery? {
        let snapshot = await gate.run { await Refresher.refresh(store, now: now, maxAge: Refresher.widgetMaxAge, fetch: fetch) }
        var state = store.alert
        let low = LowBatteryAlert.check(snapshot, floorPct: store.settings.floorPct, state: &state, now: now)
        store.alert = state
        return low
    }

    static func run() async {
        let store = Store()
        guard store.alert.on || store.outageAhead,
              await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized else { return }
        schedule()
        if let low = await evaluate(store) {
            let content = UNMutableNotificationContent()
            content.title = low.title
            content.body = low.body
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
        }
        await OutageAheadTask.update(store)
    }
}
