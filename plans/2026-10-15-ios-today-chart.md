# Today chart in the iOS app

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the settings screen shows today's charge and power, and today's charged kWh, used kWh and time on battery.

**Design:** artboard "Today chart" (`project/Chart.dc.html`) on the Battery ETA canvas, https://claude.ai/artifact/1ZfUnFUKedswkhYC5dc9wL. A TODAY card below NOW holds a CHARGE line (low/high in the header, a dotted segment over missing readings, a dot and a dashed rule at now) and a POWER row of hourly bars (green up for charge, amber down for discharge, axis `00 06 12 18 now`). A TODAY IN NUMBERS row below it shows Charged, Used and On battery.

**Architecture:**
- Every successful fetch in `Refresher.refresh` adds the reading to a `History` stored under its own App Group key `history`. The app and the widgets both go through `Refresher`, so both add samples. A reused snapshot (widget `maxAge`) and a failed fetch add nothing. No new battery requests.
- `History.add` keeps one sample per 5 minutes and drops samples older than 48 h or newer than the new reading (the clock moved back). That caps it at 577 samples, about 20 KB of JSON.
- `Snapshot` does not change, so snapshots stored before this change decode as before. A missing or unreadable `history` key reads as an empty `History`.
- `History.day(now:latest:)` builds a `DaySummary` from local midnight to now. It adds the current snapshot's reading as the live last point, so the chart is never 5 minutes behind while the app is open.
  - Line: readings more than 1 h apart get a dotted connector.
  - Bars: the mean power of the readings inside each hour; an hour with no reading has no bar.
  - Charged, Used and On battery integrate the stored power readings: each reading's power holds until the next reading, only when the two are at most 1 h apart. Charged sums charging power × time, Used sums discharging power × time, On battery sums the time while discharging over 30 W (`QuickEstimate.idleW`).
- A new IP clears the history together with the snapshot.
- App and widget processes both read-modify-write `history`. A rare collision loses one sample; nothing breaks.

**Tech stack:** Swift 5 mode, Swift Testing, Swift Charts (iOS 17), xcodegen.

## Gentle on the battery

Each rule has a test that fails if it is broken.

1. **History comes only from readings a refresh already fetched.** Opening or scrolling the chart sends no request, and nothing backfills a missing history. Tests: `aFailedFetchAddsNothing`, `aReusedSnapshotAddsNothing`, `anEmptyHistoryDoesNotTriggerAFetch` (Task 1), `historyAndTheChartSendNoExtraRequests` (Task 2).
2. **No new polling, no faster poll, never `Bat.GetStatus`.** The 30 s app poll, the 15 min widget refresh and `MarstekClient` do not change. Energy totals integrate the stored power readings. Tests: the existing `ClientTests.aReadingAsksOnlyForEsStatus`, `energyIntegratesTheStoredPower` (Task 2).
3. **Writing history does not change when `Refresher` fetches.** The reuse check reads only `store.snapshot` and its age, as today. Tests: the existing `aFreshSnapshotIsReused` and `anOldSnapshotIsFetchedAgain`, plus `theReuseCheckIgnoresHistory` (Task 1).
4. **Adding history and building the chart send zero extra requests.** Test: `historyAndTheChartSendNoExtraRequests` (Task 2) counts fetches with a `ReadingCounter` actor in the `FetchCounter` pattern from `ios/Tests/StoreTests.swift`.

## Deviations from the design for the owner to decide

