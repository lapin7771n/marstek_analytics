import Foundation
import Testing
@testable import BatteryETA

let esReply = #"{"id":2,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"bat_soc":80,"bat_cap":5120,"pv_power":0,"ongrid_power":-797,"offgrid_power":0,"total_grid_input_energy":47029}}"#

struct ProtocolTests {
    @Test func requestIdsSurviveTheFirmwaresSixteenBits() {
        for _ in 0..<1000 {
            let id = MarstekProtocol.newId()
            #expect((1...32_767).contains(id) && (1...32_767).contains(id + 1))
        }
    }

    @Test func requestAddressesInstanceZero() {
        let text = String(decoding: MarstekProtocol.request(id: 7, method: "ES.GetStatus"), as: UTF8.self)
        #expect(text == #"{"id":7,"method":"ES.GetStatus","params":{"id":0}}"#)
    }

    @Test func parsesTheEsReplyFromTheDevice() throws {
        #expect(try MarstekProtocol.replyId(Data(esReply.utf8)) == 2)
        #expect(try MarstekProtocol.esStatus(Data(esReply.utf8)) == EsStatus(socPct: 80, ongridW: -797, offgridW: 0, ratedWh: 5120))
    }

    @Test func aReplyWithNoResultIsBad() {
        #expect(throws: DeviceError.badReply("Reply has no result")) {
            try MarstekProtocol.esStatus(Data(#"{"id":2,"src":"x"}"#.utf8))
        }
    }

    @Test func aDeviceErrorCarriesItsCode() {
        #expect(throws: DeviceError.badReply("Device error -32601: Method not found")) {
            try MarstekProtocol.esStatus(Data(#"{"id":2,"error":{"code":-32601,"message":"Method not found"}}"#.utf8))
        }
    }

    @Test func aMissingFieldIsBadNeverZero() {
        #expect(throws: DeviceError.badReply("Reply has a missing field")) {
            try MarstekProtocol.esStatus(Data(#"{"id":2,"result":{"bat_soc":80,"ongrid_power":-797,"bat_cap":5120}}"#.utf8))
        }
    }

    @Test func acPowerIsOngridPlusOffgrid() {
        let reading = Reading(time: Date(timeIntervalSince1970: 0), es: EsStatus(socPct: 80, ongridW: 100, offgridW: 50, ratedWh: 5120))
        #expect(reading.acW == 150)
        #expect(reading.offgridW == 50)
    }

    @Test func energyLeftIsChargeTimesRatedCapacity() {
        let reading = Reading(time: Date(timeIntervalSince1970: 0), es: EsStatus(socPct: 80, ongridW: 0, offgridW: 0, ratedWh: 5120))
        #expect(reading.capacityWh == 4096)
        #expect(reading.ratedWh == 5120)
    }

    @Test func aMissingRatedCapacityIsBad() {
        #expect(throws: DeviceError.badReply("Reply has a missing field")) {
            try MarstekProtocol.esStatus(Data(#"{"id":2,"result":{"bat_soc":80,"ongrid_power":-797,"offgrid_power":0}}"#.utf8))
        }
    }

    @Test(arguments: [0.0, -5120.0])
    func aNonPositiveRatedCapacityIsBad(rated: Double) {
        let reply = #"{"id":2,"result":{"bat_soc":50,"ongrid_power":0,"offgrid_power":0,"bat_cap":\#(rated)}}"#
        #expect(throws: DeviceError.badReply("Reply has bat_cap \(rated)")) { try MarstekProtocol.esStatus(Data(reply.utf8)) }
    }

    @Test func aSnapshotStoredWithTemperatureStillDecodes() throws {
        let old = #"{"reading":{"time":0,"socPct":80,"acW":400,"offgridW":0,"capacityWh":4121,"ratedWh":5120,"tempC":24},"checkedAt":0}"#
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        defaults.set(Data(old.utf8), forKey: "snapshot")
        #expect(Store(defaults: defaults).snapshot?.reading?.capacityWh == 4121)
    }

    @Test func garbageHasNoId() {
        #expect(throws: DeviceError.badReply("Reply has no id")) { try MarstekProtocol.replyId(Data("garbage".utf8)) }
    }
}
