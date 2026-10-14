# iPhone app and widgets for the Marstek battery (LAN only)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** an iPhone app named Battery ETA with one settings screen and three widgets that read the battery over the home Wi‑Fi, shipped to a friend through TestFlight internal testing today.

**Architecture:** the app and the widget extension share `Shared/`. Each widget refresh opens a UDP socket to the battery, sends `ES.GetStatus`, waits 1 s, sends `Bat.GetStatus`, and stores the result in the App Group. A failed refresh keeps the last reading and marks it stale. iOS refreshes a widget about every 15–30 minutes, so the widget ETA is instant: energy left ÷ current power. The Stream Deck estimator needs continuous 15 s polling and does not port.

**Tech Stack:** Swift 5 language mode, SwiftUI, WidgetKit, Network framework (`NWConnection`), Swift Testing, xcodegen, Xcode 27, iOS 17+.

**Spec:** this plan. Device facts and the reply fixtures come from `plans/2026-10-12-streamdeck-battery-eta.md`.

## Global constraints

- The app sends only `ES.GetStatus` and `Bat.GetStatus`. It never sends a method that writes.
- One request in flight per fetch, 1 s between the two requests. The app polls every 15 s only while it is on screen.
- Team `WSCTL2V8W5`, automatic signing. Bundle IDs `com.mlapin.marstek.battery` and `com.mlapin.marstek.battery.widget`. App Group `group.com.mlapin.marstek.battery`.
- iPhone only (`TARGETED_DEVICE_FAMILY: 1`), deployment target iOS 17.0.
- Everything lives in `ios/`. All commands run from `ios/`. The generated `BatteryETA.xcodeproj` and `build/` are gitignored.
- `make test` passes after every task. Simulator: `iPhone 18 Pro` (booted).
- Conventional Commits, one subject line, no co-author trailer. Branch `feat/ios-battery-widget`, cut from `feat/streamdeck-battery-eta`.

## Review focus

1. Phone away from home or on mobile data: the widget keeps the last percent greyed, shows `NO LINK` and the age of the reading, never blank or zeros. (Task 3 test.)
2. Local Network permission denied or never granted: the widget shows `ALLOW LAN`. The app tells the user where to turn it on. (Task 3 test; the mapping from iOS is checked on the device in Task 1.)
3. A widget added before the app was ever opened, or an empty or invalid IP: `SET IP`, and no UDP traffic. (Task 3 test.)
4. Battery full, at the reserve, or idle with no backup load: `FULL`, `0m`, `—`, never `NaN` or `inf`. (Tasks 2 and 3 tests.)
5. A late datagram with another request's id is ignored, and a silent battery gets one retry. (Task 1 test.)

## Batches

- A: Task 1 (one `implementer`), then the owner's device check. Stop here if the widget cannot reach the LAN.
- B: Tasks 2, 3 (one `implementer`)
- C: Tasks 4, 5, 6 (one `implementer` on Opus)
- D: Task 7 (one `implementer` on Opus, steps 7.1–7.4), then the owner's App Store Connect steps

Time: about 4¼ hours of work plus 15–30 minutes of TestFlight processing.

---

## Task 1: Walking skeleton — a widget that reads the battery on a real iPhone

Proves the one unverified point before the real UI: a WidgetKit extension can send UDP to a LAN address using the app's Local Network permission. The spike screen and spike widget get replaced in Tasks 4 and 5.

**Files**
- Create: `ios/project.yml`, `ios/Makefile`
- Create: `ios/App/BatteryApp.swift`, `ios/Widget/BatteryWidgets.swift`
- Create: `ios/Shared/AppGroup.swift`, `ios/Shared/Once.swift`, `ios/Shared/MarstekProtocol.swift`, `ios/Shared/MarstekClient.swift`, `ios/Shared/Reading.swift`
- Create: `ios/Tests/ProtocolTests.swift`, `ios/Tests/ClientTests.swift`, `ios/Tests/FakeBattery.swift`
- Modify: `.gitignore`

**Interfaces**
- Produces: `AppGroup.id`; `Once<T>`; `EsStatus`, `BatStatus`, `MarstekProtocol.request(id:method:)`, `.replyId(_:)`, `.esStatus(_:)`, `.batStatus(_:)`; `DeviceError` (`timeout`, `blocked`, `network(String)`, `badReply(String)`); `MarstekClient(host:port:timeout:gap:)` with `reading(at:) async throws -> Reading` and `call(_:) async throws -> Data`; `Reading` (`time`, `socPct`, `acW`, `offgridW`, `capacityWh`, `ratedWh`, `tempC`), positive `acW` = discharging.

- [x] **1.1 Branch and scaffold.** From the repo root:

```bash
git switch -c feat/ios-battery-widget
printf 'ios/build/\nios/*.xcodeproj\n' >> .gitignore
mkdir -p ios/App ios/Widget ios/Shared ios/Tests
```

`ios/project.yml`:

```yaml
name: BatteryETA
options:
  bundleIdPrefix: com.mlapin.marstek
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    DEVELOPMENT_TEAM: WSCTL2V8W5
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    TARGETED_DEVICE_FAMILY: "1"
targets:
  BatteryETA:
    type: application
    platform: iOS
    sources: [App, Shared]
    dependencies:
      - target: BatteryWidget
    entitlements:
      path: App/BatteryETA.entitlements
      properties:
        com.apple.security.application-groups: [group.com.mlapin.marstek.battery]
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Battery ETA
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSLocalNetworkUsageDescription: Battery ETA reads your Marstek battery over your home Wi-Fi.
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mlapin.marstek.battery
    scheme:
      testTargets: [BatteryTests]
  BatteryWidget:
    type: app-extension
    platform: iOS
    sources: [Widget, Shared]
    entitlements:
      path: Widget/BatteryWidget.entitlements
      properties:
        com.apple.security.application-groups: [group.com.mlapin.marstek.battery]
    info:
      path: Widget/Info.plist
      properties:
        CFBundleDisplayName: Battery ETA
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mlapin.marstek.battery.widget
        SKIP_INSTALL: YES
  BatteryTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests]
    dependencies:
      - target: BatteryETA
```

`ios/Makefile` (Task 7 adds `icon`, `archive`, `upload`):

```make
SIM ?= iPhone 18 Pro

.PHONY: project test

project:
	xcodegen generate

test: project
	xcodebuild test -project BatteryETA.xcodeproj -scheme BatteryETA -destination 'platform=iOS Simulator,name=$(SIM)' -quiet
```

`ios/Shared/AppGroup.swift`:

```swift
enum AppGroup {
    static let id = "group.com.mlapin.marstek.battery"
}
```

`ios/Shared/Once.swift`:

```swift
import Foundation

final class Once<T>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
```

- [x] **1.2 Write the protocol tests.** `ios/Tests/ProtocolTests.swift` (fixtures captured from the device on 2026-10-12):

```swift
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

    @Test func garbageHasNoId() {
        #expect(throws: DeviceError.badReply("Reply has no id")) { try MarstekProtocol.replyId(Data("garbage".utf8)) }
    }
}
```

- [x] **1.3 Write the client tests and the fake battery.** `ios/Tests/FakeBattery.swift`:

```swift
import Foundation
import Network
@testable import BatteryETA

struct FakeRequest: Decodable {
    let id: Int
    let method: String
}

final class FakeBattery: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake.battery")
    private let reply: (FakeRequest, Int) -> [String]
    private var attempts = 0

    private init(listener: NWListener, reply: @escaping (FakeRequest, Int) -> [String]) {
        self.listener = listener
        self.reply = reply
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    static func start(reply: @escaping (FakeRequest, Int) -> [String]) async throws -> FakeBattery {
        let fake = FakeBattery(listener: try NWListener(using: .udp, on: .any), reply: reply)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once(continuation)
            fake.listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error): once.resume(.failure(error))
                default: break
                }
            }
            fake.listener.newConnectionHandler = { connection in
                connection.start(queue: fake.queue)
                fake.listen(connection)
            }
            fake.listener.start(queue: fake.queue)
        }
        return fake
    }

    func stop() {
        listener.cancel()
    }

    private func listen(_ connection: NWConnection) {
        connection.receiveMessage { [self] data, _, _, error in
            guard error == nil, let data, let request = try? JSONDecoder().decode(FakeRequest.self, from: data) else { return }
            attempts += 1
            for text in reply(request, attempts) {
                connection.send(content: Data(text.utf8), completion: .idempotent)
            }
            listen(connection)
        }
    }
}
```

`ios/Tests/ClientTests.swift`:

```swift
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

    @Test func readingCombinesBothMethods() async throws {
        let fake = try await FakeBattery.start { request, _ in
            request.method == "ES.GetStatus"
                ? [#"{"id":\#(request.id),"result":{"bat_soc":80,"ongrid_power":-797,"offgrid_power":0}}"#]
                : [#"{"id":\#(request.id),"result":{"bat_capacity":4121.0,"rated_capacity":5120.0,"bat_temp":24.0}}"#]
        }
        defer { fake.stop() }
        let time = Date(timeIntervalSince1970: 0)
        let reading = try await client(fake).reading(at: time)
        #expect(reading == Reading(time: time, socPct: 80, acW: -797, offgridW: 0, capacityWh: 4121, ratedWh: 5120, tempC: 24))
    }
}
```

- [x] **1.4 Run the tests and see them fail.** Write `ios/App/BatteryApp.swift` and `ios/Widget/BatteryWidgets.swift` first (step 1.6), then run `make test`. Expected: compile errors on `MarstekProtocol`, `MarstekClient`, `Reading`.

- [x] **1.5 Implement the protocol, client and reading.** `ios/Shared/MarstekProtocol.swift`:

```swift
import Foundation

struct EsStatus: Equatable {
    let socPct: Int
    let ongridW: Double
    let offgridW: Double
}

struct BatStatus: Equatable {
    let capacityWh: Double
    let ratedWh: Double
    let tempC: Double
}

enum MarstekProtocol {
    // The firmware echoes only the low 16 bits of the id and ignores 65535; the retry sends id + 1.
    static func newId() -> Int { Int.random(in: 1...32_766) }

    static func request(id: Int, method: String) -> Data {
        Data(#"{"id":\#(id),"method":"\#(method)","params":{"id":0}}"#.utf8)
    }

    static func replyId(_ data: Data) throws -> Int {
        guard let head = try? JSONDecoder().decode(Head.self, from: data) else { throw DeviceError.badReply("Reply has no id") }
        return head.id
    }

    static func esStatus(_ data: Data) throws -> EsStatus {
        let result = try decode(EsResult.self, data)
        return EsStatus(socPct: Int(result.socPct.rounded()), ongridW: result.ongridW, offgridW: result.offgridW)
    }

    static func batStatus(_ data: Data) throws -> BatStatus {
        let result = try decode(BatResult.self, data)
        guard result.ratedWh > 0 else { throw DeviceError.badReply("Reply has rated_capacity \(result.ratedWh)") }
        return BatStatus(capacityWh: result.capacityWh, ratedWh: result.ratedWh, tempC: result.tempC)
    }

    private static func decode<R: Decodable>(_ type: R.Type, _ data: Data) throws -> R {
        guard let envelope = try? JSONDecoder().decode(Envelope<R>.self, from: data) else {
            throw DeviceError.badReply("Reply has a missing field")
        }
        if let fault = envelope.error { throw DeviceError.badReply("Device error \(fault.code): \(fault.message)") }
        guard let result = envelope.result else { throw DeviceError.badReply("Reply has no result") }
        return result
    }
}

private struct Head: Decodable {
    let id: Int
}

private struct Fault: Decodable {
    let code: Int
    let message: String
}

private struct Envelope<R: Decodable>: Decodable {
    let result: R?
    let error: Fault?
}

private struct EsResult: Decodable {
    let socPct: Double
    let ongridW: Double
    let offgridW: Double

    enum CodingKeys: String, CodingKey {
        case socPct = "bat_soc"
        case ongridW = "ongrid_power"
        case offgridW = "offgrid_power"
    }
}

private struct BatResult: Decodable {
    let capacityWh: Double
    let ratedWh: Double
    let tempC: Double

    enum CodingKeys: String, CodingKey {
        case capacityWh = "bat_capacity"
        case ratedWh = "rated_capacity"
        case tempC = "bat_temp"
    }
}
```

`ios/Shared/Reading.swift`:

```swift
import Foundation

struct Reading: Codable, Equatable {
    var time: Date
    var socPct: Int
    var acW: Double
    var offgridW: Double
    var capacityWh: Double
    var ratedWh: Double
    var tempC: Double
}

extension Reading {
    init(time: Date, es: EsStatus, bat: BatStatus) {
        self.init(
            time: time, socPct: es.socPct, acW: es.ongridW + es.offgridW, offgridW: es.offgridW,
            capacityWh: bat.capacityWh, ratedWh: bat.ratedWh, tempC: bat.tempC
        )
    }
}
```

`ios/Shared/MarstekClient.swift`. Each attempt uses its own connection, so a late reply to the first attempt cannot reach the retry:

```swift
import Foundation
import Network

enum DeviceError: Error, Equatable {
    case timeout
    case blocked
    case network(String)
    case badReply(String)

    static func from(_ error: NWError, path: NWPath?) -> DeviceError {
        if path?.unsatisfiedReason == .localNetworkDenied { return .blocked }
        return .network(error.debugDescription)
    }
}

struct MarstekClient {
    let host: String
    let port: UInt16
    var timeout: TimeInterval = 2
    var gap: Duration = .seconds(1)

    func reading(at time: Date = .now) async throws -> Reading {
        let es = try MarstekProtocol.esStatus(await call("ES.GetStatus"))
        try await Task.sleep(for: gap)
        let bat = try MarstekProtocol.batStatus(await call("Bat.GetStatus"))
        return Reading(time: time, es: es, bat: bat)
    }

    func call(_ method: String) async throws -> Data {
        let id = MarstekProtocol.newId()
        do {
            return try await exchange(MarstekProtocol.request(id: id, method: method), id: id)
        } catch DeviceError.timeout {
            try await Task.sleep(for: gap)
            return try await exchange(MarstekProtocol.request(id: id + 1, method: method), id: id + 1)
        }
    }

    private func exchange(_ request: Data, id: Int) async throws -> Data {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw DeviceError.network("Bad port") }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .udp)
        let queue = DispatchQueue(label: "marstek.udp")
        let timeout = timeout
        defer { connection.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            let fail = { (error: NWError) in once.resume(.failure(DeviceError.from(error, path: connection.currentPath))) }

            connection.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error), .failed(let error): fail(error)
                default: break
                }
            }

            func listen() {
                connection.receiveMessage { data, _, _, error in
                    if let error { fail(error); return }
                    guard let data, (try? MarstekProtocol.replyId(data)) == id else { listen(); return }
                    once.resume(.success(data))
                }
            }

            connection.start(queue: queue)
            connection.send(content: request, completion: .contentProcessed { error in
                if let error { fail(error) }
            })
            listen()
            queue.asyncAfter(deadline: .now() + timeout) { once.resume(.failure(DeviceError.timeout)) }
        }
    }
}
```

