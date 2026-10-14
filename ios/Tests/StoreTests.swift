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

    @Test(arguments: ["", "192.168.68.50; rm"])
    func aBadHostSendsNothing(host: String) async {
        var fetched = false
        let snapshot = await Refresher.refresh(store(host: host)) { _ in
            fetched = true
            return reading(acW: 400)
        }
        #expect(snapshot.error == .settings)
        #expect(!fetched)
    }

    @Test func aFreshStoreHasDefaults() {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        #expect(store.settings == BatterySettings())
        #expect(store.snapshot == nil)
    }
}
