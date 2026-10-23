import UserNotifications

enum OutageAheadTask {
    static let id = "outage-ahead"
    static let recentSpan: TimeInterval = 3 * 3600

    // Works from the stored snapshot and history: it sends nothing to the battery.
    static func update(_ store: Store, now: Date = .now) async {
        guard store.outageAhead else { return }
        _ = await ScheduleFeed.tick(store, now: now)
        if store.loadModel.map({ !Calendar.current.isDate($0.fittedAt, inSameDayAs: now) }) ?? true {
            store.loadModel = LoadModel.fit(store.history.samples, now: now)
        }
        var answer = ScheduleAnswer.clear
        if let group = store.outageGroup, let state = store.schedule, state.key == group.key, let days = state.days {
            answer = Schedule.answer(days, now: now)
        }
        let center = UNUserNotificationCenter.current()
        guard case let .off(start, _) = answer, start > now else {
            await removePending(store)
            return
        }
        guard let r = store.snapshot?.reading, now.timeIntervalSince(r.time) < Face.staleAfter else { return }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let recent = store.history.samples.filter { (0...recentSpan).contains(now.timeIntervalSince($0.time)) }.compactMap(\.offgridW)
        let recentW = recent.isEmpty ? r.offgridW : Double(recent.reduce(0, +)) / Double(recent.count)
        let warning = OutageAhead.check(r, floorPct: store.settings.floorPct, answer: answer, model: store.loadModel, recentW: recentW, now: now)

        switch OutageNotice.action(for: warning, now: now, notified: store.outageAheadNotified) {
        case .remove: await removePending(store)
        case let .schedule(at):
            store.outageAheadNotified = warning?.start
            await add(warning, trigger: UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at), repeats: false))
        case .deliverNow:
            store.outageAheadNotified = warning?.start
            await add(warning, trigger: nil)
        case .nothing: break
        }
    }

    // A pending request that never fired was not delivered, so the same outage can be announced again.
    private static func removePending(_ store: Store) async {
        let center = UNUserNotificationCenter.current()
        guard await center.pendingNotificationRequests().contains(where: { $0.identifier == id }) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        store.outageAheadNotified = nil
    }

    static func remove() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    private static func add(_ warning: OutageWarning?, trigger: UNNotificationTrigger?) async {
        guard let warning else { return }
        let content = UNMutableNotificationContent()
        content.title = warning.title
        content.body = warning.body
        content.sound = .default
        content.userInfo = ["start": warning.start.timeIntervalSince1970]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