- [x] **1.6 Spike app and spike widget.** `ios/App/BatteryApp.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct BatteryApp: App {
    var body: some Scene {
        WindowGroup { SpikeScreen() }
    }
}

struct SpikeScreen: View {
    @AppStorage("host", store: UserDefaults(suiteName: AppGroup.id)) private var host = ""
    @State private var result = ""

    var body: some View {
        Form {
            TextField("Battery IP", text: $host)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Check") {
                Task {
                    do { result = "\(try await MarstekClient(host: host, port: 30000).reading())" } catch { result = "\(error)" }
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            Text(result)
        }
    }
}
```

`ios/Widget/BatteryWidgets.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct BatteryWidgets: WidgetBundle {
    var body: some Widget {
        SpikeWidget()
    }
}

struct SpikeEntry: TimelineEntry {
    let date: Date
    let text: String
}

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: .now, text: "··")
    }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        Task {
            let host = UserDefaults(suiteName: AppGroup.id)?.string(forKey: "host") ?? ""
            let text: String
            do { text = "\(try await MarstekClient(host: host, port: 30000).reading().socPct)%" } catch { text = "\(error)" }
            completion(Timeline(entries: [SpikeEntry(date: .now, text: text)], policy: .after(.now.addingTimeInterval(900))))
        }
    }
}

struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "spike", provider: SpikeProvider()) { entry in
            Text(entry.text).font(.caption).containerBackground(.black, for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}
```

- [x] **1.7 Run the tests and see them pass.** `make test`. Expected: all `ProtocolTests` and `ClientTests` pass.

- [x] **1.8 Commit.**

```bash
git add .gitignore ios
git commit -m "feat: add ios app skeleton that reads the battery over udp"
```

- [ ] **1.9 Owner: device check (about 10 minutes, iPhone on the home Wi‑Fi).**
  1. Plug in the iPhone. Developer Mode must be on (Settings → Privacy & Security → Developer Mode).
  2. `make project && open BatteryETA.xcodeproj`. Pick the iPhone, press Run. Automatic signing registers both bundle IDs and the App Group. If signing fails on the App Group, add it under Signing & Capabilities for both targets and run again.
  3. In the app, type `192.168.68.50`, tap **Check**, and tap **Allow** on the Local Network prompt. The text shows a `Reading(...)`.
  4. Add the small **Battery ETA** widget to the Home Screen. Pass: it shows `80%` or similar within a minute.
  5. Settings → Privacy & Security → Local Network → turn Battery ETA off. Tap Check again. Pass: `blocked`. Turn it back on.

  If the app reads the battery and the widget shows `blocked` or `timeout`, stop. The widget cannot use the LAN, and the plan needs a re-scope.

---

## Task 2: Instant estimate and duration format

**Files**
- Create: `ios/Shared/Estimate.swift`, `ios/Shared/Format.swift`
- Create: `ios/Tests/EstimateTests.swift`, `ios/Tests/FormatTests.swift`

**Interfaces**
- Consumes: `Reading`.
- Produces: `Mode` (`charging`, `discharging`, `idle`); `Estimate(mode:hours:)` with `hours: Double?`; `QuickEstimate.estimate(_ reading: Reading, floorPct: Double) -> Estimate`; `formatDuration(_ hours: Double) -> String`.

Rules, from the Stream Deck estimator's defaults: idle within ±30 W; charge ratio 0.88; discharge ratio 1.09; usable energy = `capacityWh − floor% × ratedWh`; cap at 240 h. While idle with a backup-socket load over 30 W, `hours` is the outage projection on that load.

- [x] **2.1 Write the failing tests.** `ios/Tests/EstimateTests.swift`:

```swift
import Foundation
import Testing
@testable import BatteryETA

func reading(soc: Int = 80, acW: Double, offgridW: Double = 0, capacityWh: Double = 4121) -> Reading {
    Reading(time: Date(timeIntervalSince1970: 1_760_000_000), socPct: soc, acW: acW, offgridW: offgridW, capacityWh: capacityWh, ratedWh: 5120, tempC: 24)
}

struct EstimateTests {
    @Test func dischargingCountsDownToTheReserve() throws {
        let est = QuickEstimate.estimate(reading(acW: 400), floorPct: 12)
        #expect(est.mode == .discharging)
        #expect(abs(try #require(est.hours) - 8.0427) < 0.001)
    }

    @Test func chargingCountsUpToRated() throws {
        let est = QuickEstimate.estimate(reading(acW: -797), floorPct: 12)
        #expect(est.mode == .charging)
        #expect(abs(try #require(est.hours) - 1.4244) < 0.001)
    }

    @Test func idleWithABackupLoadProjectsAnOutage() throws {
        let est = QuickEstimate.estimate(reading(acW: 0, offgridW: 150), floorPct: 12)
        #expect(est.mode == .idle)
        #expect(abs(try #require(est.hours) - 21.447) < 0.001)
    }

    @Test func idleWithoutABackupLoadHasNoEta() {
        #expect(QuickEstimate.estimate(reading(acW: 20), floorPct: 12) == Estimate(mode: .idle, hours: nil))
    }

    @Test func belowTheReserveIsZeroNeverNegative() {
        #expect(QuickEstimate.estimate(reading(soc: 11, acW: 400, capacityWh: 600), floorPct: 12).hours == 0)
    }

    @Test func fullWhileChargingIsZero() {
        #expect(QuickEstimate.estimate(reading(soc: 100, acW: -50, capacityWh: 5120), floorPct: 12).hours == 0)
    }

    @Test func aTinyLoadIsCapped() {
        #expect(QuickEstimate.estimate(reading(acW: 31, capacityWh: 10_000), floorPct: 0).hours == 240)
    }
}
```

`ios/Tests/FormatTests.swift`:

```swift
import Testing
@testable import BatteryETA

struct FormatTests {
    @Test(arguments: [
        (0.0, "0m"), (3.0 / 60, "3m"), (0.2, "10m"), (1.4244, "1h30"), (8.0427, "8h00"), (21.447, "21h"),
    ])
    func formats(hours: Double, text: String) {
        #expect(formatDuration(hours) == text)
    }
}
```

