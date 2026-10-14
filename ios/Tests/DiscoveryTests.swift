import Foundation
import Testing
@testable import BatteryETA

private actor Probes {
    var hosts: [String] = []
    var inFlight = 0
    var peak = 0

    func start(_ host: String) { hosts.append(host); inFlight += 1; peak = max(peak, inFlight) }
    func end() { inFlight -= 1 }
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 0)
}

private func testStore() -> Store {
    Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
}

@MainActor
struct DiscoveryTests {
    private let hosts = (1...200).map { "10.0.0.\($0)" }
    private let batteries: Set = ["10.0.0.9", "10.0.0.100"]

    private func probe(_ probes: Probes, delay: Duration = .milliseconds(2)) -> Probe {
        let batteries = batteries
        return { host in
            await probes.start(host)
            try? await Task.sleep(for: delay)
            await probes.end()
            return batteries.contains(host) ? DeviceInfo(model: "VenusE", mac: nil) : nil
        }
    }

    private func finder(_ clock: Clock = Clock(), line: BatteryLine = BatteryLine(), store: Store = testStore()) -> BatteryFinder {
        BatteryFinder(store: store, line: line, hosts: { hosts }, now: { clock.now })
    }

    @Test func oneSearchProbesEachAddressOnce() async {
        let probes = Probes()
        let finder = finder()
        finder.start(probe(probes))
        await finder.wait()
        #expect(await probes.hosts.sorted() == hosts.sorted())
        #expect(finder.found.map(\.host) == ["10.0.0.9", "10.0.0.100"])
    }

    @Test func probesStayWithinTheWidth() async {
        let probes = Probes()
        try? await Discovery.sweep(hosts, width: 8, probe: probe(probes)) { _ in }
        #expect(await probes.peak == 8)
    }

    @Test func aSilentHostIsNotAnError() async throws {
        try await Discovery.sweep(hosts, probe: { _ in throw DeviceError.timeout }) { _ in Issue.record("found") }
    }

    @Test func aDeniedPermissionStopsTheSearch() async {
        let finder = finder()
        finder.start { _ in throw DeviceError.blocked }
        await finder.wait()
        #expect(finder.outcome == .blocked)
    }

    @Test func aSecondTapDuringASearchSendsNothing() async {
        let probes = Probes()
        let finder = finder()
        finder.start(probe(probes))
        finder.start(probe(probes))
        await finder.wait()
        #expect(await probes.hosts.count == hosts.count)
    }

    @Test func oneSearchPer30Seconds() async {
        let probes = Probes()
        let clock = Clock()
        let finder = finder(clock)
        finder.start(probe(probes))
        await finder.wait()
        clock.now += 29
        finder.start(probe(probes))
        await finder.wait()
        #expect(await probes.hosts.count == hosts.count)
        clock.now += 2
        finder.start(probe(probes))
        await finder.wait()
        #expect(await probes.hosts.count == 2 * hosts.count)
    }

    @Test func stopProbesNoNewAddress() async throws {
        let probes = Probes()
        let finder = finder()
        finder.start(probe(probes, delay: .milliseconds(20)))
        try await Task.sleep(for: .milliseconds(50))
        finder.stop()
        let started = await probes.hosts.count
        await finder.wait()
        #expect(await probes.hosts.count == started)
        #expect(started < hosts.count)
    }

    @Test func theLineRefusesASecondClaim() async {
        let line = BatteryLine()
        #expect(await line.claim())
        #expect(await !line.claim())
        await line.release()
        #expect(await line.claim())
    }

    @Test func aSearchHoldsTheLineUntilItEnds() async {
        let line = BatteryLine()
        let finder = finder(line: line)
        let pollGotIn = Probes()
        finder.start { host in
            if await line.claim() { await pollGotIn.start(host) }
            return nil
        }
        await finder.wait()
        #expect(await pollGotIn.hosts.isEmpty)
        #expect(await line.claim())
    }

    @Test func aSearchWaitsForAPollInFlight() async throws {
        let line = BatteryLine()
        let probes = Probes()
        #expect(await line.claim())
        let finder = finder(line: line)
        finder.start(probe(probes))
        try await Task.sleep(for: .milliseconds(150))
        #expect(await probes.hosts.isEmpty)
        await line.release()
        await finder.wait()
        #expect(await probes.hosts.count == hosts.count)
    }

    @Test func aSearchPausesTheWidgets() async {
        let store = testStore()
        let finder = finder(store: store)
        let paused = Probes()
        finder.start { host in
            if let until = await MainActor.run(body: { store.searchUntil }), until > .now { await paused.start(host) }
            return nil
        }
        await finder.wait()
        #expect(await paused.hosts.count == hosts.count)
        #expect(store.searchUntil == nil)
    }

    @Test func theProbeSendsOneGetDeviceAndNeverRetries() async throws {
        var methods: [String] = []
        let fake = try await FakeBattery.start { request, _ in
            methods.append(request.method)
            return []
        }
        defer { fake.stop() }
        await #expect(throws: DeviceError.timeout) {
            try await MarstekClient(host: "127.0.0.1", port: fake.port, timeout: 0.3).device()
        }
        #expect(methods == ["Marstek.GetDevice"])
    }

    @Test func theProbeReadsTheModel() async throws {
        let fake = try await FakeBattery.start { request, _ in
            [deviceReply.replacingOccurrences(of: "\"id\":\t7", with: "\"id\":\(request.id)")]
        }
        defer { fake.stop() }
        let info = try await MarstekClient(host: "127.0.0.1", port: fake.port, timeout: 0.3).device()
        #expect(info.model == "VenusE 3.0")
    }
}
