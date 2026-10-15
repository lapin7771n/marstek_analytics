# Find the battery from the settings screen

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a tester taps "Find battery", picks the battery in a sheet and taps "Use this battery". The IP fills and the app checks it.

**Approved exception:** the app may send `Marstek.GetDevice`, only when the user taps "Find battery", never on a timer. Every other request stays `ES.GetStatus`.

**Design:** artboard "Find the battery" (`project/Discovery.dc.html`) on the [Battery ETA canvas](https://claude.ai/artifact/1ZfUnFUKedswkhYC5dc9wL). The canvas is read-only for this work; deviations are listed under Owner decisions.

## Facts

- **Broadcast needs an entitlement Apple must grant.** On iOS, sending or receiving a UDP broadcast or multicast needs `com.apple.developer.networking.multicast`; sending UDP unicast does not. Both need the Local Network permission the app already asks for ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), "Multicast operations"). Apple grants it per team through a [request form](https://developer.apple.com/contact/request/networking-multicast); forum reports put the wait at days. Testers need a fix today, so this plan does not use broadcast.
- **A unicast sweep needs nothing new.** Sending to each address of the subnet is ordinary unicast. Apple prefers Bonjour, which the battery does not offer.
- **Do not assume `en0`.** TN3179 says the Wi‑Fi interface name is not API. The app sweeps every IPv4 interface that is up, broadcast-capable and not loopback.
- **Before the user answers the Local Network alert,** iOS may deny the operation at once. `NWConnection` then waits with `localNetworkDenied`, which `MarstekClient` already maps to `DeviceError.blocked`.
- **Request.** `{"id":N,"method":"Marstek.GetDevice","params":{"ble_mac":"0"}}`; `"0"` asks every device ([taurgis query_device.py](https://github.com/taurgis/has-marstek-local-api/blob/main/tools/query_device.py), [API notes](https://github.com/taurgis/has-marstek-local-api/blob/main/docs/marstek_device_openapi.MD) §3.1.1). The Home Assistant integration sends it by unicast to a stored IP during setup, so firmwares it supports answer unicast.
- **Reply from this battery** (V150, unicast, 2026-10-15), pretty-printed with tabs: `{"id":7,"src":"VenusE 3.0-bc2a3314ce8d","result":{"device":"VenusE 3.0","ver":150,"ble_mac":"bc2a3314ce8d","wifi_mac":"9a254a554cc6","wifi_name":"…","ip":"192.168.68.50"}}`. Other firmware sends `device` as `VenusE`, `VenusC` or a SKU like `VNSE3-0`, and some omits the MAC fields. The app reads `device` and `wifi_mac` (else `ble_mac`), and uses the address that answered as the IP.
- **What is known about `Marstek.GetDevice` safety: little.** No report ties it to a reset or a power cut. The Home Assistant integration repeats it in a background scanner, and its reset reports point at `Bat.GetStatus` and at firmware 144–148, without proof ([issue #14](https://github.com/taurgis/has-marstek-local-api/issues/14)). Its maintainer writes that the API "does not handle high request volumes well". On Venus E 3.0 the Local API has switched itself off on Control 147, and one owner reports a reboot loop on 150.9 with no named cause ([issue #15](https://github.com/taurgis/has-marstek-local-api/issues/15)). No one has measured `GetDevice` under load, so the app sends it as rarely as the rules below allow.
- **This battery answers unicast only.** A unicast `Marstek.GetDevice` to `192.168.68.50` got the reply above; the same request to the broadcast address `192.168.71.255` got none within 3 s. That explains the "no reply" in `plans/2026-10-12-streamdeck-battery-eta.md`, and broadcast would fail even with the entitlement.
- **The home network is `192.168.68.0/22`** (this Mac: `192.168.68.56`, mask `255.255.252.0`, TP-Link Deco default). A /24 sweep would miss `192.168.69.x`–`192.168.71.x`.

## Rules for gentle discovery

Each rule has a test in `ios/Tests/DiscoveryTests.swift` that fails if the rule is broken.

| # | Rule | Test |
|---|---|---|
| 1 | Each address gets at most one `Marstek.GetDevice` per search, including addresses that already answered. No retry, no second pass. | `oneSearchProbesEachAddressOnce`, `theProbeSendsOneGetDeviceAndNeverRetries` |
| 2 | A search holds `BatteryLine`, the app's one-request-to-the-battery lock. The 30 s `ES.GetStatus` poll skips while a search holds it; a search waits for a poll already in flight. Widgets skip their fetch while `searchUntil` is set, and a search waits 5 s after taking the line so a widget fetch already in flight finishes. A search stopped while it waits for the line never takes it and clears `searchUntil`. | `theLineRefusesASecondClaim`, `aSearchHoldsTheLineUntilItEnds`, `aSearchWaitsForAPollInFlight`, `aSearchStoppedWhileWaitingForTheLineSendsNothing`, `aSearchPausesTheWidgets`, `StoreTests.aSearchSkipsTheFetch`, `StoreTests.anExpiredSearchFetches` |
| 3 | 32 addresses in flight at most, 1 s timeout each. Closing the sheet, picking a battery or sending the app to the background stops the search: no new address is probed after that, including probes already queued in the sweep. | `probesStayWithinTheWidth`, `stopProbesNoNewAddress`, `aSearchStoppedWhileWaitingForTheLineSendsNothing` |
| 4 | A tap while a search runs does nothing. A new search starts at most once per 30 s; an earlier tap reopens the sheet with the last results. A search blocked by Local Network sent nothing, so the next tap searches at once. | `aSecondTapDuringASearchSendsNothing`, `oneSearchPer30Seconds`, `aTapAfterAllowingLocalNetworkSearchesAgain` |
| 5 | Only a tap starts a search: never on launch, on a timer, from a widget or in the background. | No runtime test can prove an absence. `BatteryFinder` gets its probe only in `start(_:)`, the button action is its one caller, and the code lives in `ios/App/`, which the widget target does not compile. Review checks all three. |

## Design

- **Sweep, no broadcast.** On tap, the app reads the address and netmask of each up, broadcast-capable IPv4 interface and sends one `Marstek.GetDevice` by unicast to every other address in the subnet. Addresses in the phone's own /24 go first, so `192.168.68.50` answers within about 8 s.
- **Subnet cap /22.** A mask wider than /22 is narrowed to the /22 around the phone's address. A full /22 takes up to 32 s, a /24 up to 8 s.
- **Sheet.** The tap opens "Batteries on this Wi‑Fi". Batteries appear as they answer, as `model`, then `IP · …:A4:1C`. The first one is checked; a tap checks another. "Use this battery" stops the search, fills the IP and runs "Save and check".
- **Permission.** A probe that fails with `localNetworkDenied` stops the search, and the sheet says to allow Local Network and tap again.
- **Widget pause.** A search writes `searchUntil = now + 70 s` to the App Group and clears it when it ends. While it is set and in the future, `Refresher.refresh` returns the stored snapshot without a fetch. After taking the line, the search waits 5 s before the first probe, so a widget fetch already in flight (2 s timeout, 1 s gap, 2 s retry) finishes and never meets the sweep at the battery. Each search takes 5 s longer: up to 13 s for a /24, 37 s for a /22. The 70 s expiry frees the widgets if the app dies mid-search.
- **Merge footprint.** New files: `App/Discovery.swift`, `App/FindBattery.swift`. `BatteryApp.swift` gains the row and routes `refresh()` through `BatteryLine`. `Store.swift` gains `searchUntil` and one line in `Refresher.refresh`. `project.yml` does not change.

## Global constraints

- The rules above hold. The 30 s poll still sends only `ES.GetStatus`.
- From `ios/`, `make test` exits 0 after every task. Every new string has Ukrainian in `ios/Shared/Localizable.xcstrings`.
- Branch `claude/ios-battery-discovery-91b6ae`. Conventional Commits, one subject line, no co-author trailer, no push.

## Owner decisions

Decided 15.10: step 0.1 sent; `ES.GetStatus` fallback not needed because the battery answers `GetDevice` by unicast; widgets pause during a search; the artboard deviations below are accepted.

- The artboard footer goes inside the "Find battery" row as a second line, because the section footer already shows the reserve hint and validation errors.
- The sheet adds a "Searching…" row while the search runs, "No battery found." when it ends empty, and the Wi‑Fi or Local Network message when it cannot run.
- The model reads as the firmware sends it (`VenusE 3.0`), not `Venus E 3.0`.
- The MAC tail is omitted when the reply has no MAC.
- The close button is the SF Symbol `xmark.circle.fill`; the row icon is `magnifyingglass`.

Time: about 3 hours to build, plus 10 minutes on the iPhone.

---

## Task 0: Check GetDevice on the real battery

- [x] **0.1** From this Mac on the home Wi‑Fi, send one request and wait 3 s for a reply:

```bash
python3 -I -c 'import socket,sys;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1);s.settimeout(3);s.sendto(b"{\"id\":7,\"method\":\"Marstek.GetDevice\",\"params\":{\"ble_mac\":\"0\"}}",(sys.argv[1],30000));print(s.recvfrom(2048))' 192.168.68.50
```

Then, 10 s later, the same with `192.168.71.255`. Expected: a JSON reply with `result.device`. Record both outcomes and the verbatim reply in Facts.
- [x] **0.2** If neither address answers, stop and ask the owner. (Unicast answered.)

## Task 1: GetDevice request and reply

**Files**
- Modify: `ios/Shared/MarstekProtocol.swift`
- Test: `ios/Tests/ProtocolTests.swift`

- [x] **1.1 Tests first.** Next to `esReply` in `ios/Tests/ProtocolTests.swift`, add the reply from step 0.1, tabs and newlines kept, with the Wi‑Fi name replaced by `Home`:

```swift
let deviceReply = "{\n\t\"id\":\t7,\n\t\"src\":\t\"VenusE 3.0-bc2a3314ce8d\",\n\t\"result\":\t{\n\t\t\"device\":\t\"VenusE 3.0\",\n\t\t\"ver\":\t150,\n\t\t\"ble_mac\":\t\"bc2a3314ce8d\",\n\t\t\"wifi_mac\":\t\"9a254a554cc6\",\n\t\t\"wifi_name\":\t\"Home\",\n\t\t\"ip\":\t\"192.168.68.50\"\n\t}\n}"
```

Append to `ProtocolTests`:

```swift
    @Test func deviceRequestAsksEveryDevice() {
        let text = String(decoding: MarstekProtocol.deviceRequest(id: 7), as: UTF8.self)
        #expect(text == #"{"id":7,"method":"Marstek.GetDevice","params":{"ble_mac":"0"}}"#)
    }

    @Test func parsesTheDeviceReply() throws {
        #expect(try MarstekProtocol.device(Data(deviceReply.utf8)) == DeviceInfo(model: "VenusE 3.0", mac: "9a254a554cc6"))
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
```

Run `make test`. Expected: the build fails because `deviceRequest`, `device` and `DeviceInfo` do not exist.

- [x] **1.2 Protocol.** In `ios/Shared/MarstekProtocol.swift`, add after `EsStatus`:

```swift
struct DeviceInfo: Equatable, Sendable {
    let model: String
    let mac: String?
}
```

Add to `MarstekProtocol`:

```swift
    static func deviceRequest(id: Int) -> Data {
        Data(#"{"id":\#(id),"method":"Marstek.GetDevice","params":{"ble_mac":"0"}}"#.utf8)
    }

    static func device(_ data: Data) throws -> DeviceInfo {
        let result = try decode(DeviceResult.self, data)
        let mac = [result.wifiMac, result.bleMac].compactMap { $0 }.first { !$0.isEmpty }
        return DeviceInfo(model: result.device ?? "Marstek", mac: mac)
    }
```

Add at the bottom:

```swift
private struct DeviceResult: Decodable {
    let device: String?
    let wifiMac: String?
    let bleMac: String?

    enum CodingKeys: String, CodingKey {
        case device
        case wifiMac = "wifi_mac"
        case bleMac = "ble_mac"
    }
}
```

Run `make test`. Expected: pass.

- [x] **1.3 Commit.** `git add ios && git commit -m "feat: parse marstek getdevice replies"`

## Task 2: Subnet, sweep, line and finder

**Files**
- Create: `ios/App/Discovery.swift`
- Modify: `ios/Shared/MarstekClient.swift`
- Test: create `ios/Tests/SubnetTests.swift`, `ios/Tests/DiscoveryTests.swift`

- [x] **2.1 Subnet tests.** Create `ios/Tests/SubnetTests.swift`:

```swift
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
    }
}
```

- [x] **2.2 Discovery tests.** Create `ios/Tests/DiscoveryTests.swift`:

```swift
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
        BatteryFinder(store: store, line: line, hosts: { hosts }, now: { clock.now }, settle: .zero)
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

    @Test func aTapAfterAllowingLocalNetworkSearchesAgain() async {
        let probes = Probes()
        let finder = finder()
        finder.start { _ in throw DeviceError.blocked }
        await finder.wait()
        finder.start(probe(probes))
        await finder.wait()
        #expect(await probes.hosts.count == hosts.count)
    }

    @Test func aSecondTapDuringASearchSendsNothing() async {
        let probes = Probes()
        let clock = Clock()
        let finder = finder(clock)
        finder.start(probe(probes, delay: .milliseconds(20)))
        clock.now += 31
        finder.start(probe(probes, delay: .milliseconds(20)))
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

    @Test func aSearchStoppedWhileWaitingForTheLineSendsNothing() async throws {
        let line = BatteryLine()
        let store = testStore()
        let probes = Probes()
        #expect(await line.claim())
        let finder = finder(line: line, store: store)
        finder.start(probe(probes))
        try await Task.sleep(for: .milliseconds(50))
        finder.stop()
        await line.release()
        await finder.wait()
        #expect(await probes.hosts.isEmpty)
        #expect(store.searchUntil == nil)
        #expect(!finder.searching)
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
```

Run `make test`. Expected: the build fails because `Subnet`, `FoundBattery`, `Probe`, `Discovery`, `BatteryLine`, `BatteryFinder` and `MarstekClient.device()` do not exist.

- [x] **2.3 Client.** In `ios/Shared/MarstekClient.swift`, add after `reading(at:)`. It calls `exchange` once, so a silent address costs one datagram:

```swift
    func device() async throws -> DeviceInfo {
        let id = MarstekProtocol.newId()
        return try MarstekProtocol.device(await exchange(MarstekProtocol.deviceRequest(id: id), id: id))
    }
```

- [x] **2.4 Discovery.** Create `ios/App/Discovery.swift`:

```swift
import Darwin
import Foundation
import Observation

struct Subnet {
    let address: UInt32
    let mask: UInt32

    var hosts: [String] {
        let mask = mask | 0xFFFF_FC00
        let network = address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        let all = (network + 1..<broadcast).filter { $0 != address }
        let near = all.filter { $0 >> 8 == address >> 8 }
        let far = all.filter { $0 >> 8 != address >> 8 }
        return (near + far).map(Subnet.format)
    }

    static func local() -> [Subnet] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        return sequence(first: first, next: { $0.pointee.ifa_next }).compactMap { entry in
            let item = entry.pointee
            let flags = Int32(item.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let addr = item.ifa_addr, let mask = item.ifa_netmask, addr.pointee.sa_family == UInt8(AF_INET) else { return nil }
            return Subnet(address: ipv4(addr), mask: ipv4(mask))
        }
    }

    static func localHosts() -> [String] {
        var seen = Set<String>()
        return local().flatMap(\.hosts).filter { seen.insert($0).inserted }
    }

    static func parse(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return parts.reduce(0) { $0 << 8 | $1 }
    }

    static func format(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String(value >> $0 & 255) }.joined(separator: ".")
    }

    private static func ipv4(_ pointer: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
    }
}

struct FoundBattery: Equatable, Identifiable, Sendable {
    let host: String
    let model: String
    let mac: String?
    var id: String { host }

    var macTail: String? {
        guard let hex = mac?.filter(\.isHexDigit).uppercased(), hex.count >= 4 else { return nil }
        return "…:\(hex.suffix(4).prefix(2)):\(hex.suffix(2))"
    }
}

typealias Probe = @Sendable (String) async throws -> DeviceInfo?

// One request to the battery at a time from this process: the poll and a search share it.
actor BatteryLine {
    static let shared = BatteryLine()
    private var busy = false

    func claim() -> Bool {
        if busy { return false }
        busy = true
        return true
    }

    func take() async throws {
        while !claim() { try await Task.sleep(for: .milliseconds(100)) }
    }

    func release() {
        busy = false
    }
}

enum Discovery {
    static func sweep(
        _ hosts: [String],
        width: Int = 32,
        probe: @escaping Probe,
        found: @escaping @Sendable (FoundBattery) async -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: FoundBattery?.self) { group in
            var pending = hosts.makeIterator()
            func next() {
                guard !Task.isCancelled, let host = pending.next() else { return }
                group.addTask {
                    if Task.isCancelled { return nil }
                    do { return try await probe(host).map { FoundBattery(host: host, model: $0.model, mac: $0.mac) } }
                    catch DeviceError.blocked { throw DeviceError.blocked }
                    catch { return nil }
                }
            }
            for _ in 0..<width { next() }
            while let battery = try await group.next() {
                if let battery { await found(battery) }
                next()
            }
        }
    }

    static func live(port: Int) -> Probe {
        let port = UInt16(exactly: port) ?? 30000
        return { host in try await MarstekClient(host: host, port: port, timeout: 1).device() }
    }
}

@MainActor @Observable
final class BatteryFinder {
    enum Outcome { case noWifi, blocked }

    private(set) var searching = false
    private(set) var found: [FoundBattery] = []
    private(set) var outcome: Outcome?
    private(set) var stopped = false
    private var startedAt: Date?
    private var task: Task<Void, Never>?
    private let store: Store
    private let line: BatteryLine
    private let hosts: () -> [String]
    private let now: () -> Date
    private let settle: Duration

    init(
        store: Store = Store(),
        line: BatteryLine = .shared,
        hosts: @escaping () -> [String] = Subnet.localHosts,
        now: @escaping () -> Date = { .now },
        settle: Duration = .seconds(5)
    ) {
        self.store = store
        self.line = line
        self.hosts = hosts
        self.now = now
        self.settle = settle
    }

    func start(_ probe: @escaping Probe) {
        if searching { return }
        if let startedAt, now().timeIntervalSince(startedAt) < 30 { return }
        let hosts = hosts()
        found = []
        outcome = nil
        guard !hosts.isEmpty else { outcome = .noWifi; return }
        startedAt = now()
        searching = true
        stopped = false
        task = Task {
            store.searchUntil = Date.now + 70
            do {
                try await line.take()
            } catch {
                store.searchUntil = nil
                searching = false
                return
            }
            do {
                try await Task.sleep(for: settle)
                try await Discovery.sweep(hosts, probe: probe) { battery in await self.add(battery) }
            } catch is CancellationError {
            } catch {
                outcome = .blocked
                startedAt = nil
            }
            store.searchUntil = nil
            await line.release()
            searching = false
        }
    }

    func stop() {
        if searching { stopped = true }
        task?.cancel()
    }

    func wait() async {
        await task?.value
    }

    private func add(_ battery: FoundBattery) {
        found.append(battery)
        found.sort { Subnet.parse($0.host) ?? 0 < Subnet.parse($1.host) ?? 0 }
    }
}
```

Run `make test`. Expected: pass.

- [x] **2.5 Widget pause.** Append to `ios/Tests/StoreTests.swift`:

```swift
    @Test func aSearchSkipsTheFetch() async {
        let store = store()
        let now = Date(timeIntervalSince1970: 1000)
        store.searchUntil = now + 30
        let snapshot = await Refresher.refresh(store, now: now, maxAge: Refresher.widgetMaxAge) { _ in
            Issue.record("fetched during a search")
            return reading(acW: 400)
        }
        #expect(snapshot.reading == nil && snapshot.error == nil)
        #expect(store.snapshot == nil)
    }

    @Test func anExpiredSearchFetches() async {
        let store = store()
        let good = reading(acW: 400)
        store.searchUntil = good.time - 1
        let snapshot = await Refresher.refresh(store, now: good.time) { _ in good }
        #expect(snapshot.reading == good)
    }
```

In `ios/Shared/Store.swift`, add to `Store` after `snapshot`:

```swift
    var searchUntil: Date? {
        get { load("searchUntil") }
        set { save(newValue, "searchUntil") }
    }
```

and make this the first statement of `Refresher.refresh`:

```swift
        if let until = store.searchUntil, now < until {
            return store.snapshot ?? Snapshot(reading: nil, error: nil, checkedAt: now)
        }
```

Run `make test`. Expected: pass.

- [x] **2.6 Commit.** `git add ios && git commit -m "feat: sweep the wi-fi subnet for marstek batteries"`

## Task 3: Find battery row and sheet

**Files**
- Create: `ios/App/FindBattery.swift`
- Modify: `ios/App/BatteryApp.swift`, `ios/Shared/Localizable.xcstrings`, `CLAUDE.md`
- Test: `ios/Tests/LocalizationTests.swift`

- [x] **3.1 Test first.** In `LocalizationTests.theAppShipsUkrainian`, add:

```swift
        #expect(uk.localizedString(forKey: "Find battery", value: nil, table: nil) == "Знайти батарею")
```

and raise `strings.count >= 38` to `>= 48`. Run `make test`. Expected: fail.

- [x] **3.2 Views.** Create `ios/App/FindBattery.swift`:

```swift
import SwiftUI

struct FindBatteryRow: View {
    let port: Int
    let use: (String) -> Void
    @State private var finder = BatteryFinder()
    @State private var showing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button {
            finder.start(Discovery.live(port: port))
            showing = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("Find battery", systemImage: "magnifyingglass").foregroundStyle(Palette.good)
                Text("Looks for Marstek batteries on this Wi‑Fi. It asks each battery once, only when you tap.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showing, onDismiss: finder.stop) {
            FindBatterySheet(finder: finder) { host in
                showing = false
                use(host)
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { finder.stop() }
        }
    }
}

struct FindBatterySheet: View {
    let finder: BatteryFinder
    let use: (String) -> Void
    @State private var picked: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Batteries on this Wi‑Fi").font(.title3.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(finder.found) { battery in
                    Button { picked = battery.host } label: { row(battery) }.buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                }
                status.padding(16)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            Text("Not listed? Turn on Open API for the battery in the Marstek app, then search again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                finder.stop()
                if let chosen { use(chosen) }
            } label: {
                Text("Use this battery")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x08150F))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Palette.good.opacity(chosen == nil ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(chosen == nil)
        }
        .padding(16)
    }

    private var chosen: String? {
        picked ?? finder.found.first?.host
    }

    private func row(_ battery: FoundBattery) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: battery.model).font(.headline)
                Text(verbatim: [battery.host, battery.macTail].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if battery.host == chosen { Image(systemName: "checkmark").foregroundStyle(Palette.good) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var status: some View {
        if finder.searching {
            HStack(spacing: 8) { ProgressView(); Text("Searching…") }
        } else if finder.outcome == .noWifi {
            Text("Join the same Wi‑Fi as the battery, then tap Find battery.")
        } else if finder.outcome == .blocked {
            Text("Allow Local Network for Battery ETA, then tap Find battery again.")
        } else if finder.found.isEmpty && !finder.stopped {
            Text("No battery found.")
        }
    }
}
```

- [x] **3.3 Settings screen.** In `ios/App/BatteryApp.swift`:
  - After the IP `TextField` block (after `.accessibilityLabel("Battery IP address")`), add:

```swift
                    FindBatteryRow(port: settings.port) { host in
                        settings.host = host
                        Task { await save() }
                    }
```

  - Replace `refresh()` so the poll skips while a search holds the line and "Save and check" waits for it:

```swift
    private func refresh(waiting: Bool = false) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        if waiting {
            do { try await BatteryLine.shared.take() } catch { return }
        } else if await !BatteryLine.shared.claim() {
            return
        }
        snapshot = await Refresher.refresh(store)
        await BatteryLine.shared.release()
    }
```

  - In `save()`, change `await refresh()` to `await refresh(waiting: true)`.

- [x] **3.4 Strings.** Add to `ios/Shared/Localizable.xcstrings` with `"state": "translated"`. Check the Ukrainian with the `ukrainian-translation-review` skill before committing:

| en | uk |
|---|---|
| `Find battery` | `Знайти батарею` |
| `Looks for Marstek batteries on this Wi‑Fi. It asks each battery once, only when you tap.` | `Шукає батареї Marstek у цій мережі Wi‑Fi. Звертається до кожної один раз і лише після натискання.` |
| `Batteries on this Wi‑Fi` | `Батареї в цій мережі Wi‑Fi` |
| `Close` | `Закрити` |
| `Not listed? Turn on Open API for the battery in the Marstek app, then search again.` | `Немає в списку? Увімкніть Open API для батареї в застосунку Marstek і пошукайте ще раз.` |
| `Use this battery` | `Вибрати цю батарею` |
| `Searching…` | `Шукаю…` |
| `Join the same Wi‑Fi as the battery, then tap Find battery.` | `Підключіться до тієї ж мережі Wi‑Fi, що й батарея, і натисніть «Знайти батарею».` |
| `Allow Local Network for Battery ETA, then tap Find battery again.` | `Дозвольте Battery ETA доступ до локальної мережі й знову натисніть «Знайти батарею».` |
| `No battery found.` | `Батарею не знайдено.` |

- [x] **3.5 Constraint line.** In `CLAUDE.md`, replace "The iOS app sends only `ES.GetStatus`." with "The iOS app sends only `ES.GetStatus`, plus one `Marstek.GetDevice` per subnet address when the user taps Find battery, at most once per 30 s; never on a timer, on launch or from a widget."

- [x] **3.6 Gate.** `make test`. Expected: pass. Then build to the `iPhone 18 Pro` simulator and tap Find battery. The simulator shares the Mac's network, so on the home Wi‑Fi the sheet lists the battery at `192.168.68.50`.

- [x] **3.7 Commit.** `git add ios CLAUDE.md && git commit -m "feat: find the battery on the wi-fi from settings"`

## Task 4: Owner check on the iPhone (10 minutes)

- [ ] **4.1** `make upload BUILD=<next>`, install from TestFlight, clear the IP field, tap Find battery. Expected: the battery appears within 10 s; "Use this battery" fills `192.168.68.50` and "Now" shows a reading.
- [ ] **4.2** Watch the battery output for 10 minutes after the search. Expected: no cut.