- [x] **2.2 Run `make test`.** Expected: compile errors on `QuickEstimate` and `formatDuration`.

- [x] **2.3 Implement.** `ios/Shared/Estimate.swift`:

```swift
import Foundation

enum Mode: Equatable {
    case charging, discharging, idle
}

struct Estimate: Equatable {
    let mode: Mode
    let hours: Double?
}

enum QuickEstimate {
    static let idleW = 30.0
    static let chargeRatio = 0.88
    static let dischargeRatio = 1.09
    static let maxHours = 240.0

    static func estimate(_ r: Reading, floorPct: Double) -> Estimate {
        let usableWh = max(0, r.capacityWh - floorPct / 100 * r.ratedWh)
        if r.acW < -idleW {
            let missingWh = max(0, r.ratedWh - r.capacityWh)
            return Estimate(mode: .charging, hours: capped(missingWh / (-r.acW * chargeRatio)))
        }
        if r.acW > idleW {
            return Estimate(mode: .discharging, hours: capped(usableWh / dischargeRatio / r.acW))
        }
        if r.offgridW > idleW {
            return Estimate(mode: .idle, hours: capped(usableWh / dischargeRatio / r.offgridW))
        }
        return Estimate(mode: .idle, hours: nil)
    }

    private static func capped(_ hours: Double) -> Double {
        min(maxHours, hours)
    }
}
```

`ios/Shared/Format.swift` (same steps as `streamdeck/src/core/format.ts`):

```swift
import Foundation

func formatDuration(_ hours: Double) -> String {
    let minutes = hours * 60
    if minutes >= 600 { return "\(Int((minutes / 60).rounded()))h" }
    if minutes >= 60 {
        let rounded = Int((minutes / 10).rounded()) * 10
        return "\(rounded / 60)h" + String(format: "%02d", rounded % 60)
    }
    if minutes >= 10 { return "\(Int((minutes / 5).rounded()) * 5)m" }
    return "\(max(0, Int(minutes.rounded())))m"
}
```

- [x] **2.4 Run `make test`.** Expected: all pass.

- [x] **2.5 Commit.** `git add ios && git commit -m "feat: add instant battery eta for the ios widget"`

---

## Task 3: Settings, stored snapshot and the face model

**Files**
- Create: `ios/Shared/Store.swift`, `ios/Shared/Face.swift`
- Create: `ios/Tests/StoreTests.swift`, `ios/Tests/FaceTests.swift`

**Interfaces**
- Consumes: `MarstekClient`, `DeviceError`, `Reading`, `QuickEstimate`, `formatDuration`, `AppGroup.id`.
- Produces: `BatterySettings` (`host`, `port`, `floorPct`, `problem: String?`); `FetchError` (`settings`, `blocked`, `noLink`, `badReply`) with `text`; `Snapshot` (`reading`, `error`, `checkedAt`); `Store(defaults:)` with `settings` and `snapshot`; `Refresher.refresh(_ store: Store, now: Date, fetch:) async -> Snapshot`; `Tone`; `Face` with `init(_ snapshot: Snapshot?, floorPct: Int)` and `Face.sample`.

- [x] **3.1 Write the failing tests.** `ios/Tests/StoreTests.swift`:

```swift
import Foundation
import Testing
@testable import BatteryETA

struct StoreTests {
    private func store(host: String = "192.168.68.50") -> Store {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        store.settings = BatterySettings(host: host, port: 30000, floorPct: 12)
        return store
    }

    @Test func aGoodFetchIsStored() async {
        let store = store()
        let good = reading(acW: 400)
        let snapshot = await Refresher.refresh(store, now: good.time) { _ in good }
        #expect(snapshot == Snapshot(reading: good, error: nil, checkedAt: good.time))
        #expect(store.snapshot == snapshot)
    }

    @Test func aFailedFetchKeepsTheLastReading() async {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store) { _ in good }
        let snapshot = await Refresher.refresh(store) { _ in throw DeviceError.timeout }
        #expect(snapshot.reading == good)
        #expect(snapshot.error == .noLink)
    }

    @Test func aDeniedPermissionIsBlocked() async {
        let snapshot = await Refresher.refresh(store()) { _ in throw DeviceError.blocked }
        #expect(snapshot.error == .blocked)
    }

    @Test(arguments: ["", "192.168.68.50; rm"])
    func aBadHostSendsNothing(host: String) async {
        var fetched = false
        let snapshot = await Refresher.refresh(store(host: host)) { _ in
            fetched = true
            return reading(acW: 400)
        }
        #expect(snapshot.error == .settings)
        #expect(!fetched)
    }

    @Test func aFreshStoreHasDefaults() {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        #expect(store.settings == BatterySettings())
        #expect(store.snapshot == nil)
    }
}
```

`ios/Tests/FaceTests.swift`:

```swift
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
```

- [x] **3.2 Run `make test`.** Expected: compile errors on `Store`, `Refresher`, `Face`.

- [x] **3.3 Implement.** `ios/Shared/Store.swift`:

```swift
import Foundation

struct BatterySettings: Codable, Equatable {
    var host = ""
    var port = 30000
    var floorPct = 12

    var problem: String? {
        if host.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) == nil { return "Enter the battery IP address" }
        if !(1...65535).contains(port) { return "Port must be 1 to 65535" }
        if !(0...50).contains(floorPct) { return "Reserve must be 0 to 50 %" }
        return nil
    }
}

enum FetchError: String, Codable {
    case settings, blocked, noLink, badReply

    init(_ error: Error) {
        switch error as? DeviceError {
        case .blocked: self = .blocked
        case .badReply: self = .badReply
        default: self = .noLink
        }
    }

    var text: String {
        switch self {
        case .settings: "SET IP"
        case .blocked: "ALLOW LAN"
        case .noLink: "NO LINK"
        case .badReply: "ERROR"
        }
    }
}

struct Snapshot: Codable, Equatable {
    var reading: Reading?
    var error: FetchError?
    var checkedAt: Date
}

final class Store {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.id)) {
        self.defaults = defaults ?? .standard
    }

    var settings: BatterySettings {
        get { load("settings") ?? BatterySettings() }
        set { save(newValue, "settings") }
    }

    var snapshot: Snapshot? {
        get { load("snapshot") }
        set { save(newValue, "snapshot") }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}

enum Refresher {
    static func refresh(
        _ store: Store,
        now: Date = .now,
        fetch: (BatterySettings) async throws -> Reading = Refresher.live
    ) async -> Snapshot {
        let settings = store.settings
        var next = Snapshot(reading: store.snapshot?.reading, error: nil, checkedAt: now)
        if settings.problem != nil {
            next.error = .settings
        } else {
            do { next.reading = try await fetch(settings) } catch { next.error = FetchError(error) }
        }
        store.snapshot = next
        return next
    }

    static func live(_ settings: BatterySettings) async throws -> Reading {
        try await MarstekClient(host: settings.host, port: UInt16(settings.port)).reading()
    }
}
```

`ios/Shared/Face.swift`:

```swift
import Foundation

enum Tone: Equatable {
    case neutral, good, warn, bad
}

struct Face: Equatable {
    var percent = "··"
    var fill = 0.0
    var charging = false
    var power = ""
    var etaLabel = "BATTERY"
    var eta = "··"
    var tone = Tone.neutral
    var stale = true
    var problem: String?
    var updated: Date?
}

extension Face {
    init(_ snapshot: Snapshot?, floorPct: Int) {
        self.init()
        problem = snapshot?.error?.text
        guard let r = snapshot?.reading else {
            eta = problem ?? "··"
            return
        }
        let est = QuickEstimate.estimate(r, floorPct: Double(floorPct))
        let watts = Int(abs(r.acW).rounded())
        let etaText = est.hours.map(formatDuration) ?? "—"
        percent = "\(r.socPct)%"
        fill = min(1, max(0, Double(r.socPct) / 100))
        charging = est.mode == .charging
        stale = snapshot?.error != nil
        updated = r.time

        switch est.mode {
        case .charging:
            power = "+\(watts) W"
            tone = .good
            etaLabel = "FULL IN"
            eta = r.socPct >= 100 ? "FULL" : etaText
        case .discharging:
            power = "−\(watts) W"
            tone = r.socPct < 20 || (est.hours ?? 0) < 0.5 ? .bad : .warn
            etaLabel = "EMPTY IN"
            eta = etaText
        case .idle:
            power = "IDLE"
            etaLabel = est.hours == nil ? "ETA" : "IF OUTAGE"
            eta = est.hours == nil ? (r.socPct >= 100 ? "FULL" : "—") : etaText
        }
    }

    static let sample = Face(
        percent: "82%", fill: 0.82, charging: false, power: "−412 W", etaLabel: "EMPTY IN", eta: "6h20",
        tone: .warn, stale: false, problem: nil, updated: .now
    )
}
```

- [x] **3.4 Run `make test`.** Expected: all pass.

- [x] **3.5 Commit.** `git add ios && git commit -m "feat: store battery settings and snapshots for the ios widget"`

---

## Task 4: Three widgets