1. **Charged, Used and On battery undercount when only widgets read.** Widgets read once per 15–30 min, and a gap over 1 h is not integrated, so energy in long gaps is missing. Power swings between two readings (a kettle) are missed too. With the app open (one sample per 5 min) the numbers are close. Drop the numbers row if widget-only days read too low.
2. **The numbers are AC-side** (power at the battery's plug), so they match a plug meter, not the change in charge %.
3. **The x-axis runs from midnight to now**, as in the design, but at least 3 h wide, so just after midnight the first readings are not stretched across the whole card. The hour labels before now are `00 06 12 18`; a label closer than 2 h to now is dropped so it does not collide with `now`.
4. **The line starts at the first reading after midnight**, not at the left edge.
5. **Empty state:** with fewer than 2 readings today, the card shows "No readings yet today." and the numbers row is hidden. The design has no empty state.

## Global constraints

- The iOS app sends only `ES.GetStatus`. This plan adds no request and does not change the 30 s app poll or the widget refresh.
- Keep edits to shared files small: `Store.swift` (one property, three lines in `refresh`), `BatteryApp.swift` (one state, two sections, two lines), `Faces.swift` (two colours), `Localizable.xcstrings` (new keys only). New code goes in new files. `project.yml` does not change: xcodegen picks up new files and `import Charts` links itself.
- Branch `claude/ios-today-chart-13d596`. Conventional Commits, one subject line, no co-author trailer, no push.
- Gate: from `ios/`, `make test`.

## Review focus

1. A snapshot JSON written before this change still decodes, and the history reads as empty. (Task 1 test.)
2. A widget refresh that reuses a fresh snapshot adds no sample, so history never claims a reading that did not happen. (Task 1 test.)
3. 49 h of 30 s polling leaves at most 577 samples, none older than 48 h, under 32 KB encoded. (Task 1 test.)
4. A reading from before local midnight never shows on today's chart or in today's numbers. (Task 2 test.)
5. Each rule in "Gentle on the battery" has its test, and none of `Refresher`'s reuse logic changed.

## Batches

- A: Tasks 1 and 2 (one `implementer`)
- B: Task 3 (one `implementer`)
- Then one fresh `reviewer` on the diff of all three tasks.

Time: about 30 minutes for Task 1, 30 for Task 2, 45 for Task 3.

---

## Task 1: Reading history in the App Group store

**Files**
- Create: `ios/Shared/History.swift`, `ios/Tests/HistoryTests.swift`
- Modify: `ios/Shared/Store.swift`

**Interfaces**
- Produces: `Sample(time:socPct:acW:)`, `Sample(_ reading:)`, `History` with `samples` and `add(_:)`, `History.gap`, `Store.history`.

- [x] **1.1 Tests first.** Create `ios/Tests/HistoryTests.swift`:

```swift
import Foundation
import Testing
@testable import BatteryETA

struct HistoryTests {
    // Midnight UTC, 9 Oct 2025.
    private let start = Date(timeIntervalSince1970: 1_759_968_000)

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

    @Test func anEmptyHistoryDoesNotTriggerAFetch() async {
        let store = store()
        store.snapshot = Snapshot(reading: at(0), error: nil, checkedAt: start)
        var fetched = false
        _ = await Refresher.refresh(store, now: start.addingTimeInterval(60), maxAge: 10 * 60) { _ in
            fetched = true
            return at(1)
        }
        #expect(!fetched)
        #expect(store.history.samples.isEmpty)
    }

    @Test func theReuseCheckIgnoresHistory() async {
        let store = store()
        store.snapshot = Snapshot(reading: at(0), error: nil, checkedAt: start)
        store.history.add(at(14))
        var fetched = false
        _ = await Refresher.refresh(store, now: start.addingTimeInterval(15 * 60), maxAge: 10 * 60) { _ in
            fetched = true
            return at(15)
        }
        #expect(fetched)
    }

    @Test func anOldSnapshotStillDecodes() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let old = #"{"reading":{"time":782000000,"socPct":80,"acW":400,"offgridW":0,"capacityWh":4121,"ratedWh":5120},"checkedAt":782000000}"#
        defaults.set(Data(old.utf8), forKey: "snapshot")
        let store = Store(defaults: defaults)
        #expect(store.snapshot?.reading?.socPct == 80)
        #expect(store.history.samples.isEmpty)
    }
}
```

Run `make test`. Expected: the build fails because `History` does not exist.

- [x] **1.2 History.** Create `ios/Shared/History.swift`:

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

struct History: Codable, Equatable {
    static let keep: TimeInterval = 48 * 3600
    static let spacing: TimeInterval = 5 * 60
    static let gap: TimeInterval = 3600

    var samples: [Sample] = []

    mutating func add(_ r: Reading) {
        samples.removeAll { $0.time > r.time || r.time.timeIntervalSince($0.time) > History.keep }
        if let last = samples.last, r.time.timeIntervalSince(last.time) < History.spacing { return }
        samples.append(Sample(r))
    }
}
```

- [x] **1.3 Store and refresh.** In `ios/Shared/Store.swift`, add to `Store` below `snapshot`:

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

- [x] **1.4 Commit.** `git add ios && git commit -m "feat: keep 48 h of battery readings on ios"`

---

## Task 2: Today's summary

**Files**
- Create: `ios/Shared/DaySummary.swift`
- Test: `ios/Tests/HistoryTests.swift`

**Interfaces**
- Consumes: `History`, `Sample`, `History.gap`, `QuickEstimate.idleW`.
- Produces: `DaySummary` (`start`, `now`, `segments`, `hours`, `low`, `high`, `chargedWh`, `usedWh`, `onBattery`, `isEmpty`), `DaySummary.Segment(samples:dotted:)`, `DaySummary.HourBar(hour:watts:)`, `History.day(now:latest:calendar:)`.

- [x] **2.1 Tests first.** Append to `HistoryTests` (inside the struct):

```swift
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func history(_ readings: Reading...) -> History {
        var history = History()
        readings.forEach { history.add($0) }
        return history
    }

    @Test func theDayStartsAtMidnight() {
        let day = history(at(-30, soc: 50), at(10, soc: 70), at(20, soc: 90))
            .day(now: start.addingTimeInterval(30 * 60), latest: nil, calendar: utc)
        #expect(day.segments.flatMap(\.samples).map(\.socPct) == [70, 90])
        #expect(day.low == 70)
        #expect(day.high == 90)
        #expect(abs(day.usedWh - 400.0 / 6) < 0.01)
    }

    @Test func aGapOverAnHourIsDottedAndTheLiveReadingIsLast() {
        let day = history(at(0), at(10), at(90))
            .day(now: start.addingTimeInterval(92 * 60), latest: at(92, soc: 81), calendar: utc)
        #expect(day.segments.map(\.dotted) == [false, true, false])
        #expect(day.segments.map(\.samples.count) == [2, 2, 2])
        #expect(day.segments.last?.samples.last?.socPct == 81)
    }

    @Test func energyIntegratesTheStoredPower() {
        let day = history(at(0, acW: -1200), at(30, acW: 600), at(60, acW: 600), at(200, acW: 600))
            .day(now: start.addingTimeInterval(200 * 60), latest: nil, calendar: utc)
        #expect(abs(day.chargedWh - 600) < 0.01)
        #expect(abs(day.usedWh - 300) < 0.01)
    }

    @Test func historyAndTheChartSendNoExtraRequests() async {
        let store = store()
        let counter = ReadingCounter()
        _ = await Refresher.refresh(store, now: start) { _ in await counter.fetch(at(0)) }
        _ = await Refresher.refresh(store, now: start.addingTimeInterval(10 * 60)) { _ in await counter.fetch(at(10)) }
        for _ in 0..<3 {
            _ = store.history.day(now: start.addingTimeInterval(11 * 60), latest: store.snapshot?.reading, calendar: utc)
        }
        #expect(store.history.samples.count == 2)
        #expect(await counter.count == 2)
    }

    @Test func onBatteryCountsDischargeBetweenCloseReadings() {
        let day = history(at(0, acW: 400), at(10, acW: -800), at(20, acW: 400), at(100, acW: 400))
            .day(now: start.addingTimeInterval(100 * 60), latest: nil, calendar: utc)
        #expect(day.onBattery == 10 * 60)
    }

    @Test func eachHourBarIsTheMeanPowerWithChargingUp() {
        let day = history(at(0, acW: 400), at(30, acW: 200), at(60, acW: -800))
            .day(now: start.addingTimeInterval(70 * 60), latest: nil, calendar: utc)
        #expect(day.hours == [
            DaySummary.HourBar(hour: start, watts: -300),
            DaySummary.HourBar(hour: start.addingTimeInterval(3600), watts: 800),
        ])
    }

    @Test func oneReadingIsEmpty() {
        #expect(history(at(0)).day(now: start.addingTimeInterval(60), latest: nil, calendar: utc).isEmpty)
    }
