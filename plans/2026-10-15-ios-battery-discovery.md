# Find the battery from the settings screen

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a tester taps "Find battery" on the settings screen and the IP fills itself. With several batteries the tester picks one.

**Approved exception:** the app may send `Marstek.GetDevice`, only when the user taps "Find battery", never on a timer. Every other request stays `ES.GetStatus`.

## Facts

- **Broadcast needs an entitlement Apple must grant.** On iOS, sending or receiving a UDP broadcast or multicast needs `com.apple.developer.networking.multicast`; sending UDP unicast does not. Both need the Local Network permission the app already asks for ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), "Multicast operations"). Apple grants it per team through a [request form](https://developer.apple.com/contact/request/networking-multicast); forum reports put the wait at days. Testers need a fix today, so this plan does not use broadcast.
- **A unicast sweep needs nothing new.** Sending to each address of the subnet is ordinary unicast. Apple prefers Bonjour, which the battery does not offer.
- **Do not assume `en0`.** TN3179 says the Wi‑Fi interface name is not API. The app sweeps every IPv4 interface that is up, broadcast-capable and not loopback.
- **Before the user answers the Local Network alert,** iOS may deny the operation at once. `NWConnection` then waits with `localNetworkDenied`, which `MarstekClient` already maps to `DeviceError.blocked`.
- **Request.** `{"id":N,"method":"Marstek.GetDevice","params":{"ble_mac":"0"}}`; `"0"` asks every device ([taurgis query_device.py](https://github.com/taurgis/has-marstek-local-api/blob/main/tools/query_device.py), [API notes](https://github.com/taurgis/has-marstek-local-api/blob/main/docs/marstek_device_openapi.MD) §3.1.1). The Home Assistant integration sends it by unicast to a stored IP during setup, so firmwares it supports answer unicast.
- **Reply.** `{"id":N,"src":"…","result":{"device":…,"ver":…,"ble_mac":…,"wifi_mac":…,"wifi_name":…,"ip":…}}`. `device` may be `VenusE`, `VenusC` or a SKU like `VNSE3-0`; some firmware omits the MAC fields. The vendor PDF's JSON samples are malformed, so no verbatim reply from a Venus E 3.0 exists yet. The app reads only `device` and uses the address that answered as the IP.
- **Open risk.** `plans/2026-10-12-streamdeck-battery-eta.md` records that `Marstek.GetDevice` got no reply from this battery (firmware V150) and does not say whether it went out by broadcast or unicast. Task 0 settles it before any code.
- **The home network is `192.168.68.0/22`** (this Mac: `192.168.68.56`, mask `255.255.252.0`, TP-Link Deco default). A /24 sweep would miss `192.168.69.x`–`192.168.71.x`.

## Design

- **Sweep, no broadcast.** On tap, the app reads the address and netmask of each up, broadcast-capable IPv4 interface and sends one `Marstek.GetDevice` by unicast to every other address in the subnet. Each address gets one datagram, no retry. 64 addresses are in flight at a time, each waits 1 s.
- **Subnet cap /22.** A mask wider than /22 is narrowed to the /22 around the phone's address. A /22 takes about 16 s, a /24 about 4 s.
- **Result.** The address that answered is the battery IP; the reply's `ip` field is ignored. One battery: the app fills the IP and runs "Save and check". Several: a dialog lists `model · IP` and the tap fills and saves. None: a note under the button says what to check.
- **Permission.** A probe that fails with `localNetworkDenied` stops the sweep and the row says to allow Local Network and tap again.
- **Merge footprint.** The UI lives in a new `App/FindBattery.swift`. `BatteryApp.swift` gains one view call. `Store.swift` and `project.yml` do not change.

## Global constraints

- The battery receives one `Marstek.GetDevice` per tap and nothing else from the sweep. No timer, no launch-time discovery, no retry.
- The 30 s poll still sends only `ES.GetStatus`.
- From `ios/`, `make test` exits 0 after every task. Every new string has Ukrainian in `ios/Shared/Localizable.xcstrings`.
- Branch `claude/ios-battery-discovery-91b6ae`. Conventional Commits, one subject line, no co-author trailer, no push.

## Review focus

1. Revert `MarstekProtocol.device` or `deviceRequest`: `ProtocolTests` fail.
2. Revert the subnet cap or the self/network/broadcast exclusion: `SubnetTests` fail.
3. Add a retry to the probe, or let more probes than `width` run at once: `DiscoveryTests` fail.
4. A denied permission stops the sweep instead of reporting "no battery".

Time: about 2 hours to build, plus 10 minutes on the iPhone.

## Owner decisions

1. **May I send `Marstek.GetDevice` from this Mac in step 0.1?** One unicast datagram to `192.168.68.50:30000`, then one to the subnet broadcast `192.168.71.255`. It settles the open risk and gives the real reply fixture.
2. **If the battery stays silent on both,** should the sweep probe with `ES.GetStatus` instead? It is already allowed, the battery answers it, and its `src` (`VenusE 3.0-bc2a3314ce8d`) names the model. The design stays the same; only the request and parser change.
3. **One battery found:** the plan fills the IP and runs "Save and check" at once. The alternative is to fill only and let the tester tap Save.

---

## Task 0: Check GetDevice on the real battery (5 minutes, needs decision 1)

- [ ] **0.1** From this Mac on the home Wi‑Fi, send one request and wait 3 s for replies:

```bash
python3 -I -c 'import socket,sys;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1);s.settimeout(3);s.sendto(b"{\"id\":7,\"method\":\"Marstek.GetDevice\",\"params\":{\"ble_mac\":\"0\"}}",(sys.argv[1],30000));print(s.recvfrom(2048))' 192.168.68.50
```

Then, 10 s later, the same with `192.168.71.255`. Expected: a JSON reply with `result.device`. Record both outcomes and the verbatim reply in the Facts section.
- [ ] **0.2** If neither address answers, stop and ask the owner about decision 2.

## Task 1: GetDevice request and reply

**Files**
- Modify: `ios/Shared/MarstekProtocol.swift`
- Test: `ios/Tests/ProtocolTests.swift`

- [ ] **1.1 Tests first.** Append to `ProtocolTests`:

```swift
    @Test func deviceRequestAsksEveryDevice() {
        let text = String(decoding: MarstekProtocol.deviceRequest(id: 7), as: UTF8.self)
        #expect(text == #"{"id":7,"method":"Marstek.GetDevice","params":{"ble_mac":"0"}}"#)
    }

    @Test func parsesTheDeviceReply() throws {
        #expect(try MarstekProtocol.device(Data(deviceReply.utf8)) == "VenusE 3.0")
    }

    @Test func aDeviceReplyWithoutAModelStillCounts() throws {
        #expect(try MarstekProtocol.device(Data(#"{"id":7,"result":{"ip":"192.168.68.50"}}"#.utf8)) == "Marstek")
    }

    @Test func aDeviceReplyWithoutAResultIsBad() {
        #expect(throws: DeviceError.badReply("Reply has no result")) {
            try MarstekProtocol.device(Data(#"{"id":7,"src":"x"}"#.utf8))
        }
    }
```

and next to `esReply`:

```swift
let deviceReply = #"{"id":7,"src":"VenusE 3.0-bc2a3314ce8d","result":{"device":"VenusE 3.0","ver":150,"ble_mac":"bc2a3314ce8d","wifi_mac":"bc2a3314ce8d","wifi_name":"Deco","ip":"192.168.68.50"}}"#
```

Replace this line with the verbatim reply from step 0.1 and adjust the expected model in `parsesTheDeviceReply`. Keep `"id":7`.

Run `make test`. Expected: the build fails because `deviceRequest` and `device` do not exist.

- [ ] **1.2 Protocol.** In `ios/Shared/MarstekProtocol.swift`, add to `MarstekProtocol`:

```swift
    static func deviceRequest(id: Int) -> Data {
        Data(#"{"id":\#(id),"method":"Marstek.GetDevice","params":{"ble_mac":"0"}}"#.utf8)
    }

    static func device(_ data: Data) throws -> String {
        try decode(DeviceResult.self, data).device ?? "Marstek"
    }
```

and at the bottom:

```swift
private struct DeviceResult: Decodable {
    let device: String?
}
```

Run `make test`. Expected: pass.

- [ ] **1.3 Commit.** `git add ios && git commit -m "feat: parse marstek getdevice replies"`

## Task 2: Subnet and sweep

**Files**
- Create: `ios/App/Discovery.swift`
- Modify: `ios/Shared/MarstekClient.swift`
- Test: create `ios/Tests/SubnetTests.swift`, `ios/Tests/DiscoveryTests.swift`

- [ ] **2.1 Tests first.** Create `ios/Tests/SubnetTests.swift`:

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

    @Test func aSlash22CoversAllFourBlocks() {
        let hosts = Subnet(address: ip("192.168.68.56"), mask: ip("255.255.252.0")).hosts
        #expect(hosts.count == 1021)
        #expect(hosts.first == "192.168.68.1" && hosts.last == "192.168.71.254")
        #expect(hosts.contains("192.168.69.0") && hosts.contains("192.168.68.255"))
    }

    @Test func aWiderMaskIsNarrowedToSlash22() {
        let hosts = Subnet(address: ip("10.0.5.9"), mask: ip("255.255.0.0")).hosts
        #expect(hosts.first == "10.0.4.1" && hosts.last == "10.0.7.254")
    }

    @Test func aPointToPointMaskHasNoHosts() {
        #expect(Subnet(address: ip("10.0.0.1"), mask: ip("255.255.255.255")).hosts.isEmpty)
    }
}
```

Create `ios/Tests/DiscoveryTests.swift`:

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

struct DiscoveryTests {
    private let hosts = (1...200).map { "10.0.0.\($0)" }

    @Test func probesEachHostOnceWithinTheWidth() async throws {
        let probes = Probes()
        let found = try await Discovery.sweep(hosts, width: 8) { host in
            await probes.start(host)
            try await Task.sleep(for: .milliseconds(2))
            await probes.end()
            return host == "10.0.0.50" ? "VenusE 3.0" : nil
        }
        #expect(found == [FoundBattery(host: "10.0.0.50", model: "VenusE 3.0")])
        #expect(await probes.hosts.sorted() == hosts.sorted())
        #expect(await probes.peak == 8)
    }

    @Test func severalBatteriesComeBackInAddressOrder() async throws {
        let found = try await Discovery.sweep(hosts, width: 64) { host in
            ["10.0.0.100", "10.0.0.9"].contains(host) ? "VenusE" : nil
        }
        #expect(found.map(\.host) == ["10.0.0.9", "10.0.0.100"])
    }

    @Test func aSilentHostIsNotAnError() async throws {
        let found = try await Discovery.sweep(hosts, width: 64) { _ in throw DeviceError.timeout }
        #expect(found.isEmpty)
    }

    @Test func aDeniedPermissionStopsTheSweep() async {
        await #expect(throws: DeviceError.blocked) {
            try await Discovery.sweep(hosts, width: 64) { _ in throw DeviceError.blocked }
        }
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
            [deviceReply.replacingOccurrences(of: #""id":7"#, with: #""id":\#(request.id)"#)]
        }
        defer { fake.stop() }
        #expect(try await MarstekClient(host: "127.0.0.1", port: fake.port, timeout: 0.3).device() == "VenusE 3.0")
    }
}
```

Run `make test`. Expected: the build fails because `Subnet`, `Discovery`, `FoundBattery` and `MarstekClient.device()` do not exist.

- [ ] **2.2 Client.** In `ios/Shared/MarstekClient.swift`, add after `reading(at:)`:

```swift
    func device() async throws -> String {
        let id = MarstekProtocol.newId()
        return try MarstekProtocol.device(await exchange(MarstekProtocol.deviceRequest(id: id), id: id))
    }
```

- [ ] **2.3 Discovery.** Create `ios/App/Discovery.swift`:

```swift
import Darwin
import Foundation

struct Subnet {
    let address: UInt32
    let mask: UInt32

    var hosts: [String] {
        let mask = mask | 0xFFFF_FC00
        let network = address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return (network + 1..<broadcast).filter { $0 != address }.map(Subnet.format)
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

struct FoundBattery: Equatable, Identifiable {
    let host: String
    let model: String
    var id: String { host }
}

enum Discovery {
    static func sweep(
        _ hosts: [String],
        width: Int = 64,
        probe: @escaping @Sendable (String) async throws -> String?
    ) async throws -> [FoundBattery] {
        try await withThrowingTaskGroup(of: FoundBattery?.self) { group in
            var pending = hosts.makeIterator()
            func next() {
                guard let host = pending.next() else { return }
                group.addTask {
                    do { return try await probe(host).map { FoundBattery(host: host, model: $0) } }
                    catch DeviceError.blocked { throw DeviceError.blocked }
                    catch { return nil }
                }
            }
            for _ in 0..<width { next() }
            var found: [FoundBattery] = []
            while let result = try await group.next() {
                if let result { found.append(result) }
                next()
            }
            return found.sorted { Subnet.parse($0.host) ?? 0 < Subnet.parse($1.host) ?? 0 }
        }
    }

    static func live(port: Int) -> @Sendable (String) async throws -> String? {
        let port = UInt16(exactly: port) ?? 30000
        return { host in try await MarstekClient(host: host, port: port, timeout: 1).device() }
    }
}
```

Run `make test`. Expected: pass.

- [ ] **2.4 Commit.** `git add ios && git commit -m "feat: sweep the wi-fi subnet for marstek batteries"`

## Task 3: Find battery button

**Files**
- Create: `ios/App/FindBattery.swift`
- Modify: `ios/App/BatteryApp.swift`, `ios/Shared/Localizable.xcstrings`, `CLAUDE.md`
- Test: `ios/Tests/LocalizationTests.swift`

- [ ] **3.1 Test first.** In `LocalizationTests.theAppShipsUkrainian`, add:

```swift
        #expect(uk.localizedString(forKey: "Find battery", value: nil, table: nil) == "Знайти батарею")
```

and raise `strings.count >= 38` to `>= 43`. Run `make test`. Expected: fail.

- [ ] **3.2 Row.** Create `ios/App/FindBattery.swift`:

```swift
import SwiftUI

struct FindBatteryRow: View {
    let port: Int
    let found: (String) -> Void
    @State private var searching = false
    @State private var choices: [FoundBattery] = []
    @State private var note: LocalizedStringKey?

    var body: some View {
        Button {
            Task { await find() }
        } label: {
            HStack {
                Label(searching ? "Searching…" : "Find battery", systemImage: "wifi")
                Spacer()
                if searching { ProgressView() }
            }
        }
        .disabled(searching)
        .confirmationDialog("Choose a battery", isPresented: choosing, titleVisibility: .visible) {
            ForEach(choices) { battery in
                Button("\(battery.model) · \(battery.host)") { found(battery.host) }
            }
        }
        if let note {
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var choosing: Binding<Bool> {
        Binding(get: { choices.count > 1 }, set: { if !$0 { choices = [] } })
    }

    private func find() async {
        note = nil
        let hosts = Array(Set(Subnet.local().flatMap(\.hosts)))
        guard !hosts.isEmpty else {
            note = "Join the battery's Wi‑Fi, then tap Find battery."
            return
        }
        searching = true
        defer { searching = false }
        do {
            let batteries = try await Discovery.sweep(hosts, probe: Discovery.live(port: port))
            if batteries.count == 1 { found(batteries[0].host) }
            if batteries.isEmpty { note = "No battery found. Turn on Open API for the battery in the Marstek app." }
            choices = batteries
        } catch {
            note = "Allow Local Network for Battery ETA, then tap Find battery again."
        }
    }
}
```

- [ ] **3.3 Settings screen.** In `ios/App/BatteryApp.swift`, after the IP `TextField` block (after `.accessibilityLabel("Battery IP address")`), add:

```swift
                    FindBatteryRow(port: settings.port) { host in
                        settings.host = host
                        Task { await save() }
                    }
```

- [ ] **3.4 Strings.** Add to `ios/Shared/Localizable.xcstrings` (`"state": "translated"`); check them with the `ukrainian-translation-review` skill:

| en | uk |
|---|---|
| `Find battery` | `Знайти батарею` |
| `Searching…` | `Шукаю…` |
| `Choose a battery` | `Оберіть батарею` |
| `Join the battery's Wi‑Fi, then tap Find battery.` | `Підключіться до Wi‑Fi батареї й натисніть «Знайти батарею».` |
| `No battery found. Turn on Open API for the battery in the Marstek app.` | `Батарею не знайдено. Увімкніть Open API для батареї в застосунку Marstek.` |
| `Allow Local Network for Battery ETA, then tap Find battery again.` | `Дозвольте Battery ETA доступ до локальної мережі й знову натисніть «Знайти батарею».` |

`%@ · %@` already exists.

- [ ] **3.5 Constraint line.** In `CLAUDE.md`, replace "The iOS app sends only `ES.GetStatus`." with "The iOS app sends only `ES.GetStatus`, plus one `Marstek.GetDevice` per subnet address when the user taps Find battery; never on a timer."

- [ ] **3.6 Gate.** `make test`. Expected: pass. Then run the app on the `iPhone 18 Pro` simulator and tap Find battery: the row shows "Searching…" and ends with the no-battery note (the simulator shares the Mac's network, so on the home Wi‑Fi it finds the battery).

- [ ] **3.7 Commit.** `git add ios CLAUDE.md && git commit -m "feat: find the battery on the wi-fi from settings"`

## Task 4: Owner check on the iPhone (10 minutes)

- [ ] **4.1** `make upload BUILD=<next>`, install from TestFlight, clear the IP field, tap Find battery. Expected: within 20 s the IP fills with `192.168.68.50` and "Now" shows a reading.
- [ ] **4.2** Watch the battery output for 10 minutes after the sweep. Expected: no cut.
