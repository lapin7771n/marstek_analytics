# Low-battery alert on iOS

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battery ETA sends a local notification once when the battery is discharging with under 30 minutes left, and once when the charge reaches the reserve.

**Design:** artboard "Low-battery alert" (`project/Alert.dc.html`) on the Battery ETA canvas, https://claude.ai/artifact/1ZfUnFUKedswkhYC5dc9wL. The canvas is read-only for this work.

**Architecture:**
- A pure function `LowBatteryAlert.check(_:floorPct:state:now:)` decides from a `Snapshot` whether to notify, and updates a stored `AlertState` (`on`, `soonAlerted`, `reserveAlerted`).
- **Under 30 min:** the battery is discharging and `QuickEstimate` gives under 0.5 h. It usually fires first.
- **At reserve:** the battery is not charging and `socPct <= floorPct`. It also marks the 30-minute alert as sent, so one check never sends both.
- Both re-arm when the battery charges, or when the charge is over `floorPct + 5` with at least 1 h left. The 5 % and 1 h band stops a second notification when the load or the charge wobbles around the line.
- A snapshot with an error, or a reading older than `Face.staleAfter` (30 min), sends nothing and leaves the state alone. Away from home the app never warns from an old reading.
- `AlertTask` runs from Background App Refresh through SwiftUI's `.backgroundTask(.appRefresh(_:))`. It asks iOS for the next run no earlier than 15 min later, then reads through `SharedRefresh.shared.run { Refresher.refresh(store, maxAge: Refresher.widgetMaxAge, fetch: AlertTask.fetchOnce) }`.
- `AlertTask.fetchOnce` is `MarstekClient` with `retry: false`. A run sends at most one `ES.GetStatus` and never retries; a failed fetch waits for the next run.
- The widgets run in their own process, so they hold a different `SharedRefresh.shared`. Across the two processes the stored snapshot does the sharing: whichever reads first stores it, and the other reuses it for 10 min. If a widget and the alert both find an old snapshot in the same second, each sends one request. Closing that gap needs a lock across processes, which this plan leaves out.
- The toggle sits in a new **Alerts** section. Turning it on asks for notification permission; a refusal turns it back off and the footer says where to allow notifications.
- `AlertState` is stored under its own key. Adding a field to `BatterySettings` would make the stored settings fail to decode and wipe the user's IP.

**Tech stack:** Swift 5 mode, SwiftUI, BackgroundTasks, UserNotifications, Swift Testing, xcodegen.

## Owner decisions: where the plan differs from the canvas

1. **Power reads `−1850 W`, the canvas shows `−1 850 W`.** The alert formats the widgets' `−%lld W` string with `String(format:)`, which never groups digits, so the text does not depend on the phone's region. An `Int` interpolated into `String(localized:)` takes the region's grouping (`−1 850 W` or `−1,850 W`), which is what the widgets show today.
2. **At the reserve with no load, the power is left out:** `12 % left. The battery stops at the reserve.` The battery usually stops discharging at the reserve, so `−0 W` would be the common case.
3. **The footer says "iOS checks about every 15–30 min".** Background App Refresh promises no interval; a rarely opened app or Low Power Mode can wait hours. The plan uses the canvas text. Proposed instead: "iOS picks when to check, so an alert can come late."
4. **Added: a footer for refused permission,** "Notifications are off. Turn them on for Battery ETA in Settings." The canvas has no such state.

## Global constraints

Battery API rules, so the battery never resets or cuts power. Each has a test in Task 2.
1. A background run sends at most one `ES.GetStatus`, and none when the stored snapshot is under 10 min old. (`anAlertRunAndAWidgetRefreshShareOneRequest`, `anAlertRunReusesAFreshSnapshot`, `anAlertRunFetchesAnOldSnapshotOnce`.)
2. No retries inside a background run. (`aBackgroundFetchDoesNotRetry`.)
3. Only `ES.GetStatus`, never `Bat.GetStatus` or any other method. One UDP request in flight. (`aBackgroundFetchAsksOnlyForEsStatus`.)

