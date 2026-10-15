import Foundation
import Testing
@testable import BatteryETA

struct LowBatteryAlertTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func snapshot(soc: Int, acW: Double, error: FetchError? = nil, age: TimeInterval = 0) -> Snapshot {
        let r = Reading(
            time: now.addingTimeInterval(-age), socPct: soc, acW: acW, offgridW: 0,
            capacityWh: Double(soc) / 100 * 5120, ratedWh: 5120
        )
        return Snapshot(reading: r, error: error, checkedAt: now)
    }

    private func check(_ s: Snapshot, _ state: inout AlertState) -> LowBattery? {
        LowBatteryAlert.check(s, floorPct: 12, state: &state, now: now)
    }

    @Test func underHalfAnHourWhileDischargingNotifies() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 2000), &state) == .soon(minutes: 11, watts: 2000))
        #expect(state.soonAlerted)
    }

    @Test func halfAnHourOrMoreIsQuiet() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 400), &state) == nil)
        #expect(state == AlertState(on: true))
    }

    @Test func reachingTheReserveNotifiesOnce() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 12, acW: 100), &state) == .reserve(socPct: 12, watts: 100))
        #expect(check(snapshot(soc: 11, acW: 100), &state) == nil)
    }

    @Test func theReserveWithNoLoadLeavesOutThePower() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 12, acW: 0), &state) == .reserve(socPct: 12, watts: nil))
    }

    @Test func underHalfAnHourThenTheReserveNotifiesTwice() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 2000), &state) == .soon(minutes: 11, watts: 2000))
        #expect(check(snapshot(soc: 12, acW: 2000), &state) == .reserve(socPct: 12, watts: 2000))
        #expect(check(snapshot(soc: 12, acW: 2000), &state) == nil)
    }

    @Test func chargingAtTheReserveIsQuiet() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 10, acW: -500), &state) == nil)
    }

    @Test func justUnderHalfAnHourReadsUnder30Minutes() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 760), &state) == .soon(minutes: 29, watts: 760))
    }

    @Test func aWobblingLoadNotifiesOnce() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 2000), &state) != nil)
        #expect(check(snapshot(soc: 20, acW: 400), &state) == nil)
        #expect(state.soonAlerted)
        #expect(check(snapshot(soc: 19, acW: 2000), &state) == nil)
    }

    @Test func chargingArmsTheNextAlerts() {
        var state = AlertState(on: true, soonAlerted: true, reserveAlerted: true)
        #expect(check(snapshot(soc: 13, acW: -500), &state) == nil)
        #expect(state == AlertState(on: true))
        #expect(check(snapshot(soc: 12, acW: 100), &state) == .reserve(socPct: 12, watts: 100))
    }

    @Test func aChargeWellAboveTheReserveArmsTheNextAlerts() {
        var state = AlertState(on: true, soonAlerted: true, reserveAlerted: true)
        _ = check(snapshot(soc: 18, acW: 100), &state)
        #expect(state == AlertState(on: true))
    }

    @Test func aFailedFetchSendsNothing() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 10, acW: 100, error: .noLink), &state) == nil)
        #expect(state == AlertState(on: true))
    }

    @Test func anOldReadingSendsNothing() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 10, acW: 100, age: 31 * 60), &state) == nil)
        #expect(state == AlertState(on: true))
    }

    @Test func anAlertTurnedOffSendsNothing() {
        var state = AlertState()
        #expect(check(snapshot(soc: 10, acW: 100), &state) == nil)
    }

    @Test func theTextFollowsTheDesign() {
        #expect(LowBattery.soon(minutes: 25, watts: 1850).title == "Under 30 min left")
        #expect(LowBattery.soon(minutes: 25, watts: 1850).body == "Empty in 25 min at −1850 W. Turn off heavy loads.")
        #expect(LowBattery.reserve(socPct: 12, watts: 1850).title == "Battery at reserve")
        #expect(LowBattery.reserve(socPct: 12, watts: 1850).body == "12 % left, −1850 W. The battery stops at the reserve.")
        #expect(LowBattery.reserve(socPct: 12, watts: nil).body == "12 % left. The battery stops at the reserve.")
    }
}
