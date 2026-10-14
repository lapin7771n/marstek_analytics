# Today chart in the iOS app

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the settings screen shows charge % and power over the last 24 hours.

**Architecture:**
- Every successful fetch in `Refresher.refresh` adds the reading to a `History` stored under its own App Group key `history`. The app and the widgets both go through `Refresher`, so both add samples. A reused snapshot (widget `maxAge`) and a failed fetch add nothing. No new battery requests.
- `History.add` keeps one sample per 5 minutes and drops samples older than 48 h or newer than the new reading (the clock moved back). That caps it at 577 samples, about 20 KB of JSON.
- `Snapshot` does not change, so snapshots stored before this change decode as before. A missing or unreadable `history` key reads as an empty `History`.
- The chart adds the current snapshot's reading as a live last point, so it is never 5 minutes behind while the app is open. Readings more than 1 h apart start a new line run, so the chart does not draw a straight line across hours with no data.
- Two stacked Swift Charts share one 24 h x-axis: charge 0–100 % (green line and area), and power as areas from zero (green above zero while charging, amber below while discharging), the same sign as the `+412 W` / `−412 W` on the face.
- A new IP clears the history together with the snapshot.
- App and widget processes both read-modify-write `history`. A rare collision loses one sample; nothing breaks.

**Tech stack:** Swift 5 mode, Swift Testing, Swift Charts (iOS 17), xcodegen.

## Global constraints

- The iOS app sends only `ES.GetStatus`. This plan adds no request and does not change the 30 s app poll or the widget refresh.
- Keep edits to shared files small: `Store.swift` (one property, three lines in `refresh`), `BatteryApp.swift` (one state, one section, two lines), `Faces.swift` (one colour), `Localizable.xcstrings` (new keys only). New code goes in new files. `project.yml` does not change: xcodegen picks up new files and `import Charts` links itself.
- Branch `claude/ios-today-chart-13d596`. Conventional Commits, one subject line, no co-author trailer, no push.
- Gate: from `ios/`, `make test`.

## Review focus

1. A snapshot JSON written before this change still decodes, and the history reads as empty. (Task 1 test.)
2. A widget refresh that reuses a fresh snapshot adds no sample, so history never claims a reading that did not happen. (Task 1 test.)
3. 49 h of 30 s polling leaves at most 577 samples, none older than 48 h, under 32 KB encoded. (Task 1 test.)

## Open question

The section header says **Last 24 hours** and the x-axis is a rolling 24 h ending now, so overnight discharge stays visible after midnight. If you want "Today" from local midnight instead, say so: it changes the x domain and one string.

## Batches

- A: Task 1 (one `implementer`)
- B: Task 2 (one `implementer`)
- Then one fresh `reviewer` on the diff of both tasks.

Time: about 30 minutes per task.

---

## Task 1: Reading history in the App Group store

**Files**
- Create: `ios/Shared/History.swift`, `ios/Tests/HistoryTests.swift`
- Modify: `ios/Shared/Store.swift`

**Interfaces**
- Produces: `Sample(time:socPct:acW:)`, `History` with `samples`, `add(_:)`, `points(now:latest:)`; `ChartPoint(time:socPct:watts:run:)`; `Store.history`.

- [ ] **1.1 Tests first.** Create `ios/Tests/HistoryTests.swift`:

```swift
import Foundation
import Testing
@testable import BatteryETA

struct HistoryTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double, soc: Int = 80, acW: Double = 400) -> Reading {
        var r = reading(soc: soc, acW: acW)
        r.time = start.addingTimeInterval(minutes * 60)
        return r
    }

    private func store() -> Store {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        store.settings = BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 12)
        return store
    }

    @Test func aGoodFetchAddsASample() async {
        let store = store()
        _ = await Refresher.refresh(store, now: start) { _ in at(0) }
        #expect(store.history.samples == [Sample(time: start, socPct: 80, acW: 400)])
    }

    @Test func aFailedFetchAddsNothing() async {
        let store = store()
        _ = await Refresher.refresh(store, now: start) { _ in throw DeviceError.timeout }
        #expect(store.history.samples.isEmpty)
    }

    @Test func aReusedSnapshotAddsNothing() async {
        let store = store()
        _ = await Refresher.refresh(store, now: start) { _ in at(0) }
        _ = await Refresher.refresh(store, now: start.addingTimeInterval(5 * 60), maxAge: 10 * 60) { _ in at(5) }
        #expect(store.history.samples.count == 1)
    }

    @Test func readingsUnderFiveMinutesApartAreThinned() {
        var history = History()
        for minute in stride(from: 0.0, through: 10, by: 0.5) { history.add(at(minute)) }
        #expect(history.samples.map(\.time) == [0.0, 5, 10].map { start.addingTimeInterval($0 * 60) })
    }

    @Test func fortyNineHoursOfPollingKeepFortyEight() throws {
        var history = History()
        for minute in stride(from: 0.0, through: 49 * 60, by: 0.5) { history.add(at(minute)) }
        let last = try #require(history.samples.last).time
        #expect(history.samples.count <= 577)
        #expect(history.samples.allSatisfy { last.timeIntervalSince($0.time) <= 48 * 3600 })
        #expect(try JSONEncoder().encode(history).count < 32_000)
    }

    @Test func aClockMovedBackDropsTheFutureSamples() {
        var history = History()
        history.add(at(60))
        history.add(at(0))
        #expect(history.samples.map(\.time) == [start])
    }

    @Test func anOldSnapshotStillDecodes() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let old = #"{"reading":{"time":782000000,"socPct":80,"acW":400,"offgridW":0,"capacityWh":4121,"ratedWh":5120},"checkedAt":782000000}"#
        defaults.set(Data(old.utf8), forKey: "snapshot")
        let store = Store(defaults: defaults)
        #expect(store.snapshot?.reading?.socPct == 80)
        #expect(store.history.samples.isEmpty)
    }

    @Test func theChartAddsTheLiveReadingAndSplitsAtGaps() {
        var history = History()
        history.add(at(0, acW: 400))
        history.add(at(10, acW: -800))
        history.add(at(90))
        let points = history.points(now: start.addingTimeInterval(92 * 60), latest: at(92, soc: 81))
        #expect(points.map(\.run) == [0, 0, 1, 1])
        #expect(points.map(\.watts) == [-400, 800, -400, -400])
        #expect(points.last?.socPct == 81)
    }

    @Test func theChartShowsOnlyTheLastDay() {
        var history = History()
        history.add(at(0))
        history.add(at(25 * 60))
        let points = history.points(now: start.addingTimeInterval(25 * 3600), latest: nil)
        #expect(points.count == 1)
    }
}
```

Run `make test`. Expected: the build fails because `History` does not exist.

- [ ] **1.2 History.** Create `ios/Shared/History.swift`:

```swift
import Foundation

struct Sample: Codable, Equatable {
    var time: Date
    var socPct: Int
    var acW: Int

    enum CodingKeys: String, CodingKey { case time = "t", socPct = "s", acW = "w" }
}

extension Sample {
    init(_ r: Reading) {
        self.init(time: r.time, socPct: r.socPct, acW: Int(r.acW.rounded()))
    }
}

struct ChartPoint: Equatable, Identifiable {
    var id: Date { time }
    var time: Date
    var socPct: Int
    var watts: Int
    var run: Int
}

struct History: Codable, Equatable {
    static let keep: TimeInterval = 48 * 3600
    static let spacing: TimeInterval = 5 * 60
    static let window: TimeInterval = 24 * 3600
    static let gap: TimeInterval = 3600

    var samples: [Sample] = []

    mutating func add(_ r: Reading) {
        samples.removeAll { $0.time > r.time || r.time.timeIntervalSince($0.time) > History.keep }
        if let last = samples.last, r.time.timeIntervalSince(last.time) < History.spacing { return }
        samples.append(Sample(r))
    }

    // Charging is positive, as on the face.
    func points(now: Date, latest: Reading?) -> [ChartPoint] {
        var all = samples
        if let latest, latest.time > all.last?.time ?? .distantPast { all.append(Sample(latest)) }
        var points: [ChartPoint] = []
        var run = 0
        for s in all where now.timeIntervalSince(s.time) <= History.window {
            if let prev = points.last, s.time.timeIntervalSince(prev.time) > History.gap { run += 1 }
            points.append(ChartPoint(time: s.time, socPct: s.socPct, watts: -s.acW, run: run))
        }
        return points
    }
}
```

- [ ] **1.3 Store and refresh.** In `ios/Shared/Store.swift`, add to `Store` below `snapshot`:

```swift
    var history: History {
        get { load("history") ?? History() }
        set { save(newValue, "history") }
    }
```

In `Refresher.refresh`, replace the `do` line:

```swift
            do {
                let reading = try await fetch(settings)
                next.reading = reading
                store.history.add(reading)
            } catch {
                next.error = FetchError(error)
            }
```

Run `make test`. Expected: all tests pass.

- [ ] **1.4 Commit.** `git add ios && git commit -m "feat: keep 48 h of battery readings on ios"`

---

## Task 2: Chart on the settings screen

**Files**
- Create: `ios/App/TodayChart.swift`
- Modify: `ios/App/BatteryApp.swift`, `ios/Shared/Faces.swift`, `ios/Shared/Localizable.xcstrings`