```

Below the struct:

```swift
actor ReadingCounter {
    var count = 0

    func fetch(_ reading: Reading) -> Reading {
        count += 1
        return reading
    }
}
```

Run `make test`. Expected: the build fails because `History` has no `day`.

- [x] **2.2 Summary.** Create `ios/Shared/DaySummary.swift`:

```swift
import Foundation

struct DaySummary: Equatable {
    struct Segment: Equatable {
        var samples: [Sample]
        var dotted: Bool
    }

    // Charging is positive, as on the face.
    struct HourBar: Equatable {
        var hour: Date
        var watts: Int
    }

    var start: Date
    var now: Date
    var segments: [Segment] = []
    var hours: [HourBar] = []
    var low: Int?
    var high: Int?
    var chargedWh = 0.0
    var usedWh = 0.0
    var onBattery: TimeInterval = 0

    var isEmpty: Bool { segments.flatMap(\.samples).count < 2 }
}

extension History {
    func day(now: Date, latest: Reading?, calendar: Calendar = .current) -> DaySummary {
        let start = calendar.startOfDay(for: now)
        var all = samples
        if let latest, latest.time > all.last?.time ?? .distantPast { all.append(Sample(latest)) }
        let today = all.filter { $0.time >= start && $0.time <= now }

        var day = DaySummary(start: start, now: now)
        day.low = today.map(\.socPct).min()
        day.high = today.map(\.socPct).max()
        for (a, b) in zip(today, today.dropFirst()) {
            let gap = b.time.timeIntervalSince(a.time)
            guard gap <= History.gap else { continue }
            let wh = Double(a.acW) * gap / 3600
            if wh < 0 { day.chargedWh -= wh } else { day.usedWh += wh }
            if Double(a.acW) > QuickEstimate.idleW { day.onBattery += gap }
        }
        for s in today {
            if let prev = day.segments.last?.samples.last, s.time.timeIntervalSince(prev.time) > History.gap {
                day.segments.append(.init(samples: [prev, s], dotted: true))
                day.segments.append(.init(samples: [s], dotted: false))
            } else if day.segments.isEmpty {
                day.segments.append(.init(samples: [s], dotted: false))
            } else {
                day.segments[day.segments.count - 1].samples.append(s)
            }
        }
        day.hours = Dictionary(grouping: today) { calendar.dateInterval(of: .hour, for: $0.time)?.start ?? $0.time }
            .map { hour, group in DaySummary.HourBar(hour: hour, watts: -group.map(\.acW).reduce(0, +) / group.count) }
            .sorted { $0.hour < $1.hour }
        return day
    }
}
```

Run `make test`. Expected: all tests pass.

- [x] **2.3 Commit.** `git add ios && git commit -m "feat: summarise today's battery readings on ios"`

---

## Task 3: TODAY card and numbers on the settings screen

**Files**
- Create: `ios/App/TodayCard.swift`
- Modify: `ios/App/BatteryApp.swift`, `ios/Shared/Faces.swift`, `ios/Shared/Localizable.xcstrings`, `ios/Tests/LocalizationTests.swift`

**Interfaces**
- Consumes: `History.day(now:latest:calendar:)`, `DaySummary`, `formatDuration`, `Store.history`.
- Produces: `TodayCard(day:)`, `TodayNumbers(day:)`, `Palette.warn`, `Palette.cardEdge`.

- [ ] **3.1 Palette.** In `ios/Shared/Faces.swift`, add below `good`: `static let warn = Color(hex: 0xFFB547)` and `static let cardEdge = Color(hex: 0x2A2A30)`. Make `accent` return `warn` for `.warn`.

- [ ] **3.2 Card and numbers.** Create `ios/App/TodayCard.swift`:

```swift
import Charts
import SwiftUI