Other constraints:
- Shared files get small edits: `Store.swift` (one type, one property), `MarstekClient.swift` (one flag), `BatteryApp.swift` (one section, two scene modifiers), `project.yml` (two Info.plist keys), `Localizable.xcstrings` (nine strings). New code goes in new files.
- Gate: `make test` from `ios/`, exit 0.
- Branch `claude/ios-low-battery-alert-949c72`. Conventional Commits, one subject line, no co-author trailer, no push.

## Review focus

1. The phone is away from home: the snapshot is `NO LINK` with the last reading at 10 %. No notification. (Task 1 test.)
2. The charge sits at the reserve for hours: one notification, not one per run. (Task 1 test.)
3. The load wobbles so the time left goes 25 min → 40 min → 25 min: one notification. (Task 1 test.)
4. The battery charges and later drains to the reserve again: a second notification. (Task 1 test.)
5. A widget refreshed 5 min before the alert run: the run sends no request. A silent battery: the run sends one request, not two. (Task 2 tests.)
6. A background run wakes the app: the foreground 30 s poll stays asleep, so only the alert's one request goes out. (Owner device check, Task 2.)
7. Notification permission refused, or turned off later in iOS Settings: the toggle ends up off or the run returns before any request. (Owner device check, Task 2.)

## Batches

- A: Tasks 1 and 2 (one `implementer`), then the owner's device check.

Time: about 1½ hours of work, plus 15 minutes on the device.

---

## Task 1: Alert decision and its tests

**Files**
- Create: `ios/App/LowBatteryAlert.swift`, `ios/Tests/LowBatteryAlertTests.swift`
- Modify: `ios/Shared/Store.swift`, `ios/Shared/Localizable.xcstrings`

**Interfaces**
- Produces: `AlertState`, `Store.alert`, `LowBattery.soon(minutes:watts:)`, `LowBattery.reserve(socPct:watts:)`, `LowBattery.title`, `LowBattery.body`, `LowBatteryAlert.check(_:floorPct:state:now:)`.

- [x] **1.1 Tests first.** `ios/Tests/LowBatteryAlertTests.swift`:

```swift
import Foundation
import Testing
@testable import BatteryETA

struct LowBatteryAlertTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func snapshot(soc: Int, acW: Double, error: FetchError? = nil, age: TimeInterval = 0) -> Snapshot {
        let r = Reading(
            time: now.addingTimeInterval(-age), socPct: soc, acW: acW, offgridW: 0,
            capacityWh: Double(soc) / 100 * 5120, ratedWh: 5120
        )
        return Snapshot(reading: r, error: error, checkedAt: now)
    }

    private func check(_ s: Snapshot, _ state: inout AlertState) -> LowBattery? {
        LowBatteryAlert.check(s, floorPct: 12, state: &state, now: now)
    }

    @Test func underHalfAnHourWhileDischargingNotifies() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 2000), &state) == .soon(minutes: 11, watts: 2000))
        #expect(state.soonAlerted)
    }

    @Test func halfAnHourOrMoreIsQuiet() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 400), &state) == nil)
        #expect(state == AlertState(on: true))
    }

    @Test func reachingTheReserveNotifiesOnce() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 12, acW: 100), &state) == .reserve(socPct: 12, watts: 100))
        #expect(check(snapshot(soc: 11, acW: 100), &state) == nil)
    }

    @Test func theReserveWithNoLoadLeavesOutThePower() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 12, acW: 0), &state) == .reserve(socPct: 12, watts: nil))
    }

    @Test func underHalfAnHourThenTheReserveNotifiesTwice() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 2000), &state) == .soon(minutes: 11, watts: 2000))
        #expect(check(snapshot(soc: 12, acW: 2000), &state) == .reserve(socPct: 12, watts: 2000))
        #expect(check(snapshot(soc: 12, acW: 2000), &state) == nil)
    }

    @Test func chargingAtTheReserveIsQuiet() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 10, acW: -500), &state) == nil)
    }

    @Test func justUnderHalfAnHourReadsUnder30Minutes() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 760), &state) == .soon(minutes: 29, watts: 760))
    }

    @Test func aWobblingLoadNotifiesOnce() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 20, acW: 2000), &state) != nil)
        #expect(check(snapshot(soc: 20, acW: 400), &state) == nil)
        #expect(state.soonAlerted)
        #expect(check(snapshot(soc: 19, acW: 2000), &state) == nil)
    }

    @Test func chargingArmsTheNextAlerts() {
        var state = AlertState(on: true, soonAlerted: true, reserveAlerted: true)
        #expect(check(snapshot(soc: 13, acW: -500), &state) == nil)
        #expect(state == AlertState(on: true))
        #expect(check(snapshot(soc: 12, acW: 100), &state) == .reserve(socPct: 12, watts: 100))
    }

    @Test func aChargeWellAboveTheReserveArmsTheNextAlerts() {
        var state = AlertState(on: true, soonAlerted: true, reserveAlerted: true)
        _ = check(snapshot(soc: 18, acW: 100), &state)
        #expect(state == AlertState(on: true))
    }

    @Test func aFailedFetchSendsNothing() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 10, acW: 100, error: .noLink), &state) == nil)
        #expect(state == AlertState(on: true))
    }

    @Test func anOldReadingSendsNothing() {
        var state = AlertState(on: true)
        #expect(check(snapshot(soc: 10, acW: 100, age: 31 * 60), &state) == nil)
        #expect(state == AlertState(on: true))
    }

    @Test func anAlertTurnedOffSendsNothing() {
        var state = AlertState()
        #expect(check(snapshot(soc: 10, acW: 100), &state) == nil)
    }

    @Test func theTextFollowsTheDesign() {
        #expect(LowBattery.soon(minutes: 25, watts: 1850).title == "Under 30 min left")
        #expect(LowBattery.soon(minutes: 25, watts: 1850).body == "Empty in 25 min at −1850 W. Turn off heavy loads.")
        #expect(LowBattery.reserve(socPct: 12, watts: 1850).title == "Battery at reserve")
        #expect(LowBattery.reserve(socPct: 12, watts: 1850).body == "12 % left, −1850 W. The battery stops at the reserve.")
        #expect(LowBattery.reserve(socPct: 12, watts: nil).body == "12 % left. The battery stops at the reserve.")
    }
}
```

`soc: 20, acW: 2000` gives (1024 − 614.4) Wh ÷ 1.09 ÷ 2000 W = 0.188 h, which rounds to 11 min.

Run `make test`. Expected: the build fails because `AlertState` does not exist.

- [x] **1.2 Stored state.** In `ios/Shared/Store.swift`, add above `final class Store`:

```swift
struct AlertState: Codable, Equatable {
    var on = false
    var soonAlerted = false
    var reserveAlerted = false
}
```

And below `snapshot` in `Store`:

```swift
    var alert: AlertState {
        get { load("alert") ?? AlertState() }
        set { save(newValue, "alert") }
    }
```

`AlertState` sits in `Shared/` because `Store` is built into the widget too.

- [x] **1.3 Decision.** `ios/App/LowBatteryAlert.swift`:

```swift
import Foundation

enum LowBattery: Equatable {
    case soon(minutes: Int, watts: Int)
    case reserve(socPct: Int, watts: Int?)

    var title: String {
        switch self {
        case .soon: String(localized: "Under 30 min left")
        case .reserve: String(localized: "Battery at reserve")
        }
    }

    var body: String {
        switch self {
        case let .soon(minutes, watts):
            String(localized: "Empty in \(minutes) min at \(Self.power(watts)). Turn off heavy loads.")
        case let .reserve(socPct, watts?):
            String(localized: "\(Self.percent(socPct)) left, \(Self.power(watts)). The battery stops at the reserve.")
        case let .reserve(socPct, nil):
            String(localized: "\(Self.percent(socPct)) left. The battery stops at the reserve.")
        }
    }

    // The percent goes in as text: a bare % in a localized format key reads as a format specifier.
    static func percent(_ pct: Int) -> String { "\(pct) %" }

    // An Int interpolated into String(localized:) gets locale grouping ("−1 850 W"); %lld through String(format:) does not.
    private static func power(_ watts: Int) -> String { String(format: String(localized: "−%lld W"), watts) }
}

enum LowBatteryAlert {
    static let soonHours = 0.5
    static let rearmPct = 5
    static let rearmHours = 1.0

    static func check(_ snapshot: Snapshot, floorPct: Int, state: inout AlertState, now: Date = .now) -> LowBattery? {
        guard state.on, snapshot.error == nil, let r = snapshot.reading,
              now.timeIntervalSince(r.time) < Face.staleAfter else { return nil }
        let est = QuickEstimate.estimate(r, floorPct: Double(floorPct))
        if est.mode == .charging || (r.socPct > floorPct + rearmPct && (est.hours ?? .infinity) >= rearmHours) {
            state.soonAlerted = false
            state.reserveAlerted = false
            return nil
        }
        let watts = Int(abs(r.acW).rounded())
        if r.socPct <= floorPct {
            let first = !state.reserveAlerted
            state.soonAlerted = true
            state.reserveAlerted = true
            return first ? .reserve(socPct: r.socPct, watts: est.mode == .discharging ? watts : nil) : nil
        }
        if est.mode == .discharging, let hours = est.hours, hours < soonHours, !state.soonAlerted {
            state.soonAlerted = true
            return .soon(minutes: min(29, max(1, Int((hours * 60).rounded()))), watts: watts)
        }
        return nil
    }
}
```

- [x] **1.4 Strings.** Add to `ios/Shared/Localizable.xcstrings`, in the same shape as the existing entries (`"state": "translated"`):

| Key | Ukrainian |
|---|---|
| `Under 30 min left` | `Лишилося менше 30 хв` |
| `Empty in %lld min at %@. Turn off heavy loads.` | `Розрядиться через %1$lld хв (%2$@). Вимкніть потужні прилади.` |
| `Battery at reserve` | `Батарея на резерві` |
| `%@ left, %@. The battery stops at the reserve.` | `Лишилося %1$@, %2$@. Батарея зупиняється на резерві.` |
| `%@ left. The battery stops at the reserve.` | `Лишилося %@. Батарея зупиняється на резерві.` |
| `Alerts` | `Сповіщення` |
| `Low-battery alert` | `Сповіщення про низький заряд` |
| `Alerts once when the charge reaches the %@ reserve, and once when less than 30 min is left. iOS checks about every 15–30 min, so an alert can come late.` | `Сповіщає один раз, коли заряд дійде до резерву %@, і ще раз, коли лишиться менше 30 хв. iOS перевіряє приблизно кожні 15–30 хв, тож сповіщення може запізнитися.` |
| `Notifications are off. Turn them on for Battery ETA in Settings.` | `Сповіщення вимкнено. Увімкніть їх для Battery ETA у Параметрах.` |

Run `make test`. Expected: exit 0.

---

## Task 2: Background run, toggle and Info.plist

**Files**
- Create: `ios/App/AlertTask.swift`
- Modify: `ios/Shared/MarstekClient.swift`, `ios/App/BatteryApp.swift`, `ios/project.yml`, `ios/App/Info.plist` (regenerated by xcodegen)
- Test: `ios/Tests/StoreTests.swift`, `ios/Tests/ClientTests.swift`

**Interfaces**
- Consumes: `LowBatteryAlert.check`, `LowBattery.percent`, `Store.alert`, `Refresher.refresh(_:now:maxAge:fetch:)`, `SharedRefresh`.
- Produces: `MarstekClient.retry`, `AlertTask.id`, `AlertTask.schedule()`, `AlertTask.cancel()`, `AlertTask.turnOn() async -> Bool`, `AlertTask.fetchOnce(_:)`, `AlertTask.evaluate(_:gate:now:fetch:) async -> LowBattery?`, `AlertTask.run()`.

- [x] **2.1 Tests first.** In `ios/Tests/StoreTests.swift`, append inside `StoreTests`:

```swift
    @Test func anAlertRunAndAWidgetRefreshShareOneRequest() async {
        let store = store()
        let counter = FetchCounter()
        let now = reading(acW: 400).time
        _ = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now) { _ in await counter.fetchReading() }
        _ = await Refresher.refresh(store, now: now.addingTimeInterval(5 * 60), maxAge: Refresher.widgetMaxAge) { _ in
            await counter.fetchReading()
        }
        #expect(await counter.count == 1)
    }

    @Test func anAlertRunReusesAFreshSnapshot() async {
        let store = store()
        let counter = FetchCounter()
        let now = reading(acW: 400).time
        store.snapshot = Snapshot(reading: reading(acW: 400), error: nil, checkedAt: now)
        _ = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now.addingTimeInterval(9 * 60)) { _ in
            await counter.fetchReading()
        }
        #expect(await counter.count == 0)
    }

    @Test func anAlertRunFetchesAnOldSnapshotOnce() async {
        let store = store()
        let counter = FetchCounter()
        let now = reading(acW: 400).time
        store.snapshot = Snapshot(reading: reading(acW: 400), error: nil, checkedAt: now)
        _ = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now.addingTimeInterval(11 * 60)) { _ in
            await counter.fetchReading()
        }
        #expect(await counter.count == 1)
    }

    @Test func anAlertRunRemembersItNotified() async {
        let store = store()
        store.alert = AlertState(on: true)
        let now = reading(acW: 400).time
        store.snapshot = Snapshot(reading: reading(soc: 12, acW: 100, capacityWh: 614.4), error: nil, checkedAt: now)
        let first = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now) { _ in reading(acW: 400) }
        let second = await AlertTask.evaluate(store, gate: SharedRefresh(), now: now) { _ in reading(acW: 400) }
        #expect(first == .reserve(socPct: 12, watts: 100))
        #expect(second == nil)
    }
```

And add to `FetchCounter`:

```swift
    func fetchReading() -> Reading {
        count += 1
        return reading(acW: 400)
    }
```

In `ios/Tests/ClientTests.swift`, append inside `ClientTests`:

```swift
    @Test func aBackgroundFetchAsksOnlyForEsStatus() async throws {
        var methods: [String] = []
        let fake = try await FakeBattery.start { request, _ in
            methods.append(request.method)
            return [#"{"id":\#(request.id),"result":{"bat_soc":80,"bat_cap":5120,"ongrid_power":-797,"offgrid_power":0}}"#]
        }
        defer { fake.stop() }
        _ = try await AlertTask.fetchOnce(BatterySettings(host: "127.0.0.1", port: Int(fake.port)))
        #expect(methods == ["ES.GetStatus"])
    }

    @Test func aBackgroundFetchDoesNotRetry() async throws {
        var requests = 0
        let fake = try await FakeBattery.start { _, _ in
            requests += 1
            return []
        }
        defer { fake.stop() }
        await #expect(throws: DeviceError.timeout) {
            try await AlertTask.fetchOnce(BatterySettings(host: "127.0.0.1", port: Int(fake.port)))
        }
        #expect(requests == 1)
    }
```

`aBackgroundFetchDoesNotRetry` waits out the 2 s default timeout, so it runs the same client the background run uses.

Run `make test`. Expected: the build fails because `AlertTask` does not exist.

- [x] **2.2 Client flag.** In `ios/Shared/MarstekClient.swift`, add `var retry = true` below `gap`, and change the catch in `call(_:)` to:

```swift
        } catch DeviceError.timeout where retry {
```

The app and the widgets keep their one retry.

- [x] **2.3 Task.** `ios/App/AlertTask.swift`:

```swift
import BackgroundTasks
import UserNotifications

enum AlertTask {
    static let id = "com.mlapin.marstek.battery.alert"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
    }

    static func turnOn() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        Store().alert = AlertState(on: granted)
        if granted { schedule() }
        return granted
    }

    // One ES.GetStatus at most, no retry: a failed read waits for the next run.
    @Sendable static func fetchOnce(_ settings: BatterySettings) async throws -> Reading {
        try await MarstekClient(host: settings.host, port: UInt16(settings.port), retry: false).reading()
    }

    static func evaluate(
        _ store: Store = Store(),
        gate: SharedRefresh = .shared,
        now: Date = .now,
        fetch: @escaping @Sendable (BatterySettings) async throws -> Reading = AlertTask.fetchOnce
    ) async -> LowBattery? {
        let snapshot = await gate.run { await Refresher.refresh(store, now: now, maxAge: Refresher.widgetMaxAge, fetch: fetch) }
        var state = store.alert
        let low = LowBatteryAlert.check(snapshot, floorPct: store.settings.floorPct, state: &state, now: now)
        store.alert = state
        return low
    }

    static func run() async {
        guard Store().alert.on,
              await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized else { return }
        schedule()
        guard let low = await evaluate() else { return }
        let content = UNMutableNotificationContent()
        content.title = low.title
        content.body = low.body
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
    }
}
```

`submit` throws on the simulator; `try?` keeps the tests quiet. The tests call `evaluate` with a test `Store` and their own `SharedRefresh`, so they never touch the App Group or the network.

Run `make test`. Expected: exit 0.

- [x] **2.4 App.** In `ios/App/BatteryApp.swift`:
  - In `BatteryApp`, add `@Environment(\.scenePhase) private var phase`, and after `WindowGroup { … }`:

```swift
        .onChange(of: phase) { _, phase in
            if phase == .background, Store().alert.on { AlertTask.schedule() }
        }
        .backgroundTask(.appRefresh(AlertTask.id)) { await AlertTask.run() }
```

  - In `SettingsScreen`, add `@State private var alertOn = Store().alert.on`, `@State private var alertDenied = false` and `@Environment(\.scenePhase) private var phase`.
  - Replace `.task { await poll() }` with the line below. A background run wakes the suspended app, and the 30 s poll would wake with it and send its own request next to the alert's.

```swift
        .task(id: phase) { if phase == .active { await poll() } }
```
  - Add this section between `Section("Now")` and `Section("If it fails")`:

```swift
                Section {
                    Toggle("Low-battery alert", isOn: Binding(get: { alertOn }, set: { on in Task { await setAlert(on) } }))
                } header: {
                    Text("Alerts")
                } footer: {
                    Text(alertFooter)
                }
```

  - Add:

```swift
    private var alertFooter: String {
        alertDenied
            ? String(localized: "Notifications are off. Turn them on for Battery ETA in Settings.")
            : String(localized: "Alerts once when the charge reaches the \(LowBattery.percent(settings.floorPct)) reserve, and once when less than 30 min is left. iOS checks about every 15–30 min, so an alert can come late.")
    }

    private func setAlert(_ on: Bool) async {
        alertOn = on
        if on {
            alertOn = await AlertTask.turnOn()
            alertDenied = !alertOn
        } else {
            store.alert = AlertState()
            AlertTask.cancel()
            alertDenied = false
        }
    }
```

- [x] **2.5 Info.plist.** In `ios/project.yml`, under `BatteryETA.info.properties`, add:

```yaml
        UIBackgroundModes: [fetch]
        BGTaskSchedulerPermittedIdentifiers: [com.mlapin.marstek.battery.alert]
```

Run `make test`. Expected: exit 0, and `grep -c 'BGTaskSchedulerPermittedIdentifiers\|UIBackgroundModes' App/Info.plist` prints `2`.

- [x] **2.6 Commit.** `git add plans/2026-10-15-ios-low-battery-alert.md ios && git commit -m "feat: add low battery alert on ios"`

- [ ] **2.7 Owner: device check (15 minutes).**
  1. Install on the iPhone, open the app, turn on **Low-battery alert**, allow notifications.
  2. Set the reserve a few percent under the current charge, press **Save and check**, then send the app to the background.
  3. In Xcode, pause the app, run `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.mlapin.marstek.battery.alert"]` in the debugger, then continue. Expected: no notification.
  4. Set the reserve to the current charge, then repeat steps 2–3. Expected: one "Battery at reserve" notification. Repeat step 3 once more: none.
  5. Delete the app, reinstall it, turn on the toggle and tap **Don't Allow**. Expected: the toggle goes back off and the footer says where to allow notifications.
  6. Note whether a real background run reaches the battery over the LAN. This plan has not checked it on a device.