**Interfaces**
- Consumes: `History.points(now:latest:)`, `ChartPoint`, `Store.history`.
- Produces: `TodayChart(points:now:)`, `Palette.warn`.

- [ ] **2.1 Amber in the palette.** In `ios/Shared/Faces.swift`, add `static let warn = Color(hex: 0xFFB547)` below `good`, and make `accent` return `warn` for `.warn`.

- [ ] **2.2 Chart view.** Create `ios/App/TodayChart.swift`:

```swift
import Charts
import SwiftUI

struct TodayChart: View {
    let points: [ChartPoint]
    let now: Date

    private var charging: String { String(localized: "Charging") }
    private var discharging: String { String(localized: "Discharging") }

    var body: some View {
        if points.count < 2 {
            Text("No readings yet. The chart fills in while the app is open or a widget is on the Home Screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 16) {
                Chart(points) { p in
                    AreaMark(x: .value("Time", p.time), y: .value("Charge", p.socPct), series: .value("Run", p.run))
                        .foregroundStyle(Palette.good.opacity(0.2))
                    LineMark(x: .value("Time", p.time), y: .value("Charge", p.socPct), series: .value("Run", p.run))
                        .foregroundStyle(Palette.good)
                }
                .chartXScale(domain: now.addingTimeInterval(-History.window)...now)
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { v in
                        AxisGridLine()
                        AxisValueLabel { Text(verbatim: "\(v.as(Int.self) ?? 0)%") }
                    }
                }
                .frame(height: 110)

                Chart {
                    RuleMark(y: .value("Power", 0)).foregroundStyle(Palette.track)
                    ForEach(points) { p in
                        AreaMark(x: .value("Time", p.time), yStart: .value("Power", 0), yEnd: .value("Power", max(0, p.watts)), series: .value("Run", "c\(p.run)"))
                            .foregroundStyle(by: .value("Mode", charging))
                        AreaMark(x: .value("Time", p.time), yStart: .value("Power", 0), yEnd: .value("Power", min(0, p.watts)), series: .value("Run", "d\(p.run)"))
                            .foregroundStyle(by: .value("Mode", discharging))
                    }
                }
                .chartForegroundStyleScale([charging: Palette.good, discharging: Palette.warn])
                .chartXScale(domain: now.addingTimeInterval(-History.window)...now)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine()
                        AxisValueLabel { Text("\(abs(v.as(Int.self) ?? 0)) W") }
                    }
                }
                .frame(height: 130)
            }
            .padding(.vertical, 8)
        }
    }
}
```

If `AreaMark(x:y:series:)` or `AreaMark(x:yStart:yEnd:series:)` do not exist in the iOS 17 SDK, drop the area under the charge line and draw power as `LineMark(..., series:)` with `.foregroundStyle(by:)`; keep the run split.

- [ ] **2.3 Settings screen.** In `ios/App/BatteryApp.swift` `SettingsScreen`:
  - Add `@State private var history = Store().history` below `snapshot`.
  - Below the `Section("Now")`, add:

```swift
                Section("Last 24 hours") {
                    let now = Date.now
                    TodayChart(points: history.points(now: now, latest: snapshot?.reading), now: now)
                }
```

  - In `save()`, change the first line to `if settings.host != store.settings.host { store.snapshot = nil; store.history = History() }`.
  - In `refresh()`, add `history = store.history` after `snapshot = await Refresher.refresh(store)`.

- [ ] **2.4 Ukrainian.** Add to `ios/Shared/Localizable.xcstrings` (same shape as existing entries, `state: translated`), keeping keys sorted:

| Key | uk |
|---|---|
| `Last 24 hours` | `Останні 24 години` |
| `Time` | `Час` |
| `Charge` | `Заряд` |
| `Power` | `Потужність` |
| `Run` | `Відрізок` |
| `Mode` | `Режим` |
| `Charging` | `Заряджається` |
| `Discharging` | `Розряджається` |
| `%lld W` | `%lld Вт` |
| `No readings yet. The chart fills in while the app is open or a widget is on the Home Screen.` | `Даних ще немає. Графік заповнюється, коли застосунок відкритий або віджет є на головному екрані.` |

Skip a key that already exists. In `LocalizationTests.theAppShipsUkrainian`, add `#expect(uk.localizedString(forKey: "%lld W", value: nil, table: nil) == "%lld Вт")`.

- [ ] **2.5 Check.** Run `make test`. Expected: all tests pass. Then run the app in the iPhone simulator with a reachable battery (or seed `history` in a debug session): the section shows both charts, the hour labels read in Ukrainian with the simulator in Ukrainian, and the empty state shows on a fresh install.

- [ ] **2.6 Commit.** `git add ios && git commit -m "feat: show the last 24 hours chart in the ios app"`