struct TodayCard: View {
    let day: DaySummary

    private var domain: ClosedRange<Date> { day.start...max(day.now, day.start.addingTimeInterval(3 * 3600)) }

    private var ticks: [Date] {
        let hours = stride(from: 0.0, through: 18, by: 6)
            .map { day.start.addingTimeInterval($0 * 3600) }
            .filter { day.now.timeIntervalSince($0) >= 2 * 3600 }
        return hours + [day.now]
    }

    private var peak: Int { max(1, day.hours.map { abs($0.watts) }.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if day.isEmpty {
                Text("No readings yet today.").font(.subheadline).foregroundStyle(Palette.label)
            } else {
                header("CHARGE") {
                    if let low = day.low, let high = day.high {
                        Text("low \("\(low) %") · high \("\(high) %")")
                    }
                }
                charge
                header("POWER") {
                    Text("charge").foregroundStyle(Palette.good) + Text(verbatim: " · ") + Text("discharge").foregroundStyle(Palette.warn)
                }
                .padding(.top, 6)
                power
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.cardEdge, lineWidth: 0.5))
    }

    private var charge: some View {
        Chart {
            ForEach(Array(day.segments.enumerated()), id: \.offset) { i, segment in
                ForEach(segment.samples, id: \.time) { s in
                    LineMark(x: .value("Time", s.time), y: .value("Charge", s.socPct), series: .value("Segment", i))
                        .foregroundStyle(Palette.good)
                        .lineStyle(segment.dotted
                            ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5])
                            : StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            RuleMark(x: .value("Time", day.now))
                .foregroundStyle(Color(hex: 0x48484A))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let last = day.segments.last?.samples.last {
                PointMark(x: .value("Time", last.time), y: .value("Charge", last.socPct))
                    .foregroundStyle(Palette.good)
                    .symbolSize(100)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.track) }
        }
        .frame(height: 140)
    }