Replaces the spike widget. The approved design is the Battery ETA canvas (https://claude.ai/artifact/1ZfUnFUKedswkhYC5dc9wL), boards "Home Screen widgets" and "Lock Screen widgets". Colors follow the Stream Deck keys, except stale grey `#6E6E76`, which stays readable.

| Widget | Family | Shows |
| --- | --- | --- |
| Battery | `systemSmall` | 270° ring, percent with a small `%`, power or the problem in red |
| Battery and ETA | `systemMedium` | the small face, ETA label, ETA with small units (`6h20`), `Updated 23:41` (clock time of the reading) |
| Lock Screen | `accessoryCircular`, `accessoryRectangular` | capacity gauge with the number; or `Battery 82%`, `EMPTY IN 6h20`, power, all white |

States the design draws, all produced by `Face` from Task 3: discharging (amber), charging (green, bolt), idle with a backup load (`IF OUTAGE`, grey), low (red), away (greyed last reading, `NO LINK`), not set up (`··`, `SET IP` in red, `Open the app`).

**Files**
- Create: `ios/Shared/Faces.swift`, `ios/Tests/ValueRunsTests.swift`
- Modify: `ios/Widget/BatteryWidgets.swift` (replace the whole file)

**Interfaces**
- Consumes: `Face`, `Tone`, `Store`, `Refresher.refresh`.
- Produces: `Palette` (`bg`, `good`, `bad`, `label`, `accent(_:)`, `value(_:)`, `unit(_:)`), `Color(hex:)`, `Run`, `valueRuns(_:)`, `ValueText`, `SmallFace(face:)`, `MediumFace(face:)` (Task 5 shows `MediumFace` and uses `Palette`).

- [x] **4.1 Write the failing test.** `ios/Tests/ValueRunsTests.swift`:

```swift
import Testing
@testable import BatteryETA

struct ValueRunsTests {
    @Test func splitsDigitsFromUnits() {
        #expect(valueRuns("6h20") == [Run(text: "6", digits: true), Run(text: "h", digits: false), Run(text: "20", digits: true)])
        #expect(valueRuns("82%") == [Run(text: "82", digits: true), Run(text: "%", digits: false)])
    }

    @Test func aWordIsOneRun() {
        #expect(valueRuns("FULL") == [Run(text: "FULL", digits: false)])
    }
}
```

Run `make test`. Expected: compile errors on `valueRuns` and `Run`.

- [x] **4.2 Write the views.** `ios/Shared/Faces.swift`:

```swift
import SwiftUI

enum Palette {
    static let bg = Color(hex: 0x0F0F12)
    static let track = Color(hex: 0x24242A)
    static let label = Color(hex: 0x8E8E93)
    static let stale = Color(hex: 0x6E6E76)
    static let good = Color(hex: 0x3DDC97)
    static let bad = Color(hex: 0xFF6B5E)

    static func accent(_ face: Face) -> Color {
        if face.stale { return stale }
        switch face.tone {
        case .neutral: return Color(hex: 0xA3A3AD)
        case .good: return good
        case .warn: return Color(hex: 0xFFB547)
        case .bad: return bad
        }
    }

    static func value(_ face: Face) -> Color {
        face.stale ? stale : .white
    }

    static func unit(_ face: Face) -> Color {
        face.stale ? stale : Color(hex: 0x8E8E97)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct Run: Equatable {
    var text: String
    var digits: Bool
}

func valueRuns(_ text: String) -> [Run] {
    var runs: [Run] = []
    for char in text {
        if let last = runs.last, last.digits == char.isNumber {
            runs[runs.count - 1].text.append(char)
        } else {
            runs.append(Run(text: String(char), digits: char.isNumber))
        }
    }
    return runs
}

struct ValueText: View {
    let text: String
    let size: CGFloat
    let unitSize: CGFloat
    let color: Color
    let unitColor: Color

    var body: some View {
        if text.first?.isNumber == true {
            valueRuns(text).reduce(Text("")) { line, run in
                line + Text(run.text)
                    .font(.system(size: run.digits ? size : unitSize, weight: run.digits ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(run.digits ? color : unitColor)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        } else {
            Text(text)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

struct Bolt: View {
    let color: Color

    var body: some View {
        Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(color)
    }
}

struct Ring: View {
    let face: Face
    var width: CGFloat = 8.5

    var body: some View {
        ZStack {
            arc(1).stroke(Palette.track, style: StrokeStyle(lineWidth: width, lineCap: .round))
            if face.fill > 0 {
                arc(face.fill).stroke(Palette.accent(face), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

    private func arc(_ share: Double) -> some Shape {
        Circle().trim(from: 0, to: 0.75 * share).rotation(.degrees(135))
    }
}

struct SmallFace: View {
    let face: Face

    var body: some View {
        ZStack {
            Ring(face: face).padding(14)
            VStack(spacing: 1) {
                if face.charging && !face.stale {
                    Bolt(color: Palette.accent(face))
                }
                ValueText(text: face.percent, size: 38, unitSize: 17, color: Palette.value(face), unitColor: Palette.unit(face))
                Text(face.problem ?? face.power)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(face.problem == nil ? Palette.accent(face) : Palette.bad)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.top, 4)
            .padding(.horizontal, 26)
        }
    }
}

struct MediumFace: View {
    let face: Face

    var body: some View {
        HStack(spacing: 14) {
            SmallFace(face: face).aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 4) {
                Text(face.etaLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Palette.label)
                ValueText(
                    text: face.eta, size: 46, unitSize: 22,
                    color: face.updated == nil && face.problem != nil ? Palette.bad : Palette.value(face),
                    unitColor: Palette.unit(face)
                )
                Group {
                    if let updated = face.updated {
                        Text("Updated \(Text(updated, style: .time))")
                    } else {
                        Text("Open the app")
                    }
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(face.stale ? Color(hex: 0xA3A3AD) : Palette.label)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 20)
    }
}

struct CircularFace: View {
    let face: Face

    var body: some View {
        Gauge(value: face.fill) {
            Text("Battery")
        } currentValueLabel: {
            VStack(spacing: 0) {
                if face.charging && !face.stale {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                }
                Text(face.updated == nil ? "··" : face.percent.replacingOccurrences(of: "%", with: ""))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .opacity(face.stale ? 0.7 : 1)
    }
}

struct RectangularFace: View {
    let face: Face

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(face.updated == nil ? "Battery" : "Battery \(face.percent)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(face.updated == nil ? "Open the app" : "\(face.etaLabel) \(face.eta)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Group {
                if let problem = face.problem, let updated = face.updated {
                    Text("\(problem) · \(Text(updated, style: .time))")
                } else {
                    Text(face.problem ?? face.power)
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(face.stale ? 0.7 : 1)
    }
}
```

- [x] **4.3 Replace the spike widget.** `ios/Widget/BatteryWidgets.swift`. `contentMarginsDisabled()` lets the ring fill the widget as the design draws it:

```swift
import SwiftUI
import WidgetKit

@main
struct BatteryWidgets: WidgetBundle {
    var body: some Widget {
        RingWidget()
        EtaWidget()
        LockWidget()
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let face: Face
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: .now, face: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        let store = Store()
        let face = context.isPreview ? .sample : Face(store.snapshot, floorPct: store.settings.floorPct)
        completion(BatteryEntry(date: .now, face: face))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        Task {
            let store = Store()
            let snapshot = await Refresher.refresh(store)
            let entry = BatteryEntry(date: .now, face: Face(snapshot, floorPct: store.settings.floorPct))
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct RingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ring", provider: BatteryProvider()) { entry in
            SmallFace(face: entry.face).containerBackground(Palette.bg, for: .widget)
        }
        .configurationDisplayName("Battery")
        .description("Charge and power.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct EtaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "eta", provider: BatteryProvider()) { entry in
            MediumFace(face: entry.face).containerBackground(Palette.bg, for: .widget)
        }
        .configurationDisplayName("Battery and ETA")
        .description("Charge, power and time until full or empty.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lock", provider: BatteryProvider()) { entry in
            LockFace(face: entry.face).containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("Battery")
        .description("Charge on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockFace: View {
    @Environment(\.widgetFamily) private var family
    let face: Face

    var body: some View {
        if family == .accessoryCircular {
            CircularFace(face: face)
        } else {
            RectangularFace(face: face)
        }
    }
}
```

- [x] **4.4 Run `make test`.** Expected: build succeeds and all tests pass, `ValueRunsTests` included.

- [x] **4.5 Commit.** `git add ios && git commit -m "feat: add battery, eta and lock screen widgets"`

---

## Task 5: Settings screen

Replaces the spike screen. Matches the "Settings screen" board: dark grouped form in the rounded system font; IP, port and reserve; a filled green **Save and check** button; the medium widget as a live preview; two error hints with red captions. While on screen the app refreshes every 15 s. `checking` keeps one fetch in flight.

**Files**
- Modify: `ios/App/BatteryApp.swift` (replace the whole file)

**Interfaces**
- Consumes: `Store`, `BatterySettings`, `Refresher.refresh`, `Face`, `MediumFace`, `Palette`, `Color(hex:)`.

- [x] **5.1 Replace the spike screen.** `ios/App/BatteryApp.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct BatteryApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsScreen()
                .preferredColorScheme(.dark)
                .fontDesign(.rounded)
                .tint(Palette.good)
        }
    }
}

struct SettingsScreen: View {
    private let store = Store()
    @State private var settings = Store().settings
    @State private var snapshot = Store().snapshot
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.50", text: $settings.host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .monospacedDigit()
                        .accessibilityLabel("Battery IP address")
                    LabeledContent("Port") {
                        TextField("30000", value: $settings.port, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $settings.floorPct, in: 0...50) {
                        Text("Reserve ") + Text("\(settings.floorPct) %").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Battery IP")
                } footer: {
                    Text(settings.problem ?? "The reserve is the charge the battery keeps back. EMPTY IN counts down to it.")
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(checking ? "Checking…" : "Save and check")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x08150F))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Palette.good.opacity(saveDisabled ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(saveDisabled)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Now") {
                    MediumFace(face: Face(snapshot, floorPct: settings.floorPct))
                        .frame(height: 158)
                        .background(Palette.bg, in: RoundedRectangle(cornerRadius: 22))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("If it fails") {
                    hint("ALLOW LAN", "Settings › Privacy & Security › Local Network › turn on Battery ETA.")
                    hint("NO LINK", "Join the battery's Wi‑Fi, and turn on Open API for the battery in the Marstek app.")
                }
            }
            .navigationTitle("Battery ETA")
        }
        .task { await poll() }
    }

    private var saveDisabled: Bool {
        checking || settings.problem != nil
    }

    private func hint(_ code: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Palette.bad)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    private func save() async {
        if settings.host != store.settings.host { store.snapshot = nil }
        store.settings = settings
        await refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refresh() async {
        guard !checking else { return }
        checking = true
        snapshot = await Refresher.refresh(store)
        checking = false
    }

    private func poll() async {
        while !Task.isCancelled {
            if store.settings.problem == nil { await refresh() }
            try? await Task.sleep(for: .seconds(15))
        }
    }
}
```

- [x] **5.2 Run `make test`.** Expected: build succeeds and all tests pass.

- [x] **5.3 Check in the simulator.** The simulator uses the Mac's network, so this needs the Mac on the battery's Wi‑Fi. Launch the app, type the battery IP, tap **Save and check**. Pass: the preview shows percent, power and ETA within 3 s. Type `abc def`. Pass: the footer says `Enter the battery IP address` and the button dims. Add all three widgets and take a screenshot. Pass: they match the canvas boards, with no clipped text.

- [x] **5.4 Commit.** `git add ios && git commit -m "feat: add ios settings screen with live preview"`

---

## Task 6: Ukrainian

The app and the widgets follow the iPhone's language: Ukrainian when it is Ukrainian, English otherwise. String Catalogs hold the text. The English source strings stay as they are, so the earlier tests keep passing.

Wording decisions: durations read `6год20`, `21год`, `25хв` (the digits stay big and the units small, as in English). An outage reads `БЕЗ СВІТЛА`. The app name stays `Battery ETA`.

**Files**
- Create: `ios/Shared/Localizable.xcstrings` (built into both targets through `Shared`), `ios/App/InfoPlist.xcstrings`, `ios/Tests/LocalizationTests.swift`
- Modify: `ios/project.yml`, `ios/Shared/Format.swift`, `ios/Shared/Store.swift`, `ios/Shared/Face.swift`, `ios/Shared/Faces.swift`, `ios/App/BatteryApp.swift`

**Interfaces**
- Consumes: the strings of Tasks 2–5.
- Produces: no new API.

- [x] **6.1 Write the failing tests.** `ios/Tests/LocalizationTests.swift`:

```swift
import Foundation
import Testing
@testable import BatteryETA

struct LocalizationTests {
    private let catalog = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../Shared/Localizable.xcstrings")

    @Test func everyStringHasUkrainian() throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: [String: Any]])
        #expect(strings.count >= 38)
        for (key, entry) in strings {
            let uk = (entry["localizations"] as? [String: Any])?["uk"] as? [String: Any]
            let value = (uk?["stringUnit"] as? [String: Any])?["value"] as? String
            #expect(value?.isEmpty == false, "No Ukrainian for \(key)")
        }
    }

    @Test func theAppShipsUkrainian() throws {
        let path = try #require(Bundle.main.path(forResource: "uk", ofType: "lproj"))
        let uk = try #require(Bundle(path: path))
        #expect(uk.localizedString(forKey: "NO LINK", value: nil, table: nil) == "НЕМАЄ ЗВʼЯЗКУ")
        #expect(uk.localizedString(forKey: "h", value: nil, table: nil) == "год")
        #expect(uk.localizedString(forKey: "−%lld W", value: nil, table: nil) == "−%lld Вт")
    }
}
```

- [x] **6.2 Run `make test`.** Expected: both tests fail (no catalog, no `uk.lproj`).

- [x] **6.3 Add the catalogs.** `ios/Shared/Localizable.xcstrings`:

```json
{
  "sourceLanguage": "en",
  "strings": {
    "%@ · %@": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "%1$@ · %2$@"
          }
        }
      }
    },
    "+%lld W": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "+%lld Вт"
          }
        }
      }
    },
    "ALLOW LAN": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "ДОЗВОЛЬТЕ LAN"
          }
        }
      }
    },
    "BATTERY": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "БАТАРЕЯ"
          }
        }
      }
    },
    "Battery": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Батарея"
          }
        }
      }
    },
    "Battery %@": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Батарея %@"
          }
        }
      }
    },
    "Battery IP": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "IP батареї"
          }
        }
      }
    },
    "Battery IP address": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "IP-адреса батареї"
          }
        }
      }
    },
    "Battery and ETA": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Батарея і час"
          }
        }
      }
    },
    "Charge and power.": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Заряд і потужність."
          }
        }
      }
    },
    "Charge on the Lock Screen.": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Заряд на екрані блокування."
          }
        }
      }
    },
    "Charge, power and time until full or empty.": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Заряд, потужність і час до повного заряду чи розряду."
          }
        }
      }
    },
    "Checking…": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Перевірка…"
          }
        }
      }
    },
    "EMPTY IN": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "ДО РОЗРЯДУ"
          }
        }
      }
    },
    "ERROR": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "ПОМИЛКА"
          }
        }
      }
    },
    "ETA": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "ЧАС"
          }
        }
      }
    },
    "Enter the battery IP address": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Введіть IP-адресу батареї"
          }
        }
      }
    },
    "FULL": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "ЗАРЯДЖЕНО"
          }
        }
      }
    },
    "FULL IN": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "ДО ЗАРЯДУ"
          }
        }
      }
    },
    "IDLE": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "ПАУЗА"
          }
        }
      }
    },
    "IF OUTAGE": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "БЕЗ СВІТЛА"
          }
        }
      }
    },
    "If it fails": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Якщо не працює"
          }
        }
      }
    },
    "Join the battery's Wi‑Fi, and turn on Open API for the battery in the Marstek app.": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Підключіться до Wi‑Fi батареї й увімкніть Open API для батареї в застосунку Marstek."
          }
        }
      }
    },
    "NO LINK": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "НЕМАЄ ЗВʼЯЗКУ"
          }
        }
      }
    },
    "Now": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Зараз"
          }
        }
      }
    },
    "Open the app": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Відкрийте застосунок"
          }
        }
      }
    },
    "Port": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Порт"
          }
        }
      }
    },
    "Port must be 1 to 65535": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Порт має бути від 1 до 65535"
          }
        }
      }
    },
    "Reserve ": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Резерв "
          }
        }
      }
    },
    "Reserve must be 0 to 50 %": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Резерв має бути від 0 до 50 %"
          }
        }
      }
    },
    "SET IP": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "ВКАЖІТЬ IP"
          }
        }
      }
    },
    "Save and check": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Зберегти й перевірити"
          }
        }
      }
    },
    "Settings › Privacy & Security › Local Network › turn on Battery ETA.": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Параметри › Приватність і безпека › Локальна мережа › увімкніть Battery ETA."
          }
        }
      }
    },
    "The reserve is the charge the battery keeps back. EMPTY IN counts down to it.": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Резерв — заряд, який батарея не віддає. ДО РОЗРЯДУ рахує час до нього."
          }
        }
      }
    },
    "Updated %@": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Оновлено о %@"
          }
        }
      }
    },
    "h": {
      "comment": "Hours unit, as in 6h20 and 21h",
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "год"
          }
        }
      }
    },
    "m": {
      "comment": "Minutes unit, as in 25m",
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "хв"
          }
        }
      }
    },
    "−%lld W": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "−%lld Вт"
          }
        }
      }
    }
  },
  "version": "1.0"
}
```

`ios/App/InfoPlist.xcstrings`:

```json
{
  "sourceLanguage": "en",
  "version": "1.0",
  "strings": {
    "NSLocalNetworkUsageDescription": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Battery ETA зчитує вашу батарею Marstek через домашню мережу Wi‑Fi."
          }
        }
      }
    }
  }
}
```

In `ios/project.yml`, add at the top level `options: { developmentLanguage: en }`, and under the `info.properties` of both `BatteryETA` and `BatteryWidget` add `CFBundleLocalizations: [en, uk]`.

- [x] **6.4 Route the strings through the catalog.** SwiftUI already looks up a `Text("literal")`, `.configurationDisplayName("…")` and `.description("…")`. A `String` built in code needs `String(localized:)`. Make exactly these edits:

| File | Now | Change to |
|---|---|---|
| `Shared/Format.swift` | `"…)h"`, `"…)h" + String(format:…)`, `"…)m"` (4 returns) | Add `let h = String(localized: "h", comment: "Hours unit, as in 6h20 and 21h")` and `let m = String(localized: "m", comment: "Minutes unit, as in 25m")` at the top of `formatDuration`, and write `\(h)` and `\(m)` in place of the literal `h` and `m`. |
| `Shared/Store.swift` | `problem` returns 3 literals; `FetchError.text` returns `"SET IP"`, `"ALLOW LAN"`, `"NO LINK"`, `"ERROR"` | Wrap each in `String(localized: …)`. |
| `Shared/Face.swift` | `"BATTERY"`, `"FULL IN"`, `"FULL"`, `"EMPTY IN"`, `"IDLE"`, `"ETA"`, `"IF OUTAGE"`, `"+\(watts) W"`, `"−\(watts) W"` | Wrap each in `String(localized: …)`. Leave `Face.sample` in English. |
| `Shared/Faces.swift` | `Text(face.updated == nil ? "Battery" : "Battery \(face.percent)")` | `Text(face.updated == nil ? String(localized: "Battery") : String(localized: "Battery \(face.percent)"))`. Do the same for `"Open the app"` inside the ternary next to it. |
| `App/BatteryApp.swift` | `hint(_ code: String, _ text: String)` | `hint(_ code: LocalizedStringKey, _ text: LocalizedStringKey)`. |

- [x] **6.5 Run `make test`.** Expected: all pass, including the English assertions of Tasks 2–5.

- [x] **6.6 Check in Ukrainian.** Run `xcrun simctl spawn booted defaults write .GlobalPreferences AppleLanguages -array uk`, then `xcrun simctl shutdown booted && xcrun simctl boot "iPhone 18 Pro"`. Launch the app and add all three widgets. Pass: every label is Ukrainian, `ДО РОЗРЯДУ 6год20` fits the medium widget without clipping, and the Local Network prompt is Ukrainian. Reset with the same command and `-array en`.

- [x] **6.7 Commit.** `git add ios && git commit -m "feat: add ukrainian to the ios app and widgets"`

---

## Task 7: Icon, docs and TestFlight

**Files**
- Create: `ios/App/icon.svg`, `ios/App/Assets.xcassets/Contents.json`, `ios/App/Assets.xcassets/AppIcon.appiconset/Contents.json`, `ios/ExportOptions.plist`
- Modify: `ios/project.yml`, `ios/Makefile`, `README.md`, `CLAUDE.md`

- [x] **7.1 Icon.** `ios/App/icon.svg` (the charge ring at 75 % with clock hands, option C on the canvas):

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 144 144">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1B1B21"/><stop offset="1" stop-color="#0B0B0E"/></linearGradient></defs>
<rect width="144" height="144" fill="url(#bg)"/>
<circle cx="72" cy="74" r="50" fill="none" stroke="#24242A" stroke-width="11" stroke-linecap="round" stroke-dasharray="235.62 999" transform="rotate(135 72 74)"/>
<circle cx="72" cy="74" r="50" fill="none" stroke="#3DDC97" stroke-width="11" stroke-linecap="round" stroke-dasharray="176.7 999" transform="rotate(135 72 74)"/>
<line x1="72" y1="74" x2="72" y2="46" stroke="#FFFFFF" stroke-width="8" stroke-linecap="round"/>
<line x1="72" y1="74" x2="93" y2="65" stroke="#3DDC97" stroke-width="8" stroke-linecap="round"/>
<circle cx="72" cy="74" r="7" fill="#FFFFFF"/>
</svg>
```

`ios/App/Assets.xcassets/Contents.json`:

```json
{ "info": { "author": "xcode", "version": 1 } }
```

`ios/App/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images": [{ "filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }],
  "info": { "author": "xcode", "version": 1 }
}
```

In `ios/project.yml`, under `BatteryETA.settings.base`, add `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. Change the `BatteryETA` sources to `sources: [{ path: App, excludes: [icon.svg] }, Shared]` so the SVG stays out of the app bundle.

