import Foundation
import Testing
@testable import BatteryETA

func reading(soc: Int = 80, acW: Double, offgridW: Double = 0, capacityWh: Double = 4121) -> Reading {
    Reading(time: Date(timeIntervalSince1970: 1_760_000_000), socPct: soc, acW: acW, offgridW: offgridW, capacityWh: capacityWh, ratedWh: 5120)
}

struct EstimateTests {
    @Test func dischargingCountsDownToTheReserve() throws {
        let est = QuickEstimate.estimate(reading(acW: 400), floorPct: 12)
        #expect(est.mode == .discharging)
        #expect(abs(try #require(est.hours) - 8.0427) < 0.001)
    }

    @Test func chargingCountsUpToRated() throws {
        let est = QuickEstimate.estimate(reading(acW: -797), floorPct: 12)
        #expect(est.mode == .charging)
        #expect(abs(try #require(est.hours) - 1.4244) < 0.001)
    }

    @Test func idleWithABackupLoadProjectsAnOutage() throws {
        let est = QuickEstimate.estimate(reading(acW: 0, offgridW: 150), floorPct: 12)
        #expect(est.mode == .idle)
        #expect(abs(try #require(est.hours) - 21.447) < 0.001)
    }

    @Test func idleWithoutABackupLoadHasNoEta() {
        #expect(QuickEstimate.estimate(reading(acW: 20), floorPct: 12) == Estimate(mode: .idle, hours: nil))
    }

    @Test func belowTheReserveIsZeroNeverNegative() {
        #expect(QuickEstimate.estimate(reading(soc: 11, acW: 400, capacityWh: 600), floorPct: 12).hours == 0)
    }

    @Test func fullWhileChargingIsZero() {
        #expect(QuickEstimate.estimate(reading(soc: 100, acW: -50, capacityWh: 5120), floorPct: 12).hours == 0)
    }

    @Test func aTinyLoadIsCapped() {
        #expect(QuickEstimate.estimate(reading(acW: 31, capacityWh: 10_000), floorPct: 0).hours == 240)
    }
}
