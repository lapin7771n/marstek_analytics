import Foundation
import Testing
@testable import BatteryETA

struct FaceTests {
    private let readAt = Date(timeIntervalSince1970: 1_760_000_000)

    private func snap(_ r: Reading?, _ error: FetchError? = nil) -> Snapshot {
        Snapshot(reading: r, error: error, checkedAt: .now)
    }

    @Test func discharging() {
        let face = Face(snap(reading(acW: 400)), floorPct: 12, now: readAt)
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
        #expect(face.updated == readAt)
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

    @Test func onlyADeniedPermissionLinksToSettings() {
        #expect(Face(snap(nil, .blocked), floorPct: 12).blocked)
        #expect(Face(snap(reading(acW: 400), .blocked), floorPct: 12).blocked)
        #expect(!Face(snap(reading(acW: 400), .noLink), floorPct: 12).blocked)
        #expect(!Face(snap(reading(acW: 400)), floorPct: 12).blocked)
    }

    @Test func aReadingUnderHalfAnHourOldIsFresh() {
        #expect(!Face(snap(reading(acW: 400)), floorPct: 12, now: readAt.addingTimeInterval(29 * 60)).stale)
    }

    @Test func aReadingHalfAnHourOldIsStaleWithoutAnError() {
        #expect(Face(snap(reading(acW: 400)), floorPct: 12, now: readAt.addingTimeInterval(30 * 60)).stale)
        #expect(Face(snap(reading(acW: 400)), floorPct: 12, now: readAt.addingTimeInterval(31 * 60)).stale)
    }

    @Test func aBadReplySaysError() {
        let face = Face(snap(reading(acW: 400), .badReply), floorPct: 12, now: readAt)
        #expect(face.problem == "ERROR")
        #expect(face.stale)
    }

    @Test func aPowerBackTimeAddsAVerdict() {
        let back = readAt.addingTimeInterval(6 * 3600)
        #expect(Face(snap(reading(acW: 400)), floorPct: 12, powerBack: back, now: readAt).outage != nil)
        #expect(Face(snap(reading(acW: 400)), floorPct: 12, now: readAt).outage == nil)
        #expect(Face(snap(nil, .noLink), floorPct: 12, powerBack: back, now: readAt).outage == nil)
    }
}
