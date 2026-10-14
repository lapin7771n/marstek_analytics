import Foundation
import Testing
@testable import BatteryETA

struct FaceTests {
    private func snap(_ r: Reading?, _ error: FetchError? = nil) -> Snapshot {
        Snapshot(reading: r, error: error, checkedAt: .now)
    }

    @Test func discharging() {
        let face = Face(snap(reading(acW: 400)), floorPct: 12)
        #expect(face.percent == "80%")
        #expect(face.power == "−400 W")
        #expect(face.etaLabel == "EMPTY IN")
        #expect(face.eta == "8h00")
        #expect(face.tone == .warn)
        #expect(!face.stale)
    }

    @Test func underHalfAnHourIsBad() {
        #expect(Face(snap(reading(soc: 13, acW: 2000, capacityWh: 700)), floorPct: 12).tone == .bad)
    }

    @Test func chargingAtFullSaysFull() {
        let face = Face(snap(reading(soc: 100, acW: -50, capacityWh: 5120)), floorPct: 12)
        #expect(face.eta == "FULL")
        #expect(face.charging)
    }

    @Test func idleWithoutBackup() {
        #expect(Face(snap(reading(soc: 60, acW: 0)), floorPct: 12).eta == "—")
        #expect(Face(snap(reading(soc: 100, acW: 0, capacityWh: 5120)), floorPct: 12).eta == "FULL")
    }

    @Test func noLinkKeepsTheLastPercentGreyed() {
        let face = Face(snap(reading(acW: 400), .noLink), floorPct: 12)
        #expect(face.percent == "80%")
        #expect(face.stale)
        #expect(face.problem == "NO LINK")
        #expect(face.updated != nil)
    }

    @Test func noReadingShowsTheProblem() {
        let face = Face(snap(nil, .settings), floorPct: 12)
        #expect(face.eta == "SET IP")
        #expect(face.percent == "··")
        #expect(face.stale)
    }

    @Test func blockedSaysAllowLan() {
        #expect(Face(snap(nil, .blocked), floorPct: 12).eta == "ALLOW LAN")
    }
}