- [x] **7.2 Make targets.** Replace `ios/Makefile`:

```make
SIM ?= iPhone 18 Pro
BUILD ?= 1
ARCHIVE := build/BatteryETA.xcarchive

.PHONY: project test icon archive upload

project:
	xcodegen generate

test: project
	xcodebuild test -project BatteryETA.xcodeproj -scheme BatteryETA -destination 'platform=iOS Simulator,name=$(SIM)' -quiet

icon:
	rsvg-convert -w 1024 -h 1024 App/icon.svg | magick - -alpha off App/Assets.xcassets/AppIcon.appiconset/icon-1024.png

archive: project
	xcodebuild archive -project BatteryETA.xcodeproj -scheme BatteryETA -configuration Release -destination 'generic/platform=iOS' -archivePath $(ARCHIVE) -allowProvisioningUpdates CURRENT_PROJECT_VERSION=$(BUILD)

upload: archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

`ios/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>WSCTL2V8W5</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>testFlightInternalTestingOnly</key>
	<true/>
</dict>
</plist>
```

Run `make icon && make test`. Expected: `icon-1024.png` is 1024×1024 with no alpha (`magick identify -format '%w %h %[channels]' App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` prints `1024 1024 srgb  3.0`; ImageMagick's own SVG renderer drops the ring, so the icon goes through `rsvg-convert`), and the tests pass.

- [x] **7.3 Docs.** Add to `README.md`, after "Check the connection":

````markdown
## iPhone widgets

`ios/` holds Battery ETA, an iPhone app with three widgets: a charge ring, charge with ETA, and a Lock Screen gauge. The phone reads the battery directly, so the widgets update only on the battery's Wi‑Fi; elsewhere they show the last reading and `NO LINK`. iOS refreshes widgets about every 15–30 minutes, and the widget ETA is energy left ÷ current power.

```bash
cd ios
make test
make upload BUILD=2
```

Requires Xcode, `brew install xcodegen librsvg imagemagick`, and team `WSCTL2V8W5`. Raise `BUILD` for every upload.
````

In `CLAUDE.md`, change the first paragraph to name `ios/` too and add the commands line:

```markdown
Tools for a Marstek Venus E 3.0 home battery. `streamdeck/` is a Stream Deck plugin
(SDK 3, Node 24, TypeScript) that polls the battery's Open API over UDP on the LAN.
`ios/` is an iPhone app with widgets (SwiftUI, WidgetKit, xcodegen) that reads the same API.

