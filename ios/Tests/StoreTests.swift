import Foundation
import Testing
@testable import BatteryETA

struct StoreTests {
    private func store(host: String = "192.168.68.50") -> Store {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        store.settings = BatterySettings(host: host, port: 30000, floorPct: 12)
        return store
    }

    @Test func aBatteryOnOldFirmwareIsPolledGently() {
        let settings = BatterySettings(host: "192.168.68.50", gentleHost: "192.168.68.50")
        #expect(settings.pollInterval == .seconds(60))
        #expect(!settings.retries)
    }

    @Test func aTypedHostIsPolledAsUsual() {
        #expect(BatterySettings(host: "192.168.68.50").pollInterval == .seconds(30))
        #expect(BatterySettings(host: "192.168.68.50").retries)
        let other = BatterySettings(host: "192.168.68.51", gentleHost: "192.168.68.50")
        #expect(other.pollInterval == .seconds(30))
        #expect(other.retries)
    }

    @Test func settingsStoredBeforeThisStillDecode() throws {
        let old = Data(#"{"host":"192.168.68.50","port":30000,"floorPct":15}"#.utf8)
        let settings = try JSONDecoder().decode(BatterySettings.self, from: old)
        #expect(settings == BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 15))
        #expect(settings.gentleHost == nil)
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

    @Test func aSearchSkipsTheFetch() async {
        let store = store()
        let now = Date(timeIntervalSince1970: 1000)
        store.searchUntil = now + 30
        let snapshot = await Refresher.refresh(store, now: now, maxAge: Refresher.widgetMaxAge) { _ in
            Issue.record("fetched during a search")
            return reading(acW: 400)
        }
        #expect(snapshot.reading == nil && snapshot.error == nil)
        #expect(store.snapshot == nil)
    }

    @Test func anExpiredSearchFetches() async {
        let store = store()
        let good = reading(acW: 400)
        store.searchUntil = good.time - 1
        let snapshot = await Refresher.refresh(store, now: good.time) { _ in good }
        #expect(snapshot.reading == good)
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
}
