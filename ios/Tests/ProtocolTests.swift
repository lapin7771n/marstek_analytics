import Foundation
import Testing
@testable import BatteryETA

let esReply = #"{"id":2,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"bat_soc":80,"bat_cap":5120,"pv_power":0,"ongrid_power":-797,"offgrid_power":0,"total_grid_input_energy":47029}}"#
let batReply = #"{"id":3,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"soc":80,"charg_flag":true,"dischrg_flag":true,"bat_temp":24.0,"bat_capacity":4121.0,"rated_capacity":5120.0}}"#

struct ProtocolTests {
    @Test func requestAddressesInstanceZero() {
        let text = String(decoding: MarstekProtocol.request(id: 7, method: "ES.GetStatus"), as: UTF8.self)
        #expect(text == #"{"id":7,"method":"ES.GetStatus","params":{"id":0}}"#)
    }

    @Test func parsesTheEsReplyFromTheDevice() throws {
        #expect(try MarstekProtocol.replyId(Data(esReply.utf8)) == 2)
        #expect(try MarstekProtocol.esStatus(Data(esReply.utf8)) == EsStatus(socPct: 80, ongridW: -797, offgridW: 0))
    }

    @Test func parsesTheBatReplyFromTheDevice() throws {
        #expect(try MarstekProtocol.batStatus(Data(batReply.utf8)) == BatStatus(capacityWh: 4121, ratedWh: 5120, tempC: 24))
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
            try MarstekProtocol.esStatus(Data(#"{"id":2,"result":{"bat_soc":80,"ongrid_power":-797}}"#.utf8))
        }
    }

    @Test(arguments: [0.0, -5120.0])
    func aNonPositiveRatedCapacityIsBad(rated: Double) {
        let reply = #"{"id":3,"result":{"bat_capacity":2560,"rated_capacity":\#(rated),"bat_temp":24}}"#
        #expect(throws: DeviceError.self) { try MarstekProtocol.batStatus(Data(reply.utf8)) }
    }

    @Test func acPowerIsOngridPlusOffgrid() {
        let reading = Reading(
            time: Date(timeIntervalSince1970: 0),
            es: EsStatus(socPct: 80, ongridW: 100, offgridW: 50),
            bat: BatStatus(capacityWh: 4121, ratedWh: 5120, tempC: 24)
        )
        #expect(reading.acW == 150)
        #expect(reading.offgridW == 50)
    }

    @Test func garbageHasNoId() {
        #expect(throws: DeviceError.badReply("Reply has no id")) { try MarstekProtocol.replyId(Data("garbage".utf8)) }
    }
}
