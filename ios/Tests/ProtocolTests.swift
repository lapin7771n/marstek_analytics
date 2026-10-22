import Foundation
import Testing
@testable import BatteryETA

let esReply = #"{"id":2,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"bat_soc":80,"bat_cap":5120,"pv_power":0,"ongrid_power":-797,"offgrid_power":0,"total_grid_input_energy":47029}}"#

let deviceReply = "{\n\t\"id\":\t7,\n\t\"src\":\t\"VenusE 3.0-bc2a3314ce8d\",\n\t\"result\":\t{\n\t\t\"device\":\t\"VenusE 3.0\",\n\t\t\"ver\":\t150,\n\t\t\"ble_mac\":\t\"bc2a3314ce8d\",\n\t\t\"wifi_mac\":\t\"9a254a554cc6\",\n\t\t\"wifi_name\":\t\"Home\",\n\t\t\"ip\":\t\"192.168.68.50\"\n\t}\n}"
let device151Reply = #"{"id":7,"src":"VNSE3-0-bc2a3314ce8d","result":{"device":"VenusE 3.0","ver":151,"ble_mac":"bc2a3314ce8d","wifi_mac":"9a254a554cc6","wifi_name":"Home","ip":"192.168.68.50"}}"#
let device1476Reply = #"{"id":7,"src":"VenusE 3.0-bc2a3314ce8d","result":{"device":"VenusE 3.0","ver":1476,"ble_mac":"bc2a3314ce8d","wifi_mac":"9a254a554cc6","wifi_name":"Home","ip":"192.168.68.50"}}"#
let device148Reply = #"{"id":7,"src":"VenusE 3.0-a8dd9fd8d15c","result":{"device":"VenusE 3.0","ver":148,"ble_mac":"a8dd9fd8d15c","wifi_mac":"","wifi_name":"","ip":"192.168.1.251"}}"#
let deviceE2Reply = #"{"id":7,"src":"VenusE-bc2a3314ce8d","result":{"device":"VenusE","ver":145,"ip":"192.168.68.50"}}"#
let deviceV135Reply = #"{"id":7,"src":"VenusE 3.0-bc2a3314ce8d","result":{"device":"VenusE 3.0","ver":135,"ble_mac":"bc2a3314ce8d","wifi_mac":"9a254a554cc6","wifi_name":"Home","ip":"192.168.68.50"}}"#
let deviceE2V135Reply = #"{"id":7,"src":"VenusE-bc2a3314ce8d","result":{"device":"VenusE","ver":135,"ble_mac":"bc2a3314ce8d","wifi_mac":"9a254a554cc6","wifi_name":"Home","ip":"192.168.68.50"}}"#
let esV135Reply = #"{"id":2,"src":"VenusE-24215edb178f","result":{"id":0,"bat_soc":98,"bat_cap":5120,"pv_power":0,"ongrid_power":100,"offgrid_power":0,"total_pv_energy":0,"total_grid_output_energy":2548,"total_grid_input_energy":3273,"total_load_energy":0}}"#
let esLegacyReply = #"{"id":2,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"bat_soc":98,"bat_cap":5120,"ongrid_power":100,"offgrid_power":0,"total_grid_output_energy":2548,"total_grid_input_energy":3273,"total_load_energy":0}}"#
let esE2Reply = #"{"id":2,"src":"VenusE-bc2a3314ce8d","result":{"id":0,"bat_soc":98,"bat_cap":5120,"bat_power":-80,"ongrid_power":100,"offgrid_power":0}}"#

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
            try MarstekProtocol.esStatus(Data(#"{"id":2,"result":{"bat_soc":80,"offgrid_power":0,"bat_cap":5120}}"#.utf8))
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

    @Test func eachFirmwareReportsItsVersion() throws {
        #expect(try MarstekProtocol.device(Data(device151Reply.utf8)) == DeviceInfo(model: "VenusE 3.0", mac: "9a254a554cc6", firmware: 151))
        #expect(try MarstekProtocol.device(Data(device1476Reply.utf8)).firmware == 147)
        #expect(try MarstekProtocol.device(Data(device148Reply.utf8)) == DeviceInfo(model: "VenusE 3.0", mac: "a8dd9fd8d15c", firmware: 148))
        #expect(try MarstekProtocol.device(Data(deviceE2Reply.utf8)) == DeviceInfo(model: "VenusE", mac: nil, firmware: 145))
    }

    @Test(arguments: [
        (#""ver":150.9,"#, 150), (#""ver":"148.3","#, 148), (#""ver":"135","#, 135),
        (#""ver":"V1.35","#, nil), (#""ver":null,"#, nil), ("", nil),
        (#""ver":0,"#, nil), (#""ver":1.5,"#, nil), (#""ver":"1.0.3","#, nil),
    ] as [(String, Int?)])
    func aVerInAnyFormStillFindsTheBattery(field: String, firmware: Int?) throws {
        let reply = #"{"id":7,"result":{\#(field)"device":"VenusE 3.0"}}"#
        #expect(try MarstekProtocol.device(Data(reply.utf8)) == DeviceInfo(model: "VenusE 3.0", mac: nil, firmware: firmware))
    }

    @Test func v135RepliesParse() throws {
        #expect(try MarstekProtocol.device(Data(deviceV135Reply.utf8)) == DeviceInfo(model: "VenusE 3.0", mac: "9a254a554cc6", firmware: 135))
        #expect(try MarstekProtocol.device(Data(deviceE2V135Reply.utf8)) == DeviceInfo(model: "VenusE", mac: "9a254a554cc6", firmware: 135))
        #expect(try MarstekProtocol.esStatus(Data(esV135Reply.utf8)) == EsStatus(socPct: 98, ongridW: 100, offgridW: 0, ratedWh: 5120))
    }

    @Test func olderFirmwareStatusParses() throws {
        let expected = EsStatus(socPct: 98, ongridW: 100, offgridW: 0, ratedWh: 5120)
        #expect(try MarstekProtocol.esStatus(Data(esLegacyReply.utf8)) == expected)
        #expect(try MarstekProtocol.esStatus(Data(esE2Reply.utf8)) == expected)
    }

    @Test func aSilentBatteryManagementSystemIsBad() {
        #expect(throws: DeviceError.badReply("Reply has bat_cap 0.0")) {
            try MarstekProtocol.esStatus(Data(#"{"id":2,"result":{"bat_soc":0,"bat_cap":0,"ongrid_power":0,"offgrid_power":0}}"#.utf8))
        }
    }

    @Test(arguments: [#""bat_cap":null,"#, "", #""bat_cap":0,"#, #""bat_cap":-5120,"#])
    func aMissingRatedCapacityUsesTheVenusRating(field: String) throws {
        let reply = #"{"id":2,"result":{"bat_soc":80,\#(field)"ongrid_power":0,"offgrid_power":0}}"#
        #expect(try MarstekProtocol.esStatus(Data(reply.utf8)).ratedWh == 5120)
    }

    @Test func aNullOffgridPowerCountsAsZero() throws {
        let reply = #"{"id":2,"result":{"bat_soc":50,"bat_cap":5120,"ongrid_power":-797,"offgrid_power":null}}"#
        #expect(try MarstekProtocol.esStatus(Data(reply.utf8)).offgridW == 0)
    }

    @Test func aNullOngridPowerIsBad() {
        #expect(throws: DeviceError.badReply("Reply has a missing field")) {
            try MarstekProtocol.esStatus(Data(#"{"id":2,"result":{"bat_soc":50,"bat_cap":5120,"ongrid_power":null}}"#.utf8))
        }
    }

    @Test func aSnapshotStoredWithTemperatureStillDecodes() throws {
        let old = #"{"reading":{"time":0,"socPct":80,"acW":400,"offgridW":0,"capacityWh":4121,"ratedWh":5120,"tempC":24},"checkedAt":0}"#
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        defaults.set(Data(old.utf8), forKey: "snapshot")
        #expect(Store(defaults: defaults, directory: tempDirectory()).snapshot?.reading?.capacityWh == 4121)
    }

    @Test func garbageHasNoId() {
        #expect(throws: DeviceError.badReply("Reply has no id")) { try MarstekProtocol.replyId(Data("garbage".utf8)) }
    }

    @Test func deviceRequestAsksEveryDevice() {
        let text = String(decoding: MarstekProtocol.deviceRequest(id: 7), as: UTF8.self)
        #expect(text == #"{"id":7,"method":"Marstek.GetDevice","params":{"ble_mac":"0"}}"#)
    }

    @Test func parsesTheDeviceReply() throws {
        #expect(try MarstekProtocol.device(Data(deviceReply.utf8)) == DeviceInfo(model: "VenusE 3.0", mac: "9a254a554cc6", firmware: 150))
    }

    @Test func aDeviceReplyWithoutModelOrMacStillCounts() throws {
        let reply = #"{"id":7,"result":{"ble_mac":"","ip":"192.168.68.50"}}"#
        #expect(try MarstekProtocol.device(Data(reply.utf8)) == DeviceInfo(model: "Marstek", mac: nil))
    }

    @Test func aDeviceReplyWithoutAResultIsBad() {
        #expect(throws: DeviceError.badReply("Reply has no result")) {
            try MarstekProtocol.device(Data(#"{"id":7,"src":"x"}"#.utf8))
        }
    }
}