    private var power: some View {
        Chart {
            ForEach(day.hours, id: \.hour) { bar in
                BarMark(x: .value("Hour", bar.hour, unit: .hour), y: .value("Power", bar.watts))
                    .foregroundStyle(bar.watts > 0 ? Palette.good : Palette.warn)
                    .cornerRadius(3)
            }
            RuleMark(y: .value("Power", 0)).foregroundStyle(Color(hex: 0x38383A))
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: -peak...peak)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { v in
                AxisValueLabel {
                    if v.as(Date.self) == day.now {
                        Text("now")
                    } else if let date = v.as(Date.self) {
                        Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                    }
                }
            }
        }
        .frame(height: 84)
    }

    private func header<Trailing: View>(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.6).foregroundStyle(Palette.label)
            Spacer()
            trailing().font(.system(size: 13, design: .rounded)).foregroundStyle(Palette.label)
        }
    }
}

struct TodayNumbers: View {
    let day: DaySummary

    var body: some View {
        HStack(spacing: 0) {
            cell("Charged", kWh(day.chargedWh))
            Divider()
            cell("Used", kWh(day.usedWh))
            Divider()
            cell("On battery", formatDuration(day.onBattery / 3600))
        }
        .listRowInsets(EdgeInsets())
    }

    private func kWh(_ wh: Double) -> String {
        String(localized: "\((wh / 1000).formatted(.number.precision(.fractionLength(1)))) kWh")
    }

    private func cell(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(Palette.label)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
```

If an API above does not exist in the iOS 17 SDK (`BarMark.cornerRadius`, `AxisGridLine(stroke:)`), drop that modifier; keep the layout.

- [ ] **3.3 Settings screen.** In `ios/App/BatteryApp.swift` `SettingsScreen`:
  - Add `@State private var history = Store().history` below `snapshot`.
  - Below the `Section("Now")`, add:

```swift
                Section {
                    TodayCard(day: day)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Today")
                } footer: {
                    Text("Built from readings the app and widgets already take. Dotted: no reading, the line joins the gap.")
                }

                if !day.isEmpty {
                    Section("Today in numbers") { TodayNumbers(day: day) }
                }
```

  - Add below `saveDisabled`:

```swift
    private var day: DaySummary {
        history.day(now: .now, latest: snapshot?.reading)
    }
```

  - In `save()`, change the first line to `if settings.host != store.settings.host { store.snapshot = nil; store.history = History() }`.
  - In `refresh()`, add `history = store.history` after `snapshot = await Refresher.refresh(store)`.

- [ ] **3.4 Ukrainian.** Add to `ios/Shared/Localizable.xcstrings` (same shape as existing entries, `state: translated`), keeping keys sorted. Skip a key that already exists. Run the `ukrainian-translation-review` skill on the new values before committing.

| Key | uk |
|---|---|
| `Today` | `Сьогодні` |
| `CHARGE` | `ЗАРЯД` |
| `POWER` | `ПОТУЖНІСТЬ` |
| `low %@ · high %@` | `мін. %1$@ · макс. %2$@` |
| `charge` | `заряд` |
| `discharge` | `розряд` |
| `now` | `зараз` |
| `No readings yet today.` | `Сьогодні ще немає даних.` |
| `Built from readings the app and widgets already take. Dotted: no reading, the line joins the gap.` | `Графік будується з даних, які застосунок і віджети вже отримують. Пунктир: даних немає, лінія зʼєднує проміжок.` |
| `Today in numbers` | `Сьогодні в цифрах` |
| `Charged` | `Заряджено` |
| `Used` | `Витрачено` |
| `On battery` | `Від батареї` |
| `%@ kWh` | `%@ кВт·год` |
| `Time` | `Час` |
| `Charge` | `Заряд` |
| `Power` | `Потужність` |
| `Hour` | `Година` |
| `Segment` | `Відрізок` |

In `LocalizationTests.theAppShipsUkrainian`, add `#expect(uk.localizedString(forKey: "%@ kWh", value: nil, table: nil) == "%@ кВт·год")`.

- [ ] **3.5 Check.** Run `make test`. Expected: all tests pass. Then run the app in the iPhone simulator against the battery and compare the screen with the "Today chart" artboard: card edge and radius, header labels, dotted gap, now dot and rule, bar colours, axis `00 06 12 18 now`, numbers row. Switch the simulator to Ukrainian and check that no label is cut off.

- [ ] **3.6 Commit.** `git add ios && git commit -m "feat: show today's charge and power in the ios app"`