## Commands (run from `streamdeck/`)

`npm run build` · `npm run watch` · `npm run typecheck` · `npm test` ·
`MARSTEK_HOST=192.168.68.50 npm run probe`

From `ios/`: `make test` · `make icon` · `make upload BUILD=<n>`
```

- [x] **7.4 Commit.** `git add ios README.md CLAUDE.md && git commit -m "feat: add ios icon and testflight upload"`

- [ ] **7.5 Owner: App Store Connect (about 15 minutes, plus 15–30 minutes of processing).**
  1. Xcode → Settings → Accounts: signed in with the Apple ID of team `WSCTL2V8W5`.
  2. appstoreconnect.apple.com → Apps → **+** → New App: iOS, name `Battery ETA` (if taken, any unique name; the Home Screen keeps `Battery ETA`), bundle ID `com.mlapin.marstek.battery`, SKU `battery-eta`.
  3. From `ios/`: `make upload BUILD=1`.
  4. Users and Access → **+**: invite the friend's Apple ID with the Marketing role and access to Battery ETA only. Internal testers need one of Account Holder, Admin, App Manager, Developer or Marketing. Marketing gives the least access.
  5. After the friend accepts: TestFlight → Internal Testing → **+** group `Friends`, add the friend, add build 1.
  6. The friend installs TestFlight, then Battery ETA. Their battery needs Open API turned on in the Marstek app and a fixed IP. On first launch they tap **Save and check** on their home Wi‑Fi and allow Local Network.
