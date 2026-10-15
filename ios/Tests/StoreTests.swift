import Foundation
import Testing
@testable import BatteryETA

struct StoreTests {
    private func store(host: String = "192.168.68.50") -> Store {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        store.settings = BatterySettings(host: host, port: 30000, floorPct: 12)
        return store
    }

    @Test func aGoodFetchIsStored() async {
        let store = store()
        let good = reading(acW: 400)
        let snapshot = await Refresher.refresh(store, now: good.time) { _ in good }
        #expect(snapshot == Snapshot(reading: good, error: nil, checkedAt: good.time))
        #expect(store.snapshot == snapshot)
    }

    @Test func aFailedFetchKeepsTheLastReading() async {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store) { _ in good }
        let snapshot = await Refresher.refresh(store) { _ in throw DeviceError.timeout }
        #expect(snapshot.reading == good)
        #expect(snapshot.error == .noLink)
    }

    @Test func aDeniedPermissionIsBlocked() async {
        let snapshot = await Refresher.refresh(store()) { _ in throw DeviceError.blocked }
        #expect(snapshot.error == .blocked)
    }

    @Test(arguments: ["", "192.168.68.50; rm", "192.168.68.500", "192.168.68"])
    func aBadHostSendsNothing(host: String) async {
        var fetched = false
        let snapshot = await Refresher.refresh(store(host: host)) { _ in
            fetched = true
            return reading(acW: 400)
        }
        #expect(snapshot.error == .settings)
        #expect(!fetched)
    }

    @Test func aBadReplyIsAnError() async {
        let snapshot = await Refresher.refresh(store()) { _ in throw DeviceError.badReply("x") }
        #expect(snapshot.error == .badReply)
        #expect(Face(snapshot, floorPct: 12).problem == "ERROR")
    }

    @Test func anIpNeedsFourOctetsUpTo255() {
        #expect(BatterySettings(host: "192.168.68.500").problem == "Enter the battery IP address")
        #expect(BatterySettings(host: "192.168.68").problem == "Enter the battery IP address")
        #expect(BatterySettings(host: "192.168.68.50").problem == nil)
        #expect(BatterySettings(host: "battery.local").problem == nil)
    }

    @Test func aFreshStoreHasDefaults() {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        #expect(store.settings == BatterySettings())
        #expect(store.snapshot == nil)
    }

    @Test func aFreshSnapshotIsReused() async {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store, now: good.time) { _ in good }
        var fetched = false
        let snapshot = await Refresher.refresh(store, now: good.time.addingTimeInterval(5 * 60), maxAge: 10 * 60) { _ in
            fetched = true
            return good
        }
        #expect(!fetched)
        #expect(snapshot.checkedAt == good.time)
    }

    @Test func anOldSnapshotIsFetchedAgain() async {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store, now: good.time) { _ in good }
        var fetched = false
        _ = await Refresher.refresh(store, now: good.time.addingTimeInterval(11 * 60), maxAge: 10 * 60) { _ in
            fetched = true
            return good
        }
        #expect(fetched)
    }

    @Test func aSettingsSnapshotIsNotReused() async {
        let store = store(host: "")
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        _ = await Refresher.refresh(store, now: now) { _ in reading(acW: 400) }
        store.settings = BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 12)
        let snapshot = await Refresher.refresh(store, now: now.addingTimeInterval(60), maxAge: 10 * 60) { _ in reading(acW: 400) }
        #expect(snapshot.error == nil)
        #expect(snapshot.reading != nil)
    }

    @Test func concurrentRefreshesShareOneFetch() async {
        let gate = SharedRefresh()
        let counter = FetchCounter()
        async let a = gate.run { await counter.fetch() }
        async let b = gate.run { await counter.fetch() }
        async let c = gate.run { await counter.fetch() }
        _ = await (a, b, c)
        #expect(await counter.count == 1)
        _ = await gate.run { await counter.fetch() }
        #expect(await counter.count == 2)
    }

    @Test func anAlertRunAndAWidgetRefreshShareOneRequest() async {
        let store = store()
        let counter = FetchCounter()
        let now = reading(acW: 400).time
        _ = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now) { _ in await counter.fetchReading() }
        _ = await Refresher.refresh(store, now: now.addingTimeInterval(5 * 60), maxAge: Refresher.widgetMaxAge) { _ in
            await counter.fetchReading()
        }
        #expect(await counter.count == 1)
    }

    @Test func anAlertRunReusesAFreshSnapshot() async {
        let store = store()
        let counter = FetchCounter()
        let now = reading(acW: 400).time
        store.snapshot = Snapshot(reading: reading(acW: 400), error: nil, checkedAt: now)
        _ = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now.addingTimeInterval(9 * 60)) { _ in
            await counter.fetchReading()
        }
        #expect(await counter.count == 0)
    }

    @Test func anAlertRunFetchesAnOldSnapshotOnce() async {
        let store = store()
        let counter = FetchCounter()
        let now = reading(acW: 400).time
        store.snapshot = Snapshot(reading: reading(acW: 400), error: nil, checkedAt: now)
        _ = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now.addingTimeInterval(11 * 60)) { _ in
            await counter.fetchReading()
        }
        #expect(await counter.count == 1)
    }

    @Test func anAlertRunRemembersItNotified() async {
        let store = store()
        store.alert = AlertState(on: true)
        let now = reading(acW: 400).time
        store.snapshot = Snapshot(reading: reading(soc: 12, acW: 100, capacityWh: 614.4), error: nil, checkedAt: now)
        let first = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now) { _ in reading(acW: 400) }
        let second = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now) { _ in reading(acW: 400) }
        #expect(first == .reserve(socPct: 12, watts: 100))
        #expect(second == nil)
    }

    @Test func powerBackIsStored() {
        let store = store()
        #expect(store.powerBack == nil)
        let back = Date(timeIntervalSince1970: 1_760_020_000)
        store.powerBack = back
        #expect(store.powerBack == back)
        store.powerBack = nil
        #expect(store.powerBack == nil)
    }

    @Test func aPowerBackTimeSendsNoBatteryRequest() async {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store, now: good.time) { _ in good }
        let counter = FetchCounter()
        let now = good.time.addingTimeInterval(60)
        store.powerBack = good.time.addingTimeInterval(6 * 3600)
        let snapshot = await Refresher.refresh(store, now: now, maxAge: Refresher.widgetMaxAge) { await counter.read($0) }
        #expect(Face(snapshot, floorPct: store.settings.floorPct, powerBack: store.powerBack, now: now).outage != nil)
        #expect(await counter.count == 0)
    }

    @Test func theOutageGroupAndScheduleAreStored() {
        let store = store()
        #expect(store.outageGroup == nil && store.schedule == nil && !store.powerBackFromSchedule)
        store.outageGroup = OutageGroup(group: 19, subgroup: 1, address: "вул. Хрещатик, 1")
        store.schedule = ScheduleState(key: "19.1", checkedAt: .now, days: nil)
        store.powerBackFromSchedule = true
        #expect(store.outageGroup?.key == "19.1" && store.schedule?.key == "19.1" && store.powerBackFromSchedule)
    }

    @Test func theScheduleFeedNeverTouchesTheBattery() async throws {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store, now: good.time) { _ in good }
        store.outageGroup = OutageGroup(group: 19, subgroup: 1, address: "вул. Хрещатик, 1")
        let midnight = Schedule.kyiv.startOfDay(for: good.time)
        let date = ISO8601DateFormatter.string(from: midnight, timeZone: Schedule.kyiv.timeZone, formatOptions: .withInternetDateTime)
        let reply = #"{"19.1":{"today":{"slots":[{"start":0,"end":1440,"type":"Definite"}],"date":"\#(date)","status":"ScheduleApplies"},"tomorrow":{"slots":[],"date":"\#(date)","status":"WaitingForSchedule"}}}"#
        let log = URLLog()
        let now = good.time.addingTimeInterval(60)
        #expect(await ScheduleFeed.tick(store, now: now, client: YasnoClient { url in await log.add(url); return Data(reply.utf8) }))
        let counter = FetchCounter()
        let snapshot = await Refresher.refresh(store, now: now, maxAge: Refresher.widgetMaxAge) { await counter.read($0) }
        #expect(Face(snapshot, floorPct: 12, powerBack: store.powerBack, now: now).outage != nil)
        #expect(await counter.count == 0)
        let hosts = await log.urls.map(\.host)
        #expect(!hosts.isEmpty && hosts.allSatisfy { $0 == "app.yasno.ua" && $0 != store.settings.host })
    }

    @Test func pollingStaysAsItIs() {
        #expect(Refresher.appPollInterval == .seconds(30))
        #expect(Refresher.widgetMaxAge == 10 * 60)
    }
}

actor FetchCounter {
    var count = 0

    func fetch() async -> Snapshot {
        count += 1
        try? await Task.sleep(for: .milliseconds(200))
        return Snapshot(reading: nil, error: .noLink, checkedAt: .now)
    }

    func fetchReading() -> Reading {
        count += 1
        return reading(acW: 400)
    }

    func read(_ settings: BatterySettings) -> Reading {
        count += 1
        return reading(acW: 400)
    }
}
