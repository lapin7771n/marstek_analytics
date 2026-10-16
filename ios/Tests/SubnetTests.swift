import Testing
@testable import BatteryETA

struct SubnetTests {
    private func ip(_ text: String) -> UInt32 { Subnet.parse(text)! }

    @Test func aSlash24SkipsNetworkBroadcastAndSelf() {
        let hosts = Subnet(address: ip("192.168.1.20"), mask: ip("255.255.255.0")).hosts
        #expect(hosts.count == 253)
        #expect(hosts.first == "192.168.1.1" && hosts.last == "192.168.1.254")
        #expect(!hosts.contains("192.168.1.20"))
    }

    @Test func aSlash22CoversAllFourBlocksOwnBlockFirst() {
        let hosts = Subnet(address: ip("192.168.68.56"), mask: ip("255.255.252.0")).hosts
        #expect(hosts.count == 1021)
        #expect(hosts.prefix(254).allSatisfy { $0.hasPrefix("192.168.68.") })
        #expect(hosts[254] == "192.168.69.0" && hosts.last == "192.168.71.254")
    }

    @Test func aWiderMaskIsNarrowedToSlash22() {
        let hosts = Subnet(address: ip("10.0.5.9"), mask: ip("255.255.0.0")).hosts
        #expect(hosts.count == 1021 && hosts.allSatisfy { ["10.0.4.", "10.0.5.", "10.0.6.", "10.0.7."].contains(where: $0.hasPrefix) })
    }

    @Test func aPointToPointMaskHasNoHosts() {
        #expect(Subnet(address: ip("10.0.0.1"), mask: ip("255.255.255.255")).hosts.isEmpty)
    }

    @Test func theMacTailIsTheLastTwoBytes() {
        #expect(FoundBattery(host: "h", model: "m", mac: "bc2a3314a41c").macTail == "…:A4:1C")
        #expect(FoundBattery(host: "h", model: "m", mac: nil).macTail == nil)
        #expect(FoundBattery(host: "h", model: "m", mac: "bc2a3314a41c", firmware: 147).detail == "h · …:A4:1C · V147")
        #expect(FoundBattery(host: "h", model: "m", mac: nil).detail == "h")
    }

    @Test(arguments: [(135, "VenusE 3.0"), (147, "VenusE 3.0"), (149, "VenusE 3.0"), (153, "VenusE"), (155, "VenusE")])
    func oldFirmwareResetsUnderLoad(firmware: Int, model: String) {
        #expect(FoundBattery(host: "h", model: model, mac: nil, firmware: firmware).resetsUnderLoad)
    }

    @Test(arguments: [(150, "VenusE 3.0"), (151, "VenusE 3.0"), (153, "VenusE 3.0"), (156, "VenusE")])
    func newerFirmwareDoesNot(firmware: Int, model: String) {
        #expect(!FoundBattery(host: "h", model: model, mac: nil, firmware: firmware).resetsUnderLoad)
    }

    @Test func unknownFirmwareIsPolledAsUsual() {
        #expect(!FoundBattery(host: "h", model: "VenusE", mac: nil).resetsUnderLoad)
    }

    @Test(arguments: [(150, "VenusE 3.0"), (156, "VenusE")])
    func newerFirmwareTakesARetry(firmware: Int, model: String) {
        #expect(FoundBattery(host: "h", model: model, mac: nil, firmware: firmware).takesRetry)
    }

    @Test(arguments: [147, nil] as [Int?])
    func oldOrUnknownFirmwareTakesNoRetry(firmware: Int?) {
        #expect(!FoundBattery(host: "h", model: "VenusE", mac: nil, firmware: firmware).takesRetry)
    }
}
