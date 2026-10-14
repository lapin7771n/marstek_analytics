import Foundation
import Testing
@testable import BatteryETA

struct ClientTests {
    private func client(_ fake: FakeBattery) -> MarstekClient {
        MarstekClient(host: "127.0.0.1", port: fake.port, timeout: 0.3, gap: .zero)
    }

    @Test func ignoresADatagramWithAnotherId() async throws {
        let fake = try await FakeBattery.start { request, _ in
            [#"{"id":\#(request.id + 100),"src":"stale"}"#, #"{"id":\#(request.id),"result":{"bat_soc":81}}"#]
        }
        defer { fake.stop() }
        let data = try await client(fake).call("ES.GetStatus")
        #expect(String(decoding: data, as: UTF8.self).contains("81"))
    }

    @Test func retriesOnceAfterATimeout() async throws {
        let fake = try await FakeBattery.start { request, attempt in
            attempt == 1 ? [] : [#"{"id":\#(request.id),"result":{"bat_soc":82}}"#]
        }
        defer { fake.stop() }
        let data = try await client(fake).call("ES.GetStatus")
        #expect(String(decoding: data, as: UTF8.self).contains("82"))
    }

    @Test func twoSilentAttemptsAreATimeout() async throws {
        let fake = try await FakeBattery.start { _, _ in [] }
        defer { fake.stop() }
        await #expect(throws: DeviceError.timeout) { try await client(fake).call("ES.GetStatus") }
    }

    @Test func aReadingAsksOnlyForEsStatus() async throws {
        var methods: [String] = []
        let fake = try await FakeBattery.start { request, _ in
            methods.append(request.method)
            return [#"{"id":\#(request.id),"result":{"bat_soc":80,"bat_cap":5120,"ongrid_power":-797,"offgrid_power":0}}"#]
        }
        defer { fake.stop() }
        let time = Date(timeIntervalSince1970: 0)
        let reading = try await client(fake).reading(at: time)
        #expect(reading == Reading(time: time, socPct: 80, acW: -797, offgridW: 0, capacityWh: 4096, ratedWh: 5120))
        #expect(methods == ["ES.GetStatus"])
    }
}
